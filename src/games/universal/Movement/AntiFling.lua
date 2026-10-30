export type Runtime = {
    framework: any,
    entity: any,
    host: any,
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
    local workspace: any = host.workspace
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local services: any = (context :: any).services
    local activity: any = services and services.activity
    local framework: any = context.framework

    local enabled: boolean = false
    local sensitivity: number = 2.5
    -- A fling is an impulse far beyond anything the body can produce. These are
    -- the only fixed numbers left: everything else scales with the character.
    local SPIN_LIMIT: number = 20        -- rad/s: a driven spin, not a turn
    local FALL_LIMIT: number = 500       -- studs/s: Roblox never falls this fast
    local antiFlingFeature: any = nil

    local function isBusy(): boolean
        if not activity or type(activity.isActive) ~= "function" then
            return false
        end
        -- Our own flings must never be cancelled by our own protection.
        return activity.isActive("fling") or activity.isActive("walkfling")
    end

    local function speedModuleWalkSpeed(): number
        local ok: boolean, feature: any = pcall(function(): any
            return framework and framework.GetModule and framework:GetModule("Speed")
        end)
        if ok and feature and feature.Enabled and feature.Options and feature.Options.Speed then
            local value: any = feature.Options.Speed.Value
            if type(value) == "number" and value > 0 then
                return value
            end
        end
        return 0
    end

    -- Runs every frame: whatever the fling did to the assembly is removed before
    -- the next physics step instead of waiting for the character to die.
    local function step(): ()
        if not enabled then
            return
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? = host.getCharacterParts()
        if not humanoid or not root or humanoid.Health <= 0 or root.Anchored then
            return
        end
        if humanoid.Sit or humanoid.SeatPart then
            return
        end
        if isBusy() then
            return
        end

        local walkSpeed: number = math.max(16, tonumber(humanoid.WalkSpeed) or 16)
        walkSpeed = math.max(walkSpeed, speedModuleWalkSpeed())
        local jumpPower: number = math.max(50, tonumber(humanoid.JumpPower) or 50)
        local maxPlanar: number = math.max(80, walkSpeed * sensitivity)
        local maxRise: number = math.max(150, jumpPower * 3)

        local velocity: Vector3 = root.AssemblyLinearVelocity
        local angular: Vector3 = root.AssemblyAngularVelocity
        local planar: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
        local changed: boolean = false
        local nextVelocity: Vector3 = velocity

        if planar.Magnitude > maxPlanar then
            -- Keep the input direction, drop the impulse. Walking is untouched:
            -- the limit is a multiple of the character's own walking speed.
            local moveDir: Vector3 = humanoid.MoveDirection
            local target: Vector3 = Vector3.zero
            if moveDir.Magnitude > 0.05 then
                target = moveDir.Unit * math.min(maxPlanar, walkSpeed)
            end
            nextVelocity = Vector3.new(target.X, velocity.Y, target.Z)
            changed = true
        end
        if velocity.Y > maxRise then
            nextVelocity = Vector3.new(nextVelocity.X, maxRise, nextVelocity.Z)
            changed = true
        elseif velocity.Y < -FALL_LIMIT then
            nextVelocity = Vector3.new(nextVelocity.X, -FALL_LIMIT, nextVelocity.Z)
            changed = true
        end
        if angular.Magnitude > SPIN_LIMIT then
            pcall(function(): ()
                root.AssemblyAngularVelocity = Vector3.zero
            end)
            changed = true
        end
        if changed then
            pcall(function(): ()
                root.AssemblyLinearVelocity = nextVelocity
                -- Older executors still route the impulse through Velocity.
                root.Velocity = nextVelocity
            end)
        end
    end

    local function toggleAntiFling(state: boolean): ()
        enabled = state == true
        disconnectFeatureConnection("AntiFling")
        if not enabled then
            return
        end
        host.featureConnections.AntiFling = host.TaskManager:Connect(step, nil, "Anti Fling")
    end

    -- No options on purpose (v138.8): Anti Fling is a plain ON/OFF card. The
    -- thresholds scale with the character by themselves -- planar speed above
    -- 2.5x WalkSpeed, rise above three jump powers, fall past 500 studs/s and spin
    -- past 20 rad/s -- so there is nothing to tune.
    antiFlingFeature = createUniversalFeature(
        "Anti Fling",
        "Cancel fling impulses on the local character every physics frame",
        2,
        toggleAntiFling,
        {categoryName = "Utilities", noOptions = true}
    )
    addFeatureTooltip(
        antiFlingFeature,
        "Each frame, any planar speed above 2.5x your WalkSpeed, any rise above three "
            .. "jump powers, any fall past 500 studs/s and any spin past 20 rad/s is "
            .. "removed while your own input is kept. It never teleports you and it "
            .. "stands alone (no Anti Void needed)."
    )

    activeCleanup = function(): ()
        enabled = false
        if disconnectFeatureConnection then
            disconnectFeatureConnection("AntiFling")
        end
    end
    Module.Initialized = true
    return antiFlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
