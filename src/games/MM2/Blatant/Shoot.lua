local Module = {
    Name = "MM2 Shoot",
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
    assert(type(core) == "table", "MM2 Shoot requires the MM2 core module")
    local prediction: any = state.mm2Prediction
    assert(type(prediction) == "table", "MM2 Shoot requires MM2 Prediction")
    local trajectoryCalibration: any = core.trajectoryCalibration
    Module.Runtime = runtime
    local connectGunFiredSignal: any = core.connectGunFiredSignal
    local disconnectGunFiredObserver: any = core.disconnectGunFiredObserver
    local findMurderer: any = core.findMurderer
    local getGunOriginCFrame: any = core.getGunOriginCFrame
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local getWeaponServiceModule: any = core.getWeaponServiceModule
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local isWeaponPathClear: any = core.isWeaponPathClear
    local describeRayBeyond: any = core.describeRayBeyond
    local mm2Settings: any = core.mm2Settings
    local validateGunShot: any = core.validateGunShot

    local shootMacro: boolean = false
    -- First thing the untouched ray meets on an allowed shot (nil if nothing
    -- short of the aim). Persisted into the shot's settings.
    local lastGunOccluder: any = nil
    local function macroUnequip(gun: Tool?): ()
        if not shootMacro or not gun then
            return
        end
        task.delay(0.01, function(): ()
            pcall(function(): ()
                local backpack: Instance? = LocalPlayer:FindFirstChildOfClass("Backpack")
                local character: Model? = LocalPlayer.Character
                if backpack and character and gun.Parent == character then
                    gun.Parent = backpack
                end
            end)
        end)
    end

    local function getSelectedShootTarget(): Player?
        local target
        if mm2Settings.shootMode == "Custom"
            and mm2Settings.shootTarget ~= "" then
            target = findPlayerByText(mm2Settings.shootTarget)
        else
            target = findMurderer()
        end
        if not target
            or target == LocalPlayer
            or not isPlayerAlive(target)
            or isProtectedTarget(target) then
            return nil
        end
        if getPlayerRole(target) ~= "Murderer" then
            return nil
        end
        return target
    end

    local function bystanderOnSegment(
        target: Player,
        startPoint: Vector3,
        endPoint: Vector3
    ): boolean
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Include
        parameters.IgnoreWater = true
        local bodies: {Instance} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= target
                and player ~= LocalPlayer
                and player.Character
                and isPlayerAlive(player) then
                table.insert(bodies, player.Character)
            end
        end
        if #bodies == 0 then
            return false
        end
        parameters.FilterDescendantsInstances = bodies
        return workspace:Raycast(startPoint, endPoint - startPoint, parameters) ~= nil
    end

    local SILENT_ORIGIN_STUDS: number = 2.5
    local SILENT_PIERCE_STUDS: number = 1.0
    local SILENT_LIFT_STUDS: number = 1.6
    local MAX_SILENT_SWEEP: number = 1.5
    -- v139.3: two different questions, two different reaches. They shared one
    -- constant in v139.2, and raising it to 200 studs for the corridor also
    -- widened the silent construction's bystander probe -- which asks a
    -- PLAYER-ONLY raycast that ignores walls. The v139.2 session then refused
    -- shots ("Another player blocks the silent shot") with an innocent 100+
    -- studs behind the murderer and a wall in between.
    --
    --  * how far behind the authored segment a body still takes the ray:
    --    the v139.1 value the silent construction was validated with.
    local BODY_OVERSHOOT_STUDS: number = 12
    --  * how far behind the AIM the corridor looks for a body (see
    --    corridorSafePoint): a long reach, because this probe stops at the
    --    first thing it meets, so a wall ends the question.
    local CORRIDOR_PROBE_STUDS: number = 200
    -- A body this close behind the aim is a point-blank innocent hit waiting
    -- to happen: even a 1-stud prediction error walks into it.
    local INNOCENT_DANGER_STUDS: number = 35
    -- Inside this distance the murderer's body covers the whole line of sight,
    -- so the lead stops helping and can even invert the shot: 17 studs/s of
    -- charge times a 0.1 s lead is 1.7 studs, more than the gap itself.
    local POINT_BLANK_STUDS: number = 6
    local MAX_AUTO_LEAD_SAFE: number = 0.6

    -- The Top/fallback origin lift belongs to the target's rig, not to a
    -- universal constant: R6 and R15 put the head at different heights
    -- above the root, and an origin spawned inside the head can be
    -- ignored by the shot. Predicted endpoint minus predicted root is
    -- the same aim offset the predictor sampled from the live rig.
    local function silentLift(info: any, predicted: Vector3): number
        if type(info) == "table"
            and typeof(info.rootPosition) == "Vector3" then
            local aimOffsetY: number = predicted.Y - info.rootPosition.Y
            if aimOffsetY > 0.5 then
                return math.clamp(aimOffsetY + 0.35, 1.2, 2.4)
            end
        end
        return SILENT_LIFT_STUDS
    end

    -- The server ray is not clipped at our authored endpoint, so the
    -- bystander check covers the segment plus a short overshoot probe: a body
    -- just behind the target would take the continuing ray.
    --
    -- v139.3: the overshoot probe now stops at the FIRST thing it meets and a
    -- wall ends it. The old version asked bystanderOnSegment, whose raycast is
    -- filtered to player characters only, so walls were transparent to it: an
    -- innocent in the next room sat on the ray and every silent shot was
    -- refused. "What is behind the aim" is corridorSafePoint's job; this check
    -- only needs to know whether the continuing ray immediately finds a body.
    local function bystanderBlocks(
        target: Player,
        startPoint: Vector3,
        endPoint: Vector3
    ): boolean
        if bystanderOnSegment(target, startPoint, endPoint) then
            return true
        end
        local segment: Vector3 = endPoint - startPoint
        if segment.Magnitude <= 0.05 then
            return false
        end
        if type(describeRayBeyond) == "function" then
            local exclude: {Instance} = {target}
            local ownCharacter: Model? = LocalPlayer and LocalPlayer.Character
            if ownCharacter then
                table.insert(exclude, ownCharacter)
            end
            local ok: boolean, hit: any = pcall(
                describeRayBeyond,
                startPoint,
                endPoint,
                BODY_OVERSHOOT_STUDS,
                exclude
            )
            if ok then
                return type(hit) == "table"
                    and hit.isBody == true
                    and hit.player ~= target
            end
        end
        local beyond: Vector3 = endPoint
            + segment.Unit * BODY_OVERSHOOT_STUDS
        return bystanderOnSegment(target, endPoint, beyond)
    end

    -- The bypass segment runs along the target's own motion. A fixed extra
    -- length guesses; the confirmed shots already measure how far the aim
    -- lands from the body, so the same measurement decides how much segment
    -- the shot needs. With no confirmations yet the uncertainty is zero and
    -- the configured value is used untouched.
    local function getSilentSweepDistance(speed: number?): number
        local configured: number = tonumber(mm2Settings.silentSweep) or 0
        local sweep: number = math.clamp(configured, 0, MAX_SILENT_SWEEP)
        local uncertainty: number = 0
        if type(prediction) == "table"
            and type(prediction.getLeadUncertainty) == "function" then
            local ok: boolean, seconds: any = pcall(
                prediction.getLeadUncertainty
            )
            if ok and type(seconds) == "number" and seconds == seconds then
                uncertainty = math.clamp(seconds, 0, 0.15)
            end
        end
        if uncertainty <= 0 then
            return sweep
        end
        local travel: number = math.max(tonumber(speed) or 0, 0)
        local extra: number = uncertainty * travel
        return math.clamp(sweep + extra, 0, MAX_SILENT_SWEEP)
    end

    local function buildSilentShot(
        target: Player,
        info: any,
        muzzleOrigin: CFrame?,
        variant: string
    ): (CFrame?, CFrame?, number, number, string)
        local predicted: Vector3 = info.endpoint
        local liftStuds: number = silentLift(info, predicted)
        local velocity: Vector3 = info.velocity
        local horizontal: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)

        local direction: Vector3? = nil
        local sweep: number = 0
        if horizontal.Magnitude > 1.5 then
            direction = horizontal.Unit

            sweep = getSilentSweepDistance(horizontal.Magnitude)
        end
        local sweepStart: Vector3 =
            direction and -direction * sweep or Vector3.zero
        local sweepEnd: Vector3 =
            direction and direction * sweep or Vector3.zero

        local approach: Vector3? = nil
        local approachOffset: number = SILENT_ORIGIN_STUDS
        if muzzleOrigin then
            local toTarget: Vector3 = predicted - muzzleOrigin.Position
            local flat: Vector3 = Vector3.new(toTarget.X, 0, toTarget.Z)
            if flat.Magnitude > 0.05 then
                approach = flat.Unit
                approachOffset = math.min(
                    SILENT_ORIGIN_STUDS,
                    math.max(1.0, flat.Magnitude * 0.6)
                )
            end
        end

        local startPoint: Vector3
        local endPoint: Vector3
        local resolvedVariant: string = variant
        local pierceAxis: Vector3? = direction or approach
        if (variant == "Through" or variant == nil or variant == "") and pierceAxis then
            resolvedVariant = "Through"
            local captured: Vector3 = info.capturedPosition or predicted
            startPoint = captured - pierceAxis * 1.0 + sweepStart
            endPoint = predicted + pierceAxis * SILENT_PIERCE_STUDS + sweepEnd
        elseif variant == "Top" then
            resolvedVariant = "Top"
            startPoint = predicted + Vector3.new(0, liftStuds, 0)
                + sweepStart
            endPoint = predicted + sweepEnd
        elseif variant == "Behind" and approach then
            resolvedVariant = "Behind"
            startPoint = predicted + approach * approachOffset + sweepStart
            endPoint = predicted + sweepEnd
        elseif approach then
            resolvedVariant = "Front"
            startPoint = predicted - approach * approachOffset + sweepStart
            endPoint = predicted + sweepEnd
        elseif direction then
            resolvedVariant = "Motion"
            startPoint = predicted + sweepStart
            endPoint = predicted + sweepEnd
        else
            resolvedVariant = "Top"
            startPoint = predicted + Vector3.new(0, liftStuds, 0)
            endPoint = predicted
        end

        if (endPoint - startPoint).Magnitude <= 0.05 then
            startPoint = predicted + Vector3.new(0, liftStuds, 0)
            endPoint = predicted
            resolvedVariant = "Top"
            sweep = 0
        end
        -- Through has length even when the configurable extra sweep is zero.
        -- Record the geometry actually authored, not just the requested
        -- variant: a bystander fallback removes the sweep and can change a
        -- Through/Behind request into the Front or lifted construction.
        if bystanderBlocks(target, startPoint, endPoint) then
            sweep = 0
            if variant ~= "Top" and approach then
                startPoint = predicted - approach * approachOffset
                resolvedVariant = "Front"
            else
                startPoint = predicted + Vector3.new(0, liftStuds, 0)
                resolvedVariant = "Top"
            end
            endPoint = predicted
            if bystanderBlocks(target, startPoint, endPoint) then
                return nil, nil, 0, 0, resolvedVariant
            end
        end

        return CFrame.lookAt(startPoint, endPoint), CFrame.new(endPoint),
            approachOffset, sweep, resolvedVariant
    end

    type FireOptions = {
        silent: boolean?,
        quiet: boolean?,
        whenReady: boolean?,
        continuous: boolean?,
        wallCheck: boolean?,
    }

    -- How long an authored request owns the gun. The feedback queue resolves
    -- or expires a shot at 1.6-1.8 s; keeping the window inside that bound
    -- means the gate never outlives the pending state it reads.
    local SHOT_CONFIRM_WINDOW: number = 1.5

    local ShootFeature: any = nil
    local lastRejectReason: string = ""

    -- v139.2: pick the aim point whose line is safest BEYOND the target.
    -- A shot that misses by a stud continues into whoever is standing behind;
    -- the aim is therefore chosen by what is behind it, not only by what is in
    -- front. Candidates stay inside the body (torso, root, head, outer limbs),
    -- so the target itself remains just as hittable.
    local function corridorSafePoint(
        target: Player,
        info: any,
        origin: Vector3,
        preferred: Vector3
    ): (Vector3, boolean, string)
        local character: Model? = target.Character
        if not character or not describeRayBeyond then
            return preferred, true, "none"
        end
        local exclude: {Instance} = {}
        local ownCharacter: Model? = LocalPlayer and LocalPlayer.Character
        if ownCharacter then
            table.insert(exclude, ownCharacter)
        end
        table.insert(exclude, character)
        local function blocker(point: Vector3): any
            local hit: any = describeRayBeyond(
                origin,
                point,
                CORRIDOR_PROBE_STUDS,
                exclude
            )
            if not hit or not hit.isBody then
                return nil
            end
            if hit.player == target then
                return nil
            end
            -- A rig with no player behind it is only a danger while alive: a
            -- corpse is not an innocent, and refusing on one costs the shot.
            if hit.player == nil and (tonumber(hit.health) or 0) <= 0 then
                return nil
            end
            return hit
        end
        -- The preferred point is the predictor's own aim; it is only touched
        -- when something alive is close behind it.
        local near: any = blocker(preferred)
        if not near or near.gap >= INNOCENT_DANGER_STUDS then
            return preferred, true, "torso"
        end
        -- Same lead the preferred point got, applied to each body part, so the
        -- candidates differ in where the ray goes, not in how far ahead it is.
        local lead: Vector3 = info.endpoint - (info.capturedPosition or info.endpoint)
        local bestPoint: Vector3 = preferred
        local bestGap: number = near.gap
        local bestName: string = "torso"
        for _, partName: string in ipairs({
            "UpperTorso", "Torso", "HumanoidRootPart", "Head",
            "RightUpperArm", "LeftUpperArm", "RightUpperLeg", "LeftUpperLeg",
            "Right Arm", "Left Arm", "Right Leg", "Left Leg",
        }) do
            local part: Instance? = character:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                local candidate: Vector3 = (part :: BasePart).Position + lead
                local hit: any = blocker(candidate)
                if not hit or hit.gap >= INNOCENT_DANGER_STUDS then
                    -- This line is safe enough: aim there instead.
                    return candidate, true, partName
                end
                if hit.gap > bestGap then
                    bestGap = hit.gap
                    bestPoint = candidate
                    bestName = partName
                end
            end
        end
        -- Every line has a body within the danger radius: the safest one is
        -- still a coin flip, so the shot is skipped (MM2 takes the gun away
        -- from a sheriff who shoots an innocent).
        return bestPoint, false, bestName
    end

    local function fireGunAtTarget(
        target: Player?,
        options: FireOptions?
    ): boolean
        local opts: FireOptions = options or {}
        local silent: boolean = mm2Settings.silentAim
        if opts.silent ~= nil then
            silent = opts.silent
        end
        local quiet: boolean = opts.quiet == true
        local continuous: boolean = opts.continuous == true
        local useRaw: boolean = mm2Settings.shootRaw
            or (continuous and silent)
        local useWallCheck: boolean = if opts.wallCheck ~= nil
            then opts.wallCheck == true
            else mm2Settings.shootWallCheck
        local function reject(message: string): boolean
            lastRejectReason = message
            if not quiet and ShootFeature then ShootFeature:SetStatus(message) end
            return false
        end

        local character, humanoid = getCharacterParts()
        if not target or not target.Character or target == LocalPlayer
            or not isPlayerAlive(target) or isProtectedTarget(target) or getPlayerRole(target) ~= "Murderer" then
            return reject("No selected shoot target was found.")
        end
        if not character or not humanoid then
            return reject("Your character is not available.")
        end
        local targetCharacter = target.Character
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun", true)
        if not gun or gun.Parent ~= character then
            return reject("Equip the sheriff gun yourself to shoot.")
        end
        if gun.Enabled == false or gun:GetAttribute("Disabled") == true
            or gun:GetAttribute("Reloading") == true or gun:GetAttribute("IsReloading") == true then
            return reject("The gun is disabled or reloading.")
        end

        local remote: Instance? = gun and gun:FindFirstChild("Shoot")
        local origin: CFrame? = getGunOriginCFrame(character, gun)

        local info: any = nil
        local reason: string? = nil
        if origin then
            local ok: boolean, endpoint: any, aimInfo: any, aimReason: any =
                pcall(prediction.gunAim, target, origin.Position)
            if not ok then return reject("Aim or visibility check failed.") end
            if endpoint == nil then
                reason = aimReason or "no samples"
            else
                info = aimInfo
            end
        end

        -- Raw mode or continuous Auto Shoot / Auto Win: when gunAim has no
        -- samples yet on the first frame, fall back immediately to the
        -- target's current root position (+ short velocity lead) so the shot
        -- fires without waiting even a single second.
        if (useRaw or continuous) and not info and target.Character then
            local targetRoot: BasePart? = target.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local vel: Vector3 = Vector3.zero
                pcall(function(): ()
                    vel = targetRoot.AssemblyLinearVelocity
                end)
                local fallbackEndpoint: Vector3 = targetRoot.Position + vel * 0.08
                info = {
                    endpoint = fallbackEndpoint,
                    velocity = vel,
                    leadSeconds = 0.08,
                    motionSource = "raw",
                    model = "raw",
                    sampleAge = 0,
                    samples = 0,
                    capturedPosition = targetRoot.Position,
                    rtt = 0,
                    echoDelay = 0,
                    rttEngine = "raw",
                    echoSamples = 0,
                    turnRate = 0,
                    brakeSeconds = 0,
                    leadCorrection = 0,
                    rootPosition = targetRoot.Position,
                }
            end
        end

        -- v139.3: at arm's length the lead stops helping and starts hurting.
        -- The murderer charging at the measured 17 studs/s covers 1.7 studs in
        -- a 0.1 s lead: from 1.5 studs away the predicted point lands BEHIND
        -- our own muzzle, the authored segment inverts, and the shot is
        -- refused as "Invalid shot geometry" (reproduced in
        -- tools/test_gun_pointblank.py). Inside POINT_BLANK_STUDS the body
        -- covers the whole sight, so aim at it and drop the lead.
        if origin and info then
            local root: BasePart? = nil
            pcall(function(): ()
                root = targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
            end)
            local aimVector: Vector3 = info.endpoint - origin.Position
            local toRoot: Vector3 = root and (root.Position - origin.Position) or aimVector
            local inverted: boolean = aimVector.Magnitude < 0.05
                or aimVector:Dot(toRoot) <= 0
            if root and (inverted or aimVector.Magnitude < POINT_BLANK_STUDS) then
                info.capturedPosition = root.Position
                info.endpoint = root.Position
                info.aimPartChosen = "HumanoidRootPart"
                info.pointBlank = true
            end
        end

        -- v139.2: choose the aim point by what is BEHIND it. The server ray
        -- does not stop at our endpoint, so a stud of prediction error turns
        -- into a body behind the murderer. Measured in the v139.1 session:
        -- 2 of 10 confirmed shots hit another player's root, 3 stopped on
        -- map geometry beyond the aim.
        if mm2Settings.avoidInnocents ~= false and origin and info then
            local chosen: Vector3, safe: boolean, picked: string =
                corridorSafePoint(target, info, origin.Position, info.endpoint)
            if not safe then
                -- Recorded like any other refusal, with its own reason, so a
                -- session can answer "how many shots did this cost me?".
                if trajectoryCalibration
                    and type(trajectoryCalibration.noteBlockedShot) == "function" then
                    pcall(trajectoryCalibration.noteBlockedShot,
                        trajectoryCalibration, {
                            reason = "corridor",
                            name = "body behind aim",
                            distance = 0,
                            skipped = false,
                            canCollide = false,
                        })
                end
                return reject("An innocent is right behind the murderer.")
            end
            if chosen ~= info.endpoint then
                local shift: Vector3 = chosen - info.endpoint
                info.capturedPosition = (info.capturedPosition or info.endpoint)
                    + shift
                info.endpoint = chosen
                info.aimPartChosen = picked
            else
                info.aimPartChosen = picked
            end
        end

        local rejectMessages: {[string]: string} = {
            ["no body"] = "The murderer has no usable body to aim at.",
            ["no samples"] = "The murderer has no fresh motion samples yet.",
            ["stale sample"] = "The murderer's position is stale; waiting for a fresh sample.",
            ["unreachable"] = "The murderer is moving too fast to intercept.",
        }
        if not remote
            or not remote:IsA("RemoteEvent")
            or not origin
            or not info then
            local message: string = rejectMessages[reason or ""]
                or (
                    not origin
                        and "The gun has no usable origin."
                        or "The murderer is unavailable or obstructed."
                )
            return reject(message)
        end

        -- One authored request at a time (v106). Continuous Auto Shoot /
        -- Auto Win bypasses the 1.5s confirmation gate so it never stops
        -- firing while the Murderer is still alive.
        local pendingShot: any = state.mm2ShotFeedback.pending
        if not continuous
            and type(pendingShot) == "table"
            and type(pendingShot.queuedAt) == "number"
            and os.clock() - pendingShot.queuedAt < SHOT_CONFIRM_WINDOW then
            local remaining: number = SHOT_CONFIRM_WINDOW
                - (os.clock() - pendingShot.queuedAt)
            return reject(string.format(
                "Shot gate: waiting for the previous shot (%.1f s left).",
                remaining))
        end

        local function safeToSend(
            shotOrigin: CFrame,
            shotEnd: CFrame,
            muzzle: CFrame?
        ): boolean
            if gun.Parent ~= character or gun.Enabled == false or gun:GetAttribute("Disabled") == true
                or gun:GetAttribute("Reloading") == true or gun:GetAttribute("IsReloading") == true then
                return reject("The gun is disabled or reloading.")
            end
            -- v139.4: "raw" means "do not wait for the near-target origin
            -- guard", NOT "do not look at walls". Raw/continuous Silent AIM
            -- used to return true here, so Auto Shoot and Auto Win (which call
            -- this path with continuous=true) fired with no wall check at all:
            -- the only geometry they ever saw was the near-target pass, never
            -- the gun's own line. A wall between the gun and the murderer is a
            -- wall in every mode, so the muzzle line is always checked.
            if useRaw then
                if not useWallCheck or not isWeaponPathClear then
                    return true
                end
                local rawMuzzle: Vector3 = (muzzle or shotOrigin).Position
                local rawClear, rawBlocker = isWeaponPathClear(
                    rawMuzzle,
                    shotEnd.Position,
                    targetCharacter,
                    nil,
                    {ignoreTarget = true}
                )
                if not rawClear then
                    if type(rawBlocker) == "table" and trajectoryCalibration
                        and type(trajectoryCalibration.noteBlockedShot) == "function" then
                        pcall(trajectoryCalibration.noteBlockedShot,
                            trajectoryCalibration, rawBlocker)
                    end
                    return reject("A wall or another body blocks the shot.")
                end
                return true
            end
            -- The muzzle is the character's gun, never the authored origin.
            -- validateGunShot checks BOTH rays: the gun's line of sight and
            -- the authored segment. Passing the silent origin twice made them
            -- one ray, so a shot the gun could not see was cleared by a
            -- near-target origin (the v105 silent map hits), and a body
            -- between the gun and the target was never looked for.
            local muzzlePosition: Vector3 = (muzzle or shotOrigin).Position
            local ok, allowed, why, blocker, occluder = pcall(validateGunShot,target,character,targetCharacter,
                muzzlePosition,shotOrigin.Position,shotEnd.Position,useWallCheck)
            if not ok or not allowed then
                if type(blocker) == "table" and trajectoryCalibration
                    and type(trajectoryCalibration.noteBlockedShot) == "function" then
                    pcall(trajectoryCalibration.noteBlockedShot, trajectoryCalibration, blocker)
                end
                return reject(why or "Shot safety check failed.")
            end
            -- Cleared, but keep what the untouched ray met: a transparent solid
            -- short of the aim is exactly the case the client cannot see.
            if type(occluder) == "table" then
                lastGunOccluder = occluder
            else
                lastGunOccluder = nil
            end
            return true
        end

        -- Do not infer a reload from our last REQUEST: a rejected packet
        -- never proves the server fired. Native Tool/attribute readiness is
        -- checked above; no speculative 3.1-second local lockout.
        if silent then

            -- The configured construction, not a hardcoded one: the setting was
            -- only ever read for telemetry, so a saved "Top" or "Front" was
            -- silently replaced by "Through" on every shot.
            local variant: string = "Through"
            local configuredSpawn: any = mm2Settings.silentSpawn
            if configuredSpawn == "Top" or configuredSpawn == "Behind"
                or configuredSpawn == "Front" then
                variant = configuredSpawn
            end
            local shotOrigin: CFrame?, shotEnd: CFrame?, offset: number,
                sweep: number, resolvedVariant: string
            if info.pointBlank and origin then
                -- v139.3: at arm's length the "Through" construction pierces
                -- along the target's own motion, and a murderer charging at us
                -- makes that direction point at US: the authored segment ended
                -- on our own muzzle (muzzle 0.5, endpoint 0.5) and every shot
                -- was refused as "Invalid shot geometry". Point blank needs no
                -- trick at all -- the muzzle already sees the body.
                shotOrigin = origin
                shotEnd = CFrame.new(info.endpoint)
                offset = 0
                sweep = 0
                resolvedVariant = "PointBlank"
            else
                shotOrigin, shotEnd, offset, sweep, resolvedVariant =
                    buildSilentShot(target, info, origin, variant)
            end
            if not shotOrigin or not shotEnd then
                if continuous and target.Character then
                    local tr: BasePart? = target.Character:FindFirstChild("HumanoidRootPart")
                    if tr then
                        local ep: Vector3 = info.endpoint or tr.Position
                        local capPt: Vector3 = info.capturedPosition or tr.Position
                        local startPt: Vector3 = capPt + Vector3.new(0, 1.2, -1.5)
                        shotOrigin = CFrame.lookAt(startPt, ep)
                        shotEnd = CFrame.new(ep)
                        offset = 1.5
                        sweep = 0
                        resolvedVariant = "Through"
                    end
                end
                if not shotOrigin or not shotEnd then
                    return reject("Another player blocks the silent shot.")
                end
            end
            variant = resolvedVariant
            -- A near-target origin inside a body can make the engine miss that
            -- containing body. Fall back to the real muzzle, never a bypass.
            -- Raw mode skips this check: the shot fires regardless.
            if not useRaw
                and not isWeaponPathClear(shotOrigin.Position,shotEnd.Position,targetCharacter,nil,{ignoreTarget=true}) then
                shotOrigin,shotEnd = origin,CFrame.new(info.endpoint)
                variant = "Muzzle"
                offset = 0
                sweep = 0
            end
            if not safeToSend(shotOrigin,shotEnd,origin) then return false end
            if not continuous then
                state.mm2ShotFeedback.queue(target, gun, shotOrigin, shotEnd)
            end

            state.lastSilentShotInfo = {
                variant = variant,
                at = os.clock(),
                offset = math.floor(offset * 10) / 10,
            }
            remote:FireServer(shotOrigin, shotEnd)

            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "gun",
                tool = gun,
                toolName = gun and gun.Name or "Gun",
                originPos = shotOrigin.Position,
                aimPos = shotEnd.Position,
                target = target,
                silent = true,
                variant = variant,
                offset = offset,
                settings = {mode = "Silent", spawn = variant,
                    sweep = sweep, wallCheck = useWallCheck,
                    leadSeconds = info.leadSeconds, motionSource = info.motionSource,
                    model = info.model,
                    sampleAge = info.sampleAge, samples = info.samples,
                    referencePoint = info.capturedPosition and {info.capturedPosition.X, info.capturedPosition.Y, info.capturedPosition.Z},
                    predictedPoint = {info.endpoint.X, info.endpoint.Y, info.endpoint.Z},
                    sampledVelocity = {info.velocity.X, info.velocity.Y, info.velocity.Z},
                    rtt = info.rtt, echoDelay = info.echoDelay,
                    rttEngine = info.rttEngine, rttData = info.rttData,
                    occluder = lastGunOccluder,
                    echoSamples = info.echoSamples,
                    turnRate = info.turnRate, brakeSeconds = info.brakeSeconds,
                    leadCorrection = info.leadCorrection},
            })
            if not quiet and ShootFeature then ShootFeature:SetStatus(nil) end
            if not continuous then
                macroUnequip(gun)
            end
            return true
        end

        local shotEndCFrame: CFrame = CFrame.new(info.endpoint)
        if not safeToSend(origin, shotEndCFrame) then return false end
        if not continuous then
            state.mm2ShotFeedback.queue(target, gun, origin, shotEndCFrame)
        end
        -- Author one endpoint, without speculative "piercing" past it.
        -- Echo timing documents transport/visual confirmation, NOT rewind
        -- duration or an authoritative hit-rate denominator.
        remote:FireServer(
            CFrame.lookAt(origin.Position, info.endpoint),
            shotEndCFrame
        )
        pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
            kind = "gun",
            tool = gun,
            toolName = gun and gun.Name or "Gun",
            originPos = origin.Position,
            aimPos = info.endpoint,
            target = target,
            silent = false,
            settings = {mode = "Normal", wallCheck = useWallCheck,
                leadSeconds = info.leadSeconds, motionSource = info.motionSource,
                model = info.model,
                sampleAge = info.sampleAge, samples = info.samples,
                referencePoint = info.capturedPosition and {info.capturedPosition.X, info.capturedPosition.Y, info.capturedPosition.Z},
                predictedPoint = {info.endpoint.X, info.endpoint.Y, info.endpoint.Z},
                sampledVelocity = {info.velocity.X, info.velocity.Y, info.velocity.Z},
                rtt = info.rtt, echoDelay = info.echoDelay,
                rttEngine = info.rttEngine, rttData = info.rttData,
                occluder = lastGunOccluder,
                echoSamples = info.echoSamples,
                turnRate = info.turnRate, brakeSeconds = info.brakeSeconds,
                leadCorrection = info.leadCorrection},
        })
        if not quiet and ShootFeature then ShootFeature:SetStatus(nil) end
        if not continuous then
            macroUnequip(gun)
        end
        return true
    end

    local shootOptionsReady: boolean = false
    local shootFeatureActive: boolean = false
    local autoShootActive: boolean = false
    local autoShootWanted: boolean = false
    local updateAutoShootConnection: (() -> ())? = nil

    local function refreshShootInfrastructure(): ()
        local wantActive: boolean = shootFeatureActive or autoShootActive
        state.mm2ShotFeedback.shootActive = wantActive
        if wantActive then
            local weaponService: any = getWeaponServiceModule()
            if type(weaponService) == "table" then
                connectGunFiredSignal(weaponService)
            end
            return
        end
        disconnectGunFiredObserver()
        state.mm2ShotFeedback.pending = nil
        state.mm2ShotFeedback.lastAccepted = nil
        state.mm2ShotFeedback.hide()
    end

    local manualShotPending: boolean = false
    local function triggerManualShot(): ()
        if not shootFeatureActive then
            notify("Enable SilentAIM first.")
            return
        end
        if manualShotPending then return end
        local character, humanoid = getCharacterParts()
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun")
        if not character or not humanoid or not gun then
            notify("No sheriff gun is available.")
            return
        end
        manualShotPending = true
        local ok: boolean, message: any = pcall(function(): ()
            if gun.Parent ~= character then
                humanoid:EquipTool(gun)
                -- Let the grip/muzzle update before sampling its origin.
                RunService.Heartbeat:Wait()
            end
            -- Never re-equip if the user switched away during that frame.
            if shootFeatureActive and LocalPlayer.Character == character and gun.Parent == character then
                fireGunAtTarget(getSelectedShootTarget(), {whenReady = true})
            end
        end)
        manualShotPending = false
        if not ok then notify("Shoot failed: " .. tostring(message)) end
    end

    local function toggleShootMurderer(enabled: boolean): ()
        shootFeatureActive = enabled
        state.mm2SilentAimEnabled = enabled
        if state.mm2KnifeThrowRefresh then state.mm2KnifeThrowRefresh() end
        autoShootActive = shootFeatureActive and autoShootWanted
        refreshShootInfrastructure()
        if updateAutoShootConnection then updateAutoShootConnection() end
    end

    local lastAutoStatus: string? = nil
    local function autoStatus(message: string): ()
        if ShootFeature and lastAutoStatus ~= message then
            lastAutoStatus = message
            ShootFeature:SetStatus(message)
        end
    end

    local function autoShootTick(): ()
        if not shootFeatureActive or not autoShootActive then return end
        local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun", true)
        if not gun or gun.Parent ~= LocalPlayer.Character then
            autoStatus("Equip gun")
            return
        end
        -- One pending slot: a second authored shot overwrites the first
        -- shot's record, its GunFired echo can no longer be matched and
        -- the calibration gains an unmatched signal. fireGunAtTarget applies
        -- the same gate to manual and automatic requests.
        if state and state.mm2ShotFeedback
            and state.mm2ShotFeedback.pending then
            autoStatus("Esperando confirmación")
            return
        end
        local target: Player? = getSelectedShootTarget()
        if not target then autoStatus("No target"); return end
        lastRejectReason = ""
        local sent: boolean = fireGunAtTarget(target, {whenReady = true, quiet = true})
        autoStatus(sent and "Auto: request sent" or lastRejectReason)
    end

    updateAutoShootConnection = function(): ()
        disconnectFeatureConnection("MM2AutoShoot")
        autoShootActive = shootOptionsReady and shootFeatureActive and autoShootWanted
        if not autoShootActive then
            lastAutoStatus = nil
            if ShootFeature then ShootFeature:SetStatus(nil) end
            return
        end
        -- One attempt per current frame, with no range/confidence/fire-delay
        -- timer. No cached aim or visibility survives into the next attempt.
        featureConnections.MM2AutoShoot = TaskManager:Connect(autoShootTick)
        autoShootTick()
    end

    local function toggleAutoShoot(enabled: boolean): ()
        autoShootWanted = enabled
        autoShootActive = shootFeatureActive and autoShootWanted
        refreshShootInfrastructure()
        if updateAutoShootConnection then updateAutoShootConnection() end
    end

    -- Preserve explicit bindings and enabled state when the old card becomes
    -- a child option. Never overwrite a setting already saved for the child.
    if type(configData) == "table" then
        local changed: boolean = false
        if configData.states["MM2.Shoot.AutoShoot"] == nil and configData.states["MM2.AutoShoot"] ~= nil then
            local enabled: boolean = configData.states["MM2.AutoShoot"] == true
            configData.states["MM2.Shoot.AutoShoot"] = enabled
            if enabled then configData.states["MM2.Shoot"] = true end
            changed = true
        end
        local oldKey: any = configData.values["Shortcut.MM2AutoShoot"]
        if configData.values["Shortcut.MM2ShootAutoShoot"] == nil and type(oldKey) == "string" then
            configData.values["Shortcut.MM2ShootAutoShoot"] = oldKey
            changed = true
        end
        if changed and type(queueConfigSave) == "function" then queueConfigSave() end
    end

    if type(configData) == "table" and configData.values["MM2.Shoot.Aimmethod"] == nil then
        configData.values["MM2.Shoot.Aimmethod"] = configData.values["MM2.Shoot.Mode"]
    end
    ShootFeature = createUniversalFeature(
        "Gun Aimbot",
        "Gun aimbot with Bullet and CFrame modes. The main assigned key fires/equips Gun. Every shot uses the kinematic predictor with the game-filter WallCheck.",
        4,
        toggleShootMurderer,
        {
            categoryName = "Combat",
            configKey = "MM2.Shoot", -- preserve existing Gun settings and activation key
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2SilentAimFeature = ShootFeature
    -- Other modules (Auto Shoot, Auto Farm's full-bag grab, Auto Win) fire
    -- through the exact Gun Aimbot path instead of hand-rolling their own shot.
    -- v139.4: the shared constructor accepts the caller's options. Without
    -- them Auto Shoot's own WallCheck setting was dropped on the floor: the
    -- wrapper hardcoded continuous=true, which is exactly the mode that used
    -- to skip the geometry check.
    state.mm2FireSilentShot = function(target: Player?, shotOpts: any): boolean
        local opts: any = type(shotOpts) == "table" and shotOpts or {}
        return fireGunAtTarget(target, {
            silent = true,
            quiet = opts.quiet ~= false,
            continuous = opts.continuous ~= false,
            wallCheck = opts.wallCheck,
        })
    end
    state.mm2FireGunShot = function(target: Player?, shotOpts: any): boolean
        local opts: any = type(shotOpts) == "table" and shotOpts or {}
        return fireGunAtTarget(target, {
            silent = opts.silent == true,
            wallCheck = opts.wallCheck,
            quiet = opts.quiet ~= false,
            continuous = opts.continuous ~= false,
        })
    end
    -- One card, two weapons: the heading keeps the gun rows together and the
    -- knife module opens its own section further down.
    if addSectionOption then addSectionOption(ShootFeature, "Gun") end
    local ShootTargetBox
    local function refreshShootOptions(): ()
        if ShootTargetBox then
            setOptionVisible(
                ShootFeature,
                ShootTargetBox.Parent :: GuiObject,
                mm2Settings.shootMode == "Custom"
            )
        end
    end
    addCycleOption(
        ShootFeature,
        "Aim method",
        {"Bullet", "CFrame"},
        mm2Settings.silentAim and 2 or 1,
        function(value: string): ()
            mm2Settings.silentAim = value == "CFrame" or value == "Silent AIM"
            refreshShootOptions()
        end,
        "Bullet fires from the gun; CFrame uses a near-target silent origin. "
            .. "Both respect WallCheck and always protect other players."
    )
    addCycleOption(
        ShootFeature,
        "Target",
        {"Murder", "Custom"},
        mm2Settings.shootMode == "Custom" and 2 or 1,
        function(value: string): ()
            mm2Settings.shootMode = value
            refreshShootOptions()
        end
    )

    if state.bindFeatureActivationKey then
        state.bindFeatureActivationKey(
            ShootFeature,
            mm2Settings.shootKey,
            triggerManualShot
        )
    end
    addToggleOption(
        ShootFeature,
        "WallCheck",
        mm2Settings.shootWallCheck,
        function(value: boolean): ()
            mm2Settings.shootWallCheck = value == true
        end,
        "Checks that no wall or solid barrier blocks the shot."
    )
    addToggleOption(
        ShootFeature,
        "Avoid innocents",
        mm2Settings.avoidInnocents ~= false,
        function(value: boolean): ()
            mm2Settings.avoidInnocents = value == true
        end,
        "The server ray keeps going past the murderer. With this on, the shot "
            .. "moves to a body part with nothing alive behind it, and is "
            .. "skipped when an innocent is right behind. Off: always shoot."
    )
    addToggleOption(
        ShootFeature,
        "Macro",
        shootMacro,
        function(value: boolean): ()
            shootMacro = value
        end,
        "Pistol macro: hides the gun 0.01 seconds after every shot."
    )
    ShootTargetBox = addTextOption(ShootFeature, "Target player", "", function(
        value: string
    ): ()
        mm2Settings.shootTarget = value
    end, false)
    refreshShootOptions()

    -- The visible Auto control is at the top, but arming waits until saved
    -- aim method/target options below have all been restored.
    shootOptionsReady = true
    if updateAutoShootConnection then updateAutoShootConnection() end

    activeCleanup = function(): ()
        toggleShootMurderer(false)
        state.mm2SilentAimFeature = nil
        state.mm2FireSilentShot = nil
        state.mm2FireGunShot = nil
        toggleAutoShoot(false)
        state.mm2ShotFeedback.hide()
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
