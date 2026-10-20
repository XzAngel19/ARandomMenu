#!/usr/bin/env python3
"""Offline audit of every saved MM2_Trajectory_Calibration.json.

Reads a directory of captures (the game writes one file plus its .before-*
history backups) and prints, per session:

  * the build stamp and how many shots/throwing events it holds;
  * gun confirmations: hits, echo vs engine ping, and the signed lead error
    at the instant the shot resolves (the recorded root at confirmation, plus
    the aim offset, projected on the target's horizontal velocity). Positive
    means the target was ahead of the aim, i.e. the shot under-led;
  * what an ideal lead would have been, so the systematic bias is a number
    instead of an opinion;
  * knife throws: speed, aim rung and how much of the throw was led.

Nothing here changes the game. It only reads files:

    python3 tools/analyze_calibration_sessions.py /path/to/captures
"""
from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path


def vec(value):
    if isinstance(value, (list, tuple)) and len(value) >= 3:
        return (float(value[0]), float(value[1]), float(value[2]))
    return None


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def finite(value):
    return isinstance(value, (int, float)) and value == value and abs(value) != float('inf')


def lead_error_seconds(event):
    """Where the target actually was when the shot resolved.

    The capture stores the root position at confirmation and the newest
    pre-shot sample. Of the three candidate instants (fire, half round trip,
    confirmation), only the confirmation position separates hits from misses
    in the saved sessions, so that is the one the aim is scored against.
    """
    root = vec((event.get('rootAtConfirmation') or {}).get('position'))
    velocity = vec((event.get('rootAtConfirmation') or {}).get('velocity'))
    history = event.get('targetHistory') or []
    aim = vec(event.get('aim'))
    if not root or not velocity or not history or not aim:
        return None
    offset = vec(history[-1].get('aimOffset')) or (0.0, 0.0, 0.0)
    aim_point = tuple(root[i] + offset[i] for i in range(3))
    vx, vz = velocity[0], velocity[2]
    speed = (vx * vx + vz * vz) ** 0.5
    if speed < 3:
        return None
    along = ((aim_point[0] - aim[0]) * vx + (aim_point[2] - aim[2]) * vz) / speed
    if abs(along) > 6:
        return None
    return along / speed


def audit(path: Path) -> dict:
    data = json.loads(path.read_text())
    session = data.get('session') or {}
    events = session.get('events') or []
    stamp = data.get('buildStamp') or 'unknown'
    guns = [e for e in events if e.get('kind') == 'gun']
    authored = [e for e in guns if e.get('phase') == 'authored']
    confirmations = [e for e in guns if e.get('phase') == 'confirmation']
    knives = [e for e in events if e.get('kind') == 'knife']
    knife_activations = [e for e in events if e.get('kind') == 'knifeActivation']

    hits = [e for e in confirmations if e.get('hitTarget') is True]
    echoes = [e['serverEchoMs'] for e in confirmations if finite(e.get('serverEchoMs'))]
    pings = [e['latencyMs'] for e in confirmations if finite(e.get('latencyMs'))]
    errors = [value for value in (lead_error_seconds(e) for e in confirmations) if value is not None]

    def stats(values):
        if not values:
            return None
        return {
            'n': len(values),
            'median': statistics.median(values),
            'min': min(values),
            'max': max(values),
        }

    # Ideal lead: the lead we used minus the error we measured. Only useful
    # where the record carries the lead it actually used.
    ideal = []
    for event in confirmations:
        used = event.get('horizontalLeadSeconds')
        error = lead_error_seconds(event)
        if finite(used) and error is not None:
            ideal.append(float(used) + error)

    knife_speeds = [e['speed'] for e in knives if finite(e.get('speed'))]
    knife_heights = [e.get('aimHeight') for e in knives if e.get('aimHeight')]

    return {
        'file': path.name,
        'stamp': stamp,
        'session': data.get('sessionId') or session.get('sessionId'),
        'savedAt': data.get('savedAt'),
        'authored': len(authored),
        'confirmed': len(confirmations),
        'hits': len(hits),
        'echo': stats(echoes),
        'ping': stats(pings),
        'lead_error': stats(errors),
        'ideal_lead': stats(ideal),
        'knives': len(knives),
        'knife_throws': len(knife_activations),
        'knife_speed': stats(knife_speeds),
        'knife_heights': {height: knife_heights.count(height) for height in set(knife_heights)},
    }


def main(argv: list[str]) -> int:
    root = Path(argv[1] if len(argv) > 1 else '.')
    files = sorted(root.glob('MM2_Trajectory_Calibration*.json'))
    if not files:
        print(f'no captures under {root}')
        return 1
    seen = set()
    for path in files:
        try:
            row = audit(path)
        except Exception as error:  # a truncated backup is not a crash
            print(f'{path.name}: unreadable ({error})')
            continue
        key = (row['stamp'], str(row['session']), row['confirmed'], row['knives'])
        if key in seen:
            continue
        seen.add(key)
        echo = row['echo']
        ping = row['ping']
        error = row['lead_error']
        ideal = row['ideal_lead']
        print(
            f"{row['stamp']:<46} shots {row['authored']:>3}"
            f" conf {row['confirmed']:>3} hits {row['hits']:>3}"
            f" echo {echo['median']:.0f} ms" if echo else
            f"{row['stamp']:<46} shots {row['authored']:>3}"
            f" conf {row['confirmed']:>3} hits {row['hits']:>3} echo n/a",
            end='',
        )
        if ping:
            print(f" ping {ping['median']:.0f} ms", end='')
        if error:
            print(
                f"  lead error median {error['median'] * 1000:+.0f} ms"
                f" [{error['min'] * 1000:+.0f}, {error['max'] * 1000:+.0f}] n={error['n']}",
                end='',
            )
        if ideal:
            print(f"  ideal lead {ideal['median'] * 1000:.0f} ms", end='')
        if row['knife_throws']:
            speed = row['knife_speed']
            print(
                f"  throws {row['knife_throws']} speed "
                + (f"{speed['median']:.0f}" if speed else 'n/a'),
                end='',
            )
        print()
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
