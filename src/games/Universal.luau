--!strict

export type FeatureDefinition = {
    id: string,
    name: string,
    order: number,
}

export type Runtime = {
    registerSection: ((string, string, {FeatureDefinition}) -> ())?,
}

local Module = {
    Name = "Universal",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local UNIVERSAL_FEATURES: {FeatureDefinition} = table.freeze({
    {id = "playerEsp", name = "Player ESP", order = 1},
    {id = "antiAfk", name = "Anti AFK", order = 2},
    {id = "antiFling", name = "Anti Fling", order = 3},
    {id = "antiVoid", name = "Anti Void", order = 4},
    {id = "fullbright", name = "Fullbright", order = 5},
    {id = "lagSwitch", name = "Lag Switch", order = 6},
})

local MOVEMENT_FEATURES: {FeatureDefinition} = table.freeze({
    {id = "fly", name = "Fly", order = 1},
    {id = "fling", name = "Fling", order = 2},
    {id = "hitboxes", name = "Hitboxes", order = 3},
    {id = "gravity", name = "Gravity", order = 4},
    {id = "jumpPower", name = "Jump Power", order = 5},
    {id = "infiniteJump", name = "Infinite Jump", order = 6},
    {id = "walkSpeed", name = "Walk Speed", order = 7},
    {id = "physicsSpeed", name = "Physics Speed", order = 8},
    {id = "fieldOfView", name = "Field of View", order = 9},
    {id = "noclip", name = "Noclip", order = 10},
    {id = "clickTeleport", name = "Click Teleport", order = 11},
    {id = "freezeMovements", name = "Freeze Movements", order = 12},
})

function Module.matches(_placeId: number): boolean
    return true
end

function Module.init(runtime: Runtime): typeof(Module)
    if Module.Initialized then
        return Module
    end
    if runtime.registerSection then
        runtime.registerSection("Universal", "Universal", UNIVERSAL_FEATURES)
        runtime.registerSection("Movement", "Movement", MOVEMENT_FEATURES)
    end
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    Module.Initialized = false
    table.clear(Module.Events)
end

return Module
