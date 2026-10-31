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
    local GravityFeature: any = nil
    local originalGravity: number? = nil

    local function restoreGravity()
        if originalGravity ~= nil then
            workspace.Gravity = originalGravity
            originalGravity = nil
        end
    end

    local function toggleGravity(enabled)
        disconnectFeatureConnection("Gravity")
        if not enabled then
            if GravityFeature then GravityFeature:SetStatus(nil) end
            restoreGravity()
            return
        end

        GravityFeature:SetStatus(tostring(math.round(gravitySettings.value)))
        if originalGravity == nil then originalGravity = workspace.Gravity end
        featureConnections.Gravity = TaskManager:Connect(function()
            if workspace.Gravity ~= gravitySettings.value then
                workspace.Gravity = gravitySettings.value
            end
        end, nil, "Gravity")
    end

    GravityFeature = createUniversalFeature(
        "Gravity",
        "Keep workspace gravity at a custom value",
        5,
        toggleGravity,
        {categoryName = "World"}
    )
    addNumberOption(GravityFeature, "Gravity value", gravitySettings.value, -500, 500, function(value)
        gravitySettings.value = value
        if GravityFeature.enabled then
            GravityFeature:SetStatus(tostring(math.round(value)))
        end
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("Gravity")
        restoreGravity()
    end
    Module.Initialized = true
    return GravityFeature
end

function Module.destroy(): ()
    if activeCleanup then
        activeCleanup()
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
