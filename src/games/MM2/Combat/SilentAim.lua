local Module = {
    Name = "MM2 Silent AIM",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Silent AIM requires the MM2 core module")
    local prediction: any = state.mm2Prediction
    assert(type(prediction) == "table", "MM2 Silent AIM requires MM2 Prediction")
    Module.Runtime = runtime

    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local isWeaponPathClear: any = core.isWeaponPathClear
    local getGunOriginCFrame: any = core.getGunOriginCFrame
    local getWeaponServiceModule: any = core.getWeaponServiceModule

    local modeConfigs: {[string]: {wallCheck: boolean, macro: boolean, targetMode: string, targetName: string}} = {
        Bullet = {
            wallCheck = if type(configData) == "table" and configData.states["MM2.SilentAIM.Bullet.WallCheck"] ~= nil
                then configData.states["MM2.SilentAIM.Bullet.WallCheck"] == true
                else true,
            macro = if type(configData) == "table" and configData.states["MM2.SilentAIM.Bullet.Macro"] ~= nil
                then configData.states["MM2.SilentAIM.Bullet.Macro"] == true
                else false,
            targetMode = if type(configData) == "table" and type(configData.values["MM2.SilentAIM.Bullet.Target"]) == "string"
                then configData.values["MM2.SilentAIM.Bullet.Target"]
                else "Murder",
            targetName = if type(configData) == "table" and type(configData.values["MM2.SilentAIM.Bullet.TargetPlayer"]) == "string"
                then configData.values["MM2.SilentAIM.Bullet.TargetPlayer"]
                else "",
        },
        CFrame = {
            wallCheck = if type(configData) == "table" and configData.states["MM2.SilentAIM.CFrame.WallCheck"] ~= nil
                then configData.states["MM2.SilentAIM.CFrame.WallCheck"] == true
                else false,
            macro = if type(configData) == "table" and configData.states["MM2.SilentAIM.CFrame.Macro"] ~= nil
                then configData.states["MM2.SilentAIM.CFrame.Macro"] == true
                else false,
            targetMode = if type(configData) == "table" and type(configData.values["MM2.SilentAIM.CFrame.Target"]) == "string"
                then configData.values["MM2.SilentAIM.CFrame.Target"]
                else "Murder",
            targetName = if type(configData) == "table" and type(configData.values["MM2.SilentAIM.CFrame.TargetPlayer"]) == "string"
                then configData.values["MM2.SilentAIM.CFrame.TargetPlayer"]
                else "",
        },
    }

    local activeMode: string = "Bullet"
    if type(configData) == "table" and type(configData.values["MM2.SilentAIM.Aimmethod"]) == "string" then
        if configData.values["MM2.SilentAIM.Aimmethod"] == "CFrame" then
            activeMode = "CFrame"
        end
    end

    local settings = {
        enabled = false,
        mode = activeMode,
        wallCheck = modeConfigs[activeMode].wallCheck,
        macro = modeConfigs[activeMode].macro,
        targetMode = modeConfigs[activeMode].targetMode,
        targetName = modeConfigs[activeMode].targetName,
    }

    local SilentAimFeature: any = nil
    local hookedWeaponService: any = nil
    local origGetMouseTargetCFrame: any = nil
    local origGetTargetPosition: any = nil
    local toolConnections: {RBXScriptConnection} = {}
    local lastNamecallRewriteAt: number = 0
    local lastCFrameHelperAt: number = 0
    local insideSilentDispatch: boolean = false

    local function clearToolConnections(): ()
        for _, conn: RBXScriptConnection in ipairs(toolConnections) do
            pcall(function(): ()
                conn:Disconnect()
            end)
        end
        table.clear(toolConnections)
    end

    local function getEquippedGun(): (Tool?, Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil, nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not humanoid or humanoid.Health <= 0 or not root then
            return nil, character, humanoid, root
        end
        local gun: Tool? = nil
        if type(getPlayerWeapon) == "function" then
            gun = getPlayerWeapon(LocalPlayer, "Gun", true)
        end
        if not gun then
            local childGun: Instance? = character:FindFirstChild("Gun")
            if childGun and childGun:IsA("Tool") then
                gun = childGun
            end
        end
        if not gun or gun.Parent ~= character then
            return nil, character, humanoid, root
        end
        return gun, character, humanoid, root
    end

    local function resolveActiveTarget(): (Player?, BasePart?)
        local target: Player? = nil
        if settings.targetMode == "Custom" then
            if type(resolveTargetPlayer) == "function" then
                target = resolveTargetPlayer(settings.targetName)
            end
        else
            if type(findMurderer) == "function" then
                target = findMurderer()
            end
            if not target then
                for _, player: Player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer then
                        local role: any = type(getPlayerRole) == "function"
                            and getPlayerRole(player)
                            or nil
                        local hasKnife: boolean = type(getPlayerWeapon) == "function"
                            and getPlayerWeapon(player, "Knife", false) ~= nil
                        if role == "Murderer" or hasKnife then
                            target = player
                            break
                        end
                    end
                end
            end
        end
        if not target or target == LocalPlayer then
            return nil, nil
        end
        if type(isPlayerAlive) == "function" and not isPlayerAlive(target) then
            return nil, nil
        end
        if type(isProtectedTarget) == "function" and isProtectedTarget(target) then
            return nil, nil
        end
        local targetChar: Model? = target.Character
        local targetRoot: BasePart? = targetChar
            and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not targetRoot then
            return nil, nil
        end
        return target, targetRoot
    end

    local function computePredictedEndpoint(
        target: Player,
        targetRoot: BasePart,
        originPos: Vector3
    ): Vector3
        if type(state.mm2PlanGunEndpoint) == "function" then
            local okPlan: boolean, info: any = pcall(state.mm2PlanGunEndpoint, target, originPos)
            if okPlan and type(info) == "table" and typeof(info.endpoint) == "Vector3" then
                return info.endpoint
            end
        end
        if type(prediction) == "table" and type(prediction.gunAim) == "function" then
            local okPred: boolean, endpoint: any = pcall(prediction.gunAim, target, originPos)
            if okPred and typeof(endpoint) == "Vector3" then
                return endpoint
            end
        end
        local vel: Vector3 = Vector3.zero
        pcall(function(): ()
            vel = targetRoot.AssemblyLinearVelocity
        end)
        local dist: number = (targetRoot.Position - originPos).Magnitude
        local leadTime: number = math.clamp(dist / 280, 0.03, 0.18)
        return targetRoot.Position + Vector3.new(vel.X, vel.Y * 0.25, vel.Z) * leadTime
    end

    local function passesWallCheck(
        originPos: Vector3,
        endpoint: Vector3,
        target: Player
    ): boolean
        if not settings.wallCheck then
            return true
        end
        if type(state.mm2CanDirectHitTarget) == "function" then
            local okHit: boolean, clearHit: any = pcall(
                state.mm2CanDirectHitTarget,
                originPos,
                endpoint,
                target
            )
            if okHit then
                return clearHit == true
            end
        end
        if type(isWeaponPathClear) == "function" then
            local okClear: boolean, clear: any = pcall(
                isWeaponPathClear,
                originPos,
                endpoint,
                target.Character
            )
            return okClear and clear == true
        end
        return true
    end

    local function buildCFrameOriginAndEnd(
        target: Player,
        targetRoot: BasePart,
        muzzleOrigin: CFrame,
        endpoint: Vector3
    ): (CFrame, CFrame)
        if type(state.mm2BuildSilentShot) == "function" then
            local okBuild: boolean, sOrigin: any, sEnd: any = pcall(
                state.mm2BuildSilentShot,
                target,
                muzzleOrigin,
                {
                    endpoint = endpoint,
                    capturedPosition = targetRoot.Position,
                    velocity = targetRoot.AssemblyLinearVelocity,
                },
                settings.wallCheck == true
            )
            if okBuild and typeof(sOrigin) == "CFrame" and typeof(sEnd) == "CFrame" then
                return sOrigin, sEnd
            end
        end
        local capturedPos: Vector3 = targetRoot.Position
        local chordFlat: Vector3 = Vector3.new(
            endpoint.X - capturedPos.X,
            0,
            endpoint.Z - capturedPos.Z
        )
        local pierceAxis: Vector3
        if chordFlat.Magnitude > 0.15 then
            pierceAxis = chordFlat.Unit
        else
            local toTargetFlat: Vector3 = Vector3.new(
                endpoint.X - muzzleOrigin.Position.X,
                0,
                endpoint.Z - muzzleOrigin.Position.Z
            )
            if toTargetFlat.Magnitude > 0.05 then
                pierceAxis = toTargetFlat.Unit
            else
                pierceAxis = Vector3.new(0, 0, -1)
            end
        end
        local startPoint: Vector3 = capturedPos - pierceAxis * 1.5
        local endPoint: Vector3 = endpoint + pierceAxis * 1.5
        if (endPoint - startPoint).Magnitude < 0.2 then
            startPoint = endpoint + Vector3.new(0, 2.0, -1.5)
            endPoint = endpoint
        end
        return CFrame.lookAt(startPoint, endPoint), CFrame.new(endPoint)
    end

    local function triggerMacroUnequip(gun: Tool?): ()
        if not settings.macro or not gun then
            return
        end
        task.delay(0.01, function(): ()
            local character: Model? = LocalPlayer and LocalPlayer.Character
            local humanoid: Humanoid? = character
                and character:FindFirstChildOfClass("Humanoid")
            if character and humanoid and gun.Parent == character then
                pcall(function(): ()
                    humanoid:UnequipTools()
                end)
            end
        end)
    end

    local function computeSilentShotPair(): (Tool?, CFrame?, CFrame?, Vector3?)
        if not settings.enabled then
            return nil, nil, nil, nil
        end
        local gun: Tool?, character: Model?, _humanoid: Humanoid?, localRoot: BasePart? =
            getEquippedGun()
        if not gun or not character or not localRoot then
            return nil, nil, nil, nil
        end
        local target: Player?, targetRoot: BasePart? = resolveActiveTarget()
        if not target or not targetRoot then
            return nil, nil, nil, nil
        end
        local muzzleOrigin: CFrame = (type(getGunOriginCFrame) == "function"
            and getGunOriginCFrame(character, gun))
            or localRoot.CFrame
        local endpoint: Vector3 = computePredictedEndpoint(
            target,
            targetRoot,
            muzzleOrigin.Position
        )
        if settings.mode == "CFrame" then
            local shotOrigin: CFrame, shotEnd: CFrame = buildCFrameOriginAndEnd(
                target,
                targetRoot,
                muzzleOrigin,
                endpoint
            )
            if settings.wallCheck and not passesWallCheck(shotOrigin.Position, shotEnd.Position, target) then
                return nil, nil, nil, nil
            end
            return gun, shotOrigin, shotEnd, endpoint
        else
            if not passesWallCheck(muzzleOrigin.Position, endpoint, target) then
                return nil, nil, nil, nil
            end
            local shotOrigin: CFrame = CFrame.lookAt(muzzleOrigin.Position, endpoint)
            local shotEnd: CFrame = CFrame.new(endpoint)
            return gun, shotOrigin, shotEnd, endpoint
        end
    end

    local function fireCFrameCompanionIfNeeded(): ()
        if not settings.enabled or insideSilentDispatch then
            return
        end
        local now: number = os.clock()
        if now - lastNamecallRewriteAt < 0.08 or now - lastCFrameHelperAt < 0.12 then
            return
        end
        local gun: Tool?, shotOrigin: CFrame?, shotEnd: CFrame? = computeSilentShotPair()
        if not gun or not shotOrigin or not shotEnd then
            return
        end
        if settings.mode == "CFrame" then
            local shootRemote: Instance? = gun:FindFirstChild("Shoot")
            if shootRemote and shootRemote:IsA("RemoteEvent") then
                lastCFrameHelperAt = now
                insideSilentDispatch = true
                pcall(function(): ()
                    (shootRemote :: RemoteEvent):FireServer(shotOrigin, shotEnd)
                end)
                insideSilentDispatch = false
            end
        end
        triggerMacroUnequip(gun)
    end

    -- Redirect callback shared with WeaponService.GetMouseTargetCFrame (PC)
    -- and WeaponService.GetTargetPosition (Mobile).
    local function redirectWeaponServiceAim(_self: any, ...: any): CFrame?
        if not settings.enabled then
            return nil
        end
        local gun: Tool?, _shotOrigin: CFrame?, shotEnd: CFrame?, endpoint: Vector3? =
            computeSilentShotPair()
        if not gun or not shotEnd or not endpoint then
            return nil
        end
        if settings.mode == "CFrame" then
            task.defer(fireCFrameCompanionIfNeeded)
        else
            triggerMacroUnequip(gun)
        end
        return CFrame.new(endpoint)
    end
    state.mm2SilentAimRedirectCFrame = redirectWeaponServiceAim

    local function installWeaponServiceRedirect(): ()
        if hookedWeaponService then
            return
        end
        pcall(function(): ()
            local wsTable: any = nil
            if type(getWeaponServiceModule) == "function" then
                wsTable = getWeaponServiceModule()
            end
            if type(wsTable) ~= "table" then
                local rs: Instance? = game:GetService("ReplicatedStorage")
                local clientServices: Instance? = rs and rs:FindFirstChild("ClientServices")
                local wsModule: Instance? = clientServices and clientServices:FindFirstChild("WeaponService")
                if wsModule then
                    local okReq: boolean, loaded: any = pcall(require, wsModule)
                    if okReq and type(loaded) == "table" then
                        wsTable = loaded
                    end
                end
            end
            if type(wsTable) ~= "table" then
                return
            end
            origGetMouseTargetCFrame = wsTable.GetMouseTargetCFrame
            origGetTargetPosition = wsTable.GetTargetPosition
            hookedWeaponService = wsTable

            if type(origGetMouseTargetCFrame) == "function" then
                wsTable.GetMouseTargetCFrame = function(self: any, ...: any): any
                    local redirected: CFrame? = redirectWeaponServiceAim(self, ...)
                    if redirected then
                        return redirected
                    end
                    return origGetMouseTargetCFrame(self, ...)
                end
            end

            if type(origGetTargetPosition) == "function" then
                wsTable.GetTargetPosition = function(self: any, ...: any): any
                    local redirected: CFrame? = redirectWeaponServiceAim(self, ...)
                    if redirected then
                        return redirected
                    end
                    return origGetTargetPosition(self, ...)
                end
            end
        end)
    end

    local function uninstallWeaponServiceRedirect(): ()
        if not hookedWeaponService then
            return
        end
        pcall(function(): ()
            if origGetMouseTargetCFrame then
                hookedWeaponService.GetMouseTargetCFrame = origGetMouseTargetCFrame
            end
            if origGetTargetPosition then
                hookedWeaponService.GetTargetPosition = origGetTargetPosition
            end
        end)
        hookedWeaponService = nil
        origGetMouseTargetCFrame = nil
        origGetTargetPosition = nil
    end

    -- Optional __namecall hook for executors supporting hookmetamethod:
    -- rewrites native Gun.Shoot:FireServer(originCF, endCF) on both PC and Mobile.
    pcall(function(): ()
        local g: any = (type(getgenv) == "function" and getgenv()) or _G
        local hookmm: any = (g and g.hookmetamethod) or (_G and (_G :: any).hookmetamethod)
        local getncm: any = (g and g.getnamecallmethod) or (_G and (_G :: any).getnamecallmethod)
        if type(hookmm) ~= "function" or type(getncm) ~= "function" then
            return
        end
        if state.mm2SilentAimNamecallHooked then
            return
        end
        state.mm2SilentAimNamecallHooked = true
        local oldNamecall: any = nil
        oldNamecall = hookmm(game, "__namecall", function(self: any, ...: any): any
            if not insideSilentDispatch
                and state.mm2SilentAimNativeActive == true
                and type(state.mm2SilentAimRewriteFireServer) == "function" then
                local method: string = getncm()
                if method == "FireServer" and typeof(self) == "Instance" and self.Name == "Shoot" then
                    local parentTool: Instance? = self.Parent
                    local character: Model? = LocalPlayer and LocalPlayer.Character
                    if parentTool and character and parentTool.Parent == character then
                        local okRewrite: boolean, newOrigin: any, newEnd: any =
                            pcall(state.mm2SilentAimRewriteFireServer)
                        if okRewrite and typeof(newOrigin) == "CFrame" and typeof(newEnd) == "CFrame" then
                            return oldNamecall(self, newOrigin, newEnd)
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
    end)

    state.mm2SilentAimRewriteFireServer = function(): (CFrame?, CFrame?)
        if not settings.enabled then
            return nil, nil
        end
        local gun: Tool?, shotOrigin: CFrame?, shotEnd: CFrame? = computeSilentShotPair()
        if not gun or not shotOrigin or not shotEnd then
            return nil, nil
        end
        lastNamecallRewriteAt = os.clock()
        triggerMacroUnequip(gun)
        return shotOrigin, shotEnd
    end

    local function bindGunTool(tool: Instance?): ()
        if not tool or not tool:IsA("Tool") or tool.Name ~= "Gun" then
            return
        end
        pcall(function(): ()
            if tool.Activated then
                table.insert(
                    toolConnections,
                    tool.Activated:Connect(function(): ()
                        if settings.enabled then
                            fireCFrameCompanionIfNeeded()
                        end
                    end)
                )
            end
        end)
    end

    local function watchCharacterGuns(): ()
        clearToolConnections()
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if character then
            for _, child: Instance in ipairs(character:GetChildren()) do
                bindGunTool(child)
            end
            pcall(function(): ()
                if character.ChildAdded then
                    table.insert(
                        toolConnections,
                        character.ChildAdded:Connect(bindGunTool)
                    )
                end
            end)
        end
        pcall(function(): ()
            if LocalPlayer and LocalPlayer.CharacterAdded then
                table.insert(
                    toolConnections,
                    LocalPlayer.CharacterAdded:Connect(function(newChar: Model): ()
                        for _, child: Instance in ipairs(newChar:GetChildren()) do
                            bindGunTool(child)
                        end
                        if newChar.ChildAdded then
                            table.insert(
                                toolConnections,
                                newChar.ChildAdded:Connect(bindGunTool)
                            )
                        end
                    end)
                )
            end
        end)
    end

    local function updateStatus(): ()
        if not SilentAimFeature or not SilentAimFeature.enabled then
            return
        end
        SilentAimFeature:SetStatus(settings.mode)
    end

    local function toggleSilentAim(enabled: boolean): ()
        settings.enabled = enabled == true
        state.mm2SilentAimNativeActive = settings.enabled
        if settings.enabled then
            installWeaponServiceRedirect()
            watchCharacterGuns()
            updateStatus()
        else
            clearToolConnections()
            uninstallWeaponServiceRedirect()
            if SilentAimFeature then
                SilentAimFeature:SetStatus(nil)
            end
        end
    end

    SilentAimFeature = createUniversalFeature(
        "Silent AIM",
        "Redirects your native Gun shots (PC mouse click & Mobile screen tap) toward the Murderer automatically without pressing any extra button. Supports independent Bullet and CFrame mode settings.",
        4,
        toggleSilentAim,
        {
            categoryName = "Combat",
            configKey = "MM2.SilentAIM",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2NativeSilentAimFeature = SilentAimFeature

    local targetPlayerBox: GuiObject? = nil
    local switchingMode: boolean = false

    local function refreshTargetPlayerVisibility(): ()
        if targetPlayerBox and type(setOptionVisible) == "function" then
            setOptionVisible(
                SilentAimFeature,
                targetPlayerBox.Parent :: GuiObject,
                settings.targetMode == "Custom"
            )
        end
    end

    local function syncModeOptions(): ()
        local cfg = modeConfigs[settings.mode] or modeConfigs.Bullet
        switchingMode = true
        settings.wallCheck = cfg.wallCheck == true
        settings.macro = cfg.macro == true
        settings.targetMode = cfg.targetMode
        settings.targetName = cfg.targetName
        if state and type(state.toggleControls) == "table" then
            local wc = state.toggleControls["MM2.SilentAIM.WallCheck"]
            if wc and type(wc.setChecked) == "function" then
                pcall(wc.setChecked, cfg.wallCheck == true)
            end
            local mc = state.toggleControls["MM2.SilentAIM.Macro"]
            if mc and type(mc.setChecked) == "function" then
                pcall(mc.setChecked, cfg.macro == true)
            end
        end
        if state and type(state.valueControls) == "table" then
            local tc = state.valueControls["MM2.SilentAIM.Target"]
            if tc and type(tc.apply) == "function" then
                pcall(tc.apply, cfg.targetMode)
            end
            local tp = state.valueControls["MM2.SilentAIM.Targetplayer"]
            if tp and type(tp.apply) == "function" then
                pcall(tp.apply, cfg.targetName)
            end
        end
        switchingMode = false
        refreshTargetPlayerVisibility()
        updateStatus()
    end

    addCycleOption(
        SilentAimFeature,
        "Aim method",
        {"Bullet", "CFrame"},
        settings.mode == "CFrame" and 2 or 1,
        function(value: string): ()
            settings.mode = (value == "CFrame") and "CFrame" or "Bullet"
            syncModeOptions()
        end,
        "Bullet redirects the shot from your Gun barrel; CFrame spawns the Gun.Shoot origin CFrame beside the Murderer. Each mode keeps independent WallCheck and Macro settings."
    )

    addCycleOption(
        SilentAimFeature,
        "Target",
        {"Murder", "Custom"},
        settings.targetMode == "Custom" and 2 or 1,
        function(value: string): ()
            settings.targetMode = value
            if not switchingMode then
                local cfg = modeConfigs[settings.mode]
                if cfg then
                    cfg.targetMode = value
                end
                if type(configData) == "table" and type(configData.values) == "table" then
                    configData.values["MM2.SilentAIM." .. settings.mode .. ".Target"] = value
                end
            end
            refreshTargetPlayerVisibility()
        end,
        "Target the Murderer automatically or a custom player name (independent per mode)."
    )

    addToggleOption(
        SilentAimFeature,
        "WallCheck",
        settings.wallCheck,
        function(value: boolean): ()
            local on: boolean = value == true
            settings.wallCheck = on
            if not switchingMode then
                local cfg = modeConfigs[settings.mode]
                if cfg then
                    cfg.wallCheck = on
                end
                if type(configData) == "table" and type(configData.states) == "table" then
                    configData.states["MM2.SilentAIM." .. settings.mode .. ".WallCheck"] = on
                end
            end
        end,
        "Only redirect the shot when there is a clear line of sight to the target (independent per mode)."
    )

    addToggleOption(
        SilentAimFeature,
        "Macro",
        settings.macro,
        function(value: boolean): ()
            local on: boolean = value == true
            settings.macro = on
            if not switchingMode then
                local cfg = modeConfigs[settings.mode]
                if cfg then
                    cfg.macro = on
                end
                if type(configData) == "table" and type(configData.states) == "table" then
                    configData.states["MM2.SilentAIM." .. settings.mode .. ".Macro"] = on
                end
            end
        end,
        "Pistol macro: automatically unequips the Gun 0.01 seconds after firing (independent per mode)."
    )

    targetPlayerBox = addTextOption(
        SilentAimFeature,
        "Target player",
        settings.targetName,
        function(value: string): ()
            settings.targetName = value
            if not switchingMode then
                local cfg = modeConfigs[settings.mode]
                if cfg then
                    cfg.targetName = value
                end
                if type(configData) == "table" and type(configData.values) == "table" then
                    configData.values["MM2.SilentAIM." .. settings.mode .. ".TargetPlayer"] = value
                end
            end
        end,
        false
    )

    syncModeOptions()

    activeCleanup = function(): ()
        toggleSilentAim(false)
        state.mm2NativeSilentAimFeature = nil
        state.mm2SilentAimRedirectCFrame = nil
        state.mm2SilentAimRewriteFireServer = nil
        state.mm2SilentAimNativeActive = false
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
