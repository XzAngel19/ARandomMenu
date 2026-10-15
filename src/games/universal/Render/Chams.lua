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

    -- Role-aware games (MM2) know every player's role, so the universal
    -- teammate/team-colour options are meaningless there ("esa opcion es
    -- dedicadamente a Universal"): instead the card grows per-role ESP
    -- toggles and the fill colour follows the role colour. The active game
    -- is known when modules initialize, so the option set is fixed then.
    local roleMode: boolean = host.state ~= nil
        and host.state.activeGameName == "MM2"

    local function playerRole(player: Player): string?
        if type(gameBridge) ~= "table"
            or type(gameBridge.playerRole) ~= "function" then
            return nil
        end
        local ok: boolean, role: any = pcall(gameBridge.playerRole, player)
        if ok and type(role) == "string" then
            return role
        end
        return nil
    end

    local function playerPerk(player: Player): string?
        if type(gameBridge) ~= "table"
            or type(gameBridge.playerPerk) ~= "function" then
            return nil
        end
        local ok: boolean, perk: any = pcall(gameBridge.playerPerk, player)
        if ok and type(perk) == "string" then
            return perk
        end
        return nil
    end

    -- Same icon map the MM2 Role Tags module draws beside the murder tag.
    local PERK_ICONS: {[string]: string} = {
        ["Footsteps"] = "rbxassetid://336404773",
        ["Sleight"] = "rbxassetid://340309581",
        ["Ninja"] = "rbxassetid://416832054",
        ["Haste"] = "rbxassetid://416942717",
        ["FakeGun"] = "rbxassetid://17899774181",
        ["Fake Gun"] = "rbxassetid://17899774181",
        ["Ghost"] = "rbxassetid://335206856",
        ["Xray"] = "rbxassetid://340313896",
        ["X-Ray"] = "rbxassetid://340313896",
        ["Trap"] = "rbxassetid://4966828196",
        ["Sprint"] = "rbxassetid://4970219155",
        ["VampireBat"] = "rbxassetid://129078122681639",
        ["Bat Form"] = "rbxassetid://129078122681639",
        ["Decoy"] = "rbxassetid://113722008817201",
    }

    local perkTag: BillboardGui? = nil

    local function destroyPerkTag(): ()
        if perkTag then
            pcall(perkTag.Destroy, perkTag)
            perkTag = nil
        end
    end

    local function clear(): ()
        for player: Player, highlight: Highlight in pairs(highlights) do
            highlights[player] = nil
            highlight:Destroy()
        end
        clearNameTags()
        destroyPerkTag()
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
                    not roleMode and card.Options["Team colours"].Value
                local allowTeammates: boolean =
                    not roleMode and card.Options["Teammates"].Value
                local showRoleEsp: {[string]: boolean} = {}
                if roleMode then
                    showRoleEsp["Murderer"] =
                        card.Options["Murderer ESP"].Value ~= false
                    showRoleEsp["Sheriff"] =
                        card.Options["Sheriff ESP"].Value ~= false
                    showRoleEsp["Hero"] =
                        card.Options["Hero ESP"].Value ~= false
                    showRoleEsp["Innocent"] =
                        card.Options["Innocent ESP"].Value ~= false
                end
                local showPerk: boolean = roleMode
                    and card.Options["Show Perk"].Value ~= false
                local perkTarget: Player? = nil

                local targets: any = entity:Refresh()
                for _, target: any in ipairs(targets) do
                    local player: Player = target.Player

                    -- Universal games: the teammate toggle decides who is
                    -- highlighted. Role games: every role is known, per-role
                    -- toggles decide, and role colours always win.
                    local allowedTeam: boolean = true
                    if not roleMode then
                        local friendly: boolean = target.IsFriendly
                        if not friendly and teamCheck
                            and type(teamCheck.isSameTeam) == "function" then
                            friendly = teamCheck.isSameTeam(player)
                        end
                        allowedTeam = allowTeammates or not friendly
                    end
                    if not (allowedTeam
                        and not protectedTargets.isProtected(player)
                        and target.Character
                        and target.Humanoid
                        and target.Humanoid.Health > 0) then
                        continue
                    end

                    local roleColour: Color3? = nil
                    if roleMode then
                        local role: string? = playerRole(player)
                        if role == "Dead" then
                            continue
                        end
                        if role ~= nil then
                            if not showRoleEsp[role] then
                                continue
                            end
                            if role == "Murderer" then
                                perkTarget = player
                            end
                        end
                        roleColour = roleNameColour(player)
                    end
                    local teamColour: Color3? = nil
                    if not roleColour and useTeamColours and target.IsFriendly then
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

                -- Perk icon above the murderer (role games only).
                if roleMode and showPerk and perkTarget and perkTarget.Character then
                    local head: BasePart? = perkTarget.Character:FindFirstChild("Head")
                        or perkTarget.Character:FindFirstChild("HumanoidRootPart")
                        :: BasePart?
                    local perk: string? = head and playerPerk(perkTarget) or nil
                    if head and perk then
                        local iconId: string? = PERK_ICONS[perk]
                            or PERK_ICONS[string.gsub(perk, "%s+", "")]
                        if iconId then
                            if not perkTag
                                or not perkTag.Parent
                                or perkTag.Adornee ~= head then
                                destroyPerkTag()
                                local billboard: BillboardGui = Instance.new("BillboardGui")
                                billboard.Name = "Wurst_ChamPerk"
                                billboard.AlwaysOnTop = true
                                billboard.LightInfluence = 0
                                billboard.Size = UDim2.fromOffset(26, 26)
                                billboard.StudsOffset = Vector3.new(0, 2.9, 0)
                                billboard.MaxDistance = 1500
                                billboard.Adornee = head
                                billboard.Parent = head
                                local icon: ImageLabel = Instance.new("ImageLabel")
                                icon.Name = "Perk"
                                icon.BackgroundTransparency = 1
                                icon.Size = UDim2.fromScale(1, 1)
                                icon.Image = iconId
                                icon.Parent = billboard
                                perkTag = billboard
                            end
                            local icon: any = perkTag and perkTag:FindFirstChild("Perk")
                            if icon and icon.Image ~= iconId then
                                icon.Image = iconId
                            end
                        end
                    else
                        destroyPerkTag()
                    end
                else
                    destroyPerkTag()
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
    if roleMode then
        -- Role games (MM2): every role is known, so per-role ESP toggles
        -- replace the universal teammate options.
        card:CreateToggle({Name = "Murderer ESP", Default = true, Tooltip = "Highlight the murderer in their role colour."})
        card:CreateToggle({Name = "Sheriff ESP", Default = true, Tooltip = "Highlight the sheriff in their role colour."})
        card:CreateToggle({Name = "Hero ESP", Default = true, Tooltip = "Highlight the hero (gun picked up mid-round) in their role colour."})
        card:CreateToggle({Name = "Innocent ESP", Default = true, Tooltip = "Highlight innocents in their role colour."})
        card:CreateToggle({Name = "Show Perk", Default = true, Tooltip = "Perk icon above the murderer."})
    else
        card:CreateToggle({Name = "Teammates", Default = false, Tooltip = "Also highlight teammates. The advanced team check decides who counts."})
        card:CreateToggle({Name = "Team colours", Default = false, Tooltip = "Teammates get their Roblox team colour; everyone else keeps the fill colour. Role colours (when the game knows roles) always win."})
    end

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
