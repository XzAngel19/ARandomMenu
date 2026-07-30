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
    {id = "playerEsp", name = "Player ESP", order = 1},
    {id = "antiAfk", name = "Anti AFK", order = 2},
    {id = "antiFling", name = "Anti Fling", order = 3},
    {id = "antiVoid", name = "Anti Void", order = 4},
    {id = "fullbright", name = "Fullbright", order = 5},
    {id = "lagSwitch", name = "Lag Switch", order = 6},
})

local Universal: SupportedModule = {
    key = "Universal",
    displayName = "Universal",
    alwaysEnabled = true,
    register = function(runtime: RuntimeApi): ()
        runtime.registerSection("Universal", "Universal", FEATURES)
    end,
}

return table.freeze(Universal)
