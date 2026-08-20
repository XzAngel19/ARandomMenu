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
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local Lighting: any = host.Lighting
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local featureConnections: any = host.featureConnections
    local TaskManager: any = host.TaskManager

    state.fullbrightSettings = {
        brightness = 3,
        clockTime = 14,
    }
    state.originalLighting = nil

    state.toggleFullbright = function(enabled)
        disconnectFeatureConnection("Fullbright")

        if not enabled then
            if state.originalLighting then
                Lighting.Brightness = state.originalLighting.brightness
                Lighting.ClockTime = state.originalLighting.clockTime
                Lighting.GlobalShadows = state.originalLighting.globalShadows
                Lighting.FogEnd = state.originalLighting.fogEnd
                Lighting.Ambient = state.originalLighting.ambient
                Lighting.OutdoorAmbient = state.originalLighting.outdoorAmbient
            end
            return
        end

        state.originalLighting = {
            brightness = Lighting.Brightness,
            clockTime = Lighting.ClockTime,
            globalShadows = Lighting.GlobalShadows,
            fogEnd = Lighting.FogEnd,
            ambient = Lighting.Ambient,
            outdoorAmbient = Lighting.OutdoorAmbient,
        }

        featureConnections.Fullbright = TaskManager:Connect(function()
            Lighting.Brightness = state.fullbrightSettings.brightness
            Lighting.ClockTime = state.fullbrightSettings.clockTime
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
        state.toggleFullbright
    )
    addNumberOption(
        FullbrightFeature,
        "Brightness",
        state.fullbrightSettings.brightness,
        0,
        10,
        function(value)
            state.fullbrightSettings.brightness = value
        end
    )
    addNumberOption(
        FullbrightFeature,
        "Clock time",
        state.fullbrightSettings.clockTime,
        0,
        24,
        function(value)
            state.fullbrightSettings.clockTime = value
        end
    )

    activeCleanup = function(): ()
        state.toggleFullbright(false)
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
