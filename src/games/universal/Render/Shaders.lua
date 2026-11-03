-- Client-side lighting, an optional local floor reflection and atmosphere.
-- Weather adapts ShaderCloud/rbxts-weather's camera cells/roof checks (ISC),
-- with outdoor sampling and splashes informed by buildthomas/Rain (Apache-2.0).
-- Surface colour maps are CC0 ambientCG assets; they are not PBR normal maps.
-- Research, pinned sources and licences: docs/third-party/shaders/README.md.
local Module = {Name = "Shaders", PlaceId = 0, Initialized = false}
local card

local WEATHER = {
    Rain = {asset = "shaderRainTexture", fallback = "rbxasset://textures/particles/SquareParticle.png",
        rate = 18, size = 0.6, speedMin = 45, speedMax = 50, lifetime = 0.85,
        transparency = 0.30, spread = 1},
    Snow = {asset = "shaderSnowTexture", fallback = "rbxasset://textures/particles/smoke_main.dds",
        rate = 8, size = 0.45, speedMin = 6, speedMax = 9, lifetime = 4,
        transparency = 0.18, spread = 12},
    ["Falling leaves"] = {asset = "shaderAutumnTexture", fallback = "rbxassetid://80805595237760",
        rate = 3, size = 0.9, speedMin = 4, speedMax = 6, lifetime = 4,
        transparency = 0.10, spread = 18},
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
}

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
    local floorReflection: any = nil
    local floorGeneration: number = 0
    local floorRetries: number = 0

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
    local weatherGeneration: number = 0

    local surfaceConnection: any = nil
    local surfaceAddedConnection: any = nil
    local surfaceRemovingConnection: any = nil
    local wakeSurfaceScan: (() -> ())? = nil
    local surfaceGeneration: number = 0
    local surfaceAssets: {[string]: any} = {}
    local surfaceTexturesOn: boolean = false
    local surfaceRecords: {[Instance]: any} = {}
    local textureCount: number = 0
    local reflectionCount: number = 0
    local textureWarning: boolean = false
    -- The world is visited incrementally, not restricted to the player's
    -- neighbourhood. Caps bound retained instances on unusually large maps.
    local MAX_TEXTURES: number = 600
    local MAX_REFLECTIONS: number = 1200
    local MAX_SURFACE_JOBS: number = 4
    local MAX_TREE_NODES: number = 20
    local MAX_PENDING: number = 2048

    local function enabled(name: string): boolean
        return card ~= nil and card.Enabled and card.Options[name] ~= nil
            and card.Options[name].Value == true
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

    local function updateStatus(): ()
        if not card or not card.Enabled then return end
        local parts: {string} = {}
        for _, name: string in ipairs({"Fog", "Rain", "Snow", "Falling leaves", "Dust motes", "Wet surfaces"}) do
            if enabled(name) then table.insert(parts, name) end
        end
        card:SetStatus(if #parts == 0 then nil else table.concat(parts, " · "))
    end

    local function stopFloorReflection(): ()
        floorGeneration += 1
        floorRetries = 0
        local session: any = floorReflection
        floorReflection = nil
        if session then pcall(function(): () session:Stop() end) end
    end

    local function refreshFloorReflection(): ()
        if not enabled("Floor reflections") then stopFloorReflection(); return end
        if floorReflection then return end
        local library: any = context.libraries and context.libraries.shaderreflection
        if not library or type(library.Start) ~= "function" then
            card:Notify("Floor reflection library unavailable")
            return
        end
        local generation: number = floorGeneration
        local session: any = nil
        local ok: boolean, result: any, failure: any = pcall(library.Start, library, function(message: string, fatal: boolean?): ()
            if card and card.Enabled then card:Notify(message) end
            if fatal and generation == floorGeneration and session ~= nil and floorReflection == session then
                -- The library stopped itself after a runtime error. A stale
                -- non-nil handle otherwise prevents any restart forever.
                floorReflection = nil
                if floorRetries < 1 then
                    floorRetries += 1
                    task.defer(function(): ()
                        if generation == floorGeneration and enabled("Floor reflections") and not floorReflection then
                            refreshFloorReflection()
                        end
                    end)
                end
            end
        end)
        if not ok or not result then
            warn("[Shaders] Floor reflection unavailable: " .. tostring(if ok then failure else result))
            card:Notify("Floor reflection unavailable; other effects are still active")
            return
        end
        session, floorReflection = result, result
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
        pcall(function(): ()
            lightOriginal.GlobalShadows = lighting.GlobalShadows
            lighting.GlobalShadows = true
            lightApplied.GlobalShadows = lighting.GlobalShadows
        end)
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

    local function refreshWater(): ()
        releaseWater()
        if not enabled("Water reflections") then return end
        pcall(function(): ()
            local terrain: any = world:FindFirstChildOfClass("Terrain")
            if not terrain then return end
            local old: number = terrain.WaterReflectance
            terrain.WaterReflectance = math.max(old, 0.55)
            waterTerrain, waterOriginal, waterApplied = terrain, old, terrain.WaterReflectance
        end)
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
            if property == "FogStart" then return math.min(original, 20) end
            if property == "FogEnd" then return math.min(original, 180) end
            return Color3.fromRGB(181, 193, 201)
        end
        if property == "Density" then return math.max(original, 0.45) end
        return math.max(original, 1.25) -- Haze
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
        weatherCells = {}
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
        local ok: boolean, failure: any = pcall(function(): ()
            local folder: Folder = Instance.new("Folder")
            weatherFolder = folder
            folder.Name = "ARMShaderWeather"
            folder.Parent = world
            local textures: {[string]: {any}} = {}
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
                -- Each cell has its own sky test. The outer ring can remain
                -- rainy when the camera is sheltered but looks outdoors.
                for _, offset: Vector3 in ipairs({
                    Vector3.new(0, 0, 0),
                    Vector3.new(-28, 0, -28), Vector3.new(0, 0, -28), Vector3.new(28, 0, -28),
                    Vector3.new(-28, 0, 0), Vector3.new(28, 0, 0),
                    Vector3.new(-28, 0, 28), Vector3.new(0, 0, 28), Vector3.new(28, 0, 28),
                }) do
                    local part: Part = cellPart("WeatherCell", Vector3.new(26, 0.2, 26))
                    local emitters: {ParticleEmitter} = {}
                    for _, name: string in ipairs(kinds) do
                        local style: any = WEATHER[name]
                        local emitter: any = nil
                        local created: boolean, failure: any = pcall(function(): ()
                            emitter = Instance.new("ParticleEmitter")
                            emitter.Name, emitter.Enabled, emitter.Texture = name, false, style.fallback
                            -- Newer particle properties are optional: a client
                            -- lacking them should still draw the basic emitter.
                            pcall(function(): ()
                                emitter.Shape, emitter.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
                            end)
                            emitter.EmissionDirection = Enum.NormalId.Bottom
                            pcall(function(): ()
                                emitter.Orientation = if name == "Rain" then Enum.ParticleOrientation.VelocityParallel
                                    else Enum.ParticleOrientation.FacingCamera
                            end)
                            emitter.Rate, emitter.Size = style.rate, NumberSequence.new(style.size)
                            emitter.Speed, emitter.Lifetime = NumberRange.new(style.speedMin, style.speedMax), NumberRange.new(style.lifetime)
                            emitter.Transparency, emitter.SpreadAngle = NumberSequence.new(style.transparency), Vector2.new(style.spread, style.spread)
                            emitter.LightInfluence, emitter.LightEmission = 0.8, if name == "Snow" then 0.2 else 0.05
                            if name == "Rain" then
                                pcall(function(): () emitter.Squash = NumberSequence.new(-2.5) end)
                                emitter.Color = ColorSequence.new(Color3.fromRGB(205, 219, 235))
                            else
                                emitter.Rotation, emitter.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-45, 45)
                            end
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
                    if #emitters > 0 then
                        table.insert(weatherCells, {part = part, emitters = emitters, offset = offset})
                    else
                        part:Destroy()
                    end
                end
            end
            local dustPart: Part? = nil
            local dust: ParticleEmitter? = nil
            if dustEnabled then
                dustPart, dust = extraEmitter("DustCell", "Dust motes", Vector3.new(20, 6, 20), "shaderSnowTexture", function(emitter: any): ()
                    emitter.Name, emitter.Enabled = "Dust motes", false
                    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
                    pcall(function(): () emitter.Shape, emitter.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume end)
                    emitter.EmissionDirection = Enum.NormalId.Top
                    pcall(function(): () emitter.Orientation = Enum.ParticleOrientation.FacingCamera end)
                    emitter.Rate, emitter.Size, emitter.Speed = 12, NumberSequence.new(0.35), NumberRange.new(0.1, 0.4)
                    emitter.Lifetime, emitter.Transparency = NumberRange.new(5), NumberSequence.new(0.35)
                    emitter.Color, emitter.LightEmission, emitter.LightInfluence = ColorSequence.new(Color3.fromRGB(255, 232, 180)), 0.35, 0.5
                end)
            end
            local mistPart: Part? = nil
            local mist: ParticleEmitter? = nil
            if mistEnabled then
                -- Distance haze and its local mist are independent: a failed
                -- optional particle must not cancel fog, rain or snow.
                mistPart, mist = extraEmitter("FogCell", "Fog mist", Vector3.new(60, 10, 60), "shaderSnowTexture", function(emitter: any): ()
                    emitter.Name, emitter.Enabled = "Fog mist", false
                    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
                    pcall(function(): () emitter.Shape, emitter.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume end)
                    emitter.EmissionDirection = Enum.NormalId.Top
                    pcall(function(): () emitter.Orientation = Enum.ParticleOrientation.FacingCamera end)
                    emitter.Rate, emitter.Size, emitter.Speed = 4, NumberSequence.new(10), NumberRange.new(0.1, 0.35)
                    emitter.Lifetime, emitter.Transparency = NumberRange.new(7, 9), NumberSequence.new(0.86)
                    emitter.Color, emitter.LightEmission, emitter.LightInfluence = ColorSequence.new(Color3.fromRGB(202, 213, 219)), 0.1, 0.7
                    emitter.Rotation, emitter.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-4, 4)
                end)
            end
            local splashPart: Part? = nil
            local splash: ParticleEmitter? = nil
            if (styleCounts.Rain or 0) > 0 then
                splashPart, splash = extraEmitter("RainSplashCell", "Rain splashes", Vector3.new(0.2, 0.2, 0.2), "shaderSnowTexture", function(emitter: any): ()
                    emitter.Name, emitter.Enabled, emitter.Rate = "Rain splashes", false, 0
                    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
                    emitter.EmissionDirection = Enum.NormalId.Top
                    pcall(function(): () emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular end)
                    emitter.Size, emitter.Speed = NumberSequence.new(1.2), NumberRange.new(0.1, 0.2)
                    emitter.Lifetime, emitter.Transparency = NumberRange.new(0.2, 0.3), NumberSequence.new(0.55)
                    emitter.Color, emitter.LightInfluence = ColorSequence.new(Color3.fromRGB(220, 229, 235)), 0.7
                end)
            end
            if particleCount == 0 then stopWeather(); return end
            local paramsOk: boolean, params: any = pcall(function(): any
                local value: RaycastParams = RaycastParams.new()
                value.FilterType, value.IgnoreWater = Enum.RaycastFilterType.Exclude, true
                return value
            end)
            if not paramsOk then params = nil end
            local previousCharacter: Model? = nil
            local lastFocus: Vector3? = nil
            local lastCamera: Camera? = nil
            local moveElapsed, roofElapsed, roofIndex = 0, 0.15, 0
            local shelterWarned: boolean = false
            local function updateWeather(deltaTime: number): ()
                moveElapsed += math.clamp(deltaTime, 0, 0.25)
                if moveElapsed < 0.05 then return end
                local elapsed: number = moveElapsed
                moveElapsed = 0
                local camera: Camera? = world.CurrentCamera
                if not camera then
                    for _, cell: any in ipairs(weatherCells) do
                        for _, emitter: ParticleEmitter in ipairs(cell.emitters) do emitter.Enabled = false end
                    end
                    if dust then dust.Enabled = false end
                    if mist then mist.Enabled = false end
                    lastCamera, lastFocus = nil, nil
                    return
                end
                local focus: Vector3 = camera.CFrame.Position
                if camera ~= lastCamera or (lastFocus and (focus - lastFocus).Magnitude > 30) then
                    for _, cell: any in ipairs(weatherCells) do
                        for _, emitter: ParticleEmitter in ipairs(cell.emitters) do emitter.Enabled = false end
                    end
                end
                lastCamera, lastFocus = camera, focus
                local character: Model? = host.LocalPlayer and host.LocalPlayer.Character
                if params and #weatherCells > 0 and (character ~= previousCharacter or roofIndex == 0) then
                    previousCharacter = character
                    local excluded: {Instance} = {folder}
                    if character then table.insert(excluded, character) end
                    params.FilterDescendantsInstances = excluded
                end
                for _, cell: any in ipairs(weatherCells) do
                    cell.part.Position = focus + cell.offset + Vector3.new(0, 20, 0)
                end
                if dustPart and dust then dustPart.Position, dust.Enabled = focus, true end
                if mistPart and mist then mistPart.Position, mist.Enabled = focus + Vector3.new(0, -2, 0), true end
                if #weatherCells == 0 then return end
                if not params then
                    for _, cell: any in ipairs(weatherCells) do
                        for _, emitter: ParticleEmitter in ipairs(cell.emitters) do emitter.Enabled = true end
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
                for _, emitter: ParticleEmitter in ipairs(cell.emitters) do emitter.Enabled = not covered end
                -- One short ground sample per open cell produces inexpensive
                -- local splashes; it does not run for snow or while sheltered.
                if castOk and not covered and splashPart and splash then
                    local groundOk: boolean, ground: any = pcall(function(): any
                        return world:Raycast(focus + cell.offset + Vector3.new(0, 20, 0), Vector3.new(0, -100, 0), params)
                    end)
                    if groundOk and ground and ground.Position and ground.Normal then
                        splashPart.Position = ground.Position + ground.Normal * 0.05
                        pcall(function(): () (splash :: ParticleEmitter):Emit(1) end)
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
        wakeSurfaceScan = nil
        for part: any, record: any in pairs(surfaceRecords) do removeSurface(part, record) end
        surfaceRecords, surfaceAssets = {}, {}
        textureCount, reflectionCount, textureWarning, surfaceTexturesOn = 0, 0, false, false
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
        local style: string? = nil
        if material == Enum.Material.Concrete or material == Enum.Material.Asphalt
            or material == Enum.Material.Pavement then style = "concrete"
        elseif material == Enum.Material.Wood or material == Enum.Material.WoodPlanks then style = "wood"
        elseif material == Enum.Material.Brick then style = "brick"
        elseif material == Enum.Material.Grass then style = "grass"
        elseif material == Enum.Material.Marble then style = "marble"
        elseif (material == Enum.Material.Plastic or material == Enum.Material.SmoothPlastic)
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
                if child:IsA("SurfaceAppearance") or child:IsA("SpecialMesh") then return nil end
                if child:IsA("Decal") then
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
                    if wakeSurfaceScan then wakeSurfaceScan() end
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
        if enabled("Glass reflections") and (material == Enum.Material.Glass
            or (plastic and window and part.Transparency >= 0.1)) then return 0.36 end
        if enabled("Wet surfaces") and part.Anchored and part.Transparency <= 0.05 and floorShape(part)
            and material ~= Enum.Material.Glass then return 0.16 end
        return nil
    end

    local function processSurface(part: any): ()
        local record: any = surfaceRecords[part]
        if not safePart(part) then
            if record then removeSurface(part, record) end
            return
        end
        if floorReflection and type(floorReflection.Observe) == "function" then
            -- Share the incremental map walk with the mirror library, even
            -- when the other surface options are switched off.
            pcall(floorReflection.Observe, floorReflection, part)
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
            faces = availableFaces(part, record, faces)
            if not faces then style = nil end
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
                    texture.Transparency = 0.55
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
                if part.Parent and not textureWarning then
                    textureWarning = true
                    card:Notify("A surface texture could not be applied on this client")
                end
            end
        elseif record and record.textures then
            for _, texture: any in ipairs(record.textures) do
                texture.Color3 = part.Color
            end
        end
        if record and not record.textures and record.reflectionApplied == nil then surfaceRecords[part] = nil end
    end

    local function refreshSurfaces(): ()
        local texturesOn: boolean = enabled("Surface textures")
        local anyOn: boolean = texturesOn or enabled("Glass reflections") or enabled("Wet surfaces")
            or (enabled("Floor reflections") and floorReflection ~= nil)
        if not anyOn then stopSurfaces(); updateStatus(); return end
        if texturesOn ~= surfaceTexturesOn then
            -- An old download must never revive a disabled texture option.
            surfaceGeneration += 1
            surfaceAssets, textureWarning, surfaceTexturesOn = {}, false, texturesOn
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
            if wakeSurfaceScan then wakeSurfaceScan() end
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
        local passWait: number = 0
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
            if not part or pendingSet[part] or pendingTail - pendingHead + 1 >= MAX_PENDING then return end
            pendingTail += 1
            pending[pendingTail], pendingSet[part] = part, true
        end
        local function beginPass(): ()
            stack = {{items = {world}, index = 1}}
            stale, staleIndex = {}, 1
            for part: any in pairs(surfaceRecords) do table.insert(stale, part) end
            priorityPending, rescanRequested, passWait = true, false, 0
        end
        wakeSurfaceScan = function(): () rescanRequested = true end

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
            if rescanRequested then beginPass() end
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
                passWait += math.clamp(deltaTime, 0, 0.25)
                if passWait >= 2 then rescanRequested = true end
            end
        end
        if world.DescendantAdded then
            surfaceAddedConnection = world.DescendantAdded:Connect(function(object: any): ()
                if object:IsA("BasePart") then enqueue(object) end
            end)
        end
        if world.DescendantRemoving then
            surfaceRemovingConnection = world.DescendantRemoving:Connect(function(object: any): ()
                local record: any = surfaceRecords[object]
                if record then removeSurface(object, record) end
            end)
        end
        surfaceConnection = host.TaskManager:Connect(updateSurfaces, nil, "Shaders surfaces")
        updateStatus()
    end
    local function cleanup(): ()
        stopFloorReflection()
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
        Tooltip = "Warm lighting, local floor reflections and optional atmosphere.",
        Function = function(on: boolean): ()
            if not on then card:SetStatus(nil); return end
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
                {"Fog", refreshFog}, {"Water", refreshWater}, {"Floor", refreshFloorReflection},
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

    card:CreateToggle({Name = "Floor reflections", Default = true, Function = function(): ()
        refreshFloorReflection(); refreshSurfaces()
    end,
        Tooltip = "Client-only mirror approximation on a few visible flat floors; not screen-space reflections."})
    card:CreateToggle({Name = "Surface textures", Default = true, Function = refreshSurfaces,
        Tooltip = "Colour detail on eligible static blocks and unions; existing decals keep their faces."})
    card:CreateToggle({Name = "Glass reflections", Default = true, Function = refreshSurfaces,
        Tooltip = "Adds sky reflectance to eligible glass and transparent windows across the map."})
    card:CreateToggle({Name = "Fog", Default = false, Function = function(): () refreshFog(); changeWeather() end,
        Tooltip = "Distance haze plus local moving mist particles; restores the game's atmosphere."})
    card:CreateToggle({Name = "Rain", Default = false, Function = changeWeather,
        Tooltip = "Local rain and splashes, with staggered shelter checks and visible outdoor cells."})
    card:CreateToggle({Name = "Snow", Default = false, Function = changeWeather,
        Tooltip = "Falling snow around the camera; can be combined with rain."})
    card:CreateToggle({Name = "Falling leaves", Default = false, Function = changeWeather,
        Tooltip = "Windblown autumn leaves near the camera."})
    card:CreateToggle({Name = "Dust motes", Default = false, Function = changeWeather,
        Tooltip = "Soft drifting particles, including indoors."})
    card:CreateToggle({Name = "Wet surfaces", Default = false, Function = refreshSurfaces,
        Tooltip = "Adds sky sheen to eligible floors across the map; does not change physics."})
    card:CreateToggle({Name = "Water reflections", Default = false, Function = refreshWater,
        Tooltip = "Increases Terrain water reflectance while enabled."})
    card:CreateNote("Client-only approximation. Reflections need flat floors; weather and quality depend on the client.")

    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if card and card.Enabled then card:Toggle(false) end
    card = nil
    Module.Initialized = false
end

return Module
