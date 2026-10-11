-- Murderers VS Sheriffs Duels shared core.
--
-- Duels keeps every Player Neutral and stores the side a player fights for in
-- its own match data, so the generic Teams-service lookup in
-- src/libraries/Entity.lua answers "nobody is on my team" and the ESP painted
-- teammates the same red it paints enemies. This module resolves the side from
-- every source the game exposes and publishes it as the menu's team provider,
-- which the ESP, Chams and Arrows all read.

local Module = {
    Name = "MVSD",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
    Menu = nil :: any,
    Runtime = nil :: any,
}

local moduleCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    Module.Runtime = runtime
    Module.Menu = runtime and runtime.Menu

    local host: any = getfenv()
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addCycleOption: any = host.addCycleOption
    local addActionOption: any = host.addActionOption

    local players: Players = game:GetService("Players")
    local runService: RunService = game:GetService("RunService")
    local localPlayer: Player = players.LocalPlayer

    local settings = {
        enabled = false,
        source = "Auto",
        onlyMyMatch = true,
        logDetection = false,
    }

    -- Attribute names the game may keep the side under. Duels has changed these
    -- between updates, so the resolver walks the whole list instead of betting
    -- on one.
    local ROLE_ATTRIBUTE_NAMES: {string} = {
        "Role", "RoleName", "PlayerRole", "MVSDRole", "GameRole",
        "SelectedRole", "AssignedRole", "RoleId", "Class", "Kit",
    }
    local TEAM_ATTRIBUTE_NAMES: {string} = {
        "Team", "TeamName", "TeamId", "TeamID", "Side", "Faction", "MatchTeam",
    }
    local MATCH_ATTRIBUTE_NAMES: {string} = {
        "Game", "Match", "MatchId", "MatchID", "Lobby", "LobbyId",
    }

    local MURDERER_WORDS: {string} = {"knife", "blade", "machete", "bat", "melee"}
    local SHERIFF_WORDS: {string} = {"revolver", "pistol", "shotgun", "rifle", "gun"}

    local function textOf(value: any): string?
        if value == nil then
            return nil
        end
        if typeof(value) == "Instance" then
            return (value :: Instance).Name
        end
        if type(value) == "string" then
            return value
        end
        if type(value) == "number" or type(value) == "boolean" then
            return tostring(value)
        end
        return nil
    end

    local function classify(text: string?): string?
        if type(text) ~= "string" or text == "" then
            return nil
        end
        local lowered: string = string.lower(text :: string)
        if string.find(lowered, "murder", 1, true)
            or string.find(lowered, "killer", 1, true) then
            return "Murderer"
        end
        if string.find(lowered, "sheriff", 1, true)
            or string.find(lowered, "deputy", 1, true)
            or lowered == "cop"
            or lowered == "cops" then
            return "Sheriff"
        end
        if string.find(lowered, "innocent", 1, true) then
            return "Innocent"
        end
        if string.find(lowered, "spect", 1, true) then
            return "Spectator"
        end
        return nil
    end

    local function firstAttribute(player: Player, names: {string}): any
        for _, attributeName: string in ipairs(names) do
            local ok: boolean, value: any = pcall(
                player.GetAttribute,
                player,
                attributeName
            )
            if ok and value ~= nil and value ~= "" then
                return value
            end
        end
        return nil
    end

    local function roleFromAttributes(player: Player): string?
        local role: string? = classify(textOf(firstAttribute(player, ROLE_ATTRIBUTE_NAMES)))
        if role then
            return role
        end
        return classify(textOf(firstAttribute(player, TEAM_ATTRIBUTE_NAMES)))
    end

    local function teamTokenFromAttributes(player: Player): string?
        local raw: any = firstAttribute(player, TEAM_ATTRIBUTE_NAMES)
        local text: string? = textOf(raw)
        if text == nil then
            return nil
        end
        local role: string? = classify(text)
        if role then
            return string.lower(role)
        end
        -- A numeric side id (1/2) still separates the two teams even when the
        -- game never spells the role out.
        return "attr:" .. string.lower(text)
    end

    local function roleFromTeamService(player: Player): string?
        local ok: boolean, team: any = pcall(function(): any
            return player.Team
        end)
        if ok and team then
            return classify((team :: Instance).Name)
        end
        return nil
    end

    local function teamTokenFromTeamService(player: Player): string?
        local ok: boolean, team: any = pcall(function(): any
            return player.Team
        end)
        if ok and team then
            return "team:" .. string.lower((team :: Instance).Name)
        end
        return nil
    end

    local function roleFromLeaderstats(player: Player): string?
        local stats: Instance? = player:FindFirstChild("leaderstats")
        if not stats then
            return nil
        end
        for _, child: Instance in ipairs(stats:GetChildren()) do
            local lowered: string = string.lower(child.Name)
            if string.find(lowered, "role", 1, true)
                or string.find(lowered, "team", 1, true) then
                local ok: boolean, value: any = pcall(function(): any
                    return (child :: any).Value
                end)
                local role: string? = classify(ok and textOf(value) or nil)
                if role then
                    return role
                end
            end
        end
        return nil
    end

    -- The overhead name plate is the one thing a spectator sees, so it is a
    -- decent fallback; scanning a whole character is not, which is why this
    -- only walks the GUIs hanging off the model.
    local function roleFromNamePlate(player: Player): string?
        local character: Model? = player.Character
        if not character then
            return nil
        end
        for _, child: Instance in ipairs(character:GetChildren()) do
            if not (child:IsA("BillboardGui") or child:IsA("SurfaceGui")) then
                continue
            end
            for _, descendant: Instance in ipairs(child:GetDescendants()) do
                if not (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) then
                    continue
                end
                local ok: boolean, text: any = pcall(function(): any
                    return (descendant :: TextLabel).Text
                end)
                local role: string? = classify(ok and textOf(text) or nil)
                if role then
                    return role
                end
            end
        end
        return nil
    end

    local function roleFromTools(player: Player): string?
        local containers: {Instance?} = {
            player.Character,
            player:FindFirstChildOfClass("Backpack"),
        }
        for _, container: Instance? in ipairs(containers) do
            if not container then
                continue
            end
            for _, child: Instance in ipairs(container:GetChildren()) do
                if not child:IsA("Tool") then
                    continue
                end
                local lowered: string = string.lower(child.Name)
                for _, word: string in ipairs(MURDERER_WORDS) do
                    if string.find(lowered, word, 1, true) then
                        return "Murderer"
                    end
                end
                for _, word: string in ipairs(SHERIFF_WORDS) do
                    if string.find(lowered, word, 1, true) then
                        return "Sheriff"
                    end
                end
            end
        end
        return nil
    end

    local ROLE_SOURCES: {[string]: {(Player) -> string?}} = {
        ["Auto"] = {
            roleFromAttributes,
            roleFromTeamService,
            roleFromLeaderstats,
            roleFromNamePlate,
        },
        ["Player attribute"] = {roleFromAttributes},
        ["Teams service"] = {roleFromTeamService},
        ["Leaderstats"] = {roleFromLeaderstats},
        ["Overhead name"] = {roleFromNamePlate},
        ["Held tool"] = {roleFromTools},
    }
    local SOURCE_OPTIONS: {string} = {
        "Auto",
        "Player attribute",
        "Teams service",
        "Leaderstats",
        "Overhead name",
        "Held tool",
    }

    local ROLE_TTL: number = 0.25
    local roleMemo: {[Player]: {role: string?, token: string?, source: string?, at: number}} =
        setmetatable({}, {__mode = "k"}) :: any
    local lastSource: string? = nil

    local function resolve(player: Player): (string?, string?, string?)
        local now: number = os.clock()
        local cached: any = roleMemo[player]
        if cached and now - cached.at < ROLE_TTL then
            return cached.role, cached.token, cached.source
        end

        local role: string? = nil
        local source: string? = nil
        local sources: {(Player) -> string?} = ROLE_SOURCES[settings.source]
            or ROLE_SOURCES["Auto"]
        for _, resolver: (Player) -> string? in ipairs(sources) do
            local ok: boolean, found: any = pcall(resolver, player)
            if ok and type(found) == "string" and found ~= "" then
                role = found
                source = settings.source == "Auto" and "auto" or settings.source
                break
            end
        end

        local token: string? = role and string.lower(role) or nil
        if token == nil then
            token = teamTokenFromAttributes(player)
                or teamTokenFromTeamService(player)
        end
        if role ~= nil and source == nil then
            source = "team token"
        end

        roleMemo[player] = {role = role, token = token, source = source, at = now}
        if role ~= nil then
            lastSource = source
        end
        return role, token, source
    end

    local function clearCache(): ()
        table.clear(roleMemo)
        lastSource = nil
    end

    local function matchIdOf(player: Player): string?
        local raw: any = firstAttribute(player, MATCH_ATTRIBUTE_NAMES)
        return textOf(raw)
    end

    local function inSameMatch(other: Player): boolean
        local mine: string? = matchIdOf(localPlayer)
        local theirs: string? = matchIdOf(other)
        if mine == nil or theirs == nil then
            -- No match marker on either side: nothing to compare, so do not
            -- hide the player.
            return true
        end
        return mine == theirs
    end

    local function isAlive(player: Player): boolean
        local character: Model? = player.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
        return humanoid ~= nil and humanoid.Health > 0
    end

    local function isTeammate(other: Player?): boolean
        if not other or other == localPlayer then
            return false
        end
        if settings.onlyMyMatch and not inSameMatch(other) then
            return false
        end
        local _, myToken: string? = resolve(localPlayer)
        local _, theirToken: string? = resolve(other)
        if myToken == nil or theirToken == nil then
            -- Unknown side is treated as an enemy: painting a stranger white
            -- would hide a real threat, painting them red costs nothing.
            return false
        end
        return myToken == theirToken
    end

    local function isEnemy(player: Player?): boolean
        if not player or player == localPlayer then
            return false
        end
        return not isTeammate(player)
    end

    local function enemies(): {Player}
        local list: {Player} = {}
        for _, player: Player in ipairs(players:GetPlayers()) do
            if player ~= localPlayer
                and player:GetAttribute("Died") ~= true
                and isEnemy(player)
                and isAlive(player) then
                table.insert(list, player)
            end
        end
        return list
    end

    local function describe(): string
        local teammates: number = 0
        local enemyCount: number = 0
        local unknown: number = 0
        for _, player: Player in ipairs(players:GetPlayers()) do
            if player ~= localPlayer then
                local _, token: string? = resolve(player)
                if token == nil then
                    unknown += 1
                elseif isTeammate(player) then
                    teammates += 1
                else
                    enemyCount += 1
                end
            end
        end
        local myRole: string? = resolve(localPlayer)
        return "you=" .. tostring(myRole or "unknown")
            .. " · teammates=" .. tostring(teammates)
            .. " · enemies=" .. tostring(enemyCount)
            .. " · unknown=" .. tostring(unknown)
            .. " · source=" .. tostring(lastSource or "none")
    end

    state.mvsdCore = {
        roleOf = function(player: Player): string?
            local role: string? = resolve(player)
            return role
        end,
        teamOf = function(player: Player): string?
            local _, token: string? = resolve(player)
            return token
        end,
        isTeammate = isTeammate,
        isEnemy = isEnemy,
        isAlive = isAlive,
        inSameMatch = inSameMatch,
        enemies = enemies,
        describe = describe,
        clearCache = clearCache,
    }

    local teamProvider: any = {
        Name = "MVSD",
        Get = function(instance: Instance): string?
            local player: Player? = nil
            if instance:IsA("Player") then
                player = instance :: Player
            elseif instance:IsA("Model") then
                player = players:GetPlayerFromCharacter(instance :: Model)
            end
            if not player then
                return nil
            end
            local _, token: string? = resolve(player)
            return token
        end,
        IsFriendly = function(player: Player?): boolean
            return isTeammate(player)
        end,
    }
    if type(host.registerTeamProvider) == "function" then
        host.registerTeamProvider(teamProvider)
    end

    local diagnosticConnection: any = nil

    local function stopDiagnostics(): ()
        if diagnosticConnection then
            diagnosticConnection:Disconnect()
            diagnosticConnection = nil
        end
    end

    local function startDiagnostics(): ()
        stopDiagnostics()
        local lastLog: number = 0
        diagnosticConnection = runService.Heartbeat:Connect(function(): ()
            local now: number = os.clock()
            if now - lastLog < 2 then
                return
            end
            lastLog = now
            clearCache()
            if settings.logDetection then
                print("[MVSD:Teams] " .. describe())
            end
        end)
    end

    local parentScroll: any = state and state.mvsdScroll
    local featuresRegistry: any = state and state.mvsdFeatures

    local TeamFeature: any = createUniversalFeature(
        "Team Detection",
        "Works out who fights for you in Duels so the ESP paints teammates "
            .. "white and enemies red",
        1,
        function(enabled: boolean): ()
            settings.enabled = enabled
            if enabled then
                startDiagnostics()
            else
                stopDiagnostics()
            end
        end,
        {
            parent = parentScroll,
            registry = featuresRegistry,
            categoryName = "Render",
        }
    )

    addCycleOption(TeamFeature, "Source", SOURCE_OPTIONS, 1, function(value: string): ()
        settings.source = value
        clearCache()
    end, "Where the team is read from. Auto tries every source in turn")

    addToggleOption(TeamFeature, "Only my match", true, function(value: boolean): ()
        settings.onlyMyMatch = value
        clearCache()
    end, "Never treat a player from another lobby as a teammate")

    addToggleOption(TeamFeature, "Log detection", false, function(value: boolean): ()
        settings.logDetection = value
    end, "Print the resolved teams to the console every 2 seconds")

    addActionOption(TeamFeature, "Re-scan teams", function(): ()
        clearCache()
        print("[MVSD:Teams] " .. describe())
    end, "Drops the cache and prints what every player resolved to")

    moduleCleanup = function(): ()
        stopDiagnostics()
        if state.gameBridge and state.gameBridge.teamProvider == teamProvider then
            state.gameBridge.teamProvider = nil
        end
        if state.teamProvider == teamProvider then
            state.teamProvider = nil
        end
        state.mvsdCore = nil
        clearCache()
    end

    Module.Events = {teamProvider = teamProvider}
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(moduleCleanup)
    moduleCleanup = function(): () end
    Module.Events = {}
    Module.Menu = nil
    Module.Runtime = nil
end

return Module
