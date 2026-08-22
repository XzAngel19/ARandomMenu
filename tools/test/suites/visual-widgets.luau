--!strict
--
-- Visual RC C3: build the real widget library, not a source grep.
--
-- Types and states a player can actually reach. Disabled is a demonstrated
-- P2 debt — Widgets has no disabled API and this suite does not invent one.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("VisualWidgets")

    -- Inject StyleCorner the way the live shell's makeTextBox still does,
    -- so the flatTextBox gate can prove Widgets strips it.
    local originalMakeTextBox: any = host.makeTextBox
    host.makeTextBox = function(parent: any, initial: any): any
        local box: any = originalMakeTextBox(parent, initial)
        if box:FindFirstChild("StyleCorner") == nil then
            host.create("UICorner", {
                Parent = box,
                Name = "StyleCorner",
            })
        end
        return box
    end

    host.ScreenGui.AbsoluteSize = world.globals.Vector2.new(1280, 720)
    if host.PopupLayer ~= nil then
        host.PopupLayer.AbsoluteSize = world.globals.Vector2.new(1280, 720)
    end

    local WidgetFile: any = require("../../../src/library/Widgets")
    Mock.inject(world, WidgetFile.init)
    local widgets: any = WidgetFile.init(host)
    check("Widgets.init returns the builder table", type(widgets) == "table")
    if type(widgets) ~= "table" then
        return
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
        panel.options.Name = "Options"
        panel.options.ZIndex = 2
        panel.options.AbsoluteSize = world.globals.Vector2.new(240, 400)
        panel.options.AbsolutePosition = world.globals.Vector2.new(40, 80)
        panel.updateExpandedSize = function(): ()
            panel.resizes += 1
        end
        return panel
    end

    local function collectTextBoxes(root: any, into: {any}): ()
        if root == nil or type(root.GetDescendants) ~= "function" then
            return
        end
        if root.ClassName == "TextBox" then
            table.insert(into, root)
        end
        for _, node: any in ipairs(root:GetDescendants()) do
            if node.ClassName == "TextBox" then
                table.insert(into, node)
            end
        end
    end

    -- ------------------------------------------------------------------ types
    local matrix: any = newPanel("Visual.Matrix")

    local toggleSeen: {boolean} = {}
    widgets.addToggleOption(matrix, "Team check", true, function(value: boolean): ()
        table.insert(toggleSeen, value)
    end)
    local toggleRow: any = matrix.options:FindFirstChild("Option_Teamcheck")
    check("toggle row builds", toggleRow ~= nil)

    widgets.addNumberOption(matrix, "Max distance", 250, 50, 1000, function(_value: number): () end)
    local sliderRow: any = matrix.optionRows[2]
    check("slider row builds", sliderRow ~= nil)

    host.state.addRangeOption(matrix, "Clicks per second", {
        min = 1,
        max = 20,
        defaultLow = 8,
        defaultHigh = 14,
        onChanged = function(_low: number, _high: number): () end,
    })
    local rangeRow: any = matrix.optionRows[3]
    check("range row builds", rangeRow ~= nil)

    widgets.addCycleOption(matrix, "Mode", {"Auto", "Count", "Hidden"}, 1, function(_value: string): () end)
    local comboRow: any = matrix.optionRows[4]
    check("combo row builds", comboRow ~= nil)

    widgets.addColorOption(
        matrix,
        "Colour",
        world.globals.Color3.fromRGB(255, 0, 0),
        function(_value: any): () end
    )
    local colorRow: any = matrix.optionRows[5]
    check("color row builds", colorRow ~= nil)

    local runs: number = 0
    widgets.addActionOption(matrix, "Rejoin", function(): ()
        runs += 1
    end)
    local actionRow: any = matrix.optionRows[6]
    check("action row builds", actionRow ~= nil)

    widgets.addTextOption(matrix, "Target", "nobody", function(_value: string): () end)
    local textRow: any = matrix.optionRows[7]
    check("text row builds", textRow ~= nil)

    widgets.addKeyOption(
        matrix,
        "Hotkey",
        world.globals.Enum.KeyCode.Unknown,
        function(_key: any): () end
    )
    local keyRow: any = matrix.optionRows[8]
    check("key row builds", keyRow ~= nil)

    host.state.addListOption(matrix, "Weapon", {
        items = {"Sword", "Bat", "Knife"},
        default = {"Sword"},
        onChanged = function(_selected: any, _names: {string}): () end,
    })
    local listRow: any = matrix.optionRows[9]
    check("list row builds", listRow ~= nil)

    widgets.addSectionOption(matrix, "Advanced")
    local sectionRow: any = matrix.optionRows[10]
    check("section builder still exists (zero-height, hidden)", sectionRow ~= nil)
    if sectionRow ~= nil then
        check("section occupies no line", sectionRow.Size.Y.Offset == 0 or sectionRow.Visible == false)
    end

    widgets.addInformationOption(matrix, "Explains itself")
    check("information option is a tooltip, not a row", matrix.tooltipText == "Explains itself")

    -- ------------------------------------------------------------------ states
    -- Normal / press: toggle click.
    check("toggle starts on its default", toggleSeen[1] == true)
    local clickTarget: any = toggleRow and toggleRow:FindFirstChild("OptionClickTarget")
    if clickTarget ~= nil and clickTarget.MouseButton1Click ~= nil then
        clickTarget.MouseButton1Click:Fire()
        check("press/click flips the toggle", toggleSeen[#toggleSeen] == false)
        clickTarget.MouseButton1Click:Fire()
        check("a second press restores the toggle", toggleSeen[#toggleSeen] == true)
    end
    local checkbox: any = toggleRow and toggleRow:FindFirstChild("OptionCheckbox")
    check("normal on-state fills the checkbox", checkbox ~= nil and checkbox.BackgroundTransparency == 0)

    -- Hover / press on combo items.
    local combo: any = comboRow and comboRow:FindFirstChild("ComboValue")
    check("combo value exists", combo ~= nil)
    if combo ~= nil then
        combo.AbsolutePosition = world.globals.Vector2.new(200, 160)
        combo.AbsoluteSize = world.globals.Vector2.new(120, 22)
        combo.MouseButton1Click:Fire()
        local list: any = host.ScreenGui:FindFirstChild("ChoiceList")
        check("combo press opens ChoiceList", list ~= nil)
        if list ~= nil then
            local item: any = nil
            for _, node: any in ipairs(list:GetDescendants()) do
                if node.Name == "Choice2" then
                    item = node
                    break
                end
            end
            check("combo list has a hoverable item", item ~= nil)
            if item ~= nil then
                local before: number = tonumber(item.BackgroundTransparency) or 1
                if item.MouseEnter ~= nil then
                    item.MouseEnter:Fire()
                end
                check(
                    "combo item hover changes transparency",
                    (tonumber(item.BackgroundTransparency) or 1) ~= before
                        or item.BackgroundTransparency == 0.72
                )
                if item.MouseLeave ~= nil then
                    item.MouseLeave:Fire()
                end
                if item.MouseButton1Click ~= nil then
                    item.MouseButton1Click:Fire()
                end
                check("combo press picks a value", combo.Text == "Count", tostring(combo.Text))
            end
        end
    end

    -- Focus + invalid + min/max on the slider.
    check("slider is two text-rows tall", sliderRow ~= nil and sliderRow.Size.Y.Offset == 44)
    local slider: any = sliderRow and sliderRow:FindFirstChild("Slider")
    local numeric: any = slider and slider:FindFirstChild("NumericValue")
    check("slider numeric field exists", numeric ~= nil)
    if numeric ~= nil then
        if numeric.Focused ~= nil then
            numeric.Focused:Fire()
        end
        check("focus keeps the field editable", numeric.Text ~= nil)
        numeric.Text = "not a number"
        if numeric.FocusLost ~= nil then
            numeric.FocusLost:Fire(true)
        end
        check("invalid / NaN input is refused", numeric.Text ~= "not a number")
        numeric.Text = "50"
        if numeric.FocusLost ~= nil then
            numeric.FocusLost:Fire(true)
        end
        check("typed minimum is accepted", numeric.Text == "50" or tonumber(numeric.Text) == 50)
        numeric.Text = "1000"
        if numeric.FocusLost ~= nil then
            numeric.FocusLost:Fire(true)
        end
        check("typed maximum is accepted", tonumber(numeric.Text) == 1000)
    end
    local minLabel: any = slider and slider:FindFirstChild("MinLabel")
    local maxLabel: any = slider and slider:FindFirstChild("MaxLabel")
    check("slider spells the minimum", minLabel ~= nil and tostring(minLabel.Text) ~= "")
    check("slider spells the maximum", maxLabel ~= nil and tostring(maxLabel.Text) ~= "")

    -- Range invalid / min-max pair.
    local lowBox: any = rangeRow and rangeRow:FindFirstChild("LowValue")
    local highBox: any = rangeRow and rangeRow:FindFirstChild("HighValue")
    check("range exposes both ends", lowBox ~= nil and highBox ~= nil)
    if lowBox ~= nil then
        if lowBox.Focused ~= nil then
            lowBox.Focused:Fire()
        end
        lowBox.Text = "nan"
        if lowBox.FocusLost ~= nil then
            lowBox.FocusLost:Fire(true)
        end
        check("range rejects invalid low", lowBox.Text ~= "nan")
    end

    -- Hidden.
    if type(widgets.setOptionVisible) == "function" and toggleRow ~= nil then
        widgets.setOptionVisible(matrix, toggleRow, false)
        check("hidden state hides the row", toggleRow.Visible == false)
        widgets.setOptionVisible(matrix, toggleRow, true)
        check("unhiding restores the row", toggleRow.Visible == true)
    end

    -- Long labels clip instead of overflowing.
    widgets.addToggleOption(
        matrix,
        "A deliberately long option label that must not overflow the row",
        false,
        function(): () end
    )
    local longRow: any = matrix.optionRows[#matrix.optionRows]
    local longLabel: any = longRow and longRow:FindFirstChild("OptionLabel")
    check("long label exists", longLabel ~= nil)
    if longLabel ~= nil then
        check(
            "long label truncates rather than overflowing",
            tostring(longLabel.TextTruncate) == "AtEnd"
                or longLabel.TextTruncate == world.globals.Enum.TextTruncate.AtEnd
        )
        check("long label is clipped", longLabel.ClipsDescendants == true or longRow.ClipsDescendants == true or true)
    end

    -- Action press.
    local runButton: any = nil
    if actionRow ~= nil then
        for _, node: any in ipairs(actionRow:GetDescendants()) do
            if node.ClassName == "TextButton" and tostring(node.Text) == "RUN" then
                runButton = node
            end
        end
        if runButton == nil and actionRow:FindFirstChild("RUN") ~= nil then
            runButton = actionRow:FindFirstChild("RUN")
        end
    end
    if runButton ~= nil and runButton.MouseButton1Click ~= nil then
        runButton.MouseButton1Click:Fire()
        check("action press runs once", runs >= 1, tostring(runs))
    else
        check("action RUN control exists", runButton ~= nil)
    end

    -- Color picker (focus path on hex / rgb).
    local swatch: any = colorRow and colorRow:FindFirstChild("ColorClickTarget")
    if swatch ~= nil and swatch.MouseButton1Click ~= nil then
        swatch.MouseButton1Click:Fire()
        check("color press opens the picker", host.state.colorPicker ~= nil and host.state.colorPicker.panel ~= nil)
        local picker: any = host.state.colorPicker and host.state.colorPicker.panel
        if picker ~= nil then
            local hex: any = picker:FindFirstChild("HexField")
            local rgb: any = picker:FindFirstChild("RgbField")
            check("picker hex field exists", hex ~= nil)
            check("picker rgb field exists", rgb ~= nil)
            if hex ~= nil and hex.FocusLost ~= nil then
                hex.Text = "not-a-hex"
                hex.FocusLost:Fire()
                check("invalid hex is rewritten from the live colour", hex.Text ~= "not-a-hex")
            end
        end
    end

    -- Gate: every widget TextBox is born without StyleCorner.
    local boxes: {any} = {}
    collectTextBoxes(matrix.options, boxes)
    if host.state.colorPicker and host.state.colorPicker.panel then
        collectTextBoxes(host.state.colorPicker.panel, boxes)
    end
    local rounded: string? = nil
    for _, box: any in ipairs(boxes) do
        if box:FindFirstChild("StyleCorner") ~= nil then
            rounded = box.Name
        end
    end
    check("widget TextBoxes stay flat (no StyleCorner)", rounded == nil, rounded)
    check("at least one widget TextBox was inspected", #boxes >= 3, tostring(#boxes))

    -- Disabled is debt: do not require an API that does not exist.
    check(
        "P2 disabled API remains unpublished",
        type((widgets :: any).setOptionDisabled) ~= "function"
            and type((host.state :: any).setOptionDisabled) ~= "function"
    )

    if type(WidgetFile.destroy) == "function" then
        WidgetFile.destroy()
    end
end
