local Core, Theme = import("Core"), import("Theme")
local Controls = {}

function Controls.section(parent, text, y)
    local title = Core.text(parent, text, 7, y, 291, 27, 20, Theme.DisplayFont)
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.TextStrokeColor3 = Theme.Black
    title.TextStrokeTransparency = 0.15
    local width = ({ Highlights = 83, ["Health Bar"] = 87, Text = 36 })[text] or 60
    Core.frame(parent, text .. "Underline", (305 - width) / 2, y + 23, width, 2,
        Color3.fromRGB(131, 36, 94))
    return title
end

function Controls.row(context, parent, label, y, selected)
    local row = Core.button(parent, label, 0, y, 305, 26)
    row.BackgroundColor3 = Theme.Selection
    row.BackgroundTransparency = selected and 0 or 1
    local caption = Core.text(row, label, 8, 0, 263, 26, 15)
    caption.TextColor3 = selected and Theme.Black or Theme.White
    local record = { row = row, caption = caption, label = label }
    table.insert(context.rows, record)
    if selected then context.selected = record end
    function record:select()
        if context.selected then
            context.selected.row.BackgroundTransparency = 1
            context.selected.caption.TextColor3 = Theme.White
        end
        context.selected = self
        row.BackgroundTransparency = 0
        caption.TextColor3 = Theme.Black
        context.status.Text = "Set color to: " .. label
        if not string.find(label, "Color", 1, true) then context.status.Text = "Set: " .. label end
    end
    context:connect(row.MouseEnter, function() context.status.Text = "Set: " .. label end)
    context:connect(row.MouseLeave, function()
        local current = context.selected
        if current then
            local prefix = string.find(current.label, "Color", 1, true) and "Set color to: " or "Set: "
            context.status.Text = prefix .. current.label
        end
    end)
    return record
end

function Controls.toggle(context, parent, label, key, y, initial, callback)
    local record = Controls.row(context, parent, label, y)
    local box = Core.frame(record.row, "Checkbox", 279, 5, 17, 17, Theme.White, 1)
    Core.stroke(box, Theme.White, 2)
    local check = Core.frame(box, "Check", 0, 0, 17, 17, Theme.White, 1)
    Core.line(check, "Short", 3, 9, 7, 13, Theme.White, 2)
    Core.line(check, "Long", 7, 13, 14, 4, Theme.White, 2)
    check.Visible = initial
    context.state[key] = initial
    function record:activate()
        self:select()
        context.state[key] = not context.state[key]
        check.Visible = context.state[key]
        callback(context.state[key])
    end
    context:connect(record.row.Activated, function() record:activate() end)
    return record
end

function Controls.number(context, parent, label, key, y, initial, minimum, maximum, step, callback)
    local record = Controls.row(context, parent, label, y)
    local value = Core.new("TextBox", {
        Name = "Value", Text = tostring(initial), ClearTextOnFocus = false,
        Position = UDim2.fromOffset(260, 0), Size = UDim2.fromOffset(38, 26),
        BackgroundTransparency = 1, BorderSizePixel = 0, Font = Theme.BodyFont,
        TextSize = 15, TextColor3 = Theme.White, TextXAlignment = Enum.TextXAlignment.Right,
    }, record.row)
    context.state[key] = initial
    local function set(number)
        number = math.clamp(math.round(number / step) * step, minimum, maximum)
        number = math.round(number * 100) / 100
        local changed = context.state[key] ~= number
        context.state[key], value.Text = number, tostring(number)
        if changed then callback(number) end
    end
    function record:activate() self:select(); value:CaptureFocus() end
    function record:adjust(direction) set(context.state[key] + step * direction) end
    context:connect(record.row.Activated, function() record:activate() end)
    context:connect(value.Focused, function() record:select() end)
    context:connect(value.FocusLost, function()
        local number = tonumber(value.Text)
        if number and number == number and math.abs(number) < math.huge then set(number)
        else value.Text = tostring(context.state[key]) end
    end)
    -- An invisible drag region preserves the reference's value-only slider.
    local drag = Core.button(record.row, "ValueDrag", 185, 0, 70, 26)
    local startX, startValue, touch
    context:connect(drag.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            record:select()
            startX, startValue = input.Position.X, context.state[key]
            touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
        end
    end)
    context:connect(context.input.InputChanged, function(input)
        if startX and (input.UserInputType == Enum.UserInputType.MouseMovement or input == touch) then
            set(startValue + (input.Position.X - startX) / context.scale.Scale / 12 * step)
        end
    end)
    context:connect(context.input.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input == touch then
            startX, touch = nil, nil
        end
    end)
    return record
end

function Controls.color(context, parent, label, key, y, initial, callback, selected)
    local record = Controls.row(context, parent, label, y, selected)
    local swatch = Core.frame(record.row, "Swatch", 275, 5, 25, 18, initial)
    Core.stroke(swatch, Color3.fromRGB(146, 151, 153), 1)
    context.state[key] = initial
    function record:activate()
        self:select()
        if context.popup then context.popup:Destroy(); context.popup = nil end
        -- Popup controls exist only while open; Destroy disconnects their events.
        local popup = Core.frame(context.canvas, "ColorPicker", 335, 350, 255, 151, Theme.Panel)
        popup.ZIndex = 20
        Core.stroke(popup, Theme.Selection, 1)
        context.popup = popup
        Core.text(popup, label, 10, 5, 218, 23, 15)
        local close = Core.button(popup, "Close", 228, 5, 22, 23)
        Core.text(close, "×", 0, 0, 22, 23, 20).TextXAlignment = Enum.TextXAlignment.Center
        close.Activated:Connect(function() popup:Destroy(); context.popup = nil end)
        local current = context.state[key]
        local fields = {}
        for index, channel in ipairs({ "R", "G", "B" }) do
            local x = 10 + (index - 1) * 80
            Core.text(popup, channel, x, 36, 20, 22, 14)
            fields[index] = Core.new("TextBox", {
                Name = channel, Text = tostring(math.round(({ current.R, current.G, current.B })[index] * 255)),
                Position = UDim2.fromOffset(x + 19, 36), Size = UDim2.fromOffset(48, 24),
                BackgroundColor3 = Theme.Black, BorderSizePixel = 0, TextColor3 = Theme.White,
                Font = Theme.BodyFont, TextSize = 15, ClearTextOnFocus = false,
            }, popup)
        end
        Core.text(popup, "RGB · 0–255", 10, 66, 230, 21, 13).TextColor3 = Theme.Muted
        local apply = Core.button(popup, "Apply", 10, 103, 235, 32)
        apply.BackgroundTransparency, apply.BackgroundColor3 = 0, Theme.Selection
        Core.text(apply, "Apply color", 8, 0, 219, 32, 15).TextColor3 = Theme.Black
        apply.Activated:Connect(function()
            local channels = {}
            for index, field in ipairs(fields) do
                local number = tonumber(field.Text)
                if not number or number ~= number or math.abs(number) == math.huge then
                    field.Text = "0"
                    return
                end
                channels[index] = math.clamp(math.round(number), 0, 255)
            end
            local color = Color3.fromRGB(channels[1], channels[2], channels[3])
            context.state[key], swatch.BackgroundColor3 = color, color
            callback(color)
            popup:Destroy(); context.popup = nil
        end)
    end
    context:connect(record.row.Activated, function() record:activate() end)
    return record
end

return Controls
