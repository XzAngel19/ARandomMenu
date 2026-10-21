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
local settings={animationPack="Off"}
-- Defined above the slice in the real module; the status line reads it.
local function rigName() return "R6" end

local description={id="target"}
local descriptionResult=description
local fetchError="network"
local calls={}
local function applyAnimationPack() table.insert(calls,"pack") return 4 end
local function getUserDescription() return descriptionResult,(descriptionResult and nil or fetchError) end
local function bundleAnimationSlots() return nil,"not a bundle" end
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
local targetCache=nil
local function cacheTarget(userId,desc)
    table.insert(calls,"cache")
    assert(userId==7 and desc==description)
    local emotes,equipped=emoteList,equippedList
    if emoteMode=="none" then emotes,equipped=nil,nil end
    targetCache={userId=userId,slots={idle="rbxassetid://1"},
        emotes=emotes,equippedEmotes=equipped}
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
local function applyCachedMovementAnimations(current,humanoid)
    table.insert(calls,"animations")
    assert(current==character)
    if animationHook then animationHook() end
    return animationCount
end
''' + section(
    SOURCE,
    '    local function applyAnimationDisguise(',
    '    local function applyDisguise(): ()',
) + r'''
applyAnimationDisguise(1,character,{},7)
assert(table.concat(calls,",")=="cache,snapshot,restore,filter-off,emotes,mesh,animations",table.concat(calls,","))
assert(emotesAppliedToHumanoid and targetCache.emotes==emoteList and targetCache.equippedEmotes==equippedList)
assert((activeCard.status or ""):find("Animation ·") and description.destroyed)
assert(#notified==0)
pass("Animation mode: snapshot, restore, emotes and movement; no avatar copy")

notified={};calls={};activeCard.status=nil;description.destroyed=false
animationCount=0
applyAnimationDisguise(1,character,{},7)
assert(#notified==0 and activeCard.status~=nil,"emote-only disguise still succeeds")
assert(table.find(calls,"animations"))

notified={};calls={};activeCard.status=nil
-- Animation mode has no toggles: it always applies movement, whatever the
-- Character-mode preference says.
animationCount=5
applyAnimationDisguise(1,character,{},7)
assert(#notified==0 and activeCard.status~=nil and table.find(calls,"animations"),
    "movement is always applied in Animation mode")
notified={};calls={};activeCard.status=nil;emoteMode="none";animationCount=0
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

notified={};calls={};activeCard.status=nil
settings.animationPack="Ninja"
applyAnimationDisguise(1,character,{},7)
assert(table.find(calls,"pack") and (activeCard.status or ""):find("pack Ninja"),
    "a selected catalog pack is applied over the target's movement animations")
settings.animationPack="Off"
pass("Animation mode: catalog pack overrides movement animations")

assert(not SOURCE_MARKER)
'''
# SOURCE_MARKER is never defined: remove that line (kept for clarity of intent).
script = script.replace("\nassert(not SOURCE_MARKER)\n", "\n")

animation_section = section(
    SOURCE,
    '    local function applyAnimationDisguise(',
    '    local function applyDisguise(): ()',
)
assert 'applyAnimationBundle' not in SOURCE
assert 'getBundleItems' not in SOURCE
assert 'copyCharacterAppearance' not in animation_section
assert 'settings.useTargetMovementAnimations' not in animation_section, \
    'Animation mode must not read the Character toggle'
assert 'settings.showTargetEmotes' not in animation_section
assert 'applyCachedMovementAnimations' in animation_section
assert 'setHumanoidEmotes' in animation_section
assert 'applyAnimationDisguise(' in SOURCE.split('local function applyDisguise(): ()', 1)[1]
assert '{"Character", "Animation"}' in SOURCE
assert 'without hiding it' in SOURCE

# Both Character toggles are gated to Character only.
movement_toggle = SOURCE.split('Name = "Use target movement animations"', 1)[1]
assert 'Values = {"Character"}' in movement_toggle.split('Tooltip', 1)[0]
emotes_toggle = SOURCE.split('Name = "Show target emotes"', 1)[1]
assert 'Values = {"Character"}' in emotes_toggle.split('Tooltip', 1)[0]
assert 'card:CreateButton' not in SOURCE, 'Show target emotes must be a check, not a run button'

# Built-in catalog animation packs: static official ids, no downloads.
assert 'ANIMATION_PACKS' in SOURCE and 'Name = "Animation Pack"' in SOURCE
for pack_name in ('Ninja', 'Knight', 'Mage', 'Zombie', 'Toy', 'Bubbly',
                  'Cartoony', 'Pirate', 'Vampire', 'Werewolf', 'Astronaut',
                  'Elder', 'Levitation', 'Robot', 'Stylish', 'Superhero',
                  'Rthro'):
    assert f'name = "{pack_name}"' in SOURCE, f'missing pack {pack_name}'
assert '"656117400"' in SOURCE and '"1083455352"' in SOURCE
assert SOURCE.count('applyAnimationPack') >= 4

with tempfile.TemporaryDirectory(prefix='disguise-animation-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
