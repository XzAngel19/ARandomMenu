local Module = {
    Name = "MM2 Fling Engine",
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- Internal MM2 engine only. Auto Farm and Auto Win keep their explicit fling
-- actions, while no Fling card or target action is installed in Universal.
function Module.init(runtime: any): any
    if Module.Initialized then return Module end
    local host: any = state.frameworkEnvironment
    local services: any = runtime and runtime.Services
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local activity: any = services and services.activity
    local protectedTargets: any = services and services.protectedTargets
    local configData: any = host.configData

    local workspace: any = host.workspace

    local function protectedCheck(player: Player?): boolean
        if not protectedTargets or type(protectedTargets.isProtected) ~= "function" then
            return false
        end
        local ok: boolean, result: any = pcall(protectedTargets.isProtected, player)
        return ok and result == true
    end

    -- v190: the MM2 Fling card is back (src/games/MM2/Other/Fling.lua), so the
    -- MM2.Fling* keys are no longer purged. The universal Fling module is still
    -- gone, and an "on" state saved by it must not be restored anywhere.
    if configData and type(configData.states) == "table" then
        configData.states["Universal.Fling"] = false
        configData.states["Universal.Fling.AutoFlingSelectedTarget"] = nil
        configData.states["MM2.Fling.AutoFlingSelectedTarget"] = nil
    end

    -- SkidFling (zqyDSUWX / YARHM), the fling every working menu copies:
    --
    --   RootPart.CFrame      = CFrame.new(targetPart.Position) * offset * spin
    --   RootPart.Velocity    = Vector3.new(9e7, 9e7 * 10, 9e7)
    --   RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
    --
    -- The local character is parked on the victim and given an absurd velocity
    -- while a finite-force BodyVelocity reinforces contact. The large impulse is
    -- applied briefly; the local body and other temporary state are restored
    -- afterwards. Actual transfer still depends on the server's physics.
    -- SkidFling adapted from the YARHM hub the user supplied
    -- (YARHM_Hub_KEYLESS_2026.txt, "Fling" -> SkidFling, originally by zqyDSUWX).
    -- MM2 callers supply a target; the engine keeps its power, prediction and retries.
    --
    -- The parts that matter and that our own port had wrong:
    --
    --   * The BodyVelocity named "EpixVel" drives at Vector3.new(9e8, 9e8, 9e8)
    --     with finite 9e9 MaxForce. It is a catapult, not a pin: the local body is
    --     thrown into the victim. With Velocity zero (our old version) nothing is
    --     transferred, the character just sits there and the camera flickers.
    --   * The pose is written through RootPart.CFrame *and*
    --     Character:SetPrimaryPartCFrame, then RootPart.Velocity/RotVelocity.
    --     No AssemblyLinearVelocity, no CustomPhysicalProperties: writing those
    --     every frame is what made our character look like it was fading.
    --   * Each pose is separated by task.wait() (Heartbeat, after physics), not
    --     RenderStepped.
    --   * Two pose sets: six poses while the victim is still (< 50 studs/s) and
    --     nine while it is already moving.
    -- Power 3 reproduces YARHM's numbers exactly (9e7 / 9e8); anything above
    -- scales BOTH textures of the trick (the pose velocity and the EpixVel pin),
    -- which is what makes the fling survive a laggy or fast-moving victim.
    local FLING_VELOCITY_BASE: Vector3 = Vector3.new(9e7, 9e7 * 10, 9e7)
    local FLING_ROT_VELOCITY_BASE: Vector3 = Vector3.new(9e8, 9e8, 9e8)
    local PIN_VELOCITY_BASE: Vector3 = Vector3.new(9e8, 9e8, 9e8)
    -- v180: finite force, like YARHM and SkidFling use. `math.huge` makes the
    -- solver fight itself on some servers (the pin "wins" every contact and the
    -- victim never receives the impulse), which is exactly the low success
    -- rate the former card was reporting.
    local PIN_FORCE: Vector3 = Vector3.new(9e9, 9e9, 9e9)

    -- v180's default 6 doubles the pose velocity against YARHM's baseline.
    -- The universal card/slider are gone; MM2 retains this fixed default.
    local FLING_POWER: number = 6
    local FLING_DURATION: number = 3
    local FLING_PREDICTION: number = 0.15
    local flingRetries: number = 2
    -- Temporary boost used by the second pass only (never persisted).
    local flingBoost: number = 1

    local function powerScale(): number
        return (FLING_POWER / 3) * flingBoost
    end

    local function scaledVelocity(base: Vector3): Vector3
        local scale: number = powerScale()
        return Vector3.new(base.X * scale, base.Y * scale, base.Z * scale)
    end

    local flingRunning: boolean = false
    local engineActive: boolean = true
    local fullFlingPin: any = nil
    local stepPhase: number = 0
    local stepAngle: number = 0
    local lastOldPos: CFrame? = nil
    local stepPin: any = nil
    local stepPinToken: number = 0

    local function setFlingRunning(running: boolean): ()
        flingRunning = running
        if activity and type(activity.set) == "function" then
            activity.set("fling", running)
        end
    end

    local function targetParts(targetPlayer: Player?): (Model?, Humanoid?, BasePart?, BasePart?, BasePart?)
        local targetCharacter: Model? = targetPlayer and targetPlayer.Character
        if not targetCharacter then
            return nil, nil, nil, nil, nil
        end
        local targetHumanoid: Humanoid? = targetCharacter:FindFirstChildOfClass("Humanoid")
        local targetRoot: BasePart? = targetHumanoid and targetHumanoid.RootPart or nil
        local targetHead: BasePart? = targetCharacter:FindFirstChild("Head") :: BasePart?
        return targetCharacter, targetHumanoid, targetRoot, targetHead, nil
    end

    -- FPos: the whole trick. Position on the victim part, then hand the assembly
    -- 9e7 and 9e8 so the contact solver launches the victim.
    local function fpos(
        character: Model,
        root: BasePart,
        basePart: BasePart,
        offset: CFrame,
        angles: CFrame,
        lead: Vector3?
    ): ()
        local origin: Vector3 = basePart.Position
        if lead then
            origin = origin + lead
        end
        local targetCFrame: CFrame = CFrame.new(origin) * offset * angles
        root.CFrame = targetCFrame
        character:SetPrimaryPartCFrame(targetCFrame)
        root.Velocity = scaledVelocity(FLING_VELOCITY_BASE)
        root.RotVelocity = scaledVelocity(FLING_ROT_VELOCITY_BASE)
    end

    -- Round trip / 2: how stale the server's copy of the victim is by the time it
    -- applies the pose we just wrote. With 300 ms of ping that is 150 ms of
    -- movement we have to lead with our own.
    local function transportSeconds(): number
        local ping: any = 0
        pcall(function(): ()
            local player: any = LocalPlayer
            if player and type(player.GetNetworkPing) == "function" then
                ping = player:GetNetworkPing()
            end
        end)
        if type(ping) ~= "number" or ping ~= ping or ping < 0 then
            ping = 0
        end
        -- GetNetworkPing returns seconds in current builds; older ones returned
        -- milliseconds. Anything above 2 is milliseconds.
        if ping > 2 then
            ping = ping / 1000
        end
        return math.clamp(ping * 0.5, 0, 0.5)
    end

    -- Where the victim will be when the server applies this pose: planar lead
    -- from its own velocity. Vertical lead is left out on purpose, it is the
    -- floor contact that carries the fling.
    local function leadFor(targetPart: BasePart?): Vector3?
        if not targetPart then
            return nil
        end
        local velocity: any = Vector3.zero
        pcall(function(): ()
            velocity = targetPart.AssemblyLinearVelocity
        end)
        if type(velocity) ~= "userdata" and type(velocity) ~= "table" then
            return nil
        end
        local seconds: number = math.clamp(
            transportSeconds() + FLING_PREDICTION,
            0,
            0.6
        )
        if seconds <= 0.001 then
            return nil
        end
        local lead: any = Vector3.new(velocity.X, 0, velocity.Z) * seconds
        return lead :: Vector3
    end

    -- The victim's own parts can be replaced (respawn, ragdoll, tool swap) while
    -- the fling runs; re-read them every pose instead of caching the first pair.
    local function liveTargetParts(
        targetPlayer: Player,
        targetCharacter: Model
    ): (Model?, Humanoid?, BasePart?, BasePart?)
        local character: Model? = targetPlayer.Character or targetCharacter
        if not character or not character.Parent then
            return nil, nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        local root: BasePart? = humanoid and humanoid.RootPart or nil
        local head: BasePart? = character:FindFirstChild("Head") :: BasePart?
        return character, humanoid, root, head
    end

    local function partSpeed(part: BasePart?): number
        return if part then part.Velocity.Magnitude else 0
    end

    -- cloneReference() gives the host a DIFFERENT reference for the same
    -- service, so "targetPlayer.Parent ~= Players" can stop the fling early.
    -- Resolve the player through the service instead.
    local function playerStillHere(player: Player): boolean
        return Players:FindFirstChild(player.Name) ~= nil
    end

    -- SFBasePart: YARHM's choreography (six poses while the victim is slow, ten
    -- while it is already moving), with the menu's adaptations:
    --
    --   * MIN_POSES before the "it is flying, stop" check, so one stale
    --     replication frame does not end the fling early;
    --   * the victim's parts are re-read on every pose (respawn, ragdoll);
    --   * each pose is led by the victim's own velocity times half the ping, so a
    --     300 ms connection still lands the contact.
    local MIN_POSES: number = 12

    local function sfBasePart(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        basePart: BasePart,
        targetCharacter: Model,
        targetPlayer: Player,
        targetHumanoid: Humanoid?,
        targetRoot: BasePart?,
        timeToWait: number,
        shouldStop: (() -> boolean)?,
        stats: any
    ): ()
        local startedAt: number = os.clock()
        local angle: number = 0
        local liveBase: BasePart = basePart

        local function currentBasePart(): BasePart?
            local characterNow: Model?, humanoidNow: Humanoid?, rootNow: BasePart?, headNow: BasePart? =
                liveTargetParts(targetPlayer, targetCharacter)
            if not characterNow then
                return nil
            end
            targetCharacter = characterNow
            targetHumanoid = humanoidNow or targetHumanoid
            targetRoot = rootNow or targetRoot
            local candidate: BasePart? = rootNow
            if rootNow and headNow then
                if (rootNow.Position - headNow.Position).Magnitude > 5 then
                    candidate = headNow
                end
            elseif headNow then
                candidate = headNow
            end
            if candidate and candidate.Parent then
                liveBase = candidate
            end
            return liveBase
        end

        local function pose(offset: CFrame, angles: CFrame): boolean
            -- Stop between individual yielded poses, not only once per group.
            if shouldStop and shouldStop() then return false end
            local part: BasePart? = currentBasePart()
            if not part then
                return false
            end
            fpos(character, root, part, offset, angles, leadFor(part))
            stats.poses += 1
            task.wait()
            return true
        end

        repeat
            if not root or not targetHumanoid then
                break
            end
            if shouldStop and shouldStop() then
                break
            end
            local part: BasePart? = currentBasePart()
            if not part then
                break
            end
            local speed: number = partSpeed(part)
            local moveDirection: Vector3 = Vector3.zero
            local walkSpeed: number = 16
            pcall(function(): ()
                moveDirection = targetHumanoid.MoveDirection
                walkSpeed = targetHumanoid.WalkSpeed
            end)
            if speed < 50 then
                angle = angle + 100
                local lead: Vector3 = moveDirection * (speed / 1.25)
                local spin: CFrame = CFrame.Angles(math.rad(angle), 0, 0)
                pose(CFrame.new(0, 1.5, 0) + lead, spin)
                pose(CFrame.new(0, -1.5, 0) + lead, spin)
                pose(CFrame.new(2.25, 1.5, -2.25) + lead, spin)
                pose(CFrame.new(-2.25, -1.5, 2.25) + lead, spin)
                pose(CFrame.new(0, 1.5, 0) + moveDirection, spin)
                pose(CFrame.new(0, -1.5, 0) + moveDirection, spin)
            else
                local downLead: number = partSpeed(targetRoot) / 1.25
                pose(CFrame.new(0, 1.5, walkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                pose(CFrame.new(0, -1.5, -walkSpeed), CFrame.Angles(0, 0, 0))
                pose(CFrame.new(0, 1.5, walkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                pose(CFrame.new(0, 1.5, downLead), CFrame.Angles(math.rad(90), 0, 0))
                pose(CFrame.new(0, -1.5, -downLead), CFrame.Angles(0, 0, 0))
                pose(CFrame.new(0, 1.5, downLead), CFrame.Angles(math.rad(90), 0, 0))
                pose(CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
                pose(CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                pose(CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(-90), 0, 0))
                pose(CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
            end
        until (stats.poses >= MIN_POSES and partSpeed(liveBase) > 500)
            or not liveBase.Parent
            or targetPlayer.Character ~= targetCharacter
            or not playerStillHere(targetPlayer)
            or (targetHumanoid ~= nil and targetHumanoid.Sit)
            or humanoid.Health <= 0
            or os.clock() > startedAt + timeToWait
            or stats.poses >= 600
    end

    local function createPin(root: BasePart): any
        local pin: any = Instance.new("BodyVelocity")
        pin.Name = "EpixVel"
        pin.Velocity = scaledVelocity(PIN_VELOCITY_BASE)
        pin.MaxForce = PIN_FORCE
        pin.Parent = root
        return pin
    end

    local function destroyPin(pin: any): ()
        if pin then pin:Destroy() end
    end

    -- Per-frame caller (Auto Win's Fling Sheriff). Same FPos pose, with a pin
    -- that is cleaned up 0.5 s after the last call so the local body is never
    -- left with an infinite-force catapult attached.
    local function flingSingleStep(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        targetPlayer: Player,
        _savedCollide: any,
        _savedProps: any
    ): boolean
        local targetCharacter: Model?, targetHumanoid: Humanoid?, targetRoot: BasePart?, targetHead: BasePart? =
            targetParts(targetPlayer)
        if not targetCharacter or not targetHead and not targetRoot then
            return false
        end
        if targetHumanoid and (targetHumanoid.Health <= 0 or targetHumanoid.Sit) then
            return false
        end
        if not targetHumanoid then
            return false
        end
        local basePart: BasePart = targetRoot or targetHead :: BasePart
        if targetRoot and targetHead then
            if (targetRoot.Position - targetHead.Position).Magnitude > 5 then
                basePart = targetHead
            end
        end
        if activity and type(activity.set) == "function" then
            activity.set("fling", true)
        end
        if not stepPin then
            stepPin = createPin(root)
        end
        stepPinToken += 1
        local myToken: number = stepPinToken
        task.delay(0.5, function(): ()
            if myToken == stepPinToken then
                destroyPin(stepPin)
                stepPin = nil
                if not flingRunning and activity and type(activity.set) == "function" then
                    activity.set("fling", false)
                end
            end
        end)
        stepAngle = (stepAngle + 100) % 360
        local speed: number = 0
        pcall(function(): ()
            speed = basePart.Velocity.Magnitude
        end)
        if speed < 50 then
            stepPhase = (stepPhase + 1) % 6
            local offsets: {CFrame} = {
                CFrame.new(0, 1.5, 0),
                CFrame.new(0, -1.5, 0),
                CFrame.new(2.25, 1.5, -2.25),
                CFrame.new(-2.25, -1.5, 2.25),
                CFrame.new(0, 1.5, 0),
                CFrame.new(0, -1.5, 0),
            }
            fpos(character, root, basePart, offsets[stepPhase + 1], CFrame.Angles(math.rad(stepAngle), 0, 0))
        else
            fpos(character, root, basePart, CFrame.new(0, 1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
        end
        return true
    end

    local function performFling(targetPlayer: Player?, options: {[string]: any}?): boolean
        if not Module.Initialized or not targetPlayer then
            return false
        end
        if protectedCheck(targetPlayer) then
            notify("player protected")
            return false
        end
        local silent: boolean = type(options) == "table" and options.silent == true
        local maxDuration: number = (type(options) == "table" and tonumber(options.duration))
            or FLING_DURATION
        local requestedStop: (() -> boolean)? = type(options) == "table"
            and type(options.shouldStop) == "function"
            and options.shouldStop
            or nil
        local function shouldStop(): boolean
            return not engineActive or (requestedStop ~= nil and requestedStop())
        end
        -- Auto Farm opts out of returning to an old round after cancellation.
        -- Other callers (including Auto Win) retain their existing return policy.
        local skipReturnOnStop: boolean = type(options) == "table" and options.skipReturnOnStop == true
        local returnCFrame: CFrame? = type(options) == "table"
            and typeof(options.returnCFrame) == "CFrame"
            and options.returnCFrame
            or nil
        -- v190: the MM2 Fling card passes its Power/Retries rows through
        -- options instead of the engine keeping global state. Callers that send
        -- nothing (Auto Farm, Auto Win) keep the documented defaults.
        local requestedPower: number? = nil
        local requestedRetries: number? = nil
        if type(options) == "table" then
            local power: number? = tonumber(options.power)
            if power then requestedPower = math.clamp(power, 1, 12) end
            local retries: number? = tonumber(options.retries)
            if retries then requestedRetries = math.clamp(math.floor(retries), 0, 3) end
        end

        if flingRunning then
            if not silent then
                notify("fling already running")
            end
            return false
        end

        setFlingRunning(true)

        local stats: any = {poses = 0, speed = 0, pinned = false, retries = 0}

        local function runFling(): boolean
            local character: Model?, humanoid: Humanoid?, root: BasePart? = getCharacterParts()
            if not character or not humanoid or not root then
                setFlingRunning(false)
                if not silent then
                    notify("character not ready")
                end
                return false
            end

            local targetCharacter: Model?, targetHumanoid: Humanoid?, targetRoot: BasePart?, targetHead: BasePart? =
                targetParts(targetPlayer)
            if not targetCharacter or not targetCharacter:FindFirstChildWhichIsA("BasePart") then
                setFlingRunning(false)
                if not silent then
                    notify("No valid character of said target player. May have died.")
                end
                return false
            end
            if not targetHumanoid then
                setFlingRunning(false)
                if not silent then
                    notify("the target has no humanoid")
                end
                return false
            end

            if partSpeed(root) < 50 then
                lastOldPos = root.CFrame
            end
            local oldPos: CFrame = returnCFrame or lastOldPos or root.CFrame

            local savedDestroyHeight: any = nil
            pcall(function(): ()
                savedDestroyHeight = workspace.FallenPartsDestroyHeight
            end)
            local camera: Camera? = workspace.CurrentCamera

            local pin: any = nil
            local success: boolean, errorMessage: any = pcall(function(): ()
                if camera then
                    pcall(function(): ()
                        local accessory: any = targetCharacter:FindFirstChildOfClass("Accessory")
                        camera.CameraSubject = targetHead
                            or (accessory and accessory:FindFirstChild("Handle"))
                            or targetHumanoid
                    end)
                end

                -- FallenPartsDestroyHeight = 0/0 while the local body crosses the
                -- map at 9e8 studs/s; always restored below.
                pcall(function(): ()
                    workspace.FallenPartsDestroyHeight = 0 / 0
                end)

                pin = createPin(root)
                fullFlingPin = pin
                stats.pinned = true
                pcall(function(): ()
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                end)

                local basePart: BasePart? = nil
                if targetRoot and targetHead then
                    if (targetRoot.Position - targetHead.Position).Magnitude > 5 then
                        basePart = targetHead
                    else
                        basePart = targetRoot
                    end
                elseif targetRoot then
                    basePart = targetRoot
                elseif targetHead then
                    basePart = targetHead
                end

                -- Retries can switch parts and temporarily boost force.
                local maxPasses: number = math.clamp(
                    math.floor(tonumber(flingRetries) or 0),
                    0,
                    3
                ) + 1
                local used: BasePart? = nil
                local pass: number = 0
                while pass < maxPasses do
                    if shouldStop and shouldStop() then break end
                    pass += 1
                    local partNow: BasePart? = nil
                    if pass == 1 then
                        partNow = basePart
                    else
                        local _c: Model?, _h: Humanoid?, rootNow: BasePart?, headNow: BasePart? =
                            liveTargetParts(targetPlayer, targetCharacter)
                        targetHumanoid = _h or targetHumanoid
                        targetRoot = rootNow or targetRoot
                        local primary: BasePart? = rootNow
                        if rootNow and headNow then
                            if (rootNow.Position - headNow.Position).Magnitude > 5 then
                                primary = headNow
                            end
                        elseif headNow then
                            primary = headNow
                        end
                        if primary == used then
                            partNow = if primary == rootNow then headNow else rootNow
                        else
                            partNow = primary
                        end
                        if partNow then
                            flingBoost = 1.5
                            stats.retries = (stats.retries or 0) + 1
                        end
                    end
                    if not partNow or not partNow.Parent then
                        flingBoost = 1
                        break
                    end
                    used = partNow
                    sfBasePart(
                        character,
                        humanoid,
                        root,
                        partNow,
                        targetCharacter,
                        targetPlayer,
                        targetHumanoid,
                        targetRoot,
                        -- Retries are half as long: they exist to catch a late
                        -- server contact, not to double the time spent posing.
                        if pass > 1 then maxDuration * 0.5 else maxDuration,
                        shouldStop,
                        stats
                    )
                    flingBoost = 1
                    stats.speed = math.max(
                        stats.speed or 0,
                        partSpeed(targetRoot),
                        partSpeed(targetHead)
                    )
                    if stats.speed > 100 then
                        break
                    end
                end
                stats.speed = math.max(
                    stats.speed or 0,
                    partSpeed(targetRoot),
                    partSpeed(targetHead)
                )
            end)

            -- The pin and temporary world state must be restored even if a pose
            -- failed. No secondary impulse is applied to the target.
            flingBoost = 1
            destroyPin(pin)
            if fullFlingPin == pin then fullFlingPin = nil end
            pcall(function(): ()
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
            end)
            pcall(function(): ()
                workspace.FallenPartsDestroyHeight = savedDestroyHeight
            end)
            local finalCharacter: Model?, finalHumanoid: Humanoid?, finalRoot: BasePart? =
                getCharacterParts()
            local cancelled: boolean = not engineActive or (skipReturnOnStop and shouldStop())
            if camera then
                pcall(function(): ()
                    camera.CameraSubject = if cancelled then (finalHumanoid or humanoid) else humanoid
                end)
            end

            local function stopBodyMotion(body: Model): ()
                for _, descendant: Instance in ipairs(body:GetChildren()) do
                    if descendant:IsA("BasePart") then
                        local bodyPart: BasePart = descendant :: BasePart
                        bodyPart.Velocity = Vector3.zero
                        bodyPart.RotVelocity = Vector3.zero
                    end
                end
            end
            if cancelled then
                -- A server teleport/new round may already have moved the body.
                -- Release the old fling velocity, but never move a new body or
                -- return the lobby body to the previous map's saved CFrame.
                pcall(stopBodyMotion, character)
            elseif finalCharacter and finalRoot and finalRoot.Parent then
                local attempts: number = 0
                repeat
                    if not engineActive or (skipReturnOnStop and shouldStop()) then
                        pcall(stopBodyMotion, character)
                        break
                    end
                    attempts += 1
                    pcall(function(): ()
                        finalRoot.CFrame = oldPos * CFrame.new(0, 0.5, 0)
                        finalCharacter:SetPrimaryPartCFrame(oldPos * CFrame.new(0, 0.5, 0))
                        if finalHumanoid then
                            pcall(function(): ()
                                finalHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                            end)
                        end
                        stopBodyMotion(finalCharacter)
                    end)
                    task.wait()
                until (finalRoot.Position - oldPos.Position).Magnitude < 25 or attempts >= 60
            end

            setFlingRunning(false)
            local touchedTarget: boolean = stats.speed > 100
            pcall(function(): ()
                state.mm2LastFling = {
                    target = tostring(targetPlayer.Name),
                    poses = stats.poses,
                    speed = stats.speed,
                    pinned = stats.pinned,
                    retries = stats.retries,
                    power = powerScale(),
                    ok = success,
                }
            end)
            if not Module.Initialized then
                return touchedTarget
            end
            if not silent then
                local speedText: string = tostring(math.floor(stats.speed))
                if not success then
                    notify("fling failed: " .. tostring(errorMessage))
                elseif touchedTarget then
                    notify(string.format(
                        "fling: %s sent flying (%s studs/s, %d poses%s)",
                        tostring(targetPlayer.Name),
                        speedText,
                        stats.poses,
                        (stats.retries or 0) > 0
                            and string.format(", %d retries", stats.retries)
                            or ""
                    ))
                else
                    notify(string.format(
                        "fling: %s did not move (%d poses, %s studs/s)",
                        tostring(targetPlayer.Name),
                        stats.poses,
                        speedText
                    ))
                end
            end
            return touchedTarget
        end

        -- Any error must reset flingRunning, otherwise every later fling answers
        -- "fling already running" for the rest of the session.
        local function guardedRun(): boolean
            local savedPower: number = FLING_POWER
            local savedRetries: number = flingRetries
            if requestedPower then FLING_POWER = requestedPower end
            if requestedRetries then flingRetries = requestedRetries end
            local ok: boolean, result: any = pcall(runFling)
            -- Restore before anything else: the engine is a single-fling
            -- machine and a later caller must not inherit this card's rows.
            FLING_POWER, flingRetries = savedPower, savedRetries
            if not ok then
                setFlingRunning(false)
                if not silent then
                    notify("fling error: " .. tostring(result))
                end
                return false
            end
            return result == true
        end

        if type(options) == "table" and options.blocking == true then
            return guardedRun()
        end
        task.spawn(guardedRun)
        return true
    end

    state.mm2PerformFling = performFling
    state.mm2FlingStep = flingSingleStep
    activeCleanup = function(): ()
        engineActive = false
        destroyPin(fullFlingPin)
        fullFlingPin = nil
        flingRunning = false
        stepPinToken += 1
        destroyPin(stepPin)
        stepPin = nil
        setFlingRunning(false)
        state.mm2PerformFling = nil
        state.mm2FlingStep = nil
    end
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if activeCleanup then pcall(activeCleanup) end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
