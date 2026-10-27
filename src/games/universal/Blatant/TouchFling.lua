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

    -- Contact physics is a deliberate per-session action, never restored ON.
    local touchFlingActive: boolean = false
    local syncing: boolean = false
    local TouchFlingFeature: any = nil

    local function toggleTouchFling(enabled: boolean): ()
        if syncing then
            return
        end
        local wanted: boolean = enabled == true
        touchFlingActive = wanted
        physics.setTouchEnabled(wanted)
        if TouchFlingFeature then
            TouchFlingFeature:SetStatus(if wanted then "ON" else nil)
        end

        if state and type(state.toggleControls) == "table" then
            local mm2Control: any = state.toggleControls["MM2.Fling.TouchFling"]
            if mm2Control and type(mm2Control.setChecked) == "function" then
                syncing = true
                pcall(mm2Control.setChecked, wanted)
                syncing = false
            end
        end
    end

    TouchFlingFeature = createUniversalFeature(
        "Touch Fling",
        "Walk into a player and the contact launches them, with your character left normal",
        14,
        toggleTouchFling,
        {noOptions = true, categoryName = "Exploits", restore = false}
    )
    addFeatureTooltip(
        TouchFlingFeature,
        "Only your body parts listen; touching someone adds a bounded contact pulse to their body and one physics step to yours. No spin, no Humanoid Physics state, no teleports, no ownership requests. OFF and respawn restore every snapshot."
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
