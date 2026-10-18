local Module = {
    Name = "MM2 Prediction",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

--[[
    Kinematic prediction core for MM2 gun shots and knife throws.

    What this model is based on (TestingStuff evidence, not guesses):

      * GunFired echoes carry (handle, origin, endpoint, hitPart). The time
        between our FireServer and that echo is the only transport number we
        can measure in-game; the saved calibration recorded 297 confirmed
        shots with a mean of ~123.5 ms.
      * ThrowingKnifeVisuals advances the blade linearly:
            CFrame + Direction * ThrowSpeed * dt
        with ThrowSpeed 96 by default and no gravity term. A blade therefore
        needs an intercept solve, not a ballistic one.
      * A remote character's replicated position is older than the server
        state the gun ray is checked against. The aim point must advance by
        the round trip plus the replication interpolation window.

    What this model deliberately does NOT do:

      * No turn-rate "discount", no acceleration extrapolation, no stop-time
        damping, no auto-tuned lead. Those were chained heuristics that
        changed each other's output and could overshoot a target that simply
        stopped. A short weighted least-squares fit over the replicated
        positions is the least-surprising estimator.
      * No invented movement when the measured velocity is zero but
        MoveDirection is not. The server only knows replicated motion.
      * No distance/confidence gate before firing. Freshness of the sample,
        WallCheck and weapon readiness are the real conditions.
]]

type Sample = {
    at: number,
    position: Vector3,
    velocity: Vector3,
    state: string,
    grounded: boolean,
    aimOffset: Vector3,
    aimPart: string,
}

type Track = {
    character: Model,
    humanoid: Humanoid,
    root: BasePart,
    samples: {Sample},
}

type Fit = {
    velocity: Vector3,
    residual: number,
    count: number,
    span: number,
}

type Motion = {
    velocity: Vector3,
    horizontal: Vector3,
    vertical: number,
    airborne: boolean,
    sampleAge: number,
    samples: number,
    residual: number,
    source: string,
}

type AimInfo = {
    endpoint: Vector3,
    targetPosition: Vector3,
    capturedPosition: Vector3,
    rootPosition: Vector3,
    velocity: Vector3,
    leadSeconds: number,
    sampleAge: number,
    samples: number,
    residual: number,
    motionSource: string,
    model: string,
    rtt: number,
    echoDelay: number?,
    flightSeconds: number?,
}

local MAX_SAMPLE_AGE: number = 0.35
local FIT_WINDOW: number = 0.16
local FIT_TAU: number = 0.055
local HISTORY_SECONDS: number = 0.6
-- Remote characters replicate around 20 Hz. 60 Hz keeps three observations per
-- replicated pose (so a fit is never built from a single packet) without
-- inventing detail that the network never sent. Raising it only re-weights the
-- same poses and costs CPU; the dominant error is the transport horizon.
local SAMPLE_HZ: number = 60
local MAX_HORIZONTAL_SPEED: number = 60
local DEFAULT_KNIFE_SPEED: number = 96
local MAX_ECHOES: number = 8
local MIN_ECHO_SAMPLES: number = 2
-- Transport + manual lead. A full second only happens when the session ping
-- or the manual offset asks for it; the status line shows the real number.
local MAX_HORIZON: number = 1.0

local settings = {
    -- Manual calibration in seconds. Positive aims further ahead.
    extraLead = 0,
    -- Half of the default 20 Hz replication interval. This is the window the
    -- client interpolates between two replicated character states.
    interpolation = 1 / 40,
}

local activeCleanup: () -> () = function(): () end

local function finiteNumber(value: any): boolean
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function finiteVector(value: any): boolean
    return value ~= nil
        and finiteNumber(value.X)
        and finiteNumber(value.Y)
        and finiteNumber(value.Z)
end

local function humanoidStateName(humanoid: Humanoid): string
    local ok: boolean, state: any = pcall(function(): any
        return humanoid:GetState()
    end)
    if not ok or state == nil then
        return ""
    end
    local name: any = state.Name
    if type(name) == "string" then
        return name
    end
    return tostring(state)
end

local AIM_PARTS: {string} = {
    "UpperTorso",
    "Torso",
    "HumanoidRootPart",
    "Head",
}

local function findAimPart(character: Model): (BasePart?, string)
    for _, partName: string in ipairs(AIM_PARTS) do
        local part: Instance? = character:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            return part :: BasePart, partName
        end
    end
    local root: Instance? = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root :: BasePart, "HumanoidRootPart"
    end
    return nil, ""
end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Prediction requires the MM2 core module")
    local predictionMath: any = core.predictionMath
    assert(type(predictionMath) == "table", "MM2 Prediction requires predictionMath")
    Module.Runtime = runtime

    local tracks: {[Player]: Track} =
        setmetatable({}, {__mode = "k"}) :: any
    local echoes: {number} = {}
    local elapsed: number = 0

    local function ensureTrack(player: Player): Track?
        local character: Model? = player.Character
        if not character then
            tracks[player] = nil
            return nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        if not humanoid or not root or humanoid.Health <= 0 then
            tracks[player] = nil
            return nil
        end
        local track: Track? = tracks[player]
        if not track or track.character ~= character then
            track = {
                character = character,
                humanoid = humanoid,
                root = root,
                samples = {},
            }
            tracks[player] = track
        end
        track.humanoid = humanoid
        track.root = root
        return track
    end

    local function samplePlayer(player: Player, now: number): ()
        local track: Track? = ensureTrack(player)
        if not track then
            return
        end
        local root: BasePart = track.root
        local position: Vector3 = root.Position
        local velocity: Vector3 = root.AssemblyLinearVelocity
        if not finiteVector(velocity) then
            velocity = Vector3.zero
        end
        local stateName: string = humanoidStateName(track.humanoid)
        -- FloorMaterial often reads Air on remote characters that are walking
        -- on flat ground. The humanoid state is the reliable signal.
        local grounded: boolean = stateName ~= "Jumping"
            and stateName ~= "Freefall"
        local aimPart: BasePart?, aimPartName: string = findAimPart(track.character)
        local aimOffset: Vector3 = aimPart
            and (aimPart.Position - position)
            or Vector3.zero

        local samples: {Sample} = track.samples
        local last: Sample? = samples[#samples]
        if last then
            local delta: number = now - last.at
            -- Respawns, teleports and ownership changes must not seed a fit.
            if delta > 0 and delta < 0.4
                and (position - last.position).Magnitude > 8 + 120 * delta then
                table.clear(samples)
            end
        end
        table.insert(samples, {
            at = now,
            position = position,
            velocity = velocity,
            state = stateName,
            grounded = grounded,
            aimOffset = aimOffset,
            aimPart = aimPartName,
        })
        while #samples > 2 and now - samples[1].at > HISTORY_SECONDS do
            table.remove(samples, 1)
        end
    end

    local function fitVelocity(track: Track, now: number): Fit?
        local samples: {Sample} = track.samples
        if #samples < 3 then
            return nil
        end
        local last: Sample = samples[#samples]
        local collected: {Sample} = {}
        local sw, st, stt: number = 0, 0, 0
        local sx, sy, sz: number = 0, 0, 0
        local stx, sty, stz: number = 0, 0, 0
        for index: number = #samples, 1, -1 do
            local sample: Sample = samples[index]
            local age: number = now - sample.at
            if age > FIT_WINDOW then
                break
            end
            table.insert(collected, 1, sample)
            local dt: number = sample.at - last.at
            local weight: number = math.exp(-math.max(0, age) / FIT_TAU)
            sw += weight
            st += weight * dt
            stt += weight * dt * dt
            sx += weight * sample.position.X
            sy += weight * sample.position.Y
            sz += weight * sample.position.Z
            stx += weight * dt * sample.position.X
            sty += weight * dt * sample.position.Y
            stz += weight * dt * sample.position.Z
        end
        if #collected < 3 or sw <= 0 then
            return nil
        end
        local denominator: number = stt - st * st / sw
        if denominator <= 1e-8 then
            return nil
        end
        local meanT: number = st / sw
        local meanX: number = sx / sw
        local meanY: number = sy / sw
        local meanZ: number = sz / sw
        local vx: number = (stx - st * sx / sw) / denominator
        local vy: number = (sty - st * sy / sw) / denominator
        local vz: number = (stz - st * sz / sw) / denominator
        local squared: number = 0
        for _, sample: Sample in ipairs(collected) do
            local dt: number = sample.at - last.at
            local dx: number = sample.position.X - (meanX + vx * (dt - meanT))
            local dy: number = sample.position.Y - (meanY + vy * (dt - meanT))
            local dz: number = sample.position.Z - (meanZ + vz * (dt - meanT))
            squared += dx * dx + dy * dy + dz * dz
        end
        return {
            velocity = Vector3.new(vx, vy, vz),
            residual = math.sqrt(squared / #collected),
            count = #collected,
            span = collected[#collected].at - collected[1].at,
        }
    end

    local function estimateMotion(track: Track, now: number): Motion?
        local samples: {Sample} = track.samples
        local last: Sample? = samples[#samples]
        if not last then
            return nil
        end
        local age: number = math.max(0, now - last.at)
        if age > MAX_SAMPLE_AGE then
            return nil
        end
        local fit: Fit? = fitVelocity(track, now)
        local reported: Vector3 = last.velocity
        local horizontal: Vector3
        local source: string
        if fit and fit.count >= 3 and fit.span >= 0.06 and fit.residual <= 0.5 then
            -- Clean replicated path: the fit rejects the single-sample spikes
            -- and is not fooled by a zero AssemblyLinearVelocity.
            horizontal = Vector3.new(fit.velocity.X, 0, fit.velocity.Z)
            source = "history"
        else
            horizontal = Vector3.new(reported.X, 0, reported.Z)
            source = "replicated"
        end
        if not finiteVector(horizontal) then
            horizontal = Vector3.zero
        elseif horizontal.Magnitude > MAX_HORIZONTAL_SPEED then
            horizontal = horizontal.Unit * MAX_HORIZONTAL_SPEED
        end
        local airborne: boolean = last.state == "Jumping"
            or last.state == "Freefall"
        local vertical: number = 0
        if airborne then
            vertical = reported.Y
            if not finiteNumber(vertical) then
                vertical = 0
            elseif math.abs(vertical) < 0.5 and fit then
                vertical = fit.velocity.Y
            end
            vertical = math.clamp(vertical, -120, 120)
        end
        return {
            velocity = Vector3.new(horizontal.X, vertical, horizontal.Z),
            horizontal = horizontal,
            vertical = vertical,
            airborne = airborne,
            sampleAge = age,
            samples = #samples,
            residual = fit and fit.residual or math.huge,
            source = source,
        }
    end

    local function predictedRoot(
        track: Track,
        motion: Motion,
        horizon: number
    ): Vector3
        local last: Sample = track.samples[#track.samples]
        local x: number = last.position.X + motion.horizontal.X * horizon
        local z: number = last.position.Z + motion.horizontal.Z * horizon
        local y: number = last.position.Y
        if motion.airborne then
            y += motion.vertical * horizon
                - 0.5 * workspace.Gravity * horizon * horizon
        end
        return Vector3.new(x, y, z)
    end

    local function currentRtt(): number
        local latency: any = nil
        if type(core.getEstimatedLatency) == "function" then
            local ok: boolean, value: any = pcall(core.getEstimatedLatency)
            if ok then
                latency = value
            end
        end
        if not finiteNumber(latency) then
            latency = 0.08
        end
        return math.clamp(latency, 0.02, 0.6)
    end

    local function echoMedian(): number?
        local count: number = #echoes
        if count < MIN_ECHO_SAMPLES then
            return nil
        end
        local sorted: {number} = table.clone(echoes)
        table.sort(sorted)
        local middle: number = (count + 1) / 2
        local lower: number = math.floor(middle)
        local upper: number = math.ceil(middle)
        return (sorted[lower] + sorted[upper]) / 2
    end

    local function noteEcho(sentAt: number, receivedAt: number): ()
        if not finiteNumber(sentAt) or not finiteNumber(receivedAt) then
            return
        end
        local delay: number = receivedAt - sentAt
        if delay < 0.02 or delay > 1.2 then
            return
        end
        table.insert(echoes, delay)
        while #echoes > MAX_ECHOES do
            table.remove(echoes, 1)
        end
    end

    local function gunHorizon(): (number, number, number?)
        local rtt: number = currentRtt()
        local echo: number? = echoMedian()
        local pipeline: number = echo or rtt
        local horizon: number = pipeline
            + settings.interpolation
            + settings.extraLead
        return math.clamp(horizon, 0.005, MAX_HORIZON), rtt, echo
    end

    local function knifeHorizon(): (number, number)
        local rtt: number = currentRtt()
        local horizon: number = rtt
            + settings.interpolation
            + settings.extraLead
        return math.clamp(horizon, 0.005, MAX_HORIZON), rtt
    end

    local function gunAim(
        target: Player,
        _muzzle: Vector3
    ): (Vector3?, AimInfo?, string?)
        local track: Track? = tracks[target]
        if not track or #track.samples == 0 then
            return nil, nil, "no samples"
        end
        local now: number = os.clock()
        local motion: Motion? = estimateMotion(track, now)
        if not motion then
            return nil, nil, "stale sample"
        end
        local pipeline: number, rtt: number, echo: number? = gunHorizon()
        local horizon: number = math.clamp(
            motion.sampleAge + pipeline,
            0.005,
            MAX_HORIZON
        )
        local rootPosition: Vector3 = predictedRoot(track, motion, horizon)
        local last: Sample = track.samples[#track.samples]
        local aimOffset: Vector3 = last.aimOffset
        local endpoint: Vector3 = rootPosition + aimOffset
        return endpoint, {
            endpoint = endpoint,
            targetPosition = endpoint,
            capturedPosition = last.position + aimOffset,
            rootPosition = rootPosition,
            velocity = motion.velocity,
            leadSeconds = horizon,
            sampleAge = motion.sampleAge,
            samples = motion.samples,
            residual = motion.residual,
            motionSource = motion.source,
            model = "kinematic-v51",
            rtt = rtt,
            echoDelay = echo,
        }, nil
    end

    local function knifeAim(
        target: Player,
        origin: Vector3,
        speed: number?
    ): (Vector3?, AimInfo?, string?)
        local track: Track? = tracks[target]
        if not track or #track.samples == 0 then
            return nil, nil, "no samples"
        end
        local now: number = os.clock()
        local motion: Motion? = estimateMotion(track, now)
        if not motion then
            return nil, nil, "stale sample"
        end
        local resolvedSpeed: number = tonumber(speed) or DEFAULT_KNIFE_SPEED
        if resolvedSpeed < 24 or resolvedSpeed > 300 then
            resolvedSpeed = DEFAULT_KNIFE_SPEED
        end
        local pipeline: number, rtt: number = knifeHorizon()
        local horizon: number = math.clamp(
            motion.sampleAge + pipeline,
            0.005,
            MAX_HORIZON
        )
        local last: Sample = track.samples[#track.samples]
        local aimStart: Vector3 = last.position + last.aimOffset
        local offset: Vector3 = aimStart + motion.velocity * horizon - origin
        local flight: number? = predictionMath.interceptTime(
            offset,
            motion.velocity,
            resolvedSpeed
        )
        if not flight then
            return nil, nil, "unreachable"
        end
        local endpoint: Vector3 = aimStart
            + motion.velocity * (horizon + flight)
        if motion.airborne then
            -- A straight blade cannot follow a ballistic arc; aim at the
            -- root's projected position at impact instead of a linear Y.
            endpoint = predictedRoot(track, motion, horizon + flight)
                + last.aimOffset
        end
        return endpoint, {
            endpoint = endpoint,
            targetPosition = endpoint,
            capturedPosition = aimStart,
            rootPosition = predictedRoot(track, motion, horizon + flight),
            velocity = motion.velocity,
            leadSeconds = horizon,
            flightSeconds = flight,
            sampleAge = motion.sampleAge,
            samples = motion.samples,
            residual = motion.residual,
            motionSource = motion.source,
            model = "kinematic-v51",
            rtt = rtt,
        }, nil
    end

    local function playerStatus(target: Player?): string
        local rtt: number = currentRtt()
        local echo: number? = echoMedian()
        local parts: {string} = {
            string.format("RTT %.0f ms", rtt * 1000),
        }
        if echo then
            table.insert(
                parts,
                string.format("echo %.0f ms (%d)", echo * 1000, #echoes)
            )
        end
        table.insert(
            parts,
            string.format("interp %.0f ms", settings.interpolation * 1000)
        )
        if settings.extraLead ~= 0 then
            table.insert(
                parts,
                string.format("manual %+.0f ms", settings.extraLead * 1000)
            )
        end
        local horizon: number = (echo or rtt)
            + settings.interpolation
            + settings.extraLead
        table.insert(
            parts,
            string.format(
                "lead %.0f ms%s",
                horizon * 1000,
                horizon > MAX_HORIZON and " (capped)" or ""
            )
        )
        if target then
            local track: Track? = tracks[target]
            local motion: Motion? = track and estimateMotion(track, os.clock())
            if motion then
                table.insert(parts, string.format("%.1f studs/s", motion.horizontal.Magnitude))
                table.insert(parts, string.format("%d samples", motion.samples))
                table.insert(parts, string.format("age %.0f ms", motion.sampleAge * 1000))
                if motion.airborne then
                    table.insert(parts, "airborne")
                end
            else
                table.insert(parts, "no fresh samples")
            end
        end
        return table.concat(parts, " · ")
    end

    local controller: any = {
        settings = settings,
        noteEcho = noteEcho,
        gunAim = gunAim,
        knifeAim = knifeAim,
        status = playerStatus,
        getRtt = currentRtt,
        getEchoDelay = echoMedian,
        predict = function(player: Player, horizon: number): Vector3?
            local track: Track? = tracks[player]
            if not track or #track.samples == 0 or not finiteNumber(horizon) then
                return nil
            end
            local motion: Motion? = estimateMotion(track, os.clock())
            if not motion then
                return nil
            end
            return predictedRoot(track, motion, math.clamp(horizon, 0, 2))
        end,
        getMotion = function(player: Player): Motion?
            local track: Track? = tracks[player]
            if not track then
                return nil
            end
            return estimateMotion(track, os.clock())
        end,
        reset = function(): ()
            table.clear(echoes)
            table.clear(tracks)
        end,
    }

    local function tick(deltaTime: number): ()
        elapsed += math.max(0, deltaTime or 0)
        local interval: number = 1 / SAMPLE_HZ
        if elapsed + 1e-9 < interval then
            return
        end
        elapsed = elapsed % interval
        local now: number = os.clock()
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                samplePlayer(player, now)
            end
        end
    end

    state.mm2Prediction = controller
    featureConnections.MM2PredictionSampler = TaskManager:Connect(tick)

    activeCleanup = function(): ()
        disconnectFeatureConnection("MM2PredictionSampler")
        if state.mm2Prediction == controller then
            state.mm2Prediction = nil
        end
        table.clear(echoes)
        table.clear(tracks)
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
