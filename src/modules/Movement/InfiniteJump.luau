--!strict
--
-- Infinite Jump.
--
-- Five shapes, because "jump again in mid-air" means different things: a fixed
-- height every time, the same as a force, a stack that climbs, a hold that
-- rises steadily, and one that only cancels a fall. An interval floor keeps
-- the character controllable — on touch especially, where the on-screen jump
-- button repeats while a finger rests on it.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "InfiniteJump",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local state: any = host.state
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local addCycleOption: any = host.addCycleOption
    local UserInputService: any = host.UserInputService
    local infiniteJumpSettings = {
        mode = "Normal",
        strength = 50,
        riseSpeed = 75,
        -- Minimum spacing between jumps. Touch fires jump requests continuously;
        -- without this the character leaves the map in a second.
        interval = 0.18,
        stackCeiling = 160,
    }
    -- Both the enabled flag and the rate limiter live on `state`: bootstrap() is
    -- already at Luau's 200 local-register ceiling.
    state.infiniteJumpEnabled = false
    state.lastInfiniteJumpAt = -math.huge

    local function performInfiniteJump(): ()
        -- A disconnected signal can still deliver the event it was already
        -- dispatching, which on touch — where the jump button fires continuously —
        -- kept launching the character after the module had been switched off.
        if not state.infiniteJumpEnabled then
            return
        end

        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root or humanoid.Health <= 0 then
            return
        end

        -- Touch cannot tap as deliberately as a keyboard can: the on-screen jump
        -- button repeats for as long as a finger rests on it, so the floor on the
        -- spacing is higher there no matter what the slider says.
        local spacing: number = infiniteJumpSettings.interval
        if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
            spacing = math.max(spacing, 0.25)
        end

        local now: number = os.clock()
        if now - state.lastInfiniteJumpAt < spacing then
            return
        end
        state.lastInfiniteJumpAt = now

        local velocity: Vector3 = root.AssemblyLinearVelocity
        local vertical: number
        if infiniteJumpSettings.mode == "Stack" then
            vertical = math.min(
                velocity.Y + infiniteJumpSettings.strength,
                infiniteJumpSettings.stackCeiling
            )
        elseif infiniteJumpSettings.mode == "Impulse" then
            -- Force instead of a velocity write: the body keeps whatever physics
            -- the game applies to it, which survives checks that watch for
            -- AssemblyLinearVelocity being overwritten.
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            root:ApplyImpulse(
                Vector3.new(0, infiniteJumpSettings.strength - velocity.Y, 0)
                    * root.AssemblyMass
            )
            return
        elseif infiniteJumpSettings.mode == "Fall" then
            -- Cancel the fall: kill downward momentum and hold position for an
            -- instant. Jumping again keeps you up without ever launching.
            if velocity.Y >= 0 then
                return
            end
            vertical = 0
        else
            vertical = infiniteJumpSettings.strength
        end

        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        root.AssemblyLinearVelocity = Vector3.new(velocity.X, vertical, velocity.Z)
    end

    local function toggleInfiniteJump(enabled)
        disconnectFeatureConnection("InfiniteJump")
        disconnectFeatureConnection("InfiniteJumpRise")
        state.infiniteJumpEnabled = false
        state.lastInfiniteJumpAt = -math.huge

        if not enabled then
            return
        end
        state.infiniteJumpEnabled = true

        -- `JumpRequest` is the one jump signal every device raises.
        featureConnections.InfiniteJump = state.onJumpRequest(function(): ()
            if infiniteJumpSettings.mode == "Rise" then
                return
            end
            performInfiniteJump()
        end)

        featureConnections.InfiniteJumpRise = TaskManager:Connect(function(): ()
            if not state.infiniteJumpEnabled
                or infiniteJumpSettings.mode ~= "Rise"
                or not state.isJumpHeld() then
                return
            end

            local _, humanoid, root = getCharacterParts()
            if not humanoid or not root or humanoid.Health <= 0 then
                return
            end

            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
            local velocity = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(
                velocity.X,
                infiniteJumpSettings.riseSpeed,
                velocity.Z
            )
        end)
    end

    local InfiniteJumpFeature = createUniversalFeature(
        "Infinite Jump",
        "Normal, force-based, stacking, hold-to-rise or fall-cancel jumping",
        7,
        toggleInfiniteJump
    )
    addCycleOption(
        InfiniteJumpFeature,
        "Mode",
        {"Normal", "Impulse", "Stack", "Rise", "Fall"},
        1,
        function(value)
            infiniteJumpSettings.mode = value
        end
    )
    addNumberOption(
        InfiniteJumpFeature,
        "Jump power",
        infiniteJumpSettings.strength,
        10,
        250,
        function(value)
            infiniteJumpSettings.strength = value
        end
    )
    addNumberOption(
        InfiniteJumpFeature,
        "Jump interval (s)",
        infiniteJumpSettings.interval,
        0.05,
        0.6,
        function(value)
            infiniteJumpSettings.interval = value
        end
    )
    addNumberOption(
        InfiniteJumpFeature,
        "Rise speed",
        infiniteJumpSettings.riseSpeed,
        10,
        350,
        function(value)
            infiniteJumpSettings.riseSpeed = value
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("InfiniteJump")
    end
    Module.Initialized = true
    return InfiniteJumpFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
