export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Safe Walk",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local currentWorkspace: Workspace = host.workspace or workspace

    local safeWalkSettings: {
        lookAhead: number,
        barrierHeight: number,
    } = {
        lookAhead = 2.8,
        barrierHeight = 4.5,
    }

    local barrierFolder: Folder? = nil
    local barrier: BasePart? = nil
    local SafeWalkFeature: any = nil

    -- Geometry rules (studs). A barrier closer than MIN_EDGE would sit inside the
    -- character's body, which pushes it back every frame; such edges are not guarded.
    -- A gap must be at least MIN_GAP wide to count as a drop, so stair treads and
    -- rail seams never place a barrier.
    local MIN_EDGE: number = 1.25
    local MIN_GAP: number = 1.5
    local PROBE_STEP: number = 0.5
    local PROBE_DEPTH: number = 6

    local function getBarrier(): BasePart
        local existing: BasePart? = barrier
        if existing and existing.Parent then
            return existing
        end
        if not barrierFolder or not barrierFolder.Parent then
            barrierFolder = Instance.new("Folder")
            barrierFolder.Name = "WurstSafeWalk"
            barrierFolder.Parent = currentWorkspace
        end
        local part: BasePart = Instance.new("Part")
        part.Name = "SafeWalkBarrier"
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Massless = true
        part.CastShadow = false
        part.Transparency = 1
        part.Material = Enum.Material.SmoothPlastic
        part:SetAttribute("WurstSafeWalk", true)
        part.Parent = barrierFolder
        barrier = part
        return part
    end

    -- Turns the single barrier off in place: no destroy/recreate, so a part never
    -- appears on top of the character.
    local function releaseBarrier(): ()
        local existing: BasePart? = barrier
        if existing and existing.Parent then
            existing.CanCollide = false
        end
    end

    local function destroyBarrier(): ()
        if barrierFolder then
            barrierFolder:Destroy()
        end
        barrierFolder = nil
        barrier = nil
    end

    -- Distance along moveDirection to the last ground before a confirmed drop
    -- (a gap of at least MIN_GAP with no floor below). nil when none is ahead.
    local function findDrop(root: BasePart, moveDirection: Vector3, parameters: RaycastParams): number?
        -- Scan far enough to confirm a MIN_GAP-wide gap that starts inside the reach.
        local reach: number = 1.0 + safeWalkSettings.lookAhead + MIN_GAP
        local lastGround: number? = nil
        local groundBeforeGap: number? = nil
        local gapStart: number? = nil
        local distance: number = PROBE_STEP
        while distance <= reach do
            local ground: RaycastResult? = currentWorkspace:Raycast(
                root.Position + moveDirection * distance,
                Vector3.new(0, -PROBE_DEPTH, 0),
                parameters
            )
            if ground then
                lastGround = distance
                gapStart = nil
                groundBeforeGap = nil
            else
                if gapStart == nil then
                    gapStart = distance
                    groundBeforeGap = lastGround
                end
                if distance - gapStart >= MIN_GAP then
                    return groundBeforeGap
                end
            end
            distance += PROBE_STEP
        end
        return nil
    end

    local function toggleSafeWalk(enabled: boolean): ()
        disconnectFeatureConnection("SafeWalk")
        destroyBarrier()
        if not enabled then
            if SafeWalkFeature then
                SafeWalkFeature:SetStatus(nil)
            end
            return
        end

        featureConnections.SafeWalk = TaskManager:Connect(function(): ()
            local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not character or not humanoid or not root
                or humanoid.Health <= 0 then
                releaseBarrier()
                return
            end

            -- Jumping or falling is a deliberate choice to leave the ledge: the barrier
            -- is off for the whole airborne phase.
            local state = humanoid:GetState()
            if humanoid.FloorMaterial == Enum.Material.Air
                or state == Enum.HumanoidStateType.Jumping
                or state == Enum.HumanoidStateType.Freefall then
                releaseBarrier()
                return
            end

            local move: Vector3 = humanoid.MoveDirection
            local flat: Vector3 = Vector3.new(move.X, 0, move.Z)
            if flat.Magnitude < 0.05 then
                return
            end
            local moveDirection: Vector3 = flat.Unit

            local parameters: RaycastParams = RaycastParams.new()
            parameters.FilterType = Enum.RaycastFilterType.Exclude
            parameters.FilterDescendantsInstances = {character}
            parameters.IgnoreWater = true

            local edge: number? = findDrop(root :: BasePart, moveDirection, parameters)
            if edge == nil then
                releaseBarrier()
                if SafeWalkFeature then
                    SafeWalkFeature:SetStatus(nil)
                end
                return
            end

            if edge < MIN_EDGE then
                -- Already at the lip: keep whatever barrier was placed on approach,
                -- never place a new one this close.
                return
            end

            local part: BasePart = getBarrier()
            local barrierHeight: number = math.max(safeWalkSettings.barrierHeight, 3)
            local feetY: number = root.Position.Y - (root.Size.Y * 0.5 + humanoid.HipHeight)
            local center: Vector3 = root.Position + moveDirection * edge
            local wallCenter: Vector3 = Vector3.new(center.X, feetY + barrierHeight * 0.5, center.Z)
            part.Size = Vector3.new(7, barrierHeight, 0.35)
            part.CFrame = CFrame.lookAt(wallCenter, wallCenter + moveDirection)
            part.CanCollide = true
            if SafeWalkFeature then
                SafeWalkFeature:SetStatus("edge")
            end
        end)
    end

    SafeWalkFeature = createUniversalFeature(
        "Safe Walk",
        "Place an invisible barrier at edges so you cannot walk off ledges",
        21,
        toggleSafeWalk,
        {
            configKey = "Universal.SafeWalk",
            categoryName = "World",
        }
    )
    addNumberOption(
        SafeWalkFeature,
        "Edge look-ahead",
        safeWalkSettings.lookAhead,
        1.5,
        6,
        function(value: number): ()
            safeWalkSettings.lookAhead = value
        end
    )
    addNumberOption(
        SafeWalkFeature,
        "Barrier height",
        safeWalkSettings.barrierHeight,
        3,
        10,
        function(value: number): ()
            safeWalkSettings.barrierHeight = value
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("SafeWalk")
        destroyBarrier()
    end
    Module.Initialized = true
    return SafeWalkFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
