--!strict
--
-- Safe Walk.
--
-- Stops the character before it walks off an edge, by probing the floor a
-- couple of studs ahead of where it is heading.

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
    local safeWalkSettings: {lookAhead: number} = {lookAhead = 2.8}
    local function toggleSafeWalk(enabled: boolean): ()
        disconnectFeatureConnection("SafeWalk")
        if not enabled then
            return
        end
        featureConnections.SafeWalk = TaskManager:Connect(function(): ()
            local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not character or not humanoid or not root
                or humanoid.MoveDirection.Magnitude < 0.05
                or humanoid.FloorMaterial == Enum.Material.Air then
                return
            end
            local params: RaycastParams = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character}
            local probeOrigin: Vector3 = root.Position
                + humanoid.MoveDirection.Unit * safeWalkSettings.lookAhead
            local ground: RaycastResult? = workspace:Raycast(
                probeOrigin,
                Vector3.new(0, -5.2, 0),
                params
            )
            if not ground then
                local velocity: Vector3 = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
            end
        end)
    end


    local SafeWalkFeature = createUniversalFeature(
        "Safe Walk",
        "Stop horizontal movement before walking over an edge",
        21,
        toggleSafeWalk
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

    activeCleanup = function(): ()
        disconnectFeatureConnection("SafeWalk")
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
