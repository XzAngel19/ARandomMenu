export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    render: any,
    services: any,
}

local Module = {
    Name = "ItemRender",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
    layer = nil :: Frame?,
}

local activeCleanup: (() -> ())? = nil

-- Bounded template fingerprint, not semantic image recognition. Ignore names,
-- world position and colour; compare geometry and mesh asset identity instead.
function Module.appearanceSignature(object: Instance): string?
    local parts: {BasePart} = {}
    local queue: {Instance} = {object}
    local cursor: number = 1
    while cursor <= #queue do
        local node: Instance = queue[cursor]
        cursor += 1
        if node:IsA("BasePart") then table.insert(parts, node :: BasePart) end
        if #parts > 32 then return nil end
        for _, child: Instance in ipairs(node:GetChildren()) do
            if #queue >= 96 then return nil end
            table.insert(queue, child)
        end
    end
    if #parts == 0 then return nil end
    local center: Vector3 = Vector3.zero
    for _, part: BasePart in ipairs(parts) do center += part.Position end
    center /= #parts
    local function numberKey(value: number): string
        return tostring(math.round(value * 20)) -- 0.05 stud tolerance
    end
    local function vectorKey(value: Vector3): string
        return numberKey(value.X) .. "," .. numberKey(value.Y) .. "," .. numberKey(value.Z)
    end
    local tokens: {string} = {}
    for _, part: BasePart in ipairs(parts) do
        local meshId: string = ""
        local meshShape: string = ""
        if part:IsA("MeshPart") then meshId = (part :: MeshPart).MeshId end
        local mesh: SpecialMesh? = part:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh?
        if mesh then
            meshId = mesh.MeshId
            meshShape = tostring(mesh.MeshType) .. ":" .. vectorKey(mesh.Scale)
                .. ":" .. vectorKey(mesh.Offset)
        end
        local shape: string = part:IsA("Part") and tostring((part :: Part).Shape) or part.ClassName
        -- Pairwise distances preserve composition across rotation/translation.
        local distances: {string} = {}
        for _, other: BasePart in ipairs(parts) do
            table.insert(distances, numberKey((part.Position - other.Position).Magnitude))
        end
        table.sort(distances)
        table.insert(tokens, table.concat({part.ClassName, shape, vectorKey(part.Size),
            meshId, meshShape, numberKey((part.Position - center).Magnitude),
            table.concat(distances, ",")}, ":"))
    end
    table.sort(tokens)
    return table.concat(tokens, "|")
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace
    local menu: any = context.services.menu

    local tracked: {[Instance]: boolean} = {}

    local index: {Instance} = {}
    local indexConnections: {RBXScriptConnection} = {}
    local indexDirty: boolean = true

    local known: {string} = {}
    local wanted: {string} = {}
    local picking: boolean = false
    local touchMatching: string = "Appearance"
    local appearances: {[string]: string} = {}
    local signatureCache: {[Instance]: any} = setmetatable({}, {__mode = "k"})
    local profileSequence: number = 0
    local nextIndexAt: number = 0
    local nextShapeRefresh: number = 0

    local function signature(instance: Instance): string?
        if signatureCache[instance] == nil then
            signatureCache[instance] = Module.appearanceSignature(instance) or false
        end
        return signatureCache[instance] or nil
    end

    local function release(instance: Instance): ()
        if not tracked[instance] then
            return
        end
        tracked[instance] = nil
        local renderLib: any = context.render
        if renderLib and Module.layer then
            renderLib:Release(Module.layer, instance)
        end
    end

    local function releaseAll(): ()
        for instance: Instance in pairs(tracked) do
            release(instance)
        end
    end

    local function matches(instance: Instance): boolean
        local lowered: string = string.lower(instance.Name)
        for _, entry: string in ipairs(wanted) do
            local appearance: string? = appearances[entry]
            if appearance then
                if signature(instance) == appearance then return true end
            elseif not string.match(entry, "^Look #%d+ ")
                and string.find(lowered, string.lower(entry), 1, true) then
                return true
            end
        end
        return false
    end

    local function rebuildIndex(): ()
        table.clear(index)
        indexDirty = false
        if #wanted == 0 then
            return
        end
        for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if descendant:IsA("BasePart") or descendant:IsA("Model") or descendant:IsA("Tool") then
                if matches(descendant) then
                    table.insert(index, descendant)
                end
            end
        end
    end

    local function watchWorkspace(): ()
        local function changed(descendant: Instance): ()
            signatureCache[descendant] = nil
            local ancestor: Instance? = descendant.Parent
            while ancestor and ancestor ~= currentWorkspace do
                signatureCache[ancestor] = nil
                ancestor = ancestor.Parent
            end
            if #wanted > 0 then indexDirty = true end
        end
        table.insert(indexConnections, currentWorkspace.DescendantAdded:Connect(changed))
        table.insert(indexConnections, currentWorkspace.DescendantRemoving:Connect(changed))
    end

    local renderLib: any = context.render
    local layer: Frame? = renderLib and renderLib:Layer("ItemRenderLayer") or nil
    Module.layer = layer

    local itemEsp: any = context.services and context.services.itemEsp
    local providerStates: {[string]: boolean} = {}

    local function forEachProvider(callback: (any) -> ()): ()
        if not itemEsp or type(itemEsp.providers) ~= "function" then
            return
        end
        for _, provider: any in ipairs(itemEsp.providers()) do
            pcall(callback, provider)
        end
    end

    local render: any
    render = framework.Categories.Visuals:CreateModule({
        Name = "ItemESP",
        Category = "Render",
        ConfigKey = "Universal.ItemRender",
        Order = 2,
        Tooltip = "Names and outlines every object on the list, wherever it is.",
        Function = function(enabled: boolean): ()
            if layer then
                layer.Visible = enabled
            end
            if not enabled then
                forEachProvider(function(provider: any): ()
                    if providerStates[provider.name] then
                        pcall(provider.setEnabled, false)
                    end
                end)
                render:SetStatus(nil)
                releaseAll()
                picking = false
                return
            end
            forEachProvider(function(provider: any): ()
                if providerStates[provider.name] then
                    pcall(provider.setEnabled, true)
                end
            end)
            render:SetStatus("0")
            render:Clean(function(): ()
                releaseAll()
                picking = false
                if layer then
                    layer.Visible = false
                end
            end)
            indexDirty = true
            watchWorkspace()
            render:Clean(function(): ()
                for _, connection: RBXScriptConnection in ipairs(indexConnections) do
                    pcall(function(): ()
                        connection:Disconnect()
                    end)
                end
                indexConnections = {}
                table.clear(index)
            end)
            render:Render(function(): ()
                -- Assets can fill MeshId/Size after parenting (streaming).
                -- Refresh at low frequency, never traverse geometry per frame.
                if next(appearances) ~= nil and os.clock() >= nextShapeRefresh then
                    nextShapeRefresh = os.clock() + 5
                    signatureCache = setmetatable({}, {__mode = "k"})
                    indexDirty = true
                end
                if indexDirty and os.clock() >= nextIndexAt then
                    nextIndexAt = os.clock() + 0.25
                    rebuildIndex()
                end
                Module.render(context, render, tracked, wanted, release, index, matches)
            end)
        end,
    })

    local objectList: any
    objectList = render:CreateList({
        Name = "Objects",
        Items = function(): {string}
            return known
        end,
        Tooltip = "Every object the module knows about. Tick the ones to draw.",
        Function = function(_selected: any, names: {string}): ()
            wanted = names
            indexDirty = true
            releaseAll()
        end,
    })

    local function learn(name: string): ()
        if name == "" then
            return
        end
        if not table.find(known, name) then
            table.insert(known, name)
            table.sort(known)
        end
        objectList:Set(name, true)
    end

    local function findBestMatchingName(query: string): string?
        local lowered: string = string.lower(query)
        local candidates: {string} = {}
        for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
            if descendant:IsA("BasePart") or descendant:IsA("Model") or descendant:IsA("Tool") then
                local dName: string = descendant.Name
                local dLower: string = string.lower(dName)
                if dLower == lowered then
                    return dName
                end
                if string.find(dLower, lowered, 1, true) then
                    table.insert(candidates, dName)
                end
            end
        end
        for _, c: string in ipairs(candidates) do
            if string.find(string.lower(c), "^" .. lowered) then
                return c
            end
        end
        if #candidates > 0 then
            return candidates[1]
        end
        return nil
    end

    local pendingInput: string = ""
    local addBox: any

    local function commitAddByName(rawText: string?): ()
        local text: string = rawText or pendingInput
        local trimmed: string = string.match(text, "^%s*(.-)%s*$") or text
        if trimmed == "" or #trimmed < 2 then
            return
        end
        local best: string = findBestMatchingName(trimmed) or trimmed
        learn(best)
        render:Notify("Added: " .. best)
        pendingInput = ""
        if addBox and addBox.Object and typeof(addBox.Object) == "Instance" and addBox.Object:IsA("TextBox") then
            addBox.Object.Text = ""
        end
    end

    addBox = render:CreateTextBox({
        Name = "Add by name",
        Default = "",
        Tooltip = "Type a name and press Enter (or click Add Object). Finds closest matching items.",
        Function = function(value: string): ()
            pendingInput = value
        end,
    })

    if addBox and addBox.Object and typeof(addBox.Object) == "Instance" and addBox.Object:IsA("TextBox") then
        local box: TextBox = addBox.Object
        box.FocusLost:Connect(function(enterPressed: boolean)
            if enterPressed then
                commitAddByName(box.Text)
            end
        end)
    end

    render:CreateButton({
        Name = "Add object",
        Tooltip = "Adds the name typed above to the list.",
        Function = function(): ()
            local text: string = (addBox.Object and addBox.Object.Text) or pendingInput
            commitAddByName(text)
        end,
    })

    local function resolveItemInstance(part: BasePart): Instance
        local tool: Tool? = part:FindFirstAncestorOfClass("Tool")
        if tool then
            return tool
        end
        local parent: Instance? = part.Parent
        if parent and parent:IsA("Model") and parent ~= currentWorkspace then
            local parentNameLower: string = string.lower(parent.Name)
            local isGenericMap: boolean = parentNameLower == "map"
                or parentNameLower == "workspace"
                or parentNameLower == "geometry"
                or parentNameLower == "spawns"
                or parentNameLower == "terrain"
                or parentNameLower == "baseplate"
            local childCount: number = #parent:GetChildren()
            if not isGenericMap and childCount <= 15 then
                return parent
            end
        end
        return part
    end

    render:CreateDropdown({
        Name = "Touch matching",
        List = {"Appearance", "Name"},
        Index = 1,
        Function = function(value: string): () touchMatching = value end,
        Tooltip = "Appearance matches a small geometry/mesh template, not every Model. "
            .. "Templates last this session; reselect after rejoining. Name keeps the old search.",
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

            menu.setVisible(false)
            render:Notify("tap the object you want rendered")
        end,
    })

    render:CreateButton({
        Name = "Clear list",
        Function = function(): ()
            for _, name: string in ipairs(known) do
                objectList:Set(name, false)
            end
            table.clear(known)
            table.clear(appearances)
            signatureCache = setmetatable({}, {__mode = "k"})
            wanted = {}
            objectList:Refresh()
            releaseAll()
            render:Notify("list cleared")
        end,
    })

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

            local hit: Instance = (result :: RaycastResult).Instance
            if not hit:IsA("BasePart") then
                render:Notify("invalid part tapped")
                menu.setVisible(true)
                return
            end
            local targetItem: Instance = resolveItemInstance(hit :: BasePart)
            local name: string = targetItem.Name
            if touchMatching == "Appearance" then
                -- Refresh cached geometry when the user explicitly selects.
                local fingerprint: string? = Module.appearanceSignature(targetItem)
                if not fingerprint then
                    menu.setVisible(true)
                    render:Notify("Object too large/complex; select a smaller part or use Name")
                    return
                end
                profileSequence += 1
                name = "Look #" .. tostring(profileSequence) .. " (" .. name .. ")"
                appearances[name] = fingerprint
            end
            learn(name)
            menu.setVisible(true)
            render:Notify(name .. " added")
        end
    )

    render:CreateNote(
        "Touch matching: Appearance selects matching geometry in this session; Name selects by name."
    )

    -- Game-provided item highlights (for example MM2's Gun ESP and Trap ESP)
    -- appear here as their own toggles. The card itself stays game-agnostic:
    -- games register providers, this module only renders them.
    local providerOptionNames: {[string]: boolean} = {}
    local function attachProvider(provider: any): ()
        if providerOptionNames[provider.name] then
            return
        end
        providerOptionNames[provider.name] = true
        render:CreateToggle({
            Name = provider.name,
            Default = false,
            Tooltip = provider.tooltip,
            Function = function(value: boolean): ()
                providerStates[provider.name] = value
                if render.Enabled then
                    pcall(provider.setEnabled, value)
                end
            end,
        })
    end
    forEachProvider(attachProvider)
    local providerWatch: (() -> ())? = nil
    if itemEsp and type(itemEsp.onChanged) == "function" then
        providerWatch = itemEsp.onChanged(function(): ()
            forEachProvider(attachProvider)
        end)
    end

    activeCleanup = function(): ()
        if render.Enabled then render:Toggle(false) end
        picking = false
        pcall(function(): ()
            pickConnection:Disconnect()
        end)
        if providerWatch then
            pcall(providerWatch)
            providerWatch = nil
        end
        for _, connection: RBXScriptConnection in ipairs(indexConnections) do
            connection:Disconnect()
        end
        table.clear(indexConnections)
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
    release: (Instance) -> (),
    index: {Instance},
    matches: (Instance) -> boolean
): ()
    local host: any = context.host
    local renderLib: any = context.render
    local layer: Frame? = Module.layer
    local localPlayer: Player = host.LocalPlayer
    local options: any = render.Options
    local currentWorkspace: Workspace = host.workspace or workspace
    local camera: Camera? = currentWorkspace.CurrentCamera

    if #wanted == 0 or not renderLib or not layer or not camera then
        for instance: Instance in pairs(tracked) do
            release(instance)
        end
        return
    end

    local resolvedCamera: Camera = camera :: Camera
    local resolvedLayer: Frame = layer :: Frame
    local character: Model? = localPlayer.Character
    local root: BasePart? = character
        and character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local origin: Vector3 = root and (root :: BasePart).Position or Vector3.zero
    local maxDistance: number = options["Max distance"].Value
    local colour: Color3 = options["Colour"].Value
    local textSize: number = math.round(options["Text size"].Value)
    local seen: {[Instance]: boolean} = {}

    for _, descendant: Instance in ipairs(index) do
        if not descendant.Parent then
            continue
        end
        local isPart: boolean = descendant:IsA("BasePart")
        local isModel: boolean = descendant:IsA("Model") or descendant:IsA("Tool")
        if not isPart and not isModel then
            continue
        end
        if character and descendant:IsDescendantOf(character) then
            continue
        end
        if not matches(descendant) then
            continue
        end
        local duplicate: boolean = false
        local ancestor: Instance? = descendant.Parent
        while ancestor and ancestor ~= currentWorkspace do
            if (ancestor:IsA("Model") or ancestor:IsA("Tool")) and matches(ancestor) then
                duplicate = true
                break
            end
            ancestor = ancestor.Parent
        end
        if duplicate then continue end

        local anchor: BasePart? = nil
        if isPart then
            anchor = descendant :: BasePart
        else
            anchor = descendant:IsA("Model") and (descendant :: Model).PrimaryPart or nil
            anchor = anchor or descendant:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
        end
        if not anchor then
            continue
        end
        local resolvedAnchor: BasePart = anchor :: BasePart
        local distance: number = (resolvedAnchor.Position - origin).Magnitude
        if distance > maxDistance then
            continue
        end
        local projected: Vector2? = renderLib:Project(resolvedCamera, resolvedAnchor.Position)
        if not projected then
            continue
        end

        seen[descendant] = true
        tracked[descendant] = true
        local drawings: any = renderLib:Set(resolvedLayer, descendant)
        drawings:Show(true)
        drawings:Label(
            "NameTag",
            options["Show distance"].Value
                    and (descendant.Name .. "  " .. tostring(math.round(distance)) .. "m")
                or descendant.Name,
            projected :: Vector2,
            0.5,
            textSize,
            colour,
            true
        )
        drawings:Highlight(
            descendant,
            colour,
            1,
            options["Outline"].Value and "Outline" or "Off"
        )
    end

    local count: number = 0
    for instance: Instance in pairs(tracked) do
        if not seen[instance] or not instance.Parent then
            release(instance)
        else
            count += 1
        end
    end
    local status: string = tostring(count)
    if render.Status ~= status then
        render:SetStatus(status)
    end
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.layer = nil
    Module.Initialized = false
end

return Module
