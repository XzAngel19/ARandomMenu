local Module = {
    Name = "MM2 Knife Throw",
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
    assert(type(core) == "table", "MM2 Knife Throw requires the MM2 core module")
    Module.Runtime = runtime
    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local prediction: any = state.mm2Prediction
    assert(type(prediction) == "table", "MM2 Knife Throw requires MM2 Prediction")
    local mm2Settings: any = core.mm2Settings
    local lastKnifePrediction: any = nil
    local lastKnifeError: string? = nil
    local lastKnifeAimName: string? = nil
    local lastKnifeAimHeight: number? = nil
    local lastKnifeRadius: number? = nil
    local isWeaponPathClear: any = core.isWeaponPathClear
    local trajectoryCalibration: any = core.trajectoryCalibration

    -- One preset: held knife, nearest visible target, normal origin,
    -- always-on animation/LOS. The animation owns the throw cadence.
    local knifeThrowSettings = {enabled = false}

    local function isValidTarget(player: Player): boolean
        if player == LocalPlayer
            or isProtectedTarget(player)
            or not isPlayerAlive(player)
            or getPlayerRole(player) == "Murderer" then
            return false
        end
        return player.Character ~= nil
            and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
    end

    local resolveKnifeAim: (Player, Vector3) -> Vector3?
    local function findNearestTarget(origin: Vector3): Player?
        local localRoot: BasePart? = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not localRoot then
            return nil
        end
        local candidates: {{player: Player, distance: number}} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then
                local targetRoot: BasePart? = player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if targetRoot then
                    table.insert(candidates, {
                        player = player,
                        distance = (targetRoot.Position - localRoot.Position).Magnitude,
                    })
                end
            end
        end
        table.sort(candidates, function(left: any, right: any): boolean
            return left.distance < right.distance
        end)
        -- Corridor checks are rays: cap them per frame. The nearest three
        -- visible targets are enough; blocked players do not starve the rest.
        for index: number = 1, math.min(#candidates, 3) do
            local candidate: any = candidates[index]
            if resolveKnifeAim(candidate.player, origin) ~= nil then
                return candidate.player
            end
        end
        return nil
    end

    local function getReadyKnife(): Tool?
        if state.mm2SilentAimEnabled ~= true then return nil end
        if findMurderer() ~= LocalPlayer then
            return nil
        end
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil
        end

        local knife: Tool? = getPlayerWeapon(LocalPlayer, "Knife", true)
        if not knife or knife.Parent ~= character or knife.Enabled == false or knife:GetAttribute("Disabled") == true then
            return nil
        end
        return knife
    end

    local function readKnifeSpeed(knife: Tool?): number
        -- ThrowingKnifeVisuals: position += Direction * ThrowSpeed * dt,
        -- default 96 studs/s, no gravity term.
        local speed: number = 96
        if knife then
            local measured: any = knife:GetAttribute("ThrowSpeed")
            if type(measured) == "number"
                and measured == measured
                and measured >= 24
                and measured <= 300 then
                speed = measured
            end
        end
        return speed
    end

    -- The blade is a physical projectile, so "clear" is not a ray question.
    -- Its own thickness decides how much gap it needs, and a rail that covers
    -- the chest still leaves the head exposed: the aim walks upward until a
    -- blade-sized body actually reaches a part of the target.
    local MIN_KNIFE_RADIUS: number = 0.12
    local MAX_KNIFE_RADIUS: number = 0.6
    -- The blade keeps flying until it hits something, so there is no range
    -- limit: only an absurd lead (a vanished target, a broken sample) is
    -- refused. Ordinary long throws stay available.
    local MAX_KNIFE_DISTANCE: number = 400

    local function finiteNumber(value: any): boolean
        return type(value) == "number"
            and value == value
            and value > -math.huge
            and value < math.huge
    end

    local function knifeRadius(knife: Tool?): number
        local handle: Instance? = knife and knife:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            local size: Vector3 = handle.Size
            -- The long axis runs along the flight path; the gap the blade has
            -- to fit through is bounded by the middle of its extents.
            local extents: {number} = {
                size.X * 0.5, size.Y * 0.5, size.Z * 0.5,
            }
            table.sort(extents)
            local section: number = extents[2]
            if finiteNumber(section) then
                return math.clamp(section, MIN_KNIFE_RADIUS, MAX_KNIFE_RADIUS)
            end
        end
        return 0.25
    end

    -- The same exclusions the game's own WeaponService uses, and no
    -- transparency rule: the blade is a solid body, so an invisible part that
    -- can collide still stops it.
    local function knifeProbeParams(): RaycastParams
        local excluded: {Instance} = {}
        if LocalPlayer.Character then
            table.insert(excluded, LocalPlayer.Character)
        end
        for _, object: Instance in ipairs(
            CollectionService:GetTagged("WeaponPassthrough")
        ) do
            table.insert(excluded, object)
        end
        local params: RaycastParams = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = excluded
        params.IgnoreWater = true
        return params
    end

    -- True when a blade of `radius` thrown from `origin` meets the target
    -- before anything else. Spherecast is exactly that body; where the engine
    -- has no Spherecast, a centre ray plus a ring at the radius proves the
    -- same thing: nothing solid is closer than the target.
    local function knifeReaches(
        origin: Vector3,
        aim: Vector3,
        radius: number,
        targetCharacter: Model
    ): boolean
        local delta: Vector3 = aim - origin
        if delta.Magnitude < 0.05 then
            return false
        end
        local params: RaycastParams = knifeProbeParams()
        local ok: boolean, result: any = pcall(function(): any
            return (workspace :: any):Spherecast(origin, radius, delta, params)
        end)
        if ok then
            local part: any = result and result.Instance
            return typeof(part) == "Instance"
                and part:IsDescendantOf(targetCharacter)
        end
        local centre: RaycastResult? = workspace:Raycast(origin, delta, params)
        if not centre or not centre.Instance:IsDescendantOf(targetCharacter) then
            return false
        end
        local reach: number = (centre.Position - origin).Magnitude
        local direction: Vector3 = delta.Unit
        local right: Vector3 = direction:Cross(Vector3.new(0, 1, 0))
        if right.Magnitude < 1e-3 then
            right = Vector3.new(1, 0, 0)
        else
            right = right.Unit
        end
        local up: Vector3 = right:Cross(direction).Unit
        for _, offset: Vector3 in ipairs({
            right * radius, right * -radius, up * radius, up * -radius,
        }) do
            local side: RaycastResult? =
                workspace:Raycast(origin + offset, delta, params)
            if side and not side.Instance:IsDescendantOf(targetCharacter)
                and (side.Position - origin).Magnitude < reach then
                return false
            end
        end
        return true
    end

    -- Chest first, then upward: a rail that covers the chest usually leaves
    -- the head exposed. Below and sideways are the last resorts.
    local KNIFE_AIM_LADDER: {{height: number, lateral: number, name: string}} = {
        {height = 0, lateral = 0, name = "chest"},
        {height = 0.55, lateral = 0, name = "upper chest"},
        {height = 1.05, lateral = 0, name = "head"},
        {height = 1.5, lateral = 0, name = "above head"},
        {height = -0.6, lateral = 0, name = "legs"},
        {height = 0.5, lateral = 0.6, name = "shoulder"},
        {height = 0.5, lateral = -0.6, name = "shoulder"},
    }

    -- The blade is a straight projectile. The predictor solves the intercept
    -- (including the measured transport delay); the probe then proves that a
    -- blade of this size reaches that point and not a rail in front of it.
    resolveKnifeAim = function(target: Player, origin: Vector3): Vector3?
        lastKnifePrediction = nil
        lastKnifeError = nil
        lastKnifeAimName = nil
        lastKnifeAimHeight = nil
        lastKnifeRadius = nil
        local knife: Tool? = getReadyKnife()
        local endpoint: Vector3?, info: any, reason: string? =
            prediction.knifeAim(target, origin, readKnifeSpeed(knife))
        if not endpoint then
            lastKnifeError = reason
            return nil
        end
        local character: Model? = target.Character
        if not character then
            return nil
        end
        if (endpoint - origin).Magnitude > MAX_KNIFE_DISTANCE then
            lastKnifeError = "too far"
            return nil
        end
        local radius: number = knifeRadius(knife)
        lastKnifeRadius = radius
        local direction: Vector3 = (endpoint - origin).Unit
        local right: Vector3 = direction:Cross(Vector3.new(0, 1, 0))
        if right.Magnitude < 1e-3 then
            right = Vector3.new(1, 0, 0)
        else
            right = right.Unit
        end
        -- Height is world-up on purpose: the ladder exists to clear a
        -- horizontal rail, so "a bit higher" must mean higher, not merely
        -- perpendicular to a steep throw.
        for _, step: any in ipairs(KNIFE_AIM_LADDER) do
            local aim: Vector3 = endpoint
                + Vector3.new(0, 1, 0) * step.height
                + right * step.lateral
            if knifeReaches(origin, aim, radius, character) then
                lastKnifePrediction = info
                lastKnifeAimName = step.name
                lastKnifeAimHeight = step.height
                return aim
            end
        end
        -- Every rung was stopped by geometry. The target is behind cover for
        -- a blade of this size, so the throw is refused instead of wasted.
        lastKnifeError = "covered"
        return nil
    end

    type ThrowJoint = {
        joint: Motor6D, c0: CFrame, transform: CFrame,
        initial: CFrame, raised: CFrame, forward: CFrame,
    }
    -- One animation cycle: windup 0.3 s plus the 0.25 s recovery. Used both
    -- for the render loop and for the no-pose timer so the packet cadence is
    -- the same no matter which branch a rig takes.
    local KNIFE_CYCLE_SECONDS: number = 0.55
    -- A packet cannot leave twice inside a quarter second, whatever calls the
    -- release path. This is the backstop for the capture that recorded ~77
    -- throws in one second; the game needs the knife back in hand first.
    local MIN_PACKET_INTERVAL: number = 0.25
    local lastPacketAt: number = -math.huge
    local throwPose: {ThrowJoint} = {}
    local throwPending: boolean = false
    local function stopThrowAnimation(): ()
        disconnectFeatureConnection("MM2KnifeAnimation")
        throwPending = false
        for _, entry: ThrowJoint in ipairs(throwPose) do
            pcall(function(): ()
                if entry.joint.Parent then
                    entry.joint.C0 = entry.c0
                    entry.joint.Transform = entry.transform
                end
            end)
        end
        table.clear(throwPose)
    end

    local function playThrowAnimation(knife: Tool, onRelease: (() -> ())?): ()
        stopThrowAnimation()
        local character: Model? = LocalPlayer.Character
        if not character or knife.Parent ~= character then return end
        local function release(): ()
            if onRelease then onRelease() end
        end
        -- Parent-space rotation is deliberate. R6 shoulders have a rotated
        -- bind frame: post-multiplying an X rotation swings sideways, not up.
        local function addJoint(partName: string, jointName: string, lift: number, forward: number, roll: number): ()
            local part: Instance? = character:FindFirstChild(partName)
            local joint: any = part and part:FindFirstChild(jointName)
            if not joint or not joint:IsA("Motor6D") then return end
            local c0: CFrame = joint.C0
            local pivot: CFrame = CFrame.new(c0.Position)
            local basis: CFrame = c0 - c0.Position
            table.insert(throwPose, {
                joint = joint, c0 = c0, transform = joint.Transform,
                initial = c0 * joint.Transform,
                raised = pivot * CFrame.Angles(math.rad(lift), 0, math.rad(roll)) * basis,
                forward = pivot * CFrame.Angles(math.rad(forward), 0, 0) * basis,
            })
        end
        if character:FindFirstChild("RightUpperArm") then
            addJoint("RightUpperArm", "RightShoulder", 155, 85, -12)
            addJoint("RightLowerArm", "RightElbow", -85, -8, 0)
            addJoint("RightHand", "RightWrist", -15, 10, 0)
        else
            addJoint("Torso", "Right Shoulder", 155, 85, -12)
        end
        if #throwPose == 0 and type(character.GetDescendants) == "function" then
            -- Rig parenting varies (MM2 spawns its own R15 bodies and
            -- not every build parents the shoulder under the arm):
            -- find the right-arm Motor6Ds wherever they sit, matched
            -- by joint name or by the arm part they drive (Part1).
            -- Without this the pose list came back empty in game and
            -- the throw fired instantly, with no animation at all.
            local wanted: {[string]: {lift: number, forward: number, roll: number}} = {
                RightShoulder = {lift = 155, forward = 85, roll = -12},
                ["Right Shoulder"] = {lift = 155, forward = 85, roll = -12},
                RightElbow = {lift = -85, forward = -8, roll = 0},
                ["Right Elbow"] = {lift = -85, forward = -8, roll = 0},
                RightWrist = {lift = -15, forward = 10, roll = 0},
                ["Right Wrist"] = {lift = -15, forward = 10, roll = 0},
            }
            local byPart1: {[string]: string} = {
                RightUpperArm = "RightShoulder", ["Right Arm"] = "RightShoulder",
                RightLowerArm = "RightElbow", RightHand = "RightWrist",
            }
            for _, object: Instance in ipairs(character:GetDescendants()) do
                if object:IsA("Motor6D") then
                    local key: string? = wanted[object.Name] and object.Name or nil
                    if not key then
                        local part1: any = (object :: any).Part1
                        if part1 then
                            key = byPart1[part1.Name]
                        end
                    end
                    local spec: any = key and wanted[key :: string]
                    if spec then
                        local joint: any = object
                        local c0: CFrame = joint.C0
                        local pivot: CFrame = CFrame.new(c0.Position)
                        local basis: CFrame = c0 - c0.Position
                        table.insert(throwPose, {
                            joint = joint, c0 = c0, transform = joint.Transform,
                            initial = c0 * joint.Transform,
                            raised = pivot * CFrame.Angles(math.rad(spec.lift), 0, math.rad(spec.roll)) * basis,
                            forward = pivot * CFrame.Angles(math.rad(spec.forward), 0, 0) * basis,
                        })
                    end
                end
            end
        end
        -- The guard is armed before the pose is inspected. Releasing from the
        -- "no joint to pose" branch without it turned a held knife into one
        -- packet per frame: the 2026-10-18 capture holds 722 authored knife
        -- events in 22 seconds, up to 77 in a single second, against a 0.55 s
        -- animation. The server cannot use that: the blade leaves the hand
        -- with whichever packet it accepted first.
        throwPending = onRelease ~= nil
        if #throwPose == 0 then
            release()
            task.delay(KNIFE_CYCLE_SECONDS, function(): ()
                if throwPending then
                    stopThrowAnimation()
                end
            end)
            return
        end
        local elapsed: number = 0
        local released: boolean = false
        featureConnections.MM2KnifeAnimation = TaskManager:Connect(function(dt: number): ()
            if LocalPlayer.Character ~= character or knife.Parent ~= character then
                stopThrowAnimation()
                return
            end
            elapsed += math.max(0, dt)
            local phase: number = elapsed < 0.2 and 1 or (elapsed < 0.3 and 2 or 3)
            local alpha: number = phase == 1 and elapsed / 0.2
                or (phase == 2 and (elapsed - 0.2) / 0.1 or (elapsed - 0.3) / 0.25)
            alpha = math.clamp(alpha, 0, 1)
            alpha = alpha * alpha * (3 - 2 * alpha)
            for _, entry: ThrowJoint in ipairs(throwPose) do
                if not entry.joint.Parent then stopThrowAnimation(); return end
                local from: CFrame = phase == 1 and entry.initial or (phase == 2 and entry.raised or entry.forward)
                local to: CFrame = phase == 1 and entry.raised or (phase == 2 and entry.forward or entry.initial)
                entry.joint.Transform = CFrame.new()
                entry.joint.C0 = from:Lerp(to, alpha)
            end
            -- Apply the forward pose before authoring exactly one packet.
            if elapsed >= 0.3 and not released then
                released = true
                pcall(release)
            end
            if elapsed >= KNIFE_CYCLE_SECONDS then stopThrowAnimation() end
        end, "render")
    end


    -- The spawn point: the handle when it exists, the hand otherwise. The
    -- position is always the real one; the rotation is completed below.
    local function knifeOrigin(knife: Tool, character: Model?): CFrame?
        if not character or character ~= LocalPlayer.Character then
            return nil
        end
        local handle: Instance? = knife:FindFirstChild("Handle")
        local hand: Instance? = character:FindFirstChild("RightHand")
            or character:FindFirstChild("Right Arm")
            or character:FindFirstChild("HumanoidRootPart")
        local source: Instance? =
            handle and handle:IsA("BasePart") and handle or hand
        if not source or not source:IsA("BasePart") then
            return nil
        end
        return (source :: BasePart).CFrame
    end

    -- One throw, one packet. The origin and the aim are resolved at the
    -- moment of sending, so a windup cannot fire from a stale hand position.
    local function performThrow(
        knife: Tool,
        remote: Instance
    ): boolean
        if not knifeThrowSettings.enabled or getReadyKnife() ~= knife then
            return false
        end
        local character: Model? = LocalPlayer.Character
        local origin: CFrame? = knifeOrigin(knife, character)
        if not origin then
            return false
        end
        -- Select again at release: do not cling to a target that closed its
        -- peek during windup when another player is now visible.
        local target: Player? = findNearestTarget(origin.Position)
        if not target then
            return false
        end
        local aim: Vector3? = resolveKnifeAim(target, origin.Position)
        if not aim or (aim - origin.Position).Magnitude < 0.05 then
            return false
        end
        -- The origin is a real CFrame, not a bare position. The native
        -- KnifeClient sends the handle's pose with a non-identity rotation
        -- (recorded in both native logs), so a server that reads LookVector
        -- takes the blade's direction from here. Pointing that look vector at
        -- the predicted point makes the packet coherent for both readings:
        -- a server that uses (target - origin) gets the same aim it always
        -- did, and a server that uses the rotation now gets the lead too,
        -- instead of world -Z. The second argument stays a position: that is
        -- where the blade has to end up.
        local travel: Vector3 = aim - origin.Position
        local originCFrame: CFrame = origin
        if travel.Magnitude > 1e-3 then
            originCFrame = CFrame.lookAt(origin.Position, aim)
        end
        -- Last gate before the wire: one packet per quarter second. The
        -- capture of 2026-10-18 proves the callers alone cannot be trusted
        -- with this (722 knife events in 22 s). Everything above is pure
        -- reading, so a rejected packet costs nothing.
        local now: number = os.clock()
        if now - lastPacketAt < MIN_PACKET_INTERVAL then
            return false
        end
        lastPacketAt = now
        remote:FireServer(originCFrame, CFrame.new(aim))
        pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
            kind = "knife", tool = knife, toolName = knife.Name,
            originPos = origin.Position, aimPos = aim, target = target,
            silent = false,
            settings = {mode = "Normal", animation = true, wallCheck = true,
                motionSource = lastKnifePrediction and lastKnifePrediction.motionSource,
                cadence = "animation-cycle",
                model = lastKnifePrediction and lastKnifePrediction.model or "kinematic-v51",
                referencePoint = lastKnifePrediction and {lastKnifePrediction.capturedPosition.X, lastKnifePrediction.capturedPosition.Y, lastKnifePrediction.capturedPosition.Z},
                predictedPoint = lastKnifePrediction and {lastKnifePrediction.endpoint.X, lastKnifePrediction.endpoint.Y, lastKnifePrediction.endpoint.Z},
                sampledVelocity = lastKnifePrediction and {lastKnifePrediction.velocity.X, lastKnifePrediction.velocity.Y, lastKnifePrediction.velocity.Z},
                leadSeconds = lastKnifePrediction and lastKnifePrediction.leadSeconds,
                flightSeconds = lastKnifePrediction and lastKnifePrediction.flightSeconds,
                sampleAge = lastKnifePrediction and lastKnifePrediction.sampleAge,
                samples = lastKnifePrediction and lastKnifePrediction.samples,
                rtt = lastKnifePrediction and lastKnifePrediction.rtt,
                echoDelay = lastKnifePrediction and lastKnifePrediction.echoDelay,
                echoSamples = lastKnifePrediction and lastKnifePrediction.echoSamples,
                rttEngine = lastKnifePrediction and lastKnifePrediction.rttEngine,
                rttData = lastKnifePrediction and lastKnifePrediction.rttData,
                turnRate = lastKnifePrediction and lastKnifePrediction.turnRate,
                brakeSeconds = lastKnifePrediction and lastKnifePrediction.brakeSeconds,
                -- Where the blade went: the aim rung it took, how much it had
                -- to clear and the body size the probe used.
                aimHeight = lastKnifeAimName,
                aimOffsetStuds = lastKnifeAimHeight,
                knifeRadius = lastKnifeRadius,
                throwSource = "auto",
                -- The packet now carries a frame whose look vector points at
                -- the aim; a capture can tell which build threw it.
                originRotation = travel.Magnitude > 1e-3 and "look-at" or "handle",
                windupSeconds = 0.3},
        })
        return true
    end

    local function throwKnife(): ()
        if not knifeThrowSettings.enabled then
            return
        end
        local knife: Tool? = getReadyKnife()
        if not knife then
            stopThrowAnimation()
            return
        end
        local events: Instance? = knife:FindFirstChild("Events")
        local remote: Instance? = events and events:FindFirstChild("KnifeThrown")
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end
        if throwPending then
            return
        end
        local character: Model? = LocalPlayer.Character
        local origin: CFrame? = knifeOrigin(knife, character)
        if not origin or not findNearestTarget(origin.Position) then
            return
        end
        local ok: boolean = pcall(
            playThrowAnimation,
            knife,
            function(): ()
                performThrow(knife, remote)
            end
        )
        if not ok then
            stopThrowAnimation()
        end
    end

    local function refreshKnifeThrow(): ()
        disconnectFeatureConnection("MM2KnifeThrow")
        if not knifeThrowSettings.enabled or state.mm2SilentAimEnabled ~= true then
            stopThrowAnimation()
            return
        end
        featureConnections.MM2KnifeThrow =
            TaskManager:Connect(function(): ()
                throwKnife()
            end)
    end
    local function toggleKnifeThrow(enabled: boolean): ()
        knifeThrowSettings.enabled = enabled
        if state.mm2KnifeRuntime then state.mm2KnifeRuntime.throwWanted = enabled end
        refreshKnifeThrow()
    end

    local feature: any = state.mm2SilentAimFeature
    assert(feature, "Knife Throw requires SilentAIM")
    local key = "MM2.Shoot.KnifeThrow"
    if configData.states[key] == nil then
        local previous = configData.states["Universal.KillAura.KnifeThrow"]
        if previous == nil then previous = configData.states["MM2.Knife.KnifeThrow"] end
        configData.states[key] = previous
    end
    local bind = "Shortcut.MM2ShootKnifeThrow"
    if configData.values[bind] == nil then
        configData.values[bind] = configData.values["Shortcut.UniversalKillAuraKnifeThrow"]
            or configData.values["Shortcut.MM2KnifeKnifeThrow"]
    end
    state.mm2KnifeThrowRefresh = refreshKnifeThrow
    state.mm2KnifeThrowOff = function(): () toggleKnifeThrow(false) end
    -- The knife options open their own section, after the Gun rows that the
    -- Shoot module already created: the two weapons never mix again.
    if addSectionOption then addSectionOption(feature, "Knife") end
    addToggleOption(feature, "Knife Throw", false, toggleKnifeThrow,
        "SilentAIM ON + held knife: repeats throws at visible targets. Full animation and WallCheck are automatic.", true)
    featureConnections.MM2KnifeThrowCharacter = LocalPlayer.CharacterAdded:Connect(stopThrowAnimation)
    activeCleanup = function(): ()
        toggleKnifeThrow(false)
        disconnectFeatureConnection("MM2KnifeThrowCharacter")
        state.mm2KnifeThrowOff = nil
        state.mm2KnifeThrowRefresh = nil
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
