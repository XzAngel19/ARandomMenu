export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Invisible",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local LocalPlayer: any = host.LocalPlayer
    local UserInputService: any = host.UserInputService or (game :: any):GetService("UserInputService")
    local RunService: RunService = host.RunService or (game :: any):GetService("RunService")
    local currentWorkspace: Workspace = host.workspace or workspace

    type InvisibleSettings = {
        voidDepth: number,
        ghostTransparency: number,
        fly: boolean,
        flySpeed: number,
    }

    local invisibleSettings: InvisibleSettings = {
        voidDepth = 120,
        ghostTransparency = 0.5,
        fly = true,
        flySpeed = 55,
    }

    local invisibleRuntime = {
        active = false,
        ghostModel = nil :: Model?,
        surfacePosition = nil :: CFrame?,
        connections = {} :: {RBXScriptConnection},
    }

    local function destroyGhost(): ()
        if invisibleRuntime.ghostModel then
            pcall(function()
                invisibleRuntime.ghostModel:Destroy()
            end)
            invisibleRuntime.ghostModel = nil
        end
    end

    local function createGhost(character: Model): Model?
        character.Archivable = true
        local clone: Instance? = character:Clone()
        character.Archivable = false
        if not clone or not clone:IsA("Model") then
            return nil
        end
        local ghost: Model = clone :: Model
        ghost.Name = "Wurst_Ghost"

        local ghostHumanoid: Humanoid? = ghost:FindFirstChildOfClass("Humanoid")
        if ghostHumanoid then
            ghostHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            ghostHumanoid.NameDisplayDistance = 0
            ghostHumanoid.HealthDisplayDistance = 0
        end

        for _, desc: Instance in ipairs(ghost:GetDescendants()) do
            if desc:IsA("Script") or desc:IsA("LocalScript") then
                desc:Destroy()
            elseif desc:IsA("BasePart") then
                desc.CanCollide = false
                desc.CanTouch = false
                desc.CanQuery = false
                desc.Anchored = true
                desc.Transparency = math.clamp(invisibleSettings.ghostTransparency, 0.1, 0.9)
                desc.CastShadow = false
            end
        end

        local highlight: Highlight = Instance.new("Highlight")
        highlight.Name = "GhostHighlight"
        highlight.FillColor = Color3.fromRGB(120, 210, 255)
        highlight.OutlineColor = Color3.fromRGB(220, 245, 255)
        highlight.FillTransparency = 0.6
        highlight.OutlineTransparency = 0.15
        highlight.Adornee = ghost
        highlight.Parent = ghost

        ghost.Parent = currentWorkspace
        return ghost
    end

    local function toggleInvisible(enabled: boolean): ()
        for _, c: RBXScriptConnection in ipairs(invisibleRuntime.connections) do
            pcall(function()
                c:Disconnect()
            end)
        end
        table.clear(invisibleRuntime.connections)

        local character: Model? = LocalPlayer.Character
        local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local camera: Camera? = currentWorkspace.CurrentCamera

        if not enabled then
            if invisibleRuntime.active and root and invisibleRuntime.surfacePosition then
                -- Teleport real character to the exact position of the ghost on the map
                root.CFrame = invisibleRuntime.surfacePosition
                root.AssemblyLinearVelocity = Vector3.zero
            end
            if camera and humanoid then
                pcall(function()
                    camera.CameraSubject = humanoid
                end)
            end
            destroyGhost()
            invisibleRuntime.active = false
            invisibleRuntime.surfacePosition = nil
            return
        end

        if not character or not root or not humanoid or humanoid.Health <= 0 then
            destroyGhost()
            return
        end

        invisibleRuntime.active = true
        invisibleRuntime.surfacePosition = root.CFrame

        local ghost: Model? = createGhost(character)
        invisibleRuntime.ghostModel = ghost

        local ghostRoot: BasePart? = ghost and ghost:FindFirstChild("HumanoidRootPart") :: BasePart?
        local ghostHumanoid: Humanoid? = ghost and ghost:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if ghostRoot and invisibleRuntime.surfacePosition then
            ghostRoot.CFrame = invisibleRuntime.surfacePosition
        end

        -- Focus the camera onto the ghost so the user stays on the map!
        if camera and ghostHumanoid then
            pcall(function()
                camera.CameraSubject = ghostHumanoid
            end)
        end

        -- RenderStepped loop: controls the ghost on the surface while keeping the real character in the void
        table.insert(
            invisibleRuntime.connections,
            RunService.RenderStepped:Connect(function(deltaTime: number): ()
                if not invisibleRuntime.active then
                    return
                end
                local currentCharacter: Model? = LocalPlayer.Character
                local currentRoot: BasePart? = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
                local currentHumanoid: Humanoid? = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
                if not currentCharacter or not currentRoot or not currentHumanoid or currentHumanoid.Health <= 0 then
                    return
                end

                local activeGhost: Model? = invisibleRuntime.ghostModel
                if not activeGhost or not activeGhost.Parent then
                    activeGhost = createGhost(currentCharacter)
                    invisibleRuntime.ghostModel = activeGhost
                    if camera and activeGhost then
                        local newGhostHumanoid: Humanoid? = activeGhost:FindFirstChildOfClass("Humanoid")
                        if newGhostHumanoid then
                            camera.CameraSubject = newGhostHumanoid
                        end
                    end
                end
                local activeGhostRoot: BasePart? = activeGhost and activeGhost:FindFirstChild("HumanoidRootPart") :: BasePart?
                local activeCam: Camera? = currentWorkspace.CurrentCamera

                local surfaceCF: CFrame = invisibleRuntime.surfacePosition or currentRoot.CFrame

                if invisibleSettings.fly and activeCam then
                    -- Fly mode: Move freely in 3D through the air with camera look
                    local flyVelocity: Vector3 = Vector3.zero
                    local camCF: CFrame = activeCam.CFrame
                    local look: Vector3 = camCF.LookVector
                    local right: Vector3 = camCF.RightVector

                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                        flyVelocity += look
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                        flyVelocity -= look
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                        flyVelocity += right
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                        flyVelocity -= right
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                        flyVelocity += Vector3.new(0, 1, 0)
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                        flyVelocity -= Vector3.new(0, 1, 0)
                    end

                    if flyVelocity.Magnitude > 0.05 then
                        local nextPos: Vector3 = surfaceCF.Position + (flyVelocity.Unit * (invisibleSettings.flySpeed * deltaTime))
                        local flatLook: Vector3 = Vector3.new(look.X, 0, look.Z)
                        if flatLook.Magnitude > 0.01 then
                            surfaceCF = CFrame.lookAt(nextPos, nextPos + flatLook.Unit)
                        else
                            surfaceCF = CFrame.new(nextPos) * surfaceCF.Rotation
                        end
                        invisibleRuntime.surfacePosition = surfaceCF
                    end
                else
                    -- Walk mode: move on ground using humanoid MoveDirection
                    local moveDir: Vector3 = currentHumanoid.MoveDirection
                    local walkSpeed: number = currentHumanoid.WalkSpeed
                    if moveDir.Magnitude > 0.05 then
                        local newPos: Vector3 = surfaceCF.Position + (moveDir.Unit * (walkSpeed * deltaTime))
                        local rayDown: RaycastResult? = currentWorkspace:Raycast(
                            newPos + Vector3.new(0, 3, 0),
                            Vector3.new(0, -12, 0)
                        )
                        if rayDown then
                            newPos = Vector3.new(newPos.X, rayDown.Position.Y + (currentHumanoid.HipHeight or 2), newPos.Z)
                        end
                        surfaceCF = CFrame.lookAt(newPos, newPos + moveDir)
                        invisibleRuntime.surfacePosition = surfaceCF
                    end
                end

                -- Position ghost root
                if activeGhostRoot and surfaceCF then
                    activeGhostRoot.CFrame = surfaceCF
                    -- Sync limbs relative to root
                    for _, child: Instance in ipairs(currentCharacter:GetChildren()) do
                        if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
                            local ghostPart: Instance? = activeGhost:FindFirstChild(child.Name)
                            if ghostPart and ghostPart:IsA("BasePart") then
                                local relCF: CFrame = currentRoot.CFrame:ToObjectSpace(child.CFrame)
                                local ghostBasePart: BasePart = ghostPart :: BasePart
                                ghostBasePart.CFrame = surfaceCF:ToWorldSpace(relCF)
                            end
                        end
                    end
                end

                -- Keep real character safely hidden in the void below the ghost position
                local voidPos: Vector3 = surfaceCF.Position - Vector3.new(0, invisibleSettings.voidDepth, 0)
                currentRoot.CFrame = CFrame.new(voidPos)
                currentRoot.AssemblyLinearVelocity = Vector3.zero
            end)
        )
    end

    local invisibleCard: any = framework.Categories.Blatant:CreateModule({
        Name = "Invisible",
        Category = "Blatant",
        Order = 8,
        Tooltip = "Shows your ghost on the map while your real character is hidden in the void. Turning it off teleports your real character to the ghost.",
        Function = toggleInvisible,
    })

    invisibleCard:CreateToggle({
        Name = "Ghost Fly",
        Default = invisibleSettings.fly,
        Function = function(value: boolean): ()
            invisibleSettings.fly = value
        end,
        Tooltip = "Fly freely across the map as a ghost using WASD, Space and Shift/Ctrl.",
    })

    invisibleCard:CreateSlider({
        Name = "Fly speed",
        Min = 16,
        Max = 200,
        Default = invisibleSettings.flySpeed,
        Function = function(value: number): ()
            invisibleSettings.flySpeed = value
        end,
        Tooltip = "Speed of the ghost while flying.",
    })

    invisibleCard:CreateSlider({
        Name = "Void depth",
        Min = 50,
        Max = 350,
        Default = invisibleSettings.voidDepth,
        Function = function(value: number): ()
            invisibleSettings.voidDepth = value
        end,
        Tooltip = "Studs below the ground your real character sits.",
    })

    invisibleCard:CreateSlider({
        Name = "Ghost transparency",
        Min = 0.1,
        Max = 0.9,
        Step = 0.05,
        Default = invisibleSettings.ghostTransparency,
        Function = function(value: number): ()
            invisibleSettings.ghostTransparency = value
            if invisibleRuntime.ghostModel then
                for _, desc: Instance in ipairs(invisibleRuntime.ghostModel:GetDescendants()) do
                    if desc:IsA("BasePart") then
                        desc.Transparency = value
                    end
                end
            end
        end,
        Tooltip = "Transparency of your local ghost representation.",
    })

    activeCleanup = function(): ()
        toggleInvisible(false)
    end
    Module.Initialized = true
    return invisibleCard
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
