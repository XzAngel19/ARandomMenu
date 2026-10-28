--!strict

export type Profile = {
    schemaVersion: number,
    gameId: number,
    key: string,
    displayName: string,
    enabledSections: {string},
    assets: {[string]: string},
}

local profile: Profile = {
    schemaVersion = 1,
    gameId = 124848751642883,
    key = "X2Duels",
    displayName = "X2 Duels (1v1)",
    enabledSections = {
        "Universal",
        "Movement",
        "MVSD",
        "Config",
    },
    assets = {},
}

return table.freeze(profile)
