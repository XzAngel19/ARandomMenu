-- Native player spectating; FreeCam pauses without losing its position.
local Module = {Name="Spectate", Initialized=false}
local card, services

function Module.init(context)
    local host = context.host
    services = context.services
    local world = host.workspace or workspace
    local chosen, camera, saved, writtenSubject
    local playerList
    local id = "ARandomMenu.Spectate." .. tostring({})
    local function localHumanoid()
        local character = host.LocalPlayer.Character
        return character and character:FindFirstChildOfClass("Humanoid")
    end
    local function freeCamSession()
        local free = services.freeCam
        return free and free.IsActive() and free.Session or nil
    end
    local function restore()
        if camera and saved then
            pcall(function()
                -- Do not take the camera back from a later owner.
                if camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= writtenSubject then return end
                local returnedToFreeCam = saved.freeCam and saved.freeCam == freeCamSession()
                if saved.freeCam and not returnedToFreeCam then
                    camera.CameraType = Enum.CameraType.Custom
                    camera.CameraSubject = localHumanoid()
                else
                    camera.CameraType = saved.kind
                    camera.CameraSubject = saved.subject == saved.localHumanoid and localHumanoid() or saved.subject
                    camera.CFrame, camera.Focus = saved.frame, saved.focus
                end
            end)
        end
        camera, saved, writtenSubject = nil, nil, nil
    end
    local function targetHumanoid()
        for _, player in ipairs(host.Players:GetPlayers()) do
            if player ~= host.LocalPlayer and player.Name == chosen then
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                return humanoid and humanoid.Health > 0 and humanoid or nil, true
            end
        end
        return nil, false
    end
    local function step()
        local humanoid, present = targetHumanoid()
        if chosen and not present then
            local departed = chosen
            chosen = nil
            if playerList then playerList:Set(departed,false);playerList:Refresh() end
        end
        if not humanoid then
            restore()
            card:SetStatus(chosen and "Waiting for respawn" or "Choose a player")
            return
        end
        local nextCamera = world.CurrentCamera
        if camera ~= nextCamera then restore() end
        if not nextCamera then return end
        if not camera then
            camera = nextCamera
            saved = {kind=camera.CameraType,subject=camera.CameraSubject,frame=camera.CFrame,focus=camera.Focus,
                freeCam=freeCamSession(),localHumanoid=localHumanoid()}
        elseif camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= writtenSubject then
            -- Adopt a newer camera baseline rather than restoring over it later.
            saved = {kind=camera.CameraType,subject=camera.CameraSubject,frame=camera.CFrame,focus=camera.Focus,
                freeCam=false,localHumanoid=localHumanoid()}
        end
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
        writtenSubject = humanoid
        card:SetStatus(chosen)
    end
    local state = {IsActive=function()
        if not card or not card.Enabled or not chosen then return false end
        local humanoid = targetHumanoid()
        return humanoid ~= nil
    end}
    services.spectate = state
    card = context.framework.Categories.Visuals:CreateModule({Name="Spectate",Category="World",ConfigKey="Universal.Spectate",Order=7,
        Tooltip="Follow one player independently of FreeCam. Deselect or switch OFF to return to your previous camera.",
        Function=function(enabled)
            if not enabled then restore();card:SetStatus(nil);return end
            card:Clean(function() host.RunService:UnbindFromRenderStep(id);restore() end)
            -- Set the subject before Roblox updates its native camera.
            host.RunService:BindToRenderStep(id,Enum.RenderPriority.Camera.Value-1,step)
            step()
        end})
    playerList = card:CreateList({Name="Player",Single=true,Items=function()
        local names={}
        for _,player in ipairs(host.Players:GetPlayers()) do
            if player ~= host.LocalPlayer then table.insert(names,player.Name) end
        end
        table.sort(names);return names
    end,EmptyText="No other players",Tooltip="Select one player; click the selected player again to stop spectating.",Function=function(_,names)
        local nextName = names[1]
        if chosen ~= nextName then restore();chosen=nextName end
        if card and card.Enabled then step() end
    end})
    Module.Initialized=true
    return card
end

function Module.destroy()
    if card and card.Enabled then card:Toggle(false) end
    if services then services.spectate=nil end
    card,services=nil,nil
    Module.Initialized=false
end
return Module
