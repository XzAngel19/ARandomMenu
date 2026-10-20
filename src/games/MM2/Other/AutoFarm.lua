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
        resetOnFull = true,
        flingMurder = false,
        flingSheriff = false,
        grabGunShoot = false,
        killAllOnFull = false,
    }

    -- How far under the coin the root rides: close enough that the
    -- body overlaps the Coin_Server touch volume, low enough that the
    -- character lies hidden under the floor.
    local UNDER_OFFSET: number = 3.1
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

    -- Maximum speed the replication can plausibly follow, derived
    -- from the measured round trip: with a low ping the server sees
    -- frequent position updates and longer steps stay legal; as the
    -- ping grows the step shrinks so the server never receives a
    -- jump it would reject (and bounce / kick for). Automatic: the
    -- status line shows the live values it computed.
    local function safeSpeed(): (number, number)
        local ping: number = 0.08
        if type(getEstimatedLatency) == "function" then
            local ok: boolean, value: any = pcall(getEstimatedLatency)
            if ok and type(value) == "number" and value == value then
                ping = math.clamp(value, 0.02, 0.6)
            end
        end
        local speed: number = math.clamp(9.0 / ping, 45, 150)
        return speed, ping
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
        local blacklist: {[Instance]: number} = {}
        local savedCollide: {[Instance]: boolean} = {}
        local collideCharacter: Model? = nil

        local function applyProne(character: Model): ()
            if collideCharacter == character then
                return
            end
            for part: Instance, was: boolean in pairs(savedCollide) do
                pcall(function(): ()
                    (part :: BasePart).CanCollide = was
                end)
            end
            table.clear(savedCollide)
            collideCharacter = character
            for _, object: Instance in ipairs(character:GetDescendants()) do
                if object:IsA("BasePart") then
                    savedCollide[object] = (object :: BasePart).CanCollide
                    pcall(function(): ()
                        (object :: BasePart).CanCollide = false
                    end)
                end
            end
        end

        local function restoreProne(): ()
            for part: Instance, was: boolean in pairs(savedCollide) do
                pcall(function(): ()
                    (part :: BasePart).CanCollide = was
                end)
            end
            table.clear(savedCollide)
            collideCharacter = nil
        end

        -- Step the root towards a point at the ping-safe speed. The
        -- step is capped per tick, so even a frame hitch cannot turn
        -- into a server-rejected teleport.
        local function moveTowards(
            root: BasePart,
            destination: Vector3,
            deltaTime: number,
            lying: boolean
        ): number
            local speed: number = safeSpeed()
            local delta: Vector3 = destination - root.Position
            local distance: number = delta.Magnitude
            if distance < 0.05 then
                return distance
            end
            local step: number = math.min(distance, speed * deltaTime)
            local newPosition: Vector3 =
                root.Position + delta.Unit * step
            local frame: CFrame
            local flat: Vector3 = Vector3.new(delta.X, 0, delta.Z)
            if flat.Magnitude > 0.05 then
                frame = CFrame.lookAt(newPosition, newPosition + flat)
            else
                frame = CFrame.new(newPosition) * root.CFrame.Rotation
            end
            if lying then
                -- Face-planted: the whole character lies flat.
                frame = frame * CFrame.Angles(math.rad(90), 0, 0)
            end
            pcall(function(): ()
                root.CFrame = frame
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
            return distance - step
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
                    task.spawn(runFullSequence)
                    return
                end
                local character: Model?, humanoid: Humanoid?,
                    root: BasePart? = characterParts()
                if not character or not humanoid or not root
                    or humanoid.Health <= 0 then
                    return
                end
                applyProne(character)
                pcall(function(): ()
                    humanoid.AutoRotate = false
                end)

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
                                moveTowards(
                                    root,
                                    (dropPosition :: Vector3)
                                        + Vector3.new(0, 1, 0),
                                    deltaTime,
                                    false
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
                local speed: number, ping: number = safeSpeed()
                if not nearest or not nearestPosition then
                    setStatus(string.format(
                        "Auto Farm: waiting for coins · bag %d/%d · speed %d u/s · ping %dms",
                        bagAmount, bagLimit, math.round(speed),
                        math.round(ping * 1000)
                    ))
                    stuckPart = nil
                    return
                end
                local destination: Vector3 =
                    (nearestPosition :: Vector3)
                    + Vector3.new(0, -UNDER_OFFSET, 0)
                local remaining: number =
                    moveTowards(root, destination, deltaTime, true)
                setStatus(string.format(
                    "Auto Farm: %d coins · bag %d/%d · speed %d u/s · ping %dms",
                    #scanCache, bagAmount, bagLimit, math.round(speed),
                    math.round(ping * 1000)
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

        -- Remember to restore collisions when the feature turns off.
        featureConnections.MM2AutoFarmRestore = {
            Disconnect = function(): ()
                restoreProne()
                local _, humanoid: Humanoid? = characterParts()
                if humanoid then
                    pcall(function(): ()
                        humanoid.AutoRotate = true
                    end)
                end
            end,
        }
    end

    local AutoFarmFeature: any = createUniversalFeature(
        "Auto Farm",
        "Lies prone under the map and collects the nearest coins (Coin ESP detection) at a ping-safe speed, with full-bag actions.",
        6,
        toggleAutoFarm,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    state.mm2AutoFarmFeature = AutoFarmFeature

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
        "Movement is automatic: the character rides face-down under the floor to the nearest pickup Coin ESP sees. The top speed is computed from your live ping (shown in the status), so the server never receives a position jump it would reject. A coin that does not collect within a second is skipped for a few seconds."
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
