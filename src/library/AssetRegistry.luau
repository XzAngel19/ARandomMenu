--!strict

local environment: any = getfenv()
local cloneReference: (Instance) -> Instance = (
    environment.cloneref
    or function(instance: Instance): Instance
        return instance
    end
) :: (Instance) -> Instance
local HttpService: HttpService =
    cloneReference(game:GetService("HttpService")) :: HttpService

export type AssetEntry = {
    category: string,
    path: string,
    dimensions: {number},
    usage: string,
}

export type AssetManifest = {
    schemaVersion: number,
    rawBaseUrl: string,
    assets: {[string]: AssetEntry?},
}

export type AssetRegistryApi = {
    getUrl: (key: string) -> string?,
    clearCache: () -> (),
}

local MANIFEST_URL: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/src/gui/Current/Assets/manifest.json"

local AssetRegistry: AssetRegistryApi = {} :: AssetRegistryApi
local cachedManifest: AssetManifest? = nil

local function getManifest(): AssetManifest
    if cachedManifest ~= nil then
        return cachedManifest
    end
    local body: string = (game :: any):HttpGet(MANIFEST_URL)
    cachedManifest = HttpService:JSONDecode(body) :: AssetManifest
    return cachedManifest :: AssetManifest
end

function AssetRegistry.getUrl(key: string): string?
    local manifest: AssetManifest = getManifest()
    local entry: AssetEntry? = manifest.assets[key]
    if entry == nil or entry.path == "" then
        return nil
    end
    return manifest.rawBaseUrl .. entry.path
end

function AssetRegistry.clearCache(): ()
    cachedManifest = nil
end

return AssetRegistry
