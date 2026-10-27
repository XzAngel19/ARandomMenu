-- v151 · MM2 Fling card, rebuilt around Infinite Yield's real walkfling.
--
-- The card owns only three things: MM2 round/target validity, the live player
-- roster (with roles from RoundStart/PlayerDataChanged and from the knife/gun
-- actually held), and the user's intents. All physics lives in
-- src/libraries/Fling.lua: one shared three-signal velocity engine. There is
-- no second motor, no CFrame loop and no velocity writer in this file.

local Module = {
    Name = "MM2 Fling",
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(_runtime: any): any
    local host: any = state.frameworkEnvironment
    local core: any = state.mm2Core
    local physics: any = state.flingPhysics
    assert(core, "MM2 Fling requires the MM2 core")
    assert(physics, "MM2 Fling requires the shared contact library")

    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local protectedTargets: any = services.protectedTargets
    local gameBridge: any = services.gameBridge
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addToggleOption: any = host.addToggleOption
    local addListOption: any = host.addListOption
    local addInformationOption: any = host.addInformationOption
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection

    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive

    local selectedPlayer: Player? = nil
    local selectedLabel: string = ""
    local autoFlingSelected: boolean = false
    local lastAutoFlingAt: number = 0
    local sequenceNumber: number = 0
    local queue: {Player} = {}
    local queueGeneration: number = 0

    local function roundIsActive(): boolean
        if type(core.isRoundLifecycleActive) ~= "function"
            or core.isRoundLifecycleActive() ~= true then
            return false
        end
        if type(core.getRoundPhase) == "function"
            and core.getRoundPhase() == "lobby" then
            return false
        end
        if type(core.findMM2Map) == "function" and not core.findMM2Map() then
            return false
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
            if not silent and Module.Initialized then
                notify(if not roundIsActive()
                    then "Fling requires an active MM2 round."
                    else "No living, valid fling target is available.")
            end
            return false
        end
        -- Touch Fling is the same engine running continuously, not a second
        -- owner: a directed action may still place and pulse a chosen target.
        if physics.isRunning() then
            if not silent then
                notify("A directed fling is already running.")
            end
            return false
        end
        local externalStop: any = type(options) == "table"
            and options.shouldStop or nil
        local duration: number = if type(options) == "table"
            then tonumber(options.duration) or 2.2 else 2.2
        if duration ~= duration or math.abs(duration) == math.huge then
            duration = 2.2
        end
        local started: boolean = physics.start(targetPlayer, {
            duration = math.clamp(duration, 0.1, 2.5),
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

    local ROLE_ORDER: {[string]: number} = {
        Murderer = 1, Sheriff = 2, Hero = 3, Innocent = 4, Dead = 5,
    }

    local function hasWeapon(player: Player, toolName: string): boolean
        if type(getPlayerWeapon) ~= "function" then
            return false
        end
        local ok: boolean, value: any = pcall(getPlayerWeapon, player, toolName, false)
        return ok and value ~= nil
    end

    local function roleOf(player: Player): string?
        if not player then
            return nil
        end
        local role: any = type(getPlayerRole) == "function"
            and getPlayerRole(player) or nil
        if not role and gameBridge and type(gameBridge.playerRole) == "function" then
            local okRole: boolean, resolved: any = pcall(gameBridge.playerRole, player)
            if okRole then
                role = resolved
            end
        end
        if role == "Murderer" or role == "Sheriff" or role == "Hero"
            or role == "Innocent" or role == "Dead" then
            return role
        end
        if hasWeapon(player, "Knife") then
            return "Murderer"
        end
        if hasWeapon(player, "Gun") then
            return "Sheriff"
        end
        local character: Model? = player.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if humanoid and humanoid.Health <= 0 then
            return "Dead"
        end
        return nil
    end

    local function rolesPublished(): boolean
        if type(core.hasActiveRoundRoles) == "function" then
            local ok: boolean, published: any = pcall(core.hasActiveRoundRoles)
            if ok and published == true then
                return true
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and roleOf(player) ~= nil then
                return true
            end
        end
        return false
    end

    local function rosterEntries(withRefresh: boolean?): {{player: Player, label: string}}
        if withRefresh ~= false then
            refreshRoles()
        end
        local entries: {{player: Player, label: string}} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and targetIsValid(player) then
                local role: string? = roleOf(player)
                local suffix: string = if role then " [" .. tostring(role) .. "]" else ""
                table.insert(entries, {
                    player = player,
                    label = tostring(player.Name) .. suffix,
                })
            end
        end
        table.sort(entries, function(left: any, right: any): boolean
            local leftRole: number = ROLE_ORDER[
                (string.match(left.label, "%[(%a+)%]") or "")
            ] or 9
            local rightRole: number = ROLE_ORDER[
                (string.match(right.label, "%[(%a+)%]") or "")
            ] or 9
            if leftRole ~= rightRole then
                return leftRole < rightRole
            end
            return string.lower(left.label) < string.lower(right.label)
        end)
        return entries
    end

    -- Read-only hooks: an offline suite can prove the list knows who is who.
    state.mm2FlingRoster = function(): {any}
        local snapshot: {any} = {}
        for _, entry: any in ipairs(rosterEntries(false)) do
            table.insert(snapshot, {
                name = tostring(entry.player.Name),
                label = entry.label,
            })
        end
        return snapshot
    end
    state.mm2FlingSelection = function(): string?
        return if selectedPlayer then tostring(selectedPlayer.Name) else nil
    end

    local function resolveByRole(wanted: string): Player?
        refreshRoles()
        local byWeapon: string? = nil
        if wanted == "Murderer" then
            byWeapon = "Knife"
        elseif wanted == "Sheriff" then
            byWeapon = "Gun"
        end
        if byWeapon and type(getPlayerWeapon) == "function" then
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and targetIsValid(player)
                    and getPlayerWeapon(player, byWeapon, false) ~= nil then
                    return player
                end
            end
        end
        local finder: any = if wanted == "Murderer" then findMurderer
            elseif wanted == "Sheriff" then findSheriff else nil
        if type(finder) == "function" then
            local found: Player? = finder()
            if targetIsValid(found) then
                return found
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and targetIsValid(player) then
                local role: string? = roleOf(player)
                if role == wanted
                    or (wanted == "Sheriff" and role == "Hero") then
                    return player
                end
            end
        end
        return nil
    end

    local function resolveSelectedTargetPlayer(): Player?
        if selectedPlayer and targetIsValid(selectedPlayer) then
            return selectedPlayer
        end
        return nil
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
        local target: Player? = resolveByRole("Murderer")
        if target then
            performFling(target)
        else
            notify(if rolesPublished()
                then "No living murderer was found in this round."
                else "MM2 has not published the roles yet. Wait for the round to start.")
        end
    end)
    addActionOption(FlingFeature, "Fling Sheriff", function(): ()
        local target: Player? = resolveByRole("Sheriff")
        if target then
            performFling(target)
        else
            notify(if rolesPublished()
                then "No living sheriff or hero was found in this round."
                else "MM2 has not published the roles yet. Wait for the round to start.")
        end
    end)

    -- "Fling All Innocents" is a queue, not a blocking coroutine: one impulse
    -- session at a time and no fixed sleeps competing with the scheduler.
    addActionOption(FlingFeature, "Fling All Innocents", function(): ()
        if not roundIsActive() or not localIsAlive() then
            notify("Fling requires an active MM2 round and a living character.")
            return
        end
        sequenceNumber += 1
        queueGeneration = sequenceNumber
        table.clear(queue)
        refreshRoles()
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if targetIsValid(player) and roleOf(player) == "Innocent" then
                table.insert(queue, player)
            end
        end
        local lastQueuedAt: number = 0
        if TaskManager and featureConnections then
            disconnectFeatureConnection("MM2FlingQueue")
            featureConnections.MM2FlingQueue = TaskManager:Connect(function(): ()
                if queueGeneration ~= sequenceNumber or #queue == 0 then
                    disconnectFeatureConnection("MM2FlingQueue")
                    return
                end
                if physics.isRunning() or os.clock() - lastQueuedAt < 0.15
                    or not roundIsActive() or not localIsAlive() then
                    return
                end
                local nextTarget: Player? = table.remove(queue, 1)
                if nextTarget and targetIsValid(nextTarget) then
                    lastQueuedAt = os.clock()
                    performFling(nextTarget, {silent = true, duration = 1.4})
                end
            end)
        end
    end)

    local function autoFlingTick(): ()
        if not autoFlingSelected or physics.isRunning()
            or os.clock() - lastAutoFlingAt < 0.45
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
            duration = 2.2,
            shouldStop = function(): boolean
                return not autoFlingSelected
            end,
        })
    end

    local listHandle: any = nil
    if type(addListOption) == "function" then
        listHandle = addListOption(FlingFeature, "Fling target", {
            items = function(): {string}
                local labels: {string} = {}
                for _, entry: any in ipairs(rosterEntries()) do
                    table.insert(labels, entry.label)
                end
                return labels
            end,
            single = true,
            default = {},
            emptyText = "No players in this round",
            hint = "Living players, ordered by role. The role comes from the round "
                .. "data and from the knife/gun actually held.",
            onChanged = function(_selected: any, names: {string}): ()
                local label: string = names[1] or ""
                selectedLabel = label
                selectedPlayer = nil
                if label == "" then
                    return
                end
                for _, entry: any in ipairs(rosterEntries(false)) do
                    if entry.label == label then
                        selectedPlayer = entry.player
                        return
                    end
                end
            end,
        })
    end

    local lastRosterSignature: string = ""
    local lastRosterSignatureAt: number = 0
    local function refreshRoster(): ()
        local parts: {string} = {}
        for _, entry: any in ipairs(rosterEntries()) do
            table.insert(parts, entry.label)
        end
        local signature: string = table.concat(parts, "|")
        if signature == lastRosterSignature then
            return
        end
        lastRosterSignature = signature
        local controls: any = state.listControls
        local key: string? = nil
        if listHandle and type(listHandle.GetAttribute) == "function" then
            local ok: boolean, value: any = pcall(function(): any
                return listHandle:GetAttribute("ListKey")
            end)
            if ok and type(value) == "string" then
                key = value
            end
        end
        local control: any = key and controls and controls[key] or nil
        if not control then
            return
        end
        pcall(function(): ()
            if selectedLabel ~= "" then
                control.set(selectedLabel, false)
            end
            if selectedPlayer and targetIsValid(selectedPlayer) then
                local role: string? = roleOf(selectedPlayer)
                local suffix: string = if role then " [" .. tostring(role) .. "]" else ""
                control.set(tostring(selectedPlayer.Name) .. suffix, true)
            end
        end)
    end
    refreshRoster()
    if TaskManager and featureConnections then
        featureConnections.MM2FlingRoster = TaskManager:Connect(function(): ()
            if os.clock() - lastRosterSignatureAt < 1 then
                return
            end
            lastRosterSignatureAt = os.clock()
            refreshRoster()
        end)
    end

    addActionOption(FlingFeature, "Fling", function(): ()
        local target: Player? = resolveSelectedTargetPlayer()
        if target then
            performFling(target)
        else
            notify("Pick a living player from the Fling target list first.")
        end
    end)
    addToggleOption(
        FlingFeature,
        "Auto Fling Selected Target",
        false,
        function(value: boolean): ()
            autoFlingSelected = value == true
            disconnectFeatureConnection("MM2AutoFlingTarget")
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
        "Active rounds only. Death, round end, target loss or OFF cancels the session. "
            .. "Uses IY's real walkfling velocity sequence on your own root for a bounded time; "
            .. "no spin and no per-frame teleport."
    )

    activeCleanup = function(): ()
        sequenceNumber += 1
        table.clear(queue)
        autoFlingSelected = false
        disconnectFeatureConnection("MM2AutoFlingTarget")
        disconnectFeatureConnection("MM2FlingRoster")
        disconnectFeatureConnection("MM2FlingQueue")
        selectedPlayer = nil
        selectedLabel = ""
        physics.cancel()
        state.mm2PerformFling = nil
        state.mm2FlingRoster = nil
        state.mm2FlingSelection = nil
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
