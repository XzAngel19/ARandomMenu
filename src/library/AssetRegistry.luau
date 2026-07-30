--!strict

local HttpService: HttpService = game:GetService("HttpService")

export type AssetManifest = {
    schemaVersion: number,
    rawBaseUrl: string,
    images: {[string]: string?},
    attribution: {[string]: string}?,
}

export type AssetRegistryApi = {
    getUrl: (key: string) -> string?,
    clearCache: () -> (),
}

local MANIFEST_URL: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/main/src/gui/Current/Images/manifest.json"

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
    local fileName: string? = manifest.images[key]
    if fileName == nil or fileName == "" then
        return nil
    end
    return manifest.rawBaseUrl .. fileName
end

function AssetRegistry.clearCache(): ()
    cachedManifest = nil
end

return AssetRegistry
