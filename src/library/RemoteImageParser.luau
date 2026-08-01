--!strict

local AssetService: AssetService = game:GetService("AssetService")
local HttpService: HttpService = game:GetService("HttpService")

type PngImage = {
    width: number,
    height: number,
    pixels: buffer,
}

type PngDecoder = {
    decode: (source: buffer) -> PngImage,
}

export type RemoteImageParserApi = {
    create_from_bytes: (imageData: string) -> EditableImage,
    apply_to: (target: Instance, url: string) -> (boolean, string?),
    destroy: () -> (),
}

local PNG_DECODER_URL: string =
    "https://raw.githubusercontent.com/XzAngel19/ARandomMenu/main/src/vendor/png-luau/png.luau"
local decoder: PngDecoder? = nil
local activeImages: {EditableImage} = {}

local function getDecoder(): PngDecoder
    if decoder then
        return decoder
    end
    local source: string = (game :: any):HttpGet(PNG_DECODER_URL, true)
    assert(#source > 64, "PNG decoder response was empty")
    local compiler: any = (getfenv() :: any).loadstring
    assert(type(compiler) == "function", "loadstring is unavailable")
    local chunk: any, compileError: any = compiler(source, "@png-luau")
    assert(type(chunk) == "function", tostring(compileError))
    local loaded: any = chunk()
    assert(type(loaded) == "table" and type(loaded.decode) == "function", "Invalid PNG decoder")
    decoder = loaded :: PngDecoder
    return decoder :: PngDecoder
end

local RemoteImageParser: RemoteImageParserApi = {} :: RemoteImageParserApi

function RemoteImageParser.create_from_bytes(imageData: string): EditableImage
    assert(#imageData >= 8, "Image response was empty")
    assert(string.sub(imageData, 1, 8) == "\137PNG\r\n\26\n", "Only PNG images are supported")
    local decoded: PngImage = getDecoder().decode(buffer.fromstring(imageData))
    local size: Vector2 = Vector2.new(decoded.width, decoded.height)
    local editable: EditableImage? = AssetService:CreateEditableImage({
        Size = size,
    })
    assert(editable, "EditableImage allocation failed")
    editable:WritePixelsBuffer(Vector2.zero, size, decoded.pixels)
    table.insert(activeImages, editable)
    return editable
end

function RemoteImageParser.apply_to(
    target: Instance,
    url: string
): (boolean, string?)
    local downloaded: boolean, imageData: any = pcall(function(): string
        return HttpService:GetAsync(url, true)
    end)
    if not downloaded or type(imageData) ~= "string" then
        downloaded, imageData = pcall(function(): string
            return (game :: any):HttpGet(url, true)
        end)
    end
    if not downloaded or type(imageData) ~= "string" then
        return false, "Download failed: " .. tostring(imageData)
    end

    local parsed: boolean, editableOrError: any = pcall(
        RemoteImageParser.create_from_bytes,
        imageData
    )
    if not parsed then
        return false, "PNG decode failed: " .. tostring(editableOrError)
    end
    local assigned: boolean, assignError: any = pcall(function(): ()
        (target :: any).ImageContent = Content.fromObject(editableOrError)
    end)
    if not assigned then
        return false, "ImageContent assignment failed: " .. tostring(assignError)
    end
    return true, nil
end

function RemoteImageParser.destroy(): ()
    for _, editable: EditableImage in ipairs(activeImages) do
        editable:Destroy()
    end
    table.clear(activeImages)
end

return RemoteImageParser
