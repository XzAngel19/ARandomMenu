local Module = {
    Name = "MM2 Notifications",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Notifications requires the MM2 core")
    Module.Runtime = runtime

    -- Instant Roles used to be an independent Blurt Roles checkbox. Preserve
    -- both its value and its old independent-on behavior, without overriding a
    -- newer Notifications master setting on subsequent boots.
    if type(configData) == "table" and type(configData.states) == "table" then
        local states: any = configData.states
        local oldKey: string = "MM2.BlurtRoles.InstantRoles"
        local newKey: string = "MM2.Notifications.InstantRoles"
        local old: any = states[oldKey]
        local changed: boolean = false
        if states[newKey] == nil and type(old) == "boolean" then
            states[newKey] = old
            if old and states["MM2.Notifications"] == nil then
                states["MM2.Notifications"] = true
            end
            changed = true
        end
        if old ~= nil then states[oldKey] = nil; changed = true end
        if changed and type(queueConfigSave) == "function" then queueConfigSave() end
    end

    local settings: any = {
        instantRoles = false,
        gun = true,
        murderClose = true,
        yourRole = true,
        roundEvents = true,
        murderDefeated = true,
    }
    local enabled: boolean = false
    local phase: string = type(core.getRoundPhase) == "function" and core.getRoundPhase() or "unknown"
    local elapsed: number = 0
    local murdererSeen: boolean = false
    local sheriffSeen: boolean = false
    local lastLocalRole: string? = nil
    local lastMurderer: Player? = nil
    local defeatNotified: boolean = false
    local nearMurderer: boolean = false
    local lastCloseAt: number = -math.huge
    local gunWasDropped: boolean = false
    local gunLastSeenAt: number = -math.huge
    local gunDropPreviousHolder: Player? = nil
    local lastGunHolder: Player? = nil
    local gunHolderInitialized: boolean = false

    local function resetRound(): ()
        murdererSeen = false
        sheriffSeen = false
        lastLocalRole = nil
        lastMurderer = nil
        defeatNotified = false
        nearMurderer = false
        lastCloseAt = -math.huge
        gunWasDropped = false
        gunLastSeenAt = -math.huge
        gunDropPreviousHolder = nil
        lastGunHolder = nil
        gunHolderInitialized = false
    end

    local function inRound(): boolean
        if type(core.isRoundLifecycleActive) == "function"
            and core.isRoundLifecycleActive() == false then return false end
        if phase == "lobby" then return false end
        return phase == "map" or (type(core.hasActiveRoundRoles) == "function" and core.hasActiveRoundRoles())
    end

    local function rootOf(player: Player?): BasePart?
        local character: Model? = player and player.Character
        return character and character:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
    end

    local function isAlive(player: Player?): boolean
        if not player then return false end
        if type(core.isPlayerAlive) == "function" then return core.isPlayerAlive(player) == true end
        return rootOf(player) ~= nil
    end

    local function showRoles(murderer: Player?, sheriff: Player?): ()
        if not enabled or not settings.instantRoles or not inRound() then return end
        if not murdererSeen and not sheriffSeen and murderer and sheriff then
            murdererSeen = true
            sheriffSeen = true
            notify("Roles ready - Murderer: " .. murderer.Name .. " | Sheriff/Hero: " .. sheriff.Name)
            return
        end
        if murderer and not murdererSeen then
            murdererSeen = true
            notify("Murderer: " .. murderer.Name)
        end
        if sheriff and not sheriffSeen then
            sheriffSeen = true
            notify("Sheriff/Hero: " .. sheriff.Name)
        end
    end

    local function gunDistance(drop: Instance?): number?
        local root: BasePart? = rootOf(LocalPlayer)
        if not root or not drop then return nil end
        local ok: boolean, distance: any = pcall(function(): number
            local position: Vector3 = if drop:IsA("BasePart")
                then (drop :: BasePart).Position
                else (drop :: Model):GetPivot().Position
            return (position - root.Position).Magnitude
        end)
        return if ok and type(distance) == "number" then distance else nil
    end

    local function updateGun(sheriff: Player?): ()
        if not settings.gun or type(core.findDroppedGun) ~= "function" then return end
        local now: number = os.clock()
        local drop: Instance? = core.findDroppedGun()
        local holder: Player? = nil
        if sheriff and isAlive(sheriff) and type(core.getPlayerWeapon) == "function"
            and core.getPlayerWeapon(sheriff, "Gun") ~= nil then holder = sheriff end
        if drop then
            if not gunWasDropped then
                -- The previous owner's Tool may still replicate briefly after
                -- the drop appears. It is not evidence they picked it back up.
                gunDropPreviousHolder = lastGunHolder or holder
                local distance: number? = gunDistance(drop)
                notify("Gun dropped" .. (distance and (" · " .. tostring(math.round(distance)) .. " studs away") or ""))
            end
            gunWasDropped = true
            gunLastSeenAt = now
        elseif gunWasDropped and holder and holder ~= gunDropPreviousHolder then
            notify("Gun picked up by " .. holder.Name)
            gunWasDropped = false
            gunDropPreviousHolder = nil
        elseif gunWasDropped and now - gunLastSeenAt >= 2 then
            -- Missing/streamed-out is not proof of a pickup.
            gunWasDropped = false
            gunDropPreviousHolder = nil
        elseif holder and gunHolderInitialized and lastGunHolder and holder ~= lastGunHolder then
            notify("Gun is now held by " .. holder.Name)
        end
        if holder then
            lastGunHolder = holder
            gunHolderInitialized = true
        end
    end

    local function confirmedDead(player: Player?): boolean
        if not player then return false end
        -- getPlayerRole can infer Dead when a character streams out. Only
        -- explicit round data or a visible zero-health humanoid is evidence.
        if type(core.getRoundRole) == "function" and core.getRoundRole(player) == "Dead" then return true end
        local character: Model? = player.Character
        local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        return humanoid ~= nil and humanoid.Health <= 0
    end

    local function updateProximity(murderer: Player?): ()
        if not settings.murderClose or not murderer or murderer == LocalPlayer
            or not isAlive(LocalPlayer) or not isAlive(murderer) then
            nearMurderer = false
            return
        end
        local localRoot: BasePart? = rootOf(LocalPlayer)
        local murderRoot: BasePart? = rootOf(murderer)
        if not localRoot or not murderRoot then nearMurderer = false; return end
        local distance: number = (murderRoot.Position - localRoot.Position).Magnitude
        local now: number = os.clock()
        if distance <= 30 and not nearMurderer and now - lastCloseAt >= 8 then
            nearMurderer = true
            lastCloseAt = now
            notify("Murderer close: " .. murderer.Name .. " · " .. tostring(math.round(distance)) .. " studs")
        elseif distance > 38 then
            nearMurderer = false
        end
    end

    local function sample(): ()
        if not enabled or not inRound() then return end
        local murderer: Player? = type(core.findMurderer) == "function" and core.findMurderer() or nil
        local sheriff: Player? = type(core.findSheriff) == "function" and core.findSheriff() or nil
        if murderer then lastMurderer = murderer end
        showRoles(murderer, sheriff)
        if settings.yourRole and type(core.getPlayerRole) == "function" then
            local myRole: any = core.getPlayerRole(LocalPlayer)
            if (myRole == "Innocent" or myRole == "Sheriff" or myRole == "Hero" or myRole == "Murderer")
                and myRole ~= lastLocalRole then
                lastLocalRole = myRole
                notify("Your role: " .. myRole)
            end
        end
        updateGun(sheriff)
        updateProximity(murderer)
        if settings.murderDefeated and not defeatNotified and confirmedDead(lastMurderer) then
            defeatNotified = true
            notify("Murderer defeated: " .. (lastMurderer :: Player).Name)
        end
    end

    local nextWarningAt: number = -math.huge
    local sampling: boolean = false
    local sampleAgain: boolean = false
    local function trySample(): ()
        -- A role lookup can rebuild the core index and synchronously emit
        -- onRoundRoles. Coalesce that callback instead of recursing into a
        -- partially updated sample; the regular tick handles further changes.
        if sampling then sampleAgain = true; return end
        sampling = true
        for _pass: number = 1, 2 do
            sampleAgain = false
            local ok: boolean, err: any = pcall(sample)
            if not ok and os.clock() >= nextWarningAt then
                nextWarningAt = os.clock() + 5
                warn("MM2 Notifications: " .. tostring(err))
            end
            if not sampleAgain or not enabled then break end
        end
        sampling = false
    end

    local unsubscribeRoles: () -> () = core.onRoundRoles(function(active: boolean): ()
        if active and enabled then trySample() end
    end)
    local unsubscribePhase: () -> () = core.onRoundPhase(function(nextPhase: string, reason: string): ()
        local previous: string = phase
        phase = nextPhase
        if nextPhase == "lobby" and previous ~= "lobby" then
            if enabled and settings.roundEvents and previous == "map" and reason ~= "subscribe" then
                notify("Round ended")
            end
            resetRound()
        elseif nextPhase == "map" and previous ~= "map" then
            resetRound()
            if enabled and settings.roundEvents and reason ~= "subscribe" then
                notify("Entered the map - round starting")
            end
            if enabled then trySample() end
        end
    end)

    local function toggleNotifications(value: boolean): ()
        enabled = value == true
        disconnectFeatureConnection("MM2NotificationsTick")
        elapsed = 0
        if not enabled then return end
        trySample()
        featureConnections.MM2NotificationsTick = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += math.max(0, deltaTime)
            if elapsed < 0.25 then return end
            elapsed = 0
            trySample()
        end, nil, "MM2 Notifications")
    end

    local feature: any = createUniversalFeature(
        "Notifications", "Private MM2 alerts for roles, the gun, nearby danger and rounds.",
        4, toggleNotifications,
        {categoryName = "Utilities", parent = MM2Scroll, registry = mm2Features}
    )
    addToggleOption(feature, "Instant Roles", false, function(value: boolean): ()
        settings.instantRoles = value
        core.mm2Settings.instantRoleNotify = value
        if enabled and value then trySample() end
    end, "Private role alerts as soon as each role is known; never sends public chat.")
    addToggleOption(feature, "Gun Notification", true, function(value: boolean): ()
        settings.gun = value
        if not value then
            gunWasDropped = false
            gunDropPreviousHolder = nil
            lastGunHolder = nil
            gunHolderInitialized = false
        elseif enabled then
            trySample()
        end
    end, "Announces a dropped gun and a confirmed new holder.")
    addToggleOption(feature, "Murder Close", true, function(value: boolean): ()
        settings.murderClose = value
        if enabled and value then trySample() end
    end, "Warns when the living Murderer is within 30 studs; includes a cooldown.")
    addToggleOption(feature, "Your Role", true, function(value: boolean): ()
        settings.yourRole = value
        if enabled and value then trySample() end
    end, "Notifies you when your role becomes known or changes.")
    addToggleOption(feature, "Round Events", true, function(value: boolean): ()
        settings.roundEvents = value
    end, "Private alerts for entering the map and the round ending.")
    addToggleOption(feature, "Murderer Defeated", true, function(value: boolean): ()
        settings.murderDefeated = value
        if enabled and value then trySample() end
    end, "Warns only when the known Murderer is confirmed dead.")
    addInformationOption(feature, "These alerts are private. Blurt Roles is the separate public-chat feature.")

    activeCleanup = function(): ()
        toggleNotifications(false)
        pcall(unsubscribeRoles)
        pcall(unsubscribePhase)
        core.mm2Settings.instantRoleNotify = false
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then return end
    Module.Initialized = false
    activeCleanup()
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
