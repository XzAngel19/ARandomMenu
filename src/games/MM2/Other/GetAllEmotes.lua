local Module = {
    Name = "MM2 Get All Emotes",
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
    assert(type(core) == "table", "MM2 Get All Emotes requires the MM2 core module")
    Module.Runtime = runtime

    type EmoteDef = {
        id: string,
        label: string,
        command: string,
        animationId: string,
        looped: boolean?,
    }

    -- The five shop animations plus the two event animations the player asked
    -- to keep. These are a fallback from the captured MM2 Database.Sync.Emotes;
    -- the live catalog can contribute other playable non-default emotes too.
    local EMOTES: {EmoteDef} = {
        { id = "sit", label = "Sit", command = "sit2", animationId = "rbxassetid://2431845940", looped = true },
        { id = "ninja", label = "Ninja Rest", command = "ninja", animationId = "rbxassetid://2431864798", looped = true },
        { id = "zen", label = "Zen", command = "zen", animationId = "rbxassetid://2431812646", looped = true },
        { id = "dab", label = "Dab", command = "dab", animationId = "rbxassetid://2445521505" },
        { id = "floss", label = "Floss", command = "floss", animationId = "rbxassetid://2452938820", looped = true },
        { id = "zombie", label = "Zombie", command = "zombie", animationId = "rbxassetid://2513692312", looped = true },
        { id = "headless", label = "Headless", command = "headless", animationId = "rbxassetid://2513664073" },
    }
    local LABELS: {string} = {}
    local ID_BY_LABEL: {[string]: string} = {}
    local KNOWN_IDS: {[string]: boolean} = {}
    local DEFAULT_IDS: {[string]: boolean} = {
        back = true, wave = true, cheer = true, laugh = true, point = true,
        dance = true, dance1 = true, dance2 = true, dance3 = true,
    }
    for _, def: EmoteDef in ipairs(EMOTES) do
        table.insert(LABELS, def.label)
        ID_BY_LABEL[def.label] = def.id
        KNOWN_IDS[def.id] = true
    end

    local selectedLabel: string = "Floss"
    local selectionTouched: boolean = false
    local activeTrack: any = nil
    local feature: any = nil
    local generation: number = 0
    local grantInFlight: boolean = false
    local catalogInFlight: boolean = false
    local activated: boolean = false

    local function stopActiveTrack(): ()
        if activeTrack then
            pcall(function(): () activeTrack:Stop(0.1) end)
            activeTrack = nil
        end
    end

    local function animationUri(value: any): string?
        if type(value) == "number" and value > 0 and value < math.huge then
            return "rbxassetid://" .. string.format("%.0f", value)
        end
        if type(value) == "string" and value ~= "" then
            return string.match(value, "^%d+$") and ("rbxassetid://" .. value) or value
        end
        return nil
    end

    -- New MM2 animations should not be silently excluded just because the
    -- captured catalog is older. Admit only playable catalog entries, never
    -- the known Roblox defaults or the non-emote Back row. This runs in the
    -- asynchronous grant path, since require may wait for game data.
    local function discoverLiveEmotes(ticket: number): ()
        local rs: Instance = game:GetService("ReplicatedStorage")
        local db: Instance? = rs:FindFirstChild("Database")
        local sync: Instance? = db and db:FindFirstChild("Sync")
        local emotesModule: Instance? = sync and sync:FindFirstChild("Emotes")
        if not emotesModule then return end
        local ok: boolean, catalog: any = pcall(require, emotesModule)
        if ticket ~= generation or not Module.Initialized
            or not ok or type(catalog) ~= "table" then
            return
        end
        local extra: {string} = {}
        for id: any, live: any in pairs(catalog) do
            if type(id) == "string" and not KNOWN_IDS[id]
                and not DEFAULT_IDS[string.lower(id)] and type(live) == "table"
                and type(live.Command) == "string" and live.Command ~= ""
                and not DEFAULT_IDS[string.lower(live.Command)]
                and animationUri(live.AnimationID) then
                table.insert(extra, id)
            end
        end
        table.sort(extra)
        for _, id: string in ipairs(extra) do
            local live: any = catalog[id]
            local label: string = type(live.Name) == "string" and live.Name ~= "" and live.Name or id
            if ID_BY_LABEL[label] then label ..= " (" .. id .. ")" end
            local def: EmoteDef = {
                id = id,
                label = label,
                command = live.Command,
                animationId = animationUri(live.AnimationID) :: string,
                looped = live.Loop == true,
            }
            table.insert(EMOTES, def)
            table.insert(LABELS, label)
            ID_BY_LABEL[label] = id
            KNOWN_IDS[id] = true
        end
        -- A saved selection for a newly discovered emote was not available
        -- when the cycle was built. Restore it silently unless the user has
        -- already chosen another value during this session.
        local values: any = type(configData) == "table" and configData.values or nil
        local saved: any = type(values) == "table" and values["MM2.GetAllEmotes.SelectEmote"] or nil
        local index: number? = type(saved) == "string" and table.find(LABELS, saved) or nil
        if not selectionTouched and index and ID_BY_LABEL[saved] then
            selectedLabel = saved
            local control: any = state.valueControls and state.valueControls["MM2.GetAllEmotes.SelectEmote"]
            if control and type(control.setIndex) == "function" then
                control.setIndex(index)
            end
        end
    end

    local function emoteDefinition(id: string): EmoteDef?
        local result: EmoteDef? = nil
        for _, def: EmoteDef in ipairs(EMOTES) do
            if def.id == id then
                result = table.clone(def)
                break
            end
        end
        if not result then
            return nil
        end
        pcall(function(): ()
            local rs: Instance = game:GetService("ReplicatedStorage")
            local db: Instance? = rs:FindFirstChild("Database")
            local sync: Instance? = db and db:FindFirstChild("Sync")
            local emotesModule: Instance? = sync and sync:FindFirstChild("Emotes")
            if not emotesModule then return end
            local ok: boolean, catalog: any = pcall(require, emotesModule)
            local live: any = ok and type(catalog) == "table" and catalog[id] or nil
            if type(live) ~= "table" then return end
            local def: EmoteDef = result :: EmoteDef
            if type(live.Command) == "string" and live.Command ~= "" then
                def.command = live.Command
            end
            local asset: string? = animationUri(live.AnimationID)
            if asset then def.animationId = asset end
            def.looped = live.Loop == true
        end)
        return result
    end

    -- The old menu has a separate GenerateEmotes method. The current
    -- CrossPlatform GUI does not: it listens to InventoryDataChanged instead.
    -- Never require the old EmoteModule without its controller/GUI: that module
    -- waits indefinitely for _G.EmoteController in the newer interface.
    local function refreshLegacyGui(rs: Instance, owned: {string}): boolean
        local globals: any = _G :: any
        local gui: any = globals and globals.EmoteFrame
        if not gui or type(globals.EmoteController) ~= "table" then return false end
        local valid: boolean, pages: any = pcall(function(): any
            return gui:FindFirstChild("EmotePages")
        end)
        if not valid or not pages then return false end
        local modules: Instance? = rs:FindFirstChild("Modules")
        local scriptModule: Instance? = modules and modules:FindFirstChild("EmoteModule")
        if not scriptModule then return false end
        local ok: boolean, emoteModule: any = pcall(require, scriptModule)
        if not ok or type(emoteModule) ~= "table"
            or type(emoteModule.GenerateEmotes) ~= "function" then
            return false
        end
        emoteModule.EmoteGUI = gui
        return pcall(emoteModule.GenerateEmotes, owned, gui)
    end

    -- Modifying ProfileData is client-side only. The native BindableEvent must
    -- be fired on the instance itself: .Event is an RBXScriptSignal and has no
    -- Fire method. Both old and CrossPlatform controllers listen to .Event.
    local function grantShopEmotes(ticket: number): (boolean, number, boolean)
        if ticket ~= generation or not Module.Initialized then return false, 0, false end
        local ok: boolean, ready: any, added: any, refreshed: any = pcall(function(): (boolean, number, boolean)
            local rs: Instance = game:GetService("ReplicatedStorage")
            local modules: Instance? = rs:FindFirstChild("Modules")
            local profileModule: Instance? = modules and modules:FindFirstChild("ProfileData")
            if not profileModule then return false, 0, false end
            local profileOk: boolean, profile: any = pcall(require, profileModule)
            if ticket ~= generation or not Module.Initialized then return false, 0, false end
            if not profileOk or type(profile) ~= "table"
                or type(profile.Emotes) ~= "table"
                or type(profile.Emotes.Owned) ~= "table" then
                return false, 0, false
            end
            local owned: {string} = profile.Emotes.Owned
            local known: {[string]: boolean} = {}
            for _, existing: any in ipairs(owned) do
                if type(existing) == "string" then known[existing] = true end
            end
            local newIds: {string} = {}
            for _, def: EmoteDef in ipairs(EMOTES) do
                if not known[def.id] then
                    table.insert(owned, def.id)
                    known[def.id] = true
                    table.insert(newIds, def.id)
                end
            end

            local remotes: Instance? = rs:FindFirstChild("Remotes")
            local inventory: Instance? = remotes and remotes:FindFirstChild("Inventory")
            local changed: any = inventory and inventory:FindFirstChild("InventoryDataChanged")
            local signalled: boolean = false
            if changed then
                -- Incremental inventory listeners need each new ID. An
                -- idempotent repeat still wakes the emote window once.
                local wakeIds: {string} = #newIds > 0 and newIds or { EMOTES[1].id }
                for _, id: string in ipairs(wakeIds) do
                    local fired: boolean = pcall(function(): ()
                        changed:Fire("Emotes", id, 1)
                    end)
                    signalled = signalled or fired
                end
            end
            if not signalled then
                signalled = refreshLegacyGui(rs, owned)
            end
            return true, #newIds, signalled
        end)
        if not ok then return false, 0, false end
        return ready == true, tonumber(added) or 0, refreshed == true
    end

    local function requestGrant(showNotification: boolean): ()
        if grantInFlight then
            if showNotification and type(notify) == "function" then
                pcall(notify, "Get All Emotes: waiting for the MM2 profile.")
            end
            return
        end
        grantInFlight = true
        local ticket: number = generation
        -- ProfileData's require can yield while the game loads; keep the menu
        -- responsive and ignore the result if this instance was destroyed.
        task.spawn(function(): ()
            local ready: boolean, added: number, refreshed: boolean = grantShopEmotes(ticket)
            if ticket ~= generation or not Module.Initialized then return end
            grantInFlight = false
            if not ready then
                if feature then feature:SetStatus("profile not ready") end
                if showNotification and type(notify) == "function" then
                    pcall(notify, "Get All Emotes: MM2 profile unavailable or not ready; try again after the game loads.")
                end
                return
            end
            local count: number = #EMOTES
            if feature then
                feature:SetStatus(refreshed and (tostring(count) .. " local emotes")
                    or (tostring(count) .. " local · UI not refreshed"))
            end
            if showNotification and type(notify) == "function" then
                local suffix: string = refreshed
                    and "The emote UI was notified."
                    or "The MM2 emote UI could not be notified; try again after it loads."
                pcall(notify, string.format(
                    "Get All Emotes: %d local entries (%d new). %s Server ownership is not verified.",
                    count, added, suffix
                ))
            end
            -- Do not let a slow/hung catalog require block the seven known
            -- entries. If it finds extras later, add and signal them in a
            -- second pass; at most one discovery may be waiting at a time.
            if not catalogInFlight then
                catalogInFlight = true
                task.spawn(function(): ()
                    if ticket ~= generation or not Module.Initialized then
                        catalogInFlight = false
                        return
                    end
                    local previous: number = #EMOTES
                    pcall(discoverLiveEmotes, ticket)
                    catalogInFlight = false
                    if ticket == generation and Module.Initialized and #EMOTES > previous then
                        requestGrant(false)
                    end
                end)
            end
        end)
    end

    local function activate(): ()
        activated = true
        if featureConnections.MM2GetAllEmotesRespawn or not (LocalPlayer and LocalPlayer.CharacterAdded) then
            return
        end
        featureConnections.MM2GetAllEmotesRespawn = LocalPlayer.CharacterAdded:Connect(function(): ()
            local ticket: number = generation
            task.delay(0.5, function(): ()
                if ticket == generation and Module.Initialized and activated then
                    requestGrant(false)
                end
            end)
        end)
    end

    -- A successful :Fire is just a request, not confirmation of playback or
    -- replication. Fall back to the local Animator only when no native event
    -- could be fired; doing both would play two tracks at once.
    local function requestEmotePlayback(id: string): boolean
        stopActiveTrack()
        local def: EmoteDef? = emoteDefinition(id)
        if not def then return false end
        local fired: boolean = false
        pcall(function(): ()
            local rs: Instance = game:GetService("ReplicatedStorage")
            local remotes: Instance? = rs:FindFirstChild("Remotes")
            local misc: Instance? = remotes and remotes:FindFirstChild("Misc")
            local event: any = misc and misc:FindFirstChild("PlayEmote")
            if event then
                fired = pcall(function(): () event:Fire(id) end)
            end
        end)
        if fired then return true end
        if def.animationId == "" then return false end

        local played: boolean = false
        pcall(function(): ()
            local character: Model? = LocalPlayer and LocalPlayer.Character
            local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then return end
            local anim: Animation = Instance.new("Animation")
            anim.Name = def.command
            anim.AnimationId = def.animationId
            local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
            local loaded: boolean, track: any = pcall(function(): any
                return if animator then animator:LoadAnimation(anim)
                    else (humanoid :: any):LoadAnimation(anim)
            end)
            if loaded and track then
                activeTrack = track
                played = pcall(function(): ()
                    track.Looped = def.looped == true
                    track:Play(0.1)
                end)
            end
            anim:Destroy()
        end)
        return played
    end

    local function playSelected(): ()
        activate()
        requestGrant(false)
        local id: string = ID_BY_LABEL[selectedLabel] or "floss"
        if not requestEmotePlayback(id) and type(notify) == "function" then
            pcall(notify, "Could not request that emote; check the character and animation permissions.")
        end
    end

    feature = createUniversalFeature(
        "Get All Emotes",
        "Adds MM2's playable non-default emotes locally, including Sit, Ninja Rest, Zen, Dab, Floss, Zombie and Headless. "
            .. "It does not grant server ownership; playback and replication depend on the game.",
        11,
        function(): ()
            activate()
            requestGrant(true)
        end,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
            action = true,
            noOptions = false,
            configKey = "MM2.GetAllEmotes",
        }
    )
    state.mm2GetAllEmotesFeature = feature

    -- Restoring the saved selection at boot must not play/grant anything.
    local cycleRestored: boolean = false
    addCycleOption(feature, "Select Emote", LABELS, 5, function(value: string): ()
        selectedLabel = value
        if not cycleRestored then
            cycleRestored = true
            return
        end
        selectionTouched = true
        playSelected()
    end, "Select and request an MM2 emote; server ownership is not changed.")
    addActionOption(feature, "Play Emote", playSelected, "Request the selected emote again.")
    addInformationOption(feature,
        "MM2's playable emotes are added locally. Existing inventory is preserved; avatar defaults "
            .. "are not added, and the server controls ownership and replication.")

    activeCleanup = function(): ()
        generation += 1
        activated = false
        disconnectFeatureConnection("MM2GetAllEmotesRespawn")
        stopActiveTrack()
        if state.mm2GetAllEmotesFeature == feature then
            state.mm2GetAllEmotesFeature = nil
        end
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then return end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
