--!strict
--
-- Fullbright.
--
-- Lighting is a client service: brightness, clock time, fog and ambient are
-- this machine's opinion about how the map looks. Every value is captured on
-- the way in and restored on the way out, because a game that dims the lights
-- for its own round logic must be allowed to do it again afterwards.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Fullbright",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local Lighting: any = host.Lighting
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local featureConnections: any = host.featureConnections
    local TaskManager: any = host.TaskManager

    local fullbrightSettings = {
        brightness = 3,
        clockTime = 14,
    }
    local originalLighting: any = nil

    local function toggleFullbright(enabled: boolean): ()
        disconnectFeatureConnection("Fullbright")

        if not enabled then
            if originalLighting then
                Lighting.Brightness = originalLighting.brightness
                Lighting.ClockTime = originalLighting.clockTime
                Lighting.GlobalShadows = originalLighting.globalShadows
                Lighting.FogEnd = originalLighting.fogEnd
                Lighting.Ambient = originalLighting.ambient
                Lighting.OutdoorAmbient = originalLighting.outdoorAmbient
            end
            return
        end

        originalLighting = {
            brightness = Lighting.Brightness,
            clockTime = Lighting.ClockTime,
            globalShadows = Lighting.GlobalShadows,
            fogEnd = Lighting.FogEnd,
            ambient = Lighting.Ambient,
            outdoorAmbient = Lighting.OutdoorAmbient,
        }

        featureConnections.Fullbright = TaskManager:Connect(function()
            Lighting.Brightness = fullbrightSettings.brightness
            Lighting.ClockTime = fullbrightSettings.clockTime
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 100000
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
            Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        end)
    end

    local FullbrightFeature = createUniversalFeature(
        "Fullbright",
        "Keep the scene bright and remove global shadows",
        15,
        toggleFullbright,
        {categoryName = "Render"}
    )
    addNumberOption(
        FullbrightFeature,
        "Brightness",
        fullbrightSettings.brightness,
        0,
        10,
        function(value)
            fullbrightSettings.brightness = value
        end
    )
    addNumberOption(
        FullbrightFeature,
        "Clock time",
        fullbrightSettings.clockTime,
        0,
        24,
        function(value)
            fullbrightSettings.clockTime = value
        end
    )

    activeCleanup = function(): ()
        toggleFullbright(false)
    end
    Module.Initialized = true
    return FullbrightFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
