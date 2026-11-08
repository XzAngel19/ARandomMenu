-- v193: "Server Settings" (Utilities).
--
-- What it does, and what it deliberately does NOT do:
--   * It reads the server the player is actually in (Job ID, player count,
--     player limit, uptime, server clock, place name) and keeps that readout on
--     the card, live, the way AutoFarm's "Overlay Info" rows work: a section of
--     stat rows that a 1 Hz task keeps writing for as long as the module lives.
--     There is no window, no timer that expires and no "refresh every" ceiling.
--   * It copies the Job ID and hops to another public server of the same place.
--   * It sets no server-side property. A Roblox client cannot change another
--     server's settings; a card that claimed to would be lying.
--
-- History, so the next edit does not undo it:
--   v191 shipped the card with "Rejoin Server", a readout that only refreshed
--   while the card was ON, and hops that could land on a full instance.
--   v192 removed the rejoin, required a free slot for a hop and drew a floating
--   overlay Frame -- which landed on top of the menu's own options and stopped
--   whenever the card was switched off.
--   v193 (the player's report) removes that window: the info is a live section
--   inside the card, it never stops, it carries server data only (no Build, no
--   Round, no You), the place row shows the place NAME and marks a subplace.
--   The hops no longer depend on any endpoint flag: every listed server is read,
--   only the ones with a free slot are candidates, and when none is joinable the
--   card falls back to joining a random server instead of failing silently.
export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "ServerSettings",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil
-- Kept so destroy() can drop the 1 Hz readout without holding the whole host.
local disconnectTicker: ((string) -> ())? = nil

-- One hop per couple of seconds at most: the public endpoint rate-limits hard
-- and a hop already interrupts the session, so stacked calls are worthless.
local HOP_COOLDOWN: number = 3

-- The live readout ticks at 1 Hz. It is not tied to the card's toggle: the
-- player asked for information that never stops, and a stat row costs one label
-- write when (and only when) the string changes.
local STAT_INTERVAL: number = 1

-- How many pages of the public server list a hop reads. Each page is 100
-- servers; two pages per sort order is ~200 candidates, which is plenty and
-- keeps the request count (and the rate limit) sane.
local MAX_PAGES: number = 2

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addInformationOption: any = host.addInformationOption
    local notify: any = host.notify
    local cloneReference: any = host.cloneReference
    local services: any = context.services or {}

    local players: any = host.Players or game:GetService("Players")
    local httpService: any = cloneReference
        and cloneReference(game:GetService("HttpService"))
        or game:GetService("HttpService")
    local teleportService: any = cloneReference
        and cloneReference(game:GetService("TeleportService"))
        or game:GetService("TeleportService")

    local tick: any = if host.TaskManager and host.TaskManager.Connect
        then host.TaskManager
        else nil
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    if type(disconnectFeatureConnection) == "function" then
        disconnectTicker = disconnectFeatureConnection
    end

    local settings = {
        showInfo = true,
    }
    local lastHopAt: number = -math.huge
    local elapsed: number = 0
    local hopping: boolean = false
    -- Declared before every closure that touches it.
    local card: any = nil
    local statRows: {[string]: any} = {}

    local function say(message: string, kind: string?): ()
        if type(notify) == "function" then
            pcall(notify, message, kind)
        end
    end

    local function jobId(): string
        local ok: boolean, value: any = pcall(function(): any
            return game.JobId
        end)
        if not ok or type(value) ~= "string" or value == "" then
            return ""
        end
        return value
    end

    local function playerList(): {any}
        local ok: boolean, list: any = pcall(function(): any
            return players:GetPlayers()
        end)
        if not ok or type(list) ~= "table" then
            return {}
        end
        return list
    end

    local function maxPlayers(): number
        local ok: boolean, value: any = pcall(function(): any
            return players.MaxPlayers
        end)
        if ok and type(value) == "number" then
            return value
        end
        return 0
    end

    -- Seconds since this server was started. `DistributedGameTime` is the
    -- server's own clock: it does not reset when you respawn or rejoin, which is
    -- exactly what "how long has this server been up" means.
    local function uptimeSeconds(): number
        local ok: boolean, value: any = pcall(function(): any
            return workspace.DistributedGameTime
        end)
        if ok and type(value) == "number" and value >= 0 then
            return value
        end
        return 0
    end

    local function clockText(): string
        local ok: boolean, value: any = pcall(function(): any
            return workspace:GetServerTimeNow()
        end)
        local stamp: number = if ok and type(value) == "number"
            then math.floor(value)
            else os.time()
        local date: any = os.date("!*t", stamp)
        if type(date) ~= "table" then
            return "--:--:--"
        end
        return string.format("%02d:%02d:%02d", date.hour, date.min, date.sec)
    end

    local function durationText(seconds: number): string
        local total: number = math.max(0, math.floor(seconds))
        local hours: number = math.floor(total / 3600)
        local minutes: number = math.floor((total % 3600) / 60)
        local secs: number = total % 60
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    end

    -- Place should show the real place name (via MarketplaceService) and
    -- whether it's a subplace (PlaceId != GameId). Falls back to game.Name.
    local function placeText(): string
        local placeOk: boolean, placeId: any = pcall(function(): any
            return game.PlaceId
        end)
        local gameOk: boolean, gameId: any = pcall(function(): any
            return game.GameId
        end)
        local label: string = "Unknown place"
        -- Try MarketplaceService for the actual place name (most accurate)
        local marketOk: boolean, marketName: any = pcall(function(): any
            local ms: any = game:GetService("MarketplaceService")
            local info: any = ms:GetProductInfo(placeId)
            return info and info.Name
        end)
        if marketOk and type(marketName) == "string" and marketName ~= "" then
            label = marketName
        else
            local nameOk: boolean, name: any = pcall(function(): any
                return game.Name
            end)
            if nameOk and type(name) == "string" and name ~= "" then
                label = name
            elseif placeOk and type(placeId) == "number" then
                label = "Place " .. tostring(placeId)
            end
        end
        if placeOk and gameOk
            and type(placeId) == "number" and type(gameId) == "number"
            and placeId ~= gameId then
            return label .. " · subplace"
        end
        return label
    end

    local function namesText(limit: number): string
        local list: {any} = playerList()
        local names: {string} = {}
        for _, player: any in ipairs(list) do
            local ok: boolean, name: any = pcall(function(): any
                return player.Name
            end)
            if ok and type(name) == "string" then
                table.insert(names, name)
            end
        end
        if #names == 0 then
            return "—"
        end
        local joined: string = table.concat(names, ", ")
        if #joined > limit then
            joined = string.sub(joined, 1, math.max(1, limit - 1)) .. "…"
        end
        return joined
    end

    local function shortJobId(): string
        local id: string = jobId()
        if id == "" then
            return "private server"
        end
        if #id > 8 then
            return string.sub(id, 1, 8)
        end
        return id
    end

    local function infoText(): string
        local limit: number = maxPlayers()
        return string.format(
            "%s · %d/%d · up %s",
            shortJobId(),
            #playerList(),
            if limit > 0 then limit else #playerList(),
            durationText(uptimeSeconds())
        )
    end

    ---------------------------------------------------------------
    -- Live readout (AutoFarm-style stat rows)
    ---------------------------------------------------------------

    -- The rows the card keeps writing. Server data only: the player asked for
    -- Build, Round and You to be removed, and for the place row to name the
    -- place (and say when it is a subplace).
    local statRowsDefinition: {{key: string, label: string, read: () -> string}} = {
        {key = "server", label = "Server", read = shortJobId},
        {key = "players", label = "Players", read = function(): string
            local limit: number = maxPlayers()
            return string.format(
                "%d / %d",
                #playerList(),
                if limit > 0 then limit else #playerList()
            )
        end},
        {key = "inServer", label = "In server", read = function(): string
            return namesText(34)
        end},
        {key = "uptime", label = "Uptime", read = function(): string
            return durationText(uptimeSeconds())
        end},
        {key = "serverTime", label = "Server time", read = function(): string
            return clockText()
        end},
        {key = "place", label = "Place", read = placeText},
    }

    local function ensureStatRows(): ()
        if not card or next(statRows) ~= nil then
            return
        end
        if type(state.addSectionOption) == "function" then
            pcall(state.addSectionOption, card, "Overlay Info")
        end
        if type(state.addStatOption) ~= "function" then
            return
        end
        for _, definition: any in ipairs(statRowsDefinition) do
            local ok: boolean, row: any = pcall(
                state.addStatOption,
                card,
                definition.label,
                "—"
            )
            if ok and row then
                statRows[definition.key] = row
            end
        end
    end

    local function refreshStats(): ()
        ensureStatRows()
        for _, definition: any in ipairs(statRowsDefinition) do
            local row: any = statRows[definition.key]
            if row and type(row.set) == "function" then
                local ok: boolean, value: any = pcall(definition.read)
                local text: string = if ok and type(value) == "string" and value ~= ""
                    then value
                    else "—"
                pcall(row.set, text)
            end
        end
        if card and type(card.SetStatus) == "function" then
            if settings.showInfo then
                pcall(function(): ()
                    card:SetStatus(infoText())
                end)
            else
                pcall(function(): ()
                    card:SetStatus(nil)
                end)
            end
        end
    end

    -- One connection for the lifetime of the module: it is created at init and
    -- only dropped by destroy(), so the readout cannot stop when the card is
    -- toggled or when an option is changed. 1 Hz, and every write is guarded by
    -- a string comparison inside the stat row.
    local function startTicker(): ()
        if not (tick and featureConnections) then
            return
        end
        if featureConnections.ServerSettingsTick then
            return
        end
        featureConnections.ServerSettingsTick = tick:Connect(
            function(deltaTime: number): ()
                elapsed += math.max(0, deltaTime or 0)
                if elapsed < STAT_INTERVAL then
                    return
                end
                elapsed = 0
                refreshStats()
            end,
            nil,
            "Server Settings"
        )
    end

    local function copyJobId(): ()
        local id: string = jobId()
        if id == "" then
            say("This server has no Job ID to copy.")
            return
        end
        -- Executors expose `setclipboard` as a global; a plain Roblox client
        -- does not, so the message still carries the id when copying fails.
        local clipboard: any = host.setclipboard or setclipboard
        local copied: boolean = false
        if type(clipboard) == "function" then
            copied = pcall(clipboard, id)
        end
        if copied then
            say("Job ID copied: " .. id, "good")
        else
            say("Job ID: " .. id)
        end
    end

    ---------------------------------------------------------------
    -- Server list
    ---------------------------------------------------------------

    -- One page of the public server list, as the Roblox web app reads it.
    -- `sortOrder` is what makes the difference between the quiet end and the
    -- busy end of the place; `cursor` walks further into the list.
    --
    -- v193: the request sends only `sortOrder`, `limit` and (for deeper pages)
    -- `cursor`. The client filters full instances itself, so it can also explain
    -- what it saw, and an unsupported query flag can no longer turn every hop
    -- into "the request failed".
    local function fetchPage(
        sortOrder: string,
        cursor: string?
    ): ({any}?, string?, string?)
        local endpoint: string = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100",
            game.PlaceId,
            sortOrder
        )
        if type(cursor) == "string" and cursor ~= "" then
            endpoint = endpoint .. "&cursor=" .. cursor
        end
        local ok: boolean, body: any = pcall(function(): any
            return (game :: any):HttpGet(endpoint)
        end)
        if not ok or type(body) ~= "string" or body == "" then
            return nil, nil, "the server list request failed (executor HTTP is blocked?)"
        end
        local decodeOk: boolean, decoded: any = pcall(function(): any
            return httpService:JSONDecode(body)
        end)
        if not decodeOk or type(decoded) ~= "table" or type(decoded.data) ~= "table" then
            return nil, nil, "the server list answer could not be read"
        end
        local nextCursor: any = decoded.nextPageCursor
        return decoded.data, if type(nextCursor) == "string" then nextCursor else nil, nil
    end

    -- Every candidate the place publishes, up to MAX_PAGES per sort order.
    local function collectPool(orders: {string}): ({any}, number, string?)
        local here: string = jobId()
        local pool: {any} = {}
        local seen: {[string]: boolean} = {}
        local total: number = 0
        local lastError: string? = nil
        for _, order: string in ipairs(orders) do
            local cursor: string? = nil
            for _ = 1, MAX_PAGES do
                local page: {any}?, nextCursor: string?, errorText: string? =
                    fetchPage(order, cursor)
                if not page then
                    lastError = errorText
                    break
                end
                for _, entry: any in ipairs(page) do
                    total += 1
                    if type(entry) == "table"
                        and type(entry.id) == "string"
                        and entry.id ~= ""
                        and entry.id ~= here
                        and not seen[entry.id] then
                        seen[entry.id] = true
                        table.insert(pool, entry)
                    end
                end
                if not nextCursor then
                    break
                end
                cursor = nextCursor
            end
        end
        return pool, total, lastError
    end

    -- A server is a candidate only when it has a slot this client can take.
    -- `playing == maxPlayers` is a full instance: TeleportToPlaceInstance
    -- rejects it, which is why v191 hops often died silently.
    local function slotFree(entry: any): boolean
        local playing: number? = tonumber(entry and entry.playing)
        if not playing or playing < 0 then
            return false
        end
        local limit: number? = tonumber(entry and entry.maxPlayers)
        if limit and limit > 0 then
            return playing < limit
        end
        -- No limit published: treat anything under 100 as joinable.
        return playing < 100
    end

    local function playersIn(entry: any): number
        return tonumber(entry and entry.playing) or 0
    end

    local function joinablePool(entries: {any}): {any}
        local pool: {any} = {}
        for _, entry: any in ipairs(entries) do
            if slotFree(entry) then
                table.insert(pool, entry)
            end
        end
        return pool
    end

    local function pick(pool: {any}, mode: string): any
        if #pool == 0 then
            return nil
        end
        -- Empty instances are never "smallest": a 0/12 server answers no
        -- question the player asked and empties out again in seconds.
        local populated: {any} = {}
        for _, entry: any in ipairs(pool) do
            if playersIn(entry) >= 1 then
                table.insert(populated, entry)
            end
        end
        local candidates: {any} = if #populated > 0 then populated else pool
        if mode == "random" then
            return candidates[math.random(1, #candidates)]
        end
        local chosen: any = candidates[1]
        for index: number = 2, #candidates do
            local entry: any = candidates[index]
            if mode == "largest" then
                if playersIn(entry) > playersIn(chosen) then
                    chosen = entry
                end
            elseif playersIn(entry) < playersIn(chosen) then
                chosen = entry
            end
        end
        return chosen
    end

    local function hop(mode: string): ()
        if hopping then
            return
        end
        if os.clock() - lastHopAt < HOP_COOLDOWN then
            say("Slow down: wait a moment before hopping again.")
            return
        end
        hopping = true
        task.spawn(function(): ()
            local ok: boolean, failure: any = pcall(function(): ()
                -- Smallest prefers quiet end, largest prefers busy end; random checks both.
                local orders: {string}
                if mode == "largest" then
                    orders = {"Desc"}
                elseif mode == "random" then
                    orders = {"Asc", "Desc"}
                else -- smallest
                    orders = {"Asc"}
                end
                local entries: {any}, total: number, errorText: string? =
                    collectPool(orders)
                local pool: {any} = joinablePool(entries)
                local chosen: any = pick(pool, mode)
                lastHopAt = os.clock()
                if not chosen then
                    -- Nothing joinable in the list, but the player asked to hop:
                    -- Teleport(place) lets Roblox pick a server with room. That
                    -- always beats a notice that says "no server found" and
                    -- leaves the player where they were.
                    local reason: string = if total == 0
                        then tostring(errorText or "the server list is empty")
                        else string.format(
                            "all %d listed servers are full",
                            total
                        )
                    say("Server hop: " .. reason .. " · joining any server instead…", "danger")
                    local teleported: boolean = pcall(function(): ()
                        teleportService:Teleport(game.PlaceId, LocalPlayer)
                    end)
                    if not teleported then
                        say("Server hop was refused by TeleportService.", "danger")
                    end
                    return
                end
                local playing: number = playersIn(chosen)
                local limit: number = tonumber(chosen.maxPlayers) or 0
                say(string.format(
                    "Hopping to the %s server: %d/%d players…",
                    mode,
                    playing,
                    if limit > 0 then limit else playing + 1
                ))
                local teleported: boolean = pcall(function(): ()
                    teleportService:TeleportToPlaceInstance(
                        game.PlaceId,
                        chosen.id,
                        LocalPlayer
                    )
                end)
                if not teleported then
                    say("Server hop was refused by TeleportService.", "danger")
                end
            end)
            hopping = false
            if not ok then
                say("Server hop failed: " .. tostring(failure), "danger")
            end
        end)
    end

    card = createUniversalFeature(
        "Server Settings",
        "Live server readout (Job ID, players, uptime, place) plus hops that only land on a server with a free slot.",
        8,
        function(enabled: boolean): ()
            -- The readout never stops: switching the card only refreshes it at
            -- once so the rows are current when the card is looked at.
            if enabled then
                elapsed = STAT_INTERVAL
                refreshStats()
            end
        end,
        {categoryName = "Utilities"}
    )
    activeCard = card

    addActionOption(card, "Copy Job ID", copyJobId)
    addActionOption(card, "Hop: smallest server", function(): ()
        hop("smallest")
    end)
    addActionOption(card, "Hop: largest server", function(): ()
        hop("largest")
    end)
    addActionOption(card, "Hop: random server", function(): ()
        hop("random")
    end)
    addInformationOption(
        card,
        "A Roblox client cannot change another server's settings. This card "
            .. "shows YOUR server, live, and moves you between public ones. "
            .. "A hop only lands where a slot is free; \"smallest\" skips empty "
            .. "instances and \"largest\" is the fullest server you can still "
            .. "join (e.g. 11/12). If every listed server is full, the hop joins "
            .. "a random one instead of failing."
    )

    ensureStatRows()
    refreshStats()
    startTicker()

    state.serverSettingsCard = card
    state.serverSettings = settings
    state.serverSettingsStats = statRows
    -- Readable by the offline suites: the hop decision is pure, and a test can
    -- check it without a live Roblox client.
    state.serverSettingsPick = function(entries: {any}, mode: string): string?
        local here: string = jobId()
        local filtered: {any} = {}
        for _, entry: any in ipairs(entries or {}) do
            if type(entry) == "table"
                and type(entry.id) == "string"
                and entry.id ~= here
                and slotFree(entry) then
                table.insert(filtered, entry)
            end
        end
        local chosen: any = pick(filtered, mode)
        return if chosen then tostring(chosen.id) else nil
    end
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    if type(disconnectTicker) == "function" then
        pcall(disconnectTicker, "ServerSettingsTick")
    end
    state.serverSettingsCard = nil
    state.serverSettings = nil
    state.serverSettingsStats = nil
    state.serverSettingsPick = nil
    activeCard = nil
end

return Module
