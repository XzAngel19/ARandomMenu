#!/usr/bin/env python3
"""Simulate the v161 lead loop over the saved calibration sessions.

What this measures: the confirmed shots store `leadErrorSeconds` (how far the
target was ahead/behind the aim when the server scored it) and the correction
that was in force. Replaying those numbers offline shows what the closed loop
would have done to the NEXT shot. It is a statement about the mechanism, not
about hit rate: the server's own validation is not observable from here.

Constants are read from the Luau source, so the simulation cannot drift away
from what the module actually uses.
"""
import argparse, json, re, statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREDICTION = (ROOT / 'src/games/MM2/Prediction.lua').read_text()


def constant(name):
    match = re.search(rf'local {name}: number = ([0-9.]+)', PREDICTION)
    if not match:
        raise SystemExit(f'missing constant {name} in Prediction.lua')
    return float(match.group(1))


MIN_SAMPLES = int(constant('LEAD_FEEDBACK_MIN_SAMPLES'))
MAX_SAMPLES = int(constant('LEAD_FEEDBACK_MAX_SAMPLES'))
SAMPLE_LIMIT = constant('LEAD_FEEDBACK_SAMPLE_LIMIT')
MAX_CORRECTION = constant('MAX_LEAD_CORRECTION')
SLEW = constant('LEAD_SLEW_PER_SAMPLE')


def mode_key(shot_mode):
    text = (shot_mode or '').lower()
    if text in ('normal', 'bullet'):
        return 'Bullet'
    if text in ('silent', 'cframe', 'silent aim'):
        return 'CFrame'
    return 'default'


def shots(path):
    data = json.loads(Path(path).read_text())
    found = {}
    for event in data.get('session', {}).get('events', []):
        if event.get('phase') != 'confirmation':
            continue
        error = event.get('leadErrorSeconds')
        if not isinstance(error, (int, float)):
            continue
        shot_id = event.get('shotId')
        row = {
            'shot': shot_id,
            'mode': mode_key(event.get('shotMode') or event.get('aimMode')),
            'error': float(error),
            'applied': float(event.get('leadCorrectionSeconds') or 0.0),
            'speed': None,
            'endpointError': event.get('endpointErrorStuds'),
        }
        trajectory = event.get('targetTrajectory') or []
        if trajectory:
            velocity = trajectory[-1].get('velocity') or [0, 0, 0]
            row['speed'] = (velocity[0] ** 2 + velocity[2] ** 2) ** 0.5
        found[shot_id] = row
    return [found[key] for key in found]


def simulate(rows):
    buckets, applied = {}, {}
    out = []
    for row in rows:
        key = row['mode']
        bucket = buckets.setdefault(key, [])
        if abs(row['error']) <= SAMPLE_LIMIT:
            bucket.append(row['error'])
            while len(bucket) > MAX_SAMPLES:
                bucket.pop(0)
            if len(bucket) >= MIN_SAMPLES:
                target = max(-MAX_CORRECTION, min(MAX_CORRECTION, statistics.median(bucket)))
                current = applied.get(key, 0.0)
                step = max(-SLEW, min(SLEW, target - current))
                applied[key] = current + step
        correction = applied.get(key, 0.0)
        out.append({**row, 'loop': correction,
                    'residual': row['error'] - correction})
    return out


def summary(rows, field):
    values = [abs(row[field]) for row in rows]
    if not values:
        return None
    return {
        'n': len(values),
        'mean': sum(values) / len(values),
        'median': statistics.median(values),
        'meanStuds': (sum(abs(row[field]) * (row['speed'] or 0) for row in rows)
                      / max(1, sum(1 for row in rows if row['speed']))),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('captures', nargs='+')
    parser.add_argument('--json', action='store_true', help='machine readable')
    args = parser.parse_args()

    report = {
        'limits': (
            'Offline replay of the recorded lead errors. The correction is '
            'measured in seconds and converted to studs with the recorded '
            'horizontal speed; it says nothing about the server accepting a '
            'shot, nor about hit rate. Same captures were not used to fit the '
            'constants.'),
        'constants': {
            'minSamples': MIN_SAMPLES,
            'maxSamples': MAX_SAMPLES,
            'sampleLimit': SAMPLE_LIMIT,
            'maxCorrection': MAX_CORRECTION,
            'slewPerSample': SLEW,
        },
        'sessions': {},
    }
    for path in args.captures:
        rows = shots(path)
        if not rows:
            continue
        simulated = simulate(rows)
        by_mode = {}
        for row in simulated:
            by_mode.setdefault(row['mode'], []).append(row)
        report['sessions'][Path(path).name] = {
            'shots': len(simulated),
            'recorded': summary(simulated, 'error'),
            'withLoop': summary(simulated, 'residual'),
            'byMode': {
                key: {
                    'shots': len(value),
                    'recorded': summary(value, 'error'),
                    'withLoop': summary(value, 'residual'),
                }
                for key, value in by_mode.items()
            },
            'trace': [
                {'shot': row['shot'], 'mode': row['mode'],
                 'error': round(row['error'], 4),
                 'applied': round(row['loop'], 4),
                 'residual': round(row['residual'], 4)}
                for row in simulated
            ],
        }

    if args.json:
        print(json.dumps(report, indent=2))
        return

    for name, session in report['sessions'].items():
        recorded = session['recorded']
        looped = session['withLoop']
        print(f'{name}: {session["shots"]} confirmaciones')
        if recorded and looped:
            print(f'  error de plomo  grabado {recorded["mean"] * 1000:6.1f} ms'
                  f'  ->  con lazo {looped["mean"] * 1000:6.1f} ms')
            print(f'  mediana         grabado {recorded["median"] * 1000:6.1f} ms'
                  f'  ->  con lazo {looped["median"] * 1000:6.1f} ms')
        for mode, data in session['byMode'].items():
            print(f'  {mode:<8} n={data["shots"]}'
                  f'  {data["recorded"]["mean"] * 1000:6.1f} ms'
                  f' -> {data["withLoop"]["mean"] * 1000:6.1f} ms')
        for row in session['trace']:
            print(f'    {row["shot"]}  {row["mode"]:<8}'
                  f' error {row["error"] * 1000:+6.1f} ms'
                  f'  corrección {row["applied"] * 1000:+6.1f} ms'
                  f'  resto {row["residual"] * 1000:+6.1f} ms')


if __name__ == '__main__':
    main()
