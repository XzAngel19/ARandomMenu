--!strict
--
-- Animation changer.
--
-- Swaps the eight animations a humanoid plays for itself — idle, walk, run,
-- jump, fall, climb, swim and mood — for the ones in a Roblox animation
-- bundle. Cosmetic by construction: it changes what your character looks like
-- while it moves, not how it moves.
--
-- The packs are not a hard-coded list of asset ids. Those lists go stale, and
-- a wrong id is a module that silently does nothing, so the catalog is asked
-- instead: `AvatarEditorService:SearchCatalog` with the bundle type set to
-- animations and the creator pinned to **Roblox**, which is the filter that
-- keeps UGC out. Each bundle is then resolved to its individual animation
-- assets through `GetItemDetails`, and each asset is matched to the slot its
-- own name says it belongs to ("Ninja Run" is the run animation).
--
-- Two ways of applying it, because games disagree about which one survives:
--
--   Description    the supported path. The animation ids are fields on the
--                  HumanoidDescription, so applying one swaps the set the way
--                  the avatar editor does.
--   Animate script the client-side `Animate` LocalScript every default
--                  character carries. Games that rebuild the character, or
--                  that re-apply their own description, undo the first path
--                  and not this one.
--
-- Both, by default.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AnimationChanger",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- The eight slots, and the words that identify each one inside a bundle's
-- item names. Order matters: "swimidle" has to be tested before "idle" or
-- every swim-idle animation lands in the idle slot.
local SLOTS: {{field: string, keys: {string}}} = {
    {field = "SwimAnimation", keys = {"swim"}},
    {field = "ClimbAnimation", keys = {"climb"}},
    {field = "RunAnimation", keys = {"run"}},
    {field = "WalkAnimation", keys = {"walk"}},
    {field = "JumpAnimation", keys = {"jump"}},
    {field = "FallAnimation", keys = {"fall"}},
    {field = "MoodAnimation", keys = {"mood"}},
    {field = "IdleAnimation", keys = {"idle"}},
}

-- Where the same eight live inside the default `Animate` script.
local ANIMATE_SLOTS: {[string]: {string}} = {
    IdleAnimation = {"idle"},
    WalkAnimation = {"walk"},
    RunAnimation = {"run"},
    JumpAnimation = {"jump"},
    FallAnimation = {"fall"},
    ClimbAnimation = {"climb"},
    SwimAnimation = {"swim", "swimidle"},
    MoodAnimation = {"mood"},
}

local function slotForName(name: string): string?
    local lowered: string = string.lower(name)
    for _, slot: {field: string, keys: {string}} in ipairs(SLOTS) do
        for _, key: string in ipairs(slot.keys) do
            if string.find(lowered, key, 1, true) then
                return slot.field
            end
        end
    end
    return nil
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer

    local runtime: any = {
        packs = {} :: {any},
        byLabel = {} :: {[string]: any},
        selected = nil :: string?,
        original = nil :: {[string]: number}?,
        searching = false,
        settingSelection = false,
    }

    local function avatarEditor(): any?
        local ok: boolean, service: any = pcall(function(): any
            return game:GetService("AvatarEditorService")
        end)
        return ok and service or nil
    end

    local function currentHumanoid(): Humanoid?
        local character: Model? = localPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    end

    -- The set the character is wearing right now, so Reset has something real
    -- to go back to rather than a guess at the defaults.
    local function rememberOriginal(): ()
        if runtime.original then
            return
        end
        local humanoid: Humanoid? = currentHumanoid()
        if not humanoid then
            return
        end
        local ok: boolean, description: any = pcall(function(): any
            return (humanoid :: Humanoid):GetAppliedDescription()
        end)
        if not ok or typeof(description) ~= "Instance" then
            return
        end
        local saved: {[string]: number} = {}
        for _, slot: {field: string, keys: {string}} in ipairs(SLOTS) do
            local read: boolean, value: any = pcall(function(): any
                return (description :: any)[slot.field]
            end)
            saved[slot.field] = (read and type(value) == "number") and value or 0
        end
        runtime.original = saved
    end

    local animations: any
    animations = framework.Categories.Utility:CreateModule({
        Name = "Animation Changer",
        Category = "Fun",
        Order = 2,
        ConfigKey = "Universal.AnimationChanger",
        Tooltip = "Wear a Roblox animation pack: idle, walk, run, jump, fall, "
            .. "climb and swim.",
        Function = function(enabled: boolean): ()
            if not enabled then
                animations:SetStatus(nil)
                Module.restore(context, runtime)
                return
            end
            animations:SetStatus(
                runtime.selected and string.sub(runtime.selected, 1, 15) or "custom"
            )
            rememberOriginal()
            -- Re-applied after a respawn, because a fresh character arrives
            -- with the game's own animations.
            animations:Event(localPlayer.CharacterAdded, function(): ()
                task.spawn(function(): ()
                    task.wait(0.4)
                    if animations.Enabled then
                        Module.apply(context, animations, runtime, true)
                    end
                end)
            end)
            task.spawn(function(): ()
                if #runtime.packs == 0 then
                    Module.search(context, animations, runtime)
                end
                Module.apply(context, animations, runtime, true)
            end)
        end,
    })

    -- One pack at a time: the list is the only control that can hold a growing
    -- set of names, so ticking a second entry unticks the first instead of
    -- letting two packs fight over the same eight slots.
    animations:CreateList({
        Name = "Pack",
        Items = function(): {string}
            local labels: {string} = {}
            for _, pack: any in ipairs(runtime.packs) do
                table.insert(labels, pack.label)
            end
            return labels
        end,
        EmptyText = "none found",
        Tooltip = "Animation bundles published by Roblox. UGC is filtered out "
            .. "by the search itself.",
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
                        animations.Options["Pack"]:Set(name, false)
                    end)
                end
            end
            runtime.settingSelection = false
            runtime.selected = chosen
            if animations.Enabled then
                animations:SetStatus(chosen and string.sub(chosen, 1, 15) or "custom")
            end
        end,
    })
    animations:CreateButton({
        Name = "Find packs",
        Tooltip = "Ask the catalog for every animation bundle Roblox itself "
            .. "published.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.search(context, animations, runtime)
            end)
        end,
    })
    animations:CreateTextBox({
        Name = "Bundle ID",
        Default = "",
        Tooltip = "Applied instead of the list when it is filled in. Useful "
            .. "for a pack the search does not return.",
    })
    animations:CreateDropdown({
        Name = "Apply through",
        List = {"Both", "Description", "Animate script"},
        Index = 1,
        Tooltip = "Description is the supported path; the Animate script "
            .. "survives games that re-apply their own description.",
    })
    animations:CreateButton({
        Name = "Apply",
        Tooltip = "Wear the selected pack now.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.apply(context, animations, runtime, false)
            end)
        end,
    })
    animations:CreateButton({
        Name = "Reset",
        Tooltip = "Put the animations the character arrived with back.",
        Function = function(): ()
            task.spawn(function(): ()
                Module.restore(context, runtime)
                animations:Notify("animations restored")
            end)
        end,
    })
    animations:CreateNote(
        "R15 only — an R6 character has no animation fields to swap. A game "
            .. "that ships its own animation script overrides both paths."
    )

    activeCleanup = function(): ()
        Module.restore(context, runtime)
        runtime.packs = {}
        runtime.byLabel = {}
        runtime.selected = nil
        runtime.original = nil
    end
    Module.Initialized = true
    return animations
end

-- Catalog search. Everything here is wrapped: the service exists in every
-- live experience, but it throws on restricted places and returns different
-- shapes across client versions, and a module that errors on a missing field
-- is worse than one that says "none found".
function Module.search(context: Runtime, animations: any, runtime: any): ()
    if runtime.searching then
        return
    end
    runtime.searching = true
    local found: {any} = {}

    local ok: boolean = pcall(function(): ()
        local service: any = game:GetService("AvatarEditorService")
        local params: any = CatalogSearchParams.new()
        pcall(function(): ()
            params.BundleTypes = {Enum.BundleType.Animations}
        end)
        pcall(function(): ()
            -- The one filter that separates Roblox's own packs from UGC.
            params.CreatorName = "Roblox"
        end)
        pcall(function(): ()
            params.SortType = Enum.CatalogSortType.MostFavorited
        end)
        local pages: any = service:SearchCatalog(params)
        for _ = 1, 3 do
            for _, item: any in ipairs(pages:GetCurrentPage()) do
                local id: number? = tonumber(item.Id or item.id)
                local name: string = tostring(item.Name or item.name or "Bundle")
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
        animations:Notify("the catalog refused the search")
        return
    end
    table.sort(found, function(left: any, right: any): boolean
        return left.label < right.label
    end)
    runtime.packs = found
    runtime.byLabel = {}
    for _, pack: any in ipairs(found) do
        runtime.byLabel[pack.label] = pack
    end
    pcall(function(): ()
        animations.Options["Pack"]:Refresh()
    end)
    animations:Notify(tostring(#found) .. " packs from Roblox")
end

-- A bundle item is often a container asset, not the AnimationClip that an
-- Animator can play. Roblox's default pack ids are the common example: putting
-- 619512767 straight into an Animation reaches LoadAnimation and fails with
-- "AnimationClip loaded is not valid". GetObjects opens the asset locally; an
-- Animation child names the real clip, while a KeyframeSequence means the id
-- was already a clip.
function Module.resolveClipId(assetId: number): number?
    local loaded: {Instance} = {}
    local ok: boolean = pcall(function(): ()
        loaded = game:GetObjects("rbxassetid://" .. tostring(assetId))
    end)
    if not ok then
        return nil
    end

    local resolved: number? = nil
    for _, root: Instance in ipairs(loaded) do
        if root:IsA("KeyframeSequence") then
            resolved = assetId
        end
        local candidates: {Instance} = {root}
        for _, descendant: Instance in ipairs(root:GetDescendants()) do
            table.insert(candidates, descendant)
        end
        for _, candidate: Instance in ipairs(candidates) do
            if candidate:IsA("Animation") then
                local id: number? = tonumber(
                    string.match((candidate :: Animation).AnimationId, "%d+")
                )
                if id and id > 0 then
                    resolved = id
                    break
                end
            end
        end
        root:Destroy()
        if resolved then
            break
        end
    end
    -- GetObjects can return several roots. The answer came from one, but none
    -- of these temporary containers belongs in the DataModel afterwards.
    for _, root: Instance in ipairs(loaded) do
        pcall(function(): ()
            root:Destroy()
        end)
    end
    return resolved
end

-- A bundle id becomes eight playable clip ids, keyed by the slot each item's
-- own name identifies.
function Module.resolveBundle(bundleId: number): {[string]: number}
    local ids: {[string]: number} = {}
    pcall(function(): ()
        local service: any = game:GetService("AvatarEditorService")
        local details: any = service:GetItemDetails(
            bundleId,
            Enum.AvatarItemType.Bundle
        )
        local items: any = details
            and (details.BundledItems or details.bundledItems or details.Items)
        if type(items) ~= "table" then
            return
        end
        for _, item: any in ipairs(items) do
            local name: string = tostring(item.Name or item.name or "")
            local id: number? = tonumber(item.Id or item.id)
            local slot: string? = slotForName(name)
            if id and slot and not ids[slot] then
                local clipId: number? = Module.resolveClipId(id)
                if clipId then
                    ids[slot] = clipId
                end
            end
        end
    end)
    return ids
end

-- The Animate script path: rewrite the AnimationId of every animation the
-- default script owns, then restart the tracks so the change is visible
-- without waiting for the next state change.
function Module.patchAnimateScript(
    character: Model,
    ids: {[string]: number}
): boolean
    local animate: Instance? = character:FindFirstChild("Animate")
    if not animate then
        return false
    end
    local touched: boolean = false
    for field: string, assetId: number in pairs(ids) do
        for _, containerName: string in ipairs(ANIMATE_SLOTS[field] or {}) do
            local container: Instance? = (animate :: Instance):FindFirstChild(
                containerName
            )
            if not container then
                continue
            end
            for _, child: Instance in ipairs((container :: Instance):GetChildren()) do
                if child:IsA("Animation") then
                    (child :: Animation).AnimationId =
                        "rbxassetid://" .. tostring(assetId)
                    touched = true
                end
            end
        end
    end
    if not touched then
        return false
    end
    local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
    local animator: Animator? = humanoid
        and humanoid:FindFirstChildOfClass("Animator") :: Animator?
    if animator then
        pcall(function(): ()
            for _, track: AnimationTrack in
                ipairs((animator :: Animator):GetPlayingAnimationTracks())
            do
                track:Stop(0)
            end
        end)
    end
    -- The default Animate script is a LocalScript on this client, so it can be
    -- kicked into re-reading the ids it owns.
    if animate:IsA("LocalScript") then
        pcall(function(): ()
            local script: LocalScript = animate :: LocalScript
            script.Disabled = true
            task.wait()
            script.Disabled = false
        end)
    end
    return true
end

function Module.apply(
    context: Runtime,
    animations: any,
    runtime: any,
    quiet: boolean
): ()
    local host: any = context.host
    local localPlayer: Player = host.LocalPlayer
    local character: Model? = localPlayer.Character
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not character or not humanoid then
        if not quiet then
            animations:Notify("no character yet")
        end
        return
    end

    local typed: number? = tonumber(animations.Options["Bundle ID"].Value)
    local bundleId: number = typed or 0
    if bundleId <= 0 then
        local pack: any = runtime.selected and runtime.byLabel[runtime.selected]
        bundleId = pack and pack.id or 0
    end
    if bundleId <= 0 then
        if not quiet then
            animations:Notify("pick a pack first")
        end
        return
    end

    local ids: {[string]: number} = Module.resolveBundle(bundleId)
    if next(ids) == nil then
        if not quiet then
            animations:Notify("that bundle has no animations")
        end
        return
    end

    local through: string = animations.Options["Apply through"].Value
    local applied: boolean = false

    if through ~= "Animate script" then
        local ok: boolean, description: any = pcall(function(): any
            return (humanoid :: Humanoid):GetAppliedDescription()
        end)
        if ok and typeof(description) == "Instance" then
            for field: string, assetId: number in pairs(ids) do
                pcall(function(): ()
                    (description :: any)[field] = assetId
                end)
            end
            applied = pcall(function(): ()
                (humanoid :: Humanoid):ApplyDescription(
                    description :: HumanoidDescription
                )
            end)
        end
    end
    if through ~= "Description" then
        applied = Module.patchAnimateScript(character :: Model, ids) or applied
    end

    if not quiet then
        animations:Notify(
            applied
                and ("wearing bundle " .. tostring(bundleId))
                or "nothing accepted the swap"
        )
    end
end

function Module.restore(context: Runtime, runtime: any): ()
    local saved: {[string]: number}? = runtime.original
    if not saved then
        return
    end
    local host: any = context.host
    local localPlayer: Player = host.LocalPlayer
    local character: Model? = localPlayer.Character
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    if not character or not humanoid then
        return
    end
    local ok: boolean, description: any = pcall(function(): any
        return (humanoid :: Humanoid):GetAppliedDescription()
    end)
    if ok and typeof(description) == "Instance" then
        for field: string, assetId: number in pairs(saved :: {[string]: number}) do
            pcall(function(): ()
                (description :: any)[field] = assetId
            end)
        end
        pcall(function(): ()
            (humanoid :: Humanoid):ApplyDescription(
                description :: HumanoidDescription
            )
        end)
    end
    Module.patchAnimateScript(character :: Model, saved :: {[string]: number})
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
