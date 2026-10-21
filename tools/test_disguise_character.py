#!/usr/bin/env python3
"""Character mode: avatar copy is authoritative; movement can never block it."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Other/Disguise.lua').read_text()

character_body = section(
    SOURCE,
    '    local function animationSlotsFromDescription(',
    '    local function refreshMeshPartSnapshot(',
)
appearance = section(
    SOURCE,
    '    local function applyCharacterDisguise(',
    '    local function applyAnimationDisguise(',
)

mappings = SOURCE[SOURCE.index('local DEFAULT_ANIMATION_IDS:'):SOURCE.index('function Module.init(')]
helper = section(SOURCE, '    local function animationIdFromValue(', '    local function animationSlotsFromDescription(')

script = PRELUDE + mappings + r'''
local animationOverrideApplied=false
local restarted=0
local stopped=0
local function restartAnimateScript(script) restarted+=1 end
Enum.HumanoidRigType = {R6 = "R6", R15 = "R15"}
-- Declared above the sliced section in the module; the harness supplies them.
local function playingAnimationTracks(humanoid)
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then return {} end
    return animator:GetPlayingAnimationTracks()
end
function releaseIdleBridge() end
-- Description-route helpers live above the slice in the module; with no
-- readable description the apply must fall back to the direct write.
local function getAppliedDescription() return nil, false end
local function applyDescriptionToHumanoid() return false, "unavailable" end
''' + helper + character_body + r'''
-- copyTargetMovementAnimations: direct description IDs, no network calls.
local function animation(name, id)
    return {Name=name,ClassName="Animation",AnimationId=id,
        IsA=function(_,c) return c=="Animation" end,
        GetDescendants=function() return {} end}
end
local idleA,idleB=animation("Animation1","old-idle"),animation("Animation2","older-idle")
local walkA=animation("Animation1","old-walk")
local function folder(name,...)
    local children={...}
    return {Name=name,ClassName="Folder",
        IsA=function(_,c) return c=="Folder" end,
        GetDescendants=function() return children end,
        FindFirstChild=function() return nil end}
end
local categories={idle=folder("idle",idleA,idleB),walk=folder("walk",walkA)}
local animate={Name="Animate",ClassName="Script",Enabled=true,
    IsA=function(_,c) return c=="Script" end,
    FindFirstChild=function(_,name) return categories[name] end}
local character={FindFirstChild=function(_,name) return name=="Animate" and animate or nil end}
local humanoid={FindFirstChildOfClass=function(_,class)
    if class~="Animator" then return nil end
    return {GetPlayingAnimationTracks=function() return {{Stop=function() stopped+=1 end}} end}
end}
local description={IdleAnimation=12345,WalkAnimation="rbxassetid://67890",RunAnimation=0/0}

local changed=applyAnimationSlots(character,humanoid,animationSlotsFromDescription(description))
assert(changed==3,"idle pair + walk slot: "..tostring(changed))
assert(idleA.AnimationId=="rbxassetid://12345" and idleB.AnimationId=="rbxassetid://12345",
    "every idle slot gets the target animation")
assert(walkA.AnimationId=="rbxassetid://67890")
assert(animationOverrideApplied and restarted==1 and stopped==1)
pass("movement copy: direct IDs, every slot, animator restart")

-- A throwing description must not explode through the caller's pcall.
local bad={}
setmetatable(bad,{__index=function() error("description unavailable") end})
local ok=pcall(function()
    return applyAnimationSlots(character,humanoid,animationSlotsFromDescription(bad))
end)
assert(ok,"field read is already guarded")
pass("movement copy never raises on a broken description")
'''

# Ordering contract inside applyCharacterDisguise: load the target's data,
# copy the avatar, then apply movement from the cache as the optional last step.
appearance_index = appearance.index('copyCharacterAppearance(character, clone)')
load_index = appearance.index('cacheTarget(userId, description)')
movement_index = appearance.index('applyCachedMovementAnimations')
assert load_index < appearance_index < movement_index, \
    'cache -> avatar -> movement is the only accepted order'
assert 'pcall(\n                applyCachedMovementAnimations' in appearance
assert 'destroyInstance(description)' in appearance
# The final status names the rig and the slot count: a report has to say
# which body ran and how many slots it wrote.
assert '"%s · %s · %d slots"' in appearance
assert 'rigName(humanoid)' in appearance

# The two Character toggles are independent gates around separate blocks.
marker = '-- Movement animations are cosmetic'
assert appearance.count(marker) == 1
emote_block, movement_tail = appearance.split(marker, 1)
emote_block = emote_block.split('local cached: TargetCache? = targetCache', 1)[1]
assert 'settings.showTargetEmotes' in emote_block
assert 'settings.useTargetMovementAnimations' not in emote_block, \
    'the emote block must not depend on the movement toggle'
assert 'setHumanoidEmotes' in emote_block
assert 'settings.useTargetMovementAnimations' in movement_tail
assert 'setHumanoidEmotes' not in movement_tail, \
    'the movement block must not depend on the emote toggle'
assert 'applyCachedMovementAnimations' in movement_tail

# No Studio/server-only asset APIs anywhere in the loading/copying helpers.
for forbidden in ('GetObjects', 'InsertService', 'LoadAsset', 'task.wait'):
    assert forbidden not in character_body, forbidden

if not (os.environ.get('LUAU') or '').endswith('luau'):
    script = 'local function pass(name) print("PASS\\t"..name) end\nlocal function near() end\n' + script
with tempfile.TemporaryDirectory(prefix='disguise-character-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
print('PASS Character: appearance copies before movement and never depends on it')
