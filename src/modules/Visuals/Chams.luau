--!strict
--
-- Chams.
-- Highlights live players through geometry. Inspired by Vape's Highlight mode,
-- but built on Roblox Highlight instances and this menu's module lifecycle.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Chams",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local entity: any = context.entity
    local host: any = context.host
    local currentWorkspace: Workspace = host.workspace or workspace
    local highlights: {[Player]: Highlight} = {}

    local card: any
    local function clear(): ()
        for player: Player, highlight: Highlight in pairs(highlights) do
            highlights[player] = nil
            highlight:Destroy()
        end
    end

    card = framework.Categories.Visuals:CreateModule({
        Name = "Chams",
        Category = "Render",
        ConfigKey = "Universal.Chams",
        Order = 2,
        Tooltip = "Highlights live players, optionally through walls.",
        Function = function(enabled: boolean): ()
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            card:SetStatus("0")
            card:Render(function(): ()
                local seen: {[Player]: boolean} = {}
                local count: number = 0
                for _, target: any in ipairs(entity:Refresh()) do
                    local player: Player = target.Player
                    local allowed: boolean = card.Options["Teammates"].Value
                        or not target.IsFriendly
                    if allowed and target.Character and target.Humanoid.Health > 0 then
                        seen[player] = true
                        count += 1
                        local highlight: Highlight? = highlights[player]
                        if not highlight then
                            highlight = Instance.new("Highlight")
                            highlight.Name = "ARandomMenu_Chams"
                            highlight.Parent = currentWorkspace
                            highlights[player] = highlight
                        end
                        highlight.Adornee = target.Character
                        highlight.FillColor = card.Options["Fill colour"].Value
                        highlight.OutlineColor = card.Options["Outline colour"].Value
                        highlight.FillTransparency = card.Options["Fill transparency"].Value
                        highlight.OutlineTransparency = card.Options["Outline transparency"].Value
                        highlight.DepthMode = card.Options["Through walls"].Value
                                and Enum.HighlightDepthMode.AlwaysOnTop
                            or Enum.HighlightDepthMode.Occluded
                    end
                end
                for player: Player, highlight: Highlight in pairs(highlights) do
                    if not seen[player] then
                        highlights[player] = nil
                        highlight:Destroy()
                    end
                end
                card:SetStatus(tostring(count))
            end)
            card:Clean(clear)
        end,
    })

    card:CreateColor({Name = "Fill colour", Default = Color3.fromRGB(0, 204, 255)})
    card:CreateColor({Name = "Outline colour", Default = Color3.fromRGB(255, 255, 255)})
    card:CreateSlider({Name = "Fill transparency", Min = 0, Max = 1, Step = 0.05, Default = 0.5})
    card:CreateSlider({Name = "Outline transparency", Min = 0, Max = 1, Step = 0.05, Default = 0})
    card:CreateToggle({Name = "Through walls", Default = true})
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
