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

    local fallHumanoid: Humanoid? = nil
    local fallConnection: RBXScriptConnection? = nil
    local fallTrack: AnimationTrack? = nil
    local fallLoadAttempted: boolean = false
    local fallJumpPower: number = 50
    local jumpAnimationIds: {[string]: boolean} = {}

    local function stopFallTrack(): ()
        if fallTrack then fallTrack:Stop(0) end
    end

    local function clearFallController(): ()
        if fallConnection then fallConnection:Disconnect(); fallConnection = nil end
        if fallTrack then
            fallTrack:Stop(0)
            fallTrack:Destroy()
            fallTrack = nil
        end
        fallHumanoid = nil
        fallLoadAttempted = false
        table.clear(jumpAnimationIds)
    end

    local function playNativeFall(humanoid: Humanoid): ()
        local animator: Animator? = humanoid:FindFirstChildOfClass("Animator") :: Animator?
        if not animator then return end
        -- Stop only the rig's jump clips, not arbitrary emotes/other modules.
        -- Freefall alone leaves Animate's jumpAnimTime running for ~0.3s.
        if not fallLoadAttempted then
            local character: Model? = LocalPlayer.Character
            local animate: Instance? = character and character:FindFirstChild("Animate")
            local folder: Instance? = animate and animate:FindFirstChild("fall")
            local animation: Animation? = folder and folder:FindFirstChildOfClass("Animation") :: Animation?
            if animation then
                fallLoadAttempted = true
                local jumpFolder: Instance? = animate and animate:FindFirstChild("jump")
                if jumpFolder then
                    for _, child: Instance in ipairs(jumpFolder:GetChildren()) do
                        if child:IsA("Animation") then jumpAnimationIds[(child :: Animation).AnimationId] = true end
                    end
                end
                local ok: boolean, loaded: any = pcall(function(): AnimationTrack
                    return animator:LoadAnimation(animation)
                end)
                if ok and loaded then
                    fallTrack = loaded
                    loaded.Priority = Enum.AnimationPriority.Movement
                    loaded.Looped = true
                end
            end
        end
        for _, track: AnimationTrack in ipairs(animator:GetPlayingAnimationTracks()) do
            local animation: Animation? = track.Animation
            if animation and jumpAnimationIds[animation.AnimationId] then track:Stop(0) end
        end
        if fallTrack and not fallTrack.IsPlaying then fallTrack:Play(0, 1, 1) end
    end

    local function syncFallController(humanoid: Humanoid?, enabled: boolean): ()
        if not enabled or not humanoid then
            if fallHumanoid then clearFallController() end
            return
        end
        if fallHumanoid == humanoid then return end
        clearFallController()
        fallHumanoid = humanoid
        local character: Model? = LocalPlayer.Character
        local animate: Instance? = character and character:FindFirstChild("Animate")
        local jumpFolder: Instance? = animate and animate:FindFirstChild("jump")
        if jumpFolder then
            for _, child: Instance in ipairs(jumpFolder:GetChildren()) do
                if child:IsA("Animation") then jumpAnimationIds[(child :: Animation).AnimationId] = true end
            end
        end
        fallConnection = humanoid.StateChanged:Connect(function(_, nextState: Enum.HumanoidStateType): ()
            if nextState == Enum.HumanoidStateType.Jumping then
                -- Switching state before physics applies the ground jump
                -- must not cancel its takeoff (including native mobile jumps).
                local _, _, root: BasePart? = characterParts()
                if root then
                    local velocity: Vector3 = root.AssemblyLinearVelocity
                    if velocity.Y <= 0 then
                        root.AssemblyLinearVelocity = Vector3.new(velocity.X, fallJumpPower, velocity.Z)
                    end
                end
                humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                playNativeFall(humanoid)
            elseif nextState == Enum.HumanoidStateType.Freefall then
                playNativeFall(humanoid)
            else
                stopFallTrack()
            end
        end)
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

    local function performInfiniteJump(mode: string, strength: number, interval: number): ()
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
        -- Fall is a jump with the falling state/animation, not a brake
        -- that only works after Y turns negative. X/Z momentum is unchanged.
        fallJumpPower = strength
        syncFallController(humanoid, mode == "Fall")
        humanoid:ChangeState(mode == "Fall" and Enum.HumanoidStateType.Freefall or Enum.HumanoidStateType.Jumping)
        ;(root :: BasePart).AssemblyLinearVelocity = Vector3.new(velocity.X, strength, velocity.Z)
        if mode == "Fall" then playNativeFall(humanoid) end
    end

    local jump: any
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
            if not enabled then
                jump:SetStatus(nil)
                return
            end

            jump:SetStatus("active")
            jump:Clean(function(): () restoreJumpPower(); clearFallController() end)

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
                    performInfiniteJump(mode, strength, interval)
                end))
            end

            jump:Loop(function(): ()
                local opts = jump.Options
                local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not humanoid or not root or humanoid.Health <= 0 then
                    clearFallController()
                    return
                end

                local fallMode: boolean = opts["Infinite jump"] and opts["Infinite jump"].Value
                    and opts["Infinite jump mode"].Value == "Fall"
                fallJumpPower = opts["Infinite jump power"].Value
                syncFallController(humanoid, fallMode)
                if fallMode then
                    local currentState: Enum.HumanoidStateType = humanoid:GetState()
                    if currentState == Enum.HumanoidStateType.Jumping then
                        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                        playNativeFall(humanoid)
                    elseif currentState == Enum.HumanoidStateType.Freefall then
                        playNativeFall(humanoid)
                    else
                        stopFallTrack()
                    end
                end

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

                if opts["Auto jump"] and opts["Auto jump"].Value then
                    local moveDir: Vector3 = humanoid.MoveDirection
                    if moveDir.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air then
                        if fallMode then
                            performInfiniteJump("Fall", fallJumpPower, opts["Jump interval"].Value)
                        else
                            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                        end
                    end
                end

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

    jump:CreateToggle({
        Name = "Custom jump power",
        Default = false,
        Tooltip = "Enables custom jump height/power for ground jumps. Turn off if you only want Infinite Jump or High Jump.",
    })

    jump:CreateSlider({
        Name = "Jump power",
        Show = {Option = "Custom jump power", Values = {true}},
        Min = 0,
        Max = 500,
        Default = 80,
        Function = function(value: number): ()
            if jump.Enabled and jump.Options["Custom jump power"].Value then
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
        Tooltip = "Vertical velocity applied when High Jump button is pressed.",
    })

    jump:CreateToggle({
        Name = "Infinite jump",
        Default = false,
        Tooltip = "Allows jumping repeatedly in mid-air.",
    })

    jump:CreateDropdown({
        Name = "Infinite jump mode",
        Show = {Option = "Infinite jump", Values = {true}},
        List = {"Normal", "Rise", "Fall"},
        Index = 1,
        Tooltip = "Normal = mid-air jump; Rise = hold to rise; Fall = jump using Freefall and your rig's falling animation, including while ascending.",
    })

    jump:CreateSlider({
        Name = "Infinite jump power",
        Show = {
            {Option = "Infinite jump", Values = {true}},
            {Option = "Infinite jump mode", Values = {"Normal", "Fall"}},
        },
        Min = 10,
        Max = 250,
        Default = 50,
        Tooltip = "Vertical impulse applied during mid-air jumps.",
    })

    jump:CreateSlider({
        Name = "Rise speed",
        Show = {
            {Option = "Infinite jump", Values = {true}},
            {Option = "Infinite jump mode", Values = {"Rise"}},
        },
        Min = 10,
        Max = 350,
        Default = 75,
        Tooltip = "Vertical speed while holding jump in Rise mode.",
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
