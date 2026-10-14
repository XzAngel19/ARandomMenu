local Module = {
    Name = "MM2 Weapon Visuals",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}
local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local core: any = state.mm2Core
    assert(type(core) == "table", "Weapon Visuals requires the MM2 core")
    Module.Runtime = runtime
    local options = {
        enabled = false, doubleGun = false, doubleKnife = false, electricKnife = false,
        color = Color3.fromRGB(100, 185, 255), intensity = 1,
    }
    local connections: {RBXScriptConnection} = {}
    local characterConnections: {RBXScriptConnection} = {}
    local visualFolder: Folder? = nil
    local electricTask: any = nil
    local arcs: {any} = {}
    local queued = false
    local generation = 0
    local rebuild: () -> ()

    local function disconnectAll(list: {RBXScriptConnection}): ()
        for _, connection in ipairs(list) do connection:Disconnect() end
        table.clear(list)
    end
    local function clearVisuals(): ()
        if electricTask then electricTask:Disconnect(); electricTask = nil end
        table.clear(arcs)
        if visualFolder then visualFolder:Destroy(); visualFolder = nil end
    end
    local function queueRebuild(): ()
        if not options.enabled or queued then return end
        queued = true
        local version = generation
        task.defer(function(): ()
            if version ~= generation then return end
            queued = false
            if options.enabled then rebuild() end
        end)
    end

    -- Clone geometry only, never a Tool/model or functional descendants. All
    -- sanitization happens detached, before anything enters the DataModel.
    local function geometryClone(source: BasePart): BasePart?
        if not (source:IsA("Part") or source:IsA("MeshPart") or source:IsA("UnionOperation")
            or source:IsA("WedgePart") or source:IsA("CornerWedgePart")) then return nil end
        local ok, copy = pcall(source.Clone, source)
        if not ok or not copy then return nil end
        copy:ClearAllChildren()
        for _, tag in ipairs(CollectionService:GetTags(copy)) do CollectionService:RemoveTag(copy, tag) end
        for key in pairs(copy:GetAttributes()) do copy:SetAttribute(key, nil) end
        copy.Name = "LocalWeaponGeometry"
        copy.Anchored = false
        copy.CanCollide = false
        copy.CanTouch = false
        copy.CanQuery = false
        copy.Massless = true
        copy.AssemblyLinearVelocity = Vector3.zero
        copy.AssemblyAngularVelocity = Vector3.zero
        -- Recreate only visual children; no nested scripts, references or tags.
        for _, child in ipairs(source:GetChildren()) do
            if child:IsA("DataModelMesh") or child:IsA("Decal")
                or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
                local childOk, visual = pcall(child.Clone, child)
                if childOk and visual then
                    visual:ClearAllChildren()
                    for _, tag in ipairs(CollectionService:GetTags(visual)) do CollectionService:RemoveTag(visual, tag) end
                    for key in pairs(visual:GetAttributes()) do visual:SetAttribute(key, nil) end
                    visual.Parent = copy
                end
            end
        end
        return copy
    end

    local function attach(part: BasePart, limb: BasePart, pose: CFrame): ()
        part.CFrame = pose
        local joint = Instance.new("WeldConstraint")
        joint.Part0 = limb
        joint.Part1 = part
        joint.Parent = part
        part.Parent = visualFolder
    end

    local function addElectric(part: BasePart): ()
        -- Own invisible carrier: the real weapon receives no children/changes.
        local carrier = Instance.new("Part")
        carrier.Name = "LocalElectricCarrier"
        carrier.Size = Vector3.new(0.05, 0.05, 0.05)
        carrier.Transparency = 1
        carrier.Anchored = false
        carrier.CanCollide = false
        carrier.CanTouch = false
        carrier.CanQuery = false
        carrier.Massless = true
        attach(carrier, part, part.CFrame)
        local size = part.Size
        local length = math.max(size.X, size.Y, size.Z, 0.5)
        local axis = size.X >= size.Y and size.X >= size.Z and Vector3.xAxis
            or (size.Y >= size.Z and Vector3.yAxis or Vector3.zAxis)
        local nodes: {Attachment} = {}
        for i = 1, 6 do
            local node = Instance.new("Attachment")
            node.Position = axis * length * ((i - 1) / 5 - 0.5)
            node.Parent = carrier
            table.insert(nodes, node)
            if i > 1 then
                local beam = Instance.new("Beam")
                beam.Attachment0 = nodes[i - 1]
                beam.Attachment1 = node
                beam.FaceCamera = true
                beam.Color = ColorSequence.new(options.color)
                beam.LightEmission = 1
                beam.Width0 = 0.02 + 0.025 * options.intensity
                beam.Width1 = beam.Width0
                beam.Transparency = NumberSequence.new(0.1)
                beam.Parent = carrier
            end
        end
        table.insert(arcs, {nodes = nodes, axis = axis, length = length})
    end

    local function visualBlade(tool: Tool): BasePart?
        local vh = tool:FindFirstChild("VH", true)
        if vh then
            if vh:IsA("BasePart") then return vh end
            local geometry = vh:FindFirstChildWhichIsA("BasePart", true)
            if geometry then return geometry end
        end
        local handle = tool:FindFirstChild("Handle")
        return handle and handle:IsA("BasePart") and handle or nil
    end

    rebuild = function(): ()
        clearVisuals()
        local character = LocalPlayer.Character
        if not options.enabled or not character then return end
        local left = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
        local right = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
        visualFolder = Instance.new("Folder")
        visualFolder.Name = "MM2LocalWeaponVisuals"
        visualFolder.Parent = workspace
        for _, kind in ipairs({"Gun", "Knife"}) do
            local tool = core.getPlayerWeapon(LocalPlayer, kind, true)
            if not tool or tool.Parent ~= character then continue end
            local double = kind == "Gun" and options.doubleGun or kind == "Knife" and options.doubleKnife
            local blade = visualBlade(tool)
            if kind == "Knife" and options.electricKnife and blade then addElectric(blade) end
            if not double or not left or not right or not left:IsA("BasePart") or not right:IsA("BasePart") then continue end
            local copied = 0
            for _, source in ipairs(tool:GetDescendants()) do
                if not source:IsA("BasePart") then continue end
                local part = geometryClone(source)
                if part then
                    attach(part, left, left.CFrame * right.CFrame:ToObjectSpace(source.CFrame))
                    if kind == "Knife" and options.electricKnife and source == blade then addElectric(part) end
                    copied += 1
                    if copied >= 64 then break end -- bounded cost for complex skins
                end
            end
        end
        if #arcs > 0 then
            local elapsed = 0
            electricTask = TaskManager:Connect(function(dt: number): ()
                elapsed += dt
                if elapsed < 0.125 then return end -- 8 Hz only while electric is visible
                elapsed = 0
                for _, arc in ipairs(arcs) do
                    for i, node in ipairs(arc.nodes) do
                        local jitter = (i == 1 or i == #arc.nodes) and Vector3.zero
                            or Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
                                * 0.22 * options.intensity
                        node.Position = arc.axis * arc.length * ((i - 1) / 5 - 0.5) + jitter
                    end
                end
            end)
        end
    end

    local function watchCharacter(character: Model): ()
        disconnectAll(characterConnections)
        clearVisuals()
        table.insert(characterConnections, character.DescendantAdded:Connect(function(object: Instance): ()
            if object:IsA("Tool") or object:IsA("BasePart") then queueRebuild() end
        end))
        table.insert(characterConnections, character.DescendantRemoving:Connect(function(object: Instance): ()
            if object:IsA("Tool") or object:IsA("BasePart") then queueRebuild() end
        end))
        queueRebuild()
    end
    local function setEnabled(enabled: boolean): ()
        generation += 1
        queued = false
        options.enabled = enabled
        disconnectAll(connections)
        disconnectAll(characterConnections)
        clearVisuals()
        if not enabled then return end
        table.insert(connections, LocalPlayer.CharacterAdded:Connect(watchCharacter))
        table.insert(connections, LocalPlayer.CharacterRemoving:Connect(function(): ()
            generation += 1
            queued = false
            disconnectAll(characterConnections)
            clearVisuals()
        end))
        if LocalPlayer.Character then watchCharacter(LocalPlayer.Character) end
    end

    local feature = createUniversalFeature("Weapon Visuals",
        "Local cosmetics only. No extra damage, unlocks or replication to other players.",
        15, setEnabled, {categoryName = "Render", parent = MM2Scroll, registry = mm2Features})
    addToggleOption(feature, "Double Gun", false, function(value: boolean): ()
        options.doubleGun = value; queueRebuild()
    end)
    addToggleOption(feature, "Double Knife", false, function(value: boolean): ()
        options.doubleKnife = value; queueRebuild()
    end)
    addToggleOption(feature, "Electric Knife", false, function(value: boolean): ()
        options.electricKnife = value; queueRebuild()
    end, "Original local beam effect, not the official inventory effect.")
    addColorOption(feature, "Electric color", options.color, function(value: Color3): ()
        options.color = value; queueRebuild()
    end)
    addNumberOption(feature, "Electric intensity", 1, 0.25, 3, function(value: number): ()
        options.intensity = math.clamp(value, 0.25, 3); queueRebuild()
    end)

    activeCleanup = function(): () setEnabled(false) end
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then return end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Runtime = nil
end
return Module
