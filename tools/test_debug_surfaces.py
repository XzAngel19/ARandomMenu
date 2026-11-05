#!/usr/bin/env python3
"""Calibration is popup-only in both release and debug; recording requires Yes."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
base = (ROOT / "src/games/MM2/base.lua").read_text()
wurst = (ROOT / "src/Wurst.lua").read_text()
manifest = (ROOT / "src/libraries/Manifest.lua").read_text()
assert "debug = DEBUG_LOGS" in wurst
assert "rememberLabel = \"Don't Show Again\"" in base
assert 'state.confirmDialog({' in base and 'trajectoryCalibration:prepare()' in base
assert '"MM2.Calibration.Consent"' in base and '"MM2.Calibration.DontShowAgain"' in base
for name in ("TrajectoryCalibration.lua", "CalibrationTrails.lua"):
    assert name not in manifest and not (ROOT / "src/games/MM2/Other" / name).exists()
for path in (ROOT / "src/games").rglob("*.lua"):
    assert "state.debug" not in path.read_text(), f"{path} hides user surface behind debug"
print("PASS debug surfaces: consent-gated Calibration is popup-only")
