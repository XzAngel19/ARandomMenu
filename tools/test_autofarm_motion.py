#!/usr/bin/env python3
"""Behavioural harness for MM2 Auto Farm's motion layer.

The user's report was physical, not cosmetic: the farm "moves but falls into the
void" and Walk "does nothing". Static string tests cannot catch that, so this
harness boots the real module with a small physics model:

  * every simulated frame runs the RunService.Stepped callbacks (before physics),
  * then gravity is applied and the root is integrated,
  * then the task tick (Heartbeat) runs with its delta time.

It then asserts what a player would see:

  1. Below (Hitbox) flies from the round's start to a coin 40 studs away and
     holds altitude on the way (never sinks below the depth budget).
  2. Walk mode keeps the body walkable (no PlatformStand, no under-map hide) and
     hands the humanoid a real move direction; if the humanoid controller is
     dead the velocity carry moves the body instead.
  3. Falling below the budget is caught and the body is put back inside the map
     instead of continuing to fall.
  4. "Stay Under When Round starts" never buries a Walk-mode body.
"""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/games/MM2/Other/AutoFarm.lua").read_text()

PRELUDE = r'''
local Vector3 = {}
local mt = {}
function Vector3.new(x, y, z)
    return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, mt)
end
Vector3.zero = Vector3.new(0, 0, 0)
mt.__index = function(a, k)
    if k == "Magnitude" then
        return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
    end
    if k == "Unit" then
        local m = a.Magnitude
        if m == 0 then return Vector3.zero end
        return Vector3.new(a.X / m, a.Y / m, a.Z / m)
    end
    return nil
end
mt.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
mt.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
mt.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
mt.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
    return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
mt.__div = function(a, b) return a * (1 / b) end

local CF = {}
CF.__index = CF
CF.__mul = function(a, b)
    local out = setmetatable({}, CF)
    out.Position = a.Position + b.Position
    out.LookVector = a.LookVector
    return out
end
CF.__add = function(a, b)
    local out = setmetatable({}, CF)
    out.Position = a.Position + b
    out.LookVector = a.LookVector
    return out
end
CF.__sub = function(a, b)
    local out = setmetatable({}, CF)
    out.Position = a.Position - b
    out.LookVector = a.LookVector
    return out
end
local CFrame = {}
function CFrame.new(x, y, z)
    local c = setmetatable({}, CF)
    if type(x) == "table" then
        c.Position = x
    else
        c.Position = Vector3.new(x or 0, y or 0, z or 0)
    end
    c.LookVector = Vector3.new(0, 0, -1)
    return c
end
function CFrame.Angles() return CFrame.new(0, 0, 0) end

local typeof = function(value)
    if type(value) == "table" then
        local meta = getmetatable(value)
        if meta == CF then return "CFrame" end
        if meta == mt then return "Vector3" end
    end
    return type(value)
end

local Enum = {
    HumanoidStateType = {Running = "Running", GettingUp = "GettingUp", Seated = "Seated"},
    Material = {SmoothPlastic = "SmoothPlastic"},
    RaycastFilterType = {Exclude = "Exclude"},
    SurfaceType = {Smooth = "Smooth"},
}
local function Color3_fromRGB(r, g, b) return {R = r, G = g, B = b} end
Color3 = {fromRGB = Color3_fromRGB}

-- clock -------------------------------------------------------------------
-- The module times everything with os.clock(), so the simulation owns it.
local now = 0
local function currentTime() return now end
local os = {clock = currentTime, time = currentTime}
local task = {
    wait = function() end,
    spawn = function(fn) fn() end,
    delay = function(_seconds, fn) fn() end,
}

-- instances ---------------------------------------------------------------
local function signal()
    local handlers = {}
    local self = {}
    function self:Connect(fn)
        table.insert(handlers, fn)
        return {Disconnect = function()
            for index, item in ipairs(handlers) do
                if item == fn then table.remove(handlers, index) break end
            end
        end}
    end
    function self:Fire(...)
        local snapshot = {}
        for index, fn in ipairs(handlers) do snapshot[index] = fn end
        for _, fn in ipairs(snapshot) do fn(...) end
    end
    self.count = function() return #handlers end
    return self
end

local Instance = {new = function(class) return {ClassName = class, Parent = nil,
    Destroy = function(self) self.Parent = nil end} end}

-- The local body ----------------------------------------------------------
local rootProps = {Position = Vector3.new(0, 12, 0), Size = Vector3.new(2, 2, 1),
    AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero,
    CanCollide = true, Parent = true, Name = "HumanoidRootPart"}
local root = setmetatable({}, {__index = function(_, key)
    if key == "CFrame" then return CFrame.new(rootProps.Position) end
    return rootProps[key]
end, __newindex = function(_, key, value)
    if key == "CFrame" then
        rootProps.Position = value.Position
        return
    end
    if key == "Position" then
        rootProps.Position = value
        return
    end
    rootProps[key] = value
end})
local function rootSpan()
    local size = rootProps.Size
    return size.Y
end

local humanoid = {Health = 100, WalkSpeed = 16, PlatformStand = false,
    AutoRotate = true, Sit = false, Jump = false,
    MoveDirection = Vector3.zero, movedDirection = nil}
function humanoid:Move(direction)
    humanoid.movedDirection = direction
end
function humanoid:ChangeState() end
function humanoid:EquipTool() end
function humanoid:SetStateEnabled() end

local torso = {Name = "Torso", ClassName = "Part", Parent = true, CanCollide = true,
    Position = Vector3.new(0, 12, 0)}
function torso:IsA(class) return class == "BasePart" end
function torso:FindFirstChild() return nil end
function torso:FindFirstChildWhichIsA() return nil end
function root:IsA(class) return class == "BasePart" end
function root:FindFirstChild() return nil end
function root:FindFirstChildWhichIsA() return nil end

local character = {Name = "Local", ClassName = "Model", Parent = true}
function character:FindFirstChildOfClass(class)
    if class == "Humanoid" then return humanoid end
    return nil
end
function character:FindFirstChild(name)
    if name == "HumanoidRootPart" then return root end
    if name == "Torso" then return torso end
    return nil
end
function character:GetChildren() return {root, torso} end
function character:GetDescendants() return {root, torso} end
function character:PivotTo(frame)
    rootProps.Position = frame.Position
end
function character:FindFirstChildWhichIsA() return root end

local LocalPlayer = {Name = "Local", Character = character}
local Players = {GetPlayers = function() return {LocalPlayer} end}

-- The map, so isCharacterInActiveRound says "in round" --------------------
local mapFloor = {Name = "Floor", ClassName = "Part", Parent = true,
    Position = Vector3.new(0, 10, 0)}
function mapFloor:IsA(class) return class == "BasePart" end
function mapFloor:FindFirstChild() return nil end
function mapFloor:FindFirstChildWhichIsA() return nil end
local mapModel = {Name = "Map", ClassName = "Model", Parent = true}
function mapModel:FindFirstChild(name)
    if name == "Spawns" then return nil end
    if name == "CoinContainer" then return nil end
    return nil
end
function mapModel:FindFirstChildWhichIsA() return mapFloor end

-- Coins -------------------------------------------------------------------
local coins = {}
local function makeCoin(position)
    local props = {Name = "Coin_Server", ClassName = "Part", Parent = workspace,
        Position = position, Collected = false}
    local coin = setmetatable({}, {__index = function(_, key)
        if key == "IsA" then return function(_, class) return class == "BasePart" end end
        return props[key]
    end, __newindex = function(_, key, value) props[key] = value end})
    function coin:GetAttribute(name)
        if name == "Collected" then return props.Collected end
        return nil
    end
    function coin:SetAttribute(name, value)
        if name == "Collected" then props.Collected = value end
    end
    function coin:FindFirstChild() return nil end
    table.insert(coins, {part = coin, props = props})
    return coin
end

workspace = {FallenPartsDestroyHeight = -500, CurrentCamera = nil}
function workspace:GetChildren() return {mapModel, mapFloor} end
function workspace:GetDescendants()
    local out = {}
    for _, entry in ipairs(coins) do table.insert(out, entry.part) end
    return out
end
function workspace:FindFirstChild(name)
    if name == "Map" then return mapModel end
    return nil
end
function workspace:Raycast(origin, direction)
    local floorY = 10
    if origin.Y >= floorY and origin.Y + direction.Y <= floorY then
        return {Position = Vector3.new(origin.X, floorY, origin.Z), Instance = mapFloor}
    end
    return nil
end
RaycastParams = {new = function()
    return {FilterDescendantsInstances = {}, FilterType = nil,
        RespectCanCollide = false, IgnoreWater = false}
end}

local CollectionService = {GetTagged = function() return {} end}
game = {GetService = function(_, name)
    if name == "CollectionService" then return CollectionService end
    if name == "Players" then return Players end
    if name == "Workspace" then return workspace end
    return nil
end}

-- Services the module pulls from the host --------------------------------
local steppedSignal = signal()
local heartbeatSignal = signal()
local RunService = {Stepped = steppedSignal, Heartbeat = heartbeatSignal,
    RenderStepped = signal(), IsStudio = function() return false end}

local tasks = {}
local TaskManager = {Connect = function(_, callback)
    table.insert(tasks, callback)
    local entry = {callback = callback}
    function entry:Disconnect()
        for index, item in ipairs(tasks) do
            if item == callback then table.remove(tasks, index) break end
        end
    end
    return entry
end}

-- The MM2 core -----------------------------------------------------------
state = {}
state.mm2Core = {
    getPlayerRole = function(player) return "Innocent" end,
    getPlayerWeapon = function() return nil end,
    isPlayerAlive = function() return true end,
    findMurderer = function() return nil end,
    findSheriff = function() return nil end,
    findDroppedGun = function() return nil end,
    isRoundLifecycleActive = function() return true end,
    findMM2Map = function() return mapModel end,
    getEstimatedLatency = function() return 0.05 end,
    getGunOriginCFrame = function() return CFrame.new(0, 12, 0) end,
}

-- Host API ----------------------------------------------------------------
notify = function() end
getCharacterParts = function() return character, humanoid, root end
featureConnections = {}
disconnectFeatureConnection = function(key)
    local connection = featureConnections[key]
    if connection and type(connection.Disconnect) == "function" then
        connection:Disconnect()
    end
    featureConnections[key] = nil
end

local optionCallbacks = {}
local feature = {name = "Auto Farm", status = nil}
function feature:SetStatus(text) self.status = text end

createUniversalFeature = function(name, _description, _order, onToggle, _configuration)
    feature.onToggle = onToggle
    return feature
end
addCycleOption = function(_feature, name, _values, _default, callback)
    optionCallbacks[name] = callback
end
addNumberOption = function(_feature, name, _default, _min, _max, callback)
    optionCallbacks[name] = callback
end
addToggleOption = function(_feature, name, _default, callback)
    optionCallbacks[name] = callback
end
addInformationOption = function() end
addSectionOption = function() end

-- Frame driver -----------------------------------------------------------
local GRAVITY = 196.2
local frameDelta = 1 / 60

local function stepFrame()
    now += frameDelta
    steppedSignal:Fire(frameDelta)
    -- physics: gravity on our new velocity, then integrate
    local velocity = rootProps.AssemblyLinearVelocity
    local falling = Vector3.new(velocity.X, velocity.Y - GRAVITY * frameDelta, velocity.Z)
    local position = rootProps.Position
    rootProps.Position = Vector3.new(
        position.X + falling.X * frameDelta,
        position.Y + falling.Y * frameDelta,
        position.Z + falling.Z * frameDelta
    )
    -- The map floor only holds a body whose parts still collide (Walk); Below
    -- flies with NoClip, so the floor must not catch it.
    if rootProps.CanCollide and rootProps.Position.Y < 10 + 1 then
        rootProps.Position = Vector3.new(rootProps.Position.X, 11, rootProps.Position.Z)
        rootProps.AssemblyLinearVelocity = Vector3.new(
            rootProps.AssemblyLinearVelocity.X, 0, rootProps.AssemblyLinearVelocity.Z)
    end
    for _, callback in ipairs(tasks) do
        callback(frameDelta)
    end
end

local function frames(count)
    for _ = 1, count do stepFrame() end
end

local function resetBody()
    rootProps.Position = Vector3.new(0, 12, 0)
    rootProps.AssemblyLinearVelocity = Vector3.zero
    rootProps.AssemblyAngularVelocity = Vector3.zero
    rootProps.Size = Vector3.new(2, 2, 1)
    rootProps.CanCollide = true
    humanoid.Health = 100
    humanoid.PlatformStand = false
    humanoid.AutoRotate = true
    humanoid.WalkSpeed = 16
    humanoid.movedDirection = nil
    character.Parent = true
    LocalPlayer.Character = character
    now = 0
end

local passed = 0
local function pass(name)
    passed += 1
    print("PASS", name)
end
local function near(a, b, epsilon)
    assert(math.abs(a - b) <= (epsilon or 1e-6), tostring(a) .. " != " .. tostring(b))
end
'''

SCRIPT = PRELUDE + "\nlocal Module = (function()\n" + SOURCE + "\nend)()\n" + r'''
Module.init(nil)
assert(feature.onToggle, "Auto Farm must build its card")
local function setMode(value) optionCallbacks["Farm Mode"](value) end
local function setSpeed(value) optionCallbacks["Farm Speed"](value) end
local function setStayUnder(value) optionCallbacks["Stay Under When Round starts"](value) end

-- 1) Below (Hitbox): fly to a coin 40 studs away ---------------------------
resetBody()
table.clear(coins)
local coin = makeCoin(Vector3.new(40, 10, 0))
setMode("Below (Hitbox)")
setSpeed(24)
setStayUnder(true)
feature.onToggle(true)
local lowest = 0
for _ = 1, 300 do
    stepFrame()
    if rootProps.Position.Y < lowest then lowest = rootProps.Position.Y end
end
local finalPosition = rootProps.Position
local distanceToCoin = math.sqrt(
    (finalPosition.X - 40) ^ 2 + (finalPosition.Z - 0) ^ 2
)
assert(distanceToCoin < 8,
    "Below must reach the coin, ended " .. tostring(distanceToCoin) .. " studs away")
near(finalPosition.Y, 10 - 3, 6)
assert(lowest > 12 - 90,
    "Below must never sink past the depth budget, lowest Y was " .. tostring(lowest))
assert(humanoid.PlatformStand, "Below flies with PlatformStand")
assert(rootProps.Size.Y == 8, "Below grows the root hitbox")

-- A stalled task tick (the full-bag sequence sets `busy`) used to leave the body
-- with no writes at all, so gravity took it: this is the free fall the user saw.
local beforeStall = rootProps.Position.Y
for _ = 1, 60 do
    now += frameDelta
    steppedSignal:Fire(frameDelta)
    local velocity = rootProps.AssemblyLinearVelocity
    local falling = Vector3.new(velocity.X, velocity.Y - GRAVITY * frameDelta, velocity.Z)
    local position = rootProps.Position
    rootProps.Position = Vector3.new(
        position.X + falling.X * frameDelta,
        position.Y + falling.Y * frameDelta,
        position.Z + falling.Z * frameDelta
    )
end
near(rootProps.Position.Y, beforeStall, 1.5)
pass("Below (Hitbox) flies to the coin and holds altitude, even with the tick stalled")

-- 2) Walk: walkable body + a real move direction ---------------------------
resetBody()
table.clear(coins)
makeCoin(Vector3.new(40, 10, 0))
setMode("Walk")
setSpeed(20)
setStayUnder(true)
feature.onToggle(true)
frames(30)
assert(not humanoid.PlatformStand, "Walk must never leave PlatformStand on")
assert(humanoid.AutoRotate, "Walk must leave AutoRotate on")
assert(rootProps.Size.Y == 2, "Walk must not keep the Below hitbox")
assert(humanoid.WalkSpeed == 20, "Walk uses the Farm Speed slider as WalkSpeed")
assert(humanoid.movedDirection and humanoid.movedDirection.Magnitude > 0.5,
    "Walk must hand the humanoid a real direction")
local walkLowest = rootProps.Position.Y
frames(240)
assert(rootProps.Position.Y > walkLowest - 40, "Walk must not fall through the floor")
-- With a humanoid controller that never moves the body, the velocity carry has
-- to take over after two seconds of no progress.
local carried = math.abs(rootProps.AssemblyLinearVelocity.X) > 5
assert(carried, "the walk fallback carry must move the body when Move does nothing")
assert(rootProps.Position.X > 4, "the walk fallback actually travels, X=" .. tostring(rootProps.Position.X))
pass("Walk stays walkable, asks the humanoid to move, and carries when it cannot")

-- 3) The void is caught and the body is put back ---------------------------
resetBody()
table.clear(coins)
makeCoin(Vector3.new(40, 10, 0))
setMode("Below (Hitbox)")
setStayUnder(true)
feature.onToggle(true)
frames(5)
rootProps.Position = Vector3.new(0, -600, 0)
frames(4)
assert(rootProps.Position.Y > -100,
    "a deep fall must be recovered, Y is " .. tostring(rootProps.Position.Y))
assert(rootProps.Position.Y > workspace.FallenPartsDestroyHeight + 40,
    "recovered above the destroy height")
pass("falling into the void is caught and the body is put back inside the map")

-- 4) Stay Under never buries a Walk body -----------------------------------
resetBody()
table.clear(coins)
setMode("Walk")
setStayUnder(true)
feature.onToggle(true)
frames(90)
assert(rootProps.Position.Y >= 10.5,
    "Walk with Stay Under on must stay on the map, Y is " .. tostring(rootProps.Position.Y))
assert(not humanoid.PlatformStand, "Walk never gets PlatformStand")
pass("Stay Under no longer buries a Walk-mode body")

feature.onToggle(false)
print("PASS " .. passed .. " Auto Farm motion suites")
'''

with tempfile.TemporaryDirectory() as tmp:
    script = Path(tmp) / "autofarm_motion.luau"
    script.write_text(SCRIPT)
    subprocess.run([os.environ.get("LUAU", "luau"), str(script)], check=True)
