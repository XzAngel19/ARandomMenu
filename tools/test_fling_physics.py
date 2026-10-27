#!/usr/bin/env python3
"""Exercise the real shared Fling controller with deterministic physics mocks.

The mechanism is Infinite Yield's: the LOCAL assembly spins (BodyAngularVelocity
99999, infinite density, massless + no collision) and the contact carries that
energy into the other body. Writing velocity to another player's assembly does
nothing, which is why the previous bounded-pulse version looked like it was
disabled.

These tests cover the mechanism, the duty cycle, ownership and cleanup. They do
not prove server-side knockback: only a live session can show that.
"""
from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path

from test_mm2_precision import PRELUDE

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/libraries/Fling.lua").read_text()
MM2_SOURCE = (ROOT / "src/games/MM2/Blatant/Fling.lua").read_text()
TOUCH_SOURCE = (ROOT / "src/games/universal/Blatant/TouchFling.lua").read_text()
NOCLIP_SOURCE = (ROOT / "src/games/universal/Blatant/Noclip.lua").read_text()

# The retired velocity-pulse design must not come back.
for forbidden in (
    "SetNetworkOwner",
    "CameraSubject",
    "BodyVelocity",
    "BodyGyro",
    "9e7",
    "9e8",
    "10000",
    "12000",
    "20000",
):
    assert forbidden not in SOURCE, forbidden
# No per-frame Lua at all: the whole point of the IY mechanism is that the
# engine does the work and we only flip the constraint. The words may appear in
# comments explaining the old design, never as a connection.
for forbidden in ("PreSimulation", "Heartbeat", "RenderStepped", "Stepped"):
    assert f"RunService.{forbidden}" not in SOURCE, f"Fling must not connect {forbidden}"
    assert f"{forbidden}:Connect" not in SOURCE, f"Fling must not connect {forbidden}"
assert "RunService" not in SOURCE.replace("run the", ""), (
    "Fling must not need RunService at all"
)
assert "SPIN_RATE: number = 99999" in SOURCE
assert re.search(r"PhysicalProperties\.new\(\s*math\.huge, 0\.3, 0\.5\s*\)", SOURCE)
assert "BodyAngularVelocity" in SOURCE
assert "task.wait(SPIN_ON)" in SOURCE and "task.wait(SPIN_OFF)" in SOURCE
# Never write to the target: another player's assembly is not ours to drive.
for line in SOURCE.splitlines():
    stripped = line.strip()
    if stripped.startswith("targetRoot."):
        raise AssertionError(f"Fling writes the target assembly: {stripped}")

script = PRELUDE + r'''
local cfMt = {}
cfMt.__index = cfMt
cfMt.__mul = function(a,b) return CFrame.new(a.Position + b.Position) end
CFrame = {}
function CFrame.new(x,y,z)
    local p = if type(x) == "table" then x else Vector3.new(x or 0,y or 0,z or 0)
    return setmetatable({Position=p,LookVector=Vector3.new(0,0,-1)},cfMt)
end
function CFrame.lookAt(p,q)
    local result = CFrame.new(p)
    result.LookVector = (q-p).Unit
    return result
end
CFrame.Angles = function() return CFrame.new() end
Enum.HumanoidStateType = {Seated="Seated",Physics="Physics",GettingUp="GettingUp"}
Enum.PositionAlignmentMode = {OneAttachment="OneAttachment",TwoAttachment="TwoAttachment"}

local oldTypeof = typeof
function typeof(value)
    if type(value) == "table" and value._instance then return "Instance" end
    return oldTypeof(value)
end

-- Deterministic task scheduler: spawn/delay create coroutine records, wait
-- yields, and pump(dt) advances a virtual clock.
local scheduler = {now = 0, records = {}, pending = {}}
os = {clock = function() return scheduler.now end}
task = {}
local function schedule(co, wakeAt)
    local record = {co = co, wakeAt = wakeAt}
    scheduler.records[co] = record
    table.insert(scheduler.pending, record)
    return record
end
function task.spawn(fn, ...)
    local co = coroutine.create(fn)
    schedule(co, scheduler.now)
    if select("#", ...) > 0 then
        local args = table.pack(...)
        local ok, err = coroutine.resume(co, table.unpack(args, 1, args.n))
        assert(ok, err)
    end
    return co
end
function task.delay(dt, fn)
    local co = coroutine.create(fn)
    return schedule(co, scheduler.now + (dt or 0)).co
end
local pump
function task.wait(dt)
    local co = coroutine.running()
    local record = scheduler.records[co]
    if not record then
        -- Main thread (e.g. a blocking wrapper loop): advance the clock and
        -- run everything that has come due instead of trying to yield.
        pump(dt)
        return dt
    end
    record.wakeAt = scheduler.now + (dt or 0)
    coroutine.yield()
end
pump = function(dt)
    scheduler.now += (dt or 1/60)
    local steps = 0
    while steps < 500 do
        steps += 1
        local resumed = false
        local index = 1
        while index <= #scheduler.pending do
            local record = scheduler.pending[index]
            if record.wakeAt <= scheduler.now + 1e-9 then
                local ok, err = coroutine.resume(record.co)
                assert(ok, err)
                if coroutine.status(record.co) == "dead" then
                    table.remove(scheduler.pending, index)
                    scheduler.records[record.co] = nil
                else
                    index += 1
                end
                resumed = true
            else
                index += 1
            end
        end
        if not resumed then
            return
        end
    end
end

PhysicalProperties = {}
function PhysicalProperties.new(density, friction, elasticity)
    return {density = density, friction = friction, elasticity = elasticity, Density = density}
end

local function signal()
    local s = {callbacks = {}}
    function s:Connect(fn)
        local c = {Connected = true, fn = fn}
        function c:Disconnect() self.Connected = false end
        table.insert(self.callbacks, c)
        return c
    end
    function s:Fire(...)
        for _, c in ipairs(self.callbacks) do
            if c.Connected then c.fn(...) end
        end
    end
    function s:live()
        local n = 0
        for _, c in ipairs(self.callbacks) do if c.Connected then n += 1 end end
        return n
    end
    return s
end

local created = {}
Instance = {}
function Instance.new(class, parent)
    local o = {ClassName = class, children = {}, _instance = true, props = {}}
    function o:IsA(c)
        return c == self.ClassName or (c == "BasePart" and self.ClassName == "Part")
            or (c == "Model" and self.ClassName == "Model")
    end
    function o:FindFirstChildOfClass(c)
        for _, child in ipairs(self.children) do
            if child.ClassName == c then return child end
        end
        return nil
    end
    function o:FindFirstChild(name)
        for _, child in ipairs(self.children) do
            if child.Name == name then return child end
        end
        return nil
    end
    function o:GetChildren() return self.children end
    function o:GetDescendants()
        local out = {}
        local function walk(node)
            for _, child in ipairs(node.children) do
                table.insert(out, child)
                walk(child)
            end
        end
        walk(self)
        return out
    end
    function o:PivotTo(frame)
        self.pivotCalls = (self.pivotCalls or 0) + 1
        local root = self:FindFirstChild("HumanoidRootPart")
        if root then root.CFrame = frame; root.Position = frame.Position end
    end
    function o:Destroy()
        local parent = self.Parent
        if parent and parent.children then
            for i, child in ipairs(parent.children) do
                if child == self then table.remove(parent.children, i); break end
            end
        end
        self.Parent = nil
        self.destroyed = true
    end
    o.Touched = signal()
    o.Died = signal()
    o.DescendantAdded = signal()
    setmetatable(o, {
        __index = function(self, key)
            if key == "Parent" then return self.props.Parent end
            if self.props[key] ~= nil then return self.props[key] end
            return nil
        end,
        __newindex = function(self, key, value)
            if key == "Parent" then
                local old = self.props.Parent
                if old and old.children then
                    for i, child in ipairs(old.children) do
                        if child == self then table.remove(old.children, i); break end
                    end
                end
                self.props.Parent = value
                if value and value.children then table.insert(value.children, self) end
                return
            end
            self.props[key] = value
        end,
    })
    if parent then o.Parent = parent end
    if class == "BodyAngularVelocity" then table.insert(created, o) end
    return o
end

local function makeRig(name, position)
    local character = Instance.new("Model")
    character.Name = name
    local humanoid = Instance.new("Humanoid", character)
    humanoid.Name = "Humanoid"
    humanoid.Health = 100
    humanoid.AutoRotate = true
    humanoid.Sit = false
    local root = Instance.new("Part", character)
    root.Name = "HumanoidRootPart"
    root.CanCollide = false
    root.CanTouch = false
    root.Massless = false
    root.CustomPhysicalProperties = {density = 0.7}
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.Position = position
    root.CFrame = CFrame.new(position)
    humanoid.RootPart = root
    local torso = Instance.new("Part", character)
    torso.Name = "UpperTorso"
    torso.CanCollide = true
    torso.CanTouch = false
    torso.Massless = false
    torso.CustomPhysicalProperties = {density = 0.7}
    torso.Position = position
    torso.CFrame = CFrame.new(position)
    return character, humanoid, root, torso
end

local localCharacter, humanoid, root, torso = makeRig("Local", Vector3.new(0,10,0))
local targetCharacter, targetHumanoid, targetRoot, targetTorso = makeRig("Target", Vector3.new(0,10,-3))
localCharacter.Parent = Instance.new("Workspace")
targetCharacter.Parent = localCharacter.Parent
local LocalPlayer = {Name = "Local", Character = localCharacter}
local target = {Name = "Target", Character = targetCharacter, Parent = true}
local Players = {}
target.Parent = Players
function Players:GetPlayers() return {LocalPlayer, target} end
function Players:GetPlayerFromCharacter(character)
    if character == localCharacter then return LocalPlayer end
    if character == targetCharacter then return target end
    return nil
end
local activityValue = false
local activity = {
    set = function(name, value) assert(name == "fling"); activityValue = value end,
    isActive = function(name) return name == "fling" and activityValue end,
}
local host = {Players = Players, LocalPlayer = LocalPlayer}
local Module = (function()
''' + SOURCE + r'''
end)()
local physics = Module.init({host = host, services = {activity = activity}})

local function constraint()
    return root:FindFirstChild("WurstFlingSpin")
end
local function sameVector(a, b)
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

-- Boot with everything OFF: no listener, no constraint, no spin, no signals.
assert(root.Touched:live() == 0, "no Touched listener while OFF")
assert(localCharacter.pivotCalls == nil, "OFF does not move the character")
assert(not physics.isRunning() and not physics.isTouchEnabled() and not activityValue)
pass("Fling OFF allocates nothing and moves nothing")

-- The local character is held while it spins: IY alone throws the flinger too.
local function holdConstraint()
    -- The attachment and the AlignPosition share the name; pick the constraint.
    for _, child in ipairs(root.children) do
        if child.ClassName == "AlignPosition" and child.Name == "WurstFlingHold" then
            return child
        end
    end
    return nil
end
local function holdAttachment()
    for _, child in ipairs(root.children) do
        if child.ClassName == "Attachment" and child.Name == "WurstFlingHold" then
            return child
        end
    end
    return nil
end

-- Directed fling: IY mechanism.
local home = root.CFrame
local targetBefore = targetRoot.AssemblyLinearVelocity
assert(physics.start(target, {duration = 0.4}))
assert(localCharacter.pivotCalls == 1, "one contact placement")
local spin = constraint()
assert(spin, "directed fling attaches the IY spin")
assert(spin.AngularVelocity.Y == 99999, "99999 rad/s spin")
assert(spin.MaxTorque.Y == math.huge and spin.P == math.huge, "infinite torque")
assert(root.Massless == true and torso.Massless == true, "body becomes massless")
assert(root.CanCollide == false and torso.CanCollide == false,
    "no collision pairs are created (that was physics cost)")
assert(root.CustomPhysicalProperties.density == math.huge, "infinite density")
assert(sameVector(targetRoot.AssemblyLinearVelocity, targetBefore),
    "never writes the target assembly (it would be overwritten anyway)")
assert(not physics.start(target, {duration = 0.4}), "one directed owner")
assert(spin and physics.isHeld(), "the spinner is position-held")
local hold = holdConstraint()
assert(hold and hold.RigidityEnabled == true, "rigid AlignPosition, no spring")
assert(hold.Attachment0 and hold.Attachment0.Name == "WurstFlingHold")
-- OneAttachment holds the world Position; the default (0,0,0) would drag the
-- player to the origin, so it must be the contact position.
assert(hold.Position == root.Position, "the hold is pinned where the contact was")
pass("directed fling spins the local assembly and never drives the target")

-- Duty cycle: 0.2 s spinning, 0.1 s stopped.
pump(0.05)
assert(constraint().AngularVelocity.Y == 99999, "spinning at the start of the cycle")
pump(0.2)
assert(constraint().AngularVelocity.Y == 0, "spin stops after 0.2 s")
pump(0.1)
assert(constraint().AngularVelocity.Y == 99999, "spin resumes after 0.1 s")
pass("IY duty cycle 0.2 s on / 0.1 s off with no per-frame Lua")

-- Duration end restores everything.
pump(0.4)
assert(not physics.isRunning(), "session ends at its duration")
assert(constraint() == nil, "constraint destroyed")
assert(root.Massless == false and torso.Massless == false, "massless restored")
assert(root.CanCollide == false and torso.CanCollide == true, "collision restored")
assert(root.CustomPhysicalProperties.density == 0.7, "physical properties restored")
assert(localCharacter.pivotCalls == 2,
    "the only extra placement is the one return home, never a per-frame one")
assert(not physics.isHeld() and holdConstraint() == nil
    and holdAttachment() == nil, "the position hold is released with the spin")
pass("directed fling restores density, massless and collision")

-- The pin has a short life: a long session must not freeze the player.
assert(physics.start(target, {duration = 2}))
assert(physics.isHeld() and constraint() ~= nil)
pump(1.0)
assert(constraint() ~= nil, "the spin is still running")
assert(not physics.isHeld() and holdConstraint() == nil,
    "the position pin expires on its own after ~0.8 s")
physics.cancel()

-- Local death cancels without leaving the constraint behind.
assert(physics.start(target, {duration = 2}))
assert(constraint() ~= nil)
humanoid.Health = 0
pump(0.1)
assert(constraint() == nil, "death releases the spin on the next poll")
humanoid.Died:Fire()
assert(constraint() == nil, "the Died event is idempotent here")
humanoid.Health = 100
physics.cancel()
assert(not physics.isRunning())
pass("death releases the spin")

-- Touch Fling: listen with CanTouch only, spin on real contact.
physics.setTouchEnabled(true)
assert(physics.isTouchEnabled() and activityValue)
assert(root.CanTouch == true and torso.CanTouch == true, "body listens for contact")
assert(root.CanCollide == false and torso.CanCollide == true,
    "listening does not change collisions")
assert(root.Touched:live() == 1, "one listener per body part")
assert(constraint() == nil, "idle Touch never spins")
pump(1)
local placementsBefore: number? = localCharacter.pivotCalls
assert(constraint() == nil, "idle Touch never spins")
assert(localCharacter.pivotCalls == placementsBefore,
    "idle Touch never places the character")
root.Touched:Fire(targetRoot)
local touchSpin = constraint()
assert(touchSpin and touchSpin.AngularVelocity.Y == 99999, "contact starts the spin")
assert(touchSpin.MaxTorque.Y == math.huge, "contact spin keeps infinite torque")
-- The touched player flies; you stay where the contact happened.
assert(physics.isHeld() and holdConstraint() ~= nil,
    "Touch holds the local player while it spins")
local heldRootVel = root.AssemblyLinearVelocity
assert(sameVector(heldRootVel, Vector3.zero),
    "the spinner never keeps a launch velocity of its own")
assert(sameVector(targetRoot.AssemblyLinearVelocity, targetBefore),
    "Touch never writes the target either")
pass("Touch spins on contact only")

-- Walking away releases the spin by itself.
pump(0.7)
assert(constraint() == nil, "contact expiry releases the spin")
assert(holdConstraint() == nil and holdAttachment() == nil,
    "contact expiry releases the position hold")
assert(root.Massless == false and root.CustomPhysicalProperties.density == 0.7,
    "contact expiry restores the body")
root.Touched:Fire(targetRoot)
assert(constraint() ~= nil, "a new contact spins again")
physics.setTouchEnabled(false)
assert(constraint() == nil and not activityValue, "OFF releases the spin")
assert(root.CanTouch == false and torso.CanTouch == false, "CanTouch restored")
assert(root.Touched:live() == 0, "OFF disconnects the listeners")
pass("Touch OFF and contact expiry restore every snapshot")

-- A non-player touch never spins.
physics.setTouchEnabled(true)
local prop = Instance.new("Part", localCharacter.Parent)
root.Touched:Fire(prop)
assert(constraint() == nil, "touching scenery is not a fling")
physics.setTouchEnabled(false)
pass("scenery contact is ignored")

-- The real universal card wiring.
local universalState = {flingPhysics = physics, toggleControls = {}}
host.state = universalState
host.configData = {states = {}}
host.addFeatureTooltip = function() end
local touchCard = nil
host.createUniversalFeature = function(_name, _description, _order, callback, _config)
    touchCard = {onToggle = callback}
    function touchCard:SetStatus(value) self.status = value end
    return touchCard
end
local TouchModule = (function()
''' + TOUCH_SOURCE + r'''
end)()
TouchModule.init({host = host})
assert(type(universalState.setTouchFlingEnabled) == "function")
touchCard.onToggle(true)
assert(physics.isTouchEnabled() and touchCard.status == "ON")
touchCard.onToggle(false)
assert(not physics.isTouchEnabled())
TouchModule.destroy()
pass("universal Touch card wires ON/OFF and cleanup")

-- Noclip keeps one collision owner and never walks the tree per frame.
host.featureConnections = {}
host.disconnectFeatureConnection = function(key)
    local connection = host.featureConnections[key]
    if connection then connection:Disconnect(); host.featureConnections[key] = nil end
end
local noclipTick = nil
host.TaskManager = {Connect = function(_, callback)
    noclipTick = callback
    return {Disconnect = function()
        if noclipTick == callback then noclipTick = nil end
    end}
end}
local noclipCard = nil
host.createUniversalFeature = function(_name, _description, _order, callback, _config)
    noclipCard = {onToggle = callback}
    return noclipCard
end
local NoclipModule = (function()
''' + NOCLIP_SOURCE + r'''
end)()
NoclipModule.init({host = host, services = {activity = activity}})
noclipCard.onToggle(true)
local descendantWalks = 0
local originalGetDescendants = localCharacter.GetDescendants
localCharacter.GetDescendants = function(self)
    descendantWalks += 1
    return originalGetDescendants(self)
end
noclipTick()
local afterFirst = descendantWalks
for _ = 1, 10 do noclipTick() end
assert(descendantWalks == afterFirst, "Noclip must not walk the tree every frame")
assert(torso.CanCollide == false, "Noclip takes collisions once")
noclipCard.onToggle(false)
NoclipModule.destroy()
assert(torso.CanCollide == true, "Noclip restores its own snapshot")
pass("Noclip caches the part list instead of walking it every frame")

-- Destroy cleans everything.
physics.setTouchEnabled(true)
root.Touched:Fire(targetRoot)
assert(constraint() ~= nil)
physics.destroy()
assert(constraint() == nil and holdConstraint() == nil and holdAttachment() == nil)
assert(not physics.isTouchEnabled() and not activityValue)
assert(root.CanTouch == false and root.CustomPhysicalProperties.density == 0.7)
pass("destroy releases the spin, the hold and restores the body")
'''

script += r'''
-- MM2 wrapper guards and blocking contract, using the real module next.
local roundActive = false
state = {
    flingPhysics = nil,
    mm2Core = nil,
    frameworkEnvironment = nil,
    clearRoleMemo = function() end,
    setTouchFlingEnabled = function(on) physics.setTouchEnabled(on) end,
}
services = {
    protectedTargets = {isProtected = function() return false end},
    gameBridge = {playerRole = function() return "Innocent" end},
    activity = activity,
}
mm2Features = {}
local core = {
    isRoundLifecycleActive = function() return roundActive end,
    findMM2Map = function() return true end,
    isPlayerAlive = function(player)
        if player == LocalPlayer then return humanoid.Health > 0 end
        return targetHumanoid.Health > 0
    end,
    getPlayerWeapon = function() return nil end,
    getPlayerRole = function() return "Innocent" end,
    findMurderer = function() return target end,
    findSheriff = function() return target end,
    requestRoleRefresh = function() end,
}
host.getCharacterParts = function() return localCharacter, humanoid, root end
host.notify = function() end
host.findPlayerByText = function() return target end
host.configData = {states = {}}
host.featureConnections = {}
host.disconnectFeatureConnection = function(key)
    local connection = host.featureConnections[key]
    if connection then connection:Disconnect(); host.featureConnections[key] = nil end
end
host.TaskManager = {Connect = function(_, callback)
    return {Disconnect = function() end}
end}
host.createUniversalFeature = function(_name, _description, _order, callback, _config)
    return {SetStatus = function() end, onToggle = callback}
end
host.addActionOption = function() end
host.addTextOption = function() end
host.addInformationOption = function() end
host.addToggleOption = function() end
LocalPlayer.Name = "Local"
target.Name = "Target"
state.mm2Core = core
state.frameworkEnvironment = host
physics = Module.init({host = host, services = {activity = activity}})
state.flingPhysics = physics
local MM2Module = (function()
''' + MM2_SOURCE + r'''
end)()
MM2Module.init({})
assert(type(state.mm2PerformFling) == "function")
assert(not state.mm2PerformFling(target, {silent = true}), "lobby rejected")
assert(not physics.isRunning())
roundActive = true
humanoid.Health = 0
assert(not state.mm2PerformFling(target, {silent = true}), "dead local rejected")
assert(not physics.isRunning())
humanoid.Health = 100
assert(not state.mm2PerformFling(LocalPlayer, {silent = true}), "self target rejected")
assert(state.mm2PerformFling(target, {silent = true}), "valid round target starts")
assert(not state.mm2PerformFling(target, {silent = true}), "second session rejected")
physics.cancel()
assert(not physics.isRunning())
pass("MM2 wrapper rejects lobby, death and self target and deduplicates sessions")

-- task.wait advances the fake clock; the blocking wrapper waits for the end.
localCharacter.pivotCalls = 0
assert(state.mm2PerformFling(target, {
    silent = true, blocking = true, duration = 0.1, restorePosition = false,
}))
assert(not physics.isRunning(), "blocking waits for the bounded session")
assert(localCharacter.pivotCalls == 1,
    "Auto Farm path has one live contact placement and no cancellation return")
MM2Module.destroy()
assert(state.mm2PerformFling == nil, "MM2 cleanup removes export")
physics.destroy()
pass("MM2 blocking cancellation and destroy cleanup")
'''

with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as handle:
    handle.write(script)
    path = handle.name
try:
    result = subprocess.run(
        [os.environ.get("LUAU", str(ROOT / "tools/luau/bin/luau")), path],
        text=True, capture_output=True,
    )
    print(result.stdout, end="")
    if result.returncode:
        print(result.stderr, end="")
        raise SystemExit(result.returncode)
finally:
    os.unlink(path)
