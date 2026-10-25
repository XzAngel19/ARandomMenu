#!/usr/bin/env python3
"""Independent KnifeThrow module: Remote-based throw with WallCheck and Delay."""
import os
import subprocess
import tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Combat/KnifeThrow.lua').read_text()

# The new KnifeThrow is an independent module that invokes the Remote directly
# for natural throw animation, with WallCheck and user-controlled Delay
assert 'createUniversalFeature' in SOURCE
assert '"Knife Throw"' in SOURCE
assert '"WallCheck"' in SOURCE
assert '"Delay"' in SOURCE
assert 'categoryName = "Combat"' in SOURCE

# Verify it invokes the Remote directly (natural throw)
assert 'remote:FireServer' in SOURCE or 'FireServer' in SOURCE

# Verify it has the required structure
assert 'local function getKnife' in SOURCE
assert 'local function findTarget' in SOURCE
assert 'local function throwKnife' in SOURCE
assert 'local function toggleKnifeThrow' in SOURCE

# Verify WallCheck logic exists
assert 'isWeaponPathClear' in SOURCE or 'wallCheck' in SOURCE.lower()

# Verify Delay logic exists
assert 'settings.delay' in SOURCE
assert 'lastThrowAttempt' in SOURCE

print('PASS Independent KnifeThrow: Remote-based throw, WallCheck, user-controlled Delay, Combat category')
