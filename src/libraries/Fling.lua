local Module = {
    Name = "FlingPhysics",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeLibrary: any = nil

-- Shared owner for directed MM2 contact and universal Touch Fling. High
-- velocities exist only between PreSimulation and PostSimulation, so physics
-- can transfer momentum without accumulating a launch on the local assembly.
-- No ownership requests, remotes, camera writes, global destroy-height changes,
-- deprecated body movers or target-humanoid velocity writes are used.
function Module.init(context: any): any
    local host: any = context.host or context
    local RunService: any = host.RunService
    local Players: any = host.Players
    local LocalPlayer: Player = host.LocalPlayer
    local services: any = context.services or host.services
    local activity: any = services and services.activity

    assert(RunService and RunService.PreSimulation and RunService.PostSimulation,
        "Fling physics requires PreSimulation and PostSimulation")

    local currentSession: any = nil
    local pulseBackup: any = nil
    local destroyed: boolean = false

    local touchEnabled: boolean = false
    local touchCharacter: Model? = nil
    local touchConnections: {RBXScriptConnection} = {}
    local touchContacts: {[Player]: number} = {}

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

    local function finishSession(reason: string): ()
        local session: any = currentSession
        if not session then
            return
        end
        currentSession = nil
        if pulseBackup and pulseBackup.kind == "target" then
            restorePulse()
        end

        for part: BasePart, canCollide: boolean in pairs(session.collisions) do
            if part.Parent then
                pcall(function(): ()
                    part.CanCollide = canCollide
                end)
            end
        end
        table.clear(session.collisions)

        local humanoid: Humanoid? = session.humanoid
        if humanoid and humanoid.Parent then
            pcall(function(): ()
                humanoid.AutoRotate = session.autoRotate
                humanoid:SetStateEnabled(
                    Enum.HumanoidStateType.Seated,
                    session.seatedEnabled
                )
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end

        local _, livingHumanoid: Humanoid?, root: BasePart? = livingParts(LocalPlayer)
        if root and livingHumanoid and LocalPlayer.Character == session.character
            and root == session.root then
            pcall(function(): ()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                if reason ~= "lost-local" and session.restorePosition ~= false then
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
            duration = math.clamp(duration, 0.1, 3),
            startedAt = os.clock(),
            collisions = {},
            autoRotate = humanoid.AutoRotate,
            seatedEnabled = seatedEnabled,
        }

        for _, object: Instance in ipairs(character:GetChildren()) do
            if object:IsA("BasePart") then
                local part: BasePart = object :: BasePart
                session.collisions[part] = part.CanCollide
                part.CanCollide = true
            end
        end
        humanoid.AutoRotate = false
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        currentSession = session
        setActivity()
        return true
    end

    local function disconnectTouch(): ()
        for _, connection: RBXScriptConnection in ipairs(touchConnections) do
            connection:Disconnect()
        end
        table.clear(touchConnections)
        table.clear(touchContacts)
        touchCharacter = nil
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
            touchContacts[player] = os.clock()
        end
    end

    local function bindTouchPart(part: BasePart): ()
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
        for _, object: Instance in ipairs(character:GetDescendants()) do
            if object:IsA("BasePart") then
                bindTouchPart(object :: BasePart)
            end
        end
        table.insert(touchConnections, character.DescendantAdded:Connect(function(object: Instance): ()
            if touchEnabled and object:IsA("BasePart") then
                bindTouchPart(object :: BasePart)
            end
        end))
        table.insert(touchConnections, humanoid.Died:Connect(function(): ()
            table.clear(touchContacts)
            if pulseBackup and pulseBackup.kind == "touch" then
                restorePulse()
            end
        end))
    end

    local function setTouchEnabled(enabled: boolean): ()
        local wanted: boolean = enabled == true
        if touchEnabled == wanted then
            return
        end
        touchEnabled = wanted
        if touchEnabled then
            bindTouchCharacter()
        else
            disconnectTouch()
            if pulseBackup and pulseBackup.kind == "touch" then
                restorePulse()
            end
        end
        setActivity()
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
        local contactPosition: Vector3 =
            (session.targetRoot.CFrame * CFrame.new(0, 0, 2.2)).Position
        if not finiteVector(targetPosition) or not finiteVector(contactPosition)
            or not finiteVector(root.Position) then
            finishSession("invalid-target")
            return
        end
        local toContact: Vector3 = contactPosition - root.Position
        local distance: number = toContact.Magnitude
        if not savePulse("target", root) then
            return
        end
        if distance > 4.5 then
            -- Approach through the physics step only. Never solve contact by
            -- teleporting the local assembly to the target every frame.
            local approachSpeed: number = math.min(220, math.max(40, distance * 10))
            root.AssemblyLinearVelocity = toContact.Unit * approachSpeed
            root.AssemblyAngularVelocity = Vector3.zero
            return
        end
        local towards: Vector3 = targetPosition - root.Position
        if towards.Magnitude <= 0.001 then
            towards = session.targetRoot.CFrame.LookVector
        end
        if towards.Magnitude <= 0.001 then
            restorePulse()
            return
        end
        root.AssemblyLinearVelocity = towards.Unit * 180 + Vector3.new(0, 50, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 140, 0)
    end

    local function stepTouch(): ()
        if not touchEnabled or pulseBackup then
            return
        end
        if touchCharacter ~= LocalPlayer.Character then
            bindTouchCharacter()
        end
        local _, humanoid: Humanoid?, root: BasePart? = livingParts(LocalPlayer)
        if not humanoid or not root then
            return
        end

        local now: number = os.clock()
        local contactRoot: BasePart? = nil
        local newest: number = 0
        for player: Player, touchedAt: number in pairs(touchContacts) do
            local _, targetHumanoid: Humanoid?, targetRoot: BasePart? =
                livingParts(player)
            if now - touchedAt <= 0.3 and targetHumanoid and targetRoot
                and (targetRoot.Position - root.Position).Magnitude <= 8 then
                if touchedAt > newest then
                    newest = touchedAt
                    contactRoot = targetRoot
                end
            else
                touchContacts[player] = nil
            end
        end
        if not contactRoot then
            return
        end

        local direction: Vector3 = contactRoot.Position - root.Position
        direction = Vector3.new(direction.X, 0, direction.Z)
        if direction.Magnitude <= 0.001 then
            local look: Vector3 = root.CFrame.LookVector
            direction = Vector3.new(look.X, 0, look.Z)
        end
        if direction.Magnitude <= 0.001 or not savePulse("touch", root) then
            return
        end
        root.AssemblyLinearVelocity = direction.Unit * 150 + Vector3.new(0, 70, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 120, 0)
    end

    local preConnection: RBXScriptConnection = RunService.PreSimulation:Connect(function(): ()
        if destroyed then
            return
        end
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
    local postConnection: RBXScriptConnection = RunService.PostSimulation:Connect(function(): ()
        restorePulse()
    end)
    local characterConnection: RBXScriptConnection = LocalPlayer.CharacterAdded:Connect(function(): ()
        if currentSession then
            finishSession("lost-local")
        end
        if touchEnabled then
            bindTouchCharacter()
        end
    end)

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
        preConnection:Disconnect()
        postConnection:Disconnect()
        characterConnection:Disconnect()
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
