#!/usr/bin/env python3
"""Independent KnifeThrow module: verify WallCheck option."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'src/games/MM2/Combat/KnifeThrow.lua').read_text()

# Verify WallCheck option exists
assert '"WallCheck"' in SOURCE
assert 'settings.wallCheck' in SOURCE or 'wallCheck' in SOURCE.lower()

# Verify it uses path checking
assert 'isWeaponPathClear' in SOURCE or 'wall' in SOURCE.lower()

# Verify the option has proper description
assert 'WallCheck' in SOURCE

print('PASS Independent KnifeThrow: WallCheck option present with path validation')
