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
    gameId = 93978595733734,
    key = "VD",
    displayName = "Violence District",
    enabledSections = {
        "Universal",
        "Movement",
        "VD",
        "Config",
    },
    assets = {},
}

return table.freeze(profile)
