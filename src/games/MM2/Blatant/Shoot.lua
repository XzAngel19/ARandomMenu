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
    local describeRayHit: any = core.describeRayHit
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

    local SILENT_ORIGIN_STUDS: number = 2.5
    local SILENT_PIERCE_STUDS: number = 1.0
    local SILENT_LIFT_STUDS: number = 1.6
    local MAX_SILENT_SWEEP: number = 1.5
    -- Inside this distance the murderer's body covers the whole line of sight,
    -- so the lead stops helping and can even invert the shot: 17 studs/s of
    -- charge times a 0.1 s lead is 1.7 studs, more than the gap itself.
    local POINT_BLANK_STUDS: number = 6

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
            -- v161: the silent path is the CFrame mode; its measurements are
            -- the ones that size the sweep.
            local ok: boolean, seconds: any = pcall(
                prediction.getLeadUncertainty,
                "CFrame"
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
        _target: Player,
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
        return CFrame.lookAt(startPoint, endPoint), CFrame.new(endPoint),
            approachOffset, sweep, resolvedVariant
    end

    type FireOptions = {
        silent: boolean?,
        quiet: boolean?,
        whenReady: boolean?,
        continuous: boolean?,
        wallCheck: boolean?,
        -- Native PC hook: construct the same shot but let the original
        -- FireServer send it once instead of sending a second packet.
        redirect: ((CFrame, CFrame) -> ())?,
        nativeRedirect: boolean?,
        nativeOrigin: CFrame?,
    }

    -- Experimental policy, not a measured hit-rate optimization: prefer the
    -- ordinary muzzle path nearby/stationary and the CFrame path for a fast,
    -- distant target. It selects exactly one path per request; a refusal is
    -- not evidence that a second packet would be safe or accepted.
    local function chooseExperimentalGunMode(target: Player?, origin: Vector3?): string
        local character: Model? = target and target.Character
        local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not root or not origin then return "Bullet" end
        local speed: number = 0
        pcall(function(): ()
            local velocity: Vector3 = root.AssemblyLinearVelocity
            speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        end)
        if (root.Position - origin).Magnitude >= 30 and speed >= 8 then return "CFrame" end
        return "Bullet"
    end

    -- How long an authored request owns the gun. The feedback queue resolves
    -- or expires a shot at 1.6-1.8 s; keeping the window inside that bound
    -- means the gate never outlives the pending state it reads.
    local SHOT_CONFIRM_WINDOW: number = 1.5

    local ShootFeature: any = nil
    local lastRejectReason: string = ""

    -- The parts an aim may land on, best first, for the ghost preference.
    local AIM_BODY_PARTS: {string} = {
        "UpperTorso", "Torso", "HumanoidRootPart", "Head",
        "RightUpperArm", "LeftUpperArm", "RightUpperLeg", "LeftUpperLeg",
        "Right Arm", "Left Arm", "Right Leg", "Left Leg",
    }

    -- v161: the aim can be perfect and still be stopped by a GHOST part --
    -- transparent AND non-colliding, which every client wall check skips. The
    -- v159 session lost exactly that shot: 0.24 studs from the torso, occluder
    -- "Workspace.Workplace.Raggy.HumanoidRootPart", transparency 1,
    -- CanCollide false, 10.3 studs in front of the aim. What the server's own
    -- weapon ray does with such a part is not known, so this never refuses a
    -- shot: it only prefers another part of the same body whose line does not
    -- cross the ghost. If every candidate crosses it, the original point stands.
    local function ghostOnLine(
        muzzle: Vector3,
        endpoint: Vector3,
        targetCharacter: Model?
    ): any
        if type(describeRayHit) ~= "function" then
            return nil
        end
        local ok: boolean, hit: any = pcall(
            describeRayHit,
            muzzle,
            endpoint,
            targetCharacter
        )
        if not ok or type(hit) ~= "table" or hit.onTarget then
            return nil
        end
        if hit.transparency ~= 1 or hit.canCollide ~= false then
            return nil
        end
        local reach: number = (endpoint - muzzle).Magnitude
        if type(hit.distance) ~= "number" or hit.distance >= reach - 0.5 then
            return nil
        end
        return hit
    end

    -- The ghost probe is a preference, not a gate, so it is allowed to be
    -- stale: what is cached is which body part was clean, never a position.
    -- v162: Auto Shoot calls the aim path every frame; probing there cost up
    -- to 13 raycasts per frame. Now it costs at most 5 every 0.15 s and the
    -- cached answer is one FindFirstChild plus the same lead arithmetic.
    local GHOST_PROBE_INTERVAL: number = 0.15
    local GHOST_PROBE_CANDIDATES: number = 4
    local ghostProbe: any = {
        target = nil,
        at = -math.huge,
        partName = nil,
    }

    -- Returns a cleaner endpoint and the part it moved to, or nil.
    local function avoidGhostAim(
        target: Player,
        info: any,
        muzzle: Vector3
    ): (Vector3?, string?)
        local character: Model? = target.Character
        if not character or not info or typeof(info.endpoint) ~= "Vector3" then
            return nil, nil
        end
        local now: number = os.clock()
        if target ~= ghostProbe.target
            or now - ghostProbe.at >= GHOST_PROBE_INTERVAL then
            ghostProbe.target = target
            ghostProbe.at = now
            ghostProbe.partName = nil
            if ghostOnLine(muzzle, info.endpoint, character) then
                local captured: Vector3? = info.capturedPosition
                local probeLead: Vector3 = captured
                        and (info.endpoint - captured)
                    or Vector3.zero
                local tried: number = 0
                for _, partName: string in ipairs(AIM_BODY_PARTS) do
                    if tried >= GHOST_PROBE_CANDIDATES then
                        break
                    end
                    local part: Instance? = character:FindFirstChild(partName)
                    if part and part:IsA("BasePart") then
                        tried += 1
                        local candidate: Vector3 = (part :: BasePart).Position
                            + probeLead
                        if not ghostOnLine(muzzle, candidate, character) then
                            ghostProbe.partName = partName
                            break
                        end
                    end
                end
            end
        end
        local partName: string? = ghostProbe.partName
        if not partName then
            return nil, nil
        end
        local part: Instance? = character:FindFirstChild(partName)
        if not part or not part:IsA("BasePart") then
            ghostProbe.partName = nil
            return nil, nil
        end
        local captured: Vector3? = info.capturedPosition
        local lead: Vector3 = captured and (info.endpoint - captured) or Vector3.zero
        return (part :: BasePart).Position + lead, partName
    end

    local function fireGunAtTarget(
        target: Player?,
        options: FireOptions?
    ): boolean
        local opts: FireOptions = options or {}
        local silent: boolean = mm2Settings.silentAim
        local experimental: boolean = opts.silent == nil and mm2Settings.experimentalAim == true
        if experimental then
            local localCharacter: Model? = LocalPlayer and LocalPlayer.Character
            local ownRoot: BasePart? = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
            silent = chooseExperimentalGunMode(target, ownRoot and ownRoot.Position) == "CFrame"
        elseif opts.silent ~= nil then
            silent = opts.silent
        end
        local quiet: boolean = opts.quiet == true
        local continuous: boolean = opts.continuous == true
        -- An intercepted native FireServer is already being sent by the game.
        -- Rechecking a Tool that the native script just put on cooldown can
        -- only suppress the redirect, not prevent an extra shot.
        local nativeRedirect: boolean = opts.nativeRedirect == true and type(opts.redirect) == "function"
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
        if not nativeRedirect and (gun.Enabled == false or gun:GetAttribute("Disabled") == true
            or gun:GetAttribute("Reloading") == true or gun:GetAttribute("IsReloading") == true) then
            return reject("The gun is disabled or reloading.")
        end

        local remote: Instance? = gun and gun:FindFirstChild("Shoot")
        local okOrigin: boolean, foundOrigin: any = pcall(getGunOriginCFrame, character, gun)
        local origin: CFrame? = okOrigin and foundOrigin or nil
        if not origin and nativeRedirect and typeof(opts.nativeOrigin) == "CFrame" then
            origin = opts.nativeOrigin
        end

        -- v160: the two cheap gates move ABOVE the aim solve. Auto Shoot runs
        -- this function every frame; during the 1.5 s confirmation window it
        -- used to pay for the predictor plus wall rays and then
        -- reject at the very end. Refusing before the work leaves the firing
        -- instant unchanged (the gate is time based) and makes an Auto Shoot
        -- that is holding fire cost almost nothing per frame.
        local pendingShot: any = state.mm2ShotFeedback.pending
        if not continuous and not nativeRedirect
            and type(pendingShot) == "table"
            and type(pendingShot.queuedAt) == "number"
            and os.clock() - pendingShot.queuedAt < SHOT_CONFIRM_WINDOW then
            local remaining: number = SHOT_CONFIRM_WINDOW
                - (os.clock() - pendingShot.queuedAt)
            return reject(string.format(
                "Shot gate: waiting for the previous shot (%.1f s left).",
                remaining))
        end
        -- Do not overwrite the feedback record for an earlier shot just to
        -- redirect a second click; telemetry is optional and cannot gate it.
        local trackFeedback: boolean = not continuous
            and not (nativeRedirect and type(pendingShot) == "table")
        if not remote or not remote:IsA("RemoteEvent") or not origin then
            return reject(not origin and "The gun has no usable origin."
                or "The murderer is unavailable or obstructed.")
        end

        local info: any = nil
        local reason: string? = nil
        if origin then
            -- v161: tell the predictor which way this shot will be authored.
            -- Bullet and CFrame keep separate measured lead corrections.
            local aimMode: string = silent and "CFrame" or "Bullet"
            local ok: boolean, endpoint: any, aimInfo: any, aimReason: any =
                pcall(prediction.gunAim, target, origin.Position, aimMode)
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
        -- v186: an explicit manual press (the Gun Aimbot keybind) is the same
        -- kind of user act as the intercepted native click, so it gets the
        -- same validated first-sample fallback. Without it the press died
        -- silently whenever the predictor had no fresh sample yet (round
        -- start, target respawn), while a mouse click still fired: the gun
        -- appeared to ignore the keybind entirely.
        if (useRaw or continuous or nativeRedirect or opts.whenReady == true) and not info and target.Character then
            local targetRoot: BasePart? = target.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local vel: Vector3 = Vector3.zero
                pcall(function(): ()
                    vel = targetRoot.AssemblyLinearVelocity or Vector3.zero
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

        -- v161: the aim is final at this point; make sure its line does not
        -- cross a ghost body part (transparent + non-colliding) that every
        -- client wall check skips. Preference only: failure keeps the point.
        if info and origin and targetCharacter then
            local cleaner: Vector3?, cleanerPart: string? =
                avoidGhostAim(target, info, origin.Position)
            if cleaner then
                info.endpoint = cleaner
                info.targetPosition = cleaner
                info.ghostAvoided = cleanerPart
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
        -- firing while the Murderer is still alive. The gate itself is
        -- checked above, before any aim or raycast work.
        local function safeToSend(
            shotOrigin: CFrame,
            shotEnd: CFrame,
            muzzle: CFrame?
        ): boolean
            if gun.Parent ~= character or (not nativeRedirect and (gun.Enabled == false
                or gun:GetAttribute("Disabled") == true or gun:GetAttribute("Reloading") == true
                or gun:GetAttribute("IsReloading") == true)) then
                return reject("The gun is disabled or reloading.")
            end
            -- v139.4: "raw" means "do not wait for the near-target origin
            -- guard", NOT "do not look at walls". Raw/continuous Silent AIM
            -- used to return true here, so Auto Shoot and Auto Win (which call
            -- this path with continuous=true) fired with no wall check at all:
            -- the only geometry they ever saw was the near-target pass, never
            -- the gun's own line. When WallCheck is enabled, check the muzzle
            -- line too; Auto Farm explicitly opts out of that filter.
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
                    return reject("Could not construct the silent shot.")
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
            if trackFeedback then
                pcall(state.mm2ShotFeedback.queue, target, gun, shotOrigin, shotEnd)
            end

            state.lastSilentShotInfo = {
                variant = variant,
                at = os.clock(),
                offset = math.floor(offset * 10) / 10,
            }
            if opts.redirect then
                opts.redirect(shotOrigin, shotEnd)
            else
                remote:FireServer(shotOrigin, shotEnd)
            end

            local function recordSilent(): ()
                pcall(function(): ()
                    if not trajectoryCalibration or type(trajectoryCalibration.noteAuthoredShot) ~= "function" then return end
                    trajectoryCalibration:noteAuthoredShot({
                        kind = "gun",
                        source = nativeRedirect and "native-redirect" or "menu",
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
                            leadCorrection = info.leadCorrection,
                            leadCorrectionTarget = info.leadCorrectionTarget,
                            leadSamples = info.leadSamples, aimMode = info.aimMode,
                            ghostAvoided = info.ghostAvoided},
                    })
                end)
            end
            if nativeRedirect and task and type(task.defer) == "function" then
                task.defer(recordSilent)
            else
                recordSilent()
            end
            if not quiet and ShootFeature then
                ShootFeature:SetStatus(experimental and "Experimental · CFrame · request sent" or nil)
            end
            if not continuous then
                macroUnequip(gun)
            end
            return true
        end

        local shotEndCFrame: CFrame = CFrame.new(info.endpoint)
        if not safeToSend(origin, shotEndCFrame) then return false end
        if trackFeedback then
            pcall(state.mm2ShotFeedback.queue, target, gun, origin, shotEndCFrame)
        end
        -- Author one endpoint, without speculative "piercing" past it.
        -- Echo timing documents transport/visual confirmation, NOT rewind
        -- duration or an authoritative hit-rate denominator.
        local shotOriginCFrame: CFrame = CFrame.lookAt(origin.Position, info.endpoint)
        if opts.redirect then
            opts.redirect(shotOriginCFrame, shotEndCFrame)
        else
            remote:FireServer(shotOriginCFrame, shotEndCFrame)
        end
        local function recordBullet(): ()
            pcall(function(): ()
                if not trajectoryCalibration or type(trajectoryCalibration.noteAuthoredShot) ~= "function" then return end
                trajectoryCalibration:noteAuthoredShot({
                    kind = "gun",
                    source = nativeRedirect and "native-redirect" or "menu",
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
                        leadCorrection = info.leadCorrection,
                        leadCorrectionTarget = info.leadCorrectionTarget,
                        leadSamples = info.leadSamples, aimMode = info.aimMode,
                        ghostAvoided = info.ghostAvoided},
                })
            end)
        end
        if nativeRedirect and task and type(task.defer) == "function" then
            task.defer(recordBullet)
        else
            recordBullet()
        end
        if not quiet and ShootFeature then
            ShootFeature:SetStatus(experimental and "Experimental · Bullet · request sent" or nil)
        end
        if not continuous then
            macroUnequip(gun)
        end
        return true
    end

    local shootOptionsReady: boolean = false
    local shootFeatureActive: boolean = false
    local autoShootActive: boolean = false
    local autoShootWanted: boolean = false
    local transientShotActive: boolean = false
    local transientShotGeneration: number = 0
    local updateAutoShootConnection: (() -> ())? = nil

    local observerGeneration: number = 0
    -- v187: the native hook compares the intercepted remote against this
    -- cache, resolved OUTSIDE the hook. Resolving it inside the hook (the
    -- v183-v186 code called getPlayerWeapon/FindFirstChild there) performs
    -- namecalls of its own, which overwrite the pending namecall method;
    -- the original trampoline then dispatched the wrong method and the
    -- native Gun/Knife client calls died inside our hook ("argument #1
    -- expects a string, but Instance was passed", live session 2026-11-06).
    local cachedShootRemote: Instance? = nil
    local lastCacheProbeAt: number = -math.huge
    local function refreshShootRemoteCache(): ()
        local remote: Instance? = nil
        local okGun: boolean, foundGun: any = pcall(getPlayerWeapon, LocalPlayer, "Gun", true)
        local gun: Tool? = if okGun then foundGun else nil
        if gun then
            pcall(function(): ()
                local found: Instance? = gun:FindFirstChild("Shoot")
                if found and found:IsA("RemoteEvent") then
                    remote = found
                end
            end)
        end
        cachedShootRemote = remote
    end

    local function refreshShootInfrastructure(): ()
        observerGeneration += 1
        local generation: number = observerGeneration
        local wantActive: boolean = shootFeatureActive or autoShootActive or transientShotActive
        state.mm2ShotFeedback.shootActive = wantActive
        if wantActive then
            local function observe(): ()
                local weaponService: any = getWeaponServiceModule()
                if generation ~= observerGeneration or not state.mm2ShotFeedback.shootActive then return end
                if type(weaponService) == "table" then connectGunFiredSignal(weaponService) end
            end
            if state.isMobile then
                observe() -- preserve the mobile path
            else
                task.spawn(observe) -- never delay PC click redirection for an observer
            end
            refreshShootRemoteCache()
            return
        end
        disconnectGunFiredObserver()
        state.mm2ShotFeedback.pending = nil
        state.mm2ShotFeedback.lastAccepted = nil
        state.mm2ShotFeedback.hide()
        refreshShootRemoteCache()
    end

    local shotHookInstalled: boolean = false
    local shotHookWrapper: any = nil
    local originalNamecall: any = nil
    local function installNativeGunHook(): boolean
        if state.isMobile then return true end
        if shotHookInstalled then return true end
        local hook: any = state.hookMetamethod
        local getMethod: any = state.getNamecallMethod
        local checkCaller: any = state.checkCaller
        if type(hook) ~= "function" or type(getMethod) ~= "function"
            or type(checkCaller) ~= "function" then
            return false
        end
        local predecessor: any = nil
        -- v187: the v183-v186 hook performed its own method calls
        -- (getPlayerWeapon, FindFirstChild, raycasts) before invoking the
        -- original namecall trampoline. Every one of those calls overwrites
        -- the pending namecall method, so the trampoline dispatched
        -- whatever method ran last instead of FireServer and the native
        -- call died: live output showed "argument #1 expects a string, but
        -- Instance was passed" from this hook for KnifeClient calls, plus
        -- 'GetValue' (lacking capability Plugin) from GunClient -- the
        -- weapons stopped actuating while Gun Aimbot was on. Two rules now:
        -- (1) before the trampoline, only plain/C calls run: the method
        -- check, checkcaller, and a comparison against the Shoot remote
        -- cached OUTSIDE the hook; anything else trampolines immediately.
        -- (2) once the solver has run (and clobbered the method register
        -- beyond repair), modified or original frames are re-sent through
        -- the engine: a fresh remote:FireServer call re-enters this hook,
        -- which sees the guard flag and trampolines it while its method
        -- register is still exactly "FireServer".
        local resendingNativeShot: boolean = false
        local function resendThroughEngine(remote: any, ...: any): any
            resendingNativeShot = true
            local results: any = table.pack(pcall(function(...: any): any
                return ((remote :: any) :: RemoteEvent):FireServer(...)
            end, ...))
            resendingNativeShot = false
            if results[1] == true then
                return table.unpack(results, 2, results.n)
            end
            return nil
        end
        local function redirectNamecall(remote: any, ...: any): any
            if resendingNativeShot then
                return predecessor(remote, ...)
            end
            if not shootFeatureActive or not shootOptionsReady then
                return predecessor(remote, ...)
            end
            local okMethod: boolean, method: any = pcall(getMethod)
            if not okMethod or method ~= "FireServer" then
                return predecessor(remote, ...)
            end
            local okCaller: boolean, fromExecutor: any = pcall(checkCaller)
            if not okCaller or fromExecutor ~= false then
                -- Auto Shoot, Auto Farm, Knife and other executor-originated
                -- packets keep their own settings and never enter this hook.
                return predecessor(remote, ...)
            end
            if remote ~= cachedShootRemote then
                -- Not the gun's Shoot remote (or the cache has not caught
                -- up with a newly acquired gun): trampolines untouched,
                -- and schedule a cache refresh outside this call.
                if task and type(task.defer) == "function" then
                    local now: number = os.clock()
                    if now - lastCacheProbeAt >= 0.5 then
                        lastCacheProbeAt = now
                        task.defer(refreshShootRemoteCache)
                    end
                end
                return predecessor(remote, ...)
            end
            local arguments: any = table.pack(...)
            if typeof(arguments[1]) ~= "CFrame" or typeof(arguments[2]) ~= "CFrame" then
                return predecessor(remote, ...)
            end
            local shotOrigin: CFrame? = nil
            local shotEnd: CFrame? = nil
            local ok: boolean = pcall(function(): boolean
                lastRejectReason = ""
                return fireGunAtTarget(getSelectedShootTarget(), {
                    quiet = true,
                    nativeRedirect = true,
                    nativeOrigin = arguments[1],
                    redirect = function(origin: CFrame, endpoint: CFrame): ()
                        shotOrigin, shotEnd = origin, endpoint
                    end,
                })
            end)
            if shotOrigin and shotEnd then
                if ShootFeature then
                    pcall(function(): () ShootFeature:SetStatus("Native click redirected") end)
                end
                return resendThroughEngine(remote, shotOrigin, shotEnd,
                    table.unpack(arguments, 3, arguments.n))
            end
            if ShootFeature then
                pcall(function(): ()
                    ShootFeature:SetStatus(if not ok then "Native redirect failed; original click kept"
                        else (lastRejectReason ~= "" and lastRejectReason or "Native click unchanged"))
                end)
            end
            -- No target, blocked line, unsupported geometry or an error: keep
            -- the native click intact instead of blocking it or firing twice.
            -- Re-sent through the engine for the same reason as the redirect:
            -- the solver's own calls already clobbered the method register.
            return resendThroughEngine(remote, table.unpack(arguments, 1, arguments.n))
        end
        local callback: any = redirectNamecall
        if type(state.newCClosure) == "function" then
            local ok: boolean, wrapped: any = pcall(state.newCClosure, callback)
            if ok and type(wrapped) == "function" then callback = wrapped end
        end
        local ok: boolean, old: any = pcall(hook, game, "__namecall", callback)
        if not ok or type(old) ~= "function" then return false end
        predecessor = old
        originalNamecall, shotHookWrapper, shotHookInstalled = old, callback, true
        return true
    end

    local function uninstallNativeGunHook(): ()
        if not shotHookInstalled or type(state.hookMetamethod) ~= "function" then return end
        local ok: boolean, displaced: any = pcall(state.hookMetamethod, game, "__namecall", originalNamecall)
        if not ok then return end
        if displaced == shotHookWrapper then
            shotHookInstalled, shotHookWrapper, originalNamecall = false, nil, nil
        elseif type(displaced) == "function" then
            -- Someone else wrapped us. Put their hook back and leave our
            -- now-inert wrapper in their chain instead of clobbering it.
            pcall(state.hookMetamethod, game, "__namecall", displaced)
        end
    end

    local manualShotPending: boolean = false
    local function triggerManualShot(): ()
        if state.isMobile and not shootFeatureActive then
            notify("Enable Gun Aimbot first.")
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
            if (not state.isMobile or shootFeatureActive)
                and LocalPlayer.Character == character and gun.Parent == character then
                if not shootFeatureActive and not state.isMobile then
                    transientShotGeneration += 1
                    local generation: number = transientShotGeneration
                    transientShotActive = true
                    refreshShootInfrastructure()
                    task.delay(2, function(): ()
                        if generation ~= transientShotGeneration then return end
                        transientShotActive = false
                        refreshShootInfrastructure()
                    end)
                end
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
        if enabled and not state.isMobile then
            if not installNativeGunHook() then
                notify("Native click redirect needs executor hookmetamethod, getnamecallmethod and checkcaller; the keybind can still fire.")
            end
        elseif not enabled then
            uninstallNativeGunHook()
        end
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
        featureConnections.MM2AutoShoot =
            TaskManager:Connect(autoShootTick, nil, "MM2 Auto Shoot")
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
        state.isMobile
            and "Gun Aimbot with Normal(Bullet), Silent(Cframe), and Experimental modes. The assigned action fires/equips Gun; WallCheck is configurable per mode."
            or "Redirect native clicks with Bullet or Silent(CFrame). One optional keybind fires even while the module is off.",
        4,
        toggleShootMurderer,
        {
            categoryName = "Exploits",
            configKey = "MM2.Shoot", -- preserve existing Gun settings and activation key
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2SilentAimFeature = ShootFeature
    state.mm2ChooseExperimentalAim = chooseExperimentalGunMode
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
    local states: any = type(configData) == "table" and configData.states or {}
    local values: any = type(configData) == "table" and configData.values or {}
    -- Display names changed, but the old Bullet/CFrame keys keep their
    -- per-mode settings and remain valid when loading existing profiles.
    local function modeKey(value: any): string
        if value == "Experimental" then return "Experimental" end
        if value == "CFrame" or value == "Silent(Cframe)" or value == "Silent(CFrame)" then return "CFrame" end
        return "Bullet"
    end
    local savedMode: any = values["MM2.Shoot.Aimmethod"]
    local initialMode: string = modeKey(savedMode
        or (mm2Settings.experimentalAim and "Experimental" or (mm2Settings.silentAim and "CFrame" or "Bullet")))
    if state.isMobile then
        if savedMode == "Bullet" or savedMode == "CFrame" or savedMode == "Silent(CFrame)" then
            values["MM2.Shoot.Aimmethod"] = (savedMode == "CFrame" or savedMode == "Silent(CFrame)")
                and "Silent(Cframe)" or "Normal(Bullet)"
            if type(queueConfigSave) == "function" then queueConfigSave() end
        end
    else
        if initialMode == "Experimental" then initialMode = "Bullet" end
        local normalized: string = initialMode == "CFrame" and "Silent(CFrame)" or "Bullet"
        if values["MM2.Shoot.Aimmethod"] ~= normalized then
            values["MM2.Shoot.Aimmethod"] = normalized
            if type(queueConfigSave) == "function" then queueConfigSave() end
        end
    end
    local function modeConfig(mode: string): any
        local prefix: string = "MM2.Shoot." .. mode .. "."
        local legacy: boolean = mode == initialMode
        local wall: any = states[prefix .. "WallCheck"]
        local macro: any = states[prefix .. "Macro"]
        local targetMode: any = values[prefix .. "Target"]
        local targetName: any = values[prefix .. "TargetPlayer"]
        if legacy then
            if wall == nil then wall = states["MM2.Shoot.WallCheck"] end
            if macro == nil then macro = states["MM2.Shoot.Macro"] end
            if targetMode == nil then targetMode = values["MM2.Shoot.Target"] end
            if targetName == nil then targetName = values["MM2.Shoot.Targetplayer"] end
        end
        return {wallCheck = wall == nil or wall == true, macro = macro == true,
            targetMode = targetMode == "Custom" and "Custom" or "Murder",
            targetName = type(targetName) == "string" and targetName or ""}
    end
    local modeConfigs: any = {Bullet = modeConfig("Bullet"), CFrame = modeConfig("CFrame"),
        Experimental = modeConfig("Experimental")}
    local activeModeKey: string = initialMode
    local switching: boolean = false
    local optionsReady: boolean = false
    local ShootTargetBox
    local function refreshShootOptions(): ()
        if ShootTargetBox then
            setOptionVisible(ShootFeature, ShootTargetBox.Parent :: GuiObject, mm2Settings.shootMode == "Custom")
        end
    end
    local function syncMode(): ()
        local cfg: any = modeConfigs[activeModeKey] or modeConfigs.Bullet
        switching = true
        mm2Settings.shootWallCheck = cfg.wallCheck
        shootMacro, mm2Settings.shootMode, mm2Settings.shootTarget = cfg.macro, cfg.targetMode, cfg.targetName
        if state and type(state.toggleControls) == "table" then
            for _, item: any in ipairs({{"WallCheck", cfg.wallCheck}, {"Macro", cfg.macro}}) do
                local control: any = state.toggleControls["MM2.Shoot." .. item[1]]
                if control and control.setChecked then pcall(control.setChecked, item[2]) end
            end
        end
        if state and type(state.valueControls) == "table" then
            local target: any = state.valueControls["MM2.Shoot.Target"]
            local name: any = state.valueControls["MM2.Shoot.Targetplayer"]
            if target and target.apply then pcall(target.apply, cfg.targetMode) end
            if name and name.apply then pcall(name.apply, cfg.targetName) end
        end
        switching = false
        refreshShootOptions()
    end
    local aimMethods: {string} = state.isMobile
        and {"Normal(Bullet)", "Silent(Cframe)", "Experimental"}
        or {"Bullet", "Silent(CFrame)"}
    addCycleOption(ShootFeature, "Aim method", aimMethods,
        initialMode == "Experimental" and 3 or (initialMode == "CFrame" and 2 or 1),
        function(value: string): ()
            activeModeKey = modeKey(value)
            mm2Settings.experimentalAim = activeModeKey == "Experimental"
            mm2Settings.silentAim = activeModeKey == "CFrame"
            syncMode()
        end,
        state.isMobile
            and "Experimental selects one route based on movement and range; hit-rate improvement is unverified. Options are saved per mode."
            or "One keybind is shared; WallCheck and target settings are saved per mode.")
    addCycleOption(ShootFeature, "Target", {"Murder", "Custom"}, 1, function(value: string): ()
        mm2Settings.shootMode = value
        if optionsReady and not switching then
            modeConfigs[activeModeKey].targetMode = value
            values["MM2.Shoot." .. activeModeKey .. ".Target"] = value
        end
        refreshShootOptions()
    end)
    if state.bindFeatureActivationKey then
        state.bindFeatureActivationKey(ShootFeature, mm2Settings.shootKey, triggerManualShot)
    end
    if not state.isMobile then
        local binding: any = state.shortcutBindings and state.shortcutBindings[ShootFeature.configKey]
        if binding then binding.feedback = nil end
        if type(state.addFeatureShortcutOption) == "function" then
            state.addFeatureShortcutOption(ShootFeature, "Keybind",
                "Optional: click the box and press a key. It fires in either mode, even when Gun Aimbot is off.")
        end
    end
    addToggleOption(ShootFeature, "WallCheck", true, function(value: boolean): ()
        mm2Settings.shootWallCheck = value == true
        if optionsReady and not switching then
            modeConfigs[activeModeKey].wallCheck = value == true
            states["MM2.Shoot." .. activeModeKey .. ".WallCheck"] = value == true
        end
    end, "Check for walls; saved independently per mode.")
    addToggleOption(ShootFeature, "Macro", false, function(value: boolean): ()
        shootMacro = value == true
        if optionsReady and not switching then
            modeConfigs[activeModeKey].macro = value == true
            states["MM2.Shoot." .. activeModeKey .. ".Macro"] = value == true
        end
    end, "Pistol macro: hides the gun after the shot; saved per mode.")
    ShootTargetBox = addTextOption(ShootFeature, "Target player", "", function(value: string): ()
        mm2Settings.shootTarget = value
        if optionsReady and not switching then
            modeConfigs[activeModeKey].targetName = value
            values["MM2.Shoot." .. activeModeKey .. ".TargetPlayer"] = value
            if type(queueConfigSave) == "function" then queueConfigSave() end
        end
    end, false)
    optionsReady = true
    syncMode()

    -- The visible Auto control is at the top, but arming waits until saved
    -- aim method/target options below have all been restored.
    shootOptionsReady = true
    if shootFeatureActive and not state.isMobile and not shotHookInstalled then
        if not installNativeGunHook() then
            notify("Native click redirect needs executor hookmetamethod, getnamecallmethod and checkcaller; the keybind can still fire.")
        end
    end
    if updateAutoShootConnection then updateAutoShootConnection() end

    activeCleanup = function(): ()
        transientShotGeneration += 1
        transientShotActive = false
        toggleShootMurderer(false)
        state.mm2SilentAimFeature = nil
        state.mm2FireSilentShot = nil
        state.mm2FireGunShot = nil
        state.mm2ChooseExperimentalAim = nil
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
