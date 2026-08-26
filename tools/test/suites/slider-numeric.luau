--!strict
--
-- Headless tests: numeric sliders and ranges.
--
-- A Wurst slider shows min / max and an editable current value. The rail
-- keeps a finite drag range, while the text field accepts any finite number.
-- Auto Clicker's CPS is a low/high range that stays ordered. Typed junk, NaN
-- and inf must not stick.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("SliderNumeric")

    local WidgetFile: any = require("../../../src/library/Widgets")
    Mock.inject(world, WidgetFile.init)
    local widgets: any = host._widgets
    if type(widgets) ~= "table" then
        widgets = WidgetFile.init(host)
        host._widgets = widgets
    end

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

    local last: number = -1
    local panel: any = newPanel("Slider.Numeric")
    widgets.addNumberOption(panel, "Speed", 32, 16, 200, function(value: number): ()
        last = value
    end)
    local row: any = panel.optionRows[1]
    check("a slider builds a row", row ~= nil)
    local box: any = row and row:FindFirstChild("NumericValue")
    if box == nil and row then
        local slider: any = row:FindFirstChild("Slider")
        box = slider and slider:FindFirstChild("NumericValue")
    end
    check("the current value is an editable TextBox", box ~= nil and box.ClassName == "TextBox")
    if box ~= nil then
        local placeholder: string = tostring(box.PlaceholderText or "")
        check(
            "min is visible on the slider",
            string.find(placeholder, "16", 1, true) ~= nil,
            placeholder
        )
        check(
            "max is visible on the slider",
            string.find(placeholder, "200", 1, true) ~= nil,
            placeholder
        )
        check(
            "the current value is shown",
            tostring(box.Text) == "32" or last == 32,
            tostring(box.Text)
        )

        box.Text = "64"
        if box.FocusLost and box.FocusLost.Fire then
            box.FocusLost:Fire()
        end
        check("FocusLost commits a typed current value", last == 64, tostring(last))

        box.Text = "9999"
        box.FocusLost:Fire()
        check("typed values are not clamped to the drag rail", last == 9999, tostring(last))

        local before: number = last
        box.Text = "not-a-number"
        if box.FocusLost and box.FocusLost.Fire then
            box.FocusLost:Fire()
        end
        check("invalid text is rejected", last == before, tostring(last))

        box.Text = "nan"
        if box.FocusLost and box.FocusLost.Fire then
            box.FocusLost:Fire()
        end
        check("NaN is rejected", last == before, tostring(last))

        box.Text = "inf"
        if box.FocusLost and box.FocusLost.Fire then
            box.FocusLost:Fire()
        end
        check(
            "inf is rejected or not finite",
            last == before or (last == last and last ~= math.huge and last ~= -math.huge),
            tostring(last)
        )

        -- Drag path clamps. The track is 100 px wide at x=0 in the mock.
        local slider: any = row:FindFirstChild("Slider")
        if slider and slider.InputBegan then
            local track: any = slider:FindFirstChild("Track")
            if track then
                track.AbsolutePosition = world.globals.Vector2.new(0, 0)
                track.AbsoluteSize = world.globals.Vector2.new(100, 6)
            end
            slider.InputBegan:Fire({
                UserInputType = world.globals.Enum.UserInputType.MouseButton1,
                Position = world.globals.Vector2.new(100, 0),
            })
            check(
                "a drag past the end clamps to max",
                last <= 200,
                tostring(last)
            )
            slider.InputBegan:Fire({
                UserInputType = world.globals.Enum.UserInputType.MouseButton1,
                Position = world.globals.Vector2.new(-50, 0),
            })
            check(
                "a drag past the start clamps to min",
                last >= 16,
                tostring(last)
            )
        end
    end

    local decimalValue: number = 0
    local decimalPanel: any = newPanel("Slider.Decimal")
    widgets.addNumberOption(
        decimalPanel,
        "Opacity",
        0.5,
        0,
        2,
        function(value: number): () decimalValue = value end
    )
    local decimalRow: any = decimalPanel.optionRows[1]
    local decimalSlider: any = decimalRow and decimalRow:FindFirstChild("Slider")
    local decimalBox: any = decimalSlider and decimalSlider:FindFirstChild("NumericValue")
    if decimalBox then
        decimalBox.Text = "1.7339128"
        decimalBox.FocusLost:Fire()
    end
    check(
        "typed decimal sliders preserve deliberate precision",
        decimalValue == 1.7339128,
        tostring(decimalValue)
    )

    local steppedValue: number = 0
    local steppedPanel: any = newPanel("Slider.Stepped")
    widgets.addNumberOption(
        steppedPanel,
        "Scale",
        1,
        0,
        2,
        function(value: number): () steppedValue = value end,
        nil,
        0.05
    )
    local steppedRow: any = steppedPanel.optionRows[1]
    local steppedSlider: any = steppedRow and steppedRow:FindFirstChild("Slider")
    local steppedBox: any = steppedSlider and steppedSlider:FindFirstChild("NumericValue")
    if steppedBox then
        steppedBox.Text = "1.7339128"
        steppedBox.FocusLost:Fire()
    end
    check("typed values ignore the drag step", steppedValue == 1.7339128, tostring(steppedValue))
    check(
        "decimal config stores the deliberate typed value",
        host.configData.values["Slider.Decimal.Opacity"] == 1.7339128,
        tostring(host.configData.values["Slider.Decimal.Opacity"])
    )
    check(
        "explicit step remains a drag-rail setting",
        host.configData.values["Slider.Stepped.Scale"] == 1.7339128,
        tostring(host.configData.values["Slider.Stepped.Scale"])
    )

    local integerValue: number = 0
    local integerPanel: any = newPanel("Slider.Integer")
    widgets.addNumberOption(
        integerPanel,
        "Count",
        32,
        16,
        200,
        function(value: number): () integerValue = value end
    )
    local integerRow: any = integerPanel.optionRows[1]
    local integerSlider: any = integerRow and integerRow:FindFirstChild("Slider")
    local integerBox: any = integerSlider and integerSlider:FindFirstChild("NumericValue")
    if integerBox then
        integerBox.Text = "32.7"
        integerBox.FocusLost:Fire()
    end
    check(
        "integer sliders preserve a deliberate typed fraction",
        integerValue == 32.7,
        tostring(integerValue)
    )
    check(
        "integer config preserves a deliberate typed fraction",
        host.configData.values["Slider.Integer.Count"] == 32.7,
        tostring(host.configData.values["Slider.Integer.Count"])
    )
    if integerSlider then
        local track: any = integerSlider:FindFirstChild("Track")
        if track then
            track.AbsolutePosition = world.globals.Vector2.new(0, 0)
            track.AbsoluteSize = world.globals.Vector2.new(100, 6)
        end
        integerSlider.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.MouseButton1,
            Position = world.globals.Vector2.new(37, 0),
        })
    end
    check(
        "integer slider drags stay integral",
        integerValue % 1 == 0,
        tostring(integerValue)
    )

    -- Range: low / high stay ordered.
    local lows: {number} = {}
    local highs: {number} = {}
    local rangePanel: any = newPanel("Slider.Range")
    widgets.addRangeOption(rangePanel, "CPS", {
        min = 1,
        max = 28,
        defaultLow = 8,
        defaultHigh = 12,
        onChanged = function(low: number, high: number): ()
            table.insert(lows, low)
            table.insert(highs, high)
        end,
    })
    check("a range row builds", rangePanel.optionRows[1] ~= nil)
    check(
        "range defaults are ordered",
        #lows > 0 and lows[#lows] <= highs[#highs],
        tostring(lows[#lows]) .. ".." .. tostring(highs[#highs])
    )
    local rangeRow: any = rangePanel.optionRows[1]
    local lowValue: any = rangeRow and rangeRow:FindFirstChild("LowValue")
    local highValue: any = rangeRow and rangeRow:FindFirstChild("HighValue")
    local dash: any = rangeRow and rangeRow:FindFirstChild("RangeDash")
    check(
        "the range exposes editable low and high values",
        lowValue ~= nil and highValue ~= nil and dash ~= nil
    )
    if lowValue ~= nil and highValue ~= nil then
        check(
            "the editable range starts at its configured defaults",
            tonumber(lowValue.Text) == 8 and tonumber(highValue.Text) == 12,
            tostring(lowValue.Text) .. "–" .. tostring(highValue.Text)
        )
        lowValue.Text = "-999"
        lowValue.FocusLost:Fire()
        highValue.Text = "9999"
        highValue.FocusLost:Fire()
        check(
            "typed range values are not clamped to the drag rail",
            lows[#lows] == -999 and highs[#highs] == 9999,
            tostring(lows[#lows]) .. ".." .. tostring(highs[#highs])
        )
    end

    -- Booted modules: Speed is a single value, CPS is a range.
    local bootShell: any = require("../boot_shell")
    local boot: any = bootShell(ctx)
    check("slider boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end
    local env: any = boot.env
    local fw: any = env.state and env.state.framework
    check("framework is published after boot", type(fw) == "table")
    if type(fw) == "table" then
        local speed: any = fw.Modules and (fw.Modules.SpeedHack or fw.Modules.Speed)
        check("Speed is a module", speed ~= nil)
        if speed ~= nil then
            local option: any = speed.Options and speed.Options.Speed
            check("Speed stays a single value", option ~= nil and type(option.Value) == "number")
            if option ~= nil then
                check(
                    "Speed metadata min/max match the slider",
                    option.Metadata and option.Metadata.min == 16 and option.Metadata.max == 200,
                    option.Metadata and tostring(option.Metadata.min)
                )
                check(
                    "Speed current matches metadata",
                    option.Metadata.current == option.Value
                )
            end
        end
        local clicker: any = fw.Modules and fw.Modules["Auto Clicker"]
        check("Auto Clicker is a module", clicker ~= nil)
        if clicker ~= nil then
            local cps: any = clicker.Options and clicker.Options.CPS
            check("CPS is a range table", cps ~= nil and type(cps.Value) == "table")
            if cps ~= nil and type(cps.Value) == "table" then
                check(
                    "CPS low/high are ordered",
                    type(cps.Value.Min) == "number"
                        and type(cps.Value.Max) == "number"
                        and cps.Value.Min <= cps.Value.Max,
                    tostring(cps.Value.Min) .. ".." .. tostring(cps.Value.Max)
                )
                check(
                    "CPS metadata keeps the same low/high",
                    cps.Metadata.rangeLow == cps.Value.Min
                        and cps.Metadata.rangeHigh == cps.Value.Max
                )
            end
        end
    end

    -- Mobile path: the same TextBox is the editor; there is no second
    -- numeric surface for touch.
    check(
        "the widget library does not invent a mobile-only numeric field",
        string.find(ctx.bundleSource or "", "MobileNumeric", 1, true) == nil
    )

    if boot.state and type(boot.state.destruct) == "function" then
        boot.state.destruct()
    end
end
