-- Vape-style world waypoints, with names / Save here instead of encoded coordinates.
local Module = {Name="Markers",Initialized=false}
local card, clear, inputConnection, services
function Module.init(context)
    local host, render = context.host, context.render
    services = context.services
    local menu = services.menu
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
                points[name]={x,y,z,position[4]=="surface" and "surface" or nil}; loaded += 1
            end
        end
    end
    local listeners = {}
    local function pointNames()
        local names={};for name in pairs(points) do table.insert(names,name) end;table.sort(names);return names
    end
    services.points = {
        Names=pointNames,
        Get=function(name)
            local data=points[name]
            if data then return Vector3.new(data[1],data[2],data[3]),data[4]=="surface" end
        end,
        Subscribe=function(callback)
            listeners[callback]=true
            return function() listeners[callback]=nil end
        end,
    }
    local list, tracked = nil, {}
    local picking, pickName, pickMenuVisible = false, nil, false
    local function finishPick(status, reopen)
        local wasPicking = picking
        picking = false
        if card then card:SetStatus(status) end
        if wasPicking and pickMenuVisible and reopen ~= false then menu.setVisible(true) end
        pickMenuVisible = false
    end
    local function save()
        if config then config.values[key]=points;if host.queueConfigSave then host.queueConfigSave() end end
        for callback in pairs(listeners) do callback() end
    end
    clear=function(reopen) render:ReleaseAll(layer);table.clear(tracked);layer.Visible=false;finishPick(nil,reopen) end
    card=context.framework.Categories.Render:CreateModule({Name="Markers",Category="Render",ConfigKey="Universal.Markers",
        Tooltip="Save your standing coordinates or mark a surface. Points are shared with Teleport and kept per game.",Function=function(enabled)
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
    local function pointName()
        return string.sub(string.match(card.Options.Name.Value or "","^%s*(.-)%s*$") or "",1,48)
    end
    local function nextPointName()
        local base=pointName()
        local index=1
        while true do
            local suffix=base=="" and tostring(index) or " #"..index
            local name=(base=="" and "Point " or string.sub(base,1,48-#suffix))..suffix
            if not points[name] then return name end
            index+=1
        end
    end
    local function savedName()
        local name=pointName()
        return name~="" and name or nextPointName()
    end
    local function storePoint(position,name,surface)
        if name=="" then card:Notify("Enter a point name.");return false end
        if not position or position.X~=position.X or position.Y~=position.Y or position.Z~=position.Z
            or math.max(math.abs(position.X),math.abs(position.Y),math.abs(position.Z))>=1e7 then
            card:Notify("Position unavailable. Use coordinates in the form x, y, z.");return false
        end
        local count=0;for _ in pairs(points) do count+=1 end
        if count>=128 and not points[name] then card:Notify("Marker limit reached (128). Delete a point first.");return false end
        points[name]={position.X,position.Y,position.Z,surface and "surface" or nil};save();list:Refresh();list:Set(name,true)
        card:SetStatus(name);return true
    end
    card:CreateTextBox({Name="Name",Default="",Placeholder="Home, exit, meeting spot..."})
    card:CreateButton({Name="Save here",Tooltip="Save your character standing x, y, z here, not the camera position.",Function=function()
        local character=host.LocalPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        storePoint(root and root.Position,savedName())
    end})
    card:CreateButton({Name="Touch",Tooltip="Hides the menu to pick a surface. Escape cancels; new points are numbered, never overwritten. Works while OFF too.",Function=function()
        if picking then finishPick();return end
        pickName=nextPointName()
        picking=true
        pickMenuVisible=menu.isVisible()
        card:SetStatus("Click/tap a surface · Esc cancels")
        menu.setVisible(false)
    end})
    if config and config.values["Universal.Markers.Point"]==nil then
        config.values["Universal.Markers.Point"]=config.values["Universal.Markers.Places"]
    end
    list=card:CreateList({Name="Point",Items=pointNames,Default=pointNames(),
        EmptyText="No points. Use Save here or Touch.",OnRemove=function(name)
            if not points[name] then return end
            list:Set(name,false);points[name]=nil;save();list:Refresh()
            render:Release(layer,name);tracked[name]=nil
        end})
    card:CreateToggle({Name="Manual coordinates",Default=false})
    card:CreateTextBox({Name="Coordinates",Default="",Placeholder="x, y, z",Show={Option="Manual coordinates",Values={true}}})
    card:CreateButton({Name="Save coordinates",Show={Option="Manual coordinates",Values={true}},Function=function()
        local x,y,z=string.match(card.Options.Coordinates.Value or "","^%s*([%+%-%.%deE]+)%s*,%s*([%+%-%.%deE]+)%s*,%s*([%+%-%.%deE]+)%s*$")
        x,y,z=tonumber(x),tonumber(y),tonumber(z)
        storePoint(x and y and z and Vector3.new(x,y,z) or nil,savedName())
    end})
    card:CreateToggle({Name="Distance",Default=true})
    card:CreateColor({Name="Colour",Default=Color3.fromRGB(85,255,85)})
    inputConnection=host.UserInputService.InputBegan:Connect(function(event,processed)
        if not picking then return end
        if event.KeyCode==Enum.KeyCode.Escape then
            finishPick();return
        end
        if processed or host.UserInputService:GetFocusedTextBox() then return end
        if event.UserInputType~=Enum.UserInputType.MouseButton1 and event.UserInputType~=Enum.UserInputType.Touch then return end
        local camera=(host.workspace or workspace).CurrentCamera
        if not camera then return end
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances=host.LocalPlayer.Character and {host.LocalPlayer.Character} or {}
        params.RespectCanCollide=true;params.IgnoreWater=true
        local ray=camera:ScreenPointToRay(event.Position.X,event.Position.Y)
        local hit=(host.workspace or workspace):Raycast(ray.Origin,ray.Direction*5000,params)
        if hit and storePoint(hit.Position,pickName,true) then finishPick(pickName)
        else card:SetStatus("No surface · tap again") end
    end)
    Module.Initialized=true
    return card
end
function Module.destroy()
    if clear then clear(false) end
    if card and card.Enabled then card:Toggle(false) end
    if inputConnection then inputConnection:Disconnect();inputConnection=nil end
    if services then services.points=nil end
    card,clear,services=nil,nil,nil;Module.Initialized=false
end
return Module
