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
    local roundTimer: any = core.roundTimer
    local getRoundData: any = core.getRoundData

    -- The core already waited for ReplicatedStorage.Remotes.Gameplay, so these
    -- are resolved from it instead of racing the replication ourselves.
    local gameplayRemotes: Instance? = core.mm2GameplayRemotes
    local timerRoundStart: Instance? = gameplayRemotes
        and gameplayRemotes:FindFirstChild("RoundStart")
    local timerGetter: Instance? = gameplayRemotes
        and gameplayRemotes:FindFirstChild("GetTimer", true)

    local timerSpoofActive: boolean = false
    local revealedTimerObjects: {[Instance]: boolean} =
        setmetatable({}, {__mode = "k"}) :: any
    local ownedLabel: TextLabel? = nil
    local fallbackGui: ScreenGui? = nil
    local fallbackLabel: TextLabel? = nil
    local lastResyncAt: number = -math.huge

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
        if not (frame and frame:IsA("GuiObject")) then
            return nil, nil
        end
        -- MM2 has renamed this label across updates, so take the first
        -- TextLabel in the frame instead of trusting a single name.
        local label: Instance? = frame:FindFirstChild("XPText")
            or frame:FindFirstChild("Timer")
            or frame:FindFirstChildWhichIsA("TextLabel", true)
        return frame, (label and label:IsA("TextLabel")) and label or nil
    end

    local function formatRoundClock(remaining: number): string
        local minutes: number = math.floor(remaining / 60)
        local seconds: number = remaining - minutes * 60
        if minutes > 0 then
            return string.format("%d:%02d", minutes, seconds)
        end
        return tostring(seconds) .. "s"
    end

    local function destroyFallback(): ()
        if fallbackGui then
            pcall(function(): ()
                (fallbackGui :: any):Destroy()
            end)
        end
        fallbackGui = nil
        fallbackLabel = nil
    end

    -- Last resort: MM2's own Timer frame is gone or has no label. Draw our own
    -- so the feature still does what its name says.
    local function ensureFallbackLabel(): TextLabel?
        if fallbackLabel and fallbackLabel.Parent then
            return fallbackLabel
        end
        destroyFallback()
        local playerGui: PlayerGui? = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then
            return nil
        end
        local gui: ScreenGui = create("ScreenGui", {
            Parent = playerGui,
            Name = "WurstRoundTimer",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 50,
        }) :: any
        local label: TextLabel = create("TextLabel", {
            Parent = gui,
            Name = "Clock",
            BackgroundTransparency = 0.35,
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 6),
            Size = UDim2.new(0, 96, 0, 26),
            Font = CONTROL_FONT,
            TextSize = 18,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Text = "",
        }) :: any
        create("UICorner", {Parent = label, CornerRadius = UDim.new(0, 6)})
        fallbackGui = gui
        fallbackLabel = label
        return label
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

    local function hideRevealedObjects(): ()
        for object: Instance, _ in pairs(revealedTimerObjects) do
            if object and object.Parent then
                local guiObject: any = object
                pcall(function(): ()
                    guiObject.Visible = false
                end)
            end
        end
        revealedTimerObjects = setmetatable({}, {__mode = "k"}) :: any
        ownedLabel = nil
        destroyFallback()
    end

    local function restoreRoundTimerRole(): ()
        if timerSpoofActive
            and timerRoundStart
            and timerRoundStart:IsA("RemoteEvent")
            and next(getRoundData()) ~= nil
            and roundTimer.endsAt then
            local remaining: number =
                math.max(1, math.floor(roundTimer.endsAt - os.clock()))
            fireClientSignal(timerRoundStart.OnClientEvent, remaining, getRoundData())
        end
        timerSpoofActive = false
        hideRevealedObjects()
    end

    local function paintClock(label: TextLabel, remaining: number): ()
        label.Text = formatRoundClock(remaining)
        label.TextColor3 = remaining <= 30
            and Color3.fromRGB(255, 70, 70)
            or Color3.fromRGB(255, 255, 255)
    end

    -- Returns true when we are the ones driving the on-screen clock, so the
    -- caller keeps refreshing it instead of assuming the game took over.
    local function revealTimerManually(remaining: number): boolean
        local frame: GuiObject?, label: TextLabel? = findGameTimerFrame()
        if frame then
            if not frame.Visible then
                revealedTimerObjects[frame] = true
                frame.Visible = true
            end
            if label then
                ownedLabel = label
                paintClock(label, remaining)
                return true
            end
        end
        local fallback: TextLabel? = ensureFallbackLabel()
        if fallback then
            ownedLabel = fallback
            paintClock(fallback, remaining)
            return true
        end
        return false
    end

    local function resyncFromServer(): ()
        if not (timerGetter and timerGetter:IsA("RemoteFunction")) then
            return
        end
        lastResyncAt = os.clock()
        task.spawn(function(): ()
            pcall(function(): ()
                local remaining: number? = tonumber((timerGetter :: any):InvokeServer())
                if remaining and remaining > 0 then
                    roundTimer.endsAt = os.clock() + remaining
                end
            end)
        end)
    end

    local function toggleAlwaysShowTimer(enabled: boolean): ()
        disconnectFeatureConnection("MM2AlwaysTimer")

        if not enabled then
            restoreRoundTimerRole()
            return
        end

        lastResyncAt = -math.huge
        resyncFromServer()

        local elapsed: number = 1
        local lastSpoofAt: number = -math.huge
        featureConnections.MM2AlwaysTimer = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.25 then
                return
            end
            elapsed = 0

            local remaining: number? = roundTimer.endsAt
                and math.max(0, math.ceil(roundTimer.endsAt - os.clock()))
            if not remaining or remaining <= 0 then
                timerSpoofActive = false
                -- Round over (or we joined mid-round and never saw RoundStart):
                -- drop whatever we forced on screen and ask the server again.
                if next(revealedTimerObjects) ~= nil or ownedLabel then
                    hideRevealedObjects()
                end
                if os.clock() - lastResyncAt >= 5 then
                    resyncFromServer()
                end
                return
            end

            local frame: GuiObject? = findGameTimerFrame()
            local weOwnTheClock: boolean = ownedLabel ~= nil
                and ownedLabel.Parent ~= nil
                and (fallbackLabel == ownedLabel or frame ~= nil)

            -- The game is showing its own countdown and we did not force it:
            -- leave it alone, it updates itself.
            if frame and frame.Visible and not weOwnTheClock
                and revealedTimerObjects[frame] == nil then
                return
            end

            -- This is the bug the split exposed: once we revealed the frame it
            -- stayed "Visible", the loop bailed out early and the number froze
            -- on whatever second it was revealed at. Now we keep painting it.
            if weOwnTheClock then
                paintClock(ownedLabel :: TextLabel, remaining)
                return
            end

            if os.clock() - lastSpoofAt >= 2 then
                lastSpoofAt = os.clock()
                if spoofRoundTimerRole(remaining) then
                    timerSpoofActive = true
                else
                    revealTimerManually(remaining)
                end
            else
                revealTimerManually(remaining)
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
        destroyFallback()
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
