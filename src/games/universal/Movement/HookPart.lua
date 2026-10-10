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
}

local Module = {
    Name = "HookPart",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

local SCAN_DIRECTIONS: number = 16
local SCAN_HEIGHTS: {number} = {-2.1, -0.5, 0.8, 1.8}

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local services: any = context.services
    local movementInput: any = services.movementInput
    local getCharacterParts: any = host.getCharacterParts
    local UserInputService: any = host.UserInputService or (game :: any):GetService("UserInputService")
    local currentWorkspace: Workspace = host.workspace or workspace

    local lastHookJumpAt: number = -math.huge
    local lastScanAt: number = -math.huge
    local currentSighting: HookSighting? = nil
    local highlight: Highlight? = nil

    local settings = {
        ladderBoost = true,
        ladderJumpLength = 65,
        ladderJumpHeight = 60,
        obstacleBoost = true,
        obstaclePower = 85,
        selfFling = false,
        flingMultiplier = 950,
        wallhopAssist = true,
        wallhopPower = 35,
        directionMode = "Camera",
        detectionRange = 3.5,
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

    local function isLadderPart(part: BasePart): boolean
        if part:IsA("TrussPart") then
            return true
        end
        local lowerName: string = string.lower(part.Name)
        return string.find(lowerName, "ladder") ~= nil
            or string.find(lowerName, "truss") ~= nil
            or string.find(lowerName, "escalera") ~= nil
    end

    local function scanSurroundings(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        range: number
    ): HookSighting?
        local isClimbing: boolean = humanoid:GetState() == Enum.HumanoidStateType.Climbing

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

        local bestSighting: HookSighting? = nil
        local bestDistance: number = range + 1

        -- 1. Horizontal and angled raycasts around the character
        for i: number = 0, SCAN_DIRECTIONS - 1 do
            local angle: number = (i / SCAN_DIRECTIONS) * math.pi * 2
            local direction: Vector3 = Vector3.new(math.sin(angle), 0, math.cos(angle))

            for _, heightOffset: number in ipairs(SCAN_HEIGHTS) do
                local origin: Vector3 = root.Position + Vector3.new(0, heightOffset, 0)
                local hit: RaycastResult? = currentWorkspace:Raycast(
                    origin,
                    direction * range,
                    parameters
                )

                if hit and hit.Instance and hit.Instance:IsA("BasePart") then
                    local part: BasePart = hit.Instance
                    if part.CanCollide then
                        local dist: number = hit.Distance
                        local norm: Vector3 = hit.Normal
                        local isLadder: boolean = isClimbing or isLadderPart(part)
                        local kind: HookKind = "Wall"

                        if isLadder then
                            kind = "Ladder"
                        elseif math.abs(norm.Y) > 0.45 then
                            -- Stepped slope, tank tread, crate top corner, wedged geometry
                            kind = "Obstacle"
                        else
                            local partNameLower: string = string.lower(part.Name)
                            if string.find(partNameLower, "tank")
                                or string.find(partNameLower, "crate")
                                or string.find(partNameLower, "box")
                                or string.find(partNameLower, "prop")
                                or string.find(partNameLower, "car")
                                or string.find(partNameLower, "vehicle")
                                or string.find(partNameLower, "barrel")
                                or string.find(partNameLower, "wheel") then
                                kind = "Obstacle"
                            else
                                kind = "Wall"
                            end
                        end

                        if dist < bestDistance then
                            bestDistance = dist
                            bestSighting = {
                                kind = kind,
                                part = part,
                                normal = norm,
                                direction = direction,
                                distance = dist,
                                name = part.Name,
                            }
                        end
                    end
                end
            end
        end

        -- 2. Spatial Query for hooked/wedged parts (e.g. stuck inside or against tank collision hull)
        if settings.checkAllParts and (not bestSighting or bestDistance > 1.8) then
            local overlap: OverlapParams = OverlapParams.new()
            overlap.FilterType = Enum.RaycastFilterType.Exclude
            overlap.FilterDescendantsInstances = filter
            overlap.MaxParts = 8
            overlap.RespectCanCollide = true

            local boxSize: Vector3 = Vector3.new(range * 1.5, 4.5, range * 1.5)
            local nearbyParts: {BasePart} = {}
            local getBoundsOk: boolean = pcall(function()
                nearbyParts = currentWorkspace:GetPartBoundsInBox(root.CFrame, boxSize, overlap)
            end)
            if not getBoundsOk or #nearbyParts == 0 then
                pcall(function()
                    nearbyParts = currentWorkspace:GetPartsInPart(root, overlap)
                end)
            end

            for _, part: BasePart in ipairs(nearbyParts) do
                if part.CanCollide and part ~= root then
                    local offset: Vector3 = part.Position - root.Position
                    local dist: number = offset.Magnitude
                    local isLadder: boolean = isClimbing or isLadderPart(part)
                    local kind: HookKind = isLadder and "Ladder" or "Obstacle"

                    if dist < bestDistance then
                        bestDistance = dist
                        local normalVec: Vector3 = offset.Magnitude > 0.01 and -offset.Unit or -root.CFrame.LookVector
                        bestSighting = {
                            kind = kind,
                            part = part,
                            normal = normalVec,
                            direction = offset.Magnitude > 0.01 and offset.Unit or root.CFrame.LookVector,
                            distance = dist,
                            name = part.Name,
                        }
                    end
                end
            end
        end

        if isClimbing and not bestSighting then
            -- Climbing without specific part hit
            bestSighting = {
                kind = "Ladder",
                part = root,
                normal = -root.CFrame.LookVector,
                direction = root.CFrame.LookVector,
                distance = 1.0,
                name = "Ladder",
            }
        end

        return bestSighting
    end

    local function getLaunchDirection(root: BasePart, humanoid: Humanoid, sighting: HookSighting?): Vector3
        local cam: Camera? = currentWorkspace.CurrentCamera
        local mode: string = settings.directionMode

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
        elseif mode == "Normal" and sighting then
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

    local function executeHookJump(): ()
        local now: number = os.clock()
        if now - lastHookJumpAt < 0.22 then
            return
        end

        local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not character or not humanoid or not root or humanoid.Health <= 0 then
            return
        end

        local sighting: HookSighting? = currentSighting
            or scanSurroundings(character, humanoid, root, settings.detectionRange)
        if not sighting then
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
            -- Long & High jump off ladder
            local horizSpeed: number = settings.ladderJumpLength
            local vertSpeed: number = settings.ladderJumpHeight
            root.AssemblyLinearVelocity = Vector3.new(
                flatLaunchDir.X * horizSpeed,
                math.max(currentVel.Y, vertSpeed),
                flatLaunchDir.Z * horizSpeed
            )
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            if activeCard then
                activeCard:SetStatus("Ladder Jump!")
            end

        elseif sighting.kind == "Obstacle" then
            if not settings.obstacleBoost then
                return
            end

            if settings.selfFling then
                -- Extreme velocity self-fling out of obstacles/tank
                local flingSpeed: number = settings.flingMultiplier
                local flingVec: Vector3 = Vector3.new(
                    flatLaunchDir.X * flingSpeed,
                    flingSpeed * 0.45,
                    flatLaunchDir.Z * flingSpeed
                )
                root.AssemblyLinearVelocity = flingVec
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                if activeCard then
                    activeCard:SetStatus("SELF FLING!")
                end
            else
                -- High obstacle boost to easily vault over tanks/crates
                local boostPower: number = settings.obstaclePower
                local outwardNorm: Vector3 = sighting.normal
                local combinedDir: Vector3 = (flatLaunchDir * 0.7 + Vector3.new(outwardNorm.X, 0, outwardNorm.Z) * 0.3)
                if combinedDir.Magnitude > 0.01 then
                    combinedDir = combinedDir.Unit
                else
                    combinedDir = flatLaunchDir
                end

                root.AssemblyLinearVelocity = Vector3.new(
                    combinedDir.X * boostPower,
                    math.max(currentVel.Y + 15, boostPower * 0.65),
                    combinedDir.Z * boostPower
                )
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                if activeCard then
                    activeCard:SetStatus("Obstacle Boost!")
                end
            end

        elseif sighting.kind == "Wall" then
            if not settings.wallhopAssist then
                return
            end

            -- Wallhop assist
            local kick: number = settings.wallhopPower
            local norm: Vector3 = sighting.normal
            local kickHoriz: Vector3 = Vector3.new(norm.X, 0, norm.Z)
            if kickHoriz.Magnitude > 0.01 then
                kickHoriz = kickHoriz.Unit
            else
                kickHoriz = -flatLaunchDir
            end

            root.AssemblyLinearVelocity = Vector3.new(
                currentVel.X * 0.3 + kickHoriz.X * kick + flatLaunchDir.X * (kick * 0.4),
                math.max(currentVel.Y, 52),
                currentVel.Z * 0.3 + kickHoriz.Z * kick + flatLaunchDir.Z * (kick * 0.4)
            )
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
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

            -- Continuous detection loop
            card:Loop(function(): ()
                local now: number = os.clock()
                if now - lastScanAt < 0.06 then
                    return
                end
                lastScanAt = now

                local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
                if not character or not humanoid or not root or humanoid.Health <= 0 then
                    destroyHighlight()
                    currentSighting = nil
                    return
                end

                local sighting: HookSighting? = scanSurroundings(
                    character,
                    humanoid,
                    root,
                    settings.detectionRange
                )
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
                if not settings.highlightObject or sighting.part == root then
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
                highlight.FillTransparency = 0.72
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
        Max = 6.0,
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
