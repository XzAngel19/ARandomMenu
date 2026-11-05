export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "AntiFling",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local services: any = context.services
    local activity: any = services and services.activity
    local framework: any = context.framework
    local players: any = host.Players
    local localPlayer: any = host.LocalPlayer
    local world: any = host.workspace or workspace
    local featureConnections: any = host.featureConnections
    local disconnect: any = host.disconnectFeatureConnection

    local enabled: boolean = false
    local playerShield: boolean = true
    local impactShield: boolean = true
    local feature: any = nil
    local character: Model? = nil
    local links: {[BasePart]: {[BasePart]: any}} = {}
    local hazardSeen: {[BasePart]: number} = {}
    local nextScan: number = 0
    local dangerUntil: number = 0
    local suspended: boolean = false
    local warnedOverlap: boolean = false

    -- Limits are deliberately conservative. The shield is local physics, not
    -- server authority; do not change other people's CanCollide or global groups.
    local SCAN_INTERVAL: number = 0.15
    local RADIUS: number = 30
    local HAZARD_HOLD: number = 0.75
    local LINEAR_LIMIT: number = 80
    local SURFACE_LIMIT: number = 70
    local MAX_LINKS: number = 2048
    local MAX_PARTS: number = 200

    local function isBusy(): boolean
        return activity ~= nil and type(activity.isActive) == "function"
            and (activity.isActive("fling") or activity.isActive("walkfling"))
    end

    local function destroyLinks(): ()
        for _, perLocal: {[BasePart]: any} in pairs(links) do
            for _, constraint: any in pairs(perLocal) do
                pcall(function(): () constraint:Destroy() end)
            end
        end
        table.clear(links)
        table.clear(hazardSeen)
        dangerUntil = 0
    end

    local function isToolPart(part: Instance): boolean
        local ok: boolean, result: any = pcall(function(): any
            return part:FindFirstAncestorOfClass("Tool")
        end)
        return ok and result ~= nil
    end

    local function listBodyParts(model: Model?, onlyCollidable: boolean): {BasePart}
        local parts: {BasePart} = {}
        if not model or not model.Parent then return parts end
        local ok: boolean, descendants: any = pcall(function(): any return model:GetDescendants() end)
        if not ok or type(descendants) ~= "table" then return parts end
        for _, object: Instance in ipairs(descendants) do
            if object:IsA("BasePart") and not isToolPart(object) then
                local part: BasePart = object :: BasePart
                if not onlyCollidable or part.CanCollide then table.insert(parts, part) end
            end
        end
        return parts
    end

    local function fastPart(part: BasePart, scale: number?): boolean
        local ok: boolean, fast: any = pcall(function(): boolean
            -- Relative speed alone flags a stationary player when *we* sprint;
            -- arm the fallback only for motion driven by the other assembly.
            local linear: Vector3 = part.AssemblyLinearVelocity
            local angular: Vector3 = part.AssemblyAngularVelocity
            local radius: number = math.min(part.Size.Magnitude * 0.5, 20)
            local multiplier: number = scale or 1
            return linear.Magnitude > LINEAR_LIMIT * multiplier
                or angular.Magnitude * radius > SURFACE_LIMIT * multiplier
        end)
        return ok and fast == true
    end

    local function supportAssembly(root: BasePart, humanoid: Humanoid, owner: Model): BasePart?
        local ok: boolean, result: any = pcall(function(): any
            local params: RaycastParams = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {owner}
            params.IgnoreWater = true
            params.RespectCanCollide = true
            local distance: number = math.max(4, (tonumber(humanoid.HipHeight) or 2) + root.Size.Y * 0.5 + 2)
            return world:Raycast(root.Position, Vector3.new(0, -distance, 0), params)
        end)
        local ground: any = ok and result and result.Instance
        if ground and ground:IsA("BasePart") then
            return ground.AssemblyRootPart or ground
        end
        return nil
    end

    local function synchronize(owner: Model, humanoid: Humanoid, root: BasePart, now: number): ()
        local ownParts: {BasePart} = listBodyParts(owner, true)
        local desired: {[BasePart]: boolean} = {}
        local candidates: {any} = {}
        local characterModels: {[Model]: boolean} = {}
        local roster: any = players:GetPlayers()

        -- Track every visible player body, not the shared world collision group.
        -- Nearest bodies get the bounded constraint budget first on large servers.
        for _, player: Player in ipairs(roster) do
            local other: Model? = player ~= localPlayer and player.Character or nil
            if other and other ~= owner and other.Parent then
                characterModels[other] = true
                local otherRoot: BasePart? = other:FindFirstChild("HumanoidRootPart") :: BasePart?
                local distance: number = otherRoot and (otherRoot.Position - root.Position).Magnitude or math.huge
                table.insert(candidates, {model = other, distance = distance,
                    parts = if playerShield then listBodyParts(other, false) else {}})
            end
        end
        table.sort(candidates, function(a: any, b: any): boolean return a.distance < b.distance end)
        if playerShield then
            for _, candidate: any in ipairs(candidates) do
                for _, part: BasePart in ipairs(candidate.parts) do
                    desired[part] = true
                    if candidate.distance <= RADIUS and fastPart(part, nil) then
                        dangerUntil = math.max(dangerUntil, now + HAZARD_HOLD)
                    end
                end
            end
        end

        -- The query is local and bounded. Anchored geometry, the supporting
        -- platform/assembly, seats and tools keep their normal interactions.
        -- A fast loose part is suppressed only briefly while it remains risky.
        if impactShield and not humanoid.Sit and not humanoid.SeatPart then
            local overlap: any = nil
            pcall(function(): ()
                overlap = OverlapParams.new()
                overlap.FilterType = Enum.RaycastFilterType.Exclude
                overlap.FilterDescendantsInstances = {owner}
                overlap.MaxParts = MAX_PARTS
                overlap.RespectCanCollide = true
            end)
            local ok: boolean, nearby: any = pcall(function(): any
                return world:GetPartBoundsInRadius(root.Position, RADIUS, overlap)
            end)
            if not ok or type(nearby) ~= "table" then
                if not warnedOverlap and type(host.notify) == "function" then
                    warnedOverlap = true
                    host.notify("Anti Fling: moving-object scan unavailable; player protection remains active.")
                end
            else
                local floorAssembly: BasePart? = supportAssembly(root, humanoid, owner)
                for _, instance: Instance in ipairs(nearby) do
                    if instance:IsA("BasePart") then
                        local part: BasePart = instance :: BasePart
                        local isCharacterPart: boolean = false
                        local ancestor: Instance? = part.Parent
                        while ancestor and ancestor ~= world do
                            if characterModels[ancestor :: any] then isCharacterPart = true break end
                            ancestor = ancestor.Parent
                        end
                        local inOwner: boolean = part:IsDescendantOf(owner)
                        local isTool: boolean = isToolPart(part)
                        local assembly: BasePart? = part.AssemblyRootPart or part
                        -- Ordinary weapon/tools remain interactive. An extreme
                        -- spinning/flying handle is treated as a hazard, at 3x
                        -- the loose-object threshold, only while it is nearby.
                        if part.Parent and part.CanCollide and not part.Anchored and not inOwner
                            and (not isCharacterPart or isTool)
                            and (not floorAssembly or assembly ~= floorAssembly)
                            and fastPart(part, if isTool then 3 else nil) then
                            hazardSeen[part] = now
                            dangerUntil = math.max(dangerUntil, now + HAZARD_HOLD)
                        end
                    end
                end
            end
            for part: BasePart, seen: number in pairs(hazardSeen) do
                if not part.Parent or now - seen > HAZARD_HOLD then
                    hazardSeen[part] = nil
                else
                    desired[part] = true
                end
            end
        else
            table.clear(hazardSeen)
        end

        -- Allocate the finite budget afresh in priority order: newly dangerous
        -- objects first, then nearest players. Otherwise 2,048 older/farther
        -- links could permanently starve a new incoming threat.
        local ordered: {BasePart} = {}
        local included: {[BasePart]: boolean} = {}
        local function include(part: BasePart): ()
            if desired[part] and part.Parent and not included[part] then
                included[part] = true
                table.insert(ordered, part)
            end
        end
        local hazards: {BasePart} = {}
        for part: BasePart in pairs(hazardSeen) do table.insert(hazards, part) end
        table.sort(hazards, function(a: BasePart, b: BasePart): boolean
            return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude
        end)
        for _, part: BasePart in ipairs(hazards) do include(part) end
        if playerShield then
            for _, candidate: any in ipairs(candidates) do
                for _, part: BasePart in ipairs(candidate.parts) do include(part) end
            end
        end
        local accepted: {[BasePart]: {[BasePart]: boolean}} = {}
        local allocated: number = 0
        for _, other: BasePart in ipairs(ordered) do
            if allocated >= MAX_LINKS then break end
            local perLocal: {[BasePart]: boolean} = {}
            for _, own: BasePart in ipairs(ownParts) do
                if allocated >= MAX_LINKS then break end
                if own ~= other then
                    perLocal[own] = true
                    allocated += 1
                end
            end
            if next(perLocal) then accepted[other] = perLocal end
        end
        -- Remove old or lower-priority pairs before filling the new budget.
        for other: BasePart, perLocal: {[BasePart]: any} in pairs(links) do
            local wanted: {[BasePart]: boolean}? = accepted[other]
            for own: BasePart, constraint: any in pairs(perLocal) do
                if not wanted or not wanted[own] or not own.Parent or not other.Parent then
                    pcall(function(): () constraint:Destroy() end)
                    perLocal[own] = nil
                end
            end
            if next(perLocal) == nil then links[other] = nil end
        end
        for other: BasePart, wanted: {[BasePart]: boolean} in pairs(accepted) do
            local perLocal: {[BasePart]: any} = links[other] or {}
            links[other] = perLocal
            for own: BasePart in pairs(wanted) do
                if not perLocal[own] then
                    local ok: boolean, constraint: any = pcall(function(): any
                        local link: NoCollisionConstraint = Instance.new("NoCollisionConstraint")
                        link.Part0, link.Part1 = own, other
                        link.Parent = own
                        return link
                    end)
                    if ok and constraint then perLocal[own] = constraint end
                end
            end
            if next(perLocal) == nil then links[other] = nil end
        end
    end

    local function step(): ()
        if not enabled then return end
        local owner: Model?, humanoid: Humanoid?, root: BasePart? = host.getCharacterParts()
        if owner ~= character then
            destroyLinks()
            character = owner
            nextScan = 0
        end
        if not owner or not humanoid or not root or not owner.Parent or humanoid.Health <= 0 then
            destroyLinks()
            return
        end
        if isBusy() then
            if not suspended then destroyLinks() end
            suspended = true
            return
        end
        if suspended then suspended = false nextScan = 0 end
        local now: number = os.clock()
        if now >= nextScan then
            nextScan = now + SCAN_INTERVAL
            local ok: boolean, err: any = pcall(synchronize, owner, humanoid, root, now)
            if not ok then
                -- A streaming object may disappear during the scan. Retry on
                -- the next interval, without leaving partial constraints stuck.
                destroyLinks()
                if type(host.warn) == "function" then host.warn("Anti Fling: " .. tostring(err)) end
            end
        end
        if now > dangerUntil or root.Anchored or humanoid.Sit or humanoid.SeatPart then return end
        -- Emergency damping is only armed by a nearby extreme mover. Normal
        -- sprinting, jumps, vehicles and game launch pads are not capped merely
        -- because this feature is on.
        local walkSpeed: number = math.max(16, tonumber(humanoid.WalkSpeed) or 16)
        local speed: any = framework and framework:GetModule("Speed Hack")
        if speed and speed.Enabled and speed.Options.Speed then
            walkSpeed = math.max(walkSpeed, tonumber(speed.Options.Speed.Value) or 0)
        end
        local jumpPower: number = math.max(50, tonumber(humanoid.JumpPower) or 50)
        local velocity: Vector3 = root.AssemblyLinearVelocity
        local planar: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
        local limit: number = math.max(120, walkSpeed * 4)
        local riseLimit: number = math.max(180, jumpPower * 4)
        local nextVelocity: Vector3 = velocity
        local changed: boolean = false
        if planar.Magnitude > limit then
            local move: Vector3 = humanoid.MoveDirection
            local direction: Vector3 = move.Magnitude > 0.05 and move.Unit * walkSpeed or Vector3.zero
            nextVelocity = Vector3.new(direction.X, nextVelocity.Y, direction.Z)
            changed = true
        end
        if nextVelocity.Y > riseLimit then
            nextVelocity = Vector3.new(nextVelocity.X, riseLimit, nextVelocity.Z)
            changed = true
        end
        pcall(function(): ()
            if root.AssemblyAngularVelocity.Magnitude > 25 then
                root.AssemblyAngularVelocity = Vector3.zero
            end
            if changed then root.AssemblyLinearVelocity = nextVelocity end
        end)
    end

    local function toggleAntiFling(value: boolean): ()
        enabled = value == true
        disconnect("AntiFling")
        destroyLinks()
        character = nil
        nextScan = 0
        suspended = false
        if enabled then
            featureConnections.AntiFling = host.TaskManager:Connect(step, nil, "Anti Fling")
        end
    end

    feature = host.createUniversalFeature(
        "Anti Fling",
        "Collision Shield: local player and extreme-object protection",
        2,
        toggleAntiFling,
        {categoryName = "Utilities"}
    )
    host.addToggleOption(feature, "Player Shield", true, function(value: boolean): ()
        playerShield = value == true
        nextScan = 0
        if not playerShield and not impactShield then destroyLinks() end
    end, "Prevent local physical collisions with other character bodies without changing their collision settings.")
    host.addToggleOption(feature, "Impact Shield", true, function(value: boolean): ()
        impactShield = value == true
        nextScan = 0
        if not playerShield and not impactShield then destroyLinks() end
    end, "Temporarily avoid nearby extreme-speed loose objects; support platforms, seated vehicles and ordinary tools are left alone.")
    host.addFeatureTooltip(feature,
        "Collision Shield only changes local collision pairs. Extremely fast/streamed objects and server-owned physics can still launch you.")

    activeCleanup = function(): ()
        toggleAntiFling(false)
    end
    Module.Initialized = true
    return feature
end

function Module.destroy(): ()
    if activeCleanup then pcall(activeCleanup) end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
