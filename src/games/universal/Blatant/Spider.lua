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
        realistic: boolean,
        ceilingWalk: boolean,
    }
    local spiderSettings: SpiderSettings = {
        mode = "Velocity",
        speed = 32,
        climbState = false,
        realistic = true,
        ceilingWalk = true,
    }
    local SpiderFeature: any = nil

    local function toggleSpider(enabled: boolean): ()
        disconnectFeatureConnection("Spider")
        if not enabled then
            if SpiderFeature then
                SpiderFeature:SetStatus(nil)
            end
            local character: Model?, humanoidOrNil: Humanoid?, rootOrNil: BasePart? =
                getCharacterParts()
            if rootOrNil then
                -- Restore upright orientation
                local curPos: Vector3 = rootOrNil.Position
                local flatForward: Vector3 = Vector3.new(rootOrNil.CFrame.LookVector.X, 0, rootOrNil.CFrame.LookVector.Z)
                if flatForward.Magnitude > 0.01 then
                    rootOrNil.CFrame = CFrame.lookAt(curPos, curPos + flatForward.Unit, Vector3.new(0, 1, 0))
                end
            end
            return
        end

        local statusText: string = spiderSettings.realistic and "Realistic" or spiderSettings.mode
        SpiderFeature:SetStatus(statusText)

        local onSurface: boolean = false
        local lastSurfaceNormal: Vector3 = Vector3.new(0, 1, 0)

        featureConnections.Spider = TaskManager:Connect(function(deltaTime: number): ()
            local character: Model?, humanoidOrNil: Humanoid?, rootOrNil: BasePart? =
                getCharacterParts()
            if not character or not humanoidOrNil or not rootOrNil then
                onSurface = false
                return
            end
            local humanoid: Humanoid = humanoidOrNil :: Humanoid
            local root: BasePart = rootOrNil :: BasePart
            local cam: Camera? = workspace.CurrentCamera

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

            local hipHeight: number = humanoid.HipHeight > 0 and humanoid.HipHeight or 2.0
            local rootPos: Vector3 = root.Position
            local moveDir: Vector3 = humanoid.MoveDirection

            -- Realistic Spider-Man mode: feet planted on wall/ceiling, walking with feet
            if spiderSettings.realistic then
                -- Scan 1: Below current feet (to maintain stick while walking along a surface)
                local feetRay: RaycastResult? = workspace:Raycast(
                    rootPos,
                    -root.CFrame.UpVector * (hipHeight + 1.8),
                    raycastParams
                )

                -- Scan 2: In front / move direction (to step onto an approaching wall)
                local frontRay: RaycastResult? = nil
                if moveDir.Magnitude > 0.05 then
                    frontRay = workspace:Raycast(
                        rootPos - root.CFrame.UpVector * (hipHeight * 0.5),
                        moveDir.Unit * 3.0,
                        raycastParams
                    )
                else
                    frontRay = workspace:Raycast(
                        rootPos - root.CFrame.UpVector * (hipHeight * 0.5),
                        root.CFrame.LookVector * 2.5,
                        raycastParams
                    )
                end

                -- Scan 3: Ceiling (if ceiling walk is enabled and jumping near ceiling)
                local ceilingRay: RaycastResult? = nil
                if spiderSettings.ceilingWalk then
                    ceilingRay = workspace:Raycast(
                        rootPos,
                        Vector3.new(0, 3.8, 0),
                        raycastParams
                    )
                end

                local activeSurface: RaycastResult? = nil
                if frontRay and frontRay.Instance and frontRay.Instance:IsA("BasePart") then
                    activeSurface = frontRay
                elseif feetRay and feetRay.Instance and feetRay.Instance:IsA("BasePart") and math.abs(feetRay.Normal.Y) < 0.92 then
                    activeSurface = feetRay
                elseif ceilingRay and ceilingRay.Instance and ceilingRay.Instance:IsA("BasePart") and ceilingRay.Normal.Y < -0.6 then
                    activeSurface = ceilingRay
                end

                if activeSurface and activeSurface.Instance and activeSurface.Instance:IsA("BasePart") then
                    local surfNormal: Vector3 = activeSurface.Normal.Unit
                    lastSurfaceNormal = surfNormal
                    onSurface = true

                    -- Prevent humanoid falling / tripping on wall
                    humanoid.PlatformStand = false
                    humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)

                    -- Compute surface tangent axes
                    local surfUp: Vector3 = surfNormal
                    local wallUpVector: Vector3 = Vector3.new(0, 1, 0) - surfNormal * surfNormal.Y
                    if wallUpVector.Magnitude > 0.01 then
                        wallUpVector = wallUpVector.Unit
                    else
                        -- Ceiling or floor
                        wallUpVector = (root.CFrame.LookVector - surfNormal * root.CFrame.LookVector:Dot(surfNormal)).Unit
                    end

                    local wallRightVector: Vector3 = wallUpVector:Cross(surfNormal).Unit

                    -- Map movement input along the surface
                    local surfaceMove: Vector3 = Vector3.zero
                    if cam then
                        local camLook: Vector3 = cam.CFrame.LookVector
                        local projLook: Vector3 = camLook - surfNormal * camLook:Dot(surfNormal)
                        if projLook.Magnitude > 0.01 then
                            projLook = projLook.Unit
                        else
                            projLook = wallUpVector
                        end
                        local projRight: Vector3 = projLook:Cross(surfNormal).Unit

                        if moveDir.Magnitude > 0.05 then
                            -- Project humanoid move direction onto surface
                            local projMove: Vector3 = moveDir - surfNormal * moveDir:Dot(surfNormal)
                            if projMove.Magnitude > 0.01 then
                                surfaceMove = projMove.Unit
                            else
                                surfaceMove = projLook
                            end
                        end
                    end

                    -- Rotate character so UpVector aligns with surface normal (feet on the surface!)
                    local lookRef: Vector3 = surfaceMove.Magnitude > 0.05 and surfaceMove or wallUpVector
                    local targetCF: CFrame = CFrame.lookAt(rootPos, rootPos + lookRef, surfNormal)
                    root.CFrame = root.CFrame:Lerp(targetCF, math.clamp(deltaTime * 14, 0, 1))

                    -- Apply velocity along surface + downward foot adhesion force towards the surface
                    local adhesionForce: Vector3 = -surfNormal * 28
                    local walkVelocity: Vector3 = (surfaceMove.Magnitude > 0.05) and (surfaceMove * spiderSettings.speed) or Vector3.zero

                    root.AssemblyLinearVelocity = walkVelocity + adhesionForce
                    return
                else
                    if onSurface then
                        -- Stepped off the wall onto ground or into open air: smoothly restore upright
                        local curPos: Vector3 = root.Position
                        local flatForward: Vector3 = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
                        if flatForward.Magnitude > 0.01 then
                            local uprightCF: CFrame = CFrame.lookAt(curPos, curPos + flatForward.Unit, Vector3.new(0, 1, 0))
                            root.CFrame = root.CFrame:Lerp(uprightCF, math.clamp(deltaTime * 12, 0, 1))
                            if math.abs(root.CFrame.UpVector.Y - 1) < 0.05 then
                                onSurface = false
                            end
                        else
                            onSurface = false
                        end
                    end
                end
                return
            end

            -- Legacy / Classic Climb Mode (Velocity, Impulse, CFrame)
            if moveDir.Magnitude < 0.05 then
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
                return
            end

            if spiderSettings.climbState then
                humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
            end

            if spiderSettings.mode == "CFrame" then
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
                root.CFrame = root.CFrame + Vector3.new(0, spiderSettings.speed * deltaTime, 0)
            elseif spiderSettings.mode == "Impulse" then
                root:ApplyImpulse(Vector3.new(0, spiderSettings.speed, 0) * root.AssemblyMass)
            else
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, spiderSettings.speed, velocity.Z)
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
            if SpiderFeature.enabled and not spiderSettings.realistic then
                SpiderFeature:SetStatus(value)
            end
        end,
        "Classic climb mode when Realistic is disabled."
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
        "Realistic",
        spiderSettings.realistic,
        function(value: boolean): ()
            spiderSettings.realistic = value
            if SpiderFeature.enabled then
                SpiderFeature:SetStatus(value and "Realistic" or spiderSettings.mode)
            end
        end,
        "Spiderman physics: Plants your feet on the wall or ceiling with full surface walking animations."
    )
    addToggleOption(
        SpiderFeature,
        "Ceiling Walk",
        spiderSettings.ceilingWalk,
        function(value: boolean): ()
            spiderSettings.ceilingWalk = value
        end,
        "Allows walking upside-down on ceilings with your feet when Realistic mode is enabled."
    )
    addToggleOption(
        SpiderFeature,
        "Climb state",
        spiderSettings.climbState,
        function(value: boolean): ()
            spiderSettings.climbState = value
        end,
        "Uses climbing state in classic mode."
    )
    addFeatureTooltip(
        SpiderFeature,
        "Walk into walls or ceilings to run on them like Spider-Man using your feet, or use classic vertical climbing."
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
