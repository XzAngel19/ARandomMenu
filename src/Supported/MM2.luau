--!strict

export type SupportedGame = {
    key: string,
    displayName: string,
    gameId: number,
    profilePath: string,
    matches: (self: SupportedGame, gameId: number, placeId: number) -> boolean,
}

local MM2: SupportedGame = {
    key = "MM2",
    displayName = "Murder Mystery 2",
    gameId = 142823291,
    profilePath = "src/Profile/142823291.lua",
    matches = function(self: SupportedGame, gameId: number, placeId: number): boolean
        return gameId == self.gameId or placeId == self.gameId
    end,
}

return table.freeze(MM2)
