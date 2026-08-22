--!strict
--
-- Zoom Unlocker.
--
-- Lifts the camera distance limits the game set, and optionally the first
-- person lock with them. Client-side camera properties only: the server has no
-- opinion about how far your own camera sits from your head.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "ZoomUnlocker",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    type ZoomSettings = {
        minDistance: number,
        maxDistance: number,
        unlockFirstPerson: boolean,
    }
    type ZoomState = {
        minDistance: number,
        maxDistance: number,
        cameraMode: Enum.CameraMode,
    }
    local zoomSettings: ZoomSettings = {
        minDistance = 0.5,
        maxDistance = 400,
        unlockFirstPerson = true,
    }
    local originalZoomState: ZoomState? = nil
    local ZoomFeature: any = nil

    local function toggleZoomUnlocker(enabled: boolean): ()
        disconnectFeatureConnection("ZoomUnlocker")
        if originalZoomState then
            LocalPlayer.CameraMinZoomDistance = originalZoomState.minDistance
            LocalPlayer.CameraMaxZoomDistance = originalZoomState.maxDistance
            LocalPlayer.CameraMode = originalZoomState.cameraMode
            originalZoomState = nil
        end
        if not enabled then
            if ZoomFeature then ZoomFeature:SetStatus(nil) end
            return
        end
        ZoomFeature:SetStatus(tostring(math.round(zoomSettings.maxDistance)) .. " studs")
        originalZoomState = {
            minDistance = LocalPlayer.CameraMinZoomDistance,
            maxDistance = LocalPlayer.CameraMaxZoomDistance,
            cameraMode = LocalPlayer.CameraMode,
        }
        featureConnections.ZoomUnlocker = TaskManager:Connect(function(): ()
            LocalPlayer.CameraMinZoomDistance = math.min(
                zoomSettings.minDistance,
                zoomSettings.maxDistance
            )
            LocalPlayer.CameraMaxZoomDistance = math.max(
                zoomSettings.minDistance,
                zoomSettings.maxDistance
            )
            if zoomSettings.unlockFirstPerson then
                LocalPlayer.CameraMode = Enum.CameraMode.Classic
            elseif originalZoomState then
                LocalPlayer.CameraMode = originalZoomState.cameraMode
            end
        end)
    end


    ZoomFeature = createUniversalFeature(
        "Zoom",
        "Extend camera zoom and optionally leave forced first person",
        23,
        toggleZoomUnlocker,
        {
            configKey = "Universal.ZoomUnlocker",
            categoryName = "Render",
        }
    )
    addNumberOption(
        ZoomFeature,
        "Maximum distance",
        zoomSettings.maxDistance,
        25,
        2000,
        function(value: number): ()
            zoomSettings.maxDistance = value
            if ZoomFeature.enabled then
                ZoomFeature:SetStatus(tostring(math.round(value)) .. " studs")
            end
        end
    )
    addNumberOption(
        ZoomFeature,
        "Minimum distance",
        zoomSettings.minDistance,
        0.5,
        50,
        function(value: number): ()
            zoomSettings.minDistance = value
        end
    )
    addToggleOption(
        ZoomFeature,
        "Unlock forced first person",
        zoomSettings.unlockFirstPerson,
        function(value: boolean): ()
            zoomSettings.unlockFirstPerson = value
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("ZoomUnlocker")
    end
    Module.Initialized = true
    return ZoomFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
