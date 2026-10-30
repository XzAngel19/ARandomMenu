#!/usr/bin/env python3
"""v139.2: knife throw discipline -- the blade must be in hand, and the aim
solver must not run every frame.

The saved v139.1 session has 13 knife activations and 9 observed blades. Four
crossed the remote without ever becoming a projectile, and the ones that did
fire from the RightHand fallback origin instead of the knife handle, because
`EquipTool` is a round trip and `FireServer` is not. This suite runs the real
`throwKnife` from the module against a tool that only reaches the character
after one frame and asserts:

  * the first call equips and does NOT fire,
  * the remote is not re-spammed while the equip is travelling,
  * once the handle is in the character the throw fires with the handle origin,
  * the equipped path still works for a tool that was already in hand,
  * the idle manual-only loop does not solve; a live tracer remains capped at
    15x/s; the solver also stays idle during a throw cooldown without a tracer;
  * auto throws remain on time, and native mouse/touch redirects still resolve.

LUAU=/path/to/luau python3 tools/test_mm2_knife_equip.py
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE, section

ROOT = Path(__file__).resolve().parents[1]
KNIFE = (ROOT / "src/games/MM2/Combat/KnifeThrow.lua").read_text()

code = PRELUDE + r'''
local clock = 0
-- The module reads os.clock() for its cooldown and its aim cache.
os.clock = function() return clock end
local Player = {Name = 'Local'}
local LocalPlayer = Player
local fired = {}
local equips = 0

local remote = {IsA = function(_, class) return class == 'RemoteEvent' end}
function remote:FireServer(origin, target)
    table.insert(fired, {origin = origin, target = target})
end

local function makeKnife()
    local handle = {CFrame = CFrame.new(Vector3.new(0, 2, 0))}
    function handle:IsA(class) return class == 'BasePart' end
    local events = {KnifeThrown = remote}
    function events:FindFirstChild(name)
        if name == 'KnifeThrown' then return remote end
        return nil
    end
    local tool = {Name = 'Knife', Parent = nil}
    function tool:FindFirstChild(name)
        if name == 'Handle' then return handle end
        if name == 'Events' then return events end
        return nil
    end
    function tool:IsA() return true end
    return tool, handle
end

local knife, handle = makeKnife()
local backpack = {}
local character = {Name = 'Character'}
function character:FindFirstChild(name)
    if name == 'RightHand' then return nil end
    if name == 'Right Arm' then return nil end
    if name == 'HumanoidRootPart' then return handle end
    return nil
end
function character:FindFirstChildOfClass(class)
    if class == 'Humanoid' then
        return {Health = 100, EquipTool = function(_, tool)
            equips += 1
            -- The equip is a round trip: the tool reaches the character only
            -- when the next frame is simulated.
        end}
    end
    return nil
end
Player.Character = character
Player.FindFirstChildOfClass = function(_, class)
    if class == 'Backpack' then return {GetChildren = function() return {} end} end
    return nil
end
knife.Parent = backpack

local function getPlayerWeapon() return knife end
local function getPlayerRole(who)
    if who == Player then return 'Murderer' end
    return 'Innocent'
end
local function isPlayerAlive() return true end
local protectedPlayer = nil
local function isProtectedTarget(player) return player == protectedPlayer end
local function getEstimatedLatency() return 0.1 end
local function isWeaponPathClear() return true end
local lobby = {Player}
local getPlayersCalls = 0
local Players = {GetPlayers = function()
    getPlayersCalls += 1
    return lobby
end}
local state = {mm2Prediction = nil, mm2Core = {}}
local roundActive = true
state.mm2Core.isRoundLifecycleActive = function() return roundActive end
local blocked, hasGround = false, true
local RaycastParams = {new = function() return {} end}
local vectorMeta = getmetatable(Vector3.zero)
local typeof = function(value)
    if getmetatable(value) == vectorMeta then return 'Vector3' end
    return type(value)
end
local workspace = {Raycast = function(_, origin, direction)
    if direction.Y == -18 then
        if hasGround then return {Position = Vector3.new(origin.X, 0, origin.Z)} end
        return nil
    end
    if blocked then return {Position = origin + direction * 0.2} end
    return nil
end}
-- The decompiled WeaponService returns CFrame for BOTH methods. The real
-- consumer can access .Position, so a Vector3 result is not a valid mock.
local originalMouse = CFrame.new(Vector3.new(10, 20, 30))
local originalTarget = CFrame.new(Vector3.new(40, 50, 60))
local forwardedSelf, forwardedX, forwardedY
local weaponService = {}
function weaponService:GetMouseTargetCFrame() return originalMouse end
function weaponService:GetTargetPosition(x, y)
    forwardedSelf, forwardedX, forwardedY = self, x, y
    return originalTarget
end
local module = {}
local clientServices = {FindFirstChild = function(_, name) return name == 'WeaponService' and module or nil end}
local replicated = {FindFirstChild = function(_, name) return name == 'ClientServices' and clientServices or nil end}
local game = {GetService = function(_, name) return name == 'ReplicatedStorage' and replicated or nil end}
local require = function(mod) assert(mod == module); return weaponService end
local featureConnections = {}
local function disconnectFeatureConnection(name) featureConnections[name] = nil end
local function createUniversalFeature() return {} end
local function addToggleOption() end
local function addNumberOption() end
local function addInformationOption() end

-- Module.init state that lives above the extracted section.
local settings = {enabled = true, autoThrow = true, wallCheck = true,
    knifeTracer = false, delay = 0.6}
local lastThrowAttempt = 0
local tracerPart, targetDotPart = nil, nil
local hookedWeaponService, origGetMouseTargetCFrame, origGetTargetPosition =
    nil, nil, nil
local function destroyTracerVisuals() end
local function setKnifeStatus() end
local prediction = nil

local function load()
''' + section(
    KNIFE, "    -- Check if player is valid target", "    -- Toggle function"
) + r'''
    return throwKnife, getKnife, getThrowOriginCFrame, knifeThrowLoop,
        installWeaponServiceRedirect, uninstallWeaponServiceRedirect
end

local throwKnife, getKnife, _getOrigin, knifeThrowLoop, installRedirect, uninstallRedirect = load()
local target = {Name = 'MurdererTarget', Character = {
    FindFirstChild = function() return nil end,
}}
local victimRoot = {Position = Vector3.new(6, 0, 0), AssemblyLinearVelocity = Vector3.zero,
    IsA = function(_, class) return class == 'BasePart' end}
function target.Character:FindFirstChild(name)
    if name == 'HumanoidRootPart' then return victimRoot end
    return nil
end
function target.Character:FindFirstChildOfClass(class)
    if class == 'Humanoid' then return {Health = 100} end
    return nil
end
target.Character.IsA = function(_, c) return c == 'Model' end
table.insert(lobby, target)

-- 1. First call: the knife is in the backpack. It equips, it must NOT fire.
local ok = throwKnife(target, knife)
assert(ok == false, 'a throw from a backpack tool must not fire')
assert(#fired == 0, 'no packet may leave before the blade is in hand')
assert(equips == 1, 'the equip must be requested exactly once')

-- 2. The equip is still travelling (same frame): no second EquipTool, no fire.
clock = 0.05
assert(throwKnife(target, knife) == false, 'still waiting for the equip')
assert(equips == 1, 'the equip must not be re-spammed every frame')
assert(#fired == 0, 'no packet while the equip is in flight')

-- 3. The server accepted the equip: the blade is in the character now.
knife.Parent = character
ok = throwKnife(target, knife)
assert(ok == true, 'an equipped blade must throw')
assert(#fired == 1, 'exactly one packet per throw')
assert(equips == 1, 'no extra equip once the blade is in hand')

-- 4. Already equipped from the start: fire immediately.
fired = {}
assert(throwKnife(target, knife) == true, 'an already equipped blade throws at once')
assert(#fired == 1 and equips == 1, 'one packet, no equip churn')

-- 5. Manual-only mode has no reason to predict 15 times per second: both
-- native WeaponService hooks below solve at the actual input event instead.
settings.autoThrow = false
settings.knifeTracer = false
settings.delay = 0.6
getPlayersCalls = 0
clock = 100
knifeThrowLoop()
for frame = 1, 60 do
    clock = 100 + frame / 60
    knifeThrowLoop()
end
assert(getPlayersCalls == 0,
    'manual-only idle must do zero aim selections, saw ' .. tostring(getPlayersCalls))
local idleSolves = getPlayersCalls

-- Live tracer still needs to run its bounded preview, even without auto-throw.
settings.knifeTracer = true
getPlayersCalls = 0
for frame = 1, 60 do
    clock = 110 + frame / 60
    knifeThrowLoop()
end
assert(getPlayersCalls >= 2 and getPlayersCalls <= 20,
    'tracer should refresh at a capped rate, saw ' .. tostring(getPlayersCalls))
local tracerSolves = getPlayersCalls
settings.knifeTracer = false

-- Once a successful auto throw starts its cooldown, no tracer means no
-- selection/prediction/rays until the next throw is actually due.
settings.autoThrow = true
fired = {}
getPlayersCalls = 0
clock = 150
knifeThrowLoop()
assert(#fired == 1, 'the first ready auto throw fires immediately')
local initialCalls = getPlayersCalls
for frame = 1, 29 do
    clock = 150 + frame / 60
    knifeThrowLoop()
end
assert(#fired == 1 and getPlayersCalls == initialCalls,
    'cooldown without tracer must not re-solve every 1/15 s')

-- 6. And the thinning must not cost a throw: the blade still leaves on time.
settings.autoThrow = true
fired = {}
getPlayersCalls = 0
local throws = 0
for frame = 1, 120 do
    clock = 200 + frame / 60
    local before = #fired
    knifeThrowLoop()
    if #fired > before then throws += 1 end
end
assert(throws >= 3 and throws <= 5,
    'a 0.6 s delay over 2 s must throw 3-4 times, saw ' .. tostring(throws))
assert(getPlayersCalls <= 2 * 20,
    'throwing must not restore a per-frame solve (saw ' .. tostring(getPlayersCalls) .. ')')

-- 7. Nobody visible: no packet at all. v159 removed the speculative lane, so
-- an empty lobby spends nothing instead of throwing into an opening.
lobby = {Player}
fired = {}
clock = 300
knifeThrowLoop()
assert(#fired == 0, 'an empty lobby must not spend a knife')
clock = 300.7
knifeThrowLoop()
assert(#fired == 0, 'an empty lobby must stay silent across frames')

-- 8. A target behind cover: WallCheck refuses it and nothing is thrown. The
-- old build aimed at a lane near that body, which is what the user saw as a
-- knife aimed through the wall.
lobby = {Player, target}
isWeaponPathClear = function() return false end
fired = {}
clock = 302
knifeThrowLoop()
assert(#fired == 0, 'a target behind cover must not be thrown at')

-- 9. Protection and OFF stay silent even with a clear target. (The old round
-- guard lived inside the speculative path; with the lane gone, a visible
-- target is thrown at exactly like before v156.)
isWeaponPathClear = function() return true end
protectedPlayer = target
clock = 306
knifeThrowLoop()
assert(#fired == 0, 'knife ignored protection')
protectedPlayer, settings.enabled = nil, false
clock = 308
knifeThrowLoop()
assert(#fired == 0, 'knife fired while OFF')

-- 10. The captured native WeaponService returns CFrame for BOTH methods.
-- With a visible target both native consumers share the predicted point; with
-- nobody visible they must fall through to the game's own aim, untouched.
settings.enabled, settings.autoThrow = true, false
lobby = {Player, target}
clock = 310
installRedirect()
local function nativeConsumer(cf)
    assert(type(cf) == 'table' and typeof(cf.Position) == 'Vector3',
        'native consumer requires a CFrame-like object with a Vector3 Position')
    return cf.Position
end
local mouseAim = nativeConsumer(weaponService:GetMouseTargetCFrame())
local touchAim = nativeConsumer(weaponService:GetTargetPosition(123, 456))
assert((mouseAim - touchAim).Magnitude < 1e-6, 'mouse/touch must share the predicted point')
assert((touchAim - victimRoot.Position).Magnitude < 5, 'visible target was not selected')
-- Hidden target: the original method decides, arguments forwarded.
isWeaponPathClear = function() return false end
assert(weaponService:GetTargetPosition(123, 456) == originalTarget,
    'a hidden target must preserve the native aim')
assert(forwardedSelf == weaponService and forwardedX == 123 and forwardedY == 456,
    'fallback must forward self and viewport coordinates')
-- Empty lobby: same, the redirect invents nothing.
isWeaponPathClear = function() return true end
lobby = {Player}
clock = 311
assert(weaponService:GetMouseTargetCFrame() == originalMouse,
    'empty lobby redirected the native mouse aim')
assert(weaponService:GetTargetPosition(7, 8) == originalTarget,
    'empty lobby redirected the native touch aim')
-- Unequipped and OFF must not override either native method.
lobby = {Player, target}
knife.Parent = backpack
assert(weaponService:GetMouseTargetCFrame() == originalMouse, 'unequipped knife redirected mouse')
assert(weaponService:GetTargetPosition(1, 2) == originalTarget, 'unequipped knife redirected touch')
knife.Parent = character
settings.enabled = false
assert(weaponService:GetMouseTargetCFrame() == originalMouse, 'OFF did not bypass mouse redirect')
assert(weaponService:GetTargetPosition(3, 4) == originalTarget, 'OFF did not bypass touch redirect')
uninstallRedirect()
assert(weaponService:GetMouseTargetCFrame() == originalMouse, 'uninstall did not restore mouse')
assert(weaponService:GetTargetPosition(5, 6) == originalTarget, 'uninstall did not restore touch')
assert(forwardedSelf == weaponService and forwardedX == 5 and forwardedY == 6)
print('PASS knife manual contract: CFrame mouse/touch, visible target, hidden fallback, OFF, unequipped and restore')
print('PASS knife discipline: nothing visible and nothing blocked spends no knife')

print('PASS knife equip: no packet before the blade is in hand, then one per throw')
print('PASS knife loop: manual idle ' .. tostring(idleSolves)
    .. ' solves/s, tracer ' .. tostring(tracerSolves)
    .. ' solves/s, no cooldown solves, ' .. tostring(throws) .. ' throws on schedule')
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="knife-equip-") as directory:
        script = Path(directory) / "equip.luau"
        script.write_text(code)
        subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)


if __name__ == "__main__":
    main()
