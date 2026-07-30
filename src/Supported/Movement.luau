--!strict

export type FeatureDefinition = {
    id: string,
    name: string,
    order: number,
}

export type RuntimeApi = {
    registerSection: (
        key: string,
        displayName: string,
        features: {FeatureDefinition}
    ) -> (),
}

export type SupportedModule = {
    key: string,
    displayName: string,
    alwaysEnabled: boolean,
    register: (runtime: RuntimeApi) -> (),
}

local FEATURES: {FeatureDefinition} = table.freeze({
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
})

local Movement: SupportedModule = {
    key = "Movement",
    displayName = "Movement",
    alwaysEnabled = true,
    register = function(runtime: RuntimeApi): ()
        runtime.registerSection("Movement", "Movement", FEATURES)
    end,
}

return table.freeze(Movement)
