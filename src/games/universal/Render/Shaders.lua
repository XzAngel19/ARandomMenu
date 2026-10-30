-- Shaders: colour grading and light bloom for the whole scene, built only on
-- the engine's own post-processing effects. No executor functions, no image
-- assets, nothing that writes to a remote: it is a camera/look module.
--
-- Everything it creates lives under one folder in Lighting and is destroyed
-- when the module is turned off. Nothing else in Lighting is touched, and there
-- is no loop: an option changes the effect objects once and stops.
local Module = {Name = "Shaders", PlaceId = 0, Initialized = false}
local card

-- A look is an OFFSET on top of the manual sliders, never a value that
-- overwrites them. Choosing "Neon" and then raising Saturation keeps both, and
-- no widget has to be written to from code (which is what made the old
-- preset-driven modules fight their own UI).
local LOOKS = {
    {name = "None", saturation = 0, contrast = 0, brightness = 0,
        bloom = 0, rays = 0, tint = nil, tintWeight = 0},
    {name = "Cinematic", saturation = -0.12, contrast = 0.16, brightness = -0.01,
        bloom = 0.35, rays = 0.2, tint = Color3.fromRGB(255, 236, 214),
        tintWeight = 0.45},
    {name = "Vivid", saturation = 0.35, contrast = 0.1, brightness = 0.02,
        bloom = 0.2, rays = 0.1, tint = nil, tintWeight = 0},
    {name = "Neon", saturation = 0.6, contrast = 0.2, brightness = 0.04,
        bloom = 1, rays = 0.5, tint = Color3.fromRGB(240, 250, 255),
        tintWeight = 0.25},
    {name = "Noir", saturation = -1, contrast = 0.28, brightness = -0.02,
        bloom = 0.1, rays = 0, tint = nil, tintWeight = 0},
    {name = "Warm", saturation = 0.1, contrast = 0.05, brightness = 0.03,
        bloom = 0.25, rays = 0.3, tint = Color3.fromRGB(255, 214, 170),
        tintWeight = 0.6},
    {name = "Frost", saturation = -0.05, contrast = 0.12, brightness = 0.02,
        bloom = 0.3, rays = 0.15, tint = Color3.fromRGB(190, 225, 255),
        tintWeight = 0.55},
    {name = "Dream", saturation = 0.15, contrast = -0.12, brightness = 0.06,
        bloom = 1.4, rays = 0.7, tint = Color3.fromRGB(235, 225, 255),
        tintWeight = 0.35},
}

local LOOK_NAMES: {string} = {}
for _, look in ipairs(LOOKS) do
    table.insert(LOOK_NAMES, look.name)
end

local function lookFor(name: any): any
    for _, look in ipairs(LOOKS) do
        if look.name == name then
            return look
        end
    end
    return LOOKS[1]
end

-- Colour grading is a look, so the values are clamped to the ranges the effect
-- accepts: a slider at its limit plus a look must not be rejected by the
-- engine and silently stop updating everything else.
local function clamped(value: any, low: number, high: number): number
    local number = tonumber(value) or 0
    if number ~= number then
        number = 0
    end
    return math.clamp(number, low, high)
end

function Module.init(context: any): any
    -- `host.Lighting` is the wrapper the rest of the menu uses; the service is
    -- the fallback, because a module that silently creates nothing when the
    -- environment table is missing one key looks exactly like "it does
    -- nothing".
    local lighting = context.host and context.host.Lighting
    if not lighting then
        pcall(function(): ()
            lighting = game:GetService("Lighting")
        end)
    end
    local folder: Instance? = nil
    local color: any = nil
    local bloom: any = nil
    local rays: any = nil
    local destroyed: boolean = false
    -- v162: apply() used to bail out when `card.Enabled` was false. The card is
    -- not "enabled" until the toggle callback has returned, so the very first
    -- apply did nothing and the module appeared dead until an option was
    -- touched. This flag is set by the callback itself.
    local active: boolean = false

    local function createEffect(className: string, name: string): any
        local parent: any = folder
        if not parent then
            return nil
        end
        local ok: boolean, effect: any = pcall(function(): any
            local instance = Instance.new(className)
            instance.Name = name
            instance.Parent = parent
            return instance
        end)
        if ok and effect then
            return effect
        end
        return nil
    end

    local function cleanup(): ()
        for _, effect in ipairs({color, bloom, rays}) do
            if effect then
                pcall(function(): ()
                    effect.Enabled = false
                end)
            end
        end
        color, bloom, rays = nil, nil, nil
        if folder then
            pcall(function(): ()
                folder:Destroy()
            end)
            folder = nil
        end
        destroyed = true
    end

    local function ensureEffects(): boolean
        if color then
            return true
        end
        destroyed = false
        local ok: boolean, created: any = pcall(function(): any
            local parent = Instance.new("Folder")
            parent.Name = "ARandomMenuShaders"
            parent.Parent = lighting
            return parent
        end)
        if not ok or not created then
            return false
        end
        folder = created
        color = createEffect("ColorCorrectionEffect", "ARMShaderColor")
        bloom = createEffect("BloomEffect", "ARMShaderBloom")
        rays = createEffect("SunRaysEffect", "ARMShaderRays")
        return color ~= nil
    end

    local function lerpColor(from: Color3, to: Color3, alpha: number): Color3
        local weight: number = math.clamp(alpha, 0, 1)
        return Color3.new(
            from.R + (to.R - from.R) * weight,
            from.G + (to.G - from.G) * weight,
            from.B + (to.B - from.B) * weight
        )
    end

    local function options(): any
        return card and card.Options or {}
    end

    local function readOption(name: string, fallback: number): number
        local option = options()[name]
        if option == nil then
            return fallback
        end
        return clamped(option.Value, -1e6, 1e6)
    end

    local function apply(): ()
        if not card or not active then
            return
        end
        if not ensureEffects() then
            card:SetStatus("Post-processing unavailable")
            return
        end
        local look: any = lookFor(options().Look and options().Look.Value)
        if color then
            pcall(function(): ()
                color.Saturation = clamped(
                    readOption("Saturation", 0) + look.saturation,
                    -1,
                    1
                )
                color.Contrast = clamped(
                    readOption("Contrast", 0) + look.contrast,
                    -1,
                    1
                )
                color.Brightness = clamped(
                    readOption("Brightness", 0) + look.brightness,
                    -1,
                    1
                )
                local tint: Color3 = options().Tint and options().Tint.Value
                    or Color3.new(1, 1, 1)
                color.TintColor = look.tint
                        and lerpColor(tint, look.tint, look.tintWeight)
                    or tint
            end)
        end
        if bloom then
            pcall(function(): ()
                local intensity: number = clamped(
                    readOption("Bloom", 0) + look.bloom,
                    0,
                    10
                )
                bloom.Intensity = intensity
                bloom.Size = clamped(readOption("Bloom size", 24), 0, 56)
                bloom.Threshold = clamped(readOption("Bloom threshold", 1.1), 0, 5)
                bloom.Enabled = intensity > 0.01
            end)
        end
        if rays then
            pcall(function(): ()
                local intensity: number = clamped(
                    readOption("Sun rays", 0) + look.rays,
                    0,
                    1
                )
                rays.Intensity = intensity
                rays.Spread = clamped(readOption("Ray spread", 0.5), 0, 1)
                rays.Enabled = intensity > 0.01
            end)
        end
        card:SetStatus(look.name == "None" and nil or look.name)
    end

    card = context.framework.Categories.Render:CreateModule({
        Name = "Shaders",
        Category = "Render",
        ConfigKey = "Universal.Shaders",
        Tooltip = "Colour grading, bloom and sun rays for the whole scene. "
            .. "Engine effects only: nothing is sent to the server.",
        Function = function(enabled: boolean): ()
            active = enabled == true
            if not enabled then
                cleanup()
                card:SetStatus(nil)
                return
            end
            if not ensureEffects() then
                card:SetStatus("Post-processing unavailable")
                return
            end
            card:Clean(cleanup)
            apply()
        end,
    })

    card:CreateDropdown({
        Name = "Look",
        List = LOOK_NAMES,
        -- v162: "Cinematic" by default. "None" is neutral on every channel, so
        -- turning the module on changed nothing at all and the only honest
        -- report the player could make was "it does nothing".
        Index = 2,
        Function = function(): ()
            apply()
        end,
        Tooltip = "A preset that is added on top of the sliders below. "
            .. "None leaves only what you set yourself.",
    })
    card:CreateSlider({
        Name = "Saturation",
        Min = -1,
        Max = 1,
        Default = 0,
        Decimal = 2,
        Function = function(): ()
            apply()
        end,
        Tooltip = "Negative drains colour, positive boosts it.",
    })
    card:CreateSlider({
        Name = "Contrast",
        Min = -0.5,
        Max = 0.5,
        Default = 0,
        Decimal = 2,
        Function = function(): ()
            apply()
        end,
        Tooltip = "Separates dark from light; negative flattens the image.",
    })
    card:CreateSlider({
        Name = "Brightness",
        Min = -0.3,
        Max = 0.3,
        Default = 0,
        Decimal = 2,
        Function = function(): ()
            apply()
        end,
        Tooltip = "Overall exposure of the colour pass.",
    })
    card:CreateColor({
        Name = "Tint",
        Default = Color3.fromRGB(255, 255, 255),
        Function = function(): ()
            apply()
        end,
        Tooltip = "Colour cast for the whole screen. Looks blend toward their "
            .. "own tint on top of it.",
    })
    card:CreateSlider({
        Name = "Bloom",
        Min = 0,
        Max = 2,
        Default = 0.6,
        Decimal = 2,
        Function = function(): ()
            apply()
        end,
        Tooltip = "Glow around bright surfaces. Zero disables the effect.",
    })
    card:CreateSlider({
        Name = "Bloom threshold",
        Min = 0,
        Max = 3,
        Default = 1.1,
        Decimal = 2,
        Function = function(): ()
            apply()
        end,
        Tooltip = "How bright a surface must be before it glows.",
    })
    card:CreateSlider({
        Name = "Bloom size",
        Min = 0,
        Max = 56,
        Default = 24,
        Function = function(): ()
            apply()
        end,
        Tooltip = "Spread of the glow, in engine units.",
    })
    card:CreateSlider({
        Name = "Sun rays",
        Min = 0,
        Max = 1,
        Default = 0.2,
        Decimal = 2,
        Function = function(): ()
            apply()
        end,
        Tooltip = "Rays around the sun. Zero disables the effect.",
    })
    card:CreateSlider({
        Name = "Ray spread",
        Min = 0,
        Max = 1,
        Default = 0.5,
        Decimal = 2,
        Function = function(): ()
            apply()
        end,
        Tooltip = "How wide the sun rays fan out.",
    })
    card:CreateNote(
        "Colour grading and bloom are client-side post-processing: they change "
            .. "what you see, not what the server or other players receive. "
            .. "Fullbright also raises ambient light; this module does not."
    )

    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if card and card.Enabled then
        card:Toggle(false)
    end
    card = nil
    Module.Initialized = false
end

return Module
