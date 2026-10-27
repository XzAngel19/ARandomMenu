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
        local result = character ~= nil and humanoid ~= nil and root ~= nil
            and humanoid.Health > 0 and root.Parent ~= nil and not root.Anchored
        return result
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

    -- One source of truth for "who is what". The card used to guess the role in
    -- three different places and none of them fell back to the held tool, which
    -- is what MM2 actually replicates: the murderer carries the knife and the
    -- sheriff (or the hero who picked the gun up) carries the gun. That is why
    -- the list looked empty and "Fling Murderer" said nobody was found.
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
        if not role and type(gameBridge.playerRole) == "function" then
            local okRole: boolean, resolved: any = pcall(gameBridge.playerRole, player)
            if okRole then
                role = resolved
            end
        end
        if role == "Murderer" or role == "Sheriff" or role == "Hero"
            or role == "Innocent" or role == "Dead" then
            return role
        end
        -- Tool inference: what the server actually puts in the backpack.
        if hasWeapon(player, "Knife") then
            return "Murderer"
        end
        if hasWeapon(player, "Gun") then
            return "Sheriff"
        end
        if role == nil then
            local character: Model? = player.Character
            local humanoid: Humanoid? = character
                and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if humanoid and humanoid.Health <= 0 then
                return "Dead"
            end
        end
        return role
    end

    -- "It does not detect anyone" is usually not a bug: MM2 has not published
    -- the round roles yet. Saying which of the two happened is the difference
    -- between a feature that looks broken and one the user can wait out.
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

    -- Read-only hooks. They describe exactly what the card is showing, which is
    -- the only way an offline suite can prove "the list knows who is who".
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
            if target and targetIsValid(target) and roleOf(target) ~= "Dead" then
                return target
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and targetIsValid(player)
                and roleOf(player) == "Murderer" then
                return player
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
                and roleOf(target) ~= "Murderer" and roleOf(target) ~= "Dead" then
                return target
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and targetIsValid(player) then
                local role: string? = roleOf(player)
                if role == "Sheriff" or role == "Hero" then
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
        local target: Player? = resolveMurdererTarget()
        if target then
            performFling(target)
        else
            notify(if rolesPublished()
                then "No living murderer was found in this round."
                else "MM2 has not published the roles yet. Wait for the round to start.")
        end
    end)
    addActionOption(FlingFeature, "Fling Sheriff", function(): ()
        local target: Player? = resolveSheriffOrHeroTarget()
        if target then
            performFling(target)
        else
            notify(if rolesPublished()
                then "No living sheriff or hero was found in this round."
                else "MM2 has not published the roles yet. Wait for the round to start.")
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
                if targetIsValid(player) and roleOf(player) == "Innocent" then
                    performFling(player, {blocking = true, silent = true})
                    task.wait(0.05)
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

    -- The target is a live list of the players this round, already labelled with
    -- their role. Typing a name by hand was the reason the card "detected
    -- nothing": a typo, a display name or a player who joined a second ago all
    -- looked identical to a broken feature.
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
                -- Only a label that is still in the living roster can become a
                -- target: a stale saved name must never point at a dead player
                -- or at someone from the previous round.
                for _, entry: any in ipairs(rosterEntries(false)) do
                    if entry.label == label then
                        selectedPlayer = entry.player
                        return
                    end
                end
            end,
        })
    end

    -- Keep the labels honest while roles change between rounds (the murderer of
    -- this round is not the murderer of the next one). Cheap: one signature
    -- string every second, and it does nothing at all until it changes.
    local lastRosterSignature: string = ""
    local lastRosterSignatureAt: number = 0
    local function rosterSignature(): string
        local parts: {string} = {}
        for _, entry: any in ipairs(rosterEntries()) do
            table.insert(parts, entry.label)
        end
        return table.concat(parts, "|")
    end
    local function refreshRoster(): ()
        local signature: string = rosterSignature()
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
            -- Drop a selection whose player left, then re-point the label of a
            -- selection whose role changed.
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
            disconnectFeatureConnection("MM2FlingRoster")
        end
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
