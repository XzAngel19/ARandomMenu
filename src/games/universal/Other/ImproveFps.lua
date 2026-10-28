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
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption

    local fpsSettings: {[string]: boolean} = {
        textures = true,
        particles = true,
        shadows = true,
        materials = false,
        lighting = false,
        post = false,
        guiEffects = false,
        worldGui = false,
        gameGui = false,
        coreGui = false,
        geometry = false,
        scenery = false,
        quality = false,
        terrain = false,
        lights = false,
    }
    local fpsModeEnabled: boolean = false
    local generation: number = 0
    local ImproveFpsFeature: any = nil
    local function selectedEffectCount(): number
        local count: number = 0
        for _name: string, selected: boolean in pairs(fpsSettings) do
            if selected then count += 1 end
        end
        return count
    end

    local fpsVisualCache: any = {}
    local propertyWatches: {[any]: any} = {}

    local function cacheFpsProperty(object: any, property: string): ()
        local data: any = fpsVisualCache[object]
        if not data then
            data = {}
            fpsVisualCache[object] = data
            -- Keep snapshots strongly until OFF (even detached objects).
            -- Destroyed objects cannot be restored and must not accumulate.
            local ok, connection = pcall(function()
                return object.Destroying:Connect(function()
                    fpsVisualCache[object] = nil
                    local watch = propertyWatches[object]
                    propertyWatches[object] = nil
                    if watch then watch:Disconnect() end
                end)
            end)
            if ok then propertyWatches[object] = connection end
        end
        if data[property] == nil then
            data[property] = object[property]
        end
    end

    local lighting: any = host.Lighting
    local playerGui: any = host.PlayerGui
    local scenery: {[any]: boolean} = setmetatable({}, {__mode = "k"})
    local coreGuiCache: {[any]: boolean} = {}
    local function setProperty(object: any, property: string, value: any): ()
        -- Individual protected writes: an unsupported property must not
        -- prevent the remaining optimizations on that object.
        pcall(function()
            cacheFpsProperty(object, property)
            object[property] = value
        end)
    end
    local function protectedGui(object: any): boolean
        local current = object
        while current do
            if current == host.ScreenGui or current.Name == "TouchGui"
                or current.Name == "Chat" or current.Name == "BubbleChat" then return true end
            current = current.Parent
            if type(current) ~= "table" and typeof(current) ~= "Instance" then break end
        end
        return false
    end
    local function updateScenery(part: any): ()
        local character = host.LocalPlayer and host.LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local cached = fpsVisualCache[part]
        local function restorePart()
            if cached and cached.LocalTransparencyModifier ~= nil then
                pcall(function() part.LocalTransparencyModifier = cached.LocalTransparencyModifier end)
            end
        end
        if not root or not part.Parent or not part.Anchored or not part.CanCollide then restorePart(); return end
        -- Static map only. Never cull characters, tools, or physics objects.
        local current = part.Parent
        while current and current ~= workspace do
            if current:IsA("Tool") or current:IsA("Accessory")
                or current:FindFirstChildOfClass("Humanoid") then restorePart(); return end
            current = current.Parent
        end
        local far = (part.Position - root.Position).Magnitude > 350
        if far then setProperty(part, "LocalTransparencyModifier", 1)
        elseif cached and cached.LocalTransparencyModifier ~= nil then
            pcall(function() part.LocalTransparencyModifier = cached.LocalTransparencyModifier end)
        end
    end

    local function applyFpsObject(object: Instance): ()
        -- A deferred DescendantAdded callback can arrive after destruction.
        -- Keep existing detached snapshots for restoration, but never acquire
        -- new ownership of an object already outside the scene.
        if object ~= workspace and object ~= lighting and object ~= playerGui and object.Parent == nil then return end
        local target: any = object
        if lighting and object == lighting and fpsSettings.lighting then
            setProperty(object, "EnvironmentDiffuseScale", 0)
            setProperty(object, "EnvironmentSpecularScale", 0)
        end
        if fpsSettings.shadows and object == lighting then setProperty(object, "GlobalShadows", false) end
        if fpsSettings.lights and object:IsA("Light") then setProperty(object, "Enabled", false) end
        if fpsSettings.terrain and object:IsA("Terrain") then
            setProperty(object, "Decoration", false)
            setProperty(object, "WaterWaveSize", 0)
            setProperty(object, "WaterWaveSpeed", 0)
            setProperty(object, "WaterReflectance", 0)
        end
        if fpsSettings.post and object:IsA("PostEffect") then
            setProperty(object, "Enabled", false)
        end
        if not protectedGui(object) then
            if fpsSettings.guiEffects and (object:IsA("UIStroke") or object:IsA("UIGradient")) then
                setProperty(object, "Enabled", false)
            elseif fpsSettings.guiEffects and object:IsA("ViewportFrame") then
                setProperty(object, "Visible", false)
            end
            if fpsSettings.worldGui and (object:IsA("BillboardGui") or object:IsA("SurfaceGui")) then
                setProperty(object, "Enabled", false)
            end
            if fpsSettings.gameGui and object:IsA("ScreenGui") then
                setProperty(object, "Enabled", false)
            end
        end
        if fpsSettings.geometry and (object:IsA("MeshPart") or object:IsA("PartOperation")) then
            setProperty(object, "RenderFidelity", Enum.RenderFidelity.Performance)
        end
        if fpsSettings.scenery and object:IsA("BasePart") and object.Anchored and object.CanCollide then
            scenery[object] = true
            updateScenery(object)
        end
        if fpsSettings.textures and (object:IsA("Decal") or object:IsA("Texture")) then
            cacheFpsProperty(object, "Transparency")
            target.Transparency = 1
        elseif fpsSettings.textures and object:IsA("MeshPart") then
            setProperty(object, "TextureID", "")
        elseif fpsSettings.textures and object:IsA("SpecialMesh") then
            setProperty(object, "TextureId", "")
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
        for _, connection in pairs(propertyWatches) do pcall(function() connection:Disconnect() end) end
        propertyWatches = {}
        for object: any, properties: any in pairs(fpsVisualCache) do
            if object then
                for property: string, value: any in pairs(properties) do
                    pcall(function(): ()
                        object[property] = value
                    end)
                end
            end
        end
        fpsVisualCache = {}
        scenery = setmetatable({}, {__mode = "k"})
        local starterGui = host.StarterGui
        if starterGui then
            for kind, value in pairs(coreGuiCache) do
                pcall(function() starterGui:SetCoreGuiEnabled(kind, value) end)
            end
        end
        coreGuiCache = {}
    end

    local function toggleImproveFps(enabled: boolean): ()
        generation += 1
        local token: number = generation
        fpsModeEnabled = enabled
        for _, name in ipairs({"ImproveFPS", "ImproveFPSLighting", "ImproveFPSGui", "ImproveFPSDistance"}) do
            disconnectFeatureConnection(name)
        end
        restoreFpsObjects()

        if not enabled then
            if ImproveFpsFeature then ImproveFpsFeature:SetStatus(nil) end
            return
        end
        ImproveFpsFeature:SetStatus(tostring(selectedEffectCount()) .. " options")
        if fpsSettings.quality then
            pcall(function() setProperty(settings().Rendering, "QualityLevel", Enum.QualityLevel.Level01) end)
        end

        local containers = {workspace}
        if lighting then table.insert(containers, lighting) end
        if playerGui then table.insert(containers, playerGui) end
        for index, container in ipairs(containers) do
            local name = ({"ImproveFPS", "ImproveFPSLighting", "ImproveFPSGui"})[index]
            featureConnections[name] = container.DescendantAdded:Connect(function(object)
                if fpsModeEnabled and token == generation then pcall(applyFpsObject, object) end
            end)
        end
        if fpsSettings.coreGui and host.StarterGui then
            -- Do not disable All, Health or the mobile touch controls.
            for _, kind in ipairs({Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack,
                Enum.CoreGuiType.Chat, Enum.CoreGuiType.EmotesMenu}) do
                pcall(function()
                    local value = host.StarterGui:GetCoreGuiEnabled(kind)
                    if type(value) == "boolean" then
                        coreGuiCache[kind] = value
                        host.StarterGui:SetCoreGuiEnabled(kind, false)
                    end
                end)
            end
        end
        if fpsSettings.scenery and host.TaskManager then
            local elapsed, cursor = 0, 1
            -- v139.1: one long lived array, cleared in place. Rebuilding it
            -- every second threw away the whole list (thousands of parts on a
            -- big map) and left it for the collector: a guaranteed hitch.
            local pending: {BasePart} = {}
            featureConnections.ImproveFPSDistance = host.TaskManager:Connect(function(dt)
                elapsed += dt
                if cursor > #pending then
                    if elapsed < 1 then return end
                    elapsed = 0
                    table.clear(pending)
                    for part in pairs(scenery) do
                        if part.Parent then table.insert(pending, part) else scenery[part] = nil end
                    end
                    cursor = 1
                end
                -- Bound work per frame instead of rescanning a huge map in
                -- one callback, which would defeat an FPS optimization.
                local last = math.min(#pending, cursor + 199)
                while cursor <= last do
                    if not fpsModeEnabled or token ~= generation then return end
                    pcall(updateScenery, pending[cursor])
                    cursor += 1
                end
            end)
        end
        task.spawn(function(): ()
            local scanned = 0
            for _, container in ipairs(containers) do
                if not fpsModeEnabled or token ~= generation then return end
                pcall(applyFpsObject, container)
                for _, object in ipairs(container:GetDescendants()) do
                    if not fpsModeEnabled or token ~= generation then return end
                    pcall(applyFpsObject, object)
                    scanned += 1
                    if scanned % 250 == 0 then task.wait() end
                end
            end
        end)
    end

    local function refreshFps(): ()
        if fpsModeEnabled then
            toggleImproveFps(true)
        end
    end

    ImproveFpsFeature = createUniversalFeature(
        "Improve FPS",
        "Apply only the selected reversible optimizations",
        26,
        toggleImproveFps,
        {categoryName = "World"}
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

    for _, definition in ipairs({
        {"Lowest render quality", "quality", "Requests render quality Level01 where the client permits it; restores the original level when OFF."},
        {"Simple lighting", "lighting", "Disables environment diffuse/specular reflections."},
        {"Disable local lights", "lights", "Turns off PointLight, SpotLight and SurfaceLight instances. May darken the map."},
        {"Simplify terrain", "terrain", "Disables terrain decoration, water waves and water reflections where writable. Physics is unchanged."},
        {"Disable post effects", "post", "Disables bloom, blur (including menu blur), depth of field, color correction and sun rays."},
        {"Simplify game UI", "guiEffects", "Disables game UI strokes, gradients and 3D viewport previews. Menu and touch controls are protected."},
        {"Hide world UI", "worldGui", "Hides floating labels and SurfaceGui displays; may hide game information."},
        {"Hide game UI", "gameGui", "Aggressive: hides game ScreenGuis, including HUD/objectives. Keeps this menu, chat and TouchGui."},
        {"Hide Roblox panels", "coreGui", "Hides player list, backpack, chat and emotes panel. Health and mobile movement remain available."},
        {"Low detail meshes", "geometry", "Requests Performance render fidelity for meshes/unions; does not change collisions."},
        {"Hide distant scenery", "scenery", "Aggressive: locally hides static map parts beyond 350 studs, updating periodically. May hide distant objectives; collisions remain."},
    }) do
        local key: string = definition[2]
        addToggleOption(ImproveFpsFeature, definition[1], false, function(value: boolean)
            fpsSettings[key] = value
            refreshFps()
        end, definition[3])
    end

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
