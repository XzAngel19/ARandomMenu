export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
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
    local movementInput: any = context.services.movementInput
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

    local function moveDirection(): Vector3
        local camera: Camera? = currentWorkspace.CurrentCamera
        local forward: number, right: number = 0, 0
        if movementInput.getVector then
            forward, right = movementInput.getVector()
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
    speed = framework.Categories.Blatant:CreateModule({
        Name = "SpeedHack",
        Category = "Blatant",
        ConfigKey = "Universal.Speed",
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
