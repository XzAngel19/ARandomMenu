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

-- A catalog emote's page id is usually NOT the id of the animation behind
-- it: pasting the shop id into an Animation fails to load. InsertService can
-- pull the marketplace asset locally, and the Animation instance inside it
-- carries the real animation id.
local function resolveCatalogEmoteId(assetId: number): number?
    local loaded: boolean, model: any = pcall(function(): any
        return game:GetService("InsertService"):LoadAsset(assetId)
    end)
    if not loaded or typeof(model) ~= "Instance" then
        return nil
    end
    local found: number? = nil
    pcall(function(): ()
        local candidates: {Instance} = {model :: Instance}
        for _, descendant: Instance in ipairs((model :: Instance):GetDescendants()) do
            table.insert(candidates, descendant)
        end
        for _, instance: Instance in ipairs(candidates) do
            if instance:IsA("Animation") then
                local id: number = tonumber(
                    string.match((instance :: Animation).AnimationId or "", "%d+")
                ) or 0
                if id > 0 then
                    found = id
                    break
                end
            end
        end
    end)
    pcall(function(): ()
        (model :: Instance):Destroy()
    end)
    return found
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
    -- emotes must play on the double to be seen at all. The double runs on
    -- an AnimationController (no Humanoid), so search the whole rig.
    local function puppetAnimator(): Animator?
        local rig: Model? = spoofAvatar.getRig and spoofAvatar.getRig() or nil
        if not rig then
            return nil
        end
        local existing: Animator? =
            (rig :: Model):FindFirstChildWhichIsA("Animator", true) :: Animator?
        if existing then
            return existing
        end
        local controller: AnimationController? =
            (rig :: Model):FindFirstChildOfClass("AnimationController") :: AnimationController?
        if not controller then
            return nil
        end
        local created: boolean, made: any = pcall(function(): any
            local instance: Animator = Instance.new("Animator")
            instance.Parent = controller
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
            .. "emote id, Roblox or UGC - catalog page ids work too.",
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
    emotes:CreateTextBox({
        Name = "Search",
        Default = "",
        Tooltip = "A name to look for in the catalog.",
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

    local function attempt(id: number): (Animation?, AnimationTrack?)
        local animation: Animation = Instance.new("Animation")
        animation.Name = "WurstEmote"
        animation.AnimationId = "rbxassetid://" .. tostring(id)
        -- Keep it in the data model while it loads; destroying (or leaving
        -- limbo) early can silently cancel the fetch.
        animation.Parent = (target :: Animator).Parent or (target :: Animator)
        local loaded: boolean, track: any = pcall(function(): any
            return (target :: Animator):LoadAnimation(animation)
        end)
        if loaded and typeof(track) == "Instance" then
            return animation, track
        end
        animation:Destroy()
        return nil, nil
    end

    local function start(animation: Animation, track: AnimationTrack): any
        stop()
        local playing: any = {track = track, animation = animation}
        runtime.current = playing
        track.Priority = EMOTE_PRIORITY
        track.Looped = emotes.Options["Loop"].Value == true
        pcall(function(): ()
            track:Play(0.1)
            track:AdjustSpeed(emotes.Options["Speed"].Value)
        end)
        track.Stopped:Once(function(): ()
            if runtime.current == playing then
                runtime.current = nil
            end
            pcall(function(): ()
                track:Destroy()
            end)
            pcall(function(): ()
                animation:Destroy()
            end)
        end)
        return playing
    end

    local function loadedInTime(playing: any, seconds: number): boolean
        local deadline: number = os.clock() + seconds
        while
            runtime.current == playing
            and not (playing.track :: AnimationTrack).IsLoaded
            and os.clock() < deadline
        do
            task.wait(0.05)
        end
        return runtime.current == playing
            and (playing.track :: AnimationTrack).IsLoaded
    end

    -- 1) Direct load: works when the id already is an animation id.
    local animation: Animation?, track: AnimationTrack? = attempt(assetId)
    if track and animation then
        local playing: any = start(animation :: Animation, track :: AnimationTrack)
        if loadedInTime(playing, 3) then
            emotes:Notify("playing " .. tostring(assetId))
            return
        end
        -- The track never received its data: probably a catalog page id.
    end

    -- 2) Resolve the emote through the marketplace and retry.
    local resolved: number? = resolveCatalogEmoteId(assetId)
    if not resolved or resolved <= 0 or resolved == assetId then
        stop()
        emotes:Notify("that id would not load as an emote")
        return
    end
    animation, track = attempt(resolved)
    if not track or not animation then
        stop()
        emotes:Notify("that id would not load as an emote")
        return
    end
    local playing: any = start(animation :: Animation, track :: AnimationTrack)
    if loadedInTime(playing, LOAD_TIMEOUT) then
        emotes:Notify("playing " .. tostring(resolved))
    else
        emotes:Notify("that id would not load as an emote")
        stop()
    end
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
