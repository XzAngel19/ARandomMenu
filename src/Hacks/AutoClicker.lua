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

local function isGameButton(
    instance: Instance,
    isMenuOwned: (Instance) -> boolean
): boolean
    if not instance:IsA("GuiButton") then
        return false
    end

    if isMenuOwned(instance) then
        return false
    end
    return true
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local userInput: UserInputService = host.UserInputService
    local isMenuOwned: (Instance) -> boolean = host.isMenuOwned
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
            if not isGameButton(descendant, isMenuOwned) then
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
                clicker:SetStatus(nil)
                return
            end
            local cps: any = clicker.Options["CPS"].Value
            clicker:SetStatus(
                tostring(math.round(cps.Min))
                    .. "-"
                    .. tostring(math.round(cps.Max))
                    .. " CPS"
            )

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

                    runtime.nextClickAt = 0
                    return
                end

                local mode: string = options["Click"].Value

                if context.services.menu.isVisible()
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
                        pcall(function(): ()
                            (tool :: Tool):Activate()
                        end)
                        return
                    end

                    if weapons then
                        local candidate: any = weapons:Best({All = true})
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
        Function = function(value: any): ()
            if clicker.Enabled then
                clicker:SetStatus(
                    tostring(math.round(value.Min))
                        .. "-"
                        .. tostring(math.round(value.Max))
                        .. " CPS"
                )
            end
        end,
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
                if isGameButton(candidate, isMenuOwned) then
                    runtime.learning = false
                    runtime.target = candidate :: GuiButton
                    clicker.Options["Button name"]:Set(candidate.Name)
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
