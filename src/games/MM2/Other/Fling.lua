-- v190: the MM2 Fling card comes back as its own card.
--
-- History: v183 removed the universal `Fling` card at the player's request
-- ("borren el Fling universal"), and the removal also took the MM2 card with
-- it -- the engine stayed (`FlingEngine.lua`) but only Auto Farm and Auto Win
-- could reach it. This module is that card again, MM2 only: pick a player from
-- the list and the SkidFling engine throws them.
--
-- The card never flings on its own: no saved selection starts a fling at
-- injection, and the list is the only trigger. Power and Retries travel with
-- each call, so Auto Farm/Auto Win keep the documented engine defaults.
--
-- Anti Fling cancels the fling's own contact (its whole job is to prevent
-- contact with a flinging body), so both this card and Walk Fling warn and
-- refuse while it is on -- MM2 only, as the player asked.
local Module = {
    Name = "MM2 Fling",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Fling requires the MM2 core module")
    Module.Runtime = runtime

    local localPlayer: any = LocalPlayer
    local playerService: any = Players

    local settings = {
        power = 6,
        retries = 2,
    }
    local FlingFeature: any = nil
    -- The list publishes its stored selection once, while it is being built.
    -- Acting on that first call would fling a player at injection.
    local listReady: boolean = false

    local function antiFlingOn(): boolean
        return state.antiFlingActive == true
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

    local function canFling(player: any): boolean
        if not player or player == localPlayer then
            return false
        end
        local character: any = livingCharacter(player)
        return character ~= nil
    end

    local function playerNames(): {string}
        local names: {string} = {}
        for _, player: any in ipairs(roster()) do
            if canFling(player) then
                table.insert(names, tostring(player.Name))
            end
        end
        table.sort(names)
        return names
    end

    local function findPlayer(name: string?): any?
        if not name or name == "" then
            return nil
        end
        for _, player: any in ipairs(roster()) do
            if tostring(player.Name) == name then
                return player
            end
        end
        return nil
    end

    local function setStatus(text: string?): ()
        if FlingFeature and type(FlingFeature.SetStatus) == "function" then
            pcall(function(): ()
                FlingFeature:SetStatus(text)
            end)
        end
    end

    local function flingPlayer(name: string?): boolean
        if not name or name == "" then
            setStatus("Pick a target")
            return false
        end
        if antiFlingOn() then
            -- The player asked for this notice: with Anti Fling on the shield
            -- blocks the contact the fling needs, so the fling would just look
            -- broken and blame the engine.
            if type(notify) == "function" then
                notify("Anti Fling is ON: turn it off before flinging someone.")
            end
            setStatus("Anti Fling is ON")
            return false
        end
        local target: any = findPlayer(name)
        if not target then
            setStatus("Player left")
            return false
        end
        local perform: any = state.mm2PerformFling
        if type(perform) ~= "function" then
            setStatus("Fling engine unavailable")
            return false
        end
        setStatus("Flinging " .. tostring(name))
        local started: boolean = false
        pcall(function(): ()
            started = perform(target, {
                power = settings.power,
                retries = settings.retries,
            })
        end)
        if not started then
            setStatus("Fling busy or refused")
        end
        return started
    end

    FlingFeature = createUniversalFeature(
        "Fling",
        "Flings the player you pick with the MM2 SkidFling engine. Turn Anti Fling off first.",
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

    local listHandle: any = nil
    if type(addListOption) == "function" then
        listHandle = addListOption(FlingFeature, "Target player", {
            items = playerNames,
            single = true,
            default = {},
            emptyText = "No other players",
            hint = "Pick a player to fling right now. Anti Fling must be OFF: it cancels the contact the fling needs.",
            onChanged = function(_selected: any, names: {string}): ()
                if not listReady then
                    return
                end
                local chosen: string? = names and names[1]
                if not chosen or chosen == "" then
                    return
                end
                -- Clear the row so the same player can be picked again; the
                -- empty publish that follows is ignored above.
                local key: string = tostring(FlingFeature.configKey or "MM2.Fling")
                    .. ".Targetplayer"
                local controls: any = state.listControls and state.listControls[key]
                if controls then
                    listReady = false
                    pcall(function(): ()
                        controls.set(chosen, false)
                    end)
                    listReady = true
                end
                flingPlayer(chosen)
            end,
        })
        listReady = true
    end

    if type(addNumberOption) == "function" then
        addNumberOption(FlingFeature, "Power", settings.power, 1, 10,
            function(value: number): ()
                settings.power = math.clamp(tonumber(value) or 6, 1, 10)
            end,
            "YARHM's exact numbers are Power 3. Higher values scale both the pose velocity and the pin, which is what lands a fling on a laggy or fast-moving target.",
            1)
        addNumberOption(FlingFeature, "Retries", settings.retries, 0, 3,
            function(value: number): ()
                settings.retries = math.clamp(math.floor(tonumber(value) or 0), 0, 3)
            end,
            "Extra half-length passes that swap the contact part, for a server that misses the first contact.",
            2)
    end
    if type(addInformationOption) == "function" then
        addInformationOption(
            FlingFeature,
            "MM2 only. While Anti Fling is ON the fling is refused with a notice: "
                .. "its collision shield stops the contact the fling needs."
        )
    end

    state.mm2FlingFeature = FlingFeature
    state.mm2FlingSettings = settings
    activeCleanup = function(): ()
        state.mm2FlingFeature = nil
        state.mm2FlingSettings = nil
    end
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
