--!strict

export type SupportedGame = {
    key: string,
    displayName: string,
    gameId: number,
    profilePath: string,
    matches: (self: SupportedGame, gameId: number, placeId: number) -> boolean,
}

local TRS: SupportedGame = {
    key = "TRS",
    displayName = "Realistic Street Soccer",
    gameId = 14315258385,
    profilePath = "src/Profile/trs.json",
    matches = function(self: SupportedGame, gameId: number, placeId: number): boolean
        return gameId == self.gameId or placeId == self.gameId
    end,
}

return table.freeze(TRS)
