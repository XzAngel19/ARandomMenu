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
    local RunService: RunService = host.RunService or (game :: any):GetService("RunService")
    local currentWorkspace: Workspace = host.workspace or workspace

    type InvisibleSettings = {
        voidDepth: number,
        ghostTransparency: number,
        cameraFollowGhost: boolean,
    }

    local invisibleSettings: InvisibleSettings = {
        voidDepth = 200,
        ghostTransparency = 0.5,
        cameraFollowGhost = true,
    }

    local invisibleRuntime = {
        active = false,
        ghostModel = nil :: Model?,
        surfacePosition = nil :: CFrame?,
        connections = {} :: {RBXScriptConnection},
        originalParts = {} :: {[BasePart]: boolean},
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

        -- Remove server scripts and physics constraints from ghost
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
        highlight.FillColor = Color3.fromRGB(130, 200, 255)
        highlight.OutlineColor = Color3.fromRGB(200, 240, 255)
        highlight.FillTransparency = 0.65
        highlight.OutlineTransparency = 0.2
        highlight.Adornee = ghost
        highlight.Parent = ghost

        local camera: Camera? = currentWorkspace.CurrentCamera
        ghost.Parent = camera or currentWorkspace
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

        if not enabled then
            if invisibleRuntime.active and root and invisibleRuntime.surfacePosition then
                -- Restore real character to surface position where the ghost walked
                root.CFrame = invisibleRuntime.surfacePosition
                root.AssemblyLinearVelocity = Vector3.zero
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
        if ghostRoot and invisibleRuntime.surfacePosition then
            ghostRoot.CFrame = invisibleRuntime.surfacePosition
        end

        -- Render loop: drive ghost visually on the ground while keeping the real character in the void
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
                end
                local activeGhostRoot: BasePart? = activeGhost and activeGhost:FindFirstChild("HumanoidRootPart") :: BasePart?

                -- Update surface position with humanoid move direction
                local moveDir: Vector3 = currentHumanoid.MoveDirection
                local walkSpeed: number = currentHumanoid.WalkSpeed
                local surfaceCF: CFrame = invisibleRuntime.surfacePosition or currentRoot.CFrame

                if moveDir.Magnitude > 0.05 then
                    local newPos: Vector3 = surfaceCF.Position + (moveDir.Unit * (walkSpeed * deltaTime))
                    -- Raycast down to keep ghost on ground
                    local rayDown: RaycastResult? = currentWorkspace:Raycast(
                        newPos + Vector3.new(0, 3, 0),
                        Vector3.new(0, -10, 0)
                    )
                    if rayDown then
                        newPos = Vector3.new(newPos.X, rayDown.Position.Y + (currentHumanoid.HipHeight or 2), newPos.Z)
                    end
                    local targetLook: Vector3 = newPos + moveDir
                    surfaceCF = CFrame.lookAt(newPos, targetLook)
                    invisibleRuntime.surfacePosition = surfaceCF
                end

                -- Sync ghost parts to surface
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

                -- Keep real character offset downward in the void so server/others cannot see or hit it
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
        Tooltip = "Makes your character a ghost on the map while your real character is in the void so nobody can see you.",
        Function = toggleInvisible,
    })

    invisibleCard:CreateSlider({
        Name = "Void depth",
        Min = 50,
        Max = 500,
        Default = invisibleSettings.voidDepth,
        Function = function(value: number): ()
            invisibleSettings.voidDepth = value
        end,
        Tooltip = "How far below the surface your real character is placed.",
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
