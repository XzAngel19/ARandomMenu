export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Spider",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local addCycleOption: any = host.addCycleOption
    local addFeatureTooltip: any = host.addFeatureTooltip
    local workspace: Workspace = host.workspace or workspace

    type SpiderSettings = {
        mode: string,
        speed: number,
        climbState: boolean,
        impulseInterval: number,
    }
    local spiderSettings: SpiderSettings = {
        mode = "Velocity",
        speed = 30,
        climbState = false,
        impulseInterval = 0.15,
    }
    local SpiderFeature: any = nil
    local climbingHumanoid: Humanoid? = nil
    local function releaseClimbState()
        local humanoid = climbingHumanoid
        climbingHumanoid = nil
        if humanoid and humanoid.Parent and humanoid.Health > 0 and humanoid:GetState() == Enum.HumanoidStateType.Climbing then
            humanoid:ChangeState(humanoid.FloorMaterial == Enum.Material.Air
                and Enum.HumanoidStateType.Freefall or Enum.HumanoidStateType.Running)
        end
    end

    local function toggleSpider(enabled: boolean): ()
        disconnectFeatureConnection("Spider")
        releaseClimbState()
        if not enabled then
            if SpiderFeature then
                SpiderFeature:SetStatus(nil)
            end

            return
        end

        SpiderFeature:SetStatus(spiderSettings.mode)

        local impulseElapsed: number = math.huge

        featureConnections.Spider = TaskManager:Connect(function(deltaTime: number): ()
            impulseElapsed += math.max(0, deltaTime)
            local character: Model?, humanoidOrNil: Humanoid?, rootOrNil: BasePart? =
                getCharacterParts()
            if not character or not humanoidOrNil or not rootOrNil or humanoidOrNil.Health <= 0
                or humanoidOrNil.Sit or rootOrNil.Anchored then
                releaseClimbState()
                return
            end
            if climbingHumanoid and climbingHumanoid ~= humanoidOrNil then releaseClimbState() end
            local humanoid: Humanoid = humanoidOrNil :: Humanoid
            local root: BasePart = rootOrNil :: BasePart

            local raycastParams: RaycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.RespectCanCollide = true
            raycastParams.CollisionGroup = root.CollisionGroup
            local ignored: {Instance} = {character :: Instance}
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    table.insert(ignored, player.Character :: Instance)
                end
            end
            raycastParams.FilterDescendantsInstances = ignored

            local hipHeight: number = humanoid.HipHeight > 0 and humanoid.HipHeight or 2.0
            local rootPos: Vector3 = root.Position
            local moveDir: Vector3 = humanoid.MoveDirection

            if moveDir.Magnitude < 0.05 then
                releaseClimbState()
                return
            end

            local origin: Vector3 = rootPos - Vector3.new(0, math.max(hipHeight - 0.5, 0), 0)
            local wall: RaycastResult? = workspace:Raycast(
                origin,
                moveDir.Unit * 2.5,
                raycastParams
            )
            local velocity: Vector3 = root.AssemblyLinearVelocity
            if not wall or math.abs((wall :: RaycastResult).Normal.Y) >= 0.35 then
                releaseClimbState()
                return
            end

            if moveDir:Dot(wall.Normal) > -0.1 then releaseClimbState();return end

            if spiderSettings.climbState then
                climbingHumanoid = humanoid
                humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
            end

            if spiderSettings.mode == "CFrame" then
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
                local rise = Vector3.new(0, spiderSettings.speed * math.clamp(deltaTime, 0, 0.1), 0)
                local ceiling = workspace:Raycast(rootPos, rise + Vector3.new(0, hipHeight + 1, 0), raycastParams)
                if ceiling then rise = Vector3.new(0, math.max(0, ceiling.Distance - hipHeight - 1), 0) end
                root.CFrame = root.CFrame + rise
            elseif spiderSettings.mode == "Impulse" then
                -- Pulsed, mass-independent boost, not +speed every frame.
                -- The old integration accelerated indefinitely and depended on FPS.
                if impulseElapsed >= spiderSettings.impulseInterval then
                    impulseElapsed = 0
                    local deltaVelocity: number = math.max(0, spiderSettings.speed - velocity.Y)
                    if deltaVelocity > 0 then root:ApplyImpulse(Vector3.new(0, deltaVelocity, 0) * root.AssemblyMass) end
                end
            else
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, spiderSettings.speed, velocity.Z)
            end
        end)
    end

    SpiderFeature = createUniversalFeature(
        "Spider",
        "Climb a wall while moving toward it",
        20,
        toggleSpider,
        {categoryName = "Exploits"}
    )
    local modeRows: {[string]: any} = {}
    local function refreshModeRows(): ()
        for name: string, row: any in pairs(modeRows) do
            local visible: boolean = name == "Impulse interval" and spiderSettings.mode == "Impulse"
            if host.setOptionVisible then host.setOptionVisible(SpiderFeature, row, visible)
            elseif row then row.Visible = visible end
        end
    end
    addCycleOption(
        SpiderFeature,
        "Mode",
        {"Velocity", "Impulse", "CFrame"},
        1,
        function(value: string): ()
            spiderSettings.mode = value
            refreshModeRows()
            if SpiderFeature.enabled then
                -- Restart the pulse timer on a mode change.
                toggleSpider(false)
                toggleSpider(true)
            end
        end,
        "Velocity: continuous climb. Impulse: timed upward boosts. CFrame: bounded vertical steps."
    )
    addNumberOption(
        SpiderFeature,
        "Climb speed",
        spiderSettings.speed,
        5,
        100,
        function(value: number): ()
            spiderSettings.speed = value
        end
    )
    addToggleOption(
        SpiderFeature,
        "Climb state",
        spiderSettings.climbState,
        function(value: boolean): ()
            spiderSettings.climbState = value
            if not value then releaseClimbState() end
        end,
        "Uses climbing state in classic modes (Velocity, Impulse, CFrame)."
    )
    local impulseRow: any = addNumberOption(SpiderFeature, "Impulse interval", spiderSettings.impulseInterval,
        0.05, 0.5, function(value: number): () spiderSettings.impulseInterval = value end,
        "Seconds between bounded upward impulses. Only used by Impulse mode.", 0.05)
    if impulseRow then modeRows["Impulse interval"] = impulseRow end
    refreshModeRows()
    addFeatureTooltip(
        SpiderFeature,
        "Climb only when pushing into a nearby vertical wall. No wall rotation or ceiling walking."
    )

    activeCleanup = function(): ()
        toggleSpider(false)
    end
    Module.Initialized = true
    return SpiderFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
