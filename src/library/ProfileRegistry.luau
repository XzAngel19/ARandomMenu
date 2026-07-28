--!strict

local HttpService: HttpService = game:GetService("HttpService")

export type Profile = {
    schemaVersion: number,
    gameId: number,
    key: string,
    displayName: string,
    enabledSections: {string},
    assets: {[string]: string},
}

type ProfileIndex = {
    schemaVersion: number,
    profiles: {[string]: string},
}

export type ProfileRegistryApi = {
    get: (gameId: number) -> Profile?,
    getCurrent: () -> Profile?,
}

local RAW_ROOT: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/main/"

local ProfileRegistry: ProfileRegistryApi = {} :: ProfileRegistryApi

local function fetchJson(path: string): any
    local body: string = game:HttpGet(RAW_ROOT .. path)
    return HttpService:JSONDecode(body)
end

function ProfileRegistry.get(gameId: number): Profile?
    local index: ProfileIndex = fetchJson("src/Profile/index.json") :: ProfileIndex
    local path: string? = index.profiles[tostring(gameId)]
    if path == nil then
        return nil
    end
    return fetchJson(path) :: Profile
end

function ProfileRegistry.getCurrent(): Profile?
    return ProfileRegistry.get(game.GameId)
end

return ProfileRegistry
