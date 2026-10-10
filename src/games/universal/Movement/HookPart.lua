--!strict
export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

type HookKind = "Ladder" | "Obstacle" | "Wall"

type HookSighting = {
    kind: HookKind,
    part: BasePart,
    normal: Vector3,
    direction: Vector3,
    distance: number,
    name: string,
    isWedge: boolean,
}

local Module = {
    Name = "HookPart",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

local SCAN_DIRECTIONS: number = 16
local SCAN_HEIGHTS: {number} = {-1.8, -0.6, 0.5, 1.5}

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local services: any = context.services
    local movementInput: any = services.movementInput
    local getCharacterParts: any = host.getCharacterParts
    local UserInputService: any = host.UserInputService or (game :: any):GetService("UserInputService")
    local RunService: RunService = host.RunService or (game :: any):GetService("RunService")
    local currentWorkspace: Workspace = host.workspace or workspace

    local lastHookJumpAt: number = -math.huge
    local lastScanAt: number = -math.huge
    local lastClimbAt: number = -math.huge
    local lastObstacleTouchAt: number = -math.huge
    local currentSighting: HookSighting? = nil
    local highlight: Highlight? = nil

    local settings = {
        ladderBoost = true,
        ladderJumpLength = 70,
        ladderJumpHeight = 65,
        obstacleBoost = true,
        obstaclePower = 90,
        selfFling = false,
        flingMultiplier = 1100,
        wallhopAssist = true,
        wallhopPower = 38,
        airborneWallhopOnly = true,
        requireStuckIntent = true,
        directionMode = "Camera",
        detectionRange = 2.4,
        checkAllParts = true,
        highlightObject = true,
    }

    local function destroyHighlight(): ()
        if highlight then
            pcall(function()
                highlight:Destroy()
            end)
            highlight = nil
        end
    end

    local function isLadderStructure(part: Instance): boolean
        if part:IsA("TrussPart") then
            return true
        end
        local current: Instance? = part
        for _ = 1, 3 do
            if not current then break end
            local lowerName: string = string.lower(current.Name)
            if string.find(lowerName, "ladder") ~= nil
                or string.find(lowerName, "truss") ~= nil
                or string.find(lowerName, "escalera") ~= nil
                or string.find(lowerName, "climb") ~= nil then
                return true
            end
            current = current.Parent
        end
        return false
    end

    local function isSmallDecoration(part: BasePart): boolean
        -- Filter out tiny fence posts, thin railings, or miniature props that shouldn't hijack ground jumps
        local sz: Vector3 = part.Size
        if (sz.X <= 0.9 and sz.Z <= 0.9) or (sz.X <= 0.5 and sz.Y <= 0.5) then
            return true
        end
        return false
    end

    local function scanSurroundings(
        character: Model,
        humanoid: Humanoid,
        root: BasePart
    ): HookSighting?
        local now: number = os.clock()
        local state: Enum.HumanoidStateType = humanoid:GetState()
        local isCurrentlyClimbing: boolean = state == Enum.HumanoidStateType.Climbing
        if isCurrentlyClimbing then
            lastClimbAt = now
        end

        local isGrounded: boolean = humanoid.FloorMaterial ~= Enum.Material.Air
        local moveDir: Vector3 = humanoid.MoveDirection
        local horizVelocity: number = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude

        local filter: {Instance} = {character}
        local ghost: Instance? = currentWorkspace:FindFirstChild("Wurst_Ghost")
        if ghost then
            table.insert(filter, ghost)
        end

        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances = filter
        parameters.IgnoreWater = true
        parameters.RespectCanCollide = true

        -- Priority 1: Ladder detection (Roblox climbing state or 200ms grace window)
        local climbingGrace: boolean = (now - lastClimbAt) <= 0.22
        if isCurrentlyClimbing or climbingGrace then
            -- Raycast forward to find the ladder part or normal
            local forwardRay: RaycastResult? = currentWorkspace:Raycast(
                root.Position,
                root.CFrame.LookVector * 3.0,
                parameters
            )
            local ladderPart: BasePart = (forwardRay and forwardRay.Instance:IsA("BasePart") and forwardRay.Instance) or root
            local ladderNorm: Vector3 = (forwardRay and forwardRay.Normal) or -root.CFrame.LookVector

            return {
                kind = "Ladder",
                part = ladderPart,
                normal = ladderNorm,
                direction = root.CFrame.LookVector,
                distance = forwardRay and forwardRay.Distance or 1.2,
                name = ladderPart.Name ~= root.Name and ladderPart.Name or "Ladder",
                isWedge = false,
            }
        end

        local bestSighting: HookSighting? = nil
        local bestDistance: number = settings.detectionRange + 1

        -- Priority 2: Check box in front of player for ladders / trusses (to not miss rung gaps)
        local overlapLadder: OverlapParams = OverlapParams.new()
        overlapLadder.FilterType = Enum.RaycastFilterType.Exclude
        overlapLadder.FilterDescendantsInstances = filter
        overlapLadder.MaxParts = 6

        local frontBoxCF: CFrame = root.CFrame * CFrame.new(0, 0, -1.3)
        local nearbyTrusses: {BasePart} = {}
        pcall(function()
            nearbyTrusses = currentWorkspace:GetPartBoundsInBox(frontBoxCF, Vector3.new(2.4, 4.0, 2.0), overlapLadder)
        end)
        for _, part: BasePart in ipairs(nearbyTrusses) do
            if part.CanCollide and isLadderStructure(part) then
                return {
                    kind = "Ladder",
                    part = part,
                    normal = -root.CFrame.LookVector,
                    direction = root.CFrame.LookVector,
                    distance = (part.Position - root.Position).Magnitude,
                    name = part.Name,
                    isWedge = false,
                }
            end
        end

        -- Priority 3: Scan surroundings for Obstacles (Tank, Crates, Props) and Walls
        for i: number = 0, SCAN_DIRECTIONS - 1 do
            local angle: number = (i / SCAN_DIRECTIONS) * math.pi * 2
            local direction: Vector3 = Vector3.new(math.sin(angle), 0, math.cos(angle))

            for _, heightOffset: number in ipairs(SCAN_HEIGHTS) do
                local origin: Vector3 = root.Position + Vector3.new(0, heightOffset, 0)
                local hit: RaycastResult? = currentWorkspace:Raycast(
                    origin,
                    direction * settings.detectionRange,
                    parameters
                )

                if hit and hit.Instance and hit.Instance:IsA("BasePart") then
                    local part: BasePart = hit.Instance
                    if part.CanCollide then
                        local dist: number = hit.Distance
                        local norm: Vector3 = hit.Normal
                        local isLadder: boolean = isLadderStructure(part)

                        if isLadder then
                            return {
                                kind = "Ladder",
                                part = part,
                                normal = norm,
                                direction = direction,
                                distance = dist,
                                name = part.Name,
                                isWedge = false,
                            }
                        end

                        local partNameLower: string = string.lower(part.Name)
                        local isKnownObstacle: boolean = string.find(partNameLower, "tank") ~= nil
                            or string.find(partNameLower, "crate") ~= nil
                            or string.find(partNameLower, "box") ~= nil
                            or string.find(partNameLower, "prop") ~= nil
                            or string.find(partNameLower, "vehicle") ~= nil
                            or string.find(partNameLower, "barrel") ~= nil
                            or string.find(partNameLower, "wheel") ~= nil
                            or math.abs(norm.Y) > 0.40

                        local isSmall: boolean = isSmallDecoration(part)

                        -- Ground bypass: On the ground, ignore tiny fence posts or random decorative walls
                        -- unless player is deliberately pushing into an obstacle/tank!
                        if isGrounded then
                            if isSmall and not isKnownObstacle then
                                -- Skip small fence posts while grounded (solves Image 2!)
                                continue
                            end

                            if settings.requireStuckIntent then
                                -- Check if player is pressing into the obstacle
                                local pushingIntoPart: boolean = moveDir.Magnitude > 0.1 and moveDir:Dot(direction) > 0.30
                                local isStuckMoving: boolean = moveDir.Magnitude > 0.1 and horizVelocity < 3.0
                                if not (pushingIntoPart or isStuckMoving or isKnownObstacle) then
                                    continue
                                end
                            end
                        else
                            -- Airborne: Allow wallhop or obstacle vaulting
                            if settings.airborneWallhopOnly and not isKnownObstacle and isSmall then
                                continue
                            end
                        end

                        local kind: HookKind = isKnownObstacle and "Obstacle" or "Wall"

                        if dist < bestDistance then
                            bestDistance = dist
                            bestSighting = {
                                kind = kind,
                                part = part,
                                normal = norm,
                                direction = direction,
                                distance = dist,
                                name = part.Name,
                                isWedge = isKnownObstacle,
                            }
                        end
                    end
                end
            end
        end

        -- Priority 4: Spatial Query for wedged/hooked character parts (e.g. inside MM2 tank collision)
        if settings.checkAllParts and (not bestSighting or bestDistance > 1.8) then
            local overlap: OverlapParams = OverlapParams.new()
            overlap.FilterType = Enum.RaycastFilterType.Exclude
            overlap.FilterDescendantsInstances = filter
            overlap.MaxParts = 6
            overlap.RespectCanCollide = true

            local nearbyParts: {BasePart} = {}
            pcall(function()
                nearbyParts = currentWorkspace:GetPartBoundsInBox(root.CFrame, Vector3.new(3.2, 4.5, 3.2), overlap)
            end)

            for _, part: BasePart in ipairs(nearbyParts) do
                if part.CanCollide and part ~= root then
                    local isLadder: boolean = isLadderStructure(part)
                    if isLadder then
                        return {
                            kind = "Ladder",
                            part = part,
                            normal = -root.CFrame.LookVector,
                            direction = root.CFrame.LookVector,
                            distance = 1.0,
                            name = part.Name,
                            isWedge = false,
                        }
                    end

                    if not isSmallDecoration(part) then
                        local offset: Vector3 = part.Position - root.Position
                        local dist: number = offset.Magnitude
                        local normVec: Vector3 = offset.Magnitude > 0.01 and -offset.Unit or -root.CFrame.LookVector

                        if dist < bestDistance then
                            bestDistance = dist
                            bestSighting = {
                                kind = "Obstacle",
                                part = part,
                                normal = normVec,
                                direction = offset.Magnitude > 0.01 and offset.Unit or root.CFrame.LookVector,
                                distance = dist,
                                name = part.Name,
                                isWedge = true,
                            }
                        end
                    end
                end
            end
        end

        return bestSighting
    end

    local function getLaunchDirection(root: BasePart, humanoid: Humanoid, sighting: HookSighting): Vector3
        local cam: Camera? = currentWorkspace.CurrentCamera
        local mode: string = settings.directionMode

        if sighting.kind == "Ladder" then
            -- On a ladder, launch outward from the wall and upward in the camera view
            if cam then
                local camLook: Vector3 = cam.CFrame.LookVector
                return Vector3.new(camLook.X, math.max(camLook.Y, 0.4), camLook.Z).Unit
            end
            local outward: Vector3 = sighting.normal
            if outward.Magnitude > 0.1 then
                return Vector3.new(outward.X, 0.5, outward.Z).Unit
            end
            return Vector3.new(0, 1, 0)
        end

        if mode == "Camera" and cam then
            return cam.CFrame.LookVector
        elseif mode == "Movement" then
            local moveDir: Vector3 = humanoid.MoveDirection
            if moveDir.Magnitude > 0.1 then
                return moveDir.Unit
            end
            if cam then
                return cam.CFrame.LookVector
            end
            return root.CFrame.LookVector
        elseif mode == "Normal" then
            local norm: Vector3 = sighting.normal
            if norm.Magnitude > 0.1 then
                return norm.Unit
            end
        elseif mode == "Upward" then
            return Vector3.new(0, 1, 0)
        end

        if cam then
            return cam.CFrame.LookVector
        end
        return root.CFrame.LookVector
    end

    local function applySustainedImpulse(root: BasePart, targetVel: Vector3, durationSeconds: number): ()
        -- Apply over multiple frames (within the 200ms server rewind window) so Roblox internal friction/ladder code
        -- doesn't cancel or override the velocity immediately!
        local startTime: number = os.clock()
        local connection: RBXScriptConnection? = nil
        connection = RunService.Heartbeat:Connect(function(): ()
            if not root or not root.Parent or (os.clock() - startTime) >= durationSeconds then
                if connection then
                    connection:Disconnect()
                    connection = nil
                end
                return
            end
            root.AssemblyLinearVelocity = targetVel
        end)
    end

    local function executeHookJump(): ()
        local now: number = os.clock()
        if now - lastHookJumpAt < 0.20 then
            return
        end

        local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not character or not humanoid or not root or humanoid.Health <= 0 then
            return
        end

        local sighting: HookSighting? = currentSighting or scanSurroundings(character, humanoid, root)
        if not sighting then
            return
        end

        local isGrounded: boolean = humanoid.FloorMaterial ~= Enum.Material.Air

        -- Bypass check: If grounded on flat grass/floor and the sighting is just a casual Wall (not ladder or obstacle),
        -- allow a normal clean Roblox jump without hijacking or deviating!
        if isGrounded and sighting.kind == "Wall" and settings.airborneWallhopOnly then
            return
        end

        lastHookJumpAt = now
        local launchDir: Vector3 = getLaunchDirection(root, humanoid, sighting)
        local flatLaunchDir: Vector3 = Vector3.new(launchDir.X, 0, launchDir.Z)
        if flatLaunchDir.Magnitude > 0.01 then
            flatLaunchDir = flatLaunchDir.Unit
        else
            flatLaunchDir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
        end

        local currentVel: Vector3 = root.AssemblyLinearVelocity

        if sighting.kind == "Ladder" then
            if not settings.ladderBoost then
                return
            end

            -- Clean detach from ladder: switch to Jumping
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

            local horizSpeed: number = settings.ladderJumpLength
            local vertSpeed: number = settings.ladderJumpHeight
            local ladderVel: Vector3 = Vector3.new(
                flatLaunchDir.X * horizSpeed,
                vertSpeed,
                flatLaunchDir.Z * horizSpeed
            )

            root.AssemblyLinearVelocity = ladderVel
            -- Reinforce over 0.08s (5 frames) to defeat Roblox's ladder detach clamp
            applySustainedImpulse(root, ladderVel, 0.08)

            if activeCard then
                activeCard:SetStatus("Ladder Leap!")
            end

        elseif sighting.kind == "Obstacle" then
            if not settings.obstacleBoost then
                return
            end

            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

            if settings.selfFling then
                local flingSpeed: number = settings.flingMultiplier
                local flingVec: Vector3 = Vector3.new(
                    flatLaunchDir.X * flingSpeed,
                    flingSpeed * 0.40,
                    flatLaunchDir.Z * flingSpeed
                )
                root.AssemblyLinearVelocity = flingVec
                applySustainedImpulse(root, flingVec, 0.09)
                if activeCard then
                    activeCard:SetStatus("SELF FLING!")
                end
            else
                local boostPower: number = settings.obstaclePower
                local outwardNorm: Vector3 = sighting.normal
                local combinedDir: Vector3 = (flatLaunchDir * 0.75 + Vector3.new(outwardNorm.X, 0, outwardNorm.Z) * 0.25)
                if combinedDir.Magnitude > 0.01 then
                    combinedDir = combinedDir.Unit
                else
                    combinedDir = flatLaunchDir
                end

                local obstacleVel: Vector3 = Vector3.new(
                    combinedDir.X * boostPower,
                    math.max(currentVel.Y + 22, boostPower * 0.70),
                    combinedDir.Z * boostPower
                )
                root.AssemblyLinearVelocity = obstacleVel
                applySustainedImpulse(root, obstacleVel, 0.06)
                if activeCard then
                    activeCard:SetStatus("Obstacle Boost!")
                end
            end

        elseif sighting.kind == "Wall" then
            if not settings.wallhopAssist then
                return
            end

            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

            local kick: number = settings.wallhopPower
            local norm: Vector3 = sighting.normal
            local kickHoriz: Vector3 = Vector3.new(norm.X, 0, norm.Z)
            if kickHoriz.Magnitude > 0.01 then
                kickHoriz = kickHoriz.Unit
            else
                kickHoriz = -flatLaunchDir
            end

            local wallVel: Vector3 = Vector3.new(
                currentVel.X * 0.25 + kickHoriz.X * kick + flatLaunchDir.X * (kick * 0.45),
                math.max(currentVel.Y, 54),
                currentVel.Z * 0.25 + kickHoriz.Z * kick + flatLaunchDir.Z * (kick * 0.45)
            )
            root.AssemblyLinearVelocity = wallVel
            if activeCard then
                activeCard:SetStatus("Wallhop!")
            end
        end
    end

    local card: any
    card = framework.Categories.Movement:CreateModule({
        Name = "HookPart",
        Category = "Movement",
        ConfigKey = "Universal.HookPart",
        Order = 32,
        Tooltip = "Amplify jumps off ladders, get unstuck from obstacles (like MM2 tanks & crates) with custom boost or self-fling, and wallhop off any part.",
        Function = function(enabled: boolean): ()
            destroyHighlight()
            currentSighting = nil
            lastHookJumpAt = -math.huge
            lastClimbAt = -math.huge

            if not enabled then
                card:SetStatus(nil)
                return
            end
            card:SetStatus("Active")

            -- Connect jump hooks
            if movementInput and type(movementInput.onJumpRequest) == "function" then
                card:Clean(movementInput.onJumpRequest(function(): ()
                    executeHookJump()
                end))
            end

            if UserInputService and UserInputService.JumpRequest then
                card:Clean(UserInputService.JumpRequest:Connect(function(): ()
                    executeHookJump()
                end))
            end

            -- Track humanoid state changes (especially Climbing for the 200ms grace window)
            local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if humanoid then
                card:Clean(humanoid.StateChanged:Connect(function(oldState: Enum.HumanoidStateType, newState: Enum.HumanoidStateType): ()
                    if newState == Enum.HumanoidStateType.Climbing or oldState == Enum.HumanoidStateType.Climbing then
                        lastClimbAt = os.clock()
                    end
                end))
            end

            -- Continuous detection loop
            card:Loop(function(): ()
                local now: number = os.clock()
                if now - lastScanAt < 0.05 then
                    return
                end
                lastScanAt = now

                local curChar: Model?, curHum: Humanoid?, curRoot: BasePart? = getCharacterParts()
                if not curChar or not curHum or not curRoot or curHum.Health <= 0 then
                    destroyHighlight()
                    currentSighting = nil
                    return
                end

                if curHum:GetState() == Enum.HumanoidStateType.Climbing then
                    lastClimbAt = now
                end

                local sighting: HookSighting? = scanSurroundings(curChar, curHum, curRoot)
                currentSighting = sighting

                if not sighting then
                    destroyHighlight()
                    card:SetStatus("Ready")
                    return
                end

                local statusText: string = sighting.kind .. ": " .. sighting.name
                if settings.selfFling and sighting.kind == "Obstacle" then
                    statusText = "Fling Ready: " .. sighting.name
                end
                card:SetStatus(statusText)

                -- Visual highlight of hooked object
                if not settings.highlightObject or sighting.part == curRoot then
                    destroyHighlight()
                    return
                end

                if not highlight or not highlight.Parent then
                    highlight = Instance.new("Highlight")
                    highlight.Name = "Wurst_HookPart_Highlight"
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Parent = currentWorkspace
                end

                if sighting.kind == "Ladder" then
                    highlight.FillColor = Color3.fromRGB(80, 220, 255)
                    highlight.OutlineColor = Color3.fromRGB(150, 240, 255)
                elseif sighting.kind == "Obstacle" then
                    if settings.selfFling then
                        highlight.FillColor = Color3.fromRGB(255, 60, 60)
                        highlight.OutlineColor = Color3.fromRGB(255, 120, 120)
                    else
                        highlight.FillColor = Color3.fromRGB(255, 180, 50)
                        highlight.OutlineColor = Color3.fromRGB(255, 220, 100)
                    end
                else
                    highlight.FillColor = Color3.fromRGB(60, 255, 140)
                    highlight.OutlineColor = Color3.fromRGB(120, 255, 180)
                end
                highlight.FillTransparency = 0.70
                highlight.OutlineTransparency = 0.15
                highlight.Adornee = sighting.part
            end)
        end,
    })

    card:CreateToggle({
        Name = "Ladder Boost",
        Default = settings.ladderBoost,
        Function = function(value: boolean): ()
            settings.ladderBoost = value
        end,
        Tooltip = "Makes jumps off ladders and trusses significantly longer and higher.",
    })

    card:CreateSlider({
        Name = "Ladder Jump Length",
        Min = 20,
        Max = 200,
        Default = settings.ladderJumpLength,
        Step = 5,
        Function = function(value: number): ()
            settings.ladderJumpLength = value
        end,
        Tooltip = "Forward velocity impulse when jumping off a ladder.",
    })

    card:CreateSlider({
        Name = "Ladder Jump Height",
        Min = 20,
        Max = 150,
        Default = settings.ladderJumpHeight,
        Step = 5,
        Function = function(value: number): ()
            settings.ladderJumpHeight = value
        end,
        Tooltip = "Upward vertical impulse when leaping from a ladder.",
    })

    card:CreateToggle({
        Name = "Obstacle Boost",
        Default = settings.obstacleBoost,
        Function = function(value: boolean): ()
            settings.obstacleBoost = value
        end,
        Tooltip = "Gives a strong impulse when wedged or jumping against obstacles, tanks, and crates.",
    })

    card:CreateSlider({
        Name = "Obstacle Power",
        Min = 25,
        Max = 300,
        Default = settings.obstaclePower,
        Step = 5,
        Function = function(value: number): ()
            settings.obstaclePower = value
        end,
        Tooltip = "Power of the jump boost when hooked on an obstacle or tank.",
    })

    card:CreateToggle({
        Name = "Self Fling",
        Default = settings.selfFling,
        Function = function(value: boolean): ()
            settings.selfFling = value
        end,
        Tooltip = "Turns obstacle jump into a massive self-fling to launch yourself across the map.",
    })

    card:CreateSlider({
        Name = "Fling Multiplier",
        Min = 200,
        Max = 3500,
        Default = settings.flingMultiplier,
        Step = 50,
        Function = function(value: number): ()
            settings.flingMultiplier = value
        end,
        Tooltip = "Velocity magnitude applied when triggering a self-fling.",
    })

    card:CreateToggle({
        Name = "Wallhop Assist",
        Default = settings.wallhopAssist,
        Function = function(value: boolean): ()
            settings.wallhopAssist = value
        end,
        Tooltip = "Allows resetting jump and leaping off any wall surface.",
    })

    card:CreateSlider({
        Name = "Wallhop Power",
        Min = 15,
        Max = 100,
        Default = settings.wallhopPower,
        Step = 5,
        Function = function(value: number): ()
            settings.wallhopPower = value
        end,
        Tooltip = "Impulse applied when performing a wallhop.",
    })

    card:CreateToggle({
        Name = "Airborne Wallhop Only",
        Default = settings.airborneWallhopOnly,
        Function = function(value: boolean): ()
            settings.airborneWallhopOnly = value
        end,
        Tooltip = "Only triggers wallhop when already in mid-air, preventing strange jumps on the ground next to fences.",
    })

    card:CreateToggle({
        Name = "Require Stuck Intent",
        Default = settings.requireStuckIntent,
        Function = function(value: boolean): ()
            settings.requireStuckIntent = value
        end,
        Tooltip = "Only activates obstacle boost when moving towards the object or wedged against it.",
    })

    card:CreateDropdown({
        Name = "Direction Mode",
        List = {"Camera", "Movement", "Normal", "Upward"},
        Index = 1,
        Function = function(value: string): ()
            settings.directionMode = value
        end,
        Tooltip = "Determines the direction in which boost / fling impulse is applied.",
    })

    card:CreateSlider({
        Name = "Detection Range",
        Min = 1.5,
        Max = 5.0,
        Default = settings.detectionRange,
        Step = 0.1,
        Function = function(value: number): ()
            settings.detectionRange = value
        end,
        Tooltip = "Distance around the player to scan for hooked parts, ladders, and walls.",
    })

    card:CreateToggle({
        Name = "Check All Parts",
        Default = settings.checkAllParts,
        Function = function(value: boolean): ()
            settings.checkAllParts = value
        end,
        Tooltip = "Deep spatial collision check (raycasts + box overlap) for tanks, crates, and geometry.",
    })

    card:CreateToggle({
        Name = "Highlight Object",
        Default = settings.highlightObject,
        Function = function(value: boolean): ()
            settings.highlightObject = value
        end,
        Tooltip = "Outlines the part, ladder, or obstacle you are hooked to.",
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        pcall(activeCard.Toggle, false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
