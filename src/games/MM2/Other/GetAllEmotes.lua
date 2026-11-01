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

    -- Fallback catalog from the TestingStuff client snapshot; live Sync wins.
    local BUILTIN_EMOTES: {EmoteDef} = {
        { id = "ninja", name = "Ninja Rest", command = "ninja", animationId = "rbxassetid://2431864798", looped = true },
        { id = "sit", name = "Sit", command = "sit2", animationId = "rbxassetid://2431845940", looped = true },
        { id = "zen", name = "Zen", command = "zen", animationId = "rbxassetid://2431812646", looped = true },
        { id = "dab", name = "Dab", command = "dab", animationId = "rbxassetid://2445521505" },
        { id = "floss", name = "Floss", command = "floss", animationId = "rbxassetid://2452938820", looped = true },
        { id = "zombie", name = "Zombie", command = "zombie", animationId = "rbxassetid://2513692312", looped = true },
        { id = "headless", name = "Headless", command = "headless", animationId = "rbxassetid://2513664073" },
        { id = "wave", name = "Wave", command = "wave", animationId = "http://www.roblox.com/asset/?id=128777973" },
        { id = "cheer", name = "Cheer", command = "cheer", animationId = "http://www.roblox.com/asset/?id=129423030" },
        { id = "laugh", name = "Laugh", command = "laugh", animationId = "http://www.roblox.com/asset/?id=129423131" },
        { id = "point", name = "Point", command = "point", animationId = "http://www.roblox.com/asset/?id=128853357" },
        { id = "dance1", name = "Dance 1", command = "dance1", animationId = "http://www.roblox.com/asset/?id=182435998", looped = true },
        { id = "dance2", name = "Dance 2", command = "dance2", animationId = "http://www.roblox.com/asset/?id=182436842", looped = true },
        { id = "dance3", name = "Dance 3", command = "dance3", animationId = "http://www.roblox.com/asset/?id=182436935", looped = true },
    }

    local SPECIAL_EMOTE_LABELS: {string} = {
        "Ninja Rest",
        "Sit",
        "Zen",
        "Dab",
        "Floss",
        "Zombie",
        "Headless",
    }

    local LABEL_TO_EMOTE_ID: {[string]: string} = {
        ["Ninja Rest"] = "ninja",
        ["Sit"] = "sit",
        ["Zen"] = "zen",
        ["Dab"] = "dab",
        ["Floss"] = "floss",
        ["Zombie"] = "zombie",
        ["Headless"] = "headless",
    }

    local selectedEmoteLabel: string = "Floss"
    local activeTrack: any = nil
    local generation: number = 0
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

    local function collectAllEmotes(): ({EmoteDef}, {[string]: EmoteDef})
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
            if emotesModule then
                local okReq: boolean, syncEmotes: any = pcall(require, emotesModule)
                if okReq and type(syncEmotes) == "table" then
                    for emoteId: any, info: any in pairs(syncEmotes) do
                        if type(emoteId) == "string" and emoteId ~= "Back" and type(info) == "table" then
                            local asset = animationUri(info.AnimationID)
                            if type(info.Command) == "string" or asset then
                                local entry = byId[emoteId]
                                if not entry then
                                    entry = { id = emoteId, name = emoteId, command = emoteId, animationId = "" }
                                    byId[emoteId] = entry
                                    table.insert(list, entry)
                                end
                                if type(info.Name) == "string" and info.Name ~= "" then
                                    entry.name = info.Name
                                end
                                if type(info.Command) == "string" and info.Command ~= "" then
                                    entry.command = info.Command
                                end
                                if asset then
                                    entry.animationId = asset
                                end
                                entry.looped = info.Loop == true
                            end
                        end
                    end
                end
            end
        end)

        return list, byId
    end

    -- Update the client's ProfileData and inventory event when available.
    -- Neither a local table nor a BindableEvent proves server-side ownership.
    local function unlockAllEmotes(showNotification: boolean?): number
        local allEmotes: {EmoteDef}, _byId: {[string]: EmoteDef} = collectAllEmotes()
        local localCount: number = 0

        pcall(function(): ()
            local rs: Instance? = game:GetService("ReplicatedStorage")
            if not rs then
                return
            end

            -- 1. Update ReplicatedStorage.Modules.ProfileData.Emotes.Owned
            local modulesFolder: Instance? = rs:FindFirstChild("Modules")
            local profileDataMod: Instance? = modulesFolder and modulesFolder:FindFirstChild("ProfileData")
            local ownedTable: {string}? = nil
            if profileDataMod then
                local okProf: boolean, profileData: any = pcall(require, profileDataMod)
                if okProf and type(profileData) == "table" then
                    if type(profileData.Emotes) ~= "table" then
                        profileData.Emotes = { Owned = {} }
                    elseif type(profileData.Emotes.Owned) ~= "table" then
                        profileData.Emotes.Owned = {}
                    end
                    ownedTable = profileData.Emotes.Owned
                end
            end

            local ownedSet: {[string]: boolean} = {}
            if type(ownedTable) == "table" then
                for _, existingId: any in ipairs(ownedTable) do
                    if type(existingId) == "string" then
                        ownedSet[existingId] = true
                    end
                end
            end

            -- 2. Locate InventoryDataChanged BindableEvent for EmoteWindow & Inventory UI
            local remotesFolder: Instance? = rs:FindFirstChild("Remotes")
            local invRemotes: Instance? = remotesFolder and remotesFolder:FindFirstChild("Inventory")
            local invChanged: Instance? = invRemotes and invRemotes:FindFirstChild("InventoryDataChanged")

            for _, def: EmoteDef in ipairs(allEmotes) do
                local updated: boolean = type(ownedTable) == "table"
                if updated and not ownedSet[def.id] then
                    ownedSet[def.id] = true
                    table.insert(ownedTable :: {string}, def.id)
                end
                if invChanged and type((invChanged :: any).Fire) == "function" then
                    pcall(function(): ()
                        (invChanged :: any):Fire("Emotes", def.id, 1)
                    end)
                end
                if updated then localCount += 1 end
            end

            -- 3. Also support EmoteModule.GenerateEmotes if used by the current UI layout
            local emoteModInst: Instance? = modulesFolder and modulesFolder:FindFirstChild("EmoteModule")
            if emoteModInst and type(ownedTable) == "table" then
                pcall(function(): ()
                    local okEm: boolean, emoteModule: any = pcall(require, emoteModInst)
                    if okEm and type(emoteModule) == "table" and type(emoteModule.GenerateEmotes) == "function" then
                        local emoteGui: any = (_G and (_G :: any).EmoteFrame) or emoteModule.EmoteGUI
                        if emoteGui then
                            pcall(emoteModule.GenerateEmotes, ownedTable, emoteGui)
                        end
                    end
                end)
            end
        end)

        if GetAllEmotesFeature and GetAllEmotesFeature.enabled then
            GetAllEmotesFeature:SetStatus(string.format("%d local emotes", localCount))
        end
        if showNotification and type(notify) == "function" then
            pcall(notify, string.format("Get All Emotes: %d local emote entries; server ownership is not verified.", localCount))
        end
        return localCount
    end

    -- Request the game's native emote, or use the character Animator as a
    -- fallback. The game's permissions determine playback and replication.
    local function requestEmotePlayback(emoteId: string): boolean
        stopActiveTrack()
        local _list: {EmoteDef}, byId: {[string]: EmoteDef} = collectAllEmotes()
        local def: EmoteDef? = byId[emoteId]
        local firedBindable: boolean = false

        pcall(function(): ()
            local rs: Instance? = game:GetService("ReplicatedStorage")
            local remotes: Instance? = rs and rs:FindFirstChild("Remotes")
            local misc: Instance? = remotes and remotes:FindFirstChild("Misc")
            local playEmoteEvent: Instance? = misc and misc:FindFirstChild("PlayEmote")
            if playEmoteEvent and type((playEmoteEvent :: any).Fire) == "function" then
                (playEmoteEvent :: any):Fire(emoteId)
                firedBindable = true
            end
        end)

        if firedBindable then
            return true
        end

        -- Direct Humanoid/Animator fallback; replication is game-dependent.
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

    local function toggleGetAllEmotes(enabled: boolean): ()
        generation += 1
        local currentGeneration: number = generation
        disconnectFeatureConnection("MM2GetAllEmotesRespawn")

        if not enabled then
            stopActiveTrack()
            if GetAllEmotesFeature then
                GetAllEmotesFeature:SetStatus(nil)
            end
            return
        end

        local count: number = unlockAllEmotes(true)
        GetAllEmotesFeature:SetStatus(string.format("%d local emotes", count))

        if LocalPlayer and LocalPlayer.CharacterAdded then
            featureConnections.MM2GetAllEmotesRespawn = LocalPlayer.CharacterAdded:Connect(function(): ()
                task.delay(0.5, function(): ()
                    if currentGeneration == generation and GetAllEmotesFeature and GetAllEmotesFeature.enabled then
                        unlockAllEmotes(false)
                    end
                end)
            end)
        end
    end

    GetAllEmotesFeature = createUniversalFeature(
        "Get All Emotes",
        "Attempts to populate the local MM2 emote list and play selected animations. Server ownership and replication depend on the game.",
        11,
        toggleGetAllEmotes,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2GetAllEmotesFeature = GetAllEmotesFeature

    addActionOption(
        GetAllEmotesFeature,
        "Get All Emotes",
        function(): ()
            unlockAllEmotes(true)
        end,
        "Update the local emote list; this does not prove server-side ownership."
    )

    addCycleOption(
        GetAllEmotesFeature,
        "Select Emote",
        SPECIAL_EMOTE_LABELS,
        5,
        function(value: string): ()
            selectedEmoteLabel = value
        end,
        "Select an MM2 emote to request through the game or the character Animator."
    )

    addActionOption(
        GetAllEmotesFeature,
        "Play Emote",
        function(): ()
            local emoteId: string = LABEL_TO_EMOTE_ID[selectedEmoteLabel] or "floss"
            unlockAllEmotes(false)
            requestEmotePlayback(emoteId)
        end,
        "Request the selected emote. Playback and visibility to others are not guaranteed."
    )

    activeCleanup = function(): ()
        toggleGetAllEmotes(false)
        if state.mm2GetAllEmotesFeature == GetAllEmotesFeature then state.mm2GetAllEmotesFeature = nil end
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
