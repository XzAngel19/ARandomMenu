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
    local addTextOption: any = host.addTextOption
    local addInformationOption: any = host.addInformationOption
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local findPlayerByText: any = host.findPlayerByText
    local configData: any = host.configData

    local workspace: any = host.workspace
    local RunService: any = host.RunService

    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive

    -- Walk Fling is its own card now (Universal "Walk Fling"). The two option
    -- keys this card used to own are dropped, so an old saved config cannot
    -- restore anything here on injection.
    if configData and type(configData.states) == "table" then
        configData.states["MM2.Fling.AutoFlingSelectedTarget"] = nil
        configData.states["MM2.Fling.TouchFling"] = nil
    end

    -- SkidFling (zqyDSUWX / YARHM), the fling every working menu copies:
    --
    --   RootPart.CFrame      = CFrame.new(targetPart.Position) * offset * spin
    --   RootPart.Velocity    = Vector3.new(9e7, 9e7 * 10, 9e7)
    --   RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
    --
    -- The local character is parked on the victim and given an absurd velocity
    -- while a BodyVelocity (Velocity 0, MaxForce 9e9) keeps it from being thrown
    -- into the sky. That enormous velocity exists just long enough for the
    -- contact solver to hand it to the victim, which is why this version actually
    -- launches people and the old CFrame-lock one did not.
    local FLING_VELOCITY: Vector3 = Vector3.new(9e7, 9e7 * 10, 9e7)
    local FLING_ROT_VELOCITY: Vector3 = Vector3.new(9e8, 9e8, 9e8)

    local flingRunning: boolean = false
    local flingTargetName: string = ""
    local selectedTargetChoice: string = "Murderer"
    local stepPhase: number = 0
    local stepAngle: number = 0

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        activity.set("fling", running)
    end

    local function waitHeartbeat(): ()
        local ok: boolean = pcall(function(): ()
            if RunService and RunService.Heartbeat and RunService.Heartbeat.Wait then
                RunService.Heartbeat:Wait()
            elseif task and task.wait then
                task.wait()
            end
        end)
        if not ok then
            task.wait()
        end
    end

    local function waitRenderStepped(): ()
        local ok: boolean = pcall(function(): ()
            if RunService and RunService.RenderStepped and RunService.RenderStepped.Wait then
                RunService.RenderStepped:Wait()
            elseif RunService and RunService.Heartbeat and RunService.Heartbeat.Wait then
                RunService.Heartbeat:Wait()
            else
                task.wait()
            end
        end)
        if not ok then
            task.wait()
        end
    end

    local function moveCharacter(character: Model, cframe: CFrame): ()
        if type(character.PivotTo) == "function" then
            character:PivotTo(cframe)
        elseif type(character.SetPrimaryPartCFrame) == "function" then
            character:SetPrimaryPartCFrame(cframe)
        end
    end

    local function targetRootPart(targetPlayer: Player?): (Model?, Humanoid?, BasePart?)
        local targetCharacter: Model? = targetPlayer and targetPlayer.Character
        if not targetCharacter or not targetCharacter.Parent then
            return nil, nil, nil
        end
        local targetHumanoid: Humanoid? = targetCharacter:FindFirstChildOfClass("Humanoid")
        local targetPart: BasePart? = (targetHumanoid and targetHumanoid.RootPart)
            or (targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?)
            or (targetCharacter:FindFirstChild("Head") :: BasePart?)
            or targetCharacter:FindFirstChildWhichIsA("BasePart")
        return targetCharacter, targetHumanoid, targetPart
    end

    -- One SkidFling pose: park the local character on the victim (offset above or
    -- below, rotating) and hand the assembly the huge velocity.
    local function flingPose(
        character: Model,
        root: BasePart,
        targetPart: BasePart,
        verticalOffset: number,
        angle: number
    ): ()
        local position: Vector3 = targetPart.Position + Vector3.new(0, verticalOffset, 0)
        local rotation: CFrame = CFrame.Angles(math.rad(angle), 0, 0)
        local targetCFrame: CFrame = CFrame.new(position) * rotation
        pcall(function(): ()
            root.CFrame = targetCFrame
            moveCharacter(character, targetCFrame)
            root.Velocity = FLING_VELOCITY
            root.AssemblyLinearVelocity = FLING_VELOCITY
            root.RotVelocity = FLING_ROT_VELOCITY
            root.AssemblyAngularVelocity = FLING_ROT_VELOCITY
            pcall(function(): ()
                root.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
            end)
        end)
    end

    -- Single pose for per-frame callers (Auto Win's Fling Sheriff).
    local function flingSingleStep(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        targetPlayer: Player,
        _savedCollide: any,
        _savedProps: any
    ): boolean
        local _targetCharacter: Model?, targetHumanoid: Humanoid?, targetPart: BasePart? =
            targetRootPart(targetPlayer)
        if not targetPart or not targetPart.Parent then
            return false
        end
        if targetHumanoid and (targetHumanoid.Health <= 0 or targetHumanoid.Sit) then
            return false
        end
        activity.set("fling", true)
        -- A single pose must not leave the activity flag on forever: that would
        -- silently disable Anti Fling and Walk Fling for the rest of the session.
        if type(task) == "table" and type(task.delay) == "function" then
            task.delay(0.5, function(): ()
                if not flingRunning then
                    activity.set("fling", false)
                end
            end)
        end
        stepPhase = (stepPhase + 1) % 2
        stepAngle = (stepAngle + 100) % 360
        local verticalOffset: number = if stepPhase == 0 then 1.5 else -1.5
        flingPose(character, root, targetPart, verticalOffset, stepAngle)
        return true
    end

    local function performFling(targetPlayer: Player?, options: {[string]: any}?): boolean
        if not Module.Initialized or not targetPlayer then
            return false
        end
        if protectedTargets.isProtected(targetPlayer) then
            notify("player protected")
            return false
        end
        local silent: boolean = type(options) == "table" and options.silent == true
        local maxDuration: number = (type(options) == "table" and tonumber(options.duration)) or 2.0
        local shouldStop: (() -> boolean)? = type(options) == "table"
            and type(options.shouldStop) == "function"
            and options.shouldStop
            or nil
        local returnCFrame: CFrame? = type(options) == "table"
            and typeof(options.returnCFrame) == "CFrame"
            and options.returnCFrame
            or nil

        if flingRunning then
            if not silent then
                notify("fling already running")
            end
            return false
        end

        setFlingRunning(true)

        local function runFling(): boolean
            local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not character or not humanoid or not root then
                setFlingRunning(false)
                if not silent then
                    notify("character not ready")
                end
                return false
            end

            local savedCFrame: CFrame = returnCFrame or root.CFrame
            local savedDestroyHeight: any = workspace.FallenPartsDestroyHeight
            local camera: Camera? = workspace.CurrentCamera
            local savedCameraSubject: any = camera and camera.CameraSubject or nil
            local bodyVelocity: any = nil
            local touchedTarget: boolean = false
            local reason: string = "timeout"

            local success: boolean, errorMessage: any = pcall(function(): ()
                local _targetCharacter: Model?, targetHumanoid: Humanoid?, targetPart: BasePart? =
                    targetRootPart(targetPlayer)
                if not targetPart or not targetPart.Parent then
                    error("the target has no character", 0)
                end
                if targetHumanoid and targetHumanoid.Sit then
                    error("the target is seated", 0)
                end

                if camera then
                    pcall(function(): ()
                        camera.CameraSubject = targetHumanoid or targetPart
                    end)
                end
                -- The original disables the destroy layer while the character
                -- flies through the map; it is always put back below.
                pcall(function(): ()
                    workspace.FallenPartsDestroyHeight = 0 / 0
                end)

                local bodyVelocityInstance: any = Instance.new("BodyVelocity")
                pcall(function(): ()
                    bodyVelocityInstance.Name = "WurstFlingBodyVelocity"
                    bodyVelocityInstance.Velocity = Vector3.zero
                    bodyVelocityInstance.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                    bodyVelocityInstance.Parent = root
                end)
                bodyVelocity = bodyVelocityInstance

                pcall(function(): ()
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                end)

                local startedAt: number = os.clock()
                local angle: number = 0
                local verticalOffset: number = 1.5

                while flingRunning and os.clock() - startedAt < maxDuration do
                    if shouldStop and shouldStop() then
                        reason = "stopped"
                        break
                    end
                    if targetPlayer.Parent == nil then
                        reason = "left"
                        break
                    end
                    local liveCharacter: Model?, liveHumanoid: Humanoid?, liveRoot: BasePart? =
                        getCharacterParts()
                    if not liveCharacter or not liveHumanoid or not liveRoot then
                        reason = "died"
                        break
                    end
                    if liveRoot ~= root or liveHumanoid ~= humanoid or liveHumanoid.Health <= 0 then
                        reason = "died"
                        break
                    end

                    local _liveTarget: Model?, liveTargetHumanoid: Humanoid?, liveTargetPart: BasePart? =
                        targetRootPart(targetPlayer)
                    if not liveTargetPart or not liveTargetPart.Parent then
                        reason = "gone"
                        break
                    end
                    if liveTargetHumanoid and liveTargetHumanoid.Health <= 0 then
                        touchedTarget = true
                        reason = "killed"
                        break
                    end
                    if liveTargetHumanoid and liveTargetHumanoid.Sit then
                        reason = "seated"
                        break
                    end
                    local targetSpeed: number = 0
                    pcall(function(): ()
                        targetSpeed = liveTargetPart.AssemblyLinearVelocity.Magnitude
                    end)
                    if targetSpeed > 500 then
                        touchedTarget = true
                        reason = "flung"
                        break
                    end

                    angle = (angle + 100) % 360
                    verticalOffset = -verticalOffset
                    flingPose(liveCharacter, liveRoot, liveTargetPart, verticalOffset, angle)
                    waitRenderStepped()
                end
            end)

            if bodyVelocity then
                pcall(function(): ()
                    bodyVelocity:Destroy()
                end)
                bodyVelocity = nil
            end
            pcall(function(): ()
                workspace.FallenPartsDestroyHeight = savedDestroyHeight
            end)
            pcall(function(): ()
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
            end)

            local finalCharacter: Model?, finalHumanoid: Humanoid?, finalRoot: BasePart? =
                getCharacterParts()
            if finalCharacter and finalRoot and finalRoot.Parent then
                for _ = 1, 25 do
                    pcall(function(): ()
                        moveCharacter(finalCharacter, savedCFrame)
                        for _, descendant: Instance in ipairs(finalCharacter:GetDescendants()) do
                            if descendant:IsA("BasePart") then
                                local bodyPart: BasePart = descendant :: BasePart
                                bodyPart.Velocity = Vector3.zero
                                bodyPart.AssemblyLinearVelocity = Vector3.zero
                                bodyPart.AssemblyAngularVelocity = Vector3.zero
                            end
                        end
                    end)
                    if (finalRoot.Position - savedCFrame.Position).Magnitude < 6 then
                        break
                    end
                    waitHeartbeat()
                end
            end
            if finalHumanoid then
                pcall(function(): ()
                    finalHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
            end
            if camera then
                pcall(function(): ()
                    camera.CameraSubject = savedCameraSubject or finalHumanoid
                end)
            end

            setFlingRunning(false)
            if not Module.Initialized then
                return touchedTarget
            end
            if not silent then
                if not success then
                    notify("fling failed: " .. tostring(errorMessage))
                elseif touchedTarget then
                    notify("fling complete: " .. targetPlayer.Name .. " went flying.")
                elseif reason == "left" then
                    notify("fling stopped: " .. targetPlayer.Name .. " left the game.")
                elseif reason == "gone" then
                    notify("fling stopped: the target character disappeared.")
                elseif reason == "died" then
                    notify("fling stopped: your character died.")
                elseif reason == "seated" then
                    notify("fling stopped: target is seated.")
                end
            end
            return touchedTarget
        end

        if type(options) == "table" and options.blocking == true then
            return runFling()
        end
        task.spawn(runFling)
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

    -- The card is a group: this only reports the container state. Turning it off
    -- never starts a fling, and nothing here runs on injection.
    local function toggleFlingModule(enabled: boolean): ()
        activity.set("fling", flingRunning and enabled == true)
    end

    local FlingFeature: any = createUniversalFeature(
        "Fling",
        "MM2 only: launch the murderer, the sheriff or any chosen player",
        7,
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
            "Select Murderer, Sheriff, or a specific player in the server for Fling."
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
    addInformationOption(
        FlingFeature,
        "MM2 only. SkidFling. Pick a role action, or choose a player in Select Target / "
            .. "Target player and press Fling. Walk Fling is its own card."
    )

    activeCleanup = function(): ()
        flingRunning = false
        if disconnectFeatureConnection then
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
