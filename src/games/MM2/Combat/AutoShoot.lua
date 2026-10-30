local Module = {
    Name = "MM2 Auto Shoot",
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
    assert(type(core) == "table", "MM2 Auto Shoot requires the MM2 core module")
    local prediction: any = state.mm2Prediction
    assert(type(prediction) == "table", "MM2 Auto Shoot requires MM2 Prediction")
    Module.Runtime = runtime

    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local isWeaponPathClear: any = core.isWeaponPathClear
    local getGunOriginCFrame: any = core.getGunOriginCFrame

    local settings = {
        mode = "Bullet",
        wallCheck = true,
        proximity = false,
        aura = 25,
    }

    local autoShootActive: boolean = false
    local AutoShootFeature: any = nil
    local toolConnections: {RBXScriptConnection} = {}
    local lastShotSentAt: number = 0
    local AUTO_SHOT_PACE_SECONDS: number = 0.22

    local function clearToolConnections(): ()
        for _, conn: RBXScriptConnection in ipairs(toolConnections) do
            pcall(function(): ()
                conn:Disconnect()
            end)
        end
        table.clear(toolConnections)
    end

    local function findLocalGun(): (Tool?, Model?, Humanoid?, BasePart?)
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
            gun = getPlayerWeapon(LocalPlayer, "Gun", false)
        end
        if not gun then
            local charGun: Instance? = character:FindFirstChild("Gun")
            if charGun and charGun:IsA("Tool") then
                gun = charGun
            end
        end
        if not gun then
            local backpack: Instance? = LocalPlayer:FindFirstChildOfClass("Backpack")
            local bpGun: Instance? = backpack and backpack:FindFirstChild("Gun")
            if bpGun and bpGun:IsA("Tool") then
                gun = bpGun
            end
        end
        return gun, character, humanoid, root
    end

    local function ensureGunEquipped(
        character: Model,
        humanoid: Humanoid,
        gun: Tool
    ): boolean
        if gun.Parent == character then
            return true
        end
        pcall(function(): ()
            humanoid:EquipTool(gun)
        end)
        if gun.Parent ~= character then
            pcall(function(): ()
                gun.Parent = character
            end)
        end
        return gun.Parent == character
    end

    local function resolveMurdererTarget(
        localRoot: BasePart,
        enforceProximity: boolean
    ): (Player?, BasePart?)
        local murderer: Player? = nil
        if type(findMurderer) == "function" then
            murderer = findMurderer()
        end
        if not murderer then
            local playersService: Players = game:GetService("Players")
            for _, player: Player in ipairs(playersService:GetPlayers()) do
                if player ~= LocalPlayer then
                    local role: any = type(getPlayerRole) == "function"
                        and getPlayerRole(player)
                        or nil
                    local hasKnife: boolean = type(getPlayerWeapon) == "function"
                        and getPlayerWeapon(player, "Knife", false) ~= nil
                    if role == "Murderer" or hasKnife then
                        murderer = player
                        break
                    end
                end
            end
        end
        if not murderer or murderer == LocalPlayer then
            return nil, nil
        end
        if type(isPlayerAlive) == "function" and not isPlayerAlive(murderer) then
            return nil, nil
        end
        if type(isProtectedTarget) == "function" and isProtectedTarget(murderer) then
            return nil, nil
        end
        local targetChar: Model? = murderer.Character
        local targetRoot: BasePart? = targetChar
            and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not targetRoot then
            return nil, nil
        end
        if enforceProximity then
            local okDist: boolean, distance: any = pcall(function(): any
                return (targetRoot.Position - localRoot.Position).Magnitude
            end)
            if okDist and type(distance) == "number" and distance > settings.aura then
                return nil, nil
            end
        end
        return murderer, targetRoot
    end

    local function computeTargetEndpoint(
        target: Player,
        targetRoot: BasePart,
        originPos: Vector3,
        aimMode: string?
    ): Vector3
        if type(prediction) == "table" and type(prediction.gunAim) == "function" then
            local ok: boolean, endpoint: any = pcall(
                prediction.gunAim,
                target,
                originPos,
                aimMode
            )
            if ok and typeof(endpoint) == "Vector3" then
                return endpoint
            end
        end
        local vel: Vector3 = Vector3.zero
        pcall(function(): ()
            vel = targetRoot.AssemblyLinearVelocity
        end)
        return targetRoot.Position + vel * 0.08
    end

    local function fireCFrameShotImmediate(
        target: Player,
        targetRoot: BasePart,
        character: Model,
        localRoot: BasePart,
        gun: Tool
    ): boolean
        local shootRemote: Instance? = gun:FindFirstChild("Shoot")
        if not (shootRemote and shootRemote:IsA("RemoteEvent")) then
            return false
        end
        if gun.Enabled == false
            or gun:GetAttribute("Disabled") == true
            or gun:GetAttribute("Reloading") == true
            or gun:GetAttribute("IsReloading") == true then
            return false
        end
        local originCF: CFrame = (type(getGunOriginCFrame) == "function"
            and getGunOriginCFrame(character, gun))
            or localRoot.CFrame
        local endpoint: Vector3 = computeTargetEndpoint(
            target,
            targetRoot,
            originCF.Position,
            "CFrame"
        )
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
                endpoint.X - originCF.Position.X,
                0,
                endpoint.Z - originCF.Position.Z
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
        local shotOrigin: CFrame = CFrame.lookAt(startPoint, endPoint)
        local shotEnd: CFrame = CFrame.new(endPoint)
        local firedSilent: boolean = false
        if type(state.mm2FireSilentShot) == "function" then
            -- v139.4: our own WallCheck has to travel with the request. The
            -- shared constructor used to be called with the target only and
            -- hardcoded continuous=true, so this mode fired with no geometry
            -- check and then, when it was refused, fell back to its own CFrame
            -- -- also unchecked.
            local okSilent: boolean, res: any = pcall(state.mm2FireSilentShot, target, {
                continuous = true,
                quiet = true,
                wallCheck = settings.wallCheck,
            })
            firedSilent = okSilent and res == true
            -- A false result or exception can mean a safety refusal or an
            -- uncertain send. Never bypass it or send a second request. Pace
            -- exceptions too: the send may have happened before the error.
            if not okSilent then lastShotSentAt = os.clock() end
            if not firedSilent then return false end
        end
        if not firedSilent then
            -- Never fire past a wall: the hand-rolled CFrame is only a
            -- transport fallback, not a bypass.
            local clear: boolean = false
            if settings.wallCheck and type(isWeaponPathClear) == "function" then
                local okClear: boolean, allowed: any = pcall(
                    isWeaponPathClear,
                    originCF.Position,
                    endpoint,
                    target.Character,
                    nil,
                    {ignoreTarget = true}
                )
                clear = okClear and allowed == true
            else
                clear = true
            end
            if clear then
                local okFire: boolean = pcall(function(): ()
                    (shootRemote :: RemoteEvent):FireServer(shotOrigin, shotEnd)
                end)
                if not okFire then
                    lastShotSentAt = os.clock()
                    return false
                end
            else
                lastShotSentAt = 0
                return false
            end
        end
        lastShotSentAt = os.clock()
        return true
    end

    local function fireBulletShotImmediate(
        target: Player,
        targetRoot: BasePart,
        character: Model,
        localRoot: BasePart,
        gun: Tool
    ): boolean
        local shootRemote: Instance? = gun:FindFirstChild("Shoot")
        if not (shootRemote and shootRemote:IsA("RemoteEvent")) then
            return false
        end
        if gun.Enabled == false
            or gun:GetAttribute("Disabled") == true
            or gun:GetAttribute("Reloading") == true
            or gun:GetAttribute("IsReloading") == true then
            return false
        end
        local originCF: CFrame = (type(getGunOriginCFrame) == "function"
            and getGunOriginCFrame(character, gun))
            or localRoot.CFrame
        local endpoint: Vector3 = computeTargetEndpoint(
            target,
            targetRoot,
            originCF.Position,
            "Bullet"
        )
        if settings.wallCheck and type(isWeaponPathClear) == "function" then
            local okClear: boolean, clear: any = pcall(
                isWeaponPathClear,
                originCF.Position,
                endpoint,
                target.Character
            )
            if not okClear or clear ~= true then
                return false
            end
        end
        local firedCore: boolean = false
        if type(state.mm2FireGunShot) == "function" then
            local okShot: boolean, res: any = pcall(state.mm2FireGunShot, target, {
                silent = false,
                wallCheck = settings.wallCheck,
                continuous = true,
                quiet = true,
            })
            firedCore = okShot and res == true
            -- Respect a refusal or uncertain send from the shared path.
            if not okShot then lastShotSentAt = os.clock() end
            if not firedCore then return false end
        end
        if not firedCore then
            local shotOrigin: CFrame = CFrame.lookAt(originCF.Position, endpoint)
            local shotEnd: CFrame = CFrame.new(endpoint)
            local okFire: boolean = pcall(function(): ()
                (shootRemote :: RemoteEvent):FireServer(shotOrigin, shotEnd)
            end)
            if not okFire then
                lastShotSentAt = os.clock()
                return false
            end
        end
        lastShotSentAt = os.clock()
        return true
    end

    -- Shared helper for Auto Win ("Insta Kill As Sheriff (Usa AutoShoot CFrame)")
    -- and Auto Shoot CFrame mode: equips the gun the instant the player
    -- receives it (whether as Sheriff, Hero, or Innocent who picked up GunDrop)
    -- and fires Silent AIM CFrame continuously until the Murderer is dead.
    local function executeAutoShootCFrameOnce(enforceProximity: boolean): boolean
        local gun: Tool?, character: Model?, humanoid: Humanoid?,
            localRoot: BasePart? = findLocalGun()
        if not gun or not character or not humanoid or not localRoot then
            lastShotSentAt = 0
            return false
        end
        local target: Player?, targetRoot: BasePart? =
            resolveMurdererTarget(localRoot, enforceProximity)
        if not target or not targetRoot then
            return false
        end
        if not ensureGunEquipped(character, humanoid, gun) then
            return false
        end
        if os.clock() - lastShotSentAt < AUTO_SHOT_PACE_SECONDS then
            return true
        end
        return fireCFrameShotImmediate(target, targetRoot, character, localRoot, gun)
    end
    state.mm2AutoShootCFrameOnce = executeAutoShootCFrameOnce

    local function autoShootTick(): ()
        if not autoShootActive then
            return
        end
        local gun: Tool?, character: Model?, humanoid: Humanoid?,
            localRoot: BasePart? = findLocalGun()
        if not gun or not character or not humanoid or not localRoot then
            lastShotSentAt = 0
            return
        end
        local target: Player?, targetRoot: BasePart? =
            resolveMurdererTarget(localRoot, settings.proximity == true)
        if not target or not targetRoot then
            return
        end
        if not ensureGunEquipped(character, humanoid, gun) then
            return
        end
        if os.clock() - lastShotSentAt < AUTO_SHOT_PACE_SECONDS then
            return
        end
        local isCFrame: boolean = settings.mode == "CFrame"
            or settings.mode == "Cframe"
            or settings.mode == "Silent AIM"
        if settings.mode == "Experimental" then
            -- Share Gun Aimbot's selector and safety path, but use this card's
            -- own WallCheck/Proximity. Never send both on an uncertain result.
            local mode: string = "Bullet"
            if type(state.mm2ChooseExperimentalAim) == "function" then
                local origin: CFrame = (type(getGunOriginCFrame) == "function"
                    and getGunOriginCFrame(character, gun)) or localRoot.CFrame
                local okMode: boolean, chosen: any = pcall(state.mm2ChooseExperimentalAim, target, origin.Position)
                if okMode and chosen == "CFrame" then mode = "CFrame" end
            end
            local sent: boolean = false
            local uncertain: boolean = false
            if type(state.mm2FireGunShot) == "function" then
                local ok: boolean, result: any = pcall(state.mm2FireGunShot, target, {
                    silent = mode == "CFrame", wallCheck = settings.wallCheck,
                    continuous = true, quiet = true,
                })
                sent = ok and result == true
                -- A thrown error can happen after dispatch; pace rather than
                -- repeatedly sending on every frame while the result is unknown.
                uncertain = not ok
                if uncertain then lastShotSentAt = os.clock() end
            end
            if sent then lastShotSentAt = os.clock() end
            if AutoShootFeature then AutoShootFeature:SetStatus("Experimental · " .. mode
                .. (sent and " · request sent" or (uncertain and " · send uncertain" or " · not sent"))) end
        elseif isCFrame then
            fireCFrameShotImmediate(target, targetRoot, character, localRoot, gun)
        else
            fireBulletShotImmediate(target, targetRoot, character, localRoot, gun)
        end
    end

    local function watchToolContainer(container: Instance?): ()
        if not container or type((container :: any).ChildAdded) ~= "table"
            and typeof((container :: any).ChildAdded) ~= "RBXScriptSignal" then
            return
        end
        pcall(function(): ()
            local conn: RBXScriptConnection = (container :: any).ChildAdded:Connect(
                function(child: Instance): ()
                    if autoShootActive and child and child.Name == "Gun" then
                        autoShootTick()
                    end
                end
            )
            table.insert(toolConnections, conn)
        end)
    end

    local function setupInstantGunWatchers(): ()
        clearToolConnections()
        if not LocalPlayer then
            return
        end
        watchToolContainer(LocalPlayer.Character)
        watchToolContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
        pcall(function(): ()
            if LocalPlayer.CharacterAdded then
                table.insert(
                    toolConnections,
                    LocalPlayer.CharacterAdded:Connect(function(newChar: Model): ()
                        watchToolContainer(newChar)
                        watchToolContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
                    end)
                )
            end
            if LocalPlayer.ChildAdded then
                table.insert(
                    toolConnections,
                    LocalPlayer.ChildAdded:Connect(function(child: Instance): ()
                        if child and child:IsA("Backpack") then
                            watchToolContainer(child)
                        end
                    end)
                )
            end
        end)
    end

    local function updateStatus(): ()
        if not AutoShootFeature or not AutoShootFeature.enabled then
            return
        end
        if settings.proximity then
            AutoShootFeature:SetStatus(
                settings.mode .. " · " .. tostring(settings.aura) .. " studs"
            )
        else
            AutoShootFeature:SetStatus(settings.mode)
        end
    end

    -- v139: this card and the MM2 "Shoot" card both used the key MM2AutoShoot,
    -- so enabling both lost one handle and left a ghost task firing every frame
    -- after the card was switched off. Each card owns its own key now, and the
    -- connection is dropped before a new one is made.
    local CONNECTION_KEY: string = "MM2AutoShootCard"

    local function toggleAutoShoot(enabled: boolean): ()
        autoShootActive = enabled == true
        if enabled then
            updateStatus()
            setupInstantGunWatchers()
            disconnectFeatureConnection(CONNECTION_KEY)
            featureConnections[CONNECTION_KEY] = TaskManager:Connect(
                autoShootTick,
                nil,
                "Auto Shoot"
            )
            autoShootTick()
        else
            clearToolConnections()
            disconnectFeatureConnection(CONNECTION_KEY)
            if AutoShootFeature then
                AutoShootFeature:SetStatus(nil)
            end
        end
    end

    AutoShootFeature = createUniversalFeature(
        "Auto Shoot",
        "Automatically equips the Gun the instant you receive it (as Sheriff or Hero) and shoots the Murderer continuously using Bullet (respects WallCheck) or CFrame (Silent AIM). Optional Proximity radius filter.",
        4,
        toggleAutoShoot,
        {
            categoryName = "Combat",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoShootFeature = AutoShootFeature

    local auraSlider: GuiObject? = nil
    local states: any = type(configData) == "table" and configData.states or {}
    local values: any = type(configData) == "table" and configData.values or {}
    local initialMode: string = values["MM2.AutoShoot.Mode"] or "Bullet"
    if initialMode ~= "CFrame" and initialMode ~= "Experimental" then initialMode = "Bullet" end
    local function modeConfig(mode: string): any
        local prefix: string = "MM2.AutoShoot." .. mode .. "."
        local legacy: boolean = mode == initialMode
        local wall: any = states[prefix .. "WallCheck"]
        local proximity: any = states[prefix .. "Proximity"]
        local aura: any = values[prefix .. "Aura"]
        if wall == nil and legacy then wall = states["MM2.AutoShoot.WallCheck"] end
        if proximity == nil and legacy then proximity = states["MM2.AutoShoot.Proximity"] end
        if aura == nil and legacy then aura = values["MM2.AutoShoot.Aura"] end
        return {wallCheck = wall == nil or wall == true, proximity = proximity == true,
            aura = type(aura) == "number" and aura or 25}
    end
    local modeConfigs: any = {Bullet = modeConfig("Bullet"), CFrame = modeConfig("CFrame"),
        Experimental = modeConfig("Experimental")}
    local switching: boolean = false
    local optionsReady: boolean = false
    local function refreshProximityOption(): ()
        if auraSlider and type(setOptionVisible) == "function" then
            setOptionVisible(AutoShootFeature, auraSlider.Parent :: GuiObject, settings.proximity == true)
        end
        updateStatus()
    end
    local function syncMode(): ()
        local cfg: any = modeConfigs[settings.mode] or modeConfigs.Bullet
        switching = true
        settings.wallCheck, settings.proximity, settings.aura = cfg.wallCheck, cfg.proximity, cfg.aura
        if state and type(state.toggleControls) == "table" then
            local wc: any = state.toggleControls["MM2.AutoShoot.WallCheck"]
            local px: any = state.toggleControls["MM2.AutoShoot.Proximity"]
            if wc and wc.setChecked then pcall(wc.setChecked, cfg.wallCheck) end
            if px and px.setChecked then pcall(px.setChecked, cfg.proximity) end
        end
        if state and type(state.valueControls) == "table" then
            local au: any = state.valueControls["MM2.AutoShoot.Aura"]
            if au and au.apply then pcall(au.apply, cfg.aura) end
        end
        switching = false
        refreshProximityOption()
    end
    addCycleOption(AutoShootFeature, "Mode", {"Bullet", "CFrame", "Experimental"}, 1,
        function(value: string): () settings.mode = value; syncMode() end,
        "Experimental selects one path based on range and movement; the heuristic does not guarantee hits. Options are independent per mode.")
    addToggleOption(AutoShootFeature, "WallCheck", true, function(value: boolean): ()
        settings.wallCheck = value == true
        if optionsReady and not switching then
            modeConfigs[settings.mode].wallCheck = settings.wallCheck
            states["MM2.AutoShoot." .. settings.mode .. ".WallCheck"] = settings.wallCheck
        end
    end, "Check for walls; saved independently per mode.")
    addToggleOption(AutoShootFeature, "Proximity", false, function(value: boolean): ()
        settings.proximity = value == true
        if optionsReady and not switching then
            modeConfigs[settings.mode].proximity = settings.proximity
            states["MM2.AutoShoot." .. settings.mode .. ".Proximity"] = settings.proximity
        end
        refreshProximityOption()
    end, "Only shoot inside Aura radius; saved independently per mode.")
    auraSlider = addNumberOption(AutoShootFeature, "Aura", 25, 5, 150, function(value: number): ()
        settings.aura = value
        if optionsReady and not switching then
            modeConfigs[settings.mode].aura = value
            values["MM2.AutoShoot." .. settings.mode .. ".Aura"] = value
        end
        if AutoShootFeature.enabled then AutoShootFeature:SetStatus(tostring(value) .. " studs") end
    end, "Maximum distance with Proximity enabled, saved per mode.", 1)
    optionsReady = true
    syncMode()

    activeCleanup = function(): ()
        toggleAutoShoot(false)
        state.mm2AutoShootFeature = nil
        state.mm2AutoShootCFrameOnce = nil
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
