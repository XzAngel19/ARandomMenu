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

      * No unmeasured heuristics. The turn (chord) and braking terms are
        computed from two weighted fits 0.10 s apart, gated on clean residuals
        and a real speed, and capped at 45 degrees / the stop distance. A
        straight run leaves both at zero; nothing here guesses.
      * No auto-tuned lead. The transport is the median of at least six fresh
        echoes inside sane pairing limits, with the smoothed RTT as fallback.
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
    -- Weighted mean sample time. The slope is the chord over the window, so
    -- this is where the measured velocity actually points.
    center: number,
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
    -- Signed yaw rate in rad/s measured between two fits. Zero when the
    -- measurement is not trustworthy (slow, noisy or too few samples).
    turnRate: number,
    -- Longitudinal acceleration along the current direction, clamped. Used
    -- only to keep the lead length honest while the target speeds up or stops.
    longitudinalAccel: number,
    -- Seconds until the target stops when it is braking hard, else nil.
    brakeSeconds: number?,
    -- How far behind `now` the fitted direction sits.
    fitLag: number,
    -- True only when the measured vertical speed is worth extrapolating. The
    -- humanoid state alone is not enough: a replicated "Jumping" pose can be a
    -- character standing at the apex of a jump.
    verticalLead: boolean,
}

type AimInfo = {
    endpoint: Vector3,
    targetPosition: Vector3,
    capturedPosition: Vector3,
    rootPosition: Vector3,
    velocity: Vector3,
    leadSeconds: number,
    turnRate: number,
    brakeSeconds: number?,
    sampleAge: number,
    samples: number,
    residual: number,
    motionSource: string,
    model: string,
    rtt: number,
    echoDelay: number?,
    -- How many echoes back the recorded delay. Zero means the horizon used
    -- the ping, which the calibration can distinguish from a real median.
    echoSamples: number,
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
-- A median of two echoes is just the mean of two mismatches. Six fresh
-- samples keep the transport estimate stable; before that the smoothed RTT is
-- the better number.
local MIN_ECHO_SAMPLES: number = 6
-- Pairing sanity limits. An echo only reaches noteEcho after base.lua matched
-- the same gun, an origin within 3.5 studs and a direction within ~15 degrees,
-- so a late sample is our own shot, not a crossed one. The upper bound mirrors
-- the 1.6 s pending-shot window in base.lua; the v18 session has a confirmed
-- 1007.7 ms echo at 270.3 ms ping, which an 800 ms cut would have thrown away.
local MIN_ECHO_DELAY: number = 0.05
local MAX_ECHO_DELAY: number = 1.6
-- Transport + manual lead. A full second only happens when the session ping
-- or the manual offset asks for it; the status line shows the real number.
local MAX_HORIZON: number = 1.0
-- Automatic lead never exceeds this. At 16 studs/s a 1 s lead is 16 studs of
-- overshoot; past 0.6 s the sample is stale enough that refusing to invent
-- more distance is safer. Manual offset is still allowed up to MAX_HORIZON.
local MAX_AUTO_LEAD: number = 0.6
-- Turn and braking corrections are measured, never guessed:
--   * two weighted fits 0.10 s apart give a signed yaw rate;
--   * the same pair gives longitudinal acceleration for the stop cap.
local TURN_SPAN: number = 0.10
local TURN_MIN_SPEED: number = 2.0
local TURN_MAX_RATE: number = 10.0
-- Below ~23 deg/s the two fits are mostly replication jitter; a correction
-- that small only adds noise to the endpoint.
local TURN_MIN_RATE: number = 0.4
local TURN_MAX_ANGLE: number = math.rad(45)
-- Two fits over replicated poses disagree by jitter as much as by turning.
-- At 0.5 the recorded session produced 224 deg and 152 deg turns on a
-- straight run; at 0.20 the shots with a >100 deg turn drop from five to two
-- and the measured aim improves, so this is where the noise stops.
local TURN_RESIDUAL: number = 0.20
-- Vertical extrapolation needs a real vertical speed. A humanoid reported as
-- Jumping at its apex has almost no vertical velocity; dropping the aim by a
-- full ballistic term there is what put shot 6 2.3 studs under the target.
local VERTICAL_MIN_SPEED: number = 5.0
-- Robust transport fallback: a single GetNetworkPing spike (0.31 s against a
-- 0.107 s baseline in the 2026-10-18 session) must not move the next aim.
local RTT_SAMPLES: number = 8
local RTT_SAMPLE_INTERVAL: number = 0.25
local BRAKE_MIN_ACCEL: number = 6.0
local BRAKE_MAX_ACCEL: number = 120.0

local settings = {
    -- Automatic lead is the default: the measured FireServer -> GunFired echo
    -- (fallback: smoothed ping) already includes the device/network timing.
    -- Manual offset is only used when autoLead is turned off.
    autoLead = true,
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

    local function fitVelocity(track: Track, reference: number): Fit?
        local samples: {Sample} = track.samples
        if #samples < 3 then
            return nil
        end
        -- Collect the window that ends at `reference`, not necessarily at the
        -- newest sample: the same weights applied to an older window give the
        -- velocity direction 0.10 s ago, which is what the turn rate needs.
        local collected: {Sample} = {}
        for index: number = #samples, 1, -1 do
            local sample: Sample = samples[index]
            if sample.at <= reference + 1e-4 then
                if reference - sample.at > FIT_WINDOW then
                    break
                end
                table.insert(collected, 1, sample)
            end
        end
        if #collected < 3 then
            return nil
        end
        local anchor: number = collected[#collected].at
        local sw, st, stt: number = 0, 0, 0
        local sx, sy, sz: number = 0, 0, 0
        local stx, sty, stz: number = 0, 0, 0
        for _, sample: Sample in ipairs(collected) do
            local dt: number = sample.at - anchor
            local age: number = math.max(0, reference - sample.at)
            local weight: number = math.exp(-age / FIT_TAU)
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
        if sw <= 0 then
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
            local dt: number = sample.at - anchor
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
            center = reference + meanT,
        }
    end

    -- Two fits 0.10 s apart: their directions give the signed yaw rate, their
    -- magnitudes give the longitudinal braking. Everything is gated on a clean
    -- fit and a real speed, so noise and near-stationary targets stay at zero.
    local function measureTurn(
        track: Track,
        now: number,
        fit: Fit
    ): (number, number, number?, number)
        local fitLag: number = math.max(0, now - fit.center)
        if fit.count < 3 or fit.span < 0.06 or fit.residual > TURN_RESIDUAL then
            return 0, 0, nil, fitLag
        end
        local previous: Fit? = fitVelocity(track, now - TURN_SPAN)
        if not previous or previous.count < 3 or previous.span < 0.04
            or previous.residual > TURN_RESIDUAL then
            return 0, 0, nil, fitLag
        end
        local v0: Vector3 = Vector3.new(previous.velocity.X, 0, previous.velocity.Z)
        local v1: Vector3 = Vector3.new(fit.velocity.X, 0, fit.velocity.Z)
        if v0.Magnitude < TURN_MIN_SPEED or v1.Magnitude < TURN_MIN_SPEED then
            return 0, 0, nil, fitLag
        end
        local dt: number = math.max(0.04, fit.center - previous.center)
        local cross: number = v0.Z * v1.X - v0.X * v1.Z
        local dot: number = v0.X * v1.X + v0.Z * v1.Z
        local rate: number = math.clamp(
            math.atan2(cross, dot) / dt,
            -TURN_MAX_RATE,
            TURN_MAX_RATE
        )
        if math.abs(rate) < TURN_MIN_RATE then
            rate = 0
        end
        local ax: number = (v1.X - v0.X) / dt
        local az: number = (v1.Z - v0.Z) / dt
        local speed: number = v1.Magnitude
        local along: number = math.clamp(
            (ax * v1.X + az * v1.Z) / speed,
            -BRAKE_MAX_ACCEL,
            BRAKE_MAX_ACCEL
        )
        local brakeSeconds: number? = nil
        if along <= -BRAKE_MIN_ACCEL then
            local currentSpeed: number = math.max(0, speed + along * fitLag)
            brakeSeconds = currentSpeed / -along
        end
        return rate, along, brakeSeconds, fitLag
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
        local turnRate: number = 0
        local longitudinalAccel: number = 0
        local brakeSeconds: number? = nil
        local fitLag: number = 0
        local verticalLead: boolean = false
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
        if fit then
            turnRate, longitudinalAccel, brakeSeconds, fitLag =
                measureTurn(track, now, fit)
        end
        if airborne and math.abs(vertical) >= VERTICAL_MIN_SPEED then
            verticalLead = true
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
            turnRate = turnRate,
            longitudinalAccel = longitudinalAccel,
            brakeSeconds = brakeSeconds,
            fitLag = fitLag,
            verticalLead = verticalLead,
        }
    end

    -- Lead displacement for a horizon, with the measured turn and braking.
    -- The fitted direction sits `fitLag` behind now, and the chord over the
    -- horizon points at the tangent halfway through it, so the rotation is
    -- rate * (horizon/2 + fitLag). Capped at 45 degrees on purpose: a larger
    -- correction is a turn the samples cannot describe anymore.
    local function leadHorizontal(motion: Motion, horizon: number): Vector3
        local speed: number = motion.horizontal.Magnitude
        if speed < 1e-4 or horizon <= 0 then
            return Vector3.zero
        end
        local direction: Vector3 = motion.horizontal.Unit
        if math.abs(motion.turnRate) > 1e-3 then
            local angle: number = math.clamp(
                motion.turnRate * (horizon * 0.5 + motion.fitLag),
                -TURN_MAX_ANGLE,
                TURN_MAX_ANGLE
            )
            local cosine: number = math.cos(angle)
            local sine: number = math.sin(angle)
            direction = Vector3.new(
                direction.X * cosine + direction.Z * sine,
                0,
                -direction.X * sine + direction.Z * cosine
            )
        end
        -- The fit is a chord over the window, so it lags the current speed.
        -- Correct it by the measured longitudinal acceleration over that lag,
        -- and include the acceleration over the horizon itself. Both terms
        -- are clamped in measureTurn; a clean straight run leaves them at 0.
        -- Only deceleration earns a length correction. In the recorded v61
        -- session the measured "acceleration" of a running target swung to the
        -- +120 clamp and stretched the lead by 1.5 studs; a real stop is the
        -- case that matters and it is a negative value.
        local along: number = math.min(0, motion.longitudinalAccel)
        local speedNow: number = math.max(0, speed + along * motion.fitLag)
        local length: number = speedNow * horizon
            + 0.5 * along * horizon * horizon
        length = math.max(0, length)
        if motion.brakeSeconds and horizon > motion.brakeSeconds then
            -- The target is already stopped by then; extrapolating further
            -- would aim past it.
            length = math.min(
                length,
                speedNow * motion.brakeSeconds * 0.5
            )
        end
        return direction * length
    end

    local function predictedRoot(
        track: Track,
        motion: Motion,
        horizon: number
    ): Vector3
        local last: Sample = track.samples[#track.samples]
        local lead: Vector3 = leadHorizontal(motion, horizon)
        local x: number = last.position.X + lead.X
        local z: number = last.position.Z + lead.Z
        local y: number = last.position.Y
        if motion.verticalLead then
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

    -- A median of recent readings, not the live number. A single spike in the
    -- engine estimate produced leads of 0.36-0.40 s against a 0.13 s baseline
    -- on 2026-10-18, and both of those shots missed by 7+ studs.
    local rttSamples: {number} = {}
    local lastRttSampleAt: number = -math.huge
    local function robustRtt(): number
        local now: number = os.clock()
        if now - lastRttSampleAt >= RTT_SAMPLE_INTERVAL then
            lastRttSampleAt = now
            table.insert(rttSamples, currentRtt())
            while #rttSamples > RTT_SAMPLES do
                table.remove(rttSamples, 1)
            end
        end
        local sorted: {number} = table.clone(rttSamples)
        table.insert(sorted, currentRtt())
        table.sort(sorted)
        return sorted[math.floor((#sorted + 1) / 2)]
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
        if delay < MIN_ECHO_DELAY or delay > MAX_ECHO_DELAY then
            return
        end
        table.insert(echoes, delay)
        while #echoes > MAX_ECHOES do
            table.remove(echoes, 1)
        end
    end

    local function manualLead(): number
        return settings.autoLead and 0 or settings.extraLead
    end

    local function gunHorizon(): (number, number, number?)
        local rtt: number = robustRtt()
        local echo: number? = echoMedian()
        -- The echo is measured client-side from the activation to the
        -- confirmation, so it is a real round trip rather than an engine
        -- estimate; it replaces the ping when a median exists. It has to be
        -- measured from the confirmation path for that to happen at all:
        -- v61 recorded none (`echoDelay` nil on all 13 shots).
        local pipeline: number = echo or rtt
        local horizon: number = pipeline
            + settings.interpolation
            + manualLead()
        if settings.autoLead then
            horizon = math.min(horizon, MAX_AUTO_LEAD)
        end
        return math.clamp(horizon, 0.005, MAX_HORIZON), rtt, echo
    end

    local function knifeHorizon(): (number, number)
        local rtt: number = robustRtt()
        local horizon: number = rtt
            + settings.interpolation
            + manualLead()
        if settings.autoLead then
            horizon = math.min(horizon, MAX_AUTO_LEAD)
        end
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
            echoSamples = #echoes,
            turnRate = motion.turnRate,
            brakeSeconds = motion.brakeSeconds,
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
        local initial: Vector3 = motion.velocity
        local flight: number? = predictionMath.interceptTime(
            aimStart + initial * horizon - origin,
            initial,
            resolvedSpeed
        )
        if not flight then
            return nil, nil, "unreachable"
        end
        -- One re-solve with the average velocity over the whole flight: a
        -- turning or braking target does not travel along the instantaneous
        -- tangent, and the blade needs the chord.
        local span: number = horizon + flight
        local lead: Vector3 = leadHorizontal(motion, span)
        local vertical: number = motion.verticalLead and motion.vertical or 0
        if motion.verticalLead then
            vertical -= 0.5 * workspace.Gravity * span
        end
        local effective: Vector3 = Vector3.new(
            lead.X,
            vertical * span,
            lead.Z
        ) / span
        local revised: number? = predictionMath.interceptTime(
            aimStart + effective * horizon - origin,
            effective,
            resolvedSpeed
        )
        if revised then
            flight = revised
            span = horizon + flight
            lead = leadHorizontal(motion, span)
            vertical = motion.verticalLead and motion.vertical or 0
            if motion.verticalLead then
                vertical -= 0.5 * workspace.Gravity * span
            end
            effective = Vector3.new(lead.X, vertical * span, lead.Z) / span
        end
        local endpoint: Vector3 = aimStart + effective * (horizon + flight)
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
            echoSamples = #echoes,
            turnRate = motion.turnRate,
            brakeSeconds = motion.brakeSeconds,
        }, nil
    end

    local function playerStatus(target: Player?): string
        local rtt: number = robustRtt()
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
        if settings.autoLead then
            table.insert(
                parts,
                echo and "auto lead (echo)" or "auto lead (ping)"
            )
        elseif settings.extraLead ~= 0 then
            table.insert(
                parts,
                string.format("manual %+.0f ms", settings.extraLead * 1000)
            )
        end
        local horizon: number = (echo or rtt)
            + settings.interpolation
            + manualLead()
        local capped: boolean = false
        if settings.autoLead and horizon > MAX_AUTO_LEAD then
            horizon = MAX_AUTO_LEAD
            capped = true
        end
        if horizon > MAX_HORIZON then
            horizon = MAX_HORIZON
            capped = true
        end
        table.insert(
            parts,
            string.format(
                "lead %.0f ms%s",
                horizon * 1000,
                capped and " (capped)" or ""
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
                if math.abs(motion.turnRate) > 0.05 then
                    table.insert(
                        parts,
                        string.format("turn %+.0f deg/s", math.deg(motion.turnRate))
                    )
                end
                if motion.brakeSeconds then
                    table.insert(
                        parts,
                        string.format("brake %.2f s", motion.brakeSeconds)
                    )
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
        -- The movement window that ends at the call, oldest first, with `at`
        -- in seconds relative to now (negative). Telemetry attaches it to each
        -- shot so an alternative predictor can be replayed offline from the
        -- same inputs instead of being judged only on live hits.
        getHistory = function(
            player: Player,
            seconds: number?
        ): ({any}?, number?)
            local track: Track? = tracks[player]
            if not track or #track.samples < 2 then
                return nil, 0
            end
            local span: number = math.clamp(
                seconds or HISTORY_SECONDS,
                0.05,
                HISTORY_SECONDS
            )
            -- Times are relative to the newest sample, not to this call. The
            -- modules do not share a clock epoch (the v61 log recorded a
            -- -2546 s offset), so only the predictor's own timestamps can be
            -- subtracted from each other. The caller gets the age separately.
            local newest: Sample = track.samples[#track.samples]
            local age: number = math.max(0, os.clock() - newest.at)
            local points: {any} = {}
            for _, sample: Sample in ipairs(track.samples) do
                local at: number = sample.at - newest.at
                if at >= -span - 1e-6 then
                    table.insert(points, {
                        at = at,
                        position = sample.position,
                        velocity = sample.velocity,
                        state = sample.state,
                        grounded = sample.grounded,
                    })
                end
            end
            if #points < 2 then
                return nil, age
            end
            return points, age
        end,
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
            table.clear(rttSamples)
            lastRttSampleAt = -math.huge
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
