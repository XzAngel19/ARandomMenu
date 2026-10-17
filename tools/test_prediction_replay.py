#!/usr/bin/env python3
"""Fixed de-identified client-pose regression fixtures; NEVER a hit-rate test."""
from pathlib import Path
from replay_gun_prediction import run
ROOT=Path(__file__).resolve().parents[1]
fixtures=ROOT/'tools/fixtures/prediction-v42'
for names in [('development',),('holdout',),('small-v34','small-v31')]:
 report=run([fixtures/(name+'.json') for name in names])
 assert report['all']['samples']>0
 assert report['all']['adaptiveMAE'] <= report['all']['referenceMAE']+1e-8
print('PASS fixed client-pose replay: 477 samples; A/B same samples, no server accuracy claim')
