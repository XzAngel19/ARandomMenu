-- Client-side lighting, surface detail and atmosphere.
-- Weather adapts ShaderCloud/rbxts-weather's camera cells/roof checks (ISC),
-- with outdoor sampling and splashes informed by buildthomas/Rain (Apache-2.0).
-- Surface colour maps are CC0 ambientCG assets; they are not PBR normal maps.
-- Research, pinned sources and licences: docs/third-party/shaders/README.md.
local Module = {Name = "Shaders", PlaceId = 0, Initialized = false}
local card

-- The near grid keeps layered weather visible; a sparse outer ring extends it
-- across more of the rendered scene without populating an unbounded world.
-- Native particles are still camera-centred, not weather simulated map-wide.
-- Rate and lifetime are both budgeted: transparent overdraw costs GPU too.
-- Mobile/touch clients ask for fewer particles at creation. Per-emitter caps
-- documented by Roblox are 400/s desktop and 100/s mobile.
-- The local CC0 sprites remain primary, with public Roblox-hosted fallbacks.
local MAX_EMITTER_RATE: number = 320
local MAX_WEATHER_RATE: number = 2000
local MAX_MOBILE_WEATHER_RATE: number = 1000
local MAX_CELL_EMITTERS: number = 4
local FOG_ACTOR_LIMIT: number = 16 -- plus the local player
local FOG_SAMPLE_INTERVAL: number = 0.25
local FOG_WIND: Vector3 = Vector3.new(0.12, 0.02, 0.04)
local WEATHER_GRID: {any} = {}
do
    for _, offset: Vector3 in ipairs({
        Vector3.new(0, 0, 0),
        Vector3.new(-36, 0, -36), Vector3.new(0, 0, -36), Vector3.new(36, 0, -36),
        Vector3.new(-36, 0, 0), Vector3.new(36, 0, 0),
        Vector3.new(-36, 0, 36), Vector3.new(0, 0, 36), Vector3.new(36, 0, 36),
    }) do table.insert(WEATHER_GRID, {offset = offset, far = false}) end
    for _, x: number in ipairs({-112, 0, 112}) do
        for _, z: number in ipairs({-112, 0, 112}) do
            if x ~= 0 or z ~= 0 then table.insert(WEATHER_GRID, {offset = Vector3.new(x, 0, z), far = true}) end
        end
    end
end
local WEATHER = {
    Rain = {asset = "shaderRainTexture", fallback = "rbxassetid://1822883048",
        layers = {
            -- Streak layer: fast, thin, squashed along its own velocity.
            {rate = 110, mobileRate = 64, farRate = 28, mobileFarRate = 14, size = 1.15, speedMin = 62, speedMax = 80,
                lifetime = 0.85, transparency = 0.26, spread = 2, squash = -3.2,
                color = {205, 219, 235}, lightEmission = 0.10, lightInfluence = 0.85,
                acceleration = Vector3.new(2, -12, 0)},
            -- Close layer: shorter-lived drops near the camera make the fall
            -- read as dense without another cell or another part.
            {rate = 40, mobileRate = 0, size = 0.65, speedMin = 48, speedMax = 66,
                lifetime = 0.5, transparency = 0.18, spread = 4, squash = -2.4,
                color = {214, 226, 240}, lightEmission = 0.14, lightInfluence = 0.8,
                acceleration = Vector3.new(2, -10, 0)},
        }},
    Snow = {asset = "shaderSnowTexture", fallback = "rbxasset://textures/particles/smoke_main.dds",
        layers = {
            -- Slow, large, lit flakes. LightEmission keeps them visible in the
            -- dark maps (MM2 has night rounds) instead of grey-on-grey.
            {rate = 22, mobileRate = 14, farRate = 8, mobileFarRate = 4, size = 1.25, speedMin = 4.5, speedMax = 7,
                lifetime = 5, transparency = 0.12, spread = 28, spin = 45,
                color = {252, 253, 255}, lightEmission = 0.55, lightInfluence = 0.35,
                acceleration = Vector3.new(3, 0, 1.5)},
        }},
    -- Leaves stay larger and lit enough to be legible, but shorter lifetime and
    -- lower rates avoid retaining as many overlapping sprites as v177.
    ["Falling leaves"] = {asset = "shaderAutumnTexture", fallback = "rbxassetid://80805595237760",
        layers = {
            {rate = 8, mobileRate = 4, farRate = 3, mobileFarRate = 2, size = 1.6, speedMin = 3, speedMax = 5.5, lifetime = 6,
                transparency = 0.05, spread = 30, spin = 90,
                color = {255, 196, 120}, lightEmission = 0.4, lightInfluence = 0.55,
                acceleration = Vector3.new(3, 0, 2)},
        }},
}
local WEATHER_ORDER = {"Rain", "Snow", "Falling leaves"}
-- Roblox documents these ColorMap IDs for its base materials. They let a
-- compatible client try a fallback while local artwork is loading or absent;
-- actual rendering of either source is still client-dependent.
local SURFACE_STYLES = {
    concrete = {asset = "shaderConcreteTexture", fallback = "rbxassetid://9920484153", u = 12, v = 6},
    wood = {asset = "shaderWoodTexture", fallback = "rbxassetid://9920626778", u = 12, v = 12},
    brick = {asset = "shaderBrickTexture", fallback = "rbxassetid://9920482813", u = 12, v = 6},
    grass = {asset = "shaderGrassTexture", fallback = "rbxassetid://9920551868", u = 12, v = 12},
    marble = {asset = "shaderMarbleTexture", fallback = "rbxassetid://9439430596", u = 12, v = 12},
    -- v177: MM2-style maps are mostly stone, not Wood or Marble. These reuse the
    -- concrete/marble albedos with their own tiling (no new download): the point
    -- is coverage of the materials the maps actually use.
    stone = {asset = "shaderConcreteTexture", fallback = "rbxassetid://9920484153", u = 8, v = 4},
    sand = {asset = "shaderConcreteTexture", fallback = "rbxassetid://9920484153", u = 16, v = 8},
    ice = {asset = "shaderMarbleTexture", fallback = "rbxassetid://9439430596", u = 8, v = 8},
}
-- Built once with pcall: a client that lacks a newer Enum.Material must simply
-- not map it, not throw while scanning the map.
local MATERIAL_STYLES: {[any]: string} = {}
do
    local groups: {[string]: {string}} = {
        concrete = {"Concrete", "Asphalt", "Pavement"},
        stone = {"Cobblestone", "Slate", "Rock", "Basalt", "Sandstone", "Limestone", "Granite", "Pebble"},
        sand = {"Sand", "Ground", "Mud"},
        ice = {"Ice", "Glacier"},
        wood = {"Wood", "WoodPlanks"},
        brick = {"Brick"},
        grass = {"Grass", "LeafyGrass"},
        marble = {"Marble"},
    }
    for style: string, names: {string} in pairs(groups) do
        for _, name: string in ipairs(names) do
            local ok: boolean, value: any = pcall(function(): any
                return (Enum.Material :: any)[name]
            end)
            if ok and value ~= nil then MATERIAL_STYLES[value] = style end
        end
    end
end

function Module.init(context: any): any
    local host: any = context.host
    local lighting: Lighting = host.Lighting
    local world: Workspace = host.workspace
    local color: ColorCorrectionEffect? = nil
    local bloom: BloomEffect? = nil
    local rays: SunRaysEffect? = nil
    local lightOriginal: {[string]: any} = {}
    local lightApplied: {[string]: any} = {}
    local waterOriginal: any = nil
    local waterApplied: any = nil
    local waterTerrain: any = nil
    local cardEverEnabled: boolean = false

    local fogTarget: any = nil
    local fogOriginal: {[string]: any} = {}
    local fogApplied: {[string]: any} = {}
    local fogConnections: {any} = {}
    local fogPropertyConnections: {any} = {}
    local fogGeneration: number = 0
    local fogMutating: boolean = false
    local fogQueued: boolean = false

    local weatherFolder: Folder? = nil
    local weatherConnection: any = nil
    local weatherCells: {any} = {}
    local mistCells: {any} = {}
    local weatherGeneration: number = 0
    local weatherCompact: boolean = false
    local weatherRate: number = 0
    local fogMovingActors: number = 0

    local surfaceConnection: any = nil
    local surfaceAddedConnection: any = nil
    local surfaceRemovingConnection: any = nil
    local wakeSurfaceScan: ((string?) -> ())? = nil
    local retrySurface: ((any) -> ())? = nil
    local surfaceGeneration: number = 0
    local surfaceAssets: {[string]: any} = {}
    local surfaceTexturesOn: boolean = false
    local surfaceRecords: {[Instance]: any} = {}
    local surfaceFaceOwners: {[Instance]: any} = {}
    local surfaceFaceCount: number = 0
    local textureCount: number = 0
    local reflectionCount: number = 0
    local textureWarning: boolean = false
    -- v177 diagnostics: "it does nothing" needs numbers, not guesses.
    local surfaceSeen: number = 0
    local surfaceReserved: number = 0
    local surfaceNoStyle: number = 0
    local surfacePasses: number = 0
    local surfaceQueueDrops: number = 0
    -- The world is visited incrementally, not restricted to the player's
    -- neighbourhood. Caps bound retained instances on unusually large maps.
    local MAX_TEXTURES: number = 600
    local MAX_REFLECTIONS: number = 1200
    local MAX_SURFACE_JOBS: number = 4
    local MAX_TREE_NODES: number = 20
    local MAX_PENDING: number = 2048
    local MAX_FACE_OWNERS: number = 2048

    local function enabled(name: string): boolean
        return card ~= nil and card.Enabled and card.Options[name] ~= nil
            and card.Options[name].Value == true
    end

    local function compactWeather(): boolean
        -- Touch devices with an attached keyboard may not be labelled isMobile
        -- by the UI; give them the safer particle budget as well. A touch PC
        -- may get the conservative profile, not a desktop-sized allocation.
        local touch: boolean = false
        pcall(function(): () touch = host.UserInputService ~= nil and host.UserInputService.TouchEnabled == true end)
        return touch or (host.state ~= nil and host.state.isMobile == true)
    end

    -- Executor registration can return a URI even when Roblox cannot load the
    -- image. Keep the built-in/Roblox fallback unless the image fetch reports
    -- success. This runs only in the existing asynchronous asset jobs; even a
    -- successful preload does not prove that a particular device drew pixels.
    local function imageAvailable(asset: string): boolean
        local ok: boolean, provider: any = pcall(function(): any
            return host.ContentProvider or game:GetService("ContentProvider")
        end)
        if not ok or not provider then return false end
        local probe: any = nil
        local seenSuccess, seenFailure = false, false
        local loaded: boolean = pcall(function(): ()
            probe = Instance.new("ImageLabel")
            probe.Image = asset
            provider:PreloadAsync({probe}, function(_id: any, status: any): ()
                if status == Enum.AssetFetchStatus.Success then
                    seenSuccess = true
                else
                    seenFailure = true
                end
            end)
        end)
        if probe then pcall(function(): () probe:Destroy() end) end
        return loaded and seenSuccess and not seenFailure
    end

    -- Include non-weather effects as well, with a compact status line.
    local STATUS_LABELS: {{option: string, label: string}} = {
        {option = "Surface textures", label = "Surfaces"},
        {option = "Glass reflections", label = "Glass"},
        {option = "Wet surfaces", label = "Wet"},
        {option = "Water reflections", label = "Water"},
        {option = "Fog", label = "Fog"},
        {option = "Rain", label = "Rain"},
        {option = "Snow", label = "Snow"},
        {option = "Falling leaves", label = "Leaves"},
        {option = "Dust motes", label = "Dust"},
    }
    local function updateStatus(): ()
        if not card or not card.Enabled then return end
        local parts: {string} = {}
        local shown: number = 0
        for _, entry: {option: string, label: string} in ipairs(STATUS_LABELS) do
            if enabled(entry.option) then
                shown += 1
                if shown <= 4 then table.insert(parts, entry.label) end
            end
        end
        if shown > #parts then table.insert(parts, "+" .. tostring(shown - #parts)) end
        card:SetStatus(if #parts == 0 then nil else table.concat(parts, " · "))
    end

    local function restoreProperties(object: any, original: {[string]: any}, applied: {[string]: any}): ()
        for property: string, value: any in pairs(applied) do
            pcall(function(): ()
                -- A later change from the game wins over our old snapshot.
                if object[property] == value then object[property] = original[property] end
            end)
        end
    end

    local function applyLighting(): ()
        local function setMinimum(property: string, minimum: number): ()
            pcall(function(): ()
                local old: number = (lighting :: any)[property]
                local value: number = math.max(old, minimum)
                lightOriginal[property] = old
                ;(lighting :: any)[property] = value
                lightApplied[property] = (lighting :: any)[property]
            end)
        end
        -- These engine properties affect material/sky lighting even when a
        -- place's own post effects compete with our colour correction.
        -- Do not raise diffuse light or exposure: both can wash out an
        -- already-bright floor even with the reflection itself switched off.
        setMinimum("EnvironmentSpecularScale", 0.65)
        setMinimum("ShadowSoftness", 0.35)
        -- Do not force GlobalShadows on: maps deliberately disable them and
        -- forcing dynamic shadows can be expensive, especially on phones.
    end

    local function releaseWater(): ()
        local terrain: any = waterTerrain
        local original: any = waterOriginal
        local applied: any = waterApplied
        waterTerrain, waterOriginal, waterApplied = nil, nil, nil
        if terrain and applied ~= nil then
            pcall(function(): ()
                if terrain.WaterReflectance == applied then terrain.WaterReflectance = original end
            end)
        end
    end

    local waterWarned: boolean = false
    local function refreshWater(): ()
        releaseWater()
        if not enabled("Water reflections") then return end
        local applied: boolean = false
        pcall(function(): ()
            local terrain: any = world:FindFirstChildOfClass("Terrain")
            if not terrain then return end
            local old: number = terrain.WaterReflectance
            if terrain.WaterReflectance == nil then return end
            terrain.WaterReflectance = math.max(old, 0.75)
            waterTerrain, waterOriginal, waterApplied = terrain, old, terrain.WaterReflectance
            applied = true
        end)
        -- A place without Terrain cannot show water at all. Saying so once is
        -- better than a checked box that never does anything (MM2 has no water).
        if not applied and not waterWarned then
            waterWarned = true
            card:Notify("Water reflections needs Terrain water; this place has none")
        end
        updateStatus()
    end

    local function releaseFog(): ()
        fogGeneration += 1
        for _, connection: any in ipairs(fogPropertyConnections) do
            pcall(function(): () connection:Disconnect() end)
        end
        fogPropertyConnections = {}
        local target: any = fogTarget
        local original, applied = fogOriginal, fogApplied
        fogTarget, fogOriginal, fogApplied = nil, {}, {}
        if target then restoreProperties(target, original, applied) end
    end

    local function fogValue(target: any, property: string, original: any): any
        if target == lighting then
            -- v176: the previous values (start 20, end 180) were readable but
            -- soft; the engine's FogEnd is what a place without an Atmosphere
            -- actually draws, so pull the wall in and keep a light grey-blue
            -- tint instead of the place's original colour.
            if property == "FogStart" then return math.min(original, 8) end
            if property == "FogEnd" then return math.min(original, 110) end
            return Color3.fromRGB(176, 188, 196)
        end
        -- Atmosphere supersedes FogEnd. Density 0-1 and Haze 0-10 are the
        -- documented ranges (create.roblox.com/docs/environment/atmosphere);
        -- 0,45/1,25 sat below a visible haze.
        if property == "Density" then return math.max(original, 0.58) end
        return math.max(original, 4.5) -- Haze
    end

    local function refreshFog(): ()
        if fogMutating then return end
        fogMutating = true
        if not enabled("Fog") then
            releaseFog()
            fogMutating = false
            updateStatus()
            return
        end
        local atmosphere: Atmosphere? = nil
        for _, child: Instance in ipairs(lighting:GetChildren()) do
            if child:IsA("Atmosphere") then atmosphere = child :: Atmosphere; break end
        end
        -- Atmosphere supersedes FogEnd. Never insert a duplicate or delete a
        -- game-owned object: switch to the actual engine path in use instead.
        local target: any = atmosphere or lighting
        if fogTarget == target then
            fogMutating = false
            updateStatus()
            return
        end
        releaseFog()
        fogTarget = target
        local generation: number = fogGeneration
        local properties: {string} = if atmosphere then {"Density", "Haze"} else {"FogStart", "FogEnd", "FogColor"}
        for _, property: string in ipairs(properties) do
            local applied: boolean = pcall(function(): ()
                local old: any = target[property]
                fogOriginal[property] = old
                target[property] = fogValue(target, property, old)
                fogApplied[property] = target[property]
            end)
            if applied then
                local pending: boolean = false
                local observed: boolean, connection: any = pcall(function(): any
                    return target:GetPropertyChangedSignal(property):Connect(function(): ()
                        if fogMutating or generation ~= fogGeneration or fogTarget ~= target or not enabled("Fog") then return end
                        local read: boolean, current: any = pcall(function(): any return target[property] end)
                        if not read or current == fogApplied[property] then return end
                        -- Preserve the latest game value, including changes
                        -- made shortly before disabling or replacing the fog.
                        fogOriginal[property] = current
                        if pending then return end
                        pending = true
                        task.defer(function(): ()
                            pending = false
                            if generation ~= fogGeneration or fogTarget ~= target or not enabled("Fog") then return end
                            pcall(function(): ()
                                local value: any = target[property]
                                if value ~= fogApplied[property] then fogOriginal[property] = value end
                                fogMutating = true
                                local ok: boolean = pcall(function(): ()
                                    target[property] = fogValue(target, property, fogOriginal[property])
                                    fogApplied[property] = target[property]
                                end)
                                fogMutating = false
                                if not ok then return end
                            end)
                            fogMutating = false
                        end)
                    end)
                end)
                if observed and connection then table.insert(fogPropertyConnections, connection) end
            end
        end
        fogMutating = false
        updateStatus()
    end

    local function watchAtmosphere(object: Instance): ()
        if not object:IsA("Atmosphere") or fogMutating or fogQueued or not enabled("Fog") then return end
        fogQueued = true
        task.defer(function(): ()
            fogQueued = false
            if card and card.Enabled then refreshFog() end
        end)
    end

    local function stopWeather(): ()
        weatherGeneration += 1
        if weatherConnection then
            pcall(function(): () weatherConnection:Disconnect() end)
            weatherConnection = nil
        end
        if weatherFolder then
            pcall(function(): () weatherFolder:Destroy() end)
            weatherFolder = nil
        end
        weatherCells, mistCells = {}, {}
        weatherRate, fogMovingActors, weatherCompact = 0, 0, false
    end

    local function fadedTransparency(value: number, fadeIn: number, fadeOut: number): any
        local ok, sequence = pcall(function(): any
            return NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(fadeIn, value),
                NumberSequenceKeypoint.new(fadeOut, value), NumberSequenceKeypoint.new(1, 1),
            })
        end)
        return if ok then sequence else NumberSequence.new(value)
    end

    local function changeWeather(): ()
        stopWeather()
        if not card or not card.Enabled then return end
        local kinds: {string} = {}
        for _, name: string in ipairs(WEATHER_ORDER) do
            if enabled(name) then table.insert(kinds, name) end
        end
        local dustEnabled: boolean = enabled("Dust motes")
        local mistEnabled: boolean = enabled("Fog")
        if #kinds == 0 and not dustEnabled and not mistEnabled then updateStatus(); return end
        local generation: number = weatherGeneration
        local mobile: boolean = compactWeather()
        weatherCompact = mobile
        local ok: boolean, failure: any = pcall(function(): ()
            local folder: Folder = Instance.new("Folder")
            weatherFolder = folder
            folder.Name = "ARMShaderWeather"
            folder.Parent = world
            local textures: {[string]: {any}} = {}
            local transparencyByLayer: {[string]: any} = {}
            local failedStyles: {[string]: boolean} = {}
            local styleCounts: {[string]: number} = {}
            local particleCount: number = 0
            local function remember(asset: string, emitter: ParticleEmitter): ()
                if not textures[asset] then textures[asset] = {} end
                table.insert(textures[asset], emitter)
                particleCount += 1
            end
            local function particleFailure(name: string, failure: any): ()
                if failedStyles[name] then return end
                failedStyles[name] = true
                warn("[Shaders:" .. name .. "] " .. tostring(failure))
                card:Notify(name .. " particles unavailable; other effects remain active")
            end
            local function cellPart(name: string, size: Vector3): Part
                local part: Part = Instance.new("Part")
                local created: boolean, failure: any = pcall(function(): ()
                    part.Name, part.Anchored = name, true
                    part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
                    part.CastShadow, part.Transparency, part.Size = false, 1, size
                    part.Parent = folder
                end)
                if not created then part:Destroy(); error(failure, 0) end
                return part
            end
            local function extraEmitter(name: string, label: string, size: Vector3, asset: string, configure: (any) -> ()): (Part?, ParticleEmitter?)
                local part: any, emitter: any = nil, nil
                local created: boolean, failure: any = pcall(function(): ()
                    part = cellPart(name, size)
                    emitter = Instance.new("ParticleEmitter")
                    configure(emitter)
                    emitter.Parent = part
                end)
                if not created then
                    if emitter then pcall(function(): () emitter:Destroy() end) end
                    if part then pcall(function(): () part:Destroy() end) end
                    particleFailure(label, failure)
                    return nil, nil
                end
                remember(asset, emitter)
                return part, emitter
            end
            if #kinds > 0 then
                -- Nine 40-stud near cells plus eight sparse 112-stud outer
                -- cells cover roughly 336 studs across the visible scene. The
                -- ring is still bounded and follows the camera; this is not an
                -- unlimited global weather simulation. Each cell checks roofs.
                for _, spec: any in ipairs(WEATHER_GRID) do
                    local offset: Vector3 = spec.offset
                    local width: number = if spec.far then 112 else 40
                    local part: Part = cellPart("WeatherCell", Vector3.new(width, 0.2, width))
                    local emitters: {ParticleEmitter} = {}
                    for _, name: string in ipairs(kinds) do
                        local style: any = WEATHER[name]
                        for index, layer: any in ipairs(style.layers) do
                            if #emitters < MAX_CELL_EMITTERS then
                                local rate: number
                                if spec.far then
                                    rate = if mobile then layer.mobileFarRate or 0 else layer.farRate or 0
                                else
                                    rate = if mobile then layer.mobileRate or 0 else layer.rate
                                end
                                -- A mobile client is capped at 100 particles/s per
                                -- emitter; asking for more only wastes a write.
                                rate = math.min(rate, MAX_EMITTER_RATE)
                                if mobile then rate = math.min(rate, 100) end
                                if rate > 0 then
                                    local emitter: any = nil
                                    local created: boolean, failure: any = pcall(function(): ()
                                        emitter = Instance.new("ParticleEmitter")
                                        emitter.Name = if index == 1 then name else name .. " " .. index
                                        emitter.Enabled, emitter.Texture = false, style.fallback
                                        -- Newer particle properties are optional: a
                                        -- client lacking them should still draw the
                                        -- basic emitter.
                                        pcall(function(): ()
                                            emitter.Shape, emitter.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
                                        end)
                                        emitter.EmissionDirection = Enum.NormalId.Bottom
                                        pcall(function(): ()
                                            emitter.Orientation = if name == "Rain" then Enum.ParticleOrientation.VelocityParallel
                                                else Enum.ParticleOrientation.FacingCamera
                                        end)
                                        emitter.Rate, emitter.Size = rate, NumberSequence.new(layer.size)
                                        emitter.Speed = NumberRange.new(layer.speedMin, layer.speedMax)
                                        emitter.Lifetime = NumberRange.new(layer.lifetime)
                                        local key: string = name .. ":" .. tostring(index)
                                        if not transparencyByLayer[key] then
                                            transparencyByLayer[key] = if name == "Rain" then NumberSequence.new(layer.transparency)
                                                else fadedTransparency(layer.transparency, 0.1, 0.85)
                                        end
                                        emitter.Transparency = transparencyByLayer[key]
                                        emitter.SpreadAngle = Vector2.new(layer.spread, layer.spread)
                                        emitter.LightInfluence = layer.lightInfluence or 0.8
                                        emitter.LightEmission = layer.lightEmission or 0.05
                                        pcall(function(): () emitter.Acceleration = layer.acceleration end)
                                        if name == "Rain" then
                                            -- Roblox documents negative Squash for
                                            -- VelocityParallel: it stretches the
                                            -- sprite along its travel direction.
                                            pcall(function(): () emitter.Squash = NumberSequence.new(layer.squash or -3) end)
                                        else
                                            local spin: number = layer.spin or 0
                                            if spin > 0 then
                                                emitter.Rotation = NumberRange.new(0, 360)
                                                emitter.RotSpeed = NumberRange.new(-spin, spin)
                                            end
                                        end
                                        local tint: {number} = layer.color
                                        emitter.Color = ColorSequence.new(Color3.fromRGB(tint[1], tint[2], tint[3]))
                                        emitter.Parent = part
                                    end)
                                    if created then
                                        table.insert(emitters, emitter)
                                        styleCounts[name] = (styleCounts[name] or 0) + 1
                                        remember(style.asset, emitter)
                                    else
                                        if emitter then pcall(function(): () emitter:Destroy() end) end
                                        particleFailure(name, failure)
                                    end
                                end
                            end
                        end
                    end
                    if #emitters > 0 then
                        table.insert(weatherCells, {part = part, emitters = emitters, offset = offset, far = spec.far})
                    else
                        part:Destroy()
                    end
                end
            end
            local dustPart: Part? = nil
            local dust: ParticleEmitter? = nil
            if dustEnabled then
                -- v177: 12 motes of 0,35 studs at 0,35 transparency could not be
                -- seen. Bigger, brighter, longer-lived and in a wider box so the
                -- motes drift past the camera instead of sitting in one spot.
                dustPart, dust = extraEmitter("DustCell", "Dust motes", Vector3.new(26, 8, 26), "shaderSnowTexture", function(emitter: any): ()
                    emitter.Name, emitter.Enabled = "Dust motes", false
                    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
                    pcall(function(): () emitter.Shape, emitter.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume end)
                    emitter.EmissionDirection = Enum.NormalId.Top
                    pcall(function(): () emitter.Orientation = Enum.ParticleOrientation.FacingCamera end)
                    emitter.Rate, emitter.Size, emitter.Speed = if mobile then 12 else 20, NumberSequence.new(0.55), NumberRange.new(0.15, 0.5)
                    emitter.Lifetime, emitter.Transparency = NumberRange.new(5), fadedTransparency(0.26, 0.15, 0.8)
                    emitter.Color, emitter.LightEmission, emitter.LightInfluence = ColorSequence.new(Color3.fromRGB(255, 238, 200)), 0.5, 0.35
                    pcall(function(): () emitter.Acceleration = Vector3.new(0.15, 0.05, 0.1) end)
                end)
            end
            if mistEnabled then
                -- Near patches plus a sparse outer ring let native Acceleration
                -- move already-live particles near local and remote characters.
                -- They supplement global Lighting fog; they are not a physical
                -- fluid and cannot carve a hole in Roblox's distance haze.
                for _, spec: any in ipairs(WEATHER_GRID) do
                    local offset: Vector3 = spec.offset
                    local width: number = if spec.far then 112 else 40
                    local part: Part?, emitter: ParticleEmitter? = extraEmitter(
                        "FogCell", "Fog mist", Vector3.new(width, 12, width), "shaderSnowTexture", function(mist: any): ()
                            mist.Name, mist.Enabled = "Fog mist", false
                            mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
                            pcall(function(): () mist.Shape, mist.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume end)
                            mist.EmissionDirection = Enum.NormalId.Top
                            pcall(function(): () mist.Orientation = Enum.ParticleOrientation.FacingCamera end)
                            mist.Rate, mist.Size, mist.Speed = if mobile or spec.far then 1 else 2, NumberSequence.new(18), NumberRange.new(0.1, 0.4)
                            mist.Lifetime = NumberRange.new(4.5, 5.5)
                            -- Fade in/out rather than popping when a cell moves.
                            mist.Transparency = fadedTransparency(0.78, 0.2, 0.75)
                            mist.Color, mist.LightEmission, mist.LightInfluence = ColorSequence.new(Color3.fromRGB(208, 218, 226)), 0.12, 0.9
                            mist.Rotation, mist.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-4, 4)
                            pcall(function(): () mist.Acceleration = FOG_WIND end)
                        end)
                    if part and emitter then
                        table.insert(mistCells, {part = part, emitter = emitter, offset = offset, far = spec.far, force = FOG_WIND})
                    end
                end
            end
            local splashPart: Part? = nil
            local splash: ParticleEmitter? = nil
            if (styleCounts.Rain or 0) > 0 then
                splashPart, splash = extraEmitter("RainSplashCell", "Rain splashes", Vector3.new(0.2, 0.2, 0.2), "shaderSnowTexture", function(emitter: any): ()
                    emitter.Name, emitter.Enabled, emitter.Rate = "Rain splashes", false, 0
                    emitter.Texture = "rbxassetid://1822856633"
                    emitter.EmissionDirection = Enum.NormalId.Top
                    pcall(function(): () emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular end)
                    -- v176: bigger and longer-lived than the old 1,2/0,25 pair,
                    -- so a ground hit is actually readable as a splash ring.
                    emitter.Size, emitter.Speed = NumberSequence.new(2.2), NumberRange.new(0.1, 0.2)
                    emitter.Lifetime, emitter.Transparency = NumberRange.new(0.28, 0.36), NumberSequence.new(0.45)
                    emitter.Color, emitter.LightInfluence = ColorSequence.new(Color3.fromRGB(220, 229, 235)), 0.7
                    emitter.LightEmission = 0.15
                end)
            end
            -- One shared budget includes every automatic emitter, including
            -- mist. Splashes are explicit bounded Emit calls and not Rate.
            local function clampWeatherBudget(): boolean
                local emitters: {any} = {}
                for _, cellData: any in ipairs(weatherCells) do
                    for _, emitter: ParticleEmitter in ipairs(cellData.emitters) do table.insert(emitters, emitter) end
                end
                if dust then table.insert(emitters, dust) end
                for _, cell: any in ipairs(mistCells) do table.insert(emitters, cell.emitter) end
                local total: number = 0
                for _, emitter: any in ipairs(emitters) do total += emitter.Rate end
                local budget: number = if mobile then MAX_MOBILE_WEATHER_RATE else MAX_WEATHER_RATE
                if total <= budget or total <= 0 then weatherRate = total; return false end
                local scale: number = budget / total
                weatherRate = 0
                for _, emitter: any in ipairs(emitters) do
                    pcall(function(): () emitter.Rate = math.max(0, math.floor(emitter.Rate * scale)) end)
                    weatherRate += emitter.Rate
                end
                return true
            end
            if clampWeatherBudget() then
                card:Notify("Weather density capped to the local particle budget")
            end
            if particleCount == 0 then stopWeather(); return end
            local paramsOk: boolean, params: any = pcall(function(): any
                local value: RaycastParams = RaycastParams.new()
                value.FilterType, value.IgnoreWater = Enum.RaycastFilterType.Exclude, true
                -- Only collidable geometry is a roof. Maps are full of invisible
                -- or non-collidable decoration above the camera, and treating it
                -- as a ceiling was hiding the rain for entire rounds.
                pcall(function(): () value.RespectCanCollide = true end)
                return value
            end)
            if not paramsOk then params = nil end
            local previousCharacter: Model? = nil
            local moveElapsed, roofElapsed, roofIndex = 0, 0.15, 0
            local fogElapsed: number = FOG_SAMPLE_INTERVAL
            local lastFocus: Vector3? = nil
            local actorCursor, actorEpoch = 0, 0
            local actorSamples: {[any]: any} = {}
            local shelterWarned: boolean = false

            local function updateMistForActors(focus: Vector3): ()
                -- Sampling is capped and round-robin, not one connection or
                -- emitter per player. Velocity also detects remote characters;
                -- positional deltas cover clients that move roots via CFrame.
                actorEpoch += 1
                local movers: {any} = {}
                local function sample(player: any): ()
                    if not player then return end
                    pcall(function(): ()
                        local character: any = player.Character
                        if not character then actorSamples[player] = nil; return end
                        local root: any = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
                        if not root or not root:IsA("BasePart") then actorSamples[player] = nil; return end
                        local position: Vector3 = root.Position
                        local old: any = actorSamples[player]
                        actorSamples[player] = {position = position, character = character, epoch = actorEpoch}
                        local vx, vz = 0, 0
                        pcall(function(): ()
                            local velocity: Vector3 = root.AssemblyLinearVelocity
                            vx, vz = velocity.X, velocity.Z
                        end)
                        local speed: number = math.sqrt(vx * vx + vz * vz)
                        if speed < 1.25 and old and old.character == character then
                            vx, vz = position.X - old.position.X, position.Z - old.position.Z
                            speed = math.sqrt(vx * vx + vz * vz)
                            -- About one stud/s at the normal sampling interval.
                            if speed < 0.25 then return end
                        elseif speed < 1.25 then
                            return
                        end
                        local dx, dz = position.X - focus.X, position.Z - focus.Z
                        if dx * dx + dz * dz > 240 * 240 or math.abs(position.Y - focus.Y) > 40 then return end
                        table.insert(movers, {position = position, x = vx / speed, z = vz / speed})
                    end)
                end
                sample(host.LocalPlayer)
                local ok, players = pcall(function(): any
                    return if host.Players then host.Players:GetPlayers() else {}
                end)
                if ok and type(players) == "table" and #players > 0 then
                    local count: number = math.min(#players, FOG_ACTOR_LIMIT)
                    for i = 1, count do
                        local player: any = players[(actorCursor + i - 1) % #players + 1]
                        if player ~= host.LocalPlayer then sample(player) end
                    end
                    actorCursor = (actorCursor + count) % #players
                end
                if actorEpoch % 16 == 0 then
                    for player: any, data: any in pairs(actorSamples) do
                        if actorEpoch - data.epoch > 16 then actorSamples[player] = nil end
                    end
                end
                fogMovingActors = #movers
                for _, cell: any in ipairs(mistCells) do
                    local pos: Vector3 = cell.part.Position
                    local closest: any = nil
                    local radius: number = if cell.far then 80 else 38
                    local best: number = radius * radius
                    local bestX, bestZ = 0, 0
                    for _, mover: any in ipairs(movers) do
                        local dx, dz = pos.X - mover.position.X, pos.Z - mover.position.Z
                        local distance: number = dx * dx + dz * dz
                        if distance < best and math.abs(pos.Y - mover.position.Y) <= 24 then
                            closest, best, bestX, bestZ = mover, distance, dx, dz
                        end
                    end
                    local force: Vector3 = FOG_WIND
                    if closest then
                        local distance: number = math.sqrt(best)
                        local ux, uz = closest.x, closest.z
                        if distance >= 1 then ux, uz = bestX / distance, bestZ / distance end
                        local strength: number = 2.4 * (1 - math.min(distance / radius, 1))
                        force = FOG_WIND + Vector3.new(ux * strength, 0.04, uz * strength)
                    end
                    local previous: Vector3 = cell.force
                    local dx, dy, dz = force.X - previous.X, force.Y - previous.Y, force.Z - previous.Z
                    if dx * dx + dy * dy + dz * dz > 0.04 then
                        local changed: boolean = pcall(function(): () cell.emitter.Acceleration = force end)
                        if changed then cell.force = force end
                    end
                end
            end

            local function updateWeather(deltaTime: number): ()
                moveElapsed += math.clamp(deltaTime, 0, 0.25)
                if moveElapsed < 0.05 then return end
                local elapsed: number = moveElapsed
                moveElapsed = 0
                local camera: Camera? = world.CurrentCamera
                if not camera then
                    lastFocus, fogMovingActors = nil, 0
                    for _, cell: any in ipairs(weatherCells) do
                        -- Force a fresh shelter decision after camera recovery.
                        cell.applied = nil
                        for _, emitter: ParticleEmitter in ipairs(cell.emitters) do
                            if emitter.Enabled then emitter.Enabled = false end
                        end
                    end
                    if dust and dust.Enabled then dust.Enabled = false end
                    for _, cell: any in ipairs(mistCells) do
                        if cell.emitter.Enabled then cell.emitter.Enabled = false end
                    end
                    return
                end
                local focus: Vector3 = camera.CFrame.Position
                -- v175 switched every emitter off on each camera move and
                -- re-enabled one cell per 0,15 s poll, so walking showed rain in
                -- bursts or not at all while moving. Keep the last known
                -- visibility: the staggered sky test corrects one cell per
                -- 0,15 s ray (bounded), and the cells follow the camera below.
                local character: Model? = host.LocalPlayer and host.LocalPlayer.Character
                if params and #weatherCells > 0 and (character ~= previousCharacter or roofIndex == 0) then
                    previousCharacter = character
                    local excluded: {Instance} = {folder}
                    if character then table.insert(excluded, character) end
                    params.FilterDescendantsInstances = excluded
                end
                local moved: boolean = true
                if lastFocus then
                    local dx, dy, dz = focus.X - lastFocus.X, focus.Y - lastFocus.Y, focus.Z - lastFocus.Z
                    moved = dx * dx + dy * dy + dz * dz >= 6.25
                end
                if moved then
                    for _, cell: any in ipairs(weatherCells) do
                        cell.part.Position = focus + cell.offset + Vector3.new(0, 20, 0)
                    end
                    if dustPart then dustPart.Position = focus end
                    for _, cell: any in ipairs(mistCells) do
                        cell.part.Position = focus + cell.offset + Vector3.new(0, -2, 0)
                    end
                    lastFocus = focus
                end
                if dust and not dust.Enabled then dust.Enabled = true end
                for _, cell: any in ipairs(mistCells) do
                    if not cell.emitter.Enabled then cell.emitter.Enabled = true end
                end
                if #mistCells > 0 then
                    fogElapsed += elapsed
                    if fogElapsed >= FOG_SAMPLE_INTERVAL then
                        fogElapsed = 0
                        updateMistForActors(focus)
                    end
                end
                if #weatherCells == 0 then return end
                if not params then
                    for _, cell: any in ipairs(weatherCells) do
                        cell.applied = false
                        for _, emitter: ParticleEmitter in ipairs(cell.emitters) do
                            if not emitter.Enabled then emitter.Enabled = true end
                        end
                    end
                    if not shelterWarned then
                        shelterWarned = true
                        card:Notify("Weather shelter checks unavailable; particles may pass through roofs")
                    end
                    return
                end
                roofElapsed += elapsed
                if roofElapsed < 0.15 then return end
                roofElapsed = 0
                roofIndex = roofIndex % #weatherCells + 1
                local cell: any = weatherCells[roofIndex]
                local castOk: boolean, hit: any = pcall(function(): any
                    return world:Raycast(focus + cell.offset, Vector3.new(0, 150, 0), params)
                end)
                -- A denied ray is unknown, not evidence of a roof. Keep the
                -- weather visible, report the trade-off once and avoid splash
                -- casts until shelter checks are available again.
                local covered: boolean = castOk and hit ~= nil
                if not castOk and not shelterWarned then
                    shelterWarned = true
                    card:Notify("Weather shelter checks unavailable; particles may pass through roofs")
                end
                if castOk and hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.Transparency >= 0.95 then
                    covered = false
                end
                -- Write Enabled only when a cell changes state: the old code
                -- rewrote every emitter of the sampled cell on each poll, and a
                -- write to Enabled restarts the emitter's particle budget.
                if cell.applied ~= covered then
                    cell.applied = covered
                    for _, emitter: ParticleEmitter in ipairs(cell.emitters) do emitter.Enabled = not covered end
                end
                -- One short ground sample per open cell produces inexpensive
                -- local splashes; it does not run for snow or while sheltered.
                if castOk and not covered and splashPart and splash then
                    local groundOk: boolean, ground: any = pcall(function(): any
                        return world:Raycast(focus + cell.offset + Vector3.new(0, 20, 0), Vector3.new(0, -100, 0), params)
                    end)
                    if groundOk and ground and ground.Position and ground.Normal then
                        splashPart.Position = ground.Position + ground.Normal * 0.05
                        pcall(function(): () (splash :: ParticleEmitter):Emit(2) end)
                    end
                end
            end
            weatherConnection = host.TaskManager:Connect(function(deltaTime: number): ()
                local updated: boolean, reason: any = pcall(updateWeather, deltaTime)
                if not updated then
                    warn("[Shaders:Weather] " .. tostring(reason))
                    stopWeather()
                    if card and card.Enabled then card:Notify("Weather stopped on this client; other effects remain active") end
                end
            end, nil, "Shaders weather")
            local imageWarned: boolean = false
            for assetKey: string, emitters: {any} in pairs(textures) do
                task.spawn(function(): ()
                    local state: any = host.state
                    if not state or type(state.resolveAsset) ~= "function" then return end
                    local resolved: boolean, asset: any = pcall(state.resolveAsset, assetKey)
                    if generation ~= weatherGeneration or not card or not card.Enabled then return end
                    local usable: boolean = resolved and type(asset) == "string" and asset ~= "" and imageAvailable(asset)
                    if generation ~= weatherGeneration or not card or not card.Enabled then return end
                    if not usable then
                        if not imageWarned then
                            imageWarned = true
                            card:Notify("Custom weather image unavailable; using particle fallback")
                        end
                        return
                    end
                    for _, emitter: ParticleEmitter in ipairs(emitters) do
                        pcall(function(): () emitter.Texture = asset end)
                    end
                end)
            end
        end)
        if not ok then
            stopWeather()
            warn("[Shaders] Weather unavailable: " .. tostring(failure))
            card:Notify("Weather unavailable; lighting is still active")
        end
        updateStatus()
    end

    local function removeTextures(record: any): ()
        if not record.textures then return end
        for _, texture: any in ipairs(record.textures) do
            pcall(function(): () texture:Destroy() end)
            textureCount -= 1
        end
        record.textures, record.style, record.faces, record.asset = nil, nil, nil, nil
    end

    local function removeReflection(part: any, record: any): ()
        if record.reflectionApplied == nil then return end
        pcall(function(): ()
            if part.Reflectance == record.reflectionApplied then part.Reflectance = record.reflectionOriginal end
        end)
        record.reflectionOriginal, record.reflectionApplied, record.reflectionTarget = nil, nil, nil
        reflectionCount -= 1
    end

    local function removeSurface(part: any, record: any): ()
        removeTextures(record)
        removeReflection(part, record)
        surfaceRecords[part] = nil
    end

    local function stopSurfaces(): ()
        surfaceGeneration += 1
        if surfaceConnection then
            pcall(function(): () surfaceConnection:Disconnect() end)
            surfaceConnection = nil
        end
        if surfaceAddedConnection then
            pcall(function(): () surfaceAddedConnection:Disconnect() end)
            surfaceAddedConnection = nil
        end
        if surfaceRemovingConnection then
            pcall(function(): () surfaceRemovingConnection:Disconnect() end)
            surfaceRemovingConnection = nil
        end
        wakeSurfaceScan, retrySurface = nil, nil
        for part: any, record: any in pairs(surfaceRecords) do removeSurface(part, record) end
        surfaceRecords, surfaceAssets, surfaceFaceOwners = {}, {}, {}
        textureCount, reflectionCount, surfaceFaceCount, textureWarning, surfaceTexturesOn = 0, 0, 0, false, false
    end

    local function safePart(part: any): boolean
        if not part:IsA("BasePart") or part.Transparency >= 0.95 then return false end
        local parent: any = part.Parent
        while parent and parent ~= world do
            if parent == world.CurrentCamera or parent == weatherFolder
                or (host.LocalPlayer and parent == host.LocalPlayer.Character)
                or parent:IsA("Tool") or parent:IsA("Accessory") then return false end
            if parent:IsA("Model") and (parent:FindFirstChildOfClass("Humanoid")
                or parent:FindFirstChildOfClass("AnimationController")) then return false end
            parent = parent.Parent
        end
        return parent == world
    end

    local function floorShape(part: any): boolean
        local s: Vector3 = part.Size
        return s.X >= 8 and s.Z >= 8 and s.Y <= math.min(s.X, s.Z) * 0.5
            and part.CFrame.UpVector.Y >= 0.87
    end

    local function textureStyle(part: any): (string?, {any}?)
        -- Roblox's face Texture supports anchored block Parts and CSG unions.
        -- Keep meshes, variants and moving objects untouched; a colour image
        -- is not a normal/roughness PBR map.
        local block: boolean = part.ClassName == "Part" and part.Shape == Enum.PartType.Block
        if (not block and part.ClassName ~= "UnionOperation") or not part.Anchored
            or part.Transparency > 0.05 or part.MaterialVariant ~= "" then return nil, nil end
        local material: any = part.Material
        local style: string? = MATERIAL_STYLES[material]
        if not style and (material == Enum.Material.Plastic or material == Enum.Material.SmoothPlastic)
            and floorShape(part) and part.Size.X >= 12 and part.Size.Z >= 12 and part.Size.Y <= 3 then
            -- Many simple maps use plain plastic for their floors.
            style = "concrete"
        end
        if not style then return nil, nil end
        if floorShape(part) then return style, {Enum.NormalId.Top} end
        local size: Vector3 = part.Size
        if (style == "brick" or style == "concrete") and size.Y >= 8
            and math.max(size.X, size.Z) >= 8 and math.min(size.X, size.Z) <= 4
            and part.CFrame.UpVector.Y >= 0.87 then
            return style, if size.Z <= size.X then {Enum.NormalId.Front, Enum.NormalId.Back}
                else {Enum.NormalId.Left, Enum.NormalId.Right}
        end
        return nil, nil
    end

    local function rememberFaceOwner(object: any, part: any): ()
        if surfaceFaceOwners[object] then
            surfaceFaceOwners[object] = part
        elseif surfaceFaceCount < MAX_FACE_OWNERS then
            surfaceFaceOwners[object] = part
            surfaceFaceCount += 1
        end
    end

    local function availableFaces(part: any, record: any, requested: {any}): {any}?
        local blocked: {[any]: boolean} = {}
        for _, child: any in ipairs(part:GetChildren()) do
            local ours: boolean = false
            if record and record.textures then
                for _, texture: any in ipairs(record.textures) do
                    if texture == child then ours = true; break end
                end
            end
            if not ours then
                -- Full mesh appearances cannot safely be overlaid as if they
                -- were ordinary flat faces. Existing decals only own their
                -- own face, not every side of the part.
                if child:IsA("SurfaceAppearance") or child:IsA("SpecialMesh") then
                    rememberFaceOwner(child, part)
                    return nil
                end
                if child:IsA("Decal") then
                    rememberFaceOwner(child, part)
                    local ok: boolean, face: any = pcall(function(): any return child.Face end)
                    if not ok or face == nil then return nil end
                    blocked[face] = true
                end
            end
        end
        local available: {any} = {}
        for _, face: any in ipairs(requested) do
            if not blocked[face] then table.insert(available, face) end
        end
        return if #available > 0 then available else nil
    end

    local function textureAsset(key: string, fallback: string): string
        local value: string? = surfaceAssets[key]
        if not value then
            -- Start with an official Roblox material image, so the first scan
            -- need not wait for executor-specific files or a slow download.
            surfaceAssets[key] = fallback
            local generation: number = surfaceGeneration
            task.spawn(function(): ()
                local state: any = host.state
                local ok, asset = false, nil
                if state and type(state.resolveAsset) == "function" then ok, asset = pcall(state.resolveAsset, key) end
                if generation ~= surfaceGeneration or not enabled("Surface textures") then return end
                local usable: boolean = ok and type(asset) == "string" and asset ~= "" and imageAvailable(asset)
                if generation ~= surfaceGeneration or not enabled("Surface textures") then return end
                if usable then
                    surfaceAssets[key] = asset
                    -- Revisit already decorated parts after an async asset
                    -- resolves, without waiting for a complete world pass.
                    if wakeSurfaceScan then wakeSurfaceScan(key) end
                elseif not textureWarning then
                    textureWarning = true
                    card:Notify("Custom textures unavailable; trying Roblox material images")
                end
            end)
        end
        return surfaceAssets[key]
    end

    local function wantedReflection(part: any): number?
        local material: any = part.Material
        local plastic: boolean = material == Enum.Material.Plastic or material == Enum.Material.SmoothPlastic
        local name: string = string.lower(part.Name)
        local size: Vector3 = part.Size
        local window: boolean = name == "pane" or string.find(name, "window", 1, true) ~= nil
            or string.find(name, "glass", 1, true) ~= nil
            or (math.min(size.X, size.Y, size.Z) <= 2 and math.max(size.X, size.Y, size.Z) >= 4)
        -- Thin transparent plastic panes frequently have only the default
        -- name "Part". This is sky/environment reflectance, not a mirror.
        -- v177: 0,16/0,36 reflectance was washed out by the place's own lighting,
        -- especially at night. These are still sky/environment reflectance, not a
        -- mirror: the visible amount still depends on the map and the quality.
        if enabled("Glass reflections") and (material == Enum.Material.Glass
            or (plastic and window and part.Transparency >= 0.1)) then return 0.5 end
        if enabled("Wet surfaces") and part.Anchored and part.Transparency <= 0.05 and floorShape(part)
            and material ~= Enum.Material.Glass then return 0.32 end
        return nil
    end

    local function processSurface(part: any): ()
        surfaceSeen += 1
        local record: any = surfaceRecords[part]
        if not safePart(part) then
            if record then removeSurface(part, record) end
            return
        end
        local reflection: number? = wantedReflection(part)
        if record and record.reflectionApplied ~= nil and record.reflectionTarget ~= reflection then
            removeReflection(part, record)
        end
        if reflection and record and record.reflectionApplied ~= nil and part.Reflectance ~= record.reflectionApplied then
            -- Some games rewrite windows after map/round changes. Preserve
            -- that latest value for OFF, then restore the requested minimum.
            local current: number = part.Reflectance
            local updated: boolean = pcall(function(): ()
                part.Reflectance = math.max(current, reflection :: number)
            end)
            if updated then
                record.reflectionOriginal, record.reflectionApplied = current, part.Reflectance
            end
        end
        if reflection and (not record or record.reflectionApplied == nil) and reflectionCount < MAX_REFLECTIONS
            and part.Reflectance < reflection then
            record = record or {}
            local old: number = part.Reflectance
            local ok: boolean = pcall(function(): () part.Reflectance = reflection end)
            if ok then
                record.reflectionOriginal, record.reflectionApplied = old, part.Reflectance
                record.reflectionTarget = reflection
                reflectionCount += 1
                surfaceRecords[part] = record
            end
        end
        local style, faces = nil, nil
        if enabled("Surface textures") then style, faces = textureStyle(part) end
        if style and faces then
            local available: {any}? = availableFaces(part, record, faces)
            if not available then surfaceReserved += 1 end
            faces = available
            if not faces then style = nil end
        elseif enabled("Surface textures") then
            surfaceNoStyle += 1
        end
        local faceKey: string? = if faces then tostring(faces[1]) .. ":" .. tostring(faces[2]) else nil
        local definition: any = if style then SURFACE_STYLES[style] else nil
        local asset: string? = if definition then textureAsset(definition.asset, definition.fallback) else nil
        if record and record.textures and (record.style ~= style or record.faces ~= faceKey or record.asset ~= asset) then
            removeTextures(record)
        end
        if style and faces and asset and (not record or not record.textures) and textureCount + #faces <= MAX_TEXTURES then
            record = record or {}
            record.textures, record.style, record.faces, record.asset = {}, style, faceKey, asset
            surfaceRecords[part] = record
            local complete: boolean = true
            for _, face: any in ipairs(faces) do
                local texture: any = nil
                local ok: boolean = pcall(function(): ()
                    texture = Instance.new("Texture")
                    texture.Name, texture.Face = "ARMShaderTexture", face
                    -- Local executor/built-in URIs can be silently ignored by
                    -- the newer PBR ColorMapContent path. The legacy Texture
                    -- setter is a reported workaround for local images;
                    -- official rbxassetid images use the modern API first.
                    local localImage: boolean = not string.match(asset, "^rbxassetid://")
                        and not string.match(asset, "^https?://")
                    local assigned: boolean
                    if localImage then
                        assigned = pcall(function(): () texture.Texture = asset end)
                        if not assigned then
                            assigned = pcall(function(): () texture.ColorMapContent = Content.fromUri(definition.fallback) end)
                            if not assigned then texture.Texture = definition.fallback end
                            if not textureWarning then
                                textureWarning = true
                                card:Notify("Local textures unsupported; trying Roblox material images")
                            end
                        end
                    else
                        assigned = pcall(function(): () texture.ColorMapContent = Content.fromUri(asset) end)
                        if not assigned then texture.Texture = asset end
                    end
                    texture.StudsPerTileU, texture.StudsPerTileV = definition.u, definition.v
                    -- Tint the overlay by the original colour, not a blend
                    -- towards white (the old blend washed dark floors out).
                    -- v177: 0.55 was invisible on night maps; 0.42 still reads
                    -- as detail rather than a repaint.
                    texture.Transparency = 0.42
                    texture.Color3 = part.Color
                    texture.Parent = part
                end)
                if ok then
                    table.insert(record.textures, texture)
                    textureCount += 1
                else
                    complete = false
                    if texture then pcall(function(): () texture:Destroy() end) end
                    break
                end
            end
            if not complete then
                removeTextures(record)
                -- Retry one transient creation failure without restarting the
                -- whole hierarchy walk; persistent failures stay bounded.
                if part.Parent and retrySurface then retrySurface(part) end
                if part.Parent and not textureWarning then
                    textureWarning = true
                    card:Notify("A surface texture could not be applied on this client")
                end
            end
        elseif record and record.textures then
            for _, texture: any in ipairs(record.textures) do
                if texture.Color3 ~= part.Color then texture.Color3 = part.Color end
            end
        end
        if record and not record.textures and record.reflectionApplied == nil then surfaceRecords[part] = nil end
    end

    local function refreshSurfaces(): ()
        local texturesOn: boolean = enabled("Surface textures")
        local anyOn: boolean = texturesOn or enabled("Glass reflections") or enabled("Wet surfaces")
        if not anyOn then stopSurfaces(); updateStatus(); return end
        if texturesOn ~= surfaceTexturesOn then
            -- An old download must never revive a disabled texture option.
            surfaceGeneration += 1
            surfaceAssets, textureWarning, surfaceTexturesOn = {}, false, texturesOn
            if not texturesOn then surfaceFaceOwners, surfaceFaceCount = {}, 0 end
        end
        for part: any, record: any in pairs(surfaceRecords) do
            if not texturesOn then removeTextures(record) end
            local valid: boolean, wanted: any = pcall(function(): any
                return if safePart(part) then wantedReflection(part) else nil
            end)
            if record.reflectionApplied ~= nil and (not valid or record.reflectionTarget ~= wanted) then
                removeReflection(part, record)
            end
            if not record.textures and record.reflectionApplied == nil then surfaceRecords[part] = nil end
        end
        if surfaceConnection then
            if wakeSurfaceScan then wakeSurfaceScan(nil) end
            updateStatus()
            return
        end

        -- Walk the hierarchy in bounded slices; no GetDescendants snapshot and
        -- no radius eviction. Streaming additions are queued separately and
        -- a later pass reconciles changed/removed parts even without signals.
        local stack: {any} = {}
        local pending: {[number]: any} = {}
        local pendingSet: {[any]: boolean} = {}
        local pendingHead, pendingTail = 1, 0
        local stale: {any} = {}
        local staleIndex: number = 1
        local rescanRequested: boolean = true
        local recoveryPending: boolean = false
        local passWait, workElapsed, recordElapsed = 0, 0, 0
        local recordBatch: {any} = {}
        local recordIndex: number = 1
        local retryQueue: {any} = {}
        local retryAttempts: {[any]: boolean} = {}
        local retrySlots, retryElapsed = 0, 0
        local priorityPending: boolean = false
        local warned: boolean = false
        local capWarned: boolean = false
        local groundParams: any = nil
        pcall(function(): ()
            groundParams = RaycastParams.new()
            groundParams.FilterType, groundParams.IgnoreWater = Enum.RaycastFilterType.Exclude, true
            pcall(function(): () groundParams.RespectCanCollide = true end)
        end)
        local function enqueue(part: any): ()
            if not part or pendingSet[part] then return end
            if pendingTail - pendingHead + 1 >= MAX_PENDING then
                -- A huge streamed-in model can overflow the bounded queue.
                -- Finish the current traversal, then recover by another pass.
                surfaceQueueDrops += 1
                recoveryPending = true
                return
            end
            pendingTail += 1
            pending[pendingTail], pendingSet[part] = part, true
        end
        retrySurface = function(part: any): ()
            if retryAttempts[part] or retrySlots >= 64 then return end
            retryAttempts[part], retrySlots = true, retrySlots + 1
            table.insert(retryQueue, part)
        end
        local function beginPass(): ()
            surfacePasses += 1
            stack = {{items = {world}, index = 1}}
            stale, staleIndex = {}, 1
            for part: any in pairs(surfaceRecords) do table.insert(stale, part) end
            priorityPending, rescanRequested, passWait = true, false, 0
        end
        wakeSurfaceScan = function(assetKey: string?): ()
            if not assetKey then rescanRequested = true; return end
            -- Asset resolution only affects already-decorated records using
            -- that sprite. Do not restart a full 100k-node map walk per asset.
            for part: any, record: any in pairs(surfaceRecords) do
                local style: any = record.style and SURFACE_STYLES[record.style]
                if style and style.asset == assetKey then enqueue(part) end
            end
        end

        local function structural(node: any): boolean
            return node == world or node:IsA("BasePart") or node:IsA("Model") or node:IsA("Folder")
        end
        local function ignoredTree(node: any): boolean
            if node == world then return false end
            if not node.Parent or node == world.CurrentCamera or node == weatherFolder
                or (host.LocalPlayer and node == host.LocalPlayer.Character)
                or node:IsA("Tool") or node:IsA("Accessory") then return true end
            if node:IsA("Model") and (node:FindFirstChildOfClass("Humanoid")
                or node:FindFirstChildOfClass("AnimationController")) then return true end
            return not structural(node)
        end
        local function nextTreeNode(): (any, boolean)
            while #stack > 0 do
                local top: any = stack[#stack]
                local node: any = top.items[top.index]
                top.index += 1
                if not node then
                    table.remove(stack)
                else
                    local ok: boolean, ignored: any = pcall(ignoredTree, node)
                    if ok and not ignored then
                        local childrenOk: boolean, children: any = pcall(function(): any return node:GetChildren() end)
                        if childrenOk and type(children) == "table" and #children > 0 then
                            table.insert(stack, {items = children, index = 1})
                        end
                        return node, true
                    end
                    -- Even skipped children consume the traversal budget.
                    return nil, true
                end
            end
            return nil, false
        end
        local function processSafely(part: any): ()
            local ok: boolean, failure: any = pcall(processSurface, part)
            if not ok and not warned then
                warned = true
                warn("[Shaders] A surface could not be enhanced: " .. tostring(failure))
            end
            if not capWarned and (textureCount >= MAX_TEXTURES or reflectionCount >= MAX_REFLECTIONS) then
                capWarned = true
                card:Notify("Surface limit reached; some parts may be unchanged")
            end
        end
        local function updateSurfaces(deltaTime: number): ()
            -- A fixed cadence avoids doing twice the work at 120 FPS. Four
            -- surface jobs per slice is at most ~120/s, independent of FPS.
            workElapsed += math.clamp(deltaTime, 0, 0.25)
            if workElapsed < 1 / 30 then return end
            local elapsed: number = workElapsed
            workElapsed = 0
            if rescanRequested then beginPass() end
            if #retryQueue > 0 then
                retryElapsed += elapsed
                if retryElapsed >= 2 then
                    retryElapsed = 0
                    for _ = 1, 8 do
                        local part: any = table.remove(retryQueue, 1)
                        if not part then break end
                        enqueue(part)
                    end
                end
            else
                retryElapsed = 0
            end
            recordElapsed += elapsed
            if recordElapsed >= 0.5 then
                recordElapsed = 0
                if recordIndex > #recordBatch then
                    recordBatch, recordIndex = {}, 1
                    for part: any in pairs(surfaceRecords) do table.insert(recordBatch, part) end
                end
                -- Small rotating reconciliation detects changed materials,
                -- physics, colours and game rewrites without per-part signals.
                for _ = 1, 8 do
                    local part: any = recordBatch[recordIndex]
                    if not part then break end
                    recordIndex += 1
                    if surfaceRecords[part] then enqueue(part) end
                end
            end
            if priorityPending then
                priorityPending = false
                local camera: Camera? = world.CurrentCamera
                if camera and groundParams then
                    local ok: boolean, hit: any = pcall(function(): any
                        local excluded: {Instance} = {}
                        local character: Model? = host.LocalPlayer and host.LocalPlayer.Character
                        if character then table.insert(excluded, character) end
                        if weatherFolder then table.insert(excluded, weatherFolder) end
                        groundParams.FilterDescendantsInstances = excluded
                        return world:Raycast(camera.CFrame.Position, Vector3.new(0, -80, 0), groundParams)
                    end)
                    if ok and hit and hit.Instance then enqueue(hit.Instance) end
                end
            end
            -- Reconcile stale records in small batches even if a whole model
            -- was streamed out and no longer appears in the hierarchy walk.
            for _ = 1, 8 do
                local part: any = stale[staleIndex]
                if not part then break end
                staleIndex += 1
                local record: any = surfaceRecords[part]
                if record then
                    local ok: boolean, safe: any = pcall(safePart, part)
                    if not ok or not safe then removeSurface(part, record) end
                end
            end
            local jobs, nodes = 0, 0
            while jobs < MAX_SURFACE_JOBS and nodes < MAX_TREE_NODES do
                local part: any = nil
                if pendingHead <= pendingTail then
                    part = pending[pendingHead]
                    pending[pendingHead] = nil
                    pendingHead += 1
                    pendingSet[part] = nil
                    if pendingHead > pendingTail then pending, pendingHead, pendingTail = {}, 1, 0 end
                else
                    local node: any, visited: boolean = nextTreeNode()
                    if not visited then break end
                    nodes += 1
                    if node and node:IsA("BasePart") then part = node end
                end
                if part then processSafely(part); jobs += 1 end
            end
            if #stack == 0 and pendingHead > pendingTail and staleIndex > #stale then
                passWait += elapsed
                if recoveryPending then
                    recoveryPending, rescanRequested = false, true
                elseif passWait >= 30 then
                    -- Streaming and decal signals handle immediate additions;
                    -- a much slower full pass catches silent property changes.
                    rescanRequested = true
                end
            end
        end
        local function queueFaceOwner(object: any, removing: boolean): ()
            -- In deferred signal mode Parent may already be nil or point to a
            -- different part by the time DescendantRemoving runs. Remember a
            -- bounded set of owners so the previously blocked face is retried.
            if not surfaceTexturesOn or object.Name == "ARMShaderTexture" then return end
            if object:IsA("Decal") or object:IsA("SurfaceAppearance") or object:IsA("SpecialMesh") then
                local old: any = surfaceFaceOwners[object]
                local parent: any = object.Parent
                if old then enqueue(old) end
                if parent and parent ~= old and parent:IsA("BasePart") then enqueue(parent) end
                if removing then
                    if old then surfaceFaceOwners[object], surfaceFaceCount = nil, surfaceFaceCount - 1 end
                elseif parent and parent:IsA("BasePart") then
                    rememberFaceOwner(object, parent)
                end
            end
        end
        if world.DescendantAdded then
            surfaceAddedConnection = world.DescendantAdded:Connect(function(object: any): ()
                if object:IsA("BasePart") then enqueue(object) else queueFaceOwner(object, false) end
            end)
        end
        if world.DescendantRemoving then
            surfaceRemovingConnection = world.DescendantRemoving:Connect(function(object: any): ()
                local record: any = surfaceRecords[object]
                if record then removeSurface(object, record) else queueFaceOwner(object, true) end
            end)
        end
        surfaceConnection = host.TaskManager:Connect(updateSurfaces, nil, "Shaders surfaces")
        updateStatus()
    end
    local function cleanup(): ()
        stopWeather()
        stopSurfaces()
        releaseWater()
        for _, connection: any in ipairs(fogConnections) do pcall(function(): () connection:Disconnect() end) end
        fogConnections = {}
        fogMutating = true
        releaseFog()
        fogMutating = false
        restoreProperties(lighting, lightOriginal, lightApplied)
        lightOriginal, lightApplied = {}, {}
        if color then pcall(function(): () color:Destroy() end); color = nil end
        if bloom then pcall(function(): () bloom:Destroy() end); bloom = nil end
        if rays then pcall(function(): () rays:Destroy() end); rays = nil end
    end

    local function makeEffect(className: string, name: string, configure: (any) -> ()): any
        local effect: any = nil
        local ok: boolean, failure: any = pcall(function(): ()
            effect = Instance.new(className)
            effect.Name = name
            configure(effect)
            effect.Parent = lighting
        end)
        if ok then return effect end
        if effect then pcall(function(): () effect:Destroy() end) end
        warn("[Shaders:" .. className .. "] " .. tostring(failure))
        card:Notify(className .. " unavailable; other effects remain active")
        return nil
    end

    card = context.framework.Categories.Render:CreateModule({
        Name = "Shaders", Category = "Render", ConfigKey = "Universal.Shaders",
        Tooltip = "Client-side lighting, surface detail and optional atmosphere.",
        Function = function(on: boolean): ()
            if not on then card:SetStatus(nil); return end
            cardEverEnabled = true
            cleanup()
            card:Clean(cleanup)
            color = makeEffect("ColorCorrectionEffect", "ARMShaderColor", function(effect: any): ()
                effect.Brightness, effect.Contrast, effect.Saturation = 0, 0.08, 0.05
                effect.TintColor, effect.Enabled = Color3.fromRGB(255, 247, 236), true
            end)
            bloom = makeEffect("BloomEffect", "ARMShaderBloom", function(effect: any): ()
                effect.Intensity, effect.Size, effect.Threshold, effect.Enabled = 0.2, 24, 0.95, true
            end)
            rays = makeEffect("SunRaysEffect", "ARMShaderRays", function(effect: any): ()
                effect.Intensity, effect.Spread, effect.Enabled = 0.1, 0.6, true
            end)
            applyLighting()
            if lighting.ChildAdded then table.insert(fogConnections, lighting.ChildAdded:Connect(watchAtmosphere)) end
            if lighting.ChildRemoved then table.insert(fogConnections, lighting.ChildRemoved:Connect(watchAtmosphere)) end
            -- Each optional subsystem owns its failure; an unsupported engine
            -- feature must not take down the rest of the user's effects.
            for _, entry: {any} in ipairs({
                {"Fog", refreshFog}, {"Water", refreshWater},
                {"Surfaces", refreshSurfaces}, {"Weather", changeWeather},
            }) do
                local name: string, start: () -> () = entry[1], entry[2]
                local ok: boolean, reason: any = pcall(start)
                if not ok then
                    warn("[Shaders:" .. name .. "] " .. tostring(reason))
                    card:Notify(name .. " unavailable; other effects remain active")
                end
            end
        end,
    })

    -- v177 diagnostics. The client is the only place that can say whether the map
    -- had compatible surfaces or whether the particles even exist. Each line is a fact the module already tracks.
    local function effectState(effect: any): string
        if not effect then return "missing" end
        return if effect.Enabled == true then "on" else "off"
    end
    local function switchState(name: string): string
        return if enabled(name) then "on" else "off"
    end
    local function countSurfaceRecords(wantTextures: boolean, wantReflection: boolean): number
        local total: number = 0
        for _, record: any in pairs(surfaceRecords) do
            local hasTextures: boolean = record.textures ~= nil and #record.textures > 0
            local hasReflection: boolean = record.reflectionApplied ~= nil
            if (not wantTextures or hasTextures) and (not wantReflection or hasReflection) then
                total += 1
            end
        end
        return total
    end
    local function describeWeather(): string
        local total, on, covered = 0, 0, 0
        for _, cell: any in ipairs(weatherCells) do
            if cell.applied == true then covered += 1 end
            for _, emitter: ParticleEmitter in ipairs(cell.emitters) do
                total += 1
                if emitter.Enabled then on += 1 end
            end
        end
        local kinds: {string} = {}
        for _, name: string in ipairs({"Rain", "Snow", "Falling leaves"}) do
            if enabled(name) then table.insert(kinds, name) end
        end
        return string.format("folder=%s cells=%d emitters=%d on=%d covered=%d kinds=%s fogCells=%d moving=%d configuredRate=%d profile=%s",
            tostring(weatherFolder ~= nil), #weatherCells, total, on, covered,
            if #kinds > 0 then table.concat(kinds, "/") else "none", #mistCells, fogMovingActors, weatherRate,
            if weatherCompact then "compact" else "standard")
    end
    local function describe(): {string}
        local stamp: string = "?"
        local stampOk: boolean, value: any = pcall(function(): any
            return host.state and host.state.boot and host.state.boot.stamp
        end)
        if stampOk and type(value) == "string" then stamp = value end
        local lines: {string} = {}
        table.insert(lines, "[Shaders] stamp=" .. stamp .. " · card=" .. (if card and card.Enabled then "on" else "off"))
        table.insert(lines, "[Shaders] post: color=" .. effectState(color) .. " bloom=" .. effectState(bloom)
            .. " rays=" .. effectState(rays) .. " · specular=" .. tostring(lighting.EnvironmentSpecularScale)
            .. " shadows=" .. tostring(lighting.GlobalShadows))
        -- Counts are cumulative visits, not unique parts; repeated passes or
        -- reconciliation can visit the same part more than once.
        table.insert(lines, "[Shaders] surfaces: " .. switchState("Surface textures")
            .. " · visits=" .. tostring(surfaceSeen) .. " passes=" .. tostring(surfacePasses)
            .. " textured=" .. tostring(countSurfaceRecords(true, false))
            .. " reservedVisits=" .. tostring(surfaceReserved)
            .. " noStyleVisits=" .. tostring(surfaceNoStyle)
            .. " queueDrops=" .. tostring(surfaceQueueDrops)
            .. " cap=" .. tostring(MAX_TEXTURES))
        table.insert(lines, "[Shaders] reflectance: wet=" .. switchState("Wet surfaces")
            .. " glass=" .. switchState("Glass reflections")
            .. " parts=" .. tostring(countSurfaceRecords(false, true)) .. "/" .. tostring(MAX_REFLECTIONS))
        table.insert(lines, "[Shaders] weather: " .. describeWeather())
        local terrain: any = nil
        pcall(function(): () terrain = world:FindFirstChildOfClass("Terrain") end)
        table.insert(lines, "[Shaders] water: " .. switchState("Water reflections")
            .. " · terrain=" .. tostring(terrain ~= nil)
            .. (if terrain then " reflectance=" .. tostring((terrain :: any).WaterReflectance) else " (needs Terrain water)"))
        local camera: any = world.CurrentCamera
        local character: any = host.LocalPlayer and host.LocalPlayer.Character
        table.insert(lines, "[Shaders] camera=" .. tostring(camera ~= nil) .. " character=" .. tostring(character ~= nil))
        return lines
    end

    -- v177: a child toggle used to switch its own box while the card was OFF and
    -- do nothing at all, which reads as "this effect is broken". Say it instead of
    -- silently ignoring the click.
    local function optionAction(name: string, apply: () -> ()): () -> ()
        return function(): ()
            if card and not card.Enabled then
                -- Saved values are replayed while the UI is built, long before
                -- the card was ever enabled: that is not the user clicking.
                if cardEverEnabled then
                    card:Notify("Shaders is off: turn on the Shaders card to see " .. name)
                end
                return
            end
            local ok: boolean, reason: any = pcall(apply)
            if not ok then
                warn("[Shaders:" .. name .. "] " .. tostring(reason))
                card:Notify(name .. " could not be applied on this client")
            end
        end
    end

    card:CreateToggle({Name = "Surface textures", Default = true, Function = optionAction("Surface textures", refreshSurfaces),
        Tooltip = "Colour detail on eligible static blocks and unions; existing decals keep their faces."})
    card:CreateToggle({Name = "Glass reflections", Default = true, Function = optionAction("Glass reflections", refreshSurfaces),
        Tooltip = "Adds sky reflectance to eligible glass and transparent windows across the map."})
    card:CreateToggle({Name = "Fog", Default = false, Function = optionAction("Fog", function(): () refreshFog(); changeWeather() end),
        Tooltip = "Global distance haze plus nearby mist that drifts away from moving characters; restores the game's atmosphere."})
    card:CreateToggle({Name = "Rain", Default = false, Function = optionAction("Rain", changeWeather),
        Tooltip = "Near and distant rain cells with splashes and staggered shelter checks; follows the camera."})
    card:CreateToggle({Name = "Snow", Default = false, Function = optionAction("Snow", changeWeather),
        Tooltip = "Falling snow around the camera; can be combined with rain."})
    card:CreateToggle({Name = "Falling leaves", Default = false, Function = optionAction("Falling leaves", changeWeather),
        Tooltip = "Windblown autumn leaves near the camera."})
    card:CreateToggle({Name = "Dust motes", Default = false, Function = optionAction("Dust motes", changeWeather),
        Tooltip = "Soft drifting particles, including indoors."})
    card:CreateToggle({Name = "Wet surfaces", Default = false, Function = optionAction("Wet surfaces", refreshSurfaces),
        Tooltip = "Adds sky sheen to eligible floors across the map; does not change physics."})
    card:CreateToggle({Name = "Water reflections", Default = false, Function = optionAction("Water reflections", refreshWater),
        Tooltip = "Increases Terrain water reflectance while enabled."})
    card:CreateButton({Name = "Diagnose", Function = function(): ()
        local lines: {string} = describe()
        for _, line: string in ipairs(lines) do
            print(line)
            card:Notify(line)
        end
    end,
        Tooltip = "Prints what each Shaders effect reached on this client: surface visits, particle counts and Terrain."})

    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if card and card.Enabled then card:Toggle(false) end
    card = nil
    Module.Initialized = false
end

return Module
