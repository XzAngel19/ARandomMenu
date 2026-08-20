--!strict
--
-- Kill Aura.
--
-- Swings whatever melee weapon you are holding at everyone around you. Vape's
-- version is one range slider, a CPS slider and an angle; this one separates
-- the three decisions that actually change how it behaves in a game:
--
--   * When to swing      — swing range, field of view, wall check, priority.
--   * How to hit         — the tool's own Activate, plus contact firing
--                          (`firetouchinterest`) for weapons that only damage
--                          on touch, at a shorter attack range.
--   * How obvious to be  — rotation off, snapped for a single frame around the
--                          swing (silent), or held on the target.
--
-- Defaults are deliberately playable: a single target, 12-stud reach, 9 swings
-- a second, a 220° field of view, walls respected and friends skipped. Turning
-- it on and leaving every option alone works; the rest is folded away behind
-- one switch.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "KillAura",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- Melee damage in Roblox arrives one of three ways, and a weapon can use any
-- combination of them, so all three are attempted per swing.
-- Weapon detection.
--
-- `character:FindFirstChildOfClass("Tool")` is not enough: plenty of games keep
-- the weapon somewhere else, hand you two tools at once, or give the sword a
-- name the module cannot guess. So the module learns instead of guessing — it
-- watches `Tool.Activated`, and whatever you swing manually becomes the weapon
-- it swings from then on. There is also a button that binds whatever is in
-- your hands right now, and a name box for the stubborn cases.
local function collectTools(localPlayer: Player): {Tool}
    local tools: {Tool} = {}
    local character: Model? = localPlayer.Character
    if character then
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(tools, child :: Tool)
            end
        end
    end
    local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, child: Instance in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(tools, child :: Tool)
            end
        end
    end
    return tools
end

local function toolHandle(tool: Tool?): BasePart?
    if not tool then
        return nil
    end
    local resolved: Tool = tool :: Tool
    local handle: Instance? = resolved:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        return handle :: BasePart
    end
    -- Some weapons name their handle anything at all; the first part in the
    -- tool is a better guess than nothing.
    for _, descendant: Instance in ipairs(resolved:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant :: BasePart
        end
    end
    return nil
end

local function activateTool(tool: Tool?): ()
    if not tool then
        return
    end
    pcall(function(): ()
        tool:Activate()
    end)
end

local function fireContact(handle: BasePart?, target: BasePart): ()
    if not handle then
        return
    end
    local environment: any = getfenv()
    local fire: any = environment.firetouchinterest
    if type(fire) ~= "function" then
        return
    end
    -- 1 = TouchEnded, 0 = TouchBegan; both are needed or the game keeps
    -- thinking the parts are still overlapping and ignores the next swing.
    pcall(fire, handle, target, 1)
    pcall(fire, handle, target, 0)
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local entityLibrary: any = context.entity
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace

    local nextSwingAt: number = 0
    local highlights: {[Player]: Highlight} = {}
    local targetPanel: any = nil

    -- Target readout, the way Vape shows it: who the aura is actually on, how
    -- much of them is left, and how far away they are — because "the aura is
    -- running" and "the aura is hitting that person" are different facts and
    -- only one of them is worth screen space.
    local function ensureTargetPanel(): any
        if targetPanel and targetPanel.root.Parent then
            return targetPanel
        end
        local root: Frame = host.create("Frame", {
            Parent = host.ScreenGui,
            Name = "KillAuraTarget",
            AnchorPoint = Vector2.new(0, 1),
            BackgroundColor3 = Color3.fromRGB(14, 14, 16),
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 18, 1, -18),
            Size = UDim2.fromOffset(188, 54),
            Visible = false,
            ZIndex = 60,
        }) :: Frame
        host.create("UICorner", {Parent = root, CornerRadius = UDim.new(0, 4)})
        host.create("UIStroke", {
            Parent = root,
            Color = Color3.fromRGB(92, 92, 98),
            Transparency = 0.6,
            Thickness = 1,
        })
        local portrait: ImageLabel = host.create("ImageLabel", {
            Parent = root,
            Name = "Portrait",
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = "",
            Position = UDim2.new(0, 8, 0.5, 0),
            Size = UDim2.fromOffset(38, 38),
            ZIndex = 61,
        }) :: ImageLabel
        local name: TextLabel = host.makeTextLabel(root, "", 12)
        name.Name = "TargetName"
        name.Position = UDim2.fromOffset(54, 8)
        name.Size = UDim2.new(1, -62, 0, 15)
        name.ZIndex = 61
        local detail: TextLabel = host.makeTextLabel(root, "", 10)
        detail.Name = "TargetDetail"
        detail.Position = UDim2.fromOffset(54, 23)
        detail.Size = UDim2.new(1, -62, 0, 13)
        detail.TextColor3 = Color3.fromRGB(158, 158, 166)
        detail.ZIndex = 61
        local track: Frame = host.create("Frame", {
            Parent = root,
            Name = "HealthTrack",
            BackgroundColor3 = Color3.fromRGB(34, 34, 38),
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(54, 40),
            Size = UDim2.new(1, -64, 0, 4),
            ZIndex = 61,
        }) :: Frame
        host.create("UICorner", {Parent = track, CornerRadius = UDim.new(1, 0)})
        local fill: Frame = host.create("Frame", {
            Parent = track,
            Name = "HealthFill",
            BackgroundColor3 = Color3.fromRGB(232, 232, 236),
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 62,
        }) :: Frame
        host.create("UICorner", {Parent = fill, CornerRadius = UDim.new(1, 0)})
        targetPanel = {
            root = root,
            portrait = portrait,
            name = name,
            detail = detail,
            fill = fill,
        }
        return targetPanel
    end

    local function showTarget(entity: any?): ()
        if not entity then
            if targetPanel and targetPanel.root.Parent then
                targetPanel.root.Visible = false
            end
            return
        end
        local panel: any = ensureTargetPanel()
        panel.root.Visible = true
        panel.portrait.Image = "rbxthumb://type=AvatarHeadShot&id="
            .. tostring(entity.Player.UserId)
            .. "&w=150&h=150"
        panel.name.Text = entity.Player.DisplayName
        panel.detail.Text = tostring(math.round(entity.Health))
            .. " hp  ·  "
            .. tostring(math.round(entity.Distance))
            .. "m"
        panel.fill.Size = UDim2.fromScale(
            math.clamp(entity.Health / math.max(entity.MaxHealth, 1), 0, 1),
            1
        )
    end

    local function clearHighlights(keep: {[Player]: boolean}?): ()
        for player: Player, highlight: Highlight in pairs(highlights) do
            if not keep or not keep[player] then
                pcall(function(): ()
                    highlight:Destroy()
                end)
                highlights[player] = nil
            end
        end
    end

    local function markTarget(entity: any, inAttackRange: boolean, options: any): ()
        if not options["Highlight targets"].Value then
            return
        end
        local existing: Highlight? = highlights[entity.Player]
        if not existing or not existing.Parent then
            local created: Highlight = Instance.new("Highlight")
            created.Name = "RTM_KillAuraTarget"
            created.FillTransparency = 0.75
            created.Parent = entity.Character
            highlights[entity.Player] = created
            existing = created
        end
        local highlight: Highlight = existing :: Highlight
        highlight.Adornee = entity.Character
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        -- Two states, because "in swing range" and "actually being hit" are
        -- different things and the gap between them is where reach cheating
        -- becomes visible.
        local colour: Color3 = inAttackRange
            and options["Attack colour"].Value
            or options["Reach colour"].Value
        highlight.FillColor = colour
        highlight.OutlineColor = colour
    end

    -- Declared before the helpers below because they read its options: the
    -- card is built further down, but `equippedTool` is written against it.
    local aura: any = nil
    local weapons: any = context.weapons

    -- The weapon the player last swung by hand. Everything else is a fallback.
    local learnedWeapon: string? = nil
    local learnConnections: {RBXScriptConnection} = {}

    local function watchTool(tool: Tool): ()
        table.insert(
            learnConnections,
            tool.Activated:Connect(function(): ()
                learnedWeapon = tool.Name
            end)
        )
    end

    local function watchAllTools(): ()
        for _, connection: RBXScriptConnection in ipairs(learnConnections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        learnConnections = {}
        for _, tool: Tool in ipairs(collectTools(localPlayer)) do
            watchTool(tool)
        end
    end

    local function matchesWanted(tool: Tool, wanted: string): boolean
        return string.find(string.lower(tool.Name), string.lower(wanted), 1, true) ~= nil
    end

    -- Order of preference: the name you typed, the weapon you last swung, then
    -- whatever is in your hands.
    local function equippedTool(): (Tool?, BasePart?)
        local character: Model? = localPlayer.Character
        if not character then
            return nil, nil
        end
        local wanted: string = tostring(aura.Options["Weapon name"].Value or "")
        local held: {Tool} = {}
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(held, child :: Tool)
            end
        end

        if wanted ~= "" then
            for _, tool: Tool in ipairs(held) do
                if matchesWanted(tool, wanted) then
                    return tool, toolHandle(tool)
                end
            end
        end
        if learnedWeapon then
            for _, tool: Tool in ipairs(held) do
                if tool.Name == learnedWeapon then
                    return tool, toolHandle(tool)
                end
            end
        end
        local first: Tool? = held[1]
        return first, toolHandle(first)
    end

    -- Equipping: the wanted weapon if the backpack has it, otherwise the first
    -- tool there, because a game that stows your sword on respawn should not
    -- end the aura.
    local function equipFromBackpack(): ()
        local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
        local humanoid: Humanoid? = localPlayer.Character
            and localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not backpack or not humanoid then
            return
        end
        local wanted: string = tostring(aura.Options["Weapon name"].Value or "")
        local chosen: Tool? = nil
        for _, child: Instance in ipairs(backpack:GetChildren()) do
            if not child:IsA("Tool") then
                continue
            end
            local tool: Tool = child :: Tool
            if wanted ~= "" and matchesWanted(tool, wanted) then
                chosen = tool
                break
            end
            if learnedWeapon and tool.Name == learnedWeapon then
                chosen = tool
                break
            end
            if not chosen then
                chosen = tool
            end
        end
        if chosen then
            pcall(function(): ()
                humanoid:EquipTool(chosen :: Tool)
            end)
        end
    end

    aura = framework.Categories.Combat:CreateModule({
        Name = "Kill Aura",
        Category = "Combat",
        Order = 1,
        Tooltip = "Swings your weapon at everyone in reach, with its own "
            .. "range, rate, field of view and rotation.",
        Function = function(enabled: boolean): ()
            nextSwingAt = 0
            if not enabled then
                clearHighlights()
                showTarget(nil)
                return
            end

            aura:Clean(function(): ()
                clearHighlights()
                showTarget(nil)
            end)
            -- Learn from the player: whichever tool they swing by hand becomes
            -- the weapon the aura uses.
            watchAllTools()
            aura:Event(localPlayer.CharacterAdded, function(): ()
                task.defer(watchAllTools)
            end)
            local backpack: Instance? = localPlayer:FindFirstChild("Backpack")
            if backpack then
                aura:Event(backpack.ChildAdded, function(child: Instance): ()
                    if child:IsA("Tool") then
                        watchTool(child :: Tool)
                    end
                end)
            end
            aura:Clean(function(): ()
                for _, connection: RBXScriptConnection in ipairs(learnConnections) do
                    pcall(function(): ()
                        connection:Disconnect()
                    end)
                end
                learnConnections = {}
            end)

            aura:Loop(function(): ()
                local options: any = aura.Options
                if options["Activation"].Value == "Hold key"
                    and not userInput:IsKeyDown(options["Hold key"].Value) then
                    clearHighlights()
                    return
                end
                if not entityLibrary:IsAlive() then
                    clearHighlights()
                    return
                end

                local tool: Tool?, handle: BasePart? = equippedTool()
                local hasPicked: boolean = #(options["Weapons"].Selected or {}) > 0
                if not tool and not hasPicked then
                    if options["Auto equip"].Value then
                        equipFromBackpack()
                    end
                    if options["Require tool"].Value then
                        -- Only meaningful when the game actually uses tools;
                        -- a ticked weapon is proof that it does not.
                        clearHighlights()
                        return
                    end
                end

                entityLibrary:Refresh()
                local targets: {any} = entityLibrary:InRange({
                    Range = options["Swing range"].Value,
                    Limit = math.round(options["Max targets"].Value),
                    IgnoreTeam = not options["Team check"].Value,
                    IgnoreWalls = not options["Wall check"].Value,
                    Angle = options["Field of view"].Value,
                    Sort = options["Priority"].Value,
                })
                if #targets == 0 then
                    clearHighlights()
                    showTarget(nil)
                    return
                end
                if options["Show target"].Value then
                    showTarget(targets[1])
                else
                    showTarget(nil)
                end

                local now: number = os.clock()
                local rate: number = math.max(options["Swings per second"].Value, 0.5)
                local jitter: number = options["Rate jitter"].Value
                local canSwing: boolean = now >= nextSwingAt
                local attackRange: number = options["Attack range"].Value
                local mode: string = options["Mode"].Value
                local keep: {[Player]: boolean} = {}

                local root: BasePart? = entityLibrary.LocalEntity
                    and entityLibrary.LocalEntity.RootPart
                local rotation: string = options["Rotation"].Value
                local originalCFrame: CFrame? = root and root.CFrame or nil

                if canSwing then
                    -- One randomised interval per swing rather than a fixed
                    -- clock: a perfectly even 9.00 CPS is the easiest thing in
                    -- the world for a server to notice.
                    nextSwingAt = now
                        + (1 / rate)
                        + (math.random() - 0.5) * 2 * jitter
                end

                if rotation ~= "Off" and root then
                    local first: any = targets[1]
                    local flat: Vector3 = first.RootPart.Position
                        * Vector3.new(1, 0, 1)
                    root.CFrame = CFrame.lookAt(
                        root.Position,
                        Vector3.new(flat.X, root.Position.Y + 0.01, flat.Z)
                    )
                end

                for index: number, entity: any in ipairs(targets) do
                    if mode == "Single" and index > 1 then
                        break
                    end
                    keep[entity.Player] = true
                    local inAttackRange: boolean = entity.Distance <= attackRange
                    markTarget(entity, inAttackRange, options)

                    if not canSwing then
                        continue
                    end
                    -- Ticked candidates first: in a game with no Tool
                    -- instances at all, they are the only thing that swings.
                    local swung: boolean = false
                    if weapons then
                        for _, label: string in ipairs(aura.Options["Weapons"].Selected or {}) do
                            local candidate: any = weapons:Find(label)
                            if candidate and weapons:Activate(candidate) then
                                swung = true
                            end
                        end
                    end
                    if not swung then
                        activateTool(tool)
                    end
                    if options["Swing only"].Value then
                        -- Swing and nothing else: the tool's own Activate, no
                        -- touch events, no reach. What a player's hand does.
                        continue
                    end
                    if not inAttackRange or not options["Contact damage"].Value then
                        continue
                    end
                    -- Contact firing needs a part to touch: the parts actually
                    -- inside the target's box, not just the root, or weapons
                    -- with limb-only hitboxes never register.
                    local overlap: OverlapParams = OverlapParams.new()
                    overlap.FilterType = Enum.RaycastFilterType.Include
                    overlap.FilterDescendantsInstances = {entity.Character}
                    local parts: {BasePart} = currentWorkspace:GetPartBoundsInBox(
                        entity.RootPart.CFrame,
                        Vector3.new(5, 6, 5),
                        overlap
                    )
                    for _, part: BasePart in ipairs(parts) do
                        fireContact(handle, part)
                    end
                end

                -- Silent rotation puts the character back the way the player
                -- left it, so the camera never fights the aura.
                if rotation == "Silent" and root and originalCFrame then
                    root.CFrame = originalCFrame :: CFrame
                end

                clearHighlights(keep)
            end)
        end,
    })

    aura:CreateSection("Weapon")
    -- Games with nine swords, a pickaxe and a mobile attack button need a set,
    -- not a guess: everything the weapon library can find is listed here and
    -- you tick the ones the aura is allowed to swing. Empty means "whatever is
    -- in my hands", which is what most games need.
    aura:CreateList({
        Name = "Weapons",
        Items = function(): {string}
            if not weapons then
                return {}
            end
            return weapons:Labels({All = true})
        end,
        EmptyText = "auto",
        Tooltip = "Tick the weapons this module may use. Covers tools, view "
            .. "models, inventory slots and the game's own attack button.",
    })
    aura:CreateTextBox({
        Name = "Weapon name",
        Default = "",
        Tooltip = "Part of the tool's name. Leave empty and the module uses "
            .. "whatever you last swung by hand.",
    })
    aura:CreateButton({
        Name = "Bind held tool",
        Tooltip = "Remembers whatever is in your hands right now.",
        Function = function(): ()
            local tool: Tool? = equippedTool()
            if not tool then
                aura:Notify("nothing equipped")
                return
            end
            learnedWeapon = (tool :: Tool).Name
            aura:Notify((tool :: Tool).Name .. " bound")
        end,
    })
    aura:CreateToggle({
        Name = "Swing only",
        Default = false,
        Tooltip = "Only press the weapon; never fire its touch events. Slower, "
            .. "but indistinguishable from swinging by hand.",
    })

    aura:CreateSection("Targeting")
    aura:CreateSlider({
        Name = "Swing range",
        Min = 5,
        Max = 60,
        Default = 12,
        Tooltip = "Distance at which the weapon starts swinging.",
    })
    aura:CreateSlider({
        Name = "Max targets",
        Min = 1,
        Max = 10,
        Default = 3,
    })
    aura:CreateDropdown({
        Name = "Mode",
        List = {"Multi", "Single"},
        Index = 1,
        Tooltip = "Multi hits everyone in reach per swing, Single sticks to "
            .. "the best target.",
    })
    aura:CreateDropdown({
        Name = "Priority",
        List = {"Distance", "Health", "Threat"},
        Index = 1,
        Tooltip = "Which target comes first: nearest, weakest, or the one "
            .. "most dangerous to you.",
    })
    aura:CreateSlider({
        Name = "Swings per second",
        Min = 1,
        Max = 20,
        Default = 9,
    })

    local advancedRows: {any} = {}
    table.insert(advancedRows, aura:CreateSection("Advanced"))
    table.insert(advancedRows, aura:CreateDropdown({
        Name = "Activation",
        List = {"Always", "Hold key"},
        Index = 1,
    }))
    table.insert(advancedRows, aura:CreateBind({
        Name = "Hold key",
        Default = Enum.KeyCode.Unknown,
    }))
    table.insert(advancedRows, aura:CreateSlider({
        Name = "Attack range",
        Min = 5,
        Max = 40,
        Default = 14,
        Tooltip = "Distance at which contact damage is fired. Keep it near "
            .. "the weapon's real reach.",
    }))
    table.insert(advancedRows, aura:CreateSlider({
        Name = "Field of view",
        Min = 30,
        Max = 360,
        Default = 220,
        Tooltip = "Degrees in front of you a target has to be inside.",
    }))
    table.insert(advancedRows, aura:CreateSlider({
        Name = "Rate jitter",
        Min = 0,
        Max = 0.2,
        Default = 0.03,
        Tooltip = "Random seconds added to or taken off each interval.",
    }))
    table.insert(advancedRows, aura:CreateDropdown({
        Name = "Rotation",
        List = {"Off", "Silent", "Face"},
        Index = 2,
        Tooltip = "Silent turns you for the swing only and puts you back; "
            .. "Face keeps you pointed at the target.",
    }))
    table.insert(advancedRows, aura:CreateToggle({
        Name = "Contact damage",
        Default = true,
        Tooltip = "Also fire the weapon's touch events. Needed by most melee "
            .. "weapons; requires firetouchinterest.",
    }))
    table.insert(advancedRows, aura:CreateToggle({
        Name = "Wall check",
        Default = true,
    }))
    table.insert(advancedRows, aura:CreateToggle({
        Name = "Team check",
        Default = true,
    }))
    table.insert(advancedRows, aura:CreateToggle({
        Name = "Require tool",
        Default = true,
        Tooltip = "Do nothing while your hands are empty.",
    }))
    table.insert(advancedRows, aura:CreateToggle({
        Name = "Auto equip",
        Default = false,
        Tooltip = "Pull the first tool out of the backpack when empty-handed.",
    }))
    table.insert(advancedRows, aura:CreateToggle({
        Name = "Highlight targets",
        Default = true,
    }))
    table.insert(advancedRows, aura:CreateToggle({
        Name = "Show target",
        Default = true,
        Tooltip = "Corner readout with the current target's avatar, health "
            .. "and distance.",
        Function = function(value: boolean): ()
            if not value then
                showTarget(nil)
            end
        end,
    }))
    table.insert(advancedRows, aura:CreateColor({
        Name = "Attack colour",
        Default = Color3.fromRGB(235, 110, 110),
    }))
    table.insert(advancedRows, aura:CreateColor({
        Name = "Reach colour",
        Default = Color3.fromRGB(150, 150, 158),
    }))

    aura:CreateToggle({
        Name = "Show advanced",
        Default = false,
        Tooltip = "Everything above works on its own; this reveals the rest.",
        Function = function(value: boolean): ()
            for _, option: any in ipairs(advancedRows) do
                option:SetVisible(value)
            end
        end,
    })

    aura:CreateNote(
        "Friend List protects players from this module in every game."
    )

    activeCleanup = function(): ()
        clearHighlights()
        if targetPanel and targetPanel.root then
            pcall(function(): ()
                targetPanel.root:Destroy()
            end)
            targetPanel = nil
        end
    end
    Module.Initialized = true
    return aura
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
