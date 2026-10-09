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
    local currentWorkspace: Workspace = host.workspace or workspace
    local highlights: {[Player]: Highlight} = {}
    local murderTag: BillboardGui? = nil
    local lastUpdate: number = -math.huge

    local function destroyMurderTag(): ()
        if murderTag then
            pcall(murderTag.Destroy, murderTag)
            murderTag = nil
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
                -- Role assignment bypasses the regular 0.2 s work throttle;
                -- the next rendered frame recolours every existing highlight.
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
    local function clear(): ()
        for player: Player, highlight: Highlight in pairs(highlights) do
            highlights[player] = nil
            highlight:Destroy()
        end
        destroyMurderTag()
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
                        if type(gameBridge.playerRoleColor) == "function" then
                            roleColour = gameBridge.playerRoleColor(player)
                        end
                        -- Without a role the chams used to fall straight back
                        -- to white, which is exactly what made an undetected
                        -- MM2 innocent look like "no cham at all". Team colour
                        -- is a far better guess than white.
                        local teamColour: Color3? = nil
                        local teamOption: any = card.Options["Team colours"]
                        if not roleColour
                            and teamOption ~= nil
                            and teamOption.Value == true
                            and target.Team then
                            local ok: boolean, resolved: any = pcall(function(): any
                                return target.Team.TeamColor.Color
                            end)
                            if ok and typeof(resolved) == "Color3" then
                                teamColour = resolved
                            end
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
                -- Murder tag: the old standalone MM2 card is now an option
                -- here. The role lookup goes through the game bridge, so the
                -- tag only appears where the game exposes roles.
                local tagTarget: Player? = nil
                if card.Options["Murder tag"].Value == true
                    and type(gameBridge.playerRole) == "function" then
                    for _, target: any in ipairs(entity:Refresh()) do
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
                if not tagTarget then
                    destroyMurderTag()
                else
                    local tagCharacter: Model? = tagTarget.Character
                    local tagHead: BasePart? = tagCharacter
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
                            -- Sits above the head where the standalone card
                            -- used to place it.
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
