#!/usr/bin/env python3
"""Character toggles: independent, cache-only, never refetch the avatar."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Other/Disguise.lua').read_text()

saved = section(
    SOURCE,
    '    local function savedToggle(',
    '    local settings = {',
)
handlers = section(
    SOURCE,
    '    local function activeCharacter(): (any, any)',
    '    local function restoreAndRelease(): ()',
)

script = PRELUDE + 'local host={configData={states={}}}\n' + saved + r'''
local settings={mode="Character"}
local activeCard={Enabled=true,status=nil}
local function status(message) activeCard.status=message end
local notifications={}
local function notify(message) table.insert(notifications,message) end
local humanoid={}
local character={FindFirstChildOfClass=function(_,class)
    if class~="Humanoid" then return nil end
    return humanoid
end}
local LocalPlayer={Character=character}
local targetCache=nil
local calls={}
local function applyDisguise() table.insert(calls,"refetch") end
local function applyCachedMovementAnimations(ch,h)
    table.insert(calls,"anim+")
    assert(ch==character and h==humanoid)
    return 1
end
local function restoreMovementAnimationsOnly(ch,h)
    table.insert(calls,"anim-")
    assert(ch==character and h==humanoid)
end
local function applyCachedEmotes(ch,h)
    table.insert(calls,"emote+")
    assert(ch==character and h==humanoid)
    return true
end
local function restoreEmotesOnly(ch,h)
    table.insert(calls,"emote-")
    assert(ch==character and h==humanoid)
end
''' + handlers + r'''
local function reset() table.clear(calls); notifications={} end
local function cached(emotes,equipped)
    targetCache={userId=7,slots={idle="rbxassetid://1"},
        emotes=emotes,equippedEmotes=equipped}
end
local emotes={hello=true}

cached(emotes,{1})
setMovementAnimationsEnabled(true)
assert(table.concat(calls,",")=="anim+",table.concat(calls,","))
assert(settings.useTargetMovementAnimations==true and activeCard.status=="Character")
assert(#notifications==0,"cached animations apply without a refetch")
pass("movement ON: cached apply, no avatar refetch")

reset()
setMovementAnimationsEnabled(false)
assert(table.concat(calls,",")=="anim-")
assert(settings.useTargetMovementAnimations==false)
pass("movement OFF: restores only the Animate slots")

reset()
setTargetEmotesEnabled(false)
assert(table.concat(calls,",")=="emote-","emotes must not touch animations")
assert(settings.showTargetEmotes==false)
pass("emotes OFF: restores only the Humanoid emotes")

reset()
setTargetEmotesEnabled(true)
assert(table.concat(calls,",")=="emote+")
assert(settings.showTargetEmotes==true and #notifications==0)
pass("emotes ON: cached apply, no avatar refetch")

reset();cached(nil,nil)
setTargetEmotesEnabled(true)
assert(table.concat(calls,",")=="" and #notifications==1
    and notifications[1]:find("did not expose"),"nothing to show is reported")
pass("emotes ON without emote data: reported, no refetch")

reset();targetCache=nil
setMovementAnimationsEnabled(true)
assert(table.concat(calls,",")=="refetch")
reset();targetCache=nil
setTargetEmotesEnabled(true)
assert(table.concat(calls,",")=="refetch")
pass("no cache: a real application is requested instead of guessing")

reset();cached(emotes,{1})
settings.mode="Animation"
setMovementAnimationsEnabled(false)
setTargetEmotesEnabled(false)
assert(table.concat(calls,",")=="" and #notifications==0,
    "Animation mode has no toggles to run")
assert(settings.useTargetMovementAnimations==false and settings.showTargetEmotes==false)
settings.mode="Character"
pass("Animation mode: handlers are inert but keep the preference")

reset();activeCard.Enabled=false
setMovementAnimationsEnabled(true)
assert(table.concat(calls,",")=="","a disabled card does nothing")
activeCard.Enabled=true

reset();LocalPlayer.Character=nil
setMovementAnimationsEnabled(true)
setTargetEmotesEnabled(true)
assert(table.concat(calls,",")=="" and #notifications==0,
    "no character means no work and no false notice")
LocalPlayer.Character=character
pass("disabled card and missing character fail closed")

reset();cached(emotes,{1})
setMovementAnimationsEnabled(true)
setTargetEmotesEnabled(false)
assert(table.concat(calls,",")=="anim+,emote-")
setMovementAnimationsEnabled(false)
setTargetEmotesEnabled(true)
assert(table.concat(calls,",")=="anim+,emote-,anim-,emote+")
pass("both toggles are independent in either order")

host.configData.states["Universal.Disguise.Usetargetmovementanimations"]=false
assert(savedToggle("Use target movement animations",true)==false,
    "a saved OFF check must win over the default")
host.configData.states["Universal.Disguise.Showtargetemotes"]=true
assert(savedToggle("Show target emotes",false)==true)
host.configData=nil
assert(savedToggle("Show target emotes",false)==false,"missing config falls back")
pass("saved checkbox state is read with the same key the widget persists")
'''

if not (os.environ.get('LUAU') or '').endswith('luau'):
    script = 'local function pass(name) print("PASS\\t"..name) end\n' + script
with tempfile.TemporaryDirectory(prefix='disguise-toggles-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
print('PASS Character toggles: independent, cache-only, no refetch, Animation inert')
