-- v151 · Universal Touch Fling: continuous Infinite Yield `walkfling`.
--
-- The card is only a switch. The three-signal velocity engine and its local
-- noclip live in src/libraries/Fling.lua. There is no Touched-listener fan-out:
-- IY's mechanism works by walking into another character while the local root
-- publishes one high-velocity physics window per frame. Session-only
-- (restore = false): injecting with an old config must never arm the engine.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Touch Fling",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local physics: any = state.flingPhysics
    assert(physics, "Touch Fling requires the shared walkfling library")
    assert(type(physics.setTouchEnabled) == "function",
        "Touch Fling requires the continuous engine entry point")

    local touchFlingActive: boolean = false
    local TouchFlingFeature: any = nil

    local function toggleTouchFling(enabled: boolean): ()
        local wanted: boolean = enabled == true
        touchFlingActive = wanted
        physics.setTouchEnabled(wanted)
        if TouchFlingFeature then
            TouchFlingFeature:SetStatus(if wanted then "WALKFLING ON" else nil)
        end
    end

    TouchFlingFeature = createUniversalFeature(
        "Touch Fling",
        "Continuous IY walkfling: walk into players to fling them",
        14,
        toggleTouchFling,
        {noOptions = true, categoryName = "Exploits", restore = false}
    )
    addFeatureTooltip(
        TouchFlingFeature,
        "Runs Infinite Yield's real walkfling on your OWN root: every physics "
            .. "frame publishes vel * 10000 + 10000Y, restores it on "
            .. "RenderStepped, and alternates ±0.1Y on Stepped. Local "
            .. "character collisions are disabled while ON and restored on "
            .. "OFF. No spinning, no target writes, no constraints and no "
            .. "per-frame CFrame. Keep it OFF when you are not flinging."
    )

    if state then
        state.touchFlingFeature = TouchFlingFeature
        state.setTouchFlingEnabled = function(on: boolean): ()
            toggleTouchFling(on == true)
        end
    end

    activeCleanup = function(): ()
        toggleTouchFling(false)
        if state then
            state.touchFlingFeature = nil
            state.setTouchFlingEnabled = nil
        end
    end
    Module.Initialized = true
    return TouchFlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
