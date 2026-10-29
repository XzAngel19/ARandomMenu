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
assert '"Bullet"' in auto_shoot and '"CFrame"' in auto_shoot and '"Experimental"' in auto_shoot
assert '"WallCheck"' in auto_shoot
assert '"Proximity"' in auto_shoot
assert '"Aura"' in auto_shoot

# Proximity Warning module was removed and replaced by Auto Win in Utilities
assert not (ROOT / 'src/games/MM2/Other/ProximityWarning.lua').exists()
auto_win = (ROOT / 'src/games/MM2/Other/AutoWin.lua').read_text()
assert '"Auto Win"' in auto_win
assert '"Insta Kill as Murder"' in auto_win
assert '"Insta Kill As Sheriff"' in auto_win
assert '"Fling Sheriff and Get Gun"' in auto_win

# Knife Throw should also be independent now
knife_throw = (ROOT / 'src/games/MM2/Combat/KnifeThrow.lua').read_text()
assert 'createUniversalFeature' in knife_throw
assert '"Knife Throw"' in knife_throw
assert 'categoryName = "Combat"' in knife_throw
assert '"WallCheck"' in knife_throw
assert '"Delay"' in knife_throw

# Gun Aimbot (formerly SilentAIM) should have Bullet/CFrame modes and WallCheck as the single gate
assert '"Gun Aimbot"' in S
assert '"Bullet"' in S and '"CFrame"' in S and '"Experimental"' in S
for retained in ('Aim method', 'Target', 'WallCheck', 'Macro'):
    assert f'"{retained}"' in S, f'{retained} must still be in Gun Aimbot'

fling = (ROOT / 'src/games/universal/Blatant/Fling.lua').read_text()
assert '\n        "Auto Fling Selected Target",\n' not in fling, 'Auto Fling must stay deleted'
assert 'configData.states["MM2.Fling.AutoFlingSelectedTarget"] = nil' in fling, \
    'the stale Auto Fling key must be dropped at boot'
assert '"Touch Fling"' not in fling, 'Walk Fling is its own card now, not an option here'
assert 'FLING_VELOCITY' in fling and '9e7' in fling, 'Fling must use the SkidFling velocity'
walkfling = (ROOT / 'src/games/universal/Blatant/WalkFling.lua').read_text()
assert '"Walk Fling"' in walkfling, 'Walk Fling must be its own module'
assert 'configData.states["Universal.WalkFling"] = false' in walkfling, \
    'Walk Fling must never be restored from the saved config'
assert 'MAP_FLING_WARMUP_SECONDS' in auto_win, 'Auto Win must wait for map load before Fling Sheriff'

print('PASS Auto Shoot and Knife Throw are now independent Combat modules with required options')
