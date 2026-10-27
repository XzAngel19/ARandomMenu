local Module = {
    Name = "FlingPhysics",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: any = nil

-- One owner for directed MM2 contact and universal Touch Fling.
--
-- A fling is a bounded momentum transfer, NOT a physics takeover of the local
-- avatar. What this library writes:
--
--   * Directed: ONE contact placement of the local character next to the
--     target, then bounded contact pulses. No per-tick CFrame, no
--     PlatformStand, no Humanoid Physics state, no spin.
--   * Contact pulses: a bounded AssemblyLinearVelocity on the touched
--     assembly (the target) and the same bounded pulse on the local root for
--     one physics step. The local root is the assembly the server owns and
--     accepts, so that one step is what carries the momentum into the
--     collision; the target write makes the contact visible immediately.
--
-- It never writes Humanoid state, AutoRotate, Sit, a spin, network ownership
-- or a per-frame velocity on the local root. Those writes are what made
-- earlier builds rotate the player in place instead of flinging the target,
-- and they made the engine rebuild colliding assemblies every frame.

function Module.init(context: any): any
    local host: any = context.host or context
    local RunService: any = host.RunService
    local Players: any = host.Players
    local LocalPlayer: Player = host.LocalPlayer
    local services: any = context.services or host.services
    local activity: any = services and services.activity

    assert(RunService and RunService.PreSimulation and RunService.Heartbeat,
        "Fling physics requires PreSimulation and Heartbeat")

    -- Bounded pulse budgets. The linear result stays below 250 studs/s.
    local DIRECTED_SPEED: number = 170
    local DIRECTED_LIFT: number = 20
    local TOUCH_SPEED: number = 165
    local TOUCH_LIFT: number = 0
    local TARGET_SPEED: number = 200
    local TARGET_LIFT: number = 60
    local PULSE_COOLDOWN: number = 1 / 20
    local CONTACT_SECONDS: number = 0.25
    local CONTACT_RANGE: number = 14
    local LINEAR_LIMIT: number = 250

    local currentSession: any = nil
    local selfPulse: any = nil
    local destroyed: boolean = false

    local touchEnabled: boolean = false
    local touchCharacter: Model? = nil
    local touchConnections: {RBXScriptConnection} = {}
    local touchContacts: {[Player]: {at: number, pulsedAt: number}} = {}
    local touchCollisions: {[BasePart]: {canCollide: boolean, canTouch: boolean}} = {}
    local touchBoundParts: {[BasePart]: boolean} = {}
    local contactCollisionsOwned: boolean = false

    local preConnection: RBXScriptConnection? = nil
    local heartbeatConnection: RBXScriptConnection? = nil
    local characterConnection: RBXScriptConnection? = nil
    local ensureRunSignals: () -> ()
    local setTouchEnabled: (enabled: boolean) -> ()

    local function setActivity(): ()
        if activity and type(activity.set) == "function" then
            pcall(activity.set, "fling", currentSession ~= nil or touchEnabled)
        end
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
        local character: Model?, humanoid: Humanoid?, root: BasePart? = getParts(player)
        if not character or not humanoid or not root or humanoid.Health <= 0
            or not root.Parent or root.Anchored then
            return character, humanoid, nil
        end
        return character, humanoid, root
    end

    -- The bounded impulse both sides of a contact receive.
    local function boundedPulse(direction: Vector3, speed: number, lift: number): Vector3
        local pulse: Vector3 = Vector3.new(0, lift, 0)
        if direction.Magnitude > 0.001 then
            pulse += direction.Unit * speed
        end
        if not finiteVector(pulse) then
            return Vector3.zero
        end
        if pulse.Magnitude > LINEAR_LIMIT then
            pulse = pulse.Unit * LINEAR_LIMIT
        end
        return pulse
    end

    -- One physics step of local momentum. The original velocity is restored on
    -- Heartbeat, so the avatar never keeps drifting or spinning after a touch.
    local function restoreSelfPulse(): ()
        local pulse: any = selfPulse
        selfPulse = nil
        if pulse and pulse.root and pulse.root.Parent then
            pcall(function(): ()
                pulse.root.AssemblyLinearVelocity = pulse.linear
                pulse.root.AssemblyAngularVelocity = pulse.angular
            end)
        end
    end

    local function pulseSelf(root: BasePart, direction: Vector3, speed: number, lift: number): boolean
        if selfPulse and selfPulse.root ~= root then
            restoreSelfPulse()
        end
        if not selfPulse then
            local linear: Vector3 = root.AssemblyLinearVelocity
            local angular: Vector3 = root.AssemblyAngularVelocity
            if not finiteVector(linear) or not finiteVector(angular) then
                return false
            end
            selfPulse = {root = root, linear = linear, angular = angular}
        end
        local ok: boolean = pcall(function(): ()
            root.AssemblyLinearVelocity = boundedPulse(direction, speed, lift)
            -- No spin: the player's body normalises itself on the next frame.
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        if not ok then
            restoreSelfPulse()
        end
        return ok
    end

    -- Momentum handed to the touched assembly. It is deliberately not restored:
    -- that velocity IS the fling, and reconciliation belongs to whoever owns it.
    local function pulseTarget(targetRoot: BasePart, direction: Vector3): boolean
        local pulse: Vector3 = boundedPulse(direction, TARGET_SPEED, TARGET_LIFT)
        if pulse.Magnitude <= 0 then
            return false
        end
        return pcall(function(): ()
            targetRoot.AssemblyLinearVelocity = pulse
            targetRoot.AssemblyAngularVelocity = Vector3.new(0, 25, 0)
        end)
    end

    local function disconnectRunSignals(): ()
        if preConnection then
            preConnection:Disconnect()
            preConnection = nil
        end
        if heartbeatConnection then
            heartbeatConnection:Disconnect()
            heartbeatConnection = nil
        end
        if characterConnection then
            characterConnection:Disconnect()
            characterConnection = nil
        end
    end

    local function maybeDisconnectRunSignals(): ()
        if not currentSession and not touchEnabled then
            disconnectRunSignals()
        end
    end

    -- Contact needs CanTouch (for the listener) and CanCollide (so the shove
    -- actually meets the target's body). Both are snapshot once when Touch is
    -- enabled and restored on OFF/respawn: no per-contact assembly rebuild.
    local function restoreTouchCollisions(): ()
        if contactCollisionsOwned then
            for part: BasePart, snapshot: any in pairs(touchCollisions) do
                if part.Parent then
                    pcall(function(): ()
                        if snapshot.canCollide ~= nil then
                            part.CanCollide = snapshot.canCollide
                        end
                        if snapshot.canTouch ~= nil then
                            part.CanTouch = snapshot.canTouch
                        end
                    end)
                end
            end
            contactCollisionsOwned = false
        end
        table.clear(touchCollisions)
        table.clear(touchBoundParts)
    end

    local function disconnectTouch(): ()
        restoreSelfPulse()
        for _, connection: RBXScriptConnection in ipairs(touchConnections) do
            connection:Disconnect()
        end
        table.clear(touchConnections)
        table.clear(touchContacts)
        touchCharacter = nil
        restoreTouchCollisions()
    end

    local function finishSession(reason: string): ()
        local session: any = currentSession
        if not session then
            return
        end
        currentSession = nil
        restoreSelfPulse()

        local character: Model?, livingHumanoid: Humanoid?, root: BasePart? =
            getParts(LocalPlayer)
        if character == session.character and root == session.root and root
            and root.Parent then
            pcall(function(): ()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                if reason ~= "lost-local" and session.restorePosition ~= false
                    and livingHumanoid and livingHumanoid.Health > 0 then
                    session.character:PivotTo(session.returnCFrame)
                end
            end)
        end
        setActivity()
        maybeDisconnectRunSignals()
    end

    local function cancel(): ()
        finishSession("cancelled")
    end

    local function start(target: Player?, options: {[string]: any}?): boolean
        if destroyed or currentSession or not target or target == LocalPlayer then
            return false
        end
        if touchEnabled then
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
        local duration: number = tonumber(settings.duration) or 1.4
        if duration ~= duration or math.abs(duration) == math.huge then
            duration = 1.4
        end
        duration = math.clamp(duration, 0.1, 3)
        local targetPosition: Vector3 = targetRoot.Position
        local contactPosition: Vector3 =
            (targetRoot.CFrame * CFrame.new(0, 0, 2.2)).Position
        if not finiteVector(targetPosition) or not finiteVector(contactPosition)
            or not finiteVector(root.Position)
            or (targetPosition - root.Position).Magnitude > 650 then
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
            startedAt = os.clock(),
            lastPulseAt = -math.huge,
        }

        -- A directed action gets one contact placement. It is never a
        -- per-frame CFrame writer; the Humanoid is left exactly as it is.
        currentSession = session
        local placed: boolean = pcall(function(): ()
            character:PivotTo(CFrame.lookAt(contactPosition, targetPosition))
        end)
        if not placed then
            finishSession("error")
            return false
        end
        local connected: boolean = pcall(ensureRunSignals)
        if not connected then
            finishSession("error")
            return false
        end
        setActivity()
        return true
    end

    local function noteTouch(hit: BasePart): ()
        if not touchEnabled or not hit then
            return
        end
        local model: any = hit.Parent
        for _ = 1, 3 do
            if not model or typeof(model) ~= "Instance" then
                return
            end
            if model:FindFirstChildOfClass("Humanoid") then
                break
            end
            model = model.Parent
        end
        if not model or typeof(model) ~= "Instance" then
            return
        end
        local ok: boolean, player: any = pcall(function(): any
            return Players:GetPlayerFromCharacter(model)
        end)
        if ok and player and player ~= LocalPlayer then
            local existing: any = touchContacts[player]
            if existing then
                existing.at = os.clock()
            else
                touchContacts[player] = {at = os.clock(), pulsedAt = -math.huge}
            end
        end
    end

    local function bindTouchPart(part: BasePart): ()
        if touchBoundParts[part] then
            return
        end
        touchBoundParts[part] = true
        touchCollisions[part] = {
            canCollide = part.CanCollide,
            canTouch = part.CanTouch,
        }
        -- Listening requires CanTouch; the collider value is what makes the
        -- shove meet the target's body, so it is enabled once below.
        pcall(function(): ()
            part.CanTouch = true
        end)
        table.insert(touchConnections, part.Touched:Connect(noteTouch))
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
        touchCharacter = character
        -- Root and body parts are direct children. Accessory/tool handles are
        -- deliberately excluded: they add collision pairs but not body contact.
        for _, object: Instance in ipairs(character:GetChildren()) do
            if object:IsA("BasePart") then
                bindTouchPart(object :: BasePart)
            end
        end
        -- One snapshot pass: collisions on, once per session.
        contactCollisionsOwned = true
        for part: BasePart in pairs(touchCollisions) do
            if part.Parent and not part.CanCollide then
                pcall(function(): ()
                    part.CanCollide = true
                end)
            end
        end
        table.insert(touchConnections, character.DescendantAdded:Connect(function(object: Instance): ()
            if touchEnabled and object.Parent == character
                and object:IsA("BasePart") then
                bindTouchPart(object :: BasePart)
                if contactCollisionsOwned and not (object :: BasePart).CanCollide then
                    pcall(function(): ()
                        (object :: BasePart).CanCollide = true
                    end)
                end
            end
        end))
        table.insert(touchConnections, humanoid.Died:Connect(function(): ()
            table.clear(touchContacts)
            restoreSelfPulse()
        end))
    end

    setTouchEnabled = function(enabled: boolean): ()
        local wanted: boolean = enabled == true
        if touchEnabled == wanted or (destroyed and wanted) then
            return
        end
        touchEnabled = wanted
        if touchEnabled then
            ensureRunSignals()
            bindTouchCharacter()
        else
            disconnectTouch()
        end
        setActivity()
        maybeDisconnectRunSignals()
    end

    local function stepTarget(session: any): ()
        if os.clock() - session.startedAt >= session.duration then
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
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingParts(LocalPlayer)
        if not character or character ~= session.character or not humanoid
            or humanoid ~= session.humanoid or not root or root ~= session.root then
            finishSession("lost-local")
            return
        end
        if session.target.Parent ~= Players
            or session.target.Character ~= session.targetCharacter
            or session.targetHumanoid.Health <= 0
            or not session.targetRoot.Parent then
            finishSession("lost-target")
            return
        end

        local targetPosition: Vector3 = session.targetRoot.Position
        local direction: Vector3 = targetPosition - root.Position
        if not finiteVector(targetPosition) or not finiteVector(direction)
            or direction.Magnitude > CONTACT_RANGE then
            finishSession("lost-contact")
            return
        end
        local now: number = os.clock()
        if now - session.lastPulseAt < PULSE_COOLDOWN then
            return
        end
        session.lastPulseAt = now
        pulseTarget(session.targetRoot, direction)
        pulseSelf(root, direction, DIRECTED_SPEED, DIRECTED_LIFT)
    end

    local function stepTouch(): ()
        if not touchEnabled then
            return
        end
        if touchCharacter ~= LocalPlayer.Character then
            bindTouchCharacter()
        end
        local _, humanoid: Humanoid?, root: BasePart? = livingParts(LocalPlayer)
        if not humanoid or not root then
            table.clear(touchContacts)
            restoreSelfPulse()
            return
        end

        local now: number = os.clock()
        local pending: {Player} = {}
        for player: Player, contact: {at: number, pulsedAt: number} in pairs(touchContacts) do
            if now - contact.at <= CONTACT_SECONDS then
                table.insert(pending, player)
            else
                touchContacts[player] = nil
            end
        end
        if #pending == 0 then
            return
        end
        for _, player: Player in ipairs(pending) do
            local contact: any = touchContacts[player]
            if contact and now - contact.pulsedAt >= PULSE_COOLDOWN then
                local _, targetHumanoid: Humanoid?, targetRoot: BasePart? =
                    livingParts(player)
                local direction: Vector3? = nil
                if targetHumanoid and targetRoot
                    and (targetRoot.Position - root.Position).Magnitude <= CONTACT_RANGE then
                    direction = targetRoot.Position - root.Position
                end
                if direction and finiteVector(direction) then
                    contact.pulsedAt = now
                    direction = Vector3.new(direction.X, 0, direction.Z)
                    if direction.Magnitude <= 0.001 then
                        local look: Vector3 = root.CFrame.LookVector
                        direction = Vector3.new(look.X, 0, look.Z)
                    end
                    if targetRoot then
                        pulseTarget(targetRoot, direction)
                    end
                    pulseSelf(root, direction, TOUCH_SPEED, TOUCH_LIFT)
                end
            end
        end
    end

    ensureRunSignals = function(): ()
        if preConnection then
            return
        end
        preConnection = RunService.PreSimulation:Connect(function(): ()
            if destroyed then
                return
            end
            -- A second restore point: no stale local pulse survives a physics
            -- step even if Heartbeat is delayed by a hitch.
            if currentSession then
                local session: any = currentSession
                local ok: boolean = pcall(stepTarget, session)
                if not ok and currentSession == session then
                    finishSession("error")
                end
            elseif touchEnabled then
                local ok: boolean = pcall(stepTouch)
                if not ok then
                    setTouchEnabled(false)
                    restoreSelfPulse()
                end
            end
        end)
        heartbeatConnection = RunService.Heartbeat:Connect(function(): ()
            if not destroyed then
                restoreSelfPulse()
            end
        end)
        characterConnection = LocalPlayer.CharacterAdded:Connect(function(): ()
            if currentSession then
                finishSession("lost-local")
            end
            restoreSelfPulse()
            if touchEnabled then
                bindTouchCharacter()
            end
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
    function library.destroy(): ()
        if destroyed then
            return
        end
        destroyed = true
        setTouchEnabled(false)
        finishSession("destroyed")
        restoreSelfPulse()
        disconnectRunSignals()
        setActivity()
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    activeLibrary = library
    Module.Initialized = true
    return library
end

function Module.destroy(): ()
    if activeLibrary then
        activeLibrary.destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
