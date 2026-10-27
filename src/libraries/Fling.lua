-- v150 · Shared contact physics, rebuilt from zero.
--
-- Evidence used (see docs/FIXES-v150.md):
--   * TestingStuff/place, source.rbxlx (MM2 placeId 142823291, place version
--     1447): Workspace.Gravity = 196.2, FallenPartsDestroyHeight = -500,
--     TouchesUseCollisionGroups = false. Collision group "Characters" collides
--     with itself, so two live players really do exchange contact impulses.
--   * The RBXL snapshot has 107 `Coin_Server` parts, each with a
--     `TouchInterest` (TouchTransmitter). Server-owned anchored parts cannot
--     change owner (Roblox network-ownership docs); a client-side
--     `firetouchinterest` cannot make the server credit a coin.
--   * Roblox docs: `BasePart:ApplyImpulse()` changes an owned assembly's
--     velocity through the physics solver; `Humanoid:Move()` is overwritten by
--     the default control script; network ownership decides whose physics the
--     server believes.
--
-- Mechanism: a bounded, finite impulse on an assembly we can actually steer.
-- We first try to obtain network ownership of the target's root (only when the
-- executor exposes a real setter AND `GetNetworkOwner()` confirms it). If that
-- is unavailable we apply the impulse to our own root while standing next to
-- the target, so the contact transfers momentum. Nothing spins, nothing is
-- pinned, no CFrame is written per frame, no constraint survives a session and
-- no velocity is left behind.
--
-- This is an offline-verified physics controller. Whether a live MM2 server
-- accepts the resulting knockback still has to be observed in game.

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
    local LocalPlayer: Player = host.LocalPlayer
    local RunService: any = host.RunService
    local TaskManager: any = host.TaskManager
    local services: any = context.services or host.services
    local activity: any = services and services.activity
    local clock: () -> number = if type((host :: any).clock) == "function"
        then (host :: any).clock else os.clock

    -- Finite numbers. Roblox clamps absurd velocities; 1e6-style spikes were
    -- the old design and produced no reproducible knockback for this user.
    local PULSE_SPEED: number = 190        -- studs/s of velocity change
    local PULSE_LIFT: number = 42          -- upward component
    local PULSE_INTERVAL: number = 0.09    -- seconds between impulses
    local RESTORE_AFTER: number = 0.045    -- one physics window for contact
    local TOUCH_PULSE: number = 0.3
    local TOUCH_COOLDOWN: number = 0.45
    local CONTACT_RANGE: number = 16
    local MAX_DURATION: number = 2.5
    local PLACE_DISTANCE: number = 2.4

    local destroyed: boolean = false
    local currentSession: any = nil
    local touchEnabled: boolean = false
    local touchConnections: {any} = {}
    local touchBoundParts: {[any]: boolean} = {}
    local lastTouchAt: number = -math.huge

    local generation: number = 0
    local pulseHandle: any = nil
    local pulseActive: boolean = false
    local pulseOptions: any = nil
    local baselineVelocity: any = nil
    local baselineRoot: any = nil
    local pendingRestore: boolean = false
    local ownedParts: {[any]: boolean} = {}
    local lastStrategy: string = "idle"

    local function setActivity(): ()
        if activity and type(activity.set) == "function" then
            pcall(activity.set, "fling",
                currentSession ~= nil or touchEnabled or pulseActive)
        end
    end

    local function getParts(player: Player?): (Model?, Humanoid?, BasePart?)
        local character: Model? = player and player.Character
        if not character or not character.Parent then
            return nil, nil, nil
        end
        local humanoid: Humanoid? =
            character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then
            return character, nil, nil
        end
        local root: BasePart? = (humanoid.RootPart
            or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
        return character, humanoid, root
    end

    local function livingParts(player: Player?): (Model?, Humanoid?, BasePart?)
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            getParts(player)
        if not character or not humanoid or not root or humanoid.Health <= 0
            or not root.Parent or root.Anchored then
            return character, humanoid, nil
        end
        return character, humanoid, root
    end

    local function finiteVector(value: any): boolean
        local ok: boolean, x: any, y: any, z: any = pcall(function(): any
            return value.X, value.Y, value.Z
        end)
        return ok and type(x) == "number" and type(y) == "number"
            and type(z) == "number" and x == x and y == y and z == z
            and math.abs(x) ~= math.huge and math.abs(y) ~= math.huge
            and math.abs(z) ~= math.huge
    end

    -- Executor-provided ownership setters are optional. A plain `loadstring`
    -- does not have them; in that case the contact path is used instead.
    local function environment(): any
        local ok: boolean, env: any = pcall(getfenv)
        if ok and type(env) == "table" then
            return env
        end
        return _G or {}
    end

    local function ownerSetter(): any
        local env: any = environment()
        local okGenv: boolean, genv: any = pcall(getgenv)
        for _, name: string in ipairs({
            "setnetworkowner", "set_network_owner", "SetNetworkOwner",
            "setnetworkownership",
        }) do
            local candidate: any = env[name]
            if type(candidate) ~= "function" and okGenv and type(genv) == "table" then
                candidate = genv[name]
            end
            if type(candidate) == "function" then
                return candidate
            end
        end
        return nil
    end

    local function releaseOwnership(): ()
        for part: any in pairs(ownedParts) do
            if part and part.Parent then
                pcall(function(): ()
                    if type((part :: any).SetNetworkOwnershipAuto) == "function" then
                        (part :: any):SetNetworkOwnershipAuto()
                    end
                end)
                local setter: any = ownerSetter()
                if setter then
                    pcall(setter, part, nil)
                end
            end
            ownedParts[part] = nil
        end
    end

    local function tryOwn(part: any): boolean
        if not part or not part.Parent or part.Anchored then
            return false
        end
        local setter: any = ownerSetter()
        if setter then
            pcall(setter, part)
            pcall(setter, part, LocalPlayer)
        end
        pcall(function(): ()
            if type((part :: any).SetNetworkOwner) == "function" then
                (part :: any):SetNetworkOwner(LocalPlayer)
            end
        end)
        local ok: boolean, owner: any = pcall(function(): any
            if type((part :: any).GetNetworkOwner) == "function" then
                return (part :: any):GetNetworkOwner()
            end
            return nil
        end)
        if ok and owner == LocalPlayer then
            ownedParts[part] = true
            return true
        end
        return false
    end

    local function impulse(part: any, direction: Vector3, speed: number): boolean
        if not part or not part.Parent then
            return false
        end
        local mass: number = 1
        pcall(function(): ()
            local value: any = (part :: any).AssemblyMass
            if type(value) == "number" and value > 0.05 and value < 1e6 then
                mass = value
            end
        end)
        local delta: Vector3 = direction * speed
        if type((part :: any).ApplyImpulse) == "function" then
            local ok: boolean = pcall(function(): ()
                (part :: any):ApplyImpulse(delta * mass)
            end)
            if ok then
                return true
            end
        end
        return pcall(function(): ()
            local current: any = (part :: any).AssemblyLinearVelocity
            if finiteVector(current) then
                (part :: any).AssemblyLinearVelocity = current + delta
            end
        end) == true
    end

    local function directionTo(from: Vector3, to: Vector3): Vector3
        local flat: Vector3 = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
        if flat.Magnitude < 0.001 then
            return Vector3.new(0, 0.2, -1)
        end
        local unit: Vector3 = flat / flat.Magnitude
        return Vector3.new(unit.X, PULSE_LIFT / PULSE_SPEED, unit.Z)
    end

    local function restoreBaseline(): ()
        pendingRestore = false
        if baselineVelocity and baselineRoot and baselineRoot.Parent then
            pcall(function(): ()
                baselineRoot.AssemblyLinearVelocity = baselineVelocity
            end)
        end
    end

    local function stopPulse(finished: boolean?): ()
        generation += 1
        if pulseHandle then
            pcall(function(): () pulseHandle:Disconnect() end)
            pulseHandle = nil
        end
        local options: any = pulseOptions
        pulseOptions = nil
        pulseActive = false
        restoreBaseline()
        baselineVelocity = nil
        baselineRoot = nil
        releaseOwnership()
        setActivity()
        if finished and options and type(options.onFinished) == "function" then
            pcall(options.onFinished)
        end
    end

    -- One impulse per interval. When ownership is confirmed the impulse goes
    -- straight to the target's assembly; otherwise it goes through our own
    -- root and the documented character-to-character contact.
    local function applyImpulseOnce(options: any): boolean
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingParts(LocalPlayer)
        if not character or not humanoid or not root then
            return false
        end
        local targetRoot: any = options and options.targetRoot
        if not targetRoot or not targetRoot.Parent then
            return false
        end
        if not finiteVector(root.Position) or not finiteVector(targetRoot.Position) then
            return false
        end
        if (targetRoot.Position - root.Position).Magnitude > CONTACT_RANGE * 2
            and not options.owned then
            return false
        end
        if options.owned == nil then
            options.owned = tryOwn(targetRoot)
        end
        local direction: Vector3 = directionTo(root.Position, targetRoot.Position)
        if options.owned then
            lastStrategy = "ownership"
            if impulse(targetRoot, direction, PULSE_SPEED) then
                return true
            end
            options.owned = false
        end
        lastStrategy = "contact"
        if not baselineVelocity then
            local ok: boolean, value: any = pcall(function(): any
                return root.AssemblyLinearVelocity
            end)
            baselineVelocity = (ok and finiteVector(value)) and value or nil
            baselineRoot = root
        end
        local applied: boolean = impulse(root, direction, PULSE_SPEED)
        if applied then
            pendingRestore = true
        end
        return applied
    end

    local function beginPulse(options: any): ()
        if destroyed then
            return
        end
        stopPulse(false)
        generation += 1
        local token: number = generation
        pulseOptions = options
        pulseActive = true
        lastStrategy = "idle"
        setActivity()

        local duration: number = math.clamp(tonumber(options.duration) or 1.2,
            0.1, MAX_DURATION)
        local elapsed: number = 0
        local sinceImpulse: number = PULSE_INTERVAL
        local sinceRestore: number = 0

        local function finish(): ()
            if generation ~= token then
                return
            end
            stopPulse(true)
        end

        local function tick(deltaTime: number): ()
            if generation ~= token or destroyed then
                return
            end
            local dt: number = if type(deltaTime) == "number"
                and deltaTime > 0 and deltaTime < 1 then deltaTime else 1 / 60
            elapsed += dt
            if pendingRestore then
                sinceRestore += dt
                if sinceRestore >= RESTORE_AFTER then
                    sinceRestore = 0
                    restoreBaseline()
                end
            end
            if type(options.shouldStop) == "function" then
                local ok: boolean, stop: any = pcall(options.shouldStop)
                if not ok or stop == true then
                    finish()
                    return
                end
            end
            if elapsed >= duration then
                finish()
                return
            end
            sinceImpulse += dt
            if sinceImpulse >= PULSE_INTERVAL then
                sinceImpulse = 0
                applyImpulseOnce(options)
            end
        end

        if TaskManager and type(TaskManager.Connect) == "function" then
            local ok: boolean, handle: any = pcall(function(): any
                return TaskManager:Connect(tick)
            end)
            if ok and handle then
                pulseHandle = handle
            end
        end
        if not pulseHandle then
            -- Host without the shared scheduler: bounded coroutine fallback.
            task.spawn(function(): ()
                while generation == token and not destroyed do
                    tick(1 / 60)
                    task.wait(1 / 30)
                end
            end)
        end
    end

    local function finishSession(reason: string): ()
        local session: any = currentSession
        if not session then
            return
        end
        currentSession = nil
        stopPulse(false)
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            getParts(LocalPlayer)
        if character == session.character and root == session.root and root
            and root.Parent and reason ~= "lost-local"
            and session.restorePosition ~= false and humanoid
            and humanoid.Health > 0 then
            pcall(function(): ()
                character:PivotTo(session.returnCFrame)
            end)
        end
        setActivity()
    end

    local function cancel(): ()
        local hadSession: boolean = currentSession ~= nil
        finishSession("cancelled")
        if not hadSession then
            -- A standalone Touch pulse has no session object; it still has to
            -- be cancellable by OFF, death or an explicit card action.
            stopPulse(false)
        end
    end

    local function start(target: Player?, options: {[string]: any}?): boolean
        if destroyed or currentSession or not target or target == LocalPlayer then
            return false
        end
        if touchEnabled then
            -- One owner at a time: an explicit directed action wins.
            setTouchEnabled(false)
        end
        local targetCharacter: Model?, targetHumanoid: Humanoid?, targetRoot: BasePart? =
            livingParts(target)
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingParts(LocalPlayer)
        if not targetCharacter or not targetHumanoid or not targetRoot
            or not character or not humanoid or not root then
            return false
        end
        local settings: any = options or {}
        local duration: number = tonumber(settings.duration) or 1.2
        if duration ~= duration or math.abs(duration) == math.huge then
            duration = 1.2
        end
        duration = math.clamp(duration, 0.1, MAX_DURATION)
        if not finiteVector(root.Position) or not finiteVector(targetRoot.Position)
            or (targetRoot.Position - root.Position).Magnitude > 650 then
            return false
        end

        local session: any = {
            target = target,
            targetCharacter = targetCharacter,
            targetHumanoid = targetHumanoid,
            targetRoot = targetRoot,
            character = character,
            humanoid = humanoid,
            root = root,
            returnCFrame = if typeof(settings.returnCFrame) == "CFrame"
                then settings.returnCFrame else root.CFrame,
            restorePosition = settings.restorePosition ~= false,
            shouldStop = settings.shouldStop,
            duration = duration,
            startedAt = clock(),
        }
        currentSession = session

        -- ONE placement, same mechanism MM2 itself uses for TeleportToPart
        -- (CharacterClient.lua calls `character:PivotTo`). Not per frame.
        if settings.place ~= false and typeof(session.returnCFrame) == "CFrame" then
            pcall(function(): ()
                local look: any = (root :: any).LookVector
                local flat: Vector3 = if finiteVector(look)
                    then Vector3.new(look.X, 0, look.Z)
                    else Vector3.new(0, 0, -1)
                if flat.Magnitude < 0.001 then
                    flat = Vector3.new(0, 0, -1)
                end
                local contact: Vector3 = targetRoot.Position
                    - (flat / flat.Magnitude) * PLACE_DISTANCE
                local frame: CFrame = session.returnCFrame
                character:PivotTo(CFrame.new(contact) * (frame - frame.Position))
            end)
        end

        beginPulse({
            duration = duration,
            targetRoot = targetRoot,
            restorePosition = session.restorePosition,
            shouldStop = function(): boolean
                if type(settings.shouldStop) == "function" then
                    local ok: boolean, stop: any = pcall(settings.shouldStop)
                    if not ok or stop == true then
                        return true
                    end
                end
                if currentSession ~= session then
                    return true
                end
                local _, livingHumanoid: Humanoid?, livingRoot: BasePart? =
                    livingParts(LocalPlayer)
                local _, targetLivingHumanoid: Humanoid?, targetLivingRoot: BasePart? =
                    livingParts(target)
                return not livingHumanoid or not livingRoot
                    or livingHumanoid ~= session.humanoid
                    or livingRoot ~= session.root
                    or not targetLivingHumanoid or not targetLivingRoot
            end,
            onFinished = function(): ()
                if currentSession == session then
                    finishSession("completed")
                end
            end,
        })
        setActivity()
        return true
    end

    local function instanceLike(value: any): boolean
        if value == nil then
            return false
        end
        local kind: string = typeof(value)
        return kind == "Instance" or kind == "table" or kind == "userdata"
    end

    local function noteTouch(hit: BasePart): ()
        if not touchEnabled or not hit or destroyed then
            return
        end
        if currentSession or pulseActive then
            return
        end
        local now: number = clock()
        if now - lastTouchAt < TOUCH_COOLDOWN then
            return
        end
        local model: any = hit.Parent
        for _ = 1, 3 do
            if not instanceLike(model) then
                return
            end
            local okHum: boolean, humanoid: any = pcall(function(): any
                return model:FindFirstChildOfClass("Humanoid")
            end)
            if okHum and humanoid then
                break
            end
            model = model.Parent
        end
        if not instanceLike(model) then
            return
        end
        local ok: boolean, player: any = pcall(function(): any
            return Players:GetPlayerFromCharacter(model)
        end)
        if not ok or not player or player == LocalPlayer then
            return
        end
        local _, targetHumanoid: Humanoid?, targetRoot: BasePart? = livingParts(player)
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingParts(LocalPlayer)
        if not targetHumanoid or not targetRoot or not character
            or not humanoid or not root then
            return
        end
        if (targetRoot.Position - root.Position).Magnitude > CONTACT_RANGE then
            return
        end
        lastTouchAt = now
        beginPulse({
            duration = TOUCH_PULSE,
            targetRoot = targetRoot,
            shouldStop = function(): boolean
                return not touchEnabled or currentSession ~= nil
            end,
        })
    end

    local function disconnectTouch(): ()
        for _, connection: any in ipairs(touchConnections) do
            if type(connection) == "table" and type(connection.Disconnect) == "function" then
                pcall(function(): () connection:Disconnect() end)
            end
        end
        table.clear(touchConnections)
        table.clear(touchBoundParts)
    end

    local function bindTouchCharacter(): ()
        disconnectTouch()
        if not touchEnabled then
            return
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingParts(LocalPlayer)
        if not character or not humanoid or not root then
            return
        end
        local function bindPart(part: any): ()
            if touchBoundParts[part] or not part.Parent then
                return
            end
            if type((part :: any).Touched) == "table"
                and type((part :: any).Touched.Connect) == "function" then
                local ok: boolean, connection: any = pcall(function(): any
                    return (part :: any).Touched:Connect(noteTouch)
                end)
                if ok and connection then
                    touchBoundParts[part] = true
                    table.insert(touchConnections, connection)
                end
            end
        end
        local okChildren: boolean, children: any = pcall(function(): any
            return character:GetChildren()
        end)
        if okChildren and type(children) == "table" then
            for _, object: any in ipairs(children) do
                local okIsA: boolean, isPart: any = pcall(function(): any
                    return object:IsA("BasePart")
                end)
                if okIsA and isPart then
                    bindPart(object)
                end
            end
        end
        if type((character :: any).DescendantAdded) == "table" then
            local okAdd: boolean, connection: any = pcall(function(): any
                return (character :: any).DescendantAdded:Connect(function(object: any): ()
                    if not touchEnabled then
                        return
                    end
                    local okIsA: boolean, isPart: any = pcall(function(): any
                        return object:IsA("BasePart")
                    end)
                    if okIsA and isPart then
                        bindPart(object)
                    end
                end)
            end)
            if okAdd and connection then
                table.insert(touchConnections, connection)
            end
        end
        if type((humanoid :: any).Died) == "table" then
            local okDied: boolean, connection: any = pcall(function(): any
                return (humanoid :: any).Died:Connect(function(): ()
                    stopPulse(false)
                end)
            end)
            if okDied and connection then
                table.insert(touchConnections, connection)
            end
        end
    end

    function setTouchEnabled(enabled: boolean): ()
        local wanted: boolean = enabled == true
        if touchEnabled == wanted or (destroyed and wanted) then
            return
        end
        touchEnabled = wanted
        if touchEnabled then
            bindTouchCharacter()
        else
            disconnectTouch()
            stopPulse(false)
        end
        setActivity()
    end
    Module.__touchBinder = function(enabled: boolean): ()
        setTouchEnabled(enabled)
    end

    -- Re-bind after a respawn: Touch must survive a new character model.
    local lifecycleConnection: any = nil
    if LocalPlayer and type((LocalPlayer :: any).CharacterAdded) == "table"
        and type((LocalPlayer :: any).CharacterAdded.Connect) == "function" then
        pcall(function(): ()
            lifecycleConnection =
                (LocalPlayer :: any).CharacterAdded:Connect(function(): ()
                    if touchEnabled then
                        task.defer(bindTouchCharacter)
                    end
                end)
        end)
    end

    local library: any = {}
    function library.start(target: Player?, options: {[string]: any}?): boolean
        return start(target, options)
    end
    function library.cancel(): ()
        cancel()
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
        return pulseActive
    end
    function library.isSpinning(): boolean
        return false
    end
    function library.isHeld(): boolean
        return false
    end
    -- Diagnostics: which documented path the last impulse actually used.
    function library.lastStrategy(): string
        return lastStrategy
    end
    function library.hasOwnership(): boolean
        return next(ownedParts) ~= nil
    end
    function library.constants(): any
        return {
            pulseSpeed = PULSE_SPEED,
            pulseLift = PULSE_LIFT,
            pulseInterval = PULSE_INTERVAL,
            touchPulse = TOUCH_PULSE,
            touchCooldown = TOUCH_COOLDOWN,
            maxDuration = MAX_DURATION,
        }
    end
    function library.destroy(): ()
        if destroyed then
            return
        end
        destroyed = true
        setTouchEnabled(false)
        finishSession("destroyed")
        stopPulse(false)
        if lifecycleConnection then
            pcall(function(): () lifecycleConnection:Disconnect() end)
            lifecycleConnection = nil
        end
        lastStrategy = "idle"
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
