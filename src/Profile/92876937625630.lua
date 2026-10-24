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
    gameId = 92876937625630,
    key = "X2Duels",
    displayName = "X2 Duels (MVS)",
    enabledSections = {
        "Universal",
        "Movement",
        "MVSD",
        "Config",
    },
    assets = {},
}

return table.freeze(profile)
