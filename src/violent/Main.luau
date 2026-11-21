local Core = import("Core")
local context = Core.context()
local gui = Core.screen(context)
context.canvas = Core.frame(gui, "ReferenceCanvas", 0, 0, 614, 550, nil, 1)
context.scale = Core.new("UIScale", { Scale = 1 }, context.canvas)
local function fit()
    local size = gui.AbsoluteSize
    if size.X > 0 and size.Y > 0 then
        context.scale.Scale = math.min(1, size.X / 614, size.Y / 550)
    end
end
context:connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
fit()
import("Window").build(context)
import("Preview").build(context)

-- Only UI is exported. State is local presentation data, never game settings.
return {
    Gui = gui,
    State = context.state,
    Destroy = function() gui:Destroy() end,
}
