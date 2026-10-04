export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Fly",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local movementInput: any = context.services.movementInput
    local platformStand: any = context.services.platformStandOwnership
    local mobileActions: any = context.services.mobileActions
    local getCharacterParts: any = host.getCharacterParts
    local UserInputService: any = host.UserInputService
    local currentWorkspace: Workspace = host.workspace or workspace

    type FlySettings = {
        method: string,
        floatMethod: string,
        speed: number,
        verticalSpeed: number,
        response: number,
        burstInterval: number,
        wallCheck: boolean,
        platformStand: boolean,
        faceCamera: boolean,
        upKey: Enum.KeyCode,
        downKey: Enum.KeyCode,
    }

    local flySettings: FlySettings = {
        method = "Velocity",
        floatMethod = "Velocity",
        speed = 70,
        verticalSpeed = 56,
        response = 1,
        burstInterval = 0.2,
        wallCheck = true,
        platformStand = true,
        faceCamera = true,
        upKey = Enum.KeyCode.Space,
        downKey = Enum.KeyCode.LeftControl,
    }

    local flyRuntime: any = {
        yLevel = nil :: number?,
        burstAt = 0,
        platform = nil :: BasePart?,
        walkSpeed = nil :: number?,
    }
    local flySmoothedVelocity: Vector3 = Vector3.zero

    local flyObjects: {[Instance]: boolean} =
        setmetatable({}, {__mode = "k"}) :: any
    local flyTouchVertical: number = 0

    local function removeFlyObjects(): ()
        platformStand.set("Fly", nil)

        for object: Instance in pairs(flyObjects) do
            if object.Parent then
                object:Destroy()
            end
        end
        flyObjects = setmetatable({}, {__mode = "k"}) :: any
    end

    local function restoreWalkSpeed(): ()
        local _, humanoid: Humanoid? = getCharacterParts()
        if humanoid and flyRuntime.walkSpeed then
            (humanoid :: Humanoid).WalkSpeed = flyRuntime.walkSpeed :: number
        end
        flyRuntime.walkSpeed = nil
    end

    local function ensureFlyConstraints(root: BasePart): (LinearVelocity, AlignOrientation)
        local attachment: Attachment? = root:FindFirstChild("Wurst_FlyAttachment") :: Attachment?
        if not attachment then
            local newAttachment: Attachment = Instance.new("Attachment")
            newAttachment.Name = "Wurst_FlyAttachment"
            newAttachment.Parent = root
            attachment = newAttachment
        end
        local resolvedAttachment: Attachment = attachment :: Attachment
        flyObjects[resolvedAttachment] = true

        local velocity: LinearVelocity? = root:FindFirstChild("Wurst_FlyVelocity") :: LinearVelocity?
        if not velocity then
            local newVelocity: LinearVelocity = Instance.new("LinearVelocity")
            newVelocity.Name = "Wurst_FlyVelocity"
            newVelocity.Attachment0 = resolvedAttachment
            newVelocity.MaxForce = math.huge
            newVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
            newVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
            newVelocity.Parent = root
            velocity = newVelocity
        end
        flyObjects[velocity :: LinearVelocity] = true

        local orientation: AlignOrientation? =
            root:FindFirstChild("Wurst_FlyOrientation") :: AlignOrientation?
        if not orientation then
            local newOrientation: AlignOrientation = Instance.new("AlignOrientation")
            newOrientation.Name = "Wurst_FlyOrientation"
            newOrientation.Attachment0 = resolvedAttachment
            newOrientation.MaxTorque = math.huge
            newOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
            newOrientation.Responsiveness = 28
            newOrientation.RigidityEnabled = false
            newOrientation.Parent = root
            orientation = newOrientation
        end
        flyObjects[orientation :: AlignOrientation] = true

        return velocity :: LinearVelocity, orientation :: AlignOrientation
    end

    local function getFlyDirection(camera: Camera): (Vector3, number, Vector3)
        local cameraForward: Vector3 = Vector3.new(
            camera.CFrame.LookVector.X,
            0,
            camera.CFrame.LookVector.Z
        )
        local cameraRight: Vector3 = Vector3.new(
            camera.CFrame.RightVector.X,
            0,
            camera.CFrame.RightVector.Z
        )
        cameraForward = cameraForward.Magnitude > 0.001
            and cameraForward.Unit
            or Vector3.new(0, 0, -1)
        cameraRight = cameraRight.Magnitude > 0.001
            and cameraRight.Unit
            or Vector3.new(1, 0, 0)

        local forwardScalar: number, rightScalar: number = movementInput.getVector()
        local horizontal: Vector3 = cameraForward * forwardScalar
            + cameraRight * rightScalar
        if horizontal.Magnitude > 1 then
            horizontal = horizontal.Unit
        end

        local vertical: number = 0
        if flyTouchVertical > 0
            or (UserInputService.KeyboardEnabled
                and UserInputService:IsKeyDown(flySettings.upKey)) then
            vertical = vertical + 1
        end
        if flyTouchVertical < 0
            or (UserInputService.KeyboardEnabled
                and UserInputService:IsKeyDown(flySettings.downKey)) then
            vertical = vertical - 1
        end

        if vertical == 0 and not UserInputService.KeyboardEnabled and movementInput.isJumpHeld() then
            vertical = 1
        end

        return horizontal, vertical, cameraForward
    end

    local applyFlyHorizontal: (BasePart, Humanoid, Vector3, number) -> ()
    local applyFlyVertical: (BasePart, Humanoid, number, number) -> ()
    do
    applyFlyHorizontal = function(
        root: BasePart,
        humanoid: Humanoid,
        moveDirection: Vector3,
        deltaTime: number
    ): ()
        local method: string = flySettings.method
        local currentVelocity: Vector3 = root.AssemblyLinearVelocity
        local target: Vector3 = moveDirection * flySettings.speed

        if method == "WalkSpeed" then
            if not flyRuntime.walkSpeed then
                flyRuntime.walkSpeed = humanoid.WalkSpeed
            end
            humanoid.WalkSpeed = flySettings.speed
            return
        end

        if method == "Pulse" then

            local period: number = math.max(flySettings.burstInterval, 0.05) * 2
            local burst: boolean = (os.clock() % period) < (period * 0.5)
            target = target * (burst and 1.8 or 0.2)
        end

        if method == "CFrame" or method == "Blink" then
            local step: Vector3 = moveDirection * flySettings.speed * deltaTime
            if method == "Blink" then
                local interval: number = math.max(flySettings.burstInterval, 0.05)
                if os.clock() < flyRuntime.burstAt then
                    step = Vector3.zero
                else
                    flyRuntime.burstAt = os.clock() + interval
                    step = moveDirection * flySettings.speed * interval
                end
            end
            if step.Magnitude > 0.001 and flySettings.wallCheck then
                local raycastParams: RaycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
                local wallHit: RaycastResult? = currentWorkspace:Raycast(
                    root.Position,
                    step + step.Unit * 2,
                    raycastParams
                )
                if wallHit then
                    step = Vector3.zero
                end
            end
            if step.Magnitude > 0.001 then
                root.CFrame = root.CFrame + step
            end

            root.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
            return
        end

        if method == "Impulse" then
            local difference: Vector3 = (target - currentVelocity)
                * Vector3.new(1, 0, 1)

            local threshold: number = moveDirection.Magnitude < 0.01 and 10 or 2
            if difference.Magnitude > threshold then
                root:ApplyImpulse(difference * root.AssemblyMass)
            end
            return
        end

        local alpha: number = 1 - math.exp(-12 * flySettings.response * deltaTime)
        flySmoothedVelocity = flySmoothedVelocity:Lerp(target, alpha)
        if method == "Constraint" then
            return
        end
        root.AssemblyLinearVelocity = Vector3.new(
            flySmoothedVelocity.X,
            currentVelocity.Y,
            flySmoothedVelocity.Z
        )
    end

    applyFlyVertical = function(
        root: BasePart,
        humanoid: Humanoid,
        vertical: number,
        deltaTime: number
    ): ()
        local method: string = flySettings.floatMethod
        local currentVelocity: Vector3 = root.AssemblyLinearVelocity
        local targetY: number = vertical * flySettings.verticalSpeed

        if method == "Floor" then
            local platform: BasePart? = flyRuntime.platform
            if not platform or not platform.Parent then
                local newPlatform: BasePart = Instance.new("Part")
                newPlatform.Name = "Wurst_FlyPlatform"
                newPlatform.Anchored = true
                newPlatform.CanQuery = false
                newPlatform.CanTouch = false
                newPlatform.Size = Vector3.new(8, 1, 8)
                newPlatform.Transparency = 1

                newPlatform.Parent = currentWorkspace.CurrentCamera
                flyRuntime.platform = newPlatform
                platform = newPlatform
            end
            local resolved: BasePart = platform :: BasePart

            resolved.CFrame = vertical < 0
                and CFrame.new(0, -4096, 0)
                or CFrame.new(root.Position - Vector3.new(0, humanoid.HipHeight + 1.5, 0))
            if vertical > 0 then
                root.AssemblyLinearVelocity = Vector3.new(
                    currentVelocity.X,
                    targetY,
                    currentVelocity.Z
                )
            end
            return
        end

        if method == "Bypass" then

            local period: number = math.max(flySettings.burstInterval, 0.05) * 5
            if (os.clock() % period) > (period * 0.8) then

                flyRuntime.yLevel = nil
                return
            end
            local held: number = flyRuntime.yLevel or root.Position.Y
            held = held + targetY * deltaTime
            flyRuntime.yLevel = held
            root.AssemblyLinearVelocity = Vector3.new(
                currentVelocity.X,
                0,
                currentVelocity.Z
            )
            root.CFrame = root.CFrame + Vector3.new(0, held - root.Position.Y, 0)
            return
        end

        if method == "Hover" or method == "Jump" then
            local level: number = flyRuntime.yLevel or root.Position.Y
            level = level + targetY * deltaTime
            if flySettings.wallCheck then
                local offset: number = level - root.Position.Y
                if math.abs(offset) > 0.001 then
                    local raycastParams: RaycastParams = RaycastParams.new()
                    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                    raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
                    local ceilingHit: RaycastResult? = currentWorkspace:Raycast(
                        root.Position,
                        Vector3.new(0, offset, 0),
                        raycastParams
                    )
                    if ceilingHit then
                        level = ceilingHit.Position.Y
                            - math.sign(offset) * (humanoid.HipHeight + 0.5)
                    end
                end
            end
            flyRuntime.yLevel = level
            if method == "Hover" then
                root.AssemblyLinearVelocity = Vector3.new(
                    currentVelocity.X,
                    0,
                    currentVelocity.Z
                )
                root.CFrame = root.CFrame + Vector3.new(0, level - root.Position.Y, 0)
            elseif root.Position.Y < level - 0.5 then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
            return
        end

        if method == "Bounce" then
            local period: number = math.max(flySettings.burstInterval, 0.05) * 4
            local rising: boolean = (os.clock() % period) < (period * 0.5)
            targetY = targetY
                + (rising and 1 or -1) * flySettings.verticalSpeed * 0.45
        end

        if method == "Impulse" then
            local difference: number = targetY - currentVelocity.Y
            if math.abs(difference) > 2 then
                root:ApplyImpulse(Vector3.new(0, difference, 0) * root.AssemblyMass)
            end
            return
        end

        root.AssemblyLinearVelocity = Vector3.new(
            currentVelocity.X,
            targetY,
            currentVelocity.Z
        )
    end
    end

    local fly: any
    fly = framework.Categories.Movement:CreateModule({
        Name = "Flight",
        Category = "Movement",
        ConfigKey = "Universal.Fly",
        Tooltip = "Use WASD to move, Space to rise and LeftControl to descend. "
            .. "Method picks how you travel sideways and Float picks what "
            .. "holds you up; if a game blocks one combination, another "
            .. "usually works.",
        Function = function(enabled: boolean): ()

            removeFlyObjects()
            flySmoothedVelocity = Vector3.zero
            flyTouchVertical = 0
            flyRuntime.yLevel = nil
            flyRuntime.burstAt = 0
            if flyRuntime.platform then
                (flyRuntime.platform :: BasePart):Destroy()
                flyRuntime.platform = nil
            end
            restoreWalkSpeed()

            if not enabled then
                fly:SetStatus(nil)
                local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
                if root then
                    (root :: BasePart).AssemblyLinearVelocity = Vector3.zero
                end
                if humanoid then
                    platformStand.set("Fly", false)
                    platformStand.apply(humanoid :: Humanoid)
                end
                return
            end

            fly:SetStatus(flySettings.method)
            fly:Loop(function(deltaTime: number): ()
                local _, humanoid, root = getCharacterParts()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not humanoid or not root or not camera then

                    flyRuntime.yLevel = nil
                    return
                end

                local method: string = flySettings.method
                local floatMethod: string = flySettings.floatMethod

                local canRagdoll: boolean = method ~= "WalkSpeed"
                    and floatMethod ~= "Floor"
                    and floatMethod ~= "Jump"
                platformStand.set(
                    "Fly",
                    canRagdoll and (flySettings.platformStand or method == "CFrame")
                )
                platformStand.apply(humanoid)

                local moveDirection, vertical, cameraForward = getFlyDirection(camera)
                if flySettings.wallCheck and moveDirection.Magnitude > 0.001 then
                    local raycastParams: RaycastParams = RaycastParams.new()
                    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                    raycastParams.FilterDescendantsInstances = {root.Parent :: Instance}
                    local wallHit: RaycastResult? = currentWorkspace:Raycast(
                        root.Position,
                        moveDirection.Unit * 2.75,
                        raycastParams
                    )
                    if wallHit then
                        moveDirection = Vector3.zero
                    end
                end

                if method == "Constraint" then
                    local velocity, orientation = ensureFlyConstraints(root)
                    applyFlyHorizontal(root, humanoid, moveDirection, deltaTime)
                    velocity.Enabled = true
                    velocity.VectorVelocity = Vector3.new(
                        flySmoothedVelocity.X,
                        vertical * flySettings.verticalSpeed,
                        flySmoothedVelocity.Z
                    )
                    orientation.Enabled = flySettings.faceCamera
                    orientation.CFrame = CFrame.lookAt(Vector3.zero, cameraForward)
                    return
                end

                removeFlyObjects()
                applyFlyHorizontal(root, humanoid, moveDirection, deltaTime)
                applyFlyVertical(root, humanoid, vertical, deltaTime)

                if floatMethod ~= "Floor" and flyRuntime.platform then
                    (flyRuntime.platform :: BasePart):Destroy()
                    flyRuntime.platform = nil
                end
                if floatMethod ~= "Hover" and floatMethod ~= "Jump" then
                    flyRuntime.yLevel = nil
                end

                if flySettings.faceCamera and cameraForward.Magnitude > 0.001 then
                    root.CFrame = CFrame.lookAt(root.Position, root.Position + cameraForward)
                end
            end)
        end,
    })

    fly:CreateDropdown({
        Name = "Method",
        List = {"Velocity", "Constraint", "Impulse", "CFrame", "Blink", "Pulse", "WalkSpeed"},
        Index = 1,
        Function = function(value: string): ()
            flySettings.method = value
            if fly.Enabled then
                fly:SetStatus(value)
            end
        end,
        Tooltip = "Sideways engine. Velocity is smooth, CFrame ignores physics, "
            .. "WalkSpeed just runs faster.",
    })
    fly:CreateDropdown({
        Name = "Float",
        List = {"Velocity", "Impulse", "Hover", "Jump", "Bounce", "Floor", "Bypass"},
        Index = 1,
        Function = function(value: string): ()
            flySettings.floatMethod = value
        end,
        Tooltip = "What keeps you airborne. Hover locks an altitude, Floor "
            .. "stands you on an invisible part, and Bypass drops you to the "
            .. "ground for an instant every few seconds so the server sees "
            .. "you land.",
    })
    fly:CreateSlider({
        Name = "Horizontal speed",
        Min = 10,
        Max = 500,
        Default = flySettings.speed,
        Function = function(value: number): ()
            flySettings.speed = value
        end,
        Tooltip = "Studs per second while holding WASD.",
    })
    fly:CreateSlider({
        Name = "Vertical speed",
        Min = 10,
        Max = 350,
        Default = flySettings.verticalSpeed,
        Function = function(value: number): ()
            flySettings.verticalSpeed = value
        end,
        Tooltip = "Studs per second while rising or descending.",
    })
    fly:CreateSlider({
        Name = "Response multiplier",
        Show = {Option = "Method", Values = {"Velocity", "Constraint", "Pulse"}},
        Min = 0.5,
        Max = 2,
        Default = flySettings.response,
        Function = function(value: number): ()
            flySettings.response = value
        end,
        Tooltip = "How sharply the flight reacts to input. Higher is twitchier.",
    })
    fly:CreateSlider({
        Name = "Burst interval (s)",
        Min = 0.05,
        Max = 1,
        Default = flySettings.burstInterval,
        Function = function(value: number): ()
            flySettings.burstInterval = value
        end,
        Tooltip = "Cycle length for Blink, Pulse, Bounce and Bypass. Shorter "
            .. "is smoother.",
    })
    fly:CreateToggle({
        Name = "Wall check",
        Default = flySettings.wallCheck,
        Function = function(value: boolean): ()
            flySettings.wallCheck = value
        end,
        Tooltip = "Stop against solid geometry instead of flying through it.",
    })
    fly:CreateToggle({
        Name = "PlatformStand",
        Default = flySettings.platformStand,
        Function = function(value: boolean): ()
            flySettings.platformStand = value
        end,
        Tooltip = "Ragdoll the character while flying. Smoother, but no animations.",
    })
    fly:CreateToggle({
        Name = "Face camera",
        Default = flySettings.faceCamera,
        Function = function(value: boolean): ()
            flySettings.faceCamera = value
        end,
        Tooltip = "Rotate the character to follow wherever the camera looks.",
    })
    local upKey: any = fly:CreateBind({
        Name = "Up key",
        Default = flySettings.upKey,
        Function = function(value: Enum.KeyCode): ()
            flySettings.upKey = value
        end,
        Tooltip = "Hold to gain altitude.",
    })
    local downKey: any = fly:CreateBind({
        Name = "Down key",
        Default = flySettings.downKey,
        Function = function(value: Enum.KeyCode): ()
            flySettings.downKey = value
        end,
        Tooltip = "Hold to lose altitude.",
    })

    if mobileActions.bindPlacement then
        mobileActions.bindPlacement(
            upKey.Object,
            "UniversalFlyUp",
            "UP",
            function(): () end,
            {
                onPress = function(): ()
                    flyTouchVertical = 1
                end,
                onRelease = function(): ()
                    if flyTouchVertical == 1 then
                        flyTouchVertical = 0
                    end
                end,
            }
        )
        mobileActions.bindPlacement(
            downKey.Object,
            "UniversalFlyDown",
            "DOWN",
            function(): () end,
            {
                onPress = function(): ()
                    flyTouchVertical = -1
                end,
                onRelease = function(): ()
                    if flyTouchVertical == -1 then
                        flyTouchVertical = 0
                    end
                end,
            }
        )
    end

    activeCleanup = function(): ()
        removeFlyObjects()
        restoreWalkSpeed()
    end
    Module.Initialized = true
    return fly
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
