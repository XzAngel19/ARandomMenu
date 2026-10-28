local Module = {Name = "Nametags", Initialized = false}
local activeCard, cleanup, roleBinding
local BLACK = Color3.new(0, 0, 0)

function Module.init(context: any): any
    local host, entity, render = context.host, context.entity, context.render
    local layer = render:Layer("NametagsLayer")
    local tracked = {}
    local store = host.configData
    -- Preserve explicit new choices; migrate only previously enabled overlays.
    if store and store.states["Universal.Nametags"] == nil then
        local states, values = store.states, store.values
        states["Universal.Nametags"] = states["Universal.Chams"] == true and states["Universal.Chams.Nametags"] == true
            or states["Universal.PlayerESP"] == true and states["Universal.PlayerESP.Nametags"] ~= false
        if values["Universal.Nametags.Textsize"] == nil then values["Universal.Nametags.Textsize"] = values["Universal.PlayerESP.Textsize"] end
        for new, old in pairs({Background="Nameplate",Displayname="Displayname",Heldtool="Heldtool",Showrole="Showrole",Rolecolours="Rolecolours"}) do
            local key = "Universal.Nametags." .. new
            if states[key] == nil then states[key] = states["Universal.PlayerESP." .. old] end
        end
        for key, colour in pairs(table.clone(values)) do
            if string.sub(key,1,20) == "Universal.PlayerESP." and string.lower(string.sub(key,-6)) == "colour" then
                local newKey = "Universal.Nametags." .. string.sub(key,21)
                if values[newKey] == nil then values[newKey] = colour end
            end
        end
    end
    local textService = game:GetService("TextService")
    local card
    local function clear()
        render:ReleaseAll(layer); table.clear(tracked); layer.Visible = false
    end
    local function fit(drawing, slot, text, size, viewport)
        local label = drawing.labels[slot]
        if not label then return end
        local key = text .. ":" .. tostring(size) .. ":" .. tostring(viewport.X)
        drawing.textMetrics = drawing.textMetrics or {}
        -- v139.1: GetTextSize + Size + TextTruncate only when the text or the
        -- size really changed. Writing Size every frame re-laid out every
        -- nametag in the scene, which is a visible hitch with many players.
        if not drawing.textMetrics[slot] or drawing.textMetrics[slot].key ~= key then
            local width = #text * size * 0.65 + 8
            pcall(function() width = textService:GetTextSize(text, size, Enum.Font.Arial, Vector2.new(10000,100)).X + 8 end)
            width = math.max(1, math.min(width, viewport.X - 24))
            drawing.textMetrics[slot] = {key = key, width = width}
            label.AutomaticSize = Enum.AutomaticSize.None
            label.Size = UDim2.fromOffset(width, size + 7)
            label.TextTruncate = Enum.TextTruncate.AtEnd
        end
        -- Clamped to screen independently of target position, not a clipped name.
        local half = drawing.textMetrics[slot].width * 0.5
        local clampedX = math.clamp(label.Position.X.Offset, half + 8, math.max(half + 8, viewport.X - half - 8))
        if math.abs(clampedX - label.Position.X.Offset) >= 0.5 then
            label.Position = UDim2.fromOffset(clampedX, label.Position.Y.Offset)
        end
    end
    card = context.framework.Categories.Visuals:CreateModule({Name = "Nametags", Category = "Render",
        ConfigKey = "Universal.Nametags", Order = 3,
        Tooltip = "Readable player nameplates, account names, distance and game roles. Independent of ESP and Chams.",
        Function = function(enabled)
            if not enabled then clear(); card:SetStatus(nil); return end
            layer.Visible = true
            card:Clean(clear)
            card:Render(function()
                local camera = (host.workspace or workspace).CurrentCamera
                if not camera then clear(); return end
                layer.Visible = true
                local seen, count = {}, 0
                local options = card.Options
                for _, target in ipairs(entity:Refresh()) do
                    local player = target.Player
                    if not player or target.Health <= 0 or target.Distance > options["Max distance"].Value
                        or not (roleBinding.provider and roleBinding.provider.ReplacesTeams) and not options.Teammates.Value and target.IsFriendly then continue end
                    local head = target.Head or target.RootPart
                    local point = head and render:Project(camera, head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.7, 0))
                    if not point or point.X < 0 or point.Y < 0 or point.X > camera.ViewportSize.X or point.Y > camera.ViewportSize.Y
                        or not options["Through walls"].Value and not entity:VisibleFrom(target) then continue end
                    local colour, role = roleBinding:Resolve(player, options.Colour.Value)
                    local shown = options["Display name"].Value and player.DisplayName or player.Name
                    local details = {}
                    if options["Account name"].Value and shown ~= player.Name then table.insert(details, "@" .. player.Name) end
                    if options["Show role"].Value and role then table.insert(details, role) end

                    if options["Held tool"].Value then
                        local tool = target.Character:FindFirstChildOfClass("Tool")
                        if tool then table.insert(details, tool.Name) end
                    end
                    seen[player] = true; tracked[player] = true; count += 1
                    local drawing = render:Set(layer, player)
                    drawing:Show(true)
                    local size = math.round(options["Text size"].Value)
                    if #details > 0 then shown ..= " [" .. table.concat(details, "] [") .. "]" end
                    if options.Distance.Value then shown = "[" .. tostring(math.round(target.Distance)) .. "] " .. shown end
                    local y = math.max(point.Y, size + 16)
                    drawing:Label("Name", shown, Vector2.new(point.X, y), 1, size, colour, options.Background.Value)
                    local label = drawing.labels.Name
                    if label then
                        if not drawing.flatNametag then
                            for _, child in ipairs(label:GetChildren()) do
                                if child:IsA("UICorner") or child:IsA("UIStroke") then child:Destroy()
                                elseif child:IsA("UIPadding") then
                                    child.PaddingLeft, child.PaddingRight = UDim.new(0,4), UDim.new(0,4)
                                end
                            end
                            drawing.flatNametag = true
                        end
                        -- v139.1: these are constant. Re-assigning Font in
                        -- particular re-shapes the glyphs of every label every
                        -- single frame.
                        if label.Font ~= Enum.Font.Arial then
                            label.Font = Enum.Font.Arial
                        end
                        if label.BackgroundColor3 ~= BLACK then
                            label.BackgroundColor3 = BLACK
                        end
                        local plate: number = options.Background.Value and 0.5 or 1
                        if label.BackgroundTransparency ~= plate then
                            label.BackgroundTransparency = plate
                        end
                        if label.TextStrokeTransparency ~= 1 then
                            label.TextStrokeTransparency = 1
                        end
                    end
                    fit(drawing, "Name", shown, size, camera.ViewportSize)
                    drawing:HideLabel("Details")
                end
                for player in pairs(tracked) do
                    if not seen[player] then render:Release(layer,player); tracked[player] = nil end
                end
                card:SetStatus(tostring(count))
            end)
        end})
    card:CreateToggle({Name = "Display name", Default = true})
    card:CreateToggle({Name = "Account name", Default = false, Show = {Option = "Display name"}})
    card:CreateToggle({Name = "Distance", Default = false})
    card:CreateToggle({Name = "Show role", Default = false})
    card:CreateToggle({Name = "Held tool", Default = false})
    card:CreateToggle({Name = "Background", Default = true})
    card:CreateSlider({Name = "Text size", Min = 10, Max = 24, Default = 14})
    card:CreateColor({Name = "Colour", Default = Color3.fromRGB(85, 255, 85)})
    card:CreateSlider({Name = "Max distance", Min = 50, Max = 5000, Default = 1000})
    card:CreateToggle({Name = "Through walls", Default = true})
    card:CreateToggle({Name = "Teammates", Default = true})
    roleBinding = context.services.gameRoles:Bind(card)
    card.OptionFilter = function(name)
        if name == "Show role" then return roleBinding.provider ~= nil end
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
    if roleBinding then roleBinding:Destroy() end
    activeCard, cleanup, roleBinding = nil, nil, nil
    Module.Initialized = false
end
return Module
