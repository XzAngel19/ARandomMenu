local Module = {
    Name = "MM2 Shoot",
    PlaceId = 142823291,
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
    assert(type(core) == "table", "MM2 Shoot requires the MM2 core module")
    local prediction: any = state.mm2Prediction
    assert(type(prediction) == "table", "MM2 Shoot requires MM2 Prediction")
    local trajectoryCalibration: any = core.trajectoryCalibration
    Module.Runtime = runtime
    local connectGunFiredSignal: any = core.connectGunFiredSignal
    local disconnectGunFiredObserver: any = core.disconnectGunFiredObserver
    local findMurderer: any = core.findMurderer
    local getGunOriginCFrame: any = core.getGunOriginCFrame
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local getWeaponServiceModule: any = core.getWeaponServiceModule
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local isWeaponPathClear: any = core.isWeaponPathClear
    local mm2Settings: any = core.mm2Settings
    local validateGunShot: any = core.validateGunShot

    local shootMacro: boolean = false
    -- First thing the untouched ray meets on an allowed shot (nil if nothing
    -- short of the aim). Persisted into the shot's settings.
    local lastGunOccluder: any = nil
    local function macroUnequip(gun: Tool?): ()
        if not shootMacro or not gun then
            return
        end
        task.delay(0.01, function(): ()
            pcall(function(): ()
                local backpack: Instance? = LocalPlayer:FindFirstChildOfClass("Backpack")
                local character: Model? = LocalPlayer.Character
                if backpack and character and gun.Parent == character then
                    gun.Parent = backpack
                end
            end)
        end)
    end

    local function getSelectedShootTarget(): Player?
        local target
        if mm2Settings.shootMode == "Custom"
            and mm2Settings.shootTarget ~= "" then
            target = findPlayerByText(mm2Settings.shootTarget)
        else
            target = findMurderer()
        end
        if not target
            or target == LocalPlayer
            or not isPlayerAlive(target)
            or isProtectedTarget(target) then
            return nil
        end
        if getPlayerRole(target) ~= "Murderer" then
            return nil
        end
        return target
    end

    local function bystanderOnSegment(
        target: Player,
        startPoint: Vector3,
        endPoint: Vector3
    ): boolean
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Include
        parameters.IgnoreWater = true
        local bodies: {Instance} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= target
                and player ~= LocalPlayer
                and player.Character
                and isPlayerAlive(player) then
                table.insert(bodies, player.Character)
            end
        end
        if #bodies == 0 then
            return false
        end
        parameters.FilterDescendantsInstances = bodies
        return workspace:Raycast(startPoint, endPoint - startPoint, parameters) ~= nil
    end

    local SILENT_ORIGIN_STUDS: number = 2.5
    local SILENT_PIERCE_STUDS: number = 1.0
    local SILENT_LIFT_STUDS: number = 1.6
    local MAX_SILENT_SWEEP: number = 1.5

    local function getSilentSweepDistance(): number
        local configured: number = tonumber(mm2Settings.silentSweep) or 0
        return math.clamp(configured, 0, MAX_SILENT_SWEEP)
    end

    local function buildSilentShot(
        target: Player,
        info: any,
        muzzleOrigin: CFrame?,
        variant: string
    ): (CFrame?, CFrame?, number)
        local predicted: Vector3 = info.endpoint
        local velocity: Vector3 = info.velocity
        local horizontal: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)

        local direction: Vector3? = nil
        local sweep: number = 0
        if horizontal.Magnitude > 1.5 then
            direction = horizontal.Unit

            sweep = getSilentSweepDistance()
        end
        local sweepStart: Vector3 =
            direction and -direction * sweep or Vector3.zero
        local sweepEnd: Vector3 =
            direction and direction * sweep or Vector3.zero

        local approach: Vector3? = nil
        local approachOffset: number = SILENT_ORIGIN_STUDS
        if muzzleOrigin then
            local toTarget: Vector3 = predicted - muzzleOrigin.Position
            local flat: Vector3 = Vector3.new(toTarget.X, 0, toTarget.Z)
            if flat.Magnitude > 0.05 then
                approach = flat.Unit
                approachOffset = math.min(
                    SILENT_ORIGIN_STUDS,
                    math.max(1.0, flat.Magnitude * 0.6)
                )
            end
        end

        local startPoint: Vector3
        local endPoint: Vector3
        if variant == "Through" and approach then

            local captured: Vector3 = info.capturedPosition or predicted
            startPoint = captured - approach * 1.0 + sweepStart
            endPoint = predicted + approach * SILENT_PIERCE_STUDS + sweepEnd
        elseif variant == "Top" then
            startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
                + sweepStart
            endPoint = predicted + sweepEnd
        elseif variant == "Behind" and approach then
            startPoint = predicted + approach * approachOffset + sweepStart
            endPoint = predicted + sweepEnd
        elseif approach then

            startPoint = predicted - approach * approachOffset + sweepStart
            endPoint = predicted + sweepEnd
        elseif direction then
            startPoint = predicted + sweepStart
            endPoint = predicted + sweepEnd
        else

            startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
            endPoint = predicted
        end

        if (endPoint - startPoint).Magnitude <= 0.05 then
            startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
            endPoint = predicted
        end
        -- Through has length even when the configurable extra sweep is zero.
        if bystanderOnSegment(target, startPoint, endPoint) then

            if variant ~= "Top" and approach then
                startPoint = predicted - approach * approachOffset
            else
                startPoint = predicted + Vector3.new(0, SILENT_LIFT_STUDS, 0)
            end
            endPoint = predicted
            if bystanderOnSegment(target, startPoint, endPoint) then
                return nil, nil, 0
            end
        end

        return CFrame.lookAt(startPoint, endPoint), CFrame.new(endPoint),
            approachOffset
    end

    type FireOptions = {
        silent: boolean?,
        quiet: boolean?,
        whenReady: boolean?,
    }

    local ShootFeature: any = nil
    local lastRejectReason: string = ""

    local function fireGunAtTarget(
        target: Player?,
        options: FireOptions?
    ): boolean
        local opts: FireOptions = options or {}
        local silent: boolean = mm2Settings.silentAim
        if opts.silent ~= nil then
            silent = opts.silent
        end
        local quiet: boolean = opts.quiet == true
        local function reject(message: string): boolean
            lastRejectReason = message
            if not quiet and ShootFeature then ShootFeature:SetStatus(message) end
            return false
        end

        local character, humanoid = getCharacterParts()
        if not target or not target.Character or target == LocalPlayer
            or not isPlayerAlive(target) or isProtectedTarget(target) or getPlayerRole(target) ~= "Murderer" then
            return reject("No selected shoot target was found.")
        end
        if not character or not humanoid then
            return reject("Your character is not available.")
        end
        local targetCharacter = target.Character
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun", true)
        if not gun or gun.Parent ~= character then
            return reject("Equip the sheriff gun yourself to shoot.")
        end
        if gun.Enabled == false or gun:GetAttribute("Disabled") == true
            or gun:GetAttribute("Reloading") == true or gun:GetAttribute("IsReloading") == true then
            return reject("The gun is disabled or reloading.")
        end

        local remote: Instance? = gun and gun:FindFirstChild("Shoot")
        local origin: CFrame? = getGunOriginCFrame(character, gun)

        local info: any = nil
        local reason: string? = nil
        if origin then
            local ok: boolean, endpoint: any, aimInfo: any, aimReason: any =
                pcall(prediction.gunAim, target, origin.Position)
            if not ok then return reject("Aim or visibility check failed.") end
            if endpoint == nil then
                reason = aimReason or "no samples"
            else
                info = aimInfo
            end
        end

        local rejectMessages: {[string]: string} = {
            ["no body"] = "The murderer has no usable body to aim at.",
            ["no samples"] = "The murderer has no fresh motion samples yet.",
            ["stale sample"] = "The murderer's position is stale; waiting for a fresh sample.",
            ["unreachable"] = "The murderer is moving too fast to intercept.",
        }
        if not remote
            or not remote:IsA("RemoteEvent")
            or not origin
            or not info then
            local message: string = rejectMessages[reason or ""]
                or (
                    not origin
                        and "The gun has no usable origin."
                        or "The murderer is unavailable or obstructed."
                )
            return reject(message)
        end

        local function safeToSend(shotOrigin: CFrame, shotEnd: CFrame): boolean
            if gun.Parent ~= character or gun.Enabled == false or gun:GetAttribute("Disabled") == true
                or gun:GetAttribute("Reloading") == true or gun:GetAttribute("IsReloading") == true then
                return reject("The gun is disabled or reloading.")
            end
            local ok, allowed, why, blocker, occluder = pcall(validateGunShot,target,character,targetCharacter,
                shotOrigin.Position,shotOrigin.Position,shotEnd.Position,mm2Settings.shootWallCheck)
            if not ok or not allowed then
                if type(blocker) == "table" and trajectoryCalibration
                    and type(trajectoryCalibration.noteBlockedShot) == "function" then
                    pcall(trajectoryCalibration.noteBlockedShot, trajectoryCalibration, blocker)
                end
                return reject(why or "Shot safety check failed.")
            end
            -- Cleared, but keep what the untouched ray met: a transparent solid
            -- short of the aim is exactly the case the client cannot see.
            if type(occluder) == "table" then
                lastGunOccluder = occluder
            else
                lastGunOccluder = nil
            end
            return true
        end

        -- Do not infer a reload from our last REQUEST: a rejected packet
        -- never proves the server fired. Native Tool/attribute readiness is
        -- checked above; no speculative 3.1-second local lockout.
        if silent then

            local variant: string = mm2Settings.silentSpawn
            local shotOrigin: CFrame?, shotEnd: CFrame?, offset: number =
                buildSilentShot(target, info, origin, variant)
            if not shotOrigin or not shotEnd then
                return reject("Another player blocks the silent shot.")
            end
            -- A near-target origin inside a body can make the engine miss that
            -- containing body. Fall back to the real muzzle, never a bypass.
            if not isWeaponPathClear(shotOrigin.Position,shotEnd.Position,targetCharacter,nil,{ignoreTarget=true}) then
                shotOrigin,shotEnd = origin,CFrame.new(info.endpoint)
            end
            if not safeToSend(shotOrigin,shotEnd) then return false end
            state.mm2ShotFeedback.queue(target, gun, shotOrigin, shotEnd)
            if state.mm2ShotFeedback.pending then
                state.mm2ShotFeedback.pending.silentSpawn = variant
            end

            state.lastSilentShotInfo = {
                variant = variant,
                at = os.clock(),
                offset = math.floor(offset * 10) / 10,
            }
            remote:FireServer(shotOrigin, shotEnd)

            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "gun",
                tool = gun,
                toolName = gun and gun.Name or "Gun",
                originPos = shotOrigin.Position,
                aimPos = shotEnd.Position,
                target = target,
                silent = true,
                variant = variant,
                offset = offset,
                settings = {mode = "Silent", spawn = variant,
                    sweep = mm2Settings.silentSweep, wallCheck = mm2Settings.shootWallCheck,
                    leadSeconds = info.leadSeconds, motionSource = info.motionSource,
                    model = info.model,
                    sampleAge = info.sampleAge, samples = info.samples,
                    referencePoint = info.capturedPosition and {info.capturedPosition.X, info.capturedPosition.Y, info.capturedPosition.Z},
                    predictedPoint = {info.endpoint.X, info.endpoint.Y, info.endpoint.Z},
                    sampledVelocity = {info.velocity.X, info.velocity.Y, info.velocity.Z},
                    rtt = info.rtt, echoDelay = info.echoDelay,
                    rttEngine = info.rttEngine, rttData = info.rttData,
                    occluder = lastGunOccluder,
                    echoSamples = info.echoSamples,
                    turnRate = info.turnRate, brakeSeconds = info.brakeSeconds},
            })
            if not quiet and ShootFeature then ShootFeature:SetStatus(nil) end
            macroUnequip(gun)
            return true
        end

        local shotEndCFrame: CFrame = CFrame.new(info.endpoint)
        if not safeToSend(origin, shotEndCFrame) then return false end
        state.mm2ShotFeedback.queue(target, gun, origin, shotEndCFrame)
        -- Author one endpoint, without speculative "piercing" past it.
        -- Echo timing documents transport/visual confirmation, NOT rewind
        -- duration or an authoritative hit-rate denominator.
        remote:FireServer(
            CFrame.lookAt(origin.Position, info.endpoint),
            shotEndCFrame
        )
        pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
            kind = "gun",
            tool = gun,
            toolName = gun and gun.Name or "Gun",
            originPos = origin.Position,
            aimPos = info.endpoint,
            target = target,
            silent = false,
            settings = {mode = "Normal", wallCheck = mm2Settings.shootWallCheck,
                leadSeconds = info.leadSeconds, motionSource = info.motionSource,
                model = info.model,
                sampleAge = info.sampleAge, samples = info.samples,
                referencePoint = info.capturedPosition and {info.capturedPosition.X, info.capturedPosition.Y, info.capturedPosition.Z},
                predictedPoint = {info.endpoint.X, info.endpoint.Y, info.endpoint.Z},
                sampledVelocity = {info.velocity.X, info.velocity.Y, info.velocity.Z},
                rtt = info.rtt, echoDelay = info.echoDelay,
                rttEngine = info.rttEngine, rttData = info.rttData,
                occluder = lastGunOccluder,
                echoSamples = info.echoSamples,
                turnRate = info.turnRate, brakeSeconds = info.brakeSeconds},
        })
        if not quiet and ShootFeature then ShootFeature:SetStatus(nil) end
        macroUnequip(gun)
        return true
    end

    local shootOptionsReady: boolean = false
    local shootFeatureActive: boolean = false
    local autoShootActive: boolean = false
    local autoShootWanted: boolean = false
    local updateAutoShootConnection: (() -> ())? = nil

    local function refreshShootInfrastructure(): ()
        local wantActive: boolean = shootFeatureActive or autoShootActive
        state.mm2ShotFeedback.shootActive = wantActive
        if wantActive then
            local weaponService: any = getWeaponServiceModule()
            if type(weaponService) == "table" then
                connectGunFiredSignal(weaponService)
            end
            return
        end
        disconnectGunFiredObserver()
        state.mm2ShotFeedback.pending = nil
        state.mm2ShotFeedback.lastAccepted = nil
        state.mm2ShotFeedback.hide()
    end

    local manualShotPending: boolean = false
    local function triggerManualShot(): ()
        if not shootFeatureActive then
            notify("Enable SilentAIM first.")
            return
        end
        if manualShotPending then return end
        local character, humanoid = getCharacterParts()
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun")
        if not character or not humanoid or not gun then
            notify("No sheriff gun is available.")
            return
        end
        manualShotPending = true
        local ok: boolean, message: any = pcall(function(): ()
            if gun.Parent ~= character then
                humanoid:EquipTool(gun)
                -- Let the grip/muzzle update before sampling its origin.
                RunService.Heartbeat:Wait()
            end
            -- Never re-equip if the user switched away during that frame.
            if shootFeatureActive and LocalPlayer.Character == character and gun.Parent == character then
                fireGunAtTarget(getSelectedShootTarget(), {whenReady = true})
            end
        end)
        manualShotPending = false
        if not ok then notify("Shoot failed: " .. tostring(message)) end
    end

    local function toggleShootMurderer(enabled: boolean): ()
        shootFeatureActive = enabled
        state.mm2SilentAimEnabled = enabled
        if state.mm2KnifeThrowRefresh then state.mm2KnifeThrowRefresh() end
        autoShootActive = shootFeatureActive and autoShootWanted
        refreshShootInfrastructure()
        if updateAutoShootConnection then updateAutoShootConnection() end
    end

    local lastAutoStatus: string? = nil
    local function autoStatus(message: string): ()
        if ShootFeature and lastAutoStatus ~= message then
            lastAutoStatus = message
            ShootFeature:SetStatus(message)
        end
    end

    local function autoShootTick(): ()
        if not shootFeatureActive or not autoShootActive then return end
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun", true)
        if not gun or gun.Parent ~= LocalPlayer.Character then
            autoStatus("Equip gun")
            return
        end
        local target: Player? = getSelectedShootTarget()
        if not target then autoStatus("No target"); return end
        lastRejectReason = ""
        local sent: boolean = fireGunAtTarget(target, {whenReady = true, quiet = true})
        autoStatus(sent and "Auto: request sent" or lastRejectReason)
    end

    updateAutoShootConnection = function(): ()
        disconnectFeatureConnection("MM2AutoShoot")
        autoShootActive = shootOptionsReady and shootFeatureActive and autoShootWanted
        if not autoShootActive then
            lastAutoStatus = nil
            if ShootFeature then ShootFeature:SetStatus(nil) end
            return
        end
        -- One attempt per current frame, with no range/confidence/fire-delay
        -- timer. No cached aim or visibility survives into the next attempt.
        featureConnections.MM2AutoShoot = TaskManager:Connect(autoShootTick)
        autoShootTick()
    end

    local function toggleAutoShoot(enabled: boolean): ()
        autoShootWanted = enabled
        autoShootActive = shootFeatureActive and autoShootWanted
        refreshShootInfrastructure()
        if updateAutoShootConnection then updateAutoShootConnection() end
    end

    -- Preserve explicit bindings and enabled state when the old card becomes
    -- a child option. Never overwrite a setting already saved for the child.
    if type(configData) == "table" then
        local changed: boolean = false
        if configData.states["MM2.Shoot.AutoShoot"] == nil and configData.states["MM2.AutoShoot"] ~= nil then
            local enabled: boolean = configData.states["MM2.AutoShoot"] == true
            configData.states["MM2.Shoot.AutoShoot"] = enabled
            if enabled then configData.states["MM2.Shoot"] = true end
            changed = true
        end
        local oldKey: any = configData.values["Shortcut.MM2AutoShoot"]
        if configData.values["Shortcut.MM2ShootAutoShoot"] == nil and type(oldKey) == "string" then
            configData.values["Shortcut.MM2ShootAutoShoot"] = oldKey
            changed = true
        end
        if changed and type(queueConfigSave) == "function" then queueConfigSave() end
    end

    if type(configData) == "table" and configData.values["MM2.Shoot.Aimmethod"] == nil then
        configData.values["MM2.Shoot.Aimmethod"] = configData.values["MM2.Shoot.Mode"]
    end
    ShootFeature = createUniversalFeature(
        "SilentAIM",
        "Gun aim and Knife Throw. The main assigned key fires/equips Gun; Auto Shoot and Knife Throw use your held weapon. Every shot uses the kinematic predictor with the game-filter WallCheck.",
        4,
        toggleShootMurderer,
        {
            categoryName = "Combat",
            configKey = "MM2.Shoot", -- preserve existing Gun settings and activation key
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2SilentAimFeature = ShootFeature
    -- One card, two weapons: the heading keeps the gun rows together and the
    -- knife module opens its own section further down.
    if addSectionOption then addSectionOption(ShootFeature, "Gun") end
    addToggleOption(ShootFeature, "Auto Shoot", false, toggleAutoShoot,
        "While SilentAIM is ON and you hold the gun: try every frame as soon as the current target is visible. No distance or prediction-confidence gate. Uses the Gun aim method.", true)
    local ShootTargetBox
    local wallCheckRow: GuiObject? = nil
    local silentSweepRow: GuiObject? = nil
    local silentSpawnRow: GuiObject? = nil
    local spawnStatsRow: GuiObject? = nil
    local leadOffsetRow: GuiObject? = nil
    local function refreshShootOptions(): ()
        if ShootTargetBox then
            setOptionVisible(
                ShootFeature,
                ShootTargetBox.Parent :: GuiObject,
                mm2Settings.shootMode == "Custom"
            )
        end
        -- Silent-only controls stay hidden while the mode is Prediction.
        local silent: boolean = mm2Settings.silentAim == true
        if wallCheckRow then setOptionVisible(ShootFeature, wallCheckRow, true) end
        if silentSweepRow then
            setOptionVisible(ShootFeature, silentSweepRow :: GuiObject, silent)
        end
        if silentSpawnRow then
            setOptionVisible(ShootFeature, silentSpawnRow :: GuiObject, silent)
        end
        if spawnStatsRow then
            setOptionVisible(ShootFeature, spawnStatsRow :: GuiObject, silent)
        end
        -- The manual offset only exists as an advanced fallback; automatic
        -- lead is the default and needs no tuning.
        if leadOffsetRow then
            setOptionVisible(
                ShootFeature,
                leadOffsetRow :: GuiObject,
                prediction.settings.autoLead ~= true
            )
        end
    end
    addCycleOption(
        ShootFeature,
        "Aim method",
        {"Prediction", "Silent AIM"},
        mm2Settings.silentAim and 2 or 1,
        function(value: string): ()
            mm2Settings.silentAim = value == "Silent AIM"
            refreshShootOptions()
        end,
        "Prediction fires from the gun; Silent AIM uses a near-target origin. "
            .. "Both respect WallCheck and always protect other players."
    )
    addCycleOption(
        ShootFeature,
        "Target",
        {"Murder", "Custom"},
        mm2Settings.shootMode == "Custom" and 2 or 1,
        function(value: string): ()
            mm2Settings.shootMode = value
            refreshShootOptions()
        end
    )

    if state.bindFeatureActivationKey then
        state.bindFeatureActivationKey(
            ShootFeature,
            mm2Settings.shootKey,
            triggerManualShot
        )
    end
    local wallButton = addToggleOption(
        ShootFeature,
        "WallCheck",
        mm2Settings.shootWallCheck,
        function(value: boolean): ()
            mm2Settings.shootWallCheck = value
        end,
        "Check the fired segment with the game's own WeaponService filter: "
            .. "WeaponPassthrough tags and invisible layers are ignored and the "
            .. "first solid surface or player blocks the shot. Applies to gun and knife."
    )
    wallCheckRow = wallButton and wallButton.Parent
    addToggleOption(
        ShootFeature,
        "Macro",
        shootMacro,
        function(value: boolean): ()
            shootMacro = value
        end,
        "Pistol macro: hides the gun 0.01 seconds after every shot."
    )
    silentSweepRow = addNumberOption(
        ShootFeature,
        "Silent sweep",
        mm2Settings.silentSweep,
        0,
        MAX_SILENT_SWEEP,
        function(value: number): ()
            mm2Settings.silentSweep = math.clamp(value, 0, MAX_SILENT_SWEEP)
        end,
        "Exact extra distance in studs at each end of the silent shot ray, "
            .. "along measured horizontal movement. 0 disables it; max 1.5. "
            .. "No local physics change. Segments crossing another player are "
            .. "shortened and checked again, or rejected.",
        0.05
    )
    local silentSpawnValues: {string} = {"Front", "Through", "Top", "Behind"}
    local silentSpawnIndex: number = 1
    for valueIndex: number, value: string in ipairs(silentSpawnValues) do
        if value == mm2Settings.silentSpawn then
            silentSpawnIndex = valueIndex
        end
    end
    local silentSpawnButton = addCycleOption(
        ShootFeature,
        "Silent spawn",
        silentSpawnValues,
        silentSpawnIndex,
        function(value: string): ()
            mm2Settings.silentSpawn = value
        end,
        "Where the silent bullet is authored: Front = in front of the torso "
            .. "at torso height; Through = pierces the torso; Top = the old "
            .. "geometry (1.6 studs above); Behind = far side. Check Spawn A/B "
            .. "status to see which variant actually scores."
    )
    if silentSpawnButton then
        silentSpawnRow = silentSpawnButton.Parent :: GuiObject
    end
    local function spawnStatsText(): string
        local stats: any = state.mm2ShotFeedback and
            state.mm2ShotFeedback.spawnStats or {}
        local parts: {string} = {}
        for _, variant: string in ipairs({"Front", "Through", "Top", "Behind"}) do
            local s: any = stats[variant]
            if s and s.shots > 0 then
                table.insert(
                    parts,
                    string.format(
                        "%s %d/%d",
                        variant,
                        s.hits,
                        s.shots
                    )
                )
            end
        end
        if #parts == 0 then
            return "Spawn A/B: no silent shots counted yet."
        end
        return "Spawn A/B (hits/shots): " .. table.concat(parts, " · ")
    end
    local spawnStatsButton = addActionOption(ShootFeature, "Spawn A/B status", function(): ()
        notify(spawnStatsText())
    end)
    if spawnStatsButton then
        spawnStatsRow = spawnStatsButton.Parent :: GuiObject
    end
    local autoLeadButton = addToggleOption(
        ShootFeature,
        "Auto lead",
        true,
        function(value: boolean): ()
            prediction.settings.autoLead = value
            refreshShootOptions()
        end,
        "Recommended. Uses the measured FireServer -> GunFired echo (or your "
            .. "ping while it learns), the replication window and the sample "
            .. "age. It adapts to your FPS, device and network without manual "
            .. "tuning. Turn it off only to test a fixed manual offset.",
        false
    )
    if autoLeadButton then
        setOptionVisible(ShootFeature, autoLeadButton.Parent :: GuiObject, true)
    end
    leadOffsetRow = addNumberOption(
        ShootFeature,
        "Lead offset ms",
        math.round(prediction.settings.extraLead * 1000),
        -300,
        600,
        function(value: number): ()
            -- Typed values are not quantized by the UI, so 1 ms precision is
            -- real. The predictor adds this on top of echo/RTT + interpolation.
            prediction.settings.extraLead = math.clamp(value, -300, 600) / 1000
        end,
        "Manual timing correction in milliseconds, on top of the measured "
            .. "FireServer -> GunFired echo (or ping) and the replication "
            .. "interpolation. Type an exact value in the numeric box; the "
            .. "slider moves in 1 ms steps. Positive aims further ahead, "
            .. "negative closer, 0 keeps the measured model. Prediction status "
            .. "shows the resulting lead; it saturates at the model's cap.",
        1
    )
    addActionOption(ShootFeature, "Prediction status", function(): ()
        notify(prediction.status(getSelectedShootTarget()))
    end)
    addActionOption(ShootFeature, "Reset prediction", function(): ()
        if type(prediction.reset) == "function" then
            prediction.reset()
        end
        notify("Prediction history and echo samples cleared.")
    end)
    ShootTargetBox = addTextOption(ShootFeature, "Target player", "", function(
        value: string
    ): ()
        mm2Settings.shootTarget = value
    end, false)
    refreshShootOptions()

    -- The visible Auto control is at the top, but arming waits until saved
    -- aim method/target options below have all been restored.
    shootOptionsReady = true
    if updateAutoShootConnection then updateAutoShootConnection() end

    activeCleanup = function(): ()
        toggleShootMurderer(false)
        state.mm2SilentAimFeature = nil
        toggleAutoShoot(false)
        state.mm2ShotFeedback.hide()
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
