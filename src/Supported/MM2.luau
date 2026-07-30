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
    {id = "roleEsp", name = "Role ESP", order = 1},
    {id = "gunVisuals", name = "Gun Visuals", order = 2},
    {id = "shoot", name = "Shoot", order = 3},
    {id = "sheriffCFrame", name = "Sheriff CFrame", order = 4},
    {id = "knife", name = "Knife", order = 5},
    {id = "loopInteract", name = "Loop All Interact", order = 6},
    {id = "silence", name = "Silence", order = 7},
    {id = "autoPlay", name = "Auto Play ID", order = 8},
    {id = "sprint", name = "Sprint", order = 9},
    {id = "improveFps", name = "Improve FPS", order = 10},
    {id = "timer", name = "Always Show Timer", order = 11},
    {id = "teleport", name = "Teleport", order = 12},
    {id = "fling", name = "Fling", order = 13},
})

local MM2: SupportedModule = {
    key = "MM2",
    displayName = "Murder Mystery 2",
    gameId = 142823291,
    profilePath = "src/Profile/142823291.lua",
    matches = function(gameId: number, placeId: number): boolean
        return gameId == 142823291 or placeId == 142823291
    end,
    register = function(runtime: RuntimeApi): ()
        runtime.registerSection("MM2", "Murder Mystery 2", FEATURES)
    end,
}

return table.freeze(MM2)
