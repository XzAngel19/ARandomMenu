--!strict
export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Disguise",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local Players: Players = host.Players or (game :: any):GetService("Players")
    local MarketplaceService: MarketplaceService = host.MarketplaceService or (game :: any):GetService("MarketplaceService")
    local LocalPlayer: Player = host.LocalPlayer or Players.LocalPlayer

    local cloned = setmetatable({}, {__mode = "k"}) :: {[Instance]: boolean}
    local originalItems: {Instance} = {}

    local settings = {
        mode = "Character",
        id = "239702688",
    }

    local function itemAdded(obj: Instance, manual: boolean?): ()
        if (obj:IsA("Accessory")
            or obj:IsA("ShirtGraphic")
            or obj:IsA("Shirt")
            or obj:IsA("Pants")
            or obj:IsA("BodyColors")
            or manual) and not cloned[obj] then
            obj:ClearAllChildren()
            task.defer(function()
                pcall(obj.Destroy, obj)
            end)
        end
    end

    local function applyDisguise(): ()
        table.clear(cloned)
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
        if not character or not humanoid or humanoid.Health <= 0 then
            return
        end

        local numericId: number = tonumber(settings.id) or (settings.mode == "Character" and 239702688 or 43)

        if settings.mode == "Character" then
            local success: boolean, description: any = pcall(function()
                return Players:GetHumanoidDescriptionFromUserId(numericId)
            end)

            if success and description and activeCard and activeCard.Enabled then
                character.Archivable = true
                local clone: Model = character:Clone()
                clone.Parent = game

                local originalDesc: any = humanoid:FindFirstChildOfClass("HumanoidDescription")
                if not originalDesc then
                    originalDesc = {
                        HeightScale = 1,
                        SetEmotes = function() end,
                        SetEquippedEmotes = function() end,
                    }
                end

                pcall(function()
                    originalDesc.JumpAnimation = description.JumpAnimation
                    description.HeightScale = originalDesc.HeightScale
                end)

                local cloneHumanoid: Humanoid? = clone:FindFirstChildOfClass("Humanoid")
                if cloneHumanoid then
                    pcall(function()
                        cloneHumanoid:ApplyDescriptionResetAsync(description)
                    end)
                end

                -- Listen for clothing/accessory additions and clean old ones
                activeCard:Clean(character.ChildAdded:Connect(function(child: Instance)
                    itemAdded(child)
                end))

                for _, obj: Instance in ipairs(character:GetChildren()) do
                    itemAdded(obj)
                end

                for _, obj: Instance in ipairs(clone:GetChildren()) do
                    cloned[obj] = true
                    if obj:IsA("Accessory") then
                        for _, objd: Instance in ipairs(obj:GetDescendants()) do
                            if objd:IsA("Weld") and objd.Part1 then
                                objd.Part1 = character:FindFirstChild(objd.Part1.Name) :: BasePart?
                            elseif objd:IsA("RigidConstraint") and objd.Attachment1 then
                                objd.Attachment1 = character:FindFirstChild(objd.Attachment1.Name, true) :: Attachment?
                            end
                        end
                        obj.Parent = character
                    elseif obj:IsA("ShirtGraphic") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("BodyColors") then
                        obj.Parent = character
                    elseif obj.Name == "Head" and obj:IsA("MeshPart") then
                        local realHead: Instance? = character:FindFirstChild("Head")
                        if realHead and realHead:IsA("MeshPart") and not realHead:FindFirstChild("FaceControls") then
                            realHead.MeshId = obj.MeshId
                        end
                    end
                end

                local face: Instance? = character:FindFirstChild("face", true)
                local cface: Instance? = clone:FindFirstChild("face", true)
                if face then
                    itemAdded(face, true)
                end
                if cface then
                    local realHead: Instance? = character:FindFirstChild("Head")
                    if realHead then
                        cface.Parent = realHead
                    end
                end

                -- Register emotes on HumanoidDescription so Roblox emote wheel replicates to server!
                pcall(function()
                    originalDesc:SetEmotes(description:GetEmotes())
                    originalDesc:SetEquippedEmotes(description:GetEquippedEmotes())
                end)

                pcall(function()
                    description:Destroy()
                    clone:ClearAllChildren()
                    clone:Destroy()
                end)
            end

        elseif settings.mode == "Animation" then
            -- Animation bundle replacement (replicates across the server via Animator)
            local success: boolean, data: any = pcall(function()
                return MarketplaceService:GetProductInfo(numericId, Enum.InfoType.Bundle)
            end)

            if success and type(data) == "table" and activeCard and activeCard.Enabled then
                local items: {any} = data.Items or {}
                local animate: Instance? = character:FindFirstChild("Animate")
                if not animate then
                    return
                end

                for _, item: any in ipairs(items) do
                    local itemName: string = tostring(item.Name or "")
                    local parts: {string} = string.split(itemName, " ")
                    local itemType: string = parts[2] and string.lower(parts[2]) or string.lower(itemName)

                    if itemType ~= "animation" and item.Id then
                        local sucObj: boolean, objects: any = pcall(function()
                            return (game :: any):GetObjects("rbxassetid://" .. tostring(item.Id))
                        end)

                        if sucObj and type(objects) == "table" and objects[1] then
                            local animAsset: Animation? = objects[1]:FindFirstChildWhichIsA("Animation", true) :: Animation?
                            if animAsset then
                                local targetCategory: Instance? = animate:FindFirstChild(itemType)
                                local targetAnim: Animation? = targetCategory and targetCategory:FindFirstChildWhichIsA("Animation") :: Animation?
                                if targetAnim then
                                    targetAnim.AnimationId = animAsset.AnimationId
                                end
                            end
                        end
                    end
                end

                -- Stop old animation tracks so new bundle animations play and replicate immediately
                local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
                if animator then
                    for _, track: AnimationTrack in ipairs(animator:GetPlayingAnimationTracks()) do
                        pcall(function()
                            track:Stop()
                        end)
                    end
                end
            end
        end
    end

    local card: any
    card = framework.Categories.World:CreateModule({
        Name = "Disguise",
        Category = "World",
        ConfigKey = "Universal.Disguise",
        Order = 26,
        Tooltip = "Changes your avatar or animation pack to a specific ID (replicates real emotes and animations).",
        Function = function(enabled: boolean): ()
            if enabled then
                card:SetStatus(settings.mode)
                applyDisguise()
                activeCard:Clean(LocalPlayer.CharacterAdded:Connect(function()
                    task.wait(0.5)
                    if card.Enabled then
                        applyDisguise()
                    end
                end))
            else
                table.clear(cloned)
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
                applyDisguise()
            end
        end,
        Tooltip = "Character: Copies player avatar, clothes, and emotes.\nAnimation: Loads real replicated animation pack (Ninja, Zombie, Mage, etc.).",
    })

    card:CreateTextBox({
        Name = "Target ID",
        Default = settings.id,
        Function = function(value: string): ()
            if value and value ~= "" then
                settings.id = value
                if card.Enabled then
                    applyDisguise()
                end
            end
        end,
        Tooltip = "User ID for Character mode, or Bundle ID (e.g. 43 = Ninja) for Animation mode.",
    })

    card:CreateDropdown({
        Name = "Animation Preset",
        List = {
            "Custom",
            "Ninja (43)",
            "Zombie (53)",
            "Mage (84)",
            "Levitation (54)",
            "Superhero (44)",
            "Toy (45)",
            "Oldschool (46)",
            "Vampire (55)",
            "Elder (80)",
        },
        Index = 1,
        Function = function(value: string): ()
            local bundleIdMap: {[string]: string} = {
                ["Ninja (43)"] = "43",
                ["Zombie (53)"] = "53",
                ["Mage (84)"] = "84",
                ["Levitation (54)"] = "54",
                ["Superhero (44)"] = "44",
                ["Toy (45)"] = "45",
                ["Oldschool (46)"] = "46",
                ["Vampire (55)"] = "55",
                ["Elder (80)"] = "80",
            }
            local foundId: string? = bundleIdMap[value]
            if foundId then
                settings.mode = "Animation"
                settings.id = foundId
                if card.Enabled then
                    applyDisguise()
                end
            end
        end,
        Tooltip = "Quick presets for popular Roblox animation bundles.",
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        pcall(activeCard.Toggle, false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
