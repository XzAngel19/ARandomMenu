#!/usr/bin/env python3
"""Disguise animation sources: target slots, rig defaults, packs and playback."""
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
settle = section(
    SOURCE,
    '    -- Runs after the ids are written.',
    '    -- Animation mode also accepts an animation *bundle* id',
)

script = PRELUDE + mappings + r'''
local game = {}
local host = {MarketplaceService = nil}
-- The module yields while it verifies playback; the harness must not.
local task = {wait = function() end, spawn = function() end}
local Enum = {
    InfoType = {Bundle = "Bundle"},
    HumanoidRigType = {R6 = "R6", R15 = "R15"},
}
''' + helpers + r'''
-- The slice calls the script restart as a global, exactly like the real module
-- does through its local; the stub counts restarts and proves they happen.
local restarted = 0
function restartAnimateScript() restarted += 1 end
function isInsideCharacter() return true end
-- Defined above the sliced section in the real file, so the harness supplies it.
local restoredCalls = 0
function restoreMovementAnimationsOnly()
    restoredCalls += 1
    animationOverrideApplied = false
end
local notices = {}
function notify(message) table.insert(notices, message) end
animationOverrideApplied = false
targetCache = nil

-- The bridge is the fallback path that plays the idle directly through the
-- Animator when the restarted script starts no track. `bridgeWorksFrom` says
-- on which attempt it is allowed to succeed, so one test can prove the
-- rig-default fallback and another the final restore.
local bridgeAttempts = 0
local bridgeWorksFrom = 1
local playing = {}
local function track(playingFlag)
    return {IsPlaying = playingFlag, Stop = function(self) self.IsPlaying = false end,
        Destroy = function() end, Play = function(self) self.IsPlaying = playingFlag end}
end
local function animator()
    return {GetPlayingAnimationTracks = function() return playing end,
        LoadAnimation = function()
            bridgeAttempts += 1
            return track(bridgeAttempts >= bridgeWorksFrom)
        end}
end
local function makeCharacter()
    local function animation(name, id)
        return {Name=name,AnimationId=id,
            IsA=function(_,c) return c=="Animation" end,
            GetDescendants=function() return {} end}
    end
    local function folder(name, children)
        return {Name=name,
            IsA=function(_,c) return c=="Folder" end,
            GetDescendants=function() return children end}
    end
    local idle1, idle2, idle3 = animation("Animation1", "mine-1"),
        animation("Animation2", "mine-2"), animation("Animation3", "mine-3")
    local walk = animation("WalkAnim", "mine-walk")
    local categories = {
        idle = folder("idle", {idle1, idle2, idle3}),
        walk = folder("walk", {walk}),
    }
    local animate = {FindFirstChild=function(_, name) return categories[name] end}
    local character = {FindFirstChild=function(_, name)
        return name == "Animate" and animate or nil
    end, GetDescendants=function() return {} end}
    return character, animate, {idle1=idle1, idle2=idle2, idle3=idle3, walk=walk}
end
local function humanoidFor(rigType, character)
    return {RigType = rigType, Parent = character or {GetDescendants=function() return {} end},
        FindFirstChildOfClass=function(_, class)
            if class ~= "Animator" then return nil end
            return animator()
        end}
end
function readDescriptionEmotes() return nil, nil end
''' + settle + pack + r'''
-- 1) The description wins where it has a value.
local slots = animationSlotsFromDescription({IdleAnimation = 12345})
assert(slots.idle == "rbxassetid://12345")
assert(slots.walk == nil, "a zero slot stays empty until apply time")
pass("description slots: only the non-zero fields are copied")

-- 2) The cache no longer bakes a rig: it stores exactly what the target set.
cacheTarget(7, {IdleAnimation = 12345})
assert(targetCache.slots.idle == "rbxassetid://12345", "a chosen idle is not replaced")
assert(targetCache.slots.walk == nil,
    "a zero slot must not be filled before the rig is known")
pass("cache: the description is stored as-is, no rig assumption")

-- 3) The defaults follow the body. An R6 rig never receives the R15 set: those
--    clips are keyed to UpperTorso/RightUpperArm and do not play at all, which
--    is the frozen rest pose in the report.
local r6 = resolvedAnimationSlots({}, humanoidFor(Enum.HumanoidRigType.R6, nil))
assert(r6.idle[1] == "180435571" and r6.idle[2] == "180435792", "R6 idle pair")
assert(r6.walk[1] == "180426354" and r6.run[1] == "180426354", "R6 walk/run")
assert(r6.jump[1] == "125750702" and r6.fall[1] == "180436148")
assert(r6.climb[1] == "180436334")
assert(r6.swim == nil and r6.swimidle == nil, "R6 has no swim default to invent")
local r15 = resolvedAnimationSlots({}, humanoidFor(Enum.HumanoidRigType.R15, nil))
assert(r15.idle[1] == "507766666" and r15.walk[1] == "507777826", "R15 defaults")
pass("rig defaults: R6 gets the classic set, R15 gets the 50xxxxx set")

-- 4) An avatar with no pack arrives as R15 ids (or as 0). On an R6 body those
--    ids are recognised as "not mine" and replaced, never applied.
local mixed = resolvedAnimationSlots(
    {walk = "rbxassetid://507777826", idle = {"rbxassetid://507766666"}},
    humanoidFor(Enum.HumanoidRigType.R6, nil)
)
assert(mixed.walk[1] == "180426354", "an R15 default must not reach an R6 rig")
assert(mixed.idle[1] == "180435571", "the R6 idle replaces the R15 one")
local custom = resolvedAnimationSlots(
    {walk = "rbxassetid://99887766"},
    humanoidFor(Enum.HumanoidRigType.R6, nil)
)
assert(custom.walk == "rbxassetid://99887766", "a real custom pack is still tried")
pass("rig defaults: R15 defaults are substituted on R6, custom ids are kept")

-- 5) A fully default R6 avatar: two idle variants in order plus walk, and the
--    script is restarted once.
playing = {track(true)}
local character, animate, refs = makeCharacter()
local r6 = humanoidFor(Enum.HumanoidRigType.R6, character)
local changed = applyAnimationSlots(character, r6,
    animationSlotsFromDescription({}))
assert(changed == 4, "two idle variants plus the walk for R6: " .. tostring(changed))
assert(refs.idle1.AnimationId == "rbxassetid://180435571")
assert(refs.idle2.AnimationId == "rbxassetid://180435792")
assert(refs.idle3.AnimationId == "rbxassetid://180435792",
    "the second variant repeats when the set has only two")
assert(refs.walk.AnimationId == "rbxassetid://180426354")
assert(animationOverrideApplied and restarted == 1)
assert(settleMovementAnimations(character, r6) == true,
    "a playing body settles without a bridge")
pass("apply: R6 defaults in order, one restart, no R15 id")

-- 6) When the target's clips load but nothing plays, the rig's own set goes on
--    and the menu says so. The avatar is never left in a still pose.
notices = {}
playing = {}
bridgeAttempts = 0
bridgeWorksFrom = 2
local character2, _, refs2 = makeCharacter()
local r6b = humanoidFor(Enum.HumanoidRigType.R6, character2)
local customSlots = {idle = "rbxassetid://777777", walk = "rbxassetid://888888"}
local applied = applyAnimationSlots(character2, r6b, customSlots)
assert(applied == 4, "one idle id fills the three slots, plus the walk: "
    .. tostring(applied))
assert(settleMovementAnimations(character2, r6b) == true,
    "the rig's own set takes over instead of leaving a still body")
assert(refs2.idle1.AnimationId == "rbxassetid://180435571",
    "the fallback writes the rig's default idle")
assert(refs2.walk.AnimationId == "rbxassetid://180426354")
assert(#notices >= 1 and string.find(notices[#notices], "do not play"),
    "the fallback is reported, not hidden")
pass("apply: clips that never play fall back to the rig's own set")

-- 7) If even the rig's defaults cannot play, everything goes back and the
--    override flag is cleared: no frozen avatar and no false claim.
notices = {}
playing = {}
bridgeAttempts = 0
bridgeWorksFrom = 99
local character3, _, _ = makeCharacter()
local r6c = humanoidFor(Enum.HumanoidRigType.R6, character3)
local restored = applyAnimationSlots(character3, r6c, customSlots)
assert(restored == 4, "the slots were written before the check")
assert(settleMovementAnimations(character3, r6c) == false,
    "nothing can play, so the settle step fails")
assert(restoredCalls == 1, "the snapshot restore runs exactly once")
assert(animationOverrideApplied == false, "the override must be released")
assert(#notices >= 1 and string.find(notices[#notices], "your own animations are back"),
    "the failure is reported in the status")
pass("apply: a rig that cannot animate anything restores the snapshot")

-- 8) A playing track is not a moving body. A bought R15 pack on an R6 rig makes
--    the Animator report a track forever while no joint is written; that is
--    the frozen avatar reported for every target except the default one. The
--    check must read the joints, not the track flag, and put back a set that
--    actually moves the rig.
notices = {}
playing = {track(true)}
bridgeAttempts = 0
bridgeWorksFrom = 1
local character4, _, refs4 = makeCharacter()
local jointReads = 0
-- The joint moves only while the slot holds a clip built for this rig: an R15
-- clip on an R6 body writes nothing, which is exactly the frozen case.
local rigJoint = setmetatable({}, {
    __index = function(_, key)
        if key == "Transform" then
            jointReads += 1
            if refs4.idle1.AnimationId == "rbxassetid://555" then
                return {X = 0, Y = 0, Z = 0, R00 = 1, R11 = 1, R22 = 1}
            end
            return {X = 0, Y = 0, Z = 0,
                R00 = math.cos(jointReads * 0.25), R11 = 1, R22 = 1}
        end
        if key == "IsA" then
            return function(_, className) return className == "Motor6D" end
        end
        return nil
    end,
})
character4.GetDescendants = function() return {rigJoint} end
local r6d = humanoidFor(Enum.HumanoidRigType.R6, character4)
local applied4 = applyAnimationSlots(character4, r6d, {idle = "rbxassetid://555"})
assert(applied4 == 4, "one idle id fills three slots, plus walk: " .. tostring(applied4))
assert(settleMovementAnimations(character4, r6d) == true,
    "a track that never moves a joint cannot count as a working animation")
assert(refs4.idle1.AnimationId == "rbxassetid://180435571",
    "the rig's own idle replaces the frozen clip")
assert(refs4.walk.AnimationId == "rbxassetid://180426354")
assert(jointReads >= 6, "the settle step samples every joint in the window: "
    .. tostring(jointReads))
assert(#notices >= 1 and string.find(notices[#notices], "do not play"),
    "the substitution is reported in the status")
pass("apply: a frozen rig is detected from the joints, not from IsPlaying")

-- 9) An animation pack id maps its seven items by name.
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
assert(packSlots.idle == "rbxassetid://111")
assert(packSlots.walk == "rbxassetid://222" and packSlots.run == "rbxassetid://333")
assert(packSlots.jump == "rbxassetid://444" and packSlots.fall == "rbxassetid://555")
assert(packSlots.climb == "rbxassetid://666")
assert(packSlots.swimidle == "rbxassetid://888", "swim idle must win over swim")
assert(packSlots.swim == "rbxassetid://777")
pass("animation pack: seven categories by item name, swim vs swim idle")

-- 10) A bundle that is not an animation pack, or a fetch that fails, is
--     reported instead of being written into the slots.
host.MarketplaceService = {GetProductInfo = function()
    return {BundleType = "AvatarAccessories", Items = {}}
end}
local wrongSlots, wrongError = bundleAnimationSlots(44)
assert(wrongSlots == nil and string.find(wrongError, "not an animation pack"),
    tostring(wrongError))
host.MarketplaceService = {GetProductInfo = function() error("not a bundle") end}
local missingSlots, missingError = bundleAnimationSlots(45)
assert(missingSlots == nil and string.find(missingError, "did not return a bundle"),
    tostring(missingError))
pass("animation pack: non-animation bundles and fetch errors are reported")
'''

with tempfile.TemporaryDirectory(prefix='disguise-defaults-') as tmp:
    path = Path(tmp) / 'test.luau'
    path.write_text(script)
    subprocess.run([os.environ.get('LUAU', 'luau'), str(path)], check=True)
