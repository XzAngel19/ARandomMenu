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
        originPos: Vector3
    ): Vector3
        if type(prediction) == "table" and type(prediction.gunAim) == "function" then
            local ok: boolean, endpoint: any = pcall(
                prediction.gunAim,
                target,
                originPos
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
            originCF.Position
        )
        local lookDir: Vector3 = Vector3.new(0, 0, -1)
        pcall(function(): ()
            lookDir = targetRoot.CFrame.LookVector
        end)
        local startPoint: Vector3 = endpoint - lookDir * 2.5 + Vector3.new(0, 1.2, 0)
        if (startPoint - endpoint).Magnitude < 0.2 then
            startPoint = endpoint + Vector3.new(0, 2.0, -2.5)
        end
        local shotOrigin: CFrame = CFrame.lookAt(startPoint, endpoint)
        local shotEnd: CFrame = CFrame.new(endpoint)
        local firedSilent: boolean = false
        if type(state.mm2FireSilentShot) == "function" then
            local okSilent: boolean, res: any = pcall(state.mm2FireSilentShot, target)
            firedSilent = okSilent and res == true
        end
        if not firedSilent then
            pcall(function(): ()
                (shootRemote :: RemoteEvent):FireServer(shotOrigin, shotEnd)
            end)
        end
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
            originCF.Position
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
        end
        if not firedCore then
            local shotOrigin: CFrame = CFrame.lookAt(originCF.Position, endpoint)
            local shotEnd: CFrame = CFrame.new(endpoint)
            pcall(function(): ()
                (shootRemote :: RemoteEvent):FireServer(shotOrigin, shotEnd)
            end)
        end
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
        local isCFrame: boolean = settings.mode == "CFrame"
            or settings.mode == "Cframe"
            or settings.mode == "Silent AIM"
        if isCFrame then
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

    local function toggleAutoShoot(enabled: boolean): ()
        autoShootActive = enabled == true
        if enabled then
            updateStatus()
            setupInstantGunWatchers()
            featureConnections.MM2AutoShoot = TaskManager:Connect(autoShootTick)
            autoShootTick()
        else
            clearToolConnections()
            disconnectFeatureConnection("MM2AutoShoot")
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
    local function refreshProximityOption(): ()
        if auraSlider and type(setOptionVisible) == "function" then
            setOptionVisible(
                AutoShootFeature,
                auraSlider.Parent :: GuiObject,
                settings.proximity == true
            )
        end
        updateStatus()
    end

    addCycleOption(AutoShootFeature, "Mode", {"Bullet", "CFrame"}, 1,
        function(value: string): ()
            settings.mode = value
            updateStatus()
        end,
        "Bullet: shoots continuously while respecting WallCheck. CFrame: shoots immediately with Silent AIM CFrame upon receiving the gun.")

    addToggleOption(AutoShootFeature, "WallCheck", true,
        function(value: boolean): ()
            settings.wallCheck = value
        end,
        "In Bullet mode, only shoot when there is a clear line of sight to the Murderer.")

    addToggleOption(AutoShootFeature, "Proximity", false,
        function(value: boolean): ()
            settings.proximity = value == true
            refreshProximityOption()
        end,
        "When enabled, only shoot when the Murderer enters the configured radius.")

    auraSlider = addNumberOption(AutoShootFeature, "Aura", 25, 5, 150,
        function(value: number): ()
            settings.aura = value
            if AutoShootFeature.enabled then
                AutoShootFeature:SetStatus(tostring(value) .. " studs")
            end
        end,
        "Maximum distance in studs to automatically shoot at the Murderer while Proximity is ON.", 1)

    refreshProximityOption()

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
