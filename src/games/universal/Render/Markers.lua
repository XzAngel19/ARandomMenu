-- Vape-style world waypoints, with names / Save here instead of encoded coordinates.
local Module = {Name="Markers",Initialized=false}
local card, clear
function Module.init(context)
    local host, render = context.host, context.render
    local layer = render:Layer("MarkersLayer")
    local key = "Universal.Markers.Places." .. tostring(game.PlaceId)
    local config = host.configData
    local points = {}
    local stored = config and config.values[key]
    if type(stored) ~= "table" then stored = {} end
    local loaded = 0
    for name, position in pairs(stored) do
        if type(name)=="string" and type(position)=="table" and loaded < 128 then
            local x,y,z=tonumber(position[1]),tonumber(position[2]),tonumber(position[3])
            if x and y and z and x==x and y==y and z==z and math.max(math.abs(x),math.abs(y),math.abs(z)) < 1e7 then
                points[name]={x,y,z}; loaded += 1
            end
        end
    end
    local list, tracked = nil, {}
    local function save()
        if config then config.values[key]=points;if host.queueConfigSave then host.queueConfigSave() end end
    end
    clear=function() render:ReleaseAll(layer);table.clear(tracked);layer.Visible=false end
    card=context.framework.Categories.Render:CreateModule({Name="Markers",Category="Render",ConfigKey="Universal.Markers",
        Tooltip="Name a place and save your current position. Points are kept separately for each game.",Function=function(enabled)
            if not enabled then clear();return end
            layer.Visible=true;card:Clean(clear)
            card:Render(function()
                local camera=(host.workspace or workspace).CurrentCamera
                if not camera then clear();return end
                layer.Visible=true
                local seen={}
                for name, data in pairs(points) do
                    if not list:IsSelected(name) then continue end
                    local position=Vector3.new(data[1],data[2],data[3])
                    local at=render:Project(camera,position)
                    if not at or at.X<0 or at.Y<0 or at.X>camera.ViewportSize.X or at.Y>camera.ViewportSize.Y then continue end
                    local text=name
                    if card.Options.Distance.Value then text ..= " [" .. math.round((camera.CFrame.Position-position).Magnitude) .. "]" end
                    local drawing=render:Set(layer,name)
                    drawing:Show(true)
                    drawing:Label("Marker",text,Vector2.new(at.X,at.Y),1,14,card.Options.Colour.Value,true)
                    seen[name],tracked[name]=true,true
                end
                for name in pairs(tracked) do if not seen[name] then render:Release(layer,name);tracked[name]=nil end end
            end)
        end})
    card:CreateTextBox({Name="Name",Default="",Placeholder="Home, exit, meeting spot..."})
    card:CreateButton({Name="Save here",Function=function()
        local name=string.sub(string.match(card.Options.Name.Value or "","^%s*(.-)%s*$") or "",1,48)
        if name=="" then card:Notify("Enter a name for this place.");return end
        local character=host.LocalPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local position=root and root.Position
        if card.Options["Manual coordinates"].Value then
            local x,y,z=string.match(card.Options.Coordinates.Value or "","^%s*([%+%-%.%deE]+)%s*,%s*([%+%-%.%deE]+)%s*,%s*([%+%-%.%deE]+)%s*$")
            x,y,z=tonumber(x),tonumber(y),tonumber(z)
            position=x and y and z and x==x and y==y and z==z and math.max(math.abs(x),math.abs(y),math.abs(z))<1e7 and Vector3.new(x,y,z) or nil
        end
        if not position then card:Notify("Position unavailable. Check your character or coordinates (x, y, z).");return end
        local count=0;for _ in pairs(points) do count+=1 end
        if count>=128 and not points[name] then card:Notify("Marker limit reached (128). Remove a place first.");return end
        points[name]={position.X,position.Y,position.Z};save();list:Refresh();list:Set(name,true)
    end})
    card:CreateButton({Name="Remove named place",Function=function()
        local name=string.match(card.Options.Name.Value or "","^%s*(.-)%s*$")
        if not points[name] then card:Notify("No saved place has that name.");return end
        list:Set(name,false);points[name]=nil;save();list:Refresh()
    end})
    local defaults={};for name in pairs(points) do defaults[name]=true end
    list=card:CreateList({Name="Places",Items=function()
        local names={};for name in pairs(points) do table.insert(names,name) end;table.sort(names);return names
    end,Default=defaults,EmptyText="No places saved. Name a place, then Save here."})
    card:CreateToggle({Name="Distance",Default=true})
    card:CreateColor({Name="Colour",Default=Color3.fromRGB(85,255,85)})
    card:CreateToggle({Name="Manual coordinates",Default=false})
    card:CreateTextBox({Name="Coordinates",Default="",Placeholder="x, y, z",Show={Option="Manual coordinates",Values={true}}})
    Module.Initialized=true
    return card
end
function Module.destroy()
    if card and card.Enabled then card:Toggle(false) end
    if clear then clear() end
    card,clear=nil,nil;Module.Initialized=false
end
return Module
