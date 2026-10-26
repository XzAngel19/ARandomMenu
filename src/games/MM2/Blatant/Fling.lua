export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "MM2 Fling",
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(runtime: any): any
    local host: any = state.frameworkEnvironment
    local core: any = state.mm2Core
    assert(core, "MM2 Fling requires the MM2 core")
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local activity: any = services.activity
    local protectedTargets: any = services.protectedTargets
    local gameBridge: any = services.gameBridge
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addCycleOption: any = host.addCycleOption
    local addToggleOption: any = host.addToggleOption
    local addTextOption: any = host.addTextOption
    local addInformationOption: any = host.addInformationOption
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local findPlayerByText: any = host.findPlayerByText

    local workspace: any = host.workspace
    local RunService: any = host.RunService

    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive

    -- High-impulse velocities modeled after Infinite Yield's walkfling + fling:
    -- pulsed on Heartbeat, reset on RenderStepped (before physics integration),
    -- and micro-oscillated on Stepped so replication never sleeps while the
    -- local character never integrates into the void or NullZone.
    local FLING_PULSE_VEL: Vector3 = Vector3.new(250000, 250000, 250000)
    local FLING_ANGULAR_VEL: Vector3 = Vector3.new(0, 99999, 0)

    local flingRunning: boolean = false
    local walkFlingEnabled: boolean = false
    local flingTargetName: string = ""
    local selectedTargetChoice: string = "Murderer"
    local autoFlingSelected: boolean = false
    local lastAutoFlingAt: number = 0
    local stepPhase: number = 0
    local stepAngle: number = 0
    local stepMovel: number = 0.1

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        activity.set("fling", running or walkFlingEnabled)
    end

    local function waitHeartbeat(): ()
        local ok: boolean = pcall(function(): ()
            if RunService.Heartbeat and RunService.Heartbeat.Wait then
                RunService.Heartbeat:Wait()
            end
        end)
        if not ok then
            task.wait()
        end
    end

    local function waitRenderStepped(): ()
        local ok: boolean = pcall(function(): ()
            if RunService.RenderStepped and RunService.RenderStepped.Wait then
                RunService.RenderStepped:Wait()
            elseif RunService.Heartbeat and RunService.Heartbeat.Wait then
                RunService.Heartbeat:Wait()
            end
        end)
        if not ok then
            task.wait()
        end
    end

    local function waitStepped(): ()
        local ok: boolean = pcall(function(): ()
            if RunService.Stepped and RunService.Stepped.Wait then
                RunService.Stepped:Wait()
            elseif RunService.Heartbeat and RunService.Heartbeat.Wait then
                RunService.Heartbeat:Wait()
            end
        end)
        if not ok then
            task.wait()
        end
    end

    local function forceCharacterFlingPhysics(
        character: Model,
        savedCollide: {[BasePart]: boolean},
        savedProps: {[BasePart]: PhysicalProperties?},
        savedMassless: {[BasePart]: boolean}?
    ): ()
        local heavyProps: PhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
        for _, child: Instance in ipairs(character:GetDescendants()) do
            if child:IsA("BasePart") then
                local part: BasePart = child :: BasePart
                if savedCollide[part] == nil then
                    savedCollide[part] = part.CanCollide
                end
                if savedProps[part] == nil then
                    pcall(function(): ()
                        savedProps[part] = part.CustomPhysicalProperties
                    end)
                end
                if savedMassless and savedMassless[part] == nil then
                    pcall(function(): ()
                        savedMassless[part] = part.Massless
                    end)
                end
                pcall(function(): ()
                    part.CanCollide = false
                    part.CustomPhysicalProperties = heavyProps
                end)
            end
        end
        local rootPart: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            pcall(function(): ()
                rootPart.CanCollide = true
                rootPart.CustomPhysicalProperties = heavyProps
            end)
        end
    end

    local function restoreCharacterPhysics(
        savedCollide: {[BasePart]: boolean},
        savedProps: {[BasePart]: PhysicalProperties?},
        savedMassless: {[BasePart]: boolean}?
    ): ()
        for part: BasePart, wasCollide: boolean in pairs(savedCollide) do
            if part and part.Parent then
                pcall(function(): ()
                    part.CanCollide = wasCollide
                end)
            end
        end
        for part: BasePart, oldProps: PhysicalProperties? in pairs(savedProps) do
            if part and part.Parent then
                pcall(function(): ()
                    part.CustomPhysicalProperties = oldProps
                end)
            end
        end
        if savedMassless then
            for part: BasePart, wasMassless: boolean in pairs(savedMassless) do
                if part and part.Parent then
                    pcall(function(): ()
                        part.Massless = wasMassless
                    end)
                end
            end
            table.clear(savedMassless)
        end
        table.clear(savedCollide)
        table.clear(savedProps)
    end

    local function resolveTargetContactPart(targetChar: Model): BasePart?
        return (targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?)
            or (targetChar:FindFirstChild("UpperTorso") :: BasePart?)
            or (targetChar:FindFirstChild("Torso") :: BasePart?)
            or (targetChar:FindFirstChild("Head") :: BasePart?)
            or targetChar:FindFirstChildWhichIsA("BasePart")
    end

    local function resolveTargetHorizontalVelocity(
        targetPart: BasePart,
        targetHum: Humanoid?
    ): Vector3
        local targetVel: Vector3 = Vector3.zero
        local moveDir: Vector3 = Vector3.zero
        local walkSpeed: number = 16
        pcall(function(): ()
            targetVel = targetPart.AssemblyLinearVelocity
            if targetHum then
                moveDir = targetHum.MoveDirection
                if type(targetHum.WalkSpeed) == "number" and targetHum.WalkSpeed > 0 then
                    walkSpeed = targetHum.WalkSpeed
                end
            end
        end)
        local flatVel: Vector3 = Vector3.new(targetVel.X, 0, targetVel.Z)
        local flatMove: Vector3 = Vector3.new(moveDir.X, 0, moveDir.Z)
        if flatMove.Magnitude > 0.05 then
            local moveVel: Vector3 = flatMove.Unit * math.max(flatVel.Magnitude, walkSpeed)
            if flatVel.Magnitude < 2 then
                flatVel = moveVel
            else
                flatVel = flatVel * 0.65 + moveVel * 0.35
            end
        end
        if flatVel.Magnitude > 40 then
            flatVel = flatVel.Unit * 40
        end
        return flatVel
    end

    local function computePhaseOffset(
        phaseIndex: number,
        flatVel: Vector3,
        verticalVel: number
    ): Vector3
        local isMoving: boolean = flatVel.Magnitude > 1.25
        local leadStep: number = 0
        local bodyOffset: Vector3 = Vector3.zero
        if phaseIndex == 0 then
            leadStep = 0.0
            bodyOffset = Vector3.new(0, 0, 0)
        elseif phaseIndex == 1 then
            leadStep = 0.05
            bodyOffset = Vector3.new(0, 1.25, 0)
        elseif phaseIndex == 2 then
            leadStep = 0.10
            bodyOffset = Vector3.new(0, -1.25, 0)
        elseif phaseIndex == 3 then
            leadStep = 0.16
            bodyOffset = if isMoving
                then Vector3.new(0, 0.3, 0)
                else Vector3.new(1.0, 0.4, -1.0)
        elseif phaseIndex == 4 then
            leadStep = 0.22
            bodyOffset = if isMoving
                then Vector3.new(0, -0.3, 0)
                else Vector3.new(-1.0, -0.4, 1.0)
        else
            leadStep = 0.08
            bodyOffset = Vector3.new(0.6, 0.15, 0.6)
        end

        local leadOffset: Vector3 = flatVel * leadStep
        if leadOffset.Magnitude > 6.5 then
            leadOffset = leadOffset.Unit * 6.5
        end
        local yLead: number = math.clamp(verticalVel * 0.06, -2.0, 2.5)
        return leadOffset + bodyOffset + Vector3.new(0, yLead, 0)
    end

    -- Single-step high-impulse contact sweep (usable from per-frame loops
    -- such as Auto Win's Fling Sheriff and Get Gun).
    local function flingSingleStep(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        targetPlayer: Player,
        savedCollide: {[BasePart]: boolean}?,
        savedProps: {[BasePart]: PhysicalProperties?}?
    ): boolean
        local targetChar: Model? = targetPlayer and targetPlayer.Character
        if not targetChar then
            return false
        end
        local targetHum: Humanoid? = targetChar:FindFirstChildOfClass("Humanoid")
        local targetPart: BasePart? = resolveTargetContactPart(targetChar)
        if not targetPart or (targetHum and targetHum.Health <= 0) then
            return false
        end
        local destroyHeight: number = workspace.FallenPartsDestroyHeight
        if destroyHeight ~= destroyHeight or math.abs(destroyHeight) > 1e6 then
            destroyHeight = -500
        end
        if targetPart.Position.Y <= destroyHeight + 55 then
            return false
        end

        activity.set("fling", true)
        if savedCollide and savedProps then
            forceCharacterFlingPhysics(character, savedCollide, savedProps, nil)
        else
            pcall(function(): ()
                root.CanCollide = true
                root.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
            end)
        end

        stepPhase = (stepPhase + 1) % 6
        stepAngle = (stepAngle + 100) % 360
        stepMovel = -stepMovel
        local flatVel: Vector3 = resolveTargetHorizontalVelocity(targetPart, targetHum)
        local verticalVel: number = 0
        pcall(function(): ()
            verticalVel = targetPart.AssemblyLinearVelocity.Y
        end)
        local totalOffset: Vector3 = computePhaseOffset(stepPhase, flatVel, verticalVel)

        local rotCF: CFrame = CFrame.Angles(
            math.rad(stepAngle),
            math.rad(stepAngle),
            0
        )
        local finalCF: CFrame = CFrame.new(targetPart.Position + totalOffset) * rotCF

        pcall(function(): ()
            if humanoid.Sit then
                humanoid.Sit = false
            end
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
            humanoid.AutoRotate = false
            root.CFrame = finalCF
            character:PivotTo(finalCF)
            root.AssemblyLinearVelocity = FLING_PULSE_VEL + Vector3.new(0, stepMovel, 0)
            root.AssemblyAngularVelocity = FLING_ANGULAR_VEL
        end)
        return true
    end

    -- Target Fling combining Infinite Yield's walkfling Heartbeat->RenderStepped->Stepped
    -- velocity pulse and BodyAngularVelocity spin with tight multi-phase target CFrame lock.
    local function performFling(targetPlayer: Player?, options: {[string]: any}?): boolean
        if not Module.Initialized or not targetPlayer then
            return false
        end
        if protectedTargets.isProtected(targetPlayer) then
            notify("player protected")
            return false
        end
        local silent: boolean = type(options) == "table" and options.silent == true
        local maxDuration: number = (type(options) == "table" and tonumber(options.duration)) or 3.5
        local shouldStop: (() -> boolean)? = type(options) == "table"
            and type(options.shouldStop) == "function"
            and options.shouldStop
            or nil

        if flingRunning then
            if not silent then
                notify("fling already running")
            end
            return false
        end

        setFlingRunning(true)

        local function runFlingRoutine(): boolean
            local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not character or not humanoid or not root then
                setFlingRunning(false)
                if not silent then
                    notify("character not ready")
                end
                return false
            end

            local savedCFrame: CFrame = (type(options) == "table"
                and typeof(options.returnCFrame) == "CFrame"
                and options.returnCFrame)
                or root.CFrame
            local savedAutoRotate: boolean = humanoid.AutoRotate
            local savedDestroyHeight: number = workspace.FallenPartsDestroyHeight
            if savedDestroyHeight ~= savedDestroyHeight or math.abs(savedDestroyHeight) > 1e6 then
                savedDestroyHeight = -500
            end
            local voidThreshold: number = savedDestroyHeight + 45

            local camera: Camera? = workspace.CurrentCamera
            local savedCameraSubject: any = camera and camera.CameraSubject or nil
            local savedCollide: {[BasePart]: boolean} = {}
            local savedProps: {[BasePart]: PhysicalProperties?} = {}
            local savedMassless: {[BasePart]: boolean} = {}
            local bodyAngVel: BodyAngularVelocity? = nil

            local touchedTarget: boolean = false
            local reason: string = "timeout"

            local success: boolean, errorMessage: any = pcall(function(): ()
                local startedAt: number = os.clock()
                local angle: number = 0
                local movel: number = 0.1
                local phaseIdx: number = 0

                local initialTargetChar: Model? = targetPlayer.Character
                local initialTargetPart: BasePart? = initialTargetChar
                    and resolveTargetContactPart(initialTargetChar)
                local initialTargetPos: Vector3 = initialTargetPart
                    and initialTargetPart.Position
                    or root.Position

                pcall(function(): ()
                    workspace.FallenPartsDestroyHeight = 0 / 0
                end)

                humanoid.AutoRotate = false
                if humanoid.Sit then
                    humanoid.Sit = false
                end
                pcall(function(): ()
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                end)

                -- Infinite Yield fling BodyAngularVelocity spin (lines 17673-17679)
                pcall(function(): ()
                    local bav: BodyAngularVelocity = Instance.new("BodyAngularVelocity")
                    bav.Name = "WurstFlingBAV"
                    bav.AngularVelocity = Vector3.new(0, 99999, 0)
                    bav.MaxTorque = Vector3.new(0, math.huge, 0)
                    bav.P = math.huge
                    bav.Parent = root
                    bodyAngVel = bav
                end)

                while flingRunning and os.clock() - startedAt < maxDuration do
                    if shouldStop and shouldStop() then
                        reason = "stopped"
                        break
                    end
                    if targetPlayer.Parent == nil then
                        reason = "left"
                        break
                    end

                    local targetCharacter: Model? = targetPlayer.Character
                    local targetHumanoid: Humanoid? = targetCharacter
                        and targetCharacter:FindFirstChildOfClass("Humanoid")
                        :: Humanoid?
                    local targetPart: BasePart? = targetCharacter
                        and resolveTargetContactPart(targetCharacter)
                    if not targetCharacter or not targetPart or not targetPart.Parent then
                        reason = "gone"
                        break
                    end
                    if targetHumanoid and targetHumanoid.Health <= 0 then
                        touchedTarget = true
                        reason = "killed"
                        break
                    end
                    if targetHumanoid and targetHumanoid.Sit then
                        reason = "seated"
                        break
                    end
                    if targetPart.Position.Y <= voidThreshold or targetPart.Position.Y >= 4000 then
                        touchedTarget = true
                        reason = "void"
                        break
                    end

                    local targetVel: Vector3 = Vector3.zero
                    pcall(function(): ()
                        targetVel = targetPart.AssemblyLinearVelocity
                    end)
                    local targetSpeed: number = targetVel.Magnitude
                    local targetDisplaced: number = (targetPart.Position - initialTargetPos).Magnitude
                    -- Only count as flung early if the target has actually been
                    -- launched far away (>130 studs) at high speed (>450 studs/s),
                    -- so indoor wall/ceiling bounces never abort the fling!
                    if targetSpeed > 450 and targetDisplaced > 130 then
                        touchedTarget = true
                        reason = "flung"
                        break
                    end

                    local liveChar: Model?, liveHumanoid: Humanoid?, liveRoot: BasePart? =
                        getCharacterParts()
                    if not liveChar or not liveHumanoid or not liveRoot or liveHumanoid.Health <= 0 then
                        reason = "died"
                        break
                    end
                    if liveRoot ~= root or liveHumanoid ~= humanoid or liveRoot.Anchored then
                        reason = "died"
                        break
                    end

                    if camera and targetHumanoid then
                        pcall(function(): ()
                            camera.CameraSubject = targetHumanoid
                        end)
                    end

                    forceCharacterFlingPhysics(liveChar, savedCollide, savedProps, savedMassless)

                    pcall(function(): ()
                        (targetPart :: any):SetNetworkOwner(LocalPlayer)
                    end)

                    phaseIdx = (phaseIdx + 1) % 6
                    angle = (angle + 100) % 360
                    local rotCF: CFrame = CFrame.Angles(math.rad(angle), math.rad(angle), 0)
                    local flatVel: Vector3 = resolveTargetHorizontalVelocity(targetPart, targetHumanoid)
                    local offsetVec: Vector3 = computePhaseOffset(phaseIdx, flatVel, targetVel.Y)
                    local contactCF: CFrame = CFrame.new(targetPart.Position + offsetVec) * rotCF

                    -- Step 1: Position on target & wait for Heartbeat, then pulse velocity
                    -- exactly like Infinite Yield's walkfling (lines 17765-17792).
                    pcall(function(): ()
                        if bodyAngVel then
                            bodyAngVel.AngularVelocity = Vector3.new(0, 99999, 0)
                        end
                        liveRoot.CFrame = contactCF
                        liveChar:PivotTo(contactCF)
                    end)
                    waitHeartbeat()

                    if not flingRunning or not liveRoot.Parent or not targetPart.Parent then
                        break
                    end

                    pcall(function(): ()
                        local dirVec: Vector3 = if flatVel.Magnitude > 1
                            then flatVel.Unit
                            else Vector3.new(1, 1, 1)
                        liveRoot.Velocity = dirVec * 250000 + Vector3.new(0, 250000, 0)
                        liveRoot.AssemblyLinearVelocity = dirVec * 250000 + Vector3.new(0, 250000, 0)
                        liveRoot.AssemblyAngularVelocity = FLING_ANGULAR_VEL
                    end)

                    -- Step 2: Wait for RenderStepped and immediately zero velocity
                    -- BEFORE Stepped/Physics integrates our local character!
                    waitRenderStepped()
                    if liveRoot and liveRoot.Parent and targetPart and targetPart.Parent then
                        pcall(function(): ()
                            liveRoot.Velocity = Vector3.zero
                            liveRoot.AssemblyLinearVelocity = Vector3.zero
                            liveRoot.CFrame = contactCF
                            liveChar:PivotTo(contactCF)
                        end)
                    end

                    -- Step 3: Wait for Stepped and apply micro-oscillation (+/- 0.1 Y)
                    -- so network replication stays awake.
                    waitStepped()
                    if liveRoot and liveRoot.Parent then
                        pcall(function(): ()
                            liveRoot.Velocity = Vector3.new(0, movel, 0)
                            liveRoot.AssemblyLinearVelocity = Vector3.new(0, movel, 0)
                            movel = -movel
                        end)
                    end
                end
            end)

            if bodyAngVel then
                pcall(function(): ()
                    bodyAngVel:Destroy()
                end)
                bodyAngVel = nil
            end

            restoreCharacterPhysics(savedCollide, savedProps, savedMassless)

            local finalChar: Model?, finalHumanoid: Humanoid?, finalRoot: BasePart? =
                getCharacterParts()
            if finalHumanoid then
                pcall(function(): ()
                    finalHumanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
                    finalHumanoid.PlatformStand = false
                    finalHumanoid.AutoRotate = savedAutoRotate
                    finalHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
                if camera then
                    pcall(function(): ()
                        camera.CameraSubject = savedCameraSubject or finalHumanoid
                    end)
                end
            end
            if finalChar and finalRoot and finalRoot.Parent then
                local returnCF: CFrame = savedCFrame
                for _ = 1, 5 do
                    pcall(function(): ()
                        for _, part: Instance in ipairs(finalChar:GetDescendants()) do
                            if part:IsA("BasePart") then
                                (part :: BasePart).Velocity = Vector3.zero;
                                (part :: BasePart).AssemblyLinearVelocity = Vector3.zero;
                                (part :: BasePart).AssemblyAngularVelocity = Vector3.zero
                            end
                        end
                        finalRoot.CFrame = returnCF
                        finalChar:PivotTo(returnCF)
                    end)
                    if (finalRoot.Position - returnCF.Position).Magnitude <= 6 then
                        break
                    end
                    waitHeartbeat()
                end
            end

            pcall(function(): ()
                workspace.FallenPartsDestroyHeight = savedDestroyHeight
            end)

            setFlingRunning(false)
            if not Module.Initialized then
                return touchedTarget
            end
            if not silent then
                if not success then
                    notify("fling failed: " .. tostring(errorMessage))
                elseif touchedTarget then
                    notify("fling complete: " .. targetPlayer.Name .. " went down.")
                elseif reason == "left" then
                    notify("fling stopped: " .. targetPlayer.Name .. " left the game.")
                elseif reason == "gone" then
                    notify("Fling stopped: the target character disappeared.")
                elseif reason == "died" then
                    notify("Fling stopped: your character died.")
                elseif reason == "seated" then
                    notify("Fling stopped: target is seated.")
                else
                    notify(
                        "Fling stopped after "
                            .. string.format("%.0f", maxDuration)
                            .. "s of flight."
                    )
                end
            end
            return touchedTarget
        end

        if type(options) == "table" and options.blocking == true then
            return runFlingRoutine()
        end
        task.spawn(runFlingRoutine)
        return true
    end

    state.mm2PerformFling = performFling
    state.mm2FlingStep = flingSingleStep

    local function refreshRoles(): ()
        if type(state.clearRoleMemo) == "function" then
            pcall(state.clearRoleMemo)
        end
        if type(core.requestRoleRefresh) == "function" then
            pcall(core.requestRoleRefresh, false)
        end
    end

    local function resolveMurdererTarget(): Player?
        refreshRoles()
        if type(getPlayerWeapon) == "function" then
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                    and getPlayerWeapon(player, "Gun", false) == nil
                    and getPlayerWeapon(player, "Knife", false) ~= nil then
                    return player
                end
            end
        end
        if type(findMurderer) == "function" then
            local target: Player? = findMurderer()
            if target
                and target ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(target))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(target, "Gun", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(target)
                    or "Murderer"
                if role ~= "Hero" and role ~= "Sheriff" and role ~= "Dead" then
                    return target
                end
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(player, "Gun", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(player)
                    or nil
                if not role and type(gameBridge.playerRole) == "function" then
                    local okRole: boolean, r: any = pcall(gameBridge.playerRole, player)
                    if okRole then
                        role = r
                    end
                end
                if role == "Murderer" then
                    return player
                end
            end
        end
        return nil
    end

    local function resolveSheriffOrHeroTarget(): Player?
        refreshRoles()
        if type(getPlayerWeapon) == "function" then
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                    and getPlayerWeapon(player, "Knife", false) == nil
                    and getPlayerWeapon(player, "Gun", false) ~= nil then
                    return player
                end
            end
        end
        if type(findSheriff) == "function" then
            local target: Player? = findSheriff()
            if target
                and target ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(target))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(target, "Knife", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(target)
                    or "Sheriff"
                if role ~= "Murderer" and role ~= "Dead" then
                    return target
                end
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(player, "Knife", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(player)
                    or nil
                if not role and type(gameBridge.playerRole) == "function" then
                    local okRole: boolean, r: any = pcall(gameBridge.playerRole, player)
                    if okRole then
                        role = r
                    end
                end
                if role == "Sheriff" or role == "Hero" then
                    return player
                end
            end
        end
        return nil
    end

    local function resolvePlayerByQuery(rawQuery: string): Player?
        local query: string = string.lower(string.gsub(rawQuery or "", "^%s*(.-)%s*$", "%1"))
        if query == "" then
            return nil
        end
        if query == "murderer" or query == "murder" then
            return resolveMurdererTarget()
        end
        if query == "sheriff" or query == "hero" then
            return resolveSheriffOrHeroTarget()
        end
        if type(findPlayerByText) == "function" then
            local okFind: boolean, found: any = pcall(findPlayerByText, rawQuery)
            if okFind and found and found ~= LocalPlayer then
                return found :: Player
            end
        end
        local compactQuery: string = string.gsub(query, "%s+", "")
        local prefixMatch: Player? = nil
        local partialMatch: Player? = nil
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local uName: string = string.lower(tostring(player.Name or ""))
                local dName: string = string.lower(tostring((player :: any).DisplayName or player.Name or ""))
                local uCompact: string = string.gsub(uName, "%s+", "")
                local dCompact: string = string.gsub(dName, "%s+", "")
                if uName == query or dName == query or uCompact == compactQuery or dCompact == compactQuery then
                    return player
                end
                if not prefixMatch and (
                    string.sub(uName, 1, #query) == query
                    or string.sub(dName, 1, #query) == query
                ) then
                    prefixMatch = player
                end
                if not partialMatch and (
                    string.find(uName, query, 1, true) ~= nil
                    or string.find(dName, query, 1, true) ~= nil
                    or string.find(uCompact, compactQuery, 1, true) ~= nil
                    or string.find(dCompact, compactQuery, 1, true) ~= nil
                ) then
                    partialMatch = player
                end
            end
        end
        return prefixMatch or partialMatch
    end

    local function resolveSelectedTargetPlayer(): Player?
        local typed: string = string.gsub(flingTargetName or "", "%s+", "")
        if typed ~= "" then
            local byTyped: Player? = resolvePlayerByQuery(flingTargetName)
            if byTyped then
                return byTyped
            end
        end
        if selectedTargetChoice and selectedTargetChoice ~= "" then
            return resolvePlayerByQuery(selectedTargetChoice)
        end
        return nil
    end

    -- Infinite Yield walkfling loop when the Fling module toggle is turned ON
    local function startWalkFlingLoop(): ()
        task.spawn(function(): ()
            local movel: number = 0.1
            while walkFlingEnabled and Module.Initialized do
                if flingRunning then
                    waitHeartbeat()
                else
                    waitHeartbeat()
                    if not walkFlingEnabled then
                        break
                    end
                    local character: Model?, _humanoid: Humanoid?, root: BasePart? = getCharacterParts()
                    if character and root and root.Parent then
                        local savedVel: Vector3 = root.AssemblyLinearVelocity
                        pcall(function(): ()
                            for _, part: Instance in ipairs(character:GetChildren()) do
                                if part:IsA("BasePart") then
                                    (part :: BasePart).CanCollide = false
                                end
                            end
                            local spike: Vector3 = savedVel * 10000 + Vector3.new(0, 10000, 0)
                            root.Velocity = spike
                            root.AssemblyLinearVelocity = spike
                        end)
                        waitRenderStepped()
                        if character and character.Parent and root and root.Parent then
                            pcall(function(): ()
                                root.Velocity = savedVel
                                root.AssemblyLinearVelocity = savedVel
                            end)
                        end
                        waitStepped()
                        if character and character.Parent and root and root.Parent then
                            pcall(function(): ()
                                local osc: Vector3 = savedVel + Vector3.new(0, movel, 0)
                                root.Velocity = osc
                                root.AssemblyLinearVelocity = osc
                                movel = -movel
                            end)
                        end
                    end
                end
            end
        end)
    end

    local function toggleFlingModule(enabled: boolean): ()
        walkFlingEnabled = enabled == true
        activity.set("fling", walkFlingEnabled or flingRunning)
        if walkFlingEnabled then
            if autoFlingSelected then
                lastAutoFlingAt = 0
            end
            local target: Player? = resolveSelectedTargetPlayer()
            if target and not flingRunning then
                performFling(target, {
                    silent = false,
                    duration = 3.5,
                })
            end
            startWalkFlingLoop()
        else
            local character: Model?, _humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if character and root then
                pcall(function(): ()
                    root.Velocity = Vector3.zero
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end

    local FlingFeature: any = createUniversalFeature(
        "Fling",
        "MM2 only: fling the murderer, sheriff or innocents, or walk-fling on contact",
        2,
        toggleFlingModule,
        {category = true, categoryName = "Exploits", registry = mm2Features, configKey = "MM2.Fling"}
    )

    addActionOption(FlingFeature, "Fling Murderer", function(): ()
        local target: Player? = resolveMurdererTarget()
        if target then
            performFling(target)
        else
            notify("No murderer was found.")
        end
    end)
    addActionOption(FlingFeature, "Fling Sheriff", function(): ()
        local target: Player? = resolveSheriffOrHeroTarget()
        if target then
            performFling(target)
        else
            notify("No sheriff or hero was found.")
        end
    end)
    addActionOption(FlingFeature, "Fling All Innocents", function(): ()
        refreshRoles()
        task.spawn(function(): ()
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player)) then
                    local hasKnife: boolean = type(getPlayerWeapon) == "function"
                        and getPlayerWeapon(player, "Knife", false) ~= nil
                    local hasGun: boolean = type(getPlayerWeapon) == "function"
                        and getPlayerWeapon(player, "Gun", false) ~= nil
                    local role: any = type(getPlayerRole) == "function"
                        and getPlayerRole(player)
                        or nil
                    if not role and type(gameBridge.playerRole) == "function" then
                        local okRole: boolean, r: any = pcall(gameBridge.playerRole, player)
                        if okRole then
                            role = r
                        end
                    end
                    if not hasKnife and not hasGun and role == "Innocent" then
                        performFling(player, {blocking = true})
                        task.wait(0.05)
                    end
                end
            end
        end)
    end)

    local targetChoices: {string} = {"Murderer", "Sheriff"}
    local targetSelectorButton: any = nil

    local function rebuildTargetChoices(): ()
        table.clear(targetChoices)
        table.insert(targetChoices, "Murderer")
        table.insert(targetChoices, "Sheriff")
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and type(player.Name) == "string" and player.Name ~= "" then
                table.insert(targetChoices, player.Name)
            end
        end
    end
    rebuildTargetChoices()

    if type(addCycleOption) == "function" then
        targetSelectorButton = addCycleOption(
            FlingFeature,
            "Select Target",
            targetChoices,
            1,
            function(value: string): ()
                rebuildTargetChoices()
                selectedTargetChoice = value
            end,
            "Select Murderer, Sheriff, or a specific player in the server for Fling and Auto Fling."
        )
    end

    if Players.PlayerAdded then
        featureConnections.MM2FlingPlayerAdded = Players.PlayerAdded:Connect(function(): ()
            rebuildTargetChoices()
        end)
    end
    if Players.PlayerRemoving then
        featureConnections.MM2FlingPlayerRemoving = Players.PlayerRemoving:Connect(function(): ()
            rebuildTargetChoices()
        end)
    end

    local function autoFlingTick(): ()
        if not autoFlingSelected or flingRunning then
            return
        end
        if os.clock() - lastAutoFlingAt < 0.35 then
            return
        end
        local localChar: Model?, localHum: Humanoid?, localRoot: BasePart? = getCharacterParts()
        if not localChar or not localHum or not localRoot or localHum.Health <= 0 then
            return
        end
        local target: Player? = resolveSelectedTargetPlayer()
        if not target or protectedTargets.isProtected(target) then
            return
        end
        if type(isPlayerAlive) == "function" and not isPlayerAlive(target) then
            return
        end
        local targetChar: Model? = target.Character
        local targetHum: Humanoid? = targetChar
            and targetChar:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        local targetPart: BasePart? = targetChar
            and resolveTargetContactPart(targetChar)
        if not targetChar or not targetHum or targetHum.Health <= 0 or targetHum.Sit or not targetPart then
            return
        end
        local destroyHeight: number = workspace.FallenPartsDestroyHeight
        if destroyHeight ~= destroyHeight or math.abs(destroyHeight) > 1e6 then
            destroyHeight = -500
        end
        if targetPart.Position.Y <= destroyHeight + 55 or targetPart.Position.Y >= 4000 then
            return
        end
        lastAutoFlingAt = os.clock()
        performFling(target, {
            silent = true,
            duration = 3.5,
            shouldStop = function(): boolean
                return not autoFlingSelected
            end,
        })
    end

    addTextOption(
        FlingFeature,
        "Target player",
        "",
        function(value: string): ()
            flingTargetName = value
        end,
        false,
        "Exact or partial username / display name (optional if Select Target is used)"
    )
    addActionOption(FlingFeature, "Fling", function(): ()
        local target: Player? = resolveSelectedTargetPlayer()
        if target then
            performFling(target)
        else
            notify("No valid target player was found.")
        end
    end)
    addToggleOption(
        FlingFeature,
        "Auto Fling Selected Target",
        false,
        function(value: boolean): ()
            autoFlingSelected = value == true
            if disconnectFeatureConnection then
                disconnectFeatureConnection("MM2AutoFlingTarget")
            end
            if autoFlingSelected and TaskManager and featureConnections then
                lastAutoFlingAt = 0
                featureConnections.MM2AutoFlingTarget =
                    TaskManager:Connect(autoFlingTick)
                autoFlingTick()
            end
        end,
        "Continuously flings the target chosen in Select Target or Target player whenever they are alive."
    )
    addInformationOption(
        FlingFeature,
        "MM2 only. Choose a role action, select a target in Select Target / Target player, or enable Fling for walk-fling."
    )

    activeCleanup = function(): ()
        autoFlingSelected = false
        walkFlingEnabled = false
        if disconnectFeatureConnection then
            disconnectFeatureConnection("MM2AutoFlingTarget")
            disconnectFeatureConnection("MM2FlingPlayerAdded")
            disconnectFeatureConnection("MM2FlingPlayerRemoving")
        end
        setFlingRunning(false)
        state.mm2PerformFling = nil
        state.mm2FlingStep = nil
        targetSelectorButton = nil
    end
    Module.Initialized = true
    return FlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
