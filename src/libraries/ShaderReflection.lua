-- Client-only approximation of a polished floor. No physics or game parts are
-- modified. Off-axis surface projection adapts ViewportStencil by Aziorux and
-- rbx-viewport-window by EgoMoose (MIT); see docs/third-party/shaders/.
local Module = {Name = "ShaderReflection", Initialized = false}
local sessions: {[any]: boolean} = {}

local MAX_LOCAL_PARTS = 24
local MAX_ACTORS = 3
local MAX_ACTOR_PARTS = 36
local MAX_SCENE_PARTS = 18
local MAX_QUERY = 100
local MAX_SECONDARY = 2
local MAX_SECONDARY_PARTS = 32
local MAX_TRACKED_FLOORS = 600
local MAX_FLOOR_CHECKS_PER_TICK = 32
local MAX_FLOOR_SIZE = 256
local SECONDARY_INTERVAL = 1
local SECONDARY_POSE_INTERVAL = 1 / 15
local MAX_CREATIONS_PER_TICK = 3
local FLOOR_INTERVAL = 0.20
local SCENE_INTERVAL = 2
local POSE_INTERVAL = 1 / 30

-- Basis of a top face in SurfaceGui canvas coordinates. These projection
-- equations are adapted from ViewportStencil's MIT-licensed Projection.lua.
local FACE_BACK = -Vector3.FromNormalId(Enum.NormalId.Top)
local FACE_RIGHT = CFrame.fromAxisAngle(Vector3.new(FACE_BACK.Y, 0, 0), math.pi / 2) * FACE_BACK
local FACE_UP = FACE_BACK:Cross(FACE_RIGHT).Unit
local FACE_ROTATION = CFrame.fromMatrix(Vector3.zero, FACE_RIGHT, FACE_UP, FACE_BACK)
local MAX_FOV = math.rad(120)
local MAX_FOV_TAN = math.tan(MAX_FOV / 2)

local function reflectedFrame(frame: CFrame, point: Vector3, normal: Vector3): CFrame
    local function flip(vector: Vector3): Vector3
        return vector - normal * (2 * vector:Dot(normal))
    end
    local position: Vector3 = point + flip(frame.Position - point)
    -- A reflection has negative handedness, so negate one basis vector to
    -- build a valid CFrame. Individual asymmetrical meshes are approximate.
    return CFrame.fromMatrix(position, -flip(frame.RightVector), flip(frame.UpVector), flip(frame.ZVector))
end

local function surfaceProjection(part: BasePart): (CFrame, Vector2, CFrame)
    local surface: CFrame = part.CFrame * CFrame.new(-FACE_BACK * part.Size / 2) * FACE_ROTATION
    local size: Vector2 = Vector2.new((part.Size * FACE_RIGHT).Magnitude, (part.Size * FACE_UP).Magnitude)
    return surface, size, surface.Rotation * CFrame.Angles(0, math.pi, 0)
end

local function project(camera: Camera, part: BasePart, gui: SurfaceGui, viewport: ViewportFrame, viewCamera: Camera, maxCanvas: number?): boolean
    local surface, size, viewRotation = surfaceProjection(part)
    if size.X <= 0 or size.Y <= 0 then return false end
    local cameraFrame: CFrame = camera.CFrame
    local look: Vector3 = cameraFrame.LookVector
    local forwardExtent: number = math.abs(part.CFrame.RightVector:Dot(look)) * part.Size.X / 2
        + math.abs(part.CFrame.ZVector:Dot(look)) * part.Size.Z / 2
    -- Disable the viewport when the whole patch is behind the camera.
    if (surface.Position - cameraFrame.Position):Dot(look) + forwardExtent <= 0 then return false end
    local relative: Vector3 = surface:PointToObjectSpace(cameraFrame.Position)
    local distance: number = -relative.Z
    if distance <= 0.1 or distance > 160 then return false end
    local offsetX, offsetY = relative.X / size.X, relative.Y / size.Y
    -- Bound the off-axis viewport when the camera is well outside this floor.
    if math.max(math.abs(offsetX), math.abs(offsetY)) > 1 then return false end
    local scale: number = 1 + 2 * math.max(math.abs(offsetX), math.abs(offsetY))
    local halfHeight: number = size.Y / 2
    local fov: number = 2 * math.atan2(halfHeight, distance)
    local factor: number
    if fov > MAX_FOV then
        viewCamera.FieldOfView = 120
        factor = distance * MAX_FOV_TAN / halfHeight / scale
    else
        viewCamera.FieldOfView = math.max(math.deg(fov), 1)
        factor = 1 / scale
    end
    -- A deliberately non-orthonormal CFrame provides the off-axis projection.
    viewport.Position = UDim2.fromScale(0.5 - offsetX, 0.5 - offsetY)
    viewport.Size = UDim2.fromScale(scale, scale)
    viewCamera.CFrame = (viewRotation + camera.CFrame.Position)
        * CFrame.new(0, 0, 0, factor, 0, 0, 0, factor, 0, 0, 0, 1)
    -- The viewport itself is enlarged by `scale`; cap its effective pixel
    -- extent too. Bucket the divisor to avoid resizing its render target on
    -- every tiny camera movement.
    local scaleBudget: number = math.ceil(scale * 2) / 2
    local resolution: number = (maxCanvas or 1024) / scaleBudget / math.max(size.X, size.Y)
    local canvasSize: Vector2 = Vector2.new(math.max(32, math.floor(size.X * resolution)), math.max(32, math.floor(size.Y * resolution)))
    if gui.CanvasSize ~= canvasSize then gui.CanvasSize = canvasSize end
    return true
end

function Module.init(host: any): any
    local api: any = {}

    function api:Start(report: (string) -> ()): (any?, string?)
        local world: Workspace = host.workspace or workspace
        local player: Player = host.LocalPlayer
        local playerGui: PlayerGui? = host.PlayerGui or (player and player:FindFirstChildOfClass("PlayerGui"))
        local mobile: boolean = host.state ~= nil and host.state.isMobile == true
        local primaryCanvas: number = if mobile then 768 else 1024
        local secondaryCanvas: number = if mobile then 384 else 512
        local primaryPoseInterval: number = if mobile then 1 / 20 else POSE_INTERVAL
        local secondaryPoseInterval: number = if mobile then 1 / 10 else SECONDARY_POSE_INTERVAL
        if not world or not player or not playerGui or not host.TaskManager then
            return nil, "PlayerGui or camera services unavailable"
        end

        local stopped: boolean = false
        local folder: Folder? = nil
        local plane: Part? = nil
        local gui: SurfaceGui? = nil
        local viewport: ViewportFrame? = nil
        local viewCamera: Camera? = nil
        local scene: WorldModel? = nil
        local workConnection: any = nil
        local renderConnection: any = nil
        local rayParams: RaycastParams? = nil
        local overlapParams: OverlapParams? = nil
        local records: {[Instance]: any} = {}
        local actors: {[Instance]: any} = {}
        local queue: {any} = {}
        local candidates: {[Instance]: number} = {}
        local candidateCount, candidateOrder = 0, 0
        local secondary: {[Instance]: any} = {}
        local secondaryElapsed, secondaryPoseElapsed = SECONDARY_INTERVAL, 0
        local selectionItems: {any}? = nil
        local selectionIndex: number = 1
        local selectionChoices: {any} = {}
        local secondaryFailed, candidateWarned = false, false
        local planePoint: Vector3? = nil
        local planeNormal: Vector3? = nil
        local currentFloor: BasePart? = nil
        local currentCharacter: Model? = nil
        local planeVersion: number = 0
        local floorElapsed, sceneElapsed, poseElapsed = FLOOR_INTERVAL, SCENE_INTERVAL, POSE_INTERVAL
        local missingElapsed: number = 0
        local missingReported: boolean = false
        local avatarWarned: boolean = false
        local workWarned: boolean = false
        local session: any = {}

        local function clearMirrorCopies(mirror: any): ()
            for _, record: any in pairs(mirror.records) do pcall(function(): () record.copy:Destroy() end) end
            for _, actor: any in pairs(mirror.actors) do pcall(function(): () actor:Destroy() end) end
            mirror.records, mirror.actors, mirror.queue = {}, {}, {}
        end
        local function destroyMirror(mirror: any): ()
            clearMirrorCopies(mirror)
            if mirror.gui then pcall(function(): () mirror.gui:Destroy() end) end
            if mirror.plane then pcall(function(): () mirror.plane:Destroy() end) end
        end
        local function clearCopies(): ()
            for _, record: any in pairs(records) do pcall(function(): () record.copy:Destroy() end) end
            for _, actor: any in pairs(actors) do pcall(function(): () actor:Destroy() end) end
            records, actors, queue = {}, {}, {}
            for _, mirror: any in pairs(secondary) do clearMirrorCopies(mirror) end
        end

        function session:Stop(): ()
            if stopped then return end
            stopped = true
            sessions[session] = nil
            if workConnection then pcall(function(): () workConnection:Disconnect() end); workConnection = nil end
            if renderConnection then pcall(function(): () renderConnection:Disconnect() end); renderConnection = nil end
            clearCopies()
            for _, mirror: any in pairs(secondary) do destroyMirror(mirror) end
            secondary, candidates = {}, {}
            candidateCount = 0
            if gui then pcall(function(): () gui:Destroy() end); gui = nil end
            if folder then pcall(function(): () folder:Destroy() end); folder = nil end
            -- Also destroy partially constructed instances if setup failed.
            if viewport then pcall(function(): () viewport:Destroy() end); viewport = nil end
            if viewCamera then pcall(function(): () viewCamera:Destroy() end); viewCamera = nil end
            if scene then pcall(function(): () scene:Destroy() end); scene = nil end
            if plane then pcall(function(): () plane:Destroy() end); plane = nil end
        end

        local ok, failure = pcall(function(): ()
            folder = Instance.new("Folder")
            folder.Name, folder.Parent = "ARMShaderFloorReflection", world
            plane = Instance.new("Part")
            plane.Parent = folder
            plane.Name, plane.Anchored = "ReflectionSurface", true
            plane.CanCollide, plane.CanTouch, plane.CanQuery = false, false, false
            plane.CastShadow, plane.Transparency = false, 1
            plane.Size = Vector3.new(8, 0.04, 8)

            -- ViewportFrames in a SurfaceGui need PlayerGui + Adornee; a GUI
            -- parented directly to a Workspace part does not reliably render.
            gui = Instance.new("SurfaceGui")
            gui.Enabled = false
            gui.Parent = playerGui
            gui.Name, gui.Adornee, gui.Face = "ARMShaderFloorReflection", plane, Enum.NormalId.Top
            gui.SizingMode, gui.ZIndexBehavior = Enum.SurfaceGuiSizingMode.FixedSize, Enum.ZIndexBehavior.Sibling
            gui.AlwaysOnTop, gui.ClipsDescendants = false, true
            gui.LightInfluence, gui.Brightness, gui.ResetOnSpawn = 0, 1, false
            gui.MaxDistance = 180
            viewport = Instance.new("ViewportFrame")
            viewport.Parent = gui
            viewport.Name, viewport.BackgroundTransparency, viewport.BorderSizePixel = "Reflection", 1, 0
            viewport.ImageTransparency = 0.12
            viewport.AnchorPoint = Vector2.new(0.5, 0.5)
            viewport.Ambient = Color3.fromRGB(215, 215, 215)
            viewport.LightColor = Color3.fromRGB(215, 210, 200)
            viewport.LightDirection = Vector3.new(-1, -1, -1)
            viewCamera = Instance.new("Camera")
            viewCamera.Parent = viewport
            viewport.CurrentCamera = viewCamera
            scene = Instance.new("WorldModel")
            scene.Name, scene.Parent = "ReflectedScene", viewport
            rayParams = RaycastParams.new()
            rayParams.FilterType, rayParams.IgnoreWater = Enum.RaycastFilterType.Exclude, true
            pcall(function(): () rayParams.RespectCanCollide = true end)
            pcall(function(): ()
                overlapParams = OverlapParams.new()
                overlapParams.FilterType, overlapParams.MaxParts = Enum.RaycastFilterType.Exclude, MAX_QUERY
            end)
        end)
        if not ok then session:Stop(); return nil, tostring(failure) end

        local function eligibleFloor(part: any): boolean
            if not part:IsA("BasePart") or not part.Parent or not part.Anchored
                or part.Transparency >= 0.95 or part.CFrame.UpVector.Y < 0.97 then return false end
            local size: Vector3 = part.Size
            if size.X < 6 or size.Z < 6 or size.Y > math.min(size.X, size.Z) * 0.5 then return false end
            local parent: any = part.Parent
            while parent and parent ~= world do
                if parent == folder or parent == world.CurrentCamera or parent:IsA("Tool") or parent:IsA("Accessory") then
                    return false
                end
                if parent:IsA("Model") and (parent:FindFirstChildOfClass("Humanoid")
                    or parent:FindFirstChildOfClass("AnimationController")) then return false end
                parent = parent.Parent
            end
            return parent == world
        end

        -- Called by Shaders' incremental world traversal. A bounded set of
        -- compatible floors can be considered from the camera, not only from
        -- the character's downward ray.
        function session:Observe(part: any): ()
            if stopped or candidates[part] then return end
            local valid: boolean, eligible: any = pcall(eligibleFloor, part)
            if not valid or not eligible then return end
            if candidateCount >= MAX_TRACKED_FLOORS then
                if not candidateWarned then
                    candidateWarned = true
                    pcall(report, "Floor reflection tracking limit reached; some floors may be skipped")
                end
                return
            end
            candidateOrder += 1
            candidates[part] = candidateOrder
            candidateCount += 1
        end

        local function loseFloor(deltaTime: number, hasRoot: boolean): ()
            if gui then gui.Enabled = false end
            if currentFloor then
                currentFloor, planePoint, planeNormal = nil, nil, nil
                clearCopies()
            end
            if hasRoot then
                missingElapsed += deltaTime
                if missingElapsed >= 6 and not missingReported then
                    missingReported = true
                    report("Floor reflection needs a nearby flat solid floor")
                end
            else
                missingElapsed = 0
            end
        end

        local function findFloor(deltaTime: number): ()
            local character: Model? = player.Character
            if character ~= currentCharacter then
                currentCharacter = character
                clearCopies()
                avatarWarned, missingReported = false, false
                sceneElapsed = SCENE_INTERVAL
            end
            local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not root or not root:IsA("BasePart") or not root.Parent then loseFloor(deltaTime, false); return end
            rayParams.FilterDescendantsInstances = {character, folder}
            local hitOk: boolean, hit: any = pcall(function(): any
                return world:Raycast(root.Position + Vector3.new(0, 1, 0), Vector3.new(0, -15, 0), rayParams)
            end)
            local floor: any = if hitOk and hit then hit.Instance else nil
            if not floor or not floor:IsA("BasePart") or not floor.Parent or not floor.Anchored
                or floor.Transparency >= 0.95 or not hit.Normal or hit.Normal.Y < 0.97
                or floor.CFrame.UpVector.Y < 0.97 or floor.Size.X < 3 or floor.Size.Z < 3 then
                loseFloor(deltaTime, true)
                return
            end
            missingElapsed, missingReported = 0, false
            local localHit: Vector3 = floor.CFrame:PointToObjectSpace(hit.Position)
            -- Cover the complete rectangular floor up to a bounded 256-stud
            -- surface instead of just a 24x20 patch under the player.
            local width: number = math.min(floor.Size.X - 0.04, MAX_FLOOR_SIZE)
            local depth: number = math.min(floor.Size.Z - 0.04, MAX_FLOOR_SIZE)
            local x: number = math.clamp(localHit.X, (width - floor.Size.X) / 2, (floor.Size.X - width) / 2)
            local z: number = math.clamp(localHit.Z, (depth - floor.Size.Z) / 2, (floor.Size.Z - depth) / 2)
            plane.Size = Vector3.new(width, 0.04, depth)
            plane.CFrame = floor.CFrame * CFrame.new(x, localHit.Y + 0.04, z)
            local point: Vector3 = floor.CFrame:PointToWorldSpace(Vector3.new(0, localHit.Y, 0))
            local normal: Vector3 = floor.CFrame.UpVector
            if floor ~= currentFloor or not planePoint or not planeNormal
                or math.abs((point - planePoint):Dot(normal)) > 0.04
                or (normal - planeNormal).Magnitude > 0.01 then
                currentFloor, planePoint, planeNormal = floor, point, normal
                planeVersion += 1
                sceneElapsed = SCENE_INTERVAL
            else
                planePoint, planeNormal = point, normal
            end
        end

        local function isScenePart(part: any): boolean
            if not part:IsA("BasePart") or not part.Parent or not part.Anchored or part == currentFloor
                or part.Transparency >= 0.9 then return false end
            local parent: any = part.Parent
            while parent and parent ~= world do
                if parent == folder or parent == world.CurrentCamera or parent:IsA("Tool") or parent:IsA("Accessory") then
                    return false
                end
                if parent:IsA("Model") and (parent:FindFirstChildOfClass("Humanoid")
                    or parent:FindFirstChildOfClass("AnimationController")) then return false end
                parent = parent.Parent
            end
            if parent ~= world then return false end
            local size: Vector3 = part.Size
            local height: number = (part.Position - (planePoint :: Vector3)):Dot(planeNormal :: Vector3)
            -- Geometry below the mirror would be flipped above it, occluding
            -- the viewport. Exclude it as well as floors at the mirror plane.
            if height < -0.25 then return false end
            if size.Y <= 2 and size.X >= 5 and size.Z >= 5 and height < 2 then return false end
            return math.max(size.X, size.Y, size.Z) >= 2
        end

        -- Classic clothing needs a Model with a Humanoid; copying only loose
        -- body parts loses shirts and pants. Never clone the original Humanoid
        -- or its scripts/joints. Layered clothing can still differ in a viewport.
        local function actorModel(character: Model, targetScene: WorldModel, actorTable: {[Instance]: any}): Model?
            if actorTable[character] and actorTable[character].Parent then return actorTable[character] end
            local model: Model? = nil
            local ok: boolean = pcall(function(): ()
                model = Instance.new("Model")
                model.Name = "ReflectedActor"
                local humanoid: Humanoid = Instance.new("Humanoid")
                humanoid.Parent = model
                humanoid.AutoRotate, humanoid.PlatformStand = false, true
                humanoid.RequiresNeck, humanoid.BreakJointsOnDeath = false, false
                humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
                local original: Humanoid? = character:FindFirstChildOfClass("Humanoid")
                if original then pcall(function(): () humanoid.RigType = original.RigType end) end
                local count: number = 0
                for _, item: Instance in ipairs(character:GetChildren()) do
                    if count >= 8 then break end
                    if item:IsA("Clothing") or item:IsA("ShirtGraphic")
                        or item:IsA("BodyColors") or item:IsA("CharacterMesh") then
                        local copied: boolean, appearance: any = pcall(function(): any return item:Clone() end)
                        if copied and appearance then
                            appearance:ClearAllChildren()
                            appearance.Parent = model
                            count += 1
                        end
                    end
                end
                model.Parent = targetScene
            end)
            if not ok then
                if model then pcall(function(): () model:Destroy() end) end
                return nil
            end
            actorTable[character] = model
            return model
        end

        local function scanScene(): ()
            if not currentFloor or not plane or not planePoint then return end
            local desired: {[Instance]: boolean} = {}
            local desiredActors: {[Instance]: boolean} = {}
            local pending: {any} = {}
            local focusRoot: any = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
            local scanPosition: Vector3 = if focusRoot then focusRoot.Position else plane.Position
            local dynamicCount, actorCount = 0, 0
            local function remember(part: any, dynamic: boolean, parent: any?): ()
                if desired[part] then return end
                desired[part] = true
                local record: any = records[part]
                if record then
                    record.dynamic = dynamic
                    if parent and record.copy.Parent ~= parent then record.copy.Parent = parent end
                else
                    table.insert(pending, {source = part, dynamic = dynamic, parent = parent})
                end
            end
            local function includeCharacter(character: any, limit: number): ()
                if not character or dynamicCount >= MAX_ACTOR_PARTS or actorCount >= MAX_ACTORS then return end
                local fetched: boolean, descendants: any = pcall(function(): any return character:GetDescendants() end)
                if not fetched or type(descendants) ~= "table" then return end
                local parts: {any} = {}
                local selected: {[Instance]: boolean} = {}
                local function selectPart(part: any): ()
                    if #parts >= limit or dynamicCount + #parts >= MAX_ACTOR_PARTS or selected[part] then return end
                    if part:IsA("BasePart") and part.Parent
                        and (part.Transparency < 0.95 or part.Name == "HumanoidRootPart") then
                        selected[part] = true
                        table.insert(parts, part)
                    end
                end
                -- Preserve the invisible root and body before filling the
                -- remaining budget with accessory handles.
                local root: any = character:FindFirstChild("HumanoidRootPart")
                if root then selectPart(root) end
                local children: {Instance} = character:GetChildren()
                for i: number = 1, math.min(#children, 300) do
                    if #parts >= limit or dynamicCount + #parts >= MAX_ACTOR_PARTS then break end
                    selectPart(children[i])
                end
                for i: number = 1, math.min(#descendants, 300) do
                    if #parts >= limit or dynamicCount + #parts >= MAX_ACTOR_PARTS then break end
                    selectPart(descendants[i])
                end
                if #parts == 0 then return end
                local model: Model? = actorModel(character, scene :: WorldModel, actors)
                if not model then
                    if character == currentCharacter and not avatarWarned then
                        avatarWarned = true
                        pcall(report, "Avatar reflection unavailable; other effects are still active")
                    end
                    return
                end
                desiredActors[character] = true
                actorCount += 1
                for _, part: any in ipairs(parts) do
                    remember(part, true, model)
                    dynamicCount += 1
                end
            end
            includeCharacter(currentCharacter, MAX_LOCAL_PARTS)
            local players: any = host.Players
            local otherCharacters: {any} = {}
            if players then
                local playersOk: boolean, list: any = pcall(function(): any return players:GetPlayers() end)
                if playersOk and type(list) == "table" then
                    for _, other: any in ipairs(list) do
                        if other ~= player and other.Character then
                            table.insert(otherCharacters, other.Character)
                            local root: any = other.Character:FindFirstChild("HumanoidRootPart")
                            if root and (root.Position - scanPosition).Magnitude <= 30 then
                                includeCharacter(other.Character, 12)
                            end
                        end
                    end
                end
            end
            if overlapParams then
                local excluded: {any} = {folder}
                if currentCharacter then table.insert(excluded, currentCharacter) end
                for _, character: any in ipairs(otherCharacters) do table.insert(excluded, character) end
                local queryOk: boolean, nearby: any = pcall(function(): any
                    overlapParams.FilterDescendantsInstances = excluded
                    return world:GetPartBoundsInRadius(scanPosition, 32, overlapParams)
                end)
                if queryOk and type(nearby) == "table" then
                    local candidates: {any} = {}
                    for i: number = 1, math.min(#nearby, MAX_QUERY) do
                        local part: any = nearby[i]
                        local valid: boolean, eligible: any = pcall(isScenePart, part)
                        if valid and eligible then
                            local distance: number = (part.Position - scanPosition).Magnitude
                            local size: Vector3 = part.Size
                            local weight: number = math.max(1, math.min(12, math.max(size.X, size.Y, size.Z)))
                            table.insert(candidates, {part = part, score = distance / weight})
                        end
                    end
                    table.sort(candidates, function(a: any, b: any): boolean return a.score < b.score end)
                    for i: number = 1, math.min(#candidates, MAX_SCENE_PARTS) do remember(candidates[i].part, false) end
                end
            end
            for source: any, record: any in pairs(records) do
                if not desired[source] or not source.Parent then
                    pcall(function(): () record.copy:Destroy() end)
                    records[source] = nil
                end
            end
            for character: any, actor: any in pairs(actors) do
                if not desiredActors[character] then
                    pcall(function(): () actor:Destroy() end)
                    actors[character] = nil
                end
            end
            queue = pending
        end

        local function copyPrepared(source: any, parent: any, point: Vector3, normal: Vector3): any
            local cloneOk: boolean, copy: any = pcall(function(): any return source:Clone() end)
            if not cloneOk or not copy then return nil end
            local prepared: boolean = pcall(function(): ()
                -- Clone only visible geometry. Never parent scripts, joints,
                -- emitters, GUIs or tools into the PlayerGui/WorldModel.
                for _, child: any in ipairs(copy:GetChildren()) do
                    if child:IsA("DataModelMesh") or child:IsA("Decal") or child:IsA("SurfaceAppearance") then
                        child:ClearAllChildren()
                    else
                        child:Destroy()
                    end
                end
                copy.Anchored = true
                copy.CanCollide, copy.CanTouch, copy.CanQuery = false, false, false
                copy.CastShadow, copy.LocalTransparencyModifier = false, 0
                copy.CFrame = reflectedFrame(source.CFrame, point, normal)
                copy.Parent = parent
            end)
            if not prepared then pcall(function(): () copy:Destroy() end); return nil end
            return copy
        end

        local function makeCopy(item: any): ()
            local source: any = item.source
            if not source or not source.Parent or records[source] or not scene then return end
            local copy: any = copyPrepared(source, item.parent or scene, planePoint :: Vector3, planeNormal :: Vector3)
            if copy then
                records[source] = {copy = copy, dynamic = item.dynamic, frame = source.CFrame, planeVersion = planeVersion}
            end
        end

        local function updateCopies(): ()
            if not planePoint or not planeNormal then return end
            for source: any, record: any in pairs(records) do
                if not source.Parent or not record.copy.Parent then
                    pcall(function(): () record.copy:Destroy() end)
                    records[source] = nil
                else
                    local frame: CFrame = source.CFrame
                    if record.dynamic then
                        if record.copy.Transparency ~= source.Transparency then record.copy.Transparency = source.Transparency end
                        if record.copy.Color ~= source.Color then record.copy.Color = source.Color end
                        if record.copy.Size ~= source.Size then record.copy.Size = source.Size end
                    end
                    if record.dynamic or frame ~= record.frame or record.planeVersion ~= planeVersion then
                        record.copy.CFrame = reflectedFrame(frame, planePoint :: Vector3, planeNormal :: Vector3)
                        record.frame, record.planeVersion = frame, planeVersion
                    end
                end
            end
        end

        -- Secondary mirrors trade complete SSR for a bounded number of actual
        -- additional ViewportFrames. They reuse a subset of the primary scene's
        -- sources but project them onto each floor's own plane.
        local function positionMirror(mirror: any, camera: Camera): ()
            local floor: any = mirror.floor
            local size: Vector3 = floor.Size
            local width: number = math.min(size.X - 0.04, MAX_FLOOR_SIZE)
            local depth: number = math.min(size.Z - 0.04, MAX_FLOOR_SIZE)
            local localCamera: Vector3 = floor.CFrame:PointToObjectSpace(camera.CFrame.Position)
            local x: number = math.clamp(localCamera.X, (width - size.X) / 2, (size.X - width) / 2)
            local z: number = math.clamp(localCamera.Z, (depth - size.Z) / 2, (size.Z - depth) / 2)
            mirror.plane.Size = Vector3.new(width, 0.04, depth)
            mirror.plane.CFrame = floor.CFrame * CFrame.new(x, size.Y / 2 + 0.04, z)
            local point: Vector3 = floor.CFrame:PointToWorldSpace(Vector3.new(0, size.Y / 2, 0))
            local normal: Vector3 = floor.CFrame.UpVector
            if not mirror.point or not mirror.normal
                or math.abs((point - mirror.point):Dot(normal)) > 0.04
                or (normal - mirror.normal).Magnitude > 0.01 then
                mirror.version += 1
            end
            mirror.point, mirror.normal = point, normal
        end

        local function makeMirror(floor: any, camera: Camera): any
            local mirror: any = {floor = floor, records = {}, actors = {}, queue = {}, version = 0, syncElapsed = 1}
            local success: boolean, reason: any = pcall(function(): ()
                mirror.plane = Instance.new("Part")
                local surface: Part = mirror.plane
                surface.Name, surface.Parent, surface.Anchored = "ReflectionSurfaceRemote", folder, true
                surface.CanCollide, surface.CanTouch, surface.CanQuery = false, false, false
                surface.CastShadow, surface.Transparency = false, 1
                positionMirror(mirror, camera)
                mirror.gui = Instance.new("SurfaceGui")
                local surfaceGui: SurfaceGui = mirror.gui
                surfaceGui.Name, surfaceGui.Parent, surfaceGui.Adornee = "ARMShaderFloorReflectionRemote", playerGui, surface
                surfaceGui.Face, surfaceGui.Enabled = Enum.NormalId.Top, false
                surfaceGui.SizingMode, surfaceGui.ZIndexBehavior = Enum.SurfaceGuiSizingMode.FixedSize, Enum.ZIndexBehavior.Sibling
                surfaceGui.AlwaysOnTop, surfaceGui.ClipsDescendants = false, true
                surfaceGui.LightInfluence, surfaceGui.Brightness, surfaceGui.ResetOnSpawn = 0, 1, false
                surfaceGui.MaxDistance = 180
                mirror.viewport = Instance.new("ViewportFrame")
                local frame: ViewportFrame = mirror.viewport
                frame.Name, frame.Parent = "Reflection", surfaceGui
                frame.BackgroundTransparency, frame.BorderSizePixel, frame.ImageTransparency = 1, 0, 0.12
                frame.AnchorPoint = Vector2.new(0.5, 0.5)
                frame.Ambient, frame.LightColor = Color3.fromRGB(215, 215, 215), Color3.fromRGB(215, 210, 200)
                frame.LightDirection = Vector3.new(-1, -1, -1)
                mirror.camera = Instance.new("Camera")
                mirror.camera.Parent = frame
                frame.CurrentCamera = mirror.camera
                mirror.scene = Instance.new("WorldModel")
                mirror.scene.Name, mirror.scene.Parent = "ReflectedScene", frame
            end)
            if not success then
                destroyMirror(mirror)
                if mirror.viewport then pcall(function(): () mirror.viewport:Destroy() end) end
                if mirror.camera then pcall(function(): () mirror.camera:Destroy() end) end
                if mirror.scene then pcall(function(): () mirror.scene:Destroy() end) end
                warn("[Shaders:AdditionalFloor] " .. tostring(reason))
                return nil
            end
            return mirror
        end

        local function chooseMirrors(): number
            local camera: Camera? = world.CurrentCamera
            if not camera or secondaryFailed then selectionItems = nil; return 0 end
            if not selectionItems then
                selectionItems, selectionIndex, selectionChoices = {}, 1, {}
                for floor: any, order: number in pairs(candidates) do
                    table.insert(selectionItems :: {any}, {floor = floor, order = order})
                end
            end
            local items: {any} = selectionItems :: {any}
            local frame: CFrame = camera.CFrame
            local look: Vector3 = frame.LookVector
            -- A large map can have hundreds of floors: inspect only a slice
            -- per tick and keep the best two instead of sorting the whole map.
            -- Reserve two checks to revalidate winners at the end of a pass.
            for _ = 1, MAX_FLOOR_CHECKS_PER_TICK - MAX_SECONDARY do
                local item: any = items[selectionIndex]
                if not item then break end
                selectionIndex += 1
                local floor: any, order: number = item.floor, item.order
                local ok: boolean, eligible: any = pcall(eligibleFloor, floor)
                if not ok or not eligible then
                    if candidates[floor] then candidates[floor] = nil; candidateCount -= 1 end
                elseif floor ~= currentFloor then
                    local localCamera: Vector3 = floor.CFrame:PointToObjectSpace(frame.Position)
                    local size: Vector3 = floor.Size
                    local dx: number = math.max(0, math.abs(localCamera.X) - size.X / 2)
                    local dz: number = math.max(0, math.abs(localCamera.Z) - size.Z / 2)
                    local dy: number = math.abs(localCamera.Y - size.Y / 2)
                    local distance: number = math.sqrt(dx * dx + dy * dy + dz * dz)
                    local extent: number = math.abs(floor.CFrame.RightVector:Dot(look)) * size.X / 2
                        + math.abs(floor.CFrame.ZVector:Dot(look)) * size.Z / 2
                    local width, depth = math.min(size.X - 0.04, MAX_FLOOR_SIZE), math.min(size.Z - 0.04, MAX_FLOOR_SIZE)
                    local patchX: number = math.clamp(localCamera.X, (width - size.X) / 2, (size.X - width) / 2)
                    local patchZ: number = math.clamp(localCamera.Z, (depth - size.Z) / 2, (size.Z - depth) / 2)
                    local canProject: boolean = localCamera.Y > size.Y / 2 + 0.14
                        and math.abs(localCamera.X - patchX) / width <= 1
                        and math.abs(localCamera.Z - patchZ) / depth <= 1
                    if canProject and distance <= 160 and (floor.Position - frame.Position):Dot(look) + extent > 0 then
                        table.insert(selectionChoices, {
                            floor = floor, score = distance - (if secondary[floor] then 8 else 0), order = order,
                        })
                        table.sort(selectionChoices, function(a: any, b: any): boolean
                            return if a.score == b.score then a.order < b.order else a.score < b.score
                        end)
                        if #selectionChoices > MAX_SECONDARY then table.remove(selectionChoices) end
                    end
                end
            end
            if selectionIndex <= #items then return 0 end
            selectionItems = nil
            local choices: {any} = {}
            for _, choice: any in ipairs(selectionChoices) do
                local ok: boolean, eligible: any = pcall(eligibleFloor, choice.floor)
                if ok and eligible and choice.floor ~= currentFloor then table.insert(choices, choice) end
            end
            selectionChoices = {}
            local desired: {[Instance]: boolean} = {}
            for _, choice: any in ipairs(choices) do desired[choice.floor] = true end
            for floor: any, mirror: any in pairs(secondary) do
                if not desired[floor] then destroyMirror(mirror); secondary[floor] = nil end
            end
            local created: number = 0
            for _, choice: any in ipairs(choices) do
                local floor: any = choice.floor
                local mirror: any = secondary[floor]
                if not mirror then
                    -- A partially constructed plane also consumes this tick's
                    -- creation budget if a later SurfaceGui allocation fails.
                    created += 1
                    mirror = makeMirror(floor, camera)
                    if not mirror then
                        secondaryFailed = true
                        pcall(report, "Additional floor reflections unavailable; the main reflection remains active")
                        break
                    end
                    secondary[floor] = mirror
                else
                    positionMirror(mirror, camera)
                end
            end
            return created
        end
        local function syncMirror(mirror: any): ()
            local wanted: {[Instance]: boolean} = {}
            local dynamic, static = 0, 0
            for source: any, record: any in pairs(records) do
                if record.dynamic and dynamic < MAX_SECONDARY_PARTS - 8
                    and (source.Position - mirror.point):Dot(mirror.normal) >= -0.25 then
                    wanted[source] = true
                    dynamic += 1
                end
            end
            for source: any, record: any in pairs(records) do
                if not record.dynamic and static < 8
                    and (source.Position - mirror.point):Dot(mirror.normal) >= -0.25 then
                    wanted[source] = true
                    static += 1
                end
            end
            mirror.queue = {}
            for source: any, record: any in pairs(mirror.records) do
                if not wanted[source] or not source.Parent or not record.copy.Parent then
                    pcall(function(): () record.copy:Destroy() end)
                    mirror.records[source] = nil
                end
            end
            for character: any, actor: any in pairs(mirror.actors) do
                if not actors[character] then
                    pcall(function(): () actor:Destroy() end)
                    mirror.actors[character] = nil
                end
            end
            for source: any in pairs(wanted) do
                if not mirror.records[source] then table.insert(mirror.queue, source) end
            end
        end

        local function makeMirrorCopy(mirror: any, source: any): ()
            local primary: any = records[source]
            if not primary or not source.Parent or mirror.records[source] then return end
            local destination: any = mirror.scene
            for character: any, actor: any in pairs(actors) do
                if primary.copy.Parent == actor then
                    destination = actorModel(character, mirror.scene, mirror.actors) or mirror.scene
                    break
                end
            end
            local copy: any = copyPrepared(source, destination, mirror.point, mirror.normal)
            if copy then
                mirror.records[source] = {copy = copy, dynamic = primary.dynamic, frame = source.CFrame, planeVersion = mirror.version}
            end
        end

        local function updateMirrorCopies(mirror: any): ()
            for source: any, record: any in pairs(mirror.records) do
                if not source.Parent or not record.copy.Parent or not records[source] then
                    pcall(function(): () record.copy:Destroy() end)
                    mirror.records[source] = nil
                else
                    local frame: CFrame = source.CFrame
                    if record.dynamic then
                        if record.copy.Transparency ~= source.Transparency then record.copy.Transparency = source.Transparency end
                        if record.copy.Color ~= source.Color then record.copy.Color = source.Color end
                        if record.copy.Size ~= source.Size then record.copy.Size = source.Size end
                    end
                    if record.dynamic or frame ~= record.frame or record.planeVersion ~= mirror.version then
                        record.copy.CFrame = reflectedFrame(frame, mirror.point, mirror.normal)
                        record.frame, record.planeVersion = frame, mirror.version
                    end
                end
            end
        end

        local function updateWork(deltaTime: number): ()
            local dt: number = math.clamp(deltaTime, 0, 0.25)
            floorElapsed += dt
            sceneElapsed += dt
            poseElapsed += dt
            secondaryElapsed += dt
            secondaryPoseElapsed += dt
            if floorElapsed >= FLOOR_INTERVAL then
                local elapsed: number = floorElapsed
                floorElapsed = 0
                findFloor(elapsed)
            end
            if not currentFloor then return end
            local budget: number = MAX_CREATIONS_PER_TICK
            if selectionItems ~= nil or secondaryElapsed >= SECONDARY_INTERVAL then
                if selectionItems == nil then secondaryElapsed = 0 end
                budget -= chooseMirrors()
            end
            if sceneElapsed >= SCENE_INTERVAL then sceneElapsed = 0; scanScene() end
            while budget > 0 do
                local item: any = table.remove(queue, 1)
                if not item then break end
                makeCopy(item)
                budget -= 1
            end
            for _, mirror: any in pairs(secondary) do
                mirror.syncElapsed += dt
                if mirror.syncElapsed >= 0.4 then
                    mirror.syncElapsed = 0
                    syncMirror(mirror)
                end
                while budget > 0 do
                    local source: any = table.remove(mirror.queue, 1)
                    if not source then break end
                    makeMirrorCopy(mirror, source)
                    budget -= 1
                end
            end
            if #queue == 0 and not avatarWarned and currentCharacter and actors[currentCharacter] then
                local found: boolean = false
                for source: any, record: any in pairs(records) do
                    if record.copy.Parent == actors[currentCharacter] and source.Transparency < 0.95 then
                        found = true
                        break
                    end
                end
                if not found then
                    avatarWarned = true
                    pcall(report, "Avatar parts could not be copied for the floor reflection")
                end
            end
            local anyVisible: boolean = gui ~= nil and gui.Enabled == true
            if not anyVisible then
                for _, mirror: any in pairs(secondary) do
                    if mirror.gui.Enabled then anyVisible = true; break end
                end
            end
            if anyVisible and poseElapsed >= primaryPoseInterval then poseElapsed = 0; updateCopies() end
            if anyVisible and secondaryPoseElapsed >= secondaryPoseInterval then
                secondaryPoseElapsed = 0
                for _, mirror: any in pairs(secondary) do
                    if mirror.gui.Enabled then updateMirrorCopies(mirror) end
                end
            end
        end

        local function work(deltaTime: number): ()
            local worked: boolean, reason: any = pcall(function(): ()
                if not gui or not gui.Parent or not folder or not folder.Parent or not plane or not plane.Parent then
                    error("reflection container was removed")
                end
                updateWork(deltaTime)
            end)
            if not worked and not workWarned then
                workWarned = true
                warn("[Shaders:FloorReflection] " .. tostring(reason))
                session:Stop()
                pcall(report, "Floor reflection unavailable on this client")
            end
        end
        local function render(): ()
            local camera: Camera? = world.CurrentCamera
            if not camera or not currentFloor or not gui or not plane or not viewport or not viewCamera then
                if gui then gui.Enabled = false end
                for _, mirror: any in pairs(secondary) do mirror.gui.Enabled = false end
                return
            end
            local projected: boolean, visible: any = pcall(project, camera, plane, gui, viewport, viewCamera, primaryCanvas)
            if not projected then
                warn("[Shaders:FloorProjection] " .. tostring(visible))
                session:Stop()
                pcall(report, "Floor projection unavailable on this client")
                return
            end
            gui.Enabled = visible == true
            for _, mirror: any in pairs(secondary) do
                local ok: boolean, shown: any = pcall(project, camera, mirror.plane, mirror.gui, mirror.viewport, mirror.camera, secondaryCanvas)
                mirror.gui.Enabled = ok and shown == true
            end
        end
        local connected: boolean, connectFailure: any = pcall(function(): ()
            workConnection = host.TaskManager:Connect(work, nil, "Shaders floor reflection")
            renderConnection = host.TaskManager:Connect(render, "render", "Shaders floor projection")
        end)
        if not connected then session:Stop(); return nil, tostring(connectFailure) end
        sessions[session] = true
        return session, nil
    end

    Module.Initialized = true
    return api
end

function Module.destroy(): ()
    for session: any in pairs(sessions) do session:Stop() end
    Module.Initialized = false
end

return Module
