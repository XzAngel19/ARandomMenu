export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "EmotePlayer",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- An emote must stay a real animation for other players to see it; this
-- priority sits above the animations games usually force onto characters.
local EMOTE_PRIORITY: Enum.AnimationPriority = Enum.AnimationPriority.Action2

-- How long to wait for the animation data to arrive before giving up.
local LOAD_TIMEOUT: number = 5

local function trimmed(text: string): string
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local spoofAvatar: any = context.services.spoofAvatar

    local runtime: any = {
        current = nil :: any?,
        catalog = {} :: {any},
        byLabel = {} :: {[string]: number},
        searching = false,
        settingSelection = false,
        selected = nil :: string?,
    }

    -- While Disguise is wearing a body double, the real body is invisible:
    -- emotes must play on the double to be seen at all.
    local function puppetAnimator(): Animator?
        local rig: Model? = spoofAvatar.getRig and spoofAvatar.getRig() or nil
        if not rig then
            return nil
        end
        local humanoid: Humanoid? =
            (rig :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then
            return nil
        end
        local existing: Animator? =
            (humanoid :: Humanoid):FindFirstChildOfClass("Animator") :: Animator?
        if existing then
            return existing
        end
        local created: boolean, made: any = pcall(function(): any
            local instance: Animator = Instance.new("Animator")
            instance.Parent = humanoid
            return instance
        end)
        return created and made or nil
    end

    local function animator(): Animator?
        local preferred: Animator? = puppetAnimator()
        if preferred then
            return preferred
        end
        local character: Model? = localPlayer.Character
        if not character or not (character :: Model).Parent then
            return nil
        end
        local humanoid: Humanoid? =
            (character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid?
        if humanoid then
            local existing: Animator? =
                (humanoid :: Humanoid):FindFirstChildOfClass("Animator") :: Animator?
            if existing then
                return existing
            end
        end
        -- Some games parent the Animator elsewhere (the root part, say).
        local anywhere: Animator? =
            (character :: Model):FindFirstChildWhichIsA("Animator", true) :: Animator?
        if anywhere then
            return anywhere
        end
        local created: boolean, made: any = pcall(function(): any
            if not humanoid then
                return nil
            end
            local instance: Animator = Instance.new("Animator")
            instance.Parent = humanoid
            return instance
        end)
        return created and made or nil
    end

    local SAVED_KEY: string = "Universal.EmotePlayer.SavedIDs"
    local function labels(): {string}
        local rows: {string} = {}
        runtime.byLabel = {}
        for _, emote: any in ipairs(spoofAvatar.getEmotes()) do
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
        local saved: any = host.configData
            and host.configData.values[SAVED_KEY]
        if type(saved) == "string" and saved ~= "" then
            for idText: string in string.gmatch(saved, "[^,]+") do
                local id: number? = tonumber(idText)
                if id then
                    local label: string = "Saved " .. tostring(id)
                    runtime.byLabel[label] = id
                    table.insert(rows, label)
                end
            end
        end
        return rows
    end

    local function stop(): ()
        local current: any? = runtime.current
        runtime.current = nil
        if not current then
            return
        end
        pcall(function(): ()
            (current :: any).track:Stop(0.15)
        end)
        pcall(function(): ()
            (current :: any).track:Destroy()
        end)
        pcall(function(): ()
            (current :: any).animation:Destroy()
        end)
    end

    local emotes: any
    emotes = framework.Categories.Utility:CreateModule({
        Name = "Emote Player",
        Category = "Fun",
        Order = 3,
        ConfigKey = "Universal.EmotePlayer",
        Tooltip = "Play any emote by id - Roblox's own or UGC - with live "
            .. "speed and loop control.",
        Function = function(enabled: boolean): ()
            if not enabled then
                emotes:SetStatus(nil)
                stop()
                return
            end
            emotes:SetStatus(
                runtime.selected and string.sub(runtime.selected, 1, 15) or "custom"
            )
            emotes:Event(localPlayer.CharacterAdded, function(): ()
                stop()
            end)
            emotes:Clean(stop)
        end,
    })

    emotes:CreateList({
        Name = "Emote",
        Items = labels,
        EmptyText = "nothing yet - search or wear a disguise",
        Tooltip = "Pick what to play: emotes from the avatar you are "
            .. "wearing, plus whatever the last search returned.",
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
            if emotes.Enabled then
                emotes:SetStatus(chosen and string.sub(chosen, 1, 15) or "custom")
            end
        end,
    })
    emotes:CreateTextBox({
        Name = "Custom ID",
        Default = "",
        Tooltip = "Optional: overrides the pick above when filled in. Any "
            .. "emote animation id, Roblox or UGC.",
    })
    emotes:CreateButton({
        Name = "Save ID",
        Tooltip = "Keeps the id from Custom ID in the Emote list, so it "
            .. "survives rejoins and reinjects.",
        Function = function(): ()
            local typed: number? = tonumber(
                tostring(emotes.Options["Custom ID"].Value or "")
            )
            if not typed or typed <= 0 then
                emotes:Notify("put an emote id in Custom ID first")
                return
            end
            local store: any = host.configData
            if not store then
                return
            end
            local saved: string = type(store.values[SAVED_KEY]) == "string"
                and store.values[SAVED_KEY]
                or ""
            for idText: string in string.gmatch(saved, "[^,]+") do
                if tonumber(idText) == typed then
                    emotes:Notify(tostring(typed) .. " is already saved")
                    return
                end
            end
            store.values[SAVED_KEY] = saved == ""
                and tostring(typed)
                or (saved .. "," .. tostring(typed))
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
            pcall(function(): ()
                emotes.Options["Emote"]:Refresh()
            end)
            emotes:Notify("saved " .. tostring(typed))
        end,
    })
    emotes:CreateSlider({
        Name = "Speed",
        Min = 0.1,
        Max = 5,
        Step = 0.05,
        Default = 1,
        Tooltip = "Playback rate. Changes apply to the emote that is "
            .. "playing right now.",
        Function = function(value: number): ()
            local current: any? = runtime.current
            if current then
                pcall(function(): ()
                    (current :: any).track:AdjustSpeed(value)
                end)
            end
        end,
    })
    emotes:CreateToggle({
        Name = "Loop",
        Default = false,
        Tooltip = "Keep the emote running until you stop it. Toggling it "
            .. "mid-emote applies immediately.",
        Function = function(value: boolean): ()
            local current: any? = runtime.current
            if current then
                pcall(function(): ()
                    (current :: any).track.Looped = value
                end)
            end
        end,
    })
    emotes:CreateButton({
        Name = "Play",
        Tooltip = "Play the picked emote, or the custom id.",
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
    emotes:CreateTextBox({
        Name = "Search",
        Default = "",
        Tooltip = "A name to look for in the catalog. Leave Roblox only off "
            .. "to include UGC emotes.",
    })
    emotes:CreateToggle({
        Name = "Roblox only",
        Default = false,
        Tooltip = "Restrict the search to emotes Roblox published itself.",
    })
    emotes:CreateButton({
        Name = "Find emotes",
        Tooltip = "Search the catalog for the name above; results land in "
            .. "the Emote list.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.search(context, emotes, runtime)
            end)
        end,
    })
    emotes:CreateNote(
        "An emote is a real animation on your character, so other players "
            .. "see it. While Disguise is on, it plays on the body double."
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
        trimmed(tostring(emotes.Options["Custom ID"].Value or ""))
    )
    local assetId: number = typed or 0
    if assetId <= 0 and runtime.selected then
        assetId = runtime.byLabel[runtime.selected] or 0
    end
    if assetId <= 0 then
        emotes:Notify("pick an emote or fill in Custom ID")
        return
    end

    local target: Animator? = animator()
    if not target then
        emotes:Notify("no character to animate")
        return
    end

    stop()
    local animation: Animation = Instance.new("Animation")
    animation.Name = "WurstEmote"
    animation.AnimationId = "rbxassetid://" .. tostring(assetId)
    -- Keep it in the data model while it loads; destroying (or leaving
    -- limbo) early can silently cancel the fetch.
    animation.Parent = (target :: Animator).Parent or (target :: Animator)
    local loaded: boolean, track: any = pcall(function(): any
        return (target :: Animator):LoadAnimation(animation)
    end)
    if not loaded or typeof(track) ~= "Instance" then
        animation:Destroy()
        emotes:Notify("that id is not an animation you can play")
        return
    end

    local resolved: AnimationTrack = track :: AnimationTrack
    local playing: any = {track = resolved, animation = animation}
    runtime.current = playing
    resolved.Priority = EMOTE_PRIORITY
    resolved.Looped = emotes.Options["Loop"].Value == true
    pcall(function(): ()
        resolved:Play(0.1)
        resolved:AdjustSpeed(emotes.Options["Speed"].Value)
    end)

    resolved.Stopped:Once(function(): ()
        if runtime.current == playing then
            runtime.current = nil
        end
        pcall(function(): ()
            resolved:Destroy()
        end)
        pcall(function(): ()
            animation:Destroy()
        end)
    end)

    -- The Animation instance has to outlive the load: destroying it early
    -- silently cancels the fetch and nothing plays. Wait for the data, and
    -- only report failure if it never arrives.
    task.spawn(function(): ()
        local deadline: number = os.clock() + LOAD_TIMEOUT
        while
            runtime.current == playing
            and not resolved.IsLoaded
            and os.clock() < deadline
        do
            task.wait(0.05)
        end
        if runtime.current == playing and not resolved.IsLoaded then
            emotes:Notify("that id would not load as an animation")
            if runtime.current == playing then
                stop()
            end
        end
    end)

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
