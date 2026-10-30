local Module = {
    Name = "MM2 Auto Win",
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
    assert(type(core) == "table", "MM2 Auto Win requires the MM2 core module")
    local prediction: any = state.mm2Prediction
    Module.Runtime = runtime

    local findDroppedGun: any = core.findDroppedGun
    local findMM2Map: any = core.findMM2Map
    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local getGunOriginCFrame: any = core.getGunOriginCFrame
    local getPlayerRole: any = core.getPlayerRole
    local getPlayerWeapon: any = core.getPlayerWeapon
    local isPlayerAlive: any = core.isPlayerAlive
    local isProtectedTarget: any = core.isProtectedTarget
    local isRoundLifecycleActive: any = core.isRoundLifecycleActive

    local ABOVE_MAP_OFFSET: number = 120
    local MAP_FLING_WARMUP_SECONDS: number = 5.0
    local SHERIFF_READY_DELAY_SECONDS: number = 2.0
    local SHERIFF_FLING_COOLDOWN_SECONDS: number = 1.2

    local settings = {
        instaKillMurder = true,
        instaKillSheriff = true,
        flingSheriffGetGun = false,
        flingMurderIfDead = false,
    }

    local autoWinActive: boolean = false
    local AutoWinFeature: any = nil
    local lastStatus: string? = nil

    local sheriffWins: number = 0
    local murderWins: number = 0
    local innocentWins: number = 0
    local sheriffWinsStat: any = nil
    local murderWinsStat: any = nil
    local innocentWinsStat: any = nil

    local wasOnMap: boolean = false
    local mapEnteredAt: number = 0
    local sheriffFirstSeenAt: number = 0
    local lastSheriffFlingAt: number = 0
    local participatedInRound: boolean = false
    local roundMyRole: string? = nil
    local roundSawMurderer: boolean = false
    local roundCountedWin: boolean = false
    local flungMurderThisDeath: boolean = false
    local flingBusy: boolean = false

    local safeAbovePosition: Vector3? = nil
    local savedCollide: {[Instance]: boolean} = {}
    local savedCustomProps: {[BasePart]: PhysicalProperties?} = {}
    local victimSnapshots: {[BasePart]: {cframe: CFrame, anchored: boolean, canCollide: boolean}} = {}
    local toolConnections: {RBXScriptConnection} = {}
    local flingAngle: number = 0

    local function updateWinOverlay(): ()
        if sheriffWinsStat and type(sheriffWinsStat.set) == "function" then
            sheriffWinsStat.set(tostring(sheriffWins))
        end
        if murderWinsStat and type(murderWinsStat.set) == "function" then
            murderWinsStat.set(tostring(murderWins))
        end
        if innocentWinsStat and type(innocentWinsStat.set) == "function" then
            innocentWinsStat.set(tostring(innocentWins))
        end
    end

    local function awardRoundWin(roleCategory: string?): ()
        if roundCountedWin then
            return
        end
        local cat: string = roleCategory or roundMyRole or "Innocent"
        roundCountedWin = true
        if cat == "Murderer" then
            murderWins += 1
        elseif cat == "Sheriff" or cat == "Hero" then
            sheriffWins += 1
        else
            innocentWins += 1
        end
        updateWinOverlay()
    end

    local function setStatus(text: string?): ()
        if text == lastStatus then
            return
        end
        lastStatus = text
        if AutoWinFeature then
            AutoWinFeature:SetStatus(text)
        end
    end

    local function yawOf(frame: CFrame): number
        local look: Vector3 = frame.LookVector
        return math.atan2(-look.X, -look.Z)
    end

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then
            return nil, nil, nil
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not humanoid or not root then
            return nil, nil, nil
        end
        return character, humanoid, root
    end

    local function findLobbyReferencePart(): BasePart?
        for _, child: Instance in ipairs(workspace:GetChildren()) do
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

    -- True as soon as the player's character is on the MM2 map, even during
    -- the pre-round countdown before roles or weapons have been handed out.
    local function isCharacterOnMap(root: BasePart): (boolean, Vector3?)
        if type(findMM2Map) ~= "function" then
            return false, nil
        end
        local map: Instance? = findMM2Map()
        if not map then
            return false, nil
        end
        local okRoot: boolean, rootPos: any = pcall(function(): any
            return root.Position
        end)
        if not okRoot or typeof(rootPos) ~= "Vector3" then
            return false, nil
        end
        local lobbyPart: BasePart? = findLobbyReferencePart()
        if lobbyPart then
            local okLobbyDist: boolean, lobbyDist: any = pcall(function(): any
                return ((rootPos :: Vector3) - lobbyPart.Position).Magnitude
            end)
            if okLobbyDist and type(lobbyDist) == "number" and lobbyDist <= 350 then
                return false, nil
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
            local okMapDist: boolean, mapDist: any = pcall(function(): any
                return ((rootPos :: Vector3) - refPart.Position).Magnitude
            end)
            if okMapDist and type(mapDist) == "number" and mapDist > 1500 then
                return false, nil
            end
            return true, refPart.Position
        end
        return true, rootPos :: Vector3
    end

    local function restoreVictims(): ()
        for part: BasePart, snap in pairs(victimSnapshots) do
            if part and part.Parent then
                pcall(function(): ()
                    part.Anchored = snap.anchored
                    part.CanCollide = snap.canCollide
                    part.CFrame = snap.cframe
                end)
            end
        end
        table.clear(victimSnapshots)
    end

    local function restoreLocalCharacter(): ()
        restoreVictims()
        if services and services.activity then
            pcall(function(): ()
                services.activity.set("fling", false)
            end)
        end
        for part: Instance, wasCollide: boolean in pairs(savedCollide) do
            if part and part.Parent then
                pcall(function(): ()
                    (part :: BasePart).CanCollide = wasCollide
                end)
            end
        end
        table.clear(savedCollide)
        for part: BasePart, oldProps: PhysicalProperties? in pairs(savedCustomProps) do
            if part and part.Parent then
                pcall(function(): ()
                    part.CustomPhysicalProperties = oldProps
                end)
            end
        end
        table.clear(savedCustomProps)

        local character: Model?, humanoid: Humanoid?, root: BasePart? = characterParts()
        if humanoid then
            pcall(function(): ()
                humanoid.PlatformStand = false
                humanoid.AutoRotate = true
                humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
                humanoid:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
        if root then
            pcall(function(): ()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                if safeAbovePosition then
                    local groundPos: Vector3 = safeAbovePosition - Vector3.new(0, ABOVE_MAP_OFFSET - 4, 0)
                    local targetCF: CFrame = CFrame.new(groundPos)
                        * CFrame.Angles(0, yawOf(root.CFrame), 0)
                    if character then
                        pcall(function(): ()
                            character:PivotTo(targetCF)
                        end)
                    end
                    root.CFrame = targetCF
                end
            end)
        end
    end

    local function disableCharacterCollisions(character: Model): ()
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

    local function enableCharacterFlingCollisions(character: Model): ()
        local heavyProps: PhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
        for _, object: Instance in ipairs(character:GetChildren()) do
            if object:IsA("BasePart") then
                local part: BasePart = object :: BasePart
                if savedCollide[part] == nil then
                    savedCollide[part] = part.CanCollide
                end
                if savedCustomProps[part] == nil then
                    pcall(function(): ()
                        savedCustomProps[part] = part.CustomPhysicalProperties
                    end)
                end
                pcall(function(): ()
                    part.CanCollide = true
                    part.CustomPhysicalProperties = heavyProps
                end)
            end
        end
    end

    local function holdAboveMap(
        character: Model,
        humanoid: Humanoid,
        root: BasePart
    ): ()
        if services and services.activity then
            pcall(function(): ()
                services.activity.set("fling", false)
            end)
        end
        disableCharacterCollisions(character)
        local holdPos: Vector3 = safeAbovePosition
            or (root.Position + Vector3.new(0, ABOVE_MAP_OFFSET, 0))
        pcall(function(): ()
            humanoid.PlatformStand = true
            humanoid.AutoRotate = false
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = CFrame.new(holdPos)
                * CFrame.Angles(0, yawOf(root.CFrame), 0)
        end)
    end

    local function findLocalTool(toolName: string): Tool?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if type(getPlayerWeapon) == "function" then
            local found: Tool? = getPlayerWeapon(LocalPlayer, toolName, false)
            if found then
                return found
            end
        end
        if character then
            local inChar: Instance? = character:FindFirstChild(toolName)
            if inChar and inChar:IsA("Tool") then
                return inChar
            end
        end
        local backpack: Instance? = LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            local inBp: Instance? = backpack:FindFirstChild(toolName)
            if inBp and inBp:IsA("Tool") then
                return inBp
            end
        end
        return nil
    end

    local function ensureToolEquipped(
        character: Model,
        humanoid: Humanoid,
        tool: Tool
    ): boolean
        if tool.Parent == character then
            return true
        end
        pcall(function(): ()
            humanoid:EquipTool(tool)
        end)
        if tool.Parent ~= character then
            pcall(function(): ()
                tool.Parent = character
            end)
        end
        return tool.Parent == character
    end

    local function findActiveMurderer(): Player?
        local playersService: Players = game:GetService("Players")
        if type(getPlayerWeapon) == "function" then
            for _, player: Player in ipairs(playersService:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                    and getPlayerWeapon(player, "Gun", false) == nil
                    and getPlayerWeapon(player, "Knife", false) ~= nil then
                    return player
                end
            end
        end
        if type(findMurderer) == "function" then
            local target: Player? = findMurderer()
            if target
                and target ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(target))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(target, "Gun", false) == nil) then
                return target
            end
        end
        for _, player: Player in ipairs(playersService:GetPlayers()) do
            if player ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(player, "Gun", false) == nil) then
                local role: any = type(getPlayerRole) == "function"
                    and getPlayerRole(player)
                    or nil
                if role == "Murderer" then
                    return player
                end
            end
        end
        return nil
    end

    local function findActiveSheriffOrHero(): Player?
        local playersService: Players = game:GetService("Players")
        if type(getPlayerWeapon) == "function" then
            for _, player: Player in ipairs(playersService:GetPlayers()) do
                if player ~= LocalPlayer
                    and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                    and getPlayerWeapon(player, "Knife", false) == nil
                    and getPlayerWeapon(player, "Gun", false) ~= nil then
                    return player
                end
            end
        end
        if type(findSheriff) == "function" then
            local target: Player? = findSheriff()
            if target
                and target ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(target))
                and (type(getPlayerWeapon) ~= "function"
                    or getPlayerWeapon(target, "Knife", false) == nil) then
                return target
            end
        end
        return nil
    end

    -- Insta Kill as Murder (Kill All while staying safely above the map).
    local function runInstaKillAsMurder(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        knife: Tool
    ): boolean
        holdAboveMap(character, humanoid, root)
        if not ensureToolEquipped(character, humanoid, knife) then
            return false
        end
        local handle: BasePart? = (knife:FindFirstChild("Handle") :: BasePart?)
            or knife:FindFirstChildWhichIsA("BasePart")
        local slashRemote: Instance? = knife:FindFirstChild("Slash")
        local stabRemote: Instance? = knife:FindFirstChild("Stab")
        local eventsFolder: Instance? = knife:FindFirstChild("Events")
        local touchedRemote: Instance? = eventsFolder
            and eventsFolder:FindFirstChild("HandleTouched")

        local attackCF: CFrame = (handle and handle.CFrame)
            or (root.CFrame * CFrame.new(0, 0, -2.5))
        local playersService: Players = game:GetService("Players")
        local hitAny: boolean = false

        for _, player: Player in ipairs(playersService:GetPlayers()) do
            if player ~= LocalPlayer
                and (type(isPlayerAlive) ~= "function" or isPlayerAlive(player))
                and (type(isProtectedTarget) ~= "function" or not isProtectedTarget(player)) then
                local victimChar: Model? = player.Character
                local victimRoot: BasePart? = victimChar
                    and victimChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                if victimChar and victimRoot then
                    local onVictimMap: boolean = isCharacterOnMap(victimRoot)
                    if onVictimMap then
                        hitAny = true
                        if not victimSnapshots[victimRoot] then
                            pcall(function(): ()
                                victimSnapshots[victimRoot] = {
                                    cframe = victimRoot.CFrame,
                                    anchored = victimRoot.Anchored,
                                    canCollide = victimRoot.CanCollide,
                                }
                            end)
                        end
                        pcall(function(): ()
                            victimRoot.Anchored = true
                            victimRoot.CanCollide = false
                            victimRoot.AssemblyLinearVelocity = Vector3.zero
                            victimRoot.AssemblyAngularVelocity = Vector3.zero
                            victimRoot.CFrame = attackCF
                        end)
                        if slashRemote and slashRemote:IsA("RemoteEvent") then
                            pcall(function(): ()
                                (slashRemote :: RemoteEvent):FireServer("Slash")
                            end)
                        end
                        if stabRemote and stabRemote:IsA("RemoteEvent") then
                            pcall(function(): ()
                                (stabRemote :: RemoteEvent):FireServer("Slash")
                            end)
                        end
                        if touchedRemote and touchedRemote:IsA("RemoteEvent") then
                            pcall(function(): ()
                                (touchedRemote :: RemoteEvent):FireServer(victimRoot)
                            end)
                        end
                        if handle and type(state.fireTouchInterest) == "function" then
                            pcall(state.fireTouchInterest, handle, victimRoot, 0)
                            pcall(state.fireTouchInterest, handle, victimRoot, 1)
                        end
                    end
                end
            end
        end
        if not hitAny then
            restoreVictims()
            awardRoundWin("Murderer")
        end
        return hitAny
    end

    -- Insta Kill As Sheriff (uses AutoShoot CFrame immediately upon receiving
    -- the Gun, whether our role is Sheriff, Hero, or Innocent).
    local function runInstaKillAsSheriff(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        gun: Tool
    ): boolean
        holdAboveMap(character, humanoid, root)
        if not ensureToolEquipped(character, humanoid, gun) then
            return false
        end
        local murderer: Player? = findActiveMurderer()
        if not murderer then
            if roundSawMurderer then
                awardRoundWin("Sheriff")
            end
            return false
        end
        roundSawMurderer = true
        if type(state.mm2AutoShootCFrameOnce) == "function" then
            local okHelper: boolean, helperRes: any =
                pcall(state.mm2AutoShootCFrameOnce, false)
            if okHelper and helperRes == true then
                return true
            end
        end
        if type(isProtectedTarget) == "function" and isProtectedTarget(murderer) then
            return false
        end
        local targetChar: Model? = murderer.Character
        local targetRoot: BasePart? = targetChar
            and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not targetRoot then
            return false
        end
        if type(state.mm2FireSilentShot) == "function" then
            -- v139.4: pass our options so the shared path keeps the wall check.
            local okSilent: boolean, res: any = pcall(state.mm2FireSilentShot, murderer, {
                continuous = true,
                quiet = true,
                wallCheck = true,
            })
            if okSilent and res == true then
                return true
            end
        end
        local shootRemote: Instance? = gun:FindFirstChild("Shoot")
        if not (shootRemote and shootRemote:IsA("RemoteEvent")) then
            return false
        end
        local originCF: CFrame = (type(getGunOriginCFrame) == "function"
            and getGunOriginCFrame(character, gun))
            or root.CFrame
        local endpoint: Vector3 = targetRoot.Position
        if type(prediction) == "table" and type(prediction.gunAim) == "function" then
            local okAim: boolean, aimPt: any = pcall(
                prediction.gunAim,
                murderer,
                originCF.Position
            )
            if okAim and typeof(aimPt) == "Vector3" then
                endpoint = aimPt
            else
                local vel: Vector3 = Vector3.zero
                pcall(function(): ()
                    vel = targetRoot.AssemblyLinearVelocity
                end)
                endpoint = targetRoot.Position + vel * 0.08
            end
        end
        local startPoint: Vector3 = endpoint + Vector3.new(0, 1.5, -2.5)
        local shotOrigin: CFrame = CFrame.lookAt(startPoint, endpoint)
        local shotEnd: CFrame = CFrame.new(endpoint)
        -- v139.4: the hand-rolled fallback must not shoot through a wall.
        if type(isWeaponPathClear) == "function" then
            local okClear: boolean, allowed: any = pcall(
                isWeaponPathClear,
                originCF.Position,
                endpoint,
                targetChar,
                nil,
                {ignoreTarget = true}
            )
            if not okClear or allowed ~= true then
                return false
            end
        end
        pcall(function(): ()
            (shootRemote :: RemoteEvent):FireServer(shotOrigin, shotEnd)
        end)
        return true
    end

    -- Grab the dropped gun ONLY via fireTouchInterest while staying safely
    -- above the map (never risking a teleport down to the map).
    local function grabDroppedGunTouchOnly(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        drop: Instance
    ): boolean
        holdAboveMap(character, humanoid, root)
        if type(state.fireTouchInterest) ~= "function" then
            return false
        end
        local touchPart: BasePart? = nil
        if drop:IsA("BasePart") then
            touchPart = drop :: BasePart
        elseif drop:IsA("Model") then
            touchPart = (drop:FindFirstChild("Handle", true) :: BasePart?)
                or drop:FindFirstChildWhichIsA("BasePart", true)
        end
        if not touchPart then
            return false
        end
        pcall(state.fireTouchInterest, root, touchPart, 0)
        pcall(state.fireTouchInterest, root, touchPart, 1)
        return findLocalTool("Gun") ~= nil
    end

    -- Controlled, bounded Fling on the Sheriff: waits for map/character warmup,
    -- uses state.mm2PerformFling with a returnCFrame to safeAbovePosition when
    -- available (or bounded 10000-stud/s impulse fallback so our character
    -- never enters Roblox's floating-point NullZone or void).
    local function flingSheriffStep(
        character: Model,
        humanoid: Humanoid,
        root: BasePart,
        sheriff: Player
    ): boolean
        local sheriffChar: Model? = sheriff.Character
        local sheriffHum: Humanoid? = sheriffChar
            and sheriffChar:FindFirstChildOfClass("Humanoid")
        local sheriffRoot: BasePart? = sheriffChar
            and sheriffChar:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not sheriffChar or not sheriffHum or sheriffHum.Health <= 0 or sheriffHum.Sit or not sheriffRoot then
            holdAboveMap(character, humanoid, root)
            return false
        end
        local destroyHeight: number = workspace.FallenPartsDestroyHeight
        if destroyHeight ~= destroyHeight or math.abs(destroyHeight) > 1e6 then
            destroyHeight = -500
        end
        local sheriffPos: Vector3 = sheriffRoot.Position
        if sheriffPos.Y <= destroyHeight + 60 then
            holdAboveMap(character, humanoid, root)
            return false
        end
        local sheriffOnMap: boolean = isCharacterOnMap(sheriffRoot)
        if not sheriffOnMap then
            holdAboveMap(character, humanoid, root)
            return false
        end

        if type(state.mm2PerformFling) == "function" then
            if os.clock() - lastSheriffFlingAt < SHERIFF_FLING_COOLDOWN_SECONDS then
                holdAboveMap(character, humanoid, root)
                return true
            end
            flingBusy = true
            lastSheriffFlingAt = os.clock()
            local returnPos: Vector3 = safeAbovePosition
                or (root.Position + Vector3.new(0, ABOVE_MAP_OFFSET, 0))
            task.spawn(function(): ()
                pcall(state.mm2PerformFling, sheriff, {
                    silent = true,
                    duration = 2.6,
                    blocking = true,
                    returnCFrame = CFrame.new(returnPos),
                    shouldStop = function(): boolean
                        if not autoWinActive or not settings.flingSheriffGetGun then
                            return true
                        end
                        if findLocalTool("Gun") ~= nil then
                            return true
                        end
                        if type(findDroppedGun) == "function" and findDroppedGun() ~= nil then
                            return true
                        end
                        return false
                    end,
                })
                lastSheriffFlingAt = os.clock()
                local cNow: Model?, hNow: Humanoid?, rNow: BasePart? = characterParts()
                if cNow and hNow and rNow and autoWinActive then
                    holdAboveMap(cNow, hNow, rNow)
                end
                flingBusy = false
            end)
            return true
        end

        if type(state.mm2FlingStep) == "function" then
            local okStep: boolean, res: any = pcall(
                state.mm2FlingStep,
                character,
                humanoid,
                root,
                sheriff,
                savedCollide,
                savedCustomProps
            )
            if okStep and res == true then
                return true
            end
            holdAboveMap(character, humanoid, root)
            return false
        end

        if services and services.activity then
            pcall(function(): ()
                services.activity.set("fling", true)
            end)
        end
        enableCharacterFlingCollisions(character)
        flingAngle = (flingAngle + 100) % 360
        local phase: number = math.floor(flingAngle / 100) % 4
        local sweepOffset: CFrame = if phase == 0
            then CFrame.new(0, 1.5, 0)
            elseif phase == 1 then CFrame.new(0, -1.5, 0)
            elseif phase == 2 then CFrame.new(2.0, 1.2, -2.0)
            else CFrame.new(-2.0, -1.2, 2.0)
        local sheriffVel: Vector3 = Vector3.zero
        pcall(function(): ()
            sheriffVel = sheriffRoot.AssemblyLinearVelocity
        end)
        local targetCF: CFrame = CFrame.new(sheriffPos + sheriffVel * 0.08)
            * sweepOffset
            * CFrame.Angles(math.rad(flingAngle), math.rad(flingAngle), 0)
        pcall(function(): ()
            if humanoid.Sit then
                humanoid.Sit = false
            end
            humanoid.AutoRotate = false
            root.CFrame = targetCF
            character:PivotTo(targetCF)
            root.AssemblyLinearVelocity = Vector3.new(10000, 12000, 10000)
            root.AssemblyAngularVelocity = Vector3.new(12000, 12000, 12000)
        end)
        return true
    end

    local function autoWinTick(): ()
        if not autoWinActive or flingBusy then
            return
        end
        local character: Model?, humanoid: Humanoid?, root: BasePart? = characterParts()
        if not character or not humanoid or not root or humanoid.Health <= 0 then
            return
        end

        local onMap: boolean, mapRefPos: Vector3? = isCharacterOnMap(root)
        local activeMurderer: Player? = findActiveMurderer()
        if activeMurderer then
            roundSawMurderer = true
        end

        if not onMap then
            if wasOnMap then
                wasOnMap = false
                mapEnteredAt = 0
                sheriffFirstSeenAt = 0
                lastSheriffFlingAt = 0
                safeAbovePosition = nil
                restoreLocalCharacter()
            end

            local roundStillRunning: boolean = type(findMM2Map) == "function"
                and findMM2Map() ~= nil
                and activeMurderer ~= nil
                and (type(isRoundLifecycleActive) ~= "function"
                    or isRoundLifecycleActive() ~= false)

            if not roundStillRunning then
                if participatedInRound and not roundCountedWin and roundSawMurderer then
                    local myRoleNow: any = type(getPlayerRole) == "function"
                        and getPlayerRole(LocalPlayer)
                        or nil
                    if myRoleNow ~= "Dead" then
                        awardRoundWin(roundMyRole)
                    end
                end
                participatedInRound = false
                roundMyRole = nil
                roundSawMurderer = false
                roundCountedWin = false
                flungMurderThisDeath = false
                setStatus("Auto Win: waiting for map")
                return
            end

            -- We are in the lobby while the round is still running on the map
            -- (meaning we died / were killed during the round).
            local myRole: any = type(getPlayerRole) == "function"
                and getPlayerRole(LocalPlayer)
                or nil
            local diedInRound: boolean = participatedInRound or myRole == "Dead"
            if settings.flingMurderIfDead
                and diedInRound
                and not flungMurderThisDeath
                and activeMurderer then
                flungMurderThisDeath = true
                if type(state.mm2PerformFling) == "function" then
                    flingBusy = true
                    setStatus("Auto Win: Flinging Murderer (killed us)")
                    task.spawn(function(): ()
                        pcall(state.mm2PerformFling, activeMurderer, {
                            silent = true,
                            duration = 4.0,
                            blocking = true,
                        })
                        flingBusy = false
                    end)
                    return
                end
            end

            setStatus("Auto Win: waiting in lobby")
            return
        end

        if not wasOnMap or not safeAbovePosition then
            wasOnMap = true
            mapEnteredAt = os.clock()
            sheriffFirstSeenAt = 0
            lastSheriffFlingAt = 0
            participatedInRound = true
            flungMurderThisDeath = false
            local anchor: Vector3 = mapRefPos or root.Position
            safeAbovePosition = anchor + Vector3.new(0, ABOVE_MAP_OFFSET, 0)
        end

        -- Check if the Murderer died while we are alive on the map -> count win!
        if roundSawMurderer and not activeMurderer and not roundCountedWin then
            awardRoundWin(roundMyRole)
        end

        -- 1) Murderer / Knife check: Insta Kill as Murder (Kill All).
        local knife: Tool? = findLocalTool("Knife")
        if knife then
            roundMyRole = "Murderer"
            if settings.instaKillMurder then
                runInstaKillAsMurder(character, humanoid, root, knife)
                setStatus("Auto Win: Insta Kill as Murder")
            else
                holdAboveMap(character, humanoid, root)
                setStatus("Auto Win: safe above map (Murderer)")
            end
            return
        end

        -- 2) Gun check (Sheriff OR Hero OR Innocent who received the Gun!):
        --    Dispara al momento que reciba la pistola con AutoShoot CFrame,
        --    incluso si Fling Sheriff and Get Gun está desactivado y el arma
        --    se recogió con Auto Grab Gun.
        local gun: Tool? = findLocalTool("Gun")
        if gun then
            roundMyRole = "Sheriff"
            if settings.instaKillSheriff then
                runInstaKillAsSheriff(character, humanoid, root, gun)
                setStatus("Auto Win: Insta Kill As Sheriff (CFrame)")
            else
                holdAboveMap(character, humanoid, root)
                setStatus("Auto Win: safe above map (Gun ready)")
            end
            return
        end

        if not roundMyRole then
            local roleNow: any = type(getPlayerRole) == "function"
                and getPlayerRole(LocalPlayer)
                or nil
            if roleNow == "Murderer" then
                roundMyRole = "Murderer"
            elseif roleNow == "Sheriff" or roleNow == "Hero" then
                roundMyRole = "Sheriff"
            else
                roundMyRole = "Innocent"
            end
        end

        -- 3) Dropped gun on the map: grab ONLY via fireTouchInterest (no
        --    risky teleport) if Fling Sheriff and Get Gun is ON or Auto Grab
        --    Gun is enabled.
        local autoGrabExternal: boolean = state.mm2GunAuraEnabled == true
            or state.mm2AutoGetGunEnabled == true
        if settings.flingSheriffGetGun or autoGrabExternal then
            local drop: Instance? = type(findDroppedGun) == "function"
                and findDroppedGun()
                or nil
            if drop then
                local grabbed: boolean = grabDroppedGunTouchOnly(
                    character,
                    humanoid,
                    root,
                    drop
                )
                setStatus("Auto Win: touching dropped gun")
                if grabbed then
                    roundMyRole = "Sheriff"
                    local freshGun: Tool? = findLocalTool("Gun")
                    if freshGun and settings.instaKillSheriff then
                        runInstaKillAsSheriff(character, humanoid, root, freshGun)
                    end
                end
                return
            end
        end

        -- 4) Fling Sheriff and Get Gun while Sheriff is still alive.
        --    Wait for the map and characters to finish loading before flinging
        --    so the local character never gets destabilized on spawn.
        if settings.flingSheriffGetGun then
            local nowClock: number = os.clock()
            local mapElapsed: number = nowClock - mapEnteredAt
            if mapElapsed < MAP_FLING_WARMUP_SECONDS then
                holdAboveMap(character, humanoid, root)
                setStatus("Auto Win: loading map before fling...")
                return
            end
            local sheriff: Player? = findActiveSheriffOrHero()
            if sheriff
                and sheriff ~= LocalPlayer
                and (type(isProtectedTarget) ~= "function" or not isProtectedTarget(sheriff)) then
                if sheriffFirstSeenAt == 0 then
                    sheriffFirstSeenAt = nowClock
                end
                if nowClock - sheriffFirstSeenAt < SHERIFF_READY_DELAY_SECONDS then
                    holdAboveMap(character, humanoid, root)
                    setStatus("Auto Win: waiting for Sheriff to settle...")
                    return
                end
                if flingSheriffStep(character, humanoid, root, sheriff) then
                    setStatus("Auto Win: flinging Sheriff for gun")
                    return
                end
            else
                sheriffFirstSeenAt = 0
            end
        end

        -- 5) Default on map (including pre-round before weapons are given):
        --    Stay safely high above the map where nobody can kill us.
        holdAboveMap(character, humanoid, root)
        setStatus("Auto Win: safe above map")
    end

    local function clearToolConnections(): ()
        for _, conn: RBXScriptConnection in ipairs(toolConnections) do
            pcall(function(): ()
                conn:Disconnect()
            end)
        end
        table.clear(toolConnections)
    end

    local function watchToolContainer(container: Instance?): ()
        if not container
            or (type((container :: any).ChildAdded) ~= "table"
                and typeof((container :: any).ChildAdded) ~= "RBXScriptSignal") then
            return
        end
        pcall(function(): ()
            local conn: RBXScriptConnection = (container :: any).ChildAdded:Connect(
                function(child: Instance): ()
                    if autoWinActive
                        and child
                        and (child.Name == "Gun" or child.Name == "Knife") then
                        autoWinTick()
                    end
                end
            )
            table.insert(toolConnections, conn)
        end)
    end

    local function setupInstantWeaponWatchers(): ()
        clearToolConnections()
        if not LocalPlayer then
            return
        end
        watchToolContainer(LocalPlayer.Character)
        watchToolContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
        pcall(function(): ()
            if LocalPlayer.CharacterAdded then
                table.insert(
                    toolConnections,
                    LocalPlayer.CharacterAdded:Connect(function(newChar: Model): ()
                        watchToolContainer(newChar)
                        watchToolContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
                    end)
                )
            end
            if LocalPlayer.ChildAdded then
                table.insert(
                    toolConnections,
                    LocalPlayer.ChildAdded:Connect(function(child: Instance): ()
                        if child and child:IsA("Backpack") then
                            watchToolContainer(child)
                        end
                    end)
                )
            end
        end)
    end

    local function toggleAutoWin(enabled: boolean): ()
        autoWinActive = enabled == true
        disconnectFeatureConnection("MM2AutoWin")
        clearToolConnections()
        if not enabled then
            wasOnMap = false
            participatedInRound = false
            roundMyRole = nil
            roundSawMurderer = false
            roundCountedWin = false
            flungMurderThisDeath = false
            restoreLocalCharacter()
            safeAbovePosition = nil
            setStatus(nil)
            return
        end
        setupInstantWeaponWatchers()
        featureConnections.MM2AutoWin = TaskManager:Connect(autoWinTick, nil, "MM2 Auto Win")
        autoWinTick()
    end

    AutoWinFeature = createUniversalFeature(
        "Auto Win",
        "Keeps your character safely above the map as soon as you enter the map (even before the round starts) so nobody can kill you, with Insta Kill as Murder, Insta Kill As Sheriff (AutoShoot CFrame), Fling Sheriff and Get Gun, and Fling Murder if Dead.",
        8,
        toggleAutoWin,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoWinFeature = AutoWinFeature

    if type(state.addSectionOption) == "function" then
        state.addSectionOption(AutoWinFeature, "Overlay Info")
    end
    if type(state.addStatOption) == "function" then
        sheriffWinsStat = state.addStatOption(AutoWinFeature, "Sheriff Wins", "0")
        murderWinsStat = state.addStatOption(AutoWinFeature, "Murder Wins", "0")
        innocentWinsStat = state.addStatOption(AutoWinFeature, "Innocent Wins", "0")
    end

    addToggleOption(AutoWinFeature, "Insta Kill as Murder", true,
        function(value: boolean): ()
            settings.instaKillMurder = value == true
        end,
        "Automatically kills all living players as soon as you receive the Knife as Murderer.")

    addToggleOption(AutoWinFeature, "Insta Kill As Sheriff", true,
        function(value: boolean): ()
            settings.instaKillSheriff = value == true
        end,
        "Automatically equips the Gun and shoots the Murderer using AutoShoot CFrame the instant you receive the Gun (as Sheriff or Hero).")

    addToggleOption(AutoWinFeature, "Fling Sheriff and Get Gun", false,
        function(value: boolean): ()
            settings.flingSheriffGetGun = value == true
        end,
        "Safely flies to the Sheriff with Fling without killing yourself, then automatically grabs the dropped gun via TouchInterest once the Sheriff dies and shoots the Murderer.")

    addToggleOption(AutoWinFeature, "Fling Murder if Dead", false,
        function(value: boolean): ()
            settings.flingMurderIfDead = value == true
        end,
        "If the Murderer kills you and sends you to the lobby while the round is still active, automatically flings the Murderer.")

    activeCleanup = function(): ()
        toggleAutoWin(false)
        state.mm2AutoWinFeature = nil
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
