local Module = {
    Name = "FlingPhysics",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: any = nil

-- One owner for directed MM2 contact and universal Touch Fling. A pulse is
-- applied before physics and remains in place through Heartbeat, when the
-- engine has had a chance to simulate/replicate it. There is no always-on
-- loop, target-humanoid writer, ownership request or global physics change.
function Module.init(context: any): any
    local host: any = context.host or context
    local RunService: any = host.RunService
    local Players: any = host.Players
    local LocalPlayer: Player = host.LocalPlayer
    local services: any = context.services or host.services
    local activity: any = services and services.activity

    assert(RunService and RunService.PreSimulation and RunService.Heartbeat,
        "Fling physics requires PreSimulation and Heartbeat")

    local currentSession: any = nil
    local pulseBackup: any = nil
    local destroyed: boolean = false

    local touchEnabled: boolean = false
    local touchCharacter: Model? = nil
    local touchConnections: {RBXScriptConnection} = {}
    local touchContacts: {[Player]: {at: number}} = {}
    local touchCollisions: {[BasePart]: {canCollide: boolean, canTouch: boolean}} = {}
    local touchBoundParts: {[BasePart]: boolean} = {}
    local lastTouchPulseAt: number = -math.huge
    local touchPhysicsActive: boolean = false
    local touchHumanoidBackup: any = nil

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

    local function restorePulse(): ()
        local backup: any = pulseBackup
        pulseBackup = nil
        if backup and backup.root and backup.root.Parent then
            pcall(function(): ()
                backup.root.AssemblyLinearVelocity = backup.linear
                backup.root.AssemblyAngularVelocity = backup.angular
            end)
        end
    end

    local function savePulse(kind: string, root: BasePart): boolean
        if pulseBackup then
            return false
        end
        local linear: Vector3 = root.AssemblyLinearVelocity
        local angular: Vector3 = root.AssemblyAngularVelocity
        if not finiteVector(linear) or not finiteVector(angular) then
            return false
        end
        pulseBackup = {
            kind = kind,
            root = root,
            linear = linear,
            angular = angular,
        }
        return true
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

    -- Idle Touch must not turn the whole avatar into a colliding assembly.
    -- Only a real, recent contact gets physics ownership; the snapshots stay
    -- alive for CanTouch listening and are fully restored on OFF/rebind.
    local function restoreTouchPhysics(): ()
        if not touchPhysicsActive and not touchHumanoidBackup then
            return
        end
        touchPhysicsActive = false
        lastTouchPulseAt = -math.huge
        for part: BasePart, snapshot: any in pairs(touchCollisions) do
            if part.Parent and part.CanCollide ~= snapshot.canCollide then
                pcall(function(): ()
                    part.CanCollide = snapshot.canCollide
                end)
            end
        end
        local backup: any = touchHumanoidBackup
        touchHumanoidBackup = nil
        local humanoid: Humanoid? = backup and backup.humanoid
        if humanoid and humanoid.Parent then
            pcall(function(): ()
                humanoid.AutoRotate = backup.autoRotate
                humanoid.Sit = backup.wasSitting
                humanoid:SetStateEnabled(
                    Enum.HumanoidStateType.Seated,
                    backup.seatedEnabled
                )
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
    end

    local function engageTouchPhysics(humanoid: Humanoid): ()
        local backup: any = touchHumanoidBackup
        if backup and backup.humanoid ~= humanoid then
            restoreTouchPhysics()
            backup = nil
        end
        if not backup then
            local seatedEnabled: boolean = true
            pcall(function(): ()
                seatedEnabled = humanoid:GetStateEnabled(
                    Enum.HumanoidStateType.Seated
                )
            end)
            backup = {
                humanoid = humanoid,
                autoRotate = humanoid.AutoRotate,
                wasSitting = humanoid.Sit,
                seatedEnabled = seatedEnabled,
            }
            touchHumanoidBackup = backup
        end
        touchPhysicsActive = true
        for part: BasePart in pairs(touchCollisions) do
            if part.Parent and not part.CanCollide then
                pcall(function(): ()
                    part.CanCollide = true
                end)
            end
        end
        -- A running Humanoid can overwrite assembly velocities before the
        -- solver uses them. Physics state is therefore part of each contact
        -- pulse, not a one-time toggle-side effect.
        pcall(function(): ()
            humanoid.AutoRotate = false
            humanoid.Sit = false
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
            humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        end)
    end

    local function restoreTouchCollisions(): ()
        for part: BasePart, snapshot: any in pairs(touchCollisions) do
            if part.Parent then
                pcall(function(): ()
                    part.CanCollide = snapshot.canCollide
                    part.CanTouch = snapshot.canTouch
                end)
            end
        end
        table.clear(touchCollisions)
        table.clear(touchBoundParts)
    end

    local function disconnectTouch(): ()
        restoreTouchPhysics()
        if pulseBackup and pulseBackup.kind == "touch" then
            restorePulse()
        end
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
        if pulseBackup and pulseBackup.kind == "target" then
            restorePulse()
        end

        for part: BasePart, snapshot: any in pairs(session.collisions) do
            if part.Parent then
                pcall(function(): ()
                    part.CanCollide = snapshot.canCollide
                    part.CanTouch = snapshot.canTouch
                end)
            end
        end
        table.clear(session.collisions)

        local humanoid: Humanoid? = session.humanoid
        if humanoid and humanoid.Parent then
            pcall(function(): ()
                humanoid.AutoRotate = session.autoRotate
                humanoid.Sit = session.wasSitting
                humanoid:SetStateEnabled(
                    Enum.HumanoidStateType.Seated,
                    session.seatedEnabled
                )
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end

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

        local seatedEnabled: boolean = true
        pcall(function(): ()
            seatedEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Seated)
        end)
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
            collisions = {},
            autoRotate = humanoid.AutoRotate,
            wasSitting = humanoid.Sit,
            seatedEnabled = seatedEnabled,
        }

        for _, object: Instance in ipairs(character:GetChildren()) do
            if object:IsA("BasePart") then
                local part: BasePart = object :: BasePart
                session.collisions[part] = {
                    canCollide = part.CanCollide,
                    canTouch = part.CanTouch,
                }
                part.CanCollide = true
                part.CanTouch = true
            end
        end
        humanoid.AutoRotate = false
        humanoid.Sit = false
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)

        -- A directed action gets one contact placement. It is never a
        -- per-frame CFrame writer; subsequent motion is only the pulse.
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
            touchContacts[player] = {at = os.clock()}
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
        -- Listening requires CanTouch, not a permanent collision change.
        part.CanTouch = true
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
        -- deliberately excluded: they add collision pairs but are not needed
        -- for a body-contact pulse.
        for _, object: Instance in ipairs(character:GetChildren()) do
            if object:IsA("BasePart") then
                bindTouchPart(object :: BasePart)
            end
        end
        table.insert(touchConnections, character.DescendantAdded:Connect(function(object: Instance): ()
            if touchEnabled and object.Parent == character
                and object:IsA("BasePart") then
                bindTouchPart(object :: BasePart)
            end
        end))
        table.insert(touchConnections, humanoid.Died:Connect(function(): ()
            table.clear(touchContacts)
            restoreTouchPhysics()
            if pulseBackup and pulseBackup.kind == "touch" then
                restorePulse()
            end
        end))
    end

    setTouchEnabled = function(enabled: boolean): ()
        local wanted: boolean = enabled == true
        if touchEnabled == wanted or (destroyed and wanted) then
            return
        end
        touchEnabled = wanted
        lastTouchPulseAt = -math.huge
        if touchEnabled then
            ensureRunSignals()
            bindTouchCharacter()
        else
            disconnectTouch()
            if pulseBackup and pulseBackup.kind == "touch" then
                restorePulse()
            end
        end
        setActivity()
        maybeDisconnectRunSignals()
    end

    local function boundedPulse(direction: Vector3, speed: number, lift: number): Vector3
        -- Keep the impulse in the same bounded range as ordinary character
        -- physics. The timing/contact fix must not be replaced by an extreme
        -- velocity spike or by multiplying an already-moving assembly.
        local pulse: Vector3 = Vector3.new(0, lift, 0)
        if direction.Magnitude > 0.001 then
            pulse += direction.Unit * speed
        end
        if not finiteVector(pulse) then
            return Vector3.zero
        end
        if pulse.Magnitude > 250 then
            pulse = pulse.Unit * 250
        end
        return pulse
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
            or direction.Magnitude > 14 then
            finishSession("lost-contact")
            return
        end
        if not savePulse("target", root) then
            return
        end
        root.AssemblyLinearVelocity = boundedPulse(direction, 180, 50)
        root.AssemblyAngularVelocity = Vector3.new(0, 140, 0)
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
            restoreTouchPhysics()
            return
        end

        local now: number = os.clock()
        local contactRoot: BasePart? = nil
        local newest: number = -math.huge
        for player: Player, contact: {at: number} in pairs(touchContacts) do
            local _, targetHumanoid: Humanoid?, targetRoot: BasePart? =
                livingParts(player)
            if now - contact.at <= 0.25 and targetHumanoid and targetRoot
                and (targetRoot.Position - root.Position).Magnitude <= 14 then
                if contact.at > newest then
                    newest = contact.at
                    contactRoot = targetRoot
                end
            else
                touchContacts[player] = nil
            end
        end
        if not contactRoot then
            restoreTouchPhysics()
            return
        end
        if now - lastTouchPulseAt < 1 / 30 then
            return
        end

        local direction: Vector3 = contactRoot.Position - root.Position
        if not finiteVector(direction) then
            restoreTouchPhysics()
            return
        end
        direction = Vector3.new(direction.X, 0, direction.Z)
        if direction.Magnitude <= 0.001 then
            local look: Vector3 = root.CFrame.LookVector
            direction = Vector3.new(look.X, 0, look.Z)
        end
        engageTouchPhysics(humanoid)
        if not savePulse("touch", root) then
            return
        end
        root.AssemblyLinearVelocity = boundedPulse(direction, 150, 70)
        -- Keep the player's own avatar upright and readable on contact. The
        -- old yaw spin made Touch Fling orbit instead of moving normally.
        root.AssemblyAngularVelocity = Vector3.zero
        lastTouchPulseAt = now
    end

    ensureRunSignals = function(): ()
        if preConnection then
            return
        end
        preConnection = RunService.PreSimulation:Connect(function(): ()
            if destroyed then
                return
            end
            -- Also protects against a missed Heartbeat after a character or
            -- executor timing anomaly; no stale pulse crosses two frames.
            restorePulse()
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
                    restorePulse()
                end
            end
        end)
        heartbeatConnection = RunService.Heartbeat:Connect(function(): ()
            if not destroyed then
                restorePulse()
            end
        end)
        characterConnection = LocalPlayer.CharacterAdded:Connect(function(): ()
            if currentSession then
                finishSession("lost-local")
            end
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
        restorePulse()
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
