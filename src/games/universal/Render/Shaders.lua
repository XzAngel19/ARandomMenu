-- Client-side lighting, an optional local floor reflection and atmosphere.
-- Weather adapts ShaderCloud/rbxts-weather's camera cells/roof checks (ISC),
-- with outdoor sampling and splashes informed by buildthomas/Rain (Apache-2.0).
-- Surface colour maps are CC0 ambientCG assets; they are not PBR normal maps.
-- Research, pinned sources and licences: docs/third-party/shaders/README.md.
local Module = {Name = "Shaders", PlaceId = 0, Initialized = false}
local card

local WEATHER = {
    Rain = {asset = "shaderRainTexture", fallback = "rbxasset://textures/particles/SquareParticle.png",
        rate = 12, size = 0.45, speedMin = 45, speedMax = 50, lifetime = 0.85,
        transparency = 0.38, spread = 1},
    Snow = {asset = "shaderSnowTexture", fallback = "rbxasset://textures/particles/smoke_main.dds",
        rate = 5, size = 0.35, speedMin = 6, speedMax = 9, lifetime = 4,
        transparency = 0.18, spread = 12},
    ["Falling leaves"] = {asset = "shaderAutumnTexture", fallback = "rbxassetid://80805595237760",
        rate = 2, size = 0.9, speedMin = 4, speedMax = 6, lifetime = 4,
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

    local fogAtmosphere: Atmosphere? = nil
    local fogOwned: boolean = false
    local fogOriginal: {[string]: any} = {}
    local fogApplied: {[string]: any} = {}
    local fogConnections: {any} = {}
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

    local function updateStatus(): ()
        if not card or not card.Enabled then return end
        local parts: {string} = {}
        for _, name: string in ipairs({"Fog", "Rain", "Snow", "Falling leaves", "Dust motes", "Wet surfaces"}) do
            if enabled(name) then table.insert(parts, name) end
        end
        card:SetStatus(if #parts == 0 then nil else table.concat(parts, " · "))
    end

    local function stopFloorReflection(): ()
        if floorReflection then
            pcall(function(): () floorReflection:Stop() end)
            floorReflection = nil
        end
    end

    local function refreshFloorReflection(): ()
        if not enabled("Floor reflections") then stopFloorReflection(); return end
        if floorReflection then return end
        local library: any = context.libraries and context.libraries.shaderreflection
        if not library or type(library.Start) ~= "function" then
            card:Notify("Floor reflection library unavailable")
            return
        end
        local ok: boolean, result: any, failure: any = pcall(library.Start, library, function(message: string): ()
            if card and card.Enabled then card:Notify(message) end
        end)
        if not ok or not result then
            warn("[Shaders] Floor reflection unavailable: " .. tostring(if ok then failure else result))
            card:Notify("Floor reflection unavailable; other effects are still active")
            return
        end
        floorReflection = result
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
        local atmosphere: Atmosphere? = fogAtmosphere
        local owned: boolean = fogOwned
        local original: {[string]: any} = fogOriginal
        local applied: {[string]: any} = fogApplied
        fogAtmosphere, fogOwned = nil, false
        fogOriginal, fogApplied = {}, {}
        if not atmosphere then return end
        if owned then
            pcall(function(): () atmosphere:Destroy() end)
        else
            restoreProperties(atmosphere, original, applied)
        end
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
        local external: Atmosphere? = nil
        for _, child: Instance in ipairs(lighting:GetChildren()) do
            if child:IsA("Atmosphere") and child ~= fogAtmosphere then
                external = child :: Atmosphere
                break
            end
        end
        if fogAtmosphere and fogAtmosphere.Parent == lighting
            and (not fogOwned or not external) then
            fogMutating = false
            updateStatus()
            return
        end
        releaseFog()
        local atmosphere: Atmosphere = external or (Instance.new("Atmosphere") :: Atmosphere)
        fogAtmosphere, fogOwned = atmosphere, external == nil
        local values: {[string]: any} = {
            Density = 0.38, Offset = 0.25, Haze = 1.25, Glare = 0.1,
            Color = Color3.fromRGB(220, 229, 238), Decay = Color3.fromRGB(155, 170, 185),
        }
        for property: string, value: any in pairs(values) do
            pcall(function(): ()
                fogOriginal[property] = (atmosphere :: any)[property]
                ;(atmosphere :: any)[property] = value
                fogApplied[property] = (atmosphere :: any)[property]
            end)
        end
        if fogOwned then atmosphere.Parent = lighting end
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
            local function remember(asset: string, emitter: ParticleEmitter): ()
                if not textures[asset] then textures[asset] = {} end
                table.insert(textures[asset], emitter)
            end
            local function cellPart(name: string, size: Vector3): Part
                local part: Part = Instance.new("Part")
                part.Name, part.Anchored = name, true
                part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
                part.CastShadow, part.Transparency, part.Size = false, 1, size
                part.Parent = folder
                return part
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
                        local emitter: ParticleEmitter = Instance.new("ParticleEmitter")
                        emitter.Name, emitter.Enabled, emitter.Texture = name, false, style.fallback
                        emitter.Shape, emitter.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
                        emitter.EmissionDirection = Enum.NormalId.Bottom
                        emitter.Orientation = if name == "Rain" then Enum.ParticleOrientation.VelocityParallel
                            else Enum.ParticleOrientation.FacingCamera
                        emitter.Rate, emitter.Size = style.rate, NumberSequence.new(style.size)
                        emitter.Speed, emitter.Lifetime = NumberRange.new(style.speedMin, style.speedMax), NumberRange.new(style.lifetime)
                        emitter.Transparency, emitter.SpreadAngle = NumberSequence.new(style.transparency), Vector2.new(style.spread, style.spread)
                        emitter.LightInfluence, emitter.LightEmission = 0.8, if name == "Snow" then 0.2 else 0.05
                        if name == "Rain" then
                            emitter.Squash = NumberSequence.new(-2.5)
                            emitter.Color = ColorSequence.new(Color3.fromRGB(205, 219, 235))
                        else
                            emitter.Rotation, emitter.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-45, 45)
                        end
                        emitter.Parent = part
                        table.insert(emitters, emitter)
                        remember(style.asset, emitter)
                    end
                    table.insert(weatherCells, {part = part, emitters = emitters, offset = offset})
                end
            end
            local dustPart: Part? = nil
            local dust: ParticleEmitter? = nil
            if dustEnabled then
                dustPart = cellPart("DustCell", Vector3.new(20, 6, 20))
                dust = Instance.new("ParticleEmitter")
                dust.Name, dust.Enabled = "Dust motes", false
                dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
                dust.Shape, dust.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
                dust.EmissionDirection, dust.Orientation = Enum.NormalId.Top, Enum.ParticleOrientation.FacingCamera
                dust.Rate, dust.Size, dust.Speed = 12, NumberSequence.new(0.35), NumberRange.new(0.1, 0.4)
                dust.Lifetime, dust.Transparency = NumberRange.new(5), NumberSequence.new(0.35)
                dust.Color, dust.LightEmission, dust.LightInfluence = ColorSequence.new(Color3.fromRGB(255, 232, 180)), 0.35, 0.5
                dust.Parent = dustPart
                remember("shaderSnowTexture", dust)
            end
            local mistPart: Part? = nil
            local mist: ParticleEmitter? = nil
            if mistEnabled then
                -- Atmosphere handles distance haze; these translucent sprites
                -- supply a small moving layer near the camera, even indoors.
                mistPart = cellPart("FogCell", Vector3.new(60, 10, 60))
                mist = Instance.new("ParticleEmitter")
                mist.Name, mist.Enabled = "Fog mist", false
                mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
                mist.Shape, mist.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
                mist.EmissionDirection, mist.Orientation = Enum.NormalId.Top, Enum.ParticleOrientation.FacingCamera
                mist.Rate, mist.Size, mist.Speed = 4, NumberSequence.new(10), NumberRange.new(0.1, 0.35)
                mist.Lifetime, mist.Transparency = NumberRange.new(7, 9), NumberSequence.new(0.86)
                mist.Color, mist.LightEmission, mist.LightInfluence = ColorSequence.new(Color3.fromRGB(202, 213, 219)), 0.1, 0.7
                mist.Rotation, mist.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-4, 4)
                mist.Parent = mistPart
                remember("shaderSnowTexture", mist)
            end
            local splashPart: Part? = nil
            local splash: ParticleEmitter? = nil
            if enabled("Rain") then
                splashPart = cellPart("RainSplashCell", Vector3.new(0.2, 0.2, 0.2))
                splash = Instance.new("ParticleEmitter")
                splash.Name, splash.Enabled, splash.Rate = "Rain splashes", false, 0
                splash.Texture = "rbxasset://textures/particles/smoke_main.dds"
                splash.Orientation, splash.EmissionDirection = Enum.ParticleOrientation.VelocityPerpendicular, Enum.NormalId.Top
                splash.Size, splash.Speed = NumberSequence.new(1.2), NumberRange.new(0.1, 0.2)
                splash.Lifetime, splash.Transparency = NumberRange.new(0.2, 0.3), NumberSequence.new(0.55)
                splash.Color, splash.LightInfluence = ColorSequence.new(Color3.fromRGB(220, 229, 235)), 0.7
                splash.Parent = splashPart
                remember("shaderSnowTexture", splash)
            end
            local params: RaycastParams = RaycastParams.new()
            params.FilterType, params.IgnoreWater = Enum.RaycastFilterType.Exclude, true
            local previousCharacter: Model? = nil
            local lastFocus: Vector3? = nil
            local lastCamera: Camera? = nil
            local moveElapsed, roofElapsed, roofIndex = 0, 0.15, 0
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
                if character ~= previousCharacter or roofIndex == 0 then
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
                roofElapsed += elapsed
                if roofElapsed < 0.15 then return end
                roofElapsed = 0
                roofIndex = roofIndex % #weatherCells + 1
                local cell: any = weatherCells[roofIndex]
                local castOk: boolean, hit: any = pcall(function(): any
                    return world:Raycast(focus + cell.offset, Vector3.new(0, 150, 0), params)
                end)
                local covered: boolean = not castOk or hit ~= nil
                if castOk and hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.Transparency >= 0.95 then
                    covered = false
                end
                for _, emitter: ParticleEmitter in ipairs(cell.emitters) do emitter.Enabled = not covered end
                -- One short ground sample per open cell produces inexpensive
                -- local splashes; it does not run for snow or while sheltered.
                if not covered and splashPart and splash then
                    local groundOk: boolean, ground: any = pcall(function(): any
                        return world:Raycast(focus + cell.offset + Vector3.new(0, 20, 0), Vector3.new(0, -100, 0), params)
                    end)
                    if groundOk and ground and ground.Position and ground.Normal then
                        splashPart.Position = ground.Position + ground.Normal * 0.05
                        pcall(function(): () (splash :: ParticleEmitter):Emit(1) end)
                    end
                end
            end
            weatherConnection = host.TaskManager:Connect(updateWeather, nil, "Shaders weather")
            for assetKey: string, emitters: {any} in pairs(textures) do
                task.spawn(function(): ()
                    local state: any = host.state
                    if not state or type(state.resolveAsset) ~= "function" then return end
                    local resolved: boolean, asset: any = pcall(state.resolveAsset, assetKey)
                    if not resolved or type(asset) ~= "string" or asset == ""
                        or generation ~= weatherGeneration or not card or not card.Enabled then return end
                    for _, emitter: ParticleEmitter in ipairs(emitters) do emitter.Texture = asset end
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
        if not part:IsA("BasePart") or not part.Anchored or part.Transparency >= 0.95 then return false end
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
        -- Only flat, anchored block Parts. MeshParts, custom variants, decals,
        -- characters and physics are never replaced or given fake PBR maps.
        if part.ClassName ~= "Part" or part.Shape ~= Enum.PartType.Block
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

    local function externalSurface(part: any, record: any): boolean
        for _, child: any in ipairs(part:GetChildren()) do
            local ours: boolean = false
            if record and record.textures then
                for _, texture: any in ipairs(record.textures) do
                    if texture == child then ours = true; break end
                end
            end
            if not ours and (child:IsA("Decal") or child:IsA("SurfaceAppearance") or child:IsA("SpecialMesh")) then
                return true
            end
        end
        return false
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
                if ok and type(asset) == "string" and asset ~= "" then
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
        local window: boolean = name == "pane" or string.find(name, "window", 1, true) ~= nil
            or string.find(name, "glass", 1, true) ~= nil
        if enabled("Glass reflections") and (material == Enum.Material.Glass
            or (plastic and window and part.Transparency >= 0.1)) then return 0.22 end
        if enabled("Wet surfaces") and part.Transparency <= 0.05 and floorShape(part)
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
        if style and externalSurface(part, record) then style, faces = nil, nil end
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
                    -- ColorMapContent is the current Decal/Texture API;
                    -- older clients still expose the legacy Texture field.
                    local assigned: boolean = pcall(function(): ()
                        texture.ColorMapContent = Content.fromUri(asset)
                    end)
                    if not assigned then texture.Texture = asset end
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
        if color then color:Destroy(); color = nil end
        if bloom then bloom:Destroy(); bloom = nil end
        if rays then rays:Destroy(); rays = nil end
    end

    local function makeEffect(className: string, name: string): any
        local effect: any = Instance.new(className)
        effect.Name, effect.Parent = name, lighting
        return effect
    end

    card = context.framework.Categories.Render:CreateModule({
        Name = "Shaders", Category = "Render", ConfigKey = "Universal.Shaders",
        Tooltip = "Warm lighting, local floor reflections and optional atmosphere.",
        Function = function(on: boolean): ()
            if not on then card:SetStatus(nil); return end
            cleanup()
            card:Clean(cleanup)
            local ok, failure = pcall(function(): ()
                color = makeEffect("ColorCorrectionEffect", "ARMShaderColor")
                bloom = makeEffect("BloomEffect", "ARMShaderBloom")
                rays = makeEffect("SunRaysEffect", "ARMShaderRays")
                color.Brightness, color.Contrast, color.Saturation = 0, 0.08, 0.05
                color.TintColor, color.Enabled = Color3.fromRGB(255, 247, 236), true
                bloom.Intensity, bloom.Size, bloom.Threshold, bloom.Enabled = 0.2, 24, 0.95, true
                rays.Intensity, rays.Spread, rays.Enabled = 0.1, 0.6, true
                applyLighting()
                if lighting.ChildAdded then table.insert(fogConnections, lighting.ChildAdded:Connect(watchAtmosphere)) end
                if lighting.ChildRemoved then table.insert(fogConnections, lighting.ChildRemoved:Connect(watchAtmosphere)) end
                refreshFog()
                refreshWater()
                refreshFloorReflection()
                refreshSurfaces()
                changeWeather()
            end)
            if not ok then card:Toggle(false); error(failure, 0) end
        end,
    })

    card:CreateToggle({Name = "Floor reflections", Default = true, Function = function(): ()
        refreshFloorReflection(); refreshSurfaces()
    end,
        Tooltip = "Client-only mirror approximation on a few visible flat floors; not screen-space reflections."})
    card:CreateToggle({Name = "Surface textures", Default = true, Function = refreshSurfaces,
        Tooltip = "Incremental map-wide colour detail on eligible blocks; no meshes or existing decals."})
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
