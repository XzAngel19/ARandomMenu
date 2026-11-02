-- Client-side Roblox post effects and lightweight weather. The Photoreal,
-- Golden Hour, Blue Hour and Overcast grades adapt the post-processing presets
-- from HathuwstAlkan/Roblox-Skyscraper-Lighting (MIT). Weather adapts the
-- camera-centred, roof-aware particle idea from ShaderCloud/rbxts-weather (ISC),
-- but uses four emitters and staggered raycasts rather than its large grids.
-- Licences, pinned revisions and texture credits: docs/third-party/shaders/.
local Module = {Name = "Shaders", PlaceId = 0, Initialized = false}
local card

-- The original looks and their manual controls remain available. The imported
-- presets keep the old slider defaults as offsets, so existing profiles work.
local LOOKS = {
    {name = "None", saturation = 0, contrast = 0, brightness = 0, bloom = 0, rays = 0},
    {name = "Photoreal", saturation = 0.05, contrast = 0.10, brightness = 0.01,
        bloom = -0.28, rays = -0.15, bloomSize = 22, bloomThreshold = 2.0},
    {name = "Golden Hour", saturation = 0.10, contrast = 0.12, brightness = 0.03,
        bloom = -0.18, rays = -0.05, bloomSize = 26, bloomThreshold = 1.6,
        tint = Color3.fromRGB(255, 246, 236), tintWeight = 0.6},
    {name = "Blue Hour", saturation = 0.04, contrast = 0.10, brightness = 0.01,
        bloom = -0.38, rays = -0.12, bloomSize = 14, bloomThreshold = 2.2,
        tint = Color3.fromRGB(255, 250, 245), tintWeight = 0.6},
    {name = "Overcast", saturation = -0.05, contrast = 0.08, brightness = -0.01,
        bloom = -0.35, rays = -0.18, bloomSize = 20, bloomThreshold = 1.9,
        tint = Color3.fromRGB(235, 240, 245), tintWeight = 0.6},
    {name = "Cinematic", saturation = 0.10, contrast = 0.12, brightness = 0.01,
        bloom = 0, rays = 0, tint = Color3.fromRGB(255, 240, 226), tintWeight = 0.25},
    {name = "Vivid", saturation = 0.35, contrast = 0.1, brightness = 0.02,
        bloom = 0.2, rays = 0.1},
    {name = "Neon", saturation = 0.6, contrast = 0.2, brightness = 0.04,
        bloom = 1, rays = 0.5, tint = Color3.fromRGB(240, 250, 255), tintWeight = 0.25},
    {name = "Noir", saturation = -1, contrast = 0.28, brightness = -0.02,
        bloom = 0.1, rays = 0},
    {name = "Warm", saturation = 0.1, contrast = 0.05, brightness = 0.03,
        bloom = 0.25, rays = 0.3, tint = Color3.fromRGB(255, 214, 170), tintWeight = 0.6},
    {name = "Frost", saturation = -0.05, contrast = 0.12, brightness = 0.02,
        bloom = 0.3, rays = 0.15, tint = Color3.fromRGB(190, 225, 255), tintWeight = 0.55},
    {name = "Dream", saturation = 0.15, contrast = -0.12, brightness = 0.06,
        bloom = 1.4, rays = 0.7, tint = Color3.fromRGB(235, 225, 255), tintWeight = 0.35},
}

local LOOK_NAMES = {}
local LOOK_BY_NAME = {}
for _, look in ipairs(LOOKS) do
    table.insert(LOOK_NAMES, look.name)
    LOOK_BY_NAME[look.name] = look
end

local WEATHER = {
    Rain = {asset = "shaderRainTexture", fallback = "rbxasset://textures/particles/SquareParticle.png",
        rate = 15, size = 0.45, speedMin = 45, speedMax = 50, lifetime = 0.85,
        transparency = 0.38, spread = 1},
    Snow = {asset = "shaderSnowTexture", fallback = "rbxasset://textures/particles/smoke_main.dds",
        rate = 7, size = 0.35, speedMin = 6, speedMax = 9, lifetime = 4,
        transparency = 0.18, spread = 12},
    Autumn = {asset = "shaderAutumnTexture", fallback = "rbxassetid://80805595237760",
        rate = 3, size = 0.9, speedMin = 4, speedMax = 6, lifetime = 4,
        transparency = 0.10, spread = 18},
}

function Module.init(context: any): any
    local host: any = context.host
    local lighting: Lighting = host.Lighting
    local world: Workspace = host.workspace
    local color: ColorCorrectionEffect? = nil
    local bloom: BloomEffect? = nil
    local rays: SunRaysEffect? = nil
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

    local function updateStatus(): ()
        if not card or not card.Enabled then return end
        local opts: any = card.Options
        if not opts.Look or not opts.Weather or not opts.Fog then return end
        local parts: {string} = {}
        if opts.Look.Value ~= "None" then table.insert(parts, opts.Look.Value) end
        if opts.Weather.Value ~= "Clear" then table.insert(parts, opts.Weather.Value) end
        if opts.Fog.Value then table.insert(parts, "Fog") end
        card:SetStatus(if #parts == 0 then nil else table.concat(parts, " · "))
    end

    local function releaseFog(): ()
        local atmosphere: Atmosphere? = fogAtmosphere
        local owned: boolean = fogOwned
        local original: {[string]: any} = fogOriginal
        local applied: {[string]: any} = fogApplied
        fogAtmosphere = nil
        fogOwned = false
        fogOriginal = {}
        fogApplied = {}
        if not atmosphere then return end
        if owned then
            pcall(function(): () atmosphere:Destroy() end)
        else
            -- Do not undo a value another game script changed after us.
            for property: string, value: any in pairs(applied) do
                pcall(function(): ()
                    if (atmosphere :: any)[property] == value then
                        (atmosphere :: any)[property] = original[property]
                    end
                end)
            end
        end
    end

    local function refreshFog(): ()
        if fogMutating then return end
        fogMutating = true
        if not card or not card.Enabled or not card.Options.Fog or not card.Options.Fog.Value then
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
        fogAtmosphere = atmosphere
        fogOwned = external == nil
        local values: {[string]: any} = {
            Density = 0.38, Offset = 0.25, Haze = 1.25, Glare = 0.1,
            Color = Color3.fromRGB(220, 229, 238),
            Decay = Color3.fromRGB(155, 170, 185),
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
        if not object:IsA("Atmosphere") or fogMutating or fogQueued
            or not card or not card.Enabled or not card.Options.Fog
            or not card.Options.Fog.Value then return end
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
        if not card or not card.Enabled or not card.Options.Weather then return end
        local mode: string = card.Options.Weather.Value
        local style: any = WEATHER[mode]
        if not style then updateStatus(); return end
        local generation: number = weatherGeneration
        local ok: boolean, failure: any = pcall(function(): ()
            local folder: Folder = Instance.new("Folder")
            weatherFolder = folder
            folder.Name = "ARMShaderWeather"
            folder.Parent = world
            -- Four non-colliding 24x24 cells, with rates capped per cell.
            for _, offset: Vector3 in ipairs({
                Vector3.new(-12, 0, -12), Vector3.new(-12, 0, 12),
                Vector3.new(12, 0, -12), Vector3.new(12, 0, 12),
            }) do
                local part: Part = Instance.new("Part")
                part.Name = "WeatherCell"
                part.Anchored = true
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
                part.CastShadow = false
                part.Transparency = 1
                part.Size = Vector3.new(24, 0.2, 24)
                part.Parent = folder
                local emitter: ParticleEmitter = Instance.new("ParticleEmitter")
                emitter.Name = mode
                emitter.Enabled = false
                emitter.Texture = style.fallback
                emitter.Shape = Enum.ParticleEmitterShape.Box
                emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
                emitter.EmissionDirection = Enum.NormalId.Bottom
                emitter.Orientation = if mode == "Rain"
                    then Enum.ParticleOrientation.VelocityParallel
                    else Enum.ParticleOrientation.FacingCamera
                emitter.Rate = style.rate
                emitter.Size = NumberSequence.new(style.size)
                emitter.Speed = NumberRange.new(style.speedMin, style.speedMax)
                emitter.Lifetime = NumberRange.new(style.lifetime)
                emitter.Transparency = NumberSequence.new(style.transparency)
                emitter.SpreadAngle = Vector2.new(style.spread, style.spread)
                emitter.LightInfluence = 0.8
                emitter.LightEmission = if mode == "Snow" then 0.2 else 0.05
                if mode == "Rain" then
                    emitter.Squash = NumberSequence.new(-2.5)
                    emitter.Color = ColorSequence.new(Color3.fromRGB(205, 219, 235))
                else
                    emitter.Rotation = NumberRange.new(0, 360)
                    emitter.RotSpeed = NumberRange.new(-45, 45)
                end
                emitter.Parent = part
                table.insert(weatherCells, {part = part, emitter = emitter, offset = offset})
            end
            local params: RaycastParams = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.IgnoreWater = true
            local previousCharacter: Model? = nil
            local lastFocus: Vector3? = nil
            local lastCamera: Camera? = nil
            local moveElapsed: number = 0
            local roofElapsed: number = 0.15
            local roofIndex: number = 0
            local function updateWeather(deltaTime: number): ()
                -- Part positions are updated at most 20 times/s, not every
                -- rendered frame. One roof ray per 0.15 s is staggered.
                moveElapsed += math.clamp(deltaTime, 0, 0.25)
                if moveElapsed < 0.05 then return end
                local elapsed: number = moveElapsed
                moveElapsed = 0
                local camera: Camera? = world.CurrentCamera
                if not camera then
                    for _, cell: any in ipairs(weatherCells) do cell.emitter.Enabled = false end
                    lastCamera = nil
                    lastFocus = nil
                    return
                end
                local focus: Vector3 = camera.CFrame.Position
                if camera ~= lastCamera or (lastFocus and (focus - lastFocus).Magnitude > 30) then
                    -- Recheck each cell after a jump, without bypassing the
                    -- global ray interval during rapid camera changes.
                    for _, cell: any in ipairs(weatherCells) do cell.emitter.Enabled = false end
                end
                lastCamera = camera
                lastFocus = focus
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
                roofElapsed += elapsed
                if roofElapsed < 0.15 then return end
                roofElapsed = 0
                roofIndex = roofIndex % #weatherCells + 1
                local cell: any = weatherCells[roofIndex]
                local castOk: boolean, hit: any = pcall(function(): any
                    return world:Raycast(focus + cell.offset, Vector3.new(0, 150, 0), params)
                end)
                local covered: boolean = castOk and hit ~= nil
                if covered and hit.Instance and hit.Instance:IsA("BasePart")
                    and hit.Instance.Transparency >= 0.95 then
                    covered = false
                end
                cell.emitter.Enabled = not covered
            end
            weatherConnection = host.TaskManager:Connect(updateWeather, nil, "Shaders weather")
            -- Begin with a built-in texture. Network/file work never blocks a frame.
            task.spawn(function(): ()
                local state: any = host.state
                if not state or type(state.resolveAsset) ~= "function" then return end
                local resolved: boolean, asset: any = pcall(state.resolveAsset, style.asset)
                if not resolved or type(asset) ~= "string" or asset == ""
                    or generation ~= weatherGeneration or not card or not card.Enabled then return end
                for _, cell: any in ipairs(weatherCells) do
                    cell.emitter.Texture = asset
                end
            end)
        end)
        if not ok then
            stopWeather()
            warn("[Shaders] Weather unavailable: " .. tostring(failure))
            card:Notify("Weather unavailable; the colour effects are still active")
        end
        updateStatus()
    end

    local function cleanup(): ()
        stopWeather()
        for _, connection: any in ipairs(fogConnections) do
            pcall(function(): () connection:Disconnect() end)
        end
        fogConnections = {}
        fogMutating = true
        releaseFog()
        fogMutating = false
        if color then color:Destroy(); color = nil end
        if bloom then bloom:Destroy(); bloom = nil end
        if rays then rays:Destroy(); rays = nil end
    end

    local function makeEffect(className: string, name: string): any
        local effect: any = Instance.new(className)
        effect.Name = name
        effect.Parent = lighting
        return effect
    end

    local function apply(): ()
        -- Widget restoration can call this while the card is being built.
        if not card or not card.Enabled or not color or not bloom or not rays then return end
        local opts: any = card.Options
        local look: any = LOOK_BY_NAME[opts.Look.Value] or LOOKS[1]
        local tint: Color3 = opts.Tint.Value
        if look.tint then tint = tint:Lerp(look.tint, look.tintWeight) end
        -- Old saved/typed values can exceed slider ranges. Never apply a
        -- documented blackout brightness or a black multiplicative tint.
        color.Saturation = math.clamp(opts.Saturation.Value + look.saturation, -1, 1)
        color.Contrast = math.clamp(opts.Contrast.Value + look.contrast, -0.35, 0.25)
        color.Brightness = math.clamp(opts.Brightness.Value + look.brightness, -0.05, 0.3)
        color.TintColor = Color3.new(math.clamp(tint.R, 0.6, 1),
            math.clamp(tint.G, 0.6, 1), math.clamp(tint.B, 0.6, 1))
        color.Enabled = true
        bloom.Intensity = math.clamp(opts.Bloom.Value + look.bloom, 0, 10)
        bloom.Size = math.clamp(opts["Bloom size"].Value + (look.bloomSize or 24) - 24, 0, 56)
        bloom.Threshold = math.clamp(opts["Bloom threshold"].Value + (look.bloomThreshold or 1.1) - 1.1, 0, 5)
        bloom.Enabled = bloom.Intensity > 0.01
        rays.Intensity = math.clamp(opts["Sun rays"].Value + look.rays, 0, 1)
        rays.Spread = math.clamp(opts["Ray spread"].Value, 0, 1)
        rays.Enabled = rays.Intensity > 0.01
        updateStatus()
    end

    local function diagnose(): ()
        if not color or not bloom or not rays then
            print("[Shaders] off")
            card:Notify("Shaders is off")
            return
        end
        local text: string = string.format(
            "[Shaders] Look=%s; Color: parent=%s enabled=%s brightness=%.2f contrast=%.2f saturation=%.2f tint=(%.2f,%.2f,%.2f); Bloom: parent=%s enabled=%s intensity=%.2f; Rays: parent=%s enabled=%s intensity=%.2f",
            card.Options.Look.Value, color.Parent and color.Parent.Name or "nil", tostring(color.Enabled),
            color.Brightness, color.Contrast, color.Saturation, color.TintColor.R, color.TintColor.G, color.TintColor.B,
            bloom.Parent and bloom.Parent.Name or "nil", tostring(bloom.Enabled), bloom.Intensity,
            rays.Parent and rays.Parent.Name or "nil", tostring(rays.Enabled), rays.Intensity
        )
        print(text)
        local parents = {lighting}
        local camera: Camera? = world.CurrentCamera
        if camera then table.insert(parents, camera) end
        for _, parent in ipairs(parents) do
            for _, other in ipairs(parent:GetChildren()) do
                if other ~= color and other:IsA("ColorCorrectionEffect") and other.Enabled then
                    local tint: Color3 = other.TintColor
                    print(string.format("[Shaders] Other color: parent=%s name=%s brightness=%.2f contrast=%.2f saturation=%.2f tint=(%.2f,%.2f,%.2f)",
                        parent.Name, other.Name, other.Brightness, other.Contrast, other.Saturation, tint.R, tint.G, tint.B))
                end
            end
        end
        card:Notify("Color enabled=" .. tostring(color.Enabled) .. " · details printed to console")
    end

    card = context.framework.Categories.Render:CreateModule({
        Name = "Shaders", Category = "Render", ConfigKey = "Universal.Shaders",
        Tooltip = "Photoreal lighting presets, fog and lightweight client-side weather.",
        Function = function(enabled: boolean): ()
            if not enabled then card:SetStatus(nil); return end
            cleanup()
            card:Clean(cleanup)
            local ok, failure = pcall(function()
                color = makeEffect("ColorCorrectionEffect", "ARMShaderColor")
                bloom = makeEffect("BloomEffect", "ARMShaderBloom")
                rays = makeEffect("SunRaysEffect", "ARMShaderRays")
                if lighting.ChildAdded then table.insert(fogConnections, lighting.ChildAdded:Connect(watchAtmosphere)) end
                if lighting.ChildRemoved then table.insert(fogConnections, lighting.ChildRemoved:Connect(watchAtmosphere)) end
                apply()
                refreshFog()
                changeWeather()
            end)
            if not ok then
                card:Toggle(false)
                error(failure, 0)
            end
        end,
    })

    card:CreateDropdown({Name = "Look", List = LOOK_NAMES, Index = 2, Function = apply,
        Tooltip = "Photoreal presets plus the original colour looks."})
    card:CreateDropdown({Name = "Weather", List = {"Clear", "Rain", "Snow", "Autumn"},
        Index = 1, Function = changeWeather, Tooltip = "Lightweight particles around the camera; roofs limit them."})
    card:CreateToggle({Name = "Fog", Default = false, Function = refreshFog,
        Tooltip = "Adds atmospheric fog locally without deleting the game's effects."})
    card:CreateToggle({Name = "Advanced", Default = false,
        Tooltip = "Show the original manual colour, bloom and sun-ray controls."})
    local advanced = {Option = "Advanced"}
    local function slider(name: string, min: number, max: number, default: number,
        tooltip: string, fractional: boolean): ()
        card:CreateSlider({Name = name, Min = min, Max = max, Default = default,
            Decimal = if fractional then 2 else nil, Step = if fractional then 0.01 else nil,
            Function = apply, Tooltip = tooltip, Show = advanced})
    end
    slider("Saturation", -1, 1, 0, "Negative drains colour, positive boosts it.", true)
    slider("Contrast", -0.35, 0.25, 0, "Separates dark from light; limited to preserve detail.", true)
    slider("Brightness", -0.05, 0.3, 0, "Applied brightness is limited to avoid a black screen.", true)
    card:CreateColor({Name = "Tint", Default = Color3.fromRGB(255, 255, 255),
        Function = apply, Tooltip = "Colour cast blended with the look; very dark colours are lightened.", Show = advanced})
    slider("Bloom", 0, 2, 0.6, "Glow around bright surfaces; zero disables it.", true)
    slider("Bloom threshold", 0, 3, 1.1, "Brightness needed for glow.", true)
    slider("Bloom size", 0, 56, 24, "Spread of the glow.", false)
    slider("Sun rays", 0, 1, 0.2, "Rays around the sun; zero disables them.", true)
    slider("Ray spread", 0, 1, 0.5, "Width of the sun rays.", true)
    card:CreateButton({Name = "Diagnose", Function = diagnose,
        Tooltip = "Print the effects' actual parents and enabled states.", Show = advanced})
    card:CreateNote("Client-side only. Graphics quality can suppress effects; weather textures fall back if download is unavailable.")

    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if card and card.Enabled then card:Toggle(false) end
    card = nil
    Module.Initialized = false
end

return Module
