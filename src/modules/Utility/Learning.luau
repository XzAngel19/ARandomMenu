--!strict
--
-- Learning.
--
-- Creates a local, user-triggered screen sample for feature engineering. A
-- capture is never taken in the background, uploaded, or sent through a
-- remote: the player must press Capture now, and the executor must expose an
-- explicit screenshot function. The sidecar JSON describes the sample without
-- copying gameplay objects or player chat.
--
-- Roblox's standard Luau API has no screen-capture primitive. The shell
-- exposes a small capability service for executors that provide one; when it
-- is unavailable this card reports that fact instead of pretending to capture.

export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Learning",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local services: any = context.services
    local captureService: any = services and services.screenCapture
    local product: any = host.PRODUCT or {}
    local httpService: any = host.HttpService
    local currentWorkspace: Workspace = host.workspace or workspace
    local sampleNumber: number = 0
    local card: any

    local function writeMetadata(path: string, payload: any): boolean
        if not captureService or type(captureService.writeText) ~= "function" then
            return false
        end
        local ok: boolean, encoded: any = pcall(function(): string
            return httpService:JSONEncode(payload)
        end)
        if not ok or type(encoded) ~= "string" then
            return false
        end
        return captureService.writeText(path, encoded) == true
    end

    local function captureSample(): ()
        if not captureService or type(captureService.isAvailable) ~= "function"
            or not captureService.isAvailable() then
            card:Notify("screenshot API unavailable")
            card:SetStatus("unavailable")
            return
        end
        if type(captureService.capture) ~= "function"
            or type(captureService.writeText) ~= "function" then
            card:Notify("screen capture service incomplete")
            card:SetStatus("unavailable")
            return
        end

        sampleNumber += 1
        local folder: string = tostring(product.storageFolder or "ARandomMenu")
            .. "/Learning"
        local stamp: string = tostring(os.time())
        local base: string = folder
            .. "/"
            .. tostring(game.PlaceId)
            .. "-"
            .. stamp
            .. "-"
            .. tostring(sampleNumber)
        local imagePath: string = base .. ".png"
        local metadataPath: string = base .. ".json"
        local captured: boolean, reason: any = captureService.capture(imagePath)
        if not captured then
            card:Notify(tostring(reason or "screen capture failed"))
            card:SetStatus("failed")
            return
        end

        local camera: Camera? = currentWorkspace.CurrentCamera
        local viewport: Vector2 = camera
            and camera.ViewportSize
            or Vector2.new(0, 0)
        local payload: {[string]: any} = {
            schema = 1,
            kind = "learning-screen-sample",
            image = imagePath,
            capturedAt = os.time(),
            placeId = game.PlaceId,
            viewport = {width = viewport.X, height = viewport.Y},
            source = "manual Capture now action",
            menuVisible = services.menu.isVisible(),
        }
        local wrote: boolean = writeMetadata(metadataPath, payload)
        if not wrote then
            card:Notify("image saved; metadata could not be written")
            card:SetStatus("image saved")
            return
        end
        card:SetStatus("saved " .. tostring(sampleNumber))
        card:Notify("saved learning sample " .. tostring(sampleNumber))
    end

    card = framework.Categories.Other:CreateModule({
        Name = "Learning",
        Category = "Other",
        ConfigKey = "Universal.Learning",
        Kind = "group",
        Order = 26,
        Tooltip = "Save a manual local screenshot and a small metadata sidecar.",
        Function = function(_enabled: boolean): ()
            -- Group cards have no runtime loop. Keeping this callback empty
            -- makes the ownership explicit: only the button below captures.
        end,
    })
    card:CreateButton({
        Name = "Capture now",
        Tooltip = "Save one screenshot locally; no upload or background capture.",
        Function = captureSample,
    })
    card:CreateNote(
        "Manual and local only. Standard Roblox Luau has no screenshot API."
    )

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
