#!/usr/bin/env python3
"""Synthetic checks for the offline analyzer, independent of private/raw logs."""
import json
from pathlib import Path
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True

from analyze_mm2_json import analyze, clean_track, forecasts, replay, inspect_trajectory

class EvidenceAnalysisTests(unittest.TestCase):
    def track(self):
        return [{"dt": i / 20, "position": [16 * i / 20, 0, 0], "velocity": [16, 0, 0],
                 "moveDirection": [1, 0, 0], "grounded": True, "humanoidState": "Running"}
                for i in range(21)]

    def test_constant_velocity_interpolation(self):
        rows = replay([{"kind": "gun", "targetTrajectory": self.track()}])
        self.assertEqual(len(rows), 28)
        for row in rows:
            self.assertGreater(row["windows"], 0)
            self.assertLess(row["per_trajectory_mean_error_studs"]["mean"], 1e-8)

    def test_only_current_intent_used(self):
        track = self.track()
        track[1]["moveDirection"] = [0, 0, 1]
        predicted = forecasts(track[1], track[0], .2)["intent50"]
        self.assertAlmostEqual(predicted[0], .8 + 1.6)
        self.assertAlmostEqual(predicted[2], 1.6)

    def test_malformed_and_nonmonotone_tracks_rejected(self):
        track = self.track()
        track[3]["dt"] = track[2]["dt"]
        self.assertEqual(clean_track(track), [])
        track = self.track()
        track[3]["velocity"][0] = float('nan')
        self.assertEqual(clean_track(track), [])

    def test_no_extrapolation_of_reference_future(self):
        rows = replay([{"kind": "gun", "targetTrajectory": self.track()[:3]}])
        self.assertEqual(rows, [])

    def test_deduplication_place_isolation_and_unknown(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder)
            data = {"placeId": 142823291, "schema": 2, "shots": [{"kind": "gun", "outcome": {"verdict": "unconfirmed"}}], "hits": []}
            raw = json.dumps(data)
            (p / 'a.json').write_text(raw)
            (p / 'copy.json').write_text(raw)
            (p / 'other.json').write_text(json.dumps({**data, "placeId": 99}))
            result = analyze(p)
            self.assertEqual(len(result['duplicate_files']), 1)
            self.assertEqual(len(result['datasets']), 2)
            self.assertEqual(result['datasets'][0]['outcomes'], {'unconfirmed': 1})
            self.assertIn('excluded_from_MM2', result['datasets'][1])

    def test_auto_tune_cohorts_are_not_merged(self):
        events = [
            {"kind": "gun", "phase": "authored", "shotId": "a", "settings": {"autoTune": True, "horizon": .2}},
            {"kind": "gun", "phase": "confirmation", "shotId": "a", "latencyMs": 180, "hitTarget": True},
            {"kind": "gun", "phase": "authored", "shotId": "b", "settings": {"autoTune": False, "horizon": .2}},
            {"kind": "gun", "phase": "unconfirmed", "shotId": "b"},
        ]
        r = inspect_trajectory({"session": {"events": events}})["auto_tune_cohorts"]
        self.assertEqual(r["on"]["target_hit_parts"], 1)
        self.assertEqual(r["off"]["signals"], 0)
        self.assertEqual(r["off"]["unconfirmed"], 1)
        self.assertEqual(r["on"]["actual_correction_logged"], 0)

    def test_detected_mm2_place_stays_separate(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder)
            for place in (142823291, 99):
                (p / f"{place}.json").write_text(json.dumps({"placeId": place,
                    "kind": "mm2-trajectory-analytics", "session": {"events": []}}))
            (p / 'learning.json').write_text(json.dumps({"placeId": 99, "shots": [], "schema": 2}))
            r = analyze(p)
            self.assertEqual(len(r['datasets']), 3)
            self.assertFalse(any('excluded_from_MM2' in d for d in r['datasets']))
            self.assertIsNone(r['reference_snapshot'])

    def test_profiles_and_burst_do_not_inflate_acceptance(self):
        events = []
        for index in (1, 2, 3):
            events.append({"kind": "gun", "phase": "authored", "shotId": str(index), "settings": {
                "prediction": {"profile": "Old"}, "burst": {"groupId": "g", "index": index, "count": 4}}})
        events += [
            {"kind": "gun", "phase": "burst-signal", "groupId": "g", "targetBodySignal": True},
            {"kind": "gun", "phase": "confirmation", "shotId": "1", "latencyMs": 200, "hitTarget": False, "syntheticHit": True},
            {"kind": "gun", "phase": "unconfirmed", "shotId": "2"},
            {"kind": "gun", "phase": "authored", "shotId": "a", "settings": {"prediction": {"profile": "Actual"}}},
        ]
        r = inspect_trajectory({"session": {"events": events}})
        self.assertEqual(r["prediction_profiles"]["Old"], {"authored": 3, "signals": 1, "target_hit_parts": 0, "unconfirmed": 1})
        self.assertEqual(r["prediction_profiles"]["Actual"]["authored"], 1)
        self.assertEqual(r["burst_groups"]["g"]["planned"], 4)
        self.assertEqual(r["burst_groups"]["g"]["authored"], 3)
        self.assertEqual(r["burst_groups"]["g"]["signals"], 1)
        self.assertEqual(r["burst_groups"]["g"]["group_level_body_signals"], 1)
        self.assertEqual(r["burst_groups"]["g"]["target_hit_parts"], 0)

if __name__ == '__main__': unittest.main()
