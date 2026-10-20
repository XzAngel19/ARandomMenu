#!/usr/bin/env python3
"""Provider rows (Gun ESP, Trap ESP) must never be ON and silently dead."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Render/ItemRender.lua').read_text()

start = SOURCE.index('local function setProviderEnabled')
end = SOURCE.index('-- Bounded template fingerprint')
helper = SOURCE[start:end]

script = helper + r'''
local provider = {name = "Gun ESP", enabled = nil}
-- Providers are plain functions, called as pcall(setEnabled, value).
provider.setEnabled = function(value) provider.enabled = value end
local function newCard(initial)
    local card = {Enabled = initial, Toggles = 0, Activated = 0,
        Activate = function(self) self.Activated += 1 end,
        Toggle = function(self, value) self.Toggles += 1; self.Enabled = value end}
    card.Feature = {enabled = initial,
        activate = function() card.Activated += 1; card.Enabled = true end}
    return card
end

-- Card OFF, row ON: the card comes ON through its own switch, and the
-- provider is not enabled directly (the card's enable path does that).
local states = {}
local card = newCard(false)
setProviderEnabled(card, states, provider, true)
assert(card.Activated == 1, "the card's switch is used")
assert(card.Toggles == 0, "the internal toggle is not a substitute")
assert(provider.enabled == nil, "the provider waits for the card's enable path")
assert(states["Gun ESP"] == true)

-- Card ON, row ON: the provider turns on and the card is not re-activated.
card = newCard(true)
setProviderEnabled(card, states, provider, true)
assert(provider.enabled == true and card.Activated == 0)

-- Card ON, row OFF: the provider stops.
setProviderEnabled(card, states, provider, false)
assert(provider.enabled == false and states["Gun ESP"] == false)

-- Card OFF, row OFF: nothing to do beyond remembering the OFF state.
card = newCard(false)
local calls = 0
provider.setEnabled = function() calls += 1 end
setProviderEnabled(card, states, provider, false)
assert(calls == 0 and card.Activated == 0 and card.Toggles == 0)
assert(states["Gun ESP"] == false)

-- A module without the framework feature still enables (internal fallback).
card = newCard(false)
card.Feature = nil
setProviderEnabled(card, states, provider, true)
assert(card.Toggles == 1 and card.Enabled == true, "Toggle(true) fallback")

print("PASS ItemESP providers: ON with card OFF brings the card, ON with card ON enables, OFF disables, no dead ON")
'''

with tempfile.TemporaryDirectory(prefix='provider-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
