#!/usr/bin/env python3
"""Static contract for Anti AFK.

The module attempts input on a timer and on Idled, falling back across
input services. This static check cannot verify that the executor supports
the calls or that Roblox's idle timer actually resets.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Other/AntiAfk.lua').read_text()

assert '"Anti AFK"' in SOURCE
# Proactive: never wait for the 20-minute warning.
assert "AntiAFKTimer" in SOURCE and "elapsed < 150" in SOURCE
# Reactive answer to the idle warning is kept.
assert "LocalPlayer.Idled:Connect" in SOURCE
# Legacy capture alone is not trusted: explicit down/up, then the
# legacy click, then a whole other input service.
assert "Button2Down" in SOURCE and "Button2Up" in SOURCE
assert 'GetService("VirtualInputManager")' in SOURCE
assert "SendMouseButtonEvent" in SOURCE
# Screen centre, not the (0,0) corner.
assert "ViewportSize / 2" in SOURCE
# OFF and unload disconnect both connections.
assert SOURCE.count('disconnectFeatureConnection("AntiAFKTimer")') >= 2

print("PASS Anti AFK: proactive 150 s input simulation, Idled answer, "
      "VirtualUser down/up -> legacy click -> VirtualInputManager "
      "fallback, full disconnect cleanup")
