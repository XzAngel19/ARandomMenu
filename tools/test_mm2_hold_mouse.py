#!/usr/bin/env python3
"""Execute the real v191 "Hold Mouse" path of MM2 Knife Stab.

What this proves:

  * with Hold Mouse OFF, the Knife Stab tick still swings on its own;
  * with Hold Mouse ON the tick never swings (the automatic kill aura is off),
    and a mouse click / touch on the real input service swings instead, at the
    SAME reach the aura uses ("Aura Range");
  * a click outside that reach does nothing;
  * the tool's own cooldown still paces the manual swings, so holding the button
    does not spam the remote;
  * the listener is dropped when the option is turned off and when the module is
    destroyed.

It does NOT prove that a Roblox server accepts the stab: the knife remote is a
mock and the physics are not simulated.
"""

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Blatant/KnifeAura.lua").read_text(encoding="utf-8")
MANIFEST = (ROOT / "src/libraries/Manifest.lua").read_text(encoding="utf-8")

assert '"src/games/MM2/Blatant/KnifeAura.lua"' in MANIFEST, "Knife Stab must stay in the MM2 load list"
assert 'Name = "Hold Mouse"' in SOURCE, "the option exists"

script = r'''
-- ---------------------------------------------------------------- primitives
local Vector3 = {}
Vector3.__index = Vector3
local function vec(x, y, z)
    return setmetatable({ X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) }, Vector3)
end
Vector3.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3.__mul = function(a, s) return vec(a.X * s, a.Y * s, a.Z * s) end
Vector3.new = vec

local now = 0
local jobs = {}
os = { clock = function() return now end }
task = {
    spawn = function(fn) coroutine.wrap(fn)() end,
    wait = function(seconds) now += seconds or 0 end,
    delay = function(seconds, fn) table.insert(jobs, { due = now + (seconds or 0), fn = fn }) end,
}
local function advance(seconds)
    now += seconds
    local ran = true
    while ran do
        ran = false
        for index = #jobs, 1, -1 do
            local job = jobs[index]
            if job.due <= now then
                table.remove(jobs, index)
                job.fn()
                ran = true
            end
        end
    end
end

Enum = {
    UserInputType = { MouseButton1 = "MouseButton1", Touch = "Touch" },
    KeyCode = {},
}

-- --------------------------------------------------------------- input layer
local inputConnections = {}
local UserInputService = {
    GetFocusedTextBox = function() return nil end,
    InputBegan = {
        Connect = function(_, fn)
            local connection = { fn = fn, connected = true }
            function connection:Disconnect() self.connected = false end
            table.insert(inputConnections, connection)
            return connection
        end,
    },
}
local function click(userInputType)
    for _, connection in ipairs(inputConnections) do
        if connection.connected then
            connection.fn({ UserInputType = userInputType }, false)
        end
    end
end

-- ------------------------------------------------------------------- players
local Players = { GetPlayers = function() return roster end }
local function newPlayer(name, options)
    options = options or {}
    local root = { Parent = true, Name = "HumanoidRootPart", Position = vec(options.x or 0, 0, options.z or 0) }
    local humanoid = { Health = options.alive == false and 0 or 100, RootPart = root }
    local character = { Parent = true }
    function character:FindFirstChild(name2)
        if name2 == "HumanoidRootPart" then return root end
        return nil
    end
    function character:FindFirstChildOfClass(class)
        if class == "Humanoid" then return humanoid end
        return nil
    end
    return { Name = name, Parent = Players, Character = character, humanoid = humanoid, root = root }
end

local LocalPlayer = newPlayer("Me")
local victim = newPlayer("Victim", { x = 10 })
local farVictim = newPlayer("Far", { x = 25 })
local roster = { LocalPlayer, victim, farVictim }
Players.GetPlayers = function() return roster end

-- --------------------------------------------------------------------- knife
local stabs = {}
local function newKnife()
    local events = {}
    local handleTouched = {
        FireServer = function(_, target) table.insert(stabs, { kind = "remote", target = target, at = now }) end,
    }
    function handleTouched:IsA(class) return class == "RemoteEvent" end
    function events:FindFirstChild(name)
        if name == "HandleTouched" then return handleTouched end
        return nil
    end
    local knife = {
        Name = "Knife",
        Enabled = true,
        Parent = LocalPlayer.Character,
        tool = true,
    }
    function knife:FindFirstChild(name)
        if name == "Handle" then
            return { IsA = function(_, class) return class == "BasePart" end, Parent = knife }
        end
        if name == "Events" then return events end
        return nil
    end
    function knife:GetAttribute(name) return nil end
    function knife:Activate()
        table.insert(stabs, { kind = "activate", at = now })
    end
    return knife
end
local knife = newKnife()

-- ----------------------------------------------------------------------- UI
local toggles = {}
local sliders = {}
local lists = {}
local buttons = {}
local auraEnabled = false
local aura = nil
local function makeFeature()
    local feature = {
        description = "KillAura description",
        tooltipText = "KillAura description",
        enabled = false,
    }
    function feature:SetName(name) self.name = name end
    function feature:SetStatus(status) self.status = status end
    function feature:activate() self.enabled = true end
    return feature
end
local auraFeature = makeFeature()
aura = {
    Enabled = false,
    Feature = auraFeature,
    EnabledAtStart = false,
    CreateToggle = function(_, definition)
        toggles[definition.Name] = definition
        return { Name = definition.Name }
    end,
    CreateSlider = function(_, definition)
        sliders[definition.Name] = definition
        return { Name = definition.Name }
    end,
    CreateList = function(_, definition)
        lists[definition.Name] = {
            Selected = {},
            Set = function(self) end,
            Refresh = function(self) end,
        }
        return lists[definition.Name]
    end,
    SetStatus = function() end,
    CreateButton = function(_, definition)
        buttons[definition.Name] = definition
        return { Name = definition.Name }
    end,
}
function aura:Toggle(value)
    self.Enabled = value
    if self.CombatAdapter then self.CombatAdapter(value) end
end
function aura:RefreshVisibility() end

local featureConnections = {}
local disconnected = {}
local function disconnectFeatureConnection(key)
    featureConnections[key] = nil
    disconnected[key] = true
end
local TaskManager = {
    Connect = function(_, fn)
        local connection = { fn = fn }
        function connection:Disconnect() self.gone = true end
        return connection
    end,
}
local function tick(delta)
    local connection = featureConnections.MM2KnifeController
    if connection and connection.fn then connection.fn(delta) end
end

local notices = {}
local function notify(message) table.insert(notices, message) end
local function refreshFeatureToggle() end
local function queueConfigSave() end

configData = { values = {}, states = {} }
state = {
    framework = { GetModule = function(_, name) if name == "KillAura" then return aura end end },
    mm2Core = {
        getPlayerRole = function(player)
            if player == LocalPlayer then return "Murderer" end
            if player == victim or player == farVictim then return "Innocent" end
            return nil
        end,
        getPlayerWeapon = function(player, name)
            if player == LocalPlayer and name == "Knife" then return knife end
            return nil
        end,
        isPlayerAlive = function(player)
            return player.humanoid ~= nil and player.humanoid.Health > 0
        end,
        isProtectedTarget = function() return false end,
        trajectoryCalibration = { noteAuthoredShot = function() end },
    },
    shortcutBindings = {},
    fireTouchInterest = nil,
}

local Module = (function()
''' + SOURCE + r'''
end)()

local function eq(actual, expected, message)
    if actual ~= expected then
        error(message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected), 0)
    end
end

Module.init({})
assert(aura.Feature.name == "Knife Stab", "the card keeps the MM2 name")
assert(toggles["Knife Aura"], "the automatic aura toggle still exists")
assert(toggles["Hold Mouse"], "v191 adds the Hold Mouse toggle")
eq(toggles["Hold Mouse"].Default, false, "Hold Mouse starts OFF")

-- Turn Knife Stab on: the automatic loop must be armed first. The real UI
-- applies each option default through its callback, so the mock does the same.
aura:Toggle(true)
toggles["Knife Aura"].Function(true)
assert(state.mm2KnifeRuntime.auraWanted == true, "the aura option arms the controller")

-- OFF (default): the aura swings by itself.
local function stabCount() return #stabs end
local before = stabCount()
tick(0.1)          -- arm the interval
advance(1)
eq(stabCount() > before, true, "Hold Mouse OFF: the aura swings on its own")

-- ON: the same tick must do nothing at all.
toggles["Hold Mouse"].Function(true)
before = stabCount()
for _ = 1, 40 do
    tick(0.1)
    advance(0.1)
end
eq(stabCount(), before, "Hold Mouse ON: the automatic aura never swings")
assert(inputConnections[#inputConnections].connected, "Hold Mouse installs a click listener")

-- A click inside the aura reach swings once, at the same reach.
click("MouseButton1")
advance(1)
eq(stabCount(), before + 2, "one click = Activate + the knife remote")

-- Holding the button does not spam the remote: the knife cooldown paces it.
advance(1)
click("MouseButton1")
advance(0.05)
local afterOneClick = stabCount()
click("MouseButton1")   -- 0.05 s later: the knife is still cooling down
advance(1)
eq(stabCount(), afterOneClick, "clicks inside the cooldown are dropped")

-- A click with the target out of range does nothing.
advance(1)
roster = { LocalPlayer, farVictim }
before = stabCount()
click("MouseButton1")
advance(1)
eq(stabCount(), before, "a click outside Aura Range never stabs")
roster = { LocalPlayer, victim, farVictim }

-- Touch works too (mobile).
advance(1)
before = stabCount()
click("Touch")
advance(1)
eq(stabCount(), before + 2, "a touch swings like a click")

-- Turning the option off drops the listener and restores the automatic aura.
toggles["Hold Mouse"].Function(false)
assert(not inputConnections[#inputConnections].connected, "the listener is disconnected")
advance(1)
before = stabCount()
for _ = 1, 20 do
    tick(0.1)
    advance(0.1)
end
assert(stabCount() > before, "Hold Mouse OFF: the automatic aura is back")

-- Aura Range still governs the manual reach.
toggles["Hold Mouse"].Function(true)
sliders["Aura Range"].Function(8)
advance(1)
before = stabCount()
roster = { LocalPlayer, victim }  -- 10 studs: outside an 8-stud reach
click("MouseButton1")
advance(1)
eq(stabCount(), before, "the manual reach follows Aura Range")
roster = { LocalPlayer, victim, farVictim }
sliders["Aura Range"].Function(14)

-- Destroy drops the listener for good.
toggles["Hold Mouse"].Function(true)
Module.destroy()
assert(not inputConnections[#inputConnections].connected, "destroy drops the click listener")
print("PASS Knife Stab Hold Mouse: automatic aura off, click/touch at Aura Range, cooldown, cleanup")
'''

with tempfile.TemporaryDirectory(prefix="hold-mouse-") as temp:
    path = Path(temp) / "hold_mouse.luau"
    path.write_text(script, encoding="utf-8")
    result = subprocess.run(
        [os.environ.get("LUAU", "luau"), str(path)], capture_output=True, text=True
    )
    if result.returncode:
        raise SystemExit(f"Hold Mouse failed:\n{result.stdout[-6000:]}\n{result.stderr}")
    print(next(line for line in result.stdout.splitlines() if line.startswith("PASS Knife Stab")))
