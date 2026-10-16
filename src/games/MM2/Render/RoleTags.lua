local Module = {
    Name = "MM2 Role Tags",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

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

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Role Tags requires the MM2 core module")
    Module.Runtime = runtime

    local settings = {
        enabled = false,
        murderTag = true,
        roleTags = true,
        showPerk = true,
        gunEsp = true,
        trapEsp = true,
    }

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

    local function syncEspToggles(): ()
        if type(core.toggleGunEsp) == "function" then
            pcall(core.toggleGunEsp, settings.gunEsp)
        end
        if type(core.toggleTrapEsp) == "function" then
            pcall(core.toggleTrapEsp, settings.trapEsp)
        end
    end

    local bridge: any = services.gameBridge

    local function playerRole(player: Player): string?
        if bridge and type(bridge.playerRole) == "function" then
            local ok: boolean, role: any = pcall(bridge.playerRole, player)
            if ok and type(role) == "string" then
                return role
            end
        end
        return nil
    end

    local function playerRoleColor(player: Player): Color3?
        if bridge and type(bridge.playerRoleColor) == "function" then
            local ok: boolean, colour: any =
                pcall(bridge.playerRoleColor, player)
            if ok and typeof(colour) == "Color3" then
                return colour
            end
        end
        return nil
    end

    local function playerPerk(player: Player): string?
        if type(core.getPlayerPerk) == "function" then
            local ok: boolean, perk: any = pcall(core.getPlayerPerk, player)
            if ok and type(perk) == "string" then
                return perk
            end
        end
        return nil
    end

    local function headOf(character: Model): BasePart?
        local head: Instance? = character:FindFirstChild("Head")
            or character:FindFirstChild("HumanoidRootPart")
        if head and head:IsA("BasePart") then
            return head :: BasePart
        end
        return nil
    end

    local function update(): ()
        local now: number = os.clock()
        if now - lastUpdate < 0.2 then
            return
        end
        lastUpdate = now

        -- Murder tag: one billboard over the murderer.
        local tagTarget: Player? = nil
        if settings.murderTag then
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and player.Character
                    and player.Character:FindFirstChildOfClass("Humanoid")
                    and (player.Character:FindFirstChildOfClass("Humanoid")
                        :: Humanoid).Health > 0
                    and playerRole(player) == "Murderer" then
                    tagTarget = player
                    break
                end
            end
        end
        if not tagTarget then
            destroyMurderTag()
        else
            local head: BasePart? = headOf(tagTarget.Character :: Model)
            if not head then
                destroyMurderTag()
            else
                if not murderTag
                    or not murderTag.Parent
                    or murderTag.Adornee ~= head then
                    destroyMurderTag()
                    local billboard: BillboardGui = Instance.new("BillboardGui")
                    billboard.Name = "Wurst_MurderTag"
                    billboard.AlwaysOnTop = true
                    billboard.LightInfluence = 0
                    billboard.Size = UDim2.fromOffset(150, 22)
                    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
                    billboard.MaxDistance = 1500
                    billboard.Adornee = head
                    billboard.Parent = head
                    local label: TextLabel = Instance.new("TextLabel")
                    label.Name = "Murder"
                    label.BackgroundTransparency = 1
                    label.Size = UDim2.fromScale(1, 1)
                    label.Font = Enum.Font.GothamBold
                    label.TextSize = 14
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
                local colour: Color3? = playerRoleColor(tagTarget)
                if colour then
                    local label: any =
                        murderTag and murderTag:FindFirstChild("Murder")
                    if label and label.TextColor3 ~= colour then
                        label.TextColor3 = colour
                    end
                end
            end
        end

        -- Perk icon on the murder tag.
        local perkIcon: any = murderTag
            and murderTag:FindFirstChild("PerkIcon")
        if settings.showPerk and perkIcon and tagTarget then
            local perk: string? = playerPerk(tagTarget)
            local iconId: string? = perk
                and (PERK_ICONS[perk]
                    or PERK_ICONS[string.gsub(perk, "%s+", "")])
                or nil
            if iconId then
                if perkIcon.Image ~= iconId then
                    perkIcon.Image = iconId
                end
                perkIcon.Visible = true
                perkIcon.ImageTransparency = 0
            else
                perkIcon.Visible = false
            end
        elseif perkIcon and perkIcon.Visible then
            perkIcon.Visible = false
        end

        -- Role tags for every player with a known living role.
        if not settings.roleTags then
            clearRoleTags()
            return
        end
        local seen: {[Player]: boolean} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local character: Model? = player.Character
                local humanoid: Humanoid? = character
                    and character:FindFirstChildOfClass("Humanoid")
                    :: Humanoid?
                local role: string? = playerRole(player)
                if character
                    and humanoid
                    and (humanoid :: Humanoid).Health > 0
                    and role
                    and role ~= "Dead"
                    and not (settings.murderTag and role == "Murderer") then
                    local head: BasePart? = headOf(character :: Model)
                    if head then
                        seen[player] = true
                        local tag: BillboardGui? = roleTags[player]
                        if not tag
                            or not tag.Parent
                            or tag.Adornee ~= head then
                            if tag then
                                pcall(tag.Destroy, tag)
                            end
                            local billboard: BillboardGui =
                                Instance.new("BillboardGui")
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
                            label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                            label.TextStrokeTransparency = 0.2
                            label.Parent = billboard
                            roleTags[player] = billboard
                            tag = billboard
                        end
                        local label: any = tag and tag:FindFirstChild("Role")
                        if label then
                            local roleUpper: string = string.upper(role :: string)
                            if label.Text ~= roleUpper then
                                label.Text = roleUpper
                            end
                            local colour: Color3? = playerRoleColor(player)
                            if colour and label.TextColor3 ~= colour then
                                label.TextColor3 = colour
                            end
                        end
                    end
                end
            end
        end
        for player: Player, tag: BillboardGui in pairs(roleTags) do
            if not seen[player] then
                roleTags[player] = nil
                pcall(tag.Destroy, tag)
            end
        end
    end

    local function setEnabled(enabled: boolean): ()
        settings.enabled = enabled
        disconnectFeatureConnection("MM2RoleTags")
        destroyMurderTag()
        clearRoleTags()
        if not enabled then
            if feature then
                feature:SetStatus(nil)
            end
            return
        end
        lastUpdate = -math.huge
        featureConnections.MM2RoleTags = TaskManager:Connect(function(
            deltaTime: number
        ): ()
            update()
        end)
    end

    local feature = createUniversalFeature(
        "Role Tags",
        "MM2 role billboards: role tags, the Murder tag with perk icon, and "
            .. "gun/trap ESP",
        16,
        setEnabled,
        {
            categoryName = "Render",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    addToggleOption(
        feature,
        "Murder tag",
        settings.murderTag,
        function(value: boolean): ()
            settings.murderTag = value
        end,
        "A billboard reading MURDER over the murderer, in their role colour."
    )
    addToggleOption(
        feature,
        "Role tags",
        settings.roleTags,
        function(value: boolean): ()
            settings.roleTags = value
        end,
        "Every player's role above their head once the round reveals it."
    )
    addToggleOption(
        feature,
        "Show Perk",
        settings.showPerk,
        function(value: boolean): ()
            settings.showPerk = value
        end,
        "Perk icon beside the Murder tag."
    )
    -- Gun ESP and Trap ESP live in the universal ItemESP card now (the user
    -- asked for them there): they are registered as item providers, so the
    -- universal card keeps no MM2 knowledge of its own.
    local unregisterProviders: {() -> ()} = {}
    local itemEspService: any = services and services.itemEsp
    if itemEspService and type(itemEspService.register) == "function" then
        local function registerEsp(name: string, tooltip: string, key: string): ()
            local unregister: any = itemEspService.register({
                name = name,
                tooltip = tooltip,
                setEnabled = function(on: boolean): ()
                    settings[key] = on
                    syncEspToggles()
                end,
            })
            if type(unregister) == "function" then
                table.insert(unregisterProviders, unregister)
            end
        end
        registerEsp(
            "Gun ESP",
            "Highlights dropped and carried guns.",
            "gunEsp"
        )
        registerEsp(
            "Trap ESP",
            "Highlights murderer traps.",
            "trapEsp"
        )
    end

    activeCleanup = function(): ()
        setEnabled(false)
        for _, unregister: () -> () in ipairs(unregisterProviders) do
            pcall(unregister)
        end
        table.clear(unregisterProviders)
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
