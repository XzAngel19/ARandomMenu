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

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local services: any = context.services
    local captureService: any = services and services.screenCapture
    local product: any = host.PRODUCT or {}
    local httpService: any = host.HttpService
    local currentWorkspace: Workspace = host.workspace or workspace
    local sampleNumber: number = 0

    local notify: any = host.notify
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addInformationOption: any = host.addInformationOption

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
            notify("Learning: screenshot API unavailable")
            return
        end
        if type(captureService.capture) ~= "function"
            or type(captureService.writeText) ~= "function" then
            notify("Learning: screen capture service incomplete")
            return
        end

        sampleNumber += 1
        local folder: string = tostring(product.storageFolder or "Wurst")
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
            notify("Learning: " .. tostring(reason or "screen capture failed"))
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
            notify("Learning: image saved; metadata could not be written")
            return
        end
        notify("Learning: saved sample " .. tostring(sampleNumber))
    end

    local LearningFeature: any = state.learningFeature
    if not LearningFeature then
        LearningFeature = createUniversalFeature(
            "Learning",
            "Evidence collection in one card: remote logging and screen samples.",
            26,
            function(_enabled: boolean): () end,
            {category = true, categoryName = "Other"}
        )
        state.learningFeature = LearningFeature
    end
    local finishPanel = state.beginCardPanel(LearningFeature, "Screen samples")

    addActionOption(LearningFeature, "Capture now", function(): ()
        captureSample()
    end, "Save one screenshot locally; no upload or background capture.")
    addInformationOption(
        LearningFeature,
        "Manual and local only. Standard Roblox Luau has no screenshot API."
    )
    finishPanel()

    activeCleanup = function(): () end
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
