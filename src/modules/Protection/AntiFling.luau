--!strict
--
-- Anti-Fling.
--
-- Watches your own assembly velocity and puts you back where you were the
-- moment it goes somewhere no legitimate movement could take it. The threshold
-- is a slider because "impossible" is different in a game with vehicles.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AntiFling",
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
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local antiFlingSettings = {velocityLimit = 120}
    local antiFlingSafeCFrame = nil

    local function toggleAntiFling(enabled)
        disconnectFeatureConnection("AntiFling")
        antiFlingSafeCFrame = nil

        if not enabled then
            return
        end

        featureConnections.AntiFling = TaskManager:Connect(function()
            -- Your own fling is deliberate; standing on the brakes during it
            -- is the module fighting its owner.
            if state.flingRunning then
                return
            end

            local _, humanoid, root = getCharacterParts()
            if not humanoid or not root then
                return
            end

            local linearSpeed = root.AssemblyLinearVelocity.Magnitude
            local angularSpeed = root.AssemblyAngularVelocity.Magnitude

            if linearSpeed > antiFlingSettings.velocityLimit
                or angularSpeed > antiFlingSettings.velocityLimit then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                if antiFlingSafeCFrame then
                    root.CFrame = antiFlingSafeCFrame
                end
            elseif humanoid.FloorMaterial ~= Enum.Material.Air
                and linearSpeed < antiFlingSettings.velocityLimit * 0.45 then
                antiFlingSafeCFrame = root.CFrame
            end
        end)
    end

    local AntiFlingFeature = createUniversalFeature(
        "Anti-Fling",
        "Stop extreme local velocity and return to safety",
        14,
        toggleAntiFling
    )
    addNumberOption(
        AntiFlingFeature,
        "Velocity limit",
        antiFlingSettings.velocityLimit,
        40,
        1000,
        function(value)
            antiFlingSettings.velocityLimit = value
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("AntiFling")
    end
    Module.Initialized = true
    return AntiFlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
