-- Local ghost: a real, unanchored Humanoid walks under native gravity.
-- Only explicit Ghost Fly moves the clone by velocity; the real character
-- stays hidden underneath at `Void depth`.
--
-- v188 contract:
--   * The clone is the visible, controlled body. The real character follows it
--     from below, so other clients keep seeing the puppet, never the player.
--   * Void depth defaults to its minimum: the fake body sits right under you
--     instead of disappearing 120 studs down where it stops being useful.
--   * No Highlight by default. The blue outline was drawn over the clone and
--     over the real body through walls; it is now an OFF-by-default option.
--   * Ghost Fly moves by AssemblyLinearVelocity with the shared movement
--     input, so WASD, mobile sticks and custom keybinds all work, and the
--     clone no longer teleports through geometry.
--   * Ghost WalkSpeed is a real slider; Left Shift keeps multiplying it.
--   * Void guard keeps a walking ghost from falling into the map void; it is
--     a bounded clamp, not server physics.
local Module = {Name="Ghost",PlaceId=0,Initialized=false}
local cleanup

function Module.init(context)
    local host, services = context.host, context.services
    local player, input, run = host.LocalPlayer, host.UserInputService, host.RunService
    local world = host.workspace or workspace
    -- The real body rides at the lowest usable depth: right under the puppet.
    -- Raising this only hides you further from your own clone, so it is the
    -- slider minimum rather than an arbitrary 120-stud default.
    local VOID_DEPTH_MIN, VOID_DEPTH_MAX = 1, 350
    local settings = {
        fly=false, flySpeed=55, walkSpeed=16, sprintMultiplier=2,
        depth=VOID_DEPTH_MIN, transparency=0.5, outline=false, voidGuard=true,
    }
    local state = {connections={},tracks={}}
    local card

    -- One-time migration: v187 and older shipped `Void depth` defaulting to
    -- 120 studs, which parks the real body so far down it is useless. The saved
    -- value is only rewritten when it was never touched (absent or exactly the
    -- old default); a depth the player actually chose is kept.
    do
        local stored = type(configData) == "table" and configData.values or nil
        if type(stored) == "table" and stored["UI.GhostDepthDefault"] ~= 1 then
            local saved = tonumber(stored["Universal.Ghost.Voiddepth"])
            if saved == nil or saved == 120 then
                stored["Universal.Ghost.Voiddepth"] = VOID_DEPTH_MIN
            end
            stored["UI.GhostDepthDefault"] = 1
            if type(queueConfigSave) == "function" then queueConfigSave() end
        end
    end
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
    local function destroyHeight()
        local height=world.FallenPartsDestroyHeight
        if height~=height or math.abs(height)==math.huge then return -500 end
        return height
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
        state.floor=nil
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
    local function turnOff()
        local feature=card and card.Feature
        if feature and feature.enabled and type(feature.activate)=="function" then
            feature.activate()
        elseif card and card.Enabled then
            card:Toggle(false)
        else
            stop()
        end
    end
    local function applyAppearance()
        if not state.model then return end
        local transparency=math.clamp(settings.transparency,0,1)
        for _,object in ipairs(state.model:GetDescendants()) do
            if object:IsA("BasePart") then object.Transparency=transparency end
        end
        local highlight=state.model:FindFirstChild("GhostHighlight")
        if settings.outline then
            if not highlight then
                highlight=Instance.new("Highlight")
                highlight.Name="GhostHighlight"
                highlight.FillColor=Color3.fromRGB(120,210,255)
                highlight.OutlineColor=Color3.fromRGB(220,245,255)
                highlight.FillTransparency=0.85
                highlight.OutlineTransparency=0.15
                highlight.DepthMode=Enum.HighlightDepthMode.Occluded
                highlight.Adornee=state.model
                highlight.Parent=state.model
            end
        elseif highlight then
            highlight:Destroy()
        end
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
            elseif object:IsA("Highlight") or object:IsA("BillboardGui")
                or object:IsA("SurfaceGui") or object:IsA("SelectionBox") then
                -- Whatever the avatar brought (spawn outlines, name plates)
                -- must not leak onto the puppet.
                object:Destroy()
            end
        end
        clone.Name="Wurst_Ghost"
        -- Hide the puppet from every menu that indexes workspace models: both
        -- Entity and NPCESP reject WurstDisguise models, so the ghost never
        -- shows up as a bot and never gets an ESP box or outline.
        pcall(function() clone:SetAttribute("WurstDisguise",true) end)
        humanoid.AutoRotate=true;humanoid.PlatformStand=false;humanoid.Sit=false
        humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
        humanoid.WalkSpeed=math.clamp(settings.walkSpeed,0,500)
        clone:PivotTo(root.CFrame)
        clone.Parent=world
        state.character,state.model,state.humanoid,state.root = character,clone,humanoid,ghostRoot
        state.camera=nil
        state.anchorY=root.Position.Y
        applyAppearance()
        return true
    end
    local function animate()
        local humanoid=state.humanoid
        local kind=humanoid:GetState()
        local name=kind==Enum.HumanoidStateType.Jumping and "jump"
            or humanoid.FloorMaterial==Enum.Material.Air and "fall"
            or humanoid.MoveDirection.Magnitude>0.05 and (humanoid.WalkSpeed>settings.walkSpeed and "run" or "walk") or "idle"
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
    -- Movement intent, shared with Fly and the mobile dock through the service.
    -- Reading raw keys here was why mobile sticks and custom binds did nothing.
    local function moveVector()
        if input:GetFocusedTextBox() then return Vector3.zero end
        local movement=services.movementInput
        if movement and type(movement.getVector)=="function" then
            local ok,forward,right=pcall(movement.getVector)
            if ok and type(forward)=="number" and type(right)=="number" then
                local camera=world.CurrentCamera
                local lookForward,lookRight=Vector3.new(0,0,-1),Vector3.new(1,0,0)
                if camera then
                    local look=camera.CFrame.LookVector
                    local rightVector=camera.CFrame.RightVector
                    lookForward=Vector3.new(look.X,0,look.Z)
                    lookRight=Vector3.new(rightVector.X,0,rightVector.Z)
                    lookForward=lookForward.Magnitude>0.001 and lookForward.Unit or Vector3.new(0,0,-1)
                    lookRight=lookRight.Magnitude>0.001 and lookRight.Unit or Vector3.new(1,0,0)
                end
                local direction=lookForward*forward+lookRight*right
                return direction.Magnitude>1 and direction.Unit or direction
            end
        end
        local humanoid=parts(player.Character)
        return humanoid and humanoid.MoveDirection or Vector3.zero
    end
    local function verticalIntent()
        if input:GetFocusedTextBox() then return 0 end
        local up,down=0,0
        if input:IsKeyDown(Enum.KeyCode.Space) then up=1 end
        if input:IsKeyDown(Enum.KeyCode.LeftControl) then down=1 end
        if up==0 and down==0 then
            local movement=services.movementInput
            if movement and type(movement.isJumpHeld)=="function" then
                local ok,held=pcall(movement.isJumpHeld)
                if ok and held==true then up=1 end
            end
        end
        return up-down
    end
    local function wallBlocked(ghostRoot,step)
        if step.Magnitude<0.001 then return step end
        local parameters=state.wallParams
        if not parameters then
            parameters=RaycastParams.new()
            parameters.FilterType=Enum.RaycastFilterType.Exclude
            parameters.RespectCanCollide,parameters.IgnoreWater=true,true
            state.wallParams=parameters
        end
        if state.wallCharacter~=state.model then
            state.wallCharacter=state.model
            parameters.FilterDescendantsInstances=state.model and {state.model} or {}
        end
        local ok,hit=pcall(function() return world:Raycast(ghostRoot.Position,step,parameters) end)
        if not ok or not hit then return step end
        return step.Unit*math.max(0,(hit.Position-ghostRoot.Position).Magnitude-0.3)
    end
    local function applyFly(ghostRoot,ghostHumanoid,dt)
        local camera=world.CurrentCamera
        local direction=moveVector()
        local vertical=verticalIntent()
        local horizontal=Vector3.zero
        if direction.Magnitude>0.001 then
            horizontal=direction.Unit*math.clamp(settings.flySpeed,0,1000)
        end
        if camera then
            local forward=camera.CFrame.LookVector
            if vertical>0 then horizontal=horizontal+Vector3.yAxis*math.clamp(settings.flySpeed,0,1000)
            elseif vertical<0 then horizontal=horizontal-Vector3.yAxis*math.clamp(settings.flySpeed,0,1000) end
        end
        if horizontal.Magnitude>0.001 then
            local step=horizontal*math.clamp(dt,0,0.1)
            local clear=wallBlocked(ghostRoot,step)
            ghostRoot.AssemblyLinearVelocity=clear/math.max(math.clamp(dt,0,0.1),1/240)
        else
            -- Space and LeftControl are the vertical pair; with the camera
            -- facing forward this keeps the puppet where it was released.
            ghostRoot.AssemblyLinearVelocity=Vector3.zero
        end
        ghostRoot.AssemblyAngularVelocity=Vector3.zero
        if camera and direction.Magnitude<0.001 and vertical==0 then
            ghostHumanoid.WalkSpeed=0
        else
            ghostHumanoid.WalkSpeed=math.clamp(settings.walkSpeed,0,500)
        end
    end
    -- A bounded floor: while walking, a clone that leaves every solid surface
    -- keeps falling forever and drags the real body into the map void. The
    -- guard re-seats it on the last known height instead -- local only.
    local function voidGuard(ghostRoot,ghostHumanoid)
        if not settings.voidGuard or settings.fly then return end
        local floor=destroyHeight()+24
        local position=ghostRoot.Position
        local anchor=state.anchorY or position.Y
        -- Grounded frames move the anchor down with the ghost (stairs, hills);
        -- airborne frames compare against the last known solid height.
        if ghostHumanoid.FloorMaterial~=Enum.Material.Air and position.Y>anchor
            and position.Y-anchor<=12 then
            state.anchorY=position.Y
            anchor=position.Y
        end
        -- Seat on the higher of "260 studs below the last solid ground" and
        -- "24 studs above the map floor": whichever the map reaches first.
        local limit=math.max(anchor-260,floor)
        if position.Y>limit then return end
        ghostRoot.CFrame=CFrame.new(ghostRoot.Position.X,limit+4,ghostRoot.Position.Z)
        ghostRoot.AssemblyLinearVelocity,ghostRoot.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
        pcall(function() ghostHumanoid:ChangeState(Enum.HumanoidStateType.Landed) end)
    end
    local function step(dt)
        local character=player.Character
        local humanoid, root=parts(character)
        if not humanoid or not root or humanoid.Health<=0 then return end
        if state.character~=character then
            if not spawnGhost(character,root) then
                turnOff()
                card:Notify("Could not create a live character.")
                return
            end
        end
        if not state.model.Parent or not state.root.Parent or state.humanoid.Health<=0 then turnOff();return end
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
            applyFly(ghostRoot,ghostHumanoid,dt)
        else
            -- No CFrame assignment, floor-snapping or fixed-height plane here.
            -- Roblox resolves gravity, ground, walls, slopes and jumping.
            local focused=input:GetFocusedTextBox()
            local sprint=focused and 1 or (input:IsKeyDown(Enum.KeyCode.LeftShift) and math.max(1,settings.sprintMultiplier) or 1)
            ghostHumanoid.WalkSpeed=math.clamp(settings.walkSpeed*sprint,0,500)
            local direction=moveVector()
            ghostHumanoid:Move(focused and Vector3.zero or direction,false)
            voidGuard(ghostRoot,ghostHumanoid)
        end
        animate()
        local depth=math.clamp(settings.depth or 0,0,1000)
        local position=ghostRoot.Position
        root.CFrame=CFrame.new(position.X,math.max(position.Y-depth,destroyHeight()+12),position.Z)
        root.AssemblyLinearVelocity,root.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
    end
    card=context.framework.Categories.Utilities:CreateModule({Name="Ghost",Category="Utilities",Order=8,
        Tooltip="Your local ghost walks under gravity with its own WalkSpeed; Left Shift sprints. Ghost Fly is explicit flight with WASD, Space and LeftControl. The real body stays Void depth studs underneath.",Function=function(enabled)
            stop()
            if not enabled then return end
            local character=player.Character
            local humanoid,root=parts(character)
            if not humanoid or not root or humanoid.Health<=0 or not spawnGhost(character,root) then
                -- Let the card activation/restore path record OFF as well.
                card:Toggle(false)
                error("Ghost could not create a live character.",0)
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
        Tooltip="OFF: native walking, falling and jumping. ON: WASD and the mobile stick fly, Space rises, LeftControl descends."})
    card:CreateSlider({Name="Fly speed",Show={Option="Ghost Fly"},Min=1,Max=250,Default=55,Function=function(value) settings.flySpeed=value end})
    card:CreateSlider({Name="Ghost WalkSpeed",Min=1,Max=200,Default=settings.walkSpeed,Function=function(value)
        settings.walkSpeed=math.clamp(value,0,500)
        if state.humanoid and not settings.fly then state.humanoid.WalkSpeed=settings.walkSpeed end
    end,Tooltip="Walking speed of the ghost. Left Shift multiplies it by the sprint multiplier."})
    card:CreateSlider({Name="Sprint multiplier",Min=1,Max=5,Step=0.1,Default=settings.sprintMultiplier,Function=function(value)
        settings.sprintMultiplier=math.max(1,value)
    end,Tooltip="Left Shift multiplier while walking. 1 disables sprinting."})
    card:CreateSlider({Name="Void depth",Min=VOID_DEPTH_MIN,Max=VOID_DEPTH_MAX,Default=settings.depth,Function=function(value)
        settings.depth=math.max(0,value)
    end,Tooltip="How far under the ghost the real body sits. The default is the minimum, so the puppet stays right under you; raise it only when a game needs the body further down."})
    card:CreateToggle({Name="Void guard",Default=settings.voidGuard,Function=function(value) settings.voidGuard=value end,
        Tooltip="Walking only: when the ghost falls past the map floor it is re-seated instead of dragging you into the void. Local clamp, not server physics."})
    card:CreateSlider({Name="Ghost transparency",Min=0.1,Max=0.9,Step=0.05,Default=settings.transparency,Function=function(value)
        settings.transparency=math.clamp(value,0,1)
        applyAppearance()
    end})
    card:CreateToggle({Name="Outline",Default=false,Function=function(value) settings.outline=value;applyAppearance() end,
        Tooltip="Off by default: the blue Highlight outline drew over the puppet and through walls. Turn it on if you want it."})
    cleanup=turnOff
    Module.Initialized=true;return card
end
function Module.destroy()
    if cleanup then cleanup() end
    cleanup=nil;Module.Initialized=false
end
return Module
