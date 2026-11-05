export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Infinite Jump",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local services: any = context.services
    local LocalPlayer: Player = host.LocalPlayer
    local UserInputService: UserInputService = host.UserInputService
    local RunService: RunService = host.RunService
    local movementInput: any = services and services.movementInput

    local lastBoostAt: number = -math.huge
    local pressHeld: boolean = false
    local jumpTouch: any = nil
    local heldKey: any = nil
    local infiniteJump: any

    local function mode(): string
        local option: any = infiniteJump and infiniteJump.Options and infiniteJump.Options.Mode
        return option and option.Value == "Rise" and "Rise" or "Normal"
    end

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return character, humanoid, root
    end

    local function canBoostJump(humanoid: Humanoid?): boolean
        if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
            return false
        end
        local currentState: Enum.HumanoidStateType = humanoid:GetState()
        return currentState ~= Enum.HumanoidStateType.Seated
            and currentState ~= Enum.HumanoidStateType.Swimming
            and currentState ~= Enum.HumanoidStateType.Climbing
            and currentState ~= Enum.HumanoidStateType.Physics
            and currentState ~= Enum.HumanoidStateType.PlatformStanding
            and currentState ~= Enum.HumanoidStateType.Ragdoll
            and currentState ~= Enum.HumanoidStateType.Dead
    end

    infiniteJump = framework.Categories.Exploits:CreateModule({
        Name = "Infinite Jump",
        Category = "Exploits",
        ConfigKey = "Universal.InfiniteJump",
        Order = 10,
        Tooltip = "Normal adds one jump per press; Rise ascends while the jump key or mobile jump button is held.",
        Function = function(enabled: boolean): ()
            lastBoostAt = -math.huge
            pressHeld = false
            jumpTouch = nil
            heldKey = nil
            if not enabled then
                infiniteJump:SetStatus(nil)
                return
            end

            infiniteJump:SetStatus(mode())

            local function executeAirJump(): ()
                local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not humanoid or not root or root.Anchored or not canBoostJump(humanoid) then
                    return
                end
                local power: number = infiniteJump.Options["Jump Power"]
                    and infiniteJump.Options["Jump Power"].Value
                    or 50
                -- Leave the first positive ground jump to Roblox on both PC
                -- and mobile. Negative power deliberately inverts takeoff.
                if humanoid.FloorMaterial ~= Enum.Material.Air and power >= 0 then
                    return
                end
                local now: number = os.clock()
                if now - lastBoostAt < 0.08 then
                    return
                end
                lastBoostAt = now

                local velocity: Vector3 = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, power, velocity.Z)
                humanoid:ChangeState(
                    if power < 0
                        then Enum.HumanoidStateType.Freefall
                        else Enum.HumanoidStateType.Jumping
                )
            end

            local function onJumpRequested(): ()
                if UserInputService and type(UserInputService.GetFocusedTextBox) == "function"
                    and UserInputService:GetFocusedTextBox() then return end
                if pressHeld then
                    return
                end
                pressHeld = true
                if UserInputService and UserInputService.TouchEnabled then
                    local okTouches: boolean, touches: any = pcall(function(): any
                        return UserInputService:GetTouches()
                    end)
                    if okTouches and type(touches) == "table" then
                        if #touches == 1 then
                            jumpTouch = touches[1]
                        else
                            local gui: Instance? = LocalPlayer
                                and LocalPlayer:FindFirstChildOfClass("PlayerGui")
                            local touchGui: Instance? = gui and gui:FindFirstChild("TouchGui")
                            local button: any = touchGui and touchGui:FindFirstChild("JumpButton", true)
                            if button then
                                local at: Vector2 = button.AbsolutePosition
                                local size: Vector2 = button.AbsoluteSize
                                for _, touch: any in ipairs(touches) do
                                    local p: Vector3 = touch.Position
                                    if p.X >= at.X and p.Y >= at.Y
                                        and p.X <= at.X + size.X
                                        and p.Y <= at.Y + size.Y then
                                        jumpTouch = touch
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                executeAirJump()
            end

            if movementInput and type(movementInput.onJumpRequest) == "function" then
                infiniteJump:Clean(movementInput.onJumpRequest(onJumpRequested))
            elseif UserInputService and UserInputService.JumpRequest then
                infiniteJump:Clean(UserInputService.JumpRequest:Connect(onJumpRequested))
            end

            -- Direct PC (Spacebar / Gamepad ButtonA) + Mobile TouchGui JumpButton support
            if UserInputService and UserInputService.InputBegan then
                infiniteJump:Clean(UserInputService.InputBegan:Connect(function(input: any, gameProcessed: boolean): ()
                    if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
                        local typing: boolean = type(UserInputService.GetFocusedTextBox) == "function"
                            and UserInputService:GetFocusedTextBox() ~= nil
                        if not gameProcessed and not typing then
                            heldKey = input.KeyCode
                            onJumpRequested()
                        end
                    elseif input.UserInputType == Enum.UserInputType.Touch then
                        local gui: Instance? = LocalPlayer
                            and LocalPlayer:FindFirstChildOfClass("PlayerGui")
                        local touchGui: Instance? = gui and gui:FindFirstChild("TouchGui")
                        local button: any = touchGui and touchGui:FindFirstChild("JumpButton", true)
                        if button and button.AbsolutePosition and button.AbsoluteSize and input.Position then
                            local at: Vector2 = button.AbsolutePosition
                            local size: Vector2 = button.AbsoluteSize
                            local p: Vector3 = input.Position
                            if p.X >= at.X and p.Y >= at.Y
                                and p.X <= at.X + size.X
                                and p.Y <= at.Y + size.Y then
                                jumpTouch = input
                                pressHeld = true
                                executeAirJump()
                            end
                        end
                    end
                end))
            end

            if UserInputService and UserInputService.InputEnded then
                infiniteJump:Clean(UserInputService.InputEnded:Connect(function(event: any): ()
                    if (event.KeyCode == Enum.KeyCode.Space or event.KeyCode == Enum.KeyCode.ButtonA)
                        and (heldKey == nil or heldKey == event.KeyCode) then
                        pressHeld = false
                        heldKey = nil
                        jumpTouch = nil
                    elseif event.UserInputType == Enum.UserInputType.Touch
                        and not heldKey and (not jumpTouch or event == jumpTouch) then
                        pressHeld = false
                        jumpTouch = nil
                    end
                end))
            end

            if UserInputService and UserInputService.WindowFocusReleased then
                infiniteJump:Clean(UserInputService.WindowFocusReleased:Connect(function(): ()
                    pressHeld = false
                    jumpTouch = nil
                    heldKey = nil
                end))
            end
            if UserInputService and UserInputService.TextBoxFocused then
                infiniteJump:Clean(UserInputService.TextBoxFocused:Connect(function(): ()
                    pressHeld = false
                    jumpTouch = nil
                    heldKey = nil
                end))
            end

            if RunService and RunService.PreSimulation then
                infiniteJump:Clean(RunService.PreSimulation:Connect(function(): ()
                    local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                    if not humanoid or not root or humanoid.Health <= 0 then
                        return
                    end
                    local power: number = infiniteJump.Options["Jump Power"]
                        and infiniteJump.Options["Jump Power"].Value
                        or 50
                    local typing: boolean = type(UserInputService.GetFocusedTextBox) == "function"
                        and UserInputService:GetFocusedTextBox() ~= nil
                    if typing then
                        pressHeld = false
                        jumpTouch = nil
                        heldKey = nil
                        return
                    end
                    if mode() == "Rise" and pressHeld and not root.Anchored and canBoostJump(humanoid) then
                        -- A held jump is an ongoing vertical velocity, not a
                        -- second auto-jump loop. Preserve horizontal motion.
                        local vel: Vector3 = root.AssemblyLinearVelocity
                        root.AssemblyLinearVelocity = Vector3.new(vel.X, power, vel.Z)
                        if power < 0 and humanoid:GetState() == Enum.HumanoidStateType.Jumping then
                            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                        end
                    elseif mode() == "Normal" and power < 0
                        and humanoid:GetState() == Enum.HumanoidStateType.Jumping then
                        local vel: Vector3 = root.AssemblyLinearVelocity
                        root.AssemblyLinearVelocity = Vector3.new(vel.X, power, vel.Z)
                        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                    end
                end))
            end
        end,
    })

    infiniteJump:CreateDropdown({
        Name = "Mode",
        List = {"Normal", "Rise"},
        Index = 1,
        Function = function(value: string): ()
            if infiniteJump.Enabled then infiniteJump:SetStatus(value) end
        end,
    })

    infiniteJump:CreateSlider({
        Name = "Jump Power",
        Min = 1,
        Max = 250,
        Default = 50,
        Tooltip = "Vertical jump velocity applied in mid-air (1-250 slider preset; supports negative values to invert jump physics).",
    })

    activeCleanup = function(): ()
        if infiniteJump.Enabled then
            infiniteJump:Toggle(false)
        end
    end

    Module.Initialized = true
    return infiniteJump
end

function Module.destroy(): ()
    if activeCleanup then
        activeCleanup()
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
