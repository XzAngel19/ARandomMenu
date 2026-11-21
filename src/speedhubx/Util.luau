--!nocheck
--[[
    Speed Hub X — Util
    ===================
    Instance factory helpers, safe executor GUI parenting, dragging,
    viewport-aware UI scaling and small tween helpers.

    Everything in this module is pure UI plumbing.  No gameplay, farming,
    combat, movement, safe-mode or automation logic exists anywhere in
    this project by design — feature callbacks live in Features/*.luau
    and are intentionally left empty.
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require("Theme")

local Util = {}

---------------------------------------------------------------------------
-- Instance factory
---------------------------------------------------------------------------
-- Usage:
--   local f = Util.create("Frame", { Size = ..., Parent = parent }, { child1, child2 })
-- Special props:
--   Corner   = number | UDim        -> adds UICorner
--   Stroke   = { Thickness, Color, Transparency, ... } -> adds UIStroke
--   Gradient = { Color = ColorSequence|{Color3,Color3}, Rotation, ... } -> adds UIGradient
--   Padding  = number | UDim        -> adds UIPadding (all sides)
--   Children = { ... }              -> alternative to 3rd argument
function Util.create(className, props, children)
    local instance = Instance.new(className)
    props = props or {}

    local corner   = props.Corner
    local stroke   = props.Stroke
    local gradient = props.Gradient
    local padding  = props.Padding

    for key, value in pairs(props) do
        if key ~= "Corner" and key ~= "Stroke" and key ~= "Gradient" and key ~= "Padding" and key ~= "Children" then
            instance[key] = value
        end
    end

    if corner ~= nil then
        local radius = typeof(corner) == "number" and UDim.new(0, corner) or corner
        local ui = Instance.new("UICorner")
        ui.CornerRadius = radius
        ui.Parent = instance
    end

    if stroke ~= nil then
        local ui = Instance.new("UIStroke")
        for key, value in pairs(stroke) do
            ui[key] = value
        end
        ui.Parent = instance
    end

    if gradient ~= nil then
        local ui = Instance.new("UIGradient")
        for key, value in pairs(gradient) do
            if key == "Color" and typeof(value) == "table" then
                local seq = {}
                for i, color in ipairs(value) do
                    seq[i] = ColorSequenceKeypoint.new((i - 1) / math.max(#value - 1, 1), color)
                end
                ui.Color = ColorSequence.new(seq)
            else
                ui[key] = value
            end
        end
        ui.Parent = instance
    end

    if padding ~= nil then
        local ui = Instance.new("UIPadding")
        local uniform = typeof(padding) == "number" and UDim.new(0, padding) or padding
        ui.PaddingLeft = uniform
        ui.PaddingRight = uniform
        ui.PaddingTop = uniform
        ui.PaddingBottom = uniform
        ui.Parent = instance
    end

    local kids = children or props.Children
    if kids then
        for _, child in ipairs(kids) do
            child.Parent = instance
        end
    end

    return instance
end

---------------------------------------------------------------------------
-- Safe GUI parenting (executor-first, with graceful fallbacks)
---------------------------------------------------------------------------
-- Preference order:
--   1. gethui()              (executors expose a hidden, syn-protected container)
--   2. CoreGui               (pcall-probed — some executors block writes)
--   3. Players.LocalPlayer.PlayerGui  (always available on a client)
function Util.getGuiParent()
    local okHui, hui = pcall(function()
        if typeof(gethui) == "function" then
            return gethui()
        end
        return nil
    end)
    if okHui and typeof(hui) == "Instance" then
        return hui
    end

    local okCore = pcall(function()
        local probe = Instance.new("Frame")
        probe.Name = "__SpeedHubXProbe"
        probe.Parent = game:GetService("CoreGui")
        probe:Destroy()
    end)
    if okCore then
        return game:GetService("CoreGui")
    end

    local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    return playerGui
end

-- Some executors require gui objects to be flagged as protected so they do
-- not vanish on camera/character resets or get reaped by the engine.
function Util.protectGui(gui)
    pcall(function()
        if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
            syn.protect_gui(gui)
        end
    end)
    pcall(function()
        local protect = typeof(protect_gui) == "function" and protect_gui or nil
        if protect then
            protect(gui)
        end
    end)
end

-- If the script is executed twice, drop the previous instance instead of
-- stacking duplicates.
function Util.destroyPrevious(parent)
    local existing = parent:FindFirstChild(Theme.WindowName .. ".ScreenGui")
    if existing then
        existing:Destroy()
    end
    local stray = parent:FindFirstChild(Theme.WindowName)
    if stray then
        stray:Destroy()
    end
end

---------------------------------------------------------------------------
-- Viewport-aware scaling
---------------------------------------------------------------------------
-- Keeps the fixed-size design (1234x791) fully visible on any screen.
function Util.computeScale(designWidth, designHeight)
    local camera = Workspace.CurrentCamera
    if camera == nil then
        return 1
    end
    local viewport = camera.ViewportSize
    local availableWidth = math.max(viewport.X - 32, 240)
    local availableHeight = math.max(viewport.Y - 32, 180)
    local scale = math.min(1, availableWidth / designWidth, availableHeight / designHeight)
    return scale
end

function Util.bindScale(uiScale, designWidth, designHeight, connections)
    local function update()
        uiScale.Scale = Util.computeScale(designWidth, designHeight)
    end
    update()
    local camera = Workspace.CurrentCamera
    if camera then
        local conn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
        if connections then
            table.insert(connections, conn)
        end
    end
    return update
end

---------------------------------------------------------------------------
-- Dragging (title bar / floating logo)
---------------------------------------------------------------------------
-- `getScale` optionally returns the UIScale applied between the ScreenGui
-- and `target` (the window lives under a UIScale; the floating logo does
-- not).  Screen-pixel deltas are divided by it so drag speed matches the
-- rendered size.  Returns a cleanup function that disconnects the handlers.
function Util.makeDraggable(handle, target, connections, getScale)
    local dragging = false
    local dragStart = nil
    local startAnchor = nil

    local function currentScale()
        if getScale then
            return math.max(getScale(), 0.05)
        end
        return 1
    end

    local function anchorInPixels(position, viewport)
        return Vector2.new(
            position.X.Scale * viewport.X + position.X.Offset,
            position.Y.Scale * viewport.Y + position.Y.Offset
        )
    end

    local beginConn = handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            local camera = Workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1017)
            startAnchor = anchorInPixels(target.Position, viewport)
        end
    end)

    local changedConn = UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local camera = Workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1017)
        local targetSize = target.AbsoluteSize
        local anchor = target.AnchorPoint
        local delta = (input.Position - dragStart) / currentScale()
        local anchorPoint = startAnchor + delta
        -- Keep at least 40 design-pixels of the widget inside the viewport.
        local margin = 40 * currentScale()
        local halfX = targetSize.X * anchor.X
        local halfY = targetSize.Y * anchor.Y
        anchorPoint = Vector2.new(
            math.clamp(anchorPoint.X, margin - halfX, viewport.X - margin + (targetSize.X - halfX)),
            math.clamp(anchorPoint.Y, margin - halfY, viewport.Y - margin + (targetSize.Y - halfY))
        )
        target.Position = UDim2.new(0, anchorPoint.X, 0, anchorPoint.Y)
    end)

    local endConn = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    if connections then
        table.insert(connections, beginConn)
        table.insert(connections, changedConn)
        table.insert(connections, endConn)
    end
    return function()
        beginConn:Disconnect()
        changedConn:Disconnect()
        endConn:Disconnect()
    end
end

---------------------------------------------------------------------------
-- Tweens
---------------------------------------------------------------------------
local TweenService = game:GetService("TweenService")

function Util.tween(instance, duration, properties, style, direction)
    local info = TweenInfo.new(
        duration or 0.18,
        style or Enum.EasingStyle.Quad,
        direction or Enum.EasingDirection.Out
    )
    local tween = TweenService:Create(instance, info, properties)
    tween:Play()
    return tween
end

function Util.lerpColor(a, b, t)
    return a:Lerp(b, t)
end

return Util
