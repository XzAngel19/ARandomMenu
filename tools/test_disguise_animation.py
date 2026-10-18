#!/usr/bin/env python3
"""Animation mode: the target's emotes and movement only, never its avatar."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Other/Disguise.lua').read_text()

script = PRELUDE + r'''
local character=setmetatable({},{__tostring=function() return "character" end})
local activeCard={Enabled=true,status=nil,notifies={}}
function activeCard:SetStatus(value) self.status=value end
local notified={}
local function notify(message) table.insert(notified,message) end
local function status(message) activeCard.status=message end
local function destroyInstance(instance) instance.destroyed=true end
local emotesAppliedToHumanoid=false
local targetEmotes=nil
local targetEquippedEmotes=nil

local description={id="target"}
local descriptionResult=description
local fetchError="network"
local calls={}
local function getUserDescription() return descriptionResult,(descriptionResult and nil or fetchError) end
local generation=1
local function stillCurrent(token,current)
    return generation==token and activeCard.Enabled and current==character
end

local originalSnapshot={emotes={original=true},equippedEmotes={equipped=true}}
local function ensureSnapshot(current,humanoid)
    table.insert(calls,"snapshot")
    assert(current==character)
    return originalSnapshot
end
local function restoreOriginalAppearance() table.insert(calls,"restore") end
local function stopAppearanceFilter() table.insert(calls,"filter-off") end
local function refreshMeshPartSnapshot() table.insert(calls,"mesh") end

local emoteList={hello=true}
local equippedList={1}
local emoteMode="ok"
local function readDescriptionEmotes()
    if emoteMode=="none" then return nil,nil end
    return emoteList,equippedList
end
local function setHumanoidEmotes(humanoid,emotes,equipped)
    table.insert(calls,"emotes")
    assert(emotes==emoteList or emotes==originalSnapshot.emotes)
    if emoteMode=="fail" and emotes==emoteList then return false,"blocked" end
    if emotes==originalSnapshot.emotes then emotesAppliedToHumanoid=false end
    return true,nil
end

local animationCount=2
local animationHook=nil
local function copyTargetMovementAnimations(current,humanoid,desc)
    table.insert(calls,"animations")
    assert(current==character and desc==description)
    if animationHook then animationHook() end
    return animationCount
end
''' + section(
    SOURCE,
    '    local function applyAnimationDisguise(',
    '    local function applyDisguise(): ()',
) + r'''
applyAnimationDisguise(1,character,{},7)
assert(table.concat(calls,",")=="snapshot,restore,filter-off,emotes,mesh,animations",table.concat(calls,","))
assert(emotesAppliedToHumanoid and targetEmotes==emoteList and targetEquippedEmotes==equippedList)
assert((activeCard.status or ""):find("Animation ·") and description.destroyed)
assert(#notified==0)
pass("Animation mode: snapshot, restore, emotes and movement; no avatar copy")

notified={};calls={};activeCard.status=nil;description.destroyed=false
animationCount=0
applyAnimationDisguise(1,character,{},7)
assert(#notified==0 and activeCard.status~=nil,"emote-only disguise still succeeds")
assert(table.find(calls,"animations"))

notified={};calls={};activeCard.status=nil
emoteMode="none";animationCount=0
applyAnimationDisguise(1,character,{},7)
assert(#notified==1 and notified[1]:find("did not expose") and activeCard.status==nil)
pass("Animation mode: emote-only works; nothing available is reported, not silent")

notified={};activeCard.status=nil;emoteMode="ok";animationCount=2
descriptionResult=nil
applyAnimationDisguise(1,character,{},7)
assert(#notified==1 and notified[1]:find("Could not load") and activeCard.status==nil)
descriptionResult=description
generation=2
applyAnimationDisguise(1,character,{},7)
assert(#notified==1 and description.destroyed,"stale request must release the description without applying")
generation=1
pass("Animation mode: load failure and stale token fail closed")

notified={};activeCard.status=nil;emoteMode="fail";animationCount=3
applyAnimationDisguise(1,character,{},7)
assert(#notified==1 and notified[1]:find("emotes could not") and activeCard.status~=nil,"movement still applies")
emoteMode="ok";emotesAppliedToHumanoid=false;calls={};activeCard.status=nil
animationHook=function() activeCard.Enabled=false end
applyAnimationDisguise(1,character,{},7)
animationHook=nil
assert(table.find(calls,"animations") and calls[#calls]=="emotes" and not emotesAppliedToHumanoid,"respawn/disable rolls the emotes back")
assert(activeCard.status==nil,"a cancelled apply must not report success")
activeCard.Enabled=true
pass("Animation mode: partial success, rollback when the character changes")

assert(not SOURCE_MARKER)
'''
# SOURCE_MARKER is never defined: remove that line (kept for clarity of intent).
script = script.replace("\nassert(not SOURCE_MARKER)\n", "\n")

assert 'applyAnimationBundle' not in SOURCE
assert 'getBundleItems' not in SOURCE
assert 'copyCharacterAppearance' not in section(
    SOURCE,
    '    local function applyAnimationDisguise(',
    '    local function applyDisguise(): ()',
)
assert 'applyAnimationDisguise(' in SOURCE.split('local function applyDisguise(): ()', 1)[1]
assert '{"Character", "Animation"}' in SOURCE
assert 'without hiding it' in SOURCE

with tempfile.TemporaryDirectory(prefix='disguise-animation-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
