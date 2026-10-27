local Module = {
    Name = "FlingPhysics",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: any = nil

-- Fling, copied from Infinite Yield (the reference the user gave us).
--
-- IY ships two different flings and they are not interchangeable:
--
--   IY `fling` (line 11373) — density = math.huge, noclip, and a
--   BodyAngularVelocity of 99999 rad/s on the LOCAL root, cycled 0.2 s on /
--   0.1 s off. It flings by spinning your own assembly, so the body turns like a
--   top and you lose the controls while it runs. That is the version v146-v148
--   used, and it is exactly what the user kept reporting as "rota horrible y 0%
--   control".
--
--   IY `walkfling` (line 11453) — described in IY itself as "Basically fling but
--   no spinning". Every frame it stores the root velocity, writes
--   `velocity * 1000000 + Vector3.new(0, 1000000, 0)` for exactly one
--   RenderStepped, puts the original velocity back, waits one Stepped and
--   re-applies `velocity + Vector3.new(0, 0.1, 0)`. Nothing spins, nothing is
--   attached, the character never turns, and the player keeps walking: the huge
--   velocity only exists inside the physics step that resolves the contact, so
--   it is never what the server sees your body doing.
--
-- v149 is that second function, used for everything: Touch Fling and the directed
-- flings (Fling Murderer / Sheriff / Innocents / Fling / Auto Fling). Nothing in
-- this file rotates the character, nothing pins it, nothing writes to another
-- player, and there is no constraint left behind between pulses.

function Module.init(context: any): any
    local host: any = context.host or context
    local Players: any = host.Players
    local LocalPlayer: Player = host.LocalPlayer
    local services: any = context.services or host.services
    local activity: any = services and services.activity
    local RunService: any = host.RunService
    if not RunService and host.game and type(host.game.GetService) == "function" then
        local okService: boolean, service: any = pcall(function(): any
            return host.game:GetService("RunService")
        end)
        if okService then
            RunService = service
        end
    end

    -- IY walkfling numbers, literally (line 11470-11486).
    local PULSE_SCALE: number = 1000000
    local PULSE_LIFT: Vector3 = Vector3.new(0, 1000000, 0)
    local PULSE_DRIFT: Vector3 = Vector3.new(0, 0.1, 0)
    -- One contact runs the pulse for a moment; longer than a frame so the contact
    -- is delivered, short enough that the player never stops walking.
    local TOUCH_PULSE: number = 0.18
    local TOUCH_COOLDOWN: number = 0.35
    local CONTACT_RANGE: number = 20

    local destroyed: boolean = false
    local currentSession: any = nil
    local touchEnabled: boolean = false
    local touchConnections: {RBXScriptConnection} = {}
    local touchCanTouch: {[BasePart]: boolean} = {}
    local touchCooldownUntil: number = 0

    -- Only one pulse loop may own the root at a time.
    local pulseToken: number = 0
    local pulseActive: boolean = false

    local renderSignal: any = RunService and RunService.RenderStepped or nil
    local steppedSignal: any = RunService and RunService.Stepped or nil

    local function setActivity(): ()
        if activity and type(activity.set) == "function" then
            pcall(
                activity.set,
                "fling",
                currentSession ~= nil or touchEnabled or pulseActive
            )
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
        local character: Model?, humanoid: Humanoid?, root: BasePart? = getParts(player)
        if not character or not humanoid or not root or humanoid.Health <= 0
            or not root.Parent or root.Anchored then
            return character, humanoid, nil
        end
        return character, humanoid, root
    end

    -- IY waits on frame signals here. `task.wait()` is the fallback so the module
    -- still works when the host does not expose RunService.
    local function waitFrame(signal: any): ()
        if signal and type(signal.Wait) == "function" then
            local ok: boolean = pcall(function(): ()
                signal:Wait()
            end)
            if ok then
                return
            end
        end
        task.wait()
    end

    -- A real Vector3 (and our numeric mock of one) has three numbers in X/Y/Z.
    local function isVector(value: any): boolean
        local ok: boolean, x: any, y: any, z: any = pcall(function(): any
            return value.X, value.Y, value.Z
        end)
        return ok and type(x) == "number" and type(y) == "number"
            and type(z) == "number"
    end

    -- One iteration of IY's walkfling loop. Returns the velocity it restored, or
    -- nil when the root disappeared mid-pulse.
    local function pulseOnce(root: BasePart): Vector3?
        local ok: boolean, velocity: any = pcall(function(): any
            return root.AssemblyLinearVelocity
        end)
        if not ok or not isVector(velocity) or not root.Parent then
            return nil
        end
        pcall(function(): ()
            -- BasePart.Velocity in IY is the deprecated alias of this property.
            root.AssemblyLinearVelocity = velocity * PULSE_SCALE + PULSE_LIFT
        end)
        waitFrame(renderSignal)
        if not root.Parent then
            return nil
        end
        pcall(function(): ()
            root.AssemblyLinearVelocity = velocity
        end)
        waitFrame(steppedSignal)
        if not root.Parent then
            return nil
        end
        pcall(function(): ()
            root.AssemblyLinearVelocity = velocity + PULSE_DRIFT
        end)
        return velocity
    end

    -- IY's loop body, bounded: run pulses until `deadline` or until `shouldStop`.
    -- The player's own velocity is put back when the loop ends, so nothing is
    -- left over and walking resumes untouched.
    local function runPulses(
        root: BasePart,
        seconds: number,
        shouldStop: (() -> boolean)?,
        onFinished: (() -> ())?
    ): ()
        pulseToken += 1
        local token: number = pulseToken
        pulseActive = true
        setActivity()
        task.spawn(function(): ()
            local deadline: number = os.clock() + math.max(0.05, seconds)
            local lastVelocity: Vector3? = nil
            while pulseToken == token and not destroyed
                and os.clock() < deadline do
                if type(shouldStop) == "function" then
                    local okStop: boolean, stop: any = pcall(shouldStop)
                    if not okStop or stop == true then
                        break
                    end
                end
                local restored: Vector3? = pulseOnce(root)
                if not restored then
                    break
                end
                lastVelocity = restored
            end
            if pulseToken == token then
                pulseToken += 1
                pulseActive = false
                if lastVelocity and root.Parent then
                    pcall(function(): ()
                        root.AssemblyLinearVelocity = lastVelocity
                    end)
                end
                setActivity()
                if type(onFinished) == "function" then
                    pcall(onFinished)
                end
            end
        end)
    end

    local function stopPulses(): ()
        pulseToken += 1
        pulseActive = false
    end

    local function finishSession(reason: string): ()
        local session: any = currentSession
        if not session then
            return
        end
        currentSession = nil
        stopPulses()
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            getParts(LocalPlayer)
        if character == session.character and root == session.root and root
            and root.Parent then
            pcall(function(): ()
                if reason ~= "lost-local" and session.restorePosition ~= false
                    and humanoid and humanoid.Health > 0 then
                    session.character:PivotTo(session.returnCFrame)
                end
            end)
        end
        setActivity()
    end

    local function cancel(): ()
        finishSession("cancelled")
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

    local function start(target: Player?, options: {[string]: any}?): boolean
        if destroyed or currentSession or not target or target == LocalPlayer then
            return false
        end
        if touchEnabled then
            -- One owner at a time; the directed action wins.
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
            or not finiteVector(root.Position) then
            return false
        end
        if (targetPosition - root.Position).Magnitude > 650 then
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
        }
        currentSession = session

        -- Get next to the target without touching the orientation: the position
        -- changes, which way the character looks does not.
        local placed: boolean = pcall(function(): ()
            local startCFrame: CFrame = session.returnCFrame
            character:PivotTo(CFrame.new(contactPosition)
                * (startCFrame - startCFrame.Position))
        end)
        if not placed then
            finishSession("error")
            return false
        end

        runPulses(root, duration, function(): boolean
            if type(session.shouldStop) == "function" then
                local okStop: boolean, stop: any = pcall(session.shouldStop)
                if not okStop or stop == true then
                    return true
                end
            end
            if currentSession ~= session then
                return true
            end
            -- Death, respawn or a replaced character ends the session without
            -- waiting for the duration.
            local _, livingHumanoid: Humanoid?, livingRoot: BasePart? =
                livingParts(LocalPlayer)
            return not livingHumanoid or not livingRoot
                or livingHumanoid ~= session.humanoid
                or livingRoot ~= session.root
        end, function(): ()
            if currentSession == session then
                finishSession("completed")
            end
        end)
        setActivity()
        return true
    end

    local function noteTouch(hit: BasePart): ()
        if not touchEnabled or not hit or destroyed then
            return
        end
        if currentSession or pulseActive then
            return
        end
        local now: number = os.clock()
        if now < touchCooldownUntil then
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
        if not ok or not player or player == LocalPlayer then
            return
        end
        local _, targetHumanoid: Humanoid?, targetRoot: BasePart? = livingParts(player)
        if not targetHumanoid or not targetRoot then
            return
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingParts(LocalPlayer)
        if not character or not humanoid or not root then
            return
        end
        if (targetRoot.Position - root.Position).Magnitude > CONTACT_RANGE then
            return
        end
        touchCooldownUntil = now + TOUCH_COOLDOWN
        -- No placement, no spin, no pin: IY's walkfling pulses on the spot the
        -- contact happened, and the player keeps walking through it.
        runPulses(root, TOUCH_PULSE, nil, nil)
    end

    local function bindTouchPart(part: BasePart): ()
        if touchCanTouch[part] ~= nil then
            return
        end
        touchCanTouch[part] = part.CanTouch
        pcall(function(): ()
            part.CanTouch = true
        end)
        table.insert(touchConnections, part.Touched:Connect(noteTouch))
    end

    local function disconnectTouch(): ()
        stopPulses()
        for _, connection: RBXScriptConnection in ipairs(touchConnections) do
            connection:Disconnect()
        end
        table.clear(touchConnections)
        for part: BasePart, canTouch: boolean in pairs(touchCanTouch) do
            if part.Parent then
                pcall(function(): ()
                    part.CanTouch = canTouch
                end)
            end
        end
        table.clear(touchCanTouch)
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
            stopPulses()
        end))
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
        end
        setActivity()
    end
    Module.__touchBinder = function(enabled: boolean): ()
        setTouchEnabled(enabled)
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
    -- The spin is gone; these two stay so a stale caller gets an honest answer
    -- instead of a nil method error.
    function library.isSpinning(): boolean
        return false
    end
    function library.isHeld(): boolean
        return false
    end
    function library.isPulsing(): boolean
        return pulseActive
    end
    function library.destroy(): ()
        if destroyed then
            return
        end
        destroyed = true
        setTouchEnabled(false)
        finishSession("destroyed")
        stopPulses()
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
