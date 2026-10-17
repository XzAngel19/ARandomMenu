local Module = {Name = "ZoomUnlocker", Initialized = false}
local cleanup

function Module.init(context)
    local host, player = context.host, context.host.LocalPlayer
    local access = context.services.cameraAccess
    local settings = {minimum=0.5, maximum=400, firstPerson=true, walls=false}
    local original, feature
    local function bounds(minimum,maximum)
        if player.CameraMinZoomDistance > maximum then player.CameraMinZoomDistance = minimum end
        player.CameraMaxZoomDistance = maximum
        player.CameraMinZoomDistance = minimum
    end
    local function apply()
        bounds(math.min(settings.minimum,settings.maximum),math.max(settings.minimum,settings.maximum))
        player.CameraMode = settings.firstPerson and Enum.CameraMode.Classic or original.mode
        local walls = access:ThroughWalls(settings.walls)
        feature:SetStatus(settings.walls and (walls and tostring(math.round(settings.maximum)) .. " / walls" or "walls unavailable")
            or tostring(math.round(settings.maximum)) .. " studs")
    end
    cleanup = function()
        host.disconnectFeatureConnection("ZoomUnlocker")
        access:ThroughWalls(false)
        if original then
            bounds(original.minimum,original.maximum)
            player.CameraMode = original.mode
            original = nil
        end
    end
    feature = host.createUniversalFeature("Zoom", "Extend zoom; optionally let the camera pass through walls.", 23, function(enabled)
        cleanup()
        if not enabled then feature:SetStatus(nil); return end
        original = {minimum=player.CameraMinZoomDistance, maximum=player.CameraMaxZoomDistance, mode=player.CameraMode}
        apply()
        host.featureConnections.ZoomUnlocker = host.TaskManager:Connect(apply)
    end, {configKey="Universal.ZoomUnlocker", categoryName="Render"})
    local function update(key,value)
        settings[key] = value
        if feature.enabled then apply() end
    end
    host.addNumberOption(feature,"Maximum distance",settings.maximum,25,2000,function(value) update("maximum",value) end)
    host.addNumberOption(feature,"Minimum distance",settings.minimum,0.5,50,function(value) update("minimum",value) end)
    host.addToggleOption(feature,"Unlock forced first person",settings.firstPerson,function(value) update("firstPerson",value) end)
    host.addToggleOption(feature,"Through walls",settings.walls,function(value) update("walls",value) end)
    Module.Initialized = true
    return feature
end
function Module.destroy()
    if cleanup then pcall(cleanup); cleanup = nil end
    Module.Initialized = false
end
return Module
