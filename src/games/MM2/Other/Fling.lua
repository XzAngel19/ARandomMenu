-- v191: the MM2 Fling card, rebuilt around the FULL historical card instead of
-- the single-target one v190 shipped.
--
-- History: the old menu had its own Fling (src/games/MM2/Blatant/Fling.lua plus
-- src/libraries/Fling.lua) with role buttons -- "Fling Murderer", "Fling
-- Sheriff", "Fling All Innocents", a live roster labelled by role and an auto
-- fling -- and a different physics engine. v183 removed the universal card and
-- the engine stayed; v190 brought back a minimal "pick a player" card on top of
-- `FlingEngine.lua`. The player asked for the old role buttons back, so this
-- card is that one again, but it keeps running on the CURRENT engine
-- (`state.mm2PerformFling`), which is the one that knows about `flingBoost`,
-- the EpixVel pin and retries. Both engines are never mixed.
--
-- Power is at the maximum the engine accepts (12, i.e. four times YARHM's
-- 9e7/9e8 pose velocity) and retries at the maximum (3), so a single call
-- throws as hard and as reliably as the engine can: that was the second half of
-- the request ("el poder sea el máximo y lo más eficaz posible").
--
-- Anti Fling cancels the contact a fling needs, so every path here refuses with
-- a notice while it is ON (MM2 only, as the player asked).
local Module = {
    Name = "MM2 Fling",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

-- The engine clamps Power to 1..12 and Retries to 0..3. The card's default is
-- the top of both ranges.
local MAX_POWER: number = 12
local MAX_RETRIES: number = 3
local FLING_DURATION: number = 3
local AUTO_FLING_INTERVAL: number = 0.35

local ROLE_ORDER: {[string]: number} = {
    Murderer = 1, Sheriff = 2, Hero = 3, Innocent = 4, Dead = 5,
}

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Fling requires the MM2 core module")
    Module.Runtime = runtime

    local localPlayer: any = LocalPlayer
    local playerService: any = Players
    local gameBridge: any = services and services.gameBridge or nil
    local protectedTargets: any = services and services.protectedTargets or nil
    local TaskManager: any = TaskManager
    local featureConnections: any = featureConnections
    local disconnectFeatureConnection: any = disconnectFeatureConnection

    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive

    local settings = {
        power = MAX_POWER,
        retries = MAX_RETRIES,
        autoFling = false,
        autoFlingTarget = nil :: any,
    }
    local FlingFeature: any = nil
    -- The list publishes its stored selection once while it is being built;
    -- acting on that first call would fling a player at injection.
    local listReady: boolean = false
    local selectedPlayer: any = nil
    local selectedLabel: string = ""
    local allInnocentsSequence: number = 0
    local autoElapsed: number = 0

    local function antiFlingOn(): boolean
        return state.antiFlingActive == true
    end

    local function setStatus(text: string?): ()
        if FlingFeature and type(FlingFeature.SetStatus) == "function" then
            pcall(function(): ()
                FlingFeature:SetStatus(text)
            end)
        end
    end

    local function notifyUser(text: string): ()
        if type(notify) == "function" then
            pcall(notify, text)
        end
    end

    local function roster(): {any}
        local ok: boolean, players: any = pcall(function(): any
            return playerService:GetPlayers()
        end)
        if not ok or type(players) ~= "table" then
            return {}
        end
        return players
    end

    local function livingCharacter(player: any): (any?, any?)
        local character: any = player and player.Character
        if not character or not character.Parent then
            return nil, nil
        end
        local humanoid: any = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return nil, nil
        end
        return character, humanoid
    end

    local function rootOf(player: any): any?
        local character: any = player and player.Character
        if not character then
            return nil
        end
        local root: any = character:FindFirstChild("HumanoidRootPart")
        if not root or root.Parent == nil then
            return nil
        end
        return root
    end

    -- v192: `Players` above is a CLONED reference on executors that expose
    -- `cloneref`, so `player.Parent == Players` is false for every real player
    -- (a clone never compares equal to the original instance). v191 used that
    -- comparison as its "is this still a player" guard and the roster came out
    -- empty: the card could not see a single target. The guard now asks the
    -- instance what it is instead of which table it belongs to.
    local function isLivePlayer(player: any): boolean
        if not player or player == localPlayer then
            return false
        end
        local classOk: boolean, className: any = pcall(function(): any
            return player.ClassName
        end)
        if not classOk or className ~= "Player" then
            return false
        end
        local parentOk: boolean, parent: any = pcall(function(): any
            return player.Parent
        end)
        return parentOk and parent ~= nil
    end

    -- A target is only ever a living, unprotected other player whose root is
    -- still in the world: a stale name from the previous round must never
    -- become a fling target.
    local function canFling(player: any): boolean
        if not isLivePlayer(player) then
            return false
        end
        if protectedTargets and type(protectedTargets.isProtected) == "function" then
            local ok: boolean, protected: any = pcall(protectedTargets.isProtected, player)
            if ok and protected == true then
                return false
            end
        end
        if type(isPlayerAlive) == "function" then
            local ok: boolean, alive: any = pcall(isPlayerAlive, player)
            if ok and alive == false then
                return false
            end
        end
        local character: any = livingCharacter(player)
        return character ~= nil and rootOf(player) ~= nil
    end

    local function hasWeapon(player: any, toolName: string): boolean
        if type(getPlayerWeapon) ~= "function" then
            return false
        end
        local ok: boolean, weapon: any = pcall(getPlayerWeapon, player, toolName, false)
        return ok and weapon ~= nil
    end

    -- One source of truth for "who is what": the round data first, then the
    -- tool the server actually replicates (the murderer carries the knife, the
    -- sheriff/hero carries the gun), then a dead humanoid. The old card guessed
    -- in three places and none of them used the held tool, which is why its
    -- Murderer button often answered "nobody found".
    local function roleOf(player: any): string?
        if not player then
            return nil
        end
        local role: any = nil
        if type(getPlayerRole) == "function" then
            local ok: boolean, value: any = pcall(getPlayerRole, player)
            if ok then
                role = value
            end
        end
        if not role and gameBridge and type(gameBridge.playerRole) == "function" then
            local ok: boolean, value: any = pcall(gameBridge.playerRole, player)
            if ok then
                role = value
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
        if role == nil then
            local character: any = player.Character
            local humanoid: any = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health <= 0 then
                return "Dead"
            end
        end
        return role
    end

    local function rolesPublished(): boolean
        if type(core.hasActiveRoundRoles) == "function" then
            local ok: boolean, published: any = pcall(core.hasActiveRoundRoles)
            if ok and published == true then
                return true
            end
        end
        for _, player: any in ipairs(roster()) do
            if player ~= localPlayer and roleOf(player) ~= nil then
                return true
            end
        end
        return false
    end

    local function refreshRoles(): ()
        if type(state.clearRoleMemo) == "function" then
            pcall(state.clearRoleMemo)
        end
        if type(core.requestRoleRefresh) == "function" then
            pcall(core.requestRoleRefresh, false)
        end
    end

    local function rosterEntries(withRefresh: boolean?): {{player: any, label: string}}
        if withRefresh ~= false then
            refreshRoles()
        end
        local entries: {{player: any, label: string}} = {}
        for _, player: any in ipairs(roster()) do
            if player ~= localPlayer and canFling(player) then
                local role: string? = roleOf(player)
                table.insert(entries, {
                    player = player,
                    label = tostring(player.Name) .. (role and (" [" .. role .. "]") or ""),
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

    local function resolveMurdererTarget(): any?
        refreshRoles()
        for _, player: any in ipairs(roster()) do
            if player ~= localPlayer and canFling(player)
                and not hasWeapon(player, "Gun") and hasWeapon(player, "Knife") then
                return player
            end
        end
        if type(findMurderer) == "function" then
            local ok: boolean, target: any = pcall(findMurderer)
            if ok and target and canFling(target) and roleOf(target) ~= "Dead" then
                return target
            end
        end
        for _, player: any in ipairs(roster()) do
            if player ~= localPlayer and canFling(player) and roleOf(player) == "Murderer" then
                return player
            end
        end
        return nil
    end

    local function resolveSheriffTarget(): any?
        refreshRoles()
        for _, player: any in ipairs(roster()) do
            if player ~= localPlayer and canFling(player)
                and not hasWeapon(player, "Knife") and hasWeapon(player, "Gun") then
                return player
            end
        end
        if type(findSheriff) == "function" then
            local ok: boolean, target: any = pcall(findSheriff)
            if ok and target and canFling(target) then
                local role: string? = roleOf(target)
                if role ~= "Murderer" and role ~= "Dead" then
                    return target
                end
            end
        end
        for _, player: any in ipairs(roster()) do
            if player ~= localPlayer and canFling(player) then
                local role: string? = roleOf(player)
                if role == "Sheriff" or role == "Hero" then
                    return player
                end
            end
        end
        return nil
    end

    -- What the card is showing, readable by the offline suite: the labels it
    -- publishes and the player the current selection resolves to.
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

    local function performFling(target: any, options: {[string]: any}?): boolean
        if antiFlingOn() then
            -- Turning Anti Fling off is the documented answer; without this
            -- notice the fling just looks broken and blames the engine.
            if not (type(options) == "table" and options.silent == true) then
                notifyUser("Anti Fling is ON: turn it off before flinging someone.")
            end
            setStatus("Anti Fling is ON")
            return false
        end
        if not canFling(target) then
            if not (type(options) == "table" and options.silent == true) then
                notifyUser("No living, valid fling target is available.")
                setStatus("No target")
            end
            return false
        end
        local perform: any = state.mm2PerformFling
        if type(perform) ~= "function" then
            setStatus("Fling engine unavailable")
            return false
        end
        local call: {[string]: any} = {
            power = settings.power,
            retries = settings.retries,
            duration = FLING_DURATION,
        }
        if type(options) == "table" then
            for key: string, value: any in pairs(options) do
                call[key] = value
            end
        end
        if call.power == nil then call.power = settings.power end
        if call.retries == nil then call.retries = settings.retries end
        setStatus("Flinging " .. tostring(target.Name))
        local started: boolean = false
        local ok: boolean, result: any = pcall(perform, target, call)
        if ok then
            started = result == true
        end
        if not started then
            setStatus("Fling busy or refused")
        end
        return started
    end

    local function flingSelected(label: string?): boolean
        local target: any = nil
        if label and label ~= "" then
            for _, entry: any in ipairs(rosterEntries(false)) do
                if entry.label == label then
                    target = entry.player
                    break
                end
            end
        end
        if not target then
            target = if canFling(selectedPlayer) then selectedPlayer else nil
        end
        if not target then
            setStatus("Pick a target")
            if label and label ~= "" then
                notifyUser("That player is not a living fling target any more.")
            end
            return false
        end
        return performFling(target)
    end

    local function flingAllInnocents(): ()
        if antiFlingOn() then
            notifyUser("Anti Fling is ON: turn it off before flinging someone.")
            setStatus("Anti Fling is ON")
            return
        end
        allInnocentsSequence += 1
        local sequence: number = allInnocentsSequence
        refreshRoles()
        task.spawn(function(): ()
            local flung: number = 0
            for _, player: any in ipairs(roster()) do
                if sequence ~= allInnocentsSequence then
                    break
                end
                if canFling(player) and roleOf(player) == "Innocent" then
                    if performFling(player, {
                        blocking = true,
                        silent = true,
                        duration = FLING_DURATION,
                    }) then
                        flung += 1
                    end
                    task.wait(0.05)
                end
            end
            if sequence == allInnocentsSequence then
                setStatus(flung > 0 and ("Flung " .. tostring(flung)) or nil)
            end
        end)
    end

    local function stopAutoFling(): ()
        settings.autoFling = false
        settings.autoFlingTarget = nil
        autoElapsed = 0
        disconnectFeatureConnection("MM2FlingAuto")
    end

    local function startAutoFling(): ()
        disconnectFeatureConnection("MM2FlingAuto")
        autoElapsed = 0
        featureConnections.MM2FlingAuto =
            TaskManager:Connect(function(deltaTime: number): ()
                autoElapsed += math.max(0, deltaTime)
                if autoElapsed < AUTO_FLING_INTERVAL then
                    return
                end
                autoElapsed = 0
                if not settings.autoFling or antiFlingOn() then
                    return
                end
                local target: any = settings.autoFlingTarget
                if not canFling(target) then
                    target = if canFling(selectedPlayer) then selectedPlayer else nil
                end
                if not target then
                    return
                end
                performFling(target, {silent = true, duration = FLING_DURATION})
            end, nil, "MM2 Fling Auto")
    end

    FlingFeature = createUniversalFeature(
        "Fling",
        "MM2 only: throws the murderer, the sheriff, every innocent or the player you pick, at maximum power.",
        9,
        function(): () end,
        {
            categoryName = "Exploits",
            parent = MM2Scroll,
            registry = mm2Features,
            -- Group card: the card itself never "runs", it holds the controls.
            kind = "group",
        }
    )

    -- The role buttons are the point of this card: one click, one role.
    if type(addActionOption) == "function" then
        addActionOption(FlingFeature, "Fling Murderer", function(): ()
            local target: any = resolveMurdererTarget()
            if target then
                performFling(target)
            else
                notifyUser(if rolesPublished()
                    then "No living murderer was found in this round."
                    else "MM2 has not published the roles yet. Wait for the round to start.")
            end
        end)
        addActionOption(FlingFeature, "Fling Sheriff", function(): ()
            local target: any = resolveSheriffTarget()
            if target then
                performFling(target)
            else
                notifyUser(if rolesPublished()
                    then "No living sheriff or hero was found in this round."
                    else "MM2 has not published the roles yet. Wait for the round to start.")
            end
        end)
        addActionOption(FlingFeature, "Fling All Innocents", function(): ()
            flingAllInnocents()
        end)
    end

    -- The roster is a live list of the players in this round, already labelled
    -- with their role, sorted murderer first.
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
            emptyText = "No other players",
            hint = "Living players, ordered by role. Anti Fling must be OFF: it cancels the contact a fling needs.",
            onChanged = function(_selected: any, names: {string}): ()
                local label: string = names and names[1] or ""
                if label == "" then
                    -- The row is cleared right after a pick so the same player
                    -- can be chosen again; that empty publish must not forget
                    -- the target, or "Fling" would have nothing to repeat.
                    return
                end
                selectedLabel = label
                selectedPlayer = nil
                for _, entry: any in ipairs(rosterEntries(false)) do
                    if entry.label == label then
                        selectedPlayer = entry.player
                        settings.autoFlingTarget = entry.player
                        break
                    end
                end
                if not listReady then
                    -- The stored selection is published while the card is being
                    -- built: remember it, but never fling on injection.
                    return
                end
                if selectedPlayer then
                    local target: any = selectedPlayer
                    -- Clear the row so the same player can be picked again; the
                    -- empty publish that follows is ignored above.
                    local key: string = tostring(FlingFeature.configKey or "MM2.Fling")
                        .. ".Flingtarget"
                    local controls: any = state.listControls and state.listControls[key]
                    if controls then
                        listReady = false
                        pcall(function(): ()
                            controls.set(label, false)
                        end)
                        listReady = true
                    end
                    performFling(target)
                end
            end,
        })
        listReady = true
    end

    if type(addActionOption) == "function" then
        addActionOption(FlingFeature, "Fling", function(): ()
            flingSelected(selectedLabel)
        end)
    end
    if type(addToggleOption) == "function" then
        addToggleOption(FlingFeature, "Auto Fling Selected Target", false,
            function(value: boolean): ()
                settings.autoFling = value == true
                if settings.autoFling then
                    if not canFling(selectedPlayer) then
                        settings.autoFling = false
                        notifyUser("Pick a living player in \"Fling target\" first.")
                        if state.setToggleChecked then
                            pcall(state.setToggleChecked,
                                tostring(FlingFeature.configKey or "MM2.Fling")
                                    .. ".AutoFlingSelectedTarget", false)
                        end
                        return
                    end
                    settings.autoFlingTarget = selectedPlayer
                    startAutoFling()
                else
                    stopAutoFling()
                end
            end)
    end

    if type(addNumberOption) == "function" then
        addNumberOption(FlingFeature, "Power", settings.power, 1, MAX_POWER,
            function(value: number): ()
                settings.power = math.clamp(math.floor(tonumber(value) or MAX_POWER), 1, MAX_POWER)
            end,
            "Fling strength. 12 is the maximum the engine accepts: four times YARHM's 9e7/9e8 pose velocity, which is what carries a fling through a laggy or fast server.",
            1)
        addNumberOption(FlingFeature, "Retries", settings.retries, 0, MAX_RETRIES,
            function(value: number): ()
                settings.retries = math.clamp(math.floor(tonumber(value) or MAX_RETRIES), 0, MAX_RETRIES)
            end,
            "Extra passes that swap the contact part when the server misses the first one. 3 is the maximum.",
            1)
    end
    if type(addInformationOption) == "function" then
        addInformationOption(
            FlingFeature,
            "MM2 only. Every button refuses while Anti Fling is ON: its collision "
                .. "shield cancels the contact a fling needs."
        )
    end

    activeCleanup = function(): ()
        allInnocentsSequence += 1
        stopAutoFling()
        state.mm2FlingFeature = nil
        state.mm2FlingSettings = nil
    end
    state.mm2FlingFeature = FlingFeature
    state.mm2FlingSettings = settings
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
