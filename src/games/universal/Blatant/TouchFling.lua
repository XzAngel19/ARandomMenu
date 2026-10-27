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
    assert(physics, "Touch Fling requires the shared Fling physics library")
    assert(type(physics.setTouchEnabled) == "function",
        "Touch Fling requires the contact entry point of the shared library")

    -- Contact physics is a deliberate per-session action, never restored ON.
    local touchFlingActive: boolean = false
    local TouchFlingFeature: any = nil

    local function toggleTouchFling(enabled: boolean): ()
        local wanted: boolean = enabled == true
        touchFlingActive = wanted
        physics.setTouchEnabled(wanted)
        if TouchFlingFeature then
            TouchFlingFeature:SetStatus(if wanted then "ON" else nil)
        end
    end

    TouchFlingFeature = createUniversalFeature(
        "Touch Fling",
        "Walk normally: whoever you bump into gets flung. No spin, no rotation, full control",
        14,
        toggleTouchFling,
        {noOptions = true, categoryName = "Exploits", restore = false}
    )
    addFeatureTooltip(
        TouchFlingFeature,
        "Infinite Yield's walkfling, which IY itself describes as \"fling but no "
            .. "spinning\": on contact your root velocity gets IY's exact pulse "
            .. "(velocity * 1000000 + 1e6 up) for one render window only, is restored "
            .. "before the physics step, and is followed by IY's 0.1 stud drift. "
            .. "Nothing is attached to your body, nothing is pinned, and the character "
            .. "never turns: you keep walking and you keep looking where you look. "
            .. "OFF and respawn restore every snapshot."
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
