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
    gameId: number,
    profilePath: string,
    matches: (gameId: number, placeId: number) -> boolean,
    register: (runtime: RuntimeApi) -> (),
}

local FEATURES: {FeatureDefinition} = table.freeze({
    {id = "ballControl", name = "Ball Control", order = 1},
    {id = "pickup", name = "Pickup", order = 2},
    {id = "pass", name = "Pass", order = 3},
    {id = "shoot", name = "Shoot", order = 4},
    {id = "powerShot", name = "Power Shot", order = 5},
    {id = "longShot", name = "Long Shot", order = 6},
    {id = "trajectory", name = "Trajectory", order = 7},
})

local TRS: SupportedModule = {
    key = "TRS",
    displayName = "Realistic Street Soccer",
    gameId = 14315258385,
    profilePath = "src/Profile/14315258385.lua",
    matches = function(gameId: number, placeId: number): boolean
        return gameId == 14315258385 or placeId == 14315258385
    end,
    register = function(runtime: RuntimeApi): ()
        runtime.registerSection("TRS", "Realistic Street Soccer", FEATURES)
    end,
}

return table.freeze(TRS)
