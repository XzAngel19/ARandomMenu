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

    -- The core keeps roundTimer.endsAt locked to whatever live source the
    -- current map still publishes (see the "Round clock" section of base.lua):
    -- the workspace.RoundTimerPart attribute on older maps, the game's own HUD
    -- countdown label on the current map, and the one-shot RoundStart anchor as
    -- a last resort. The number painted here is the game's own number - this
    -- module only decides where to paint it.
    local revealedTimerObjects: {[Instance]: boolean} =
        setmetatable({}, {__mode = "k"}) :: any
    local fallbackGui: ScreenGui? = nil
    local fallbackLabel: TextLabel? = nil
    local gameCaption: TextLabel? = nil
    local lastPaintedText: string = ""

    -- The recursive FindFirstChildWhichIsA below is the only expensive part of
    -- this lookup, so the answer is cached and rescanned at most once a second
    -- (or immediately once the cached frame/label is destroyed).
    local timerFrameCache: {frame: Instance?, label: Instance?, at: number} =
        {frame = nil, label = nil, at = -math.huge}

    local function findGameTimerFrame(): (GuiObject?, TextLabel?)
        local cachedFrame: Instance? = timerFrameCache.frame
        if cachedFrame and cachedFrame.Parent
            and (not timerFrameCache.label or timerFrameCache.label.Parent) then
            return cachedFrame, timerFrameCache.label
        end
        if os.clock() - timerFrameCache.at < 1 then
            return nil, nil
        end
        timerFrameCache.at = os.clock()
        local playerGui: PlayerGui? = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local mainGui: Instance? = playerGui and playerGui:FindFirstChild("MainGUI")
        local gameFrame: Instance? = mainGui and mainGui:FindFirstChild("Game")
        local frame: Instance? = gameFrame and gameFrame:FindFirstChild("Timer")
        local validFrame: Instance? = (frame and frame:IsA("GuiObject")) and frame or nil
        timerFrameCache.frame = validFrame
        timerFrameCache.label = nil
        if not validFrame then
            return nil, nil
        end
        -- MM2 has renamed this label across updates, so take the first TextLabel
        -- in the frame instead of trusting a single name.
        local label: Instance? = validFrame:FindFirstChild("XPText")
            or validFrame:FindFirstChild("Timer")
            or validFrame:FindFirstChildWhichIsA("TextLabel", true)
        local validLabel: Instance? = (label and label:IsA("TextLabel")) and label or nil
        timerFrameCache.label = validLabel
        return validFrame, validLabel
    end

    local function destroyGameCaption(): ()
        if gameCaption then
            pcall(function(): ()
                (gameCaption :: any):Destroy()
            end)
            gameCaption = nil
        end
    end

    -- The white "Timer" caption that sits above the borrowed game label.
    local function ensureGameCaption(frame: GuiObject): ()
        if gameCaption and gameCaption.Parent then
            if gameCaption.Parent ~= frame then
                destroyGameCaption()
            else
                return
            end
        end
        gameCaption = create("TextLabel", {
            Parent = frame,
            Name = "WurstTimerCaption",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 0),
            Size = UDim2.fromOffset(80, 16),
            Font = CONTROL_FONT,
            Text = "Timer",
            TextSize = 12,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
            TextStrokeTransparency = 0.4,
        }) :: any
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
        create("TextLabel", {
            Parent = gui,
            Name = "Caption",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 6),
            Size = UDim2.new(0, 96, 0, 14),
            Font = CONTROL_FONT,
            Text = "Timer",
            TextSize = 11,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
            TextStrokeTransparency = 0.4,
        })
        local label: TextLabel = create("TextLabel", {
            Parent = gui,
            Name = "Clock",
            BackgroundTransparency = 0.35,
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 20),
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
        destroyGameCaption()
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
                ensureGameCaption(frame)
                paintClock(label, remaining)
                return
            end
        end
        destroyGameCaption()
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
        "Show the round countdown from the game's own timer (HUD label or "
            .. "RoundTimerPart), murderer or not",
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
