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
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local workspace: any = host.workspace
    local fovSettings = {value = 90}
    local FovFeature: any = nil
    state.fovController = state.fovController or {
        owners = {},
        baselines = setmetatable({}, {__mode = "k"}),
        sequence = 0,
    }
    state.fovController.set = function(ownerId: string, value: number?): ()
        local controller: any = state.fovController
        if value == nil then
            controller.owners[ownerId] = nil
            if next(controller.owners) == nil then
                for camera: Camera, baseline: number in pairs(controller.baselines) do
                    if camera.Parent then
                        camera.FieldOfView = baseline
                    end
                end
                controller.baselines = setmetatable({}, {__mode = "k"})
            end
            return
        end
        local owner: any = controller.owners[ownerId]
        if not owner then
            controller.sequence += 1
            owner = {sequence = controller.sequence, value = value}
            controller.owners[ownerId] = owner
        else
            owner.value = value
        end
    end
    state.fovController.apply = function(camera: Camera?): ()
        if not camera then
            return
        end
        local controller: any = state.fovController
        if controller.baselines[camera] == nil then
            controller.baselines[camera] = camera.FieldOfView
        end
        local selected: any = nil
        for _, owner: any in pairs(controller.owners) do
            if not selected or owner.sequence > selected.sequence then
                selected = owner
            end
        end
        if selected then
            camera.FieldOfView = selected.value
        end
    end

    local function toggleFov(enabled)
        disconnectFeatureConnection("FOV")
        state.fovController.set("Universal", enabled and fovSettings.value or nil)
        if not enabled then
            if FovFeature then FovFeature:SetStatus(nil) end
            return
        end

        FovFeature:SetStatus(tostring(math.round(fovSettings.value)))
        featureConnections.FOV = TaskManager:Connect(function()
            state.fovController.set("Universal", fovSettings.value)
            state.fovController.apply(workspace.CurrentCamera)
        end)
    end

    FovFeature = createUniversalFeature(
        "FOV",
        "Keep the camera field of view fixed",
        10,
        toggleFov
    )
    addNumberOption(FovFeature, "Field of view", fovSettings.value, 20, 120, function(value)
        fovSettings.value = value
        if FovFeature.enabled then
            FovFeature:SetStatus(tostring(math.round(value)))
        end
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("Fov")
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
