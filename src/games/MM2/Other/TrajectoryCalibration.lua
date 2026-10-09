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

    local TrajectoryFeature: any = createUniversalFeature(
        "Trajectory Calibration",
        "MM2-only target motion, jump, ping, endpoint and knife-flight analytics",
        5,
        function(): () end,
        {
            category = true,
            categoryName = "Other",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addActionOption(TrajectoryFeature, "Show learned profile", function(): ()
        notify(trajectoryCalibration:status())
    end)
    addActionOption(TrajectoryFeature, "Save calibration", function(): ()
        if trajectoryCalibration:save("manual") then
            notify("Trajectory calibration saved in the executor workspace.")
        else
            notify("Trajectory calibration could not be saved; check F9.")
        end
    end)
    addActionOption(TrajectoryFeature, "Clear History", function(): ()
        trajectoryCalibration:reset()
        notify("Trajectory calibration history cleared.")
    end)
    addInformationOption(
        TrajectoryFeature,
        "Schema 2 records 30 Hz target windows only around your shots/throws. It stays isolated from Universal analytics and never changes weapon arguments."
    )

    activeCleanup = function(): ()
        -- nothing persistent to undo
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
