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
        name: string,
        command: string,
        animationId: string,
        looped: boolean?,
    }

    -- Only the five emotes that MM2 actually sells. The default avatar emotes
    -- (wave, cheer, laugh, point, dance1-3) are not shop entries: writing them
    -- into ProfileData.Emotes.Owned only polluted the profile and the emote
    -- window, so they are never granted. Confirmed against the TestingStuff
    -- place capture: Database.Sync.Emotes marks exactly these ids with a
    -- numeric Price (ninja 650, zen 800, dab 700, floss 750, zombie NotForSale
    -- but still a shop item), while the avatar set carries Price "NotForSale"
    -- and no AnimationID.
    local SHOP_EMOTE_IDS: {string} = { "ninja", "zen", "dab", "floss", "zombie" }

    -- Fallback catalog from the TestingStuff client snapshot; the live Sync
    -- module wins when it is available.
    local BUILTIN_EMOTES: {EmoteDef} = {
        { id = "ninja", name = "Ninja Rest", command = "ninja", animationId = "rbxassetid://2431864798", looped = true },
        { id = "zen", name = "Zen", command = "zen", animationId = "rbxassetid://2431812646", looped = true },
        { id = "dab", name = "Dab", command = "dab", animationId = "rbxassetid://2445521505" },
        { id = "floss", name = "Floss", command = "floss", animationId = "rbxassetid://2452938820", looped = true },
        { id = "zombie", name = "Zombie", command = "zombie", animationId = "rbxassetid://2513692312", looped = true },
    }

    -- The cycle lists the same five emotes, in the order a player expects.
    local EMOTE_LABELS: {string} = { "Ninja Rest", "Zen", "Dab", "Floss", "Zombie" }

    local LABEL_TO_EMOTE_ID: {[string]: string} = {
        ["Ninja Rest"] = "ninja",
        ["Zen"] = "zen",
        ["Dab"] = "dab",
        ["Floss"] = "floss",
        ["Zombie"] = "zombie",
    }

    local selectedEmoteLabel: string = "Floss"
    local activeTrack: any = nil
    local GetAllEmotesFeature: any = nil

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

    -- The live Sync table, restricted to the shop ids. Anything the game adds
    -- that is not in SHOP_EMOTE_IDS is ignored on purpose.
    local function collectEmotes(): ({EmoteDef}, {[string]: EmoteDef})
        local list: {EmoteDef} = {}
        local byId: {[string]: EmoteDef} = {}

        for _, def: EmoteDef in ipairs(BUILTIN_EMOTES) do
            local copy: EmoteDef = table.clone(def)
            byId[copy.id] = copy
            table.insert(list, copy)
        end

        pcall(function(): ()
            local rs: Instance? = game:GetService("ReplicatedStorage")
            local db: Instance? = rs and rs:FindFirstChild("Database")
            local syncFolder: Instance? = db and db:FindFirstChild("Sync")
            local emotesModule: Instance? = syncFolder and syncFolder:FindFirstChild("Emotes")
            if not emotesModule then
                return
            end
            local okReq: boolean, syncEmotes: any = pcall(require, emotesModule)
            if not okReq or type(syncEmotes) ~= "table" then
                return
            end
            for _, emoteId: string in ipairs(SHOP_EMOTE_IDS) do
                local info: any = syncEmotes[emoteId]
                if type(info) == "table" then
                    local entry: EmoteDef = byId[emoteId]
                        or {
                            id = emoteId,
                            name = emoteId,
                            command = emoteId,
                            animationId = "",
                        }
                    if not byId[emoteId] then
                        byId[emoteId] = entry
                        table.insert(list, entry)
                    end
                    if type(info.Name) == "string" and info.Name ~= "" then
                        entry.name = info.Name
                    end
                    if type(info.Command) == "string" and info.Command ~= "" then
                        entry.command = info.Command
                    end
                    local asset: string? = animationUri(info.AnimationID)
                    if asset then
                        entry.animationId = asset
                    end
                    entry.looped = info.Loop == true
                end
            end
        end)

        return list, byId
    end

    -- Rebuild the game's own emote window from ProfileData, exactly like the
    -- client does after InventoryDataChanged. This is what makes the emotes
    -- usable without reopening the game UI.
    local function refreshEmoteWindow(owned: {string}): ()
        pcall(function(): ()
            local rs: Instance? = game:GetService("ReplicatedStorage")
            local modulesFolder: Instance? = rs and rs:FindFirstChild("Modules")
            local emoteInst: Instance? = modulesFolder and modulesFolder:FindFirstChild("EmoteModule")
            if not emoteInst then
                return
            end
            local okEm: boolean, emoteModule: any = pcall(require, emoteInst)
            if not okEm or type(emoteModule) ~= "table" then
                return
            end
            local gui: any = emoteModule.EmoteGUI
                or (type(getgenv) == "function" and (getgenv() :: any).EmoteFrame)
                or nil
            if gui and type(emoteModule.GenerateEmotes) == "function" then
                pcall(emoteModule.GenerateEmotes, owned, gui)
            end
        end)
    end

    -- Write the five shop ids into the client's ProfileData and wake the
    -- inventory UI. Neither a local table nor a BindableEvent proves
    -- server-side ownership: the server still decides what actually plays.
    local function grantShopEmotes(showNotification: boolean?): number
        local list: {EmoteDef} = collectEmotes()
        local granted: number = 0
        local ownedList: {string}? = nil

        pcall(function(): ()
            local rs: Instance? = game:GetService("ReplicatedStorage")
            if not rs then
                return
            end

            -- 1. ReplicatedStorage.Modules.ProfileData.Emotes.Owned
            local owned: {string}? = nil
            local modulesFolder: Instance? = rs:FindFirstChild("Modules")
            local profileDataMod: Instance? = modulesFolder
                and modulesFolder:FindFirstChild("ProfileData")
            if profileDataMod then
                local okProf: boolean, profileData: any = pcall(require, profileDataMod)
                if okProf and type(profileData) == "table" then
                    if type(profileData.Emotes) ~= "table" then
                        profileData.Emotes = { Owned = {} }
                    elseif type(profileData.Emotes.Owned) ~= "table" then
                        profileData.Emotes.Owned = {}
                    end
                    owned = profileData.Emotes.Owned
                end
            end

            local known: {[string]: boolean} = {}
            if owned then
                for _, existingId: any in ipairs(owned) do
                    if type(existingId) == "string" then
                        known[existingId] = true
                    end
                end
                for _, def: EmoteDef in ipairs(list) do
                    if not known[def.id] then
                        known[def.id] = true
                        table.insert(owned, def.id)
                        granted += 1
                    end
                end
                ownedList = owned
            end

            -- 2. InventoryDataChanged. In MM2 this is a RemoteEvent whose
            -- client-side channel is the inner BindableEvent (`.Event`); the
            -- old code fired the RemoteEvent itself, which does not exist
            -- client-side, so the emote window never rebuilt.
            local remotesFolder: Instance? = rs:FindFirstChild("Remotes")
            local invRemotes: Instance? = remotesFolder and remotesFolder:FindFirstChild("Inventory")
            local invChanged: any = invRemotes and invRemotes:FindFirstChild("InventoryDataChanged")
            if invChanged and owned then
                for _, def: EmoteDef in ipairs(list) do
                    if known[def.id] then
                        pcall(function(): ()
                            if invChanged.Event and type(invChanged.Event.Fire) == "function" then
                                invChanged.Event:Fire("Emotes", def.id, 1)
                            elseif type(invChanged.Fire) == "function" then
                                invChanged:Fire("Emotes", def.id, 1)
                            end
                        end)
                    end
                end
            end
        end)

        if ownedList then
            refreshEmoteWindow(ownedList)
        end

        if GetAllEmotesFeature then
            GetAllEmotesFeature:SetStatus(string.format("%d shop emotes", #list))
        end
        if showNotification and type(notify) == "function" then
            pcall(
                notify,
                string.format(
                    "Get All Emotes: %d shop emotes written to the local profile "
                        .. "(%d new). The server still decides what plays.",
                    #list,
                    granted
                )
            )
        end
        return granted
    end

    -- The game's own PlayEmote BindableEvent (Remotes.Misc.PlayEmote) takes the
    -- emote id; the Animator is only the fallback when the game refuses.
    local function requestEmotePlayback(emoteId: string): boolean
        stopActiveTrack()
        local _list: {EmoteDef}, byId: {[string]: EmoteDef} = collectEmotes()
        local def: EmoteDef? = byId[emoteId]
        local firedGameEvent: boolean = false

        pcall(function(): ()
            local rs: Instance? = game:GetService("ReplicatedStorage")
            local remotes: Instance? = rs and rs:FindFirstChild("Remotes")
            local misc: Instance? = remotes and remotes:FindFirstChild("Misc")
            local playEmoteEvent: any = misc and misc:FindFirstChild("PlayEmote")
            if playEmoteEvent and type(playEmoteEvent.Fire) == "function" then
                playEmoteEvent:Fire(emoteId)
                firedGameEvent = true
            end
        end)

        if firedGameEvent then
            return true
        end

        if not def or def.animationId == "" then
            return false
        end
        local playedFallback: boolean = false
        pcall(function(): ()
            local character: Model? = LocalPlayer and LocalPlayer.Character
            local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then
                return
            end
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
                playedFallback = pcall(function(): ()
                    track.Looped = def.looped == true
                    track:Play(0.1)
                end)
            end
            anim:Destroy()
        end)

        return playedFallback
    end

    -- One click: grant the five shop emotes and rebuild the game's window.
    local function runGetAllEmotes(): ()
        local granted: number = grantShopEmotes(true)
        if GetAllEmotesFeature then
            GetAllEmotesFeature:SetStatus(
                string.format("%d shop emotes", #collectEmotes())
            )
        end
        if granted == 0 and type(notify) == "function" then
            pcall(notify, "Get All Emotes: the shop emotes were already in the local profile.")
        end
    end

    -- Re-apply after a respawn/reset: the game can rebuild the profile and the
    -- emote window, and the grant is local-only, so a fresh character gets it
    -- again without the player pressing the button.
    local function hookRespawn(): ()
        if featureConnections.MM2GetAllEmotesRespawn then
            return
        end
        if not (LocalPlayer and LocalPlayer.CharacterAdded) then
            return
        end
        featureConnections.MM2GetAllEmotesRespawn = LocalPlayer.CharacterAdded:Connect(
            function(): ()
                task.delay(0.5, function(): ()
                    if Module.Initialized then
                        pcall(grantShopEmotes, false)
                    end
                end)
            end
        )
    end

    GetAllEmotesFeature = createUniversalFeature(
        "Get All Emotes",
        "Button: writes the five MM2 shop emotes (Ninja Rest, Zen, Dab, Floss, "
            .. "Zombie) into the local emote profile and rebuilds the emote "
            .. "window. Server ownership is not guaranteed.",
        11,
        function(): ()
            runGetAllEmotes()
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
    state.mm2GetAllEmotesFeature = GetAllEmotesFeature

    -- The cycle widget calls the callback once at creation with the saved
    -- value. That is a restore, not a choice: playing an emote there fired a
    -- toast on every single boot.
    local cycleRestored: boolean = false
    addCycleOption(
        GetAllEmotesFeature,
        "Select Emote",
        EMOTE_LABELS,
        4,
        function(value: string): ()
            selectedEmoteLabel = value
            if not cycleRestored then
                cycleRestored = true
                return
            end
            local emoteId: string = LABEL_TO_EMOTE_ID[value] or "floss"
            -- v180: choosing an emote plays it right away. Before this the cycle
            -- only stored a label and the player had to press Play afterwards,
            -- which read as "Select Emote does nothing".
            grantShopEmotes(false)
            if not requestEmotePlayback(emoteId) and type(notify) == "function" then
                pcall(notify, "MM2 refused that emote; it may not be owned server-side.")
            end
        end,
        "Pick an emote and play it immediately through the game."
    )

    addActionOption(
        GetAllEmotesFeature,
        "Play Emote",
        function(): ()
            local emoteId: string = LABEL_TO_EMOTE_ID[selectedEmoteLabel] or "floss"
            grantShopEmotes(false)
            if not requestEmotePlayback(emoteId) and type(notify) == "function" then
                pcall(notify, "MM2 refused that emote; it may not be owned server-side.")
            end
        end,
        "Replay the emote chosen in Select Emote."
    )

    addInformationOption(
        GetAllEmotesFeature,
        "Button, not a toggle: one click grants the shop emotes. The button "
            .. "stays idle until you press it again."
    )

    hookRespawn()

    activeCleanup = function(): ()
        disconnectFeatureConnection("MM2GetAllEmotesRespawn")
        stopActiveTrack()
        if state.mm2GetAllEmotesFeature == GetAllEmotesFeature then
            state.mm2GetAllEmotesFeature = nil
        end
    end
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
