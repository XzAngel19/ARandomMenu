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
        color = Color3.fromRGB(100, 185, 255),
        trailEsp = false,
        tracerData = false,
    }
    local connections: {RBXScriptConnection} = {}
    local characterConnections: {RBXScriptConnection} = {}
    local visualFolder: Folder? = nil
    local trailFolder: Folder? = nil
    local gunFiredConnection: any = nil
    local queued = false
    local generation = 0
    local activeDouble = false
    local doubleBindings: {any} = {}
    local originalMirrorJoints: {[Motor6D]: any} = setmetatable({}, {__mode = "k"})
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
        if not originalMirrorJoints[joint] then
            originalMirrorJoints[joint] = {c0 = joint.C0, transform = joint.Transform}
        end
        -- Drive the real limb joint, not the duplicate weapon. C0 is not
        -- the Animator's per-frame pose channel. Neutralize that channel
        -- while applying the complete desired pose through the joint basis.
        joint.C0 = parentFrame:Inverse() * desired * joint.C1
        joint.Transform = CFrame.new()
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
        for joint: Motor6D, original: any in pairs(originalMirrorJoints) do
            if joint.Parent then
                joint.C0 = original.c0
                joint.Transform = original.transform
            end
            originalMirrorJoints[joint] = nil
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
            for _, candidate: Instance in ipairs(character:GetDescendants()) do
                if candidate:IsA("Motor6D") and candidate.Part1 == lUpper then
                    leftShoulder = candidate :: Motor6D
                    break
                end
            end
        end
        if not leftShoulder then return end
        local frame: CFrame = (torso :: BasePart).CFrame
        local function animatedFrame(part: BasePart, joint: Motor6D?, parent: CFrame): CFrame
            if joint and joint.Part0 and joint.Part1 == part then
                return parent * joint.C0 * joint.Transform * joint.C1:Inverse()
            end
            return part.CFrame
        end
        local rightShoulder: Motor6D? = findJoint(rUpper, {"RightShoulder", "Right Shoulder"})
            or findJoint(torso, {"Right Shoulder", "RightShoulder"})
        local rightUpperFrame: CFrame = animatedFrame(rUpper, rightShoulder, frame)
        local desiredUpper: CFrame = mirrorAcross(frame, rightUpperFrame)
        mirrorJoint(leftShoulder :: Motor6D, frame, desiredUpper)

        if rLower and lLower then
            local leftElbow: Motor6D? = findJoint(lLower, {"LeftElbow"})
            if leftElbow then
                local rightLowerFrame: CFrame = animatedFrame(rLower,
                    findJoint(rLower, {"RightElbow"}) or findJoint(rUpper, {"RightElbow"}), rightUpperFrame)
                local desiredLower: CFrame = mirrorAcross(frame, rightLowerFrame)
                mirrorJoint(leftElbow :: Motor6D, desiredUpper, desiredLower)
                if rHand and lHand then
                    local leftWrist: Motor6D? =
                        findJoint(lHand, {"LeftWrist"})
                    if leftWrist then
                        local rightHandFrame: CFrame = animatedFrame(rHand,
                            findJoint(rHand, {"RightWrist"}) or findJoint(rLower, {"RightWrist"}), rightLowerFrame)
                        local desiredHand: CFrame = mirrorAcross(frame, rightHandFrame)
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
        table.clear(doubleBindings)
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
        copy.LocalTransparencyModifier = 0
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
    -- hitPart): the reported endpoint, not proof of damage/death or an
    -- authoritative target pose at the time the server processed the shot.
    -- ------------------------------------------------------------------

    local function ensureTrailFolder(): Folder
        if not trailFolder or not trailFolder.Parent then
            trailFolder = Instance.new("Folder")
            trailFolder.Name = "MM2TrailESP"
            trailFolder.Parent = workspace
        end
        -- Bound transient visuals even if many players fire together.
        local children: {Instance} = trailFolder:GetChildren()
        while #children >= 64 do
            children[1]:Destroy()
            table.remove(children, 1)
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
        if options.trailEsp and length > 0.5 then
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
        -- Pixel-sized ring at the reported endpoint; never highlight the
        -- entire hitPart (a single hitPart can be a whole wall).
        local anchor: Part = Instance.new("Part")
        anchor.Name = "TrailLanding"
        anchor.Size = Vector3.new(0.02, 0.02, 0.02)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanQuery = false
        anchor.CanTouch = false
        anchor.Position = hit
        anchor.Parent = folder
        local billboard: BillboardGui = Instance.new("BillboardGui")
        billboard.Name = "LandingCircle"
        billboard.Adornee = anchor
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(12, 12)
        billboard.Parent = anchor
        local ring: Frame = Instance.new("Frame")
        ring.Size = UDim2.fromScale(1, 1)
        ring.BackgroundTransparency = 1
        ring.Parent = billboard
        local corner: UICorner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = ring
        local stroke: UIStroke = Instance.new("UIStroke")
        stroke.Color = options.color
        stroke.Thickness = 2
        stroke.Parent = ring
        task.delay(1.55, function(): ()
            if anchor.Parent then anchor:Destroy() end
        end)
    end

    local function reportTracerData(origin: Vector3, hit: Vector3, hitPart: any): ()
        local murderer: Player? = core.findMurderer()
        local root: BasePart? = murderer and murderer.Character
            and murderer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local calibration: any = core.trajectoryCalibration
        if calibration and type(calibration.noteTracerData) == "function" then
            calibration:noteTracerData({origin = origin, endpoint = hit,
                hitPart = hitPart, target = murderer, targetPosition = root and root.Position})
        end
        if root and murderer then
            notify(string.format("Tracer: endpoint %.1f studs from observed %s (range %.0f)",
                (hit - root.Position).Magnitude, murderer.DisplayName, (hit - origin).Magnitude))
        end
    end

    local function connectGunFired(): ()
        if gunFiredConnection then
            return
        end
        local ok: boolean, weaponService: any = pcall(function(): any
            if type(core.getWeaponServiceModule) == "function" then
                return core.getWeaponServiceModule()
            end
            local replicatedStorage: any = game:GetService("ReplicatedStorage")
            local clientServices: any = replicatedStorage:FindFirstChild("ClientServices")
            return clientServices and clientServices:FindFirstChild("WeaponService") or nil
        end)
        if not ok or type(weaponService) ~= "table" and typeof(weaponService) ~= "Instance" then
            return
        end
        if typeof(weaponService) == "Instance" and weaponService:IsA("ModuleScript") then
            local loaded: boolean, result: any = pcall(state.requireModule, weaponService)
            if not loaded then return end
            weaponService = result
        end
        if type(weaponService) ~= "table" and typeof(weaponService) ~= "Instance" then return end
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
                local function position(value: any): Vector3?
                    local vector: Vector3? = typeof(value) == "Vector3" and value
                        or typeof(value) == "CFrame" and value.Position or nil
                    if vector and vector.X == vector.X and vector.Y == vector.Y
                        and vector.Z == vector.Z and vector.Magnitude < 1e7 then
                        return vector
                    end
                    return nil
                end
                local origin: Vector3? = position(originValue)
                local hit: Vector3? = position(hitValue)
                if not origin or not hit then
                    return
                end
                local character: Model? = LocalPlayer.Character
                local backpack: Instance? = LocalPlayer:FindFirstChildOfClass("Backpack")
                local isOurGun: boolean = typeof(gunHandle) == "Instance"
                    and ((character ~= nil and gunHandle:IsDescendantOf(character))
                        or (backpack ~= nil and gunHandle:IsDescendantOf(backpack)))
                if options.trailEsp or (options.tracerData and isOurGun) then
                    drawShotTrail(origin, hit, hitPart)
                end
                if options.tracerData and isOurGun then
                    reportTracerData(origin, hit, hitPart)
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
                    -- A live weld offset, not a snapshot made while the
                    -- skin may still be at its spawn/default position.
                    local joint: Weld = Instance.new("Weld")
                    joint.Part0 = left
                    joint.Part1 = part
                    joint.C0 = right.CFrame:ToObjectSpace((source :: BasePart).CFrame)
                    joint.C1 = CFrame.new()
                    part.CFrame = left.CFrame * joint.C0
                    joint.Parent = part
                    part.Parent = visualFolder
                    table.insert(doubleBindings, {source = source, joint = joint, right = right})
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
                feature:SetStatus(#parts > 0 and table.concat(parts, " · ") or nil)
            end
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
            -- PreSimulation runs after Animator evaluation and before Motor6D
            -- transforms are applied. RunService has no PostAnimation event.
            table.insert(connections, RunService.PreSimulation:Connect(function(): ()
                local character: Model? = LocalPlayer.Character
                if character then
                    for _, binding: any in ipairs(doubleBindings) do
                        if binding.source.Parent and binding.joint.Parent and binding.right.Parent then
                            binding.joint.C0 = binding.right.CFrame:ToObjectSpace(binding.source.CFrame)
                        end
                    end
                    mirrorArms(character)
                end
            end))
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
        "Local double-weapon cosmetics and shot feedback. No extra damage or replication.",
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
    addColorOption(feature, "Trail color", options.color, function(value: Color3): ()
        options.color = value
    end)
    addToggleOption(feature, "TrailESP", false, function(value: boolean): ()
        options.trailEsp = value
        if not value then
            clearTrails()
        end
    end, "Draws every replicated bullet's path and landing point, from the server's GunFired signal.")
    addToggleOption(feature, "Tracer Data", false, function(value: boolean): ()
        options.tracerData = value
        if not value and not options.trailEsp then clearTrails() end
    end, "Saves your GunFired endpoint and hit part with Calibration, draws a landing circle, "
        .. "and compares to the target's client-observed position (not a server miss measurement).")

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
