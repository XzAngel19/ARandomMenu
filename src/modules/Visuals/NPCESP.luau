--!strict
--
-- NPC ESP.
-- Finds humanoid models that do not belong to Players and renders them through
-- the shared pool. Workspace is rescanned at a low rate, never every frame.

export type Runtime = {
    framework: any,
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
    local getCharacterParts: any = host.getCharacterParts
    local layer: Frame = render:Layer("NpcEspLayer")
    local candidates: {[Model]: Humanoid} = {}
    local nextScanAt: number = 0

    local function scan(): ()
        local found: {[Model]: Humanoid} = {}
        for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if descendant:IsA("Humanoid") then
                local model: Model? = descendant.Parent :: Model?
                if model and model:IsA("Model")
                    and players:GetPlayerFromCharacter(model) == nil then
                    found[model] = descendant :: Humanoid
                end
            end
        end
        for model: Model in pairs(candidates) do
            if not found[model] then
                render:Release(layer, model)
            end
        end
        candidates = found
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
        Tooltip = "Boxes and highlights for non-player humanoid models.",
        Function = function(enabled: boolean): ()
            layer.Visible = enabled
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            nextScanAt = 0
            card:Render(function(): ()
                local now: number = os.clock()
                if now >= nextScanAt then
                    nextScanAt = now + 0.75
                    scan()
                end
                local camera: Camera? = currentWorkspace.CurrentCamera
                local _character: Model?, _humanoid: Humanoid?, localRoot: BasePart? =
                    getCharacterParts()
                if not camera or not localRoot then
                    return
                end
                local visibleCount: number = 0
                for model: Model, humanoid: Humanoid in pairs(candidates) do
                    local root: BasePart? = model:FindFirstChild("HumanoidRootPart") :: BasePart?
                        or model.PrimaryPart
                        or model:FindFirstChildWhichIsA("BasePart") :: BasePart?
                    local drawing: any = render:Set(layer, model)
                    if not root or humanoid.Health <= 0
                        or (root.Position - localRoot.Position).Magnitude
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
                        local text: string = model.Name
                        if card.Options["Health"].Value then
                            text ..= " [" .. tostring(math.round(humanoid.Health)) .. "]"
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
    card:CreateColor({Name = "Colour", Default = Color3.fromRGB(255, 170, 0)})
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
