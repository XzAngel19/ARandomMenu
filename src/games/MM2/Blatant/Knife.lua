local Module = {
    Name = "MM2 Knife",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

--[[
    MM2 Knife - one card for everything the murderer's blade does.

    Knife Aura and Knife Throw used to be two separate cards that duplicated
    the same "who can I legally hit" logic and disagreed about it. They are one
    module now: the blade is one weapon, and the two ways of using it are two
    toggles on it.

    AURA  stabs the nearest valid target in range through the game's own
          HandleTouched remote - the same path a real swing takes, so nothing
          about the packet is unusual.

    THROW fires KnifeThrown with an authored origin/aim pair:

        KnifeThrown:FireServer(CFrame.new(origin), CFrame.new(aim))

          Normal  throws from the hand and leads the target by the blade's
                  flight time - the target has to be roughly in the open.
          Silent  authors the origin a few studs beside the target so the
                  server spawns the blade already touching them, at any
                  distance and through walls.

    THE LEAD (this is the part that used to be wrong)

        lead = spawn delay + distance / throw speed

    The blade does not exist the instant the packet is sent: the calibration
    measures how long the server takes to spawn it (the shipped files put it at
    ~211 ms, and the 200 ms everyone quotes is that delay, not a tolerance the
    server grants us). Leading by the flight time alone therefore threw ~3
    studs behind every moving target at walking pace. The spawn delay is
    measured, stored with the rest of the calibration history and folded in
    here, and the distance/lead pair is relaxed over three passes because
    moving the aim point changes the distance it is measured from.
]]
function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Knife requires the MM2 core module")
    Module.Runtime = runtime
    local findMurderer: any = core.findMurderer
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local getFilteredVelocity: any = core.getFilteredVelocity
    local trajectoryCalibration: any = core.trajectoryCalibration

    local DEFAULT_KNIFE_SPEED: number = 96
    local DEFAULT_SPAWN_DELAY: number = 0.2
    local BODY_PART_NAMES: {string} = {
        "UpperTorso",
        "LowerTorso",
        "Torso",
        "Head",
        "HumanoidRootPart",
    }

    local knifeSettings = {
        aura = false,
        throw = false,
        auraRange = 14,
        autoRange = false,
        throwMode = "Normal",
        fireDelay = 1,
        throwRange = 120,
        spawnOffset = 5,
        useMeasuredDelay = true,
        manualSpawnDelay = 200,
        leadBias = 0,
    }

    state.mm2KnifeRuntime = {
        lastAuraSwing = -math.huge,
    } :: {lastAuraSwing: number}

    local lastThrow: number = -math.huge

    local function knifeRuntime(): any
        if type(state.mm2KnifeRuntime) ~= "table" then
            state.mm2KnifeRuntime = {lastAuraSwing = -math.huge}
        end
        return state.mm2KnifeRuntime
    end

    -- Measured throw speed and spawn delay, both from the same calibration the
    -- rest of MM2 reads. Anything that is not measured falls back to the
    -- documented defaults instead of quietly disabling the lead.
    local function calibrationEstimates(): any?
        if not trajectoryCalibration
            or type(trajectoryCalibration.getEstimates) ~= "function" then
            return nil
        end
        local ok: boolean, estimates: any = pcall(function(): any
            return trajectoryCalibration:getEstimates()
        end)
        if not ok or type(estimates) ~= "table" then
            return nil
        end
        return estimates
    end

    local function getKnifeSpeed(): number
        local estimates: any? = calibrationEstimates()
        local speed: number? = estimates and estimates.knifeSpeed
        if type(speed) == "number" and speed > 1 then
            return speed :: number
        end
        return DEFAULT_KNIFE_SPEED
    end

    local function getSpawnDelaySeconds(): number
        if not knifeSettings.useMeasuredDelay then
            return math.max(0, knifeSettings.manualSpawnDelay / 1000)
        end
        local estimates: any? = calibrationEstimates()
        local delay: number? = estimates and estimates.knifeSpawnDelayMs
        if type(delay) == "number" and delay > 0 then
            return math.clamp((delay :: number) / 1000, 0, 0.75)
        end
        return DEFAULT_SPAWN_DELAY
    end

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

    local function findNearestTarget(
        origin: Vector3,
        maxDistance: number
    ): Player?
        local closest: Player? = nil
        local closestDistance: number = maxDistance
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then
                local targetRoot: BasePart? = player.Character
                    and player.Character:FindFirstChild("HumanoidRootPart")
                    :: BasePart?
                if targetRoot then
                    local distance: number =
                        (targetRoot.Position - origin).Magnitude
                    if distance <= closestDistance then
                        closest = player
                        closestDistance = distance
                    end
                end
            end
        end
        return closest
    end

    -- Vertical centre of the rig. A blade that lands centre-mass has the whole
    -- body above and below it as tolerance, which matters more for a thrown
    -- projectile than for a hitscan.
    local function bodyCentre(character: Model, root: BasePart): Vector3
        local top: number = -math.huge
        local bottom: number = math.huge
        local found: boolean = false
        for _, partName: string in ipairs(BODY_PART_NAMES) do
            local part: BasePart? =
                character:FindFirstChild(partName) :: BasePart?
            if part and part:IsA("BasePart") then
                found = true
                top = math.max(top, part.Position.Y + part.Size.Y * 0.5)
                bottom = math.min(bottom, part.Position.Y - part.Size.Y * 0.5)
            end
        end
        if not found or top <= bottom then
            return root.Position
        end
        return Vector3.new(root.Position.X, (top + bottom) * 0.5, root.Position.Z)
    end

    -- Solve lead = spawnDelay + distance / speed.
    --
    -- The distance is measured to the aim point, which is placed using the
    -- lead, so the two are relaxed together. Three passes converge to well
    -- under a tenth of a stud at any range the blade reaches.
    local function predictThrowAim(
        target: Player,
        originPos: Vector3
    ): Vector3
        local character: Model = target.Character :: Model
        local root: BasePart =
            character:FindFirstChild("HumanoidRootPart") :: BasePart
        local centre: Vector3 = bodyCentre(character, root)
        local velocity: Vector3 = getFilteredVelocity(target, root)
        local speed: number = getKnifeSpeed()
        local spawnDelay: number = getSpawnDelaySeconds()
        local bias: number = knifeSettings.leadBias

        local aim: Vector3 = centre
        for _ = 1, 3 do
            local distance: number = (aim - originPos).Magnitude
            local lead: number = math.max(
                0,
                spawnDelay + distance / speed + bias
            )
            aim = centre + velocity * lead
        end
        return aim
    end

    local function silentThrow(): boolean
        return knifeSettings.throwMode == "Silent"
    end

    -- -----------------------------------------------------------------------
    -- Aura
    -- -----------------------------------------------------------------------
    local function getEffectiveRange(): number
        if knifeSettings.autoRange then
            local estimates: any? = calibrationEstimates()
            local maxStab: number? = estimates and estimates.maxStabDistance
            if type(maxStab) == "number" and (maxStab :: number) >= 8 then
                return math.clamp(math.floor(maxStab :: number), 8, 28)
            end
        end
        return knifeSettings.auraRange or 14
    end

    local function getEquippedWeapon(name: string, _tag: string): Tool?
        return getPlayerWeapon(LocalPlayer, name, true)
    end

    local function canUseEquippedKnife(): (Tool?, BasePart?)
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        local root: BasePart? = character
            and character:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        local knife: Tool? = getEquippedWeapon("Knife", "Weapon_Knife")
        if not character
            or not humanoid
            or humanoid.Health <= 0
            or not root
            or not knife
            or knife:GetAttribute("Disabled") == true
            or getPlayerRole(LocalPlayer) ~= "Murderer" then
            return nil, nil
        end
        return knife, root
    end

    local function processKnifeAura(): ()
        local knife: Tool?, localRoot: BasePart? = canUseEquippedKnife()
        if not knife or not localRoot then
            return
        end

        local currentRange: number = getEffectiveRange()
        local target: Player? = findNearestTarget(
            (localRoot :: BasePart).Position,
            currentRange
        )
        local targetCharacter: Model? = target and target.Character
        local targetRoot: BasePart? = targetCharacter
            and targetCharacter:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        if not target
            or not targetCharacter
            or not targetRoot
            or ((targetRoot :: BasePart).Position
                - (localRoot :: BasePart).Position).Magnitude > currentRange
            or os.clock() - knifeRuntime().lastAuraSwing < 0.86 then
            return
        end

        local handle: BasePart? = knife:FindFirstChild("Handle") :: BasePart?
        if not handle or not handle:IsA("BasePart") then
            return
        end

        knifeRuntime().lastAuraSwing = os.clock()
        local events: Instance? = knife:FindFirstChild("Events")
        local handleTouched: Instance? = events
            and events:FindFirstChild("HandleTouched")
        knife:Activate()
        task.delay(0.025, function(): ()
            local currentKnife: Tool?, currentLocalRoot: BasePart? =
                canUseEquippedKnife()
            local currentCharacter: Model? = target.Character
            local currentRoot: BasePart? = currentCharacter
                and currentCharacter:FindFirstChild("HumanoidRootPart")
                :: BasePart?
            local currentHandle: BasePart? =
                (knife :: Tool):FindFirstChild("Handle") :: BasePart?
            if not knifeSettings.aura
                or currentKnife ~= knife
                or not currentLocalRoot
                or not currentCharacter
                or not currentRoot
                or not currentHandle
                or not currentHandle:IsA("BasePart")
                or ((currentRoot :: BasePart).Position
                    - (currentLocalRoot :: BasePart).Position).Magnitude
                    > currentRange then
                return
            end

            if handleTouched and handleTouched:IsA("RemoteEvent") then
                handleTouched:FireServer(currentRoot)
            elseif type(state.fireTouchInterest) == "function" then
                pcall(state.fireTouchInterest, currentHandle, currentRoot, 0)
                pcall(state.fireTouchInterest, currentHandle, currentRoot, 1)
            end
            pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
                kind = "stab",
                toolName = "Knife",
                originPos = (currentLocalRoot :: BasePart).Position,
                aimPos = (currentRoot :: BasePart).Position,
                target = target,
            })
        end)
    end

    -- -----------------------------------------------------------------------
    -- Throw
    -- -----------------------------------------------------------------------
    local function getReadyKnife(): Tool?
        if findMurderer() ~= LocalPlayer then
            return nil
        end
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil
        end
        -- The backpack is searched too: an unequipped knife has to be equipped
        -- before the next tick, exactly like the gun in Shoot.
        local knife: Tool? = getPlayerWeapon(LocalPlayer, "Knife")
        if not knife or knife:GetAttribute("Disabled") == true then
            return nil
        end
        if knife.Parent ~= character then
            local humanoid: Humanoid? =
                character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            if humanoid then
                humanoid:EquipTool(knife)
            end
            return nil
        end
        return knife
    end

    local function throwKnife(): ()
        if os.clock() - lastThrow < knifeSettings.fireDelay then
            return
        end
        local silent: boolean = silentThrow()
        local knife: Tool? = getReadyKnife()
        if not knife then
            return
        end
        local events: Instance? = (knife :: Tool):FindFirstChild("Events")
        local remote: Instance? = events and events:FindFirstChild("KnifeThrown")
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end
        local character: Model? = LocalPlayer.Character
        local throwerPart: BasePart? = character
            and (character:FindFirstChild("RightHand")
                or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
        if not throwerPart then
            return
        end

        -- Silent ignores range: the whole point is to reach a target anywhere.
        local target: Player? = findNearestTarget(
            (throwerPart :: BasePart).Position,
            silent and 100000 or knifeSettings.throwRange
        )
        if not target then
            return
        end
        local targetRoot: BasePart =
            (target :: Player).Character:FindFirstChild("HumanoidRootPart")
                :: BasePart

        local originPos: Vector3
        if silent then
            -- Spawn the blade just beside the target, on the thrower's side, so
            -- it travels a few studs into them and connects regardless of walls.
            local toThrower: Vector3 =
                (throwerPart :: BasePart).Position - targetRoot.Position
            if toThrower.Magnitude > 0.1 then
                toThrower = toThrower.Unit
            else
                toThrower = Vector3.new(0, 0, 1)
            end
            originPos =
                targetRoot.Position + toThrower * knifeSettings.spawnOffset
        else
            originPos = (throwerPart :: BasePart).Position
        end

        local aimPos: Vector3 =
            predictThrowAim(target :: Player, originPos)
        remote:FireServer(CFrame.new(originPos), CFrame.new(aimPos))
        lastThrow = os.clock()
        pcall(trajectoryCalibration.noteAuthoredShot, trajectoryCalibration, {
            kind = "knife",
            tool = knife,
            toolName = (knife :: Tool).Name,
            originPos = originPos,
            aimPos = aimPos,
            target = target,
            silent = silent,
        })
    end

    -- -----------------------------------------------------------------------
    -- Shared controller: one heartbeat drives whichever half is enabled.
    -- -----------------------------------------------------------------------
    local function refreshKnifeController(): ()
        disconnectFeatureConnection("MM2KnifeController")
        disconnectFeatureConnection("MM2KnifeAura")
        disconnectFeatureConnection("MM2KnifeThrow")
        if not knifeSettings.aura and not knifeSettings.throw then
            return
        end

        local auraElapsed: number = 0
        local throwElapsed: number = 0
        featureConnections.MM2KnifeController =
            TaskManager:Connect(function(deltaTime: number): ()
                if knifeSettings.aura then
                    auraElapsed += deltaTime
                    if auraElapsed >= 0.05 then
                        auraElapsed %= 0.05
                        processKnifeAura()
                    end
                end
                if knifeSettings.throw then
                    throwElapsed += deltaTime
                    if throwElapsed >= 1 / 30 then
                        throwElapsed = 0
                        throwKnife()
                    end
                end
            end)
    end

    local KnifeFeature = createUniversalFeature(
        "Knife",
        "The murderer's blade: aura stabs in range, throw leads by the measured "
            .. "spawn delay plus flight time, silent throws spawn beside the target",
        6,
        function(enabled: boolean): ()
            -- The card's own switch is the master: enabling the module arms
            -- whichever half is toggled on, and the two inner toggles stay
            -- independent so "aura only", "throw only" and "both" all work.
            if not enabled then
                knifeSettings.aura = false
                knifeSettings.throw = false
            end
            refreshKnifeController()
        end,
        {
            categoryName = "Blatant",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    addSectionOption(KnifeFeature, "Aura")
    addToggleOption(
        KnifeFeature,
        "Aura",
        false,
        function(value: boolean): ()
            knifeSettings.aura = value
            refreshKnifeController()
        end,
        "Stabs the nearest valid target in range through the game's own "
            .. "HandleTouched remote."
    )
    addNumberOption(
        KnifeFeature,
        "Range",
        knifeSettings.auraRange,
        7,
        30,
        function(value: number): ()
            knifeSettings.auraRange = value
        end,
        "Maximum stab distance.",
        1
    )
    addToggleOption(
        KnifeFeature,
        "Auto Range",
        knifeSettings.autoRange,
        function(value: boolean): ()
            knifeSettings.autoRange = value
        end,
        "Uses the longest stab the calibration has actually confirmed instead "
            .. "of the manual range."
    )

    addSectionOption(KnifeFeature, "Throw")
    addToggleOption(
        KnifeFeature,
        "Throw",
        false,
        function(value: boolean): ()
            knifeSettings.throw = value
            refreshKnifeController()
        end,
        "Auto-throws the knife at the nearest target."
    )
    addCycleOption(
        KnifeFeature,
        "Throw mode",
        {"Normal", "Silent"},
        1,
        function(value: string): ()
            knifeSettings.throwMode = value
        end,
        "Normal throws from the hand and respects range. Silent authors the "
            .. "blade beside the target, so it connects at any distance and "
            .. "through walls."
    )
    addNumberOption(
        KnifeFeature,
        "Fire delay",
        knifeSettings.fireDelay,
        0.2,
        3,
        function(value: number): ()
            knifeSettings.fireDelay = value
        end,
        "Seconds between automatic throws.",
        0.1
    )
    addNumberOption(
        KnifeFeature,
        "Throw range",
        knifeSettings.throwRange,
        10,
        400,
        function(value: number): ()
            knifeSettings.throwRange = value
        end,
        "Maximum target distance for normal throws. Silent ignores this.",
        5
    )
    addNumberOption(
        KnifeFeature,
        "Spawn offset",
        knifeSettings.spawnOffset,
        1,
        15,
        function(value: number): ()
            knifeSettings.spawnOffset = value
        end,
        "Silent only: how far beside the target the blade spawns.",
        1
    )
    addToggleOption(
        KnifeFeature,
        "Measured delay",
        knifeSettings.useMeasuredDelay,
        function(value: boolean): ()
            knifeSettings.useMeasuredDelay = value
        end,
        "Leads by the spawn delay the calibration measured (about 200 ms) "
            .. "instead of the manual value below."
    )
    addNumberOption(
        KnifeFeature,
        "Manual delay",
        knifeSettings.manualSpawnDelay,
        0,
        500,
        function(value: number): ()
            knifeSettings.manualSpawnDelay = math.clamp(value, 0, 500)
        end,
        "Spawn delay in milliseconds, used when Measured delay is off.",
        5
    )
    addNumberOption(
        KnifeFeature,
        "Lead bias",
        knifeSettings.leadBias,
        -0.15,
        0.15,
        function(value: number): ()
            knifeSettings.leadBias = math.clamp(value, -0.15, 0.15)
        end,
        "Extra lead in seconds. Positive throws further ahead of the target.",
        0.005
    )
    addActionOption(KnifeFeature, "Throw status", function(): ()
        -- Say where each number came from. A throw that misses is usually a
        -- lead built on defaults, and the only way to see that is to show how
        -- many samples back the measured value really is.
        local estimates: any? = calibrationEstimates()
        local delaySource: string = knifeSettings.useMeasuredDelay
            and "measured"
            or "manual"
        if knifeSettings.useMeasuredDelay and estimates then
            local samples: number = tonumber(estimates.confirmedDelays) or 0
            delaySource = string.format("measured, %d samples", samples)
        end
        local speedSource: string = ""
        if estimates then
            local throws: number = tonumber(estimates.confirmedThrows) or 0
            if throws > 0 then
                speedSource = string.format(" (%d throws)", throws)
            end
        end
        notify(string.format(
            "Knife · speed %.1f studs/s%s · spawn delay %.0f ms (%s)"
                .. " · aura %s · throw %s (%s)",
            getKnifeSpeed(),
            speedSource,
            getSpawnDelaySeconds() * 1000,
            delaySource,
            knifeSettings.aura and "on" or "off",
            knifeSettings.throw and "on" or "off",
            knifeSettings.throwMode
        ))
    end)

    activeCleanup = function(): ()
        knifeSettings.aura = false
        knifeSettings.throw = false
        refreshKnifeController()
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
