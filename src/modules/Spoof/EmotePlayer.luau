--!strict
--
-- Emote player.
--
-- Plays an emote by asset id — a Roblox one or a UGC one, they load through
-- exactly the same path — and stops it again. Three places to get an id from,
-- because a player has one of three things in hand:
--
--   * the emotes the disguise read off the avatar it is wearing;
--   * whatever the catalog returns for a search, which is the only way to find
--     a UGC emote by name;
--   * an id pasted straight in, which always works and needs nothing.
--
-- The track is loaded into the humanoid's own Animator, so the emote plays on
-- the real character and everyone sees it — this is the one thing on the Spoof
-- page that is not local-only, because an emote *is* an animation the server
-- replicates. It is still cosmetic: it moves your avatar and nothing else.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "EmotePlayer",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function trimmed(text: string): string
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local state: any = host.state

    local runtime: any = {
        track = nil :: AnimationTrack?,
        catalog = {} :: {any},
        byLabel = {} :: {[string]: number},
        searching = false,
        settingSelection = false,
        selected = nil :: string?,
    }

    state.spoofEmotes = state.spoofEmotes or {}

    local function animator(): Animator?
        local character: Model? = localPlayer.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then
            return nil
        end
        local existing: Animator? =
            humanoid:FindFirstChildOfClass("Animator") :: Animator?
        if existing then
            return existing
        end
        -- A character built without one still animates through it, so it is
        -- worth creating rather than giving up.
        local created: boolean, made: any = pcall(function(): any
            local instance: Animator = Instance.new("Animator")
            instance.Parent = humanoid
            return instance
        end)
        return created and made or nil
    end

    -- Everything the player can pick from, in one list: what the disguise
    -- found, what the last search returned, and nothing else.
    local function labels(): {string}
        local rows: {string} = {}
        runtime.byLabel = {}
        for _, emote: any in ipairs(state.spoofEmotes or {}) do
            if type(emote) == "table" and type(emote.id) == "number" then
                local label: string = tostring(emote.name) .. "  ·  avatar"
                runtime.byLabel[label] = emote.id
                table.insert(rows, label)
            end
        end
        for _, item: any in ipairs(runtime.catalog) do
            runtime.byLabel[item.label] = item.id
            table.insert(rows, item.label)
        end
        return rows
    end

    local function stop(): ()
        local track: AnimationTrack? = runtime.track
        runtime.track = nil
        if track then
            local resolved: AnimationTrack = track :: AnimationTrack
            pcall(function(): ()
                resolved:Stop(0.15)
                resolved:Destroy()
            end)
        end
    end

    local emotes: any
    emotes = framework.Categories.Utility:CreateModule({
        Name = "Emote Player",
        Category = "Spoof",
        Order = 3,
        Parent = state.spoofScroll,
        Registry = state.spoofFeatures,
        Tooltip = "Play any emote by id — Roblox's own or UGC.",
        Function = function(enabled: boolean): ()
            if not enabled then
                stop()
                return
            end
            -- Dying mid-emote leaves a track pointing at a humanoid that no
            -- longer exists.
            emotes:Event(localPlayer.CharacterAdded, function(): ()
                stop()
            end)
            emotes:Clean(stop)
        end,
    })

    emotes:CreateList({
        Name = "Emote",
        Items = labels,
        EmptyText = "paste an id",
        Tooltip = "Emotes from the avatar you are wearing, plus whatever the "
            .. "last search returned.",
        Function = function(_selected: any, names: {string}): ()
            if runtime.settingSelection then
                return
            end
            local chosen: string? = nil
            for _, name: string in ipairs(names) do
                if name ~= runtime.selected then
                    chosen = name
                    break
                end
            end
            chosen = chosen or names[1]
            runtime.settingSelection = true
            for _, name: string in ipairs(names) do
                if name ~= chosen then
                    pcall(function(): ()
                        emotes.Options["Emote"]:Set(name, false)
                    end)
                end
            end
            runtime.settingSelection = false
            runtime.selected = chosen
        end,
    })
    emotes:CreateTextBox({
        Name = "Emote ID",
        Default = "",
        Tooltip = "Played instead of the list when it is filled in. Any emote "
            .. "animation id, Roblox or UGC.",
    })
    emotes:CreateTextBox({
        Name = "Search",
        Default = "",
        Tooltip = "A name to look for in the catalog. Leave the module's "
            .. "Roblox-only switch off to include UGC emotes.",
    })
    emotes:CreateToggle({
        Name = "Roblox only",
        Default = false,
        Tooltip = "Restrict the search to emotes Roblox published itself.",
    })
    emotes:CreateButton({
        Name = "Find emotes",
        Tooltip = "Search the catalog for the name above.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.search(context, emotes, runtime)
            end)
        end,
    })
    emotes:CreateSlider({
        Name = "Speed",
        Min = 0.25,
        Max = 2,
        Default = 1,
        Tooltip = "Playback rate.",
    })
    emotes:CreateToggle({
        Name = "Loop",
        Default = false,
        Tooltip = "Keep the emote running until you stop it.",
    })
    emotes:CreateButton({
        Name = "Play",
        Tooltip = "Play the ticked emote, or the id in the box.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.play(context, emotes, runtime, animator, stop)
            end)
        end,
    })
    emotes:CreateButton({
        Name = "Stop",
        Tooltip = "Stop whatever is playing.",
        Function = function(): ()
            stop()
        end,
    })
    emotes:CreateNote(
        "An emote is a real animation on your character, so other players see "
            .. "it. Games that lock the humanoid's state, or R6 characters, "
            .. "will refuse some of them."
    )

    activeCleanup = function(): ()
        stop()
        runtime.catalog = {}
        runtime.byLabel = {}
        runtime.selected = nil
    end
    Module.Initialized = true
    return emotes
end

function Module.search(context: Runtime, emotes: any, runtime: any): ()
    if runtime.searching then
        return
    end
    local keyword: string = trimmed(tostring(emotes.Options["Search"].Value or ""))
    if keyword == "" then
        emotes:Notify("type something to look for")
        return
    end
    runtime.searching = true
    local found: {any} = {}

    local ok: boolean = pcall(function(): ()
        local service: any = game:GetService("AvatarEditorService")
        local params: any = CatalogSearchParams.new()
        params.SearchKeyword = keyword
        pcall(function(): ()
            params.AssetTypes = {Enum.AvatarAssetType.EmoteAnimation}
        end)
        if emotes.Options["Roblox only"].Value then
            pcall(function(): ()
                params.CreatorName = "Roblox"
            end)
        end
        local pages: any = service:SearchCatalog(params)
        for _ = 1, 2 do
            for _, item: any in ipairs(pages:GetCurrentPage()) do
                local id: number? = tonumber(item.Id or item.id)
                local name: string = tostring(item.Name or item.name or "Emote")
                if id then
                    table.insert(found, {
                        id = id,
                        label = name .. "  ·  " .. tostring(id),
                    })
                end
            end
            if pages.IsFinished then
                break
            end
            pages:AdvanceToNextPageAsync()
        end
    end)

    runtime.searching = false
    if not ok then
        emotes:Notify("the catalog refused the search")
        return
    end
    runtime.catalog = found
    pcall(function(): ()
        emotes.Options["Emote"]:Refresh()
    end)
    emotes:Notify(tostring(#found) .. " emotes found")
end

function Module.play(
    context: Runtime,
    emotes: any,
    runtime: any,
    animator: () -> Animator?,
    stop: () -> ()
): ()
    local typed: number? = tonumber(
        trimmed(tostring(emotes.Options["Emote ID"].Value or ""))
    )
    local assetId: number = typed or 0
    if assetId <= 0 and runtime.selected then
        assetId = runtime.byLabel[runtime.selected] or 0
    end
    if assetId <= 0 then
        emotes:Notify("tick an emote or paste an id")
        return
    end

    local target: Animator? = animator()
    if not target then
        emotes:Notify("no character to animate")
        return
    end

    stop()
    local animation: Animation = Instance.new("Animation")
    animation.AnimationId = "rbxassetid://" .. tostring(assetId)
    local loaded: boolean, track: any = pcall(function(): any
        return (target :: Animator):LoadAnimation(animation)
    end)
    if not loaded or typeof(track) ~= "Instance" then
        animation:Destroy()
        emotes:Notify("that id is not an animation you can play")
        return
    end

    local resolved: AnimationTrack = track :: AnimationTrack
    resolved.Priority = Enum.AnimationPriority.Action
    resolved.Looped = emotes.Options["Loop"].Value == true
    runtime.track = resolved
    local ok: boolean = pcall(function(): ()
        resolved:Play(0.1)
        resolved:AdjustSpeed(emotes.Options["Speed"].Value)
    end)
    animation:Destroy()
    if not ok then
        emotes:Notify("the game refused to play it")
        return
    end
    if not resolved.Looped then
        -- One-shot emotes clean themselves up, so the Stop button is only for
        -- the looping ones.
        resolved.Stopped:Once(function(): ()
            if runtime.track == resolved then
                runtime.track = nil
            end
        end)
    end
    emotes:Notify("playing " .. tostring(assetId))
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
