-- Rescue actual void falls, not ordinary jumps or long drops onto lower ground.
local Module={Name="AntiVoid",PlaceId=0,Initialized=false}
local cleanup
function Module.init(context)
    local host, world = context.host, context.host.workspace
    local antiFling, velocityLimit, platform, token = false,120,nil,0
    local previousCharacter, previousRoot, previousPlanar
    local function removePlatform()
        token+=1
        if platform then platform:Destroy();platform=nil end
    end
    local function active(name)
        return context.services.activity and context.services.activity.isActive(name)
    end
    local function module(name)
        return context.framework and context.framework.GetModule and context.framework:GetModule(name)
    end
    local function expectedSpeed(humanoid)
        local speed=math.max(16,humanoid.WalkSpeed)
        local feature=module("Speed")
        if feature and feature.Enabled then speed=math.max(speed,feature.Options.Speed.Value) end
        return speed
    end
    local function nearOtherCharacter(root,character)
        if not host.Players then return false end
        for _,player in ipairs(host.Players:GetPlayers()) do
            local other=player.Character
            local otherRoot=other and other~=character and other:FindFirstChild("HumanoidRootPart")
            if otherRoot and (otherRoot.Position-root.Position).Magnitude<=10 then return true end
        end
        return false
    end
    local function step(dt)
        local character,humanoid,root=host.getCharacterParts()
        if not humanoid or not root or humanoid.Health<=0 then return end
        local velocity=root.AssemblyLinearVelocity
        local planar=Vector3.new(velocity.X,0,velocity.Z)
        if previousCharacter~=character or previousRoot~=root then
            previousCharacter,previousRoot,previousPlanar=character,root,planar
            removePlatform()
        end
        local fly=module("Fly")
        if root.Anchored or humanoid.Sit or humanoid.SeatPart or active("fling") or active("ghost")
            or active("teleport") or fly and fly.Enabled then
            previousPlanar=planar;return
        end
        if antiFling then
            local speed=expectedSpeed(humanoid)
            local limit=math.max(velocityLimit,speed*1.75)
            local spin=root.AssemblyAngularVelocity.Magnitude>velocityLimit
            local impulse=planar.Magnitude>limit and previousPlanar
                and (planar-previousPlanar).Magnitude>limit*0.65
            if (spin or impulse) and nearOtherCharacter(root,character) then
                -- Remove the contact impulse, not the player's position/input.
                -- Ordinary downward velocity is never treated as a fling.
                local desired=humanoid.MoveDirection*speed
                root.AssemblyLinearVelocity=Vector3.new(desired.X,spin and math.min(velocity.Y,math.max(0,humanoid.JumpPower or 50)) or velocity.Y,desired.Z)
                root.AssemblyAngularVelocity=Vector3.zero
                planar=Vector3.new(desired.X,0,desired.Z)
            end
        end
        previousPlanar=planar
        if humanoid.FloorMaterial~=Enum.Material.Air or velocity.Y>=0 or platform then return end
        local destroyHeight=world.FallenPartsDestroyHeight
        if destroyHeight~=destroyHeight or math.abs(destroyHeight)==math.huge then destroyHeight=-500 end
        local distance=root.Position.Y-destroyHeight
        if distance>math.max(20,-velocity.Y*0.25) then return end
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={character}
        params.RespectCanCollide=true;params.IgnoreWater=false
        if root.CollisionGroup then params.CollisionGroup=root.CollisionGroup end
        -- A real floor before the destroy layer means this is a legitimate drop.
        local hit=world:Raycast(root.Position,Vector3.new(0,-math.clamp(distance,1,15000),0),params)
        if hit and hit.Position.Y>destroyHeight+2 then return end
        local rescue=Instance.new("Part")
        rescue.Name="Wurst_AntiVoidPlatform";rescue.Anchored=true;rescue.CanCollide=true
        rescue.CanQuery=false;rescue.CanTouch=false;rescue.CastShadow=false
        rescue.Size=Vector3.new(42,1,42);rescue.Transparency=1
        rescue.CFrame=CFrame.new(root.Position-Vector3.new(0,4.25,0));rescue.Parent=world
        platform=rescue
        root.AssemblyLinearVelocity=Vector3.new(velocity.X,0,velocity.Z)
        root.AssemblyAngularVelocity=Vector3.zero
        token+=1;local mine=token
        task.delay(3,function() if mine==token then removePlatform() end end)
    end
    local feature=host.createUniversalFeature("Anti Void","Rescue imminent falls into the destroy layer, not normal drops",4,function(enabled)
        host.disconnectFeatureConnection("AntiVoid");removePlatform()
        previousCharacter,previousRoot,previousPlanar=nil,nil,nil
        if enabled then host.featureConnections.AntiVoid=host.TaskManager:Connect(step) end
    end,{categoryName="Utilities"})
    local velocityRow
    local function showLimit()
        if not velocityRow then return end
        if host.setOptionVisible then host.setOptionVisible(feature,velocityRow,antiFling) else velocityRow.Visible=antiFling end
    end
    host.addToggleOption(feature,"Anti fling",false,function(value) antiFling=value;showLimit() end,
        "Damp sudden sideways/spin impulses near other players. Never rolls you back or blocks normal falling.")
    velocityRow=host.addNumberOption(feature,"Velocity limit",120,40,1000,function(value) velocityLimit=math.max(1,value) end)
    showLimit()
    host.addFeatureTooltip(feature,"Only rescues a falling character near the void when there is no collidable floor below. Anti fling respects movement speed and never teleports you back.")
    cleanup=function() host.disconnectFeatureConnection("AntiVoid");removePlatform() end
    Module.Initialized=true;return feature
end
function Module.destroy()
    if cleanup then cleanup() end
    cleanup=nil;Module.Initialized=false
end
return Module
