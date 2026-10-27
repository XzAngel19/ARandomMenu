export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "WalkFling",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local RunService: any = host.RunService or game:GetService("RunService")
    local workspace: any = host.workspace
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local configData: any = host.configData
    local services: any = (context :: any).services
    local activity: any = services and services.activity

    -- A persisted ON state must not start a fling on injection: the pulse only
    -- answers to an explicit toggle during the session.
    if type(configData) == "table" and type(configData.states) == "table" then
        configData.states["Universal.WalkFling"] = false
    end

    local enabled: boolean = false
    local session: number = 0
    -- No slider: this is the Infinite Yield default and it is what works.
    local POWER: number = 10000
    local savedCollision: any = setmetatable({}, {__mode = "k"})
    local walkFlingFeature: any = nil

    local function getCharacterRoot(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character or not character.Parent then
            return nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        local root: BasePart? = (humanoid and humanoid.RootPart)
            or (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
            or (character:FindFirstChild("Torso") :: BasePart?)
        if not humanoid or humanoid.Health <= 0 or not root then
            return character, humanoid, nil
        end
        return character, humanoid, root
    end

    local function waitSignal(signal: any): ()
        if signal and type(signal.Wait) == "function" then
            local ok: boolean = pcall(function(): ()
                signal:Wait()
            end)
            if ok then
                return
            end
        end
        task.wait()
    end

    local function rememberCollision(character: Model): ()
        for _, part: Instance in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") and savedCollision[part] == nil then
                savedCollision[part] = (part :: BasePart).CanCollide
            end
        end
    end

    local function restoreCollision(): ()
        for part: any, canCollide: any in pairs(savedCollision) do
            if part and part.Parent then
                pcall(function(): ()
                    part.CanCollide = canCollide
                end)
            end
        end
        savedCollision = setmetatable({}, {__mode = "k"})
    end

    local function stopWalkFling(): ()
        enabled = false
        session += 1
        restoreCollision()
        local _character: Model?, _humanoid: Humanoid?, root: BasePart? = getCharacterRoot()
        if root and root.Parent then
            pcall(function(): ()
                root.Velocity = Vector3.zero
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
        if activity and type(activity.set) == "function" then
            activity.set("walkfling", false)
        end
        if walkFlingFeature then
            walkFlingFeature:SetStatus(nil)
        end
    end

    -- Infinite Yield's walkfling, which the user approved: spike the root
    -- velocity inside the RenderStepped window, put it back before the physics
    -- step and micro-oscillate so replication stays awake. The only additions
    -- are the session token (so an old loop cannot outlive a new toggle) and the
    -- collision restore on the way out.
    local function startWalkFling(): ()
        if enabled then
            return
        end
        enabled = true
        session += 1
        local mySession: number = session
        local movel: number = 0.1
        if activity and type(activity.set) == "function" then
            activity.set("walkfling", true)
        end
        if walkFlingFeature then
            walkFlingFeature:SetStatus("ON")
        end

        task.spawn(function(): ()
            while enabled and session == mySession and Module.Initialized do
                waitSignal(RunService and RunService.Heartbeat)
                if not enabled or session ~= mySession then
                    break
                end
                local character: Model?, _humanoid: Humanoid?, root: BasePart? = getCharacterRoot()
                if character and root and root.Parent then
                    local savedVelocity: Vector3 = root.AssemblyLinearVelocity
                    pcall(function(): ()
                        rememberCollision(character)
                        for _, part: Instance in ipairs(character:GetChildren()) do
                            if part:IsA("BasePart") then
                                (part :: BasePart).CanCollide = false
                            end
                        end
                        local spike: Vector3 = savedVelocity * POWER + Vector3.new(0, POWER, 0)
                        root.Velocity = spike
                        root.AssemblyLinearVelocity = spike
                    end)
                    waitSignal(RunService and RunService.RenderStepped)
                    -- A toggle-off that lands in the middle of an iteration must
                    -- not re-apply the spike after stop() already parked the body.
                    local stillRunning: boolean = enabled and session == mySession
                    if stillRunning and character.Parent and root.Parent then
                        pcall(function(): ()
                            root.Velocity = savedVelocity
                            root.AssemblyLinearVelocity = savedVelocity
                        end)
                    end
                    waitSignal(RunService and RunService.Stepped)
                    if stillRunning and enabled and session == mySession
                        and character.Parent and root.Parent then
                        pcall(function(): ()
                            local oscillated: Vector3 = savedVelocity + Vector3.new(0, movel, 0)
                            root.Velocity = oscillated
                            root.AssemblyLinearVelocity = oscillated
                            movel = -movel
                        end)
                    end
                end
            end
            if session == mySession then
                restoreCollision()
            end
        end)
    end

    local function toggleWalkFling(state: boolean): ()
        if state == true then
            startWalkFling()
            return
        end
        stopWalkFling()
    end

    walkFlingFeature = createUniversalFeature(
        "Walk Fling",
        "Fling on contact while walking (Infinite Yield walkfling)",
        8,
        toggleWalkFling,
        {categoryName = "Exploits", noOptions = true}
    )
    addFeatureTooltip(
        walkFlingFeature,
        "While ON, every physics frame the local character is noclipped and given a "
            .. "huge velocity for one frame, which launches whoever you walk into. "
            .. "Collisions are restored when it stops. It never starts on injection."
    )

    activeCleanup = function(): ()
        stopWalkFling()
    end
    Module.Initialized = true
    return walkFlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
