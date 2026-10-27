-- Rescue actual void falls, not ordinary jumps or long drops onto lower ground.
local Module={Name="AntiVoid",PlaceId=0,Initialized=false}
local cleanup
function Module.init(context)
    local host, world = context.host, context.host.workspace
    local antiFling, voidGuard, platform, platformY, token = false, false, nil, nil, 0
    local stripOwnedByStepped = false
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
        if platform then platform:Destroy();platform=nil;platformY=nil end
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
    -- Anti fling (Infinite Yield's idea) used to run `GetDescendants()` over
    -- every other character and write CanCollide + both assembly velocities on
    -- every part, every single frame -- with three pcall closures allocated per
    -- part. In a full MM2 server that is thousands of closures and ~600 physics
    -- property writes per frame, which is what made the game's Physics step go
    -- from ~2 ms to ~12 ms and the FPS collapse.
    --
    -- It now costs two property reads per player in the steady state and only
    -- touches a character that actually looks like it is flinging. Part lists
    -- are cached per character (invalidated on DescendantAdded) so the frame
    -- path never walks a tree, and the expensive writes happen once per
    -- detection window instead of once per frame.
    local STRIP_SECONDS = 0.45
    local STRIP_RESTRIKE = 0.1
    -- 60 studs: beyond that a character's contact cannot reach the local root
    -- in the half second the strip lasts.
    local STRIP_RANGE = 60
    -- Injectable clock: lets a suite drive the detection window without
    -- sleeping, and keeps the frame path free of extra service lookups.
    local clock: () -> number = if type((host :: any).clock) == "function"
        then (host :: any).clock else os.clock
    local partCache = setmetatable({}, {__mode = "k"})
    local stripped = setmetatable({}, {__mode = "k"})
    local walkCache = setmetatable({}, {__mode = "k"})
    local cacheWatchers = setmetatable({}, {__mode = "k"})

    -- The previous version wrapped this in a closure per part per frame.
    local function isBasePart(inst: any): boolean
        if type(inst) ~= "table" and typeof(inst) ~= "Instance" then
            return false
        end
        local ok: boolean, verdict: any = pcall(inst.IsA, inst, "BasePart")
        if ok then
            return verdict == true
        end
        -- Table-backed part (test harness / executor proxy): identity is the
        -- physics surface we are about to write.
        return (inst :: any).CanCollide ~= nil
            and (inst :: any).AssemblyLinearVelocity ~= nil
    end

    local function partsOf(character: any)
        local cached = partCache[character]
        if cached ~= nil then
            return cached
        end
        local list = {}
        local okDesc, descendants = pcall(function(): any
            return character:GetDescendants()
        end)
        if okDesc and type(descendants) == "table" then
            for _, inst in ipairs(descendants) do
                if isBasePart(inst) then
                    list[#list + 1] = inst
                end
            end
        end
        partCache[character] = list
        -- One listener per character, not one scan per frame.
        if cacheWatchers[character] == nil then
            local added = (character :: any).DescendantAdded
            if added and type(added.Connect) == "function" then
                local connection = added:Connect(function(inst)
                    if isBasePart(inst) then
                        partCache[character] = nil
                    end
                end)
                cacheWatchers[character] = connection
            end
        end
        return list
    end

    local function walkOf(character, humanoid)
        local cached = walkCache[character]
        if cached then
            return cached
        end
        local walk = 16
        if humanoid then
            walk, _ = motionLimits(humanoid)
        end
        walkCache[character] = walk
        return walk
    end

    local function releaseStrip(entry)
        if not entry then
            return
        end
        for part, canCollide in pairs(entry.saved) do
            if part.Parent and part.CanCollide ~= canCollide then
                pcall(function()
                    part.CanCollide = canCollide
                end)
            end
        end
        entry.saved = nil
    end

    local function stripCharacter(character, entry, now)
        local list = partsOf(character)
        local saved = entry.saved or {}
        -- Only a part that can collide can transfer a contact. In R6/R15 that is
        -- typically the torso and the head: two or three writes instead of one
        -- per part, and nothing at all on the parts that are already off.
        for i = 1, #list do
            local part = list[i]
            if part.Parent and part.CanCollide ~= false then
                if saved[part] == nil then
                    saved[part] = part.CanCollide == true
                end
                part.CanCollide = false
            end
        end
        entry.saved = saved
        entry.untilAt = now + STRIP_SECONDS
        entry.reStrikeAt = now + STRIP_RESTRIKE
    end

    local function stripOtherPlayerCollisions()
        if not antiFling or active("fling") then
            return
        end
        local playersService = host.Players
        if not playersService or type(playersService.GetPlayers) ~= "function" then
            return
        end
        local list = playersService:GetPlayers()
        if type(list) ~= "table" then
            return
        end
        local now = clock()
        local localPlayer = host.LocalPlayer
        local myRoot = nil
        do
            local _, _, root = host.getCharacterParts()
            myRoot = root
        end
        local myPosition = myRoot and myRoot.Position or nil
        for i = 1, #list do
            local other = list[i]
            if other ~= localPlayer then
                local character = other.Character
                local entry = character and stripped[character]
                if entry then
                    if now >= entry.untilAt then
                        releaseStrip(entry)
                        stripped[character] = nil
                    elseif now >= entry.reStrikeAt then
                        -- Same detected fling: nothing to write. CanCollide is
                        -- already off and restoring it early is what let the
                        -- contact through; the entry just stays until it expires.
                        entry.reStrikeAt = now + STRIP_RESTRIKE
                    end
                elseif character then
                    local root = (character :: any).PrimaryPart
                        or character:FindFirstChild("HumanoidRootPart")
                    if root and (isBasePart(root)
                        or (root :: any).AssemblyLinearVelocity ~= nil) then
                        -- A fling on the other side of the map cannot touch us.
                        local reachable = true
                        if myPosition then
                            local okDelta, delta = pcall(function(): number
                                return (root.Position - myPosition).Magnitude
                            end)
                            reachable = okDelta and type(delta) == "number"
                                and delta <= STRIP_RANGE
                        end
                        if not reachable then
                            continue
                        end
                        -- Two reads decide it. No tree walk, no allocation.
                        local spin = root.AssemblyAngularVelocity.Magnitude
                        local speed = root.AssemblyLinearVelocity.Magnitude
                        local okHumanoid, humanoid = pcall(function(): any
                            return character:FindFirstChildOfClass("Humanoid")
                        end)
                        if not okHumanoid then
                            humanoid = nil
                        end
                        local walk = walkOf(character, humanoid)
                        if spin > SPIN_LIMIT or speed > walk * SPEED_FACTOR * 1.5 then
                            entry = {saved = nil}
                            stripped[character] = entry
                            stripCharacter(character, entry, now)
                        end
                    end
                end
            end
        end
    end
    local function releaseAllStrips()
        for character, entry in pairs(stripped) do
            releaseStrip(entry)
            stripped[character] = nil
        end
        table.clear(partCache)
        table.clear(walkCache)
        for character, connection in pairs(cacheWatchers) do
            if connection and connection.Disconnect then
                pcall(connection.Disconnect, connection)
            end
            cacheWatchers[character] = nil
        end
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
            -- Stepped owns the scan when it exists (it runs before the solver
            -- and reads the same values), so the Heartbeat path must not run it
            -- a second time in the same frame.
            if not stripOwnedByStepped then
                stripOtherPlayerCollisions()
            end
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
        if platform then
            if platformY then
                pcall(function()
                    platform.CFrame=CFrame.new(root.Position.X,platformY,root.Position.Z)
                end)
                if root.Position.Y<=platformY+6 and velocity.Y<0 then
                    root.AssemblyLinearVelocity=Vector3.new(velocity.X,0,velocity.Z)
                    root.AssemblyAngularVelocity=Vector3.zero
                end
            end
            return
        end
        if humanoid.FloorMaterial~=Enum.Material.Air or velocity.Y>=0 then return end
        local destroyHeight=world.FallenPartsDestroyHeight
        if destroyHeight~=destroyHeight or math.abs(destroyHeight)==math.huge then destroyHeight=-500 end
        local distance=root.Position.Y-destroyHeight
        if distance>math.max(35,-velocity.Y*0.25) then return end
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
        rescue.Size=Vector3.new(256,4,256);rescue.Transparency=1
        platformY=root.Position.Y-4.25
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
        host.disconnectFeatureConnection("AntiVoidStepped")
        if not antiFling then overSpeedTicks=0 end
        if voidGuard or antiFling then
            host.featureConnections.AntiVoid=host.TaskManager:Connect(step)
        end
        stripOwnedByStepped = antiFling and host.RunService ~= nil
            and host.RunService.Stepped ~= nil
        if stripOwnedByStepped then
            host.featureConnections.AntiVoidStepped=host.RunService.Stepped:Connect(stripOtherPlayerCollisions)
        end
    end
    local feature=host.createUniversalFeature("Anti Void","Rescue imminent falls into the destroy layer, not normal drops",4,function(enabled)
        voidGuard=enabled
        removePlatform()
        previousCharacter,previousRoot,previousVelocity,overSpeedTicks=nil,nil,nil,0
        refresh()
    end,{categoryName="Utilities"})
    host.addToggleOption(feature,"Anti fling",false,function(value) antiFling=value;refresh() end,
        "Cancels a fling on contact: strips other players' collisions on Stepped and damps spin/launch impulses. Works without Anti Void.")
    host.addFeatureTooltip(feature,"Only rescues a falling character near the void when there is no collidable floor below. Anti fling never teleports you back and keeps your input.")
    cleanup=function()
        host.disconnectFeatureConnection("AntiVoid")
        host.disconnectFeatureConnection("AntiVoidStepped")
        releaseAllStrips()
        removePlatform()
    end
    Module.Initialized=true;return feature
end
function Module.destroy()
    if cleanup then cleanup() end
    cleanup=nil;Module.Initialized=false
end
return Module
