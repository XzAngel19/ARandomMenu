local Module = {
    Name = "MM2 Role Tags",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Role Tags requires the MM2 core module")
    Module.Runtime = runtime
    local MM2Effects: any = core.MM2Effects
    local getPlayerRole: any = core.getPlayerRole
    local isProtectedTarget: any = core.isProtectedTarget
    local mm2Settings: any = core.mm2Settings

    -- ---------------------------------------------------------------------------
    -- Role nametags: a coloured label floating over each player's head. The
    -- murderer is the loud one (red), everything else is opt-in.
    -- ---------------------------------------------------------------------------
    local RoleTagEffects = create("Folder", {
        Parent = MM2Effects,
        Name = "RoleTags",
    })

    local ROLE_TAG_TEXT: {[string]: string} = {
        Murderer = "MURDERER",
        Sheriff = "SHERIFF",
        Hero = "HERO",
        Innocent = "INNOCENT",
        Dead = "DEAD",
    }

    local function colourForRole(role: string?): Color3
        if role == "Murderer" then return mm2Settings.murdererColor end
        if role == "Sheriff" then return mm2Settings.sheriffColor end
        if role == "Hero" then return mm2Settings.heroColor end
        if role == "Innocent" then return mm2Settings.innocentColor end
        if role == "Dead" then return mm2Settings.deadColor end
        return Color3.fromRGB(235, 235, 240)
    end

    type RoleTagRecord = {
        billboard: BillboardGui,
        label: TextLabel,
        stroke: UIStroke,
        reference: ObjectValue,
        head: BasePart?,
        role: string?,
    }

    local roleTags: {[Player]: RoleTagRecord} = {}
    local roleTagsEnabled: boolean = false

    local function destroyRoleTag(player: Player): ()
        local record: RoleTagRecord? = roleTags[player]
        if record then
            roleTags[player] = nil
            record.billboard:Destroy()
            record.reference:Destroy()
        end
    end

    local function clearRoleTags(): ()
        for player: Player, _record: RoleTagRecord in pairs(roleTags) do
            destroyRoleTag(player)
        end
    end

    local function createRoleTag(head: BasePart): RoleTagRecord
        local billboard: BillboardGui = Instance.new("BillboardGui")
        billboard.Name = "Wurst_RoleTag"
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.Size = UDim2.fromOffset(170, 24)
        billboard.StudsOffset = Vector3.new(0, 2.7, 0)
        billboard.MaxDistance = 1500
        billboard.Adornee = head
        -- A BillboardGui nested inside a ScreenGui never renders (nested layer
        -- collectors are skipped), so it lives on the part like the rest of the
        -- MM2 markers and the folder only keeps a reference for cleanup.
        billboard.Parent = head

        local reference: ObjectValue = Instance.new("ObjectValue")
        reference.Name = "RoleTagReference"
        reference.Value = billboard
        reference.Parent = RoleTagEffects

        local label: TextLabel = Instance.new("TextLabel")
        label.Name = "Role"
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.FontFace = CONTROL_FONT
        label.TextSize = 15
        label.TextScaled = false
        label.TextStrokeTransparency = 1
        label.Text = ""
        label.Parent = billboard

        local stroke: UIStroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 0, 0)
        stroke.Thickness = 2
        stroke.Transparency = 0.15
        stroke.Parent = label

        return {
            billboard = billboard,
            label = label,
            stroke = stroke,
            reference = reference,
            head = head,
            role = nil,
        }
    end

    local function refreshRoleTags(): ()
        local seen: {[Player]: boolean} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            local character: Model? = player.Character
            local head: BasePart? = character
                and (character:FindFirstChild("Head")
                    or character:FindFirstChild("HumanoidRootPart"))
                :: BasePart?
            local role: string? = character and getPlayerRole(player) or nil
            local wanted: boolean = head ~= nil
                and role ~= nil
                and role ~= "Dead"
                and player ~= LocalPlayer
                and (mm2Settings.roleTagsAll or role == "Murderer")
                and not isProtectedTarget(player)

            if wanted then
                seen[player] = true
                local record: RoleTagRecord? = roleTags[player]
                if record and (not record.billboard.Parent or record.head ~= head) then
                    destroyRoleTag(player)
                    record = nil
                end
                if not record then
                    record = createRoleTag(head :: BasePart)
                    roleTags[player] = record
                end
                local resolved: RoleTagRecord = record :: RoleTagRecord
                local colour: Color3 = colourForRole(role)
                if resolved.role ~= role then
                    resolved.role = role
                    resolved.label.Text = ROLE_TAG_TEXT[role :: string]
                        or string.upper(role :: string)
                end
                -- Re-applied every pass so the live colour pickers take effect
                -- without waiting for a role change.
                if resolved.label.TextColor3 ~= colour then
                    resolved.label.TextColor3 = colour
                    resolved.stroke.Color = Color3.new(
                        colour.R * 0.12,
                        colour.G * 0.12,
                        colour.B * 0.12
                    )
                end
            end
        end
        for player: Player, _record: RoleTagRecord in pairs(roleTags) do
            if not seen[player] then
                destroyRoleTag(player)
            end
        end
    end

    local unsubscribeRoles: () -> () = core.onRoundRoles(function(): ()
        if roleTagsEnabled then
            -- Server role pushes and tool/collision changes bypass the normal
            -- 0.35 s housekeeping interval.
            refreshRoleTags()
        end
    end)

    local function toggleRoleTags(enabled: boolean): ()
        roleTagsEnabled = enabled
        disconnectFeatureConnection("MM2RoleTags")
        clearRoleTags()
        if not enabled then
            return
        end
        local elapsed: number = 1
        featureConnections.MM2RoleTags = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.35 then
                return
            end
            elapsed = 0
            refreshRoleTags()
        end)
    end

    local RoleTagsFeature = createUniversalFeature(
        "Role Tags",
        "Floating role label over every head - the murderer in red",
        2,
        toggleRoleTags,
        {
            categoryName = "Render",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addToggleOption(
        RoleTagsFeature,
        "All roles",
        mm2Settings.roleTagsAll,
        function(value: boolean): ()
            mm2Settings.roleTagsAll = value
            clearRoleTags()
        end,
        "Off: only the murderer is tagged. On: sheriff, hero and innocents too."
    )

    activeCleanup = function(): ()
        pcall(unsubscribeRoles)
        toggleRoleTags(false)
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
