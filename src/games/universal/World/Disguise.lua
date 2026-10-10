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

local DEFAULT_USER_ID: number = 239702688
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

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local Players: Players = host.Players or (game :: any):GetService("Players")
    local MarketplaceService: MarketplaceService = host.MarketplaceService
        or (game :: any):GetService("MarketplaceService")
    local LocalPlayer: Player = host.LocalPlayer or Players.LocalPlayer

    local cloned = setmetatable({}, {__mode = "k"}) :: {[Instance]: boolean}
    local disguisedItems = setmetatable({}, {__mode = "k"}) :: {[Instance]: boolean}
    local snapshot: AppearanceSnapshot? = nil
    local filteredCharacter: Model? = nil
    local filterConnection: RBXScriptConnection? = nil
    local generation: number = 0
    local restoring: boolean = false
    local emotesAppliedToHumanoid: boolean = false
    local animationBundleApplied: boolean = false
    local targetEmotes: any = nil
    local targetEquippedEmotes: any = nil

    local settings = {
        mode = "Character",
        id = tostring(DEFAULT_USER_ID),
    }

    local function notify(message: string): ()
        pcall(print, "[Wurst:Disguise] " .. message)
        if activeCard then
            pcall(activeCard.Notify, activeCard, message)
        end
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
        animationBundleApplied = false
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
            -- The Humanoid's child HumanoidDescription is the live avatar
            -- description, matching the original VapeV4 emote flow.
            return true, nil
        end

        -- Some games do not keep a HumanoidDescription child. In that case
        -- apply the edited copy to the local Humanoid so the emote wheel sees
        -- the new equipped list, then let Disguise re-copy its visual items.
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

        -- Older clients expose Disabled instead of Enabled.
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

        local restartRestoredAnimations: boolean = animationBundleApplied
        animationBundleApplied = false

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
        local value: number? = tonumber(trimmed)
        if not value or value <= 0 or value % 1 ~= 0 then
            return nil, "Enter a positive integer ID."
        end
        return value, nil
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
                    -- Copy mesh identifiers only; retain live part dimensions,
                    -- joint objects, and collision settings.
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

        targetEmotes, targetEquippedEmotes = readDescriptionEmotes(description)
        local emoteWarning: string? = nil
        if targetEmotes and targetEquippedEmotes then
            local emotesApplied: boolean, emoteError: string? = setHumanoidEmotes(
                humanoid,
                targetEmotes,
                targetEquippedEmotes
            )
            if emotesApplied then
                emotesAppliedToHumanoid = true
                refreshMeshPartSnapshot(character, current)
            else
                emoteWarning = tostring(emoteError)
                -- SetEmotes may have succeeded before SetEquippedEmotes failed;
                -- roll back a partial update using the captured local profile.
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
        destroyInstance(description)
        destroyInstance(clone)
        if not copied then
            notify("The avatar was loaded, but some appearance parts could not be copied: "
                .. tostring(copyError))
            return
        end
        if stillCurrent(token, character) then
            activeCard:SetStatus("Character")
            local emoteCount: number = 0
            if type(targetEmotes) == "table" then
                for _ in pairs(targetEmotes) do
                    emoteCount += 1
                end
            end
            local message: string = "Avatar disguise applied; live body-part dimensions were left unchanged. "
            if emoteWarning then
                message ..= "Emotes could not be applied: " .. emoteWarning
            elseif emoteCount > 0 then
                message ..= tostring(emoteCount)
                    .. " target emote(s) copied; open the Roblox emote menu."
            else
                message ..= "The target description returned no emotes."
            end
            notify(message)
        end
    end

    local function getService(name: string): any
        local supplied: any = host[name]
        if supplied then
            return supplied
        end
        local ok: boolean, result: any = pcall(function()
            return (game :: any):GetService(name)
        end)
        return if ok then result else nil
    end

    local function getBundleItems(
        bundleId: number,
        productInfo: any
    ): ({any}?, string?)
        local directItems: any = productInfo.Items or productInfo.items
        local hasDirectItems: boolean = type(directItems) == "table"
            and #directItems > 0
        local directType: string = tostring(productInfo.BundleType or "")
        if hasDirectItems and directType ~= "" then
            return directItems, directType
        end

        for _, serviceName: string in ipairs({"AssetService", "AvatarEditorService"}) do
            local service: any = getService(serviceName)
            local method: any = service and service.GetBundleDetailsAsync
            if type(method) == "function" then
                local ok: boolean, details: any = pcall(method, service, bundleId)
                if ok and type(details) == "table" then
                    local items: any = details.Items or details.items
                    local bundleType: string = tostring(
                        details.BundleType or directType
                    )
                    if bundleType ~= ""
                        and type(items) == "table"
                        and #items > 0 then
                        return items, bundleType
                    end
                    if bundleType ~= "" and hasDirectItems then
                        return directItems, bundleType
                    end
                end
            end
        end
        if hasDirectItems then
            return directItems, directType
        end
        return nil, nil
    end

    local function getAnimationType(itemName: string): string
        local normalized: string = string.lower(itemName)
            :gsub("%s*animations?%s*$", "")
            :gsub("%s+", "")
        local aliases: {[string]: string} = {
            pose = "idle",
            idling = "idle",
            walking = "walk",
            running = "run",
            jumping = "jump",
            falling = "fall",
            climbing = "climb",
            swimming = "swim",
        }
        return aliases[normalized] or normalized
    end

    local function applyAnimationBundle(
        token: number,
        character: Model,
        humanoid: Humanoid,
        bundleId: number
    ): ()
        local items: {any}?, rawBundleType: string? = getBundleItems(
            bundleId,
            {}
        )
        local productInfoError: string? = nil
        if not items or rawBundleType == nil or rawBundleType == "" then
            if not stillCurrent(token, character) then
                return
            end
            local infoOk: boolean, productInfo: any = pcall(function()
                return MarketplaceService:GetProductInfo(
                    bundleId,
                    Enum.InfoType.Bundle
                )
            end)
            if not stillCurrent(token, character) then
                return
            end
            if infoOk and type(productInfo) == "table" then
                local fallbackItems: {any}?, fallbackBundleType: string? =
                    getBundleItems(bundleId, productInfo)
                if fallbackItems then
                    items = fallbackItems
                end
                if fallbackBundleType and fallbackBundleType ~= "" then
                    rawBundleType = fallbackBundleType
                end
            else
                productInfoError = tostring(productInfo)
            end
        end
        if not stillCurrent(token, character) then
            return
        end
        if not items then
            local detail: string = productInfoError
                and (" " .. productInfoError)
                or ""
            notify("Could not read the bundle's animation items." .. detail)
            return
        end
        local bundleType: string = string.lower(tostring(rawBundleType or ""))
        if bundleType == "" then
            notify("This client could not verify the bundle type.")
            return
        end
        if not string.find(bundleType, "animation", 1, true) then
            notify("That ID is not an avatar animation bundle.")
            return
        end

        local current: AppearanceSnapshot = ensureSnapshot(character, humanoid)
        restoreOriginalAppearance(character, humanoid)
        stopAppearanceFilter()

        local animate: Instance? = character:FindFirstChild("Animate")
        if not animate then
            notify("This character has no Animate script to update.")
            return
        end

        local changedCount: number = 0
        for _, item: any in ipairs(items) do
            if not stillCurrent(token, character) then
                return
            end
            local itemName: string = tostring(item.Name or item.name or "")
            local itemId: number? = tonumber(item.Id or item.AssetId or item.id)
            local itemType: string = getAnimationType(itemName)
            local targetCategory: Instance? = animate:FindFirstChild(itemType)
            if itemId and targetCategory then
                local objectsOk: boolean, objects: any = pcall(function()
                    return (game :: any):GetObjects(
                        "rbxassetid://" .. tostring(itemId)
                    )
                end)
                if objectsOk and type(objects) == "table" then
                    if not stillCurrent(token, character) then
                        for _, object: Instance in ipairs(objects) do
                            destroyInstance(object)
                        end
                        return
                    end
                    local sourceAnimation: Animation? = nil
                    for _, object: Instance in ipairs(objects) do
                        if object:IsA("Animation") then
                            sourceAnimation = object
                            break
                        end
                        sourceAnimation = object:FindFirstChildWhichIsA(
                            "Animation",
                            true
                        ) :: Animation?
                        if sourceAnimation then
                            break
                        end
                    end
                    if sourceAnimation then
                        local targetAnimations: {Animation} = {}
                        if targetCategory:IsA("Animation") then
                            table.insert(targetAnimations, targetCategory)
                        end
                        for _, object: Instance in ipairs(targetCategory:GetDescendants()) do
                            if object:IsA("Animation") then
                                table.insert(targetAnimations, object)
                            end
                        end
                        for _, animation: Animation in ipairs(targetAnimations) do
                            local changed: boolean = pcall(function()
                                animation.AnimationId = sourceAnimation.AnimationId
                            end)
                            if changed then
                                changedCount += 1
                            end
                        end
                    end
                    for _, object: Instance in ipairs(objects) do
                        destroyInstance(object)
                    end
                end
            end
        end

        if changedCount == 0 then
            -- Ensure a failed lookup doesn't leave a half-selected mode behind.
            restoreOriginalAppearance(character, humanoid)
            notify("No compatible animations were found in that bundle.")
            return
        end

        animationBundleApplied = true
        local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            for _, track: AnimationTrack in ipairs(animator:GetPlayingAnimationTracks()) do
                pcall(track.Stop, track)
            end
        end
        restartAnimateScript(animate)
        if current.character == character and stillCurrent(token, character) then
            activeCard:SetStatus("Animation")
            notify("Animation bundle applied to " .. tostring(changedCount)
                .. " slots; Animate restarted. Original IDs return when disabled.")
        end
    end

    local function applyDisguise(): ()
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
        targetEmotes = nil
        targetEquippedEmotes = nil
        task.spawn(function(): ()
            if selectedMode == "Character" then
                applyCharacterDisguise(
                    token,
                    character :: Model,
                    humanoid :: Humanoid,
                    numericId :: number
                )
            else
                applyAnimationBundle(
                    token,
                    character :: Model,
                    humanoid :: Humanoid,
                    numericId :: number
                )
            end
        end)
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
        table.clear(cloned)
        table.clear(disguisedItems)
    end

    local function sortedEmoteNames(data: any): {string}
        local names: {string} = {}
        if type(data) == "table" then
            for name: any in pairs(data) do
                if type(name) == "string" then
                    table.insert(names, name)
                end
            end
        end
        table.sort(names)
        return names
    end

    local function equippedEmoteNames(data: any): {string}
        local names: {string} = {}
        local seen: {[string]: boolean} = {}
        if type(data) == "table" then
            for key: any, entry: any in pairs(data) do
                local name: any = nil
                if type(entry) == "string" then
                    name = entry
                elseif entry == true and type(key) == "string" then
                    name = key
                elseif type(entry) == "table" then
                    name = entry.Name or entry.name or entry[1]
                end
                if type(name) == "string" and not seen[name] then
                    seen[name] = true
                    table.insert(names, name)
                end
            end
        end
        table.sort(names)
        return names
    end

    local function formatNameList(names: {string}): string
        if #names == 0 then
            return "none"
        end
        local shown: {string} = {}
        for index: number = 1, math.min(#names, 12) do
            table.insert(shown, names[index])
        end
        if #names > 12 then
            table.insert(shown, "+" .. tostring(#names - 12) .. " more")
        end
        return table.concat(shown, ", ")
    end

    local card: any
    card = framework.Categories.Other:CreateModule({
        Name = "Disguise",
        Category = "Other",
        ConfigKey = "Universal.Disguise",
        Order = 26,
        Tooltip = "Copies avatar cosmetics, equipped emotes, or animation IDs without changing live body-part dimensions.",
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
                    targetEmotes = nil
                    targetEquippedEmotes = nil
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
        Tooltip = "Character: cosmetics and equipped emotes from a user ID. Animation: avatar-animation bundles only.",
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
        Tooltip = "Positive integer user ID (Character) or avatar-animation bundle ID (Animation).",
    })


    card:CreateButton({
        Name = "Show target emotes",
        Function = function(): ()
            if type(targetEmotes) ~= "table" then
                notify("Load a user ID in Character mode before listing emotes.")
                return
            end
            local names: {string} = sortedEmoteNames(targetEmotes)
            local equipped: {string} = equippedEmoteNames(targetEquippedEmotes)
            notify(string.format(
                "Target emotes (%d): %s | Equipped (%d): %s",
                #names,
                formatNameList(names),
                #equipped,
                formatNameList(equipped)
            ))
        end,
        Tooltip = "Lists the emotes and equipped emote slots returned for the target user ID.",
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
