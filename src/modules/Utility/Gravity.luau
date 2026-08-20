--!strict
--
-- Gravity.
--
-- `workspace.Gravity` is a client property here: the server keeps its own
-- value and other players fall at their own rate. Restored on disable.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Gravity",
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
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local workspace: any = host.workspace
    local gravitySettings = {value = 196.2}
    local originalGravity = workspace.Gravity

    local function toggleGravity(enabled)
        disconnectFeatureConnection("Gravity")

        if not enabled then
            workspace.Gravity = originalGravity
            return
        end

        originalGravity = workspace.Gravity
        featureConnections.Gravity = TaskManager:Connect(function()
            workspace.Gravity = gravitySettings.value
        end)
    end

    local GravityFeature = createUniversalFeature(
        "Gravity",
        "Keep workspace gravity at a custom value",
        5,
        toggleGravity
    )
    addNumberOption(GravityFeature, "Gravity value", gravitySettings.value, 0, 500, function(value)
        gravitySettings.value = value
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("Gravity")
    end
    Module.Initialized = true
    return GravityFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
