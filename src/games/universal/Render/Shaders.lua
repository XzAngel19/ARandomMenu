-- Roblox's native post-processing effects run as direct children of Lighting.
-- They affect only this client; the game's own effects are left alone.
local Module = {Name = "Shaders", PlaceId = 0, Initialized = false}
local card

-- Presets are added to the manual sliders, so changing a look never overwrites
-- the user's saved controls.
local LOOKS = {
    {name = "None", saturation = 0, contrast = 0, brightness = 0,
        bloom = 0, rays = 0},
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

function Module.init(context: any): any
    local lighting: Lighting = context.host.Lighting
    local color: ColorCorrectionEffect? = nil
    local bloom: BloomEffect? = nil
    local rays: SunRaysEffect? = nil

    local function cleanup(): ()
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
        -- Saved/typed values can exceed slider ranges. Brightness -1 or a
        -- black multiplicative tint makes the entire rendered world black.
        color.Saturation = math.clamp(opts.Saturation.Value + look.saturation, -1, 1)
        color.Contrast = math.clamp(opts.Contrast.Value + look.contrast, -0.35, 0.25)
        color.Brightness = math.clamp(opts.Brightness.Value + look.brightness, -0.05, 0.3)
        color.TintColor = Color3.new(math.clamp(tint.R, 0.6, 1),
            math.clamp(tint.G, 0.6, 1), math.clamp(tint.B, 0.6, 1))
        color.Enabled = true

        bloom.Intensity = math.clamp(opts.Bloom.Value + look.bloom, 0, 10)
        bloom.Size = math.clamp(opts["Bloom size"].Value, 0, 56)
        bloom.Threshold = math.clamp(opts["Bloom threshold"].Value, 0, 5)
        bloom.Enabled = bloom.Intensity > 0.01

        rays.Intensity = math.clamp(opts["Sun rays"].Value + look.rays, 0, 1)
        rays.Spread = math.clamp(opts["Ray spread"].Value, 0, 1)
        rays.Enabled = rays.Intensity > 0.01
        card:SetStatus(if look.name == "None" then nil else look.name)
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
        local camera: Camera? = context.host.workspace.CurrentCamera
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
        Name = "Shaders",
        Category = "Render",
        ConfigKey = "Universal.Shaders",
        Tooltip = "Native Roblox colour grading, bloom and sun rays on this client.",
        Function = function(enabled: boolean): ()
            if not enabled then
                card:SetStatus(nil)
                return
            end
            cleanup()
            card:Clean(cleanup)
            local ok, failure = pcall(function()
                color = makeEffect("ColorCorrectionEffect", "ARMShaderColor")
                bloom = makeEffect("BloomEffect", "ARMShaderBloom")
                rays = makeEffect("SunRaysEffect", "ARMShaderRays")
                apply()
            end)
            if not ok then
                -- Config restoration may catch the error without sending OFF.
                card:Toggle(false)
                error(failure, 0)
            end
        end,
    })

    card:CreateDropdown({Name = "Look", List = LOOK_NAMES, Index = 2, Function = apply,
        Tooltip = "Preset added to the sliders below. None uses only your sliders."})

    local function slider(name: string, min: number, max: number, default: number,
        tooltip: string, fractional: boolean): ()
        card:CreateSlider({Name = name, Min = min, Max = max, Default = default,
            Decimal = if fractional then 2 else nil,
            Step = if fractional then 0.01 else nil,
            Function = apply, Tooltip = tooltip})
    end
    slider("Saturation", -1, 1, 0, "Negative drains colour, positive boosts it.", true)
    slider("Contrast", -0.35, 0.25, 0, "Separates dark from light; limited to preserve detail.", true)
    slider("Brightness", -0.05, 0.3, 0, "Applied brightness is limited to avoid a black screen.", true)
    card:CreateColor({Name = "Tint", Default = Color3.fromRGB(255, 255, 255),
        Function = apply, Tooltip = "Colour cast blended with the look; very dark colours are lightened."})
    slider("Bloom", 0, 2, 0.6, "Glow around bright surfaces; zero disables it.", true)
    slider("Bloom threshold", 0, 3, 1.1, "Brightness needed for glow.", true)
    slider("Bloom size", 0, 56, 24, "Spread of the glow.", false)
    slider("Sun rays", 0, 1, 0.2, "Rays around the sun; zero disables them.", true)
    slider("Ray spread", 0, 1, 0.5, "Width of the sun rays.", true)
    card:CreateButton({Name = "Diagnose", Function = diagnose,
        Tooltip = "Print the effects' actual parents and enabled states."})
    card:CreateNote("Client-side effects depend on graphics quality. Improve FPS > Disable post effects can suppress them.")

    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if card and card.Enabled then card:Toggle(false) end
    card = nil
    Module.Initialized = false
end

return Module
