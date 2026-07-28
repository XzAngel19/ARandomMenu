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
    gameId = 142823291,
    key = "MM2",
    displayName = "Murder Mystery 2",
    enabledSections = {
        "Universal",
        "Movement",
        "MM2",
        "Config",
    },
    assets = {
        icon = "mm2Icon",
    },
}

return table.freeze(profile)
