#!/usr/bin/env python3
"""Independent KnifeThrow module: verify structure and Remote-based throw."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Combat/KnifeThrow.lua').read_text()

# The new KnifeThrow is independent, not a rebuild of the old complex module
assert 'createUniversalFeature' in SOURCE
assert '"Knife Throw"' in SOURCE
assert 'categoryName = "Combat"' in SOURCE

# Verify required options
assert '"WallCheck"' in SOURCE
assert '"Delay"' in SOURCE

# Verify it has the core functions
assert 'local function getKnife' in SOURCE
assert 'local function findTarget' in SOURCE
assert 'local function throwKnife' in SOURCE
assert 'local function toggleKnifeThrow' in SOURCE

# Verify it invokes Remote directly for natural animation
assert 'FireServer' in SOURCE

print('PASS Independent KnifeThrow: simple Remote-based module, no complex rebuild needed')
