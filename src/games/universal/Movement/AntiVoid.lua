-- v150 · Anti Void + Anti fling, rebuilt from zero.
--
-- Evidence: MM2 (TestingStuff place 142823291) has no floor under its maps.
-- Workspace.Gravity is 196.2 and FallenPartsDestroyHeight is -500, while the
-- House2 / Bank2 maps live around Y=240..280. Waiting for the destroy layer
-- therefore cannot rescue a normal void fall. The game's own CharacterClient
-- teleports with a single `character:PivotTo` on TeleportToPart, so a single
-- bounded rescue is consistent with the game; a per-frame CFrame writer is not.
--
-- Anti fling damps impulses on the LOCAL root (the assembly we own) and strips
-- nearby flinging characters' collisions once per detection window. Part lists
-- are cached, no GetDescendants() runs per frame, and nothing is left modified
-- after OFF/death/respawn/destroy.

local Module = { Name = "AntiVoid", PlaceId = 0, Initialized = false }
local cleanup: (() -> ())? = nil

function Module.init(context: any): any
    local host: any = context.host
    local world: any = host.workspace
    local RunService: any = host.RunService
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local framework: any = context.framework
    local services: any = context.services
    local activity: any = services and services.activity
    local getCharacterParts: any = host.getCharacterParts
    local clock: () -> number = if type((host :: any).clock) == "function"
        then (host :: any).clock else os.clock

    local antiFling: boolean = false
    local voidGuard: boolean = false
    local stripOwnedByStepped: boolean = false

    local SPIN_LIMIT: number = 20
    local SPEED_FACTOR: number = 2.2
    local JUMP_FACTOR: number = 3
    local STRIP_SECONDS: number = 0.45
    local STRIP_RANGE: number = 60
    local FALL_MARGIN: number = 16
    local RESCUE_COOLDOWN: number = 1.5
    local RAY_DISTANCE: number = 120

    local safeCFrame: any = nil
    local safeCharacter: any = nil
    local safeY: number? = nil
    local lastRescueAt: number = -math.huge
    local previousCharacter: any = nil
    local previousRoot: any = nil
    local previousVelocity: any = nil
    local overSpeedTicks: number = 0

    local partCache: any = setmetatable({}, {__mode = "k"})
    local walkCache: any = setmetatable({}, {__mode = "k"})
    local stripped: any = setmetatable({}, {__mode = "k"})
    local cacheWatchers: any = setmetatable({}, {__mode = "k"})

    local function active(name: string): boolean
        return activity ~= nil and type(activity.isActive) == "function"
            and activity.isActive(name) == true
    end

    local function module(name: string): any
        if framework and type(framework.GetModule) == "function" then
            local ok: boolean, found: any = pcall(framework.GetModule, framework, name)
            if ok then
                return found
            end
        end
        return nil
    end

    local function motionLimits(humanoid: any): (number, number)
        local walk: number = math.max(16, tonumber(humanoid.WalkSpeed) or 16)
        local feature: any = module("Speed")
        if feature and feature.Enabled and feature.Options and feature.Options.Speed
            and type(feature.Options.Speed.Value) == "number" then
            walk = math.max(walk, feature.Options.Speed.Value)
        end
        return walk, math.max(50, tonumber(humanoid.JumpPower) or 50)
    end

    local function isBasePart(inst: any): boolean
        if inst == nil then
            return false
        end
        local ok: boolean, verdict: any = pcall(function(): any
            if type(inst.IsA) == "function" then
                return inst:IsA("BasePart")
            end
            return nil
        end)
        if ok and verdict ~= nil then
            return verdict == true
        end
        return (inst :: any).CanCollide ~= nil
            and (inst :: any).AssemblyLinearVelocity ~= nil
    end

    local function partsOf(character: any): {any}
        local cached: any = partCache[character]
        if cached ~= nil then
            return cached
        end
        local list: {any} = {}
        local ok: boolean, descendants: any = pcall(function(): any
            return character:GetDescendants()
        end)
        if ok and type(descendants) == "table" then
            for _, inst: any in ipairs(descendants) do
                if isBasePart(inst) then
                    table.insert(list, inst)
                end
            end
        end
        partCache[character] = list
        if cacheWatchers[character] == nil then
            local added: any = (character :: any).DescendantAdded
            if added and type(added.Connect) == "function" then
                local okAdd: boolean, connection: any = pcall(function(): any
                    return added:Connect(function(inst: any): ()
                        if isBasePart(inst) then
                            partCache[character] = nil
                        end
                    end)
                end)
                if okAdd then
                    cacheWatchers[character] = connection
                end
            end
        end
        return list
    end

    local function walkOf(character: any, humanoid: any): number
        local cached: any = walkCache[character]
        if cached then
            return cached
        end
        local walk: number = 16
        if humanoid then
            walk = motionLimits(humanoid)
        end
        walkCache[character] = walk
        return walk
    end

    local function releaseStrip(entry: any): ()
        if not entry or not entry.saved then
            return
        end
        for part, canCollide in pairs(entry.saved) do
            if part and part.Parent and part.CanCollide ~= canCollide then
                pcall(function(): () part.CanCollide = canCollide end)
            end
        end
        entry.saved = nil
    end

    local function releaseAllStrips(): ()
        for character, entry in pairs(stripped) do
            releaseStrip(entry)
            stripped[character] = nil
        end
        table.clear(partCache)
        table.clear(walkCache)
        for character, connection in pairs(cacheWatchers) do
            if connection and type(connection.Disconnect) == "function" then
                pcall(connection.Disconnect, connection)
            end
            cacheWatchers[character] = nil
        end
    end

    -- Two reads per player in the steady state. Writes happen once per 0.45 s
    -- detection window, never once per frame.
    local function stripOtherPlayerCollisions(): ()
        if not antiFling or active("fling") then
            return
        end
        local playersService: any = host.Players
        if not playersService or type(playersService.GetPlayers) ~= "function" then
            return
        end
        local list: any = playersService:GetPlayers()
        if type(list) ~= "table" then
            return
        end
        local now: number = clock()
        local localPlayer: any = host.LocalPlayer
        local myRoot: any = nil
        do
            local _, _, found: any = getCharacterParts()
            myRoot = found
        end
        local myPosition: any = myRoot and myRoot.Position or nil
        for i = 1, #list do
            local other: any = list[i]
            if other ~= localPlayer then
                local character: any = other.Character
                local entry: any = character and stripped[character]
                if entry then
                    if now >= entry.untilAt then
                        releaseStrip(entry)
                        stripped[character] = nil
                    end
                elseif character then
                    local root: any = (character :: any).PrimaryPart
                    if not root and type(character.FindFirstChild) == "function" then
                        local okFind: boolean, found: any = pcall(function(): any
                            return character:FindFirstChild("HumanoidRootPart")
                        end)
                        if okFind then
                            root = found
                        end
                    end
                    if root and isBasePart(root) then
                        local reachable: boolean = true
                        if myPosition and root.Position then
                            local okDelta: boolean, delta: any = pcall(function(): any
                                return (root.Position - myPosition).Magnitude
                            end)
                            reachable = okDelta and type(delta) == "number"
                                and delta <= STRIP_RANGE
                        end
                        local spin: any = root.AssemblyAngularVelocity
                            and root.AssemblyAngularVelocity.Magnitude or 0
                        local speed: any = root.AssemblyLinearVelocity
                            and root.AssemblyLinearVelocity.Magnitude or 0
                        local humanoid: any = nil
                        if type(character.FindFirstChildOfClass) == "function" then
                            local okHum: boolean, foundHum: any = pcall(function(): any
                                return character:FindFirstChildOfClass("Humanoid")
                            end)
                            if okHum then
                                humanoid = foundHum
                            end
                        end
                        local walk: number = walkOf(character, humanoid)
                        if reachable and ((type(spin) == "number" and spin > SPIN_LIMIT)
                            or (type(speed) == "number" and speed > walk * SPEED_FACTOR * 1.5)) then
                            local saved: any = {}
                            for _, part: any in ipairs(partsOf(character)) do
                                if part and part.Parent and part.CanCollide ~= false then
                                    if saved[part] == nil then
                                        saved[part] = part.CanCollide == true
                                    end
                                    pcall(function(): () part.CanCollide = false end)
                                end
                            end
                            stripped[character] = {
                                saved = saved,
                                untilAt = now + STRIP_SECONDS,
                            }
                        end
                    end
                end
            end
        end
    end

    local function forgetSafe(): ()
        safeCFrame = nil
        safeCharacter = nil
        safeY = nil
    end

    local function rememberSafe(character: any, root: any, humanoid: any): ()
        if not character or not root or not humanoid then
            return
        end
        local grounded: boolean = humanoid.FloorMaterial ~= Enum.Material.Air
        local velocity: any = root.AssemblyLinearVelocity
        local falling: boolean = velocity ~= nil
            and type(velocity.Y) == "number" and velocity.Y < -1
        if grounded and not falling then
            safeCharacter = character
            safeCFrame = root.CFrame
            safeY = root.Position.Y
        end
    end

    local function rescuePossible(character: any, root: any): boolean
        if not character or not root or not safeCFrame or safeCharacter ~= character
            or safeY == nil or type(character.PivotTo) ~= "function" then
            return false
        end
        local velocity: any = root.AssemblyLinearVelocity
        if velocity == nil or type(velocity.Y) ~= "number" or velocity.Y >= 0 then
            return false
        end
        if root.Position.Y > (safeY :: number) - FALL_MARGIN then
            return false
        end
        if clock() - lastRescueAt < RESCUE_COOLDOWN then
            return false
        end
        -- A real floor before the void means this is a legitimate drop.
        if world and type(world.Raycast) == "function" and RaycastParams then
            local params: any = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character}
            params.RespectCanCollide = true
            local ok: boolean, hit: any = pcall(function(): any
                return world:Raycast(root.Position,
                    Vector3.new(0, -RAY_DISTANCE, 0), params)
            end)
            if ok and hit and hit.Position
                and hit.Position.Y > root.Position.Y - RAY_DISTANCE + 2 then
                return false
            end
        end
        return true
    end

    local function rescue(character: any, root: any): ()
        local target: any = safeCFrame
        lastRescueAt = clock()
        pcall(function(): () character:PivotTo(target) end)
        pcall(function(): ()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local function step(deltaTime: number): ()
        local character: any, humanoid: any, root: any = getCharacterParts()
        if not character or not humanoid or not root or humanoid.Health <= 0 then
            return
        end
        if previousCharacter ~= character or previousRoot ~= root then
            previousCharacter, previousRoot = character, root
            previousVelocity = nil
            overSpeedTicks = 0
            forgetSafe()
        end
        local velocity: any = root.AssemblyLinearVelocity or Vector3.zero
        local fly: any = module("Fly")
        local busy: boolean = root.Anchored or humanoid.Sit or humanoid.SeatPart
            or active("fling") or active("ghost") or active("teleport")
            or (fly and fly.Enabled) or false

        if antiFling and not busy then
            if not stripOwnedByStepped then
                stripOtherPlayerCollisions()
            end
            local walk: number, jump: number = motionLimits(humanoid)
            local limit: number = walk * SPEED_FACTOR
            local planar: any = velocity and Vector3.new(velocity.X, 0, velocity.Z)
                or Vector3.zero
            local spin: any = root.AssemblyAngularVelocity
                and root.AssemblyAngularVelocity.Magnitude or 0
            local rise: boolean = velocity ~= nil
                and type(velocity.Y) == "number"
                and velocity.Y > jump * JUMP_FACTOR
            local delta: any = previousVelocity and (velocity - previousVelocity)
                or Vector3.zero
            local kick: number = math.max(planar.Magnitude,
                Vector3.new(delta.X, 0, delta.Z).Magnitude)
            if planar.Magnitude > limit then
                overSpeedTicks += 1
            else
                overSpeedTicks = 0
            end
            if (type(spin) == "number" and spin > SPIN_LIMIT) or rise
                or kick > limit or overSpeedTicks >= 2 then
                local desired: any = humanoid.MoveDirection or Vector3.zero
                local lifted: boolean = rise
                    or (type(spin) == "number" and spin > SPIN_LIMIT)
                pcall(function(): ()
                    root.AssemblyLinearVelocity = Vector3.new(
                        desired.X * walk,
                        lifted and math.min(velocity.Y, jump) or velocity.Y,
                        desired.Z * walk)
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
                velocity = root.AssemblyLinearVelocity
                overSpeedTicks = 0
            end
        end
        previousVelocity = velocity

        if not voidGuard or busy then
            return
        end
        rememberSafe(character, root, humanoid)
        if rescuePossible(character, root) then
            rescue(character, root)
            previousVelocity = Vector3.zero
        end
    end

    local function refresh(): ()
        disconnectFeatureConnection("AntiVoid")
        disconnectFeatureConnection("AntiVoidStepped")
        if not antiFling then
            overSpeedTicks = 0
        end
        if voidGuard or antiFling then
            featureConnections.AntiVoid = TaskManager:Connect(step)
        end
        stripOwnedByStepped = antiFling and RunService ~= nil
            and type((RunService :: any).Stepped) == "table"
            and type((RunService :: any).Stepped.Connect) == "function"
        if stripOwnedByStepped then
            featureConnections.AntiVoidStepped =
                (RunService :: any).Stepped:Connect(stripOtherPlayerCollisions)
        end
    end

    local feature: any = host.createUniversalFeature(
        "Anti Void",
        "Rescue real void falls with one bounded teleport back to the last safe ground",
        4,
        function(enabled: boolean): ()
            voidGuard = enabled == true
            forgetSafe()
            previousCharacter, previousRoot, previousVelocity = nil, nil, nil
            overSpeedTicks = 0
            refresh()
        end,
        {categoryName = "Utilities"}
    )
    host.addToggleOption(feature, "Anti fling", false, function(value: boolean): ()
        antiFling = value == true
        refresh()
    end,
        "Damps launch impulses on your own root and strips a nearby flinger's collisions once per detection window. Works without Anti Void.")
    host.addFeatureTooltip(feature,
        "Anti Void remembers the last grounded position and performs a single PivotTo only when the character is falling with no floor below. Anti fling never teleports and never fights an explicit MM2 Fling.")

    cleanup = function(): ()
        disconnectFeatureConnection("AntiVoid")
        disconnectFeatureConnection("AntiVoidStepped")
        stripOwnedByStepped = false
        releaseAllStrips()
        forgetSafe()
    end
    Module.Initialized = true
    return feature
end

function Module.destroy(): ()
    if cleanup then
        pcall(cleanup)
    end
    cleanup = nil
    Module.Initialized = false
end

return Module
