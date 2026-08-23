--!strict
--
-- Wall Hop.
-- A jump made while facing a near-vertical wall kicks the character upward and
-- away from it. One raycast per jump request; no permanent movement loop.

export type Runtime = {
    framework: any,
    host: any,
    services: any,
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

    local card: any
    card = framework.Categories.Movement:CreateModule({
        Name = "WallHop",
        Category = "Movement",
        ConfigKey = "Universal.WallHop",
        Order = 31,
        Tooltip = "Jump at a wall to vault upward and away from it.",
        Function = function(enabled: boolean): ()
            if not enabled then
                card:SetStatus(nil)
                return
            end
            card:SetStatus("ready")
            card:Clean(movementInput.onJumpRequest(function(): ()
                local now: number = os.clock()
                if now - lastHopAt < card.Options["Cooldown"].Value then
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
                local hit: RaycastResult? = currentWorkspace:Raycast(
                    root.Position,
                    root.CFrame.LookVector * card.Options["Reach"].Value,
                    parameters
                )
                if not hit or math.abs(hit.Normal.Y) > 0.35 then
                    return
                end
                lastHopAt = now
                local velocity: Vector3 = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(
                    velocity.X + hit.Normal.X * card.Options["Push"].Value,
                    math.max(velocity.Y, card.Options["Height"].Value),
                    velocity.Z + hit.Normal.Z * card.Options["Push"].Value
                )
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                card:SetStatus("hop")
                task.delay(0.25, function(): ()
                    if card.Enabled then
                        card:SetStatus("ready")
                    end
                end)
            end))
        end,
    })

    card:CreateSlider({Name = "Height", Min = 20, Max = 100, Step = 1, Default = 48})
    card:CreateSlider({Name = "Push", Min = 0, Max = 60, Step = 1, Default = 24})
    card:CreateSlider({Name = "Reach", Min = 1.5, Max = 5, Step = 0.1, Default = 2.5})
    card:CreateSlider({Name = "Cooldown", Min = 0.1, Max = 1, Step = 0.05, Default = 0.25})

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
