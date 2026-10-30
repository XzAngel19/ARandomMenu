local Module = {
    Name = "MM2 Sprint",
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Sprint requires the MM2 core module")
    Module.Runtime = runtime

    local sprintTrailObjects: {Instance} = {}


    local function clearSprintTrail(): ()
        for _, object: Instance in ipairs(sprintTrailObjects) do
            if object.Parent then
                object:Destroy()
            end
        end
        table.clear(sprintTrailObjects)
    end

    local function ensureSprintTrail(root: BasePart): Trail
        local existing: Instance? = root:FindFirstChild("Wurst_SprintTail")
        if existing and existing:IsA("Trail") then
            return existing
        end

        clearSprintTrail()
        local left: Attachment = Instance.new("Attachment")
        left.Name = "Wurst_SprintLeft"
        left.Position = Vector3.new(-0.8, -0.5, 0.75)
        left.Parent = root

        local right: Attachment = Instance.new("Attachment")
        right.Name = "Wurst_SprintRight"
        right.Position = Vector3.new(0.8, -0.5, 0.75)
        right.Parent = root

        local trail: Trail = Instance.new("Trail")
        trail.Name = "Wurst_SprintTail"
        trail.Attachment0 = left
        trail.Attachment1 = right
        trail.Color = ColorSequence.new(
            Color3.fromRGB(255, 220, 55),
            Color3.fromRGB(175, 115, 20)
        )
        trail.Lifetime = 0.38
        trail.LightEmission = 0.25
        trail.FaceCamera = true
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(1, 1),
        })
        trail.Enabled = false
        trail.Parent = root
        sprintTrailObjects = {trail, left, right}
        return trail
    end

    local speed: any = state.framework and state.framework:GetModule("Speed")
    assert(speed, "Sprint option requires the Speed module")
    speed.ClearSprint = clearSprintTrail
    speed.SprintFrame = function(active: boolean, root: BasePart): ()
        if not active then clearSprintTrail(); return end
        local _, humanoid: Humanoid? = getCharacterParts()
        ensureSprintTrail(root).Enabled = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.05
    end
    local function releaseSprint(): ()
        disconnectFeatureConnection("MM2SprintHold")
        speed.SetSprintHeld(false)
        clearSprintTrail()
    end
    speed:CreateButton({
        Name = "Sprint", Hold = true,
        Function = function(): ()
            speed.SetSprintHeld(true)
            if not featureConnections.MM2SprintHold then
                featureConnections.MM2SprintHold = TaskManager:Connect(speed.StepSprint, nil, "MM2 Sprint")
            end
        end,
        OnRelease = releaseSprint,
        Tooltip = "Hold this button, its assigned key or the touch action to sprint. Works with Speed OFF; release restores normal Speed or your original speed. No toggle state is saved.",
    })
    activeCleanup = function(): ()
        releaseSprint()
        speed.ClearSprint = nil
        speed.SprintFrame = nil
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
