-- MM2 Auto Unbox: opens the game's own 1000-coin mystery boxes by pressing
-- the same button a player presses.
--
-- Why the UI and not a remote: the box purchase is a client-side flow that
-- the game exposes only through its Unboxing window. Firing a remote nobody
-- has seen would be a guess; pressing the real button runs the real code, and
-- the inventory change that follows proves it worked.
local Module = {
    Name = "MM2 Auto Unbox",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

-- The labels the Unboxing window uses. Localisation strings in the place
-- dump: "OPEN BOX", "Opening Box...", "Open - {number1}", "Unboxing".
local OPEN_LABELS: {string} = {
    "OPEN BOX",
    "OPENBOX",
    "UNBOX",
    "HATCH",
}
-- The game's own unboxing windows, straight from the place dump. A generic
-- "OPEN" button is only trusted inside one of these.
local WINDOW_NAMES: {string} = {
    "Unboxing",
    "Unboxing2",
    "Hatching",
    "MysteryBoxOpen",
    "MysteryBox",
}
-- Never press a button that spends Robux: those are the purchase prompts.
local FORBIDDEN_LABELS: {string} = {
    "PURCHASE",
    "BUY",
    "ROBUX",
}

local function uppercase(text: any): string
    return string.upper(tostring(text or ""))
end

local function isOpenLabel(text: string): boolean
    for _, label: string in ipairs(FORBIDDEN_LABELS) do
        if string.find(text, label, 1, true) then
            return false
        end
    end
    if text == "OPEN" or string.sub(text, 1, 7) == "OPEN - " then
        return true
    end
    for _, label: string in ipairs(OPEN_LABELS) do
        if string.find(text, label, 1, true) then
            return true
        end
    end
    return false
end

-- Visible and interactive all the way up to the ScreenGui.
local function isPressable(button: GuiButton): boolean
    if button.Visible ~= true then
        return false
    end
    local active: any = (button :: any).Active
    if active == false then
        return false
    end
    local interactable: any = (button :: any).Interactable
    if interactable == false then
        return false
    end
    local parent: Instance? = button.Parent
    while parent do
        local visible: any = (parent :: any).Visible
        if visible == false then
            return false
        end
        if parent:IsA("ScreenGui") or parent:IsA("PlayerGui") then
            break
        end
        parent = parent.Parent
    end
    return true
end

local function isWindow(object: Instance): boolean
    local name: string = object.Name
    for _, windowName: string in ipairs(WINDOW_NAMES) do
        if name == windowName then
            return true
        end
    end
    return false
end

-- Only "OPEN BOX" and friends are specific enough to trust anywhere; a bare
-- "OPEN" could belong to any menu on screen.
local function isSpecificOpenLabel(text: string): boolean
    for _, label: string in ipairs(OPEN_LABELS) do
        if string.find(text, label, 1, true) then
            return true
        end
    end
    return string.sub(text, 1, 7) == "OPEN - "
end

local function findButtonIn(root: Instance?, specificOnly: boolean): GuiButton?
    if not root then
        return nil
    end
    local ok: boolean, descendants: any = pcall(function(): any
        return root:GetDescendants()
    end)
    if not ok or type(descendants) ~= "table" then
        return nil
    end
    for _, object: Instance in ipairs(descendants) do
        if object:IsA("GuiButton") then
            local button: GuiButton = object :: GuiButton
            local text: string = uppercase(button.Text)
            local name: string = uppercase(button.Name)
            local usable: boolean
            if specificOnly then
                usable = isSpecificOpenLabel(text) or isSpecificOpenLabel(name)
            else
                usable = isOpenLabel(text) or isOpenLabel(name)
            end
            if usable and isPressable(button) then
                return button
            end
        end
    end
    return nil
end

local function findWindows(playerGui: Instance?): {Instance}
    local windows: {Instance} = {}
    if not playerGui then
        return windows
    end
    local ok: boolean, descendants: any = pcall(function(): any
        return playerGui:GetDescendants()
    end)
    if not ok or type(descendants) ~= "table" then
        return windows
    end
    for _, object: Instance in ipairs(descendants) do
        if isWindow(object) then
            table.insert(windows, object)
        end
    end
    return windows
end

-- Returns the button and, when it was found, the window it belongs to. Every
-- window is tried: the game keeps some of them in the PlayerGui while hidden.
local function findOpenButton(playerGui: Instance?): (GuiButton?, Instance?)
    local windows: {Instance} = findWindows(playerGui)
    for _, window: Instance in ipairs(windows) do
        local inWindow: GuiButton? = findButtonIn(window, false)
        if inWindow then
            return inWindow, window
        end
    end
    -- Last resort: the exact label is unambiguous, wherever it lives.
    local exact: GuiButton? = findButtonIn(playerGui, true)
    return exact, windows[1]
end

-- Executors expose `firesignal`; without it a GuiButton cannot be pressed from
-- a script, and pretending otherwise is worse than saying so.
local function signalFirer(): any
    local ok: boolean, firer: any = pcall(function(): any
        return (getfenv and getfenv()) or nil
    end)
    if ok and type(firer) == "table" and type(firer.firesignal) == "function" then
        return firer.firesignal
    end
    local okDirect: boolean, direct: any = pcall(function(): any
        return (firesignal :: any)
    end)
    if okDirect and type(direct) == "function" then
        return direct
    end
    return nil
end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Auto Unbox requires the MM2 core module")
    Module.Runtime = runtime

    local settings = {
        delay = 1.5,
        maxBoxes = 10,
    }
    local session = {
        opened = 0,
        failures = 0,
        pendingButton = nil :: GuiButton?,
        pendingSince = 0,
        nextAt = 0,
        finished = false,
        window = nil :: Instance?,
    }

    local function inventorySignals(): {any}
        local signals: {any} = {}
        local ok: boolean, remotes: any = pcall(function(): any
            local replicated: Instance = game:GetService("ReplicatedStorage")
            return replicated:FindFirstChild("Remotes")
        end)
        if not ok or not remotes then
            return signals
        end
        for _, name: string in ipairs({"ItemReceived", "CrateComplete", "ChangeInventoryItem"}) do
            local okFind: boolean, remote: any = pcall(function(): any
                return remotes:FindFirstChild(name, true)
            end)
            if okFind and remote and remote:IsA("RemoteEvent") then
                table.insert(signals, remote)
            end
        end
        return signals
    end

    local confirmedByRemote: boolean = false
    local confirmationConnections: {any} = {}
    local function connectConfirmations(): ()
        table.clear(confirmationConnections)
        confirmedByRemote = false
        for _, remote: any in ipairs(inventorySignals()) do
            local ok: boolean, connection: any = pcall(function(): any
                return remote.OnClientEvent:Connect(function(): ()
                    confirmedByRemote = true
                end)
            end)
            if ok and connection then
                table.insert(confirmationConnections, connection)
            end
        end
    end

    local function disconnectConfirmations(): ()
        for _, connection: any in ipairs(confirmationConnections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        table.clear(confirmationConnections)
    end

    local function report(text: string): ()
        local card: any = state.mm2AutoUnboxFeature
        if card then
            card:SetStatus(text)
        end
    end

    local function summary(): string
        if session.opened == 0 and session.failures == 0 then
            if session.window then
                return "window: " .. session.window.Name
            end
            return "waiting for a box window"
        end
        local text: string = tostring(session.opened) .. " opened"
        if session.failures > 0 then
            text ..= " · " .. tostring(session.failures) .. " failed"
        end
        if session.finished then
            text ..= " · done"
        end
        return text
    end

    -- A universal card has no :Toggle (that belongs to framework modules); it
    -- switches off through its own onToggle plus the shared repaint.
    local function turnCardOff(): ()
        local card: any = state.mm2AutoUnboxFeature
        if not card then
            return
        end
        card.enabled = false
        pcall(function(): ()
            card.onToggle(false)
        end)
        if type(refreshFeatureToggle) == "function" then
            pcall(refreshFeatureToggle, card)
        end
    end

    local function stop(reason: string?): ()
        disconnectFeatureConnection("MM2AutoUnbox")
        disconnectConfirmations()
        session.pendingButton = nil
        if reason then
            notify(reason)
        end
        turnCardOff()
    end

    local function press(button: GuiButton, firer: any): boolean
        local ok: boolean = pcall(function(): ()
            firer(button.MouseButton1Click)
        end)
        if ok then
            return true
        end
        -- Some executors expose `activated` only; try the other signal too.
        return pcall(function(): ()
            (button.Activated :: any):Fire()
        end)
    end

    local function activationConfirmed(button: GuiButton): boolean
        if confirmedByRemote then
            return true
        end
        local text: string = uppercase(button.Text)
        if string.find(text, "OPENING", 1, true) then
            return true
        end
        local parent: Instance? = button.Parent
        while parent and not parent:IsA("ScreenGui") and not parent:IsA("PlayerGui") do
            if (parent :: any).Visible == false then
                return true
            end
            parent = parent.Parent
        end
        return (button :: any).Visible == false
    end

    local function beginRun(): ()
        session.opened = 0
        session.failures = 0
        session.pendingButton = nil
        session.pendingSince = 0
        session.nextAt = 0
        session.finished = false
        session.window = nil
        confirmedByRemote = false
        connectConfirmations()
    end

    local function tick(deltaTime: number): ()
        if session.finished then
            return
        end
        if session.opened >= math.round(settings.maxBoxes) then
            session.finished = true
            report(summary())
            stop(nil)
            return
        end
        local now: number = os.clock()
        local pending: GuiButton? = session.pendingButton
        if pending then
            if activationConfirmed(pending) then
                session.opened += 1
                session.failures = 0
                confirmedByRemote = false
                session.pendingButton = nil
                session.nextAt = now + settings.delay
                report(summary())
                return
            end
            if now - session.pendingSince > 8 then
                session.failures += 1
                session.pendingButton = nil
                confirmedByRemote = false
                report(summary())
                if session.failures >= 3 then
                    session.finished = true
                    stop("Auto Unbox stopped: the box button did not respond.")
                end
            end
            return
        end
        if now < session.nextAt then
            return
        end
        local playerGui: Instance? = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        local button: GuiButton?, window: Instance? = findOpenButton(playerGui)
        session.window = window
        if not button then
            report(summary())
            session.nextAt = now + 1
            return
        end
        local firer: any = signalFirer()
        if not firer then
            session.finished = true
            stop("Auto Unbox: this executor does not expose firesignal, so the box button cannot be pressed.")
            return
        end
        if not press(button, firer) then
            session.finished = true
            stop("Auto Unbox: the box button could not be pressed.")
            return
        end
        session.pendingButton = button
        session.pendingSince = now
        report(summary())
    end

    local AutoUnboxFeature: any = createUniversalFeature(
        "Auto Unbox",
        "Opens the game's 1000-coin or candy mystery boxes by pressing their OPEN BOX button, one at a time.",
        4,
        function(enabled: boolean): ()
            disconnectFeatureConnection("MM2AutoUnbox")
            if not enabled then
                disconnectConfirmations()
                session.pendingButton = nil
                return
            end
            beginRun()
            report(summary())
            featureConnections.MM2AutoUnbox = TaskManager:Connect(tick)
        end,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoUnboxFeature = AutoUnboxFeature
    addNumberOption(
        AutoUnboxFeature,
        "Delay between boxes",
        settings.delay,
        0.8,
        5,
        function(value: number): ()
            settings.delay = value
        end
    )
    addNumberOption(
        AutoUnboxFeature,
        "Max boxes per run",
        settings.maxBoxes,
        1,
        50,
        function(value: number): ()
            settings.maxBoxes = value
        end
    )
    addActionOption(
        AutoUnboxFeature,
        "Find box button",
        function(): ()
            local playerGui: Instance? = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
            local button: GuiButton?, window: Instance? = findOpenButton(playerGui)
            if button then
                notify(
                    "Open box button found: "
                        .. tostring(button.Text)
                        .. " ("
                        .. button:GetFullName()
                        .. ")"
                        .. (window and (" inside " .. window:GetFullName()) or "")
                )
            elseif window then
                notify("The " .. window.Name .. " window is open, but it has no usable open button.")
            else
                notify("No unboxing window on screen. Open the mystery box window first.")
            end
        end
    )
    addInformationOption(
        AutoUnboxFeature,
        "Presses the OPEN BOX button inside the game's own Unboxing/Hatching window, never a purchase prompt, and counts a box only when the inventory changes."
    )

    activeCleanup = function(): ()
        state.mm2AutoUnboxFeature = nil
        disconnectFeatureConnection("MM2AutoUnbox")
        disconnectConfirmations()
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
    activeCleanup = function(): ()
    end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
