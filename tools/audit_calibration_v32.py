#!/usr/bin/env python3
"""Summarize supplied calibrations; never interpret echo counts as hit probability.
Usage: python3 tools/audit_calibration_v32.py file1.json file2.json ...
Reports a limited client-trajectory replay, NOT a server/hit-rate backtest.
"""
import argparse
import collections
import json
import math
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path)
    args = parser.parse_args()
    seen = set()
    for path in args.files:
        data = json.loads(path.read_text())
        events = data.get('session', {}).get('events', [])
        confirmations = [e for e in events if e.get('kind') == 'gun' and e.get('phase') == 'confirmation']
        traces = [e for e in events if e.get('phase') == 'tracer-data']
        print(f"{path.name}: build={data.get('buildStamp')}, events={len(events)}, gun confirmations={len(confirmations)}, hitPart-target associations={sum(e.get('hitTarget') is True for e in confirmations)}, traces={len(traces)}")
        print('  These are associations among recorded echoes, not a hit-rate denominator.')
        print('  Non-target trace hit classes:', dict(collections.Counter(
            'Workspace environment' if e.get('hitPartPath', '').startswith('Workspace.') else 'unknown'
            for e in traces if e.get('hitTarget') is False)))
        for event in confirmations:
            key = (event.get('sessionId', data.get('sessionId')), event.get('shotId'))
            if key in seen:
                continue
            seen.add(key)
            trajectory = event.get('targetTrajectory', [])
            if len(trajectory) < 2:
                continue
            initial = trajectory[0]
            horizon = min(event['pingMs'] / 1000, 0.15)
            later = next((i for i, p in enumerate(trajectory) if p['dt'] >= horizon), None)
            if later is None or later == 0:
                continue
            a, b = trajectory[later-1], trajectory[later]
            span = b['dt'] - a['dt']
            if span <= 0:
                continue
            fraction = (horizon - a['dt']) / span
            observed_y = a['position'][1] + (b['position'][1] - a['position'][1]) * fraction - initial['position'][1]
            velocity_y = initial['velocity'][1]
            airborne = initial.get('humanoidState') in ('Jumping', 'Freefall') or (not initial.get('grounded') and abs(velocity_y) > 0.5)
            lead = horizon * math.cos(horizon * math.pi / 4)
            if airborne and velocity_y > 0:
                ballistic_y = velocity_y * lead - 0.5 * 196.2 * lead * lead
                if ballistic_y > 3:
                    old = min(3, max(-3, ballistic_y))
                    new = min(6, max(-3, ballistic_y))
                    print(f'  Rising client-pose replay: observed dy={observed_y:.3f}, ballistic={ballistic_y:.3f}, old cap error={abs(old-observed_y):.3f}, new cap error={abs(new-observed_y):.3f} studs')
                    print('  Assumes default turn discount; actual pre-shot turn rate was not recorded; not proof the server would register a hit.')


if __name__ == '__main__':
    main()
