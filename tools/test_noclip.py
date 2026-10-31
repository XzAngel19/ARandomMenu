#!/usr/bin/env python3
"""Exercise the real Noclip lifecycle, including injection and respawn.

The objects/signals below model Roblox contracts; they do not prove the
server or executor will accept collision changes in a real game.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Blatant/Noclip.lua").read_text()

script = r'''
local now = 0
local os = {clock = function() return now end}
local function signal()
    local callbacks = {}
    local event = {}
    function event:Connect(callback)
        local connection = {}
        callbacks[connection] = callback
        function connection:Disconnect() callbacks[self] = nil end
        return connection
    end
    function event:Fire(value)
        for _, callback in pairs(callbacks) do callback(value) end
    end
    function event:Count()
        local count = 0
        for _ in pairs(callbacks) do count += 1 end
        return count
    end
    return event
end
local function part(name, collides)
    return {Name = name, CanCollide = collides, Parent = true,
        IsA = function(_, class) return class == "BasePart" end}
end
local function character(parts)
    local model = {children = parts, DescendantAdded = signal()}
    function model:GetDescendants() return self.children end
    function model:Add(child)
        table.insert(self.children, child)
        child.Parent = self
        self.DescendantAdded:Fire(child)
    end
    for _, child in ipairs(parts) do child.Parent = model end
    return model
end
local p1, p2 = part("Root", true), part("Accessory", false)
local first = character({p1, p2})
local player = {Character = first}
local tick, feature
local host = {LocalPlayer = player, featureConnections = {}}
function host.TaskManager_Connect(_, fn)
    tick = fn
    return {Disconnect = function() tick = nil end}
end
host.TaskManager = {Connect = host.TaskManager_Connect}
function host.disconnectFeatureConnection(key)
    local connection = host.featureConnections[key]
    if connection then connection:Disconnect(); host.featureConnections[key] = nil end
end
function host.createUniversalFeature(name, _, _, callback, options)
    feature = {name = name, toggle = callback, options = options}
    return feature
end
function host.addFeatureTooltip() end
'''+"\nlocal Module = (function()\n"+SOURCE+"\nend)()\n"+r'''
Module.init({host = host})
assert(feature.name == "Noclip" and feature.options.noOptions)
assert(p1.CanCollide and not p2.CanCollide and not tick and first.DescendantAdded:Count() == 0,
    "injection with Noclip OFF must not alter collision or connect a watcher")

feature.toggle(true)
assert(tick, "ON connects the frame task")
tick()
assert(not p1.CanCollide and not p2.CanCollide and first.DescendantAdded:Count() == 1)
local p3 = part("Added", true)
first:Add(p3)
assert(not p3.CanCollide, "new parts are immediately handled")
p1.CanCollide = true
now = 0.19; tick(); assert(p1.CanCollide, "the safety sweep stays throttled")
now = 0.21; tick(); assert(not p1.CanCollide, "the safety sweep repairs re-enabled collision")

local p4 = part("RespawnRoot", true)
local second = character({p4})
player.Character = second
now = 0.22; tick()
assert(not p4.CanCollide and first.DescendantAdded:Count() == 0 and second.DescendantAdded:Count() == 1,
    "respawn moves the watcher to the new character")
local oldAdded = part("OldAdded", true)
first:Add(oldAdded)
assert(oldAdded.CanCollide, "the old character no longer has a watcher")
feature.toggle(false)
assert(not tick and second.DescendantAdded:Count() == 0)
assert(p1.CanCollide and not p2.CanCollide and p3.CanCollide and p4.CanCollide,
    "OFF restores every original collision value")
local afterOff = part("AfterOff", true)
second:Add(afterOff)
assert(afterOff.CanCollide, "OFF does not change new parts")

feature.toggle(true); tick(); assert(not p4.CanCollide and not afterOff.CanCollide)
Module.destroy()
assert(not tick and p4.CanCollide and afterOff.CanCollide and second.DescendantAdded:Count() == 0,
    "destroy while ON restores collisions and disconnects")
print("PASS Noclip: inert injection, new parts, throttled sweep, respawn, original collisions, OFF and unload")
'''

with tempfile.TemporaryDirectory(prefix="noclip-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(script)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
