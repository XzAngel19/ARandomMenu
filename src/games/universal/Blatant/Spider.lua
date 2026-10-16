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
        ceilingWalk: boolean,
        impulseInterval: number,
    }
    local spiderSettings: SpiderSettings = {
        mode = "Spiderman",
        speed = 30,
        climbState = false,
        ceilingWalk = true,
        impulseInterval = 0.15,
    }
    local SpiderFeature: any = nil

    local function toggleSpider(enabled: boolean): ()
        disconnectFeatureConnection("Spider")
        if not enabled then
            if SpiderFeature then
                SpiderFeature:SetStatus(nil)
            end
            local _, _, rootOrNil: BasePart? = getCharacterParts()
            if rootOrNil then
                local curPos: Vector3 = rootOrNil.Position
                local flatForward: Vector3 = Vector3.new(rootOrNil.CFrame.LookVector.X, 0, rootOrNil.CFrame.LookVector.Z)
                if flatForward.Magnitude > 0.01 then
                    rootOrNil.CFrame = CFrame.lookAt(curPos, curPos + flatForward.Unit, Vector3.new(0, 1, 0))
                end
            end
            return
        end

        SpiderFeature:SetStatus(spiderSettings.mode)

        local onSurface: boolean = false
        local impulseElapsed: number = math.huge

        featureConnections.Spider = TaskManager:Connect(function(deltaTime: number): ()
            impulseElapsed += math.max(0, deltaTime)
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
            local isGrounded: boolean = humanoid.FloorMaterial ~= Enum.Material.Air

            if spiderSettings.mode == "Spiderman" then

                local feetRay: RaycastResult? = workspace:Raycast(
                    rootPos,
                    -root.CFrame.UpVector * (hipHeight + 2.2),
                    raycastParams
                )

                local wallRay: RaycastResult? = nil
                if moveDir.Magnitude > 0.05 then
                    wallRay = workspace:Raycast(
                        rootPos - root.CFrame.UpVector * (hipHeight * 0.4),
                        moveDir.Unit * 1.6,
                        raycastParams
                    )
                end

                local ceilingRay: RaycastResult? = nil
                if spiderSettings.ceilingWalk then
                    ceilingRay = workspace:Raycast(
                        rootPos,
                        Vector3.new(0, 3.5, 0),
                        raycastParams
                    )
                end

                local activeSurface: RaycastResult? = nil

                if onSurface then

                    if feetRay and feetRay.Instance and feetRay.Instance:IsA("BasePart") then
                        activeSurface = feetRay
                    elseif wallRay and wallRay.Instance and wallRay.Instance:IsA("BasePart") then
                        activeSurface = wallRay
                    elseif ceilingRay and ceilingRay.Instance and ceilingRay.Instance:IsA("BasePart") and ceilingRay.Normal.Y < -0.5 then
                        activeSurface = ceilingRay
                    end
                else

                    if wallRay and wallRay.Instance and wallRay.Instance:IsA("BasePart") and math.abs(wallRay.Normal.Y) <= 0.35 then
                        activeSurface = wallRay
                    elseif ceilingRay and ceilingRay.Instance and ceilingRay.Instance:IsA("BasePart") and ceilingRay.Normal.Y < -0.5 and not isGrounded then
                        activeSurface = ceilingRay
                    end
                end

                if activeSurface and activeSurface.Instance and activeSurface.Instance:IsA("BasePart") then
                    local surfNormal: Vector3 = activeSurface.Normal.Unit
                    onSurface = true

                    humanoid.PlatformStand = false
                    humanoid:ChangeState(Enum.HumanoidStateType.Running)

                    local wallUpVector: Vector3 = Vector3.new(0, 1, 0) - surfNormal * surfNormal.Y
                    if wallUpVector.Magnitude > 0.01 then
                        wallUpVector = wallUpVector.Unit
                    else
                        wallUpVector = root.CFrame.LookVector - surfNormal * root.CFrame.LookVector:Dot(surfNormal)
                        if wallUpVector.Magnitude <= 0.01 then
                            wallUpVector = root.CFrame.RightVector - surfNormal * root.CFrame.RightVector:Dot(surfNormal)
                        end
                        if wallUpVector.Magnitude <= 0.01 then return end
                        wallUpVector = wallUpVector.Unit
                    end

                    local surfaceMove: Vector3 = Vector3.zero
                    if cam then
                        local camLook: Vector3 = cam.CFrame.LookVector
                        local projLook: Vector3 = camLook - surfNormal * camLook:Dot(surfNormal)
                        if projLook.Magnitude > 0.01 then
                            projLook = projLook.Unit
                        else
                            projLook = wallUpVector
                        end

                        if moveDir.Magnitude > 0.05 then
                            local projMove: Vector3 = moveDir - surfNormal * moveDir:Dot(surfNormal)
                            if projMove.Magnitude > 0.01 then
                                surfaceMove = projMove.Unit
                            else
                                surfaceMove = projLook
                            end
                        end
                    end

                    local standDistance: number = hipHeight + 1.1
                    local wallHitPos: Vector3 = activeSurface.Position
                    local currentDistFromWall: number = (rootPos - wallHitPos):Dot(surfNormal)
                    local adjustedRootPos: Vector3 = rootPos

                    if currentDistFromWall < standDistance then

                        adjustedRootPos = wallHitPos + surfNormal * standDistance
                    end

                    local lookRef: Vector3 = surfaceMove.Magnitude > 0.05 and surfaceMove or wallUpVector
                    local targetCF: CFrame = CFrame.lookAt(adjustedRootPos, adjustedRootPos + lookRef, surfNormal)
                    root.CFrame = root.CFrame:Lerp(targetCF, math.clamp(deltaTime * 12, 0, 1))

                    local walkVelocity: Vector3 = (surfaceMove.Magnitude > 0.05) and (surfaceMove * spiderSettings.speed) or Vector3.zero
                    local gentleAdhesion: Vector3 = -surfNormal * 5

                    root.AssemblyLinearVelocity = walkVelocity + gentleAdhesion
                    return
                else
                    if onSurface then

                        local curPos: Vector3 = root.Position
                        local flatForward: Vector3 = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
                        if flatForward.Magnitude > 0.01 then
                            local uprightCF: CFrame = CFrame.lookAt(curPos, curPos + flatForward.Unit, Vector3.new(0, 1, 0))
                            root.CFrame = root.CFrame:Lerp(uprightCF, math.clamp(deltaTime * 10, 0, 1))
                            if math.abs(root.CFrame.UpVector.Y - 1) < 0.08 then
                                onSurface = false
                            end
                        else
                            onSurface = false
                        end
                    end
                end
                return
            end

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
        "Climb or run on walls and ceilings like Spider-Man",
        20,
        toggleSpider,
        {categoryName = "Exploits"}
    )
    local modeRows: {[string]: any} = {}
    local function refreshModeRows(): ()
        for name: string, button: any in pairs(modeRows) do
            local visible: boolean = name == "Ceiling Walk" and spiderSettings.mode == "Spiderman"
                or name == "Climb state" and spiderSettings.mode ~= "Spiderman"
                or name == "Impulse interval" and spiderSettings.mode == "Impulse"
            if host.setOptionVisible then host.setOptionVisible(SpiderFeature, button.Parent, visible)
            elseif button.Parent then button.Parent.Visible = visible end
        end
    end
    addCycleOption(
        SpiderFeature,
        "Mode",
        {"Spiderman", "Velocity", "Impulse", "CFrame"},
        1,
        function(value: string): ()
            spiderSettings.mode = value
            refreshModeRows()
            if SpiderFeature.enabled then
                -- Do not carry a ceiling pose or pulse timer into a new mode.
                toggleSpider(false)
                toggleSpider(true)
            end
        end,
        "Spiderman: Walks on walls/ceilings using your feet with realistic surface physics.\nVelocity/Impulse/CFrame: Classic upward vertical climbing modes."
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
    local ceilingRow: any = addToggleOption(
        SpiderFeature,
        "Ceiling Walk",
        spiderSettings.ceilingWalk,
        function(value: boolean): ()
            spiderSettings.ceilingWalk = value
        end,
        "Allows running upside-down on ceilings with your feet in Spiderman mode."
    )
    local climbRow: any = addToggleOption(
        SpiderFeature,
        "Climb state",
        spiderSettings.climbState,
        function(value: boolean): ()
            spiderSettings.climbState = value
        end,
        "Uses climbing state in classic modes (Velocity, Impulse, CFrame)."
    )
    if ceilingRow then modeRows["Ceiling Walk"] = ceilingRow end
    if climbRow then modeRows["Climb state"] = climbRow end
    local impulseRow: any = addNumberOption(SpiderFeature, "Impulse interval", spiderSettings.impulseInterval,
        0.05, 0.5, function(value: number): () spiderSettings.impulseInterval = value end,
        "Seconds between bounded upward impulses. Only used by Impulse mode.", 0.05)
    if impulseRow then modeRows["Impulse interval"] = impulseRow end
    refreshModeRows()
    addFeatureTooltip(
        SpiderFeature,
        "Spiderman mode plants your feet on walls and ceilings to run like Spider-Man. Classic modes pull you vertically up walls."
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
