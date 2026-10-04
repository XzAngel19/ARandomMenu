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

    type SpiderSettings = {
        mode: string,
        speed: number,
        climbState: boolean,
    }
    local spiderSettings: SpiderSettings = {
        mode = "Velocity",
        speed = 30,
        climbState = true,
    }
    local SpiderFeature: any = nil
    local function toggleSpider(enabled: boolean): ()
        disconnectFeatureConnection("Spider")
        if not enabled then
            if SpiderFeature then
                SpiderFeature:SetStatus(nil)
            end
            return
        end
        SpiderFeature:SetStatus(spiderSettings.mode)
        local climbing: boolean = false
        featureConnections.Spider = TaskManager:Connect(function(deltaTime: number): ()
            local character: Model?, humanoidOrNil: Humanoid?, rootOrNil: BasePart? =
                getCharacterParts()
            if not character or not humanoidOrNil or not rootOrNil then
                climbing = false
                return
            end
            local humanoid: Humanoid = humanoidOrNil :: Humanoid
            local root: BasePart = rootOrNil :: BasePart
            local direction: Vector3 = humanoid.MoveDirection
            if direction.Magnitude < 0.05 then
                climbing = false
                return
            end

            local raycastParams: RaycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.RespectCanCollide = true
            local ignored: {Instance} = {character :: Instance}
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    table.insert(ignored, player.Character :: Instance)
                end
            end
            raycastParams.FilterDescendantsInstances = ignored

            local origin: Vector3 = root.Position
                - Vector3.new(0, math.max(humanoid.HipHeight - 0.5, 0), 0)
            local wall: RaycastResult? = workspace:Raycast(
                origin,
                direction.Unit * 2.5,
                raycastParams
            )
            local velocity: Vector3 = root.AssemblyLinearVelocity
            if not wall or math.abs((wall :: RaycastResult).Normal.Y) >= 0.35 then
                if climbing then

                    root.AssemblyLinearVelocity =
                        Vector3.new(velocity.X, 0, velocity.Z)
                    climbing = false
                end
                return
            end

            climbing = true
            if spiderSettings.climbState then
                humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
            end
            if spiderSettings.mode == "CFrame" then
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
                root.CFrame = root.CFrame
                    + Vector3.new(0, spiderSettings.speed * deltaTime, 0)
            elseif spiderSettings.mode == "Impulse" then
                root:ApplyImpulse(
                    Vector3.new(0, spiderSettings.speed, 0) * root.AssemblyMass
                )
            else
                root.AssemblyLinearVelocity =
                    Vector3.new(velocity.X, spiderSettings.speed, velocity.Z)
            end
        end)
    end

    SpiderFeature = createUniversalFeature(
        "Spider",
        "Climb a wall automatically while moving into it",
        20,
        toggleSpider,
        {categoryName = "Movement"}
    )
    addCycleOption(
        SpiderFeature,
        "Mode",
        {"Velocity", "Impulse", "CFrame"},
        1,
        function(value: string): ()
            spiderSettings.mode = value
            if SpiderFeature.enabled then
                SpiderFeature:SetStatus(value)
            end
        end,
        "Velocity is smooth and works nearly everywhere; Impulse survives games "
            .. "that rewrite your velocity every frame; CFrame works when both are "
            .. "clamped and is the most obvious of the three."
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
        end,
        "Puts the humanoid in its climbing state, so the animation matches and "
            .. "games that read the state see a climb instead of a jump."
    )
    addFeatureTooltip(
        SpiderFeature,
        "Walk into a wall to climb it. The climb stops with the wall, so reaching "
            .. "the top steps onto it instead of launching you off."
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("Spider")
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
