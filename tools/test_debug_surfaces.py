#!/usr/bin/env python3
"""The calibration card ships in release, and consent -- not debug -- gates it."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
trajectory = (ROOT / "src/games/MM2/Other/TrajectoryCalibration.lua").read_text()
trails = (ROOT / "src/games/MM2/Other/CalibrationTrails.lua").read_text()
base = (ROOT / "src/games/MM2/base.lua").read_text()
wurst = (ROOT / "src/Wurst.lua").read_text()

# The flag the framework already uses for its debug logging is the same one
# the menu reads: one switch, no second definition of "debug".
assert "debug = DEBUG_LOGS" in wurst, "state.debug must mirror the boot flag"

# v180: the card is back for everybody. What used to be a debug gate is now a
# consent gate: no answer means nothing is written to the executor workspace.
assert "if state.debug ~= true then" not in trajectory, (
    "the Calibration card must not be hidden behind WURST_DEBUG any more"
)
assert "state.mm2CalibrationFeature" in trajectory
assert 'state.confirmDialog' in trajectory, "the Yes/No question must be the modal dialog"
assert "getConsent" in trajectory and "setConsent" in trajectory
assert "Would you like to give your calibration?" in trajectory

# The recorder honours the answer on both write paths.
assert '"MM2.Calibration.Consent"' in base
assert base.count('states["MM2.Calibration.Consent"]') >= 2, (
    "both the scheduled save and saveSnapshot must read the consent"
)
assert "environment.delfile" in base, "answering No must remove the file written before"

# The trail module depends on that card; it must skip silently, not assert.
assert "assert(core and state.mm2CalibrationFeature" not in trails, (
    "Calibration Trails must not require a card that may be missing"
)
assert trails.index("if not state.mm2CalibrationFeature then") < trails.index(
    "addToggleOption"
), "the trail options are created before the card check"

# Nothing else in the menu is debug-gated behind the user's back.
for path in (ROOT / "src/games").rglob("*.lua"):
    if path.name in ("TrajectoryCalibration.lua", "CalibrationTrails.lua"):
        continue
    text = path.read_text()
    assert "state.debug" not in text, f"{path} hides user surface behind debug"

print("PASS debug surfaces: Calibration ships in release behind consent, no hidden cards")
