--!strict
--
-- Headless tests: widgets.
--
-- Loaded by tools/test/run.luau. Suites share one world through the context
-- so the checks stay under Luau's 200-local ceiling without wrapping
-- sections in do-end.
--
return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local esp: any = ctx.esp
    local weapons: any = ctx.weapons

    section("Widgets")

    -- Everything below drives the real src/library/Widgets.luau, not the host
    -- stand-in's recording builders. It is the only place the interface code that
    -- actually ships gets executed, so the checks are about behaviour a player can
    -- see: the control appears, it starts on its stored value, operating it calls
    -- the module back and writes the value where the next session will find it.
    local WidgetFile: any = require("../../../src/library/Widgets")
    Mock.inject(world, WidgetFile.init)
    local widgets: any = WidgetFile.init(host)

    for _, name: string in ipairs({
        "addToggleOption",
        "addActionOption",
        "addNumberOption",
        "addRangeOption",
        "addCycleOption",
        "addKeyOption",
        "addTextOption",
        "addColorOption",
        "addListOption",
        "addSectionOption",
        "addInformationOption",
        "setOptionVisible",
    }) do
        check("library exports " .. name, type(widgets[name]) == "function")
    end

    -- A stand-in for the card a module builds its panel into: the same six fields
    -- `createUniversalFeature` puts on one.
    local function newPanel(configKey: string): any
        local panel: any = {
            configKey = configKey,
            optionCount = 0,
            searchText = "",
            optionRows = {},
            options = Mock.newInstance("ScrollingFrame"),
            resizes = 0,
        }
        panel.options.ZIndex = 2
        panel.updateExpandedSize = function(): ()
            panel.resizes += 1
        end
        return panel
    end

    local configValues: any = host.configData.values
    local configStates: any = host.configData.states

    -- Toggle -----------------------------------------------------------------------

    local togglePanel: any = newPanel("Universal.Sample")
    local toggleSeen: {boolean} = {}
    widgets.addToggleOption(togglePanel, "Team check", true, function(value: boolean): ()
        table.insert(toggleSeen, value)
    end)

    local toggleRow: any = togglePanel.options:FindFirstChild("Option_Teamcheck")
    check("a toggle builds one row", toggleRow ~= nil)
    check("the row carries the label",
        toggleRow ~= nil
            and toggleRow:FindFirstChild("OptionLabel") ~= nil
            and toggleRow:FindFirstChild("OptionLabel").Text == "Team check")
    check("the module is called with the default", toggleSeen[1] == true)
    check("the panel is resized once per row", togglePanel.resizes == 1)

    local savesBefore: number = host.saves
    toggleRow:FindFirstChild("OptionClickTarget").MouseButton1Click:Fire()
    check("clicking the row flips the toggle", toggleSeen[#toggleSeen] == false)
    check("the new value is stored", configStates["Universal.Sample.Teamcheck"] == false)
    check("the config save is queued", host.saves > savesBefore)

    -- Wurst's checkbox: the square in front of the label paints with the
    -- enabled colour, and clicking the row again flips it back.
    local checkbox: any = toggleRow:FindFirstChild("OptionCheckbox")
    check("the row carries the square checkbox", checkbox ~= nil)
    toggleRow:FindFirstChild("OptionClickTarget").MouseButton1Click:Fire()
    check("clicking the row again flips it back", toggleSeen[#toggleSeen] == true)
    check("the checkbox fills when on",
        checkbox ~= nil and checkbox.BackgroundTransparency == 0)

    -- A stored value beats the default, or nothing a player changes survives a
    -- rejoin.
    configStates["Universal.Sample.Chams"] = false
    local storedToggleValue: boolean = true
    widgets.addToggleOption(togglePanel, "Chams", true, function(value: boolean): ()
        storedToggleValue = value
    end)
    check("a stored value beats the default", storedToggleValue == false)

    -- Slider -----------------------------------------------------------------------

    local sliderPanel: any = newPanel("Universal.Slider")
    local sliderSeen: number = -1
    local sliderRow: any = widgets.addNumberOption(
        sliderPanel,
        "Max distance",
        250,
        50,
        1000,
        function(value: number): ()
            sliderSeen = value
        end
    )
    check("a slider calls back with its default", sliderSeen == 250)
    local numericBox: any = sliderRow:FindFirstChild("Slider"):FindFirstChild("NumericValue")
    check("the slider has a numeric field", numericBox ~= nil)
    check("the field spells out the interval",
        numericBox ~= nil and numericBox.PlaceholderText == "50 – 1000",
        numericBox and tostring(numericBox.PlaceholderText) or "none")

    numericBox.Text = "600"
    numericBox.FocusLost:Fire(true)
    check("typing a number moves the slider", sliderSeen == 600)
    check("the typed value is stored", configValues["Universal.Slider.Maxdistance"] == 600)

    -- A field that cannot be parsed puts the old value back rather than passing
    -- nil to the module.
    numericBox.Text = "not a number"
    numericBox.FocusLost:Fire(true)
    check("garbage in the field is refused", sliderSeen == 600)
    check("the field shows the value again", numericBox.Text == "600")

    -- Dragging is what the row is for, and it is the path that clamps.
    local track: any = sliderRow:FindFirstChild("Slider"):FindFirstChild("Track")
    track.AbsolutePosition = world.globals.Vector2.new(100, 0)
    track.AbsoluteSize = world.globals.Vector2.new(200, 5)
    sliderRow:FindFirstChild("Slider").InputBegan:Fire({
        UserInputType = world.globals.Enum.UserInputType.MouseButton1,
        Position = world.globals.Vector2.new(200, 0),
    })
    check("dragging to the middle lands mid-interval", sliderSeen == 525,
        "value: " .. tostring(sliderSeen))
    world.services.UserInputService.InputChanged:Fire({
        UserInputType = world.globals.Enum.UserInputType.MouseMovement,
        Position = world.globals.Vector2.new(9000, 0),
    })
    check("dragging past the end clamps to the maximum", sliderSeen == 1000)
    world.services.UserInputService.InputEnded:Fire({
        UserInputType = world.globals.Enum.UserInputType.MouseButton1,
    })
    world.services.UserInputService.InputChanged:Fire({
        UserInputType = world.globals.Enum.UserInputType.MouseMovement,
        Position = world.globals.Vector2.new(100, 0),
    })
    check("releasing ends the drag", sliderSeen == 1000)

    local function loadedNumber(stored: any): number
        configValues["Universal.Clamp.Value"] = stored
        local panel: any = newPanel("Universal.Clamp")
        local seen: number = -1
        widgets.addNumberOption(panel, "Value", 25, 10, 50, function(value: number): ()
            seen = value
        end)
        return seen
    end
    check("stored number above the rail is preserved", loadedNumber(999) == 999)
    check("stored number below the rail is preserved", loadedNumber(-999) == -999)
    check("stored NaN falls back to default", loadedNumber(0 / 0) == 25)
    check("stored infinity falls back to default", loadedNumber(math.huge) == 25)

    -- Cycle, key slot and text field --------------------------------------------------

    local cyclePanel: any = newPanel("Universal.Cycle")
    local cycleSeen: string = ""
    configValues["Universal.Cycle.Mode"] = "Velocity"
    widgets.addCycleOption(
        cyclePanel,
        "Mode",
        {"WalkSpeed", "Velocity", "CFrame"},
        1,
        function(value: string): ()
            cycleSeen = value
        end
    )
    check("a cycle starts on its stored value", cycleSeen == "Velocity")
    configValues["Universal.InvalidCycle.Mode"] = "RemovedMode"
    local invalidCycle: string = ""
    widgets.addCycleOption(
        newPanel("Universal.InvalidCycle"),
        "Mode",
        {"WalkSpeed", "Velocity", "CFrame"},
        1,
        function(value: string): () invalidCycle = value end
    )
    check("invalid stored dropdown falls back to a valid default",
        invalidCycle == "WalkSpeed")
    configValues["Universal.Removed.OldOption"] = "legacy"
    local replacementSeen: boolean = false
    widgets.addToggleOption(
        newPanel("Universal.Removed"),
        "Current option",
        false,
        function(value: boolean): () replacementSeen = value end
    )
    check("removed option data is ignored safely", replacementSeen == false)

    local keySeen: any = nil
    local keyButton: any = widgets.addKeyOption(
        cyclePanel,
        "Hotkey",
        world.globals.Enum.KeyCode.Unknown,
        function(keyCode: any): ()
            keySeen = keyCode
        end
    )
    check("a key row marks the card as having one", cyclePanel.hasKeyOption == true)
    check("an unbound slot shows nothing", keyButton.Text == "")
    -- Click the slot, then press a key. Hovering used to be enough, which bound a
    -- key every time the pointer crossed the row.
    keyButton.MouseButton1Click:Fire()
    check("clicking arms the capture", world.keyCapture ~= nil
        and world.keyCapture.button == keyButton)
    world.keyCapture.callback(world.globals.Enum.KeyCode.E)
    check("the pressed key is taken", keySeen == world.globals.Enum.KeyCode.E)
    check("the slot shows it", keyButton.Text == "E")
    check("the binding is stored", configValues["Universal.Cycle.Hotkey"] == "E")
    -- Pressing the same key again clears the slot, which is the only way to unbind.
    keyButton.MouseButton1Click:Fire()
    world.keyCapture.callback(world.globals.Enum.KeyCode.E)
    check("pressing it again clears the slot", keyButton.Text == "")

    local textSeen: string = ""
    local textBox: any = widgets.addTextOption(
        cyclePanel,
        "Target",
        "nobody",
        function(value: string): ()
            textSeen = value
        end
    )
    check("a text row calls back with its default", textSeen == "nobody")
    textBox.Text = "Player1"
    check("typing calls the module back", textSeen == "Player1")
    check("the text is stored", configValues["Universal.Cycle.Target"] == "Player1")

    -- Colour ---------------------------------------------------------------------------

    local colourPanel: any = newPanel("Universal.Colour")
    local colourSeen: any = nil
    local swatch: any = widgets.addColorOption(
        colourPanel,
        "Colour",
        world.globals.Color3.fromRGB(255, 0, 0),
        function(value: any): ()
            colourSeen = value
        end
    )
    check("a colour row calls back with its default",
        colourSeen ~= nil and math.round(colourSeen.R * 255) == 255)
    swatch.MouseButton1Click:Fire()
    check("the swatch opens the picker",
        host.state.colorPicker ~= nil and host.state.colorPicker.panel ~= nil)
    host.state.colorPicker.callback(world.globals.Color3.fromRGB(0, 128, 255))
    check("applying a colour reaches the module",
        colourSeen ~= nil and math.round(colourSeen.B * 255) == 255)
    local storedColour: any = configValues["Universal.Colour.Colour"]
    check("the colour is stored as three channels",
        type(storedColour) == "table" and storedColour[2] == 128,
        type(storedColour) == "table" and tostring(storedColour[2]) or "none")

    -- Row geometry ----------------------------------------------------------------------

    -- Wurst's line: every label starts on the same left edge, and a slider's
    -- bar is the prototype's 5 px spanning the row. The old assertion pinned
    -- the right-hand control band that died with the card-style rows.
    local geometryPanel: any = newPanel("Universal.Geometry")
    widgets.addToggleOption(geometryPanel, "One", false, function(): () end)
    widgets.addNumberOption(geometryPanel, "Two", 1, 0, 10, function(): () end)
    widgets.addCycleOption(geometryPanel, "Three", {"A", "B"}, 1, function(): () end)
    widgets.addKeyOption(
        geometryPanel,
        "Four",
        world.globals.Enum.KeyCode.Unknown,
        function(): () end
    )
    local flatRows: boolean = #geometryPanel.optionRows == 4
    for _, row: any in ipairs(geometryPanel.optionRows) do
        if row.BackgroundTransparency ~= 1 then
            flatRows = false
        end
    end
    check("every row is a flat line, not a card", flatRows)
    local geometryTrack: any =
        geometryPanel.optionRows[2]:FindFirstChild("Slider"):FindFirstChild("Track")
    check("the slider rail is the Java's 3 logical (6 px)",
        geometryTrack ~= nil and geometryTrack.Size.Y.Offset == 6,
        geometryTrack and tostring(geometryTrack.Size.Y.Offset) or "none")
    local geometryKnob: any = geometryTrack and geometryTrack:FindFirstChild("Knob")
    check("the knob is the Java's 8×8 (16×16 px)",
        geometryKnob ~= nil
            and geometryKnob.Size.X.Offset == 16
            and geometryKnob.Size.Y.Offset == 16)

    -- Action, range and list ------------------------------------------------------------

    local actionPanel: any = newPanel("Universal.Action")
    local runs: number = 0
    local runButton: any = widgets.addActionOption(actionPanel, "Rejoin", function(): ()
        runs += 1
    end)
    check("an action row draws a RUN button", runButton.Text == "RUN")
    runButton.MouseButton1Click:Fire()
    check("pressing RUN runs it once", runs == 1)
    -- The pair in the same band: RUN plus a slot the action can be bound to.
    check("the action can be bound to a key",
        world.shortcuts ~= nil and world.shortcuts["Universal.ActionRejoin"] ~= nil)
    world.shortcuts["Universal.ActionRejoin"].run()
    check("the shortcut runs the same action", runs == 2)

    local rangePanel: any = newPanel("Universal.Range")
    local rangeLow: number, rangeHigh: number = 0, 0
    host.state.addRangeOption(rangePanel, "Clicks per second", {
        min = 1,
        max = 20,
        defaultLow = 8,
        defaultHigh = 14,
        onChanged = function(low: number, high: number): ()
            rangeLow, rangeHigh = low, high
        end,
    })
    check("a range row reports both ends", rangeLow == 8 and rangeHigh == 14,
        tostring(rangeLow) .. "-" .. tostring(rangeHigh))

    -- A stored pair the wrong way round is put back in order rather than handed to
    -- the module as an interval that cannot contain anything.
    configValues["Universal.Range2.Delay.Low"] = 15
    configValues["Universal.Range2.Delay.High"] = 4
    local swappedLow: number, swappedHigh: number = 0, 0
    host.state.addRangeOption(newPanel("Universal.Range2"), "Delay", {
        min = 1,
        max = 20,
        defaultLow = 2,
        defaultHigh = 6,
        onChanged = function(low: number, high: number): ()
            swappedLow, swappedHigh = low, high
        end,
    })
    check("a reversed stored range is put back in order",
        swappedLow == 4 and swappedHigh == 15,
        tostring(swappedLow) .. "-" .. tostring(swappedHigh))

    local listPanel: any = newPanel("Universal.List")
    local listNames: {string} = {}
    local listButton: any = host.state.addListOption(listPanel, "Weapon", {
        items = {"Sword", "Bat", "Knife"},
        default = {"Sword"},
        onChanged = function(_selected: any, names: {string}): ()
            listNames = names
        end,
    })
    check("a one-item selection names the item", listButton.Text == "Sword",
        tostring(listButton.Text))
    local listControl: any = host.state.listControls["Universal.List.Weapon"]
    check("the row publishes a control for the module", listControl ~= nil)
    listControl.set("Bat", true)
    check("adding an entry updates the summary", listButton.Text == "2 of 3",
        tostring(listButton.Text))
    check("the module is told what is selected",
        table.concat(listNames, ",") == "Bat,Sword", table.concat(listNames, ","))
    check("the selection is stored",
        configValues["Universal.List.Weapon"] == "Bat,Sword",
        tostring(configValues["Universal.List.Weapon"]))

    -- Sections, notes and folding ----------------------------------------------------

    local sectionRow: any = host.state.addSectionOption(geometryPanel, "Advanced")
    check("a section is a row like any other", sectionRow ~= nil
        and table.find(geometryPanel.optionRows, sectionRow) ~= nil)
    widgets.addInformationOption(geometryPanel, "Explains itself")
    check("a note goes on the card rather than into a row",
        geometryPanel.tooltipText == "Explains itself")

    -- Performance budget -------------------------------------------------------------

    section("Performance budget")

    -- A module that starts doing more work per frame than last week has to fail
    -- here, not in a 60fps game. The numbers are the observed cost of the current
    -- modules against this mock: raise them only with a comment saying why.
    local BUDGET_TASKS_WITH_ESP: number = 12
    local BUDGET_DESCENDANT_WALKS: number = 8

    esp:Toggle()
    local tasksWithEsp: number = stub.taskCount()
    esp:Toggle()
    check(
        "ESP keeps the per-frame callback count inside budget",
        tasksWithEsp <= BUDGET_TASKS_WITH_ESP,
        "tasks: " .. tostring(tasksWithEsp)
    )

    local walks: number = 0
    local countedGui: any = world.localPlayer:FindFirstChild("PlayerGui")
    local previousGetDescendants: any = countedGui and countedGui.GetDescendants
    if countedGui then
        countedGui.GetDescendants = function(self: any): {any}
            walks += 1
            return previousGetDescendants(self)
        end
    end
    weapons:Invalidate()
    weapons:Scan({All = true})
    stub.step(0.016)
    if countedGui then
        countedGui.GetDescendants = previousGetDescendants
    end
check(
    "a frame does not walk PlayerGui more than the budget",
    walks <= BUDGET_DESCENDANT_WALKS,
    "walks: " .. tostring(walks)
)

-- Wall-clock, not the mocked os.clock: a module that starts allocating or
-- walking more per frame than last week has to fail here, not in a 60fps
-- game. Raise the number only with a comment saying what got more expensive.
local BUDGET_ESP_FRAME_SECONDS: number = 0.010
esp:Toggle()
local frameStarted: number = os.clock()
local FRAME_SAMPLES: number = 20
for _ = 1, FRAME_SAMPLES do
    stub.step(0.016)
end
local frameElapsed: number = os.clock() - frameStarted
esp:Toggle()
local perFrame: number = frameElapsed / FRAME_SAMPLES
check(
    "ESP redraw stays inside the per-frame time budget",
    perFrame <= BUDGET_ESP_FRAME_SECONDS,
    string.format("%.4fs/frame", perFrame)
)

    -- Delivery ---------------------------------------------------------------------
end
