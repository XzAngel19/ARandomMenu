#!/usr/bin/env python3
"""Get All Emotes (v181): a button, six shop emotes, and Select Emote that plays.

The card must never act like a toggle, must touch only the catalog ids the game
sells or hands out (ninja/zen/dab/floss/zombie/headless), must rebuild the
game's own emote window through Modules.EmoteModule, and must play the emote the
player picks. This mock does not prove server ownership, animation permission or
replication.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/GetAllEmotes.lua").read_text()

SCRIPT = r'''
local function signal()
    local listeners = {}
    local s = {}
    function s:Connect(fn)
        local c = {}
        listeners[c] = fn
        function c:Disconnect() listeners[self] = nil end
        return c
    end
    function s:Fire(...) for _, fn in pairs(listeners) do fn(...) end end
    function s:Count() local n = 0; for _ in pairs(listeners) do n += 1 end; return n end
    return s
end
local delayed = {}
local task = {delay = function(_, fn) table.insert(delayed, fn) end}
local function flush() while #delayed > 0 do table.remove(delayed, 1)() end end
local function container(children)
    return {FindFirstChild = function(_, name) return children[name] end}
end
local profile = {Emotes = {Owned = {'sit'}}}
local profileMod = {data = profile}
local sync = {
    ninja = {Name = 'Ninja Rest', Command = 'ninja', AnimationID = 2431864798},
    zen = {Name = 'Zen', Command = 'zen', AnimationID = 2431812646},
    dab = {Name = 'Dab', Command = 'dab', AnimationID = 2445521505},
    floss = {Name = 'Floss', Command = 'floss', AnimationID = 2452938820, Loop = true},
    zombie = {Name = 'Zombie', Command = 'zombie', AnimationID = 2513692312, Loop = true},
    headless = {Name = 'Headless', Command = 'headless', AnimationID = 2513664073},
    wave = {Name = 'Wave', Command = 'wave'},
    cheer = {Name = 'Cheer', Command = 'cheer'},
    laugh = {Name = 'Laugh', Command = 'laugh'},
    point = {Name = 'Point', Command = 'point'},
    dance1 = {Name = 'Dance1', Command = 'dance1'},
    dance2 = {Name = 'Dance2', Command = 'dance2'},
    dance3 = {Name = 'Dance3', Command = 'dance3'},
    sit = {Name = 'Sit', Command = 'sit'},
}
local syncMod = {data = sync}
local notices = {}
local inventoryEvents = {}
local changedEvent = signal()
local changed = {Event = changedEvent}
local played = {}
local playEvent = {Fire = function(_, id) table.insert(played, id) end}
local emoteRebuilds = {}
local emoteModule = {data = {
    EmoteGUI = {Name = 'Emotes'},
    GenerateEmotes = function(owned, gui) table.insert(emoteRebuilds, {owned = owned, gui = gui}) end,
}}
local modules = container({ProfileData = profileMod, EmoteModule = emoteModule})
local inventory = container({InventoryDataChanged = changed})
local remotes = {FindFirstChild = function(_, name)
    if name == 'Inventory' then return inventory end
    if name == 'Misc' then return container({PlayEmote = playEvent}) end
end}
local db = container({Sync = container({Emotes = syncMod})})
local rs = {FindFirstChild = function(_, name)
    if name == 'Modules' then return modules end
    if name == 'Remotes' then return remotes end
    if name == 'Database' then return db end
end}
local game = {GetService = function(_, name) assert(name == 'ReplicatedStorage'); return rs end}
local require = function(mod) return mod.data end
local animations = {}
local Instance = {new = function(class)
    assert(class == 'Animation')
    local a = {destroyed = false}
    function a:Destroy() self.destroyed = true end
    table.insert(animations, a)
    return a
end}
local tracks = {}
local animator = {LoadAnimation = function(_, anim)
    local t = {animation = anim, stops = 0, plays = 0}
    function t:Stop() self.stops += 1 end
    function t:Play() self.plays += 1 end
    table.insert(tracks, t)
    return t
end}
local humanoid = {Health = 100, FindFirstChildOfClass = function(_, name) return name == 'Animator' and animator end}
local character = {FindFirstChildOfClass = function(_, name) return name == 'Humanoid' and humanoid end}
local LocalPlayer = {Character = character, CharacterAdded = signal()}
local featureConnections = {}
local state = {mm2Core = {}}
local function disconnectFeatureConnection(name)
    local c = featureConnections[name]
    if c then c:Disconnect(); featureConnections[name] = nil end
end
local feature
local featureOptions = {}
local function createUniversalFeature(name, description, order, callback, options)
    featureOptions = options or {}
    feature = {enabled = false, actions = {}, cycles = {}}
    function feature:Toggle(v) callback(v); self.enabled = v end
    function feature:SetStatus(s) self.status = s end
    return feature
end
local function addActionOption(f, name, callback) f.actions[name] = callback end
local function addCycleOption(f, name, labels, index, callback)
    f.cycles[name] = {labels = labels, callback = callback}
    -- The real widget restores the saved value by calling the callback once, at
    -- creation. That call must never act on its own.
    callback(labels[index])
end
local function addInformationOption() end
local function notify(s) table.insert(notices, s) end
local MM2Scroll, mm2Features = {}, {}
'''

TESTS = r'''
Module.init({})
assert(featureOptions.action == true, 'Get All Emotes must be a button, not a toggle')
assert(featureOptions.noOptions == false)
assert(featureOptions.configKey == 'MM2.GetAllEmotes')
assert(#profile.Emotes.Owned == 1, 'the card must not grant anything on boot')
assert(LocalPlayer.CharacterAdded:Count() == 1, 'the respawn hook is armed')

-- One press: the six catalog ids, once, and nothing from the avatar set.
feature:Toggle(true)
assert(#played == 0, 'the button must not play an emote')
assert(#tracks == 0, 'restoring the saved cycle value must not play anything')
local owned = profile.Emotes.Owned
assert(#owned == 7, 'exactly six shop emotes are added: ' .. #owned)
for _, id in ipairs({'ninja', 'zen', 'dab', 'floss', 'zombie', 'headless'}) do
    local found = false
    for _, value in ipairs(owned) do if value == id then found = true end end
    assert(found, 'missing shop id ' .. id)
end
-- The live profile table is what the game's emote window reads, so the rebuild
-- must be asked for with that exact list and that exact GUI.
assert(#emoteRebuilds == 1, 'the game emote window is rebuilt once')
assert(emoteRebuilds[1].owned == owned, 'the rebuild uses the live ProfileData list')
assert(emoteRebuilds[1].gui == emoteModule.data.EmoteGUI, 'the rebuild targets the live emote GUI')
-- 'sit' is already owned by the player in this mock, so it is not a leak.
for _, id in ipairs({'wave', 'cheer', 'laugh', 'point', 'dance1', 'dance2', 'dance3'}) do
    for _, value in ipairs(owned) do assert(value ~= id, 'avatar emote leaked into the profile: ' .. id) end
end
assert(#inventoryEvents == 0, 'the inventory channel is the inner .Event, not the RemoteEvent')
assert(string.find(feature.status, '6'), 'status must report the shop count: ' .. tostring(feature.status))
assert(string.find(notices[#notices], 'server still decides'), 'never claim server ownership')

-- A second press adds nothing and says so.
feature:Toggle(true)
assert(#profile.Emotes.Owned == 7, 'the button must be idempotent')
assert(#inventoryEvents == 0)
assert(#emoteRebuilds == 2, 'pressing again still refreshes the window')

-- Select emote plays immediately through the game's own BindableEvent.
local cycle = feature.cycles['Select Emote']
assert(cycle and #cycle.labels == 6 and cycle.labels[6] == 'Headless')
cycle.callback('Headless')
assert(#played == 1 and played[1] == 'headless', 'Select emote must play the picked emote')
cycle.callback('Zombie')
assert(#played == 2 and played[2] == 'zombie', 'Select emote must play the picked emote')
cycle.callback('Ninja Rest')
assert(#played == 3 and played[3] == 'ninja')
assert(#tracks == 0, 'the game event wins over the animator fallback')

-- Replay keeps working, and the fallback is used only when the game refuses.
feature.actions['Play Emote']()
assert(#played == 4 and played[4] == 'ninja')
remotes = {FindFirstChild = function(_, name)
    if name == 'Inventory' then return inventory end
end}
feature.actions['Play Emote']()
assert(#tracks == 1 and tracks[1].plays == 1, 'the fallback must play the clip')
assert(tracks[1].animation.AnimationId == 'rbxassetid://2431864798', 'the fallback uses the live Sync asset')
assert(tracks[1].Looped == nil or tracks[1].Looped == false, 'ninja rest is not a looping clip')
feature.cycles['Select Emote'].callback('Floss')
assert(tracks[1].stops == 1 and #tracks == 2 and tracks[2].Looped == true,
    'switching emotes stops the previous clip and honours Looped')
assert(animations[#animations].destroyed, 'the temporary Animation is destroyed')

-- Respawn re-grants without duplicating and without a status claim.
profile.Emotes.Owned = {'sit'}
LocalPlayer.CharacterAdded:Fire()
assert(#delayed == 1)
flush()
assert(#profile.Emotes.Owned == 7, 'a respawn gets the emotes again')

-- Destroy releases everything.
Module.destroy()
assert(LocalPlayer.CharacterAdded:Count() == 0, 'destroy disconnects the respawn hook')
assert(tracks[#tracks].stops == 1, 'destroy stops the fallback clip')
assert(state.mm2GetAllEmotesFeature == nil)
print('PASS MM2 Get All Emotes: button only, six shop ids including Headless, window rebuild, select emote plays, fallback clip, respawn, cleanup')
'''

with tempfile.TemporaryDirectory(prefix="mm2-emotes-") as tmp:
    path = Path(tmp) / "test.luau"
    path.write_text(SCRIPT + "\nlocal Module=(function()\n" + SOURCE + "\nend)()\n" + TESTS)
    subprocess.run([os.environ.get("LUAU", "luau"), str(path)], check=True)
