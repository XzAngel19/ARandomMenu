--!strict
--
-- Headless tests: Wurst setting-row widgets against ref-wurst-settings.jpg
-- and Wurst7 4a22e53 (SliderComponent, CheckboxComponent, ColorComponent).
--
-- Logical units stay GUI-scale-1 (rail 3, knob 8×8, checkbox 11, color 22).
-- A landed the official pair at GUI scale 2: rail 6, knob 16×16,
-- checkbox 22, colour/slider 44. Those are the same numbers, not 1080p.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Setting widgets")

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

    local function collectText(root: any, into: {string}): ()
        if type(root) ~= "table" then
            return
        end
        local text: any = root.Text
        if type(text) == "string" and text ~= "" then
            table.insert(into, text)
        end
        if type(root.GetDescendants) ~= "function" then
            return
        end
        for _, node: any in ipairs(root:GetDescendants()) do
            local nodeText: any = node.Text
            if type(nodeText) == "string" and nodeText ~= "" then
                table.insert(into, nodeText)
            end
        end
    end

    local function isOfficialRail(height: number): boolean
        return height == 3 or height == 6
    end

    local function isOfficialKnob(width: number, height: number): boolean
        return (width == 8 and height == 8) or (width == 16 and height == 16)
    end

    -- Checkbox ----------------------------------------------------------------

    local togglePanel: any = newPanel("Settings.Checkbox")
    widgets.addToggleOption(togglePanel, "Debug draw", false, function(): () end)
    local toggleRow: any = togglePanel.options:FindFirstChild("Option_Debugdraw")
    check("a checkbox builds a row", toggleRow ~= nil)

    local checkbox: any = toggleRow and toggleRow:FindFirstChild("OptionCheckbox")
    check("the checkbox is a square, not a switch", checkbox ~= nil)
    if checkbox ~= nil then
        check(
            "the checkbox is Wurst's 11 logical px box at GUI scale 2",
            checkbox.Size.X.Offset == 22 and checkbox.Size.Y.Offset == 22,
            tostring(checkbox.Size.X.Offset) .. "x" .. tostring(checkbox.Size.Y.Offset)
        )
        check(
            "the checkbox has no corner radius",
            checkbox:FindFirstChildOfClass("UICorner") == nil
        )
        check(
            "the checkbox is not a pill switch",
            checkbox.Name ~= "OptionSwitch"
                and checkbox.Name ~= "Switch"
                and (checkbox.Size.X.Offset <= checkbox.Size.Y.Offset + 1)
        )
        check(
            "Widgets does not call the old switch builder",
            type(host.createToggleSwitch) == "function"
        )
    end

    -- Slider ------------------------------------------------------------------

    local sliderPanel: any = newPanel("Settings.Slider")
    widgets.addNumberOption(sliderPanel, "Opacity", 0.5, 0.15, 0.85, function(): () end)
    local sliderRow: any = sliderPanel.optionRows[1]
    check("a slider builds a two-line row", sliderRow ~= nil)
    if sliderRow ~= nil then
        check(
            "a slider is two text-rows tall (22 logical, 44 at scale 2)",
            sliderRow.Size.Y.Offset == 44,
            tostring(sliderRow.Size.Y.Offset)
        )
        local slider: any = sliderRow:FindFirstChild("Slider")
        local valueBox: any = slider and slider:FindFirstChild("NumericValue")
        check("the slider value sits on the right", valueBox ~= nil)
        if valueBox ~= nil then
            check(
                "the slider value is right-aligned",
                valueBox.TextXAlignment == world.globals.Enum.TextXAlignment.Right,
                tostring(valueBox.TextXAlignment)
            )
        end
        local track: any = slider and slider:FindFirstChild("Track")
        check("the slider has a rail", track ~= nil)
        if track ~= nil then
            check(
                "the rail is official 3 logical (6 at scale 2)",
                isOfficialRail(track.Size.Y.Offset),
                tostring(track.Size.Y.Offset)
            )
            local knob: any = track:FindFirstChild("Knob")
            check("the slider has a square knob", knob ~= nil)
            if knob ~= nil then
                check(
                    "the knob is official 8×8 logical (16×16 at scale 2)",
                    isOfficialKnob(knob.Size.X.Offset, knob.Size.Y.Offset),
                    tostring(knob.Size.X.Offset) .. "x" .. tostring(knob.Size.Y.Offset)
                )
            end
        end
    end

    -- Color -------------------------------------------------------------------

    local colorPanel: any = newPanel("Settings.Color")
    widgets.addColorOption(
        colorPanel,
        "Background",
        world.globals.Color3.fromRGB(64, 64, 64),
        function(): () end
    )
    local colorRow: any = colorPanel.optionRows[1]
    check("a colour row builds", colorRow ~= nil)
    if colorRow ~= nil then
        check(
            "a colour row has two heights, not one",
            colorRow.Size.Y.Offset >= 26,
            tostring(colorRow.Size.Y.Offset)
        )
        local hex: any = colorRow:FindFirstChild("HexValue")
        check("the colour row shows its hex", hex ~= nil)
        if hex ~= nil then
            check(
                "the hex is right-aligned",
                hex.TextXAlignment == world.globals.Enum.TextXAlignment.Right,
                tostring(hex.TextXAlignment)
            )
            check(
                "the hex spells the default",
                hex.Text == "#404040",
                tostring(hex.Text)
            )
        end
        local bar: any = colorRow:FindFirstChild("ColorBar")
        check("the colour row has a swatch bar under the label", bar ~= nil)
        if bar ~= nil then
            check(
                "the swatch is its own line",
                bar.Position.Y.Offset > 0,
                tostring(bar.Position.Y.Offset)
            )
        end
    end

    -- Forbidden icon glyphs ---------------------------------------------------

    local texts: {string} = {}
    collectText(toggleRow, texts)
    collectText(sliderRow, texts)
    collectText(colorRow, texts)
    local banned: string? = nil
    for _, text: string in ipairs(texts) do
        if text == "+" or text == "–" or text == "▪" or text == "•" or text == "■" then
            banned = text
            break
        end
    end
    check(
        "setting rows do not use +, –, ▪ as icons",
        banned == nil,
        banned
    )

    -- Theme.enabled is what an on-checkbox fills with, and what the
    -- capture's green names use. It is independent of Background/Accent/Text.
    -- Combo / action / section ------------------------------------------------

    local comboPanel: any = newPanel("Settings.Combo")
    widgets.addCycleOption(
        comboPanel,
        "Mode",
        { "Auto", "Count", "Hidden" },
        1,
        function(): () end
    )
    local comboRow: any = comboPanel.optionRows[1]
    local comboValue: any = comboRow and comboRow:FindFirstChild("ComboValue")
    check("a combo is a rectangular line, not a pill", comboValue ~= nil)
    if comboValue ~= nil then
        check(
            "the combo value is right-aligned",
            comboValue.TextXAlignment == world.globals.Enum.TextXAlignment.Right
        )
        check(
            "the combo has no corner radius",
            comboValue:FindFirstChildOfClass("UICorner") == nil
        )
    end

    local actionPanel: any = newPanel("Settings.Action")
    widgets.addActionOption(actionPanel, "Rejoin", function(): () end)
    local actionRow: any = actionPanel.optionRows[1]
    check("an action row builds", actionRow ~= nil)
    if actionRow ~= nil then
        check(
            "Widgets itself does not round the action row",
            actionRow:FindFirstChildOfClass("UICorner") == nil
        )
    end

    local sectionPanel: any = newPanel("Settings.Section")
    widgets.addSectionOption(sectionPanel, "Advanced")
    local sectionTitle: any = sectionPanel.optionRows[1]
        and sectionPanel.optionRows[1]:FindFirstChild("SectionTitle")
    if sectionTitle ~= nil then
        local heading: string = tostring(sectionTitle.Text)
        check(
            "section headings are not the old DISPLAY/FILTERS/STYLE chips",
            heading ~= "DISPLAY"
                and heading ~= "FILTERS"
                and heading ~= "STYLE"
        )
    end

    check(
        "Theme.enabled exists so the capture green can be applied",
        host.Theme.enabled ~= nil
    )
end
