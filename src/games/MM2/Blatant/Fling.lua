local Module = {
    Name = "MM2 Fling",
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(runtime: any): any
    local host: any = state.frameworkEnvironment
    local core: any = state.mm2Core
    local physics: any = state.flingPhysics
    assert(core, "MM2 Fling requires the MM2 core")
    assert(physics, "MM2 Fling requires the shared physics library")

    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local protectedTargets: any = services.protectedTargets
    local gameBridge: any = services.gameBridge
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addToggleOption: any = host.addToggleOption
    local addTextOption: any = host.addTextOption
    local addInformationOption: any = host.addInformationOption
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local findPlayerByText: any = host.findPlayerByText

    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive

    local flingTargetName: string = ""
    local autoFlingSelected: boolean = false
    local lastAutoFlingAt: number = 0
    local sequenceNumber: number = 0

    local function roundIsActive(): boolean
        if type(core.isRoundLifecycleActive) ~= "function" then
            return false
        end
        local ok: boolean, active: any = pcall(core.isRoundLifecycleActive)
        if not ok or active ~= true then
            return false
        end
        if type(core.findMM2Map) == "function" then
            local okMap: boolean, map: any = pcall(core.findMM2Map)
            return okMap and map ~= nil
        end
        return true
    end

    local function localIsAlive(): boolean
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            getCharacterParts()
        return character ~= nil and humanoid ~= nil and root ~= nil
            and humanoid.Health > 0 and root.Parent ~= nil
    end

    local function targetIsValid(target: Player?): boolean
        if not target or target == LocalPlayer or target.Parent ~= Players
            or protectedTargets.isProtected(target) then
            return false
        end
        if type(isPlayerAlive) == "function" and not isPlayerAlive(target) then
            return false
        end
        local character: Model? = target.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? = (humanoid and humanoid.RootPart)
            or (character and character:FindFirstChild("HumanoidRootPart") :: BasePart?)
        return character ~= nil and humanoid ~= nil and root ~= nil
            and humanoid.Health > 0 and root.Parent ~= nil and not root.Anchored
    end

    local function canAct(target: Player?): boolean
        return Module.Initialized and roundIsActive() and localIsAlive()
            and targetIsValid(target)
    end

    local function performFling(targetPlayer: Player?, options: {[string]: any}?): boolean
        local silent: boolean = type(options) == "table" and options.silent == true
        if not canAct(targetPlayer) then
            if not silent and Module.Initialized and not roundIsActive() then
                notify("Fling requires an active MM2 round.")
            elseif not silent then
                notify("No living, valid fling target is available.")
            end
            return false
        end
        if physics.isRunning() then
            if not silent then
                notify("A fling is already running.")
            end
            return false
        end
        if physics.isTouchEnabled() then
            if type(state.setTouchFlingEnabled) == "function" then
                state.setTouchFlingEnabled(false)
            else
                physics.setTouchEnabled(false)
            end
        end

        local externalStop: any = type(options) == "table"
            and options.shouldStop or nil
        local duration: number = if type(options) == "table"
            then tonumber(options.duration) or 1.4
            else 1.4
        if duration ~= duration or math.abs(duration) == math.huge then
            duration = 1.4
        end
        duration = math.clamp(duration, 0.1, 3)
        local started: boolean = physics.start(targetPlayer, {
            duration = duration,
            blocking = type(options) == "table" and options.blocking == true,
            returnCFrame = type(options) == "table"
                and options.returnCFrame or nil,
            restorePosition = if type(options) == "table"
                then options.restorePosition else nil,
            shouldStop = function(): boolean
                if not canAct(targetPlayer) then
                    return true
                end
                if type(externalStop) == "function" then
                    local ok: boolean, stop: any = pcall(externalStop)
                    return not ok or stop == true
                end
                return false
            end,
        })
        if started and type(options) == "table" and options.blocking == true then
            local deadline: number = os.clock() + math.clamp(duration, 0.1, 3) + 0.5
            while physics.isRunning() and os.clock() < deadline do
                if not canAct(targetPlayer) then
                    physics.cancel()
                    break
                end
                if type(externalStop) == "function" then
                    local ok: boolean, stop: any = pcall(externalStop)
                    if not ok or stop == true then
                        physics.cancel()
                        break
                    end
                end
                task.wait()
            end
            if physics.isRunning() then
                physics.cancel()
            end
        end
        if not started and not silent then
            notify("The fling could not start safely.")
        end
        return started
    end

    state.mm2PerformFling = performFling

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
                if player ~= LocalPlayer and targetIsValid(player)
                    and getPlayerWeapon(player, "Gun", false) == nil
                    and getPlayerWeapon(player, "Knife", false) ~= nil then
                    return player
                end
            end
        end
        if type(findMurderer) == "function" then
            local target: Player? = findMurderer()
            if target and targetIsValid(target)
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(target, "Gun", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(target) or "Murderer"
                if role ~= "Hero" and role ~= "Sheriff" and role ~= "Dead" then
                    return target
                end
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and targetIsValid(player)
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(player, "Gun", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(player) or nil
                if not role and type(gameBridge.playerRole) == "function" then
                    local okRole: boolean, resolved: any =
                        pcall(gameBridge.playerRole, player)
                    if okRole then
                        role = resolved
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
                if player ~= LocalPlayer and targetIsValid(player)
                    and getPlayerWeapon(player, "Knife", false) == nil
                    and getPlayerWeapon(player, "Gun", false) ~= nil then
                    return player
                end
            end
        end
        if type(findSheriff) == "function" then
            local target: Player? = findSheriff()
            if target and targetIsValid(target)
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(target, "Knife", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(target) or "Sheriff"
                if role ~= "Murderer" and role ~= "Dead" then
                    return target
                end
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and targetIsValid(player)
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(player, "Knife", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(player) or nil
                if not role and type(gameBridge.playerRole) == "function" then
                    local okRole: boolean, resolved: any =
                        pcall(gameBridge.playerRole, player)
                    if okRole then
                        role = resolved
                    end
                end
                if role == "Sheriff" or role == "Hero" then
                    return player
                end
            end
        end
        return nil
    end

    local function resolveSelectedTargetPlayer(): Player?
        local query: string = string.lower(string.gsub(
            flingTargetName or "", "^%s*(.-)%s*$", "%1"
        ))
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
            local okFind: boolean, found: any = pcall(findPlayerByText, flingTargetName)
            if okFind and targetIsValid(found) then
                return found :: Player
            end
        end
        local compactQuery: string = string.gsub(query, "%s+", "")
        local prefixMatch: Player? = nil
        local partialMatch: Player? = nil
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local userName: string = string.lower(tostring(player.Name or ""))
                local displayName: string = string.lower(tostring(
                    (player :: any).DisplayName or player.Name or ""
                ))
                local userCompact: string = string.gsub(userName, "%s+", "")
                local displayCompact: string = string.gsub(displayName, "%s+", "")
                if userName == query or displayName == query
                    or userCompact == compactQuery
                    or displayCompact == compactQuery then
                    return player
                end
                if not prefixMatch and (
                    string.sub(userName, 1, #query) == query
                    or string.sub(displayName, 1, #query) == query
                ) then
                    prefixMatch = player
                end
                if not partialMatch and (
                    string.find(userName, query, 1, true) ~= nil
                    or string.find(displayName, query, 1, true) ~= nil
                    or string.find(userCompact, compactQuery, 1, true) ~= nil
                    or string.find(displayCompact, compactQuery, 1, true) ~= nil
                ) then
                    partialMatch = player
                end
            end
        end
        return prefixMatch or partialMatch
    end

    local FlingFeature: any = createUniversalFeature(
        "Fling",
        "MM2 only: bounded physical contact against a round target",
        2,
        function(): () end,
        {
            category = true,
            categoryName = "Exploits",
            registry = mm2Features,
            configKey = "MM2.Fling",
        }
    )

    addActionOption(FlingFeature, "Fling Murderer", function(): ()
        local target: Player? = resolveMurdererTarget()
        if target then
            performFling(target)
        else
            notify("No living murderer was found in this round.")
        end
    end)
    addActionOption(FlingFeature, "Fling Sheriff", function(): ()
        local target: Player? = resolveSheriffOrHeroTarget()
        if target then
            performFling(target)
        else
            notify("No living sheriff or hero was found in this round.")
        end
    end)
    addActionOption(FlingFeature, "Fling All Innocents", function(): ()
        if not roundIsActive() or not localIsAlive() then
            notify("Fling requires an active MM2 round and a living character.")
            return
        end
        sequenceNumber += 1
        local sequence: number = sequenceNumber
        refreshRoles()
        task.spawn(function(): ()
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if sequence ~= sequenceNumber or not roundIsActive()
                    or not localIsAlive() then
                    break
                end
                if targetIsValid(player) then
                    local hasKnife: boolean = type(getPlayerWeapon) == "function"
                        and getPlayerWeapon(player, "Knife", false) ~= nil
                    local hasGun: boolean = type(getPlayerWeapon) == "function"
                        and getPlayerWeapon(player, "Gun", false) ~= nil
                    local role: any = type(getPlayerRole) == "function"
                        and getPlayerRole(player) or nil
                    if not role and type(gameBridge.playerRole) == "function" then
                        local okRole: boolean, resolved: any =
                            pcall(gameBridge.playerRole, player)
                        if okRole then
                            role = resolved
                        end
                    end
                    if not hasKnife and not hasGun and role == "Innocent" then
                        performFling(player, {blocking = true, silent = true})
                        task.wait(0.05)
                    end
                end
            end
        end)
    end)

    local function autoFlingTick(): ()
        if not autoFlingSelected or physics.isRunning() or physics.isTouchEnabled()
            or os.clock() - lastAutoFlingAt < 0.35
            or not roundIsActive() or not localIsAlive() then
            return
        end
        local target: Player? = resolveSelectedTargetPlayer()
        if not targetIsValid(target) then
            return
        end
        lastAutoFlingAt = os.clock()
        performFling(target, {
            silent = true,
            duration = 1.4,
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
        "Username, display name, or 'Murderer' / 'Sheriff'"
    )
    addActionOption(FlingFeature, "Fling", function(): ()
        local target: Player? = resolveSelectedTargetPlayer()
        if target then
            performFling(target)
        else
            notify("No valid target player was found.")
        end
    end)

    -- These are deliberate session actions. The widget layer owns the
    -- restore=false policy for boot, profiles and stale saved states.
    addToggleOption(
        FlingFeature,
        "Touch Fling",
        false,
        function(value: boolean): ()
            if type(state.setTouchFlingEnabled) == "function" then
                state.setTouchFlingEnabled(value == true)
            end
        end,
        "Walk into a player to transfer a bounded contact pulse. No teleport.",
        nil,
        false
    )
    addToggleOption(
        FlingFeature,
        "Auto Fling Selected Target",
        false,
        function(value: boolean): ()
            autoFlingSelected = value == true
            if disconnectFeatureConnection then
                disconnectFeatureConnection("MM2AutoFlingTarget")
            end
            if not autoFlingSelected then
                physics.cancel()
            elseif TaskManager and featureConnections then
                lastAutoFlingAt = 0
                featureConnections.MM2AutoFlingTarget =
                    TaskManager:Connect(autoFlingTick)
                autoFlingTick()
            end
        end,
        "Retries the selected living target only during an active MM2 round.",
        nil,
        false
    )
    addInformationOption(
        FlingFeature,
        "Active rounds only. Death, round end, target loss or OFF cancels the session."
    )

    activeCleanup = function(): ()
        sequenceNumber += 1
        autoFlingSelected = false
        if disconnectFeatureConnection then
            disconnectFeatureConnection("MM2AutoFlingTarget")
        end
        physics.cancel()
        state.mm2PerformFling = nil
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
