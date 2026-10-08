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
    local getRoundPhase: any = core.getRoundPhase

    -- MM2 itself publishes the live countdown as an attribute on
    -- workspace.RoundTimerPart, and the core keeps roundTimer.endsAt locked to
    -- it (see the "Round clock" section of base.lua). So the number painted here
    -- is the game's own number, refreshed every frame from the same source the
    -- game's Timer label reads - not a countdown rebuilt from the single
    -- RoundStart payload, which drifts and is lost entirely when RoundStart was
    -- missed.
    local revealedTimerObjects: {[Instance]: boolean} =
        setmetatable({}, {__mode = "k"}) :: any
    local fallbackGui: ScreenGui? = nil
    local fallbackLabel: TextLabel? = nil
    local lastPaintedText: string = ""

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
        -- MM2 has renamed this label across updates, so take the first TextLabel
        -- in the frame instead of trusting a single name.
        local label: Instance? = frame:FindFirstChild("XPText")
            or frame:FindFirstChild("Timer")
            or frame:FindFirstChildWhichIsA("TextLabel", true)
        return frame, (label and label:IsA("TextLabel")) and label or nil
    end

    local function formatRoundClock(remaining: number): string
        local whole: number = math.max(0, math.ceil(remaining))
        local minutes: number = math.floor(whole / 60)
        local seconds: number = whole - minutes * 60
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

    -- Last resort: MM2's own Timer frame is gone or has no label to borrow. Draw
    -- ours so the feature still does what its name says.
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
        destroyFallback()
        lastPaintedText = ""
    end

    local function paintClock(label: TextLabel, remaining: number): ()
        local text: string = formatRoundClock(remaining)
        if text == lastPaintedText and label.Text == text then
            return
        end
        lastPaintedText = text
        label.Text = text
        label.TextColor3 = remaining <= 30
            and Color3.fromRGB(255, 70, 70)
            or Color3.fromRGB(255, 255, 255)
    end

    -- Prefer the game's own frame (so the countdown sits where a player expects
    -- it), and fall back to ours only when there is nothing to borrow.
    local function paintRoundClock(remaining: number): ()
        local frame: GuiObject?, label: TextLabel? = findGameTimerFrame()
        if frame then
            if not frame.Visible then
                revealedTimerObjects[frame] = true
                frame.Visible = true
            end
            if label then
                paintClock(label, remaining)
                return
            end
        end
        local fallback: TextLabel? = ensureFallbackLabel()
        if fallback then
            paintClock(fallback, remaining)
        end
    end

    local function toggleAlwaysShowTimer(enabled: boolean): ()
        disconnectFeatureConnection("MM2AlwaysTimer")

        if not enabled then
            hideRevealedObjects()
            return
        end

        featureConnections.MM2AlwaysTimer = TaskManager:Connect(function(): ()
            local remaining: number? = roundTimer.endsAt
                and math.max(0, roundTimer.endsAt - os.clock())
            -- No live clock: either the round is over or the server has not
            -- published one yet. Put back whatever we forced on screen and let
            -- the game's own GUI do its thing.
            if not remaining or remaining <= 0 or getRoundPhase() == "lobby" then
                if next(revealedTimerObjects) ~= nil or fallbackLabel then
                    hideRevealedObjects()
                end
                return
            end
            paintRoundClock(remaining :: number)
        end)
    end

    createUniversalFeature(
        "Always Show Timer",
        "Show the round countdown from the game's own RoundTimerPart, murderer or not",
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
