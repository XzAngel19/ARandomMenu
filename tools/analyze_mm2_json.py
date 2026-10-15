#!/usr/bin/env python3
"""Offline, read-only MM2 evidence analysis. Standard library only.

python tools/analyze_mm2_json.py --data /path/to/TestingStuff --output /path/report.json
Deduplicate by bytes; never convert unknown/death-association into a hit.
Forecast errors are client-position proxies, NOT a replay of server collisions.
"""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import statistics

MODELS = ("linear", "acceleration", "intent25", "intent50", "intent100", "classic-proxy", "v17-proxy")
HORIZONS = (.15, .20, 7 / 30, .30)

def add(a, b): return [x + y for x, y in zip(a, b)]
def sub(a, b): return [x - y for x, y in zip(a, b)]
def mul(a, s): return [x * s for x in a]
def norm(a): return math.sqrt(sum(x * x for x in a))
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def clamp(a, low, high): return max(low, min(high, a))
def percentile(values, p): return sorted(values)[round((len(values) - 1) * p)] if values else None

def stats(values):
    if not values: return {"count": 0}
    return {"count": len(values), "mean": statistics.mean(values), "median": statistics.median(values),
            "p90": percentile(values, .9), "min": min(values), "max": max(values)}

def vector_valid(v):
    return isinstance(v, list) and len(v) == 3 and all(isinstance(x, (int, float)) and math.isfinite(x) for x in v)

def clean_track(points):
    # Preserve temporal order. Malformed/non-monotone tracks are not repaired
    # using future knowledge. These logs do not include authoritative server poses.
    for i, point in enumerate(points):
        if not all(vector_valid(point.get(k)) for k in ("position", "velocity", "moveDirection")): return []
        if not isinstance(point.get("dt"), (int, float)) or not math.isfinite(point["dt"]): return []
        if i and point["dt"] <= points[i - 1]["dt"]: return []
    return points

def forecasts(a, previous, horizon):
    velocity = a["velocity"]
    dt = a["dt"] - previous["dt"]
    acceleration = mul(sub(velocity, previous["velocity"]), 1 / dt)
    if norm(acceleration) > 250: acceleration = mul(acceleration, 250 / norm(acceleration))
    flat = [velocity[0], 0, velocity[2]]
    old_flat = [previous["velocity"][0], 0, previous["velocity"][2]]
    similarity = (clamp(dot(flat, old_flat) / (norm(flat) * norm(old_flat)), -1, 1)
                  if min(norm(flat), norm(old_flat)) > 1 else 1)
    rates = {"classic-proxy": clamp((1 - clamp(similarity, 0, 1)) * 6, 0, math.pi * 1.5),
             "v17-proxy": clamp(math.acos(similarity) / max(dt, 1 / 120), 0, math.pi * 1.5)}
    grounded = a["grounded"] and abs(velocity[1]) <= 6 and a["humanoidState"] != "Jumping"
    result = {}
    for model in MODELS:
        used = velocity[:]
        lead = horizon
        acceleration_offset = [0, 0, 0]
        if model in rates:
            lead = horizon * max(.25, math.cos(horizon * rates[model] / 2))
            acceleration_offset = mul(acceleration, .25 * lead * lead)
        if model == "acceleration": acceleration_offset = mul(acceleration, .25 * lead * lead)
        if model.startswith("intent") and norm(a["moveDirection"]) > .05 and norm(flat) >= 1.5:
            alpha = int(model[6:]) / 100
            desired = mul(a["moveDirection"], norm(flat) / norm(a["moveDirection"]))
            used = add(mul(used, 1 - alpha), mul(desired, alpha))
            used[1] = velocity[1]
        dy = clamp(used[1], -2.5, 2.5) * lead if grounded else used[1] * lead - .5 * 196.2 * lead * lead
        result[model] = add(a["position"], [used[0] * lead + acceleration_offset[0], dy,
                                          used[2] * lead + acceleration_offset[2]])
    return result

def replay(events):
    rows = []
    for horizon in HORIZONS:
        grouped = collections.defaultdict(list)
        axis_grouped = collections.defaultdict(list)
        window_counts = collections.Counter()
        for event in events:
            if event.get("kind") not in ("gun", "knife"): continue
            track = clean_track(event.get("targetTrajectory", []))
            errors = collections.defaultdict(list)
            axis_errors = collections.defaultdict(list)
            for i, a in enumerate(track):
                if i == 0: continue
                previous = track[i - 1]
                dt = a["dt"] - previous["dt"]
                if dt > .25 or norm(a["velocity"]) > 110 or norm(sub(a["position"], previous["position"])) > 32: continue
                truth = None
                for b, c in zip(track[i:], track[i + 1:]):
                    if b["dt"] <= a["dt"] + horizon <= c["dt"] and c["dt"] - b["dt"] <= .15:
                        fraction = (a["dt"] + horizon - b["dt"]) / (c["dt"] - b["dt"])
                        truth = add(b["position"], mul(sub(c["position"], b["position"]), fraction))
                        break
                if truth is None: continue
                for model, predicted in forecasts(a, previous, horizon).items():
                    delta = sub(predicted, truth)
                    errors[model].append(norm(delta))
                    axis_errors[(model, "horizontal")].append(math.hypot(delta[0], delta[2]))
                    axis_errors[(model, "vertical")].append(abs(delta[1]))
            for model, values in errors.items():
                # Each event/trajectory has equal weight, not each overlapping window.
                grouped[model].append(statistics.mean(values))
                window_counts[model] += len(values)
            for key, values in axis_errors.items(): axis_grouped[key].append(statistics.mean(values))
        for model, values in grouped.items():
            rows.append({"horizon": horizon, "model": model, "windows": window_counts[model],
                         "per_trajectory_mean_error_studs": stats(values),
                         "horizontal_error_studs": stats(axis_grouped[(model, "horizontal")]),
                         "vertical_error_studs": stats(axis_grouped[(model, "vertical")])})
    return rows

def inspect_trajectory(data):
    events = data["session"]["events"]
    result = {"session": {k: v for k, v in data["session"].items() if k != "events"},
              "settings": data.get("settings"), "events": len(events),
              "points": sum(len(e.get("targetTrajectory", [])) for e in events),
              "phases": dict(collections.Counter(e["kind"] + "/" + e.get("phase", "legacy") for e in events)),
              "replay": replay(events), "timing": {}}
    for kind in ("gun", "knife"):
        points = [clean_track(e.get("targetTrajectory", [])) for e in events if e["kind"] == kind]
        pairs = [(a, b) for track in points for a, b in zip(track, track[1:])]
        result["timing"][kind] = {"sample_intervals_seconds": stats([b["dt"] - a["dt"] for a, b in pairs]),
                                   "unchanged_position_pairs": sum(norm(sub(b["position"], a["position"])) < .001 for a, b in pairs),
                                   "pairs": len(pairs)}
    authored = {e["shotId"]: e for e in events if e.get("phase") == "authored"}
    result["gun_signals"] = []
    for e in events:
        if e["kind"] != "gun" or e.get("phase") != "confirmation": continue
        original = authored.get(e["shotId"])
        result["gun_signals"].append({"shot": e["shotId"].rsplit(":", 1)[-1],
                                      "authored": original is not None, "latencyMs": e["latencyMs"],
                                      "hitTarget": e["hitTarget"], "settings": e.get("settings"),
                                      "trajectoryPoints": len(e.get("targetTrajectory", []))})
    result["gun_authored_modes"] = dict(collections.Counter(e.get("settings", {}).get("mode", "unknown")
                                      for e in authored.values() if e["kind"] == "gun"))
    result["knife_authored_models"] = dict(collections.Counter(e.get("settings", {}).get("latencyModel", "unknown")
                                         for e in authored.values() if e["kind"] == "knife"))
    terminal = {e["shotId"]: e for e in events if e.get("shotId") and e.get("phase") in ("confirmation", "unconfirmed")}
    result["prediction_profiles"] = {}
    result["burst_groups"] = {}
    for shot in authored.values():
        if shot["kind"] != "gun": continue
        settings = shot.get("settings", {})
        profile = settings.get("prediction", {}).get("profile", "unrecorded")
        bucket = result["prediction_profiles"].setdefault(profile, {"authored": 0, "signals": 0, "target_hit_parts": 0, "unconfirmed": 0})
        outcome = terminal.get(shot["shotId"], {})
        bucket["authored"] += 1
        bucket["signals"] += outcome.get("phase") == "confirmation"
        bucket["target_hit_parts"] += outcome.get("phase") == "confirmation" and outcome.get("hitTarget") is True
        bucket["unconfirmed"] += outcome.get("phase") == "unconfirmed"
        burst = settings.get("burst")
        if not isinstance(burst, dict) or not burst.get("groupId"): continue
        group = result["burst_groups"].setdefault(burst["groupId"], {"planned": burst.get("count"), "authored": 0, "candidate_indices": [], "signals": 0, "target_hit_parts": 0})
        group["authored"] += 1
        group["candidate_indices"].append(burst.get("index"))
        group["signals"] += outcome.get("phase") == "confirmation"
        group["target_hit_parts"] += outcome.get("phase") == "confirmation" and outcome.get("hitTarget") is True
    for event in events:
        if event.get("kind") != "gun" or event.get("phase") != "burst-signal" or not event.get("groupId"): continue
        group = result["burst_groups"].setdefault(event["groupId"], {"planned": None, "authored": 0, "candidate_indices": [], "signals": 0, "target_hit_parts": 0})
        group["group_level_callbacks_not_unique_shots"] = group.get("group_level_callbacks_not_unique_shots", 0) + 1
        group["group_level_body_signals"] = group.get("group_level_body_signals", 0) + (event.get("targetBodySignal") is True)
        group["synthetic_contacts"] = group.get("synthetic_contacts", 0) + (event.get("syntheticHit") is True)
    result["knife_motion_models"] = dict(collections.Counter(e.get("settings", {}).get("motionModel", "unrecorded")
        for e in authored.values() if e["kind"] == "knife"))
    result["auto_tune_cohorts"] = {}
    for enabled, label in ((False, "off"), (True, "on")):
        shots = [e for e in authored.values() if e["kind"] == "gun" and e.get("settings", {}).get("autoTune") is enabled]
        signals = [terminal[e["shotId"]] for e in shots if terminal.get(e["shotId"], {}).get("phase") == "confirmation"]
        result["auto_tune_cohorts"][label] = {"authored": len(shots), "signals": len(signals),
            "target_hit_parts": sum(e.get("hitTarget") is True for e in signals),
            "unconfirmed": sum(terminal.get(e["shotId"], {}).get("phase") == "unconfirmed" for e in shots),
            "horizon_seconds": stats([e["settings"]["horizon"] for e in shots if "horizon" in e["settings"]]),
            "actual_correction_logged": sum("autoLeadCorrection" in e.get("settings", {}).get("prediction", {}) for e in shots)}
    knife_shots = sorted((e for e in authored.values() if e["kind"] == "knife"), key=lambda e: e["serverTime"])
    result["knife_configured_delays"] = dict(collections.Counter(str(e.get("settings", {}).get("fireDelay")) for e in knife_shots))
    result["knife_spacing_seconds"] = stats([b["serverTime"] - a["serverTime"] for a, b in zip(knife_shots, knife_shots[1:])])
    result["legacy_hit_labels_not_rate"] = dict(collections.Counter(str(e.get("hitTarget")) for e in events if e["kind"] == "gun"))
    return result

def analyze(directory, snapshot=None):
    report = {"reference_snapshot": snapshot, "files": [], "duplicate_files": [], "datasets": [],
              "method": {"gravity_assumption": 196.2, "maximum_interpolation_gap_seconds": .15,
                         "horizons_seconds": HORIZONS, "selection": "retrospective exploratory comparison; not a blind holdout",
                         "limitations": ["client positions, not server collisions", "legacy hit labels and totals are not reliable hit-rate denominators",
                                         "overlapping forecast windows are not independent shots", "classic/v17 proxies run at recorded cadence, not the original 120Hz internal state",
                                         "map geometry unavailable; generic kernels do not replay authored snapshots or landing probes",
                                         "fixed-horizon comparisons do not identify the correct server prediction horizon"]}}
    # Recognize MM2-specific recordings from structurally detected places, but
    # keep their datasets separate. Never pool those sessions into the main place.
    mm2_places = {142823291}
    for path in directory.glob("*.json"):
        data = json.loads(path.read_bytes())
        if data.get("kind") == "mm2-trajectory-analytics": mm2_places.add(data.get("placeId"))
    seen = {}
    for path in sorted(directory.glob("*.json")):
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        data = json.loads(raw)
        record = {"file": path.name, "sha256": digest, "bytes": len(raw), "placeId": data.get("placeId"),
                  "schema": data.get("schema"), "buildStamp": data.get("buildStamp")}
        report["files"].append(record)
        if digest in seen:
            report["duplicate_files"].append({"file": path.name, "same_as": seen[digest]})
            continue
        seen[digest] = path.name
        item = {"file": path.name, "placeId": data.get("placeId")}
        if data.get("placeId") not in mm2_places:
            item["excluded_from_MM2"] = "different place; retained in manifest, not pooled"
        elif isinstance(data.get("session", {}).get("events"), list):
            item.update(inspect_trajectory(data))
        else:
            item.update({"aggregates": data.get("aggregates"), "retained_shots": len(data.get("shots", [])),
                         "shot_kinds": dict(collections.Counter(s.get("kind", "unspecified") for s in data.get("shots", []))),
                         "outcomes": dict(collections.Counter(s.get("outcome", {}).get("verdict", "unknown") for s in data.get("shots", []))),
                         "retained_hits": len(data.get("hits", [])), "session": data.get("session"),
                         "legacy_warning": data.get("schema") == 1})
        report["datasets"].append(item)
    return report

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--snapshot", help="Source commit, if known; never inferred from filenames")
    args = parser.parse_args()
    report = analyze(args.data, args.snapshot)
    if not report["files"]: parser.error("No JSON files found")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print(f"{len(report['files'])} files; {len(report['duplicate_files'])} duplicate copies excluded; {len(report['datasets'])} unique datasets")
    for d in report["datasets"]:
        print(d["file"], "events", d.get("events"), "points", d.get("points"), "shots", d.get("retained_shots"))

if __name__ == "__main__": main()
