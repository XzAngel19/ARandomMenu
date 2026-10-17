#!/usr/bin/env python3
"""Audit Cobalt logs without counting per-listener duplicates as extra shots.

python3 tools/analyze_mm2_remote_logs.py path/to/*.log
Only packet/echo geometry is measured, never inferred hit probability.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path


def numbers(text):
    return [float(value.strip()) for value in text.split(',')]


def analyze(path):
    text = path.read_text()
    packets = []
    for block in re.split(r'(?m)^(?=2026-)', text):
        header = re.match(r'^([^,\n]+),([\d.]+),(Outgoing|Incoming):([^,\n]+)', block)
        if not header:
            continue
        args = re.search(r'Arguments = \{(.*?)\n\s*n = \d+', block, re.S)
        if not args:
            continue
        creation = re.search(r'CreationTime = ([\d.]+)', block)
        source = re.search(r'Source = "([^"]+)"', block)
        packets.append({
            'event': header[4], 'direction': header[3], 'elapsed': float(header[2]),
            'created': float(creation[1]) if creation else float(header[2]),
            'args': args[1], 'source': source[1] if source else None,
        })
    shots = [p for p in packets if p['direction'] == 'Outgoing' and p['event'] == 'Shoot']
    knives = [p for p in packets if p['direction'] == 'Outgoing' and p['event'] == 'KnifeThrown']
    echoes = [p for p in packets if p['direction'] == 'Incoming' and p['event'] == 'GunFired']
    unique = []
    for echo in echoes:
        vectors = re.findall(r'Vector3.new\(([^)]+)\)', echo['args'])
        if len(vectors) < 2:
            continue
        # Nil-parent aliases may replace the hit Instance between listeners.
        # Exact numeric ray geometry + shooter + a 20ms capture-time cluster
        # is the same echo, not four independent confirmations.
        geometry = tuple(tuple(numbers(v)) for v in vectors[:2])
        own = 'LocalPlayer.Character.Gun.Handle' in echo['args']
        if any(item['own'] == own and item['geometry'] == geometry
               and abs(echo['created'] - item['created']) < .02 for item in unique):
            continue
        unique.append({**echo, 'own': own, 'geometry': geometry})
    matched = []
    for shot in shots:
        frames = re.findall(r'CFrame.new\(([^)]+)\)', shot['args'])
        if len(frames) < 2:
            continue
        origin, aim = [numbers(frame)[:3] for frame in frames[:2]]
        candidates = [e for e in unique if e['own'] and 0 <= e['created'] - shot['created'] <= 2
                      and math.dist(e['geometry'][0], origin) < .05]
        if not candidates:
            continue
        echo = min(candidates, key=lambda e: e['created'])
        endpoint = echo['geometry'][1]
        direction = [b-a for a, b in zip(origin, aim)]
        length = math.sqrt(sum(v*v for v in direction))
        if length == 0:
            continue
        unit = [v/length for v in direction]
        actual = [b-a for a, b in zip(origin, endpoint)]
        projection = sum(a*b for a, b in zip(actual, unit))
        perpendicular = math.sqrt(sum((v - projection*u)**2 for v, u in zip(actual, unit)))
        matched.append({
            'source': shot['source'],
            'outgoingToEchoCaptureMs': round((echo['created'] - shot['created'])*1000, 3),
            'outgoingToEchoHeaderMs': round((echo['elapsed'] - shot['elapsed'])*1000, 3),
            'echoEndpointToAuthoredRayStuds': round(perpendicular, 6),
            'endpointBeyondAimStuds': round(projection - length, 6),
            'echoArguments': re.sub(r'\s+', ' ', echo['args'].strip()),
        })
    return {
        'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'outgoingShootPackets': len(shots), 'outgoingKnifePackets': len(knives),
        'knifeSources': sorted(set(k['source'] for k in knives if k['source'])),
        'knifeIntervalsSeconds': [round(b['elapsed']-a['elapsed'], 6) for a, b in zip(knives, knives[1:])],
        'gunEchoListenerRecords': len(echoes), 'deduplicatedGunEchoes': len(unique),
        'deduplicatedOwnGunEchoes': sum(e['own'] for e in unique),
        'authoredEchoPairs': matched,
        'animationEvidenceTerms': {term: text.count(term) for term in ['AnimationId', 'AnimationPlayed', 'LoadAnimation', 'Motor6D']},
        'limits': 'Echo latency is not server rewind age. Echo geometry is not target trajectory or hit rate. Native throw packets do not contain animation keyframes.',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs', nargs='+', type=Path)
    args = parser.parse_args()
    print(json.dumps([analyze(path) for path in args.logs], indent=2))
