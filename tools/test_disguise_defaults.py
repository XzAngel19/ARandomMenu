#!/usr/bin/env python3
"""Disguise animation sources: the target's slots, Roblox defaults, and packs."""
import os, subprocess, tempfile
from pathlib import Path
from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'src/games/universal/Other/Disguise.lua').read_text()

mappings = SOURCE[SOURCE.index('local DEFAULT_ANIMATION_IDS:'):SOURCE.index('function Module.init(')]
helpers = section(
    SOURCE,
    '    local function animationIdFromValue(',
    '    local function refreshMeshPartSnapshot(',
)
pack = section(
    SOURCE,
    '    local function animationAssetId(',
    '    local function applyCachedMovementAnimations(',
)

script = PRELUDE + mappings + r'''
local game = {}
local host = {MarketplaceService = nil}
local Enum = {InfoType = {Bundle = "Bundle"}}
''' + helpers + r'''
local function animation(name, id)
    return {Name=name,AnimationId=id,
        IsA=function(_,c) return c=="Animation" end,
        GetDescendants=function() return {} end}
end
local function folder(name, ...)
    local children = {...}
    return {Name=name,
        IsA=function(_,c) return c=="Folder" end,
        GetDescendants=function() return children end}
end
local idle1, idle2, idle3 = animation("Animation1", "mine-1"),
    animation("Animation2", "mine-2"), animation("Animation3", "mine-3")
local walk = animation("WalkAnim", "mine-walk")
local categories = {
    idle = folder("idle", idle1, idle2, idle3),
    walk = folder("walk", walk),
}
local animate = {FindFirstChild=function(_, name) return categories[name] end}
local character = {FindFirstChild=function(_, name)
    return name == "Animate" and animate or nil
end}
local stopped = 0
local humanoid = {FindFirstChildOfClass=function(_, class)
    if class ~= "Animator" then return nil end
    return {GetPlayingAnimationTracks=function()
        return {{Stop=function() stopped += 1 end}}
    end}
end}
local restarted = 0
function restartAnimateScript() restarted += 1 end
targetCache = nil
animationOverrideApplied = false
function readDescriptionEmotes() return nil, nil end
''' + pack + r'''
-- 1) The description wins where it has a value.
local slots = animationSlotsFromDescription({IdleAnimation = 12345})
assert(slots.idle == "rbxassetid://12345")
assert(slots.walk == nil, "a zero slot must stay empty until the cache fills it")
pass("description slots: only the non-zero fields are copied")

-- 2) Roblox's own seven clips fill every empty slot.
cacheTarget(7, {IdleAnimation = 12345})
assert(targetCache.slots.idle == "rbxassetid://12345", "a chosen idle is not replaced")
assert(targetCache.slots.walk == nil or type(targetCache.slots.walk) == "table")
assert(type(targetCache.slots.walk) == "table" and targetCache.slots.walk[1] == "507777826")
for _, field in ipairs({"run", "jump", "fall", "climb", "swim", "swimidle"}) do
    assert(type(targetCache.slots[field]) == "table" and #targetCache.slots[field] == 1,
        field .. " must fall back to Roblox's default")
end
assert(targetCache.slots.idle == "rbxassetid://12345",
    "an explicit idle slot is not padded")
pass("cache: the seven default clips fill the slots a description leaves at 0")

-- 3) A fully default avatar gets the three idle variants in order, and only
--    the categories the Animate script exposes are touched.
cacheTarget(7, {})
local changed = applyAnimationSlots(character, humanoid, targetCache.slots)
assert(changed == 4, "idle x3 plus walk: " .. tostring(changed))
assert(idle1.AnimationId == "rbxassetid://507766666")
assert(idle2.AnimationId == "rbxassetid://507766951")
assert(idle3.AnimationId == "rbxassetid://507766388")
assert(walk.AnimationId == "rbxassetid://507777826")
assert(animationOverrideApplied and stopped == 1 and restarted == 1)
pass("apply: three idle variants in order, world-default walk, animator restart")

-- 4) An animation pack id maps its seven items by name.
local items = {
    {Name = "Toy Idle", Id = 111},
    {Name = "Toy Walk", Id = 222},
    {Name = "Toy Run", Id = 333},
    {Name = "Toy Jump", Id = 444},
    {Name = "Toy Fall", Id = 555},
    {Name = "Toy Climb", Id = 666},
    {Name = "Toy Swim", Id = 777},
    {Name = "Swim (Idle)", Id = 888},
}
local asked = nil
host.MarketplaceService = {GetProductInfo = function(_, id, kind)
    asked = {id = id, kind = kind}
    return {BundleType = "AvatarAnimations", Items = items}
end}
local packSlots, packError = bundleAnimationSlots(43)
assert(packSlots and not packError, packError)
assert(asked.id == 43 and asked.kind == Enum.InfoType.Bundle)
assert(packSlots.idle == "rbxassetid://111" and packSlots.walk == "rbxassetid://222")
assert(packSlots.run == "rbxassetid://333" and packSlots.jump == "rbxassetid://444")
assert(packSlots.fall == "rbxassetid://555" and packSlots.climb == "rbxassetid://666")
assert(packSlots.swim == "rbxassetid://777", "Swim must not swallow Swim (Idle)")
assert(packSlots.swimidle == "rbxassetid://888", "the pair maps to swimidle")
pass("animation pack: seven categories by item name, swim vs swim idle")

-- 5) Anything else fails closed with an explanation.
host.MarketplaceService = {GetProductInfo = function() return {BundleType = "BodyParts"} end}
local none, why = bundleAnimationSlots(1)
assert(none == nil and type(why) == "string" and why:find("not an animation pack"))
host.MarketplaceService = {GetProductInfo = function() error("offline") end}
none, why = bundleAnimationSlots(2)
assert(none == nil and type(why) == "string" and why:find("not a user"))
pass("animation pack: non-animation bundles and fetch errors are reported")
'''
with tempfile.TemporaryDirectory(prefix='disguise-defaults-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
