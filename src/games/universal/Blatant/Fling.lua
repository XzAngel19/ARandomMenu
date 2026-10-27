export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Fling",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

-- Fling is a universal card since v138.3: SkidFling works in any game, and the
-- only target it takes is the name typed in "Target player". The MM2 role
-- actions stay available when the Murder Mystery 2 core happens to be loaded.
function Module.init(context: Runtime): any
    local host: any = context.host
    local services: any = (context :: any).services
    local Players: any = host.Players
    local LocalPlayer: any = host.LocalPlayer
    local getCharacterParts: any = host.getCharacterParts
    local notify: any = host.notify
    local activity: any = services and services.activity
    local protectedTargets: any = services and services.protectedTargets
    local gameBridge: any = services and services.gameBridge
    local createUniversalFeature: any = host.createUniversalFeature
    local addActionOption: any = host.addActionOption
    local addTextOption: any = host.addTextOption
    local addInformationOption: any = host.addInformationOption
    local findPlayerByText: any = host.findPlayerByText
    local configData: any = host.configData

    local workspace: any = host.workspace
    local RunService: any = host.RunService

    -- The MM2 core only exists while Murder Mystery 2 is loaded; every role call
    -- is resolved lazily so the card works everywhere and never errors outside
    -- MM2.
    local function mm2Core(): any
        local ok: boolean, core: any = pcall(function(): any
            return state.mm2Core
        end)
        if ok and type(core) == "table" then
            return core
        end
        return nil
    end

    local function coreFunction(name: string): any
        local core: any = mm2Core()
        if core and type(core[name]) == "function" then
            return core[name]
        end
        return nil
    end

    local function protectedCheck(player: Player?): boolean
        if not protectedTargets or type(protectedTargets.isProtected) ~= "function" then
            return false
        end
        local ok: boolean, result: any = pcall(protectedTargets.isProtected, player)
        return ok and result == true
    end

    -- The old MM2 card owned these keys. They are dropped so a saved config from
    -- v138..v138.2 cannot restore a target or a toggle that no longer exists.
    if configData and type(configData.states) == "table" then
        configData.states["MM2.Fling"] = nil
        configData.states["MM2.Fling.AutoFlingSelectedTarget"] = nil
        configData.states["MM2.Fling.TouchFling"] = nil
        configData.states["Universal.Fling"] = false
    end

    -- SkidFling (zqyDSUWX / YARHM), the fling every working menu copies:
    --
    --   RootPart.CFrame      = CFrame.new(targetPart.Position) * offset * spin
    --   RootPart.Velocity    = Vector3.new(9e7, 9e7 * 10, 9e7)
    --   RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
    --
    -- The local character is parked on the victim and given an absurd velocity
    -- while a BodyVelocity (Velocity 0, MaxForce 9e9) keeps it from being thrown
    -- into the sky. That enormous velocity exists just long enough for the
    -- contact solver to hand it to the victim, which is why this version actually
    -- launches people and the old CFrame-lock one did not.
    -- SkidFling, copied line by line from the YARHM hub the user supplied
    -- (YARHM_Hub_KEYLESS_2026.txt, "Fling" -> SkidFling, originally by zqyDSUWX).
    --
    -- The parts that matter and that our own port had wrong:
    --
    --   * The BodyVelocity named "EpixVel" drives at Vector3.new(9e8, 9e8, 9e8)
    --     with infinite MaxForce. It is a catapult, not a pin: the local body is
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
    local FLING_VELOCITY: Vector3 = Vector3.new(9e7, 9e7 * 10, 9e7)
    local FLING_ROT_VELOCITY: Vector3 = Vector3.new(9e8, 9e8, 9e8)
    local PIN_VELOCITY: Vector3 = Vector3.new(9e8, 9e8, 9e8)
    local PIN_FORCE: Vector3 = Vector3.new(math.huge, math.huge, math.huge)

    local flingRunning: boolean = false
    local flingTargetName: string = ""
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

    -- task.wait(), like the original: it resumes on Heartbeat, one physics step
    -- after the pose was written.
    local function waitFrame(): ()
        if type(task) == "table" and type(task.wait) == "function" then
            task.wait()
        end
    end

    local function moveCharacter(character: Model, cframe: CFrame): ()
        -- SetPrimaryPartCFrame is what the original calls; PivotTo is the modern
        -- equivalent when the executor/engine no longer exposes the old one.
        if type(character.SetPrimaryPartCFrame) == "function" then
            character:SetPrimaryPartCFrame(cframe)
        elseif type(character.PivotTo) == "function" then
            character:PivotTo(cframe)
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
        angles: CFrame
    ): ()
        local targetCFrame: CFrame = CFrame.new(basePart.Position) * offset * angles
        pcall(function(): ()
            root.CFrame = targetCFrame
            moveCharacter(character, targetCFrame)
            root.Velocity = FLING_VELOCITY
            root.RotVelocity = FLING_ROT_VELOCITY
        end)
    end

    local function nowSeconds(): number
        -- YARHM times the loop with tick(). os.clock() is the fallback and 0 the
        -- last resort; the pose counter below keeps the loop bounded either way.
        local ok: boolean, value: any = pcall(function(): any
            return tick()
        end)
        if ok and type(value) == "number" then
            return value
        end
        ok, value = pcall(function(): any
            return os.clock()
        end)
        if ok and type(value) == "number" then
            return value
        end
        return 0
    end

    -- Vector3 is userdata in the client and a table in the harness: read the
    -- magnitude through pcall instead of type() so both work.
    local function partSpeed(part: BasePart?): number
        if not part then
            return 0
        end
        local ok: boolean, velocity: any = pcall(function(): any
            return part.Velocity
        end)
        if not ok or not velocity then
            return 0
        end
        local okMagnitude: boolean, magnitude: any = pcall(function(): any
            return velocity.Magnitude
        end)
        if okMagnitude and type(magnitude) == "number" then
            return magnitude
        end
        return 0
    end

    -- cloneReference() gives the host a DIFFERENT reference for the same
    -- service, so "targetPlayer.Parent ~= Players" is true even for a player who
    -- is in the game. That checked true on every frame and killed the loop after
    -- a single pose set (the "finished in half a second" bug). Ask the service
    -- instead, and never stop the loop when the answer is unknown.
    local function playerStillHere(player: Player): boolean
        local ok: boolean, found: any = pcall(function(): any
            return Players:FindFirstChild(player.Name)
        end)
        if not ok then
            return true
        end
        return found ~= nil
    end

    -- SFBasePart: the choreography, exactly as written in YARHM.
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
        local startedAt: number = nowSeconds()
        local angle: number = 0
        repeat
            if not root or not targetHumanoid then
                break
            end
            if shouldStop and shouldStop() then
                break
            end
            local speed: number = partSpeed(basePart)
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
                fpos(character, root, basePart, CFrame.new(0, 1.5, 0) + lead, spin)
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, -1.5, 0) + lead, spin)
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(2.25, 1.5, -2.25) + lead, spin)
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(-2.25, -1.5, 2.25) + lead, spin)
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, 1.5, 0) + moveDirection, spin)
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, -1.5, 0) + moveDirection, spin)
                stats.poses += 1
                waitFrame()
            else
                local downLead: number = partSpeed(targetRoot) / 1.25
                fpos(character, root, basePart, CFrame.new(0, 1.5, walkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, -1.5, -walkSpeed), CFrame.Angles(0, 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, 1.5, walkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, 1.5, downLead), CFrame.Angles(math.rad(90), 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, -1.5, -downLead), CFrame.Angles(0, 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, 1.5, downLead), CFrame.Angles(math.rad(90), 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(-90), 0, 0))
                stats.poses += 1
                waitFrame()
                fpos(character, root, basePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                stats.poses += 1
                waitFrame()
            end
        until partSpeed(basePart) > 500
            or basePart.Parent ~= targetCharacter
            or targetPlayer.Character ~= targetCharacter
            or not playerStillHere(targetPlayer)
            or targetHumanoid.Sit
            or humanoid.Health <= 0
            or nowSeconds() > startedAt + timeToWait
            or stats.poses >= 600
    end

    -- Only used if SkidFling could not move the target at all: spin and push the
    -- victim's own part for two frames. Everything created here is destroyed and
    -- the result is reported in the notification, so it can never be silent.
    local RESCUE_SPIN: Vector3 = Vector3.new(1000, 1000, 1000)
    local RESCUE_PUSH: Vector3 = Vector3.new(0, 500, 0)

    local function rescueImpulse(targetCharacter: Model, targetRoot: BasePart?, targetHead: BasePart?): boolean
        local target: BasePart? = targetRoot or targetHead
        if not target then
            return false
        end
        local created: {any} = {}
        local ok: boolean = pcall(function(): ()
            local spin: any = Instance.new("BodyAngularVelocity")
            spin.Name = "Wurst_RescueSpin"
            spin.AngularVelocity = RESCUE_SPIN
            spin.MaxTorque = PIN_FORCE
            spin.Parent = target
            table.insert(created, spin)
            local push: any = Instance.new("BodyVelocity")
            push.Name = "Wurst_RescuePush"
            push.Velocity = RESCUE_PUSH
            push.MaxForce = PIN_FORCE
            push.Parent = target
            table.insert(created, push)
            for _, part: Instance in ipairs(targetCharacter:GetChildren()) do
                if part:IsA("BasePart") then
                    local bodyPart: BasePart = part :: BasePart
                    bodyPart.Velocity = RESCUE_PUSH
                    bodyPart.RotVelocity = RESCUE_SPIN
                end
            end
        end)
        waitFrame()
        waitFrame()
        for _, item: any in ipairs(created) do
            pcall(function(): ()
                item:Destroy()
            end)
        end
        return ok and #created > 0
    end

    local function createPin(root: BasePart): any
        local ok: boolean, pin: any = pcall(function(): any
            local bodyVelocity: any = Instance.new("BodyVelocity")
            bodyVelocity.Name = "EpixVel"
            bodyVelocity.Parent = root
            bodyVelocity.Velocity = PIN_VELOCITY
            bodyVelocity.MaxForce = PIN_FORCE
            return bodyVelocity
        end)
        if ok and pin then
            return pin
        end
        -- Some executors reject math.huge in a Vector3. 1e9 is the same catapult
        -- for every practical purpose, so the fling still lands.
        local okFallback: boolean, fallback: any = pcall(function(): any
            local bodyVelocity: any = Instance.new("BodyVelocity")
            bodyVelocity.Name = "EpixVel"
            bodyVelocity.Parent = root
            bodyVelocity.Velocity = PIN_VELOCITY
            bodyVelocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
            return bodyVelocity
        end)
        if okFallback then
            return fallback
        end
        return nil
    end

    local function destroyPin(pin: any): ()
        if not pin then
            return
        end
        pcall(function(): ()
            pin:Destroy()
        end)
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
        if type(task) == "table" and type(task.delay) == "function" then
            task.delay(0.5, function(): ()
                if myToken == stepPinToken then
                    destroyPin(stepPin)
                    stepPin = nil
                    if not flingRunning and activity and type(activity.set) == "function" then
                        activity.set("fling", false)
                    end
                end
            end)
        end
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
        local maxDuration: number = (type(options) == "table" and tonumber(options.duration)) or 2
        local shouldStop: (() -> boolean)? = type(options) == "table"
            and type(options.shouldStop) == "function"
            and options.shouldStop
            or nil
        local returnCFrame: CFrame? = type(options) == "table"
            and typeof(options.returnCFrame) == "CFrame"
            and options.returnCFrame
            or nil

        if flingRunning then
            if not silent then
                notify("fling already running")
            end
            return false
        end

        setFlingRunning(true)

        local stats: any = {poses = 0, speed = 0, pinned = false, rescued = false}

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

                local pin: any = createPin(root)
                stats.pinned = pin ~= nil
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
                if basePart then
                    sfBasePart(
                        character,
                        humanoid,
                        root,
                        basePart,
                        targetCharacter,
                        targetPlayer,
                        targetHumanoid,
                        targetRoot,
                        maxDuration,
                        shouldStop,
                        stats
                    )
                end

                stats.speed = math.max(partSpeed(targetRoot), partSpeed(targetHead))
                if stats.speed <= 100 then
                    stats.rescued = rescueImpulse(targetCharacter, targetRoot, targetHead)
                    stats.speed = math.max(partSpeed(targetRoot), partSpeed(targetHead), stats.speed)
                end

                destroyPin(pin)
                pcall(function(): ()
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
                end)
            end)

            pcall(function(): ()
                workspace.FallenPartsDestroyHeight = savedDestroyHeight
            end)
            if camera then
                pcall(function(): ()
                    camera.CameraSubject = humanoid
                end)
            end

            local finalCharacter: Model?, finalHumanoid: Humanoid?, finalRoot: BasePart? =
                getCharacterParts()
            if finalCharacter and finalRoot and finalRoot.Parent then
                local attempts: number = 0
                repeat
                    attempts += 1
                    pcall(function(): ()
                        finalRoot.CFrame = oldPos * CFrame.new(0, 0.5, 0)
                        moveCharacter(finalCharacter, oldPos * CFrame.new(0, 0.5, 0))
                        if finalHumanoid then
                            pcall(function(): ()
                                finalHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                            end)
                        end
                        for _, descendant: Instance in ipairs(finalCharacter:GetChildren()) do
                            if descendant:IsA("BasePart") then
                                local bodyPart: BasePart = descendant :: BasePart
                                bodyPart.Velocity = Vector3.zero
                                bodyPart.RotVelocity = Vector3.zero
                            end
                        end
                    end)
                    waitFrame()
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
                    rescued = stats.rescued,
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
                        "fling: %s sent flying (%s studs/s, %d poses)",
                        tostring(targetPlayer.Name),
                        speedText,
                        stats.poses
                    ))
                else
                    notify(string.format(
                        "fling: %s did not move (%d poses, %s studs/s%s)",
                        tostring(targetPlayer.Name),
                        stats.poses,
                        speedText,
                        stats.rescued and ", rescue used" or ""
                    ))
                end
            end
            return touchedTarget
        end

        -- Any error must reset flingRunning, otherwise every later fling answers
        -- "fling already running" for the rest of the session.
        local function guardedRun(): boolean
            local ok: boolean, result: any = pcall(runFling)
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
    local function refreshRoles(): ()
        if type(state.clearRoleMemo) == "function" then
            pcall(state.clearRoleMemo)
        end
        local requestRefresh: any = coreFunction("requestRoleRefresh")
        if requestRefresh then
            pcall(requestRefresh, false)
        end
    end

    local function roleOf(player: Player): any
        local getPlayerRole: any = coreFunction("getPlayerRole")
        local role: any = type(getPlayerRole) == "function" and getPlayerRole(player) or nil
        if not role and gameBridge and type(gameBridge.playerRole) == "function" then
            local okRole: boolean, resolved: any = pcall(gameBridge.playerRole, player)
            if okRole then
                role = resolved
            end
        end
        return role
    end

    local function weaponOf(player: Player, kind: string): any
        local getPlayerWeapon: any = coreFunction("getPlayerWeapon")
        if type(getPlayerWeapon) ~= "function" then
            return nil
        end
        local ok: boolean, weapon: any = pcall(getPlayerWeapon, player, kind, false)
        return ok and weapon or nil
    end

    local function playerAlive(player: Player): boolean
        local isPlayerAlive: any = coreFunction("isPlayerAlive")
        if type(isPlayerAlive) ~= "function" then
            return true
        end
        local ok: boolean, alive: any = pcall(isPlayerAlive, player)
        return not ok or alive ~= false
    end

    local function resolveMurdererTarget(): Player?
        refreshRoles()
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
                and playerAlive(player)
                and weaponOf(player, "Gun") == nil
                and weaponOf(player, "Knife") ~= nil then
                return player
            end
        end
        local findMurderer: any = coreFunction("findMurderer")
        if type(findMurderer) == "function" then
            local ok: boolean, target: any = pcall(findMurderer)
            if ok and target and target ~= LocalPlayer and playerAlive(target) then
                if weaponOf(target, "Gun") == nil then
                    local role: any = roleOf(target)
                    if role ~= "Hero" and role ~= "Sheriff" and role ~= "Dead" then
                        return target :: Player
                    end
                end
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and playerAlive(player) and weaponOf(player, "Gun") == nil then
                if roleOf(player) == "Murderer" then
                    return player
                end
            end
        end
        return nil
    end

    local function resolveSheriffOrHeroTarget(): Player?
        refreshRoles()
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
                and playerAlive(player)
                and weaponOf(player, "Knife") == nil
                and weaponOf(player, "Gun") ~= nil then
                return player
            end
        end
        local findSheriff: any = coreFunction("findSheriff")
        if type(findSheriff) == "function" then
            local ok: boolean, target: any = pcall(findSheriff)
            if ok and target and target ~= LocalPlayer and playerAlive(target) then
                if weaponOf(target, "Knife") == nil then
                    local role: any = roleOf(target)
                    if role ~= "Murderer" and role ~= "Dead" then
                        return target :: Player
                    end
                end
            end
        end
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and playerAlive(player) and weaponOf(player, "Knife") == nil then
                local role: any = roleOf(player)
                if role == "Sheriff" or role == "Hero" then
                    return player
                end
            end
        end
        return nil
    end

    -- The typed name is matched against username and display name: exact first,
    -- then prefix, then substring ("the list" is simply what is typed here).
    local function resolvePlayerByQuery(rawQuery: string): Player?
        local query: string = string.lower(string.gsub(rawQuery or "", "^%s*(.-)%s*$", "%1"))
        if query == "" then
            return nil
        end
        if type(findPlayerByText) == "function" then
            local okFind: boolean, found: any = pcall(findPlayerByText, rawQuery)
            if okFind and found and found ~= LocalPlayer then
                return found :: Player
            end
        end
        local compactQuery: string = string.gsub(query, "%s+", "")
        local prefixMatch: Player? = nil
        local partialMatch: Player? = nil
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local uName: string = string.lower(tostring(player.Name or ""))
                local dName: string = string.lower(tostring((player :: any).DisplayName or player.Name or ""))
                local uCompact: string = string.gsub(uName, "%s+", "")
                local dCompact: string = string.gsub(dName, "%s+", "")
                if uName == query or dName == query
                    or uCompact == compactQuery or dCompact == compactQuery then
                    return player
                end
                if not prefixMatch and (
                    string.sub(uName, 1, #query) == query
                    or string.sub(dName, 1, #query) == query
                ) then
                    prefixMatch = player
                end
                if not partialMatch and (
                    string.find(uName, query, 1, true) ~= nil
                    or string.find(dName, query, 1, true) ~= nil
                    or string.find(uCompact, compactQuery, 1, true) ~= nil
                    or string.find(dCompact, compactQuery, 1, true) ~= nil
                ) then
                    partialMatch = player
                end
            end
        end
        return prefixMatch or partialMatch
    end

    local function resolveSelectedTargetPlayer(): Player?
        local typed: string = string.gsub(flingTargetName or "", "%s+", "")
        if typed == "" then
            return nil
        end
        return resolvePlayerByQuery(flingTargetName)
    end

    -- The card is a group: this only reports the container state. Turning it off
    -- never starts a fling, and nothing here runs on injection.
    local function toggleFlingModule(enabled: boolean): ()
        if activity and type(activity.set) == "function" then
            activity.set("fling", flingRunning and enabled == true)
        end
    end

    local FlingFeature: any = createUniversalFeature(
        "Fling",
        "SkidFling: throw the player typed in Target player (MM2 roles when available)",
        7,
        toggleFlingModule,
        {category = true, categoryName = "Exploits", configKey = "Universal.Fling"}
    )

    -- This box is the whole target list: type a username or display name and the
    -- Fling button uses it. There is no dropdown and no separate "select" step.
    addTextOption(
        FlingFeature,
        "Target player",
        "",
        function(value: string): ()
            flingTargetName = value
        end,
        false,
        "Username or display name. This box is the target list."
    )
    addActionOption(FlingFeature, "Fling", function(): ()
        local target: Player? = resolveSelectedTargetPlayer()
        if target then
            performFling(target)
        else
            notify("No player matched what is typed in Target player.")
        end
    end)
    addActionOption(FlingFeature, "Fling Murderer", function(): ()
        if not mm2Core() then
            notify("Fling Murderer needs Murder Mystery 2; use Target player here.")
            return
        end
        local target: Player? = resolveMurdererTarget()
        if target then
            performFling(target)
        else
            notify("No murderer was found.")
        end
    end)
    addActionOption(FlingFeature, "Fling Sheriff", function(): ()
        if not mm2Core() then
            notify("Fling Sheriff needs Murder Mystery 2; use Target player here.")
            return
        end
        local target: Player? = resolveSheriffOrHeroTarget()
        if target then
            performFling(target)
        else
            notify("No sheriff or hero was found.")
        end
    end)
    addActionOption(FlingFeature, "Fling All Innocents", function(): ()
        if not mm2Core() then
            notify("Fling All Innocents needs Murder Mystery 2; use Target player here.")
            return
        end
        refreshRoles()
        task.spawn(function(): ()
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(coreFunction("isPlayerAlive")) ~= "function"
                        or coreFunction("isPlayerAlive")(player)) then
                    local weaponFn: any = coreFunction("getPlayerWeapon")
                    local roleFn: any = coreFunction("getPlayerRole")
                    local hasKnife: boolean = type(weaponFn) == "function"
                        and weaponFn(player, "Knife", false) ~= nil
                    local hasGun: boolean = type(weaponFn) == "function"
                        and weaponFn(player, "Gun", false) ~= nil
                    local role: any = type(roleFn) == "function" and roleFn(player) or nil
                    if not role and gameBridge and type(gameBridge.playerRole) == "function" then
                        local okRole: boolean, r: any = pcall(gameBridge.playerRole, player)
                        if okRole then
                            role = r
                        end
                    end
                    if not hasKnife and not hasGun and role == "Innocent" then
                        performFling(player, {blocking = true})
                        task.wait(0.05)
                    end
                end
            end
        end)
    end)
    addInformationOption(
        FlingFeature,
        "Type a name in Target player and press Fling. Walk Fling is its own card."
    )

    activeCleanup = function(): ()
        flingRunning = false
        setFlingRunning(false)
        state.mm2PerformFling = nil
        state.mm2FlingStep = nil
    end
    Module.Initialized = true
    return FlingFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
