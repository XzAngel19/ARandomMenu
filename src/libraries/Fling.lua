local Module = {
    Name = "FlingPhysics",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: any = nil

-- Fling, implemented the way Infinite Yield does it (the reference the user
-- provided) instead of with bounded velocity pulses.
--
-- Why the old version did nothing: it wrote AssemblyLinearVelocity on the
-- TARGET's parts. The local client does not own another player's assembly, so
-- the replication stream overwrites that write on the very next frame. What
-- actually flings someone in Roblox is your OWN assembly spinning at an extreme
-- angular velocity with an extreme physical density while it touches them: the
-- server trusts your character's motion and the contact resolution carries that
-- energy into the other body.
--
-- So the mechanism is exactly IY's:
--
--   1. CustomPhysicalProperties(density = math.huge) on the local parts.
--   2. CanCollide = false / Massless = true, so the body keeps walking normally
--      and never creates a permanent collider pair (that was also physics cost).
--   3. BodyAngularVelocity on the root at 99999 rad/s, MaxTorque = math.huge.
--
-- Three rules this module enforces on top of IY (v148):
--
--   * Touch is a BURST, not a session. Touching someone spins for 0.15 s and
--     then puts the body back exactly as it was. Between contacts nothing is
--     attached, nothing is pinned and nothing is written, so the player walks,
--     turns and jumps normally with full control. The old continuous spin is
--     what made the body look like it was circling the target (and what kept
--     throwing the flinger).
--   * The character is never rotated toward anybody: no lookAt, no facing, no
--     placement on contact. A directed fling moves the root once and keeps the
--     current orientation.
--   * The flinger is never launched. While the spin delivers the impulse a rigid
--     AlignPosition holds the root in place, and when the burst ends the body's
--     motion is zeroed and any physics drift beyond MAX_DRIFT is undone.
--
-- Everything is restored on OFF, death, respawn and destroy: the constraints are
-- destroyed, density/collision/massless go back to their snapshots.
--
-- CPU: while spinning there is NO per-frame Lua. The burst is two task.wait()
-- sleeps and Touch detection is a Touched listener. The old design ran a
-- PreSimulation + Heartbeat body every frame for the whole session.

function Module.init(context: any): any
    local host: any = context.host or context
    local Players: any = host.Players
    local LocalPlayer: Player = host.LocalPlayer
    local services: any = context.services or host.services
    local activity: any = services and services.activity

    local SPIN_RATE: number = 99999
    local SPIN_ON: number = 0.2
    local SPIN_OFF: number = 0.1
    -- One short burst per contact: long enough for the contact to resolve, short
    -- enough that the player never loses control.
    local TOUCH_BURST: number = 0.15
    -- Between bursts nothing happens; this keeps a crowded hallway from turning
    -- into a permanent spin.
    local TOUCH_COOLDOWN: number = 0.4
    local CONTACT_RANGE: number = 20
    -- A burst may never move the player more than this. Anything beyond it is
    -- physics pushing the flinger, not the player walking, so it is undone.
    local MAX_DRIFT: number = 6
    -- Directed flings hold the player for the delivery window only.
    local HOLD_SECONDS: number = 0.8

    local destroyed: boolean = false
    local currentSession: any = nil
    local touchEnabled: boolean = false
    local touchConnections: {RBXScriptConnection} = {}
    local touchCanTouch: {[BasePart]: boolean} = {}
    local touchCooldownUntil: number = 0

    local spinState: any = nil
    local spinLoopToken: number = 0

    local function setActivity(): ()
        if activity and type(activity.set) == "function" then
            pcall(activity.set, "fling", currentSession ~= nil or touchEnabled)
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

    -- Rotation only: used to move the root without changing which way the
    -- character looks.
    local function orientationOf(frame: CFrame): CFrame
        return frame - frame.Position
    end

    local function desiredPivot(character: Model, root: BasePart): CFrame
        local ok: boolean, frame: any = pcall(function(): any
            return root.CFrame
        end)
        if ok and typeof(frame) == "CFrame" then
            return frame -- current position + current orientation
        end
        local okCharacter: boolean, characterFrame: any = pcall(function(): any
            return character:GetPivot()
        end)
        if okCharacter and typeof(characterFrame) == "CFrame" then
            return characterFrame
        end
        return CFrame.new(root.Position)
    end

    local function releaseSpin(): ()
        spinLoopToken += 1
        local state: any = spinState
        spinState = nil
        if not state then
            return
        end
        if state.constraint then
            pcall(function(): ()
                state.constraint:Destroy()
            end)
        end
        if state.hold then
            pcall(function(): ()
                state.hold:Destroy()
            end)
        end
        if state.holdAttachment then
            pcall(function(): ()
                state.holdAttachment:Destroy()
            end)
        end
        for part: BasePart, snapshot: any in pairs(state.parts) do
            if part.Parent then
                pcall(function(): ()
                    if snapshot.canCollide ~= nil then
                        part.CanCollide = snapshot.canCollide
                    end
                    if snapshot.massless ~= nil then
                        part.Massless = snapshot.massless
                    end
                    if snapshot.properties ~= nil then
                        part.CustomPhysicalProperties = snapshot.properties
                    end
                end)
            end
        end
        table.clear(state.parts)

        -- Give the player their body back: no leftover launch, and if physics
        -- pushed them away during the burst, put them where the burst started.
        local root: BasePart? = state.root
        if not root or not root.Parent then
            return
        end
        pcall(function(): ()
            root.AssemblyLinearVelocity = Vector3.zero
        end)
        if state.driftGuard then
            local startPosition: Vector3? = state.startPosition
            local okDistance: boolean, distance: any = pcall(function(): number
                return startPosition and (root.Position - startPosition).Magnitude or 0
            end)
            if okDistance and type(distance) == "number" and distance > MAX_DRIFT then
                local character: Model? = state.character
                local startFrame: CFrame? = state.startCFrame
                if character and startFrame then
                    pcall(function(): ()
                        character:PivotTo(CFrame.new(startPosition)
                            * orientationOf(startFrame))
                    end)
                end
            end
        end
    end

    -- Holds the local root exactly where it is. RigidityEnabled makes the
    -- attachment a hard position constraint, so the equal-and-opposite impulse
    -- from the contact is absorbed here instead of throwing the local player.
    local function createHold(root: BasePart, position: Vector3): (any?, any?)
        local attachment: any = nil
        local hold: any = nil
        local ok: boolean = pcall(function(): ()
            attachment = Instance.new("Attachment")
            attachment.Name = "WurstFlingHold"
            attachment.Parent = root
            hold = Instance.new("AlignPosition")
            hold.Name = "WurstFlingHold"
            -- OneAttachment aligns Attachment0 with the WORLD position in
            -- `Position`. Leaving that at (0, 0, 0) -- the default -- would drag
            -- the player to the world origin, so it is pinned to the contact.
            hold.Mode = Enum.PositionAlignmentMode.OneAttachment
            hold.Position = position
            hold.Attachment0 = attachment
            hold.ApplyAtCenterOfMass = true
            -- Rigid: no spring, no drift, no tuning.
            hold.RigidityEnabled = true
            hold.Parent = root
        end)
        if not ok or not hold then
            if attachment then
                pcall(function(): ()
                    attachment:Destroy()
                end)
            end
            return nil, nil
        end
        return hold, attachment
    end

    -- IY's fling: infinite density, no collision, massless body, spinning root.
    -- `seconds` bounds the burst; nil means "until the caller releases it".
    local function engageSpin(
        character: Model,
        root: BasePart,
        seconds: number?,
        holdSeconds: number?
    ): boolean
        if spinState and spinState.root ~= root then
            releaseSpin()
        end
        if not spinState then
            local parts: {[BasePart]: any} = {}
            for _, object: Instance in ipairs(character:GetChildren()) do
                if object:IsA("BasePart") then
                    local part: BasePart = object :: BasePart
                    parts[part] = {
                        canCollide = part.CanCollide,
                        massless = part.Massless,
                        properties = part.CustomPhysicalProperties,
                    }
                end
            end
            local constraint: any = nil
            local ok: boolean = pcall(function(): ()
                local body: any = Instance.new("BodyAngularVelocity")
                body.Name = "WurstFlingSpin"
                body.AngularVelocity = Vector3.new(0, SPIN_RATE, 0)
                body.MaxTorque = Vector3.new(0, math.huge, 0)
                body.P = math.huge
                body.Parent = root
                constraint = body
            end)
            if not ok or not constraint then
                for part: BasePart, snapshot: any in pairs(parts) do
                    if part.Parent then
                        pcall(function(): ()
                            part.CanCollide = snapshot.canCollide
                            part.Massless = snapshot.massless
                            part.CustomPhysicalProperties = snapshot.properties
                        end)
                    end
                end
                return false
            end
            for part: BasePart in pairs(parts) do
                pcall(function(): ()
                    -- Exactly IY's call: density, friction, elasticity.
                    part.CustomPhysicalProperties = PhysicalProperties.new(
                        math.huge, 0.3, 0.5
                    )
                    part.CanCollide = false
                    part.Massless = true
                    part.AssemblyLinearVelocity = Vector3.zero
                end)
            end
            local startPosition: Vector3 = root.Position
            local startFrame: CFrame = desiredPivot(character, root)
            local hold: any, holdAttachment: any = createHold(root, startPosition)
            spinState = {
                root = root,
                character = character,
                constraint = constraint,
                hold = hold,
                holdAttachment = holdAttachment,
                holdPosition = startPosition,
                holdUntil = os.clock() + (holdSeconds or HOLD_SECONDS),
                startPosition = startPosition,
                startCFrame = startFrame,
                -- A directed fling may legitimately travel; a touch burst may
                -- not, so that is the one that undoes physics drift.
                driftGuard = seconds ~= nil,
                parts = parts,
            }
        end
        local releaseAt: number? = nil
        if seconds ~= nil then
            releaseAt = os.clock() + math.max(0.05, seconds)
        end
        if spinState then
            spinState.releaseAt = releaseAt
        end

        -- IY's duty cycle: spinning, then stopped, until released.
        spinLoopToken += 1
        local token: number = spinLoopToken
        task.spawn(function(): ()
            while spinState and spinLoopToken == token and not destroyed do
                local state: any = spinState
                local now: number = os.clock()
                if state.releaseAt and now >= state.releaseAt then
                    releaseSpin()
                    return
                end
                -- The pin has a short life of its own; a long fling must not
                -- trap the player in place.
                if state.hold and state.holdUntil and now >= state.holdUntil then
                    pcall(function(): ()
                        state.hold:Destroy()
                    end)
                    if state.holdAttachment then
                        pcall(function(): ()
                            state.holdAttachment:Destroy()
                        end)
                    end
                    state.hold = nil
                    state.holdAttachment = nil
                end
                if state.constraint and state.constraint.Parent then
                    pcall(function(): ()
                        state.constraint.AngularVelocity = Vector3.new(0, SPIN_RATE, 0)
                        -- Kill any drift so the hold never has to fight a
                        -- tanking velocity.
                        if state.root and state.root.Parent then
                            state.root.AssemblyLinearVelocity = Vector3.zero
                        end
                        if state.hold and state.holdPosition then
                            state.hold.Position = state.holdPosition
                        end
                    end)
                end
                task.wait(SPIN_ON)
                if not spinState or spinLoopToken ~= token or destroyed then
                    return
                end
                state = spinState
                if state.constraint and state.constraint.Parent then
                    pcall(function(): ()
                        state.constraint.AngularVelocity = Vector3.zero
                    end)
                end
                task.wait(SPIN_OFF)
            end
        end)
        return true
    end

    local function finishSession(reason: string): ()
        local session: any = currentSession
        if not session then
            return
        end
        currentSession = nil
        releaseSpin()
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            getParts(LocalPlayer)
        if character == session.character and root == session.root and root
            and root.Parent then
            pcall(function(): ()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
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

        -- One contact placement, keeping the current orientation: the character
        -- never turns to face the target.
        local placed: boolean = pcall(function(): ()
            character:PivotTo(CFrame.new(contactPosition)
                * orientationOf(session.returnCFrame))
        end)
        if not placed then
            finishSession("error")
            return false
        end
        if not engageSpin(character, root, nil, HOLD_SECONDS) then
            finishSession("error")
            return false
        end
        local deadline: number = os.clock() + duration
        task.spawn(function(): ()
            while currentSession == session and os.clock() < deadline do
                if type(session.shouldStop) == "function" then
                    local ok: boolean, stop: any = pcall(session.shouldStop)
                    if not ok or stop == true then
                        break
                    end
                end
                -- Death, respawn or a replaced character ends the session
                -- without waiting for the duration or a wrapper check.
                local _, livingHumanoid: Humanoid?, livingRoot: BasePart? =
                    livingParts(LocalPlayer)
                if not livingHumanoid or not livingRoot
                    or livingHumanoid ~= session.humanoid
                    or livingRoot ~= session.root then
                    break
                end
                task.wait(0.05)
            end
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
        if currentSession or spinState then
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
        -- One short burst. No placement, no facing, no pin after it ends: the
        -- player keeps walking and the other body takes the impulse.
        engageSpin(character, root, TOUCH_BURST, TOUCH_BURST)
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
        releaseSpin()
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
            releaseSpin()
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
    function library.isSpinning(): boolean
        return spinState ~= nil
    end
    function library.isHeld(): boolean
        return spinState ~= nil and spinState.hold ~= nil
    end
    function library.destroy(): ()
        if destroyed then
            return
        end
        destroyed = true
        setTouchEnabled(false)
        finishSession("destroyed")
        releaseSpin()
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
