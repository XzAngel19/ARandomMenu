-- v150 · Universal Touch Fling card, rebuilt from zero.
--
-- The card is only a switch. Contact detection and the bounded impulse live in
-- src/libraries/Fling.lua. It is session-only (restore = false): injecting with
-- an old config must never arm a physics action.

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
    assert(physics, "Touch Fling requires the shared contact library")
    assert(type(physics.setTouchEnabled) == "function",
        "Touch Fling requires the contact entry point of the shared library")

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
        "Walk normally: a bounded physics impulse is delivered on contact",
        14,
        toggleTouchFling,
        {noOptions = true, categoryName = "Exploits", restore = false}
    )
    addFeatureTooltip(
        TouchFlingFeature,
        "On contact with another living character the shared library applies a "
            .. "finite impulse (190 studs/s) to an assembly it can steer: the "
            .. "target's root when network ownership is confirmed, otherwise "
            .. "your own root so the character-to-character contact transfers "
            .. "momentum. No spin, no constraints, no CFrame loop and no "
            .. "velocity left behind when it stops. OFF and respawn release "
            .. "every listener and any acquired ownership."
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
