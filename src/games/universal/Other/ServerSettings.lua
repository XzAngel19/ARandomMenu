-- v192: "Server Settings" (Utilities).
--
-- What it does, and what it deliberately does NOT do:
--   * It reads the server the player is actually in (Job ID, player count,
--     player limit, uptime, place version) and shows it on the card, in a
--     toast-length status line AND, when "Show server info" is ON, in a small
--     floating overlay that carries every field the client can read.
--   * It copies the Job ID and hops to another public server of the same place.
--   * It sets no server-side property. A Roblox client cannot change another
--     server's settings; a card that claimed to would be lying. Everything here
--     is local: the info readout and the TeleportService calls.
--
-- v192 changes, asked for by the player:
--   * "Rejoin Server" is gone. It duplicated what the Roblox menu already does
--     and every accidental press threw the player out of the round.
--   * The hops now mean something. v191 asked the endpoint for the 100 lowest
--     (`Asc`) or highest (`Desc`) servers and then picked from a pool that
--     still contained FULL servers, so a "hop" bounced into an empty 1/12
--     instance -- or failed outright because 12/12 rejects the join. Now a
--     server is only a candidate when `playing < maxPlayers` (a real slot),
--     empty instances are never "smallest", and "largest" means the fullest
--     server you can still join (11/12 for a 12-slot place, exactly what the
--     player described). "Random" merges both pages so it is not biased to the
--     near-empty end.
--   * "Show server info" opens an overlay instead of only writing a short line
--     on the card.
--
-- Server hopping uses the public servers endpoint the Roblox web app itself
-- uses. Executors route `game:HttpGet` through their own queue, so the request
-- is made from the executor, never from the game's own HTTP identity.
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
local activeOverlay: any = nil

-- One hop per couple of seconds at most: the public endpoint rate-limits hard
-- and a hop already interrupts the session, so stacked calls are worthless.
local HOP_COOLDOWN: number = 3

-- The overlay is a plain ScreenGui frame, rebuilt lazily and only while the
-- option is ON: an idle menu allocates nothing.
local OVERLAY_NAME: string = "WurstServerInfo"

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
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

    -- GUI building blocks. A module runs inside the menu environment, so these
    -- are the same helpers every other card uses.
    local create: any = host.create or create
    local screenGui: any = host.ScreenGui or ScreenGui
    local theme: any = host.Theme or Theme or {}
    local product: any = host.PRODUCT or PRODUCT or {}

    -- The info readout only ticks while the card is ON, so an idle menu does no
    -- per-frame work.
    local tick: any = if host.TaskManager and host.TaskManager.Connect
        then host.TaskManager
        else nil
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection

    local settings = {
        showInfo = true,
        refreshSeconds = 3,
    }
    local lastHopAt: number = -math.huge
    local elapsed: number = 0
    local hopping: boolean = false
    -- Declared before every closure that touches it: a `local` introduced after
    -- a closure would leave that closure reading a global instead.
    local card: any = nil

    local function say(message: string, kind: string?): ()
        if type(notify) == "function" then
            pcall(notify, message, kind)
        end
    end

    local function colour(token: string, fallback: Color3): Color3
        local ok: boolean, value: any = pcall(function(): any
            return theme[token]
        end)
        if ok and typeof(value) == "Color3" then
            return value
        end
        return fallback
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

    local function playerCount(): number
        local ok: boolean, list: any = pcall(function(): any
            return players:GetPlayers()
        end)
        if not ok or type(list) ~= "table" then
            return 0
        end
        return #list
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
    -- server's own clock: it does not reset when you respawn or rejoin, which
    -- is exactly what "how long has this server been up" means.
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

    local function placeInfo(): string
        local okVersion: boolean, version: any = pcall(function(): any
            return game.PlaceVersion
        end)
        local versionText: string = if okVersion and type(version) == "number"
            then "v" .. tostring(version)
            else "v?"
        local okName: boolean, name: any = pcall(function(): any
            return game.Name
        end)
        local label: string = if okName and type(name) == "string" and name ~= ""
            then name
            else "Place " .. tostring(game.PlaceId)
        return string.format("%s · %s", label, versionText)
    end

    local function namesText(): string
        local ok: boolean, list: any = pcall(function(): any
            return players:GetPlayers()
        end)
        if not ok or type(list) ~= "table" then
            return "—"
        end
        local names: {string} = {}
        for _, player: any in ipairs(list) do
            local nameOk: boolean, name: any = pcall(function(): any
                return player.Name
            end)
            if nameOk and type(name) == "string" then
                table.insert(names, name)
            end
        end
        if #names == 0 then
            return "—"
        end
        local joined: string = table.concat(names, ", ")
        if #joined > 64 then
            joined = string.sub(joined, 1, 61) .. "…"
        end
        return joined
    end

    local function localPlayerText(): string
        local okName: boolean, name: any = pcall(function(): any
            return LocalPlayer and LocalPlayer.Name
        end)
        local okId: boolean, id: any = pcall(function(): any
            return LocalPlayer and LocalPlayer.UserId
        end)
        local nameText: string = if okName and type(name) == "string"
            then name
            else "—"
        local idText: string = if okId and type(id) == "number"
            then tostring(id)
            else "?"
        return string.format("%s (%s)", nameText, idText)
    end

    local function roundText(): string
        local core: any = state.mm2Core
        if type(core) ~= "table" or type(core.getRoundPhase) ~= "function" then
            return ""
        end
        local ok: boolean, phase: any = pcall(core.getRoundPhase)
        if not ok or type(phase) ~= "string" then
            return ""
        end
        return phase
    end

    local function infoText(): string
        local id: string = jobId()
        local shortId: string = if #id > 8 then string.sub(id, 1, 8) else id
        local count: number = playerCount()
        local limit: number = maxPlayers()
        return string.format(
            "%s · %d/%d · up %s",
            shortId ~= "" and shortId or "private server",
            count,
            limit > 0 and limit or count,
            durationText(uptimeSeconds())
        )
    end

    ------------------------------------------------------------------
    -- Overlay
    ------------------------------------------------------------------

    -- Ordered rows: label, and the function that reads the value. Built once,
    -- read every refresh, so the overlay never reallocates while it is open.
    local overlayRows: {{label: string, read: () -> string}} = {
        {label = "Job ID", read = function(): string
            local id: string = jobId()
            return if id ~= "" then id else "private server"
        end},
        {label = "Players", read = function(): string
            return string.format("%d / %d", playerCount(), maxPlayers())
        end},
        {label = "In server", read = namesText},
        {label = "Uptime", read = function(): string
            return durationText(uptimeSeconds())
        end},
        {label = "Server clock", read = function(): string
            return clockText() .. " UTC"
        end},
        {label = "Place", read = placeInfo},
        {label = "You", read = localPlayerText},
        {label = "Build", read = function(): string
            local version: any = product.version
            return if type(version) == "string" then version else "—"
        end},
        {label = "Round", read = roundText},
    }

    local overlayValues: {any} = {}

    local function overlayDestroy(): ()
        if activeOverlay and activeOverlay.Parent then
            pcall(function(): ()
                activeOverlay.Parent = nil
            end)
        end
        activeOverlay = nil
        overlayValues = {}
    end

    local function overlayBuild(): any
        if activeOverlay and activeOverlay.Parent then
            return activeOverlay
        end
        if type(create) ~= "function" or not screenGui then
            return nil
        end

        local root: any = create("Frame", {
            Name = OVERLAY_NAME,
            Parent = screenGui,
            BackgroundColor3 = colour("tooltip", Color3.fromRGB(16, 16, 18)),
            BackgroundTransparency = 0.06,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Position = UDim2.new(0, 18, 0, 96),
            Size = UDim2.new(0, 268, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 46,
        })
        pcall(function(): ()
            create("UICorner", {
                Parent = root,
                CornerRadius = UDim.new(0, 6),
            })
            create("UIStroke", {
                Parent = root,
                Color = colour("outline", Color3.fromRGB(92, 92, 98)),
                Thickness = 1,
            })
        end)

        local header: any = create("Frame", {
            Name = "Header",
            Parent = root,
            BackgroundColor3 = colour("accentSoft", Color3.fromRGB(52, 52, 56)),
            BackgroundTransparency = 0.25,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 26),
            ZIndex = 47,
        })
        create("TextLabel", {
            Name = "Title",
            Parent = header,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            Text = "Server Info",
            TextColor3 = colour("text", Color3.fromRGB(245, 245, 247)),
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -34, 1, 0),
            ZIndex = 48,
        })
        -- Drag the header to move the overlay out of the way. `Draggable` is the
        -- one-line path and is harmless if the executor's build dropped it.
        pcall(function(): ()
            header.Active = true
            header.Draggable = true
        end)
        local close: any = create("TextButton", {
            Name = "Close",
            Parent = header,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            Text = "×",
            TextColor3 = colour("textMuted", Color3.fromRGB(158, 158, 166)),
            TextSize = 16,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -6, 0, 0),
            Size = UDim2.fromOffset(22, 26),
            ZIndex = 48,
        })
        close.MouseButton1Click:Connect(function(): ()
            settings.showInfo = false
            local key: string = tostring(card and card.configKey or "ServerSettings")
                .. ".Showserverinfo"
            if type(state.setToggleChecked) == "function" then
                pcall(state.setToggleChecked, key, false)
            end
            overlayDestroy()
        end)

        local body: any = create("Frame", {
            Name = "Body",
            Parent = root,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 26),
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 47,
        })
        create("UIListLayout", {
            Parent = body,
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        create("UIPadding", {
            Parent = body,
            PaddingTop = UDim.new(0, 6),
            PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
        })

        overlayValues = {}
        for index, row: any in ipairs(overlayRows) do
            local line: any = create("Frame", {
                Name = "Row" .. tostring(index),
                Parent = body,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 17),
                LayoutOrder = index,
                ZIndex = 48,
            })
            create("TextLabel", {
                Name = "Key",
                Parent = line,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Font = Enum.Font.Gotham,
                Text = row.label,
                TextColor3 = colour("textMuted", Color3.fromRGB(158, 158, 166)),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Size = UDim2.new(0.42, 0, 1, 0),
                ZIndex = 48,
            })
            overlayValues[index] = create("TextLabel", {
                Name = "Value",
                Parent = line,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Font = Enum.Font.Gotham,
                Text = "—",
                TextColor3 = colour("text", Color3.fromRGB(245, 245, 247)),
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Position = UDim2.new(0.42, 6, 0, 0),
                Size = UDim2.new(0.58, -6, 1, 0),
                ZIndex = 48,
            })
        end

        activeOverlay = root
        return root
    end

    local function overlayRefresh(): ()
        if not settings.showInfo then
            overlayDestroy()
            return
        end
        local root: any = overlayBuild()
        if not root then
            return
        end
        for index, row: any in ipairs(overlayRows) do
            local label: any = overlayValues[index]
            if label then
                local ok: boolean, value: any = pcall(row.read)
                local text: string = if ok and type(value) == "string" and value ~= ""
                    then value
                    else "—"
                if label.Text ~= text then
                    label.Text = text
                end
            end
        end
    end

    local function refreshStatus(): ()
        if activeCard and type(activeCard.SetStatus) == "function" then
            if settings.showInfo then
                pcall(function(): ()
                    activeCard:SetStatus(infoText())
                end)
            else
                pcall(function(): ()
                    activeCard:SetStatus(nil)
                end)
            end
        end
        overlayRefresh()
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

    -- The public server list, as the Roblox web app reads it. `sortOrder` is
    -- what makes the difference between an empty instance and a real one:
    -- Asc lists the quietest servers first, Desc the fullest.
    local function fetchServers(sortOrder: string): ({any}?, string?)
        local endpoint: string = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100&excludeFullServers=true",
            game.PlaceId,
            sortOrder
        )
        local ok: boolean, body: any = pcall(function(): any
            return (game :: any):HttpGet(endpoint)
        end)
        if not ok or type(body) ~= "string" or body == "" then
            return nil, "the server list request failed (executor HTTP is blocked?)"
        end
        local decodeOk: boolean, decoded: any = pcall(function(): any
            return httpService:JSONDecode(body)
        end)
        if not decodeOk or type(decoded) ~= "table"
            or type(decoded.data) ~= "table" then
            return nil, "the server list answer could not be read"
        end
        return decoded.data, nil
    end

    -- A server is a candidate only when it has a slot this client can take.
    -- `playing == maxPlayers` is a full instance: TeleportToPlaceInstance
    -- rejects it, which is why v191 hops often died silently.
    local function joinable(entry: any, here: string): boolean
        if type(entry) ~= "table" or type(entry.id) ~= "string" then
            return false
        end
        if entry.id == here or entry.id == "" then
            return false
        end
        local playing: number? = tonumber(entry.playing)
        if not playing or playing < 0 then
            return false
        end
        local limit: number? = tonumber(entry.maxPlayers)
        if limit and limit > 0 then
            return playing < limit
        end
        -- No limit published: treat anything under 100 as joinable.
        return playing < 100
    end

    local function playersIn(entry: any): number
        return tonumber(entry and entry.playing) or 0
    end

    local function collect(mode: string): ({any}?, string?)
        local here: string = jobId()
        local orders: {string} = {mode == "largest" and "Desc" or "Asc"}
        if mode == "random" then
            orders = {"Asc", "Desc"}
        end
        local pool: {any} = {}
        local seen: {[string]: boolean} = {}
        local lastError: string? = nil
        for _, order: string in ipairs(orders) do
            local servers: {any}?, errorText: string? = fetchServers(order)
            if not servers then
                lastError = errorText
                continue
            end
            for _, entry: any in ipairs(servers) do
                if joinable(entry, here) and not seen[entry.id] then
                    seen[entry.id] = true
                    table.insert(pool, entry)
                end
            end
        end
        if #pool == 0 then
            return nil, lastError or "no public server with a free slot is listed right now"
        end
        return pool, nil
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
                local pool: {any}?, errorText: string? = collect(mode)
                if not pool then
                    say("Server hop: " .. tostring(errorText), "danger")
                    return
                end
                local chosen: any = pick(pool, mode)
                if not chosen then
                    say("Server hop: no usable server was found.", "danger")
                    return
                end
                lastHopAt = os.clock()
                local playing: number = playersIn(chosen)
                local limit: number = tonumber(chosen.maxPlayers) or 0
                say(string.format(
                    "Hopping to the %s server: %d/%d players…",
                    mode,
                    playing,
                    limit > 0 and limit or playing + 1
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

    local function restartTick(): ()
        if type(disconnectFeatureConnection) == "function" then
            disconnectFeatureConnection("ServerSettingsTick")
        end
        if not card or card.enabled ~= true then
            return
        end
        if not (tick and featureConnections) then
            return
        end
        elapsed = 0
        featureConnections.ServerSettingsTick = tick:Connect(
            function(deltaTime: number): ()
                elapsed += math.max(0, deltaTime)
                if elapsed < settings.refreshSeconds then
                    return
                end
                elapsed = 0
                refreshStatus()
            end,
            nil,
            "Server Settings"
        )
    end

    card = createUniversalFeature(
        "Server Settings",
        "Reads the server you are in and hops to another public one with a free slot; nothing here writes to the server.",
        8,
        function(enabled: boolean): ()
            if not enabled then
                if type(disconnectFeatureConnection) == "function" then
                    disconnectFeatureConnection("ServerSettingsTick")
                end
                if card and type(card.SetStatus) == "function" then
                    pcall(function(): ()
                        card:SetStatus(nil)
                    end)
                end
                overlayDestroy()
                return
            end
            refreshStatus()
            restartTick()
        end,
        {categoryName = "Utilities"}
    )
    activeCard = card
    activeOverlay = nil

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
    addToggleOption(card, "Show server info", true, function(value: boolean): ()
        settings.showInfo = value == true
        refreshStatus()
    end, "Opens a floating overlay with the Job ID, player list, uptime, server clock and place version. Only while this card is ON.")
    addNumberOption(card, "Refresh every", 3, 1, 15, function(value: number): ()
        settings.refreshSeconds = math.clamp(tonumber(value) or 3, 1, 15)
        elapsed = 0
    end, "Seconds between two server info reads. Only runs while the card is ON.", 1, true)
    addInformationOption(
        card,
        "A Roblox client cannot change another server's settings. This card "
            .. "shows YOUR server and moves you between public ones. "
            .. "Hopping only picks servers with a free slot; \"smallest\" skips "
            .. "empty instances and \"largest\" is the fullest server you can "
            .. "still join (e.g. 11/12)."
    )

    -- The info readout only ticks while the card is ON, so an idle menu does no
    -- per-frame work. A card restored as ON at boot starts its tick here.
    restartTick()

    activeCard = card
    state.serverSettingsCard = card
    state.serverSettings = settings
    -- Readable by the offline suites: the hop semantics are a pure decision,
    -- and a test can check them without a live Roblox client.
    state.serverSettingsPick = function(entries: {any}, mode: string): string?
        local here: string = jobId()
        local pool: {any} = {}
        for _, entry: any in ipairs(entries or {}) do
            if joinable(entry, here) then
                table.insert(pool, entry)
            end
        end
        local chosen: any = pick(pool, mode)
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
    state.serverSettingsCard = nil
    state.serverSettings = nil
    state.serverSettingsPick = nil
    activeCard = nil
    if activeOverlay and activeOverlay.Parent then
        pcall(function(): ()
            activeOverlay.Parent = nil
        end)
    end
    activeOverlay = nil
end

return Module
