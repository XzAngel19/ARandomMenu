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
local activeBridgeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local entity: any = context.entity
    local host: any = context.host
    local protectedTargets: any = context.services.protectedTargets
    local gameBridge: any = context.services.gameBridge
    local teamCheck: any = host.state and host.state.teamCheck
    local currentWorkspace: Workspace = host.workspace or workspace
    local highlights: {[Player]: Highlight} = {}
    local nameTags: {[Player]: BillboardGui} = {}
    local lastUpdate: number = -math.huge

    local function roleNameColour(player: Player): Color3?
        if type(gameBridge) == "table"
            and type(gameBridge.playerRoleColor) == "function" then
            local ok: boolean, colour: any =
                pcall(gameBridge.playerRoleColor, player)
            if ok and typeof(colour) == "Color3" then
                return colour
            end
        end
        return nil
    end

    local function clearNameTags(): ()
        for player: Player, tag: BillboardGui in pairs(nameTags) do
            nameTags[player] = nil
            pcall(tag.Destroy, tag)
        end
    end

    local function clear(): ()
        for player: Player, highlight: Highlight in pairs(highlights) do
            highlights[player] = nil
            highlight:Destroy()
        end
        clearNameTags()
    end

    if type(gameBridge) == "table" and type(gameBridge.onEvent) == "function" then
        activeBridgeCleanup = gameBridge.onEvent(function(kind: string): ()
            if kind == "roleUpdate" then
                lastUpdate = -math.huge
            end
        end)
    end

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
        -- The old build shipped team colours ON by default, which painted
        -- everyone red when no team data existed. Forget that legacy state
        -- (unless the player actually customised the colours) so the new
        -- white default applies.
        local teamKey: string = "Universal.Chams.Teamcolours"
        if store.states[teamKey] == true
            and store.values["Universal.Chams.Fillcolour"] == nil
            and store.values["Universal.Chams.Outlinecolour"] == nil then
            store.states[teamKey] = false
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
        end
    end

    local card: any

    card = framework.Categories.Visuals:CreateModule({
        Name = "Chams",
        Category = "Render",
        ConfigKey = "Universal.Chams",
        Order = 2,
        Tooltip = "Highlights live players, optionally through walls, with "
            .. "optional name tags.",
        Function = function(enabled: boolean): ()
            if not enabled then
                clear()
                card:SetStatus(nil)
                return
            end
            card:SetStatus("0")

            card:Render(function(): ()
                local now: number = os.clock()
                if now - lastUpdate < 0.2 then
                    return
                end
                lastUpdate = now
                local seen: {[Player]: boolean} = {}
                local count: number = 0
                local showNames: boolean = card.Options["Nametags"].Value
                local nameMaxDistance: number =
                    card.Options["Nametag distance"].Value
                local useTeamColours: boolean =
                    card.Options["Team colours"].Value

                local targets: any = entity:Refresh()
                for _, target: any in ipairs(targets) do
                    local player: Player = target.Player
                    local friendly: boolean = target.IsFriendly
                    if not friendly and teamCheck
                        and type(teamCheck.isSameTeam) == "function" then
                        friendly = teamCheck.isSameTeam(player)
                    end
                    local allowedTeam: boolean =
                        card.Options["Teammates"].Value or not friendly
                    local protected: boolean =
                        protectedTargets.isProtected(player)
                    if allowedTeam
                        and not protected
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

                        -- Colour priority: the game's role colour (when the
                        -- game knows roles), then team colour (only when the
                        -- team-colour option is on), then the chosen fill.
                        local roleColour: Color3? = roleNameColour(player)
                        local teamColour: Color3? = nil
                        if not roleColour and useTeamColours and friendly then
                            local team: Team? = player.Team
                            if team then
                                teamColour = team.TeamColor.Color
                            end
                        end
                        local fillColour: Color3 = roleColour
                            or teamColour
                            or card.Options["Fill colour"].Value
                        local outlineColour: Color3 = roleColour
                            or teamColour
                            or card.Options["Outline colour"].Value
                        local fillTransparency: number =
                            card.Options["Fill transparency"].Value
                        local outlineTransparency: number =
                            card.Options["Outline transparency"].Value
                        local depthMode: Enum.HighlightDepthMode =
                            card.Options["Through walls"].Value
                                and Enum.HighlightDepthMode.AlwaysOnTop
                            or Enum.HighlightDepthMode.Occluded
                        if resolved.Adornee ~= target.Character then
                            resolved.Adornee = target.Character
                        end
                        if resolved.FillColor ~= fillColour then
                            resolved.FillColor = fillColour
                        end
                        if resolved.OutlineColor ~= outlineColour then
                            resolved.OutlineColor = outlineColour
                        end
                        if resolved.FillTransparency ~= fillTransparency then
                            resolved.FillTransparency = fillTransparency
                        end
                        if resolved.OutlineTransparency ~= outlineTransparency then
                            resolved.OutlineTransparency = outlineTransparency
                        end
                        if resolved.DepthMode ~= depthMode then
                            resolved.DepthMode = depthMode
                        end

                        if showNames and target.Distance <= nameMaxDistance then
                            local head: BasePart? =
                                target.Character:FindFirstChild("Head")
                                    or target.Character
                                        :FindFirstChild("HumanoidRootPart")
                                    :: BasePart?
                            if head then
                                local tag: BillboardGui? = nameTags[player]
                                if not tag
                                    or not tag.Parent
                                    or tag.Adornee ~= head then
                                    if tag then
                                        pcall(tag.Destroy, tag)
                                    end
                                    local billboard: BillboardGui =
                                        Instance.new("BillboardGui")
                                    billboard.Name = "Wurst_NameTag"
                                    billboard.AlwaysOnTop = true
                                    billboard.LightInfluence = 0
                                    billboard.Size = UDim2.fromOffset(200, 20)
                                    billboard.StudsOffset =
                                        Vector3.new(0, 2.2, 0)
                                    billboard.MaxDistance = nameMaxDistance
                                    billboard.Adornee = head
                                    billboard.Parent = head
                                    local label: TextLabel =
                                        Instance.new("TextLabel")
                                    label.Name = "Name"
                                    label.BackgroundTransparency = 1
                                    label.Size = UDim2.fromScale(1, 1)
                                    label.Font = Enum.Font.GothamBold
                                    label.TextSize = 13
                                    label.TextStrokeColor3 =
                                        Color3.fromRGB(0, 0, 0)
                                    label.TextStrokeTransparency = 0.3
                                    label.Parent = billboard
                                    nameTags[player] = billboard
                                    tag = billboard
                                end
                                local label: any =
                                    tag and tag:FindFirstChild("Name")
                                if label then
                                    local wanted: string = player.DisplayName
                                    if player.DisplayName ~= player.Name then
                                        wanted = wanted .. " ("
                                            .. player.Name .. ")"
                                    end
                                    if target.Distance > 15 then
                                        wanted = wanted .. " · "
                                            .. tostring(
                                                math.round(target.Distance)
                                            ) .. "m"
                                    end
                                    if label.Text ~= wanted then
                                        label.Text = wanted
                                    end
                                    local nameColour: Color3 = roleColour
                                        or teamColour
                                        or Color3.fromRGB(255, 255, 255)
                                    if label.TextColor3 ~= nameColour then
                                        label.TextColor3 = nameColour
                                    end
                                end
                            end
                        end
                    end
                end
                for player: Player, highlight: Highlight in pairs(highlights) do
                    if not seen[player] then
                        highlights[player] = nil
                        highlight:Destroy()
                    end
                end
                for player: Player, tag: BillboardGui in pairs(nameTags) do
                    if not seen[player] or not showNames then
                        nameTags[player] = nil
                        pcall(tag.Destroy, tag)
                    end
                end

                card:SetStatus(tostring(count))
            end)
            card:Clean(clear)
        end,
    })

    card:CreateColor({Name = "Fill colour", Default = Color3.fromRGB(255, 255, 255)})
    card:CreateColor({Name = "Outline colour", Default = Color3.fromRGB(235, 250, 255)})
    card:CreateSlider({Name = "Fill transparency", Min = 0, Max = 1, Step = 0.05, Default = 0.55})
    card:CreateSlider({Name = "Outline transparency", Min = 0, Max = 1, Step = 0.05, Default = 0})
    card:CreateToggle({Name = "Through walls", Default = true})
    card:CreateToggle({Name = "Nametags", Default = false, Tooltip = "Shows each player's name and distance above the highlight, coloured by role or team when known."})
    card:CreateSlider({Name = "Nametag distance", Min = 100, Max = 2000, Step = 100, Default = 1000, Tooltip = "How far name tags stay visible."})
    card:CreateToggle({Name = "Teammates", Default = false, Tooltip = "Also highlight teammates. The advanced team check decides who counts."})
    card:CreateToggle({Name = "Team colours", Default = false, Tooltip = "Teammates get their Roblox team colour; everyone else keeps the fill colour. Role colours (when the game knows roles) always win."})

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    if activeBridgeCleanup then
        pcall(activeBridgeCleanup)
        activeBridgeCleanup = nil
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
