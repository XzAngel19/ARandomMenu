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

    local function canControlJump(humanoid: Humanoid): boolean
        if humanoid.Health <= 0 or humanoid.Sit or humanoid.SeatPart then return false end
        local state = humanoid:GetState()
        return state ~= Enum.HumanoidStateType.Seated and state ~= Enum.HumanoidStateType.Swimming
            and state ~= Enum.HumanoidStateType.Climbing and state ~= Enum.HumanoidStateType.Physics
            and state ~= Enum.HumanoidStateType.PlatformStanding and state ~= Enum.HumanoidStateType.Ragdoll
            and state ~= Enum.HumanoidStateType.FallingDown and state ~= Enum.HumanoidStateType.Dead
    end

    local fallHumanoid: Humanoid? = nil
    local fallConnection: RBXScriptConnection? = nil
    local originalStates = nil
    local redirecting = false
    local fallBoosted: Humanoid? = nil
    local pressHeld = false
    local jumpTouch: InputObject? = nil

    local function clearFallController(): ()
        if fallConnection then fallConnection:Disconnect(); fallConnection = nil end
        if fallHumanoid and fallHumanoid.Parent and originalStates then
            fallHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,originalStates.jumping)
            fallHumanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall,originalStates.freefall)
        end
        fallHumanoid, originalStates, fallBoosted = nil, nil, nil
    end
    local function enforceFall(humanoid: Humanoid): ()
        humanoid.Jump = false
        if humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,false) end
        if not humanoid:GetStateEnabled(Enum.HumanoidStateType.Freefall) then humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall,true) end
        if humanoid:GetState() == Enum.HumanoidStateType.Jumping and not redirecting then
            redirecting = true
            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
            redirecting = false
        end
    end
    local function syncFallController(humanoid: Humanoid?, enabled: boolean): ()
        if not enabled or not humanoid or not canControlJump(humanoid) then
            if fallHumanoid then clearFallController() end
            return
        end
        if fallHumanoid ~= humanoid then
            clearFallController()
            fallHumanoid = humanoid
            originalStates = {jumping=humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
                freefall=humanoid:GetStateEnabled(Enum.HumanoidStateType.Freefall)}
            fallConnection = humanoid.StateChanged:Connect(function(_,nextState)
                if not canControlJump(humanoid) or nextState == Enum.HumanoidStateType.Landed then clearFallController()
                elseif nextState == Enum.HumanoidStateType.Jumping then enforceFall(humanoid) end
            end)
        end
        enforceFall(humanoid)
    end

    local function performHighJump(velocityOverride: number?): ()
        local _, humanoid: Humanoid?, root: BasePart? = characterParts()
        if not humanoid or not root or root.Anchored or not canControlJump(humanoid) then
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

    local function performInfiniteJump(mode: string, strength: number, interval: number): ()
        local _, humanoid: Humanoid?, root: BasePart? = characterParts()
        if not humanoid or not root or root.Anchored or not canControlJump(humanoid) then
            return
        end

        local now: number = os.clock()
        if now - lastInfiniteJumpAt < interval then
            return
        end
        lastInfiniteJumpAt = now

        local velocity: Vector3 = (root :: BasePart).AssemblyLinearVelocity
        -- Positive Y is intentional: Fall changes the actual local state,
        -- not the trajectory into downward motion or a manual animation.
        -- X/Z momentum is unchanged; this makes no server-state guarantee.
        syncFallController(humanoid, mode == "Fall")
        fallBoosted = mode == "Fall" and humanoid or nil
        ;(root :: BasePart).AssemblyLinearVelocity = Vector3.new(velocity.X, strength, velocity.Z)
        humanoid:ChangeState(mode == "Fall" and Enum.HumanoidStateType.Freefall or Enum.HumanoidStateType.Jumping)
    end

    local jump: any
    local function refreshFall(): ()
        local _, humanoid, root = characterParts()
        syncFallController(humanoid,fallBoosted == humanoid and root ~= nil and not root.Anchored and jump.Enabled and jump.Options["Infinite jump"].Value
            and jump.Options["Infinite jump mode"].Value == "Fall")
    end
    jump = framework.Categories.Exploits:CreateModule({
        Name = "Jump",
        Category = "Exploits",
        ConfigKey = "Universal.Jump",
        Order = 6,
        Tooltip = "Consolidated jump controls: adjust Jump Power, execute High Jump, enable Infinite Jump and Auto Jump.",
        Function = function(enabled: boolean): ()
            restoreJumpPower()
            clearFallController()
            lastInfiniteJumpAt = -math.huge
            pressHeld, jumpTouch = false, nil
            if not enabled then
                jump:SetStatus(nil)
                return
            end

            jump:SetStatus("active")
            jump:Clean(function(): () restoreJumpPower(); clearFallController() end)

            local function requestJump(): ()
                if pressHeld then return end
                pressHeld = true
                if UserInputService.TouchEnabled then
                    local touches = UserInputService:GetTouches()
                    if #touches == 1 then jumpTouch = touches[1]
                    else
                        local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                        local touchGui = gui and gui:FindFirstChild("TouchGui")
                        local button = touchGui and touchGui:FindFirstChild("JumpButton",true)
                        if button then
                            local at, size = button.AbsolutePosition, button.AbsoluteSize
                            for _, touch in ipairs(touches) do
                                local p = touch.Position
                                if p.X >= at.X and p.Y >= at.Y and p.X <= at.X+size.X and p.Y <= at.Y+size.Y then jumpTouch = touch;break end
                            end
                        end
                    end
                end
                local _, humanoid, root = characterParts()
                -- Ground takeoff belongs to Roblox: ordinary Jumping/animation.
                -- Only a new press in midair is an extra jump.
                if not humanoid or not root then return end
                if humanoid.FloorMaterial ~= Enum.Material.Air then return end
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
                performInfiniteJump(mode, strength, interval)
            end
            if movementInput and type(movementInput.onJumpRequest) == "function" then
                jump:Clean(movementInput.onJumpRequest(requestJump))
            else
                jump:Clean(UserInputService.JumpRequest:Connect(requestJump))
            end

            jump:Clean(UserInputService.InputEnded:Connect(function(event)
                if event.KeyCode == Enum.KeyCode.Space or event.KeyCode == Enum.KeyCode.ButtonA
                    or event.UserInputType == Enum.UserInputType.Touch and (not jumpTouch or event == jumpTouch) then
                    pressHeld, jumpTouch = false, nil
                end
            end))
            jump:Clean(UserInputService.WindowFocusReleased:Connect(function() pressHeld, jumpTouch = false, nil end))
            refreshFall()
            jump:Clean(host.RunService.PreSimulation:Connect(function(): ()
                local opts = jump.Options
                local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not humanoid or not root or humanoid.Health <= 0 then
                    clearFallController()
                    return
                end

                local canMove = canControlJump(humanoid) and not root.Anchored
                local fallMode: boolean = canMove and opts["Infinite jump"] and opts["Infinite jump"].Value
                    and opts["Infinite jump mode"].Value == "Fall"
                local state = humanoid:GetState()
                local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
                    and state ~= Enum.HumanoidStateType.Jumping and state ~= Enum.HumanoidStateType.Freefall
                if grounded or fallBoosted ~= humanoid then clearFallController() end
                syncFallController(humanoid, fallMode and fallBoosted == humanoid)

                if opts["Custom jump power"] and opts["Custom jump power"].Value then
                    local wantedPower: number = opts["Jump power"] and opts["Jump power"].Value or 80
                    if originalJumpPower[humanoid] == nil then
                        originalJumpPower[humanoid] = {
                            jumpPower = humanoid.JumpPower,
                            useJumpPower = humanoid.UseJumpPower,
                        }
                    end
                    humanoid.UseJumpPower = true
                    humanoid.JumpPower = wantedPower
                else
                    restoreJumpPower()
                end

                if canMove and opts["Auto jump"] and opts["Auto jump"].Value then
                    local moveDir: Vector3 = humanoid.MoveDirection
                    if moveDir.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air then
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end

                -- Long Jump: horizontal boost when jumping
                if canMove and longJumpEnabled and humanoid.FloorMaterial ~= Enum.Material.Air then
                    local moveDir: Vector3 = humanoid.MoveDirection
                    if moveDir.Magnitude > 0.05 then
                        local dir: Vector3 = moveDir * longJumpSpeed
                        if longJumpMode == "Velocity" then
                            root.AssemblyLinearVelocity = dir + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
                        elseif longJumpMode == "Impulse" then
                            local diff: Vector3 = (dir - root.AssemblyLinearVelocity) * Vector3.new(1, 0, 1)
                            if diff.Magnitude > 2 then
                                root:ApplyImpulse(diff * root.AssemblyMass)
                            end
                        else -- CFrame
                            root.CFrame += dir * (1/60)
                        end
                    end
                end

                if canMove and opts["Infinite jump"] and opts["Infinite jump"].Value then
                    local mode: string = opts["Infinite jump mode"] and opts["Infinite jump mode"].Value or "Normal"
                    if mode == "Rise" and movementInput and type(movementInput.isJumpHeld) == "function" and movementInput.isJumpHeld() then
                        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                        local curVel: Vector3 = (root :: BasePart).AssemblyLinearVelocity
                        local riseSpd: number = opts["Rise speed"] and opts["Rise speed"].Value or 75
                        ;(root :: BasePart).AssemblyLinearVelocity = Vector3.new(curVel.X, riseSpd, curVel.Z)
                    end
                end
            end))
        end,
    })

    jump:CreateToggle({
        Name = "Custom jump power",
        Default = false,
        Tooltip = "Enables custom jump height/power for ground jumps. Turn off if you only want Infinite Jump or High Jump.",
    })

    jump:CreateSlider({
        Name = "Jump power",
        Show = {Option = "Custom jump power", Values = {true}},
        Min = -500,
        Max = 500,
        Default = 80,
        Function = function(value: number): ()
            if jump.Enabled and jump.Options["Custom jump power"].Value then
                jump:SetStatus(tostring(math.round(value)))
            end
        end,
        Tooltip = "Character jump power (default Roblox jump is 50). Negative values launch the character downward.",
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
        Min = -250,
        Max = 250,
        Default = 72,
        Tooltip = "Vertical velocity applied when High Jump button is pressed. Negative values launch the character downward.",
    })

    jump:CreateToggle({
        Name = "Infinite jump",
        Default = false,
        Function = refreshFall,
        Tooltip = "Allows jumping repeatedly in mid-air.",
    })

    jump:CreateDropdown({
        Name = "Infinite jump mode",
        Show = {Option = "Infinite jump", Values = {true}},
        List = {"Normal", "Rise", "Fall"},
        Function = refreshFall,
        Index = 1,
        Tooltip = "Normal = mid-air jump; Rise = hold to rise; Fall = normal ground jump, then Freefall for each extra mid-air press. Release jump between presses; holding does not repeat. Server behavior is not guaranteed.",
    })

    jump:CreateSlider({
        Name = "Infinite jump power",
        Show = {
            {Option = "Infinite jump", Values = {true}},
            {Option = "Infinite jump mode", Values = {"Normal", "Fall"}},
        },
        Min = -250,
        Max = 250,
        Default = 50,
        Tooltip = "Vertical impulse applied during mid-air jumps. Negative values push the character downward.",
    })

    jump:CreateSlider({
        Name = "Rise speed",
        Show = {
            {Option = "Infinite jump", Values = {true}},
            {Option = "Infinite jump mode", Values = {"Rise"}},
        },
        Min = -350,
        Max = 350,
        Default = 75,
        Tooltip = "Vertical speed while holding jump in Rise mode. Negative values descend instead of rising.",
    })

    jump:CreateSlider({
        Name = "Jump interval",
        Show = {
            {Option = "Infinite jump", Values = {true}},
            {Option = "Infinite jump mode", Values = {"Normal", "Fall"}},
        },
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

    -- Long Jump: horizontal boost when jumping (from VapeV4)
    local longJumpEnabled = false
    local longJumpSpeed = 50
    local longJumpMode = "Velocity"

    jump:CreateToggle({
        Name = "Long jump",
        Default = false,
        Function = function(value: boolean): ()
            longJumpEnabled = value
        end,
        Tooltip = "Adds horizontal speed boost in your move direction when jumping.",
    })

    jump:CreateDropdown({
        Name = "Long jump mode",
        Show = {Option = "Long jump", Values = {true}},
        List = {"Velocity", "Impulse", "CFrame"},
        Index = 1,
        Function = function(value: string): ()
            longJumpMode = value
        end,
        Tooltip = "How the horizontal boost is applied: Velocity (smooth), Impulse (forces), or CFrame (direct position).",
    })

    jump:CreateSlider({
        Name = "Long jump speed",
        Show = {Option = "Long jump", Values = {true}},
        Min = -150,
        Max = 150,
        Default = 50,
        Function = function(value: number): ()
            longJumpSpeed = value
        end,
        Tooltip = "Horizontal boost speed in studs/second. Negative values boost backwards.",
    })

    activeCleanup = function(): ()
        if jump.Enabled then jump:Toggle(false) end
        restoreJumpPower()
        clearFallController()
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
