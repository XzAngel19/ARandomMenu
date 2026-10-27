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
-- Why the previous version did nothing: it wrote AssemblyLinearVelocity on the
-- TARGET's parts. The local client does not own another player's assembly, so
-- the replication stream overwrites that write on the very next frame. Nothing
-- visible happens. What actually flings someone in Roblox is your OWN assembly
-- spinning at an extreme angular velocity with an extreme physical density while
-- it touches them: the server trusts your character's motion, and the contact
-- resolution carries that energy into the other body.
--
-- So the mechanism is exactly IY's:
--
--   1. CustomPhysicalProperties(density = math.huge) on the local parts.
--   2. CanCollide = false / Massless = true, so the body keeps walking normally
--      and never creates a permanent collider pair (that was also pure physics
--      cost).
--   3. BodyAngularVelocity on the root at 99999 rad/s, MaxTorque = math.huge.
--   4. Duty cycle 0.2 s spinning / 0.1 s stopped, like `fling` in IY.
--
-- Everything is restored on OFF, death, respawn and destroy: the constraint is
-- destroyed, density/collision/massless go back to their snapshots.
--
-- CPU: while spinning there is NO per-frame Lua. The duty cycle is two
-- task.wait() sleeps, and Touch detection is a Touched listener. The old design
-- ran a PreSimulation + Heartbeat body every frame for the whole session.

function Module.init(context: any): any
    local host: any = context.host or context
    local Players: any = host.Players
    local LocalPlayer: Player = host.LocalPlayer
    local services: any = context.services or host.services
    local activity: any = services and services.activity

    local SPIN_RATE: number = 99999
    local SPIN_ON: number = 0.2
    local SPIN_OFF: number = 0.1
    -- A contact keeps the spin armed for this long, so one bump is enough.
    local CONTACT_SECONDS: number = 0.6
    local CONTACT_RANGE: number = 20

    local destroyed: boolean = false
    local currentSession: any = nil
    local touchEnabled: boolean = false
    local touchCharacter: Model? = nil
    local touchConnections: {RBXScriptConnection} = {}
    local touchContacts: {[Player]: number} = {}
    local touchCanTouch: {[BasePart]: boolean} = {}

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
        for part: BasePart, snapshot: any in pairs(state.parts) do
            if part.Parent then
                pcall(function(): ()
                    if state.savedCollide and snapshot.canCollide ~= nil then
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
    end

    -- IY's fling: infinite density, no collision, massless body, and a spinning
    -- root. Anything the body overlaps is launched.
    local function engageSpin(character: Model, root: BasePart): boolean
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
            spinState = {
                root = root,
                character = character,
                constraint = constraint,
                parts = parts,
                savedCollide = true,
            }
        end
        -- IY's duty cycle: 0.2 s spinning, 0.1 s stopped, until released.
        spinLoopToken += 1
        local token: number = spinLoopToken
        task.spawn(function(): ()
            while spinState and spinLoopToken == token and not destroyed do
                local state: any = spinState
                if state and state.constraint and state.constraint.Parent then
                    pcall(function(): ()
                        state.constraint.AngularVelocity = Vector3.new(0, SPIN_RATE, 0)
                    end)
                end
                task.wait(SPIN_ON)
                if not spinState or spinLoopToken ~= token or destroyed then
                    return
                end
                state = spinState
                if state and state.constraint and state.constraint.Parent then
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

    local function start(target: Player?, options: {[string]: any}?): boolean
        if destroyed or currentSession or not target or target == LocalPlayer then
            return false
        end
        if touchEnabled then
            -- One owner at a time; the directed action wins.
            local previous = touchEnabled
            touchEnabled = false
            local state: any = Module.__touchBinder
            if previous and type(state) == "function" then
                pcall(state, false)
            end
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
        local function finiteVector(value: any): boolean
            local ok: boolean, x: any, y: any, z: any = pcall(function(): any
                return value.X, value.Y, value.Z
            end)
            return ok and type(x) == "number" and type(y) == "number"
                and type(z) == "number" and x == x and y == y and z == z
                and math.abs(x) ~= math.huge and math.abs(y) ~= math.huge
                and math.abs(z) ~= math.huge
        end
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

        -- One contact placement, then the spin does the work (IY does not even
        -- place: it relies on the spin and your own walking).
        local placed: boolean = pcall(function(): ()
            character:PivotTo(CFrame.lookAt(contactPosition, targetPosition))
        end)
        if not placed then
            finishSession("error")
            return false
        end
        if not engageSpin(character, root) then
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
        if not ok or not player or player == LocalPlayer then
            return
        end
        local _, targetHumanoid: Humanoid?, targetRoot: BasePart? = livingParts(player)
        if not targetHumanoid or not targetRoot then
            return
        end
        local _, humanoid: Humanoid?, root: BasePart? = livingParts(LocalPlayer)
        if not humanoid or not root then
            return
        end
        if (targetRoot.Position - root.Position).Magnitude > CONTACT_RANGE then
            return
        end
        touchContacts[player] = os.clock()
        if not spinState or spinState.root ~= root then
            local character: Model? = LocalPlayer.Character
            if character then
                engageSpin(character, root)
            end
        end
        -- The spin stays armed while any contact is fresh; this timer is the
        -- only scheduled work, and it costs nothing until it fires.
        task.delay(CONTACT_SECONDS, function(): ()
            local newest: number = -math.huge
            for _, at: number in pairs(touchContacts) do
                if at > newest then
                    newest = at
                end
            end
            if os.clock() - newest < CONTACT_SECONDS then
                return
            end
            table.clear(touchContacts)
            if touchEnabled and not currentSession then
                releaseSpin()
            end
        end)
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
        table.clear(touchContacts)
        for part: BasePart, canTouch: boolean in pairs(touchCanTouch) do
            if part.Parent then
                pcall(function(): ()
                    part.CanTouch = canTouch
                end)
            end
        end
        table.clear(touchCanTouch)
        touchCharacter = nil
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
            releaseSpin()
        end))
    end

    local setTouchEnabled: (enabled: boolean) -> ()
    setTouchEnabled = function(enabled: boolean): ()
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
