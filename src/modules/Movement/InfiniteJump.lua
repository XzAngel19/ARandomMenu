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
    services: any,
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
    local framework: any = context.framework
    local getCharacterParts: any = host.getCharacterParts
    local movementInput: any = context.services.movementInput
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
    -- Both the enabled flag and the rate limiter live on `state` so the jump
    -- callback can keep checking them after the module's own teardown has
    -- started — a signal already dispatching still delivers one last event.
    local enabledNow: boolean = false
    local lastJumpAt: number = -math.huge

    local function performInfiniteJump(): ()
        -- A disconnected signal can still deliver the event it was already
        -- dispatching, which on touch — where the jump button fires continuously —
        -- kept launching the character after the module had been switched off.
        if not enabledNow then
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
        if now - lastJumpAt < spacing then
            return
        end
        lastJumpAt = now

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

    local jump: any
    jump = framework.Categories.Movement:CreateModule({
        Name = "Infinite Jump",
        Category = "Movement",
        Tooltip = "Jump again in mid-air, as a fixed height, a force, a "
            .. "climbing stack, a hold that rises, or a fall cancel.",
        Function = function(enabled: boolean): ()
            enabledNow = false
            lastJumpAt = -math.huge
            if not enabled then
                jump:SetStatus(nil)
                return
            end
            enabledNow = true
            jump:SetStatus(infiniteJumpSettings.mode)

            -- `JumpRequest` is the one jump signal every device raises.
            jump:Clean(movementInput.onJumpRequest(function(): ()
                if infiniteJumpSettings.mode == "Rise" then
                    return
                end
                performInfiniteJump()
            end))

            jump:Loop(function(): ()
                if not enabledNow
                    or infiniteJumpSettings.mode ~= "Rise"
                    or not movementInput.isJumpHeld() then
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
        end,
    })
    jump:CreateDropdown({
        Name = "Mode",
        List = {"Normal", "Impulse", "Stack", "Rise", "Fall"},
        Index = 1,
        Function = function(value: string): ()
            infiniteJumpSettings.mode = value
            if jump.Enabled then
                jump:SetStatus(value)
            end
        end,
    })
    jump:CreateSlider({
        Name = "Jump power",
        Show = {Option = "Mode", Values = {"Normal", "Impulse", "Stack"}},
        Min = 10,
        Max = 250,
        Default = infiniteJumpSettings.strength,
        Function = function(value: number): ()
            infiniteJumpSettings.strength = value
        end,
        Tooltip = "Vertical velocity of one jump. Rise and Fall do not launch "
            .. "you, so they have no power to set.",
    })
    jump:CreateSlider({
        Name = "Rise speed",
        Show = {Option = "Mode", Values = {"Rise"}},
        Min = 10,
        Max = 350,
        Default = infiniteJumpSettings.riseSpeed,
        Function = function(value: number): ()
            infiniteJumpSettings.riseSpeed = value
        end,
    })
    jump:CreateSlider({
        Name = "Jump interval (s)",
        Show = {Option = "Mode", Values = {"Normal", "Impulse", "Stack", "Fall"}},
        Min = 0.05,
        Max = 0.6,
        Default = infiniteJumpSettings.interval,
        Function = function(value: number): ()
            infiniteJumpSettings.interval = value
        end,
        Tooltip = "Minimum spacing between jumps. Rise ignores it: it is a "
            .. "hold, not a repeat.",
    })
    -- Every row in this panel belongs to the mode, so there is no ungated
    -- final row whose creation would make the kernel re-read the rules one
    -- last time. One explicit pass keeps the panel honest.
    jump:RefreshVisibility()

    activeCleanup = function(): ()
        enabledNow = false
        lastJumpAt = -math.huge
    end
    Module.Initialized = true
    return jump
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
