local Module = {
    Name = "MM2 Auto Farm",
    PlaceId = 142823291,
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
    local getEstimatedLatency: any = core.getEstimatedLatency
    local getGunOriginCFrame: any = core.getGunOriginCFrame

    local settings = {
        speed = 16,
        resetOnFull = true,
        flingMurder = false,
        flingSheriff = false,
        grabGunShoot = false,
        killAllOnFull = false,
    }

    -- Travel height under the coin, then the collect height. The
    -- place data is exact: Coin_Server (the part that pays) is
    -- 1.2 x 2 x 2, centred on the coin, so its touch volume reaches
    -- only 1 stud above and below the coin centre. The old ride
    -- height of 3.1 put the whole body ~1 stud UNDER that volume:
    -- the farm parked beneath coin after coin and touched nothing
    -- (the "only 2-3 coins, by luck" bug). Travel stays low and
    -- hidden; on arrival the body rises to COLLECT_UNDER, where the
    -- root (2 tall) overlaps the volume by a full stud.
    local TRAVEL_UNDER: number = 2.4
    local COLLECT_UNDER: number = 0.8
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

    local function rootOf(player: Player?): BasePart?
        local character: Model? = player and player.Character
        if not character then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart") :: BasePart?
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
    local function killAll(): ()
        if type(getPlayerRole) ~= "function"
            or getPlayerRole(LocalPlayer) ~= "Murderer" then
            notify("Auto Farm: Kill All only works as the Murderer.")
            return
        end
        local character: Model?, humanoid: Humanoid?, myRoot: BasePart? =
            characterParts()
        if not character or not humanoid or not myRoot then
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
            task.wait(0.3)
        end
        if knife.Parent ~= character then
            return
        end
        local victims: {BasePart} = {}
        for _, player: Player in ipairs(Players:GetPlayers()) do
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
        if #victims == 0 then
            return
        end
        task.wait(0.15)
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
            if handleTouched and handleTouched:IsA("RemoteEvent") then
                pcall(function(): ()
                    (handleTouched :: RemoteEvent):FireServer(victimRoot)
                end)
            end
            task.wait(0.05)
        end
        task.delay(0.5, function(): ()
            for _, victimRoot: BasePart in ipairs(victims) do
                pcall(function(): ()
                    victimRoot.Anchored = false
                end)
            end
        end)
        notify("Auto Farm: Kill All fired at " .. #victims .. " players.")
    end

    -- Compact spin fling: park on the target spinning hard for a
    -- couple of seconds; contact physics does the rest.
    local function flingPlayer(target: Player?): ()
        if not target then
            return
        end
        local _, _, myRoot: BasePart? = characterParts()
        if not myRoot then
            return
        end
        local saved: CFrame = myRoot.CFrame
        local startedAt: number = os.clock()
        while os.clock() - startedAt < 2.2 do
            local targetRoot: BasePart? = rootOf(target)
            if not targetRoot then
                break
            end
            pcall(function(): ()
                myRoot.CFrame = targetRoot.CFrame
                myRoot.AssemblyAngularVelocity = Vector3.new(0, 400, 0)
                myRoot.AssemblyLinearVelocity = Vector3.zero
            end)
            task.wait()
        end
        pcall(function(): ()
            myRoot.AssemblyAngularVelocity = Vector3.zero
            myRoot.CFrame = saved
        end)
    end

    -- Auto grab gun + auto shoot: equip the dropped sheriff gun and
    -- fire one predicted shot at the murderer (same gun remote and
    -- prediction the Shoot module authors).
    local lastShotAt: number = 0
    local function shootMurderer(murderer: Player): ()
        if os.clock() - lastShotAt < 1.1 then
            return
        end
        local character: Model?, humanoid: Humanoid? = characterParts()
        if not character or not humanoid then
            return
        end
        local gun: Tool? = nil
        if type(getPlayerWeapon) == "function" then
            gun = getPlayerWeapon(LocalPlayer, "Gun")
        end
        if not gun then
            return
        end
        if gun.Parent ~= character then
            pcall(function(): ()
                humanoid:EquipTool(gun :: Tool)
            end)
            task.wait(0.2)
        end
        if gun.Parent ~= character
            or gun:GetAttribute("Reloading") == true
            or gun:GetAttribute("IsReloading") == true then
            return
        end
        local remote: Instance? = gun:FindFirstChild("Shoot")
        if not remote or not remote:IsA("RemoteEvent") then
            return
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
            return
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
                return
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
    end

    local function toggleAutoFarm(enabled: boolean): ()
        disconnectFeatureConnection("MM2AutoFarmTick")
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

        local bagAmount: number = 0
        local bagLimit: number = 0
        local busy: boolean = false
        local fullHandled: boolean = false
        local scanCache: {Instance} = {}
        local scanAt: number = 0
        local stuckPart: Instance? = nil
        local stuckSince: number = 0
        local lastTouchPulse: number = 0
        local blacklist: {[Instance]: number} = {}

        -- Engagement state. The farm touches the character ONLY while
        -- engaged (a target exists). In the lobby, between rounds, or
        -- with no coins out, the character is left completely alone --
        -- that was the camera glitch: noclip + prone applied in the
        -- lobby made the character fall through the floor.
        local engaged: boolean = false
        local engagedCharacter: Model? = nil
        local homeCFrame: CFrame? = nil
        local savedCollide: {[Instance]: boolean} = {}

        local function yawOf(frame: CFrame): number
            local look: Vector3 = frame.LookVector
            return math.atan2(-look.X, -look.Z)
        end

        local function restoreCharacter(returnHome: boolean): ()
            local character: Model?, humanoid: Humanoid?, root: BasePart? =
                characterParts()
            for part: Instance, was: boolean in pairs(savedCollide) do
                pcall(function(): ()
                    (part :: BasePart).CanCollide = was
                end)
            end
            table.clear(savedCollide)
            if humanoid then
                pcall(function(): ()
                    humanoid.PlatformStand = false
                    humanoid.AutoRotate = true
                    if humanoid.Sit then
                        humanoid.Sit = false
                    end
                    humanoid:ChangeState(Enum.HumanoidStateType.Running)
                end)
            end
            if root then
                pcall(function(): ()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    if returnHome and homeCFrame then
                        -- Back where the farm found us, upright: only
                        -- the position and yaw survive, never the
                        -- face-planted pitch.
                        root.CFrame = CFrame.new(homeCFrame.Position)
                            * CFrame.Angles(0, yawOf(homeCFrame), 0)
                    else
                        -- Stand back up exactly where we are.
                        root.CFrame = CFrame.new(root.Position)
                            * CFrame.Angles(0, yawOf(root.CFrame), 0)
                    end
                end)
            end
            engaged = false
            engagedCharacter = nil
            homeCFrame = nil
        end

        local function engage(
            character: Model,
            humanoid: Humanoid,
            root: BasePart
        ): ()
            if engagedCharacter ~= character then
                -- New body (respawn): the previous restore belongs to
                -- the old character; remember this one's start point.
                restoreCharacter(false)
                homeCFrame = root.CFrame
                engagedCharacter = character
            end
            if not engaged then
                engaged = true
                -- Lie face-down ONCE. The rotation is not rewritten
                -- every frame -- that fight is what glitched the
                -- camera. Movement below is pure velocity.
                pcall(function(): ()
                    root.CFrame = CFrame.new(root.Position)
                        * CFrame.Angles(0, yawOf(root.CFrame), 0)
                        * CFrame.Angles(math.rad(90), 0, 0)
                    humanoid.PlatformStand = true
                    humanoid.AutoRotate = false
                end)
            end
            -- NoClip: every character part (tools included) is forced
            -- non-collidable each tick, so the flight never bumps a
            -- platform edge on the way to a coin.
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

        -- Fly the root at a destination with PHYSICS velocity. The
        -- v82 build wrote CFrame positions every tick and zeroed the
        -- velocity: to the server that is a stream of teleports, and
        -- MM2 answers "Invalid position" (kick 267). A velocity the
        -- physics engine integrates replicates as ordinary movement.
        -- Speed is the Farm Speed slider -- start low, raise it until
        -- just before the server complains, that point is yours.
        local function moveTowards(
            root: BasePart,
            destination: Vector3,
            deltaTime: number
        ): number
            local delta: Vector3 = destination - root.Position
            local distance: number = delta.Magnitude
            if distance < 0.05 then
                pcall(function(): ()
                    root.AssemblyLinearVelocity = Vector3.zero
                end)
                return 0
            end
            local speed: number = math.clamp(settings.speed, 5, 60)
            if distance <= math.max(0.5, speed * deltaTime) then
                -- Final approach inside one step: land on the point
                -- and stop, instead of orbiting it at full speed.
                pcall(function(): ()
                    root.CFrame = CFrame.new(destination)
                        * (root.CFrame - root.CFrame.Position)
                    root.AssemblyLinearVelocity = Vector3.zero
                end)
                return 0
            end
            pcall(function(): ()
                root.AssemblyLinearVelocity = delta.Unit * speed
                root.AssemblyAngularVelocity = Vector3.zero
            end)
            return distance
        end

        -- The full-bag sequence, in the user's order: Kill All,
        -- reset, then the post-reset flings. Runs once per fill.
        local function runFullSequence(): ()
            busy = true
            local ok: boolean, err: any = pcall(function(): ()
                if settings.killAllOnFull then
                    killAll()
                    task.wait(0.4)
                end
                if settings.resetOnFull then
                    local oldCharacter: Model? = LocalPlayer.Character
                    local _, humanoid: Humanoid? = characterParts()
                    if humanoid then
                        pcall(function(): ()
                            humanoid.Health = 0
                        end)
                    end
                    -- Wait for the respawned character.
                    local deadline: number = os.clock() + 10
                    while os.clock() < deadline do
                        local character: Model?, newHumanoid: Humanoid?,
                            newRoot: BasePart? = characterParts()
                        if character and character ~= oldCharacter
                            and newHumanoid and newHumanoid.Health > 0
                            and newRoot then
                            break
                        end
                        task.wait(0.25)
                    end
                    task.wait(0.6)
                    if settings.flingMurder
                        and type(findMurderer) == "function" then
                        flingPlayer(findMurderer())
                    end
                    if settings.flingSheriff
                        and type(findSheriff) == "function" then
                        flingPlayer(findSheriff())
                    end
                end
            end)
            if not ok then
                warn("Auto Farm full-bag sequence failed: " .. tostring(err))
            end
            bagAmount = 0
            fullHandled = false
            busy = false
        end

        local remotes: any = core.mm2GameplayRemotes
        local collected: Instance? = remotes
            and remotes:FindFirstChild("CoinCollected")
        if collected and collected:IsA("RemoteEvent") then
            featureConnections.MM2AutoFarmCoinCollected =
                (collected :: any).OnClientEvent:Connect(
                    function(_bag: any, amount: any, limit: any): ()
                        if type(amount) == "number" then
                            bagAmount = amount
                        end
                        if type(limit) == "number" and limit > 0 then
                            bagLimit = limit
                        end
                        if bagLimit > 0 and bagAmount < bagLimit then
                            fullHandled = false
                        end
                    end
                )
        end

        featureConnections.MM2AutoFarmTick = TaskManager:Connect(
            function(deltaTime: number): ()
                if busy then
                    return
                end
                -- Full bag: run the sequence once, then keep farming.
                if bagLimit > 0 and bagAmount >= bagLimit
                    and not fullHandled
                    and (settings.killAllOnFull or settings.resetOnFull) then
                    fullHandled = true
                    restoreCharacter(false)
                    task.spawn(runFullSequence)
                    return
                end
                local character: Model?, humanoid: Humanoid?,
                    root: BasePart? = characterParts()
                if not character or not humanoid or not root
                    or humanoid.Health <= 0 then
                    return
                end

                -- Gun first: grab the dropped gun, then shoot the
                -- murderer with it; farming resumes afterwards.
                if settings.grabGunShoot then
                    local gun: Tool? = nil
                    if type(getPlayerWeapon) == "function" then
                        gun = getPlayerWeapon(LocalPlayer, "Gun")
                    end
                    if gun then
                        local murderer: Player? = nil
                        if type(findMurderer) == "function" then
                            murderer = findMurderer()
                        end
                        if murderer
                            and (type(isPlayerAlive) ~= "function"
                                or isPlayerAlive(murderer)) then
                            busy = true
                            task.spawn(function(): ()
                                pcall(shootMurderer, murderer)
                                busy = false
                            end)
                        end
                    elseif type(findDroppedGun) == "function" then
                        local drop: Instance? = findDroppedGun()
                        if drop then
                            local dropPosition: Vector3? = nil
                            pcall(function(): ()
                                if drop:IsA("BasePart") then
                                    dropPosition = (drop :: BasePart).Position
                                elseif drop:IsA("Model") then
                                    dropPosition = (drop :: Model):GetPivot().Position
                                end
                            end)
                            if dropPosition then
                                engage(character, humanoid, root)
                                moveTowards(
                                    root,
                                    (dropPosition :: Vector3)
                                        + Vector3.new(0, 1, 0),
                                    deltaTime
                                )
                                setStatus("Auto Farm: going for the dropped gun…")
                                return
                            end
                        end
                    end
                end

                -- Nearest pickup, from Coin ESP's own detection.
                if os.clock() - scanAt > 0.4 then
                    scanAt = os.clock()
                    scanCache = coinPickups()
                end
                local now: number = os.clock()
                local nearest: Instance? = nil
                local nearestPosition: Vector3? = nil
                local nearestDistance: number = math.huge
                for _, part: Instance in ipairs(scanCache) do
                    if part.Parent
                        and (not blacklist[part] or blacklist[part] < now) then
                        local position: Vector3? = nil
                        pcall(function(): ()
                            position = (part :: BasePart).Position
                        end)
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
                    -- Nothing to collect (lobby, intermission, round
                    -- over): hands off the character entirely.
                    if engaged then
                        restoreCharacter(false)
                    end
                    setStatus(string.format(
                        "Auto Farm: waiting for coins - bag %d/%d - speed %d u/s - ping %dms",
                        bagAmount, bagLimit,
                        math.round(math.clamp(settings.speed, 5, 60)),
                        pingMillis()
                    ))
                    stuckPart = nil
                    return
                end
                engage(character, humanoid, root)
                -- Two phases: fly low to below the coin, then rise
                -- into the touch volume and stay there until it pays.
                local coinPosition: Vector3 = nearestPosition :: Vector3
                local flatDelta: Vector3 = coinPosition - root.Position
                local horizontal: number =
                    Vector3.new(flatDelta.X, 0, flatDelta.Z).Magnitude
                local under: number =
                    horizontal > 1.6 and TRAVEL_UNDER or COLLECT_UNDER
                local destination: Vector3 =
                    coinPosition + Vector3.new(0, -under, 0)
                local remaining: number =
                    moveTowards(root, destination, deltaTime)
                if under == COLLECT_UNDER and remaining < 1.2 then
                    -- Belt and braces: some builds only pay on a
                    -- physics Touched, and a fully NoClipped body can
                    -- miss that pairing. Pulse the touch directly
                    -- against the Coin_Server part, like the farm in
                    -- YARHM did, until the coin is gone.
                    if now - lastTouchPulse > 0.25 then
                        lastTouchPulse = now
                        local touchPart: Instance? = nearest
                        if nearest.Name ~= "Coin_Server" then
                            local parent: Instance? = nearest.Parent
                            if parent and parent:IsA("BasePart") then
                                touchPart = parent
                            end
                        end
                        if type(state.fireTouchInterest) == "function"
                            and touchPart then
                            pcall(state.fireTouchInterest, root, touchPart, 0)
                            pcall(state.fireTouchInterest, root, touchPart, 1)
                        end
                    end
                end
                setStatus(string.format(
                    "Auto Farm: %d coins - bag %d/%d - speed %d u/s - ping %dms",
                    #scanCache, bagAmount, bagLimit,
                    math.round(math.clamp(settings.speed, 5, 60)),
                    pingMillis()
                ))
                if remaining < 1.2 then
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
                restoreCharacter(true)
            end,
        }
    end

    local AutoFarmFeature: any = createUniversalFeature(
        "Auto Farm",
        "Lies prone under the map and flies (velocity, NoClip) to the nearest coins at your Farm Speed, with full-bag actions.",
        6,
        toggleAutoFarm,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoFarmFeature = AutoFarmFeature

    addNumberOption(AutoFarmFeature, "Farm Speed", 16, 5, 60,
        function(value: number): ()
            settings.speed = value
        end, "Studs per second. If the server kicks you (Invalid position), lower it; raise it slowly to find your fastest safe speed.", 1)
    addToggleOption(AutoFarmFeature, "Reset When Full Coin Bag", true,
        function(value: boolean): ()
            settings.resetOnFull = value
        end, "Reset the character as soon as the coin bag fills.")
    addToggleOption(AutoFarmFeature, "Fling Murder after reset", false,
        function(value: boolean): ()
            settings.flingMurder = value
        end, "After the full-bag reset respawns you, fling the Murderer.")
    addToggleOption(AutoFarmFeature, "Fling Sheriff after reset", false,
        function(value: boolean): ()
            settings.flingSheriff = value
        end, "After the full-bag reset respawns you, fling the Sheriff.")
    addToggleOption(AutoFarmFeature, "Auto Grab gun and Shoot", false,
        function(value: boolean): ()
            settings.grabGunShoot = value
        end, "Grab the dropped sheriff gun when it appears and shoot the Murderer with it.")
    addToggleOption(AutoFarmFeature, "Auto Kill All When full coin bag", false,
        function(value: boolean): ()
            settings.killAllOnFull = value
        end, "As Murderer, when the bag fills: pull everyone in front of you and slash (YARHM Kill All).")
    addInformationOption(
        AutoFarmFeature,
        "Movement is by physics velocity (never position teleports) with NoClip on the whole character, face-down under the floor to the nearest pickup Coin ESP sees. If you get kicked for Invalid position, lower Farm Speed and raise it little by little - the safe limit depends on your ping and the map. Turning it off restores collisions and returns you upright to where you started."
    )

    activeCleanup = function(): ()
        state.mm2AutoFarmFeature = nil
        toggleAutoFarm(false)
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
