#!/usr/bin/env python3
"""v180: Freeze Movements must hold ANY animation, and Position Lock is tunable.

Roblox-only detection was the limitation: a game that ships its own dance or its
own run cycle has meaningless names and asset IDs, so the module has to fall
back to how the clip is played. These cases are pinned here, together with the
rows the renamed Position Lock mode exposes.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/universal/Movement/FreezeMovements.lua").read_text()

PRELUDE = r'''
local now = 0
local os = {clock = function() return now end}
local Vector3 = {zero = {Magnitude = 0}}
function Vector3.new(x, y, z) return {X = x or 0, Y = y or 0, Z = z or 0} end
local Enum = {
    HumanoidStateType = {Jumping = 'Jumping', Running = 'Running', Freefall = 'Freefall', Dead = 'Dead', Idle = 'Idle'},
    AnimationPriority = {Core = 'Core', Movement = 'Movement', Action = 'Action', Idle = 'Idle'},
}
local function typeof(v) return type(v) == 'table' and v.instance and 'Instance' or type(v) end
local function signal()
    local s = {listeners = {}}
    function s:Connect(fn)
        local c = {Connected = true, fn = fn}
        function c:Disconnect() self.Connected = false end
        table.insert(self.listeners, c)
        return c
    end
    function s:Fire(...)
        for _, c in ipairs(self.listeners) do if c.Connected then c.fn(...) end end
    end
    return s
end
local tracks = {}
local animator = {AnimationPlayed = signal(), GetPlayingAnimationTracks = function() return tracks end}
local loaded = {}
local function track(name, id, priority, looped)
    local t = {
        Name = name,
        Animation = {instance = true, Name = name, AnimationId = 'rbxassetid://' .. id},
        Priority = priority, IsPlaying = true, Looped = looped ~= false, plays = 0, stops = 0,
    }
    function t:Play() self.plays += 1; self.IsPlaying = true end
    function t:Stop() self.stops += 1; self.IsPlaying = false end
    function t:Destroy() self.destroyed = true end
    function t:AdjustSpeed() end
    return t
end
function animator:LoadAnimation(animation)
    local t = track(animation.Name, 0, 'Core')
    t.Animation = animation
    t.IsPlaying = false
    table.insert(loaded, t)
    return t
end
local root = {
    Parent = true, Anchored = false, Position = {X = 0, Y = 5, Z = 0},
    AssemblyLinearVelocity = {Magnitude = 0, X = 0, Y = 0, Z = 0},
    AssemblyAngularVelocity = {Magnitude = 0},
}
local character = {FindFirstChild = function() return nil end, FindFirstChildWhichIsA = function() return nil end}
local humanoid = {
    Parent = character,
    FindFirstChildOfClass = function() return animator end,
    GetState = function() return 'Idle' end,
    GetAppliedDescription = function()
        return {GetEmotes = function() return {} end, Destroy = function() end}
    end,
}
local tick, mode, toggle, feature
local checkboxes, numbers, sections = {}, {}, {}
local connections = {}
local stored = {values = {}, states = {}}
local localPlayer = {CharacterAdded = signal(), CharacterRemoving = signal()}
local host = {
    LocalPlayer = localPlayer,
    configData = stored,
    TaskManager = {Connect = function(_, fn) tick = fn; return {Disconnect = function() tick = nil end} end},
    featureConnections = connections,
    disconnectFeatureConnection = function(key)
        if connections[key] then connections[key]:Disconnect(); connections[key] = nil end
    end,
    getCharacterParts = function() return nil, humanoid, root end,
    createUniversalFeature = function(_, _, _, fn)
        toggle = fn
        feature = {enabled = false, SetStatus = function(self, s) self.status = s end}
        return feature
    end,
    addCycleOption = function(_, _, values, _, fn)
        assert(#values == 2 and values[1] == 'Position Lock' and values[2] == 'Motion')
        mode = fn
        fn(values[1])
    end,
    addToggleOption = function(_, name, default, fn)
        checkboxes[name] = fn
        fn(default)
        return {Parent = {Visible = true}}
    end,
    addNumberOption = function(_, name, default, _, _, fn)
        numbers[name] = fn
        fn(default)
        return {Parent = {Visible = true}}
    end,
    addSectionOption = function(_, name) sections[name] = {Visible = true}; return sections[name] end,
    addInformationOption = function() end,
}
'''

TESTS = r'''
Module.init({host = host})
assert(checkboxes['Lock rotation'] and checkboxes['Keep gravity'] and numbers['Return if pushed'],
    'Position Lock must expose its tuning rows')
assert(checkboxes['Any emote'] and checkboxes['Any animation'], 'Motion must expose the generalization rows')
assert(sections['Position Lock settings'] and sections['Motion settings'])
feature.enabled = true; toggle(true)
mode('Position Lock'); tick()
assert(root.Anchored == true, 'hard lock anchors the body')

-- Keep gravity: no anchor, pushes erased, falling preserved.
checkboxes['Keep gravity'](true); tick()
assert(root.Anchored == false, 'keep gravity must not anchor')
root.AssemblyLinearVelocity = {Magnitude = 30, X = 20, Y = -40, Z = 3}
tick()
assert(root.AssemblyLinearVelocity.X == 0 and root.AssemblyLinearVelocity.Z == 0
    and root.AssemblyLinearVelocity.Y == -40, 'horizontal pushes are erased, the fall is kept')

-- Return if pushed: a drift beyond the limit snaps back, a smaller one does not.
numbers['Return if pushed'](3)
root.Position = {X = 2, Y = 5, Z = 0}; tick()
assert(root.Position.X == 2, 'drift inside the limit is allowed')
root.Position = {X = 9, Y = 6, Z = 4}; tick()
assert(root.Position.X == 0 and root.Position.Z == 0 and root.Position.Y == 6,
    'drift beyond the limit is undone, the height is kept')
checkboxes['Keep gravity'](false); numbers['Return if pushed'](0); tick()
assert(root.Anchored == true)

-- Motion: a game emote identified only by its name keyword.
mode('Motion'); tick()
now += 1
local named = track('DancePartyEmote', 5150, 'Action')
root.AssemblyLinearVelocity = {Magnitude = 16}
animator.AnimationPlayed:Fire(named); named.IsPlaying = false; tick()
assert(#loaded == 1 and loaded[1].IsPlaying, 'a name with an emote keyword is enough')

-- A custom emote with no usable name: it is started while standing (so it must
-- be recognised then, not later) and only gets cancelled once the player walks.
local unnamed = track('Animation', 6161, 'Action')
root.AssemblyLinearVelocity = {Magnitude = 0}
humanoid.GetState = function() return 'Idle' end
animator.AnimationPlayed:Fire(unnamed)
tracks = {unnamed}
tick()
assert(#loaded == 1, 'a standing clip must not be reloaded while it still plays')
root.AssemblyLinearVelocity = {Magnitude = 16}
unnamed.IsPlaying = false
tick()
assert(#loaded == 2 and loaded[2].IsPlaying,
    'a looped Action clip started while standing survives the walk that cancelled it')

-- A weapon swing is never an emote, even standing still and looped.
local swing = track('SwordSlash', 7171, 'Action')
animator.AnimationPlayed:Fire(swing); swing.IsPlaying = false; tick()
assert(#loaded == 2, 'attacks must not be captured as emotes')

-- A custom locomotion clip (Action priority, no usable name) is frozen too.
-- Emotes take precedence over the locked clip, so release them for this check.
checkboxes['Freeze Emotes'](false)
checkboxes['Freeze Animation'](true)
local customRun = track('Locomotion', 8181, 'Action')
tracks = {customRun}; tick()
local heldCustom = loaded[#loaded]
assert(#loaded == 3 and heldCustom.Animation == customRun.Animation and heldCustom.IsPlaying,
    'Any animation must freeze the game animation, not only the Roblox walk set')
checkboxes['Any animation'](false)
assert(not heldCustom.IsPlaying, 'turning Any animation off releases it')

-- With the generalization off, an unnamed Action clip is no longer an emote.
checkboxes['Any emote'](false); checkboxes['Freeze Emotes'](true)
local another = track('Animation', 9191, 'Action')
tracks = {}
animator.AnimationPlayed:Fire(another); another.IsPlaying = false; tick()
assert(#loaded == 3, 'Any emote off keeps the strict detection')

feature.enabled = false; toggle(false)
assert(not tick and not root.Anchored)
print('PASS v180 Freeze Movements: keyword + standing custom emotes, attack exclusion, any animation, Position Lock rows')
'''

with tempfile.TemporaryDirectory(prefix="freeze-general-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(PRELUDE + "\nlocal Module=(function()\n" + SOURCE + "\nend)()\n" + TESTS)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
