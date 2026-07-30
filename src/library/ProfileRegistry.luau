--!strict

export type Profile = {
    schemaVersion: number,
    gameId: number,
    key: string,
    displayName: string,
    enabledSections: {string},
    assets: {[string]: string},
}

export type ProfileRegistryApi = {
    get: (gameId: number) -> Profile?,
    getCurrent: () -> Profile?,
}

local RAW_ROOT: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/main/"

local ProfileRegistry: ProfileRegistryApi = {} :: ProfileRegistryApi

type ProfileChunk = () -> Profile
type Compiler = (source: string, chunkName: string?) -> ProfileChunk?

function ProfileRegistry.get(gameId: number): Profile?
    local path: string = "src/Profile/" .. tostring(gameId) .. ".lua"
    local success: boolean, result: any = pcall(function(): Profile
        local source: string = (game :: any):HttpGet(RAW_ROOT .. path)
        local compiler: Compiler = (loadstring :: any) :: Compiler
        local chunk: ProfileChunk = assert(
            compiler(source, "@" .. path),
            "ARandomMenu profile failed to compile: " .. path
        )
        return chunk()
    end)

    if not success then
        return nil
    end

    return result :: Profile
end

function ProfileRegistry.getCurrent(): Profile?
    return ProfileRegistry.get(game.GameId)
end

return ProfileRegistry
