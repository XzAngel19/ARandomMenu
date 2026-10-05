export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

type WallSighting = {
    part: BasePart,
    normal: Vector3,
    direction: Vector3,
    distance: number,
}

local Module = {
    Name = "WallHop",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

local SCAN_DIRECTIONS: number = 8
local SCAN_HEIGHTS: {number} = {-2.35, 0.2, 1.2}
local ARROWS: {string} = {"↑", "↗", "→", "↘", "↓", "↙", "←", "↖"}

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local movementInput: any = context.services.movementInput
    local getCharacterParts: any = host.getCharacterParts
    local currentWorkspace: Workspace = host.workspace or workspace
    local lastHopAt: number = -math.huge
    local lastScanAt: number = -math.huge
    local nearestWall: WallSighting? = nil
    local highlight: Highlight? = nil

    local function destroyHighlight(): ()
        if highlight then
            highlight:Destroy()
            highlight = nil
        end
    end

    local function findWall(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        range: number
    ): WallSighting?
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.FilterDescendantsInstances = {character}
        parameters.IgnoreWater = true
        parameters.RespectCanCollide = true

        local best: WallSighting? = nil
        for directionIndex: number = 0, SCAN_DIRECTIONS - 1 do
            local angle: number = (directionIndex / SCAN_DIRECTIONS) * math.pi * 2
            local direction: Vector3 = Vector3.new(
                math.sin(angle),
                0,
                math.cos(angle)
            )
            for _, height: number in ipairs(SCAN_HEIGHTS) do
                local origin: Vector3 = root.Position + Vector3.new(0, height, 0)
                local hit: RaycastResult? = currentWorkspace:Raycast(
                    origin,
                    direction * range,
                    parameters
                )
                if hit
                    and hit.Instance
                    and hit.Instance:IsA("BasePart")
                    and math.abs(hit.Normal.Y) <= 0.35 then
                    if best == nil or hit.Distance < best.distance then
                        best = {
                            part = hit.Instance,
                            normal = Vector3.new(
                                hit.Normal.X,
                                0,
                                hit.Normal.Z
                            ),
                            direction = direction,
                            distance = hit.Distance,
                        }
                    end
                    break
                end
            end
        end
        if best and best.normal.Magnitude > 0.01 then
            best.normal = best.normal.Unit
        else
            best = nil
        end
        return best
    end

    local function wallArrow(root: BasePart, sighting: WallSighting): string
        local flatLook: Vector3 = Vector3.new(
            root.CFrame.LookVector.X,
            0,
            root.CFrame.LookVector.Z
        )
        if flatLook.Magnitude < 0.01 then
            return "↑"
        end
        flatLook = flatLook.Unit
        local flatDirection: Vector3 = sighting.direction
        local angle: number = math.atan2(
            flatLook:Cross(flatDirection).Y,
            flatLook:Dot(flatDirection)
        )
        local index: number = math.floor(
            (angle / (math.pi * 2)) * SCAN_DIRECTIONS + 0.5
        ) % SCAN_DIRECTIONS
        -- Arrows are listed clockwise starting at forward; atan2 grows
        -- counter-clockwise, so mirror the index.
        index = (SCAN_DIRECTIONS - index) % SCAN_DIRECTIONS + 1
        return ARROWS[index]
    end

    local card: any
    local function clearVisuals(): ()
        nearestWall = nil
        destroyHighlight()
    end

    card = framework.Categories.Blatant:CreateModule({
        Name = "WallHop",
        Category = "Blatant",
        ConfigKey = "Universal.WallHop",
        Order = 31,
        Tooltip = "Detect walls and thin ledges around you and wall hop off "
            .. "them with one realistic jump.",
        Function = function(enabled: boolean): ()
            clearVisuals()
            lastHopAt = -math.huge
            if not enabled then
                card:SetStatus(nil)
                return
            end
            card:SetStatus("ready")

            card:Clean(movementInput.onJumpRequest(function(): ()
                local now: number = os.clock()
                if now - lastHopAt < 0.3 then
                    return
                end
                local character: Model?, humanoid: Humanoid?, root: BasePart? =
                    getCharacterParts()
                if not character or not humanoid or not root
                    or humanoid.Health <= 0
                    or humanoid.FloorMaterial == Enum.Material.Air then
                    return
                end

                local range: number = tonumber(card.Options["Wall range"].Value) or 2.6
                local kick: number = tonumber(card.Options["Kick strength"].Value) or 14
                local sighting: WallSighting? = findWall(character, humanoid, root, range)
                if not sighting then
                    return
                end

                lastHopAt = now
                local jumpVelocity: number = 50
                if humanoid.UseJumpPower then
                    jumpVelocity = math.max(humanoid.JumpPower, 16)
                elseif humanoid.JumpHeight > 0 then
                    jumpVelocity = math.sqrt(
                        2 * currentWorkspace.Gravity * humanoid.JumpHeight
                    )
                end
                local velocity: Vector3 = root.AssemblyLinearVelocity
                -- One clean impulse: kick away from the wall plus a natural
                -- jump arc. No teleports, no chained boosts.
                root.AssemblyLinearVelocity = Vector3.new(
                    velocity.X * 0.35 + sighting.normal.X * kick,
                    math.max(velocity.Y, jumpVelocity + 3),
                    velocity.Z * 0.35 + sighting.normal.Z * kick
                )
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                card:SetStatus("hop")
            end))

            card:Loop(function(): ()
                local now: number = os.clock()
                if now - lastScanAt < 0.07 then
                    return
                end
                lastScanAt = now

                local character: Model?, humanoid: Humanoid?, root: BasePart? =
                    getCharacterParts()
                if not character or not humanoid or not root
                    or humanoid.Health <= 0 then
                    clearVisuals()
                    return
                end

                local range: number = tonumber(card.Options["Wall range"].Value) or 2.6
                local sighting: WallSighting? = findWall(character, humanoid, root, range)
                nearestWall = sighting

                local grounded: boolean = humanoid.FloorMaterial ~= Enum.Material.Air
                if not sighting or not grounded then
                    destroyHighlight()
                    card:SetStatus(grounded and "ready" or nil)
                    return
                end

                card:SetStatus(wallArrow(root, sighting))
                if card.Options["Highlight walls"].Value ~= true then
                    destroyHighlight()
                    return
                end
                if not highlight or not highlight.Parent then
                    highlight = Instance.new("Highlight")
                    highlight.Name = "Wurst_WallHop"
                    highlight.FillColor = Color3.fromRGB(64, 255, 140)
                    highlight.FillTransparency = 0.82
                    highlight.OutlineColor = Color3.fromRGB(64, 255, 140)
                    highlight.OutlineTransparency = 0.1
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Parent = currentWorkspace
                end
                if (highlight :: Highlight).Adornee ~= sighting.part then
                    (highlight :: Highlight).Adornee = sighting.part
                end
            end)
        end,
    })

    card:CreateSlider({
        Name = "Wall range",
        Min = 1.5,
        Max = 5,
        Default = 2.6,
        Step = 0.1,
        Tooltip = "How far from a wall you can be to wall hop.",
    })
    card:CreateSlider({
        Name = "Kick strength",
        Min = 8,
        Max = 26,
        Default = 14,
        Step = 1,
        Tooltip = "Horizontal push away from the wall on each hop.",
    })
    card:CreateToggle({
        Name = "Highlight walls",
        Default = true,
        Tooltip = "Outline the wall you can currently wall hop off.",
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
