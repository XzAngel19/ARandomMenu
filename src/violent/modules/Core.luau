local Theme = import("Theme")
local Core = {}

function Core.new(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    return object
end

function Core.frame(parent, name, x, y, width, height, color, transparency)
    return Core.new("Frame", {
        Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = color or Theme.Panel, BackgroundTransparency = transparency or 0,
        BorderSizePixel = 0,
    }, parent)
end

function Core.text(parent, text, x, y, width, height, size, font)
    local label = Core.new("TextLabel", {
        Name = text, Text = text, Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height), BackgroundTransparency = 1,
        BorderSizePixel = 0, TextColor3 = Theme.White, TextSize = size or 15,
        Font = font or Theme.BodyFont, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, parent)
    if font == Theme.DisplayFont then label.FontFace = Theme.DisplayFace end
    return label
end

function Core.button(parent, name, x, y, width, height)
    return Core.new("TextButton", {
        Name = name, Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
        BorderSizePixel = 0, Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height),
    }, parent)
end

function Core.stroke(parent, color, thickness)
    return Core.new("UIStroke", {
        Color = color or Theme.Black, Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

function Core.line(parent, name, x1, y1, x2, y2, color, thickness)
    local dx, dy = x2 - x1, y2 - y1
    local line = Core.frame(parent, name, (x1 + x2) / 2, (y1 + y2) / 2,
        math.sqrt(dx * dx + dy * dy), thickness or 1, color)
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.Rotation = math.deg(math.atan2(dy, dx))
    return line
end

function Core.context()
    local context = { connections = {}, state = {}, alive = true }
    context.input = game:GetService("UserInputService")
    function context:connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(self.connections, connection)
        return connection
    end
    function context:cleanup()
        if not self.alive then return end
        self.alive = false
        for _, connection in ipairs(self.connections) do connection:Disconnect() end
        table.clear(self.connections)
    end
    return context
end

function Core.screen(context)
    local gui = Core.new("ScreenGui", {
        Name = Theme.Name, ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    gui:SetAttribute("Owner", Theme.Identity)
    -- Each candidate is attempted independently; a present but unusable gethui
    -- or a denied CoreGui must not prevent the ordinary PlayerGui fallback.
    local candidates = {
        function()
            if type(gethui) == "function" then return gethui() end
        end,
        function() return game:GetService("CoreGui") end,
        function()
            local player = game:GetService("Players").LocalPlayer
            assert(player, "No LocalPlayer: run this inside a live Roblox client")
            return player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
        end,
    }
    local mounted = false
    for _, candidate in ipairs(candidates) do
        local ok, parent = pcall(candidate)
        if ok and typeof(parent) == "Instance" then
            local attached = pcall(function() gui.Parent = parent end)
            if attached and gui.Parent == parent then
                -- Remove ONLY earlier copies belonging to this standalone UI.
                for _, child in ipairs(parent:GetChildren()) do
                    if child ~= gui and child.Name == Theme.Name
                        and child:GetAttribute("Owner") == Theme.Identity then
                        child:Destroy()
                    end
                end
                mounted = true
                break
            end
        end
    end
    if not mounted then
        gui:Destroy()
        error("Violent UI: unable to parent ScreenGui to gethui, CoreGui, or PlayerGui")
    end
    context:connect(gui.Destroying, function() context:cleanup() end)
    context.gui = gui
    return gui
end

function Core.drag(context, handle, window)
    handle.Active = true
    local origin, startPosition, touch
    context:connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            origin, startPosition = input.Position, window.Position
            touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
        end
    end)
    context:connect(context.input.InputChanged, function(input)
        if not origin then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= touch then return end
        local scale = context.scale.Scale
        local delta = (input.Position - origin) / scale
        local viewport = context.gui.AbsoluteSize / scale
        -- Retain the full header onscreen so a dragged window is recoverable.
        local x = math.clamp(startPosition.X.Offset + delta.X, 0,
            math.max(0, viewport.X - window.Size.X.Offset))
        local y = math.clamp(startPosition.Y.Offset + delta.Y, 0,
            math.max(0, viewport.Y - handle.Size.Y.Offset))
        window.Position = UDim2.fromOffset(x, y)
    end)
    context:connect(context.input.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input == touch then
            origin, touch = nil, nil
        end
    end)
end

return Core
