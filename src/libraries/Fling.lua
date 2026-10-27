-- v151 · Shared Fling / Touch Fling engine: Infinite Yield's REAL walkfling.
--
-- Source of the mechanism: EdgeIY/infiniteyield `source`, command `walkfling`
-- (official repository, command around line 11835). The exact loop is:
--
--   noclip ON
--   repeat: wait for Heartbeat
--     vel = root.Velocity
--     root.Velocity = vel * 10000 + Vector3.new(0, 10000, 0)
--     wait for RenderStepped; root.Velocity = vel
--     wait for Stepped;      root.Velocity = vel + Vector3.new(0, ±0.1, 0)
--   until OFF
--
-- v149 claimed to copy this but used 1,000,000 instead of 10,000, never
-- inverted `movel`, and omitted the noclip that IY enables with walkfling.
-- v150 replaced it with a small ApplyImpulse, which the live game ignored.
-- v151 restores the complete three-signal sequence. It writes ONLY the local
-- root's velocity (the assembly this client owns), disables local character
-- collisions while active, restores both on OFF, and never touches the target's
-- assembly. There is no spin, density hack, BodyAngularVelocity, constraint,
-- network-ownership call, per-frame CFrame or Touched-listener fan-out.
--
-- `Touch Fling` runs the engine continuously: walk into another character.
-- A directed MM2 `Fling` runs the same engine for one bounded session after a
-- single placement next to the target. Both cannot create two engines.

local Module = {
    Name = "FlingPhysics",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: any = nil

function Module.init(context: any): any
    local host: any = context.host or context
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local RunService: any = host.RunService
    local TaskManager: any = host.TaskManager
    local services: any = context.services or host.services
    local activity: any = services and services.activity
    local clock: () -> number = if type((host :: any).clock) == "function"
        then (host :: any).clock else os.clock

    -- Literal IY walkfling numbers. These are applied to the owned local root
    -- for one physics window, then restored; they are not a sustained speed.
    local VELOCITY_SCALE: number = 10000
    local VELOCITY_LIFT: number = 10000
    local DRIFT: number = 0.1
    local PLACE_DISTANCE: number = 2.2
    local MAX_DURATION: number = 3
    local TOUCH_PULSE: number = 0.18 -- exposed for diagnostics/compat

    local destroyed: boolean = false
    local engineActive: boolean = false
    local touchEnabled: boolean = false
    local currentSession: any = nil
    local sessionTask: any = nil
    local fallbackTask: any = nil

    local stage: number = 0 -- 0 idle, 1 high velocity, 2 restored
    local drift: number = DRIFT
    local baselineRoot: any = nil
    local baselineVelocity: any = nil
    local lastStrategy: string = "idle"

    local originalCollision: {[any]: boolean} = {}
    local cachedCharacter: any = nil
    local cachedParts: {any} = {}
    local connections: {any} = {}

    local function setActivity(): ()
        if activity and type(activity.set) == "function" then
            pcall(activity.set, "fling",
                engineActive or touchEnabled or currentSession ~= nil)
        end
    end

    local function getParts(player: any): (any, any, any)
        local character: any = player and player.Character
        if not character or not character.Parent then
            return nil, nil, nil
        end
        local humanoid: any = nil
        pcall(function(): ()
            if type(character.FindFirstChildOfClass) == "function" then
                humanoid = character:FindFirstChildOfClass("Humanoid")
            end
        end)
        if not humanoid then
            return character, nil, nil
        end
        local root: any = humanoid.RootPart
        if not root and type(character.FindFirstChild) == "function" then
            pcall(function(): ()
                root = character:FindFirstChild("HumanoidRootPart")
            end)
        end
        return character, humanoid, root
    end

    local function livingParts(player: any): (any, any, any)
        local character: any, humanoid: any, root: any = getParts(player)
        if not character or not humanoid or not root or humanoid.Health <= 0
            or not root.Parent or root.Anchored then
            return character, humanoid, nil
        end
        return character, humanoid, root
    end

    local function finiteVector(value: any): boolean
        if type(value) ~= "table" and type(value) ~= "userdata" then
            return false
        end
        local ok: boolean, x: any, y: any, z: any = pcall(function(): any
            return value.X, value.Y, value.Z
        end)
        return ok and type(x) == "number" and type(y) == "number"
            and type(z) == "number" and x == x and y == y and z == z
            and math.abs(x) ~= math.huge and math.abs(y) ~= math.huge
            and math.abs(z) ~= math.huge
    end

    local function readVelocity(root: any): any
        local ok: boolean, value: any = pcall(function(): any
            return (root :: any).Velocity
        end)
        if ok and finiteVector(value) then
            return value
        end
        ok, value = pcall(function(): any
            return (root :: any).AssemblyLinearVelocity
        end)
        if ok and finiteVector(value) then
            return value
        end
        return nil
    end

    -- `Velocity` is IY's property and still works in Roblox; the assembly
    -- alias is written too so an executor that only proxies one of them works.
    local function writeVelocity(root: any, value: any): ()
        if not root or not finiteVector(value) then
            return
        end
        pcall(function(): () (root :: any).Velocity = value end)
        pcall(function(): () (root :: any).AssemblyLinearVelocity = value end)
    end

    local function rebuildParts(character: any): ()
        cachedCharacter = character
        cachedParts = {}
        if not character then
            return
        end
        local list: any = nil
        if type(character.GetDescendants) == "function" then
            pcall(function(): () list = character:GetDescendants() end)
        end
        if type(list) ~= "table" and type(character.GetChildren) == "function" then
            pcall(function(): () list = character:GetChildren() end)
        end
        if type(list) ~= "table" then
            return
        end
        for _, object: any in ipairs(list) do
            local isPart: boolean = false
            pcall(function(): ()
                isPart = type(object.IsA) == "function"
                    and object:IsA("BasePart") == true
            end)
            if isPart then
                table.insert(cachedParts, object)
            end
        end
    end

    local function stripCollisions(character: any): ()
        if cachedCharacter ~= character then
            rebuildParts(character)
        end
        for _, part: any in ipairs(cachedParts) do
            if part and part.Parent then
                local canCollide: any = nil
                pcall(function(): () canCollide = part.CanCollide end)
                if canCollide ~= false then
                    if originalCollision[part] == nil then
                        originalCollision[part] = canCollide ~= false
                    end
                    pcall(function(): () part.CanCollide = false end)
                end
            end
        end
    end

    local function restoreCollisions(): ()
        for part: any, original: boolean in pairs(originalCollision) do
            if part and part.Parent then
                pcall(function(): () part.CanCollide = original end)
            end
        end
        table.clear(originalCollision)
        cachedCharacter = nil
        cachedParts = {}
    end

    local function connectSignal(signal: any, callback: any): ()
        if not signal or type(signal.Connect) ~= "function" then
            return
        end
        local ok: boolean, connection: any = pcall(function(): any
            return signal:Connect(callback)
        end)
        if ok and connection then
            table.insert(connections, connection)
        end
    end

    -- Frame 1 of IY's cycle: after Heartbeat, publish the one-step velocity to
    -- the local assembly. The client owns its character, so this is the only
    -- assembly we write.
    local function onHeartbeat(): ()
        if not engineActive or destroyed or stage ~= 0 then
            return
        end
        local character: any, humanoid: any, root: any = livingParts(LocalPlayer)
        if not character or not humanoid or not root then
            return
        end
        local velocity: any = readVelocity(root)
        if not velocity then
            return
        end
        baselineRoot = root
        baselineVelocity = velocity
        writeVelocity(root,
            velocity * VELOCITY_SCALE + Vector3.new(0, VELOCITY_LIFT, 0))
        stage = 1
        lastStrategy = "walkfling"
    end

    -- Frame 2: RenderStepped restores the real movement velocity.
    local function onRenderStepped(): ()
        if not engineActive or destroyed or stage ~= 1 then
            return
        end
        if baselineRoot and baselineVelocity then
            writeVelocity(baselineRoot, baselineVelocity)
        end
        stage = 2
    end

    -- Frame 3: Stepped adds IY's alternating ±0.1 drift and keeps the local
    -- noclip alive. The server still owns collision resolution for others.
    local function onStepped(): ()
        if not engineActive or destroyed then
            return
        end
        local character: any = LocalPlayer and LocalPlayer.Character or nil
        if character then
            stripCollisions(character)
        end
        if stage == 2 and baselineRoot and baselineVelocity then
            writeVelocity(baselineRoot,
                baselineVelocity + Vector3.new(0, drift, 0))
            drift = -drift
            stage = 0
        elseif stage == 1 and baselineRoot and baselineVelocity then
            -- Host skipped RenderStepped: never leave the spike behind.
            writeVelocity(baselineRoot, baselineVelocity)
            stage = 0
        end
    end

    -- A host without the three RunService signals still advances one stage per
    -- scheduler tick. Production uses the real signals above, not this path.
    local function fallbackTick(): ()
        if not engineActive or destroyed then
            return
        end
        if stage == 0 then
            onHeartbeat()
        elseif stage == 1 then
            onRenderStepped()
        else
            onStepped()
        end
    end

    local heartbeatSignal: any = RunService and RunService.Heartbeat or nil
    local renderSignal: any = RunService and RunService.RenderStepped or nil
    local steppedSignal: any = RunService and RunService.Stepped or nil
    connectSignal(heartbeatSignal, onHeartbeat)
    connectSignal(renderSignal, onRenderStepped)
    connectSignal(steppedSignal, onStepped)
    if LocalPlayer and LocalPlayer.CharacterAdded then
        connectSignal(LocalPlayer.CharacterAdded, function(): ()
            rebuildParts(nil)
        end)
    end

    local function stopEngine(): ()
        if not engineActive then
            return
        end
        engineActive = false
        if baselineRoot and baselineVelocity and baselineRoot.Parent then
            writeVelocity(baselineRoot, baselineVelocity)
        end
        stage = 0
        drift = DRIFT
        baselineRoot = nil
        baselineVelocity = nil
        lastStrategy = "idle"
        restoreCollisions()
        if fallbackTask then
            pcall(function(): () fallbackTask:Disconnect() end)
            fallbackTask = nil
        end
        if sessionTask then
            pcall(function(): () sessionTask:Disconnect() end)
            sessionTask = nil
        end
        setActivity()
    end

    local finishSession: (reason: string) -> ()
    local function sessionTick(): ()
        local session: any = currentSession
        if not session or destroyed then
            return
        end
        if clock() - session.startedAt >= session.duration then
            finishSession("completed")
            return
        end
        if type(session.shouldStop) == "function" then
            local ok: boolean, stop: any = pcall(session.shouldStop)
            if not ok or stop == true then
                finishSession("cancelled")
                return
            end
        end
        local _, targetHumanoid: any, targetRoot: any = livingParts(session.target)
        local _, humanoid: any, root: any = livingParts(LocalPlayer)
        if not targetHumanoid or not targetRoot or not humanoid or not root
            or humanoid ~= session.humanoid or root ~= session.root then
            finishSession("lost-local")
        end
    end

    local function startEngine(): ()
        if engineActive or destroyed then
            return
        end
        engineActive = true
        stage = 0
        drift = DRIFT
        baselineRoot = nil
        baselineVelocity = nil
        local character: any = LocalPlayer and LocalPlayer.Character or nil
        if character then
            rebuildParts(character)
        end
        if not heartbeatSignal or not renderSignal or not steppedSignal then
            if TaskManager and type(TaskManager.Connect) == "function" then
                local ok: boolean, handle: any = pcall(function(): any
                    return TaskManager:Connect(fallbackTick)
                end)
                if ok and handle then
                    fallbackTask = handle
                end
            end
        end
        if TaskManager and type(TaskManager.Connect) == "function"
            and not sessionTask then
            local ok: boolean, handle: any = pcall(function(): any
                return TaskManager:Connect(sessionTick)
            end)
            if ok and handle then
                sessionTask = handle
            end
        end
        setActivity()
    end

    local function maybeStopEngine(): ()
        if not touchEnabled and not currentSession then
            stopEngine()
        else
            setActivity()
        end
    end

    -- One bounded placement, preserving the current look direction. This is
    -- the game's own `PivotTo` mechanism, not a per-frame CFrame writer.
    local function placeNextTo(character: any, root: any, targetRoot: any): ()
        if not character or not root or not targetRoot
            or type(character.PivotTo) ~= "function" then
            return
        end
        local from: any = root.Position
        local to: any = targetRoot.Position
        local away: any = from - to
        local length: number = math.sqrt(away.X * away.X + away.Z * away.Z)
        if length < 0.001 then
            away = Vector3.new(0, 0, 1)
            length = 1
        end
        local contact: any = to + Vector3.new(
            away.X / length * PLACE_DISTANCE, 0,
            away.Z / length * PLACE_DISTANCE)
        local look: any = Vector3.new(0, 0, -1)
        pcall(function(): ()
            local frame: any = root.CFrame
            if frame and finiteVector(frame.LookVector) then
                look = frame.LookVector
            end
        end)
        local destination: any = nil
        pcall(function(): ()
            destination = CFrame.lookAt(contact, contact + look)
        end)
        if not destination then
            destination = CFrame.new(contact)
        end
        pcall(function(): () character:PivotTo(destination) end)
    end

    local function setTouchEnabled(enabled: boolean): ()
        local wanted: boolean = enabled == true
        if touchEnabled == wanted or (destroyed and wanted) then
            return
        end
        touchEnabled = wanted
        if wanted then
            startEngine()
        else
            maybeStopEngine()
        end
        setActivity()
    end
    Module.__touchBinder = function(enabled: boolean): ()
        setTouchEnabled(enabled)
    end

    finishSession = function(reason: string): ()
        local session: any = currentSession
        if not session then
            return
        end
        currentSession = nil
        local character: any, humanoid: any, root: any = getParts(LocalPlayer)
        if character == session.character and root == session.root and root
            and root.Parent and reason ~= "lost-local"
            and session.restorePosition ~= false and humanoid
            and humanoid.Health > 0 then
            pcall(function(): () character:PivotTo(session.returnCFrame) end)
        end
        maybeStopEngine()
        setActivity()
    end

    local function start(target: any, options: any): boolean
        if destroyed or currentSession or not target or target == LocalPlayer then
            return false
        end
        local targetCharacter: any, targetHumanoid: any, targetRoot: any =
            livingParts(target)
        local character: any, humanoid: any, root: any = livingParts(LocalPlayer)
        if not targetCharacter or not targetHumanoid or not targetRoot
            or not character or not humanoid or not root then
            return false
        end
        local settings: any = type(options) == "table" and options or {}
        local duration: number = tonumber(settings.duration) or 2.2
        if duration ~= duration or math.abs(duration) == math.huge then
            duration = 2.2
        end
        duration = math.clamp(duration, 0.1, MAX_DURATION)
        local returnCFrame: any = if typeof(settings.returnCFrame) == "CFrame"
            then settings.returnCFrame else root.CFrame
        local session: any = {
            target = target,
            targetCharacter = targetCharacter,
            targetHumanoid = targetHumanoid,
            targetRoot = targetRoot,
            character = character,
            humanoid = humanoid,
            root = root,
            returnCFrame = returnCFrame,
            restorePosition = settings.restorePosition ~= false,
            shouldStop = settings.shouldStop,
            duration = duration,
            startedAt = clock(),
        }
        currentSession = session
        startEngine()
        if settings.place ~= false then
            placeNextTo(character, root, targetRoot)
        end
        setActivity()
        return true
    end

    local library: any = {}
    function library.start(target: any, options: any): boolean
        return start(target, options)
    end
    function library.cancel(): ()
        if currentSession then
            finishSession("cancelled")
        end
    end
    function library.isRunning(): boolean
        return currentSession ~= nil
    end
    function library.setTouchEnabled(enabled: boolean): ()
        setTouchEnabled(enabled)
    end
    function library.isTouchEnabled(): boolean
        return touchEnabled
    end
    function library.isPulsing(): boolean
        return engineActive
    end
    function library.isSpinning(): boolean
        return false
    end
    function library.isHeld(): boolean
        return false
    end
    function library.lastStrategy(): string
        return lastStrategy
    end
    function library.hasOwnership(): boolean
        return false
    end
    function library.constants(): any
        return {
            velocityScale = VELOCITY_SCALE,
            velocityLift = VELOCITY_LIFT,
            drift = DRIFT,
            touchPulse = TOUCH_PULSE,
            maxDuration = MAX_DURATION,
        }
    end
    function library.destroy(): ()
        if destroyed then
            return
        end
        destroyed = true
        touchEnabled = false
        currentSession = nil
        stopEngine()
        if sessionTask then
            pcall(function(): () sessionTask:Disconnect() end)
            sessionTask = nil
        end
        for _, connection: any in ipairs(connections) do
            if connection and type(connection.Disconnect) == "function" then
                pcall(function(): () connection:Disconnect() end)
            end
        end
        table.clear(connections)
        setActivity()
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = library
    Module.Initialized = true
    return library
end

return Module
