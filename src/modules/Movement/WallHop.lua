--!strict
--
-- WallHop.
-- Uses a fixed, tested offset sequence rather than exposing implementation
-- constants as settings. Three probes find a usable wall edge; the hop only
-- starts when either a side or the space above the wall is open.

export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

type PendingHop = {
    root: BasePart,
    humanoid: Humanoid,
    normal: Vector3,
    lateral: Vector3,
    startedAt: number,
    stage: number,
}

local Module = {
    Name = "WallHop",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local movementInput: any = context.services.movementInput
    local getCharacterParts: any = host.getCharacterParts
    local currentWorkspace: Workspace = host.workspace or workspace
    local lastHopAt: number = -math.huge
    local pending: PendingHop? = nil

    local function cast(
        origin: Vector3,
        direction: Vector3,
        parameters: RaycastParams
    ): RaycastResult?
        local hit: RaycastResult? = currentWorkspace:Raycast(origin, direction, parameters)
        if hit and math.abs(hit.Normal.Y) <= 0.28 then
            return hit
        end
        return nil
    end

    local card: any
    card = framework.Categories.Movement:CreateModule({
        Name = "WallHop",
        Category = "Movement",
        ConfigKey = "Universal.WallHop",
        Order = 31,
        Tooltip = "Uses nearby wall edges to perform a consistent wall hop.",
        Function = function(enabled: boolean): ()
            pending = nil
            -- A hop spent just before the card was switched off must not eat
            -- the first jump request after it comes back.
            lastHopAt = -math.huge
            if not enabled then
                card:SetStatus(nil)
                return
            end
            card:SetStatus("ready")

            card:Clean(movementInput.onJumpRequest(function(): ()
                local now: number = os.clock()
                if now - lastHopAt < 0.22 or pending ~= nil then
                    return
                end
                local character: Model?, humanoid: Humanoid?, root: BasePart? =
                    getCharacterParts()
                if not character or not humanoid or not root or humanoid.Health <= 0 then
                    return
                end

                local parameters: RaycastParams = RaycastParams.new()
                parameters.FilterType = Enum.RaycastFilterType.Exclude
                parameters.FilterDescendantsInstances = {character}
                parameters.IgnoreWater = true
                parameters.RespectCanCollide = true

                local forward: Vector3 = root.CFrame.LookVector
                local right: Vector3 = root.CFrame.RightVector
                local origin: Vector3 = root.Position + Vector3.new(0, 0.35, 0)
                local centre: RaycastResult? = cast(origin, forward * 2.65, parameters)
                if not centre then
                    return
                end

                local leftHit: RaycastResult? = cast(
                    origin - right * 0.7,
                    forward * 2.65,
                    parameters
                )
                local rightHit: RaycastResult? = cast(
                    origin + right * 0.7,
                    forward * 2.65,
                    parameters
                )
                local topHit: RaycastResult? = cast(
                    origin + Vector3.new(0, 2.6, 0),
                    forward * 2.4,
                    parameters
                )

                -- A usable edge has room on one side or above. Pushing into a
                -- fully covered wall is the unreliable case this check rejects.
                local lateral: Vector3 = Vector3.zero
                if not leftHit then
                    lateral = right * -1
                elseif not rightHit then
                    lateral = right
                elseif not topHit then
                    lateral = humanoid.MoveDirection.Magnitude > 0.05
                            and humanoid.MoveDirection.Unit
                        or right
                else
                    card:SetStatus("blocked")
                    return
                end

                lastHopAt = now
                pending = {
                    root = root,
                    humanoid = humanoid,
                    normal = centre.Normal,
                    lateral = lateral,
                    startedAt = now,
                    stage = 0,
                }
                card:SetStatus("hop")
            end))

            card:Loop(function(): ()
                local hop: PendingHop? = pending
                if not hop then
                    return
                end
                -- A character replaced mid-sequence is a different assembly, and
                -- a humanoid that died mid-sequence is not going to jump. Either
                -- way the remaining offsets are dropped rather than written into
                -- whatever is wearing the name now.
                local _character: Model?, humanoid: Humanoid?, root: BasePart? =
                    getCharacterParts()
                if not hop.root.Parent
                    or hop.humanoid.Health <= 0
                    or root ~= hop.root
                    or humanoid ~= hop.humanoid then
                    pending = nil
                    card:SetStatus("ready")
                    return
                end
                local elapsed: number = os.clock() - hop.startedAt
                if hop.stage == 0 then
                    hop.stage = 1
                    hop.root.CFrame += hop.normal * 0.35
                        + hop.lateral * 0.45
                        + Vector3.new(0, 0.3, 0)
                elseif hop.stage == 1 and elapsed >= 0.035 then
                    hop.stage = 2
                    hop.root.CFrame += hop.normal * 0.5
                        + hop.lateral * 0.7
                        + Vector3.new(0, 0.55, 0)
                elseif hop.stage == 2 and elapsed >= 0.07 then
                    local velocity: Vector3 = hop.root.AssemblyLinearVelocity
                    hop.root.AssemblyLinearVelocity = Vector3.new(
                        velocity.X + hop.normal.X * 18 + hop.lateral.X * 12,
                        math.max(velocity.Y, 52),
                        velocity.Z + hop.normal.Z * 18 + hop.lateral.Z * 12
                    )
                    hop.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    pending = nil
                    card:SetStatus("ready")
                end
            end)
        end,
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
