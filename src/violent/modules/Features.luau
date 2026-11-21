-- Deliberately EMPTY feature hooks. Never access characters, cameras,
-- remotes, world objects, executor hooks, or gameplay state in this module.
return {
    EnableSkeleton = function(_enabled) end,
    SkeletonThickness = function(_value) end,
    SkeletonColor = function(_color) end,
    HighlightESP = function(_enabled) end,
    HighlightFill = function(_enabled) end,
    HighlightOutline = function(_enabled) end,
    HighlightFillColor = function(_color) end,
    HighlightOutlineColor = function(_color) end,
    ShowHealthBar = function(_enabled) end,
    HealthBarSize = function(_value) end,
}
