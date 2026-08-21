--!strict
--
-- Auto Clicker.
--
-- It does one thing: while you are holding the attack down, it presses faster
-- than a hand can. It never starts clicking on its own — that is the whole
-- difference between an auto clicker and a bot, and it is why the reference
-- interface gates its Tool mode behind `IsMouseButtonPressed`. Turning the
-- module on arms it; your finger still fires it.
--
-- Two ways to hold:
--
--   Hold click  the real attack button (mouse button on a desktop, a finger
--               anywhere on the screen on touch). This is the SpeedAutoClicker
--               behaviour people expect: hold, and the clicks come out.
--   Hold key    a key of your own, for games where the attack is not a click
--               at all, or when you want the burst on a key you can hold with
--               a spare finger.
--
-- And four things a "click" can mean, because that also differs per game:
-- the tool's own `Activate`, a left or right click through the executor, or
-- the game's own on-screen attack button.
--
-- The rate is an interval, not a number: a clean 13.00 CPS forever is the
-- easiest pattern in the world to spot, so every gap is drawn between the two
-- ends of the CPS range.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    weapons: any?,
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
                button.MouseButton1Down,
                button.MouseButton1Click,
                (button :: any).Activated,
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
    local weapons: any = context.weapons

    local runtime: any = {
        nextClickAt = 0,
        learning = false,
        target = nil :: GuiButton?,
        touches = 0,
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
        Tooltip = "Clicks for you while you hold the attack down.",
        Function = function(enabled: boolean): ()
            runtime.nextClickAt = 0
            runtime.touches = 0
            if not enabled then
                return
            end

            -- Touch has no "is the finger down" query, so the two events that
            -- do exist are counted. Any finger on the screen is a held attack:
            -- on a phone the attack button is wherever the game drew it.
            clicker:Event(userInput.InputBegan, function(input: InputObject): ()
                if input.UserInputType == Enum.UserInputType.Touch then
                    runtime.touches += 1
                end
            end)
            clicker:Event(userInput.InputEnded, function(input: InputObject): ()
                if input.UserInputType == Enum.UserInputType.Touch then
                    runtime.touches = math.max(0, runtime.touches - 1)
                end
            end)

            clicker:Loop(function(): ()
                local options: any = clicker.Options
                local holdingAttack: boolean = false
                if options["Activation"].Value == "Hold key" then
                    local key: Enum.KeyCode = options["Hold key"].Value
                    holdingAttack = key ~= Enum.KeyCode.Unknown
                        and userInput:IsKeyDown(key)
                else
                    holdingAttack = userInput:IsMouseButtonPressed(
                        Enum.UserInputType.MouseButton1
                    ) or runtime.touches > 0
                end
                if not holdingAttack then
                    -- Nothing held, nothing pressed. The module stays armed.
                    runtime.nextClickAt = 0
                    return
                end

                local mode: string = options["Click"].Value
                -- Dragging a slider in the menu is a held mouse button too:
                -- the executor-level click paths would land in the game
                -- behind the window, so they stand down while it is open.
                if host.state.visible
                    and (mode == "Left click" or mode == "Right click") then
                    return
                end

                local now: number = os.clock()
                if now < runtime.nextClickAt then
                    return
                end
                local rate: number = options["CPS"]:GetRandomValue()
                runtime.nextClickAt = now + 1 / math.max(rate, 0.5)

                if mode == "Tool" then
                    local tool: Tool? = equippedTool()
                    if tool then
                        if options["Weapons only"].Value
                            and weapons
                            and not weapons:IsMelee((tool :: Tool).Name) then
                            return
                        end
                        pcall(function(): ()
                            (tool :: Tool):Activate()
                        end)
                        return
                    end
                    -- No Tool in hand does not mean no weapon: games like
                    -- BedFight swing a view model through their own button,
                    -- and the weapon library knows how to reach it.
                    if weapons then
                        local candidate: any = weapons:Best({Melee = true})
                        if candidate then
                            weapons:Activate(candidate)
                        end
                    end
                    return
                end

                if mode == "Screen button" then
                    local button: GuiButton? = resolveTarget()
                        or findButtonByName(tostring(options["Button name"].Value or ""))
                    if button then
                        runtime.target = button
                        pressGuiButton(button :: GuiButton)
                    end
                    return
                end

                local environment: any = getfenv()
                local click: any = mode == "Right click"
                    and environment.mouse2click
                    or environment.mouse1click
                if type(click) == "function" then
                    pcall(click)
                end
            end)
        end,
    })

    clicker:CreateTwoSlider({
        Name = "CPS",
        Min = 1,
        Max = 28,
        DefaultMin = 8,
        DefaultMax = 12,
        Tooltip = "Clicks per second. Every gap is drawn between the two ends, "
            .. "so no two clicks are the same distance apart. A fast hand peaks "
            .. "around 12; past 20 nothing human explains the rate and servers "
            .. "that log click intervals will say so.",
    })

    clicker:CreateDropdown({
        Name = "Activation",
        List = {"Hold click", "Hold key"},
        Index = 1,
        Tooltip = "Hold click follows the real attack button; Hold key runs "
            .. "while your own key is down.",
    })
    clicker:CreateBind({
        Name = "Hold key",
        Show = {Option = "Activation", Values = {"Hold key"}},
        Default = Enum.KeyCode.Unknown,
        Tooltip = "Click the slot, then press the key. On touch, tap it to "
            .. "place a button and hold that instead.",
    })

    clicker:CreateDropdown({
        Name = "Click",
        List = {"Tool", "Left click", "Right click", "Screen button"},
        Index = 1,
        Tooltip = "What one click means: activate the equipped tool, a real "
            .. "left or right click through the executor, or the game's own "
            .. "on-screen attack button.",
    })
    clicker:CreateToggle({
        Name = "Weapons only",
        Show = {Option = "Click", Values = {"Tool"}},
        Default = false,
        Tooltip = "Only click while what you are holding is a melee weapon, "
            .. "so a pickaxe or a stack of blocks is never swung.",
    })
    clicker:CreateTextBox({
        Name = "Button name",
        Show = {Option = "Click", Values = {"Screen button"}},
        Default = "",
        Tooltip = "Part of the name of the game's attack button. Filled in "
            .. "for you by Learn button.",
    })
    clicker:CreateButton({
        Name = "Learn button",
        Show = {Option = "Click", Values = {"Screen button"}},
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

    activeCleanup = function(): ()
        runtime.learning = false
        runtime.target = nil
        runtime.touches = 0
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
