--!strict
--
-- Item Render.
--
-- Object ESP: the things a round is actually won with — chests, generators,
-- beds, ores, drops, buttons — labelled with their name and outlined through
-- walls, everywhere they exist.
--
-- The list is built by pointing at things rather than by typing. **Touch part**
-- hides the menu, waits for one tap on the world, takes the name of whatever
-- was under it and puts that name on the list; from then on *every* object with
-- that name is rendered, which is the point — one tap on one iron ore lights up
-- all of them. Names can still be typed for the cases where you know them.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "ItemRender",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

type Tracked = {
    label: TextLabel,
    billboard: BillboardGui,
    highlight: Highlight?,
}

local activeCleanup: (() -> ())? = nil

local function splitNames(text: string): {string}
    local names: {string} = {}
    for entry: string in string.gmatch(text, "[^,]+") do
        local trimmed: string = string.match(entry, "^%s*(.-)%s*$") or entry
        if trimmed ~= "" then
            table.insert(names, trimmed)
        end
    end
    return names
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local create: any = host.create
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace
    local state: any = host.state

    local tracked: {[Instance]: Tracked} = {}
    local wanted: {string} = {}
    local accumulator: number = 0
    local picking: boolean = false

    local function release(instance: Instance): ()
        local entry: Tracked? = tracked[instance]
        if not entry then
            return
        end
        tracked[instance] = nil
        pcall(function(): ()
            entry.billboard:Destroy()
        end)
        if entry.highlight then
            pcall(function(): ()
                (entry.highlight :: Highlight):Destroy()
            end)
        end
    end

    local function releaseAll(): ()
        for instance: Instance in pairs(tracked) do
            release(instance)
        end
    end

    local function matches(name: string): boolean
        local lowered: string = string.lower(name)
        for _, entry: string in ipairs(wanted) do
            if string.find(lowered, string.lower(entry), 1, true) then
                return true
            end
        end
        return false
    end

    local render: any
    render = framework.Categories.Visuals:CreateModule({
        Name = "Item Render",
        Category = "Visuals",
        Order = 2,
        Tooltip = "Names and outlines every object on the list, wherever it is.",
        Function = function(enabled: boolean): ()
            if not enabled then
                releaseAll()
                picking = false
                return
            end
            render:Clean(function(): ()
                releaseAll()
                picking = false
            end)
            render:Loop(function(deltaTime: number): ()
                accumulator += deltaTime
                if accumulator < render.Options["Refresh interval"].Value then
                    return
                end
                accumulator = 0
                Module.render(context, render, tracked, wanted, release)
            end)
        end,
    })

    -- Kept on the module so the picker and the text box agree about the list.
    local namesBox: any

    local function publishNames(text: string): ()
        wanted = splitNames(text)
        releaseAll()
    end

    render:CreateSection("Objects")
    namesBox = render:CreateTextBox({
        Name = "Names",
        Default = "",
        Tooltip = "Comma-separated. Partial names match, so chest catches "
            .. "GoldChest.",
        Function = publishNames,
    })

    render:CreateButton({
        Name = "Touch part",
        Tooltip = "Hides the menu, then adds whatever you tap next.",
        Function = function(): ()
            if picking then
                picking = false
                render:Notify("cancelled")
                return
            end
            picking = true
            -- The menu is in the way of the thing you are trying to point at,
            -- so it gets out of the way and comes back on its own.
            if state.setMenuVisible then
                state.setMenuVisible(false)
            end
            render:Notify("tap the object you want rendered")
        end,
    })

    render:CreateButton({
        Name = "Clear list",
        Function = function(): ()
            wanted = {}
            if namesBox and namesBox.Object then
                namesBox.Value = ""
                pcall(function(): ()
                    namesBox.Object.Text = ""
                end)
            end
            releaseAll()
            render:Notify("list cleared")
        end,
    })

    render:CreateSection("Display")
    render:CreateToggle({
        Name = "Show distance",
        Default = true,
    })
    render:CreateToggle({
        Name = "Outline",
        Default = true,
        Tooltip = "Draw the object's silhouette through walls.",
    })
    render:CreateSlider({
        Name = "Max distance",
        Min = 50,
        Max = 5000,
        Default = 1200,
    })
    render:CreateSlider({
        Name = "Text size",
        Min = 8,
        Max = 22,
        Default = 12,
    })
    render:CreateColor({
        Name = "Colour",
        Default = Color3.fromRGB(232, 232, 236),
    })
    render:CreateSlider({
        Name = "Refresh interval",
        Min = 0,
        Max = 1,
        Default = 0.2,
        Tooltip = "Seconds between sweeps of the workspace. Objects do not "
            .. "move as often as players do.",
    })

    -- The picker: one tap, one name, menu back.
    local pickConnection: RBXScriptConnection = userInput.InputBegan:Connect(
        function(input: InputObject, processed: boolean): ()
            if not picking or processed then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            local camera: Camera? = currentWorkspace.CurrentCamera
            if not camera then
                return
            end
            -- Screen space, because that is what an input position is.
            local ray: Ray = (camera :: Camera):ScreenPointToRay(
                input.Position.X,
                input.Position.Y
            )
            local parameters: RaycastParams = RaycastParams.new()
            parameters.FilterType = Enum.RaycastFilterType.Exclude
            parameters.IgnoreWater = true
            parameters.FilterDescendantsInstances = {
                localPlayer.Character :: any,
                camera,
            }
            local result: RaycastResult? = currentWorkspace:Raycast(
                ray.Origin,
                ray.Direction.Unit * 4096,
                parameters
            )
            if not result then
                render:Notify("nothing under that tap")
                return
            end
            picking = false

            -- The model's name beats the part's: tapping a chest should add
            -- "GoldChest", not "Lid".
            local hit: Instance = (result :: RaycastResult).Instance
            local model: Instance? = hit:FindFirstAncestorOfClass("Model")
            local name: string = model and model.Name or hit.Name
            local current: string = tostring(namesBox.Value or "")
            local updated: string = current == "" and name or (current .. ", " .. name)
            namesBox.Value = updated
            pcall(function(): ()
                namesBox.Object.Text = updated
            end)
            publishNames(updated)
            if state.setMenuVisible then
                state.setMenuVisible(true)
            end
            render:Notify(name .. " added")
        end
    )

    render:CreateNote(
        "Every object sharing the name is rendered, not just the one you tapped."
    )

    activeCleanup = function(): ()
        picking = false
        pcall(function(): ()
            pickConnection:Disconnect()
        end)
        releaseAll()
    end
    Module.Initialized = true
    return render
end

function Module.render(
    context: Runtime,
    render: any,
    tracked: {[Instance]: any},
    wanted: {string},
    release: (Instance) -> ()
): ()
    local host: any = context.host
    local create: any = host.create
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    local options: any = render.Options

    if #wanted == 0 then
        for instance: Instance in pairs(tracked) do
            release(instance)
        end
        return
    end

    local character: Model? = localPlayer.Character
    local root: BasePart? = character
        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local origin: Vector3 = root and (root :: BasePart).Position or Vector3.zero
    local maxDistance: number = options["Max distance"].Value
    local colour: Color3 = options["Colour"].Value
    local textSize: number = math.round(options["Text size"].Value)
    local seen: {[Instance]: boolean} = {}

    local function lowerMatch(name: string): boolean
        local lowered: string = string.lower(name)
        for _, entry: string in ipairs(wanted) do
            if string.find(lowered, string.lower(entry), 1, true) then
                return true
            end
        end
        return false
    end

    for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
        local isPart: boolean = descendant:IsA("BasePart")
        local isModel: boolean = descendant:IsA("Model")
        if not isPart and not isModel then
            continue
        end
        if character and descendant:IsDescendantOf(character) then
            continue
        end
        if not lowerMatch(descendant.Name) then
            continue
        end
        -- A matching model renders once, as itself; its parts are skipped so a
        -- chest does not draw twelve labels.
        if isPart and descendant:FindFirstAncestorOfClass("Model") then
            local ancestor: Instance? = descendant:FindFirstAncestorOfClass("Model")
            if ancestor and lowerMatch(ancestor.Name) then
                continue
            end
        end

        local anchor: BasePart? = nil
        if isPart then
            anchor = descendant :: BasePart
        else
            anchor = (descendant :: Model).PrimaryPart
                or (descendant :: Model):FindFirstChildWhichIsA("BasePart")
        end
        if not anchor then
            continue
        end
        local resolvedAnchor: BasePart = anchor :: BasePart
        local distance: number = (resolvedAnchor.Position - origin).Magnitude
        if distance > maxDistance then
            continue
        end

        seen[descendant] = true
        local entry: any = tracked[descendant]
        if not entry then
            local billboard: BillboardGui = create("BillboardGui", {
                Parent = resolvedAnchor,
                Name = "RTM_ItemRender",
                AlwaysOnTop = true,
                LightInfluence = 0,
                MaxDistance = maxDistance,
                Size = UDim2.fromOffset(180, 24),
                StudsOffset = Vector3.new(0, 1.6, 0),
            }) :: BillboardGui
            local label: TextLabel = host.makeTextLabel(billboard, descendant.Name, textSize)
            label.Size = UDim2.fromScale(1, 1)
            label.TextXAlignment = Enum.TextXAlignment.Center
            entry = {billboard = billboard, label = label, highlight = nil}
            tracked[descendant] = entry
        end

        entry.billboard.MaxDistance = maxDistance
        entry.label.TextColor3 = colour
        entry.label.TextSize = textSize
        entry.label.Text = options["Show distance"].Value
                and (descendant.Name .. "  " .. tostring(math.round(distance)) .. "m")
            or descendant.Name

        if options["Outline"].Value then
            local highlight: Highlight? = entry.highlight
            if not highlight or not (highlight :: Highlight).Parent then
                local created: Highlight = Instance.new("Highlight")
                created.Name = "RTM_ItemOutline"
                created.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                created.FillTransparency = 1
                created.Parent = descendant
                entry.highlight = created
                highlight = created
            end
            local resolvedHighlight: Highlight = highlight :: Highlight
            resolvedHighlight.Adornee = descendant
            resolvedHighlight.OutlineColor = colour
            resolvedHighlight.OutlineTransparency = 0
        elseif entry.highlight then
            pcall(function(): ()
                (entry.highlight :: Highlight):Destroy()
            end)
            entry.highlight = nil
        end
    end

    for instance: Instance in pairs(tracked) do
        if not seen[instance] or not instance.Parent then
            release(instance)
        end
    end
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
