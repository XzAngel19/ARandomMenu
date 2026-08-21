--!strict
--
-- Speed.
--
-- The old module was one line of work — `humanoid.WalkSpeed = value` on a
-- loop — which is the one method that does nothing in every game that clamps
-- WalkSpeed, and that is most of them. This is an engine: five ways of moving
-- faster, because which one survives is a property of the game and not of the
-- player.
--
--   WalkSpeed   the humanoid's own speed. Invisible to anything that is not
--               reading it, and the first thing a game clamps.
--   Velocity    the assembly's horizontal velocity, rewritten each frame with
--               the vertical component left alone so gravity still works.
--   Impulse     the same target expressed as a force, for games that overwrite
--               velocity every frame and win the argument.
--   CFrame      stepping the root directly. Nothing to clamp, so it works
--               where the other three are ignored — and it walks through walls
--               unless the wall check stops it.
--   Teleport    CFrame in bursts. The fastest and by a distance the most
--               obvious: a character that arrives in jumps is what a spectator
--               notices first.
--
-- The direction comes from the shared input helper rather than from
-- `Humanoid.MoveDirection`, so it is the same on a keyboard, a thumbstick and
-- a phone — and it keeps working while the character is in PlatformStand,
-- where MoveDirection reads zero.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Speed",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local state: any = host.state
    local framework: any = context.framework
    local LocalPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace

    local runtime: any = {
        originalWalkSpeed = setmetatable({}, {__mode = "k"}) :: any,
        nextTeleportAt = 0,
    }

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil, nil, nil
        end
        local humanoid: Humanoid? =
            character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? =
            character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return character, humanoid, root
    end

    local function restoreWalkSpeed(): ()
        for humanoid: Humanoid, value: number in pairs(runtime.originalWalkSpeed) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = value
            end
        end
        runtime.originalWalkSpeed = setmetatable({}, {__mode = "k"}) :: any
    end

    -- Where the player is asking to go, in world space, from whichever input
    -- the device actually has.
    local function moveDirection(): Vector3
        local camera: Camera? = currentWorkspace.CurrentCamera
        local forward: number, right: number = 0, 0
        if state.getMoveInput then
            forward, right = state.getMoveInput()
        end
        if forward == 0 and right == 0 then
            local _, humanoid: Humanoid? = characterParts()
            local move: Vector3 = humanoid and humanoid.MoveDirection or Vector3.zero
            return move.Magnitude > 0.05 and move.Unit or Vector3.zero
        end
        if not camera then
            return Vector3.zero
        end
        local look: Vector3 = (camera :: Camera).CFrame.LookVector
        local side: Vector3 = (camera :: Camera).CFrame.RightVector
        local flatLook: Vector3 = Vector3.new(look.X, 0, look.Z)
        local flatSide: Vector3 = Vector3.new(side.X, 0, side.Z)
        if flatLook.Magnitude < 0.001 then
            return Vector3.zero
        end
        local direction: Vector3 =
            flatLook.Unit * forward + flatSide.Unit * right
        return direction.Magnitude > 0.05 and direction.Unit or Vector3.zero
    end

    -- Only used by CFrame and Teleport: the two that would otherwise put you
    -- inside geometry. Other characters are excluded so a crowd does not stop
    -- you dead.
    local function blocked(root: BasePart, step: Vector3): Vector3
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.RespectCanCollide = true
        local ignore: {Instance} = {LocalPlayer.Character :: Instance}
        for _, player: Player in ipairs(host.Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                table.insert(ignore, player.Character :: Instance)
            end
        end
        parameters.FilterDescendantsInstances = ignore
        local hit: RaycastResult? =
            currentWorkspace:Raycast(root.Position, step, parameters)
        if not hit then
            return step
        end
        return ((hit :: RaycastResult).Position + (hit :: RaycastResult).Normal)
            - root.Position
    end

    local speed: any
    speed = framework.Categories.Movement:CreateModule({
        Name = "Speed",
        Category = "Movement",
        Order = 1,
        Tooltip = "Move faster, by whichever of five methods this game lets "
            .. "through.",
        Function = function(enabled: boolean): ()
            runtime.nextTeleportAt = 0
            if not enabled then
                speed:SetStatus(nil)
                restoreWalkSpeed()
                return
            end
            speed:SetStatus(
                tostring(speed.Options["Mode"].Value)
                    .. " "
                    .. tostring(math.round(speed.Options["Speed"].Value))
            )
            speed:Clean(restoreWalkSpeed)
            speed:Loop(function(deltaTime: number): ()
                local options: any = speed.Options
                local _, humanoid: Humanoid?, root: BasePart? = characterParts()
                if not humanoid or not root then
                    return
                end
                local resolvedHumanoid: Humanoid = humanoid :: Humanoid
                local resolvedRoot: BasePart = root :: BasePart
                if resolvedHumanoid.Health <= 0 then
                    return
                end

                local mode: string = options["Mode"].Value
                local target: number = options["Speed"].Value

                -- WalkSpeed is the only mode that has to put something back,
                -- so it is the only one that records anything.
                if mode == "WalkSpeed" then
                    if runtime.originalWalkSpeed[resolvedHumanoid] == nil then
                        runtime.originalWalkSpeed[resolvedHumanoid] =
                            resolvedHumanoid.WalkSpeed
                    end
                    resolvedHumanoid.WalkSpeed = target
                    return
                end
                restoreWalkSpeed()

                local direction: Vector3 = moveDirection()
                if direction.Magnitude < 0.05 then
                    return
                end

                -- Hop while moving, for the games where a grounded character
                -- is the thing being clamped.
                if options["Auto jump"].Value
                    and resolvedHumanoid.FloorMaterial ~= Enum.Material.Air then
                    resolvedHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end

                local velocity: Vector3 = resolvedRoot.AssemblyLinearVelocity
                if mode == "Velocity" then
                    resolvedRoot.AssemblyLinearVelocity = Vector3.new(
                        direction.X * target,
                        velocity.Y,
                        direction.Z * target
                    )
                    return
                end
                if mode == "Impulse" then
                    local wanted: Vector3 = direction * target
                    local difference: Vector3 = Vector3.new(
                        wanted.X - velocity.X,
                        0,
                        wanted.Z - velocity.Z
                    )
                    if difference.Magnitude > 2 then
                        resolvedRoot:ApplyImpulse(
                            difference * resolvedRoot.AssemblyMass
                        )
                    end
                    return
                end

                -- CFrame and Teleport move the character themselves, so what
                -- they add is the difference between the speed asked for and
                -- the speed the humanoid is already providing.
                local extra: number =
                    math.max(target - resolvedHumanoid.WalkSpeed, 0)
                if mode == "Teleport" then
                    local now: number = os.clock()
                    if now < runtime.nextTeleportAt then
                        return
                    end
                    runtime.nextTeleportAt = now + options["Burst delay"].Value
                    local step: Vector3 = direction * extra
                        * options["Burst delay"].Value
                    if options["Wall check"].Value then
                        step = blocked(resolvedRoot, step)
                    end
                    resolvedRoot.CFrame = resolvedRoot.CFrame + step
                    return
                end

                local step: Vector3 = direction * extra * deltaTime
                if options["Wall check"].Value then
                    step = blocked(resolvedRoot, step)
                end
                resolvedRoot.CFrame = resolvedRoot.CFrame + step
            end)
        end,
    })

    speed:CreateDropdown({
        Name = "Mode",
        List = {"WalkSpeed", "Velocity", "Impulse", "CFrame", "Teleport"},
        Index = 1,
        Function = function(value: string): ()
            if speed.Enabled then
                speed:SetStatus(
                    value .. " " .. tostring(math.round(speed.Options["Speed"].Value))
                )
            end
        end,
        Tooltip = "WalkSpeed is the quietest and the first thing a game "
            .. "clamps; CFrame works where the others are ignored; Teleport is "
            .. "the fastest and the most obvious.",
    })
    speed:CreateSlider({
        Name = "Speed",
        Min = 16,
        Max = 200,
        Default = 32,
        Function = function(value: number): ()
            if speed.Enabled then
                speed:SetStatus(
                    tostring(speed.Options["Mode"].Value)
                        .. " "
                        .. tostring(math.round(value))
                )
            end
        end,
        Tooltip = "Studs per second. A default character walks at 16, sprints "
            .. "in most games at 24-28; past about 60 you are visibly not "
            .. "running.",
    })
    speed:CreateToggle({
        Name = "Wall check",
        Show = {Option = "Mode", Values = {"CFrame", "Teleport"}},
        Default = true,
        Tooltip = "Stop at geometry instead of stepping through it. Only the "
            .. "two modes that move you directly can go through a wall.",
    })
    speed:CreateSlider({
        Name = "Burst delay",
        Show = {Option = "Mode", Values = {"Teleport"}},
        Min = 0.05,
        Max = 1,
        Default = 0.2,
        Tooltip = "Seconds between jumps. Shorter is faster and reads as "
            .. "teleporting; longer reads as lag.",
    })
    speed:CreateToggle({
        Name = "Auto jump",
        Show = {Option = "Mode", Values = {"Velocity", "Impulse", "CFrame", "Teleport"}},
        Default = false,
        Tooltip = "Hop continuously while moving, for games that only clamp a "
            .. "character that is standing on something.",
    })
    speed:CreateNote(
        "If nothing happens, the game is clamping that method — try the next "
            .. "one down the list. WalkSpeed and Velocity are the two that "
            .. "look like a person moving."
    )

    activeCleanup = function(): ()
        restoreWalkSpeed()
    end
    Module.Initialized = true
    return speed
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
