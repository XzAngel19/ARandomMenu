export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Jump Settings",
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

    local function performHighJump(velocityOverride: number?): ()
        local _, humanoid: Humanoid?, root: BasePart? = characterParts()
        if not humanoid or not root or root.Anchored or not canControlJump(humanoid) then
            return
        end
        local velocityVal: number = velocityOverride or 72
        local current: Vector3 = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(
            current.X,
            velocityVal,
            current.Z
        )
        if humanoid.FloorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        end
    end

    local longJumpSpeed = 50
    local longJumpMode = "Velocity"

    local function performLongJump(): ()
        local _, humanoid: Humanoid?, root: BasePart? = characterParts()
        if not humanoid or not root or root.Anchored or not canControlJump(humanoid) then
            return
        end
        -- Read live values from options (robust if test sets Value directly)
        local optsMode: any = jump and jump.Options and jump.Options["Long jump mode"]
        local optsSpeed: any = jump and jump.Options and jump.Options["Long jump speed"]
        local mode: string = optsMode and optsMode.Value or longJumpMode
        local speed: number = optsSpeed and optsSpeed.Value or longJumpSpeed
        local moveDir: Vector3 = humanoid.MoveDirection
        local flat: Vector3 = Vector3.new(moveDir.X, 0, moveDir.Z)
        if flat.Magnitude < 0.05 then
            local cam: any = host.workspace and host.workspace.CurrentCamera
            if cam and cam.CFrame then
                local lv: Vector3 = cam.CFrame.LookVector
                flat = Vector3.new(lv.X, 0, lv.Z)
            else
                flat = Vector3.new(0, 0, -1)
            end
        end
        if flat.Magnitude < 0.001 then return end
        flat = flat.Magnitude > 1 and flat.Unit or flat
        local cur: Vector3 = root.AssemblyLinearVelocity
        if mode == "Velocity" then
            root.AssemblyLinearVelocity = Vector3.new(flat.X * speed, cur.Y, flat.Z * speed)
        elseif mode == "Impulse" then
            local diff: Vector3 = Vector3.new(flat.X * speed - cur.X, 0, flat.Z * speed - cur.Z)
            if diff.Magnitude > 0.001 then
                root:ApplyImpulse(diff * root.AssemblyMass)
            end
        else -- CFrame: instant teleport forward
            local step: Vector3 = flat * speed * 0.25
            local pos: Vector3 = root.CFrame.Position
            root.CFrame = CFrame.new(Vector3.new(pos.X + step.X, pos.Y + step.Y, pos.Z + step.Z))
        end
        if humanoid.FloorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    local jump: any
    jump = framework.Categories.Exploits:CreateModule({
        Name = "Jump Settings",
        Category = "Exploits",
        ConfigKey = "Universal.Jump",
        Order = 6,
        Tooltip = "Jump controls: adjust Jump Power, High Jump button, Long Jump button and Auto Jump. Infinite Jump moved to its own module.",
        Function = function(enabled: boolean): ()
            restoreJumpPower()
            if not enabled then
                jump:SetStatus(nil)
                return
            end
            jump:SetStatus("active")
            jump:Clean(function(): () restoreJumpPower() end)
            -- No infinite jump handling here; handled by Infinite Jump module
            jump:Clean(host.RunService.PreSimulation:Connect(function(): ()
                local opts = jump.Options
                local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not humanoid or not root or humanoid.Health <= 0 then
                    return
                end
                local canMove = canControlJump(humanoid) and not root.Anchored
                if not canMove then return end

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
                    if wantedPower < 0 and humanoid:GetState() == Enum.HumanoidStateType.Jumping then
                        local curVel: Vector3 = root.AssemblyLinearVelocity
                        root.AssemblyLinearVelocity = Vector3.new(curVel.X, wantedPower, curVel.Z)
                    end
                else
                    -- Restore if not using custom
                    if originalJumpPower[humanoid] then
                        humanoid.JumpPower = originalJumpPower[humanoid].jumpPower
                        humanoid.UseJumpPower = originalJumpPower[humanoid].useJumpPower
                        originalJumpPower[humanoid] = nil
                    end
                end

                if canMove and opts["Auto jump"] and opts["Auto jump"].Value then
                    local moveDir: Vector3 = humanoid.MoveDirection
                    if moveDir.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air then
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end
            end))
        end,
    })

    jump:CreateToggle({
        Name = "Custom jump power",
        Default = false,
        Tooltip = "Enables custom jump height/power for ground jumps.",
    })

    jump:CreateSlider({
        Name = "Jump power",
        Show = {Option = "Custom jump power", Values = {true}},
        Min = 1,
        Max = 250,
        Default = 80,
        Function = function(value: number): ()
            if jump.Enabled and jump.Options["Custom jump power"].Value then
                jump:SetStatus(tostring(math.round(value)))
            end
        end,
        Tooltip = "Character jump power (default 50). Negative launches downward.",
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
        Min = 1,
        Max = 250,
        Default = 72,
        Tooltip = "Vertical velocity for High Jump button. Negative = downward.",
    })

    jump:CreateToggle({
        Name = "Auto jump",
        Default = false,
        Tooltip = "Continuously jumps while walking on the ground.",
    })

    jump:CreateButton({
        Name = "Long jump",
        Function = function(): ()
            performLongJump()
        end,
        Tooltip = "Horizontal boost in your move/camera direction (button like High Jump). Uses Long jump mode/speed below.",
    })

    jump:CreateDropdown({
        Name = "Long jump mode",
        List = {"Velocity", "Impulse", "CFrame"},
        Index = 1,
        Function = function(value: string): ()
            longJumpMode = value
        end,
        Tooltip = "How Long Jump is applied: Velocity (smooth), Impulse (physics), CFrame (teleport).",
    })

    jump:CreateSlider({
        Name = "Long jump speed",
        Min = 1,
        Max = 250,
        Default = 50,
        Function = function(value: number): ()
            longJumpSpeed = value
        end,
        Tooltip = "Horizontal speed for Long Jump button in studs/s. Negative = backwards.",
    })

    activeCleanup = function(): ()
        if jump.Enabled then jump:Toggle(false) end
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
