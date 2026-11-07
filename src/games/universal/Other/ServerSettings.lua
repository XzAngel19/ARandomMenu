-- v191: "Server Settings" (Utilities), new card.
--
-- What it does, and what it deliberately does NOT do:
--   * It reads the server the player is actually in (Job ID, player count,
--     player limit) and shows it on the card, refreshed on a timer.
--   * It copies the Job ID, rejoins the current instance, and can hop to the
--     smallest / largest / a random public server of the same place.
--   * It sets no server-side property. A Roblox client cannot change another
--     server's settings; a card that claimed to would be lying. Everything here
--     is local: the info readout and the TeleportService calls.
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

-- One hop per couple of seconds at most: the public endpoint rate-limits hard
-- and a hop already interrupts the session, so stacked calls are worthless.
local HOP_COOLDOWN: number = 3

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

    local function infoText(): string
        local id: string = jobId()
        local shortId: string = if #id > 8 then string.sub(id, 1, 8) else id
        local count: number = playerCount()
        local limit: number = maxPlayers()
        return string.format(
            "%s · %d/%d",
            shortId ~= "" and shortId or "private server",
            count,
            limit > 0 and limit or count
        )
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
    end

    local function copyJobId(): ()
        local id: string = jobId()
        if id == "" then
            say("This server has no Job ID to copy.")
            return
        end
        -- Executors expose `setclipboard` as a global; a plain Roblox client
        -- does not, so the message still carries the id when copying fails.
        local clipboard: any = setclipboard
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

    local function rejoin(): ()
        local id: string = jobId()
        if id == "" then
            say("This server has no Job ID; rejoining the place instead.")
        end
        local ok: boolean = false
        if id ~= "" then
            ok = pcall(function(): ()
                teleportService:TeleportToPlaceInstance(game.PlaceId, id, LocalPlayer)
            end)
        end
        if not ok then
            ok = pcall(function(): ()
                teleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
        end
        if not ok then
            say("Rejoin failed: TeleportService refused the request.", "danger")
        end
    end

    -- The public server list, as the Roblox web app reads it.
    local function fetchServers(): ({any}?, string?)
        local endpoint: string = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
            game.PlaceId
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
                local servers: {any}?, errorText: string? = fetchServers()
                if not servers then
                    say("Server hop: " .. tostring(errorText), "danger")
                    return
                end
                local here: string = jobId()
                local chosen: any = nil
                local chosenPlayers: number = mode == "largest" and -1 or math.huge
                local candidates: {any} = {}
                for _, entry: any in ipairs(servers) do
                    local instanceId: any = entry and entry.id
                    if type(instanceId) == "string" and instanceId ~= here
                        and (entry.playing == nil or tonumber(entry.playing) ~= nil) then
                        table.insert(candidates, entry)
                    end
                end
                if #candidates == 0 then
                    say("Server hop: no other public server is listed right now.", "danger")
                    return
                end
                if mode == "random" then
                    chosen = candidates[math.random(1, #candidates)]
                else
                    for _, entry: any in ipairs(candidates) do
                        local playing: number = tonumber(entry.playing) or 0
                        local better: boolean = mode == "largest"
                            and playing > chosenPlayers
                            or (mode ~= "largest" and playing < chosenPlayers)
                        if better then
                            chosen = entry
                            chosenPlayers = playing
                        end
                    end
                end
                if not chosen then
                    say("Server hop: no usable server was found.", "danger")
                    return
                end
                lastHopAt = os.clock()
                say(
                    string.format(
                        "Hopping to a server with %d players…",
                        tonumber(chosen.playing) or 0
                    )
                )
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

    local card: any = nil
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
        "Reads the server you are in and hops to another public one; nothing here writes to the server.",
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
                return
            end
            refreshStatus()
            restartTick()
        end,
        {categoryName = "Utilities"}
    )
    activeCard = card

    addActionOption(card, "Copy Job ID", copyJobId)
    addActionOption(card, "Rejoin Server", rejoin)
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
        settings.showInfo = value
        refreshStatus()
    end, "Shows the Job ID and the player count on the card itself.")
    addNumberOption(card, "Refresh every", 3, 1, 15, function(value: number): ()
        settings.refreshSeconds = math.clamp(tonumber(value) or 3, 1, 15)
        elapsed = 0
    end, "Seconds between two server info reads. Only runs while the card is ON.", 1, true)
    addInformationOption(
        card,
        "A Roblox client cannot change another server's settings. This card "
            .. "shows YOUR server and moves you between public ones."
    )

    -- The info readout only ticks while the card is ON, so an idle menu does no
    -- per-frame work. A card restored as ON at boot starts its tick here.
    restartTick()

    activeCard = card
    state.serverSettingsCard = card
    state.serverSettings = settings
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
    activeCard = nil
end

return Module
