#!/usr/bin/env python3
"""Exercise the real shared Fling controller with deterministic physics mocks.

The mechanism is Infinite Yield's `walkfling` (line 11453 of the reference the
user provided), not IY's spinning `fling`:

    local Velocity = root.Velocity
    root.Velocity = Velocity * 1000000 + Vector3.new(0, 1000000, 0)
    RunService.RenderStepped:Wait()
    root.Velocity = Velocity
    RunService.Stepped:Wait()
    root.Velocity = Velocity + Vector3.new(0, 0.1, 0)

Nothing spins, nothing is attached to the body, and the huge velocity only
exists during the render window: it is put back before the physics step, which
is why the player keeps walking and is never launched. The retired spinning
design (BodyAngularVelocity 99999 + infinite density) is what made the body
rotate and lose control, so it is forbidden here.

These tests cover the mechanism, the frame ordering, ownership and cleanup. They
do not prove server-side knockback: only a live session can show that.
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


def without_comments(text: str) -> str:
    """Drop Lua comments so the retired mechanism may still be *explained*."""
    kept = []
    for line in text.splitlines():
        cut = line.find("--")
        kept.append(line if cut < 0 else line[:cut])
    return "\n".join(kept)


CODE = without_comments(SOURCE)

# The spinning IY fling and the old velocity-pulse design must not come back.
# Both are what made the character rotate ("rota horrible") with no control.
for forbidden in (
    "BodyAngularVelocity",
    "SetNetworkOwner",
    "CameraSubject",
    "BodyVelocity",
    "BodyGyro",
    "AlignPosition",
    "AlignOrientation",
    "SetPrimaryPartCFrame",
    "RigidityEnabled",
    "math.huge,",
    "99999",
    "9e7",
    "9e8",
    "250000",
):
    assert forbidden not in CODE, forbidden
# No body mutation at all: walkfling only writes the root velocity.
for forbidden in ("Massless", "CustomPhysicalProperties", "PhysicalProperties"):
    assert forbidden not in CODE, forbidden
# The only velocity write is IY's own pulse.
assert "PULSE_SCALE: number = 1000000" in CODE
assert "PULSE_LIFT: Vector3 = Vector3.new(0, 1000000, 0)" in CODE
assert "PULSE_DRIFT: Vector3 = Vector3.new(0, 0.1, 0)" in CODE
assert "velocity * PULSE_SCALE + PULSE_LIFT" in CODE
assert "velocity + PULSE_DRIFT" in CODE
# IY's ordering: the huge velocity is restored inside the render window, before
# the Stepped/physics step. Swapping these two is what would launch the player.
render_at = CODE.index("waitFrame(renderSignal)")
restore_at = CODE.index("root.AssemblyLinearVelocity = velocity\n")
stepped_at = CODE.index("waitFrame(steppedSignal)")
assert render_at < restore_at < stepped_at, "walkfling frame ordering"
# Waiting on a frame signal is not a connection: no per-frame callback at all.
for forbidden in ("RenderStepped:Connect", "Stepped:Connect", "Heartbeat:Connect"):
    assert forbidden not in CODE, forbidden
assert "RunService.RenderStepped:Connect" not in CODE
# Never write to the target: another player's assembly is not ours to drive.
for line in CODE.splitlines():
    stripped = line.strip()
    if stripped.startswith("targetRoot."):
        raise AssertionError(f"Fling writes the target assembly: {stripped}")
# The character is never turned: no lookAt anywhere, and the only PivotTo calls
# keep the orientation of the frame that was captured before the fling.
assert "lookAt" not in CODE
assert CODE.count("PivotTo(") == 2, "placement and return home, nothing else"

script = PRELUDE + r'''
local cfMt = {}
cfMt.__index = cfMt
cfMt.__mul = function(a,b) return CFrame.new(a.Position + b.Position) end
-- Roblox: CFrame - Vector3 keeps the rotation and shifts the position.
cfMt.__sub = function(a,b) return CFrame.new(a.Position - b) end
CFrame = {}
function CFrame.new(x,y,z)
    local p = if type(x) == "table" then x else Vector3.new(x or 0,y or 0,z or 0)
    return setmetatable({Position=p,LookVector=Vector3.new(0,0,-1)},cfMt)
end
CFrame.lookAt = function(p,q)
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

-- Deterministic scheduler. Two kinds of waits exist: task.wait(dt) wakes on the
-- virtual clock, and RunService signals wake when their frame fires. pump(dt)
-- advances one frame: due timers first, then Heartbeat, RenderStepped, Stepped
-- in Roblox's order, which is exactly what walkfling depends on.
local scheduler = {now = 0, records = {}, pending = {}}
os = {clock = function() return scheduler.now end}
local frameOrder = {"Heartbeat", "RenderStepped", "Stepped"}
local frameWaiters = {Heartbeat = {}, RenderStepped = {}, Stepped = {}}
local frameTrace = {}
local traceSource = nil
local traceEnabled = false

local function makeFrameSignal(name)
    local signal = {}
    function signal:Wait()
        local co = coroutine.running()
        -- Park: a coroutine waiting for a frame must not be woken by the timer
        -- loop, or the frame order this mechanism depends on disappears.
        if co and scheduler.records[co] then
            scheduler.records[co].wakeAt = math.huge
        end
        table.insert(frameWaiters[name], co)
        coroutine.yield()
    end
    function signal:Connect() error("Fling must not connect frame signals") end
    return signal
end
RunService = {
    Heartbeat = makeFrameSignal("Heartbeat"),
    RenderStepped = makeFrameSignal("RenderStepped"),
    Stepped = makeFrameSignal("Stepped"),
}

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

local function recordFrame(name)
    if not traceEnabled or not traceSource then return end
    local velocity = traceSource.AssemblyLinearVelocity
    table.insert(frameTrace, {
        frame = name,
        velocity = velocity,
    })
end

local function fireFrame(name)
    local waiters = frameWaiters[name]
    if #waiters == 0 then return false end
    recordFrame(name)
    frameWaiters[name] = {}
    for _, co in ipairs(waiters) do
        local ok, err = coroutine.resume(co)
        assert(ok, err)
        if coroutine.status(co) == "dead" then
            scheduler.records[co] = nil
            for index, record in ipairs(scheduler.pending) do
                if record.co == co then table.remove(scheduler.pending, index); break end
            end
        end
    end
    return true
end

local function runDueTimers()
    for _ = 1, 200 do
        local progressed = false
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
                progressed = true
            else
                index += 1
            end
        end
        if not progressed then return end
    end
end

-- One call = one frame: due timers, then Heartbeat, RenderStepped and Stepped.
-- Advancing a single frame per call is what makes the walkfling ordering
-- observable and keeps the 0.1 stud drift at IY's real rate.
pump = function(dt)
    scheduler.now += (dt or 1/60)
    runDueTimers()
    for _, name in ipairs(frameOrder) do
        fireFrame(name)
    end
    runDueTimers()
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
            if key == "CFrame" and value and value.LookVector then
                self.props.LookVector = value.LookVector
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
local host = {Players = Players, LocalPlayer = LocalPlayer, RunService = RunService}
local Module = (function()
''' + SOURCE + r'''
end)()
local physics = Module.init({host = host, services = {activity = activity}})
traceSource = root

local function sameVector(a, b)
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
local function resetTrace()
    table.clear(frameTrace)
    traceEnabled = true
end
local function stopTrace() traceEnabled = false end
local function hugeSamples()
    local count = 0
    for _, sample in ipairs(frameTrace) do
        if sample.velocity and math.abs(sample.velocity.Y) > 100000 then count += 1 end
    end
    return count
end
local function steppedSamplesHuge()
    for _, sample in ipairs(frameTrace) do
        if sample.frame == "Stepped" and sample.velocity
            and math.abs(sample.velocity.Y) > 100000 then
            return true
        end
    end
    return false
end

-- Boot with everything OFF: no listener, no pulse, no writes.
assert(root.Touched:live() == 0, "no Touched listener while OFF")
assert(localCharacter.pivotCalls == nil, "OFF does not move the character")
assert(not physics.isRunning() and not physics.isTouchEnabled() and not activityValue)
assert(not physics.isPulsing() and not physics.isSpinning() and not physics.isHeld())
assert(root.AssemblyLinearVelocity.Y == 0, "OFF writes no velocity")
pass("Fling OFF allocates nothing, attaches nothing and writes nothing")

-- Directed fling: IY's walkfling, applied to the target's contact point.
local home = root.CFrame
local localStartLook = root.LookVector
local targetBefore = targetRoot.AssemblyLinearVelocity
resetTrace()
assert(physics.start(target, {duration = 0.4}))
assert(localCharacter.pivotCalls == 1, "one contact placement")
assert(root.LookVector.Z == localStartLook.Z
    and root.LookVector.X == localStartLook.X,
    "the fling must not rotate the character toward the target")
assert(physics.isRunning() and physics.isPulsing(), "session owns the pulse loop")
-- Nothing is attached to the body and no physical property is touched; this is
-- what keeps full control, and it is the opposite of the spinning version.
assert(#created == 0, "no BodyAngularVelocity is ever created")
assert(root:FindFirstChild("WurstFlingSpin") == nil, "no spin constraint")
assert(root:FindFirstChild("WurstFlingHold") == nil, "no position pin")
assert(root.Massless == false and torso.Massless == false, "body stays physical")
assert(root.CanCollide == false and torso.CanCollide == true,
    "collision is not touched (Noclip owns it)")
assert(root.CustomPhysicalProperties.density == 0.7, "density is untouched")
assert(sameVector(targetRoot.AssemblyLinearVelocity, targetBefore),
    "never writes the target assembly")
assert(not physics.start(target, {duration = 0.4}), "one directed owner")
pass("directed fling pulses like walkfling without touching the body")

-- Frame ordering: the huge velocity exists during the render window only and is
-- already restored when Stepped fires. That is why walking survives and why the
-- player is not launched.
pump(0.1)
assert(hugeSamples() > 0, "the pulse really reaches 1e6 during the render window")
assert(not steppedSamplesHuge(),
    "the huge velocity is restored before the physics step")
local lastRestored = nil
for _, sample in ipairs(frameTrace) do
    if sample.frame == "Stepped" then lastRestored = sample.velocity end
end
assert(lastRestored and math.abs(lastRestored.Y) < 1000,
    "physics only ever sees the player's own velocity")
stopTrace()
pass("walkfling ordering: 1e6 is gone before the physics step runs")

-- The player's own motion is what the loop restores, not a frozen zero.
pump(0.5) -- let the previous session finish
assert(not physics.isRunning())
root.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
assert(physics.start(target, {duration = 0.3, restorePosition = false}))
resetTrace()
pump(1/60)
pump(1/60)
pump(1/60)
assert(physics.isPulsing(), "the second session is pulsing")
local sawWalking = false
for _, sample in ipairs(frameTrace) do
    if sample.frame == "Stepped" and sample.velocity.X == 16 then sawWalking = true end
end
stopTrace()
assert(sawWalking, "walking velocity survives every pulse")
assert(not steppedSamplesHuge(), "and physics still never sees the 1e6")
root.AssemblyLinearVelocity = Vector3.zero
pump(0.5)
pass("the player keeps walking through the pulse")

-- Duration end restores everything and returns the body home.
pump(0.5)
assert(not physics.isRunning(), "session ends at its duration")
assert(localCharacter.pivotCalls >= 2,
    "the only extra placement is the one return home, never a per-frame one")
assert(root.AssemblyLinearVelocity.X == 16
    and math.abs(root.AssemblyLinearVelocity.Y) < 1,
    "the walking velocity is put back (only IY's 0.1 drift remains)")
assert(#created == 0 and root:FindFirstChild("WurstFlingSpin") == nil)
assert(root.Massless == false and root.CustomPhysicalProperties.density == 0.7)

-- Death ends the session without waiting for the duration or leaving a pulse.
root.AssemblyLinearVelocity = Vector3.zero
assert(physics.start(target, {duration = 2, restorePosition = false}))
assert(physics.isRunning())
humanoid.Health = 0
pump(0.1)
assert(not physics.isRunning(), "death ends the session on the next pulse")
humanoid.Died:Fire()
assert(not physics.isRunning(), "the Died event is idempotent here")
humanoid.Health = 100
assert(not physics.isPulsing(), "no pulse survives death")
pass("death releases the fling")

-- Touch Fling: listen with CanTouch only, pulse on real contact.
physics.setTouchEnabled(true)
assert(physics.isTouchEnabled() and activityValue)
assert(root.CanTouch == true and torso.CanTouch == true, "body listens for contact")
assert(root.CanCollide == false and torso.CanCollide == true,
    "listening does not change collisions")
assert(root.Touched:live() == 1, "one listener per body part")
pump(1)
local placementsBefore: number? = localCharacter.pivotCalls
assert(not physics.isPulsing(), "idle Touch never pulses")
assert(localCharacter.pivotCalls == placementsBefore,
    "idle Touch never places the character")

local touchStartLook = root.LookVector
local touchStartPosition = root.Position
root.AssemblyLinearVelocity = Vector3.zero
resetTrace()
root.Touched:Fire(targetRoot)
assert(physics.isPulsing(), "contact starts the pulse")
pump(0.05)
assert(hugeSamples() > 0, "the contact pulse uses the same 1e6 window")
assert(not steppedSamplesHuge(), "and restores it before the physics step")
stopTrace()
assert(root.LookVector.X == touchStartLook.X
    and root.LookVector.Z == touchStartLook.Z,
    "Touch never rotates the character")
assert(localCharacter.pivotCalls == placementsBefore,
    "Touch never moves the character")
assert((root.Position - touchStartPosition).Magnitude < 0.001,
    "Touch never teleports the character")
assert(sameVector(targetRoot.AssemblyLinearVelocity, targetBefore),
    "Touch never writes the target either")
assert(#created == 0 and root:FindFirstChild("WurstFlingSpin") == nil
    and root:FindFirstChild("WurstFlingHold") == nil,
    "Touch attaches nothing")
assert(root.Massless == false and root.CustomPhysicalProperties.density == 0.7,
    "Touch leaves the body alone")
pass("Touch pulses on contact without rotating, moving or pinning the player")

-- The pulse is short and self-cleaning: full control comes back by itself.
pump(0.3)
assert(not physics.isPulsing(), "the contact pulse ends by itself")
assert(root.AssemblyLinearVelocity.X == 0
    and math.abs(root.AssemblyLinearVelocity.Y) < 1
    and root.AssemblyLinearVelocity.Z == 0,
    "the velocity the player had is restored after the pulse")
assert(root.Touched:live() == 1, "still listening, with nothing attached")
assert(activityValue, "Touch keeps the fling activity flag while armed")

-- Cooldown: a contact right after a pulse does not chain a new one.
root.Touched:Fire(targetRoot)
assert(not physics.isPulsing(), "the cooldown keeps a crowd from chaining pulses")
pump(0.5)
root.Touched:Fire(targetRoot)
assert(physics.isPulsing(), "a new contact after the cooldown pulses again")
pump(0.3)
physics.setTouchEnabled(false)
assert(not physics.isTouchEnabled() and not activityValue, "OFF releases everything")
assert(root.CanTouch == false and torso.CanTouch == false, "CanTouch restored")
assert(root.Touched:live() == 0, "OFF disconnects the listeners")
assert(not physics.isPulsing(), "OFF stops the pulse")
pass("Touch OFF restores every snapshot and the cooldown holds")

-- A non-player touch never pulses.
physics.setTouchEnabled(true)
local prop = Instance.new("Part", localCharacter.Parent)
root.Touched:Fire(prop)
assert(not physics.isPulsing(), "touching scenery is not a fling")
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
root.AssemblyLinearVelocity = Vector3.zero
pump(0.5) -- the previous test left the touch cooldown running
physics.setTouchEnabled(true)
root.Touched:Fire(targetRoot)
assert(physics.isPulsing(), "a pulse is running before destroy")
physics.destroy()
assert(not physics.isPulsing() and not physics.isRunning(), "destroy stops the pulse")
assert(not physics.isTouchEnabled() and not activityValue, "destroy clears activity")
assert(root.CanTouch == false and torso.CanTouch == false, "destroy restores CanTouch")
assert(root.Touched:live() == 0, "destroy disconnects the listeners")
assert(#created == 0 and root:FindFirstChild("WurstFlingSpin") == nil
    and root:FindFirstChild("WurstFlingHold") == nil, "nothing was ever attached")
assert(root.Massless == false and root.CustomPhysicalProperties.density == 0.7,
    "destroy leaves the body as it found it")
pump(0.3)
assert(not physics.isPulsing(), "and it cannot come back")
pass("destroy stops the pulse, disconnects and leaves the body untouched")

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
local notices: {string} = {}
host.notify = function(message) table.insert(notices, tostring(message)) end
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
local capturedActions: {[string]: any} = {}
local capturedToggles: {string} = {}
local capturedList: any = nil
host.addActionOption = function(_feature, labelText, callback)
    capturedActions[labelText] = callback
end
host.addListOption = function(_feature, labelText, definition)
    capturedList = {label = labelText, definition = definition}
    return {GetAttribute = function() return "MM2.Fling.Flingtarget" end}
end
host.addToggleOption = function(_feature, labelText)
    table.insert(capturedToggles, labelText)
end
host.addTextOption = function(_feature, labelText)
    table.insert(capturedToggles, "TEXT:" .. tostring(labelText))
end
host.addInformationOption = function() end
host.addToggleOption = function() end
LocalPlayer.Name = "Local"
target.Name = "Target"
state.mm2Core = core
state.frameworkEnvironment = host
physics = Module.init({host = host, services = {activity = activity}})
state.flingPhysics = physics
local function newMM2()
    return (function()
''' + MM2_SOURCE + r'''
    end)()
end
local MM2Module = newMM2()
MM2Module.init({})
assert(type(state.mm2PerformFling) == "function")

-- v148: the card shows a live roster and never asks for a typed name.
assert(capturedList and capturedList.label == "Fling target",
    "the Fling card must build a player list called Fling target")
assert(capturedList.definition.single == true, "one target at a time")
for _, label in ipairs(capturedToggles) do
    assert(label ~= "Touch Fling",
        "the MM2 card must not duplicate the universal Touch Fling toggle")
    assert(label ~= "TEXT:Target player",
        "the Fling card must not ask the user to type a player name")
end
local roster = state.mm2FlingRoster()
assert(#roster == 1, "the roster lists the living players of the round")
assert(roster[1].name == "Target" and roster[1].label == "Target [Innocent]",
    "the roster entry carries the resolved role")
local items = capturedList.definition.items()
assert(#items == 1 and items[1] == "Target [Innocent]",
    "the list offers the same labelled entry the roster reports")
assert(state.mm2FlingSelection() == nil, "nothing is selected at boot")
capturedList.definition.onChanged({["Target [Innocent]"] = true}, {"Target [Innocent]"})
assert(state.mm2FlingSelection() == "Target",
    "picking a row resolves to that player, not to a name typed by hand")
capturedList.definition.onChanged({}, {})
assert(state.mm2FlingSelection() == nil, "clearing the list clears the target")
pass("Fling target is a live role-labelled list, never a text box")

targetHumanoid.Health = 0
assert(#state.mm2FlingRoster() == 0, "dead players leave the list")
targetHumanoid.Health = 100
assert(#state.mm2FlingRoster() == 1, "and come back when they are alive again")

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
-- The action reads the list: it never guesses, and it never fires without one.
capturedList.definition.onChanged({["Target [Innocent]"] = true}, {"Target [Innocent]"})
capturedActions["Fling"]()
assert(physics.isRunning(), "Fling acts on the selected living player")
physics.cancel()
capturedList.definition.onChanged({}, {})
capturedActions["Fling"]()
assert(not physics.isRunning(), "Fling refuses to guess when nothing is selected")
assert(type(state.mm2FlingRoster) == "function"
    and type(state.mm2FlingSelection) == "function")
pass("Fling acts on the selection and never guesses a target")

MM2Module.destroy()
assert(state.mm2PerformFling == nil, "MM2 cleanup removes export")
assert(state.mm2FlingRoster == nil and state.mm2FlingSelection == nil,
    "MM2 cleanup removes the roster hooks")

-- A round without published roles: the knife and the gun decide the label.
-- This is the "it does not even know who the sheriff is" complaint.
local savedRole, savedWeapon = core.getPlayerRole, core.getPlayerWeapon
core.getPlayerRole = function() return nil end
core.getPlayerWeapon = function(_player, weaponName)
    if weaponName == "Gun" then return {Name = "Gun"} end
    return nil
end
services.gameBridge.playerRole = nil
capturedList = nil
local weaponModule = newMM2()
weaponModule.init({})
local weaponRoster = state.mm2FlingRoster()
assert(#weaponRoster == 1 and weaponRoster[1].label == "Target [Sheriff]",
    "the gun in the backpack marks the sheriff without round data")
weaponModule.destroy()

-- No round roles and no weapons: the card must say the roles are not published
-- yet instead of claiming nobody was found.
core.getPlayerWeapon = function() return nil end
local savedMurderer, savedSheriff = core.findMurderer, core.findSheriff
core.findMurderer = function() return nil end
core.findSheriff = function() return nil end
local unknownModule = newMM2()
unknownModule.init({})
assert(#state.mm2FlingRoster() == 1,
    "players without a known role still appear in the list")
assert(state.mm2FlingRoster()[1].label == "Target",
    "an unknown role adds no suffix and does not hide the player")
table.clear(notices)
capturedActions["Fling Murderer"]()
assert(notices[1] and string.find(notices[1], "not published", 1, true),
    "the card must explain that MM2 has not published the roles, not that nobody exists")
unknownModule.destroy()
pass("unpublished roles are explained, not hidden")
core.findMurderer, core.findSheriff = savedMurderer, savedSheriff
core.getPlayerWeapon = function(_player, weaponName)
    if weaponName == "Knife" then return {Name = "Knife"} end
    return nil
end
local knifeModule = newMM2()
knifeModule.init({})
local knifeRoster = state.mm2FlingRoster()
assert(#knifeRoster == 1 and knifeRoster[1].label == "Target [Murderer]",
    "the knife in the backpack marks the murderer without round data")
knifeModule.destroy()
core.getPlayerRole, core.getPlayerWeapon = savedRole, savedWeapon
pass("the roster names roles from round data and from the knife/gun actually held")
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
