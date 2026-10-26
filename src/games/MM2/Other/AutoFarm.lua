local Module = {
    Name = "MM2 Auto Farm",
    Events = {},
    Initialized = false,
}

local activeCleanup: () -> () = function(): ()
end

function Module.init(_runtime: any): any
    assert(state.mm2Core, "MM2 Auto Farm requires the MM2 core")
    local core: any = state.mm2Core
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local findDroppedGun: any = core.findDroppedGun
    local isRoundLifecycleActive: any = core.isRoundLifecycleActive
    local findMM2Map: any = core.findMM2Map
    local getEstimatedLatency: any = core.getEstimatedLatency
    local getGunOriginCFrame: any = core.getGunOriginCFrame

    local settings = {
        mode = "Walk",
        speed = 16,
        stayUnderOnStart = true,
        safeZone = true,
        resetOnFull = true,
        flingMurder = false,
        flingSheriff = false,
        grabGunShoot = false,
        killAllOnFull = false,
    }

    local totalCoinsCollected: number = 0
    local farmElapsedSeconds: number = 0
    local lastFormattedSecond: number = -1
    local coinsCollectedStat: any = nil
    local farmTimeStat: any = nil
    local safeZonePlatform: Part? = nil
    local enableGeneration: number = 0
    local roundGeneration: number = 0
    local rememberedBagAmount: number = 0
    local rememberedBagLimit: number = 50
    local rememberedFullHandled: boolean = false
    local unsubscribeRoundPhase: (() -> ())? = nil

    local function formatFarmTime(totalSeconds: number): string
        local whole: number = math.max(0, math.floor(totalSeconds))
        local hours: number = math.floor(whole / 3600)
        local mins: number = math.floor((whole % 3600) / 60)
        local secs: number = whole % 60
        if hours > 0 then
            return string.format("%02d:%02d:%02d", hours, mins, secs)
        end
        return string.format("%02d:%02d", mins, secs)
    end

    local function refreshFarmOverlay(): ()
        if coinsCollectedStat and type(coinsCollectedStat.set) == "function" then
            coinsCollectedStat.set(tostring(totalCoinsCollected))
        end
        local wholeSec: number = math.max(0, math.floor(farmElapsedSeconds))
        if wholeSec ~= lastFormattedSecond then
            lastFormattedSecond = wholeSec
            if farmTimeStat and type(farmTimeStat.set) == "function" then
                farmTimeStat.set(formatFarmTime(wholeSec))
            end
        end
    end

    local function destroySafeZonePlatform(): ()
        if safeZonePlatform then
            pcall(function(): ()
                safeZonePlatform:Destroy()
            end)
            safeZonePlatform = nil
        end
    end

    local function ensureSafeZonePlatform(originPos: Vector3): Vector3
        local voidCenter: Vector3 = Vector3.new(
            originPos.X + 650,
            math.max(originPos.Y + 280, 380),
            originPos.Z + 650
        )
        if not safeZonePlatform or not safeZonePlatform.Parent then
            pcall(function(): ()
                local part: Part = Instance.new("Part")
                part.Name = "Wurst_AutoFarmSafeZone"
                part.Anchored = true
                part.CanCollide = true
                part.CanQuery = false
                part.CanTouch = false
                part.CastShadow = false
                part.Size = Vector3.new(64, 4, 64)
                part.Material = Enum.Material.SmoothPlastic
                part.Color = Color3.fromRGB(35, 42, 55)
                part.Transparency = 0.15
                part.CFrame = CFrame.new(voidCenter)
                part.Parent = workspace
                safeZonePlatform = part
            end)
        end
        if safeZonePlatform and safeZonePlatform.Parent then
            return safeZonePlatform.Position + Vector3.new(0, 5, 0)
        end
        return voidCenter + Vector3.new(0, 5, 0)
    end

    -- Two ways to reach a coin, chosen with Farm Mode:
    --
    -- Walk: the humanoid simply walks on the ground (Humanoid:Move).
    -- No prone tilt, no PlatformStand, no NoClip, no flying -- the
    -- body's normal touch against Coin_Server pays, which is why this
    -- is the reliable default. The slider becomes WalkSpeed.
    --
    -- Below (Hitbox): the character stays UPRIGHT and flies by physics
    -- velocity underneath the floor, but the root's hitbox is grown
    -- while engaged (4 x 8 x 4), so riding with the root centre
    -- BELOW_OFFSET under the coin still overlaps Coin_Server (1.2 x 2 x
    -- 2, one stud either side of its centre). The old build lay the
    -- body face-down to get a part into that volume; the tilted camera
    -- fight is what glitched, and the hitbox makes it unnecessary.
    local BELOW_OFFSET: number = 3.0
    local HITBOX_SIZE: Vector3 = Vector3.new(4, 8, 4)
    -- A coin that does not collect within this long is skipped for a
    -- while instead of trapping the farm on one unreachable pickup.
    local STUCK_SECONDS: number = 1.4
    local BLACKLIST_SECONDS: number = 6

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        if type(getCharacterParts) == "function" then
            local ok: boolean, character: any, humanoid: any, root: any =
                pcall(getCharacterParts)
            if ok and character then
                return character, humanoid, root
            end
        end
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil, nil, nil
        end
        local humanoid: Humanoid? =
            character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? =
            character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return character, humanoid, root
    end

    local function livingRoundParts(): (Model?, Humanoid?, BasePart?)
        local character: Model?, humanoid: Humanoid?, root: BasePart? = characterParts()
        if not character or not humanoid or not root or humanoid.Health <= 0
            or not root.Parent then
            return character, humanoid, nil
        end
        if type(isRoundLifecycleActive) ~= "function"
            or isRoundLifecycleActive() ~= true
            or type(findMM2Map) ~= "function" or not findMM2Map() then
            return character, humanoid, nil
        end
        return character, humanoid, root
    end

    local function rootOf(player: Player?): BasePart?
        local character: Model? = player and player.Character
        if not character then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart") :: BasePart?
    end

    local function resetRememberedRound(): ()
        rememberedBagAmount = 0
        rememberedBagLimit = 50
        rememberedFullHandled = false
        roundGeneration += 1
    end

    if type(core.onRoundPhase) == "function" then
        unsubscribeRoundPhase = core.onRoundPhase(function(phase: string): ()
            if phase == "lobby" or phase == "map" then
                resetRememberedRound()
            end
        end)
    end

    -- The pickup parts of the family in use, shared with Coin ESP.
    -- A throttled local scan keeps this working if Coin ESP is off.
    local function coinPickups(): {Instance}
        if type(state.mm2CoinPickups) == "function" then
            local ok: boolean, list: any = pcall(state.mm2CoinPickups)
            if ok and type(list) == "table" then
                return list
            end
        end
        -- Cheap first: the game's own tag list. The descendant walk
        -- below is only for builds where the tag list is unavailable.
        local okTagged: boolean, tagged: any = pcall(function(): any
            return game:GetService("CollectionService"):GetTagged("CoinVisual")
        end)
        if okTagged and type(tagged) == "table" and #tagged > 0 then
            return tagged
        end
        local out: {Instance} = {}
        local ok: boolean, descendants: any = pcall(function(): any
            return workspace:GetDescendants()
        end)
        if ok and type(descendants) == "table" then
            for _, object: Instance in ipairs(descendants) do
                if object.Name == "Coin_Server" and object:IsA("BasePart") then
                    local collected: any = nil
                    pcall(function(): ()
                        collected = (object :: any):GetAttribute("Collected")
                    end)
                    if collected ~= true then
                        table.insert(out, object)
                    end
                end
            end
        end
        return out
    end

    -- Live ping for the status line. The farm speed itself is the
    -- slider: the server kicks ("Invalid position", 267) when the
    -- root arrives faster than it accepts, and that limit varies by
    -- map and connection, so the user tunes it -- start low.
    local function pingMillis(): number
        if type(getEstimatedLatency) == "function" then
            local ok: boolean, value: any = pcall(getEstimatedLatency)
            if ok and type(value) == "number" and value == value then
                return math.round(math.clamp(value, 0.02, 0.6) * 1000)
            end
        end
        return 0
    end

    local function setStatus(text: string?): ()
        local card: any = state.mm2AutoFarmFeature
        if card then
            card:SetStatus(text)
        end
    end

    -- Kill All, adapted from YARHM 1.21 ("Kill EVERYONE as
    -- murderer"): equip the knife, pull every living player in front
    -- of us (anchored), then slash. The slash uses the repo's own
    -- knife path (Events.HandleTouched per victim, as KnifeAura
    -- does) and falls back to the game's Stab remote like YARHM.
    local function killAll(shouldContinue: (() -> boolean)?): ()
        local function allowed(): boolean
            return shouldContinue == nil or shouldContinue() == true
        end
        if not allowed() or type(getPlayerRole) ~= "function"
            or getPlayerRole(LocalPlayer) ~= "Murderer" then
            notify("Auto Farm: Kill All only works as the Murderer.")
            return
        end
        local character: Model?, humanoid: Humanoid?, myRoot: BasePart? =
            livingRoundParts()
        if not character or not humanoid or not myRoot or not allowed() then
            return
        end
        local knife: Tool? = nil
        if type(getPlayerWeapon) == "function" then
            knife = getPlayerWeapon(LocalPlayer, "Knife")
        end
        if not knife then
            notify("Auto Farm: no Knife found for Kill All.")
            return
        end
        if knife.Parent ~= character then
            pcall(function(): ()
                humanoid:EquipTool(knife :: Tool)
            end)
            -- Wait only until the equip lands (one frame normally),
            -- never a fixed sleep: 0.3 s is the ceiling, not the cost.
            local equipDeadline: number = os.clock() + 0.3
            while knife.Parent ~= character
                and os.clock() < equipDeadline and allowed() do
                task.wait()
            end
        end
        if knife.Parent ~= character then
            return
        end
        local victims: {BasePart} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if not allowed() then
                break
            end
            if player ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player)) then
                local victimRoot: BasePart? = rootOf(player)
                if victimRoot then
                    table.insert(victims, victimRoot)
                    pcall(function(): ()
                        victimRoot.Anchored = true
                        victimRoot.CFrame = myRoot.CFrame
                            + myRoot.CFrame.LookVector * 1
                    end)
                end
            end
        end
        local function releaseVictims(): ()
            for _, victimRoot: BasePart in ipairs(victims) do
                pcall(function(): ()
                    victimRoot.Anchored = false
                end)
            end
        end
        if #victims == 0 then
            return
        end
        if not allowed() then
            releaseVictims()
            return
        end
        task.wait(0.15)
        if not allowed() then
            releaseVictims()
            return
        end
        local stab: Instance? = knife:FindFirstChild("Stab")
        if stab and stab:IsA("RemoteEvent") then
            pcall(function(): ()
                (stab :: RemoteEvent):FireServer("Slash")
            end)
        end
        local events: Instance? = knife:FindFirstChild("Events")
        local handleTouched: Instance? = events
            and events:FindFirstChild("HandleTouched")
        pcall(function(): ()
            (knife :: Tool):Activate()
        end)
        for _, victimRoot: BasePart in ipairs(victims) do
            if not allowed() then
                releaseVictims()
                return
            end
            if handleTouched and handleTouched:IsA("RemoteEvent") then
                pcall(function(): ()
                    (handleTouched :: RemoteEvent):FireServer(victimRoot)
                end)
            end
            task.wait(0.05)
        end
        task.delay(0.5, releaseVictims)
        notify("Auto Farm: Kill All fired at " .. #victims .. " players.")
    end

    local function flingPlayer(
        target: Player?,
        shouldContinue: (() -> boolean)?
    ): ()
        if not target or type(state.mm2PerformFling) ~= "function" then
            return
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingRoundParts()
        if not character or not humanoid or not root then
            return
        end
        pcall(state.mm2PerformFling, target, {
            silent = true,
            duration = 1.4,
            blocking = true,
            restorePosition = false,
            shouldStop = function(): boolean
                return shouldContinue ~= nil and shouldContinue() ~= true
            end,
        })
    end

    -- Auto grab gun + auto shoot: equip the dropped sheriff gun and
    -- fire predicted shots at the murderer (same gun remote and
    -- prediction the Shoot module authors).
    local lastShotAt: number = 0
    local function shootMurderer(murderer: Player): boolean
        if os.clock() - lastShotAt < 0.22 then
            return false
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingRoundParts()
        if not character or not humanoid or not root then
            return false
        end
        local gun: Tool? = nil
        if type(getPlayerWeapon) == "function" then
            gun = getPlayerWeapon(LocalPlayer, "Gun")
        end
        if not gun then
            return false
        end
        if gun.Parent ~= character then
            pcall(function(): ()
                humanoid:EquipTool(gun :: Tool)
            end)
            local equipDeadline: number = os.clock() + 0.2
            while gun.Parent ~= character
                and os.clock() < equipDeadline do
                task.wait()
            end
        end
        if gun.Parent ~= character
            or gun:GetAttribute("Reloading") == true
            or gun:GetAttribute("IsReloading") == true then
            return false
        end
        local remote: Instance? = gun:FindFirstChild("Shoot")
        if not remote or not remote:IsA("RemoteEvent") then
            return false
        end
        local origin: CFrame? = nil
        if type(getGunOriginCFrame) == "function" then
            local ok: boolean, value: any =
                pcall(getGunOriginCFrame, character, gun)
            if ok then
                origin = value
            end
        end
        if not origin then
            return false
        end
        local endpoint: Vector3? = nil
        local prediction: any = state.mm2Prediction
        if prediction and type(prediction.gunAim) == "function" then
            local ok: boolean, predicted: any = pcall(
                prediction.gunAim, murderer, (origin :: CFrame).Position)
            if ok and predicted then
                endpoint = predicted
            end
        end
        if not endpoint then
            local targetRoot: BasePart? = rootOf(murderer)
            if not targetRoot then
                return false
            end
            endpoint = targetRoot.Position + Vector3.new(0, 0.6, 0)
        end
        lastShotAt = os.clock()
        pcall(function(): ()
            (remote :: RemoteEvent):FireServer(
                CFrame.lookAt((origin :: CFrame).Position, endpoint :: Vector3),
                CFrame.new(endpoint :: Vector3)
            )
        end)
        return true
    end

    local function toggleAutoFarm(enabled: boolean): ()
        enableGeneration += 1
        local thisEnable: number = enableGeneration
        disconnectFeatureConnection("MM2AutoFarmTick")
        disconnectFeatureConnection("MM2AutoFarmStepped")
        disconnectFeatureConnection("MM2AutoFarmPreSim")
        disconnectFeatureConnection("MM2AutoFarmCoinCollected")
        -- Invokes the restore closure the previous enable registered:
        -- collisions, PlatformStand, AutoRotate and the root all go
        -- back, and the character returns to where the farm grabbed
        -- it (never left lying under the floor, stuck in geometry).
        disconnectFeatureConnection("MM2AutoFarmRestore")

        if not enabled then
            setStatus(nil)
            return
        end

        local bagAmount: number = rememberedBagAmount
        local bagLimit: number = rememberedBagLimit
        local busy: boolean = false
        local fullHandled: boolean = rememberedFullHandled
        local roundFullReached: boolean = rememberedFullHandled
        local teleportedHomeThisRound: boolean = false
        local wasInActiveRound: boolean = false
        local scanCache: {Instance} = {}
        local scanAt: number = 0
        local stuckPart: Instance? = nil
        local stuckSince: number = 0
        local lastTouchPulse: number = 0
        local blacklist: {[Instance]: number} = {}

        -- Engagement state. The farm touches the character ONLY while
        -- engaged inside an active round on a map. In the lobby or
        -- between rounds, the character is left completely alone.
        local engaged: boolean = false
        local engagedCharacter: Model? = nil
        local homeCFrame: CFrame? = nil
        local homeCharacter: Model? = nil
        local roundSurfaceY: number? = nil
        local hideAnchorPosition: Vector3? = nil
        local hiddenUnderMap: boolean = false
        local firstCoinSeenThisRound: boolean = false
        local currentTargetCoin: Instance? = nil
        local activeWalkDir: Vector3? = nil
        local activeWalkTarget: Vector3? = nil
        local belowDestination: Vector3? = nil
        local belowHold: boolean = false
        local belowDeltaTime: number = 1 / 60
        local farmAttachment: Attachment? = nil
        local farmLinearVelocity: LinearVelocity? = nil
        local farmAlignOrientation: AlignOrientation? = nil
        local savedCollide: {[Instance]: boolean} = {}
        local engagedMode: string? = nil
        local savedWalkSpeed: number? = nil
        local savedRootSize: Vector3? = nil
        local walkLastDistance: number = math.huge
        local walkStuckSince: number = 0

        local function yawOf(frame: CFrame): number
            local look: Vector3 = frame.LookVector
            return math.atan2(-look.X, -look.Z)
        end

        local function destroyFarmConstraints(): ()
            for _, constraint: any in ipairs({farmLinearVelocity, farmAlignOrientation}) do
                if constraint then
                    pcall(function(): ()
                        constraint:Destroy()
                    end)
                end
            end
            farmLinearVelocity = nil
            farmAlignOrientation = nil
            if farmAttachment then
                pcall(function(): ()
                    farmAttachment:Destroy()
                end)
                farmAttachment = nil
            end
        end

        -- Roblox constraint model: LinearVelocity owns translation and
        -- AlignOrientation owns upright yaw. They are the only per-frame
        -- Below writers; no CFrame/Velocity racing with the solver.
        local function ensureFarmConstraints(
            root: BasePart,
            velocity: Vector3,
            yaw: number
        ): ()
            pcall(function(): ()
                if not farmAttachment or farmAttachment.Parent ~= root then
                    destroyFarmConstraints()
                    local attachment: Attachment = Instance.new("Attachment")
                    attachment.Name = "WurstAutoFarmAttachment"
                    attachment.Parent = root
                    farmAttachment = attachment
                end
                if not farmLinearVelocity or farmLinearVelocity.Parent ~= root then
                    local lv: LinearVelocity = Instance.new("LinearVelocity")
                    lv.Name = "WurstAutoFarmLV"
                    lv.Attachment0 = farmAttachment
                    lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
                    lv.RelativeTo = Enum.ActuatorRelativeTo.World
                    lv.MaxForce = math.huge
                    lv.Parent = root
                    farmLinearVelocity = lv
                end
                if not farmAlignOrientation or farmAlignOrientation.Parent ~= root then
                    local ao: AlignOrientation = Instance.new("AlignOrientation")
                    ao.Name = "WurstAutoFarmAO"
                    ao.Attachment0 = farmAttachment
                    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
                    ao.MaxTorque = math.huge
                    ao.Responsiveness = 50
                    ao.Parent = root
                    farmAlignOrientation = ao
                end
                farmLinearVelocity.VectorVelocity = velocity
                farmAlignOrientation.CFrame = CFrame.Angles(0, yaw, 0)
            end)
        end

        local function findLobbyReferencePart(): BasePart?
            local okChildren: boolean, children: any = pcall(function(): any
                return workspace:GetChildren()
            end)
            if not okChildren or type(children) ~= "table" then
                return nil
            end
            for _, child: Instance in ipairs(children) do
                local lowerName: string = string.lower(tostring(child.Name))
                local isLobby: boolean = string.find(lowerName, "lobby", 1, true) ~= nil
                    or child:FindFirstChild("VotePads", true) ~= nil
                    or child:FindFirstChild("VotePad1", true) ~= nil
                    or child:FindFirstChild("VoteIcons", true) ~= nil
                if isLobby then
                    local votePads: Instance? = child:FindFirstChild("VotePads", true)
                    if votePads then
                        local padPart: BasePart? = votePads:FindFirstChildWhichIsA("BasePart", true)
                        if padPart then
                            return padPart
                        end
                    end
                    local spawns: Instance? = child:FindFirstChild("Spawns", true)
                    if spawns then
                        local spawnPart: BasePart? = spawns:FindFirstChildWhichIsA("BasePart", true)
                        if spawnPart then
                            return spawnPart
                        end
                    end
                    local anyPart: BasePart? = child:FindFirstChildWhichIsA("BasePart", true)
                    if anyPart then
                        return anyPart
                    end
                end
            end
            return nil
        end

        -- Resolves a safe indoor floor position without ever raycasting from
        -- above the building roof (which would put the player on top of the map).
        local function resolveSafeAboveGroundPosition(
            candidatePos: Vector3,
            character: Model?
        ): Vector3
            if homeCFrame then
                local dx: number = candidatePos.X - homeCFrame.Position.X
                local dz: number = candidatePos.Z - homeCFrame.Position.Z
                if (dx * dx + dz * dz) <= 64 then
                    return Vector3.new(candidatePos.X, homeCFrame.Position.Y, candidatePos.Z)
                end
            end
            local resolvedY: number = candidatePos.Y
            local wasUnderground: boolean = hiddenUnderMap or engagedMode == "Below"
            local probeTopY: number = if wasUnderground and roundSurfaceY
                then roundSurfaceY + 2.5
                elseif wasUnderground
                then candidatePos.Y + (BELOW_OFFSET + 6.0)
                else candidatePos.Y + 2.5
            local foundFloor: boolean = false
            pcall(function(): ()
                if type(workspace.Raycast) == "function" and type(RaycastParams) == "table" then
                    local params: RaycastParams = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    local excluded: {Instance} = {}
                    if character then
                        table.insert(excluded, character)
                    end
                    if safeZonePlatform then
                        table.insert(excluded, safeZonePlatform)
                    end
                    params.FilterDescendantsInstances = excluded
                    params.RespectCanCollide = true
                    params.IgnoreWater = true
                    local rayOrigin: Vector3 = Vector3.new(
                        candidatePos.X,
                        probeTopY,
                        candidatePos.Z
                    )
                    local rayDepth: number = math.max(12, (probeTopY - candidatePos.Y) + 8)
                    local hit: any = workspace:Raycast(
                        rayOrigin,
                        Vector3.new(0, -rayDepth, 0),
                        params
                    )
                    if hit and typeof(hit.Position) == "Vector3" then
                        resolvedY = hit.Position.Y + 3.2
                        foundFloor = true
                    end
                end
            end)
            if not foundFloor and wasUnderground then
                if roundSurfaceY then
                    resolvedY = roundSurfaceY
                elseif homeCFrame then
                    resolvedY = homeCFrame.Position.Y
                else
                    resolvedY = candidatePos.Y + BELOW_OFFSET + 5.5
                end
            end
            return Vector3.new(candidatePos.X, resolvedY, candidatePos.Z)
        end

        local function getHiddenUnderMapPosition(root: BasePart): Vector3
            if hideAnchorPosition then
                return hideAnchorPosition
            end
            if homeCFrame then
                return homeCFrame.Position - Vector3.new(0, BELOW_OFFSET + 5.5, 0)
            end
            return root.Position - Vector3.new(0, BELOW_OFFSET + 5.5, 0)
        end

        local function forceNoClipCharacter(character: Model): ()
            for _, object: Instance in ipairs(character:GetDescendants()) do
                if object:IsA("BasePart") then
                    if savedCollide[object] == nil then
                        savedCollide[object] = (object :: BasePart).CanCollide
                    end
                    pcall(function(): ()
                        (object :: BasePart).CanCollide = false
                    end)
                end
            end
        end

        local function holdHiddenUnderMap(
            character: Model,
            humanoid: Humanoid,
            root: BasePart
        ): ()
            local initialPlacement: boolean =
                not hiddenUnderMap and not firstCoinSeenThisRound
            if not hiddenUnderMap and firstCoinSeenThisRound then
                -- Once farming has started, losing a target means holding
                -- the current pose, never jumping back to a coin anchor.
                hideAnchorPosition = root.Position
            end
            hiddenUnderMap = true
            belowHold = true
            belowDestination = nil
            activeWalkDir = nil
            activeWalkTarget = nil
            pcall(function(): ()
                humanoid.PlatformStand = true
                humanoid.AutoRotate = false
                humanoid:Move(Vector3.zero, false)
                if initialPlacement then
                    local hidePos: Vector3 = getHiddenUnderMapPosition(root)
                    local holdCF: CFrame = CFrame.new(hidePos)
                        * CFrame.Angles(0, yawOf(root.CFrame), 0)
                    root.CFrame = holdCF
                    character:PivotTo(holdCF)
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end
            end)
        end

        -- Detects when the player's character is inside the loaded MM2 map,
        -- including the pre-round countdown seconds right after teleporting
        -- from the lobby before roles or coins have spawned.
        local function isCharacterInActiveRound(root: BasePart): boolean
            if type(findMM2Map) ~= "function" then
                return false
            end
            local map: Instance? = findMM2Map()
            if not map then
                return false
            end
            -- Proximity is only a secondary check. A loaded map or a
            -- nearby spawn must never make lobby/ended-round actions legal.
            if type(isRoundLifecycleActive) ~= "function"
                or isRoundLifecycleActive() ~= true then
                return false
            end
            if type(getPlayerRole) == "function" then
                local role: any = getPlayerRole(LocalPlayer)
                if role == "Dead" then
                    return false
                end
                if (role == "None" or role == nil)
                    and type(isRoundLifecycleActive) == "function"
                    and isRoundLifecycleActive() == false then
                    local lobbyPartCheck: BasePart? = findLobbyReferencePart()
                    if lobbyPartCheck then
                        local okLD: boolean, ld: any = pcall(function(): any
                            return (root.Position - lobbyPartCheck.Position).Magnitude
                        end)
                        if okLD and type(ld) == "number" and ld <= 350 then
                            return false
                        end
                    end
                end
            end
            local lobbyPart: BasePart? = findLobbyReferencePart()
            if lobbyPart then
                local okLobbyDist: boolean, lobbyDist: any = pcall(function(): any
                    return (root.Position - lobbyPart.Position).Magnitude
                end)
                if okLobbyDist and type(lobbyDist) == "number" and lobbyDist <= 350 then
                    return false
                end
            end
            if safeZonePlatform and safeZonePlatform.Parent then
                local okZoneDist: boolean, zoneDist: any = pcall(function(): any
                    return (root.Position - safeZonePlatform.Position).Magnitude
                end)
                if okZoneDist and type(zoneDist) == "number" and zoneDist <= 120 then
                    return true
                end
            end
            local refPart: BasePart? = nil
            local spawns: Instance? = (map :: Instance):FindFirstChild("Spawns")
            if spawns then
                refPart = spawns:FindFirstChildWhichIsA("BasePart", true)
            end
            if not refPart then
                local coinContainer: Instance? = (map :: Instance):FindFirstChild("CoinContainer")
                if coinContainer then
                    refPart = coinContainer:FindFirstChildWhichIsA("BasePart", true)
                end
            end
            if not refPart then
                refPart = (map :: Instance):FindFirstChildWhichIsA("BasePart", true)
            end
            if refPart then
                local okDist: boolean, dist: any = pcall(function(): any
                    return (root.Position - refPart.Position).Magnitude
                end)
                if okDist and type(dist) == "number" and dist > 1500 then
                    return false
                end
                return true
            end
            if type(isRoundLifecycleActive) == "function"
                and isRoundLifecycleActive() ~= true then
                return false
            end
            return true
        end

        local function restoreCharacter(
            returnHome: boolean,
            repositionActive: boolean?
        ): ()
            local wasMovedByFarm: boolean = engaged or hiddenUnderMap
            activeWalkDir = nil
            activeWalkTarget = nil
            belowDestination = nil
            belowHold = false
            destroyFarmConstraints()
            local character: Model?, humanoid: Humanoid?, root: BasePart? =
                characterParts()
            local canReposition: boolean = root ~= nil and humanoid ~= nil
                and humanoid.Health > 0 and isCharacterInActiveRound(root :: BasePart)
            if root and wasMovedByFarm then
                pcall(function(): ()
                    if savedRootSize then
                        root.Size = savedRootSize
                    end
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    if canReposition and not teleportedHomeThisRound
                        and (returnHome or repositionActive == true) then
                        local targetCF: CFrame? = nil
                        local full: boolean = bagAmount >= math.max(50, bagLimit)
                        if returnHome and homeCFrame
                            and (full or not enabled)
                            and (not homeCharacter or homeCharacter == character) then
                            local destPosition: Vector3 = resolveSafeAboveGroundPosition(
                                homeCFrame.Position, character
                            )
                            if enabled and settings.safeZone and full then
                                destPosition = ensureSafeZonePlatform(homeCFrame.Position)
                            end
                            targetCF = CFrame.new(destPosition)
                                * CFrame.Angles(0, yawOf(homeCFrame), 0)
                            if full then
                                teleportedHomeThisRound = true
                                homeCFrame = nil
                            end
                        elseif not returnHome then
                            local safePos: Vector3
                            if (hiddenUnderMap or engagedMode == "Below") and homeCFrame then
                                safePos = homeCFrame.Position
                            else
                                safePos = resolveSafeAboveGroundPosition(
                                    root.Position, character
                                )
                            end
                            targetCF = CFrame.new(safePos)
                                * CFrame.Angles(0, yawOf(root.CFrame), 0)
                        end
                        if targetCF then
                            if character then
                                character:PivotTo(targetCF)
                            end
                            root.CFrame = targetCF
                        end
                    end
                end)
            end
            for part: Instance, was: boolean in pairs(savedCollide) do
                pcall(function(): ()
                    (part :: BasePart).CanCollide = was
                end)
            end
            table.clear(savedCollide)
            if humanoid and wasMovedByFarm then
                pcall(function(): ()
                    humanoid.PlatformStand = false
                    humanoid.AutoRotate = true
                    if humanoid.Sit then
                        humanoid.Sit = false
                    end
                    if savedWalkSpeed then
                        humanoid.WalkSpeed = savedWalkSpeed
                    end
                    if humanoid.Health > 0 then
                        humanoid:Move(Vector3.zero, false)
                        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                        humanoid:ChangeState(Enum.HumanoidStateType.Running)
                    end
                end)
            end
            savedWalkSpeed = nil
            hiddenUnderMap = false
            savedRootSize = nil
            engaged = false
            engagedMode = nil
            engagedCharacter = nil
        end

        local function engage(
            character: Model,
            humanoid: Humanoid,
            root: BasePart
        ): ()
            if homeCharacter ~= character or not homeCFrame then
                local baseY: number = roundSurfaceY
                    or (if hiddenUnderMap
                        then root.Position.Y + (BELOW_OFFSET + 5.5)
                        else root.Position.Y)
                local basePos: Vector3 = Vector3.new(root.Position.X, baseY, root.Position.Z)
                homeCFrame = CFrame.new(basePos) * CFrame.Angles(0, yawOf(root.CFrame), 0)
                homeCharacter = character
            end
            if engaged and engagedMode ~= nil and engagedMode ~= settings.mode then
                restoreCharacter(false, true)
            end
            engagedMode = settings.mode
            if engagedCharacter ~= nil and engagedCharacter ~= character then
                restoreCharacter(false, true)
                engagedMode = settings.mode
                if homeCharacter ~= character or not homeCFrame then
                    homeCFrame = root.CFrame
                    homeCharacter = character
                    roundSurfaceY = root.Position.Y
                end
            end
            engagedCharacter = character
            if not engaged then
                engaged = true
                walkLastDistance = math.huge
                walkStuckSince = os.clock()
                if settings.mode ~= "Walk" then
                    hiddenUnderMap = false
                    belowHold = true
                    belowDestination = nil
                    activeWalkDir = nil
                    activeWalkTarget = nil
                    forceNoClipCharacter(character)
                    pcall(function(): ()
                        local startPos: Vector3 = root.Position
                        local surfaceY: number = roundSurfaceY
                            or (homeCFrame and homeCFrame.Position.Y)
                            or startPos.Y
                        if startPos.Y >= surfaceY - 2.0 then
                            startPos = Vector3.new(
                                startPos.X,
                                surfaceY - (BELOW_OFFSET + 2.5),
                                startPos.Z
                            )
                        end
                        local curYaw: number = yawOf(root.CFrame)
                        local startCF: CFrame = CFrame.new(startPos) * CFrame.Angles(0, curYaw, 0)
                        root.CFrame = startCF
                        character:PivotTo(startCF)
                        humanoid.PlatformStand = true
                        humanoid.AutoRotate = false
                        if savedRootSize == nil then
                            savedRootSize = root.Size
                        end
                        root.Size = HITBOX_SIZE
                    end)
                else
                    destroyFarmConstraints()
                end
            end
            if settings.mode == "Walk" then
                belowDestination = nil
                belowHold = false
                destroyFarmConstraints()
                if savedWalkSpeed == nil then
                    savedWalkSpeed = humanoid.WalkSpeed
                end
                pcall(function(): ()
                    humanoid.PlatformStand = false
                    humanoid.AutoRotate = true
                    humanoid.WalkSpeed = math.clamp(settings.speed, 5, 60)
                end)
                return
            end
            forceNoClipCharacter(character)
        end

        -- Called only by PreSimulation for Below. LinearVelocity removes
        -- gravity drift without teleporting; near the target its speed is
        -- reduced from the remaining distance instead of snapping CFrame.
        local function moveTowards(
            root: BasePart,
            destination: Vector3,
            deltaTime: number
        ): number
            local delta: Vector3 = destination - root.Position
            local distance: number = delta.Magnitude
            local curYaw: number = yawOf(root.CFrame)
            if distance < 0.05 then
                ensureFarmConstraints(root, Vector3.zero, curYaw)
                return 0
            end
            local speed: number = math.clamp(settings.speed, 5, 60)
            local dt: number = math.clamp(tonumber(deltaTime) or (1 / 60), 1 / 240, 0.1)
            local targetVel: Vector3 = if distance <= speed * dt
                then delta / dt
                else delta.Unit * speed
            ensureFarmConstraints(root, targetVel, curYaw)
            return distance
        end

        -- Walk mode movement: drives both Humanoid locomotion (re-applied on
        -- RunService.Stepped so PlayerModule.ControlModule never zeroes it on
        -- RenderStepped) and ground planar movement at the Farm Speed slider.
        local function walkTowards(
            humanoid: Humanoid,
            root: BasePart,
            destination: Vector3,
            deltaTime: number?
        ): number
            local delta: Vector3 = destination - root.Position
            local flat: Vector3 = Vector3.new(delta.X, 0, delta.Z)
            local distance: number = flat.Magnitude
            local now: number = os.clock()
            if distance < 1.2 then
                activeWalkDir = nil
                activeWalkTarget = nil
                pcall(function(): ()
                    humanoid:Move(Vector3.zero, false)
                end)
                return distance
            end
            local unitDir: Vector3 = flat.Unit
            activeWalkDir = unitDir
            activeWalkTarget = destination
            if distance < walkLastDistance - 0.25 then
                walkLastDistance = distance
                walkStuckSince = now
            elseif now - walkStuckSince > 0.65 then
                walkStuckSince = now
                pcall(function(): ()
                    humanoid.Jump = true
                end)
            end
            local speed: number = math.clamp(settings.speed, 5, 60)
            pcall(function(): ()
                humanoid.WalkSpeed = speed
                -- Humanoid locomotion is the sole Walk writer. The solver
                -- owns gravity, grounding and collision response.
                humanoid:Move(unitDir, false)
            end)
            return distance
        end

        -- The Coin_Server part that pays for a pickup entry (ESP hands
        -- out the visual, the server part is its parent).
        local function serverPartOf(part: Instance): Instance?
            if part.Name == "Coin_Server" then
                return part
            end
            local parent: Instance? = part.Parent
            if parent and parent.Name == "Coin_Server" then
                return parent
            end
            return part
        end

        local function visualPartOf(part: Instance): Instance?
            if part.Name == "CoinVisual" then
                return part
            end
            if part.Name == "Coin_Server" then
                local child: Instance? = part:FindFirstChild("CoinVisual")
                if child then
                    return child
                end
            end
            return part
        end

        -- Checks both Coin_Server and CoinVisual so a collected coin (whose
        -- "Collected" attribute is set on CoinVisual by MM2's CoinVisualizer)
        -- stops being a target on the very same frame it is picked up.
        local function stillCollectable(part: Instance): boolean
            if not part or not part.Parent then
                return false
            end
            local server: Instance? = serverPartOf(part)
            if not server or not server.Parent then
                return false
            end
            local visual: Instance? = visualPartOf(part)
            local isCollected: boolean = false
            pcall(function(): ()
                if (part :: any):GetAttribute("Collected") == true
                    or (part :: any):GetAttribute("Delete") == true then
                    isCollected = true
                    return
                end
                if (server :: any):GetAttribute("Collected") == true
                    or (server :: any):GetAttribute("Delete") == true then
                    isCollected = true
                    return
                end
                if visual and (
                    (visual :: any):GetAttribute("Collected") == true
                    or (visual :: any):GetAttribute("Delete") == true
                ) then
                    isCollected = true
                    return
                end
                if visual and visual:IsA("BasePart") and (visual :: BasePart).Transparency >= 0.95 then
                    isCollected = true
                    return
                end
                if server:IsA("BasePart") then
                    local sPart: BasePart = server :: BasePart
                    if sPart.CanTouch == false then
                        isCollected = true
                        return
                    end
                    local destroyH: number = workspace.FallenPartsDestroyHeight
                    if destroyH ~= destroyH then
                        destroyH = -500
                    end
                    if sPart.Position.Y <= destroyH + 60 then
                        isCollected = true
                        return
                    end
                end
            end)
            return not isCollected
        end

        -- Always read the anchored Coin_Server position rather than CoinVisual
        -- (CoinVisual can animate or drop when collected).
        local function coinPositionOf(part: Instance): Vector3?
            local server: Instance? = serverPartOf(part)
            local targetInst: Instance = server or part
            local pos: Vector3? = nil
            pcall(function(): ()
                if targetInst:IsA("BasePart") then
                    pos = (targetInst :: BasePart).Position
                elseif targetInst:IsA("Model") then
                    pos = (targetInst :: Model):GetPivot().Position
                end
            end)
            return pos
        end

    -- The gun grab is an in-round action for non-Murderer roles: as
    -- Murderer it must never run, and in the lobby there is no round,
    -- no murderer and no dropped gun to shoot with. Note that once an
    -- Innocent picks up the dropped gun, MM2 promotes their role to
    -- "Hero" / "Sheriff", so those roles must remain allowed while
    -- equipping and continuously shooting the Murderer.
    local function canGrabGun(): boolean
        if type(getPlayerRole) ~= "function" then
            return false
        end
        local role: any = getPlayerRole(LocalPlayer)
        if role ~= "Innocent" and role ~= "Sheriff" and role ~= "Hero" then
            return false
        end
        if type(isRoundLifecycleActive) ~= "function"
            or isRoundLifecycleActive() ~= true then
            return false
        end
        if type(findMM2Map) ~= "function" or not findMM2Map() then
            return false
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? =
            livingRoundParts()
        return character ~= nil and humanoid ~= nil and root ~= nil
            and isCharacterInActiveRound(root :: BasePart)
    end

    -- Immediate pickup attempt: pulse the touch between our root and the
    -- dropped gun's part instead of travelling or sleeping. True only
    -- when the gun has already arrived; the farm can retry on a later frame.
    local function touchDroppedGun(
        drop: Instance,
        root: BasePart
    ): boolean
        if type(state.fireTouchInterest) ~= "function" then
            return false
        end
        local touchPart: Instance? = nil
        if drop:IsA("BasePart") then
            touchPart = drop
        elseif drop:IsA("Model") then
            touchPart = drop:FindFirstChild("Handle", true)
                or drop:FindFirstChildWhichIsA("BasePart", true)
        end
        if not touchPart then
            return false
        end
        pcall(state.fireTouchInterest, root, touchPart, 0)
        pcall(state.fireTouchInterest, root, touchPart, 1)
        return type(getPlayerWeapon) == "function"
            and getPlayerWeapon(LocalPlayer, "Gun") ~= nil
    end

    -- Full-bag Auto Grab gun and Shoot: fetch the dropped sheriff gun
    -- if we do not already carry it, equip it, and continuously shoot
    -- the murderer until the murderer is eliminated or the round ends.
    local function grabGunAndShoot(shouldContinue: (() -> boolean)?): ()
        local function allowed(): boolean
            return (shouldContinue == nil or shouldContinue() == true)
                and canGrabGun()
        end
        if not allowed() then
            return
        end
        local shootLoopDeadline: number = os.clock() + 30
        while os.clock() < shootLoopDeadline and enabled and settings.grabGunShoot do
            if not allowed() then
                return
            end
            local murderer: Player? = nil
            if type(findMurderer) == "function" then
                murderer = findMurderer()
            end
            if not murderer
                or (type(isPlayerAlive) == "function"
                    and not isPlayerAlive(murderer)) then
                return
            end
            local character: Model?, humanoid: Humanoid?,
                startRoot: BasePart? = characterParts()
            if not character or not humanoid or not startRoot
                or humanoid.Health <= 0 then
                return
            end

            local gun: Tool? = nil
            if type(getPlayerWeapon) == "function" then
                gun = getPlayerWeapon(LocalPlayer, "Gun")
            end
            if not gun and type(findDroppedGun) == "function" then
                local firstDrop: Instance? = findDroppedGun()
                if firstDrop and touchDroppedGun(firstDrop, startRoot) then
                    gun = getPlayerWeapon(LocalPlayer, "Gun")
                end
                local pickupDeadline: number = os.clock() + 5
                while os.clock() < pickupDeadline and not gun do
                    if not allowed() or not settings.grabGunShoot then
                        return
                    end
                    local curChar: Model?, curHum: Humanoid?,
                        root: BasePart? = characterParts()
                    local drop: Instance? = findDroppedGun()
                    if not curChar or not curHum or not root or not drop then
                        break
                    end
                    if touchDroppedGun(drop, root) then
                        gun = getPlayerWeapon(LocalPlayer, "Gun")
                        if gun then
                            break
                        end
                    end
                    if not allowed() then
                        break
                    end
                    local dropPosition: Vector3? = nil
                    pcall(function(): ()
                        if drop:IsA("BasePart") then
                            dropPosition = (drop :: BasePart).Position
                        elseif drop:IsA("Model") then
                            dropPosition = (drop :: Model):GetPivot().Position
                        end
                    end)
                    if not dropPosition then
                        break
                    end
                    engage(curChar, curHum, root)
                    local remaining: number
                    if settings.mode == "Walk" then
                        remaining = walkTowards(
                            curHum, root, dropPosition :: Vector3)
                    else
                        local destination: Vector3 =
                            (dropPosition :: Vector3) + Vector3.new(0, 1, 0)
                        belowHold = false
                        belowDestination = destination
                        belowDeltaTime = 0.05
                        remaining = (destination - root.Position).Magnitude
                    end
                    if remaining < 2.5 then
                        task.wait(0.05)
                        gun = getPlayerWeapon(LocalPlayer, "Gun")
                        if gun then
                            break
                        end
                    end
                    task.wait()
                end
            end

            if not gun then
                -- Wait briefly for the gun to drop or become available while the round is active
                task.wait(0.15)
                continue
            end

            character, humanoid = characterParts()
            if not character or not humanoid or humanoid.Health <= 0 then
                return
            end
            if gun.Parent ~= character then
                pcall(function(): ()
                    humanoid:EquipTool(gun :: Tool)
                end)
                local equipWait: number = os.clock() + 0.15
                while gun.Parent ~= character and os.clock() < equipWait
                    and allowed() do
                    task.wait()
                end
            end
            if gun.Parent == character and allowed() then
                local firedSilent: boolean = false
                if type(state.mm2FireSilentShot) == "function" then
                    local okShot: boolean, shotRes: any =
                        pcall(state.mm2FireSilentShot, murderer)
                    firedSilent = okShot and shotRes == true
                end
                if not firedSilent then
                    shootMurderer(murderer)
                end
            end
            task.wait(0.12)
        end
    end

        -- One terminal sequence per fill. Tokens invalidate every later
        -- phase on OFF, respawn/round transition or a dead character.
        local function runFullSequence(thisEnable: number, thisRound: number): ()
            busy = true
            local function current(): boolean
                return enabled and thisEnable == enableGeneration
                    and thisRound == roundGeneration
                    and type(isRoundLifecycleActive) == "function"
                    and isRoundLifecycleActive() == true
            end
            local function alive(): boolean
                if not current() then
                    return false
                end
                local character: Model?, humanoid: Humanoid?, root: BasePart? =
                    livingRoundParts()
                return character ~= nil and humanoid ~= nil and root ~= nil
                    and isCharacterInActiveRound(root :: BasePart)
            end
            local ok: boolean, err: any = pcall(function(): ()
                if not alive() then
                    return
                end
                if settings.killAllOnFull then
                    killAll(alive)
                    if not alive() then
                        return
                    end
                    task.wait()
                end
                if not alive() then
                    return
                end
                restoreCharacter(true)
                if settings.grabGunShoot then
                    grabGunAndShoot(alive)
                    if not current() then
                        return
                    end
                    task.wait(0.15)
                end
                if settings.resetOnFull then
                    if not alive() then
                        return
                    end
                    local oldCharacter: Model? = LocalPlayer.Character
                    local _, humanoid: Humanoid? = characterParts()
                    if humanoid then
                        pcall(function(): ()
                            humanoid.Health = 0
                        end)
                    end
                    local deadline: number = os.clock() + 10
                    while os.clock() < deadline and current() do
                        local character: Model?, newHumanoid: Humanoid?,
                            newRoot: BasePart? = characterParts()
                        if character and character ~= oldCharacter
                            and newHumanoid and newHumanoid.Health > 0
                            and newRoot then
                            break
                        end
                        task.wait()
                    end
                    task.wait(0.1)
                end
                if not alive() then
                    return
                end
                if settings.flingMurder and type(findMurderer) == "function" then
                    flingPlayer(findMurderer(), alive)
                end
                if alive() and settings.flingSheriff
                    and type(findSheriff) == "function" then
                    flingPlayer(findSheriff(), alive)
                end
            end)
            if not ok then
                warn("Auto Farm full-bag sequence failed: " .. tostring(err))
            end
            busy = false
        end

        local remotes: any = core.mm2GameplayRemotes
        local collected: Instance? = remotes
            and remotes:FindFirstChild("CoinCollected")
        if collected and collected:IsA("RemoteEvent") then
            featureConnections.MM2AutoFarmCoinCollected =
                (collected :: any).OnClientEvent:Connect(
                    function(_bag: any, amount: any, limit: any): ()
                        if type(limit) == "number" and limit >= 50 then
                            bagLimit = limit
                            rememberedBagLimit = limit
                        end
                        if type(amount) == "number" then
                            if amount > bagAmount then
                                totalCoinsCollected += (amount - bagAmount)
                                refreshFarmOverlay()
                                if currentTargetCoin then
                                    blacklist[currentTargetCoin] = os.clock() + BLACKLIST_SECONDS
                                    currentTargetCoin = nil
                                end
                                scanAt = 0
                            end
                            bagAmount = amount
                            rememberedBagAmount = amount
                        end
                        local targetLimit: number = math.max(50, bagLimit)
                        if bagAmount < targetLimit then
                            fullHandled = false
                            roundFullReached = false
                            rememberedFullHandled = false
                        end
                    end
                )
        end

        local function stepFarmPhysicsOverride(): ()
            if not engaged or settings.mode ~= "Walk" then
                return
            end
            local character: Model?, humanoid: Humanoid?, root: BasePart? =
                characterParts()
            if not character or not humanoid or not root or humanoid.Health <= 0
                or not isCharacterInActiveRound(root) then
                restoreCharacter(false)
                return
            end
            if activeWalkDir then
                pcall(function(): ()
                    humanoid:Move(activeWalkDir :: Vector3, false)
                end)
            end
        end

        local function preFarmPhysics(deltaTime: number): ()
            if settings.mode == "Walk" or (not engaged and not hiddenUnderMap) then
                return
            end
            local character: Model?, humanoid: Humanoid?, root: BasePart? =
                characterParts()
            if not character or not humanoid or not root or humanoid.Health <= 0 then
                if engaged or hiddenUnderMap then
                    restoreCharacter(false)
                end
                return
            end
            if not isCharacterInActiveRound(root) then
                if engaged or hiddenUnderMap then
                    restoreCharacter(false)
                end
                return
            end
            forceNoClipCharacter(character)
            if belowHold then
                ensureFarmConstraints(root, Vector3.zero, yawOf(root.CFrame))
            elseif belowDestination then
                moveTowards(root, belowDestination :: Vector3,
                    if type(deltaTime) == "number" then deltaTime else belowDeltaTime)
            end
        end

        if RunService and RunService.Stepped then
            featureConnections.MM2AutoFarmStepped = RunService.Stepped:Connect(stepFarmPhysicsOverride)
        end
        pcall(function(): ()
            if RunService and (RunService :: any).PreSimulation then
                featureConnections.MM2AutoFarmPreSim =
                    (RunService :: any).PreSimulation:Connect(preFarmPhysics)
            end
        end)

        featureConnections.MM2AutoFarmTick = TaskManager:Connect(
            function(deltaTime: number): ()
                if type(deltaTime) == "number" and deltaTime > 0 and deltaTime < 5 then
                    farmElapsedSeconds += deltaTime
                    refreshFarmOverlay()
                end
                local character: Model?, humanoid: Humanoid?,
                    root: BasePart? = characterParts()
                if not character or not humanoid or not root
                    or humanoid.Health <= 0 then
                    if engaged or hiddenUnderMap then
                        -- Death is cleanup-only: restoreCharacter(false)
                        -- cannot reposition without a living active round.
                        restoreCharacter(false)
                    end
                    return
                end

                -- Strict lobby & non-round guard: NEVER activate, move,
                -- or farm in the lobby or outside an active round on a map.
                local inActiveRound: boolean = isCharacterInActiveRound(root)
                if not inActiveRound then
                    if engaged or hiddenUnderMap then
                        restoreCharacter(false)
                    end
                    if wasInActiveRound then
                        wasInActiveRound = false
                        roundGeneration += 1
                        rememberedBagAmount = 0
                        rememberedBagLimit = 50
                        rememberedFullHandled = false
                        bagAmount = 0
                        fullHandled = false
                        roundFullReached = false
                        teleportedHomeThisRound = false
                        firstCoinSeenThisRound = false
                        currentTargetCoin = nil
                        homeCFrame = nil
                        homeCharacter = nil
                        roundSurfaceY = nil
                        hideAnchorPosition = nil
                        destroySafeZonePlatform()
                    end
                    setStatus("Auto Farm: waiting in lobby")
                    stuckPart = nil
                    return
                end
                if busy then
                    return
                end

                if not wasInActiveRound then
                    wasInActiveRound = true
                    roundGeneration += 1
                    bagAmount = rememberedBagAmount
                    bagLimit = rememberedBagLimit
                    fullHandled = rememberedFullHandled
                    roundFullReached = rememberedFullHandled
                    teleportedHomeThisRound = false
                    firstCoinSeenThisRound = false
                    currentTargetCoin = nil
                    roundSurfaceY = root.Position.Y
                    homeCFrame = CFrame.new(root.Position)
                        * CFrame.Angles(0, yawOf(root.CFrame), 0)
                    homeCharacter = character
                    hideAnchorPosition = Vector3.new(
                        root.Position.X,
                        root.Position.Y - (BELOW_OFFSET + 5.5),
                        root.Position.Z
                    )
                end

                local targetLimit: number = math.max(50, bagLimit)

                -- Stop farming ONLY when 50 coins (full bag) are detected!
                if bagAmount >= targetLimit then
                    if not fullHandled then
                        fullHandled = true
                        rememberedFullHandled = true
                        rememberedBagAmount = bagAmount
                        roundFullReached = true
                        if settings.killAllOnFull or settings.resetOnFull
                            or settings.flingMurder or settings.flingSheriff
                            or settings.grabGunShoot then
                            task.spawn(runFullSequence, thisEnable, roundGeneration)
                        else
                            restoreCharacter(true)
                        end
                    else
                        setStatus(string.format(
                            "Auto Farm: full bag (%d/%d) - stopped at start position",
                            bagAmount, targetLimit
                        ))
                    end
                    return
                end

                if roundFullReached then
                    return
                end

                -- Void guard. While bagAmount < 50, never teleport back to
                -- homeCFrame on top of the map; recover directly to the
                -- hidden spot underneath the map instead of falling further.
                local destroyHeight: number = workspace.FallenPartsDestroyHeight
                if destroyHeight ~= destroyHeight then
                    destroyHeight = -500
                end
                if root.Position.Y <= destroyHeight + 60 then
                    holdHiddenUnderMap(character, humanoid, root)
                    setStatus(
                        "Auto Farm: recovered from the void - hidden under map"
                    )
                    return
                end

                -- Nearest pickup, from Coin ESP's own detection.
                local now: number = os.clock()
                local scanInterval: number = if #scanCache == 0 then 0.10 else 0.25
                if now - scanAt > scanInterval then
                    scanAt = now
                    scanCache = coinPickups()
                end
                local nearest: Instance? = nil
                local nearestPosition: Vector3? = nil
                local nearestDistance: number = math.huge
                for _, part: Instance in ipairs(scanCache) do
                    if part.Parent
                        and stillCollectable(part)
                        and (not blacklist[part] or blacklist[part] < now) then
                        local position: Vector3? = coinPositionOf(part)
                        if position then
                            local distance: number =
                                ((position :: Vector3) - root.Position).Magnitude
                            if distance < nearestDistance then
                                nearest = part
                                nearestPosition = position
                                nearestDistance = distance
                            end
                        end
                    end
                end
                if not nearest or not nearestPosition then
                    currentTargetCoin = nil
                    -- Only update homeCFrame X/Z before the first coin has spawned
                    -- and while not engaged, keeping roundSurfaceY so hideAnchorPosition
                    -- never drifts downward into the void!
                    if not firstCoinSeenThisRound and not engaged and homeCFrame then
                        local dx: number = root.Position.X - homeCFrame.Position.X
                        local dz: number = root.Position.Z - homeCFrame.Position.Z
                        if math.sqrt(dx * dx + dz * dz) > 14 then
                            if not hiddenUnderMap then
                                roundSurfaceY = root.Position.Y
                            end
                            local surfY: number = roundSurfaceY or homeCFrame.Position.Y
                            local safeSpawnPos: Vector3 = Vector3.new(
                                root.Position.X,
                                surfY,
                                root.Position.Z
                            )
                            homeCFrame = CFrame.new(safeSpawnPos)
                                * CFrame.Angles(0, yawOf(root.CFrame), 0)
                            homeCharacter = character
                            hideAnchorPosition = Vector3.new(
                                safeSpawnPos.X,
                                surfY - (BELOW_OFFSET + 5.5),
                                safeSpawnPos.Z
                            )
                        end
                    end
                    scanAt = now - 0.20
                    if not firstCoinSeenThisRound then
                        if settings.stayUnderOnStart then
                            holdHiddenUnderMap(character, humanoid, root)
                        elseif hiddenUnderMap or engaged then
                            restoreCharacter(false, true)
                        end
                    else
                        if settings.mode == "Walk" then
                            activeWalkDir = nil
                            activeWalkTarget = nil
                            if hiddenUnderMap then
                                restoreCharacter(false)
                            end
                            pcall(function(): ()
                                humanoid:Move(Vector3.zero, false)
                            end)
                        else
                            holdHiddenUnderMap(character, humanoid, root)
                        end
                    end
                    setStatus(string.format(
                        "Auto Farm (%s): waiting for coin - bag %d/%d - speed %d u/s - ping %dms",
                        settings.mode, bagAmount, targetLimit,
                        math.round(math.clamp(settings.speed, 5, 60)),
                        pingMillis()
                    ))
                    stuckPart = nil
                    return
                end
                firstCoinSeenThisRound = true
                currentTargetCoin = nearest
                if hiddenUnderMap and settings.mode == "Walk" then
                    restoreCharacter(false, true)
                end
                -- Capture pre-farm homeCFrame and stay engaged while
                -- bagAmount < 50 inside the active round.
                engage(character, humanoid, root)
                local remaining: number
                local arrived: boolean
                if settings.mode == "Walk" then
                    belowHold = false
                    belowDestination = nil
                    remaining = walkTowards(
                        humanoid,
                        root,
                        nearestPosition :: Vector3,
                        deltaTime
                    )
                    arrived = remaining < 1.6
                else
                    -- One fixed contact pose per coin. The 4x8x4 hitbox
                    -- reaches the server coin from this single offset;
                    -- there is no far/near height alternation.
                    local destination: Vector3 =
                        (nearestPosition :: Vector3) - Vector3.new(0, BELOW_OFFSET, 0)
                    belowHold = false
                    belowDestination = destination
                    belowDeltaTime = if type(deltaTime) == "number"
                        then deltaTime else belowDeltaTime
                    remaining = (destination - root.Position).Magnitude
                    arrived = remaining < 1.0
                end
                if arrived or remaining < 3.5 then
                    -- Pulse the touch directly against the Coin_Server part
                    -- until the coin is collected.
                    if now - lastTouchPulse > 0.08 then
                        lastTouchPulse = now
                        local touchPart: Instance? =
                            serverPartOf(nearest)
                        if type(state.fireTouchInterest) == "function"
                            and touchPart then
                            pcall(state.fireTouchInterest, root, touchPart, 0)
                            pcall(state.fireTouchInterest, root, touchPart, 1)
                        end
                    end
                end
                setStatus(string.format(
                    "Auto Farm (%s): %d coins - bag %d/%d - speed %d u/s - ping %dms",
                    settings.mode, #scanCache, bagAmount, targetLimit,
                    math.round(math.clamp(settings.speed, 5, 60)),
                    pingMillis()
                ))
                if arrived then
                    -- Parked under the coin: if it does not collect,
                    -- skip it for a while instead of getting stuck.
                    if stuckPart ~= nearest then
                        stuckPart = nearest
                        stuckSince = now
                    elseif now - stuckSince > STUCK_SECONDS then
                        blacklist[nearest] = now + BLACKLIST_SECONDS
                        stuckPart = nil
                    end
                else
                    stuckPart = nil
                end
            end
        )

        -- Turning the feature off runs this through
        -- disconnectFeatureConnection above: full restore, and the
        -- character is put back where the farm first grabbed it.
        featureConnections.MM2AutoFarmRestore = {
            Disconnect = function(): ()
                destroySafeZonePlatform()
                restoreCharacter(true)
            end,
        }
    end

    local AutoFarmFeature: any = createUniversalFeature(
        "Auto Farm",
        "Walks on the ground to the nearest coins (Walk), or flies upright under the floor with a grown hitbox that still touches them (Below), with full-bag actions.",
        6,
        toggleAutoFarm,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoFarmFeature = AutoFarmFeature

    if type(state.addSectionOption) == "function" then
        state.addSectionOption(AutoFarmFeature, "Overlay Info")
    end
    if type(state.addStatOption) == "function" then
        coinsCollectedStat = state.addStatOption(AutoFarmFeature, "Coins Collected", "0")
        farmTimeStat = state.addStatOption(AutoFarmFeature, "Time", "00:00")
    end

    local modeConfigs: {[string]: {[string]: any}} = {
        Walk = {
            speed = 16,
            stayUnderOnStart = false,
            safeZone = true,
            resetOnFull = true,
            flingMurder = false,
            flingSheriff = false,
            grabGunShoot = false,
            killAllOnFull = false,
        },
        Below = {
            speed = 16,
            stayUnderOnStart = true,
            safeZone = true,
            resetOnFull = true,
            flingMurder = false,
            flingSheriff = false,
            grabGunShoot = false,
            killAllOnFull = false,
        },
    }
    local switchingFarmMode: boolean = false

    local function syncFarmModeOptions(): ()
        local modeKey: string = (settings.mode == "Walk") and "Walk" or "Below"
        local cfg = modeConfigs[modeKey] or modeConfigs.Walk
        switchingFarmMode = true
        settings.speed = cfg.speed or 16
        settings.stayUnderOnStart = cfg.stayUnderOnStart == true
        settings.safeZone = cfg.safeZone == true
        settings.resetOnFull = cfg.resetOnFull == true
        settings.flingMurder = cfg.flingMurder == true
        settings.flingSheriff = cfg.flingSheriff == true
        settings.grabGunShoot = cfg.grabGunShoot == true
        settings.killAllOnFull = cfg.killAllOnFull == true
        if state and type(state.valueControls) == "table" then
            local sp = state.valueControls["MM2.AutoFarm.FarmSpeed"]
            if sp and type(sp.apply) == "function" then
                pcall(sp.apply, settings.speed)
            end
        end
        if state and type(state.toggleControls) == "table" then
            local pairsToSync: {{any}} = {
                {"MM2.AutoFarm.StayUnderWhenRoundstarts", settings.stayUnderOnStart},
                {"MM2.AutoFarm.SafeZone", settings.safeZone},
                {"MM2.AutoFarm.ResetWhenFullCoinBag", settings.resetOnFull},
                {"MM2.AutoFarm.FlingMurderafterreset", settings.flingMurder},
                {"MM2.AutoFarm.FlingSheriffafterreset", settings.flingSheriff},
                {"MM2.AutoFarm.AutoGrabgunandShoot", settings.grabGunShoot},
                {"MM2.AutoFarm.AutoKillAllWhenfullcoinbag", settings.killAllOnFull},
            }
            for _, entry: {any} in ipairs(pairsToSync) do
                local ctrl = state.toggleControls[entry[1]]
                if ctrl and type(ctrl.setChecked) == "function" then
                    pcall(ctrl.setChecked, entry[2] == true)
                end
            end
        end
        switchingFarmMode = false
    end

    addCycleOption(AutoFarmFeature, "Farm Mode", {"Walk", "Below (Hitbox)"}, 1,
        function(value: string): ()
            settings.mode = if value == "Walk" then "Walk" else "Below"
            syncFarmModeOptions()
        end, "Walk: your character walks on the ground to each coin (nothing about the body is changed; the slider is WalkSpeed). Below (Hitbox): upright, NoClip, flying under the floor with the root hitbox grown so it still touches the coin from below.")
    addNumberOption(AutoFarmFeature, "Farm Speed", 16, 5, 60,
        function(value: number): ()
            settings.speed = value
            if not switchingFarmMode then
                local cfg = modeConfigs[(settings.mode == "Walk") and "Walk" or "Below"]
                if cfg then cfg.speed = value end
            end
        end, "Walk mode: WalkSpeed. Below mode: flight speed in studs/second -- if the server kicks you (Invalid position), lower it; raise it slowly to find your fastest safe speed.", 1)
    addToggleOption(AutoFarmFeature, "Stay Under When Round starts", true,
        function(value: boolean): ()
            settings.stayUnderOnStart = value == true
            if not switchingFarmMode then
                local cfg = modeConfigs[(settings.mode == "Walk") and "Walk" or "Below"]
                if cfg then cfg.stayUnderOnStart = value == true end
            end
        end, "When enabled, hides your character safely underneath the map at the start of the round until coins spawn. When disabled, your character stays naturally on the map at the random spawn point where you spawned.")
    addToggleOption(AutoFarmFeature, "Safe Zone", true,
        function(value: boolean): ()
            settings.safeZone = value == true
            if not switchingFarmMode then
                local cfg = modeConfigs[(settings.mode == "Walk") and "Walk" or "Below"]
                if cfg then cfg.safeZone = value == true end
            end
        end, "When you reach 50 coins, teleports you to a platform in the void so the Murderer cannot reach or kill you.")
    addToggleOption(AutoFarmFeature, "Reset When Full Coin Bag", true,
        function(value: boolean): ()
            settings.resetOnFull = value
            if not switchingFarmMode then
                local cfg = modeConfigs[(settings.mode == "Walk") and "Walk" or "Below"]
                if cfg then cfg.resetOnFull = value == true end
            end
        end, "Reset the character as soon as the coin bag fills.")
    addToggleOption(AutoFarmFeature, "Fling Murder after reset", false,
        function(value: boolean): ()
            settings.flingMurder = value
            if not switchingFarmMode then
                local cfg = modeConfigs[(settings.mode == "Walk") and "Walk" or "Below"]
                if cfg then cfg.flingMurder = value == true end
            end
        end, "When the coin bag fills (50): fling the Murderer (after the reset above, if it is on).")
    addToggleOption(AutoFarmFeature, "Fling Sheriff after reset", false,
        function(value: boolean): ()
            settings.flingSheriff = value
            if not switchingFarmMode then
                local cfg = modeConfigs[(settings.mode == "Walk") and "Walk" or "Below"]
                if cfg then cfg.flingSheriff = value == true end
            end
        end, "When the coin bag fills (50): fling the Sheriff (after the reset above, if it is on).")
    addToggleOption(AutoFarmFeature, "Auto Grab gun and Shoot", false,
        function(value: boolean): ()
            settings.grabGunShoot = value
            if not switchingFarmMode then
                local cfg = modeConfigs[(settings.mode == "Walk") and "Walk" or "Below"]
                if cfg then cfg.grabGunShoot = value == true end
            end
        end, "Only when the coin bag fills (50), only as Innocent and only during an active round (never as Murderer, never in the lobby): try an instant touch for the dropped sheriff gun, otherwise walk/fly to it, equip it, and fire one SilentAim shot at the Murderer. Never during ordinary farming.")
    addToggleOption(AutoFarmFeature, "Auto Kill All When full coin bag", false,
        function(value: boolean): ()
            settings.killAllOnFull = value
            if not switchingFarmMode then
                local cfg = modeConfigs[(settings.mode == "Walk") and "Walk" or "Below"]
                if cfg then cfg.killAllOnFull = value == true end
            end
        end, "As Murderer, when the bag fills: pull everyone in front of you and slash (YARHM Kill All).")
    addInformationOption(
        AutoFarmFeature,
        "Walk uses Humanoid locomotion on the ground. Below (Hitbox) uses upright LinearVelocity + AlignOrientation constraints with NoClip and a 4x8x4 root hitbox, with one fixed contact offset per coin and a stationary wait when no target exists. Collected coins are dropped as targets immediately. Only explicit startup/return cleanup uses a guarded CFrame reposition, never a dead/lobby/ended-round action. If Below kicks you for Invalid position, lower Farm Speed and raise it little by little. OFF restores collisions, hitbox and WalkSpeed."
    )

    activeCleanup = function(): ()
        state.mm2AutoFarmFeature = nil
        toggleAutoFarm(false)
        if unsubscribeRoundPhase then
            pcall(unsubscribeRoundPhase)
            unsubscribeRoundPhase = nil
        end
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
    activeCleanup = function(): ()
    end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
