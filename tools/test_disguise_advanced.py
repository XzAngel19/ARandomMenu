#!/usr/bin/env python3
"""Execute Disguise's advanced bundle inputs against a complete catalog bundle."""
import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Other/Disguise.lua").read_text()
ui = section(
    SOURCE,
    '    card:CreateToggle({\n        Name = "Show Advanced",',
    '    card:CreateToggle({\n        Name = "Use target movement animations",',
)

script = PRELUDE + r'''
local settings = {
    mode = "Character",
    showAdvanced = false,
    customPackSlots = nil,
    customPackName = nil,
    customSlotIds = {},
}
local definitions = {}
local applied = {}
local notifications = {}
local statuses = {}
local humanoid = {RigType = "R15"}
local character = {FindFirstChildOfClass = function(_, className)
    if className == "Humanoid" then return humanoid end
    return nil
end}
local LocalPlayer = {Character = character}
local card = {Enabled = true}
function card:CreateToggle(definition) definitions[definition.Name] = definition end
function card:CreateTextBox(definition) definitions[definition.Name] = definition end
local function notify(message) table.insert(notifications, tostring(message)) end
local function status(message) table.insert(statuses, tostring(message)) end
local function applyAnimationPack(currentCharacter, currentHumanoid)
    assert(currentCharacter == character and currentHumanoid == humanoid)
    table.insert(applied, settings.customPackSlots)
    return 1
end

local function bundleAnimationSlots(bundleId)
    if bundleId == 43 then
        return {
            idle = "rbxassetid://101",
            walk = "rbxassetid://102",
            run = "rbxassetid://103",
            jump = "rbxassetid://104",
        }, nil
    end
    if bundleId == 44 then
        return {walk = "rbxassetid://201", run = "rbxassetid://202"}, nil
    end
    if bundleId == 45 then
        return {idle = "rbxassetid://301"}, nil
    end
    return nil, "unknown bundle"
end
''' + ui + r'''
local show = definitions["Show Advanced"]
assert(show and definitions["Pack Bundle ID"] and definitions["Walk Bundle ID"])
show.Function(true); show.Function(false); show.Function(true)
assert(#applied == 0, "merely opening Advanced must not change animations")

-- A complete bundle in Walk contributes the item named Walk, not the first
-- item in the bundle (Idle in this mock).
definitions["Walk Bundle ID"].Function("https://www.roblox.com/bundles/43/Complete-Pack")
assert(settings.customPackSlots.walk == "rbxassetid://102")
assert(settings.customPackSlots.idle == nil,
    "per-slot entry must not silently apply the whole bundle")
assert(settings.customPackSlots.run == nil)
assert(#applied == 1 and applied[1] == settings.customPackSlots)
pass("Advanced: complete bundle in Walk resolves and applies its Walk clip")

-- Different bundles can still supply different slots.
definitions["Run Bundle ID"].Function("44")
assert(settings.customPackSlots.walk == "rbxassetid://102")
assert(settings.customPackSlots.run == "rbxassetid://202")
assert(#applied == 2)
pass("Advanced: per-slot bundles remain independent and composable")

-- A complete-pack submission supersedes the old per-slot overrides instead of
-- resurrecting them on the next edit.
definitions["Pack Bundle ID"].Function("43")
assert(next(settings.customSlotIds) == nil, "old slot overrides must be cleared")
assert(settings.customPackSlots.idle == "rbxassetid://101")
assert(settings.customPackSlots.walk == "rbxassetid://102")
assert(settings.customPackSlots.run == "rbxassetid://103")
assert(#applied == 3)
pass("Advanced: complete bundle replaces stale per-slot overrides")

local before = settings.customPackSlots
definitions["Walk Bundle ID"].Function("45")
assert(settings.customPackSlots == before and #applied == 3,
    "a bundle without Walk must not erase the working selection")
assert(#notifications == 1 and notifications[1]:find("no Walk clip", 1, true))
show.Function(false); show.Function(true)
assert(#applied == 3, "show/hide remains visibility-only after a pack is loaded")

card.Enabled = false
definitions["Pack Bundle ID"].Function("44")
assert(#applied == 3, "loading while disabled stores the pack without applying it")
assert(settings.customPackSlots.walk == "rbxassetid://201")
assert(settings.customPackSlots.run == "rbxassetid://202")
card.Enabled = true
pass("Advanced: missing slots fail closed; hidden/disabled inputs stay coherent")

print("PASS Disguise advanced: named slot resolution, complete packs, no toggle side effects")
'''

assert 'Name = "Animation Pack"' not in SOURCE
assert "advancedPackArmed" not in SOURCE
assert "table.clear(settings.customSlotIds)" in ui
assert "restoreMovementAnimationsOnly" not in ui
assert "applyAnimationSlots" not in ui.split('Name = "Show Advanced"', 1)[1].split(
    'Name = "Pack Bundle ID"', 1
)[0]

with tempfile.TemporaryDirectory(prefix="disguise-advanced-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
