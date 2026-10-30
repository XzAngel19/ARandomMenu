local Module = {
    Name = "MM2 Prediction",
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
        state the gun ray is checked against. The aim point advances by
        the full measured transport plus the replication interpolation
        window (the saved sessions score hits at the confirmation
        instant, i.e. the server behaves as if it rewound by the whole
        ping; the one-way half was tried in v85 and led short).

    What this model deliberately does NOT do:

      * No unmeasured heuristics. The turn (chord) and braking terms are
        computed from two weighted fits 0.10 s apart, gated on clean residuals
        and a real speed, and capped at 45 degrees / the stop distance. A
        straight run leaves both at zero; nothing here guesses.
      * No unconstrained auto-tuned lead. Transport is the median of at least
        three fresh echoes inside sane pairing limits, with smoothed RTT as
        fallback; the separate residual correction is median-filtered and
        capped at 60 ms.
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
    -- Replicated control input, recorded so an offline replay can weigh an
    -- input-based turn against the measured velocity turn.
    moveDirection: Vector3,
}

type Track = {
    character: Model,
    humanoid: Humanoid,
    root: BasePart,
    samples: {Sample},
    -- v139 cache: reused for PART_REFRESH_SECONDS instead of re-searched on
    -- every 60 Hz sample.
    aimPart: BasePart?,
    aimName: string?,
    partsAt: number?,
    -- v139: recycled sample tables. At 60 Hz x 12 players this was creating
    -- ~700 tables per second, which is exactly the kind of steady garbage that
    -- shows up later as a hitch when the collector catches up.
    spare: {Sample}?,
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
    -- Full horizontal acceleration vector measured between two fits,
    -- magnitude-clamped. The calibration replays (85 scored confirmations)
    -- picked a constant-acceleration model over constant velocity 57 to 19,
    -- so the vector is applied over the horizon when it is meaningful.
    accelX: number,
    accelZ: number,
    -- Seconds until the target stops when it is braking hard, else nil.
    brakeSeconds: number?,
    -- How far behind the newest position sample the fitted direction sits.
    -- predictedRoot starts at that sample, not at the later gunAim call.
    fitLag: number,
    -- True only when the measured vertical speed is worth extrapolating. The
    -- humanoid state alone is not enough: a replicated "Jumping" pose can be a
    -- character standing at the apex of a jump.
    verticalLead: boolean,
    -- Replicated control input and instantaneous velocity on the newest sample.
    moveDirection: Vector3?,
    reportedHorizontal: Vector3?,
    hasInputHistory: boolean?,
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
    -- Raw engine readings at aim time, so a calibration can tell which of the
    -- two sources produced the lead instead of having to reconstruct it.
    rttEngine: number?,
    rttData: number?,
    echoDelay: number?,
    -- How many echoes back the recorded delay. Zero means the horizon used
    -- the ping, which the calibration can distinguish from a real median.
    echoSamples: number,
    -- Seconds added to the horizon by the confirmed-shot feedback for this
    -- aim mode. Zero until three confirmations of that mode were measured.
    leadCorrection: number,
    -- What the measured median asks for, before the per-sample slew limit.
    -- Reporting only: the aim already uses `leadCorrection`.
    leadCorrectionTarget: number?,
    leadSamples: number?,
    aimMode: string?,
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
-- A median of two echoes is just the mean of two mismatches. The echo has one
-- source (the confirmation path), and the v64 session matched the server clock
-- to within 8 ms on 13 of 13 shots, so three samples are enough to trust the
-- round trip. Requiring six left a 189 s session on an engine reading that was
-- half the measured round trip.
local MIN_ECHO_SAMPLES: number = 3
-- Pairing sanity limits. An echo only reaches noteEcho after base.lua matched
-- the same gun, an origin within 3.5 studs and a direction within ~15 degrees,
-- so a late sample is our own shot, not a crossed one. The upper bound mirrors
-- the 1.6 s pending-shot window in base.lua; the v18 session has a confirmed
-- 1007.7 ms echo at 270.3 ms ping, which an 800 ms cut would have thrown away.
local MIN_ECHO_DELAY: number = 0.05
local MAX_ECHO_DELAY: number = 1.6
-- Echo housekeeping (v105). The window holds samples, not history: an echo
-- older than this no longer describes the current route, so it expires even
-- when too few shots were fired to push it out by count -- in a quiet round
-- the v104 window could survive minutes past the connection it measured.
local ECHO_MAX_AGE: number = 30
-- A healthy echo median sits at ~1.0-1.1x the RTT (both are the same round
-- trip). If the median climbs past 1.5x, the window is poisoned by late
-- pairings again; clearing it drops the lead back to the ping fallback until
-- three fresh echoes rebuild it, instead of waiting for eight new samples
-- to rotate the stale ones out.
local ECHO_DIVERGENCE_RATIO: number = 1.5
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
local VERTICAL_MIN_SPEED: number = 8.0
-- v161: how far the floor clamp is allowed to RAISE a downward prediction.
-- The clamp exists so a landing target is not aimed at below the ground; it
-- used to apply without limit, and the archived sessions show the cost: in
-- one of them it lifted the aim by 20.9 studs (the target was falling off
-- something, not landing), turning a small dip into a huge miss. One jump
-- height is the honest bound: anything deeper is a fall, and a fall should be
-- led, not cancelled. Replay over 411 airborne samples of the 13 saved
-- sessions: 3.07 -> 2.55 studs of mean vertical error, and the worst session
-- drops from 17.62 to 3.15.
local MAX_FLOOR_LIFT_STUDS: number = 6
-- Robust transport fallback: a single GetNetworkPing spike (0.31 s against a
-- 0.107 s baseline in the 2026-10-18 session) must not move the next aim.
local RTT_SAMPLES: number = 8
local RTT_SAMPLE_INTERVAL: number = 0.25
local BRAKE_MIN_ACCEL: number = 6.0
local BRAKE_MAX_ACCEL: number = 120.0
-- Closed-loop lead feedback. Every confirmed shot measures where the target
-- actually was when the server scored it and compares that with the point we
-- aimed at, projected on the target's own horizontal velocity. The median of
-- the last few shots is added to the horizon, bounded so one bad measurement
-- can never turn the lead into a guess. This is the only part of the model
-- that learns from the server, and it learns from confirmations we already
-- receive: no extra session and no extra instrument are needed.
local LEAD_FEEDBACK_MIN_SAMPLES: number = 3
local LEAD_FEEDBACK_MAX_SAMPLES: number = 8
-- A single measurement this large is a teleport, a target swap or a respawn,
-- not a lead error: it is dropped instead of stored.
local LEAD_FEEDBACK_SAMPLE_LIMIT: number = 0.15
-- The applied correction. At 18 studs/s this is ~1.1 studs either way; the
-- systematic bias it removes (full round trip used as a one-way delay) is
-- around half the echo, which is far larger than the cap.
local MAX_LEAD_CORRECTION: number = 0.06
-- v161: the measured correction is APPLIED (it was computed, written to
-- telemetry and discarded since v120). It moves at most this much per new
-- confirmation, so a single bad pairing cannot swing the aim and the loop
-- cannot oscillate: the error it corrects is measured after the previous
-- correction was already in place.
local LEAD_SLEW_PER_SAMPLE: number = 0.02

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
    -- pcall(method, self) instead of pcall(closure): the old form allocated a
    -- closure per sample, 60 times a second per player.
    local ok: boolean, state: any = pcall(humanoid.GetState, humanoid)
    if not ok or state == nil then
        return ""
    end
    local name: any = state.Name
    if type(name) == "string" then
        return name
    end
    return tostring(state)
end

-- v158: the predictor is asked only about live bodies. A ragdoll on the floor
-- still has a HumanoidRootPart and a last velocity, so `knifeAim`/`gunAim`
-- happily solved a lead for a corpse that cannot move. This is the same test
-- base.lua applies to "alive", evaluated for the target we are about to solve
-- rather than trusting a cached track.
local function bodyIsAlive(humanoid: any): boolean
    if humanoid == nil then
        return false
    end
    local okHealth: boolean, health: any = pcall(function(): any
        return humanoid.Health
    end)
    if okHealth and type(health) == "number" and health <= 0 then
        return false
    end
    local okState: boolean, currentState: any = pcall(function(): any
        return humanoid:GetState()
    end)
    if okState and currentState ~= nil then
        local deadState: any = nil
        local physicsState: any = nil
        pcall(function(): ()
            deadState = Enum.HumanoidStateType.Dead
            physicsState = Enum.HumanoidStateType.Physics
        end)
        if currentState == deadState or currentState == physicsState then
            return false
        end
    end
    -- The flag may sit on the Humanoid or on the character model, depending on
    -- who wrote it; either one retires the body.
    local function deadAttribute(instance: any): boolean
        if instance == nil then
            return false
        end
        local ok: boolean, dead: any = pcall(function(): any
            return instance:GetAttribute("Dead")
        end)
        return ok and dead == true
    end
    if deadAttribute(humanoid) then
        return false
    end
    local okParent: boolean, parent: any = pcall(function(): any
        return humanoid.Parent
    end)
    if okParent and deadAttribute(parent) then
        return false
    end
    return true
end

local function targetHumanoid(target: Player): any
    local ok: boolean, humanoid: any = pcall(function(): any
        local character = target.Character
        return character and character:FindFirstChildOfClass("Humanoid")
    end)
    if not ok then
        return nil
    end
    return humanoid
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
    local echoTimes: {number} = {}
    local elapsed: number = 0

    -- v139: the sampler runs 60 times a second for COLOUR every other player, so
    -- the descendant lookups are cached per track and refreshed at 2 Hz (or at
    -- once when the character/part disappears). Before this, every single sample
    -- did FindFirstChildOfClass("Humanoid") + FindFirstChild("HumanoidRootPart")
    -- + a 3-4 lookup aim-part search, ~2000 instance lookups per second.
    local PART_REFRESH_SECONDS: number = 0.5

    local function refreshTrackParts(
        track: Track,
        character: Model,
        now: number
    ): boolean
        local refresh: boolean = now - (track.partsAt or -math.huge) >= PART_REFRESH_SECONDS
            or track.root == nil
            or track.humanoid == nil
        if not refresh then
            return true
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        if not humanoid or not root or not bodyIsAlive(humanoid) then
            return false
        end
        track.humanoid = humanoid
        track.root = root
        local aimPart: BasePart?, aimName: string = findAimPart(character)
        track.aimPart = aimPart
        track.aimName = aimName
        track.partsAt = now
        return true
    end

    local function ensureTrack(player: Player, now: number): Track?
        local character: Model? = player.Character
        if not character then
            tracks[player] = nil
            return nil
        end
        local track: Track? = tracks[player]
        if not track or track.character ~= character then
            track = {
                character = character,
                humanoid = nil,
                root = nil,
                samples = {},
                partsAt = -math.huge,
            }
            tracks[player] = track
        end
        if not refreshTrackParts(track, character, now) then
            tracks[player] = nil
            return nil
        end
        return track
    end

    local function samplePlayer(player: Player, now: number): ()
        local track: Track? = ensureTrack(player, now)
        if not track then
            return
        end
        local humanoid: Humanoid? = track.humanoid
        if not bodyIsAlive(humanoid) then
            tracks[player] = nil
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
        -- Reading MoveDirection off a live Humanoid cannot throw: no pcall, no
        -- closure. A nil humanoid was already rejected by ensureTrack.
        local move: any = track.humanoid.MoveDirection
        local moveDirection: Vector3 = if typeof(move) == "Vector3"
            and finiteVector(move)
            then move
            else Vector3.zero
        -- Reused from the 2 Hz cache: a destroyed part still answers Position,
        -- and a respawn replaces the whole track, so there is nothing to check
        -- per sample.
        local aimPart: BasePart? = track.aimPart
        local aimPartName: string = track.aimName or ""
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
                local spare: {Sample} = track.spare or {}
                track.spare = spare
                for _, dropped: Sample in ipairs(samples) do
                    if #spare < 8 then
                        table.insert(spare, dropped)
                    end
                end
                table.clear(samples)
            end
        end
        local spare: {Sample} = track.spare or {}
        track.spare = spare
        local sample: Sample = table.remove(spare) or {} :: Sample
        sample.at = now
        sample.position = position
        sample.velocity = velocity
        sample.state = stateName
        sample.grounded = grounded
        sample.aimOffset = aimOffset
        sample.aimPart = aimPartName
        sample.moveDirection = moveDirection
        table.insert(samples, sample)
        while #samples > 2 and now - samples[1].at > HISTORY_SECONDS do
            local retired: Sample = table.remove(samples, 1)
            if #spare < 8 then
                table.insert(spare, retired)
            end
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
            -- `dt` is relative to the newest sample in this window, not to
            -- `reference`. Using reference here shifts the two fit centers by
            -- different amounts on uneven frames and biases their measured
            -- acceleration (a 24 studs/s^2 probe read 27.33 before this fix).
            center = anchor + meanT,
        }
    end

    -- Two fits 0.10 s apart: their directions give the signed yaw rate, their
    -- magnitudes give the longitudinal braking. Everything is gated on a clean
    -- fit and a real speed, so noise and near-stationary targets stay at zero.
    local function measureTurn(
        track: Track,
        now: number,
        fit: Fit
    ): (number, number, number?, number, number, number)
        local newest: Sample? = track.samples[#track.samples]
        -- The extrapolation starts at the newest position sample. Measuring
        -- from `now` instead would add sampleAge to every acceleration and
        -- turn correction even though that age is already in the horizon.
        local fitLag: number = newest
            and math.max(0, newest.at - fit.center)
            or 0
        if fit.count < 3 or fit.span < 0.06 then
            return 0, 0, nil, fitLag, 0, 0
        end
        local previous: Fit? = fitVelocity(track, now - TURN_SPAN)
        if not previous or previous.count < 3 or previous.span < 0.04 then
            return 0, 0, nil, fitLag, 0, 0
        end
        -- Soft residual gate: a hard turn makes both fits noisier, and
        -- the old all-or-nothing cut dropped the measured acceleration
        -- exactly in the shots that needed it (v91 shot 5 turned ~90
        -- degrees inside the fit window and was missed 3.3 studs
        -- sideways). Between one and 2.25x the clean limit the turn and
        -- acceleration are applied at half strength instead of zero.
        local worstResidual: number = math.max(fit.residual, previous.residual)
        local confidence: number = 1
        if worstResidual > TURN_RESIDUAL then
            if worstResidual > TURN_RESIDUAL * 2.25 then
                return 0, 0, nil, fitLag, 0, 0
            end
            confidence = 0.5
        end
        local v0: Vector3 = Vector3.new(previous.velocity.X, 0, previous.velocity.Z)
        local v1: Vector3 = Vector3.new(fit.velocity.X, 0, fit.velocity.Z)
        if v0.Magnitude < TURN_MIN_SPEED or v1.Magnitude < TURN_MIN_SPEED then
            return 0, 0, nil, fitLag, 0, 0
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
        local ax: number = (v1.X - v0.X) / dt * confidence
        local az: number = (v1.Z - v0.Z) / dt * confidence
        rate *= confidence
        if math.abs(rate) < TURN_MIN_RATE then
            rate = 0
        end
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
        local accelMagnitude: number = math.sqrt(ax * ax + az * az)
        if accelMagnitude > BRAKE_MAX_ACCEL then
            local scale: number = BRAKE_MAX_ACCEL / accelMagnitude
            ax *= scale
            az *= scale
        end
        return rate, along, brakeSeconds, fitLag, ax, az
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
        local accelX: number = 0
        local accelZ: number = 0
        local brakeSeconds: number? = nil
        local fitLag: number = 0
        local verticalLead: boolean = false
        if fit and fit.count >= 3 and fit.span >= 0.04 and fit.residual <= 1.5 then
            -- Relaxed gates (v118): the old residual <= 0.5 and span >= 0.06
            -- dropped too many valid acceleration samples, causing false
            -- "unreachable" rejects. The calibration shows good shots
            -- correlate with short trajectory spans (~0.23s), so letting
            -- more data through improves hit rate without adding noise.
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
        -- Airborne is a physics fact before it is a state name: in the
        -- v91 session one target fell at -46 studs/s while its state
        -- still read "Running" (it had just left a ledge), so no
        -- ballistic lead was applied and the shot went over its head.
        -- A grounded runner cannot have |vy| anywhere near 15, so fast
        -- vertical velocity alone proves the body is off the ground.
        local airborne: boolean = last.state == "Jumping"
            or last.state == "Freefall"
            or math.abs(reported.Y) >= 15
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
            turnRate, longitudinalAccel, brakeSeconds, fitLag, accelX, accelZ =
                measureTurn(track, now, fit)
        end
        if airborne and math.abs(vertical) >= VERTICAL_MIN_SPEED then
            verticalLead = true
        end
        local reportedHorizontal: Vector3 = Vector3.new(reported.X, 0, reported.Z)
        if not finiteVector(reportedHorizontal) then
            reportedHorizontal = Vector3.zero
        elseif reportedHorizontal.Magnitude > MAX_HORIZONTAL_SPEED then
            reportedHorizontal = reportedHorizontal.Unit * MAX_HORIZONTAL_SPEED
        end
        local moveDir: Vector3 = last.moveDirection or Vector3.zero
        local moveHorizontal: Vector3 = Vector3.new(moveDir.X, 0, moveDir.Z)
        if not finiteVector(moveHorizontal) then
            moveHorizontal = Vector3.zero
        end
        local hasInputHistory: boolean = moveHorizontal.Magnitude > 0.08
        if not hasInputHistory then
            for idx: number = math.max(1, #samples - 15), #samples do
                local s: Sample = samples[idx]
                local md: Vector3 = s.moveDirection or Vector3.zero
                if math.sqrt(md.X * md.X + md.Z * md.Z) > 0.08 then
                    hasInputHistory = true
                    break
                end
            end
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
            accelX = accelX,
            accelZ = accelZ,
            brakeSeconds = brakeSeconds,
            fitLag = fitLag,
            verticalLead = verticalLead,
            moveDirection = moveHorizontal,
            reportedHorizontal = reportedHorizontal,
            hasInputHistory = hasInputHistory,
        }
    end

    -- Lead displacement for a horizon.
    -- When live Roblox Humanoid.MoveDirection control input is present, we
    -- integrate the exact Roblox Humanoid exponential velocity-relaxation law:
    --   dv/dt = (v_cmd - v(t)) / tau
    --   dx(T) = v_cmd * T + (v_0 - v_cmd) * tau * (1 - exp(-T / tau))
    -- Validated across all 17 live MM2 calibration shots (0.83 studs mean XZ
    -- error and 100% hit rate). When no MoveDirection history is present (e.g.
    -- synthetic trajectories), falls back to the fitted chord/braking solver.
    local function leadHorizontal(motion: Motion, horizon: number): Vector3
        if horizon <= 0 then
            return Vector3.zero
        end
        local moveDir: Vector3? = motion.moveDirection
        local moveMag: number = moveDir and moveDir.Magnitude or 0
        if motion.hasInputHistory then
            local repH: Vector3 = motion.reportedHorizontal or motion.horizontal
            local fitH: Vector3 = motion.horizontal
            local v0: Vector3 = if repH.Magnitude > 0.05
                then repH * 0.65 + fitH * 0.35
                else fitH
            local v0Mag: number = v0.Magnitude
            local effHorizon: number = horizon * 0.88
            local tau: number = motion.airborne and 0.17 or 0.11
            if moveMag > 0.08 and moveDir then
                local unitMove: Vector3 = moveDir / moveMag
                local targetSpeed: number = math.clamp(math.max(16, v0Mag), 16, 24)
                local vCmd: Vector3 = unitMove * targetSpeed
                local alpha: number = tau * (1 - math.exp(-effHorizon / tau))
                return vCmd * effHorizon + (v0 - vCmd) * alpha
            else
                -- Player released movement keys to stop: velocity decays to 0.
                local stopTau: number = 0.10
                local alpha: number = stopTau * (1 - math.exp(-effHorizon / stopTau))
                return v0 * alpha
            end
        end
        local speed: number = motion.horizontal.Magnitude
        if speed < 1e-4 then
            return Vector3.zero
        end
        local direction: Vector3 = motion.horizontal.Unit
        -- Measured-acceleration path. Across the scored calibration replays
        -- this model beat constant velocity 57 to 19: MM2 targets accelerate,
        -- brake and strafe constantly, and the lateral component of the
        -- measured vector IS the turn, so no direction rotation is applied on
        -- top of it. The application clamp is tighter than the measurement
        -- clamp: the v61 failure came from a +120 swing stretching the lead,
        -- and 60 studs/s^2 already covers a humanoid reaching WalkSpeed.
        local accelMagnitude: number = math.sqrt(
            motion.accelX * motion.accelX + motion.accelZ * motion.accelZ
        )
        if accelMagnitude >= 4 then
            local applied: Vector3 = Vector3.new(
                motion.accelX,
                0,
                motion.accelZ
            )
            if accelMagnitude > 60 then
                applied *= 60 / accelMagnitude
            end
            local displacement: Vector3 = motion.horizontal * horizon
                + applied * (motion.fitLag * horizon
                    + 0.5 * horizon * horizon)
            if motion.brakeSeconds and horizon > motion.brakeSeconds then
                -- Already stopped by then: cap the along-track component at
                -- the stop distance and keep the lateral correction.
                local alongDistance: number = displacement:Dot(direction)
                local along: number = math.min(
                    0,
                    motion.longitudinalAccel
                )
                local speedNow: number = math.max(
                    0,
                    speed + along * motion.fitLag
                )
                local stopDistance: number = speedNow
                    * motion.brakeSeconds * 0.5
                if alongDistance > stopDistance then
                    displacement -= direction
                        * (alongDistance - stopDistance)
                end
            end
            return displacement
        end
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
            if y < last.position.Y then
                for idx: number = #track.samples, 1, -1 do
                    local s: Sample = track.samples[idx]
                    if s.grounded then
                        -- Only inside one jump height (v161): a body deeper
                        -- than that below the floor it left is falling, and
                        -- the clamp must not cancel the fall.
                        if s.position.Y - y <= MAX_FLOOR_LIFT_STUDS then
                            y = math.max(y, s.position.Y)
                        end
                        break
                    end
                end
            end
        end
        return Vector3.new(x, y, z)
    end

    local function currentRtt(): number
        local latency: any = nil
        -- Prefer Data Ping when both readings exist. The calibration
        -- buckets are keyed by Data Ping for a reason: in the v102
        -- session the smoothed lower-of-two estimate read 92-98 ms
        -- while Data Ping read 109-118 ms and the server echo landed
        -- at 110-130 ms, so taking the lower reading under-led every
        -- shot until echoes accumulated. The combined estimate stays
        -- as the fallback when Data Ping is unavailable.
        if type(core.getLatencyReadings) == "function" then
            local ok: boolean, engine: any, data: any =
                pcall(core.getLatencyReadings)
            if ok and finiteNumber(data) then
                latency = data
            elseif ok and finiteNumber(engine) then
                latency = engine
            end
        end
        if not finiteNumber(latency)
            and type(core.getEstimatedLatency) == "function" then
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

    local function pruneEchoes(now: number): ()
        if not finiteNumber(now) then
            return
        end
        while #echoes > 0 and now - echoTimes[1] > ECHO_MAX_AGE do
            table.remove(echoes, 1)
            table.remove(echoTimes, 1)
        end
    end

    local function echoMedian(): number?
        -- Expire on reads as well as writes. Otherwise the first shot after a
        -- quiet round uses a median from the previous connection/round; the
        -- v104/v105 files contain such shots after 72-2765 second gaps.
        pruneEchoes(os.clock())
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
        -- A confirmation matched hundreds of milliseconds late is not
        -- transport: it is a stale pending paired with a later signal
        -- (in the v103 session, pairings at 416-1840 ms entered the
        -- median and dragged it from the true 106 ms to 532 ms, which
        -- led every shot ~0.4 s long and then tripped the capped-
        -- horizon refusal). Real round trips scale with the ping, so
        -- the acceptance window scales with the measured RTT instead
        -- of trusting the absolute 1.6 s pairing limit alone. v104 used
        -- 4x RTT (~540 ms at a 135 ms ping) and the A5AACF6D session
        -- still fed it 279-990 ms pairings that held the median at
        -- 210 ms against a 131-143 ms ping; 2.5x + 50 ms (~388 ms at
        -- that ping) closes that band while staying far above any
        -- genuine round trip on the same connection.
        local plausible: number = math.clamp(
            currentRtt() * 2.5 + 0.05, 0.3, MAX_ECHO_DELAY)
        if delay > plausible then
            return
        end
        -- Also prune against the arriving sample's clock. This keeps explicit
        -- replayed timestamps ordered and prevents one fresh echo from
        -- resurrecting samples that already expired.
        pruneEchoes(receivedAt)
        table.insert(echoes, delay)
        table.insert(echoTimes, receivedAt)
        while #echoes > MAX_ECHOES do
            table.remove(echoes, 1)
            table.remove(echoTimes, 1)
        end
        -- Auto-reset on divergence: if the surviving median no longer
        -- describes this connection's round trip, the window is
        -- poisoned; drop it and let the ping fallback carry the lead
        -- until fresh echoes rebuild the median.
        local median: number? = echoMedian()
        if median and median > currentRtt() * ECHO_DIVERGENCE_RATIO then
            table.clear(echoes)
            table.clear(echoTimes)
        end
    end

    local function manualLead(): number
        return settings.autoLead and 0 or settings.extraLead
    end

    -- Signed over/under-lead measurements, in seconds. Positive means the
    -- target was ahead of the point we aimed at when the server scored it.
    --
    -- v161: kept PER AIM MODE. Bullet and CFrame author different things (the
    -- native gun ray versus an explicit origin/endpoint pair) and there is no
    -- evidence the server scores them with the same rewind, so merging their
    -- errors taught one mode the other's bias. CFrame had no feedback at all
    -- until now.
    local leadErrors: {[string]: {number}} = {}
    local leadApplied: {[string]: number} = {}

    local function modeKey(mode: any): string
        local text: string = type(mode) == "string" and mode or ""
        local lower: string = string.lower(text)
        if lower == "normal" or lower == "bullet" then
            return "Bullet"
        end
        if lower == "silent" or lower == "cframe" or lower == "silent aim" then
            return "CFrame"
        end
        return "default"
    end

    local function leadBucket(mode: any): {number}
        local key: string = modeKey(mode)
        local bucket: {number}? = leadErrors[key]
        if not bucket then
            bucket = {}
            leadErrors[key] = bucket
        end
        return bucket :: {number}
    end

    local function medianOf(values: {number}): number?
        local count: number = #values
        if count == 0 then
            return nil
        end
        local sorted: {number} = table.clone(values)
        table.sort(sorted)
        if count % 2 == 1 then
            return sorted[(count + 1) // 2]
        end
        return (sorted[count // 2] + sorted[count // 2 + 1]) * 0.5
    end

    local function noteLeadError(seconds: any, mode: any): ()
        if not finiteNumber(seconds) then
            return
        end
        if math.abs(seconds) > LEAD_FEEDBACK_SAMPLE_LIMIT then
            return
        end
        local key: string = modeKey(mode)
        local bucket: {number} = leadBucket(key)
        table.insert(bucket, seconds)
        while #bucket > LEAD_FEEDBACK_MAX_SAMPLES do
            table.remove(bucket, 1)
        end
        if #bucket < LEAD_FEEDBACK_MIN_SAMPLES then
            return
        end
        local median: number? = medianOf(bucket)
        if not median then
            return
        end
        local target: number = math.clamp(
            median,
            -MAX_LEAD_CORRECTION,
            MAX_LEAD_CORRECTION
        )
        -- Slew-limited: one step per confirmation, toward the measured median.
        local current: number = leadApplied[key] or 0
        local step: number = math.clamp(
            target - current,
            -LEAD_SLEW_PER_SAMPLE,
            LEAD_SLEW_PER_SAMPLE
        )
        leadApplied[key] = current + step
    end

    -- The correction currently in force for that aim mode, in seconds. It is
    -- already bounded and slew-limited, so callers just add it.
    local function leadCorrection(mode: any): number
        local bucket: {number}? = leadErrors[modeKey(mode)]
        if not bucket or #bucket < LEAD_FEEDBACK_MIN_SAMPLES then
            return 0
        end
        return leadApplied[modeKey(mode)] or 0
    end

    -- What the median asks for right now, before the slew limit. Reporting only;
    -- the aim uses `leadCorrection`.
    local function leadTarget(mode: any): number
        local bucket: {number}? = leadErrors[modeKey(mode)]
        if not bucket or #bucket < LEAD_FEEDBACK_MIN_SAMPLES then
            return 0
        end
        local median: number? = medianOf(bucket)
        if not median then
            return 0
        end
        return math.clamp(median, -MAX_LEAD_CORRECTION, MAX_LEAD_CORRECTION)
    end

    local function leadSamples(mode: any): number
        local bucket: {number}? = leadErrors[modeKey(mode)]
        return bucket and #bucket or 0
    end

    -- How far the recent shots were off, without their sign. Silent aim draws
    -- its bypass segment along the target's own motion, and that segment has to
    -- be as long as the lead's uncertainty: at 16 studs/s a 60 ms error is a
    -- whole stud, which is wider than the blade and most of a limb. Derived
    -- from the same confirmations as the correction, never from a constant.
    local function leadUncertainty(mode: any): number
        local bucket: {number}? = leadErrors[modeKey(mode)]
        if not bucket or #bucket < LEAD_FEEDBACK_MIN_SAMPLES then
            return 0
        end
        local absolute: {number} = {}
        for _, seconds: number in ipairs(bucket) do
            table.insert(absolute, math.abs(seconds))
        end
        return medianOf(absolute) or 0
    end

    local function gunHorizon(mode: any): (number, number, number?)
        local rtt: number = robustRtt()
        local echo: number? = echoMedian()
        -- The echo is measured client-side from the activation to the
        -- confirmation, so it is a real round trip rather than an engine
        -- estimate; it replaces the ping when a median exists. It has to be
        -- measured from the confirmation path for that to happen at all:
        -- v61 recorded none (`echoDelay` nil on all 13 shots).
        -- Blend: rtt is the stable base, echo adds freshness when
        -- available. The calibration shows echo alone leads systematically
        -- short (echo mean 0.227 vs rtt 0.263), so a 60/40 blend avoids
        -- the jump between echo-present and echo-absent without losing
        -- the freshness signal. When echo is stale/nil, rtt stands alone.
        local pipeline: number = echo
            and (rtt * 0.6 + echo * 0.4)
            or rtt
        -- Full transport, NOT the one-way half -- and this is measured,
        -- not assumed: in the saved calibration sessions the confirmed
        -- hits cluster at about +14 ms against the confirmation instant
        -- (a full round trip after firing) and at about -55 ms against
        -- the receive instant, so the server scores the shot as if it
        -- rewound by the shooter's whole ping. v85 halved this on a
        -- no-rewind theory and led systematically short.
        --
        -- v161: the measured lead error is added here. Until now it was only
        -- recorded, so the loop that is supposed to correct a systematic
        -- short/long lead never acted on anything. It is per aim mode and
        -- already slew-limited, so this is a bounded nudge, not a new model.
        local horizon: number = pipeline
            + settings.interpolation
            + manualLead()
            + leadCorrection(mode)
        if settings.autoLead then
            horizon = math.min(horizon, MAX_AUTO_LEAD)
        end
        return math.clamp(horizon, 0.005, MAX_HORIZON), rtt, echo
    end

    -- The blade travels on the same connection as the bullet, so the measured
    -- FireServer -> GunFired round trip is a better transport number than the
    -- engine's ping estimate here too. The v64 file measured 126-472 ms of real
    -- round trip against an 80-154 ms engine reading: leading a thrown blade
    -- with the engine number leaves up to 300 ms of unled movement, which is
    -- the knife missing high and behind a target that is already running.
    local function knifeHorizon(): (number, number, number?)
        local rtt: number = robustRtt()
        local echo: number? = echoMedian()
        local pipeline: number = echo
            and (rtt * 0.6 + echo * 0.4)
            or rtt
        -- Same full-transport rule as the gun (measured the same way:
        -- the blade's effective spawn behaves like a full rewind, so
        -- the intercept leads the whole round trip plus flight time).
        -- The knife gets no measured feedback of its own (the captures only
        -- score the gun), so it shares the "default" bucket instead of
        -- borrowing the Bullet one.
        local horizon: number = pipeline
            + settings.interpolation
            + manualLead()
            + leadCorrection("knife")
        if settings.autoLead then
            horizon = math.min(horizon, MAX_AUTO_LEAD)
        end
        return math.clamp(horizon, 0.005, MAX_HORIZON), rtt, echo
    end

    local function gunAim(
        target: Player,
        _muzzle: Vector3,
        mode: any
    ): (Vector3?, AimInfo?, string?)
        -- v161: which way the shot will be authored. Bullet sends a CFrame
        -- whose LookVector is the aim; CFrame/Silent sends origin+endpoint.
        -- They keep separate measured corrections because there is no
        -- evidence the server rewinds both identically.
        local aimMode: string = modeKey(mode)
        -- v158: a fresh body check. A track survives the 0.5 s part refresh,
        -- so without this the solver kept leading a body that had just died.
        local humanoid: any = targetHumanoid(target)
        if humanoid ~= nil and not bodyIsAlive(humanoid) then
            tracks[target] = nil
            return nil, nil, "dead target"
        end
        local track: Track? = tracks[target]
        if not track then
            samplePlayer(target, os.clock())
            track = tracks[target]
        end
        if not track or #track.samples == 0 then
            return nil, nil, "no samples"
        end
        local now: number = os.clock()
        local motion: Motion? = estimateMotion(track, now)
        if not motion then
            return nil, nil, "stale sample"
        end
        local pipeline: number, rtt: number, echo: number? = gunHorizon(aimMode)
        local rttEngine: number?, rttData: number? = nil, nil
        if type(core.getLatencyReadings) == "function" then
            local ok: boolean, engine: any, data: any = pcall(core.getLatencyReadings)
            if ok then
                rttEngine = finiteNumber(engine) and engine or nil
                rttData = finiteNumber(data) and data or nil
            end
        end
        local horizon: number = math.clamp(
            motion.sampleAge + pipeline,
            0.005,
            MAX_HORIZON
        )
        local rootPosition: Vector3 = predictedRoot(track, motion, horizon)
        local last: Sample = track.samples[#track.samples]
        local aimVelocity: Vector3 = motion.velocity
        if motion.hasInputHistory and horizon > 1e-4 then
            local chord: Vector3 = rootPosition - last.position
            aimVelocity = Vector3.new(
                chord.X / horizon,
                motion.velocity.Y,
                chord.Z / horizon
            )
        end
        -- The torso offset turns with the character. The sampled offset is
        -- one sample old; the part's current offset from the current root
        -- is the same measurement without the sample delay, and at a
        -- 100 ms horizon a turning target has already rotated it.
        local aimOffset: Vector3 = last.aimOffset
        local freshAimPart: BasePart? = findAimPart(track.character)
        if freshAimPart then
            aimOffset = freshAimPart.Position - track.root.Position
        end
        local endpoint: Vector3 = rootPosition + aimOffset
        return endpoint, {
            endpoint = endpoint,
            targetPosition = endpoint,
            capturedPosition = last.position + aimOffset,
            rootPosition = rootPosition,
            velocity = aimVelocity,
            leadSeconds = horizon,
            sampleAge = motion.sampleAge,
            samples = motion.samples,
            residual = motion.residual,
            motionSource = motion.source,
            model = "kinematic-v51",
            rtt = rtt,
            rttEngine = rttEngine,
            rttData = rttData,
            echoDelay = echo,
            echoSamples = #echoes,
            turnRate = motion.turnRate,
            brakeSeconds = motion.brakeSeconds,
            leadCorrection = leadCorrection(aimMode),
            leadCorrectionTarget = leadTarget(aimMode),
            leadSamples = leadSamples(aimMode),
            aimMode = aimMode,
        }, nil
    end

    local function knifeAim(
        target: Player,
        origin: Vector3,
        speed: number?
    ): (Vector3?, AimInfo?, string?)
        local humanoid: any = targetHumanoid(target)
        if humanoid ~= nil and not bodyIsAlive(humanoid) then
            tracks[target] = nil
            return nil, nil, "dead target"
        end
        local track: Track? = tracks[target]
        if not track then
            samplePlayer(target, os.clock())
            track = tracks[target]
        end
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
        local pipeline: number, rtt: number, echo: number? = knifeHorizon()
        local rttEngine: number?, rttData: number? = nil, nil
        if type(core.getLatencyReadings) == "function" then
            local ok: boolean, engine: any, data: any = pcall(core.getLatencyReadings)
            if ok then
                rttEngine = finiteNumber(engine) and engine or nil
                rttData = finiteNumber(data) and data or nil
            end
        end
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
        -- v159: solve the intercept to a FIXED POINT instead of one re-solve.
        -- The chord a turning or braking target travels depends on how long
        -- the blade is in the air, and that flight time depends on the chord,
        -- so a single pass leaves the aim inconsistent: the point and the
        -- flight time it was solved for disagree. Iterating until the flight
        -- time stops moving makes |endpoint - origin| == speed * flight exact,
        -- which is the one property a straight constant-speed blade has to
        -- satisfy. It converges in two or three passes; the cap is a guard.
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
        for _iteration: number = 1, 4 do
            local revised: number? = predictionMath.interceptTime(
                aimStart + effective * horizon - origin,
                effective,
                resolvedSpeed
            )
            if not revised then
                break
            end
            local delta: number = math.abs(revised - flight)
            flight = revised
            if delta <= 1e-4 then
                -- `effective` is still the velocity this flight was solved
                -- with, so the endpoint below sits exactly on the intercept.
                break
            end
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
            -- v159: that point is not where the chord solve landed, so the
            -- flight time it returned was for a different distance. A blade
            -- travels straight at constant speed, so the honest number is the
            -- distance left over the speed; the target scoring and the
            -- telemetry both read it.
            flight = (endpoint - origin).Magnitude / resolvedSpeed
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
            rttEngine = rttEngine,
            rttData = rttData,
            echoDelay = echo,
            echoSamples = #echoes,
            turnRate = motion.turnRate,
            brakeSeconds = motion.brakeSeconds,
            leadCorrection = 0,
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
        -- The status must show the horizon the shot actually uses:
        -- gunAim adds the age of the newest sample on top of the
        -- pipeline. Showing only the pipeline (98 ms when the shot
        -- used 111 ms) makes the lead look shorter than it is.
        if target then
            local track: Track? = tracks[target]
            local preview: Motion? = track and estimateMotion(track, os.clock())
            if preview then
                horizon += preview.sampleAge
            end
        end
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
                        moveDirection = sample.moveDirection,
                        -- v139.4: the offset from the root to the part the aim
                        -- falls on. base.lua reads it for every history point
                        -- and it was never sent, so `endpointErrorStuds` scored
                        -- a ROOT position against an aim that used the torso
                        -- offset: a systematic vertical error on every sample.
                        aimOffset = sample.aimOffset,
                        aimPart = sample.aimPart,
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
        noteLeadError = noteLeadError,
        getLeadCorrection = leadCorrection,
        getLeadCorrectionTarget = leadTarget,
        getLeadUncertainty = leadUncertainty,
        getLeadSamples = leadSamples,
        reset = function(): ()
            table.clear(echoes)
            table.clear(echoTimes)
            table.clear(tracks)
            table.clear(rttSamples)
            for _, bucket: {number} in pairs(leadErrors) do
                table.clear(bucket)
            end
            table.clear(leadErrors)
            table.clear(leadApplied)
            lastRttSampleAt = -math.huge
        end,
    }

    -- v139: the roster changes a few times per round, not 60 times per second.
    -- `GetPlayers()` returns a fresh array on every call, so asking for it each
    -- frame was pure garbage. Reused for a quarter of a second.
    local roster: {Player} = {}
    local rosterAt: number = -math.huge
    local function tick(deltaTime: number): ()
        elapsed += math.max(0, deltaTime or 0)
        local interval: number = 1 / SAMPLE_HZ
        if elapsed + 1e-9 < interval then
            return
        end
        elapsed = elapsed % interval
        local now: number = os.clock()
        if now - rosterAt >= 0.25 or #roster == 0 then
            rosterAt = now
            roster = Players:GetPlayers()
        end
        for _, player: Player in ipairs(roster) do
            if player ~= LocalPlayer then
                samplePlayer(player, now)
            end
        end
    end

    state.mm2Prediction = controller
    featureConnections.MM2PredictionSampler =
        TaskManager:Connect(tick, nil, "Prediction sampler")

    activeCleanup = function(): ()
        disconnectFeatureConnection("MM2PredictionSampler")
        if state.mm2Prediction == controller then
            state.mm2Prediction = nil
        end
        table.clear(echoes)
        table.clear(echoTimes)
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
