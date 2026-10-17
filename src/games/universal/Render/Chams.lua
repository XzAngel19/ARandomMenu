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
    local lastUpdate: number = -math.huge
    local roles: any = nil
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

    -- MM2 perk assets; this module owns only the icon, not text labels.
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
        Tooltip = "Player highlights with independent role palettes and filters. Names and health have their own modules.",
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
                local roleMode = roles and roles.provider ~= nil
                local teamsReplaced = roleMode and roles.provider.ReplacesTeams == true
                local useTeamColours = not teamsReplaced and card.Options["Team colours"].Value
                local allowTeammates = not teamsReplaced and card.Options["Teammates"].Value
                local showPerk = card.Options["Show Perk"] and card.Options["Show Perk"].Value
                local perkTarget: Player? = nil
                local targets: any = entity:Refresh()
                -- Dead is a real MM2 role, not an inert colour row. Include
                -- existing corpse models only when the provider declares it.
                if roleMode and type(roles.provider.DeadRoles) == "table" and host.Players then
                    targets = table.clone(targets)
                    local included = {}
                    for _, target in ipairs(targets) do included[target.Player] = true end
                    for _, player in ipairs(host.Players:GetPlayers()) do
                        if player == host.LocalPlayer or included[player] then continue end
                        local character = player.Character
                        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                        if character and character.Parent and humanoid and humanoid.Health <= 0
                            and table.find(roles.provider.DeadRoles, roles:Role(player)) then
                            table.insert(targets, {Player = player, Character = character, Humanoid = humanoid,
                                IsFriendly = entity.IsFriendly and entity:IsFriendly(player) or false})
                        end
                    end
                end
                for _, target: any in ipairs(targets) do
                    local player: Player = target.Player

                    -- Universal games: the teammate toggle decides who is
                    -- highlighted. Role games: every role is known, per-role
                    -- toggles decide, and role colours always win.
                    local allowedTeam: boolean = true
                    if not teamsReplaced then
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
                        and (target.Humanoid.Health > 0 or roleMode and type(roles.provider.DeadRoles) == "table"
                            and table.find(roles.provider.DeadRoles, roles:Role(player)))) then
                        continue
                    end

                    local roleColour: Color3? = nil
                    if roleMode then
                        if not roles:Allows(player) then continue end
                        local role
                        roleColour, role = roles:Resolve(player, nil)
                        if role == "Murderer" then perkTarget = player end
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

                end

                for player: Player, highlight: Highlight in pairs(highlights) do
                    if not seen[player] then
                        highlights[player] = nil
                        highlight:Destroy()
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
                        else
                            destroyPerkTag()
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
    card:CreateToggle({Name = "Teammates", Default = false})
    card:CreateToggle({Name = "Team colours", Default = false})
    if host.state and host.state.activeGameName == "MM2" then
        card:CreateToggle({Name = "Show Perk", Default = true, Tooltip = "Perk icon above the murderer."})
    end
    roles = context.services.gameRoles:Bind(card, {filters = true})
    card.OptionFilter = function(name)
        if roles.provider and roles.provider.ReplacesTeams and (name == "Teammates" or name == "Team colours") then return false end
        if name == "Show Perk" then return roles.provider ~= nil and roles.provider.Name == "MM2" end
        return true
    end
    card:RefreshVisibility()
    Module.roles = roles
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
    if Module.roles then Module.roles:Destroy(); Module.roles = nil end
    activeCard = nil
    Module.Initialized = false
end

return Module
