-- Local ghost: a real, unanchored Humanoid walks under native gravity.
-- Only explicit Ghost Fly uses CFrame motion; the real character stays hidden.
local Module = {Name="Ghost",PlaceId=0,Initialized=false}
local cleanup

function Module.init(context)
    local host, services = context.host, context.services
    local player, input, run = host.LocalPlayer, host.UserInputService, host.RunService
    local world = host.workspace or workspace
    local settings = {fly=false,speed=55,depth=120,transparency=0.5}
    local state = {connections={},tracks={}}
    local card
    local function parts(character)
        return character and character:FindFirstChildOfClass("Humanoid"),
            character and character:FindFirstChild("HumanoidRootPart")
    end
    local function activity(active)
        if services.activity then services.activity.set("ghost",active) end
    end
    local function cameraBusy()
        return services.freeCam and services.freeCam.IsActive()
            or services.spectate and services.spectate.IsActive()
    end
    local function clearGhost()
        local camera = world.CurrentCamera
        if camera and camera.CameraSubject == state.humanoid then
            camera.CameraSubject = parts(player.Character)
        end
        for _,track in pairs(state.tracks) do pcall(function() track:Stop(0) end) end
        table.clear(state.tracks)
        if state.model then state.model:Destroy() end
        state.model,state.humanoid,state.root,state.animation,state.flyMode = nil,nil,nil,nil,nil
    end
    local function stop()
        for _,connection in ipairs(state.connections) do connection:Disconnect() end
        table.clear(state.connections)
        if state.character == player.Character and state.root then
            local humanoid, root = parts(player.Character)
            if root and humanoid and humanoid.Health > 0 then
                root.CFrame = state.root.CFrame
                root.AssemblyLinearVelocity,root.AssemblyAngularVelocity = Vector3.zero,Vector3.zero
            end
        end
        clearGhost();state.character=nil;activity(false)
    end
    local function spawnGhost(character,root)
        clearGhost()
        local archivable = character.Archivable
        character.Archivable = true
        local ok, clone = pcall(function() return character:Clone() end)
        character.Archivable = archivable
        if not ok or not clone then return false end
        local humanoid, ghostRoot = parts(clone)
        if not humanoid or not ghostRoot then clone:Destroy();return false end
        for _,object in ipairs(clone:GetDescendants()) do
            if object:IsA("Script") or object:IsA("LocalScript") or object:IsA("Tool") then
                object:Destroy()
            elseif object:IsA("BasePart") then
                object.Anchored = false
                object.CanTouch,object.CanQuery,object.CastShadow = false,false,false
                object.Transparency = math.clamp(settings.transparency,0,1)
                object.CanCollide = object.Name=="Head" or object.Name=="Torso"
                    or object.Name=="UpperTorso" or object.Name=="LowerTorso"
            end
        end
        clone.Name="Wurst_Ghost"
        humanoid.AutoRotate=true;humanoid.PlatformStand=false;humanoid.Sit=false
        humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
        humanoid.WalkSpeed=16
        clone:PivotTo(root.CFrame)
        clone.Parent=world
        state.character,state.model,state.humanoid,state.root = character,clone,humanoid,ghostRoot
        state.camera=nil
        local highlight=Instance.new("Highlight")
        highlight.Name="GhostHighlight";highlight.FillColor=Color3.fromRGB(120,210,255)
        highlight.OutlineColor=Color3.fromRGB(220,245,255)
        highlight.FillTransparency=0.6;highlight.OutlineTransparency=0.15
        highlight.Adornee=clone;highlight.Parent=clone
        return true
    end
    local function animate()
        local humanoid=state.humanoid
        local kind=humanoid:GetState()
        local name=kind==Enum.HumanoidStateType.Jumping and "jump"
            or humanoid.FloorMaterial==Enum.Material.Air and "fall"
            or humanoid.MoveDirection.Magnitude>0.05 and (humanoid.WalkSpeed>16 and "run" or "walk") or "idle"
        if settings.fly then name="idle" end
        if state.animation==name then return end
        if state.animation and state.tracks[state.animation] then state.tracks[state.animation]:Stop(0.15) end
        state.animation=name
        if state.tracks[name]==false then return end
        if not state.tracks[name] then
            local source=state.character:FindFirstChild("Animate")
            local folder=source and source:FindFirstChild(name)
            local animation=folder and folder:FindFirstChildWhichIsA("Animation",true)
            local temporary
            if not animation then
                local r6=humanoid.RigType==Enum.HumanoidRigType.R6
                local ids=r6 and {idle=180435571,walk=180426354,run=180426354,jump=125750702,fall=180436148}
                    or {idle=507766666,walk=507777826,run=507767714,jump=507765000,fall=507767968}
                temporary=Instance.new("Animation");temporary.AnimationId="rbxassetid://"..ids[name];animation=temporary
            end
            local ok,track=pcall(function()
                local animator=humanoid:FindFirstChildOfClass("Animator")
                if not animator then animator=Instance.new("Animator");animator.Parent=humanoid end
                return animator:LoadAnimation(animation)
            end)
            if temporary then temporary:Destroy() end
            state.tracks[name]=ok and track or false
        end
        local track=state.tracks[name]
        if track then
            track.Looped=name~="jump"
            track.Priority=name=="idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
            track:Play(0.15)
        end
    end
    local function step(dt)
        local character=player.Character
        local humanoid, root=parts(character)
        if not humanoid or not root or humanoid.Health<=0 then return end
        if state.character~=character then
            if not spawnGhost(character,root) then return end
        end
        if not state.model.Parent or not state.root.Parent or state.humanoid.Health<=0 then card:Toggle(false);return end
        local ghostRoot, ghostHumanoid=state.root,state.humanoid
        if state.flyMode~=settings.fly then
            state.flyMode=settings.fly
            for _,part in ipairs(state.model:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Anchored=settings.fly and part==ghostRoot
                    part.CanCollide=not settings.fly and (part.Name=="Head" or part.Name=="Torso"
                        or part.Name=="UpperTorso" or part.Name=="LowerTorso")
                end
            end
            ghostHumanoid.PlatformStand=settings.fly
            ghostRoot.AssemblyLinearVelocity,ghostRoot.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
        end
        local camera=world.CurrentCamera
        if camera and not cameraBusy() and (state.camera~=camera or camera.CameraSubject==humanoid) then
            camera.CameraSubject=ghostHumanoid;state.camera=camera
        end
        if settings.fly then
            if camera and not input:GetFocusedTextBox() then
                local direction=Vector3.zero
                for _,control in ipairs({{Enum.KeyCode.W,camera.CFrame.LookVector},{Enum.KeyCode.S,-camera.CFrame.LookVector},
                    {Enum.KeyCode.D,camera.CFrame.RightVector},{Enum.KeyCode.A,-camera.CFrame.RightVector},
                    {Enum.KeyCode.Space,Vector3.yAxis},{Enum.KeyCode.LeftControl,-Vector3.yAxis}}) do
                    if input:IsKeyDown(control[1]) then direction+=control[2] end
                end
                if direction.Magnitude>0 then ghostRoot.CFrame+=direction.Unit*settings.speed*math.clamp(dt,0,0.1) end
            end
        else
            -- No CFrame assignment, floor-snapping or fixed-height plane here.
            -- Roblox resolves gravity, ground, walls, slopes and jumping.
            local focused=input:GetFocusedTextBox()
            ghostHumanoid.WalkSpeed=not focused and input:IsKeyDown(Enum.KeyCode.LeftShift) and 32 or 16
            ghostHumanoid:Move(focused and Vector3.zero or humanoid.MoveDirection,false)
        end
        animate()
        local destroyHeight=world.FallenPartsDestroyHeight
        if destroyHeight~=destroyHeight or math.abs(destroyHeight)==math.huge then destroyHeight=-500 end
        local position=ghostRoot.Position
        root.CFrame=CFrame.new(position.X,math.max(position.Y-settings.depth,destroyHeight+12),position.Z)
        root.AssemblyLinearVelocity,root.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
    end
    card=context.framework.Categories.Utilities:CreateModule({Name="Ghost",Category="Utilities",Order=8,
        Tooltip="Your local ghost walks under gravity; Left Shift runs at 32. Ghost Fly explicitly enables flight.",Function=function(enabled)
            stop()
            if not enabled then return end
            local character=player.Character
            local humanoid,root=parts(character)
            if not humanoid or not root or humanoid.Health<=0 or not spawnGhost(character,root) then
                card:Notify("Ghost could not create a live character.");return
            end
            activity(true)
            table.insert(state.connections,run.PreSimulation:Connect(step))
            table.insert(state.connections,input.JumpRequest:Connect(function()
                if not settings.fly and state.humanoid and not input:GetFocusedTextBox()
                    and state.humanoid.FloorMaterial~=Enum.Material.Air then state.humanoid.Jump=true end
            end))
            step(0)
        end})
    card:CreateToggle({Name="Ghost Fly",Default=false,Function=function(value) settings.fly=value end,
        Tooltip="OFF: native walking, falling and jumping; Left Shift runs at 32. ON: WASD, Space up, Ctrl down."})
    card:CreateSlider({Name="Fly speed",Show={Option="Ghost Fly"},Min=1,Max=250,Default=55,Function=function(value) settings.speed=value end})
    card:CreateSlider({Name="Void depth",Min=50,Max=350,Default=120,Function=function(value) settings.depth=math.max(0,value) end})
    card:CreateSlider({Name="Ghost transparency",Min=0.1,Max=0.9,Step=0.05,Default=0.5,Function=function(value)
        settings.transparency=math.clamp(value,0,1)
        if state.model then for _,part in ipairs(state.model:GetDescendants()) do
            if part:IsA("BasePart") then part.Transparency=settings.transparency end
        end end
    end})
    cleanup=stop;Module.Initialized=true;return card
end
function Module.destroy()
    if cleanup then cleanup() end
    cleanup=nil;Module.Initialized=false
end
return Module
