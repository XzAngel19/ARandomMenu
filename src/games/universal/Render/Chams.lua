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
    local protectedTargets: any = context.services.protectedTargets
    local currentWorkspace: Workspace = host.workspace or workspace
    local highlights: {[Player]: Highlight} = {}
    local lastUpdate: number = -math.huge

    local store: any = host.configData
    if store and store.values and store.states then
        local oldMode: any = store.values["Universal.PlayerESP.Chams"]
        if store.states["Universal.Chams"] == nil
            and (oldMode == "Overlay" or oldMode == "Outline") then
            store.states["Universal.Chams"] = true
            local fillKey: string = "Universal.Chams.Filltransparency"
            if store.values[fillKey] == nil then
                store.values[fillKey] = oldMode == "Outline" and 1 or 0.55
            end
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
        end
    end

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
                local now: number = os.clock()
                if now - lastUpdate < 0.2 then return end
                lastUpdate = now
                local seen: {[Player]: boolean} = {}
                local count: number = 0
                for _, target: any in ipairs(entity:Refresh()) do
                    local player: Player = target.Player
                    local allowedTeam: boolean = card.Options["Teammates"].Value
                        or not target.IsFriendly
                    local protected: boolean = protectedTargets.isProtected(player)
                    if allowedTeam and not protected
                        and target.Character
                        and target.Humanoid
                        and target.Humanoid.Health > 0 then
                        seen[player] = true
                        count += 1
                        local highlight: Highlight? = highlights[player]
                        if not highlight or not highlight.Parent then
                            highlight = Instance.new("Highlight")
                            highlight.Name = "Wurst_Chams"
                            highlight.Parent = currentWorkspace
                            highlights[player] = highlight
                        end
                        local resolved: Highlight = highlight :: Highlight
                        local roleColour: Color3? = nil
                        local gameBridge: any = context.services.gameBridge
                        if type(gameBridge.playerRoleColor) == "function" then
                            roleColour = gameBridge.playerRoleColor(player)
                        end
                        local fillColour: Color3 = roleColour or card.Options["Fill colour"].Value
                        local outlineColour: Color3 = roleColour or card.Options["Outline colour"].Value
                        local fillTransparency: number = card.Options["Fill transparency"].Value
                        local outlineTransparency: number = card.Options["Outline transparency"].Value
                        local depthMode: Enum.HighlightDepthMode = card.Options["Through walls"].Value
                                and Enum.HighlightDepthMode.AlwaysOnTop
                            or Enum.HighlightDepthMode.Occluded
                        if resolved.Adornee ~= target.Character then resolved.Adornee = target.Character end
                        if resolved.FillColor ~= fillColour then resolved.FillColor = fillColour end
                        if resolved.OutlineColor ~= outlineColour then resolved.OutlineColor = outlineColour end
                        if resolved.FillTransparency ~= fillTransparency then resolved.FillTransparency = fillTransparency end
                        if resolved.OutlineTransparency ~= outlineTransparency then resolved.OutlineTransparency = outlineTransparency end
                        if resolved.DepthMode ~= depthMode then resolved.DepthMode = depthMode end
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

    card:CreateColor({Name = "Fill colour", Default = Color3.fromRGB(255, 255, 255)})
    card:CreateColor({Name = "Outline colour", Default = Color3.fromRGB(255, 255, 255)})
    card:CreateSlider({Name = "Fill transparency", Min = 0, Max = 1, Step = 0.05, Default = 0.68})
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
