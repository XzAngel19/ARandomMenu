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
    gameId = 14315258385,
    key = "TRS",
    displayName = "Realistic Street Soccer",
    enabledSections = {
        "Universal",
        "Movement",
        "TRS",
        "Config",
    },
    assets = {
        icon = "trsIcon",
    },
}

return table.freeze(profile)
