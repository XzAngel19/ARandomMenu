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
        realistic: boolean,
    }
    local spiderSettings: SpiderSettings = {
        mode = "Velocity",
        speed = 30,
        climbState = true,
        realistic = false,
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
                if spiderSettings.realistic and math.abs(root.CFrame.UpVector.Y - 1) > 0.05 then
                    local currentPos: Vector3 = root.Position
                    local flatForward: Vector3 = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
                    if flatForward.Magnitude > 0.01 then
                        local upright: CFrame = CFrame.lookAt(currentPos, currentPos + flatForward.Unit, Vector3.new(0, 1, 0))
                        root.CFrame = root.CFrame:Lerp(upright, math.clamp(deltaTime * 12, 0, 1))
                    end
                end
                return
            end

            climbing = true
            local wallNormal: Vector3 = (wall :: RaycastResult).Normal

            if spiderSettings.realistic then
                local forward: Vector3 = (root.CFrame.LookVector - wallNormal * root.CFrame.LookVector:Dot(wallNormal))
                if forward.Magnitude > 0.01 then
                    forward = forward.Unit
                else
                    forward = root.CFrame.LookVector
                end
                local targetCF: CFrame = CFrame.lookAt(root.Position, root.Position + forward, wallNormal)
                root.CFrame = root.CFrame:Lerp(targetCF, math.clamp(deltaTime * 10, 0, 1))

                local moveTangent: Vector3 = (direction - wallNormal * direction:Dot(wallNormal))
                if moveTangent.Magnitude > 0.05 then
                    moveTangent = moveTangent.Unit
                else
                    moveTangent = forward
                end
                root.AssemblyLinearVelocity = moveTangent * spiderSettings.speed - wallNormal * 8
                return
            end

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
        {categoryName = "Blatant"}
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
    addToggleOption(
        SpiderFeature,
        "Realistic",
        spiderSettings.realistic,
        function(value: boolean): ()
            spiderSettings.realistic = value
        end,
        "Defies gravity to walk on walls like ground, aligning your character to the wall surface."
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
