--!strict
--
-- Arrows.
-- Points toward live players that are outside the camera viewport. The geometry
-- is pooled by the shared renderer; no GuiObjects are allocated per frame.

export type Runtime = {
    framework: any,
    entity: any,
    render: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Arrows",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local entity: any = context.entity
    local render: any = context.render
    local protectedTargets: any = context.services.protectedTargets
    local currentWorkspace: Workspace = context.host.workspace or workspace
    local layer: Frame = render:Layer("ArrowsLayer")
    local shown: {[Player]: boolean} = {}

    local card: any
    local function clear(): ()
        render:ReleaseAll(layer)
        table.clear(shown)
        layer.Visible = false
    end

    card = framework.Categories.Visuals:CreateModule({
        Name = "Arrows",
        Category = "Render",
        ConfigKey = "Universal.Arrows",
        Order = 3,
        Tooltip = "Points toward players outside the camera view.",
        Function = function(enabled: boolean): ()
            layer.Visible = enabled
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            card:Render(function(): ()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not camera then
                    render:ReleaseAll(layer)
                    table.clear(shown)
                    return
                end
                local viewport: Vector2 = camera.ViewportSize
                local centre: Vector2 = Vector2.new(viewport.X / 2, viewport.Y / 2)
                local radius: number = math.max(40, math.min(viewport.X, viewport.Y) * 0.4)
                local seen: {[Player]: boolean} = {}
                local count: number = 0
                for _, target: any in ipairs(entity:Refresh()) do
                    local player: Player = target.Player
                    if (not card.Options["Teammates"].Value and target.IsFriendly)
                        or protectedTargets.isProtected(player)
                        or not target.Humanoid
                        or target.Humanoid.Health <= 0
                        or not target.RootPart
                        or target.Distance > card.Options["Max distance"].Value then
                        render:Release(layer, player)
                        continue
                    end
                    local projected: Vector3, onScreen: boolean =
                        camera:WorldToViewportPoint(target.RootPart.Position)
                    if onScreen then
                        render:Release(layer, player)
                        continue
                    end
                    local drawing: any = render:Set(layer, player)
                    local delta: Vector2 = Vector2.new(projected.X, projected.Y) - centre
                    if projected.Z < 0 then
                        delta = Vector2.new(-delta.X, -delta.Y)
                    end
                    if delta.Magnitude < 0.001 then
                        delta = Vector2.new(0, -1)
                    end
                    local direction: Vector2 = delta.Unit
                    local perpendicular: Vector2 = Vector2.new(-direction.Y, direction.X)
                    local tip: Vector2 = centre + direction * radius
                    local back: Vector2 = tip - direction * 16
                    local colour: Color3 = card.Options["Colour"].Value
                    drawing:Line("Arrow", 1, tip, back + perpendicular * 8, 2, colour)
                    drawing:Line("Arrow", 2, tip, back - perpendicular * 8, 2, colour)
                    drawing:HideLines("Arrow", 3, 8)
                    if card.Options["Distance"].Value then
                        drawing:Label(
                            "Distance",
                            tostring(math.round(target.Distance)) .. "m",
                            tip - direction * 26,
                            0.5,
                            12,
                            colour,
                            true
                        )
                    else
                        drawing:HideLabel("Distance")
                    end
                    drawing:Show(true)
                    seen[player] = true
                    count += 1
                end
                for player: Player in pairs(shown) do
                    if not seen[player] then
                        render:Release(layer, player)
                    end
                end
                shown = seen
                card:SetStatus(tostring(count))
            end)
            card:Clean(clear)
        end,
    })

    card:CreateColor({Name = "Colour", Default = Color3.fromRGB(0, 204, 255)})
    card:CreateToggle({Name = "Distance", Default = true})
    card:CreateSlider({Name = "Max distance", Min = 25, Max = 2000, Step = 25, Default = 500})
    card:CreateToggle({Name = "Teammates", Default = false})

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
