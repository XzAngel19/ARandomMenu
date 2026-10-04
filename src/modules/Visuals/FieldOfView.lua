--!strict
--
-- Field of View.
--
-- The camera's own FOV, held against games that write it every frame. It goes
-- through the shared FOV controller so that two modules asking for a field of
-- view do not fight each other.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "FieldOfView",
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
    local fovOwnership: any = context.services.fovOwnership
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local workspace: any = host.workspace
    local fovSettings = {value = 90}
    local FovFeature: any = nil


    local function toggleFov(enabled)
        disconnectFeatureConnection("FOV")
        fovOwnership.set("Universal", enabled and fovSettings.value or nil)
        if not enabled then
            if FovFeature then FovFeature:SetStatus(nil) end
            return
        end

        FovFeature:SetStatus(tostring(math.round(fovSettings.value)))
        featureConnections.FOV = TaskManager:Connect(function()
            fovOwnership.set("Universal", fovSettings.value)
            fovOwnership.apply(workspace.CurrentCamera)
        end)
    end

    FovFeature = createUniversalFeature(
        "FOV",
        "Keep the camera field of view fixed",
        10,
        toggleFov,
        {categoryName = "Render"}
    )
    addNumberOption(FovFeature, "Field of view", fovSettings.value, 20, 120, function(value)
        fovSettings.value = value
        if FovFeature.enabled then
            FovFeature:SetStatus(tostring(math.round(value)))
        end
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("FOV")
        fovOwnership.set("Universal", nil)
    end
    Module.Initialized = true
    return FovFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
