export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Jump",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local movementInput: any = context.services and context.services.movementInput
    local UserInputService: any = host.UserInputService or game:GetService("UserInputService")
    local LocalPlayer: Player = host.LocalPlayer or game:GetService("Players").LocalPlayer

    local originalJumpPower = setmetatable({}, {__mode = "k"}) :: {[Humanoid]: {jumpPower: number, useJumpPower: boolean}}
    local lastInfiniteJumpAt: number = -math.huge

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return character, humanoid, root
    end

    local function restoreJumpPower(): ()
        for humanoid: Humanoid, original in pairs(originalJumpPower) do
            if humanoid and humanoid.Parent then
                humanoid.JumpPower = original.jumpPower
                humanoid.UseJumpPower = original.useJumpPower
            end
        end
        originalJumpPower = setmetatable({}, {__mode = "k"}) :: any
    end

    local function performHighJump(velocityOverride: number?): ()
        local _, humanoid: Humanoid?, root: BasePart? = characterParts()
        if not humanoid or not root or humanoid.Health <= 0 then
            return
        end
        local velocityVal: number = velocityOverride or 72
        local current: Vector3 = (root :: BasePart).AssemblyLinearVelocity
        ;(root :: BasePart).AssemblyLinearVelocity = Vector3.new(
            current.X,
            velocityVal,
            current.Z
        )
        if humanoid.FloorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        end
    end

    local function performInfiniteJump(mode: string, strength: number, interval: number, stackCeiling: number): ()
        local _, humanoid: Humanoid?, root: BasePart? = characterParts()
        if not humanoid or not root or humanoid.Health <= 0 then
            return
        end

        local spacing: number = interval
        if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
            spacing = math.max(spacing, 0.25)
        end

        local now: number = os.clock()
        if now - lastInfiniteJumpAt < spacing then
            return
        end
        lastInfiniteJumpAt = now

        local velocity: Vector3 = (root :: BasePart).AssemblyLinearVelocity
        local vertical: number
        if mode == "Stack" then
            vertical = math.min(velocity.Y + strength, stackCeiling)
        elseif mode == "Impulse" then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            ;(root :: BasePart):ApplyImpulse(
                Vector3.new(0, strength - velocity.Y, 0) * (root :: BasePart).AssemblyMass
            )
            return
        elseif mode == "Fall" then
            if velocity.Y >= 0 then
                return
            end
            vertical = 0
        else
            vertical = strength
        end

        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        ;(root :: BasePart).AssemblyLinearVelocity = Vector3.new(velocity.X, vertical, velocity.Z)
    end

    local jump: any
    jump = framework.Categories.Movement:CreateModule({
        Name = "Jump",
        Category = "Movement",
        ConfigKey = "Universal.Jump",
        Order = 6,
        Tooltip = "Consolidated jump controls: adjust Jump Power, execute High Jump, enable Infinite Jump and Auto Jump.",
        Function = function(enabled: boolean): ()
            restoreJumpPower()
            lastInfiniteJumpAt = -math.huge
            if not enabled then
                jump:SetStatus(nil)
                return
            end

            jump:SetStatus(tostring(math.round(jump.Options["Jump power"].Value)))
            jump:Clean(restoreJumpPower)

            -- Connect infinite jump request if movementInput service is present
            if movementInput and type(movementInput.onJumpRequest) == "function" then
                jump:Clean(movementInput.onJumpRequest(function(): ()
                    local opts = jump.Options
                    if not opts["Infinite jump"] or not opts["Infinite jump"].Value then
                        return
                    end
                    local mode: string = opts["Infinite jump mode"] and opts["Infinite jump mode"].Value or "Normal"
                    if mode == "Rise" then
                        return
                    end
                    local strength: number = opts["Infinite jump power"] and opts["Infinite jump power"].Value or 50
                    local interval: number = opts["Jump interval"] and opts["Jump interval"].Value or 0.18
                    performInfiniteJump(mode, strength, interval, 160)
                end))
            end

            jump:Loop(function(): ()
                local opts = jump.Options
                local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not humanoid or not root or humanoid.Health <= 0 then
                    return
                end

                -- 1. Apply Jump Power
                local wantedPower: number = opts["Jump power"] and opts["Jump power"].Value or 80
                if originalJumpPower[humanoid] == nil then
                    originalJumpPower[humanoid] = {
                        jumpPower = humanoid.JumpPower,
                        useJumpPower = humanoid.UseJumpPower,
                    }
                end
                humanoid.UseJumpPower = true
                humanoid.JumpPower = wantedPower

                -- 2. Auto Jump
                if opts["Auto jump"] and opts["Auto jump"].Value then
                    local moveDir: Vector3 = humanoid.MoveDirection
                    if moveDir.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air then
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end

                -- 3. Infinite Jump "Rise" mode (hold to rise)
                if opts["Infinite jump"] and opts["Infinite jump"].Value then
                    local mode: string = opts["Infinite jump mode"] and opts["Infinite jump mode"].Value or "Normal"
                    if mode == "Rise" and movementInput and type(movementInput.isJumpHeld) == "function" and movementInput.isJumpHeld() then
                        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                        local curVel: Vector3 = (root :: BasePart).AssemblyLinearVelocity
                        local riseSpd: number = opts["Rise speed"] and opts["Rise speed"].Value or 75
                        ;(root :: BasePart).AssemblyLinearVelocity = Vector3.new(curVel.X, riseSpd, curVel.Z)
                    end
                end
            end)
        end,
    })

    jump:CreateSlider({
        Name = "Jump power",
        Min = 0,
        Max = 500,
        Default = 80,
        Function = function(value: number): ()
            if jump.Enabled then
                jump:SetStatus(tostring(math.round(value)))
            end
        end,
        Tooltip = "Character jump power (default Roblox jump is 50).",
    })

    jump:CreateButton({
        Name = "High jump",
        Function = function(): ()
            local velocityVal: number = jump.Options["High jump velocity"] and jump.Options["High jump velocity"].Value or 72
            performHighJump(velocityVal)
        end,
        Tooltip = "Launches your character into a single massive vertical jump.",
    })

    jump:CreateSlider({
        Name = "High jump velocity",
        Min = 25,
        Max = 250,
        Default = 72,
        Tooltip = "Vertical velocity applied when High Jump is activated.",
    })

    jump:CreateToggle({
        Name = "Infinite jump",
        Default = false,
        Tooltip = "Allows jumping repeatedly in mid-air.",
    })

    jump:CreateDropdown({
        Name = "Infinite jump mode",
        Show = {Option = "Infinite jump", Values = {true}},
        List = {"Normal", "Impulse", "Stack", "Rise", "Fall"},
        Index = 1,
        Tooltip = "Normal = fixed mid-air jump; Impulse = physical thrust; Stack = accumulative upward velocity; Rise = hold to float up; Fall = cancels downward fall speed.",
    })

    jump:CreateSlider({
        Name = "Infinite jump power",
        Show = {Option = "Infinite jump", Values = {true}},
        Min = 10,
        Max = 250,
        Default = 50,
        Tooltip = "Vertical impulse applied during mid-air jumps.",
    })

    jump:CreateSlider({
        Name = "Rise speed",
        Show = {Option = "Infinite jump", Values = {true}},
        Min = 10,
        Max = 350,
        Default = 75,
        Tooltip = "Vertical speed while holding jump in Rise mode.",
    })

    jump:CreateSlider({
        Name = "Jump interval",
        Show = {Option = "Infinite jump", Values = {true}},
        Min = 0.05,
        Max = 0.6,
        Default = 0.18,
        Tooltip = "Minimum delay in seconds between mid-air jumps.",
    })

    jump:CreateToggle({
        Name = "Auto jump",
        Default = false,
        Tooltip = "Continuously jumps while walking on the ground.",
    })

    activeCleanup = function(): ()
        restoreJumpPower()
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
