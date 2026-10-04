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
    local nextStatusAt: number = 0
    local highlights: {[any]: Highlight} = {}

    local function clearHighlights(keep: {[any]: boolean}?): ()
        for key: any, highlight: Highlight in pairs(highlights) do
            if not keep or not keep[key] then
                pcall(function(): ()
                    highlight:Destroy()
                end)
                highlights[key] = nil
            end
        end
    end

    local function markTarget(entity: any, options: any): ()
        if not options["Highlight targets"].Value then
            return
        end
        local key: any = entity.Player or entity.Character
        local existing: Highlight? = highlights[key]
        if not existing or not existing.Parent then
            local created: Highlight = Instance.new("Highlight")
            created.Name = "Wurst_KillAuraTarget"
            created.FillTransparency = 0.75
            created.Parent = entity.Character
            highlights[key] = created
            existing = created
        end
        local highlight: Highlight = existing :: Highlight
        highlight.Adornee = entity.Character
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        local colour: Color3 = options["Highlight colour"].Value
        highlight.FillColor = colour
        highlight.OutlineColor = colour
    end

    local aura: any = nil
    local weapons: any = context.weapons

    local function updateTargetStatus(count: number): ()
        local now: number = os.clock()
        if now < nextStatusAt then
            return
        end
        nextStatusAt = now + 0.25
        aura:SetStatus(tostring(count) .. " in range")
    end

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

    local store: any = host.configData
    if store and store.values then
        local reachKey: string = "Universal.KillAura.Reach"
        local stored: any = store.values["Universal.KillAura.Swingrange"]
        if store.values[reachKey] == nil and type(stored) == "number" then
            store.values[reachKey] = stored
            if type(host.queueConfigSave) == "function" then
                host.queueConfigSave()
            end
        end
    end

    aura = framework.Categories.Combat:CreateModule({
        Name = "Killaura",
        Category = "Combat",
        ConfigKey = "Universal.KillAura",
        Order = 1,
        Tooltip = "Swings your weapon at everyone in reach, with its own "
            .. "range, rate, field of view and rotation.",
        Function = function(enabled: boolean): ()
            nextSwingAt = 0
            nextStatusAt = 0
            if not enabled then
                aura:SetStatus(nil)
                clearHighlights()
                return
            end
            aura:SetStatus("0 in range")

            aura:Clean(function(): ()
                clearHighlights()
            end)

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
                    updateTargetStatus(0)
                    clearHighlights()
                    return
                end
                if not entityLibrary:IsAlive() then
                    updateTargetStatus(0)
                    clearHighlights()
                    return
                end

                local tool: Tool?, handle: BasePart? = equippedTool()
                if not tool then
                    if options["Auto equip"].Value then
                        equipFromBackpack()
                    end
                    if options["Require tool"].Value then

                        updateTargetStatus(0)
                        clearHighlights()
                        return
                    end
                end

                entityLibrary:Refresh()
                local targets: {any} = entityLibrary:InRange({
                    Range = options["Reach"].Value,
                    Limit = math.round(options["Max targets"].Value),
                    IgnoreTeam = not options["Team check"].Value,
                    IgnoreWalls = not options["Wall check"].Value,
                    Angle = options["Field of view"].Value,
                    IncludeNPCs = options["Target NPCs"].Value,
                    Sort = options["Priority"].Value,
                })
                updateTargetStatus(#targets)
                if #targets == 0 then
                    clearHighlights()
                    return
                end
                local now: number = os.clock()
                local rate: number = math.max(options["Swings per second"].Value, 0.5)

                local jitter: number = 1 / rate * 0.25
                local canSwing: boolean = now >= nextSwingAt
                local keep: {[any]: boolean} = {}

                local root: BasePart? = entityLibrary.LocalEntity
                    and entityLibrary.LocalEntity.RootPart
                local rotation: string = options["Rotation"].Value
                local originalCFrame: CFrame? = root and root.CFrame or nil

                if canSwing then

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

                for _, entity: any in ipairs(targets) do
                    keep[entity.Player or entity.Character] = true
                    markTarget(entity, options)

                    if not canSwing then
                        continue
                    end

                    local swung: boolean = false
                    if weapons then
                        for _, label: string in ipairs(aura.Options["Weapons"].Selected or {}) do
                            local candidate: any = weapons:Find(label)

                        if candidate and weapons:Activate(candidate, entity) then
                                swung = true
                            end
                        end
                    end
                    if not swung and tool then
                        activateTool(tool)
                        swung = true
                    end
                    if not swung and weapons then

                        local fallback: any = weapons:Best({Melee = true})
                        swung = fallback ~= nil and weapons:Activate(fallback, entity)
                    end

                    local extraHits: number =
                        math.max(math.round(options["Hits per swing"].Value) - 1, 0)
                    for _ = 1, extraHits do
                        if tool then
                            activateTool(tool)
                        elseif weapons then
                            weapons:Swing()
                        end
                    end
                    if not options["Contact damage"].Value then

                        continue
                    end

                    if not options["Hit through walls"].Value
                        and not entityLibrary:VisibleFrom(entity) then
                        continue
                    end

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

                if rotation == "Silent" and root and originalCFrame then
                    root.CFrame = originalCFrame :: CFrame
                end

                clearHighlights(keep)
            end)
        end,
    })

    aura:CreateList({
        Name = "Weapons",
        Items = function(): {string}
            if not weapons then
                return {}
            end
            return weapons:Labels({All = true, Melee = true})
        end,

        EmptyText = "",
        Tooltip = "Melee weapons this module may swing: tools, view models, "
            .. "inventory slots and the game's own attack button. Empty means "
            .. "whatever you are holding.",
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
    aura:CreateSlider({
        Name = "Reach",
        Min = 5,
        Max = 60,
        Default = 18,
        Tooltip = "Distance at which the weapon swings and its touch events "
            .. "fire. This is the only Kill Aura distance.",
    })
    aura:CreateSlider({
        Name = "Max targets",
        Min = 1,
        Max = 10,
        Default = 3,
        Tooltip = "How many valid players or NPCs one swing may hit. One "
            .. "sticks to the best target.",
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
        Default = 8,
        Tooltip = "A fast human clicks about 8-12 times a second. Twenty is "
            .. "not a person, and a server that logs click rates knows it.",
    })

    aura:CreateDropdown({
        Name = "Activation",
        List = {"Always", "Hold key"},
        Index = 1,
    })
    aura:CreateBind({
        Name = "Hold key",
        Show = {Option = "Activation", Values = {"Hold key"}},
        Default = Enum.KeyCode.Unknown,
    })
    aura:CreateSlider({
        Name = "Field of view",
        Min = 30,
        Max = 360,
        Default = 360,
        Tooltip = "Degrees around your character. 360 scans every direction; "
            .. "this is not cursor aim.",
    })
    aura:CreateDropdown({
        Name = "Rotation",
        List = {"Off", "Silent", "Face"},
        Index = 2,
        Tooltip = "Silent turns you for the swing only and puts you back; "
            .. "Face keeps you pointed at the target.",
    })
    aura:CreateSlider({
        Name = "Hits per swing",
        Min = 1,
        Max = 8,
        Default = 1,
        Tooltip = "How many times the weapon is pressed for each swing the "
            .. "rate allows. Some games count every press.",
    })
    aura:CreateToggle({
        Name = "Hit through walls",
        Default = true,
        Tooltip = "Fire contact damage even when the target is behind "
            .. "geometry. Independent of the wall check, which decides "
            .. "whether the target is picked at all.",
    })
    aura:CreateToggle({
        Name = "Contact damage",
        Default = true,
        Tooltip = "Also fire the weapon's touch events. Needed by most melee "
            .. "weapons; requires firetouchinterest.",
    })
    aura:CreateToggle({
        Name = "Wall check",
        Default = false,
        Tooltip = "Off by default: the aura hits through walls and floors "
            .. "until you ask it not to.",
    })
    aura:CreateToggle({
        Name = "Team check",
        Default = true,
        Tooltip = "Skip teammates and Friend List entries.",
    })
    aura:CreateToggle({
        Name = "Target NPCs",
        Default = false,
        Tooltip = "Include non-player humanoid models in the reach scan.",
    })
    aura:CreateToggle({
        Name = "Require tool",
        Default = false,
        Tooltip = "Do nothing while your hands are empty.",
    })
    aura:CreateToggle({
        Name = "Auto equip",
        Default = false,
        Tooltip = "Pull the weapon out of the backpack when empty-handed. Off "
            .. "by default: most games this module helps in do not need "
            .. "anything in your hands at all.",
        Function = function(value: boolean): ()
            if weapons then
                weapons:SetAllowEquip(value)
            end
        end,
    })
    aura:CreateToggle({
        Name = "Highlight targets",
        Default = false,
    })
    aura:CreateColor({
        Name = "Highlight colour",
        Show = {Option = "Highlight targets"},
        Default = Color3.fromRGB(235, 110, 110),
    })

    aura:CreateNote(
        "Safe band: 8-12 swings a second and a reach close to the weapon's "
            .. "own. Reach is the only distance this card reads; there is no "
            .. "second, longer one. Friend List protects players from this "
            .. "module in every game."
    )

    activeCleanup = function(): ()
        clearHighlights()
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
