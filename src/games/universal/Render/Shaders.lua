-- Client-side colour grading, bloom and sun rays. Roblox PostEffects must be
-- DIRECT children of Lighting or CurrentCamera: a Folder under Lighting does
-- not render them. We keep our own references and destroy only those effects.
-- No Lighting properties, game-owned effects, or remotes are changed. Rendering
-- still depends on device graphics quality and other modules/game scripts.
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
    local color: any = nil
    local bloom: any = nil
    local rays: any = nil
    local active: boolean = false
    local effectErrors: {[string]: string} = {}

    local function destroyEffect(effect: any): ()
        if effect then
            pcall(function(): ()
                effect:Destroy()
            end)
        end
    end

    local function cleanup(): ()
        -- Do not use ipairs({color, bloom, rays}): a failed first creation
        -- makes a hole that would leak the other two instances.
        destroyEffect(color)
        destroyEffect(bloom)
        destroyEffect(rays)
        color, bloom, rays = nil, nil, nil
        table.clear(effectErrors)
    end

    local function ensureEffect(effect: any, className: string, name: string): any
        if effect then
            local ok: boolean, valid: any = pcall(function(): boolean
                local parent: any = effect.Parent
                -- ClassName also handles executor-cloned service references.
                return parent ~= nil and (parent == lighting or parent.ClassName == "Lighting")
            end)
            if ok and valid then
                return effect
            end
            -- A game may have removed/reparented it since the last option
            -- change. Dispose only the instance this module created.
            destroyEffect(effect)
        end
        if not lighting then
            effectErrors[className] = "Lighting unavailable"
            return nil
        end
        local instance: any = nil
        local ok: boolean, err: any = pcall(function(): ()
            instance = Instance.new(className)
            instance.Name = name
            -- Direct parent is essential; a folder below Lighting is inert.
            instance.Parent = lighting
        end)
        if not ok then
            destroyEffect(instance)
            effectErrors[className] = tostring(err)
            return nil
        end
        effectErrors[className] = nil
        return instance
    end

    local function ensureEffects(): ()
        color = ensureEffect(color, "ColorCorrectionEffect", "ARMShaderColor")
        bloom = ensureEffect(bloom, "BloomEffect", "ARMShaderBloom")
        rays = ensureEffect(rays, "SunRaysEffect", "ARMShaderRays")
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
        ensureEffects()
        local look: any = lookFor(options().Look and options().Look.Value)
        local failures: {string} = {}
        if color then
            local ok: boolean, err: any = pcall(function(): ()
                color.Saturation = clamped(readOption("Saturation", 0) + look.saturation, -1, 1)
                color.Contrast = clamped(readOption("Contrast", 0) + look.contrast, -1, 1)
                color.Brightness = clamped(readOption("Brightness", 0) + look.brightness, -1, 1)
                local tint: Color3 = options().Tint and options().Tint.Value
                    or Color3.new(1, 1, 1)
                color.TintColor = look.tint
                        and lerpColor(tint, look.tint, look.tintWeight)
                    or tint
                color.Enabled = true
            end)
            if not ok then
                effectErrors.ColorCorrectionEffect = tostring(err)
                table.insert(failures, "color")
            else
                effectErrors.ColorCorrectionEffect = nil
            end
        else
            table.insert(failures, "color")
        end
        if bloom then
            local ok: boolean, err: any = pcall(function(): ()
                local intensity: number = clamped(readOption("Bloom", 0) + look.bloom, 0, 10)
                bloom.Intensity = intensity
                bloom.Size = clamped(readOption("Bloom size", 24), 0, 56)
                bloom.Threshold = clamped(readOption("Bloom threshold", 1.1), 0, 5)
                bloom.Enabled = intensity > 0.01
            end)
            if not ok then
                effectErrors.BloomEffect = tostring(err)
                table.insert(failures, "bloom")
            else
                effectErrors.BloomEffect = nil
            end
        else
            table.insert(failures, "bloom")
        end
        if rays then
            local ok: boolean, err: any = pcall(function(): ()
                local intensity: number = clamped(readOption("Sun rays", 0) + look.rays, 0, 1)
                rays.Intensity = intensity
                rays.Spread = clamped(readOption("Ray spread", 0.5), 0, 1)
                rays.Enabled = intensity > 0.01
            end)
            if not ok then
                effectErrors.SunRaysEffect = tostring(err)
                table.insert(failures, "rays")
            else
                effectErrors.SunRaysEffect = nil
            end
        else
            table.insert(failures, "rays")
        end
        if #failures > 0 then
            card:SetStatus("Unavailable: " .. table.concat(failures, ", "))
        elseif look.name == "None" then
            card:SetStatus(nil)
        else
            card:SetStatus(look.name)
        end
    end

    -- The diagnostic reports actual instances and state, not whether the GPU
    -- visibly rendered them. Other scripts and Improve FPS can disable them.
    local function diagnose(): ()
        local function describe(label: string, effect: any): string
            if not effect then
                return label .. ": missing"
            end
            local ok: boolean, result: any = pcall(function(): string
                local parent: any = effect.Parent
                return string.format("%s: parent=%s enabled=%s", label,
                    parent and tostring(parent.Name) or "nil", tostring(effect.Enabled))
            end)
            return ok and result or (label .. ": unreadable")
        end
        local quality: any = "unavailable"
        pcall(function(): ()
            quality = tostring(settings().Rendering.QualityLevel)
        end)
        local lines: {string} = {
            "[Shaders] active=" .. tostring(active)
                .. " look=" .. tostring(options().Look and options().Look.Value or "unknown")
                .. " quality=" .. tostring(quality),
            describe("Color", color),
            describe("Bloom", bloom),
            describe("Rays", rays),
        }
        if color then
            pcall(function(): ()
                table.insert(lines, string.format("Color: saturation=%.2f contrast=%.2f brightness=%.2f",
                    color.Saturation, color.Contrast, color.Brightness))
            end)
        end
        for className: string, message: string in pairs(effectErrors) do
            table.insert(lines, className .. " error: " .. message)
        end
        table.insert(lines, "Rendering can be affected by graphics quality and Disable post effects.")
        print(table.concat(lines, "\n"))
        card:Notify(describe("Color", color) .. " · details printed to console")
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
            -- Register cleanup even when an effect cannot be created.
            card:Clean(cleanup)
            apply()
        end,
    })

    card:CreateDropdown({
        Name = "Look",
        List = LOOK_NAMES,
        -- A preset that is visibly non-neutral when post effects are rendered.
        -- Existing user configuration is not reset.
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
        Step = 0.01,
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
        Step = 0.01,
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
        Step = 0.01,
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
        Step = 0.01,
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
        Step = 0.01,
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
        Step = 0.01,
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
        Step = 0.01,
        Function = function(): ()
            apply()
        end,
        Tooltip = "How wide the sun rays fan out.",
    })
    card:CreateButton({
        Name = "Diagnose",
        Function = diagnose,
        Tooltip = "Print actual effect parents and enabled states to the console.",
    })
    card:CreateNote(
        "Client-side post-processing; appearance depends on graphics quality. "
            .. "Improve FPS > Disable post effects can suppress these effects. "
            .. "Try Noir with Saturation 0 to check the colour pass."
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
