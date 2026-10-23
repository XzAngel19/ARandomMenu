--!strict
export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

type AppearanceTemplate = {
    object: Instance,
    parent: Instance?,
}

type MeshTemplate = {
    part: MeshPart,
    meshId: string,
    textureId: string,
}

type AnimationTemplate = {
    animation: Animation,
    animationId: string,
}

type AppearanceSnapshot = {
    character: Model,
    items: {AppearanceTemplate},
    meshParts: {MeshTemplate},
    animations: {AnimationTemplate},
    emotes: any,
    equippedEmotes: any,
    scales: {[string]: number},
    -- The humanoid description's own animation fields at snapshot
    -- time, so restoring movements can undo a description-route
    -- apply exactly instead of only rewriting Animate ids.
    descAnimations: {[string]: number},
}

local Module = {
    Name = "Disguise",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

-- 78492 is the default disguise: a normal user avatar whose movement
-- animations come from Roblox's own set, which is also the fallback below.
local DEFAULT_USER_ID: number = 78492
-- Roblox's own R15 animation set, i.e. the IDs inside the default Animate
-- script. A HumanoidDescription stores 0 for "keep the default", so copying
-- only the non-zero fields would silently keep OUR animations on the
-- disguised avatar. Filling the gaps with these makes the disguise use the
-- same set the target actually sees.
local DEFAULT_ANIMATION_IDS: {[string]: {string}} = {
    idle = {"507766666", "507766951", "507766388"},
    walk = {"507777826"},
    run = {"507767714"},
    jump = {"507765000"},
    fall = {"507767968"},
    climb = {"507765644"},
    swim = {"507784897"},
    swimidle = {"507785072"},
}
-- Roblox's own R6 set, i.e. the IDs inside the classic R6 Animate script the
-- engine inserts on blocky rigs. The R15 IDs above are keyed to UpperTorso and
-- RightUpperArm, so an R6 body cannot play them at all: the Animate script
-- stops without an error and the character freezes in its rest pose. That is
-- the still avatar in the report, not a wrong idle.
local DEFAULT_ANIMATION_IDS_R6: {[string]: {string}} = {
    idle = {"180435571", "180435792"},
    walk = {"180426354"},
    run = {"180426354"},
    jump = {"125750702"},
    fall = {"180436148"},
    climb = {"180436334"},
}
-- Every id the R15 default set owns. A HumanoidDescription from an avatar that
-- never bought a pack is indistinguishable from one that asked for the R15
-- defaults, so this table is how an R6 body recognises "these are not mine".
local R15_DEFAULT_IDS: {[string]: boolean} = {}
for _, ids: {string} in pairs(DEFAULT_ANIMATION_IDS) do
    for _, id: string in ipairs(ids) do
        R15_DEFAULT_IDS[id] = true
    end
end
-- The mirror image: every id the R6 default set owns. R6 clips are the only
-- clips an R6 body may play, and R6 ids never belong in an R15 slot.
local R6_DEFAULT_IDS: {[string]: boolean} = {}
for _, ids: {string} in pairs(DEFAULT_ANIMATION_IDS_R6) do
    for _, id: string in ipairs(ids) do
        R6_DEFAULT_IDS[id] = true
    end
end
local SCALE_FIELDS: {string} = {
    "HeightScale",
    "WidthScale",
    "DepthScale",
    "HeadScale",
    "BodyTypeScale",
    "ProportionScale",
}
local BODY_PARTS: {[string]: boolean} = {
    Head = true,
    Torso = true,
    UpperTorso = true,
    LowerTorso = true,
    LeftArm = true,
    RightArm = true,
    LeftLeg = true,
    RightLeg = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
}
local MOVEMENT_ANIMATIONS: {{descriptionField: string, scriptCategory: string}} = {
    {descriptionField = "IdleAnimation", scriptCategory = "idle"},
    {descriptionField = "WalkAnimation", scriptCategory = "walk"},
    {descriptionField = "RunAnimation", scriptCategory = "run"},
    {descriptionField = "JumpAnimation", scriptCategory = "jump"},
    {descriptionField = "ClimbAnimation", scriptCategory = "climb"},
    {descriptionField = "FallAnimation", scriptCategory = "fall"},
    {descriptionField = "SwimAnimation", scriptCategory = "swim"},
    {descriptionField = "SwimIdleAnimation", scriptCategory = "swimidle"},
    {descriptionField = "MoodAnimation", scriptCategory = "mood"},
}

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local Players: Players = host.Players or (game :: any):GetService("Players")
    local LocalPlayer: Player = host.LocalPlayer or Players.LocalPlayer

    local cloned = setmetatable({}, {__mode = "k"}) :: {[Instance]: boolean}
    local disguisedItems = setmetatable({}, {__mode = "k"}) :: {[Instance]: boolean}
    local snapshot: AppearanceSnapshot? = nil
    local filteredCharacter: Model? = nil
    local filterConnection: RBXScriptConnection? = nil
    local generation: number = 0
    local restoring: boolean = false
    local emotesAppliedToHumanoid: boolean = false
    local animationOverrideApplied: boolean = false
    -- One notice per target: a pack authored for another rig says so once
    -- instead of on every re-apply.
    local foreignPackNotified: boolean = false
    -- Slots the last apply actually wrote; the status line repeats it.
    local lastAppliedSlotCount: number = 0
    local lastDroppedSlotCount: number = 0
    -- Forward declarations. The write path runs before the settle step is
    -- defined, and Lua resolves names at definition time: without these the
    -- calls would silently become globals.
    local stopPoseMirror: () -> () = function(): () end
    local playingAnimationTracks: (Humanoid?) -> {AnimationTrack} =
        function(): {AnimationTrack}
            return {}
        end
    -- Everything the target user exposes is cached the moment the avatar
    -- description is fetched: the movement animation slots and the emotes.
    -- Character mode applies the avatar but keeps this cache loaded, so the two
    -- toggles work instantly instead of fetching the avatar again.
    type TargetCache = {
        userId: number,
        slots: {[string]: any},
        emotes: any,
        equippedEmotes: any,
        -- "R6"/"R15" when the target is in the server, nil when they are only
        -- known by id. A description never says which rig its clips were
        -- authored for, so this is the only source for that fact.
        rig: string?,
    }
    local targetCache: TargetCache? = nil

    -- The checkbox restores its saved state from configData without calling
    -- back, so the module settings must be read from the same place. Without
    -- this, a saved OFF check would still apply the target's data.
    local function savedToggle(name: string, fallback: boolean): boolean
        local store: any = host.configData
        local states: any = store and store.states
        if type(states) ~= "table" then
            return fallback
        end
        local saved: any = states["Universal.Disguise." .. name:gsub("%W", "")]
        if type(saved) == "boolean" then
            return saved
        end
        return fallback
    end

    local settings = {
        mode = "Character",
        animationSpeed = 1,
        id = tostring(DEFAULT_USER_ID),
        useTargetMovementAnimations = savedToggle(
            "Use target movement animations",
            true
        ),
        showTargetEmotes = savedToggle("Show target emotes", true),
        showAdvanced = false,
        -- Slots of a bundle resolved by id at runtime (any official or
        -- UGC pack), kept for the session so mode switches and the
        -- movement toggle reuse them without resolving again.
        customPackSlots = (nil :: any),
        customPackName = (nil :: any),
        -- Per-slot clips picked from bundles under Show Advanced:
        -- scriptCategory -> rbxassetid string.
        customSlotIds = ({} :: any),
    }

    local function status(message: string): ()
        if activeCard then activeCard:SetStatus(message) end
    end
    local function notify(message: string): ()
        pcall(print, "[Wurst:Disguise] " .. message)
        if activeCard then pcall(activeCard.Notify, activeCard, message) end
    end

    local function isAppearanceItem(obj: Instance): boolean
        return obj:IsA("Accessory")
            or obj:IsA("ShirtGraphic")
            or obj:IsA("Shirt")
            or obj:IsA("Pants")
            or obj:IsA("BodyColors")
            or ((obj:IsA("Decal") or obj:IsA("Texture"))
                and string.lower(obj.Name) == "face")
    end

    local function isInsideCharacter(obj: Instance, character: Model): boolean
        local ok: boolean, result: any = pcall(function()
            return obj:IsDescendantOf(character)
        end)
        return ok and result == true
    end

    local function rebindAccessory(character: Model, accessory: Accessory): ()
        for _, descendant: Instance in ipairs(accessory:GetDescendants()) do
            if descendant:IsA("Weld") and descendant.Part1 then
                local part: Instance? = character:FindFirstChild(
                    descendant.Part1.Name
                )
                if part and part:IsA("BasePart") then
                    descendant.Part1 = part
                end
            elseif descendant:IsA("RigidConstraint")
                and descendant.Attachment1 then
                local attachment: Instance? = character:FindFirstChild(
                    descendant.Attachment1.Name,
                    true
                )
                if attachment and attachment:IsA("Attachment") then
                    descendant.Attachment1 = attachment
                end
            end
        end
    end

    local function destroySnapshot(): ()
        local current: AppearanceSnapshot? = snapshot
        snapshot = nil
        emotesAppliedToHumanoid = false
        animationOverrideApplied = false
        if current then
            for _, entry: AppearanceTemplate in ipairs(current.items) do
                pcall(entry.object.Destroy, entry.object)
            end
        end
    end

    local function getAppliedDescription(humanoid: Humanoid): (any?, boolean)
        local child: HumanoidDescription? = humanoid:FindFirstChildOfClass(
            "HumanoidDescription"
        ) :: HumanoidDescription?
        if not child then
            local waitOk: boolean, waited: any = pcall(function()
                return humanoid:WaitForChild("HumanoidDescription", 2)
            end)
            if waitOk and waited and waited:IsA("HumanoidDescription") then
                child = waited :: HumanoidDescription
            end
        end
        if child then
            return child, false
        end
        local ok: boolean, result: any = pcall(function()
            return humanoid:GetAppliedDescription()
        end)
        if ok and result then
            return result, true
        end
        return nil, false
    end

    local function cloneTable(value: any): any
        if type(value) ~= "table" then
            return value
        end
        local copy: any = {}
        for key: any, entry: any in pairs(value) do
            copy[key] = if type(entry) == "table" then table.clone(entry) else entry
        end
        return copy
    end

    local function readDescriptionEmotes(description: any): (any?, any?)
        local ok: boolean, emotes: any, equipped: any = pcall(function()
            return description:GetEmotes(), description:GetEquippedEmotes()
        end)
        if not ok or type(emotes) ~= "table" or type(equipped) ~= "table" then
            return nil, nil
        end
        return cloneTable(emotes), cloneTable(equipped)
    end

    local function applyDescriptionToHumanoid(
        humanoid: Humanoid,
        description: any
    ): (boolean, string?)
        local humanoidObject: any = humanoid
        local lastError: string = "ApplyDescription is unavailable."
        for _, methodName: string in ipairs({
            "ApplyDescriptionResetAsync",
            "ApplyDescriptionAsync",
            "ApplyDescriptionReset",
            "ApplyDescription",
        }) do
            local method: any = humanoidObject[methodName]
            if type(method) == "function" then
                local ok: boolean, result: any = pcall(
                    method,
                    humanoidObject,
                    description
                )
                if ok then
                    return true, nil
                end
                lastError = tostring(result)
            end
        end
        return false, lastError
    end

    local function setHumanoidEmotes(
        humanoid: Humanoid,
        emotes: any,
        equippedEmotes: any
    ): (boolean, string?)
        if type(emotes) ~= "table" or type(equippedEmotes) ~= "table" then
            return false, "The avatar description did not expose emote data."
        end
        local description: any, isTemporary: boolean = getAppliedDescription(humanoid)
        if not description then
            return false, "Could not read the current HumanoidDescription."
        end
        local setOk: boolean, setError: any = pcall(function()
            description:SetEmotes(cloneTable(emotes))
            description:SetEquippedEmotes(cloneTable(equippedEmotes))
        end)
        if not setOk then
            if isTemporary then
                pcall(description.Destroy, description)
            end
            return false, tostring(setError)
        end
        if not isTemporary then

            return true, nil
        end

        local applied: boolean, applyError: string? =
            applyDescriptionToHumanoid(humanoid, description)
        pcall(description.Destroy, description)
        return applied, applyError
    end

    local function captureSnapshot(
        character: Model,
        humanoid: Humanoid
    ): AppearanceSnapshot
        local items: {AppearanceTemplate} = {}
        local meshParts: {MeshTemplate} = {}
        local animations: {AnimationTemplate} = {}
        local scales: {[string]: number} = {}
        local descAnimations: {[string]: number} = {}
        local emotes: any = {}
        local equippedEmotes: any = {}

        for _, obj: Instance in ipairs(character:GetDescendants()) do
            if isAppearanceItem(obj) then
                local ok: boolean, copy: any = pcall(function()
                    return obj:Clone()
                end)
                if ok and copy then
                    copy.Parent = nil
                    table.insert(items, {
                        object = copy,
                        parent = obj.Parent,
                    })
                end
            elseif obj:IsA("MeshPart") and BODY_PARTS[obj.Name] then
                table.insert(meshParts, {
                    part = obj,
                    meshId = obj.MeshId,
                    textureId = obj.TextureID,
                })
            elseif obj:IsA("Animation") then
                local animate: Instance? = character:FindFirstChild("Animate")
                if animate and obj:IsDescendantOf(animate) then
                    table.insert(animations, {
                        animation = obj,
                        animationId = obj.AnimationId,
                    })
                end
            end
        end

        local description: any, isTemporary: boolean = getAppliedDescription(humanoid)
        if description then
            for _, field: string in ipairs(SCALE_FIELDS) do
                local ok: boolean, value: any = pcall(function()
                    return description[field]
                end)
                if ok and type(value) == "number" then
                    scales[field] = value
                end
            end
            for _, mapping in ipairs(MOVEMENT_ANIMATIONS) do
                local okField: boolean, fieldValue: any = pcall(function()
                    return description[mapping.descriptionField]
                end)
                if okField and type(fieldValue) == "number" then
                    descAnimations[mapping.descriptionField] = fieldValue
                end
            end
            local originalEmotes: any, originalEquipped: any =
                readDescriptionEmotes(description)
            if originalEmotes and originalEquipped then
                emotes = originalEmotes
                equippedEmotes = originalEquipped
            end
            if isTemporary then
                pcall(description.Destroy, description)
            end
        end

        return {
            character = character,
            items = items,
            meshParts = meshParts,
            animations = animations,
            emotes = emotes,
            equippedEmotes = equippedEmotes,
            scales = scales,
            descAnimations = descAnimations,
        }
    end

    local function ensureSnapshot(
        character: Model,
        humanoid: Humanoid
    ): AppearanceSnapshot
        if snapshot and snapshot.character == character then
            return snapshot
        end
        destroySnapshot()
        snapshot = captureSnapshot(character, humanoid)
        return snapshot
    end

    local function restartAnimateScript(animate: Instance): ()
        local scriptObject: any = animate
        local enabledOk: boolean, wasEnabled: any = pcall(function()
            return scriptObject.Enabled
        end)
        if enabledOk and type(wasEnabled) == "boolean" then
            if not wasEnabled then
                return
            end
            local disabledOk: boolean = pcall(function()
                scriptObject.Enabled = false
            end)
            if disabledOk then
                task.wait()
                pcall(function()
                    scriptObject.Enabled = wasEnabled
                end)
                task.wait()
                return
            end
        end

        local disabledOk: boolean, wasDisabled: any = pcall(function()
            return scriptObject.Disabled
        end)
        if disabledOk and type(wasDisabled) == "boolean" then
            local pauseOk: boolean = pcall(function()
                scriptObject.Disabled = true
            end)
            if pauseOk then
                task.wait()
                pcall(function()
                    scriptObject.Disabled = wasDisabled
                end)
                task.wait()
            end
        end
    end


    -- Used when "Use target movement animations" is turned off: restore only
    -- the Animate slots, leaving the current appearance/emotes untouched.
    local function restoreMovementAnimationsOnly(
        character: Model,
        humanoid: Humanoid?
    ): ()
        stopPoseMirror()
        local current: AppearanceSnapshot? = snapshot
        if not current or current.character ~= character
            or not animationOverrideApplied then
            return
        end
        -- Undo a description-route apply on the description itself,
        -- or the engine keeps serving the foreign clips no matter
        -- what the Animate slots say.
        if humanoid and current.descAnimations then
            local description: any, isTemporary: boolean =
                getAppliedDescription(humanoid)
            if description then
                local working: any = description
                if not isTemporary then
                    local cloneOk: boolean, clone: any = pcall(function(): any
                        return description:Clone()
                    end)
                    if cloneOk and clone then
                        working = clone
                        isTemporary = true
                    end
                end
                pcall(function(): ()
                    for field: string, asset: number in pairs(
                        current.descAnimations
                    ) do
                        working[field] = asset
                    end
                end)
                applyDescriptionToHumanoid(humanoid, working)
                if isTemporary then
                    pcall(function(): ()
                        working:Destroy()
                    end)
                end
            end
        end
        for _, entry: AnimationTemplate in ipairs(current.animations) do
            if isInsideCharacter(entry.animation, character) then
                pcall(function()
                    entry.animation.AnimationId = entry.animationId
                end)
            end
        end
        animationOverrideApplied = false
        local animate: Instance? = character:FindFirstChild("Animate")
        if not animate then
            return
        end
        if humanoid then
            local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
            if animator then
                local tracksOk: boolean, tracks: any = pcall(function()
                    return animator:GetPlayingAnimationTracks()
                end)
                if tracksOk and type(tracks) == "table" then
                    for _, track: AnimationTrack in ipairs(tracks) do
                        pcall(track.Stop, track)
                    end
                end
            end
        end
        restartAnimateScript(animate)
    end

    -- HumanoidDescription already stores the target's animation asset IDs
    -- (rbxassetid://numbers). Assigning them directly is instant and does not
    -- depend on game:GetObjects / InsertService, which are Studio or server
    -- only and are the reason the old button could hang on "Downloading...".
    local function animationIdFromValue(value: any): string?
        local number: number? = nil
        if type(value) == "number" and value > 0 then
            number = value
        elseif type(value) == "string" then
            local matched: string? = string.match(value, "%d+")
            if matched then
                number = tonumber(matched)
            end
        end
        if not number or number <= 0 then
            return nil
        end
        return "rbxassetid://" .. tostring(math.floor(number))
    end

    local function animationSlotsFromDescription(description: any): {[string]: any}
        local slots: {[string]: string} = {}
        for _, mapping in ipairs(MOVEMENT_ANIMATIONS) do
            local readOk: boolean, value: any = pcall(function()
                return description[mapping.descriptionField]
            end)
            local assetId: any = if readOk then value else nil
            local chosenId: string? = animationIdFromValue(assetId)
            if chosenId then
                slots[mapping.scriptCategory] = chosenId
            end
        end
        return slots
    end

    -- Which default set fits the body we are actually driving. An R15 table on
    -- an R6 rig is the failure mode behind the frozen avatar: the clips load
    -- but nothing plays, so the character keeps its rest pose forever.
    local function rigDefaultSlots(humanoid: Humanoid?): {[string]: any}
        local rig: any = nil
        if humanoid then
            pcall(function(): ()
                rig = (humanoid :: any).RigType
            end)
        end
        if rig == Enum.HumanoidRigType.R6 then
            return DEFAULT_ANIMATION_IDS_R6
        end
        return DEFAULT_ANIMATION_IDS
    end

    local function rigName(humanoid: Humanoid?): string?
        local rig: any = nil
        if humanoid then
            pcall(function(): ()
                rig = (humanoid :: any).RigType
            end)
        end
        if rig == Enum.HumanoidRigType.R6 then
            return "R6"
        end
        if rig == Enum.HumanoidRigType.R15 then
            return "R15"
        end
        return nil
    end

    local function belongsToDefaultSet(value: any, set: {[string]: boolean}): boolean
        local function owns(entry: any): boolean
            if type(entry) == "number" then
                entry = tostring(math.floor(entry))
            end
            if type(entry) ~= "string" then
                return false
            end
            local digits: string? = string.match(entry, "%d+")
            return digits ~= nil and set[digits] == true
        end
        if type(value) == "table" then
            if #value == 0 then
                return false
            end
            for _, entry: any in ipairs(value) do
                if not owns(entry) then
                    return false
                end
            end
            return true
        end
        return owns(value)
    end

    local function belongsToR15Defaults(value: any): boolean
        return belongsToDefaultSet(value, R15_DEFAULT_IDS)
    end

    local function belongsToR6Defaults(value: any): boolean
        return belongsToDefaultSet(value, R6_DEFAULT_IDS)
    end

    -- Gaps are filled with the set that matches the rig; a slot that only
    -- holds R15 default ids on an R6 body is treated as a gap.
    --
    -- A pack description never says which rig its clips were authored for, and
    -- every pack sold since 2016 is R15. An R6 body that receives those ids is
    -- handed to the engine's legacy retargeting, which bends the limbs and
    -- sinks the torso instead of refusing the clip: that is the broken pose in
    -- the report, and it only shows up with a non-default pack, because the
    -- default pack resolves to ids the body already plays. The target's rig is
    -- no defence: in an R6 game the target is R6 too, and their description
    -- still hands out R15 clips. The rule is therefore about the clips, not
    -- about the target: an R6 body only accepts the R6 set, and an R15 body
    -- refuses the R6 set. The second return value counts the pack slots that
    -- were dropped for being foreign, so the menu can say it instead of
    -- showing a mangled avatar in silence.
    local function resolvedAnimationSlots(
        slots: {[string]: any},
        humanoid: Humanoid?,
        _targetRig: string?
    ): ({[string]: any}, number)
        local defaults: {[string]: any} = rigDefaultSlots(humanoid)
        local isR6: boolean = defaults == DEFAULT_ANIMATION_IDS_R6
        local dropped: number = 0
        local resolved: {[string]: any} = {}
        for category: string, value: any in pairs(slots) do
            -- Only the body's own rig may be written into its Animate slots.
            -- On R6 that means the R6 default ids; on R15, anything that is
            -- not an R6 default id (pack clips included).
            local owned: boolean
            if isR6 then
                owned = belongsToR6Defaults(value)
            else
                owned = not belongsToR6Defaults(value)
            end
            if owned then
                resolved[category] = value
            elseif not belongsToR15Defaults(value) then
                -- Dropping the R15 defaults is not a loss: they equal the set
                -- the R6 body already had, which is why the default pack looks
                -- fine. Only real pack clips are worth telling the user about.
                dropped += 1
            end
        end
        for category: string, ids: any in pairs(defaults) do
            if resolved[category] == nil then
                resolved[category] = ids
            end
        end
        return resolved, dropped
    end

    local function writeAnimationSlots(
        animate: Instance,
        slots: {[string]: any}
    ): number
        local changedCount: number = 0
        for _, mapping in ipairs(MOVEMENT_ANIMATIONS) do
            local chosen: any = slots[mapping.scriptCategory]
            -- One ID for the whole category, or a list: idle has up to three
            -- variants and Roblox plays them in order, so a default set keeps
            -- all three instead of repeating the first.
            local ids: {string} = {}
            if type(chosen) == "table" then
                for _, value: any in ipairs(chosen) do
                    local id: string? = animationIdFromValue(value)
                    if id then table.insert(ids, id) end
                end
            else
                local id: string? = animationIdFromValue(chosen)
                if id then table.insert(ids, id) end
            end
            local category: Instance? = animate:FindFirstChild(mapping.scriptCategory)
            if #ids > 0 and category then
                local targets: {Animation} = {}
                if category:IsA("Animation") then
                    table.insert(targets, category)
                end
                for _, descendant: Instance in ipairs(category:GetDescendants()) do
                    if descendant:IsA("Animation") then
                        table.insert(targets, descendant)
                    end
                end
                for index: number, animation: Animation in ipairs(targets) do
                    local chosenId: string = #ids == 1
                        and ids[1]
                        or ids[math.min(index, #ids)]
                    if animation.AnimationId ~= chosenId then
                        local changed: boolean = pcall(function()
                            animation.AnimationId = chosenId
                        end)
                        if changed then
                            changedCount += 1
                        end
                    end
                end
            end
        end

        return changedCount
    end

    -- Write the resolved slots into the humanoid's DESCRIPTION (on a
    -- clone, then applied) and return how many fields were set. Kept
    -- as the fallback when the Animate slots cannot be written at all;
    -- as the primary route (v94) it reported success while the running
    -- script kept playing the previous pack.
    local function applySlotsViaDescription(
        humanoid: Humanoid,
        resolved: {[string]: any}
    ): number
        local description: any, isTemporary: boolean =
            getAppliedDescription(humanoid)
        if not description then
            return 0
        end
        local working: any = description
        if not isTemporary then
            local cloneOk: boolean, clone: any = pcall(function(): any
                return description:Clone()
            end)
            if cloneOk and clone then
                working = clone
                isTemporary = true
            end
        end
        local setCount: number = 0
        local setOk: boolean = pcall(function(): ()
            for _, mapping in ipairs(MOVEMENT_ANIMATIONS) do
                local chosen: any = resolved[mapping.scriptCategory]
                if type(chosen) == "table" then
                    chosen = chosen[1]
                end
                local digits: string? = chosen
                    and string.match(tostring(chosen), "%d+")
                    or nil
                local asset: number? = digits and tonumber(digits) or nil
                if asset and asset > 0 then
                    working[mapping.descriptionField] = asset
                    setCount += 1
                end
            end
        end)
        if not setOk or setCount == 0 then
            if isTemporary then
                pcall(function(): ()
                    working:Destroy()
                end)
            end
            return 0
        end
        local applied: boolean = applyDescriptionToHumanoid(
            humanoid,
            working
        )
        if isTemporary then
            pcall(function(): ()
                working:Destroy()
            end)
        end
        return applied and setCount or 0
    end

    -- Clip sanitization lives after refreshMeshPartSnapshot (it must
    -- wait on clip loads; the avatar-copy helpers above may not).
    -- Forward-declared here so applyAnimationSlots can call it.
    local sanitizedSlots: (
        humanoid: Humanoid,
        resolved: {[string]: any}
    ) -> ({[string]: any}, number) =
        function(_humanoid: Humanoid, resolved: {[string]: any}): ({[string]: any}, number)
            return resolved, 0
        end
    local invalidClipNotified: boolean = false

    -- What every caller uses: the target's clips are resolved against the rig
    -- and written into the Animate slots. The result is verified by
    -- settleMovementAnimations right after, which owns every wait and every
    -- fallback: copying an avatar must never block on an animation check.
    local function applyAnimationSlots(
        character: Model,
        humanoid: Humanoid,
        slots: {[string]: any},
        targetRig: string?
    ): number
        local animate: Instance? = character:FindFirstChild("Animate")
        if not animate then
            return 0
        end
        local resolved: {[string]: any}, dropped: number =
            resolvedAnimationSlots(slots, humanoid, targetRig)
        -- The status reports this: "0 slots" on its own looks like a failure
        -- even when the four foreign clips were refused on purpose.
        lastDroppedSlotCount = dropped
        if dropped > 0 and not foreignPackNotified then
            foreignPackNotified = true
            notify(
                "That pack's clips are not "
                    .. (rigName(humanoid) or "your rig")
                    .. " clips; your own animations stay."
            )
        end
        -- Nothing the engine refuses here may reach the description
        -- or the slots: sanitized first, rig defaults in their place.
        local sanitized: {[string]: any}, replacedClips: number =
            sanitizedSlots(humanoid, resolved)
        resolved = sanitized
        lastResolvedSlots = resolved
        if replacedClips > 0 and not invalidClipNotified then
            invalidClipNotified = true
            notify(
                tostring(replacedClips)
                    .. " of those animation slots cannot be used in "
                    .. "this game (the engine refuses the clips); "
                    .. "your rig's own clips fill them instead."
            )
        end
        -- The Animate slots are the write that demonstrably retargets
        -- the running script (packs switched correctly until v94).
        -- The description route stays as fallback for builds whose
        -- slots cannot be written: it reports success without changing
        -- what the script plays here, which is exactly the reported
        -- "I pick Mage and Ninja keeps playing" desync.
        local changedCount: number = writeAnimationSlots(animate, resolved)
        if changedCount == 0 then
            changedCount = applySlotsViaDescription(humanoid, resolved)
        end
        if changedCount == 0 then
            return 0
        end
        animationOverrideApplied = true
        for _, track: AnimationTrack in ipairs(playingAnimationTracks(humanoid)) do
            pcall(function(): ()
                track:Stop()
            end)
        end
        restartAnimateScript(animate)
        return changedCount
    end

    -- Runs as soon as a description is fetched, before anything is applied:
    -- this is the "load everything in the background" step. It only reads the
    -- description, so it can never touch or roll back the visible appearance.
    -- The target's own rig, when they are in the server. A description carries
    -- clip ids but never the rig those clips were authored for.
    local function targetRigFor(userId: number): string?
        local ok: boolean, player: any = pcall(function(): any
            return Players:GetPlayerByUserId(userId)
        end)
        if not ok or not player then
            return nil
        end
        local character: any = player.Character
        local humanoid: any = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return nil
        end
        return rigName(humanoid)
    end

    local function cacheTarget(userId: number, description: any): ()
        local emotes: any, equippedEmotes: any = readDescriptionEmotes(description)
        -- Only what the target actually chose. A 0 in a description means
        -- "use Roblox's default", and which default that is depends on OUR rig,
        -- so the gap is filled at apply time, never here.
        local slots: {[string]: any} = animationSlotsFromDescription(description)
        foreignPackNotified = false
        targetCache = {
            userId = userId,
            slots = slots,
            emotes = emotes,
            equippedEmotes = equippedEmotes,
            rig = targetRigFor(userId),
        }
    end

    local function refreshMeshPartSnapshot(
        character: Model,
        current: AppearanceSnapshot
    ): ()
        local originalByName: {[string]: {meshId: string, textureId: string}} = {}
        for _, entry: MeshTemplate in ipairs(current.meshParts) do
            originalByName[entry.part.Name] = {
                meshId = entry.meshId,
                textureId = entry.textureId,
            }
        end

        local refreshed: {MeshTemplate} = {}
        for _, obj: Instance in ipairs(character:GetDescendants()) do
            if obj:IsA("MeshPart") and BODY_PARTS[obj.Name] then
                local original: {meshId: string, textureId: string}? =
                    originalByName[obj.Name]
                table.insert(refreshed, {
                    part = obj,
                    meshId = original and original.meshId or obj.MeshId,
                    textureId = original and original.textureId or obj.TextureID,
                })
            end
        end
        if #refreshed > 0 then
            current.meshParts = refreshed
        end
    end

    -- Runs after the ids are written. The Animate script is restarted by the
    -- write itself, but a restart does not guarantee a playing track: the
    -- classic script only replays the idle loop from a Humanoid.Running event,
    -- and a body standing still never fires one. That is the frozen pose in
    -- the report. Here the body is checked, the idle is bridged when needed,
    -- and a rig that cannot play the target's clips gets its own set back
    -- instead of keeping a still avatar.
    playingAnimationTracks = function(humanoid: Humanoid?): {AnimationTrack}
        local playing: {AnimationTrack} = {}
        if not humanoid then
            return playing
        end
        local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            return playing
        end
        local ok: boolean, tracks: any = pcall(function(): any
            return animator:GetPlayingAnimationTracks()
        end)
        if not ok or type(tracks) ~= "table" then
            return playing
        end
        for _, track: AnimationTrack in ipairs(tracks) do
            local isPlaying: boolean = false
            pcall(function(): ()
                isPlaying = track.IsPlaying == true
            end)
            if isPlaying then
                table.insert(playing, track)
            end
        end
        return playing
    end

    -- The Animator writes every pose into Motor6D.Transform. A clip built for
    -- the OTHER rig never writes a joint: Roblox still hands back a track that
    -- reports IsPlaying, so `#playingAnimationTracks > 0` is not proof that the
    -- body moves. That gap is the frozen avatar reported with every target
    -- except the default one: a bought R15 pack on an R6 body "plays" forever
    -- without moving a single limb. Reading the joints is the only client-side
    -- way to tell a body that animates from one stuck in its rest pose.
    local function poseSignature(humanoid: Humanoid?): number?
        local character: Instance? = humanoid and humanoid.Parent
        if not character then
            return nil
        end
        local joints: number = 0
        local signature: number = 0
        for _, object: Instance in ipairs(character:GetDescendants()) do
            if object:IsA("Motor6D")
                or object:IsA("AnimationConstraint") then
                local ok: boolean, transform: CFrame = pcall(function(): CFrame
                    return (object :: any).Transform
                end)
                if ok and transform then
                    joints += 1
                    signature += transform.X * 13.17 + transform.Y * 7.31
                        + transform.Z * 3.77 + transform.R00 * 29.1
                        + transform.R11 * 17.3 + transform.R22 * 11.9
                end
            end
        end
        if joints == 0 then
            -- A rig we cannot read is not a rig we may accuse of being frozen.
            return nil
        end
        return signature
    end

    -- A clip holding a pose (the floating/hover idles UGC packs ship)
    -- barely moves a joint over time, but it still WRITES the joints:
    -- their Transforms sit away from identity. A clip built for the
    -- other rig never writes a joint at all, so its Transforms stay at
    -- identity forever. That is how a held pose counts as animation
    -- while a frozen wrong-rig clip still does not.
    local function poseDriven(humanoid: Humanoid?): boolean
        local character: Instance? = humanoid and humanoid.Parent
        if not character then
            return false
        end
        for _, object: Instance in ipairs(character:GetDescendants()) do
            if object:IsA("Motor6D")
                or object:IsA("AnimationConstraint") then
                local ok: boolean, transform: CFrame = pcall(function(): CFrame
                    return (object :: any).Transform
                end)
                if ok and transform then
                    if math.abs(transform.X) > 1e-4
                        or math.abs(transform.Y) > 1e-4
                        or math.abs(transform.Z) > 1e-4
                        or math.abs(transform.R00 - 1) > 1e-3
                        or math.abs(transform.R11 - 1) > 1e-3
                        or math.abs(transform.R22 - 1) > 1e-3 then
                        return true
                    end
                end
            end
        end
        return false
    end

    -- nil means "cannot tell" (no joints exposed), and callers must keep the
    -- old behaviour in that case. A fixed step count instead of a wall clock
    -- keeps the check from ever spinning when the scheduler is stubbed.
    local function poseMoves(humanoid: Humanoid?, seconds: number): boolean?
        local before: number? = poseSignature(humanoid)
        if before == nil then
            return nil
        end
        local steps: number = 5
        for _ = 1, steps do
            task.wait(seconds / steps)
            local after: number? = poseSignature(humanoid)
            if after == nil then
                return nil
            end
            if math.abs(after - before) > 1e-3 then
                return true
            end
        end
        return false
    end

    -- Clears the tracks, restarts the script and proves the body moves again.
    -- Returns false only when nothing plays, which is the signal to fall back
    -- to the rig's own clips instead of leaving a frozen character.
    local function activateAnimationOverride(
        character: Model,
        humanoid: Humanoid,
        animate: Instance
    ): boolean
        for _, track: AnimationTrack in ipairs(playingAnimationTracks(humanoid)) do
            pcall(function(): ()
                track:Stop()
            end)
        end
        restartAnimateScript(animate)
        task.wait(0.1)
        return #playingAnimationTracks(humanoid) > 0
    end

    -- Session cache of clip verdicts, and its one-time notice.
    -- A verdict is computed ONCE per id and never inside the Animate
    -- script's retry loop.
    local clipValidity: {[string]: boolean} = {}

    -- May the engine play this clip in this place? v95 probed by
    -- loading the clip, but the probe itself printed "Failed to load
    -- animation with sanitized ID ..." for every refused clip: quieter
    -- than the old retry spam, still noise the user has to read. This
    -- verdict never loads anything into an Animator:
    --   1. Catalog metadata condemns what is certainly unusable -- a
    --      deleted/private asset, or an id that is not an Animation at
    --      all (a bundle id pasted where a clip belongs).
    --   (A fetch probe was tried and removed: ContentProvider cannot
    --      download other creators' animation assets at all, so it
    --      condemned every foreign clip -- including packs already
    --      playing on screen. Metadata is the only honest judge.)
    -- Anything a probe cannot judge acquits: an unreadable answer must
    -- never punish a working pack.
    local function clipLoads(_humanoid: Humanoid, id: string): boolean
        local cached: boolean? = clipValidity[id]
        if cached ~= nil then
            return cached
        end
        local valid: boolean = true
        -- The rigs' own sets always play; skip the probes entirely.
        if belongsToR15Defaults(id) or belongsToR6Defaults(id) then
            clipValidity[id] = true
            return true
        end
        local digits: string? = string.match(id, "%d+")
        local assetId: number? = digits and tonumber(digits) or nil
        if assetId then
            local service: any = nil
            pcall(function(): ()
                service = (host :: any).MarketplaceService
                    or (game :: any):GetService("MarketplaceService")
            end)
            if service and type(service.GetProductInfo) == "function" then
                local infoOk: boolean, info: any = pcall(function(): any
                    return service:GetProductInfo(
                        assetId,
                        Enum.InfoType.Asset
                    )
                end)
                if not infoOk or type(info) ~= "table" then
                    -- Gone or private: every load would be refused too.
                    valid = false
                else
                    local assetType: any = info.AssetTypeId
                    if assetType ~= nil then
                        local isAnimation: boolean = false
                        pcall(function(): ()
                            if type(assetType) == "number" then
                                isAnimation = assetType
                                    == Enum.AssetType.Animation.Value
                            else
                                isAnimation = assetType
                                    == Enum.AssetType.Animation
                            end
                        end)
                        if not isAnimation then
                            valid = false
                        end
                    end
                end
            end
        end
        clipValidity[id] = valid
        return valid
    end

    -- Drop every clip the engine refuses here and fill the slot with
    -- the rig's own set BEFORE anything reaches the description or the
    -- Animate slots. An invalid id inside the Animate script is the
    -- console spam and the 64-track pile-up: the script retries the
    -- load forever and every retry is another track.
    sanitizedSlots = function(
        humanoid: Humanoid,
        resolved: {[string]: any}
    ): ({[string]: any}, number)
        local defaults: {[string]: any} = rigDefaultSlots(humanoid)
        local out: {[string]: any} = {}
        local replaced: number = 0
        for category: string, value: any in pairs(resolved) do
            local kept: {string} = {}
            local list: {any} = type(value) == "table"
                and value
                or {value}
            for _, entry: any in ipairs(list) do
                local id: string? = animationIdFromValue(entry)
                if id and clipLoads(humanoid, id) then
                    table.insert(kept, id)
                end
            end
            if #kept > 0 then
                out[category] = #kept == 1 and kept[1] or kept
            else
                replaced += 1
                out[category] = defaults[category]
            end
        end
        return out, replaced
    end


    local mirrorAllowed: boolean = false
    local lastResolvedSlots: {[string]: any}? = nil

    local function settleMovementAnimations(
        character: Model,
        humanoid: Humanoid
    ): boolean
        if not animationOverrideApplied then
            return false
        end
        local animate: Instance? = character:FindFirstChild("Animate")
        if not animate then
            return false
        end
        local tracks: number = #playingAnimationTracks(humanoid)
        if tracks > 0 then
            -- The script is playing something. Only a moving pose proves it
            -- belongs to this rig.
            if poseMoves(humanoid, 0.3) ~= false then
                return true
            end
            -- A loaded clip holding a pose is still an animation: the
            -- floating/hover idles UGC packs ship barely move a joint
            -- in 0.3 s, and reverting those to the default set is
            -- exactly the "the toggle gives me no animation" report.
            if poseDriven(humanoid) then
                return true
            end
        end
        -- Description retry, the offline-capable route: the ids came
        -- from the target's HumanoidDescription (they are not in this
        -- server to be read live), and a description's animations are
        -- loaded by the avatar pipeline when it is applied. It only
        -- counts if real tracks end up playing.
        if mirrorAllowed and lastResolvedSlots then
            local viaDescription: number =
                applySlotsViaDescription(humanoid, lastResolvedSlots)
            if viaDescription > 0 then
                restartAnimateScript(animate)
                task.wait(0.15)
                if #playingAnimationTracks(humanoid) > 0
                    and (poseMoves(humanoid, 0.3) ~= false
                        or poseDriven(humanoid)) then
                    notify(
                        "The target's animations were applied through "
                            .. "their avatar description."
                    )
                    return true
                end
            end
        end

        -- Pose mirror: copy the target's joints (AnimationConstraint
        -- on this rig). startPoseMirror verifies the copy actually
        -- lands on our body before it may claim success.
        if mirrorAllowed and startPoseMirror(character, humanoid) then
            return true
        end
        local defaults: {[string]: any} = rigDefaultSlots(humanoid)
        local isR6: boolean = defaults == DEFAULT_ANIMATION_IDS_R6
        if writeAnimationSlots(animate, defaults) > 0 then
            for _, track: AnimationTrack in ipairs(
                playingAnimationTracks(humanoid)
            ) do
                pcall(function(): ()
                    track:Stop()
                end)
            end
            restartAnimateScript(animate)
            task.wait(0.1)
            if #playingAnimationTracks(humanoid) > 0
                and poseMoves(humanoid, 0.3) ~= false then
                notify(
                    "Those clips do not play on your "
                        .. (isR6 and "R6" or "R15")
                        .. " rig; your rig's own set is back."
                )
                return true
            end
        end

        restoreMovementAnimationsOnly(character, humanoid)
        notify(
            "The target's animations do not play on your rig; "
                .. "your own animations are back."
        )
        return false
    end

    -- Animation mode also accepts an animation *bundle* id (the same thing
    -- Vape's Disguise accepts). A bundle item is a catalog entry, not always
    -- a playable AnimationId, so the asset is inspected when the executor
    -- exposes GetObjects; when it does not, the item id is used directly and
    -- the status says so instead of pretending the pack was loaded.
    local function animationAssetId(itemId: any): string?
        local normalizedId: string? = animationIdFromValue(itemId)
        if not normalizedId then
            return nil
        end
        if type((game :: any).GetObjects) == "function" then
            local ok: boolean, objects: any = pcall(function(): any
                return (game :: any):GetObjects(normalizedId)
            end)
            if ok and type(objects) == "table" then
                for _, object: any in ipairs(objects) do
                    if typeof(object) == "Instance" then
                        if object:IsA("Animation") then
                            local id: string? = animationIdFromValue(object.AnimationId)
                            if id then
                                return id
                            end
                        end
                        for _, descendant: Instance in ipairs(object:GetDescendants()) do
                            if descendant:IsA("Animation") then
                                local id: string? = animationIdFromValue(descendant.AnimationId)
                                if id then
                                    return id
                                end
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    -- Which Animate slot a bundle item belongs to, from its name.
    -- Official packs name items "Ninja Run" / "Run Animation"; UGC packs
    -- name them however the creator liked ("Endless Aura Floating Pack -
    -- Idle", "hover idle", "Swim (Idle)"), so matching is by keyword
    -- with the swim-idle pair resolved before plain idle can steal it.
    local function bundleItemCategory(rawName: any): string?
        local name: string = string.lower(tostring(rawName or ""))
        local hasSwim: boolean = string.find(name, "swim", 1, true) ~= nil
        local hasIdle: boolean = string.find(name, "idle", 1, true) ~= nil
        if hasSwim and hasIdle then
            return "swimidle"
        end
        if hasIdle then
            return "idle"
        end
        if string.find(name, "walk", 1, true) then
            return "walk"
        end
        if string.find(name, "run", 1, true) then
            return "run"
        end
        if string.find(name, "jump", 1, true) then
            return "jump"
        end
        if string.find(name, "climb", 1, true) then
            return "climb"
        end
        if string.find(name, "fall", 1, true) then
            return "fall"
        end
        if hasSwim then
            return "swim"
        end
        return nil
    end

    local function slotsFromBundleItems(items: any): {[string]: any}
        local slots: {[string]: any} = {}
        if type(items) ~= "table" then
            return slots
        end
        for _, item: any in ipairs(items) do
            if type(item) == "table" then
                -- Catalog endpoints do not all use the same casing or ID
                -- field. Resolve the item itself, not merely its position
                -- in the bundle, so a full bundle pasted into Walk always
                -- contributes its Walk clip (and likewise for every slot).
                local category: string? = bundleItemCategory(
                    item.Name or item.name or item.DisplayName
                        or item.displayName or item.Type or item.type
                )
                local itemId: any = item.Id or item.id
                    or item.AssetId or item.assetId
                if category and itemId then
                    local id: string? = animationAssetId(itemId)
                        or animationIdFromValue(itemId)
                    if id then
                        -- Several items can share a slot (idle variants):
                        -- keep them all, in order, like a description does.
                        local existing: any = slots[category]
                        if type(existing) == "table" then
                            table.insert(existing, id)
                        elseif existing ~= nil then
                            slots[category] = {existing, id}
                        else
                            slots[category] = id
                        end
                    end
                end
            end
        end
        return slots
    end

    -- Any animation bundle id -> its Animate slots, whether Roblox made
    -- the pack or a UGC creator did. Two sources, in order: the
    -- MarketplaceService product info (bundle items with names), then
    -- the public catalog API for the same bundle when the executor can
    -- HttpGet it. Nothing is downloaded and nothing is hardcoded per
    -- pack, which is the only way the thousands of UGC packs can work.
    local function bundleAnimationSlots(bundleId: number): ({[string]: any}?, string?)
        local service: any = (host :: any).MarketplaceService
            or (game :: any):GetService("MarketplaceService")
        local ok: boolean, product: any = pcall(function(): any
            return service:GetProductInfo(bundleId, Enum.InfoType.Bundle)
        end)
        if ok and type(product) == "table"
            and (product.BundleType == nil
                or product.BundleType == "AvatarAnimations")
            and type(product.Items) == "table" then
            local slots: {[string]: any} = slotsFromBundleItems(product.Items)
            if next(slots) ~= nil then
                return slots, nil
            end
        end
        local httpOk: boolean, body: any = pcall(function(): any
            return (game :: any):HttpGet(
                "https://catalog.roblox.com/v1/bundles/"
                    .. tostring(math.floor(bundleId)) .. "/details"
            )
        end)
        if httpOk and type(body) == "string" then
            local httpService: any = (game :: any):GetService("HttpService")
            local decodeOk: boolean, decoded: any = pcall(function(): any
                return httpService:JSONDecode(body)
            end)
            if decodeOk and type(decoded) == "table"
                and type(decoded.items) == "table" then
                local slots: {[string]: any} =
                    slotsFromBundleItems(decoded.items)
                if next(slots) ~= nil then
                    return slots, nil
                end
            end
        end
        if ok and type(product) == "table"
            and product.BundleType ~= nil
            and product.BundleType ~= "AvatarAnimations" then
            return nil, "That bundle is not an animation pack."
        end
        return nil, "That ID is not a user and no animation pack items were found for it."
    end


    -- The target's REAL slot ids, read from their own Animate script
    -- while they are in this server. A description is a catalog
    -- snapshot; the script riding their body holds the ids the engine
    -- actually loaded for them, which are the ones that play here
    -- (Probe 1 measured exactly those loading on our own Animator).
    local function targetAnimateSlots(userId: number): {[string]: any}?
        local player: any = nil
        pcall(function(): ()
            player = Players:GetPlayerByUserId(userId)
        end)
        local targetCharacter: any = player and player.Character
        local animate: any = targetCharacter
            and targetCharacter:FindFirstChild("Animate")
        if not animate then
            return nil
        end
        local slots: {[string]: any} = {}
        for _, mapping in ipairs(MOVEMENT_ANIMATIONS) do
            local container: any =
                animate:FindFirstChild(mapping.scriptCategory)
            local animation: any = nil
            if container then
                if container:IsA("Animation") then
                    animation = container
                else
                    for _, descendant: any in ipairs(
                        container:GetDescendants()
                    ) do
                        if descendant:IsA("Animation") then
                            animation = descendant
                            break
                        end
                    end
                end
            end
            if animation then
                local id: string? =
                    animationIdFromValue(animation.AnimationId)
                if id then
                    slots[mapping.scriptCategory] = id
                end
            end
        end
        if next(slots) == nil then
            return nil
        end
        return slots
    end

    -- Applies what was already cached for the current target. No fetch and no
    -- clone: turning a toggle back on is immediate.
    local function applyCachedMovementAnimations(
        character: Model,
        humanoid: Humanoid
    ): number
        local cached: TargetCache? = targetCache
        if not cached then
            return 0
        end
        local slots: {[string]: any} =
            targetAnimateSlots(cached.userId) or cached.slots
        local changedCount: number = applyAnimationSlots(
            character,
            humanoid,
            slots,
            cached.rig
        )
        -- Zero writes do not mean the body is fine: the ids may already be
        -- the frozen set from a previous apply, and re-selecting the same
        -- target has to settle it again instead of trusting the old state.
        if changedCount > 0 or animationOverrideApplied then
            mirrorAllowed = true
            settleMovementAnimations(character, humanoid)
            mirrorAllowed = false
        end
        return changedCount
    end

    -- Advanced packs use the same resolved animation path as a target's
    -- clips. Empty slots still fall back to the current rig's own set.
    local function selectedPackSlots(): {[string]: any}?
        return settings.customPackSlots
    end

    local function packDisplayName(): string
        return settings.customPackName or "Custom"
    end

    local function applyAnimationPack(
        character: Model,
        humanoid: Humanoid
    ): number
        stopPoseMirror()
        local slots: {[string]: any}? = selectedPackSlots()
        if not slots then
            return 0
        end
        local changedCount: number = applyAnimationSlots(
            character,
            humanoid,
            slots,
            nil
        )
        if changedCount > 0 or animationOverrideApplied then
            settleMovementAnimations(character, humanoid)
        end
        return changedCount
    end

    local function applyCachedEmotes(
        character: Model,
        humanoid: Humanoid
    ): boolean
        local cached: TargetCache? = targetCache
        local current: AppearanceSnapshot? = snapshot
        if not cached or not current or current.character ~= character then
            return false
        end
        if type(cached.emotes) ~= "table" or type(cached.equippedEmotes) ~= "table" then
            return false
        end
        local applied: boolean = setHumanoidEmotes(
            humanoid,
            cached.emotes,
            cached.equippedEmotes
        )
        if not applied then
            return false
        end
        emotesAppliedToHumanoid = true
        refreshMeshPartSnapshot(character, current)
        return true
    end

    -- Independent counterpart of restoreMovementAnimationsOnly: only the
    -- emotes go back to the snapshot, the avatar and the animations stay.
    local function restoreEmotesOnly(
        character: Model,
        humanoid: Humanoid?
    ): ()
        local current: AppearanceSnapshot? = snapshot
        if not humanoid or not current or current.character ~= character
            or not emotesAppliedToHumanoid then
            return
        end
        local restored: boolean = setHumanoidEmotes(
            humanoid,
            current.emotes,
            current.equippedEmotes
        )
        if restored then
            emotesAppliedToHumanoid = false
            refreshMeshPartSnapshot(character, current)
        end
    end

    local function restoreOriginalAppearance(
        character: Model,
        humanoid: Humanoid?
    ): ()
        local current: AppearanceSnapshot? = snapshot
        if not current or current.character ~= character then
            return
        end

        restoring = true
        if emotesAppliedToHumanoid and humanoid then
            local emotesRestored: boolean = setHumanoidEmotes(
                humanoid,
                current.emotes,
                current.equippedEmotes
            )
            if emotesRestored then
                emotesAppliedToHumanoid = false
                refreshMeshPartSnapshot(character, current)
            end
        end

        local removals: {Instance} = {}
        table.clear(disguisedItems)
        table.clear(cloned)
        for _, obj: Instance in ipairs(character:GetDescendants()) do
            if isAppearanceItem(obj) then
                table.insert(removals, obj)
            end
        end
        for _, obj: Instance in ipairs(removals) do
            pcall(obj.Destroy, obj)
        end

        for _, entry: MeshTemplate in ipairs(current.meshParts) do
            if isInsideCharacter(entry.part, character) then
                pcall(function()
                    entry.part.MeshId = entry.meshId
                    entry.part.TextureID = entry.textureId
                end)
            end
        end
        for _, entry: AnimationTemplate in ipairs(current.animations) do
            if isInsideCharacter(entry.animation, character) then
                pcall(function()
                    entry.animation.AnimationId = entry.animationId
                end)
            end
        end

        local restartRestoredAnimations: boolean = animationOverrideApplied
        animationOverrideApplied = false

        for _, entry: AppearanceTemplate in ipairs(current.items) do
            local ok: boolean, copy: any = pcall(function()
                return entry.object:Clone()
            end)
            if ok and copy then
                local parent: Instance = entry.parent or character
                if parent ~= character and not isInsideCharacter(parent, character) then
                    if (copy:IsA("Decal") or copy:IsA("Texture"))
                        and string.lower(copy.Name) == "face" then
                        parent = character:FindFirstChild("Head") or character
                    else
                        parent = character
                    end
                end
                if copy:IsA("Accessory") then
                    rebindAccessory(character, copy)
                end
                pcall(function()
                    copy.Parent = parent
                end)
            end
        end
        restoring = false
        if restartRestoredAnimations then
            local animate: Instance? = character:FindFirstChild("Animate")
            if animate then
                if humanoid then
                    local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
                    if animator then
                        local tracksOk: boolean, tracks: any = pcall(function()
                            return animator:GetPlayingAnimationTracks()
                        end)
                        if tracksOk and type(tracks) == "table" then
                            for _, track: AnimationTrack in ipairs(tracks) do
                                pcall(track.Stop, track)
                            end
                        end
                    end
                end
                restartAnimateScript(animate)
            end
        end
    end

    local function stopAppearanceFilter(): ()
        if filterConnection then
            pcall(filterConnection.Disconnect, filterConnection)
            filterConnection = nil
        end
        filteredCharacter = nil
    end

    local function removeUnexpectedAppearance(obj: Instance): ()
        if restoring
            or not isAppearanceItem(obj)
            or cloned[obj]
            or disguisedItems[obj]
            or not activeCard
            or not activeCard.Enabled
            or settings.mode ~= "Character" then
            return
        end
        task.defer(function(): ()
            if restoring
                or not activeCard
                or not activeCard.Enabled
                or settings.mode ~= "Character"
                or cloned[obj]
                or disguisedItems[obj] then
                return
            end
            pcall(obj.Destroy, obj)
        end)
    end

    local function installAppearanceFilter(character: Model): ()
        if filteredCharacter == character
            and filterConnection
            and filterConnection.Connected then
            return
        end
        stopAppearanceFilter()
        filteredCharacter = character
        filterConnection = character.DescendantAdded:Connect(
            removeUnexpectedAppearance
        )
        if activeCard then
            activeCard:Clean(filterConnection)
        end
    end

    local function parseId(): (number?, string?)
        local trimmed: string = tostring(settings.id)
            :gsub("^%s+", "")
            :gsub("%s+$", "")
        if trimmed == "" then
            return nil, "Enter a positive integer ID or username first."
        end
        local value: number? = tonumber(trimmed)
        if value and value > 0 and value % 1 == 0 then
            return value, nil
        end
        for _, p: Player in ipairs(Players:GetPlayers()) do
            if string.lower(p.Name) == string.lower(trimmed)
                or string.lower(p.DisplayName) == string.lower(trimmed) then
                return p.UserId, nil
            end
        end
        local ok: boolean, resolvedId: any = pcall(function()
            return Players:GetUserIdFromNameAsync(trimmed)
        end)
        if ok and type(resolvedId) == "number" and resolvedId > 0 then
            return resolvedId, nil
        end
        return nil, "Enter a positive integer ID or valid username."
    end

    local function getUserDescription(userId: number): (any?, string?)
        local playersObject: any = Players
        local asyncGetter: any = playersObject.GetHumanoidDescriptionFromUserIdAsync
        local syncGetter: any = playersObject.GetHumanoidDescriptionFromUserId
        if type(asyncGetter) == "function" then
            local ok: boolean, result: any = pcall(asyncGetter, playersObject, userId)
            if ok and result then
                return result, nil
            end
            if not ok then
                local asyncError: string = tostring(result)
                if type(syncGetter) ~= "function" then
                    return nil, asyncError
                end
            end
        end
        if type(syncGetter) == "function" then
            local ok: boolean, result: any = pcall(syncGetter, playersObject, userId)
            if ok and result then
                return result, nil
            end
            return nil, tostring(result)
        end
        return nil, "This client does not expose a HumanoidDescription lookup API."
    end

    local function stillCurrent(token: number, character: Model): boolean
        return generation == token
            and activeCard ~= nil
            and activeCard.Enabled
            and LocalPlayer.Character == character
    end

    local function setDescriptionScales(
        description: any,
        current: AppearanceSnapshot
    ): ()
        for _, field: string in ipairs(SCALE_FIELDS) do
            local value: number? = current.scales[field]
            if value ~= nil then
                pcall(function()
                    description[field] = value
                end)
            end
        end
    end

    local function copyCharacterAppearance(
        character: Model,
        clone: Model
    ): ()
        local realHead: Instance? = character:FindFirstChild("Head")
        for _, source: Instance in ipairs(clone:GetChildren()) do
            if isAppearanceItem(source) then
                cloned[source] = true
                disguisedItems[source] = true
                if source:IsA("Accessory") then
                    rebindAccessory(character, source)
                end
                source.Parent = character
            end
        end

        local targetFace: Instance? = clone:FindFirstChild("face", true)
        if targetFace and isAppearanceItem(targetFace) and realHead then
            cloned[targetFace] = true
            disguisedItems[targetFace] = true
            targetFace.Parent = realHead
        end

    end

    local function destroyInstance(instance: Instance?): ()
        if instance then
            pcall(instance.Destroy, instance)
        end
    end

    local function applyCharacterDisguise(
        token: number,
        character: Model,
        humanoid: Humanoid,
        userId: number
    ): ()
        lastDroppedSlotCount = 0
        local description: any, fetchError: string? = getUserDescription(userId)
        if not description then
            if stillCurrent(token, character) then
                notify("Could not load that avatar: " .. tostring(fetchError))
            end
            return
        end
        if not stillCurrent(token, character) then
            destroyInstance(description)
            return
        end

        -- Load the target's animations and emotes first. They stay cached even
        -- when both toggles are off, so the appearance copy below is the only thing the
        -- toggles can ever apply later without another fetch.
        cacheTarget(userId, description)
        local cached: TargetCache? = targetCache

        local current: AppearanceSnapshot = ensureSnapshot(character, humanoid)
        restoreOriginalAppearance(character, humanoid)
        setDescriptionScales(description, current)

        local oldArchivable: boolean = character.Archivable
        character.Archivable = true
        local cloneOk: boolean, cloneResult: any = pcall(function()
            return character:Clone()
        end)
        character.Archivable = oldArchivable
        if not cloneOk or not cloneResult then
            destroyInstance(description)
            notify("Could not stage the disguise character.")
            return
        end

        local clone: Model = cloneResult :: Model
        local parentOk: boolean = pcall(function()
            clone.Parent = game
        end)
        if not parentOk then
            destroyInstance(description)
            destroyInstance(clone)
            notify("Could not stage the disguise character in this client.")
            return
        end

        local cloneHumanoid: Humanoid? = clone:FindFirstChildOfClass("Humanoid")
        if not cloneHumanoid then
            destroyInstance(description)
            destroyInstance(clone)
            notify("The staged character has no Humanoid.")
            return
        end

        local applied: boolean, applyError: string? =
            applyDescriptionToHumanoid(cloneHumanoid, description)
        if not applied then
            destroyInstance(description)
            destroyInstance(clone)
            notify("Could not apply the avatar description: " .. tostring(applyError))
            return
        end
        if not stillCurrent(token, character) then
            destroyInstance(description)
            destroyInstance(clone)
            return
        end

        local emoteWarning: string? = nil
        if settings.showTargetEmotes then
            if cached and type(cached.emotes) == "table"
                and type(cached.equippedEmotes) == "table" then
                local emotesApplied: boolean, emoteError: string? = setHumanoidEmotes(
                    humanoid,
                    cached.emotes,
                    cached.equippedEmotes
                )
                if emotesApplied then
                    emotesAppliedToHumanoid = true
                    refreshMeshPartSnapshot(character, current)
                else
                    emoteWarning = tostring(emoteError)

                    local rolledBack: boolean = setHumanoidEmotes(
                        humanoid,
                        current.emotes,
                        current.equippedEmotes
                    )
                    if not rolledBack then
                        emotesAppliedToHumanoid = true
                        emoteWarning ..= " The original emotes could not be restored yet."
                    end
                end
            else
                emoteWarning = "The target avatar description did not expose emotes."
            end
        end
        if not stillCurrent(token, character) then
            if emotesAppliedToHumanoid then
                local rolledBack: boolean = setHumanoidEmotes(
                    humanoid,
                    current.emotes,
                    current.equippedEmotes
                )
                if rolledBack then
                    emotesAppliedToHumanoid = false
                end
            end
            destroyInstance(description)
            destroyInstance(clone)
            return
        end

        installAppearanceFilter(character)
        restoring = true
        local oldItems: {Instance} = {}
        for _, obj: Instance in ipairs(character:GetDescendants()) do
            if isAppearanceItem(obj) then
                table.insert(oldItems, obj)
            end
        end
        for _, obj: Instance in ipairs(oldItems) do
            pcall(obj.Destroy, obj)
        end
        restoring = false

        local copied: boolean, copyError: any = pcall(function()
            copyCharacterAppearance(character, clone)
        end)
        destroyInstance(clone)
        if not copied then
            destroyInstance(description)
            notify("The avatar was loaded, but some appearance parts could not be copied: "
                .. tostring(copyError))
            return
        end
        if not stillCurrent(token, character) then
            destroyInstance(description)
            return
        end
        activeCard:SetStatus("Character")
        if emoteWarning and settings.showTargetEmotes then
            notify("Disguise emotes could not be applied: " .. emoteWarning)
        end
        -- Movement animations are cosmetic and optional, so they run LAST and
        -- can never block or roll back the appearance copy above.
        if settings.useTargetMovementAnimations then
            local movementOk: boolean, movementResult: any = pcall(
                applyCachedMovementAnimations,
                character,
                humanoid
            )
            lastAppliedSlotCount = movementOk
                and (tonumber(movementResult) or 0)
                or 0
            if not movementOk then
                notify(
                    "The appearance was applied, but movement animations failed: "
                        .. tostring(movementResult)
                )
            end
        end
        if settings.customPackSlots ~= nil then
            local packOk: boolean, packResult: any = pcall(
                applyAnimationPack,
                character,
                humanoid
            )
            if packOk then
                lastAppliedSlotCount = tonumber(packResult) or 0
            end
        end
        destroyInstance(description)
        -- The rig and the number of slots are the two facts a report needs:
        -- "R6 · 0 slots" and "R15 · 7 slots" are different bugs.
        local applied: string = string.format(
            "%s · %s · %d slots",
            settings.mode,
            rigName(humanoid) or "rig?",
            lastAppliedSlotCount
        )
        if (lastDroppedSlotCount or 0) > 0 then
            applied ..= string.format(
                " · %d pack clips skipped",
                lastDroppedSlotCount or 0
            )
        end
        if settings.customPackSlots ~= nil then
            applied ..= " · pack " .. packDisplayName()
        end
        status(applied)
    end

    -- Animation mode: the same target user as Character mode, but only what
    -- moves on our own avatar. No clone, mesh, accessory or texture is copied:
    -- the character you already have must stay fully visible.
    local function applyAnimationDisguise(
        token: number,
        character: Model,
        humanoid: Humanoid,
        userId: number
    ): ()
        lastDroppedSlotCount = 0
        local bundleTarget: boolean = false
        local description: any, fetchError: string? = getUserDescription(userId)
        if description then
            if not stillCurrent(token, character) then
                destroyInstance(description)
                return
            end
            cacheTarget(userId, description)
        else
            -- Not a user: Animation mode also accepts an animation pack id.
            local slots: {[string]: any}?, bundleError: string? =
                bundleAnimationSlots(userId)
            if not slots then
                if stillCurrent(token, character) then
                    notify(
                        "Could not load that ID: " .. tostring(fetchError)
                            .. " " .. tostring(bundleError)
                    )
                end
                return
            end
            if not stillCurrent(token, character) then
                return
            end
            -- Keep the resolved pack in the session library: switching
            -- to Character mode (or its movement toggle) reuses these
            -- slots instead of resolving the bundle again.
            settings.customPackSlots = slots
            settings.customPackName = "Bundle " .. tostring(userId)
            bundleTarget = true
            targetCache = {
                userId = userId,
                slots = slots :: {[string]: any},
                emotes = nil,
                equippedEmotes = nil,
            }
        end
        local cached: TargetCache? = targetCache

        local current: AppearanceSnapshot = ensureSnapshot(character, humanoid)
        restoreOriginalAppearance(character, humanoid)
        stopAppearanceFilter()

        -- Animation mode is fixed: the target's emotes and movement animations
        -- always apply. Neither Character toggle exists in this mode.
        local emotesApplied: boolean = false
        if cached and type(cached.emotes) == "table"
            and type(cached.equippedEmotes) == "table" then
            local applied: boolean, emoteError: string? = setHumanoidEmotes(
                humanoid,
                cached.emotes,
                cached.equippedEmotes
            )
            if applied then
                emotesApplied = true
                emotesAppliedToHumanoid = true
                refreshMeshPartSnapshot(character, current)
            else
                notify(
                    "Disguise emotes could not be applied: "
                        .. tostring(emoteError)
                )
            end
        end

        local changedCount: number = applyCachedMovementAnimations(character, humanoid)
        if not bundleTarget and settings.customPackSlots ~= nil then
            local packCount: number = applyAnimationPack(character, humanoid)
            if packCount > 0 then
                changedCount = packCount
            end
        end
        destroyInstance(description)
        if not stillCurrent(token, character) then
            if emotesApplied then
                local rolledBack: boolean = setHumanoidEmotes(
                    humanoid,
                    current.emotes,
                    current.equippedEmotes
                )
                if rolledBack then
                    emotesAppliedToHumanoid = false
                end
            end
            return
        end
        if not emotesApplied and changedCount == 0 then
            notify("That avatar did not expose emotes or movement animations.")
            return
        end

        activeCard:SetStatus("Animation")
        local animationLine: string = string.format(
            "Animation · %s · emotes %s · %d slots",
            rigName(humanoid) or "rig?",
            emotesApplied and "applied" or "not available",
            changedCount
        )
        if (lastDroppedSlotCount or 0) > 0 then
            animationLine ..= string.format(
                " · %d pack clips skipped",
                lastDroppedSlotCount or 0
            )
        end
        if settings.customPackSlots ~= nil then
            animationLine ..= " · pack " .. packDisplayName()
        end
        status(animationLine .. ". Your own avatar stays visible.")
    end

    local function applyDisguise(): ()
        lastDroppedSlotCount = 0
        generation += 1
        local token: number = generation
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        if not character or not humanoid or humanoid.Health <= 0 then
            notify("Your character is not ready yet.")
            return
        end
        local numericId: number?, idError: string? = parseId()
        if not numericId then
            notify(tostring(idError))
            return
        end

        local selectedMode: string = settings.mode
        -- A new application invalidates the previous target's cache. The fetch
        -- that follows repopulates it before anything is applied.
        targetCache = nil
        task.spawn(function(): ()
            if selectedMode == "Character" then
                applyCharacterDisguise(
                    token,
                    character :: Model,
                    humanoid :: Humanoid,
                    numericId :: number
                )
            else
                applyAnimationDisguise(
                    token,
                    character :: Model,
                    humanoid :: Humanoid,
                    numericId :: number
                )
            end
        end)
    end

    local function activeCharacter(): (any, any)
        local character: any = LocalPlayer.Character
        local humanoid: any = character
            and character:FindFirstChildOfClass("Humanoid")
        if not character or not humanoid then
            return nil, nil
        end
        return character, humanoid
    end

    -- Animation Speed: every playing track of our own character runs at
    -- this rate (0 freezes, 1 is normal, 2 is double). The Heartbeat
    -- below re-applies it, because the Animate script starts new tracks
    -- at speed 1 whenever the animation changes.
    local function applyAnimationSpeedValue(speed: number): ()
        local _character: any, humanoid: any = activeCharacter()
        if not humanoid then
            return
        end
        for _, track: AnimationTrack in ipairs(playingAnimationTracks(humanoid)) do
            pcall(function(): ()
                track:AdjustSpeed(speed)
            end)
        end
    end

    local function applyAnimationSpeed(): ()
        applyAnimationSpeedValue(settings.animationSpeed)
    end

    -- Character mode only. Both toggles are independent: one touches the
    -- Animate slots, the other the Humanoid emotes, and neither refetches the
    -- avatar because cacheTarget already loaded everything.
    local function setMovementAnimationsEnabled(enabled: boolean): ()
        settings.useTargetMovementAnimations = enabled
        if not activeCard or not activeCard.Enabled or settings.mode ~= "Character" then
            return
        end
        local character: any, humanoid: any = activeCharacter()
        if not character then
            return
        end
        if enabled then
            if not targetCache then
                applyDisguise()
                return
            end
            local appliedCount: number =
                applyCachedMovementAnimations(character, humanoid)
            if appliedCount == 0 and not animationOverrideApplied then
                -- The cache wrote nothing (the Animate slots already
                -- matched, or the snapshot belongs to another body):
                -- refetch and apply the whole disguise instead of
                -- leaving the character with no animation change.
                applyDisguise()
                return
            end
        else
            restoreMovementAnimationsOnly(character, humanoid)
        end
        status(settings.mode)
    end

    local function setTargetEmotesEnabled(enabled: boolean): ()
        settings.showTargetEmotes = enabled
        if not activeCard or not activeCard.Enabled or settings.mode ~= "Character" then
            return
        end
        local character: any, humanoid: any = activeCharacter()
        if not character then
            return
        end
        if enabled then
            if not targetCache then
                applyDisguise()
                return
            end
            if type(targetCache.emotes) ~= "table"
                or type(targetCache.equippedEmotes) ~= "table" then
                notify("That avatar did not expose emotes.")
                return
            end
            applyCachedEmotes(character, humanoid)
        else
            restoreEmotesOnly(character, humanoid)
        end
        status(settings.mode)
    end

    local function restoreAndRelease(): ()
        generation += 1
        applyAnimationSpeedValue(1)
        stopAppearanceFilter()
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        if character then
            restoreOriginalAppearance(character, humanoid)
        end
        destroySnapshot()
        targetCache = nil
        table.clear(cloned)
        table.clear(disguisedItems)
    end

    local card: any
    card = framework.Categories.Utilities:CreateModule({
        Name = "Disguise",
        Category = "Utilities",
        ConfigKey = "Universal.Disguise",
        Order = 26,
        Tooltip = "Character: copies accessories, clothing, face, body colors and other compatible appearance items while keeping your own body, rig and scales. Emotes and movement animations have independent toggles. Animation: applies only animations/emotes to your own avatar, without hiding it. Default ID 78492.",
        Function = function(enabled: boolean): ()
            if enabled then
                card:SetStatus(settings.mode)
                -- Keep new tracks at the chosen speed: the Animate
                -- script starts each one at 1.
                local runService: any = host.RunService
                if not runService then
                    local ok: boolean, service: any = pcall(function(): any
                        return (game :: any):GetService("RunService")
                    end)
                    if ok then
                        runService = service
                    end
                end
                if runService and runService.Heartbeat then
                    local lastSpeedAt: number = 0
                    card:Clean(runService.Heartbeat:Connect(function(): ()
                        local now: number = os.clock()
                        if now - lastSpeedAt < 0.2 then
                            return
                        end
                        lastSpeedAt = now
                        applyAnimationSpeed()
                    end))
                end
                card:Clean(LocalPlayer.CharacterAdded:Connect(function(): ()
                    generation += 1
                    stopAppearanceFilter()
                    destroySnapshot()
                    task.wait(0.5)
                    if card.Enabled then
                        applyDisguise()
                    end
                end))
                applyDisguise()
            else
                restoreAndRelease()
                card:SetStatus(nil)
            end
        end,
    })

    card:CreateDropdown({
        Name = "Mode",
        List = {"Character", "Animation"},
        Index = 1,
        Function = function(value: string): ()
            settings.mode = value
            card:SetStatus(value)
            if card.Enabled then
                if value == "Animation" then
                    local character: Model? = LocalPlayer.Character
                    local humanoid: Humanoid? = character
                        and character:FindFirstChildOfClass("Humanoid")
                        :: Humanoid?
                    if character then
                        restoreOriginalAppearance(character, humanoid)
                    end
                    stopAppearanceFilter()
                end
                applyDisguise()
            end
        end,
        Tooltip = "Character: compatible appearance items on your preserved body/rig, plus independent emote and movement toggles. Animation: the same user ID's emotes and movement animations only, always on; your character stays exactly as it is.",
    })

    card:CreateSlider({
        Name = "Animation Speed",
        Min = 0,
        Max = 2,
        Step = 0.05,
        Default = settings.animationSpeed,
        Function = function(value: number): ()
            settings.animationSpeed = math.clamp(value, 0, 2)
            if card.Enabled then
                applyAnimationSpeed()
            end
        end,
        Tooltip = "Playback speed of your character's animations while Disguise is on: 0 freezes them, 1 is normal, 2 is double speed. Turning Disguise off restores speed 1.",
    })

    -- Show Advanced only reveals the bundle inputs. It never changes the
    -- current animations before the user actually submits a bundle ID.
    card:CreateToggle({
        Name = "Show Advanced",
        Default = settings.showAdvanced,
        Function = function(value: boolean): ()
            settings.showAdvanced = value
        end,
        Tooltip = "Shows bundle inputs for a complete pack or individual slots. Opening or closing these inputs does not change the animations already applied.",
    })

    card:CreateTextBox({
        Name = "Pack Bundle ID",
        Show = {Option = "Show Advanced", Values = {true}},
        Default = "",
        Function = function(value: string): ()
            local trimmed: string = tostring(value or "")
                :gsub("^%s+", "")
                :gsub("%s+$", "")
            local digits: string? = string.match(trimmed, "%d+")
            local bundleId: number? = digits and tonumber(digits) or nil
            if not bundleId then
                notify("Enter an animation bundle ID first (the number in its catalog link).")
                return
            end
            -- Any pack at all -- official or UGC -- resolved live from
            -- the bundle's own items, so the thousands of creator packs
            -- work without a single hardcoded id.
            local slots: {[string]: any}?, bundleError: string? =
                bundleAnimationSlots(bundleId)
            if not slots then
                notify("Could not load that pack: " .. tostring(bundleError))
                return
            end
            settings.customPackSlots = slots
            settings.customPackName = "Bundle " .. tostring(bundleId)
            table.clear(settings.customSlotIds)
            if not card.Enabled then
                notify("Pack " .. tostring(bundleId) .. " loaded; it applies while Disguise is on.")
                return
            end
            local character: Model? = LocalPlayer.Character
            local humanoid: Humanoid? = character
                and character:FindFirstChildOfClass("Humanoid")
                :: Humanoid?
            if character and humanoid then
                applyAnimationPack(character, humanoid)
                status(settings.mode .. " · pack Bundle " .. tostring(bundleId))
            end
        end,
        Tooltip = "Any animation pack bundle ID from its catalog link (roblox.com/bundles/<id>/...), official or UGC -- for example 4899847411546. The bundle's items are resolved when you enter it (nothing is downloaded; the engine streams the clips) and the pack is kept for the session. It wins over the target's movement animations. R15-only clips are not forced onto an incompatible R6 body.",
    })

    -- Per-slot bundle inserts: paste any pack's bundle ID into a slot
    -- and that slot takes the pack's clip for it (Idle from one pack,
    -- Run from another, ...). Slots left empty fall back to your rig's
    -- own set when the pack applies.
    local SLOT_INSERTS: {{string}} = {
        {"Idle", "idle"},
        {"Walk", "walk"},
        {"Run", "run"},
        {"Jump", "jump"},
        {"Fall", "fall"},
        {"Climb", "climb"},
        {"Swim", "swim"},
        {"Swim Idle", "swimidle"},
    }
    for _, slotInsert: {string} in ipairs(SLOT_INSERTS) do
        local label: string = slotInsert[1]
        local category: string = slotInsert[2]
        card:CreateTextBox({
            Name = label .. " Bundle ID",
            Show = {Option = "Show Advanced", Values = {true}},
            Default = "",
            Function = function(value: string): ()
                local digits: string? = string.match(
                    tostring(value or ""),
                    "%d+"
                )
                local bundleId: number? = digits and tonumber(digits)
                    or nil
                if not bundleId then
                    notify("Enter a bundle ID for the " .. label .. " slot first.")
                    return
                end
                local slots: {[string]: any}?, bundleError: string? =
                    bundleAnimationSlots(bundleId)
                if not slots then
                    notify("Could not load that pack: " .. tostring(bundleError))
                    return
                end
                local clip: any = slots[category]
                if type(clip) == "table" then
                    clip = clip[1]
                end
                if not clip then
                    notify("That bundle has no " .. label .. " clip to take.")
                    return
                end
                settings.customSlotIds[category] = clip
                local merged: {[string]: any} = {}
                for mergedCategory: string, mergedId: any in pairs(
                    settings.customSlotIds
                ) do
                    merged[mergedCategory] = mergedId
                end
                settings.customPackSlots = merged
                settings.customPackName = "Custom slots"
                if not card.Enabled then
                    notify(label .. " slot set; it applies while Disguise is on.")
                    return
                end
                local character: Model? = LocalPlayer.Character
                local humanoid: Humanoid? = character
                    and character:FindFirstChildOfClass("Humanoid")
                    :: Humanoid?
                if character and humanoid then
                    applyAnimationPack(character, humanoid)
                    status(settings.mode .. " · pack Custom slots")
                end
            end,
            Tooltip = "Set the " .. label .. " slot from any animation pack: paste the pack's bundle ID (official or UGC) and this slot takes that pack's " .. label .. " clip. Mix slots from different packs freely; empty slots use your rig's own set.",
        })
    end

    card:CreateToggle({
        Name = "Use target movement animations",
        -- Character only: Animation mode always applies them and has no control.
        Show = {Option = "Mode", Values = {"Character"}},
        Default = settings.useTargetMovementAnimations,
        Function = function(value: boolean): ()
            setMovementAnimationsEnabled(value)
        end,
        Tooltip = "Character mode only. Shows the target user's movement animations (idle, walk, run, jump, climb, fall, swim, and Roblox's default set for any slot the avatar leaves empty) on the disguised avatar. They are already loaded, so this is instant; turning it off restores your own animations. Emotes are independent and stay untouched.",
    })

    card:CreateTextBox({
        Name = "Target ID",
        Default = settings.id,
        Function = function(value: string): ()
            local trimmed: string = tostring(value or "")
                :gsub("^%s+", "")
                :gsub("%s+$", "")
            if trimmed == "" then
                notify("Enter a user ID or animation bundle ID first.")
                return
            end
            settings.id = trimmed
            if card.Enabled then
                applyDisguise()
            end
        end,
        Tooltip = "User ID (Character copies compatible appearance items without replacing your body/rig; Animation copies only emotes and movement animations) or an animation pack ID in Animation mode. Default 78492. Missing animation slots fall back to your rig's own set.",
    })

    card:CreateToggle({
        Name = "Show target emotes",
        -- Character only: Animation mode always applies the target's emotes.
        Show = {Option = "Mode", Values = {"Character"}},
        Default = settings.showTargetEmotes,
        Function = function(value: boolean): ()
            setTargetEmotesEnabled(value)
        end,
        Tooltip = "Character mode only. Shows the target user's emotes and equipped emote slots on the disguised avatar. Independent from movement animations; turning it off restores your own emotes without touching the disguise.",
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard then
        if activeCard.Enabled then
            pcall(activeCard.Toggle, activeCard, false)
        end
        activeCard = nil
    end
    Module.Initialized = false
end

return Module
