export type Runtime = {
    framework: any,
    entity: any,
    render: any,
    host: any,
    services: any,
}

local Module = {
    Name = "NPCESP",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local render: any = context.render
    local host: any = context.host
    local players: Players = host.Players
    local currentWorkspace: Workspace = host.workspace or workspace
    local layer: Frame = render:Layer("NpcEspLayer")
    local bots: {[Model]: boolean} = {}
    local lastFrame: number = 0

    local function belongsToPlayer(model: Model): boolean
        for _, player: Player in ipairs(players:GetPlayers()) do
            local character: Model? = player.Character
            if character and (model == character or model:IsDescendantOf(character)) then
                return true
            end
        end
        return false
    end

    local function rigScore(model: Model): number
        if model:FindFirstChildWhichIsA("Humanoid", true) then return 100 end
        local parts: number = 0
        local joints: number = 0
        local hasFace: boolean = false
        local hasAccessory: boolean = false
        local standardParts: number = 0
        for _, object: Instance in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") and not object:FindFirstAncestorOfClass("Accessory") then
                parts += 1
                local name: string = string.lower(object.Name):gsub("[%s_%-]", "")
                if name == "head" or name == "torso" or name == "uppertorso"
                    or name == "lowertorso" or name == "humanoidrootpart"
                    or string.find(name, "leftarm", 1, true)
                    or string.find(name, "rightarm", 1, true)
                    or string.find(name, "leftleg", 1, true)
                    or string.find(name, "rightleg", 1, true)
                    or string.find(name, "lefthand", 1, true)
                    or string.find(name, "righthand", 1, true)
                    or string.find(name, "leftfoot", 1, true)
                    or string.find(name, "rightfoot", 1, true) then
                    standardParts += 1
                end
                if object:FindFirstChildWhichIsA("Decal") then hasFace = true end
            elseif object:IsA("Motor6D") then
                joints += 1
            elseif object:IsA("Accessory") then
                hasAccessory = true
            end
        end
        if parts < 4 or parts > 40 then return 0 end
        if standardParts >= 4 then return 80 + standardParts end
        if joints >= 3 and (hasFace or hasAccessory) then return 60 + joints end
        if hasFace and hasAccessory and parts >= 5 then return 50 + parts end
        return 0
    end

    local function owningRig(instance: Instance): Model?
        local model: Model? = instance:IsA("Model") and instance :: Model
            or instance:FindFirstAncestorOfClass("Model") :: Model?
        while model and model ~= currentWorkspace do
            if not belongsToPlayer(model) and rigScore(model) > 0 then return model end
            local parent: Instance? = model.Parent
            if not parent then break end
            model = parent:IsA("Model") and parent :: Model
                or parent:FindFirstAncestorOfClass("Model") :: Model?
        end
        return nil
    end

    local function add(model: Model): ()
        for existing: Model in pairs(bots) do
            if existing:IsDescendantOf(model) then return end
            if model:IsDescendantOf(existing) then
                bots[existing] = nil
                render:Release(layer, existing)
            end
        end
        bots[model] = true
    end

    local function inspect(instance: Instance): ()
        if not (instance:IsA("Model") or instance:IsA("Humanoid")
            or instance:IsA("BasePart") or instance:IsA("Motor6D")
            or instance:IsA("Accessory")) then return end
        local model: Model? = owningRig(instance)
        if model then add(model) end
    end

    local function remove(instance: Instance): ()
        if not instance:IsA("Model") then return end
        local model: Model = instance :: Model
        if bots[model] then
            bots[model] = nil
            render:Release(layer, model)
        end
    end

    local function scan(): ()
        table.clear(bots)
        for _, object: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if object:IsA("Model") then inspect(object) end
        end
    end

    local card: any
    local function clear(): ()
        render:ReleaseAll(layer)
        table.clear(bots)
        layer.Visible = false
    end

    card = framework.Categories.Visuals:CreateModule({
        Name = "NPCESP",
        Category = "Render",
        ConfigKey = "Universal.NPCESP",
        Order = 4,
        Tooltip = "Displays non-player character rigs as BOT.",
        Function = function(enabled: boolean): ()
            layer.Visible = enabled
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            scan()
            card:Event(currentWorkspace.DescendantAdded, inspect)
            card:Event(currentWorkspace.DescendantRemoving, remove)
            card:Render(function(): ()
                local now: number = os.clock()
                if now - lastFrame < 1 / 20 then return end
                lastFrame = now
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not camera then return end
                local localCharacter: Model? = host.LocalPlayer.Character
                local localRoot: BasePart? = localCharacter and (
                    localCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
                    or localCharacter.PrimaryPart
                    or localCharacter:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
                ) or nil
                local origin: Vector3 = localRoot and localRoot.Position or camera.CFrame.Position
                local count: number = 0
                for model: Model in pairs(bots) do
                    if not model:IsDescendantOf(currentWorkspace) or belongsToPlayer(model)
                        or rigScore(model) == 0 then
                        bots[model] = nil
                        render:Release(layer, model)
                        continue
                    end
                    local root: BasePart? = model:FindFirstChild("HumanoidRootPart", true) :: BasePart?
                        or model.PrimaryPart
                        or model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
                    local drawing: any = render:Set(layer, model)
                    if not root or (root.Position - origin).Magnitude > card.Options["Max distance"].Value then
                        drawing:Show(false)
                        continue
                    end
                    local humanoid: Humanoid? = model:FindFirstChildWhichIsA("Humanoid", true) :: Humanoid?
                    if humanoid and humanoid.Health <= 0 then
                        drawing:Show(false)
                        continue
                    end
                    local rect: any = render:ModelRect(camera, model)
                    if not rect then
                        drawing:Show(false)
                        continue
                    end
                    local colour: Color3 = card.Options["Colour"].Value
                    drawing:Box(rect, card.Options["Box"].Value and "Full" or "Off", 1, colour)
                    if card.Options["Name"].Value then
                        local text: string = "BOT"
                        if humanoid and card.Options["Health"].Value then
                            text ..= " [" .. tostring(math.round(humanoid.Health)) .. "]"
                        end
                        drawing:Label("NameTag", text, Vector2.new(rect.centreX, rect.top - 4), 1, 13, colour, true)
                    else
                        drawing:HideLabel("NameTag")
                    end
                    drawing:Highlight(
                        model,
                        colour,
                        0.55,
                        not card.Options["Highlight"].Value and "Off"
                            or (card.Options["Through walls"].Value and "AlwaysOnTop" or "Occluded")
                    )
                    drawing:Show(true)
                    count += 1
                end
                card:SetStatus(tostring(count))
            end)
            card:Clean(clear)
        end,
    })

    card:CreateToggle({Name = "Box", Default = true})
    card:CreateToggle({Name = "Highlight", Default = true})
    card:CreateToggle({Name = "Through walls", Default = true, Show = {Option = "Highlight"}})
    card:CreateToggle({Name = "Name", Default = true})
    card:CreateToggle({Name = "Health", Default = true, Show = {Option = "Name"}})
    card:CreateColor({Name = "Colour", Default = Color3.new(1, 1, 1)})
    card:CreateSlider({Name = "Max distance", Min = 25, Max = 2000, Step = 25, Default = 500})

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then activeCard:Toggle(false) end
    activeCard = nil
    Module.Initialized = false
end

return Module
