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
    local addTextOption: any = host.addTextOption
    local addInformationOption: any = host.addInformationOption

    local workspace: any = host.workspace
    local RunService: any = host.RunService

    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive

    local flingRunning: boolean = false
    local flingTargetName: string = ""
    local stepAngle: number = 0

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        activity.set("fling", running)
    end

    local function waitFrameStep(useRenderStep: boolean): ()
        if useRenderStep then
            local okRender: boolean = pcall(function(): ()
                if RunService.RenderStepped and RunService.RenderStepped.Wait then
                    RunService.RenderStepped:Wait()
                elseif RunService.Stepped and RunService.Stepped.Wait then
                    RunService.Stepped:Wait()
                else
                    RunService.Heartbeat:Wait()
                end
            end)
            if not okRender then
                pcall(function(): ()
                    RunService.Heartbeat:Wait()
                end)
            end
        else
            pcall(function(): ()
                RunService.Heartbeat:Wait()
            end)
        end
    end

    local function forceCharacterCollidable(
        character: Model,
        savedCollide: {[BasePart]: boolean},
        savedProps: {[BasePart]: PhysicalProperties?}
    ): ()
        local heavyProps: PhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
        for _, child: Instance in ipairs(character:GetChildren()) do
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
                pcall(function(): ()
                    part.CanCollide = true
                    part.CustomPhysicalProperties = heavyProps
                end)
            end
        end
    end

    local function restoreCharacterPhysics(
        savedCollide: {[BasePart]: boolean},
        savedProps: {[BasePart]: PhysicalProperties?}
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
            forceCharacterCollidable(character, savedCollide, savedProps)
        else
            pcall(function(): ()
                root.CanCollide = true
                root.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
            end)
        end

        stepAngle = (stepAngle + 100) % 360
        local phase: number = math.floor(stepAngle / 100) % 4
        local targetVel: Vector3 = Vector3.zero
        local moveDir: Vector3 = Vector3.zero
        pcall(function(): ()
            targetVel = targetPart.AssemblyLinearVelocity
            if targetHum then
                moveDir = targetHum.MoveDirection
            end
        end)

        local leadOffset: Vector3 = if targetVel.Magnitude > 1.5
            then moveDir * math.clamp(targetVel.Magnitude / 1.25, -18, 18)
                + Vector3.new(targetVel.X * 0.08, 0, targetVel.Z * 0.08)
            else Vector3.zero

        local sweepLocal: CFrame
        if phase == 0 then
            sweepLocal = CFrame.new(0, 1.5, 0)
        elseif phase == 1 then
            sweepLocal = CFrame.new(0, -1.5, 0)
        elseif phase == 2 then
            sweepLocal = CFrame.new(2.0, 1.2, -2.0)
        else
            sweepLocal = CFrame.new(-2.0, -1.2, 2.0)
        end

        local rotCF: CFrame = CFrame.Angles(
            math.rad(stepAngle),
            math.rad(stepAngle),
            0
        )
        local finalCF: CFrame = CFrame.new(targetPart.Position + leadOffset)
            * sweepLocal
            * rotCF

        pcall(function(): ()
            if humanoid.Sit then
                humanoid.Sit = false
            end
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
            humanoid.AutoRotate = false
            root.CFrame = finalCF
            character:PivotTo(finalCF)
            root.AssemblyLinearVelocity = Vector3.new(9e7, 9e7 * 10, 9e7)
            root.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
        end)
        return true
    end

    -- Reconstructed full SkidFling / YARHM Fling with BodyVelocity +
    -- high-density collision + 6-phase Heartbeat/RenderStepped FPos sweep.
    local function performFling(targetPlayer: Player?, options: {[string]: any}?): boolean
        if not Module.Initialized or not targetPlayer then
            return false
        end
        if protectedTargets.isProtected(targetPlayer) then
            notify("player protected")
            return false
        end
        local silent: boolean = type(options) == "table" and options.silent == true
        local maxDuration: number = (type(options) == "table" and tonumber(options.duration)) or 5.0
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
            local bodyVel: BodyVelocity? = nil

            local touchedTarget: boolean = false
            local reason: string = "timeout"

            local success: boolean, errorMessage: any = pcall(function(): ()
                local startedAt: number = os.clock()
                local angle: number = 0

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

                pcall(function(): ()
                    local bv: BodyVelocity = Instance.new("BodyVelocity")
                    bv.Name = "WurstFlingVel"
                    bv.Velocity = Vector3.new(9e8, 9e8, 9e8)
                    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    bv.Parent = root
                    bodyVel = bv
                end)

                local function applyFPos(
                    liveChar: Model,
                    liveRoot: BasePart,
                    basePart: BasePart,
                    posOffset: CFrame,
                    angOffset: CFrame
                ): ()
                    local targetCF: CFrame = CFrame.new(basePart.Position)
                        * posOffset
                        * angOffset
                    pcall(function(): ()
                        liveRoot.CFrame = targetCF
                        liveChar:PivotTo(targetCF)
                        liveRoot.AssemblyLinearVelocity = Vector3.new(9e7, 9e7 * 10, 9e7)
                        liveRoot.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
                    end)
                end

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
                    if targetPart.Position.Y <= voidThreshold then
                        touchedTarget = true
                        reason = "void"
                        break
                    end

                    local targetSpeed: number = 0
                    pcall(function(): ()
                        targetSpeed = targetPart.AssemblyLinearVelocity.Magnitude
                    end)
                    if targetSpeed > 250 then
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

                    forceCharacterCollidable(liveChar, savedCollide, savedProps)

                    pcall(function(): ()
                        (targetPart :: any):SetNetworkOwner(LocalPlayer)
                    end)

                    angle = (angle + 100) % 360
                    local rotCF: CFrame = CFrame.Angles(math.rad(angle), 0, 0)
                    local moveDir: Vector3 = targetHumanoid
                        and targetHumanoid.MoveDirection
                        or Vector3.zero
                    local velMag: number = math.clamp(targetSpeed / 1.25, 0, 25)

                    if targetSpeed < 1.5 then
                        applyFPos(
                            liveChar,
                            liveRoot,
                            targetPart,
                            CFrame.new(0, 1.5, 0) + moveDir * velMag,
                            rotCF
                        )
                        waitFrameStep(false)

                        applyFPos(
                            liveChar,
                            liveRoot,
                            targetPart,
                            CFrame.new(0, -1.5, 0) + moveDir * velMag,
                            rotCF
                        )
                        waitFrameStep(true)

                        applyFPos(
                            liveChar,
                            liveRoot,
                            targetPart,
                            CFrame.new(2.25, 1.5, -2.25) + moveDir * velMag,
                            rotCF
                        )
                        waitFrameStep(false)

                        applyFPos(
                            liveChar,
                            liveRoot,
                            targetPart,
                            CFrame.new(-2.25, -1.5, 2.25) + moveDir * velMag,
                            rotCF
                        )
                        waitFrameStep(true)
                    else
                        applyFPos(
                            liveChar,
                            liveRoot,
                            targetPart,
                            CFrame.new(0, 1.5, velMag) + moveDir * velMag,
                            rotCF
                        )
                        waitFrameStep(false)

                        applyFPos(
                            liveChar,
                            liveRoot,
                            targetPart,
                            CFrame.new(0, -1.5, -velMag) + moveDir * velMag,
                            rotCF
                        )
                        waitFrameStep(true)

                        applyFPos(
                            liveChar,
                            liveRoot,
                            targetPart,
                            CFrame.new(0, 1.5, 0) + moveDir,
                            rotCF
                        )
                        waitFrameStep(false)

                        applyFPos(
                            liveChar,
                            liveRoot,
                            targetPart,
                            CFrame.new(0, -1.5, 0) + moveDir,
                            rotCF
                        )
                        waitFrameStep(true)
                    end
                end
            end)

            if bodyVel then
                pcall(function(): ()
                    bodyVel:Destroy()
                end)
                bodyVel = nil
            end

            restoreCharacterPhysics(savedCollide, savedProps)

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
                local returnCF: CFrame = savedCFrame + Vector3.new(0, 2, 0)
                for _ = 1, 5 do
                    pcall(function(): ()
                        for _, part: Instance in ipairs(finalChar:GetChildren()) do
                            if part:IsA("BasePart") then
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
                    waitFrameStep(false)
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
        -- 1) Ground truth: any living player holding/carrying the Knife
        --    (and never holding the Gun).
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
        -- 2) MM2 core findMurderer(), double-checked against Gun possession.
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
        -- 3) Fallback scan across getPlayerRole / gameBridge.playerRole.
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
        -- 1) Ground truth: any living player holding/carrying the Gun
        --    (and never holding the Knife).
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
        -- 2) MM2 core findSheriff(), double-checked against Knife possession.
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
        -- 3) Fallback scan across getPlayerRole / gameBridge.playerRole.
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

    local FlingFeature: any = createUniversalFeature(
        "Fling",
        "MM2 only: fling the murderer, sheriff or innocents",
        2,
        function() end,
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
    addTextOption(
        FlingFeature,
        "Target player",
        "",
        function(value: string): ()
            flingTargetName = value
        end,
        false,
        "Exact or partial name"
    )
    addActionOption(FlingFeature, "Fling", function(): ()
        local needle: string = string.lower(
            string.gsub(flingTargetName or "", "%s+", "")
        )
        if needle == "" then
            notify("Type a player name in the Target player box first.")
            return
        end
        local exact: Player? = nil
        local partial: Player? = nil
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local name: string = string.lower(player.Name)
                if string.gsub(name, "%s+", "") == needle then
                    exact = player
                    break
                end
                if not partial and string.find(name, needle, 1, true) then
                    partial = player
                end
            end
        end
        local target: Player? = exact or partial
        if target then
            performFling(target)
        else
            notify("No player named \"" .. flingTargetName .. "\" was found.")
        end
    end)
    addInformationOption(
        FlingFeature,
        "MM2 only. Choose a role action, or enter a player name and press Fling."
    )

    activeCleanup = function(): ()
        setFlingRunning(false)
        state.mm2PerformFling = nil
        state.mm2FlingStep = nil
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
