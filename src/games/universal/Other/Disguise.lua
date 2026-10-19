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
    local releaseIdleBridge: () -> () = function(): () end
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
        id = tostring(DEFAULT_USER_ID),
        useTargetMovementAnimations = savedToggle(
            "Use target movement animations",
            true
        ),
        showTargetEmotes = savedToggle("Show target emotes", true),
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
        releaseIdleBridge()
        local current: AppearanceSnapshot? = snapshot
        if not current or current.character ~= character
            or not animationOverrideApplied then
            return
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
        local changedCount: number = writeAnimationSlots(animate, resolved)
        if changedCount == 0 then
            return 0
        end
        animationOverrideApplied = true
        releaseIdleBridge()
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
    -- description, so it can never touch or roll back the visible avatar.
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

    -- Some games restart the Animate script without replaying the idle loop:
    -- the script only plays it from a Humanoid.Running event, and a body that
    -- is standing still never fires one. The bridge plays the same Animation
    -- the script would have played, and steps aside the moment any other
    -- track (walk, jump, an emote) starts.
    local idleBridgeTrack: AnimationTrack? = nil
    releaseIdleBridge = function(): ()
        local bridge: AnimationTrack? = idleBridgeTrack
        idleBridgeTrack = nil
        if bridge then
            pcall(function(): ()
                (bridge :: any):Stop(0.15)
            end)
            pcall(function(): ()
                (bridge :: any):Destroy()
            end)
        end
    end

    local function playIdleBridge(
        humanoid: Humanoid?,
        animate: Instance
    ): AnimationTrack?
        if not humanoid then
            return nil
        end
        local idle: Instance? = animate:FindFirstChild("idle")
        local animation: Animation? = nil
        if idle then
            if idle:IsA("Animation") then
                animation = idle :: Animation
            end
            for _, descendant: Instance in ipairs(idle:GetDescendants()) do
                if not animation and descendant:IsA("Animation") then
                    animation = descendant :: Animation
                end
            end
        end
        local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
        if not animation or not animator then
            return nil
        end
        local ok: boolean, track: any = pcall(function(): any
            return animator:LoadAnimation(animation)
        end)
        if not ok or not track then
            return nil
        end
        local played: boolean = pcall(function(): ()
            track:Play(0.1)
        end)
        if not played then
            return nil
        end
        return track
    end

    local function watchIdleBridge(humanoid: Humanoid?): ()
        local bridge: AnimationTrack? = idleBridgeTrack
        if not bridge then
            return
        end
        task.spawn(function(): ()
            local deadline: number = os.clock() + 6
            while idleBridgeTrack == bridge and os.clock() < deadline do
                task.wait(0.1)
                if idleBridgeTrack ~= bridge then
                    return
                end
                for _, track: AnimationTrack in ipairs(
                    playingAnimationTracks(humanoid)
                ) do
                    if track ~= bridge then
                        releaseIdleBridge()
                        return
                    end
                end
            end
        end)
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
            if object:IsA("Motor6D") then
                local ok: boolean, transform: CFrame = pcall(function(): CFrame
                    return (object :: Motor6D).Transform
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
        releaseIdleBridge()
        for _, track: AnimationTrack in ipairs(playingAnimationTracks(humanoid)) do
            pcall(function(): ()
                track:Stop()
            end)
        end
        restartAnimateScript(animate)
        task.wait(0.1)
        if #playingAnimationTracks(humanoid) > 0 then
            return true
        end
        local bridge: AnimationTrack? = playIdleBridge(humanoid, animate)
        if not bridge then
            return false
        end
        task.wait(0.1)
        local playing: boolean = false
        pcall(function(): ()
            playing = (bridge :: any).IsPlaying == true
        end)
        if not playing then
            pcall(function(): ()
                (bridge :: any):Destroy()
            end)
            return false
        end
        idleBridgeTrack = bridge
        watchIdleBridge(humanoid)
        return true
    end

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
        end
        local bridge: AnimationTrack? = playIdleBridge(humanoid, animate)
        if bridge then
            task.wait(0.1)
            local playing: boolean = false
            pcall(function(): ()
                playing = (bridge :: any).IsPlaying == true
            end)
            if playing and poseMoves(humanoid, 0.3) ~= false then
                idleBridgeTrack = bridge
                watchIdleBridge(humanoid)
                return true
            end
            pcall(function(): ()
                (bridge :: any):Destroy()
            end)
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
            local fallbackBridge: AnimationTrack? = playIdleBridge(humanoid, animate)
            if fallbackBridge then
                task.wait(0.1)
                local playing: boolean = false
                pcall(function(): ()
                    playing = (fallbackBridge :: any).IsPlaying == true
                end)
                if playing and poseMoves(humanoid, 0.3) ~= false then
                    idleBridgeTrack = fallbackBridge
                    watchIdleBridge(humanoid)
                    notify(
                        "Those clips do not play on your "
                            .. (isR6 and "R6" or "R15")
                            .. " rig; your rig's own set is back."
                    )
                    return true
                end
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
        if type((game :: any).GetObjects) == "function" then
            local ok: boolean, objects: any = pcall(function(): any
                return (game :: any):GetObjects("rbxassetid://" .. tostring(itemId))
            end)
            if ok and type(objects) == "table" then
                for _, object: any in ipairs(objects) do
                    if typeof(object) == "Instance" then
                        if object:IsA("Animation") then
                            return object.AnimationId
                        end
                        for _, descendant: Instance in ipairs(object:GetDescendants()) do
                            if descendant:IsA("Animation") then
                                return descendant.AnimationId
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function bundleAnimationSlots(bundleId: number): ({[string]: any}?, string?)
        local service: any = (host :: any).MarketplaceService
            or (game :: any):GetService("MarketplaceService")
        local ok: boolean, product: any = pcall(function(): any
            return service:GetProductInfo(bundleId, Enum.InfoType.Bundle)
        end)
        if not ok or type(product) ~= "table" then
            return nil, "That ID is not a user and the marketplace did not return a bundle."
        end
        if product.BundleType ~= "AvatarAnimations" then
            return nil, "That bundle is not an animation pack."
        end
        if type(product.Items) ~= "table" then
            return nil, "The animation pack did not expose its items."
        end
        local slots: {[string]: any} = {}
        local categories: {string} = {
            "idle", "walk", "run", "jump", "fall", "climb", "swim", "swimidle",
        }
        for _, item: any in ipairs(product.Items) do
            local name: string = string.lower(tostring(item.Name or ""))
            local category: string? = nil
            for _, candidate: string in ipairs(categories) do
                if string.find(name, candidate, 1, true) then
                    category = candidate
                    break
                end
            end
            -- "Swim (Idle)" matches "idle" first alphabetically in the list
            -- above only if it appears earlier; make the pair explicit.
            if string.find(name, "swim", 1, true)
                and string.find(name, "idle", 1, true) then
                category = "swimidle"
            end
            if category and item.Id then
                local resolved: string? = animationAssetId(item.Id)
                slots[category] = resolved
                    or ("rbxassetid://" .. tostring(item.Id))
            end
        end
        if next(slots) == nil then
            return nil, "The animation pack did not expose a usable animation."
        end
        return slots, nil
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
        local changedCount: number = applyAnimationSlots(
            character,
            humanoid,
            cached.slots,
            cached.rig
        )
        -- Zero writes do not mean the body is fine: the ids may already be
        -- the frozen set from a previous apply, and re-selecting the same
        -- target has to settle it again instead of trusting the old state.
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
        releaseIdleBridge()
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
            elseif BODY_PARTS[source.Name]
                and source:IsA("MeshPart") then
                local target: Instance? = character:FindFirstChild(source.Name)
                if target and target:IsA("MeshPart") then

                    pcall(function()
                        target.MeshId = source.MeshId
                        target.TextureID = source.TextureID
                    end)
                end
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
        -- when both toggles are off, so the avatar below is the only thing the
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
        -- can never block or roll back the avatar copy above.
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
                    "The avatar was applied, but movement animations failed: "
                        .. tostring(movementResult)
                )
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
            applyCachedMovementAnimations(character, humanoid)
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
        Tooltip = "Character: copies the target avatar, then optionally its emotes and movement animations through two independent toggles (both preloaded). Animation: always applies that user's, or animation pack's, movement animations and emotes to your own avatar, without hiding it. Default ID 78492.",
        Function = function(enabled: boolean): ()
            if enabled then
                card:SetStatus(settings.mode)
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
        Tooltip = "Character: the visible avatar, plus independent toggles for its emotes and movement animations. Animation: the same user ID's emotes and movement animations only, always on; your character stays exactly as it is.",
    })

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
        Tooltip = "User ID (Character copies the avatar; Animation copies only its emotes and movement animations) or an animation pack ID in Animation mode. Default 78492. Missing animation slots fall back to Roblox's own R15 set.",
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
