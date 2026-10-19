#!/usr/bin/env python3
"""Developer surfaces (calibration capture) only exist with WURST_DEBUG."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
trajectory = (ROOT / 'src/games/MM2/Other/TrajectoryCalibration.lua').read_text()
trails = (ROOT / 'src/games/MM2/Other/CalibrationTrails.lua').read_text()
wurst = (ROOT / 'src/Wurst.lua').read_text()

# The flag the framework already uses for its debug logging is the same one
# the menu reads: one switch, no second definition of "debug".
assert 'debug = DEBUG_LOGS' in wurst, 'state.debug must mirror the boot flag'

# The early return must come before the card is created, or a release boot
# would still build it and only skip the rest.
gate = trajectory.index('if state.debug ~= true then')
card = trajectory.index('createUniversalFeature(')
assert gate < card, 'the debug gate must run before the Calibration card'

# The trail module depends on that card; it must skip silently, not assert.
assert 'assert(core and state.mm2CalibrationFeature' not in trails, (
    'Calibration Trails must not require a card that a release boot skips'
)
assert trails.index('if not state.mm2CalibrationFeature then') < trails.index(
    'addToggleOption'
), 'the trail options are created before the card check'

# Nothing else in the menu is debug-gated behind the user's back.
for path in (ROOT / 'src/games').rglob('*.lua'):
    if path.name in ('TrajectoryCalibration.lua', 'CalibrationTrails.lua'):
        continue
    text = path.read_text()
    assert 'state.debug' not in text, f'{path} hides user surface behind debug'

print('PASS debug surfaces: Calibration and TrailESP gated before creation, no other hidden cards')
