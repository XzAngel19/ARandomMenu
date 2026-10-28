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
            or lowered == "__none" or lowered == "nil" then
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

-- MVS also uses Team for FFA/lobby state. A shared sentinel is not a
-- team: treating it as one paints every player green and protects everyone.
local NON_TEAM_TOKENS: {[string]: boolean} = {
    ffa = true,
    freeforall = true,
    lobby = true,
    neutral = true,
    none = true,
    spectator = true,
    spectating = true,
    unknown = true,
    unassigned = true,
    solo = true,
    all = true,
    everyone = true,
    default = true,
    team = true,
    ["true"] = true,
}

local function normalizeTeamToken(value: any): string?
    local token: string? = normalizeToken(value)
    if token == nil or NON_TEAM_TOKENS[token] then
        return nil
    end
    return token
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
    local mine: string? = normalizeTeamToken(localTeam)
    local theirs: string? = normalizeTeamToken(otherTeam)
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

-- The 1v1 client consumes MatchResults(matchId, pages) and displays the
-- local page's Data.Outcome. Draw/Forfeit/Cancelled are not wins or losses.
local function matchResultOutcome(arguments: {any}): string?
    local pages: any = arguments[2]
    if type(arguments[1]) ~= "string" or arguments[1] == "" or type(pages) ~= "table" then
        return nil
    end
    for _, page: any in ipairs(pages) do
        if type(page) == "table"
            and (page.Page == "RoundInfo" or page.Page == "InfectionResult")
            and type(page.Data) == "table" then
            local outcome: any = page.Data.Outcome
            if outcome == "Win" then return "Win" end
            if outcome == "Loss" then return "Loss" end
            return "Neutral"
        end
    end
    return nil
end

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
    depth: number,
    inheritedOther: boolean?
): boolean
    if depth > 5 or seen[record] then
        return false
    end
    seen[record] = true
    -- A nested Data.Outcome remains the other player's result; dropping the
    -- parent identity used to turn an opponent's victory into a local one.
    local belongsToOther: boolean = inheritedOther == true
        or recordBelongsToOther(record, identity)

    for key: any, value: any in pairs(record) do
        if type(key) == "string" then
            local normalized: string = compact(key)
            if not belongsToOther and WINNER_KEYS[normalized] and matchesIdentity(
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
            value, identity, seen, depth + 1, belongsToOther
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

-- Solve a constant-speed projectile interception with optional downward
-- projectile gravity. The caller supplies calibrated values; this does not
-- assert that the native weapon is ballistic or that the server accepts it.
local function projectileInterceptTime(origin: any, target: any, velocity: any,
    speed: number, gravity: number, maxTime: number?): number?
    if type(speed) ~= "number" or speed ~= speed or speed <= 0 or speed > 100000
        or type(gravity) ~= "number" or gravity ~= gravity or gravity < 0 or gravity > 10000 then return nil end
    local function component(v: any, key: string): number?
        local ok: boolean, n: any = pcall(function(): any return v[key] end)
        if not ok or type(n) ~= "number" or n ~= n or math.abs(n) > 1000000 then return nil end
        return n
    end
    local ox, oy, oz = component(origin, "X"), component(origin, "Y"), component(origin, "Z")
    local tx, ty, tz = component(target, "X"), component(target, "Y"), component(target, "Z")
    local vx, vy, vz = component(velocity, "X"), component(velocity, "Y"), component(velocity, "Z")
    if not ox or not oy or not oz or not tx or not ty or not tz or not vx or not vy or not vz then return nil end
    local horizon: number = if type(maxTime) == "number" and maxTime == maxTime
        then math.clamp(maxTime, 0.05, 10) else 5
    local dx, dy, dz = tx - ox, ty - oy, tz - oz
    local function equation(t: number): number
        local x, y, z = dx + vx * t, dy + vy * t + 0.5 * gravity * t * t, dz + vz * t
        return x*x + y*y + z*z - speed*speed*t*t
    end
    if equation(0) < 0.0025 then return nil end
    local previous: number = 0
    for step: number = 1, 200 do
        local t: number = horizon * step / 200
        if equation(t) <= 0 then
            local low, high = previous, t
            for _ = 1, 24 do
                local mid: number = (low + high) / 2
                if equation(mid) > 0 then low = mid else high = mid end
            end
            return (low + high) / 2
        end
        previous = t
    end
    return nil
end

Module.projectileInterceptTime = projectileInterceptTime
Module.compact = compact
Module.normalizeToken = normalizeToken
Module.normalizeTeamToken = normalizeTeamToken
Module.sameMatch = sameMatch
Module.relation = relation
Module.isOpponent = isOpponent
Module.classifyTool = classifyTool
Module.isPlayAgainText = isPlayAgainText
Module.isVictoryText = isVictoryText
Module.isLocalVictoryLabel = isLocalVictoryLabel
Module.matchesIdentity = matchesIdentity
Module.matchResultOutcome = matchResultOutcome
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
