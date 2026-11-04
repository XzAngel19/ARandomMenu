local Module = {
    Name = "MM2 Trajectory Calibration",
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

    -- v180: the capture card is back in release. What changed is consent: the
    -- recorder only writes to the executor workspace after the player answers
    -- the prompt with Yes. Answering No keeps everything in memory and writes
    -- nothing.
    local TrajectoryFeature: any = state.mm2CalibrationFeature
    if not TrajectoryFeature then
        TrajectoryFeature = createUniversalFeature(
            "Calibration",
            "MM2 shot and knife calibration. Nothing is written to your workspace "
                .. "unless you answer Yes to the calibration prompt.",
            5,
            function(): () end,
            {
                category = true,
                categoryName = "Other",
                parent = MM2Scroll,
                registry = mm2Features,
            }
        )
        state.mm2CalibrationFeature = TrajectoryFeature
    end

    -- Three samples make a correction live and the window holds eight; twenty
    -- is a settled median, which is what a dozen or two matches should reach.
    local LEAD_SAMPLES_FOR_CONFIDENCE: number = 20

    local askedThisSession: boolean = false

    local function consent(): boolean?
        if type(trajectoryCalibration) ~= "table"
            or type(trajectoryCalibration.getConsent) ~= "function" then
            return nil
        end
        local ok: boolean, value: any = pcall(trajectoryCalibration.getConsent, trajectoryCalibration)
        if not ok then
            return nil
        end
        if value == true then
            return true
        end
        if value == false then
            return false
        end
        return nil
    end

    local function setConsent(value: boolean?): ()
        if type(trajectoryCalibration) ~= "table"
            or type(trajectoryCalibration.setConsent) ~= "function" then
            return
        end
        pcall(trajectoryCalibration.setConsent, trajectoryCalibration, value)
        if TrajectoryFeature and type(TrajectoryFeature.SetStatus) == "function" then
            TrajectoryFeature:SetStatus(
                value == true and "giving calibration"
                    or (value == false and "off" or nil)
            )
        end
    end

    -- The centred question. Yes starts saving; No guarantees nothing is saved
    -- (and removes the file a previous Yes wrote).
    local function askConsent(): ()
        askedThisSession = true
        local dialog: any = state.confirmDialog
        if type(dialog) ~= "function" then
            -- No host dialog (older bundle): stay silent rather than saving
            -- anything without an answer.
            setConsent(nil)
            return
        end
        local ok: boolean, failure: any = pcall(dialog, {
            title = "Give your calibration?",
            message = "Would you like to give your calibration? MM2 will save your "
                .. "shot and knife data to a JSON file in your executor workspace so "
                .. "the aim can be tuned with real numbers. Choose No and nothing at "
                .. "all is written.",
            yes = "Yes",
            no = "No",
            onYes = function(): ()
                setConsent(true)
                if TrajectoryFeature and type(TrajectoryFeature.SetStatus) == "function" then
                    TrajectoryFeature:SetStatus("giving calibration")
                end
                notify("Calibration ON: saving to your workspace/Telemetry folder.")
            end,
            onNo = function(): ()
                setConsent(false)
                if TrajectoryFeature and type(TrajectoryFeature.SetStatus) == "function" then
                    TrajectoryFeature:SetStatus("off")
                end
                notify("Calibration OFF: nothing will be saved.")
            end,
        })
        if not ok then
            warn("[Wurst] calibration prompt failed: " .. tostring(failure))
        end
    end

    -- The point of the calibration is a predictor that is right after a dozen
    -- matches, so the card has to say how far that has come.
    local function learningSummary(): string
        local predictor: any = state and state.mm2Prediction
        if type(predictor) ~= "table" then
            return "learning: no data yet"
        end
        if type(predictor.exportLeadState) ~= "function" then
            return "learning: readiness unavailable"
        end
        local ok: boolean, buckets: any = pcall(predictor.exportLeadState)
        if not ok or type(buckets) ~= "table" then
            return "learning: readiness unavailable"
        end
        local parts: {string} = {}
        for mode: string, entry: any in pairs(buckets) do
            if type(entry) == "table" then
                local samples: number = tonumber(entry.samples) or 0
                local applied: number = tonumber(entry.applied) or 0
                table.insert(
                    parts,
                    string.format(
                        "%s %d/%d %+d ms",
                        mode,
                        samples,
                        LEAD_SAMPLES_FOR_CONFIDENCE,
                        math.round(applied * 1000)
                    )
                )
            end
        end
        if #parts == 0 then
            return "learning: no confirmed shots yet"
        end
        table.sort(parts)
        return "learning: " .. table.concat(parts, " · ")
    end

    addActionOption(TrajectoryFeature, "Calibration status", function(): ()
        local status: string = "unavailable"
        if type(trajectoryCalibration) == "table"
            and type(trajectoryCalibration.status) == "function" then
            local ok: boolean, value: any = pcall(trajectoryCalibration.status, trajectoryCalibration)
            status = ok and tostring(value) or "unavailable"
        end
        notify(status .. " · " .. learningSummary())
    end, "Shows what the recorder has measured so far.")

    addActionOption(TrajectoryFeature, "Give calibration", function(): ()
        setConsent(true)
        notify("Calibration ON: saving to your workspace/Telemetry folder.")
    end, "Answer Yes again and start saving the current session.")

    addActionOption(TrajectoryFeature, "Stop giving calibration", function(): ()
        setConsent(false)
        notify("Calibration OFF: nothing will be saved and the file was removed.")
    end, "Answer No: stop saving and delete the file this menu wrote.")

    addActionOption(TrajectoryFeature, "Ask again", function(): ()
        setConsent(nil)
        askConsent()
    end, "Re-open the calibration question in the middle of the screen.")

    addActionOption(TrajectoryFeature, "Clear MM2 history", function(): ()
        if type(trajectoryCalibration) == "table"
            and type(trajectoryCalibration.reset) == "function" then
            pcall(trajectoryCalibration.reset, trajectoryCalibration)
        end
        notify("Trajectory calibration history cleared.")
    end, "Forget everything measured so far.")

    addInformationOption(
        TrajectoryFeature,
        "Records target windows around your shots and throws. MM2-only calibration; "
            .. "nothing is written to your workspace unless you give your calibration."
    )

    -- Ask once per session when the question has never been answered. A saved
    -- answer (Yes or No) is respected: no prompt on every injection.
    if consent() == nil and not askedThisSession then
        task.delay(3, function(): ()
            if Module.Initialized and consent() == nil then
                askConsent()
            end
        end)
    elseif consent() == true and type(TrajectoryFeature.SetStatus) == "function" then
        TrajectoryFeature:SetStatus("giving calibration")
    elseif consent() == false and type(TrajectoryFeature.SetStatus) == "function" then
        TrajectoryFeature:SetStatus("off")
    end

    activeCleanup = function(): ()
        if state.mm2CalibrationFeature == TrajectoryFeature then
            state.mm2CalibrationFeature = nil
        end
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
