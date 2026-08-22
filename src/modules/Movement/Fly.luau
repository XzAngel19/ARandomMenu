--!strict
--
-- Fly.
--
-- Seven ways of moving and seven of staying up, because no single pair works
-- everywhere: a game that clamps velocity ignores Velocity, one that rejects
-- CFrame writes ignores CFrame, and one watching the humanoid state ignores
-- both but lets an anchored part under your feet through. Each row in the
-- panel says what its option is for.
--
-- The two engine appliers keep the scope they were written in. In the shell
-- that was a register trick; here it is just where they belong.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
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
    local state: any = host.state
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
    -- One session's scratch: the altitude a Hover lock is holding, when the
    -- next Blink burst is due, the Floor platform, and the WalkSpeed to put
    -- back. Cleared at both edges of a session so a fresh character can never
    -- inherit the previous one's numbers.
    local flyRuntime: any = {
        yLevel = nil :: number?,
        burstAt = 0,
        platform = nil :: BasePart?,
        walkSpeed = nil :: number?,
    }
    local flySmoothedVelocity: Vector3 = Vector3.zero
    -- PlatformStand is contested: Fly wants the character ragdolled while
    -- VehicleSpeed may want it standing, and both can be on at once. The
    -- controller arbitrates — the last owner to speak wins, and every baseline
    -- goes back when the last owner leaves. It lives on `state` because the
    -- two modules share it; it is not Fly's alone.
    state.platformStandController = {
        owners = {},
        baselines = setmetatable({}, {__mode = "k"}),
        sequence = 0,
    }
    state.platformStandController.set = function(ownerId: string, value: boolean?): ()
        local controller: any = state.platformStandController
        if value == nil then
            controller.owners[ownerId] = nil
            if next(controller.owners) == nil then
                for humanoid: Humanoid, baseline: boolean in pairs(controller.baselines) do
                    if humanoid.Parent then
                        humanoid.PlatformStand = baseline
                    end
                end
                controller.baselines = setmetatable({}, {__mode = "k"})
            end
            return
        end
        local owner: any = controller.owners[ownerId]
        if not owner then
            controller.sequence += 1
            owner = {sequence = controller.sequence, value = value}
            controller.owners[ownerId] = owner
        else
            owner.value = value
        end
    end
    state.platformStandController.apply = function(humanoid: Humanoid): ()
        local controller: any = state.platformStandController
        if controller.baselines[humanoid] == nil then
            controller.baselines[humanoid] = humanoid.PlatformStand
        end
        local selected: any = nil
        for _, owner: any in pairs(controller.owners) do
            if not selected or owner.sequence > selected.sequence then
                selected = owner
            end
        end
        if selected then
            humanoid.PlatformStand = selected.value
        end
    end
    local flyObjects: {[Instance]: boolean} =
        setmetatable({}, {__mode = "k"}) :: any
    local flyTouchVertical: number = 0

    local function removeFlyObjects(): ()
        state.platformStandController.set("Fly", nil)

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
        local attachment: Attachment? = root:FindFirstChild("RTM_FlyAttachment") :: Attachment?
        if not attachment then
            local newAttachment: Attachment = Instance.new("Attachment")
            newAttachment.Name = "RTM_FlyAttachment"
            newAttachment.Parent = root
            attachment = newAttachment
        end
        local resolvedAttachment: Attachment = attachment :: Attachment
        flyObjects[resolvedAttachment] = true

        local velocity: LinearVelocity? = root:FindFirstChild("RTM_FlyVelocity") :: LinearVelocity?
        if not velocity then
            local newVelocity: LinearVelocity = Instance.new("LinearVelocity")
            newVelocity.Name = "RTM_FlyVelocity"
            newVelocity.Attachment0 = resolvedAttachment
            newVelocity.MaxForce = math.huge
            newVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
            newVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
            newVelocity.Parent = root
            velocity = newVelocity
        end
        flyObjects[velocity :: LinearVelocity] = true

        local orientation: AlignOrientation? =
            root:FindFirstChild("RTM_FlyOrientation") :: AlignOrientation?
        if not orientation then
            local newOrientation: AlignOrientation = Instance.new("AlignOrientation")
            newOrientation.Name = "RTM_FlyOrientation"
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

        -- Steering comes from the shared input helper, which reads Roblox's own
        -- control module: keyboard, thumbstick or gamepad, and it keeps answering
        -- while PlatformStand is on — the exact case where `MoveDirection` goes
        -- quiet and flying on a phone left the character frozen in place.
        local forwardScalar: number, rightScalar: number = state.getMoveInput()
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
        -- On touch the jump button doubles as "up" so flying needs no placed
        -- button at all to get off the ground.
        if vertical == 0 and not UserInputService.KeyboardEnabled and state.isJumpHeld() then
            vertical = 1
        end

        return horizontal, vertical, cameraForward
    end

    -- Flight engines.
    --
    -- Flying is two separate problems — what pushes you sideways and what keeps
    -- you off the ground — and games break them in different ways, so they are
    -- two independent engines instead of one preset that only ever changed a
    -- smoothing constant (which is why "Balanced", "Direct" and "Precise" all
    -- used to fly identically).
    --
    -- Horizontal:
    --   Velocity    AssemblyLinearVelocity is overwritten every frame. Smooth and
    --               responsive, and the first thing a velocity clamp notices.
    --   Constraint  a LinearVelocity constraint drives the character instead, so
    --               games that reset AssemblyLinearVelocity each step cannot undo
    --               it. It owns the vertical axis too, so the float engine idles.
    --   Impulse     the same target reached with ApplyImpulse: the body keeps its
    --               own physics, collides properly and pushes what it touches.
    --   CFrame      the root is displaced directly and velocity is left at zero,
    --               so speed caps, knockback and ragdolls have nothing to grab.
    --   Blink       CFrame movement saved up and spent in one hop per interval,
    --               which looks like teleporting to a spectator.
    --   Pulse       bursts of speed with slow coasts between them, so the
    --               average speed stays close to normal while the peaks are fast.
    --   WalkSpeed   raises Humanoid.WalkSpeed and nothing else: keeps animations
    --               and the game's own movement rules, trivially detectable.
    --
    -- Vertical:
    --   Velocity    the Y component is written directly, which also cancels
    --               gravity while you hold nothing.
    --   Impulse     the same target through ApplyImpulse.
    --   Hover       an altitude is held with CFrame writes: no drift, no physics,
    --               and gravity never applies.
    --   Jump        holds an altitude by asking the humanoid to jump whenever it
    --               falls below it, so the movement is the game's own jump.
    --   Bounce      velocity with an oscillation on top, which reads from outside
    --               as an ordinary player hopping around.
    --   Floor       an invisible anchored part is kept under your feet, so you
    --               are genuinely standing on something the entire flight.
    --   Bypass      holds the altitude but dips to the ground for a fraction of
    --               a second every few seconds, so a server that checks whether
    --               you ever land sees that you do.
    --
    -- The two engine appliers live in their own block so their registers are
    -- released back to the bootstrap function; the loop that calls them sits
    -- with the module, so the pair is declared here and assigned below.
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
            -- A burst followed by a coast: the same distance covered as a steady
            -- run at the slider value, but never a constant unnatural speed.
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
            -- Position-based flight has to keep its own momentum at zero, or the
            -- leftover velocity carries the character past wherever it stopped.
            root.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
            return
        end

        if method == "Impulse" then
            local difference: Vector3 = (target - currentVelocity)
                * Vector3.new(1, 0, 1)
            -- An impulse every frame fights the solver; only correct once the
            -- body has actually drifted away from the target.
            local threshold: number = moveDirection.Magnitude < 0.01 and 10 or 2
            if difference.Magnitude > threshold then
                root:ApplyImpulse(difference * root.AssemblyMass)
            end
            return
        end

        -- Velocity and Constraint both track the target through the response
        -- multiplier, which is the only setting that can make flight feel heavy.
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
                newPlatform.Name = "RTM_FlyPlatform"
                newPlatform.Anchored = true
                newPlatform.CanQuery = false
                newPlatform.CanTouch = false
                newPlatform.Size = Vector3.new(8, 1, 8)
                newPlatform.Transparency = 1
                -- Parented to the camera: it exists for the local physics
                -- simulation only and never shows up as a part in the world.
                newPlatform.Parent = currentWorkspace.CurrentCamera
                flyRuntime.platform = newPlatform
                platform = newPlatform
            end
            local resolved: BasePart = platform :: BasePart
            -- Descending means getting the floor out of the way for a moment.
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
            -- Vape's trick, in one branch: hold the altitude, then drop to the
            -- ground for a fraction of a second every few seconds. A server that
            -- checks "has this player touched the floor lately" sees a player who
            -- lands regularly, and the dip is short enough to fly through.
            --
            -- Air and ground times come from the burst interval: four intervals up
            -- and one down, which is long enough for the landing to register.
            local period: number = math.max(flySettings.burstInterval, 0.05) * 5
            if (os.clock() % period) > (period * 0.8) then
                -- Fall honestly for the dip: the humanoid changes state on its
                -- own, and that state is exactly what the check reads.
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
            -- Both edges of a session start from the same clean state, so a
            -- respawn or a disable-then-enable can never inherit the previous
            -- character's altitude, platform or saved WalkSpeed.
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
                    state.platformStandController.set("Fly", false)
                    state.platformStandController.apply(humanoid :: Humanoid)
                end
                return
            end

            fly:SetStatus(flySettings.method)
            fly:Loop(function(deltaTime: number): ()
                local _, humanoid, root = getCharacterParts()
                local camera: Camera? = currentWorkspace.CurrentCamera
                if not humanoid or not root or not camera then
                    -- A respawn invalidates the held altitude; picking it back up
                    -- would teleport the fresh character to the old one's height.
                    flyRuntime.yLevel = nil
                    return
                end

                local method: string = flySettings.method
                local floatMethod: string = flySettings.floatMethod
                -- WalkSpeed steering and the two engines that stand on something need
                -- a humanoid that is still allowed to walk, so PlatformStand is only
                -- honoured where it does not disable the engine that is running.
                local canRagdoll: boolean = method ~= "WalkSpeed"
                    and floatMethod ~= "Floor"
                    and floatMethod ~= "Jump"
                state.platformStandController.set(
                    "Fly",
                    canRagdoll and (flySettings.platformStand or method == "CFrame")
                )
                state.platformStandController.apply(humanoid)

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

                -- Constraints left behind by a mode switch keep driving the character
                -- against whatever engine is running now.
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
    -- The advanced block, declared: every row below says it belongs to the
    -- "Advanced settings" switch instead of the switch keeping a list of them.
    local advanced: any = {Option = "Advanced settings"}
    fly:CreateSlider({
        Name = "Response multiplier",
        Show = {advanced, {Option = "Method", Values = {"Velocity", "Constraint", "Pulse"}}},
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
        Show = advanced,
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
        Show = advanced,
        Default = flySettings.wallCheck,
        Function = function(value: boolean): ()
            flySettings.wallCheck = value
        end,
        Tooltip = "Stop against solid geometry instead of flying through it.",
    })
    fly:CreateToggle({
        Name = "PlatformStand",
        Show = advanced,
        Default = flySettings.platformStand,
        Function = function(value: boolean): ()
            flySettings.platformStand = value
        end,
        Tooltip = "Ragdoll the character while flying. Smoother, but no animations.",
    })
    fly:CreateToggle({
        Name = "Face camera",
        Show = advanced,
        Default = flySettings.faceCamera,
        Function = function(value: boolean): ()
            flySettings.faceCamera = value
        end,
        Tooltip = "Rotate the character to follow wherever the camera looks.",
    })
    local upKey: any = fly:CreateBind({
        Name = "Up key",
        Show = advanced,
        Default = flySettings.upKey,
        Function = function(value: Enum.KeyCode): ()
            flySettings.upKey = value
        end,
        Tooltip = "Hold to gain altitude.",
    })
    local downKey: any = fly:CreateBind({
        Name = "Down key",
        Show = advanced,
        Default = flySettings.downKey,
        Function = function(value: Enum.KeyCode): ()
            flySettings.downKey = value
        end,
        Tooltip = "Hold to lose altitude.",
    })

    fly:CreateToggle({
        Name = "Advanced settings",
        Default = false,
        Tooltip = "Everything above works on its own; this reveals the rest.",
    })

    -- Climbing and descending are holds on a keyboard, so they are holds on a
    -- phone too: keep a finger on UP to rise, lift it to level off. They used to
    -- latch on tap, which made hovering at a height nearly impossible.
    if state.bindMobileActionPlacement then
        state.bindMobileActionPlacement(
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
        state.bindMobileActionPlacement(
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
