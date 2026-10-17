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
    local low, mid, high = Color3.fromRGB(255,70,70), Color3.fromRGB(255,220,60), Color3.fromRGB(85,255,85)
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
    -- Vape Health is a simple number + heart near the crosshair, not a card.
    hud = create("TextLabel", {Name="SelfHP",Parent=host.ScreenGui,
        AnchorPoint=Vector2.new(0.5,0),Position=UDim2.new(0.5,6,0.5,30),Size=UDim2.fromOffset(140,24),
        BackgroundTransparency=1,BorderSizePixel=0,Visible=false,ZIndex=20,
        Text="",Font=Enum.Font.Arial,TextSize=18,TextStrokeTransparency=1,TextColor3=healthColour(1)})
    local scale = create("UIScale", {Parent=hud,Scale=1})
    local card
    local function clear()
        render:ReleaseAll(layer); table.clear(tracked); layer.Visible = false
        hud.Visible = false; hud.Text = ""
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
                        drawing:Show(true); drawing:Bar(Vector2.new(rect.left-2,rect.top), rect.height, fraction)
                        if options["Health text"].Value then
                            drawing:Label("HP", tostring(math.ceil(health)), Vector2.new(rect.left-14,rect.top+(1-fraction)*rect.height), 0.5, 12, healthColour(fraction), false)
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
                    local wanted = humanoid and humanoid.Health > 0 and tostring(math.ceil(health)) .. " ❤️" or ""
                    if hud.Text ~= wanted then hud.Text = wanted end
                    hud.TextColor3 = healthColour(fraction)
                    hud.Position = options["Self HP position"].Value == "Bottom" and UDim2.new(0.5,0,1,-110) or UDim2.new(0.5,6,0.5,30)
                    local wantedScale = options["Self HP scale"].Value
                    if camera then wantedScale = math.min(wantedScale, math.max(0.5, (camera.ViewportSize.X - 24) / 140)) end
                    scale.Scale = wantedScale
                end
                card:SetStatus(options["Self HP"].Value and tostring(count) .. " + self" or tostring(count))
            end)
        end})
    card:CreateToggle({Name = "Players", Default = true})
    card:CreateToggle({Name = "Health text", Default = false, Show = {Option = "Players"}})
    card:CreateSlider({Name = "Max distance", Min = 50, Max = 5000, Default = 2000, Show = {Option = "Players"}})
    card:CreateToggle({Name = "Teammates", Default = true, Show = {Option = "Players"}})
    card:CreateToggle({Name = "Through walls", Default = true, Show = {Option = "Players"}})
    card:CreateToggle({Name = "Self HP", Default = false})
    card:CreateDropdown({Name="Self HP position",List={"Center","Bottom"},Index=1,Show={Option="Self HP"}})
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
