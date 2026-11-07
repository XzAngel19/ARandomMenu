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
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local addInformationOption: any = host.addInformationOption
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
    -- Fixed at the previous maximum (3x Infinite Yield's baseline). There is
    -- no Power option: only an explicit ON toggle may produce this pulse.
    local POWER: number = 30000
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
        local wasEnabled: boolean = enabled
        enabled = false
        session += 1
        restoreCollision()
        local _character: Model?, _humanoid: Humanoid?, root: BasePart? = getCharacterRoot()
        if wasEnabled and root and root.Parent then
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
                RunService.Heartbeat:Wait()
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
                    RunService.RenderStepped:Wait()
                    -- A toggle-off that lands in the middle of an iteration must
                    -- not re-apply the spike after stop() already parked the body.
                    local stillRunning: boolean = enabled and session == mySession
                    if stillRunning and character.Parent and root.Parent then
                        pcall(function(): ()
                            root.Velocity = savedVelocity
                            root.AssemblyLinearVelocity = savedVelocity
                        end)
                    end
                    RunService.Stepped:Wait()
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

    -- v190: MM2-only notice. Anti Fling shields every colliding part against a
    -- body moving at fling speeds -- which is exactly the contact Walk Fling
    -- needs -- so enabling both at once made the fling look broken. The player
    -- asked for the warning instead of silent failure: refusing here makes the
    -- card revert itself and report "Could not toggle Walk Fling: ...".
    local function mm2Game(): boolean
        local shared: any = host.state
        if shared and shared.activeGameName == "MM2" then
            return true
        end
        local ok: boolean, placeId: any = pcall(function(): any return game.PlaceId end)
        return ok and placeId == 142823291
    end

    local function antiFlingOn(): boolean
        local shared: any = host.state
        return shared ~= nil and shared.antiFlingActive == true
    end

    local function toggleWalkFling(state: boolean): ()
        if state == true then
            if mm2Game() and antiFlingOn() then
                error("Anti Fling is ON. Turn it off first to use Walk Fling.", 0)
            end
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
        {categoryName = "Exploits"}
    )
    if type(addInformationOption) == "function" then
        addInformationOption(
            walkFlingFeature,
            "Collisions are restored and the body parked when the card is turned off."
        )
    end
    addFeatureTooltip(
        walkFlingFeature,
        "While ON, every physics frame the local character is noclipped and given a "
            .. "huge velocity for one frame, which launches whoever you walk into. "
            .. "Collisions are restored when it stops. It never starts on injection. "
            .. "In MM2 it refuses to start while Anti Fling is ON."
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
