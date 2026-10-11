export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "SafeWalk",
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

    local function ensureBarrier(): BasePart
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
        part.CanCollide = true
        part.CanQuery = false
        part.CanTouch = false
        part.Massless = true
        part.CastShadow = false
        part.Transparency = 1
        part.Material = Enum.Material.SmoothPlastic
        part.Size = Vector3.new(7, safeWalkSettings.barrierHeight, 0.35)
        part:SetAttribute("WurstSafeWalk", true)
        part.Parent = barrierFolder
        barrier = part
        return part
    end

    local function hideBarrier(): ()
        if barrierFolder then
            barrierFolder:Destroy()
        end
        barrierFolder = nil
        barrier = nil
    end

    local function toggleSafeWalk(enabled: boolean): ()
        disconnectFeatureConnection("SafeWalk")
        hideBarrier()
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
                hideBarrier()
                return
            end
            -- While airborne or standing still the last barrier stays in place
            -- so momentum cannot carry you over an edge mid-jump.
            if humanoid.MoveDirection.Magnitude < 0.05 then
                return
            end
            if humanoid.FloorMaterial == Enum.Material.Air then
                return
            end

            local moveDirection: Vector3 = humanoid.MoveDirection.Unit
            local parameters: RaycastParams = RaycastParams.new()
            parameters.FilterType = Enum.RaycastFilterType.Exclude
            parameters.FilterDescendantsInstances = {character}
            parameters.IgnoreWater = true

            -- Sample the ground along the movement direction to find where the
            -- floor ends. The barrier is placed just before that edge.
            local stepCount: number = 7
            local reach: number = 1.0 + safeWalkSettings.lookAhead + 0.8
            local step: number = (reach - 1.0) / (stepCount - 1)
            local lastGrounded: number? = nil
            local firstGap: number? = nil
            for index: number = 1, stepCount do
                local distance: number = 1.0 + step * (index - 1)
                local probeOrigin: Vector3 = root.Position + moveDirection * distance
                local ground: RaycastResult? = currentWorkspace:Raycast(
                    probeOrigin,
                    Vector3.new(0, -6, 0),
                    parameters
                )
                if ground then
                    lastGrounded = distance
                elseif lastGrounded ~= nil then
                    firstGap = distance
                    break
                end
            end

            if lastGrounded == nil then
                -- The edge is already under the feet: block right ahead.
                lastGrounded = 0.4
                firstGap = 1.0
            end
            if firstGap == nil then
                -- Solid floor ahead: nothing to block.
                hideBarrier()
                if SafeWalkFeature then
                    SafeWalkFeature:SetStatus(nil)
                end
                return
            end

            local edgeDistance: number = (lastGrounded + firstGap) * 0.5
            local feetHeight: number = root.Size.Y * 0.5 + humanoid.HipHeight
            local barrierHeight: number = math.max(safeWalkSettings.barrierHeight, 3)
            local part: BasePart = ensureBarrier()
            part.Size = Vector3.new(7, barrierHeight, 0.35)
            local feetY: number = root.Position.Y - feetHeight
            local position: Vector3 = root.Position + moveDirection * edgeDistance
            -- Thin axis (Z) points along the movement direction, so the wide
            -- face of the part faces the player like a wall.
            part.CFrame = CFrame.lookAt(
                Vector3.new(position.X, feetY + barrierHeight * 0.5, position.Z),
                Vector3.new(position.X, feetY + barrierHeight * 0.5, position.Z)
                    + moveDirection
            )
            if SafeWalkFeature then
                SafeWalkFeature:SetStatus("edge")
            end
        end)
    end

    SafeWalkFeature = createUniversalFeature(
        "SafeWalk",
        "Place an invisible barrier at edges so you cannot walk off ledges",
        21,
        toggleSafeWalk,
        {
            configKey = "Universal.SafeWalk",
            categoryName = "Movement",
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
        hideBarrier()
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
