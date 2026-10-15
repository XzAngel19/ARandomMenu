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

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local entity: any = context.entity
    local host: any = context.host
    local protectedTargets: any = context.services.protectedTargets
    local currentWorkspace: Workspace = host.workspace or workspace
    local highlights: {[Player]: Highlight} = {}
    local murderTag: BillboardGui? = nil
    local roleTags: {[Player]: BillboardGui} = {}
    local lastUpdate: number = -math.huge

    local function destroyMurderTag(): ()
        if murderTag then
            pcall(murderTag.Destroy, murderTag)
            murderTag = nil
        end
    end

    local function clearRoleTags(): ()
        for player: Player, tag: BillboardGui in pairs(roleTags) do
            roleTags[player] = nil
            pcall(tag.Destroy, tag)
        end
    end

    local gameBridge: any = context.services.gameBridge
    if activeBridgeCleanup then
        pcall(activeBridgeCleanup)
        activeBridgeCleanup = nil
    end
    if type(gameBridge.onEvent) == "function" then
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
    end

    local card: any

    local function syncMM2Extras(enabled: boolean): ()
        if state and state.mm2Core then
            if type(state.mm2Core.toggleGunEsp) == "function" then
                pcall(state.mm2Core.toggleGunEsp, enabled and card.Options["Gun ESP"] and card.Options["Gun ESP"].Value == true)
            end
            if type(state.mm2Core.toggleTrapEsp) == "function" then
                pcall(state.mm2Core.toggleTrapEsp, enabled and card.Options["Trap ESP"] and card.Options["Trap ESP"].Value == true)
            end
        end
    end

    local function clear(): ()
        for player: Player, highlight: Highlight in pairs(highlights) do
            highlights[player] = nil
            highlight:Destroy()
        end
        destroyMurderTag()
        clearRoleTags()
        syncMM2Extras(false)
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
            syncMM2Extras(true)

            card:Render(function(): ()
                local now: number = os.clock()
                if now - lastUpdate < 0.2 then return end
                lastUpdate = now
                local seen: {[Player]: boolean} = {}
                local count: number = 0

                local targets: any = entity:Refresh()
                for _, target: any in ipairs(targets) do
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
                        if type(gameBridge.playerRoleColor) == "function" then
                            roleColour = gameBridge.playerRoleColor(player)
                        end
                        local teamColour: Color3? = nil
                        local teamOption: any = card.Options["Team colours"]
                        if not roleColour
                            and teamOption ~= nil
                            and teamOption.Value == true then
                            local isTeammate: boolean = target.IsFriendly
                                or (LocalPlayer and target.Team and LocalPlayer.Team and target.Team == LocalPlayer.Team)
                                or (LocalPlayer and player:GetAttribute("Team") ~= nil and player:GetAttribute("Team") == LocalPlayer:GetAttribute("Team"))
                            teamColour = isTeammate and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 0, 0)
                        end
                        local fillColour: Color3 = roleColour
                            or teamColour
                            or card.Options["Fill colour"].Value
                        local outlineColour: Color3 = roleColour
                            or teamColour
                            or card.Options["Outline colour"].Value
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

                local tagTarget: Player? = nil
                if card.Options["Murder tag"].Value == true
                    and type(gameBridge.playerRole) == "function" then
                    for _, target: any in ipairs(targets) do
                        local okRole: boolean, role: any = pcall(
                            gameBridge.playerRole,
                            target.Player
                        )
                        if okRole
                            and role == "Murderer"
                            and target.Character
                            and target.Humanoid
                            and target.Humanoid.Health > 0 then
                            tagTarget = target.Player
                            break
                        end
                    end
                end

                local tagHead: BasePart? = nil
                if not tagTarget then
                    destroyMurderTag()
                else
                    local tagCharacter: Model? = tagTarget.Character
                    tagHead = tagCharacter
                        and (tagCharacter:FindFirstChild("Head")
                            or tagCharacter:FindFirstChild("HumanoidRootPart"))
                        :: BasePart?
                    if not tagHead then
                        destroyMurderTag()
                    else
                        if not murderTag
                            or not murderTag.Parent
                            or murderTag.Adornee ~= tagHead then
                            destroyMurderTag()
                            local billboard: BillboardGui = Instance.new("BillboardGui")
                            billboard.Name = "Wurst_MurderTag"
                            billboard.AlwaysOnTop = true
                            billboard.LightInfluence = 0
                            billboard.Size = UDim2.fromOffset(150, 22)
                            billboard.StudsOffset = Vector3.new(0, 3.5, 0)
                            billboard.MaxDistance = 1500
                            billboard.Adornee = tagHead
                            billboard.Parent = tagHead
                            local label: TextLabel = Instance.new("TextLabel")
                            label.Name = "Murder"
                            label.BackgroundTransparency = 1
                            label.Size = UDim2.fromScale(1, 1)
                            label.Font = Enum.Font.GothamBold
                            label.TextSize = 14
                            label.TextScaled = false
                            label.Text = "Murder"
                            label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                            label.TextStrokeTransparency = 0.3
                            label.Parent = billboard

                            local icon: ImageLabel = Instance.new("ImageLabel")
                            icon.Name = "PerkIcon"
                            icon.BackgroundTransparency = 1
                            icon.ImageTransparency = 1
                            icon.Visible = false
                            icon.Size = UDim2.fromOffset(20, 20)
                            icon.Position = UDim2.new(0, 3, 0.5, 0)
                            icon.AnchorPoint = Vector2.new(0, 0.5)
                            icon.Parent = billboard

                            murderTag = billboard
                        end
                        if type(gameBridge.playerRoleColor) == "function" then
                            local okColour: boolean, colour: any = pcall(
                                gameBridge.playerRoleColor,
                                tagTarget
                            )
                            if okColour and typeof(colour) == "Color3" then
                                local label: any =
                                    murderTag and murderTag:FindFirstChild("Murder")
                                if label and label.TextColor3 ~= colour then
                                    label.TextColor3 = colour
                                end
                            end
                        end
                    end
                end

                local perkIcon: any = murderTag
                    and murderTag:FindFirstChild("PerkIcon")
                if card.Options["Show Perk"] and card.Options["Show Perk"].Value == true
                    and tagTarget and perkIcon then
                    local targetPerk: string? = nil
                    if type(gameBridge.playerPerk) == "function" then
                        targetPerk = gameBridge.playerPerk(tagTarget)
                    end
                    if not targetPerk and state and state.mm2Core and type(state.mm2Core.getPlayerPerk) == "function" then
                        targetPerk = state.mm2Core.getPlayerPerk(tagTarget)
                    end

                    local perkIconId: string? = targetPerk and (PERK_ICONS[targetPerk] or PERK_ICONS[string.gsub(targetPerk, "%s+", "")]) or nil
                    if perkIconId then
                        if perkIcon.Image ~= perkIconId then
                            perkIcon.Image = perkIconId
                        end
                        if not perkIcon.Visible then
                            perkIcon.Visible = true
                        end
                        if perkIcon.ImageTransparency ~= 0 then
                            perkIcon.ImageTransparency = 0
                        end
                    elseif perkIcon.Visible then
                        perkIcon.Visible = false
                    end
                elseif perkIcon and perkIcon.Visible then
                    perkIcon.Visible = false
                end

                local roleTagsOption: any = card.Options["Role tags"]
                if roleTagsOption and roleTagsOption.Value == true
                    and type(gameBridge.playerRole) == "function" then
                    local seenRoleTags: {[Player]: boolean} = {}
                    for _, target: any in ipairs(targets) do
                        local player: Player = target.Player
                        if player ~= LocalPlayer
                            and target.Character
                            and target.Humanoid
                            and target.Humanoid.Health > 0
                            and not protectedTargets.isProtected(player) then
                            local okRole: boolean, role: any = pcall(gameBridge.playerRole, player)
                            if okRole and type(role) == "string" and role ~= "Dead" then

                                if card.Options["Murder tag"].Value == true and (role == "Murderer" or player == tagTarget) then
                                    continue
                                end

                                local head: BasePart? = target.Character:FindFirstChild("Head")
                                    or target.Character:FindFirstChild("HumanoidRootPart")
                                if head then
                                    seenRoleTags[player] = true
                                    local tag: BillboardGui? = roleTags[player]
                                    if not tag or not tag.Parent or tag.Adornee ~= head then
                                        if tag then pcall(tag.Destroy, tag) end
                                        local billboard: BillboardGui = Instance.new("BillboardGui")
                                        billboard.Name = "Wurst_RoleTag"
                                        billboard.AlwaysOnTop = true
                                        billboard.LightInfluence = 0
                                        billboard.Size = UDim2.fromOffset(170, 24)
                                        billboard.StudsOffset = Vector3.new(0, 2.7, 0)
                                        billboard.MaxDistance = 1500
                                        billboard.Adornee = head
                                        billboard.Parent = head

                                        local label: TextLabel = Instance.new("TextLabel")
                                        label.Name = "Role"
                                        label.BackgroundTransparency = 1
                                        label.Size = UDim2.fromScale(1, 1)
                                        label.Font = Enum.Font.GothamBold
                                        label.TextSize = 14
                                        label.TextScaled = false
                                        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                                        label.TextStrokeTransparency = 0.2
                                        label.Parent = billboard

                                        roleTags[player] = billboard
                                        tag = billboard
                                    end
                                    local label: any = tag and tag:FindFirstChild("Role")
                                    if label then
                                        local roleUpper: string = string.upper(role)
                                        if label.Text ~= roleUpper then
                                            label.Text = roleUpper
                                        end
                                        if type(gameBridge.playerRoleColor) == "function" then
                                            local okColor: boolean, color: any = pcall(gameBridge.playerRoleColor, player)
                                            if okColor and typeof(color) == "Color3" then
                                                if label.TextColor3 ~= color then
                                                    label.TextColor3 = color
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    for player: Player, tag: BillboardGui in pairs(roleTags) do
                        if not seenRoleTags[player] then
                            roleTags[player] = nil
                            pcall(tag.Destroy, tag)
                        end
                    end
                else
                    clearRoleTags()
                end

                syncMM2Extras(true)
                card:SetStatus(tostring(count))
            end)
            card:Clean(clear)
        end,
    })

    card:CreateColor({Name = "Fill colour", Default = Color3.fromRGB(150, 230, 255)})
    card:CreateColor({Name = "Outline colour", Default = Color3.fromRGB(235, 250, 255)})
    card:CreateSlider({Name = "Fill transparency", Min = 0, Max = 1, Step = 0.05, Default = 0.55})
    card:CreateSlider({Name = "Outline transparency", Min = 0, Max = 1, Step = 0.05, Default = 0})
    card:CreateToggle({Name = "Through walls", Default = true})
    card:CreateToggle({Name = "Teammates", Default = false})
    card:CreateToggle({Name = "Team colours", Default = true})
    card:CreateToggle({Name = "Murder tag", Default = true})
    card:CreateToggle({Name = "Role tags", Default = true})
    card:CreateToggle({Name = "Show Perk", Default = true})
    card:CreateToggle({Name = "Gun ESP", Default = true})
    card:CreateToggle({Name = "Trap ESP", Default = true})

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
