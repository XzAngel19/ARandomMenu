export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AntiVoid",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local workspace: any = host.workspace
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local addToggleOption: any = host.addToggleOption
    local addFeatureTooltip: any = host.addFeatureTooltip
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection

    local enabled: boolean = false
    local distance: number = 4
    local visible: boolean = false
    local platform: BasePart? = nil
    local platformY: number? = nil
    -- v160: the step used to write Size, CFrame and Transparency every single
    -- frame, even standing still, and each write inside a pcall. The part only
    -- has to move when the character moved or the platform was rebuilt.
    local writtenPosition: Vector3? = nil
    local writtenVisible: boolean? = nil
    local antiVoidFeature: any = nil

    local PLATFORM_NAME: string = "Wurst_AntiVoidPlatform"
    local PLATFORM_SIZE: Vector3 = Vector3.new(14, 1, 14)

    local function destroyPlatform(): ()
        if platform then platform:Destroy(); platform = nil end
        platformY = nil
        writtenPosition, writtenVisible = nil, nil
    end

    local function destroyHeightFloor(): number
        local destroyHeight: number = workspace.FallenPartsDestroyHeight
        -- Fling can temporarily set this to infinity; keep the platform finite.
        if destroyHeight ~= destroyHeight or math.abs(destroyHeight) > 1e6 then
            return -500
        end
        return destroyHeight
    end

    local function createPlatform(): BasePart
        local part: BasePart = Instance.new("Part")
        part.Name = PLATFORM_NAME
        part.Anchored = true
        part.CanCollide = true
        -- CanQuery=false is ignored by the engine while CanCollide=true;
        -- CanTouch=false prevents this part from producing touch events.
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.Locked = true
        part.Transparency = if visible then 0.4 else 1
        part.Size = PLATFORM_SIZE
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Parent = workspace
        return part
    end

    -- The platform follows the character horizontally and sits `distance` studs
    -- under the feet. While the character is falling it stops descending where
    -- it is, so the fall actually lands on it instead of dragging it down.
    local function step(): ()
        if not enabled then
            return
        end
        local _character: Model?, humanoid: Humanoid?, root: BasePart? = host.getCharacterParts()
        if not root or not root.Parent or (humanoid and humanoid.Health <= 0) then
            destroyPlatform()
            return
        end
        if not platform or not platform.Parent then
            destroyPlatform()
            platform = createPlatform()
            platformY = nil
        end

        local position: Vector3 = root.Position
        local desiredY: number = position.Y - distance
        if platformY == nil
            or desiredY > platformY
            or position.Y - platformY > distance + 12
            or platformY - position.Y > 200 then
            platformY = desiredY
        end
        local floor: number = destroyHeightFloor()
        local y: number = math.max(platformY or desiredY, floor + 8)

        local target: Vector3 = Vector3.new(position.X, y, position.Z)
        if writtenPosition and writtenVisible == visible
            and (target - writtenPosition).Magnitude < 0.05 then
            return
        end
        writtenPosition, writtenVisible = target, visible
        platform.CFrame = CFrame.new(target)
        platform.Transparency = if visible then 0.4 else 1
    end

    local function toggleAntiVoid(state: boolean): ()
        enabled = state == true
        disconnectFeatureConnection("AntiVoid")
        if not enabled then
            destroyPlatform()
            return
        end
        host.featureConnections.AntiVoid = host.TaskManager:Connect(step, nil, "Anti Void")
        step()
    end

    antiVoidFeature = createUniversalFeature(
        "Anti Void",
        "Invisible platform kept under the character so the void never catches you",
        1,
        toggleAntiVoid,
        {categoryName = "Utilities"}
    )
    addNumberOption(
        antiVoidFeature,
        "Distance",
        distance,
        1,
        40,
        function(value: number): ()
            distance = math.clamp(tonumber(value) or 4, 1, 40)
            platformY = nil
        end,
        "Studs below your feet where the platform waits.",
        1
    )
    addToggleOption(
        antiVoidFeature,
        "Show platform",
        false,
        function(value: boolean): ()
            visible = value == true
            if platform then
                platform.Transparency = if visible then 0.4 else 1
            end
        end,
        "Draw the platform so you can confirm where it is. Only you can see it either way."
    )
    addFeatureTooltip(
        antiVoidFeature,
        "Creates one local anchored part a few studs below the character. "
            .. "It stops descending while you fall so you can land on it. "
            .. "Touch events are disabled; its collidable surface may still appear in raycasts."
    )

    activeCleanup = function(): ()
        enabled = false
        disconnectFeatureConnection("AntiVoid")
        destroyPlatform()
    end
    Module.Initialized = true
    return antiVoidFeature
end

function Module.destroy(): ()
    if activeCleanup then
        activeCleanup()
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
