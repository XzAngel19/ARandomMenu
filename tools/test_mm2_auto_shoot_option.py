#!/usr/bin/env python3
"""Auto Shoot is now an independent module, not nested in SilentAIM."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
S = (ROOT / 'src/games/MM2/Blatant/Shoot.lua').read_text()

# Auto Shoot should NOT be in Shoot.lua anymore (it's now independent)
assert 'addToggleOption(ShootFeature, "Auto Shoot"' not in S, 'Auto Shoot must be removed from SilentAIM (now independent module)'

# Auto Shoot should exist as an independent module
auto_shoot = (ROOT / 'src/games/MM2/Combat/AutoShoot.lua').read_text()
assert 'createUniversalFeature' in auto_shoot
assert '"Auto Shoot"' in auto_shoot
assert 'categoryName = "Combat"' in auto_shoot

# Check Auto Shoot has the required options
assert '"Mode"' in auto_shoot
assert '"WallCheck"' in auto_shoot
assert '"Aura"' in auto_shoot

# Knife Throw should also be independent now
knife_throw = (ROOT / 'src/games/MM2/Combat/KnifeThrow.lua').read_text()
assert 'createUniversalFeature' in knife_throw
assert '"Knife Throw"' in knife_throw
assert 'categoryName = "Combat"' in knife_throw
assert '"WallCheck"' in knife_throw
assert '"Delay"' in knife_throw

# SilentAIM should still have the other options
for retained in ('Aim method', 'Target', 'Raw', 'Macro'):
    assert f'"{retained}"' in S, f'{retained} must still be in SilentAIM'

print('PASS Auto Shoot and Knife Throw are now independent Combat modules with required options')
