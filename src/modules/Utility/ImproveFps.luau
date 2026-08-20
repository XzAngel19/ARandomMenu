--!strict
--
-- Improve FPS.
--
-- Stripping textures, particles, shadows and materials has nothing to do with
-- any one game, so it lives here rather than inside a game module. Every
-- property this touches is cached before it is written, and restored exactly
-- when the feature is switched off — a client that ran this should look no
-- different from one that never did.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "ImproveFps",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption

    local fpsSettings: {[string]: boolean} = {
        textures = true,
        particles = true,
        shadows = true,
        materials = false,
    }
    local fpsModeEnabled: boolean = false
    -- Weak keys: a part that leaves the world takes its cached values with it
    -- instead of pinning the whole instance in memory until the next restore.
    local fpsVisualCache: any = setmetatable({}, {__mode = "k"})

    local function cacheFpsProperty(object: any, property: string): ()
        local data: any = fpsVisualCache[object]
        if not data then
            data = {}
            fpsVisualCache[object] = data
        end
        if data[property] == nil then
            data[property] = object[property]
        end
    end

    local function applyFpsObject(object: Instance): ()
        local target: any = object
        if fpsSettings.textures and (object:IsA("Decal") or object:IsA("Texture")) then
            cacheFpsProperty(object, "Transparency")
            target.Transparency = 1
        elseif fpsSettings.textures and object:IsA("MeshPart") then
            cacheFpsProperty(object, "TextureID")
            target.TextureID = ""
        end

        if fpsSettings.particles
            and (object:IsA("ParticleEmitter")
                or object:IsA("Trail")
                or object:IsA("Beam")
                or object:IsA("Smoke")
                or object:IsA("Fire")
                or object:IsA("Sparkles")) then
            cacheFpsProperty(object, "Enabled")
            target.Enabled = false
        end

        if object:IsA("BasePart") then
            if fpsSettings.shadows then
                cacheFpsProperty(object, "CastShadow")
                object.CastShadow = false
            end
            if fpsSettings.materials then
                cacheFpsProperty(object, "Material")
                cacheFpsProperty(object, "Reflectance")
                object.Material = Enum.Material.SmoothPlastic
                object.Reflectance = 0
            end
        end
    end

    local function restoreFpsObjects(): ()
        for object: any, properties: any in pairs(fpsVisualCache) do
            if object and object.Parent then
                for property: string, value: any in pairs(properties) do
                    pcall(function(): ()
                        object[property] = value
                    end)
                end
            end
        end
        fpsVisualCache = setmetatable({}, {__mode = "k"})
    end

    local function toggleImproveFps(enabled: boolean): ()
        fpsModeEnabled = enabled
        disconnectFeatureConnection("ImproveFPS")
        restoreFpsObjects()

        if not enabled then
            return
        end

        -- The initial sweep is chunked so a large map cannot freeze the client.
        task.spawn(function(): ()
            for index: number, object: Instance in ipairs(workspace:GetDescendants()) do
                if not fpsModeEnabled then
                    return
                end
                pcall(applyFpsObject, object)
                if index % 250 == 0 then
                    task.wait()
                end
            end
        end)
        featureConnections.ImproveFPS = workspace.DescendantAdded:Connect(
            function(object: Instance): ()
                if fpsModeEnabled then
                    pcall(applyFpsObject, object)
                end
            end
        )
    end
    state.toggleImproveFps = toggleImproveFps

    -- Flipping an option while the feature is already on has to redo the sweep,
    -- otherwise the setting only takes effect the next time it is toggled.
    local function refreshFps(): ()
        if fpsModeEnabled then
            toggleImproveFps(true)
        end
    end

    local ImproveFpsFeature: any = createUniversalFeature(
        "Improve FPS",
        "Apply only the selected reversible optimizations",
        26,
        toggleImproveFps
    )
    addToggleOption(ImproveFpsFeature, "Remove textures", true, function(value: boolean): ()
        fpsSettings.textures = value
        refreshFps()
    end)
    addToggleOption(ImproveFpsFeature, "Disable particles", true, function(value: boolean): ()
        fpsSettings.particles = value
        refreshFps()
    end)
    addToggleOption(ImproveFpsFeature, "Disable shadows", true, function(value: boolean): ()
        fpsSettings.shadows = value
        refreshFps()
    end)
    addToggleOption(ImproveFpsFeature, "Simple materials", false, function(value: boolean): ()
        fpsSettings.materials = value
        refreshFps()
    end)

    activeCleanup = function(): ()
        toggleImproveFps(false)
    end
    Module.Initialized = true
    return ImproveFpsFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
