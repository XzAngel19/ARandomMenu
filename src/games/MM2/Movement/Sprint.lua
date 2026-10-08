local Module = {
    Name = "MM2 Sprint",
    PlaceId = 142823291,
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

    local MM2_SPRINT_SPEED: number = 30

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

    local sprintActive: boolean = false
    local sprintBaseSpeed: number? = nil

    local function applySprintSpeed(active: boolean): ()
        local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
        if not humanoid or not root then
            return
        end
        if active then
            if sprintBaseSpeed == nil and humanoid.WalkSpeed ~= MM2_SPRINT_SPEED then
                sprintBaseSpeed = humanoid.WalkSpeed
            end
            humanoid.WalkSpeed = MM2_SPRINT_SPEED
        else
            humanoid.WalkSpeed = sprintBaseSpeed or 16
            sprintBaseSpeed = nil
        end
    end

    local function toggleSprint(enabled: boolean): ()
        disconnectFeatureConnection("MM2Sprint")

        if not enabled then
            sprintActive = false
            clearSprintTrail()
            applySprintSpeed(false)
            return
        end

        featureConnections.MM2Sprint = TaskManager:Connect(function(): ()
            local _, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not humanoid or not root then
                return
            end
            if not sprintActive then
                if sprintBaseSpeed ~= nil then

                    applySprintSpeed(false)
                end
                return
            end

            if humanoid.WalkSpeed ~= MM2_SPRINT_SPEED then
                if sprintBaseSpeed == nil then
                    sprintBaseSpeed = humanoid.WalkSpeed
                end
                humanoid.WalkSpeed = MM2_SPRINT_SPEED
            end
            ensureSprintTrail(root).Enabled = humanoid.MoveDirection.Magnitude > 0.05
        end)
    end

    local function setSprintActive(active: boolean): ()
        if sprintActive == active then
            return
        end
        sprintActive = active
        applySprintSpeed(active)
        if not active then
            local trail: Instance? = nil
            local _, _, root: BasePart? = getCharacterParts()
            if root then
                trail = root:FindFirstChild("Wurst_SprintTail")
            end
            if trail and trail:IsA("Trail") then
                trail.Enabled = false
            end
        end
    end

    createUniversalFeature(
        "Sprint",
        "Hold your key to run at 30 speed with a trail",
        10,
        toggleSprint,
        {
            kind = "hold",
            onHold = setSprintActive,
            noOptions = true,
            categoryName = "Movement",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    activeCleanup = function(): ()
        toggleSprint(false)
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
