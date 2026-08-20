--!strict
--
-- Minimal Roblox stand-in for the headless module tests.
--
-- The point is not to reimplement the engine: it is to give the module files
-- the handful of behaviours they actually depend on — instance parenting,
-- signals, vector maths, camera projection and raycasts — so their logic can be
-- exercised, and their teardown proved, without a game client. Anything a
-- module does not use is deliberately absent, so a test failing here means the
-- module reached for something new rather than the mock being incomplete.

export type MockWorld = {
    players: any,
    localPlayer: any,
    camera: any,
    workspace: any,
    raycastResult: any,
    clock: number,
    addPlayer: (name: string, team: any, position: any) -> any,
    removePlayer: (player: any) -> (),
}

local Mock = {}

local function class(name: string): any
    return name
end

-- Vectors ------------------------------------------------------------------

local Vector3Meta: any = {}
Vector3Meta.__index = Vector3Meta

local function vector3(x: number, y: number, z: number): any
    return setmetatable({X = x, Y = y, Z = z}, Vector3Meta)
end

function Vector3Meta.__add(a: any, b: any): any
    return vector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

function Vector3Meta.__sub(a: any, b: any): any
    return vector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

function Vector3Meta.__mul(a: any, b: any): any
    if type(b) == "number" then
        return vector3(a.X * b, a.Y * b, a.Z * b)
    end
    if type(a) == "number" then
        return vector3(b.X * a, b.Y * a, b.Z * a)
    end
    return vector3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

function Vector3Meta.__div(a: any, b: number): any
    return vector3(a.X / b, a.Y / b, a.Z / b)
end

function Vector3Meta.__eq(a: any, b: any): boolean
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

function Vector3Meta.__index(self: any, key: string): any
    if key == "Magnitude" then
        return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
    end
    if key == "Unit" then
        local magnitude: number = math.sqrt(
            self.X * self.X + self.Y * self.Y + self.Z * self.Z
        )
        if magnitude == 0 then
            return vector3(0, 0, 0)
        end
        return vector3(self.X / magnitude, self.Y / magnitude, self.Z / magnitude)
    end
    return rawget(Vector3Meta, key)
end

function Vector3Meta.Dot(self: any, other: any): number
    return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end

local Vector2Meta: any = {}

local function vector2(x: number, y: number): any
    return setmetatable({X = x, Y = y}, Vector2Meta)
end

function Vector2Meta.__add(a: any, b: any): any
    return vector2(a.X + b.X, a.Y + b.Y)
end

function Vector2Meta.__sub(a: any, b: any): any
    return vector2(a.X - b.X, a.Y - b.Y)
end

function Vector2Meta.__mul(a: any, b: any): any
    if type(b) == "number" then
        return vector2(a.X * b, a.Y * b)
    end
    return vector2(a.X * b.X, a.Y * b.Y)
end

function Vector2Meta.__index(self: any, key: string): any
    if key == "Magnitude" then
        return math.sqrt(self.X * self.X + self.Y * self.Y)
    end
    if key == "Unit" then
        local magnitude: number = math.sqrt(self.X * self.X + self.Y * self.Y)
        if magnitude == 0 then
            return vector2(0, 0)
        end
        return vector2(self.X / magnitude, self.Y / magnitude)
    end
    return rawget(Vector2Meta, key)
end

-- CFrames -------------------------------------------------------------------
--
-- Only the four things the modules touch: a position, the two direction
-- vectors, and adding a Vector3 to move it.

local CFrameMeta: any = {}
CFrameMeta.__index = CFrameMeta

local function cframe(position: any, look: any?): any
    return setmetatable({
        Position = position,
        LookVector = look or vector3(0, 0, -1),
        RightVector = vector3(1, 0, 0),
        UpVector = vector3(0, 1, 0),
    }, CFrameMeta)
end

function CFrameMeta.__add(a: any, b: any): any
    return cframe(a.Position + b, a.LookVector)
end

function CFrameMeta.__sub(a: any, b: any): any
    return cframe(a.Position - b, a.LookVector)
end

-- Signals ------------------------------------------------------------------

local function signal(): any
    local handlers: {any} = {}
    local object: any = {}
    function object:Connect(callback: any): any
        table.insert(handlers, callback)
        local connection: any = {Connected = true}
        function connection:Disconnect(): ()
            connection.Connected = false
            local index: number? = table.find(handlers, callback)
            if index then
                table.remove(handlers, index)
            end
        end
        return connection
    end
    function object:Fire(...: any): ()
        for _, handler: any in ipairs(table.clone(handlers)) do
            handler(...)
        end
    end
    function object:Count(): number
        return #handlers
    end
    return object
end

Mock.signal = signal

-- Instances ----------------------------------------------------------------

local function newInstance(className: string): any
    local instance: any = {
        ClassName = className,
        Name = className,
        Children = {},
        Attributes = {},
        Destroyed = false,
    }
    instance.AncestryChanged = signal()

    setmetatable(instance, {
        __index = function(self: any, key: string): any
            if key == "Parent" then
                return rawget(self, "_parent")
            end
            return nil
        end,
        __newindex = function(self: any, key: string, value: any): ()
            if key == "Parent" then
                local previous: any = rawget(self, "_parent")
                if previous then
                    local index: number? = table.find(previous.Children, self)
                    if index then
                        table.remove(previous.Children, index)
                    end
                end
                rawset(self, "_parent", value)
                if value then
                    table.insert(value.Children, self)
                end
                return
            end
            rawset(self, key, value)
        end,
    })

    function instance:IsA(query: string): boolean
        if self.ClassName == query then
            return true
        end
        if query == "BasePart" then
            return self.ClassName == "Part" or self.ClassName == "MeshPart"
        end
        if query == "GuiObject" then
            return self.ClassName == "Frame" or self.ClassName == "TextLabel"
        end
        return false
    end

    function instance:FindFirstChild(name: string): any
        for _, child: any in ipairs(self.Children) do
            if child.Name == name then
                return child
            end
        end
        return nil
    end

    function instance:FindFirstChildOfClass(query: string): any
        for _, child: any in ipairs(self.Children) do
            if child.ClassName == query then
                return child
            end
        end
        return nil
    end

    function instance:FindFirstAncestorOfClass(query: string): any
        local parent: any = self.Parent
        while parent do
            if parent.ClassName == query then
                return parent
            end
            parent = parent.Parent
        end
        return nil
    end

    function instance:GetChildren(): {any}
        return table.clone(self.Children)
    end

    function instance:GetDescendants(): {any}
        local result: {any} = {}
        for _, child: any in ipairs(self.Children) do
            table.insert(result, child)
            for _, nested: any in ipairs(child:GetDescendants()) do
                table.insert(result, nested)
            end
        end
        return result
    end

    function instance:GetExtentsSize(): any
        return vector3(4, 5, 2)
    end

    function instance:SetAttribute(key: string, value: any): ()
        self.Attributes[key] = value
    end

    function instance:GetAttribute(key: string): any
        return self.Attributes[key]
    end

    function instance:Destroy(): ()
        for _, child: any in ipairs(table.clone(self.Children)) do
            child:Destroy()
        end
        self.Parent = nil
        rawset(self, "Destroyed", true)
    end

    function instance:GetPropertyChangedSignal(_property: string): any
        return signal()
    end

    function instance:Activate(): ()
        rawset(self, "Activations", (rawget(self, "Activations") or 0) + 1)
    end

    return instance
end

Mock.newInstance = newInstance

-- Globals ------------------------------------------------------------------

-- The globals are handed out as a table rather than written into this file's
-- environment: the Luau CLI sandboxes every module in its own environment, so
-- the only way to give a module file its `Instance`, `Vector3` and `Enum` is to
-- write them into that module's own environment (see `Mock.inject`).
function Mock.install(): MockWorld
    local world: any = {clock = 1000, raycastResult = nil}

    local globals: any = {}

    globals.Instance = {new = newInstance}
    globals.Vector3 = {
        new = vector3,
        zero = vector3(0, 0, 0),
        one = vector3(1, 1, 1),
    }
    globals.Vector2 = {new = vector2, zero = vector2(0, 0)}
    globals.Color3 = {
        new = function(r: number, g: number, b: number): any
            return {R = r, G = g, B = b}
        end,
        fromRGB = function(r: number, g: number, b: number): any
            return {R = r / 255, G = g / 255, B = b / 255}
        end,
    }
    globals.UDim = {
        new = function(scale: number, offset: number): any
            return {Scale = scale, Offset = offset}
        end,
    }
    globals.UDim2 = {
        new = function(xs: number, xo: number, ys: number, yo: number): any
            return {X = {Scale = xs, Offset = xo}, Y = {Scale = ys, Offset = yo}}
        end,
        fromOffset = function(x: number, y: number): any
            return {X = {Scale = 0, Offset = x}, Y = {Scale = 0, Offset = y}}
        end,
        fromScale = function(x: number, y: number): any
            return {X = {Scale = x, Offset = 0}, Y = {Scale = y, Offset = 0}}
        end,
    }

    local function enumFolder(names: {string}): any
        local folder: any = {}
        for _, name: string in ipairs(names) do
            folder[name] = {Name = name, Value = name}
        end
        return folder
    end
    globals.Enum = {
        KeyCode = enumFolder({"Unknown", "Space", "LeftControl", "E", "Q"}),
        RaycastFilterType = enumFolder({"Exclude", "Include"}),
        HighlightDepthMode = enumFolder({"AlwaysOnTop", "Occluded"}),
        TextXAlignment = enumFolder({"Center", "Left", "Right"}),
        HumanoidStateType = enumFolder({"Jumping", "Freefall", "Running"}),
        EasingStyle = enumFolder({"Quad", "Sine", "Linear"}),
        EasingDirection = enumFolder({"Out", "In", "InOut"}),
        Material = enumFolder({"Air", "Plastic"}),
        UserInputType = enumFolder({
            "Touch",
            "MouseButton1",
            "MouseButton2",
            "Keyboard",
        }),
        ScaleType = enumFolder({"Crop", "Fit", "Stretch"}),
    }

    globals.CFrame = {
        new = function(x: any, y: number?, z: number?): any
            if type(x) == "number" then
                return cframe(vector3(x, y or 0, z or 0))
            end
            return cframe(x)
        end,
        lookAt = function(from: any, to: any): any
            local delta: any = to - from
            local magnitude: number = delta.Magnitude
            return cframe(from, magnitude > 0 and delta.Unit or vector3(0, 0, -1))
        end,
        identity = cframe(vector3(0, 0, 0)),
    }

    globals.OverlapParams = {
        new = function(): any
            return {FilterType = nil, FilterDescendantsInstances = {}}
        end,
    }

    -- Melee weapons damage through touch events; the mock counts the calls so
    -- a test can prove Kill Aura fired contact on the right parts.
    world.touchFires = 0
    globals.firetouchinterest = function(_handle: any, _part: any, _state: number): ()
        world.touchFires += 1
    end

    globals.RaycastParams = {
        new = function(): any
            return {
                FilterType = nil,
                FilterDescendantsInstances = {},
                IgnoreWater = false,
            }
        end,
    }

    local camera: any = newInstance("Camera")
    camera.CFrame = {
        Position = vector3(0, 5, 0),
        LookVector = vector3(0, 0, -1),
        RightVector = vector3(1, 0, 0),
    }
    camera.ViewportSize = vector2(1280, 720)
    function camera:WorldToViewportPoint(position: any): (any, boolean)
        -- Straight-line projection: enough for the ESP to compute a box, and
        -- deterministic, which a perspective divide would not be.
        return vector3(640 + position.X * 10, 360 - position.Y * 10, position.Z),
            position.Z <= 0
    end
    -- Screen space includes the top bar; viewport space does not. Click
    -- Teleport has to use this one, so the mock keeps them distinguishable.
    function camera:ScreenPointToRay(x: number, y: number): any
        world.lastRayCall = "ScreenPointToRay"
        return {
            Origin = self.CFrame.Position,
            Direction = vector3((x - 640) / 640, (396 - y) / 360, -1),
        }
    end
    function camera:ViewportPointToRay(x: number, y: number): any
        world.lastRayCall = "ViewportPointToRay"
        return {
            Origin = self.CFrame.Position,
            Direction = vector3((x - 640) / 640, (360 - y) / 360, -1),
        }
    end

    local mockWorkspace: any = newInstance("Workspace")
    mockWorkspace.CurrentCamera = camera
    mockWorkspace.Gravity = 196.2
    function mockWorkspace:Raycast(_origin: any, _direction: any, _params: any): any
        return world.raycastResult
    end
    function mockWorkspace:GetPartBoundsInBox(_pivot: any, _size: any, params: any): {any}
        local found: {any} = {}
        for _, instance: any in ipairs(params.FilterDescendantsInstances or {}) do
            for _, child: any in ipairs(instance:GetChildren()) do
                if child.ClassName == "Part" then
                    table.insert(found, child)
                end
            end
        end
        return found
    end

    globals.workspace = mockWorkspace
    globals.game = {
        PlaceId = 0,
        JobId = "test",
        GetService = function(_self: any, name: string): any
            return newInstance(name)
        end,
        HttpGet = function(): string
            return ""
        end,
    }
    globals.warn = function(...: any): ()
        print("[warn]", ...)
    end
    globals.typeof = function(value: any): string
        local raw: string = type(value)
        if raw == "table" and rawget(value, "ClassName") ~= nil then
            return "Instance"
        end
        return raw
    end

    globals.task = {
        spawn = function(callback: any, ...: any): ()
            callback(...)
        end,
        delay = function(_seconds: number, callback: any, ...: any): ()
            callback(...)
        end,
        wait = function(): number
            return 0
        end,
    }

    -- Deterministic time: tests advance the clock themselves so a delay can be
    -- asserted rather than slept through. The standard `os` table is frozen,
    -- so the global is replaced with one that falls through to it.
    local standardOs: any = os
    globals.os = setmetatable({
        clock = function(): number
            return world.clock
        end,
    }, {__index = standardOs})
    globals.math = math
    globals.table = table
    globals.string = string
    globals.pairs = pairs
    globals.ipairs = ipairs
    globals.pcall = pcall
    globals.select = select
    globals.type = type
    globals.tostring = tostring
    globals.tonumber = tonumber
    globals.setmetatable = setmetatable
    globals.getmetatable = getmetatable
    globals.rawget = rawget
    globals.rawset = rawset
    globals.print = print
    globals.error = error
    globals.assert = assert
    globals.next = next
    globals.unpack = unpack
    globals.getfenv = getfenv

    -- Players ---------------------------------------------------------------

    local playersService: any = newInstance("Players")
    playersService.PlayerAdded = signal()
    playersService.PlayerRemoving = signal()
    local roster: {any} = {}

    function playersService:GetPlayers(): {any}
        return table.clone(roster)
    end

    function playersService:GetPlayerFromCharacter(character: any): any
        for _, player: any in ipairs(roster) do
            if player.Character == character then
                return player
            end
        end
        return nil
    end

    local function buildCharacter(name: string, position: any): any
        local character: any = newInstance("Model")
        character.Name = name
        -- Parented like a real character: the entity library treats an
        -- unparented model as a corpse mid-respawn.
        character.Parent = mockWorkspace
        local humanoid: any = newInstance("Humanoid")
        humanoid.Name = "Humanoid"
        humanoid.Health = 100
        humanoid.MaxHealth = 100
        humanoid.Parent = character
        humanoid.HipHeight = 2
        function humanoid:EquipTool(tool: any): ()
            tool.Parent = character
        end
        local root: any = newInstance("Part")
        root.Name = "HumanoidRootPart"
        root.Position = position
        root.CFrame = cframe(position)
        root.AssemblyLinearVelocity = vector3(0, 0, 0)
        root.Parent = character
        local head: any = newInstance("Part")
        head.Name = "Head"
        head.Position = position + vector3(0, 2, 0)
        head.Parent = character
        -- An R15 rig, so the skeleton path has bones to find.
        for _, partName: string in
            ipairs({
                "UpperTorso",
                "LowerTorso",
                "LeftUpperArm",
                "LeftLowerArm",
                "LeftHand",
                "RightUpperArm",
                "RightLowerArm",
                "RightHand",
                "LeftUpperLeg",
                "LeftLowerLeg",
                "LeftFoot",
                "RightUpperLeg",
                "RightLowerLeg",
                "RightFoot",
            })
        do
            local part: any = newInstance("Part")
            part.Name = partName
            part.Position = position
            part.Parent = character
        end
        return character
    end

    function world.addPlayer(name: string, team: any, position: any): any
        local player: any = newInstance("Player")
        player.Name = name
        player.DisplayName = name
        player.Team = team
        player.Neutral = false
        player.CharacterAdded = signal()
        player.Character = buildCharacter(name, position)
        function player:IsFriendsWithAsync(_userId: number): boolean
            return false
        end
        local backpack: any = newInstance("Backpack")
        backpack.Name = "Backpack"
        backpack.Parent = player
        table.insert(roster, player)
        playersService.PlayerAdded:Fire(player)
        return player
    end

    function world.removePlayer(player: any): ()
        local index: number? = table.find(roster, player)
        if index then
            table.remove(roster, index)
        end
        playersService.PlayerRemoving:Fire(player)
    end

    local localPlayer: any = world.addPlayer("LocalTester", "Blue", vector3(0, 0, 0))
    playersService.LocalPlayer = localPlayer

    world.players = playersService
    world.localPlayer = localPlayer
    world.camera = camera
    world.workspace = mockWorkspace
    world.vector3 = vector3
    world.vector2 = vector2
    world.globals = globals
    return (world :: any) :: MockWorld
end

-- Give one module file the mocked globals by writing them into the environment
-- of any function it exported. Every function in that file — including the
-- locals it defined before this call — resolves globals through that same
-- table, so one injection covers the whole module.
function Mock.inject(world: any, fn: any): ()
    local environment: any = getfenv(fn)
    for key: string, value: any in pairs(world.globals) do
        environment[key] = value
    end
end

return Mock
