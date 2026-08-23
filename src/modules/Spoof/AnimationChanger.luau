--!strict
--
-- Animation changer.
--
-- Swaps the eight animations a humanoid plays for itself — idle, walk, run,
-- jump, fall, climb, swim and mood — for the ones in a Roblox animation
-- bundle. Cosmetic by construction: it changes what your character looks like
-- while it moves, not how it moves.
--
-- Roblox's classic packs ship with the module — sixteen of them, the ids
-- every animation script has carried for years. They load with the script,
-- no catalog call, no search button, no waiting: open the settings and the
-- list is simply there. A pack the table does not know still fits through
-- Custom ID, which takes any bundle id and resolves it at apply time.
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
    -- Published for the suites: the shipped catalog is part of the
    -- module's contract, not an implementation detail.
    builtinPacks = nil :: any,
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

-- The classic Roblox animation packs, by animation asset id. These are the
-- catalog animation assets themselves (each one is a container holding the
-- weighted clips), which is exactly what HumanoidDescription fields take.
-- Sixteen packs, stable for years; Custom ID covers anything newer.
local BUILTIN_PACKS: {{name: string, ids: {[string]: number}}} = {
    {name = "Astronaut", ids = {IdleAnimation = 1090133099, WalkAnimation = 1090131576, RunAnimation = 1090130630, JumpAnimation = 1090132507, FallAnimation = 1090132063, SwimAnimation = 1090133583, ClimbAnimation = 1090134016}},
    {name = "Bubbly", ids = {IdleAnimation = 1018553897, WalkAnimation = 1018549681, RunAnimation = 1018548665, JumpAnimation = 1018553240, FallAnimation = 1018552770, SwimAnimation = 1018554245, ClimbAnimation = 1018554668}},
    {name = "Cartoony", ids = {IdleAnimation = 837011741, WalkAnimation = 837010234, RunAnimation = 837009922, JumpAnimation = 837011171, FallAnimation = 837010685, SwimAnimation = 837012509, ClimbAnimation = 837013990}},
    {name = "Elder", ids = {IdleAnimation = 892268340, WalkAnimation = 892267099, RunAnimation = 892265784, JumpAnimation = 892267917, FallAnimation = 892267521, SwimAnimation = 892268710, ClimbAnimation = 892269341}},
    {name = "Knight", ids = {IdleAnimation = 734327140, WalkAnimation = 734326330, RunAnimation = 734325948, JumpAnimation = 734326930, FallAnimation = 734326679, SwimAnimation = 734327363, ClimbAnimation = 734329002}},
    {name = "Levitation", ids = {IdleAnimation = 619542203, WalkAnimation = 619544080, RunAnimation = 619543231, JumpAnimation = 619542888, FallAnimation = 619541867, SwimAnimation = 619543721, ClimbAnimation = 619541458}},
    {name = "Mage", ids = {IdleAnimation = 754637456, WalkAnimation = 754636298, RunAnimation = 754635032, JumpAnimation = 754637084, FallAnimation = 754636589, SwimAnimation = 754638471, ClimbAnimation = 754639239}},
    {name = "Ninja", ids = {IdleAnimation = 658832408, WalkAnimation = 658831143, RunAnimation = 658830056, JumpAnimation = 658832070, FallAnimation = 658831500, SwimAnimation = 658832807, ClimbAnimation = 658833139}},
    {name = "Pirate", ids = {IdleAnimation = 837024662, WalkAnimation = 837023892, RunAnimation = 837023444, JumpAnimation = 837024350, FallAnimation = 837024147, SwimAnimation = 837025054, ClimbAnimation = 837025325}},
    {name = "Robot", ids = {IdleAnimation = 619521748, WalkAnimation = 619522849, RunAnimation = 619522386, JumpAnimation = 619522088, FallAnimation = 619521521, SwimAnimation = 619522642, ClimbAnimation = 619521311}},
    {name = "Stylish", ids = {IdleAnimation = 619511648, WalkAnimation = 619512767, RunAnimation = 619512153, JumpAnimation = 619511974, FallAnimation = 619511417, SwimAnimation = 619512450, ClimbAnimation = 619509955}},
    {name = "Superhero", ids = {IdleAnimation = 619528125, WalkAnimation = 619529601, RunAnimation = 619528716, JumpAnimation = 619528412, FallAnimation = 619527817, SwimAnimation = 619529095, ClimbAnimation = 619527470}},
    {name = "Toy", ids = {IdleAnimation = 973771666, WalkAnimation = 973767371, RunAnimation = 973766674, JumpAnimation = 973770652, FallAnimation = 973768058, SwimAnimation = 973772659, ClimbAnimation = 973773170}},
    {name = "Vampire", ids = {IdleAnimation = 1113742618, WalkAnimation = 1113741192, RunAnimation = 1113740510, JumpAnimation = 1113742359, FallAnimation = 1113742092, SwimAnimation = 1113742944, ClimbAnimation = 1113743239}},
    {name = "Werewolf", ids = {IdleAnimation = 1113752682, WalkAnimation = 1113751657, RunAnimation = 1113750642, JumpAnimation = 1113752285, FallAnimation = 1113751889, SwimAnimation = 1113752975, ClimbAnimation = 1113754738}},
    {name = "Zombie", ids = {IdleAnimation = 619535834, WalkAnimation = 619537468, RunAnimation = 619536621, JumpAnimation = 619536283, FallAnimation = 619535616, SwimAnimation = 619537096, ClimbAnimation = 619535091}},
}
Module.builtinPacks = BUILTIN_PACKS

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
        settingSelection = false,
    }

    -- The built-in packs are the list; saved Custom IDs join them below.
    -- Nothing loads, nothing searches — sixteen names, ready at boot.
    local SAVED_KEY: string = "Universal.AnimationChanger.SavedIDs"
    local function reloadPacks(): ()
        runtime.packs = {}
        runtime.byLabel = {}
        for _, pack: any in ipairs(BUILTIN_PACKS) do
            local entry: any = {label = pack.name, ids = pack.ids}
            table.insert(runtime.packs, entry)
            runtime.byLabel[entry.label] = entry
        end
        local saved: any = host.configData
            and host.configData.values[SAVED_KEY]
        if type(saved) == "string" and saved ~= "" then
            for idText: string in string.gmatch(saved, "[^,]+") do
                local id: number? = tonumber(idText)
                if id then
                    local entry: any = {
                        label = "Saved " .. tostring(id),
                        id = id,
                    }
                    table.insert(runtime.packs, entry)
                    runtime.byLabel[entry.label] = entry
                end
            end
        end
    end
    reloadPacks()

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
    animations:CreateTextBox({
        Name = "Custom ID",
        Default = "",
        Tooltip = "Optional: a bundle id, worn instead of the pick above "
            .. "when filled in. Useful for a pack the search misses.",
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
    animations:CreateButton({
        Name = "Save ID",
        Tooltip = "Keeps the bundle id from Custom ID in the Pack list, so "
            .. "it survives rejoins and reinjects.",
        Function = function(): ()
            local typed: number? = tonumber(
                tostring(animations.Options["Custom ID"].Value or "")
            )
            if not typed or typed <= 0 then
                animations:Notify("put a bundle id in Custom ID first")
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
                    animations:Notify(tostring(typed) .. " is already saved")
                    return
                end
            end
            store.values[SAVED_KEY] = saved == ""
                and tostring(typed)
                or (saved .. "," .. tostring(typed))
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
            reloadPacks()
            pcall(function(): ()
                animations.Options["Pack"]:Refresh()
            end)
            animations:Notify("saved " .. tostring(typed))
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

    -- What to wear: a typed Custom ID wins, then the ticked pack. The
    -- built-in packs already carry their asset ids; only a bundle id has
    -- to be opened at the catalog.
    local typed: number? = tonumber(animations.Options["Custom ID"].Value)
    local pack: any = runtime.selected and runtime.byLabel[runtime.selected]
    local wearing: string = ""
    local descriptionIds: {[string]: number} = {}
    if typed and typed > 0 then
        descriptionIds = Module.resolveBundle(typed)
        wearing = "bundle " .. tostring(typed)
    elseif pack and pack.ids then
        descriptionIds = pack.ids
        wearing = tostring(pack.label)
    elseif pack and pack.id then
        descriptionIds = Module.resolveBundle(pack.id)
        wearing = tostring(pack.label)
    else
        if not quiet then
            animations:Notify("pick a pack first")
        end
        return
    end
    if next(descriptionIds) == nil then
        if not quiet then
            animations:Notify("that bundle has no animations")
        end
        return
    end

    -- Both paths, always: the description is the supported route and the
    -- Animate script is the fallback that survives games re-applying their
    -- own description.
    local applied: boolean = false
    local ok: boolean, description: any = pcall(function(): any
        return (humanoid :: Humanoid):GetAppliedDescription()
    end)
    if ok and typeof(description) == "Instance" then
        for field: string, assetId: number in pairs(descriptionIds) do
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

    -- The Animate script wants the playable clip, not the catalog
    -- container the description takes; built-in ids are containers, so
    -- each one opens to its clip here (and falls back to itself when the
    -- asset already is one).
    local animateIds: {[string]: number} = {}
    for field: string, assetId: number in pairs(descriptionIds) do
        local clip: number? = nil
        pcall(function(): ()
            clip = Module.resolveClipId(assetId)
        end)
        animateIds[field] = clip or assetId
    end
    applied = Module.patchAnimateScript(character :: Model, animateIds) or applied

    if not quiet then
        animations:Notify(
            applied
                and ("wearing " .. wearing)
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
