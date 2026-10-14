local Module = {
    Name = "MM2 Trajectory Calibration",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Trajectory Calibration requires the MM2 core module")
    Module.Runtime = runtime
    local trajectoryCalibration: any = core.trajectoryCalibration

    local TrajectoryFeature: any = state.metricsFeature
    if not TrajectoryFeature then
        TrajectoryFeature = createUniversalFeature(
            "Metrics",
            "Calibration and game-learning telemetry in one card: projectile "
                .. "analytics, client observations, optional motion calibration.",
            5,
            function(): () end,
            {
                category = true,
                categoryName = "Other",
                parent = MM2Scroll,
                registry = mm2Features,
            }
        )
        state.metricsFeature = TrajectoryFeature
    end
    local finishPanel = state.beginMetricsPanel(TrajectoryFeature, "Calibration")
    addActionOption(TrajectoryFeature, "Show learned profile", function(): ()
        local text = trajectoryCalibration:status()
        print("[Wurst:MM2:Calibration] " .. text)
        notify(text)
    end)
    addToggleOption(TrajectoryFeature, "Detailed MM2 trajectories", false, function(value: boolean): ()
        core.mm2Settings.calibrationDetails = value
    end, "OFF keeps lightweight attempts/observations; ON adds target-motion windows. This does not enable prediction training.")
    addToggleOption(TrajectoryFeature, "MM2 automatic saves", false, function(value: boolean): ()
        core.mm2Settings.calibrationAutosave = value
    end, "Optional 10-second batched saves. OFF still permits Save calibration and final save on Destruct.")
    addToggleOption(TrajectoryFeature, "Adaptive gun timing", false, function(value: boolean): ()
        core.mm2Settings.adaptiveGunTiming = value
    end, "Experimental: use fresh uniquely matched authored-shot response timing. OFF preserves the RTT baseline; response time is not collision time.")
    addToggleOption(TrajectoryFeature, "Use observed knife speed", false, function(value: boolean): ()
        core.mm2Settings.useKnifeSpeedCalibration = value
    end, "OFF uses 96 studs/s. ON uses at least 3 fresh speed observations (60s window), not the historical mean. This may describe a client visual, not collision physics.")
    addActionOption(TrajectoryFeature, "Reset live timing", function(): ()
        trajectoryCalibration:resetTiming()
        core.resetAutoLeadCorrection()
        notify("Live timing and auto lead cleared; saved history and manual biases kept.")
    end)
    addActionOption(TrajectoryFeature, "Save calibration", function(): ()
        if trajectoryCalibration:save("manual") then
            notify("Trajectory calibration saved in the executor workspace.")
        else
            notify("Trajectory calibration could not be saved; check F9.")
        end
    end)
    addActionOption(TrajectoryFeature, "Clear MM2 history", function(): ()
        trajectoryCalibration:reset()
        notify("Trajectory calibration history cleared.")
    end)
    addInformationOption(
        TrajectoryFeature,
        "Schema 4: attempts, matched signals and projectile observations are NOT kills. Detailed capture, autosave and timing adaptation are independent. See Show learned profile/F9 for observer health and save cost."
    )

    finishPanel()
    activeCleanup = function(): ()

    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
