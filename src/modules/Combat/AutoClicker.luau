--!strict
--
-- Auto Clicker.
--
-- Presses things for you, at a rate that does not look like a machine pressed
-- them. What it presses is the interesting part, because "click" means three
-- different things depending on the game and the device:
--
--   Mouse        the executor's own `mouse1click`. Desktop, and only desktop.
--   Tool         `Tool:Activate()` on whatever is equipped. Works on a phone,
--                works while the menu is open, and is what most weapons
--                actually listen to.
--   Screen button  plenty of games build their own on-screen button for
--                attacking on touch, and that button is a GuiButton in your own
--                PlayerGui. Pressing it means firing its signals, which is what
--                the game's own tap does. Tap "Learn button", then tap the
--                game's button once, and the clicker owns it from then on.
--
-- The rate is a range, not a number: a clean 13.00 CPS forever is the easiest
-- pattern in the world to spot, so every interval is drawn between the two
-- ends of the range.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AutoClicker",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- Firing a GuiButton the way a real tap does: every listener on the signals a
-- tap raises, in the order the engine raises them.
local function pressGuiButton(button: GuiButton): boolean
    local environment: any = getfenv()
    local connectionsOf: any = environment.getconnections
    local fireSignal: any = environment.firesignal
    local pressed: boolean = false

    if type(connectionsOf) == "function" then
        for _, signal: any in
            ipairs({
                button.MouseButton1Click,
                (button :: any).Activated,
                button.MouseButton1Down,
                button.MouseButton1Up,
            })
        do
            local ok: boolean, connections: any = pcall(connectionsOf, signal)
            if not ok or type(connections) ~= "table" then
                continue
            end
            for _, connection: any in ipairs(connections) do
                local fired: boolean = pcall(function(): ()
                    connection:Fire()
                end)
                pressed = pressed or fired
            end
        end
    end

    if not pressed and type(fireSignal) == "function" then
        pressed = pcall(fireSignal, (button :: any).Activated) == true
    end
    return pressed
end

local function isGameButton(instance: Instance, screenGui: Instance?): boolean
    if not instance:IsA("GuiButton") then
        return false
    end
    -- The menu's own buttons are not the game's; clicking those would just be
    -- the clicker fighting the interface.
    if screenGui and instance:IsDescendantOf(screenGui) then
        return false
    end
    return true
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local screenGui: Instance? = host.ScreenGui

    local runtime: any = {
        nextClickAt = 0,
        learning = false,
        target = nil :: GuiButton?,
        clicks = 0,
    }

    local function equippedTool(): Tool?
        local character: Model? = localPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChildOfClass("Tool") :: Tool?
    end

    -- Name-based recovery: a game that rebuilds its HUD hands you a new
    -- instance every round, and the remembered one is gone. The name survives.
    local function findButtonByName(name: string): GuiButton?
        if name == "" then
            return nil
        end
        local playerGui: Instance? = localPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return nil
        end
        local wanted: string = string.lower(name)
        for _, descendant: Instance in ipairs(playerGui:GetDescendants()) do
            if not isGameButton(descendant, screenGui) then
                continue
            end
            if string.find(string.lower(descendant.Name), wanted, 1, true) then
                return descendant :: GuiButton
            end
        end
        return nil
    end

    local function resolveTarget(): GuiButton?
        local current: GuiButton? = runtime.target
        if current and (current :: GuiButton).Parent then
            return current
        end
        runtime.target = nil
        return nil
    end

    local clicker: any
    clicker = framework.Categories.Combat:CreateModule({
        Name = "Auto Clicker",
        Category = "Combat",
        Order = 2,
        Tooltip = "Clicks, activates your tool or presses the game's own "
            .. "on-screen button, at a randomised rate.",
        Function = function(enabled: boolean): ()
            runtime.nextClickAt = 0
            runtime.clicks = 0
            if not enabled then
                return
            end

            clicker:Loop(function(): ()
                local options: any = clicker.Options
                if options["Activation"].Value == "Hold key"
                    and not userInput:IsKeyDown(options["Hold key"].Value) then
                    return
                end

                local now: number = os.clock()
                if now < runtime.nextClickAt then
                    return
                end
                local minimum: number = options["Minimum CPS"].Value
                local maximum: number = math.max(options["Maximum CPS"].Value, minimum)
                local rate: number = minimum + math.random() * (maximum - minimum)
                runtime.nextClickAt = now + 1 / math.max(rate, 0.5)

                local mode: string = options["Press"].Value
                if mode == "Tool" or mode == "Everything" then
                    local tool: Tool? = equippedTool()
                    if tool then
                        pcall(function(): ()
                            (tool :: Tool):Activate()
                        end)
                        runtime.clicks += 1
                    elseif options["Require tool"].Value and mode == "Tool" then
                        return
                    end
                end
                if mode == "Screen button" or mode == "Everything" then
                    local button: GuiButton? = resolveTarget()
                        or findButtonByName(tostring(options["Button name"].Value or ""))
                    if button then
                        runtime.target = button
                        if pressGuiButton(button :: GuiButton) then
                            runtime.clicks += 1
                        end
                    end
                end
                if mode == "Mouse" or mode == "Everything" then
                    local environment: any = getfenv()
                    local click: any = environment.mouse1click
                    if type(click) == "function" then
                        pcall(click)
                        runtime.clicks += 1
                    end
                end
            end)
        end,
    })

    clicker:CreateSection("Rate")
    clicker:CreateSlider({
        Name = "Minimum CPS",
        Min = 1,
        Max = 40,
        Default = 8,
    })
    clicker:CreateSlider({
        Name = "Maximum CPS",
        Min = 1,
        Max = 40,
        Default = 13,
        Tooltip = "Every interval is drawn between the two ends, so no two "
            .. "clicks are the same distance apart.",
    })
    clicker:CreateDropdown({
        Name = "Activation",
        List = {"Always", "Hold key"},
        Index = 1,
    })
    clicker:CreateBind({
        Name = "Hold key",
        Default = Enum.KeyCode.Unknown,
        Tooltip = "On touch, tap this slot to place a button and hold that.",
    })

    clicker:CreateSection("Target")
    clicker:CreateDropdown({
        Name = "Press",
        List = {"Tool", "Screen button", "Mouse", "Everything"},
        Index = 1,
        Tooltip = "Tool works everywhere including phones; Screen button "
            .. "presses the game's own attack button; Mouse needs a desktop "
            .. "executor.",
    })
    clicker:CreateTextBox({
        Name = "Button name",
        Default = "",
        Tooltip = "Part of the name of the game's button. Filled in for you by "
            .. "Learn button.",
    })
    clicker:CreateToggle({
        Name = "Require tool",
        Default = false,
        Tooltip = "Skip the click entirely while your hands are empty.",
    })

    local learnButton: any
    learnButton = clicker:CreateButton({
        Name = "Learn button",
        Tooltip = "Press this, then tap the game's own attack button once.",
        Function = function(): ()
            if runtime.learning then
                runtime.learning = false
                clicker:Notify("cancelled")
                return
            end
            runtime.learning = true
            clicker:Notify("tap the game's button now")
        end,
    })

    -- Learning listens for the next press anywhere in the game's own interface
    -- and takes whichever GuiButton is under it. `InputBegan` reports where the
    -- press landed, so the button is found by hit-testing rather than by asking
    -- the game to cooperate.
    local learnConnection: RBXScriptConnection = userInput.InputBegan:Connect(
        function(input: InputObject): ()
            if not runtime.learning then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            local playerGui: Instance? = localPlayer:FindFirstChild("PlayerGui")
            if not playerGui then
                return
            end
            local located: {Instance} = (playerGui :: any):GetGuiObjectsAtPosition(
                input.Position.X,
                input.Position.Y
            )
            for _, candidate: Instance in ipairs(located) do
                if isGameButton(candidate, screenGui) then
                    runtime.learning = false
                    runtime.target = candidate :: GuiButton
                    clicker.Options["Button name"].Value = candidate.Name
                    pcall(function(): ()
                        clicker.Options["Button name"].Object.Text = candidate.Name
                    end)
                    clicker:Notify("bound to " .. candidate.Name)
                    return
                end
            end
        end
    )

    clicker:CreateNote(
        "Screen button mode is for games that build their own attack button on "
            .. "touch: the clicker presses that button exactly as a finger does."
    )

    activeCleanup = function(): ()
        runtime.learning = false
        runtime.target = nil
        pcall(function(): ()
            learnConnection:Disconnect()
        end)
    end
    Module.Initialized = true
    return clicker
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
