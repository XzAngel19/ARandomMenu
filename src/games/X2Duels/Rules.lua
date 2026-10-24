-- Pure rules shared by X2 Duels combat, ESP and match automation.
-- No remote argument schemas live here: combat uses the game's native Tools.

local Module = {
    Name = "X2Duels Rules",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local function compact(value: any): string
    return string.lower(tostring(value or "")):gsub("[%W_]", "")
end

local function normalizeToken(value: any): string?
    if value == nil or value == false then
        return nil
    end
    local valueType: string = type(value)
    if valueType == "string" then
        local trimmed: string = string.match(value, "^%s*(.-)%s*$") or ""
        local lowered: string = string.lower(trimmed)
        if lowered == "" or lowered == "false" or lowered == "none"
            or lowered == "nil" then
            return nil
        end
        return lowered
    end
    if valueType == "number" or valueType == "boolean" then
        return string.lower(tostring(value))
    end

    -- Team objects are accepted without making the pure rules depend on
    -- Roblox's typeof(). Unsupported userdata simply has no readable Name.
    local ok: boolean, name: any = pcall(function(): any
        return value.Name
    end)
    if ok and name ~= nil and name ~= value then
        return normalizeToken(name)
    end
    return nil
end

local function sameMatch(localMatch: any, otherMatch: any): boolean
    local mine: string? = normalizeToken(localMatch)
    if mine == nil then
        -- Manual features can still work in places without match attributes.
        -- Auto Win additionally requires its own active-match signal.
        return true
    end
    local theirs: string? = normalizeToken(otherMatch)
    return theirs ~= nil and mine == theirs
end

local function relation(
    localTeam: any,
    otherTeam: any,
    sharesMatch: boolean
): string
    if not sharesMatch then
        return "Outside"
    end
    local mine: string? = normalizeToken(localTeam)
    local theirs: string? = normalizeToken(otherTeam)
    if mine == nil or theirs == nil then
        return "Unknown"
    end
    return mine == theirs and "Teammate" or "Enemy"
end

local function isOpponent(
    localTeam: any,
    otherTeam: any,
    sharesMatch: boolean,
    teamCheck: boolean
): boolean
    if not sharesMatch then
        return false
    end
    if not teamCheck then
        return true
    end
    -- Fail closed in team modes. Painting an unknown player amber is safer
    -- than killing a teammate because an attribute was late to replicate.
    return relation(localTeam, otherTeam, sharesMatch) == "Enemy"
end

local GUN_WORDS: {string} = {
    "gun", "revolver", "pistol", "rifle", "shotgun", "sniper", "uzi",
    "crossfire", "lightburst", "shooter", "shot",
}
local KNIFE_WORDS: {string} = {
    "knife", "blade", "dagger", "sword", "katana", "machete", "fang",
    "starcarver", "cometfall",
}

local function containsAny(text: string, words: {string}): boolean
    for _, word: string in ipairs(words) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

local function classifyTool(
    name: any,
    hasGunStructure: boolean?,
    hasKnifeStructure: boolean?
): string?
    local lowered: string = string.lower(tostring(name or ""))
    if hasGunStructure == true or containsAny(lowered, GUN_WORDS) then
        return "Gun"
    end
    if hasKnifeStructure == true or containsAny(lowered, KNIFE_WORDS) then
        return "Knife"
    end
    return nil
end

local function isPlayAgainText(value: any): boolean
    local key: string = compact(value)
    if key == "" then
        return false
    end
    if string.find(key, "playagain", 1, true)
        or string.find(key, "queueagain", 1, true) then
        return true
    end
    return key == "rematch"
        or key == "rematchbutton"
        or string.find(key, "rematchbutton", 1, true) ~= nil
end

local function isVictoryText(value: any): boolean
    if type(value) ~= "string" then
        return false
    end
    local key: string = compact(value)
    return key == "victory" or key == "winner" or key == "winners"
        or key == "win" or key == "won" or key == "youwin"
        or key == "youwon" or key == "roundwin" or key == "roundwon"
end

local function isLocalVictoryLabel(value: any): boolean
    if type(value) ~= "string" then
        return false
    end
    local key: string = compact(value)
    return key == "victory" or key == "youwin" or key == "youwon"
        or key == "roundwin" or key == "roundwon"
end

local function safeField(value: any, key: string): any
    if type(value) ~= "table" and type(value) ~= "userdata" then
        return nil
    end
    local ok: boolean, field: any = pcall(function(): any
        return value[key]
    end)
    return ok and field or nil
end

local function matchesIdentity(
    value: any,
    identity: {[string]: any},
    allowTeam: boolean,
    seen: {[any]: boolean}?,
    depth: number?
): boolean
    if value == nil then
        return false
    end
    if identity.player ~= nil and value == identity.player then
        return true
    end

    local valueType: string = type(value)
    if valueType == "string" or valueType == "number" then
        local token: string? = normalizeToken(value)
        if token == nil then
            return false
        end
        if token == "you" or token == "local" or token == "localplayer"
            or (allowTeam and token == "yourteam") then
            return true
        end
        for _, key: string in ipairs({"userId", "name", "displayName"}) do
            local expected: string? = normalizeToken(identity[key])
            if expected ~= nil and token == expected then
                return true
            end
        end
        if allowTeam then
            local team: string? = normalizeToken(identity.team)
            return team ~= nil and token == team
        end
        return false
    end
    if valueType ~= "table" and valueType ~= "userdata" then
        return false
    end
    if allowTeam then
        local expectedTeam: string? = normalizeToken(identity.team)
        local valueTeam: string? = normalizeToken(value)
        if expectedTeam ~= nil and valueTeam == expectedTeam then
            return true
        end
    end

    local level: number = depth or 0
    if level > 4 then
        return false
    end
    local visited: {[any]: boolean} = seen or {}
    if visited[value] then
        return false
    end
    visited[value] = true

    local userId: any = safeField(value, "UserId")
        or safeField(value, "PlayerId")
    if userId ~= nil then
        local expected: string? = normalizeToken(identity.userId)
        if expected ~= nil and normalizeToken(userId) == expected then
            return true
        end
    end
    for _, key: string in ipairs({"Player", "Name", "DisplayName"}) do
        local field: any = safeField(value, key)
        if field ~= nil and matchesIdentity(
            field, identity, false, visited, level + 1
        ) then
            return true
        end
    end
    if allowTeam then
        for _, key: string in ipairs({"Team", "TeamName", "TeamId", "Side"}) do
            local field: any = safeField(value, key)
            if field ~= nil then
                local expected: string? = normalizeToken(identity.team)
                local token: string? = normalizeToken(field)
                if expected ~= nil and token == expected then
                    return true
                end
            end
        end
    end
    if valueType == "table" then
        for key: any, field: any in pairs(value) do
            if type(key) == "number" and matchesIdentity(
                field, identity, allowTeam, visited, level + 1
            ) then
                return true
            end
        end
    end
    return false
end

local WINNER_KEYS: {[string]: boolean} = {
    winner = true,
    winners = true,
    winningplayer = true,
    winningplayers = true,
    winningteam = true,
    winningteams = true,
    winnerteam = true,
    teamwinner = true,
    victor = true,
    victors = true,
}
local OUTCOME_KEYS: {[string]: boolean} = {
    result = true,
    outcome = true,
    localresult = true,
    matchresult = true,
    roundresult = true,
}
local LOCAL_WIN_FLAGS: {[string]: boolean} = {
    won = true,
    iswinner = true,
    victory = true,
    localwon = true,
}

local function recordBelongsToOther(
    record: {[any]: any},
    identity: {[string]: any}
): boolean
    local userId: any = safeField(record, "UserId")
        or safeField(record, "PlayerId")
    local expectedUserId: string? = normalizeToken(identity.userId)
    if userId ~= nil and expectedUserId ~= nil then
        return normalizeToken(userId) ~= expectedUserId
    end
    local player: any = safeField(record, "Player")
    if player ~= nil and identity.player ~= nil then
        return player ~= identity.player
    end
    return false
end

local function scanResult(
    record: {[any]: any},
    identity: {[string]: any},
    seen: {[any]: boolean},
    depth: number
): boolean
    if depth > 5 or seen[record] then
        return false
    end
    seen[record] = true
    local belongsToOther: boolean = recordBelongsToOther(record, identity)

    for key: any, value: any in pairs(record) do
        if type(key) == "string" then
            local normalized: string = compact(key)
            if WINNER_KEYS[normalized] and matchesIdentity(
                value, identity, true, seen, depth + 1
            ) then
                return true
            end
            if not belongsToOther and OUTCOME_KEYS[normalized]
                and isVictoryText(value) then
                return true
            end
            if not belongsToOther and LOCAL_WIN_FLAGS[normalized]
                and value == true then
                return true
            end
        end
        if type(value) == "table" and scanResult(
            value, identity, seen, depth + 1
        ) then
            return true
        end
    end
    return false
end

local function didLocalWin(
    arguments: {[any]: any},
    identity: {[string]: any},
    directWinnerArguments: boolean?
): boolean
    if directWinnerArguments == true then
        for _, value: any in ipairs(arguments) do
            if type(value) == "string" then
                local outcome: string = compact(value)
                if string.find(outcome, "defeat", 1, true)
                    or string.find(outcome, "loss", 1, true)
                    or outcome == "lost" then
                    return false
                end
            end
        end
        for _, value: any in ipairs(arguments) do
            if type(value) ~= "table" and matchesIdentity(
                value, identity, true, nil, 0
            ) then
                return true
            end
        end
    end
    for _, value: any in ipairs(arguments) do
        if type(value) == "table" and scanResult(value, identity, {}, 0) then
            return true
        end
    end
    return false
end

Module.compact = compact
Module.normalizeToken = normalizeToken
Module.sameMatch = sameMatch
Module.relation = relation
Module.isOpponent = isOpponent
Module.classifyTool = classifyTool
Module.isPlayAgainText = isPlayAgainText
Module.isVictoryText = isVictoryText
Module.isLocalVictoryLabel = isLocalVictoryLabel
Module.matchesIdentity = matchesIdentity
Module.didLocalWin = didLocalWin

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    assert(type(runtime) == "table" and type(runtime.State) == "table",
        "X2Duels Rules requires Runtime.State")
    Module.Runtime = runtime
    runtime.State.x2duelsRules = Module
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    local runtime: any = Module.Runtime
    if runtime and runtime.State and runtime.State.x2duelsRules == Module then
        runtime.State.x2duelsRules = nil
    end
    Module.Runtime = nil
    Module.Initialized = false
end

return Module
