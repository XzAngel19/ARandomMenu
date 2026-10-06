local Module = {
    Name = "MM2 Always Show Timer",
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
    assert(type(core) == "table", "MM2 Always Show Timer requires the MM2 core module")
    Module.Runtime = runtime
    local getPlayerRole: any = core.getPlayerRole
    local roundTimer: any = core.roundTimer
    local getRoundData: any = core.getRoundData
    local timerRemotes: Instance? =
        game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local timerGameplay: Instance? = timerRemotes
        and timerRemotes:FindFirstChild("Gameplay")
    local timerRoundStart: Instance? = timerGameplay
        and timerGameplay:FindFirstChild("RoundStart")

    local timerSpoofActive: boolean = false
    local revealedTimerObjects: {[Instance]: boolean} =
        setmetatable({}, {__mode = "k"}) :: any

    local function fireClientSignal(signal: any, ...: any): boolean
        if type(getconnections) == "function" then
            local ok: boolean, connections: any = pcall(getconnections, signal)
            if ok and type(connections) == "table" then
                local delivered: boolean = false
                for _, connection: any in ipairs(connections) do
                    local fired: boolean = false
                    if type(connection.Fire) == "function" then
                        fired = pcall(connection.Fire, connection, ...)
                    end
                    if not fired and type(connection.Function) == "function" then
                        fired = pcall(connection.Function, ...)
                    end
                    delivered = delivered or fired
                end
                if delivered then
                    return true
                end
            end
        end
        if type(firesignal) == "function" then
            return (pcall(firesignal, signal, ...))
        end
        return false
    end

    local function findGameTimerFrame(): (GuiObject?, TextLabel?)
        local playerGui: PlayerGui? = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then
            return nil, nil
        end
        local mainGui: Instance? = playerGui:FindFirstChild("MainGUI")

        local gameFrame: Instance? = mainGui and mainGui:FindFirstChild("Game")
        local frame: Instance? = gameFrame and gameFrame:FindFirstChild("Timer")
        if frame and frame:IsA("GuiObject") then
            local label: Instance? = frame:FindFirstChild("XPText")
            return frame, (label and label:IsA("TextLabel")) and label or nil
        end
        return nil, nil
    end

    local function spoofRoundTimerRole(remaining: number): boolean
        if not timerRoundStart or not timerRoundStart:IsA("RemoteEvent") then
            return false
        end
        local payload: {[string]: any} = {}
        for key: any, value: any in pairs(getRoundData()) do
            payload[tostring(key)] = value
        end
        local mine: {[string]: any} = {}
        local existing: any = payload[LocalPlayer.Name]
        if type(existing) == "table" then
            for key: any, value: any in pairs(existing) do
                mine[tostring(key)] = value
            end
        end
        mine.Role = "Sheriff"
        mine.Dead = false
        payload[LocalPlayer.Name] = mine
        return fireClientSignal(
            timerRoundStart.OnClientEvent,
            math.max(1, math.floor(remaining)),
            payload
        )
    end

    local function restoreRoundTimerRole(): ()
        if timerSpoofActive
            and timerRoundStart
            and timerRoundStart:IsA("RemoteEvent")
            and next(getRoundData()) ~= nil
            and roundTimer.endsAt then
            local remaining: number = math.max(1, math.floor(roundTimer.endsAt - os.clock()))
            fireClientSignal(timerRoundStart.OnClientEvent, remaining, getRoundData())
        end
        timerSpoofActive = false

        for object: Instance, _ in pairs(revealedTimerObjects) do
            if object and object.Parent then
                local guiObject: any = object
                pcall(function(): ()
                    guiObject.Visible = false
                end)
            end
        end
        revealedTimerObjects = setmetatable({}, {__mode = "k"}) :: any
    end

    local function formatRoundClock(remaining: number): string
        local minutes: number = math.floor(remaining / 60)
        local seconds: number = remaining - minutes * 60
        if minutes > 0 then
            return tostring(minutes) .. "m " .. tostring(seconds) .. "s"
        end
        return tostring(seconds) .. "s"
    end

    local function revealTimerManually(remaining: number): ()
        local frame: GuiObject?, label: TextLabel? = findGameTimerFrame()
        if not frame then
            return
        end
        if not frame.Visible then
            revealedTimerObjects[frame] = true
            frame.Visible = true
        end
        if label then
            local localRole: string? = getPlayerRole(LocalPlayer)
            if localRole == nil or localRole == "Innocent" then
                label.Text = formatRoundClock(remaining)
                label.TextColor3 = remaining <= 30
                    and Color3.fromRGB(255, 0, 0)
                    or Color3.fromRGB(255, 255, 255)
            end
        end
    end

    local function toggleAlwaysShowTimer(enabled)
        disconnectFeatureConnection("MM2AlwaysTimer")

        if not enabled then
            restoreRoundTimerRole()
            return
        end

        local getTimer = timerRemotes and timerRemotes:FindFirstChild("GetTimer", true)
        if getTimer and getTimer:IsA("RemoteFunction") then
            task.spawn(function()
                pcall(function()
                    local remaining = tonumber(getTimer:InvokeServer())
                    if remaining and remaining > 0 then
                        roundTimer.endsAt = os.clock() + remaining
                    end
                end)
            end)
        end

        local elapsed: number = 1
        local lastSpoofAt: number = -math.huge
        featureConnections.MM2AlwaysTimer = TaskManager:Connect(function(deltaTime)
            elapsed += deltaTime
            if elapsed < 0.35 then
                return
            end
            elapsed = 0

            local remaining: number? = roundTimer.endsAt
                and math.max(0, math.ceil(roundTimer.endsAt - os.clock()))
            if not remaining or remaining <= 0 then
                if timerSpoofActive then
                    timerSpoofActive = false
                end
                return
            end

            local frame: GuiObject? = findGameTimerFrame()
            if frame and frame.Visible then

                return
            end

            if os.clock() - lastSpoofAt >= 2 then
                lastSpoofAt = os.clock()
                if spoofRoundTimerRole(remaining) then
                    timerSpoofActive = true
                else
                    revealTimerManually(remaining)
                end
            end
        end)
    end

    createUniversalFeature(
        "Always Show Timer",
        "Reveal the game's own round countdown, murderer or not",
        13,
        toggleAlwaysShowTimer,
        {
            noOptions = true,
            categoryName = "Render",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    activeCleanup = function(): ()
        toggleAlwaysShowTimer(false)
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
