-- Local ghost: a real, unanchored Humanoid walks under native gravity.
-- Only explicit Ghost Fly uses velocity; the real character stays parked
-- underneath at `Void depth`.
--
-- v189 contract (rewrite after the live report "no funciona, se traba
-- demasiado, vuela hacia arriba y se teletransporta"):
--   * The real body is ANCHORED and non-collidable while Ghost is on. v188
--     rewrote root.CFrame every single frame on a live, collidable body that
--     sat inside the floor at small depth; physics fought the writes (jitter,
--     teleports) and every write replicated (the stutter). Now the body is
--     frozen once and only re-placed at 10 Hz, so there is nothing to fight.
--   * The clone spawns ABOVE the real body instead of inside it, so the two
--     rigs never interpenetrate and the engine never launches either one.
--   * Ghost Fly is velocity driven on an UNANCHORED rig. v188 anchored the
--     root and then set AssemblyLinearVelocity, which an anchored part
--     ignores -- that is why Fly did nothing and the rest of the module moved
--     strangely. No raycasts in the flight loop either.
--   * No Void guard, no Sprint multiplier, no Outline: fewer moving parts and
--     no per-frame work beyond reading the movement service.
--   * Void depth defaults to 5 (minimum 5) and migrates older profiles.
local Module = {Name="Ghost",PlaceId=0,Initialized=false}
local cleanup

function Module.init(context)
    local host, services = context.host, context.services
    local player, input, run = host.LocalPlayer, host.UserInputService, host.RunService
    local world = host.workspace or workspace
    local VOID_DEPTH_MIN, VOID_DEPTH_MAX = 5, 350
    local settings = {fly=false, flySpeed=55, walkSpeed=16, depth=VOID_DEPTH_MIN, transparency=0.5}
    local state = {connections={},tracks={},bodyParts={}}
    local card

    -- One-time migration. v187 shipped 120 as the default (useless: the body
    -- ends up so far down it no longer follows you) and v188 offered 1. Both
    -- are rewritten to the new minimum; any other value the player actually
    -- picked is kept.
    do
        local stored = type(configData) == "table" and configData.values or nil
        if type(stored) == "table" and stored["UI.GhostDepthDefault"] ~= 2 then
            local saved = tonumber(stored["Universal.Ghost.Voiddepth"])
            if saved == nil or saved < VOID_DEPTH_MIN or saved == 120 then
                stored["Universal.Ghost.Voiddepth"] = VOID_DEPTH_MIN
            end
            stored["UI.GhostDepthDefault"] = 2
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
    -- Freeze the real body: anchored, non-collidable, no humanoid physics. It
    -- is hidden below the clone, so nothing else needs to simulate it, and
    -- freezing it here is what removes the fight that caused the jitter.
    local function parkBody(character,root,humanoid)
        state.bodyParts={}
        for _,object in ipairs(character:GetDescendants()) do
            if object:IsA("BasePart") then
                -- A rig part that reports nothing is treated as collidable, so
                -- OFF always hands back a real value instead of nil.
                local collide=object.CanCollide
                if type(collide)~="boolean" then collide=true end
                table.insert(state.bodyParts,{part=object,collide=collide})
                object.CanCollide=false
            end
        end
        if humanoid then
            humanoid.PlatformStand=true
            pcall(function() humanoid.WalkSpeed=0 end)
        end
        root.AssemblyLinearVelocity,root.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
        root.Anchored=true
    end
    local function unparkBody()
        for _,entry in ipairs(state.bodyParts) do
            local part=entry.part
            if part and part.Parent then pcall(function() part.CanCollide=entry.collide end) end
        end
        table.clear(state.bodyParts)
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
        state.syncedAt,state.camera=nil,nil
    end
    local function stop()
        for _,connection in ipairs(state.connections) do connection:Disconnect() end
        table.clear(state.connections)
        -- Restore collisions FIRST: the hand-back below touches CanCollide, so
        -- restoring it afterwards would leave the body non-collidable (it did:
        -- v189 first draft turned Ghost off and the player fell through floors).
        unparkBody()
        local humanoid, root=parts(player.Character)
        if state.character == player.Character and state.root and root and humanoid
            and humanoid.Health > 0 then
            -- Continue exactly where the puppet ended, then hand the body back
            -- to physics in one step.
            root.Anchored=false
            root.CFrame=state.root.CFrame
            root.AssemblyLinearVelocity,root.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
            humanoid.PlatformStand=false
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
    end
    local function applyMode()
        if not state.model then return end
        local ghostRoot=state.root
        for _,part in ipairs(state.model:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored=false
                -- Flying: nothing collides, so the rig never snags on geometry.
                -- Walking: only the torso/head carry the humanoid on the floor.
                part.CanCollide=not settings.fly and (part.Name=="Head" or part.Name=="Torso"
                    or part.Name=="UpperTorso" or part.Name=="LowerTorso")
            end
        end
        state.humanoid.PlatformStand=settings.fly
        ghostRoot.AssemblyLinearVelocity,ghostRoot.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
        state.flyMode=settings.fly
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
                object:Destroy()
            end
        end
        clone.Name="Wurst_Ghost"
        -- Both Entity and NPCESP reject WurstDisguise models, so the puppet
        -- never shows up as a bot or picks an ESP box.
        pcall(function() clone:SetAttribute("WurstDisguise",true) end)
        humanoid.AutoRotate=true;humanoid.PlatformStand=false;humanoid.Sit=false
        humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
        humanoid.WalkSpeed=math.clamp(settings.walkSpeed,0,500)
        -- Spawn ABOVE the real body, never inside it: two collidable rigs at
        -- the same CFrame is what launched the v188 ghost upwards.
        clone:PivotTo(CFrame.new(root.Position+Vector3.new(0,3,0)))
        clone.Parent=world
        state.character,state.model,state.humanoid,state.root = character,clone,humanoid,ghostRoot
        state.camera,state.syncedAt,state.flyMode=nil,nil,nil
        applyAppearance()
        return true
    end
    local function animate()
        local humanoid=state.humanoid
        local kind=humanoid:GetState()
        local name=kind==Enum.HumanoidStateType.Jumping and "jump"
            or humanoid.FloorMaterial==Enum.Material.Air and "fall"
            or humanoid.MoveDirection.Magnitude>0.05 and "walk" or "idle"
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
    -- Movement intent from the shared service: WASD, the mobile stick and any
    -- custom bind all arrive here. Raw keys are never read for walking.
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
    -- Throttled body sync. Anchored, so there is no physics to fight; at 10 Hz
    -- the position stays exact enough for gameplay and costs a tenth of the
    -- replicated writes v188 did every frame.
    local SYNC_INTERVAL=0.1
    local function syncBody(root,ghostRoot)
        local now=os.clock()
        if state.syncedAt and now-state.syncedAt<SYNC_INTERVAL then return end
        state.syncedAt=now
        local depth=math.clamp(settings.depth or VOID_DEPTH_MIN,0,VOID_DEPTH_MAX)
        local position=ghostRoot.Position
        root.CFrame=CFrame.new(position.X,math.max(position.Y-depth,destroyHeight()+12),position.Z)
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
            parkBody(character,root,humanoid)
            applyMode()
        end
        if not state.model.Parent or not state.root.Parent or state.humanoid.Health<=0 then turnOff();return end
        local ghostRoot, ghostHumanoid=state.root,state.humanoid
        if state.flyMode~=settings.fly then applyMode() end
        local camera=world.CurrentCamera
        if camera and not cameraBusy() and (state.camera~=camera or camera.CameraSubject==humanoid) then
            camera.CameraSubject=ghostHumanoid;state.camera=camera
        end
        if settings.fly then
            local direction=moveVector()
            local vertical=verticalIntent()
            local speed=math.clamp(settings.flySpeed,0,1000)
            local velocity=direction*speed+Vector3.yAxis*(vertical*speed)
            -- Unanchored rig + velocity: smooth, no teleporting, no raycasts.
            ghostRoot.AssemblyLinearVelocity=velocity
            ghostRoot.AssemblyAngularVelocity=Vector3.zero
            ghostHumanoid.WalkSpeed=0
        else
            -- Native walking: gravity, slopes, steps and jumping are Roblox's
            -- job. No CFrame writes and no floor snapping on the clone.
            local focused=input:GetFocusedTextBox()
            local speed=math.clamp(settings.walkSpeed,0,500)
            if ghostHumanoid.WalkSpeed~=speed then ghostHumanoid.WalkSpeed=speed end
            ghostHumanoid:Move(focused and Vector3.zero or moveVector(),false)
        end
        animate()
        syncBody(root,ghostRoot)
    end
    card=context.framework.Categories.Utilities:CreateModule({Name="Ghost",Category="Utilities",Order=8,
        Tooltip="A local clone walks under real gravity and you see through it; your real body is parked Void depth studs underneath. Ghost Fly turns the clone into a smooth velocity flight.",Function=function(enabled)
            stop()
            if not enabled then return end
            local character=player.Character
            local humanoid,root=parts(character)
            if not humanoid or not root or humanoid.Health<=0 or not spawnGhost(character,root) then
                card:Toggle(false)
                error("Ghost could not create a live character.",0)
            end
            activity(true)
            parkBody(character,root,humanoid)
            applyMode()
            table.insert(state.connections,run.PreSimulation:Connect(step))
            table.insert(state.connections,input.JumpRequest:Connect(function()
                if not settings.fly and state.humanoid and not input:GetFocusedTextBox()
                    and state.humanoid.FloorMaterial~=Enum.Material.Air then state.humanoid.Jump=true end
            end))
            step(0)
        end})
    card:CreateToggle({Name="Ghost Fly",Default=false,Function=function(value) settings.fly=value;applyMode() end,
        Tooltip="OFF: native walking and jumping. ON: smooth velocity flight with WASD or the mobile stick, Space up, LeftControl down."})
    card:CreateSlider({Name="Fly speed",Show={Option="Ghost Fly"},Min=1,Max=250,Default=settings.flySpeed,
        Function=function(value) settings.flySpeed=value end})
    card:CreateSlider({Name="Void depth",Min=VOID_DEPTH_MIN,Max=VOID_DEPTH_MAX,Default=settings.depth,Function=function(value)
        settings.depth=math.clamp(value,VOID_DEPTH_MIN,VOID_DEPTH_MAX)
    end,Tooltip="How far under the clone your real body is parked. 5 is the default: close enough to keep the puppet honest, far enough not to touch the floor."})
    card:CreateSlider({Name="Ghost WalkSpeed",Min=1,Max=200,Default=settings.walkSpeed,Function=function(value)
        settings.walkSpeed=math.clamp(value,0,500)
        if state.humanoid and not settings.fly then state.humanoid.WalkSpeed=settings.walkSpeed end
    end,Tooltip="Walking speed of the clone."})
    card:CreateSlider({Name="Ghost transparency",Min=0.1,Max=0.9,Step=0.05,Default=settings.transparency,Function=function(value)
        settings.transparency=math.clamp(value,0,1)
        applyAppearance()
    end})
    cleanup=turnOff
    Module.Initialized=true;return card
end
function Module.destroy()
    if cleanup then cleanup() end
    cleanup=nil;Module.Initialized=false
end
return Module
