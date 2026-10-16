local Module = {
    Name = "MM2 Weapon Visuals",
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
    assert(type(core) == "table", "Weapon Visuals requires the MM2 core")
    Module.Runtime = runtime
    local options = {
        enabled = false,
        doubleGun = false,
        doubleKnife = false,
        electricKnife = false,
        color = Color3.fromRGB(100, 185, 255),
        intensity = 1,
        trailEsp = false,
        tracerData = false,
    }
    local connections: {RBXScriptConnection} = {}
    local characterConnections: {RBXScriptConnection} = {}
    local visualFolder: Folder? = nil
    local trailFolder: Folder? = nil
    local gunFiredConnection: any = nil
    local electricTask: any = nil
    local arcs: {any} = {}
    local queued = false
    local generation = 0
    local activeDouble = false
    local rebuild: () -> ()
    local feature: any = nil
    local warnedEmptyGeometry = false

    local function disconnectAll(list: {RBXScriptConnection}): ()
        for _, connection in ipairs(list) do
            connection:Disconnect()
        end
        table.clear(list)
    end

    -- ------------------------------------------------------------------
    -- Arm mirroring: while a double weapon is shown, the left arm chain
    -- copies the right arm's animated pose mirrored across the torso, so
    -- BOTH arms raise together (R15 shoulder/elbow/wrist and R6 shoulder).
    -- ------------------------------------------------------------------

    local function mirrorAcross(frame: CFrame, source: CFrame): CFrame
        local offset: CFrame = frame:ToObjectSpace(source)
        local position: Vector3 = offset.Position
        local right: Vector3 = offset.RightVector
        local up: Vector3 = offset.UpVector
        return frame * CFrame.fromMatrix(
            Vector3.new(-position.X, position.Y, position.Z),
            Vector3.new(right.X, -right.Y, -right.Z),
            Vector3.new(-up.X, up.Y, up.Z)
        )
    end

    local function mirrorJoint(
        joint: Motor6D,
        parentFrame: CFrame,
        desired: CFrame
    ): ()
        joint.Transform = (parentFrame * joint.C0):Inverse() * desired * joint.C1
    end

    local function findJoint(parent: Instance, names: {string}): Motor6D?
        for _, name: string in ipairs(names) do
            local joint: Instance? = parent:FindFirstChild(name)
            if joint and joint:IsA("Motor6D") then
                return joint :: Motor6D
            end
        end
        return nil
    end

    local function resetMirror(character: Model): ()
        -- Rigs differ: R15 keeps its joints inside the limb parts, R6 keeps
        -- them inside the Torso. Collect whichever exist (a plain list with
        -- possible nil holes would stop ipairs early and leave the R6
        -- shoulder frozen in its last mirrored pose).
        local candidates: {Instance} = {}
        local function consider(name: string): ()
            local found: Instance? = character:FindFirstChild(name)
            if found then
                table.insert(candidates, found)
            end
        end
        consider("LeftUpperArm")
        consider("Left Arm")
        consider("LeftLowerArm")
        consider("LeftHand")
        consider("UpperTorso")
        consider("Torso")
        for _, holder: Instance in ipairs(candidates) do
            for _, child: Instance in ipairs(holder:GetChildren()) do
                if child:IsA("Motor6D")
                    and string.find(child.Name, "Left") then
                    (child :: Motor6D).Transform = CFrame.new()
                end
            end
        end
    end

    local function mirrorArms(character: Model): ()
        if not activeDouble then
            return
        end
        local torso: BasePart? = (character:FindFirstChild("UpperTorso")
            or character:FindFirstChild("Torso")) :: BasePart?
        if not torso then
            return
        end
        local rUpper: BasePart? = (character:FindFirstChild("RightUpperArm")
            or character:FindFirstChild("Right Arm")) :: BasePart?
        local lUpper: BasePart? = (character:FindFirstChild("LeftUpperArm")
            or character:FindFirstChild("Left Arm")) :: BasePart?
        if not rUpper or not lUpper then
            return
        end
        local rLower: BasePart? =
            character:FindFirstChild("RightLowerArm") :: BasePart?
        local lLower: BasePart? =
            character:FindFirstChild("LeftLowerArm") :: BasePart?
        local rHand: BasePart? =
            character:FindFirstChild("RightHand") :: BasePart?
        local lHand: BasePart? = character:FindFirstChild("LeftHand") :: BasePart?

        local leftShoulder: Motor6D? =
            findJoint(lUpper, {"LeftShoulder", "Left Shoulder"})
                or findJoint(torso, {"Left Shoulder", "LeftShoulder"})
        if not leftShoulder then
            return
        end
        local frame: CFrame = (torso :: BasePart).CFrame
        local desiredUpper: CFrame =
            mirrorAcross(frame, (rUpper :: BasePart).CFrame)
        mirrorJoint(leftShoulder :: Motor6D, frame, desiredUpper)

        if rLower and lLower then
            local leftElbow: Motor6D? = findJoint(lLower, {"LeftElbow"})
            if leftElbow then
                local desiredLower: CFrame =
                    mirrorAcross(frame, (rLower :: BasePart).CFrame)
                mirrorJoint(leftElbow :: Motor6D, desiredUpper, desiredLower)
                if rHand and lHand then
                    local leftWrist: Motor6D? =
                        findJoint(lHand, {"LeftWrist"})
                    if leftWrist then
                        local desiredHand: CFrame =
                            mirrorAcross(frame, (rHand :: BasePart).CFrame)
                        mirrorJoint(
                            leftWrist :: Motor6D,
                            desiredLower,
                            desiredHand
                        )
                    end
                end
            end
        end
    end

    -- ------------------------------------------------------------------

    local function clearVisuals(): ()
        if electricTask then
            electricTask:Disconnect()
            electricTask = nil
        end
        table.clear(arcs)
        if visualFolder then
            visualFolder:Destroy()
            visualFolder = nil
        end
        if activeDouble then
            activeDouble = false
            local character: Model? = LocalPlayer.Character
            if character then
                pcall(resetMirror, character :: Model)
            end
        end
    end

    local function queueRebuild(): ()
        if not options.enabled or queued then
            return
        end
        queued = true
        local version: number = generation
        task.defer(function(): ()
            if version ~= generation then
                return
            end
            queued = false
            if not options.enabled then
                return
            end
            local ok: boolean, failure: any = pcall(rebuild)
            if not ok then
                warn("[Wurst] Weapon Visuals rebuild failed: "
                    .. tostring(failure))
            end
        end)
    end

    -- Clone geometry only, never a Tool/model or functional descendants. All
    -- sanitization happens detached, before anything enters the DataModel.
    local function geometryClone(source: BasePart): BasePart?
        if not (source:IsA("Part") or source:IsA("MeshPart") or source:IsA("UnionOperation")
            or source:IsA("WedgePart") or source:IsA("CornerWedgePart")) then
            return nil
        end
        local ok: boolean, copy: any = pcall(source.Clone, source)
        if not ok or not copy then
            return nil
        end
        copy:ClearAllChildren()
        for _, tag: string in ipairs(CollectionService:GetTags(copy)) do
            CollectionService:RemoveTag(copy, tag)
        end
        for key: string in pairs(copy:GetAttributes()) do
            copy:SetAttribute(key, nil)
        end
        copy.Name = "LocalWeaponGeometry"
        copy.Anchored = false
        copy.CanCollide = false
        copy.CanTouch = false
        copy.CanQuery = false
        copy.Massless = true
        copy.AssemblyLinearVelocity = Vector3.zero
        copy.AssemblyAngularVelocity = Vector3.zero
        -- Recreate only visual children; no nested scripts, references or tags.
        for _, child: Instance in ipairs(source:GetChildren()) do
            if child:IsA("DataModelMesh") or child:IsA("Decal")
                or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
                local childOk: boolean, visual: any = pcall(child.Clone, child)
                if childOk and visual then
                    visual:ClearAllChildren()
                    for _, tag: string in ipairs(CollectionService:GetTags(visual)) do
                        CollectionService:RemoveTag(visual, tag)
                    end
                    for key: string in pairs(visual:GetAttributes()) do
                        visual:SetAttribute(key, nil)
                    end
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
        local size: Vector3 = part.Size
        local length: number = math.max(size.X, size.Y, size.Z, 0.5)
        local axis: Vector3 = size.X >= size.Y and size.X >= size.Z and Vector3.xAxis
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
        local vh: Instance? = tool:FindFirstChild("VH", true)
        if vh then
            if vh:IsA("BasePart") then
                return vh :: BasePart
            end
            local geometry: Instance? = vh:FindFirstChildWhichIsA("BasePart", true)
            if geometry then
                return geometry :: BasePart
            end
        end
        local handle: Instance? = tool:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            return handle :: BasePart
        end
        return (tool:FindFirstChildWhichIsA("BasePart", true) :: BasePart?)
    end

    local function equippedWeapon(kind: string): Tool?
        local weapon: Tool? = core.getPlayerWeapon(LocalPlayer, kind, true)
        if weapon then
            return weapon
        end
        -- Fall back to a plain name match: visual-only, and it keeps the
        -- module working if the game renames or drops its weapon tags.
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil
        end
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool")
                and string.find(
                    string.lower(child.Name),
                    string.lower(kind),
                    1,
                    true
                ) then
                return child :: Tool
            end
        end
        return nil
    end
    -- ------------------------------------------------------------------
    -- TrailESP + Tracer Data. The server replicates every accepted shot
    -- through WeaponService.GunFired(gunHandle, origin, hitPosition,
    -- hitPart): that is the ground truth of where the bullet actually
    -- landed, for everyone's shots including our own.
    -- ------------------------------------------------------------------

    local function ensureTrailFolder(): Folder
        if not trailFolder or not trailFolder.Parent then
            trailFolder = Instance.new("Folder")
            trailFolder.Name = "MM2TrailESP"
            trailFolder.Parent = workspace
        end
        return trailFolder :: Folder
    end

    local function clearTrails(): ()
        if trailFolder then
            pcall(function(): () trailFolder:Destroy() end)
            trailFolder = nil
        end
    end

    local function drawShotTrail(origin: Vector3, hit: Vector3, hitPart: any): ()
        local folder: Folder = ensureTrailFolder()
        local segment: Vector3 = hit - origin
        local length: number = segment.Magnitude
        if length > 0.5 then
            local beam: Part = Instance.new("Part")
            beam.Name = "TrailSegment"
            beam.Anchored = true
            beam.CanCollide = false
            beam.CanQuery = false
            beam.CanTouch = false
            beam.CastShadow = false
            beam.Material = Enum.Material.Neon
            beam.Color = options.color
            beam.Transparency = 0.25
            beam.Size = Vector3.new(0.07, 0.07, length)
            beam.CFrame = CFrame.lookAt(origin + segment * 0.5, hit)
            beam.Parent = folder
            pcall(function(): ()
                TweenService:Create(
                    beam,
                    TweenInfo.new(1.4, Enum.EasingStyle.Linear),
                    { Transparency = 1 }
                ):Play()
            end)
            task.delay(1.55, function(): ()
                if beam.Parent then
                    pcall(function(): () beam:Destroy() end)
                end
            end)
        end
        local marker: Part = Instance.new("Part")
        marker.Name = "TrailLanding"
        marker.Shape = Enum.PartType.Ball
        marker.Anchored = true
        marker.CanCollide = false
        marker.CanQuery = false
        marker.CanTouch = false
        marker.CastShadow = false
        marker.Material = Enum.Material.Neon
        marker.Color = options.color
        marker.Size = Vector3.new(0.5, 0.5, 0.5)
        marker.Position = hit
        marker.Parent = folder
        if typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") then
            local highlight: Highlight = Instance.new("Highlight")
            highlight.Name = "TrailHitESP"
            highlight.FillColor = options.color
            highlight.OutlineColor = options.color
            highlight.FillTransparency = 0.55
            highlight.OutlineTransparency = 0.1
            highlight.Adornee = hitPart
            highlight.Parent = folder
            task.delay(1.55, function(): ()
                if highlight.Parent then
                    pcall(function(): () highlight:Destroy() end)
                end
            end)
        end
        pcall(function(): ()
            TweenService:Create(
                marker,
                TweenInfo.new(1.4, Enum.EasingStyle.Linear),
                { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 }
            ):Play()
        end)
        task.delay(1.55, function(): ()
            if marker.Parent then
                pcall(function(): () marker:Destroy() end)
            end
        end)
    end

    local function reportTracerData(origin: Vector3, hit: Vector3): ()
        -- Where OUR bullet landed vs where the murderer actually was when
        -- the server processed the shot: the honest miss distance.
        local murderer: Player? = core.findMurderer()
        if not murderer or not murderer.Character then
            return
        end
        local root: BasePart? = murderer.Character:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        if not root then
            return
        end
        local missStuds: number = (hit - root.Position).Magnitude
        local shotRange: number = (hit - origin).Magnitude
        notify(string.format(
            "Tracer: landed %.1f studs from %s (shot range %.0f)",
            missStuds,
            murderer.DisplayName,
            shotRange
        ))
    end

    local function connectGunFired(): ()
        if gunFiredConnection then
            return
        end
        local ok: boolean, weaponService: any = pcall(function(): any
            local replicatedStorage: any = game:GetService("ReplicatedStorage")
            local clientServices: any = replicatedStorage:FindFirstChild("ClientServices")
            return clientServices and clientServices:FindFirstChild("WeaponService") or nil
        end)
        if not ok or type(weaponService) ~= "table" and typeof(weaponService) ~= "Instance" then
            return
        end
        local gunFired: any = typeof(weaponService) == "table"
            and weaponService.GunFired
            or weaponService:FindFirstChild("GunFired")
        if not gunFired then
            return
        end
        local okConnect: boolean, connection: any = pcall(function(): any
            return gunFired.OnClientEvent:Connect(function(
                gunHandle: any,
                originValue: any,
                hitValue: any,
                hitPart: any
            ): ()
                local origin: Vector3? = typeof(originValue) == "Vector3"
                    and originValue or nil
                local hit: Vector3? = typeof(hitValue) == "Vector3"
                    and hitValue or nil
                if not origin or not hit then
                    return
                end
                if options.trailEsp then
                    drawShotTrail(origin :: Vector3, hit :: Vector3, hitPart)
                end
                if options.tracerData then
                    local character: Model? = LocalPlayer.Character
                    local isOurGun: boolean = typeof(gunHandle) == "Instance"
                        and character ~= nil
                        and gunHandle:IsDescendantOf(character)
                    if isOurGun then
                        reportTracerData(
                            origin :: Vector3,
                            hit :: Vector3
                        )
                    end
                end
            end)
        end)
        if okConnect and connection then
            gunFiredConnection = connection
        end
    end

    local function disconnectGunFired(): ()
        if gunFiredConnection then
            pcall(function(): () gunFiredConnection:Disconnect() end)
            gunFiredConnection = nil
        end
        clearTrails()
    end

    rebuild = function(): ()
        clearVisuals()
        local character: Model? = LocalPlayer.Character
        if not options.enabled or not character then
            return
        end
        local left: BasePart? = (character:FindFirstChild("LeftHand")
            or character:FindFirstChild("Left Arm")) :: BasePart?
        local right: BasePart? = (character:FindFirstChild("RightHand")
            or character:FindFirstChild("Right Arm")) :: BasePart?
        visualFolder = Instance.new("Folder")
        visualFolder.Name = "MM2LocalWeaponVisuals"
        visualFolder.Parent = workspace
        local copiedByKind: {[string]: number} = {Gun = 0, Knife = 0}
        local equippedByKind: {[string]: boolean} = {}
        for _, kind: string in ipairs({"Gun", "Knife"}) do
            local tool: Tool? = equippedWeapon(kind)
            equippedByKind[kind] = tool ~= nil and tool.Parent == character
            if not tool or tool.Parent ~= character then
                continue
            end
            local double: boolean = kind == "Gun" and options.doubleGun
                or kind == "Knife" and options.doubleKnife
            local blade: BasePart? = visualBlade(tool)
            if kind == "Knife" and options.electricKnife and blade then
                addElectric(blade)
            end
            if not double
                or not left
                or not right
                or not left:IsA("BasePart")
                or not right:IsA("BasePart") then
                continue
            end
            local copied: number = 0
            for _, source: Instance in ipairs(tool:GetDescendants()) do
                if not source:IsA("BasePart") then
                    continue
                end
                local part: BasePart? =
                    geometryClone(source :: BasePart)
                if part then
                    attach(
                        part,
                        left :: BasePart,
                        (left :: BasePart).CFrame
                            * (right :: BasePart).CFrame:ToObjectSpace(
                                (source :: BasePart).CFrame
                            )
                    )
                    if kind == "Knife"
                        and options.electricKnife
                        and source == blade then
                        addElectric(part)
                    end
                    copied += 1
                    if copied >= 64 then
                        break -- bounded cost for complex skins
                    end
                end
            end
            copiedByKind[kind] = copied
            if copied > 0 then
                -- A mirrored left arm keeps the cloned weapon raised next to
                -- the real one instead of hanging from a dead limb.
                activeDouble = true
            end
        end
        -- Visible diagnostics: what the last rebuild produced. If a double
        -- was requested for an equipped weapon but nothing was copied, say
        -- so instead of failing silently ("Gun Visual no funciona").
        do
            local missing: {string} = {}
            if options.doubleGun
                and equippedByKind.Gun
                and copiedByKind.Gun == 0 then
                table.insert(missing, "Double Gun found no gun geometry - report the skin name")
            end
            if options.doubleKnife
                and equippedByKind.Knife
                and copiedByKind.Knife == 0 then
                table.insert(missing, "Double Knife found no knife geometry - report the skin name")
            end
            if #missing > 0 then
                if not warnedEmptyGeometry then
                    warnedEmptyGeometry = true
                    if type(notify) == "function" then
                        notify(table.concat(missing, " · "))
                    end
                end
            else
                warnedEmptyGeometry = false
            end
            if feature and type(feature.SetStatus) == "function" then
                local parts: {string} = {}
                if options.doubleGun and copiedByKind.Gun > 0 then
                    table.insert(parts, "2x" .. copiedByKind.Gun .. " gun")
                end
                if options.doubleKnife and copiedByKind.Knife > 0 then
                    table.insert(parts, "2x" .. copiedByKind.Knife .. " knife")
                end
                if options.electricKnife and #arcs > 0 then
                    table.insert(parts, "arc x" .. #arcs)
                end
                feature:SetStatus(#parts > 0 and table.concat(parts, " · ") or nil)
            end
        end
        if #arcs > 0 then
            local elapsed: number = 0
            electricTask = TaskManager:Connect(function(dt: number): ()
                elapsed += dt
                if elapsed < 0.125 then
                    return -- 8 Hz only while electric is visible
                end
                elapsed = 0
                for _, arc: any in ipairs(arcs) do
                    for i, node: Attachment in ipairs(arc.nodes) do
                        local jitter: Vector3 = (i == 1 or i == #arc.nodes)
                                and Vector3.zero
                            or Vector3.new(
                                math.random() - 0.5,
                                math.random() - 0.5,
                                math.random() - 0.5
                            ) * 0.22 * options.intensity
                        node.Position = arc.axis * arc.length
                            * ((i - 1) / 5 - 0.5)
                            + jitter
                    end
                end
            end)
        end
    end

    local function watchCharacter(character: Model): ()
        disconnectAll(characterConnections)
        clearVisuals()
        table.insert(
            characterConnections,
            character.DescendantAdded:Connect(function(object: Instance): ()
                if object:IsA("Tool") or object:IsA("BasePart") then
                    queueRebuild()
                end
            end)
        )
        table.insert(
            characterConnections,
            character.DescendantRemoving:Connect(function(object: Instance): ()
                if object:IsA("Tool") or object:IsA("BasePart") then
                    queueRebuild()
                end
            end)
        )
        queueRebuild()
    end

    local function setEnabled(enabled: boolean): ()
        -- Every toggle step is defensive, but executors differ: if anything
        -- in the enable path still throws, run the full disable cleanup and
        -- re-throw with a traceback so the console (and the "Could not
        -- toggle" notification, which now carries the reason) shows exactly
        -- what failed instead of a silent half-enabled state.
        local ok: boolean, failure: any = pcall(function(): ()
            generation += 1
            queued = false
            options.enabled = enabled
            disconnectAll(connections)
            disconnectAll(characterConnections)
            clearVisuals()
            disconnectGunFired()
            if not enabled then
                return
            end
            table.insert(
                connections,
                LocalPlayer.CharacterAdded:Connect(watchCharacter)
            )
            connectGunFired()
            table.insert(
                connections,
                LocalPlayer.CharacterRemoving:Connect(function(): ()
                    generation += 1
                    queued = false
                    disconnectAll(characterConnections)
                    clearVisuals()
                end)
            )
            -- Mirror the animated right arm onto the left arm every frame while a
            -- double weapon is on screen. The write must land AFTER the Animator
            -- applies its poses (otherwise it is overwritten): PostAnimation fires
            -- exactly there; PreSimulation is the fallback (also post-animator).
            local mirrorSignals: {any} = {}
            if RunService.PostAnimation then
                table.insert(mirrorSignals, RunService.PostAnimation)
            end
            if RunService.PreSimulation then
                table.insert(mirrorSignals, RunService.PreSimulation)
            end
            for _, signal: any in ipairs(mirrorSignals) do
                table.insert(
                    connections,
                    signal:Connect(function(): ()
                        local character: Model? = LocalPlayer.Character
                        if character then
                            pcall(mirrorArms, character :: Model)
                        end
                    end)
                )
            end
            if LocalPlayer.Character then
                watchCharacter(LocalPlayer.Character)
            end
        end)
        if not ok then
            local trace: string = tostring(failure)
            if debug and type(debug.traceback) == "function" then
                pcall(function(): ()
                    trace = debug.traceback(failure, 2)
                end)
            end
            warn("[Wurst] Weapon Visuals toggle ("
                .. tostring(enabled) .. ") failed: " .. trace)
            pcall(function(): ()
                generation += 1
                queued = false
                options.enabled = false
                disconnectAll(connections)
                disconnectAll(characterConnections)
                clearVisuals()
                disconnectGunFired()
            end)
            error(failure, 0)
        end
    end

    feature = createUniversalFeature(
        "Weapon Visuals",
        "Local cosmetics only: double weapons raise both arms, electric "
            .. "knife arcs. No extra damage or replication.",
        15,
        setEnabled,
        {categoryName = "Render", parent = MM2Scroll, registry = mm2Features}
    )
    addToggleOption(feature, "Double Gun", false, function(value: boolean): ()
        options.doubleGun = value
        queueRebuild()
    end)
    addToggleOption(feature, "Double Knife", false, function(value: boolean): ()
        options.doubleKnife = value
        queueRebuild()
    end)
    addToggleOption(feature, "Electric Knife", false, function(value: boolean): ()
        options.electricKnife = value
        queueRebuild()
    end, "Original local beam effect, not the official inventory effect.")
    addColorOption(feature, "Electric color", options.color, function(value: Color3): ()
        options.color = value
        queueRebuild()
    end)
    addNumberOption(feature, "Electric intensity", 1, 0.25, 3, function(value: number): ()
        options.intensity = math.clamp(value, 0.25, 3)
        queueRebuild()
    end)
    addToggleOption(feature, "TrailESP", false, function(value: boolean): ()
        options.trailEsp = value
        if not value then
            clearTrails()
        end
    end, "Draws every replicated bullet's path and landing point, from the server's GunFired signal.")
    addToggleOption(feature, "Tracer Data", false, function(value: boolean): ()
        options.tracerData = value
    end, "Reports how many studs your shots landed from the murderer.")

    activeCleanup = function(): ()
        setEnabled(false)
    end
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
    Module.Runtime = nil
end
return Module
