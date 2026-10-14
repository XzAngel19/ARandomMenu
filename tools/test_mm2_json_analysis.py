#!/usr/bin/env python3
"""Synthetic checks for the offline analyzer, independent of private/raw logs."""
import json
from pathlib import Path
import tempfile
import unittest
import sys
sys.dont_write_bytecode = True

from analyze_mm2_json import analyze, clean_track, forecasts, replay

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

if __name__ == '__main__': unittest.main()
