#!/usr/bin/env python3
"""Character mode: avatar copy is authoritative; movement can never block it."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Other/Disguise.lua').read_text()

character_body = section(
    SOURCE,
    '    local function copyTargetMovementAnimations(',
    '    local function refreshMeshPartSnapshot(',
)
appearance = section(
    SOURCE,
    '    local function applyCharacterDisguise(',
    '    local function applyAnimationDisguise(',
)

mappings = section(SOURCE, 'local MOVEMENT_ANIMATIONS:', 'function Module.init(')
helper = section(SOURCE, '    local function animationIdFromValue(', '    local function copyTargetMovementAnimations(')

script = PRELUDE + mappings + r'''
local animationOverrideApplied=false
local restarted=0
local stopped=0
local function restartAnimateScript(script) restarted+=1 end
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

local changed=copyTargetMovementAnimations(character,humanoid,description)
assert(changed==3,"idle pair + walk slot: "..tostring(changed))
assert(idleA.AnimationId=="rbxassetid://12345" and idleB.AnimationId=="rbxassetid://12345",
    "every idle slot gets the target animation")
assert(walkA.AnimationId=="rbxassetid://67890")
assert(animationOverrideApplied and restarted==1 and stopped==1)
pass("movement copy: direct IDs, every slot, animator restart")

-- A throwing description must not explode through the caller's pcall.
local bad={}
setmetatable(bad,{__index=function() error("description unavailable") end})
local ok=pcall(copyTargetMovementAnimations,character,humanoid,bad)
assert(ok,"field read is already guarded")
pass("movement copy never raises on a broken description")
'''

# Ordering contract inside applyCharacterDisguise.
appearance_index = appearance.index('copyCharacterAppearance(character, clone)')
movement_index = appearance.index('copyTargetMovementAnimations')
assert appearance_index < movement_index, 'appearance copy must run before movement'
assert 'pcall(\n                copyTargetMovementAnimations' in appearance
assert 'destroyInstance(description)\n        status("Ready")' in appearance

# copyTargetMovementAnimations must not use Studio/server-only asset APIs.
for forbidden in ('GetObjects', 'InsertService', 'LoadAsset', 'task.wait'):
    assert forbidden not in character_body, forbidden

if not (os.environ.get('LUAU') or '').endswith('luau'):
    script = 'local function pass(name) print("PASS\\t"..name) end\nlocal function near() end\n' + script
with tempfile.TemporaryDirectory(prefix='disguise-character-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
print('PASS Character: appearance copies before movement and never depends on it')
