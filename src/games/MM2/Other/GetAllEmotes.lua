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
    }

    -- Complete MM2 Sync.Emotes catalog from place, source.rbxlx (TestingStuff)
    local BUILTIN_EMOTES: {EmoteDef} = {
        { id = "ninja", name = "Ninja Rest", command = "ninja", animationId = "rbxassetid://204292303" },
        { id = "sit", name = "Sit", command = "sit2", animationId = "rbxassetid://204292303" },
        { id = "zen", name = "Zen", command = "zen", animationId = "rbxassetid://204295235" },
        { id = "dab", name = "Dab", command = "dab", animationId = "rbxassetid://248263260" },
        { id = "floss", name = "Floss", command = "floss", animationId = "rbxassetid://5917459365" },
        { id = "zombie", name = "Zombie", command = "zombie", animationId = "rbxassetid://616158929" },
        { id = "headless", name = "Headless", command = "headless", animationId = "rbxassetid://35154961" },
        { id = "wave", name = "Wave", command = "wave", animationId = "http://www.roblox.com/asset/?id=128777973" },
        { id = "cheer", name = "Cheer", command = "cheer", animationId = "http://www.roblox.com/asset/?id=129423030" },
        { id = "laugh", name = "Laugh", command = "laugh", animationId = "http://www.roblox.com/asset/?id=129423131" },
        { id = "point", name = "Point", command = "point", animationId = "http://www.roblox.com/asset/?id=128853357" },
        { id = "dance1", name = "Dance 1", command = "dance1", animationId = "http://www.roblox.com/asset/?id=182435998" },
        { id = "dance2", name = "Dance 2", command = "dance2", animationId = "http://www.roblox.com/asset/?id=182436842" },
        { id = "dance3", name = "Dance 3", command = "dance3", animationId = "http://www.roblox.com/asset/?id=182436935" },
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
    local GetAllEmotesFeature: any = nil

    local function collectAllEmotes(): ({EmoteDef}, {[string]: EmoteDef})
        local list: {EmoteDef} = {}
        local byId: {[string]: EmoteDef} = {}

        for _, def: EmoteDef in ipairs(BUILTIN_EMOTES) do
            byId[def.id] = def
            table.insert(list, def)
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
                        if type(emoteId) == "string"
                            and emoteId ~= "Back"
                            and type(info) == "table"
                            and (type(info.Command) == "string" or type(info.AnimationID) == "string") then
                            if not byId[emoteId] then
                                local entry: EmoteDef = {
                                    id = emoteId,
                                    name = tostring(info.Name or emoteId),
                                    command = tostring(info.Command or emoteId),
                                    animationId = tostring(info.AnimationID or ""),
                                }
                                byId[emoteId] = entry
                                table.insert(list, entry)
                            end
                        end
                    end
                end
            end
        end)

        return list, byId
    end

    -- Grant all emotes in ProfileData.Emotes.Owned and fire InventoryDataChanged
    -- so MM2's EmoteWindow and Inventory UI populate every emote button and wire
    -- ReplicatedStorage.Remotes.Misc.PlayEmote (which Character.Animate plays on
    -- Humanoid/Animator and replicates to the server and all other players).
    local function unlockAllEmotes(showNotification: boolean?): number
        local allEmotes: {EmoteDef}, _byId: {[string]: EmoteDef} = collectAllEmotes()
        local unlockedCount: number = 0

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
                if type(ownedTable) == "table" and not ownedSet[def.id] then
                    ownedSet[def.id] = true
                    table.insert(ownedTable, def.id)
                end
                if invChanged and type((invChanged :: any).Fire) == "function" then
                    pcall(function(): ()
                        (invChanged :: any):Fire("Emotes", def.id, 1)
                    end)
                end
                unlockedCount += 1
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
            GetAllEmotesFeature:SetStatus(string.format("%d Emotes", unlockedCount))
        end
        if showNotification and type(notify) == "function" then
            pcall(notify, string.format("Get All Emotes: unlocked %d MM2 emotes", unlockedCount))
        end
        return unlockedCount
    end

    -- Play an emote so it replicates to the server and is visible to all players:
    -- 1. Fires ReplicatedStorage.Remotes.Misc.PlayEmote:Fire(emoteId), which
    --    StarterCharacterScripts.Animate handles by playing the pre-registered
    --    emote command on LocalPlayer.Character.Humanoid.
    -- 2. Fallback: if PlayEmote is unavailable, loads the Animation onto the
    --    character's Humanoid/Animator (which Roblox replicates to the server).
    local function playServerReplicatedEmote(emoteId: string): boolean
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

        -- Direct Humanoid/Animator fallback (replicates to server via network ownership)
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
            if activeTrack then
                pcall(function(): ()
                    activeTrack:Stop(0.1)
                end)
                activeTrack = nil
            end
            local anim: Animation = Instance.new("Animation")
            anim.Name = def.command
            anim.AnimationId = def.animationId
            local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
            local track: any = if animator
                then animator:LoadAnimation(anim)
                else (humanoid :: any):LoadAnimation(anim)
            if track then
                activeTrack = track
                track:Play(0.1)
                playedFallback = true
            end
        end)

        return playedFallback
    end

    local function toggleGetAllEmotes(enabled: boolean): ()
        disconnectFeatureConnection("MM2GetAllEmotesRespawn")

        if not enabled then
            if GetAllEmotesFeature then
                GetAllEmotesFeature:SetStatus(nil)
            end
            return
        end

        unlockAllEmotes(true)

        if LocalPlayer and LocalPlayer.CharacterAdded then
            featureConnections.MM2GetAllEmotesRespawn = LocalPlayer.CharacterAdded:Connect(function(): ()
                task.delay(0.5, function(): ()
                    if GetAllEmotesFeature and GetAllEmotesFeature.enabled then
                        unlockAllEmotes(false)
                    end
                end)
            end)
        end
    end

    GetAllEmotesFeature = createUniversalFeature(
        "Get All Emotes",
        "Unlocks all MM2 emotes (Ninja Rest, Sit, Zen, Dab, Floss, Zombie, Headless, etc.) in the Emote wheel and inventory with full server replication.",
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
        "Immediately grants all MM2 emotes in your Emote wheel and inventory without buying them."
    )

    addCycleOption(
        GetAllEmotesFeature,
        "Select Emote",
        SPECIAL_EMOTE_LABELS,
        5,
        function(value: string): ()
            selectedEmoteLabel = value
        end,
        "Select an MM2 emote to play directly with server replication."
    )

    addActionOption(
        GetAllEmotesFeature,
        "Play Emote",
        function(): ()
            local emoteId: string = LABEL_TO_EMOTE_ID[selectedEmoteLabel] or "floss"
            unlockAllEmotes(false)
            playServerReplicatedEmote(emoteId)
        end,
        "Plays the selected emote on your character so all players in the server see it."
    )

    activeCleanup = function(): ()
        toggleGetAllEmotes(false)
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
