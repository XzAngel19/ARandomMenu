-- Rescue actual void falls, not ordinary jumps or long drops onto lower ground.
local Module={Name="AntiVoid",PlaceId=0,Initialized=false}
local cleanup
function Module.init(context)
    local host, world = context.host, context.host.workspace
    local antiFling, voidGuard, platform, token = false, false, nil, 0
    local previousCharacter, previousRoot, previousVelocity, overSpeedTicks
    -- Fixed physical thresholds, measured against what the body itself can
    -- produce. There is no user-facing velocity limit any more: a single
    -- number has to be retuned per game and per speed setting, and when it
    -- was wrong the protection silently did nothing.
    local SPIN_LIMIT = 20      -- rad/s: a driven spin, not a turn
    local SPEED_FACTOR = 2.2   -- multiples of the character's walking speed
    local JUMP_FACTOR = 3      -- multiples of JumpPower no jump can reach
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
    local function motionLimits(humanoid)
        local walk=math.max(16,humanoid.WalkSpeed or 16)
        local feature=module("Speed")
        if feature and feature.Enabled and feature.Options and feature.Options.Speed then
            walk=math.max(walk,feature.Options.Speed.Value)
        end
        return walk,math.max(50,humanoid.JumpPower or 50)
    end
    local function step(dt)
        local character,humanoid,root=host.getCharacterParts()
        if not humanoid or not root or humanoid.Health<=0 then return end
        local velocity=root.AssemblyLinearVelocity
        local planar=Vector3.new(velocity.X,0,velocity.Z)
        if previousCharacter~=character or previousRoot~=root then
            previousCharacter,previousRoot,previousVelocity,overSpeedTicks=character,root,velocity,0
            removePlatform()
        end
        local fly=module("Fly")
        local busy=root.Anchored or humanoid.Sit or humanoid.SeatPart or active("fling")
            or active("ghost") or active("teleport") or fly and fly.Enabled
        if antiFling and not busy then
            -- Everything is compared to the body's own mobility, so a fast
            -- walk or an intentional Speed never reads as a fling, and no
            -- slider has to match it.
            local walk,jump=motionLimits(humanoid)
            local limit=walk*SPEED_FACTOR
            local spin=root.AssemblyAngularVelocity.Magnitude>SPIN_LIMIT
            local rise=velocity.Y>jump*JUMP_FACTOR
            local delta=previousVelocity and (velocity-previousVelocity) or Vector3.zero
            local kick=math.max(planar.Magnitude,Vector3.new(delta.X,0,delta.Z).Magnitude)
            if planar.Magnitude>limit then overSpeedTicks=(overSpeedTicks or 0)+1 else overSpeedTicks=0 end
            -- Four signatures, any one of them enough: a driven spin, a rise
            -- no jump can produce, a single-frame planar spike, and a shove
            -- held over several frames (contact flings accelerate instead of
            -- jumping in one tick). Proximity is not one of them: a fling
            -- sent through a tool or a remote arrives from any distance, and
            -- the old 10-stud gate is why it used to need several attempts.
            if spin or rise or kick>limit or overSpeedTicks>=2 then
                -- Remove the impulse, never the position or the input.
                local desired=humanoid.MoveDirection*walk
                local lifted=rise or spin
                root.AssemblyLinearVelocity=Vector3.new(desired.X,
                    lifted and math.min(velocity.Y,jump) or velocity.Y,desired.Z)
                root.AssemblyAngularVelocity=Vector3.zero
                velocity=root.AssemblyLinearVelocity
                planar=Vector3.new(desired.X,0,desired.Z)
                overSpeedTicks=0
            end
        end
        previousVelocity=velocity
        if not voidGuard then return end
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
    -- Anti fling owns its connection: it protects with Anti Void off, and
    -- Anti Void keeps the rescue without ever turning the damping off.
    local function refresh()
        host.disconnectFeatureConnection("AntiVoid")
        if not antiFling then overSpeedTicks=0 end
        if voidGuard or antiFling then
            host.featureConnections.AntiVoid=host.TaskManager:Connect(step)
        end
    end
    local feature=host.createUniversalFeature("Anti Void","Rescue imminent falls into the destroy layer, not normal drops",4,function(enabled)
        voidGuard=enabled
        removePlatform()
        previousCharacter,previousRoot,previousVelocity,overSpeedTicks=nil,nil,nil,0
        refresh()
    end,{categoryName="Utilities"})
    host.addToggleOption(feature,"Anti fling",false,function(value) antiFling=value;refresh() end,
        "Cancels a fling on contact: driven spin, impossible rise, single-frame shove or a sustained one, all measured against your own walk and jump. Works without Anti Void.")
    host.addFeatureTooltip(feature,"Only rescues a falling character near the void when there is no collidable floor below. Anti fling never teleports you back and keeps your input.")
    cleanup=function() host.disconnectFeatureConnection("AntiVoid");removePlatform() end
    Module.Initialized=true;return feature
end
function Module.destroy()
    if cleanup then cleanup() end
    cleanup=nil;Module.Initialized=false
end
return Module
