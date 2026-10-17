local Module = {Name = "HP", Initialized = false}
local activeCard, cleanup, hud, roleBinding

-- Shared by world bars and Self HP; finite/max-health guards avoid NaN UI sizes.
local function healthValues(health, maximum)
    if type(health) ~= "number" or health ~= health or math.abs(health) == math.huge then health = 0 end
    if type(maximum) ~= "number" or maximum ~= maximum or maximum <= 0 or maximum == math.huge then maximum = 100 end
    health = math.max(0, health)
    return health, maximum, math.clamp(health / maximum, 0, 1)
end
local function healthColour(fraction)
    local low, mid, high = Color3.fromRGB(244,78,95), Color3.fromRGB(246,193,76), Color3.fromRGB(89,218,151)
    return fraction < 0.5 and low:Lerp(mid, fraction * 2) or mid:Lerp(high, (fraction - 0.5) * 2)
end

function Module.init(context: any): any
    local host, render, entity = context.host, context.render, context.entity
    local create = host.create
    local layer, tracked = render:Layer("HPLayer"), {}
    local store = host.configData
    if store and store.states["Universal.HP"] == nil then
        store.states["Universal.HP"] = store.states["Universal.PlayerESP"] == true
            and (store.states["Universal.PlayerESP.Healthbar"] ~= false or store.states["Universal.PlayerESP.Healthtext"] == true)
    end
    -- Native text supports Unicode heart glyphs, unlike the menu's bitmap font.
    hud = create("Frame", {Name = "SelfHP", Parent = host.ScreenGui, AnchorPoint = Vector2.new(0.5,1),
        Position = UDim2.new(0.5,0,1,-110), Size = UDim2.fromOffset(156,36),
        BackgroundColor3 = Color3.fromRGB(24,24,24), BackgroundTransparency = 0.35, BorderSizePixel = 0, Visible = false, ZIndex = 20})
    if host.ThemeEngine then host.ThemeEngine.Bind(hud,"BackgroundColor3","background") end
    local scale = create("UIScale", {Parent = hud, Scale = 1})
    local function label(name, text, position, size, font, textSize)
        return create("TextLabel", {Name = name, Parent = hud, Position = position, Size = size, BackgroundTransparency = 1,
            Text = text, Font = font, TextSize = textSize, TextColor3 = Color3.fromRGB(241,245,250), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22})
    end
    local heart = label("Heart", "❤️", UDim2.fromOffset(8,4), UDim2.fromOffset(24,24), Enum.Font.Gotham, 18)
    local value = label("Value", "", UDim2.fromOffset(37,4), UDim2.fromOffset(110,24), Enum.Font.Code, 16)
    value.TextScaled = true
    create("UITextSizeConstraint", {Parent = value, MinTextSize = 12, MaxTextSize = 16})
    local track = create("Frame", {Name = "Track", Parent = hud, Position = UDim2.fromOffset(8,31), Size = UDim2.new(1,-16,0,2),
        BackgroundColor3 = Color3.fromRGB(43,49,62), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 21})
    local trail = create("Frame", {Name = "Damage", Parent = track, Size = UDim2.fromScale(1,1), BackgroundColor3 = Color3.fromRGB(247,186,103), BorderSizePixel = 0, ZIndex = 22})
    local fill = create("Frame", {Name = "Fill", Parent = track, Size = UDim2.fromScale(1,1), BackgroundColor3 = healthColour(1), BorderSizePixel = 0, ZIndex = 23})
    local lastCharacter, delayed = nil, 1
    local card
    local function clear()
        render:ReleaseAll(layer); table.clear(tracked); layer.Visible = false
        hud.Visible = false; lastCharacter = nil; delayed = 1
    end
    card = context.framework.Categories.Visuals:CreateModule({Name = "HP", Category = "Render", ConfigKey = "Universal.HP", Order = 4,
        Tooltip = "Independent player health bars and optional heart-style Self HP display.", Function = function(enabled)
            if not enabled then clear(); card:SetStatus(nil); return end
            card:Clean(clear)
            card:Render(function(dt)
                local options = card.Options
                local targets = entity:Refresh()
                local camera = (host.workspace or workspace).CurrentCamera
                layer.Visible = true
                local seen, count = {}, 0
                if camera and options.Players.Value then
                    for _, target in ipairs(targets) do
                        if not target.Player or target.Health <= 0 or target.Distance > options["Max distance"].Value
                            or not (roleBinding.provider and roleBinding.provider.ReplacesTeams) and not options.Teammates.Value and target.IsFriendly then continue end
                        local rect = render:ModelRect(camera,target.Character)
                        if not rect or not options["Through walls"].Value and not entity:VisibleFrom(target) then continue end
                        local health, maximum, fraction = healthValues(target.Health,target.MaxHealth)
                        local drawing = render:Set(layer,target.Player)
                        drawing:Show(true); drawing:Bar(Vector2.new(rect.left-5,rect.top), rect.height, fraction)
                        if options["Health text"].Value then
                            drawing:Label("HP", tostring(math.ceil(health)), Vector2.new(rect.left-24,rect.top), 0, 12, healthColour(fraction), true)
                        else drawing:HideLabel("HP") end
                        tracked[target.Player] = true; seen[target.Player] = true; count += 1
                    end
                end
                for player in pairs(tracked) do if not seen[player] then render:Release(layer,player); tracked[player] = nil end end
                hud.Visible = options["Self HP"].Value
                if hud.Visible then
                    local character = host.LocalPlayer.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    local health, maximum, fraction = healthValues(humanoid and humanoid.Health, humanoid and humanoid.MaxHealth)
                    if character ~= lastCharacter then delayed = fraction; lastCharacter = character end
                    delayed = math.max(fraction, delayed + (fraction - delayed) * (1-math.exp(-4*math.clamp(dt or 1/60,0,0.1))))
                    local colour = healthColour(fraction)
                    local wanted = tostring(math.ceil(health)) .. " / " .. tostring(math.ceil(maximum))
                    if value.Text ~= wanted then value.Text = wanted end
                    heart.TextColor3 = colour; fill.BackgroundColor3 = colour
                    fill.Size = UDim2.fromScale(fraction,1); trail.Size = UDim2.fromScale(delayed,1)
                    local wantedScale = options["Self HP scale"].Value
                    if camera then wantedScale = math.min(wantedScale, math.max(0.5, (camera.ViewportSize.X - 24) / 156)) end
                    scale.Scale = wantedScale
                end
                card:SetStatus(options["Self HP"].Value and tostring(count) .. " + self" or tostring(count))
            end)
        end})
    card:CreateToggle({Name = "Players", Default = true})
    card:CreateToggle({Name = "Health text", Default = true, Show = {Option = "Players"}})
    card:CreateSlider({Name = "Max distance", Min = 50, Max = 5000, Default = 2000, Show = {Option = "Players"}})
    card:CreateToggle({Name = "Teammates", Default = true, Show = {Option = "Players"}})
    card:CreateToggle({Name = "Through walls", Default = true, Show = {Option = "Players"}})
    card:CreateToggle({Name = "Self HP", Default = false})
    card:CreateSlider({Name = "Self HP scale", Min = 0.8, Max = 1.6, Decimal = 1, Default = 1, Show = {Option = "Self HP"}})
    roleBinding = context.services.gameRoles:Bind(card, {palette = false})
    card.OptionFilter = function(name)
        return not (name == "Teammates" and roleBinding.provider and roleBinding.provider.ReplacesTeams)
    end
    card:RefreshVisibility()
    activeCard, cleanup = card, clear
    Module.Initialized = true
    return card
end
function Module.destroy()
    if activeCard and activeCard.Enabled then activeCard:Toggle(false) end
    if cleanup then cleanup() end
    if hud then hud:Destroy() end
    if roleBinding then roleBinding:Destroy() end
    activeCard, cleanup, hud, roleBinding = nil, nil, nil, nil
    Module.Initialized = false
end
return Module
