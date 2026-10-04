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
    local entityLibrary: any = context.entity
    local render: any = context.render
    local host: any = context.host
    local players: Players = host.Players
    local currentWorkspace: Workspace = host.workspace or workspace
    local getCharacterParts: any = host.getCharacterParts
    local layer: Frame = render:Layer("NpcEspLayer")
    local candidates: {[Model]: boolean} = {}
    local lastRender: number = -math.huge
    local bodyNames: {[string]: boolean} = {
        head = true,
        torso = true,
        uppertorso = true,
        lowertorso = true,
        humanoidrootpart = true,
        ["left arm"] = true,
        ["right arm"] = true,
        ["left leg"] = true,
        ["right leg"] = true,
        leftupperarm = true,
        rightupperarm = true,
        leftlowerarm = true,
        rightlowerarm = true,
        leftupperleg = true,
        rightupperleg = true,
        leftlowerleg = true,
        rightlowerleg = true,
        lefthand = true,
        righthand = true,
        leftfoot = true,
        rightfoot = true,
    }

    local function isRigModel(model: Model): boolean
        for _, player: Player in ipairs(players:GetPlayers()) do
            local character: Model? = player.Character
            if character and character ~= model and character:IsDescendantOf(model) then
                return false
            end
        end
        if model:FindFirstChildWhichIsA("Humanoid", true) then return true end
        local found: {[string]: boolean} = {}
        local count: number = 0
        for _, descendant: Instance in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local name: string = string.lower(descendant.Name)
                if bodyNames[name] and not found[name] then
                    found[name] = true
                    count += 1
                end
            end
        end
        local hasHead: boolean = found.head == true
        local hasTorso: boolean = found.torso == true
            or found.uppertorso == true
            or found.lowertorso == true
        return (hasHead and hasTorso and count >= 3) or count >= 6
    end

    local function addCandidate(model: Model): ()
        for existing: Model in pairs(candidates) do
            if existing:IsDescendantOf(model) then return end
            if model:IsDescendantOf(existing) then
                candidates[existing] = nil
                render:Release(layer, existing)
            end
        end
        candidates[model] = true
    end

    local function npcModel(instance: Instance): Model?
        local model: Model? = instance:IsA("Model") and instance :: Model
            or instance:FindFirstAncestorOfClass("Model") :: Model?
        while model and model ~= currentWorkspace do
            if model:IsDescendantOf(currentWorkspace)
                and model ~= host.LocalPlayer.Character
                and players:GetPlayerFromCharacter(model) == nil
                and isRigModel(model) then return model end
            local parent: Instance? = model.Parent
            model = parent and (parent:IsA("Model") and parent :: Model
                or parent:FindFirstAncestorOfClass("Model") :: Model?) or nil
        end
        return nil
    end

    local function classify(instance: Instance): ()
        if not (instance:IsA("Model") or instance:IsA("Humanoid")
            or instance:IsA("BasePart")) then return end
        local model: Model? = npcModel(instance)
        if model then addCandidate(model) end
    end

    local function forget(instance: Instance): ()
        if instance:IsA("Model") and candidates[instance :: Model] then
            candidates[instance :: Model] = nil
            render:Release(layer, instance)
        end
    end

    local function scan(): ()
        for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if descendant:IsA("Model") then classify(descendant) end
        end
    end

    local card: any
    local function clear(): ()
        render:ReleaseAll(layer)
        table.clear(candidates)
        layer.Visible = false
    end

    card = framework.Categories.Visuals:CreateModule({
        Name = "NPCESP",
        Category = "Render",
        ConfigKey = "Universal.NPCESP",
        Order = 4,
        Tooltip = "Boxes and highlights for every non-player character rig.",
        Function = function(enabled: boolean): ()
            layer.Visible = enabled
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            scan()
            card:Event(currentWorkspace.DescendantAdded, classify)
            card:Event(currentWorkspace.DescendantRemoving, forget)
            card:Render(function(): ()
                local now: number = os.clock()
                if now - lastRender < 1 / 20 then return end
                lastRender = now
                local camera: Camera? = currentWorkspace.CurrentCamera
                local _character: Model?, _humanoid: Humanoid?, localRoot: BasePart? =
                    getCharacterParts()
                if not camera then return end
                local originPosition: Vector3 = localRoot and localRoot.Position
                    or camera.CFrame.Position
                local visibleCount: number = 0
                for model: Model in pairs(candidates) do
                    local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
                    if not npcModel(model)
                        or players:GetPlayerFromCharacter(model) ~= nil
                        or model == host.LocalPlayer.Character then
                        candidates[model] = nil
                        render:Release(layer, model)
                        continue
                    end
                    if card.Options["Team check"].Value
                        and entityLibrary
                        and type(entityLibrary.IsFriendlyModel) == "function"
                        and entityLibrary:IsFriendlyModel(model) then
                        render:Release(layer, model)
                        continue
                    end
                    local root: BasePart? = model:FindFirstChild("HumanoidRootPart") :: BasePart?
                        or model.PrimaryPart
                        or model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
                    local drawing: any = render:Set(layer, model)
                    if not root or (humanoid and humanoid.Health <= 0)
                        or (root.Position - originPosition).Magnitude
                            > card.Options["Max distance"].Value then
                        drawing:Show(false)
                        continue
                    end
                    local rect: any = render:ModelRect(camera, model)
                    if not rect then
                        drawing:Show(false)
                        continue
                    end
                    local colour: Color3 = card.Options["Colour"].Value
                    drawing:Box(
                        rect,
                        card.Options["Box"].Value and "Full" or "Off",
                        1,
                        colour
                    )
                    if card.Options["Name"].Value then
                        local text: string = "BOT"
                        if card.Options["Health"].Value then
                            text ..= humanoid and (" [" .. tostring(math.round(humanoid.Health)) .. "]") or ""
                        end
                        drawing:Label(
                            "NameTag",
                            text,
                            Vector2.new(rect.centreX, rect.top - 4),
                            1,
                            13,
                            colour,
                            true
                        )
                    else
                        drawing:HideLabel("NameTag")
                    end
                    drawing:Highlight(
                        model,
                        colour,
                        0.55,
                        not card.Options["Highlight"].Value and "Off"
                            or (card.Options["Through walls"].Value
                                and "AlwaysOnTop" or "Occluded")
                    )
                    drawing:Show(true)
                    visibleCount += 1
                end
                card:SetStatus(tostring(visibleCount))
            end)
            card:Clean(clear)
        end,
    })

    card:CreateToggle({Name = "Box", Default = true})
    card:CreateToggle({Name = "Highlight", Default = true})
    card:CreateToggle({Name = "Through walls", Default = true, Show = {Option = "Highlight"}})
    card:CreateToggle({Name = "Name", Default = true})
    card:CreateToggle({Name = "Health", Default = true, Show = {Option = "Name"}})
    card:CreateToggle({
        Name = "Team check",
        Default = false,
        Tooltip = "Skip NPCs whose Team, Faction or team attribute matches yours.",
    })
    card:CreateColor({Name = "Colour", Default = Color3.fromRGB(255, 255, 255)})
    card:CreateSlider({Name = "Max distance", Min = 25, Max = 2000, Step = 25, Default = 500})

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
