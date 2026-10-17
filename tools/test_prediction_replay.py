#!/usr/bin/env python3
"""Fixed de-identified client-pose regression fixtures; NEVER a hit-rate test."""
from pathlib import Path
import replay_gun_prediction as replay
run=replay.run
ROOT=Path(__file__).resolve().parents[1]
fixtures=ROOT/'tools/fixtures/prediction-v42'
replay.BASE=(ROOT/'docs/prediction-baselines/v44/base.lua.txt').read_text()
replay.SHOOT=(ROOT/'docs/prediction-baselines/v44/Shoot.lua.txt').read_text()
for names in [('development',),('holdout',),('small-v34','small-v31')]:
 report=run([fixtures/(name+'.json') for name in names],candidate="Adaptive")
 assert report['all']['samples']>0
 assert report['all']['adaptiveMAE'] <= report['all']['referenceMAE']+1e-8
print('PASS historical archived v44 client-pose replay: 477 samples; A/B same samples, no server accuracy claim')
