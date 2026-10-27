-- v150 · MM2 Auto Farm, rebuilt from zero against the saved place.
--
-- What the game actually does (TestingStuff / "place, source.rbxlx", placeId
-- 142823291, place version 1447; and the 05-10-2026 .rbxl snapshot):
--
--   * Each pickup is a `Coin_Server` BasePart inside <map>.CoinContainer. It is
--     Anchored, CanCollide=false, CanTouch=true, 1.2 x 2 x 2 studs, carries the
--     `CoinID` attribute (e.g. "Coin") and has its own `TouchInterest`
--     (TouchTransmitter). The visible `CoinVisual` child is tagged CoinVisual.
--     After collection the server sets `Collected = true`; at round end it also
--     sets `RoundEnd` and hides it (Transparency = 1).
--   * No client remote asks for a coin. The remote spy logs contain 234
--     Incoming `CoinCollected` and 21 `CoinsStarted` events, zero outgoing
--     `GetCoin`. Collection is a SERVER `Touched` handler on those anchored,
--     server-owned parts. `firetouchinterest` from the client cannot fire that
--     server handler, so the old instant-pickup pulses could not credit coins.
--   * `CoinsStarted` carries { Coin = { CollectedAmount = 0,
--     CollectionLimit = 50 } }; `CoinCollected` carries
--     ("Coin", currentAmount, limit, { Value = 1 }). `RoundStart` carries the
--     round length and the player/role table. `RoundTimerPart.Time` counts the
--     round down and `MapID` / the CurrentMap tag identify the active map.
--   * Roblox docs: `Humanoid:Move()` is overwritten every frame by the default
--     control script unless it is bound after Character priority, while
--     `Humanoid:MoveTo()` uses WalkToPoint with an 8 s timeout. MM2 uses the
--     stock PlayerModule (ControlsEnable.lua), and the game itself teleports
--     with a single `character:PivotTo` (CharacterClient.lua).
--
-- Therefore this farm only walks. It binds one native `Humanoid:Move` after the
-- default controls, follows real `Coin_Server` positions (optionally with
-- PathfindingService waypoints), overlaps the coin so the server's own Touched
-- handler can pay, and counts ONLY `CoinCollected` events as collected coins.
-- No CFrame per tick, no grown hitbox, no velocity/constraint writers, no
-- firetouchinterest as a substitute for a server touch, no terminal actions on
-- a full bag, and no property is modified that must be restored later.

local Module = {
    Name = "MM2 Auto Farm",
    Events = {},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(_runtime: any): any
    assert(state.mm2Core, "MM2 Auto Farm requires the MM2 core")
    local core: any = state.mm2Core
    local host: any = state.frameworkEnvironment
    local workspace: any = host.workspace
    local LocalPlayer: any = host.LocalPlayer
    local RunService: any = host.RunService
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local getCharacterParts: any = host.getCharacterParts
    local framework: any = state.framework
    local activity: any = services and services.activity
    local clock: () -> number = if type((host :: any).clock) == "function"
        then (host :: any).clock else os.clock

    local gameplay: any = core.mm2GameplayRemotes
    local replicated: any = nil
    local inventory: any = nil
    local pathfinding: any = nil
    pcall(function(): ()
        replicated = game:GetService("ReplicatedStorage")
    end)
    if replicated and type(replicated.FindFirstChild) == "function" then
        pcall(function(): ()
            inventory = replicated:FindFirstChild("Remotes")
                and replicated.Remotes:FindFirstChild("Inventory")
        end)
    end
    pcall(function(): ()
        pathfinding = game:GetService("PathfindingService")
    end)

    local STEP_MIN: number = 0.15
    local STEP_MAX: number = 1
    local CONTACT_RADIUS: number = 2.2
    local CONTACT_VERTICAL: number = 3.2
    local CONTACT_TIMEOUT: number = 2.5
    local STUCK_SECONDS: number = 1.3
    local BLACKLIST_SECONDS: number = 8
    local PATH_INTERVAL: number = 0.7
    local ROAM_INTERVAL: number = 2.5
    local FALL_MARGIN: number = 18
    local RESCUE_COOLDOWN: number = 1.5
    local RENDER_BIND: string = "WurstMM2AutoFarm"

    local settings = {
        navigation = "Pathfinding",
        stepInterval = 0.4,
        jumpForHigh = true,
        roamWhenEmpty = true,
        voidRescue = true,
        stopAtFullBag = true,
    }

    local enabled: boolean = false
    local generation: number = 0
    local signals: {any} = {}
    local renderBound: boolean = false
    local desiredDirection: any = nil

    local currentVisual: any = nil
    local currentServer: any = nil
    local currentPosition: any = nil
    local currentSince: number = 0
    local contactSince: number = 0
    local blacklist: {[any]: number} = {}
    local waypoints: {any} = {}
    local waypointIndex: number = 1
    local pathAt: number = -math.huge
    local pathGeneration: number = 0
    local lastStepAt: number = 0
    local lastProgressAt: number = 0
    local lastProgressPosition: any = nil
    local lastJumpAt: number = -math.huge
    local roamAt: number = -math.huge
    local roamPosition: any = nil
    local spawns: {any} = {}
    local spawnsAt: number = -math.huge

    local bagCurrency: string? = nil
    local bagAmount: number = 0
    local bagLimit: number = 50
    local bagActive: boolean = false
    local persistentCoins: number? = nil
    local previousBagAmount: number = 0
    local coinsConfirmed: number = 0
    local activeSeconds: number = 0

    local safeCFrame: any = nil
    local safeCharacter: any = nil
    local safeY: number? = nil
    local lastRescueAt: number = -math.huge
    local lastRoot: any = nil
    local lastCharacter: any = nil

    local lastStatus: string = ""
    local lastRenderedCoins: string = ""
    local lastRenderedTime: string = ""
    local lastRenderedState: string = ""
    local coinsStat: any = nil
    local timeStat: any = nil
    local stateStat: any = nil

    local function formatTime(totalSeconds: number): string
        local whole: number = math.max(0, math.floor(totalSeconds))
        local hours: number = math.floor(whole / 3600)
        local mins: number = math.floor((whole % 3600) / 60)
        local secs: number = whole % 60
        if hours > 0 then
            return string.format("%02d:%02d:%02d", hours, mins, secs)
        end
        return string.format("%02d:%02d", mins, secs)
    end

    local function setStatus(text: string?): ()
        local value: string = text or ""
        if value == lastStatus then
            return
        end
        lastStatus = value
        local card: any = state.mm2AutoFarmFeature
        if card then
            card:SetStatus(if value == "" then nil else value)
        end
    end

    local function refreshOverlay(): ()
        local coinsText: string = tostring(coinsConfirmed)
        if coinsText ~= lastRenderedCoins then
            lastRenderedCoins = coinsText
            if coinsStat and type(coinsStat.set) == "function" then
                coinsStat.set(coinsText)
            end
        end
        local timeText: string = formatTime(activeSeconds)
        if timeText ~= lastRenderedTime then
            lastRenderedTime = timeText
            if timeStat and type(timeStat.set) == "function" then
                timeStat.set(timeText)
            end
        end
        local short: string = string.match(lastStatus, "^([^%-]+)") or ""
        short = string.match(short, "^%s*(.-)%s*$") or short
        if short ~= lastRenderedState then
            lastRenderedState = short
            if stateStat and type(stateStat.set) == "function" then
                stateStat.set(short)
            end
        end
    end

    local function remote(parent: any, name: string): any
        if not parent or type(parent.FindFirstChild) ~= "function" then
            return nil
        end
        local ok: boolean, found: any = pcall(function(): any
            return parent:FindFirstChild(name)
        end)
        return (ok and found) or nil
    end

    local function connect(signal: any, callback: any): ()
        if not signal or type(signal.Connect) ~= "function" then
            return
        end
        local ok: boolean, connection: any = pcall(function(): any
            return signal:Connect(callback)
        end)
        if ok and connection then
            table.insert(signals, connection)
        end
    end

    local function invalidatePickups(): ()
        if type(state.mm2InvalidateCoinPickups) == "function" then
            pcall(state.mm2InvalidateCoinPickups)
        end
    end

    local function resetRoundMemory(): ()
        generation += 1
        pathGeneration = generation
        currentVisual, currentServer, currentPosition = nil, nil, nil
        contactSince = 0
        waypoints = {}
        waypointIndex = 1
        pathAt = -math.huge
        roamPosition = nil
        spawns = {}
        spawnsAt = -math.huge
        table.clear(blacklist)
        bagActive = false
        bagCurrency = nil
        bagAmount = 0
        previousBagAmount = 0
        bagLimit = 50
        invalidatePickups()
    end

    -- Server events: the only legitimate confirmation that a coin was paid.
    local function onCoinsStarted(data: any): ()
        resetRoundMemory()
        if type(data) ~= "table" then
            return
        end
        for currency, info in pairs(data) do
            if type(info) == "table" then
                bagCurrency = tostring(currency)
                bagAmount = tonumber(info.CollectedAmount) or 0
                bagLimit = tonumber(info.CollectionLimit) or 50
                bagActive = true
                previousBagAmount = bagAmount
                break
            end
        end
        setStatus("Round started · waiting for pickups")
    end

    local function onCoinCollected(currency: any, amount: any, limit: any, _coin: any): ()
        local value: number = tonumber(amount) or bagAmount
        local max: number = tonumber(limit) or bagLimit
        if value > previousBagAmount then
            coinsConfirmed += 1
        end
        previousBagAmount = value
        bagAmount = value
        bagLimit = max
        bagCurrency = if type(currency) == "string" then currency else bagCurrency
        bagActive = true
        if currentVisual then
            blacklist[currentVisual] = clock() + 1
        end
        currentVisual, currentServer, currentPosition = nil, nil, nil
        contactSince = 0
        waypoints = {}
        waypointIndex = 1
        invalidatePickups()
        setStatus(string.format("Collected · bag %d/%d", bagAmount, bagLimit))
    end

    if gameplay then
        connect(remote(gameplay, "CoinsStarted") and gameplay.CoinsStarted.OnClientEvent,
            onCoinsStarted)
        connect(remote(gameplay, "CoinCollected") and gameplay.CoinCollected.OnClientEvent,
            onCoinCollected)
        connect(remote(gameplay, "RoundStart") and gameplay.RoundStart.OnClientEvent,
            function(): () resetRoundMemory() end)
        connect(remote(gameplay, "VictoryScreen") and gameplay.VictoryScreen.OnClientEvent,
            function(): () resetRoundMemory() end)
        connect(remote(gameplay, "RoundEndFade") and gameplay.RoundEndFade.OnClientEvent,
            function(): () resetRoundMemory() end)
        connect(remote(gameplay, "PlayerDataChanged") and gameplay.PlayerDataChanged.OnClientEvent,
            function(data: any): ()
                if type(data) ~= "table" or next(data) == nil then
                    resetRoundMemory()
                end
            end)
    end
    if inventory then
        connect(remote(inventory, "ChangeInventoryItem")
            and inventory.ChangeInventoryItem.OnClientEvent,
            function(category: any, item: any, total: any): ()
                if category == "Materials" and item == "Coins"
                    and type(total) == "number" then
                    persistentCoins = total
                end
            end)
    end

    local function active(name: string): boolean
        return activity ~= nil and type(activity.isActive) == "function"
            and activity.isActive(name) == true
    end

    local function featureEnabled(name: string): boolean
        if not framework or type(framework.GetModule) ~= "function" then
            return false
        end
        local ok: boolean, found: any = pcall(framework.GetModule, framework, name)
        return ok and found ~= nil and found.Enabled == true
    end

    local function roundContext(): string
        local character: any, humanoid: any, root: any = getCharacterParts()
        if not character or not humanoid or not root or humanoid.Health <= 0
            or not root.Parent then
            return "dead"
        end
        if type(core.getRoundPhase) == "function"
            and core.getRoundPhase() == "lobby" then
            return "lobby"
        end
        if type(core.isRoundLifecycleActive) == "function"
            and core.isRoundLifecycleActive() ~= true then
            return "lobby"
        end
        if type(core.findMM2Map) == "function" and not core.findMM2Map() then
            return "lobby"
        end
        local timer: any = workspace and type(workspace.FindFirstChild) == "function"
            and workspace:FindFirstChild("RoundTimerPart") or nil
        if timer and type(timer.GetAttribute) == "function" then
            local remaining: any = timer:GetAttribute("Time")
            if type(remaining) == "number" and remaining <= 0 then
                return "lobby"
            end
        end
        local role: any = type(core.getPlayerRole) == "function"
            and core.getPlayerRole(LocalPlayer) or nil
        if role ~= "Innocent" then
            return "role"
        end
        local physics: any = state.flingPhysics
        if (physics and ((type(physics.isRunning) == "function" and physics.isRunning())
                or (type(physics.isTouchEnabled) == "function" and physics.isTouchEnabled())))
            or active("fling") or active("teleport") or active("ghost")
            or featureEnabled("Fly") then
            return "busy"
        end
        return "active"
    end

    local function contextLabel(context: string): string
        if context == "lobby" then
            return "Waiting · lobby / round over"
        elseif context == "dead" then
            return "Waiting · no living character"
        elseif context == "role" then
            return "Waiting · Innocent role not confirmed"
        elseif context == "busy" then
            return "Paused · another physics feature owns the character"
        end
        return "Farming"
    end

    local function parts(): (any, any, any)
        return getCharacterParts()
    end

    local function unbindMovement(): ()
        if renderBound and RunService
            and type(RunService.UnbindFromRenderStep) == "function" then
            pcall(function(): () RunService:UnbindFromRenderStep(RENDER_BIND) end)
        end
        renderBound = false
        desiredDirection = nil
    end

    local function bindMovement(): ()
        if renderBound or not RunService
            or type(RunService.BindToRenderStep) ~= "function" then
            return
        end
        local priority: number = 201
        pcall(function(): ()
            local value: any = Enum.RenderPriority.Character.Value
            if type(value) == "number" then
                priority = value + 1
            end
        end)
        local ok: boolean = pcall(function(): ()
            RunService:BindToRenderStep(RENDER_BIND, priority, function(): ()
                if not enabled or not desiredDirection then
                    return
                end
                local character: any, humanoid: any, root: any = parts()
                if not humanoid or not root or humanoid.Health <= 0 then
                    return
                end
                pcall(function(): () humanoid:Move(desiredDirection, false) end)
            end)
        end)
        if ok then
            renderBound = true
        end
    end

    -- Fallback actuator when BindToRenderStep is unavailable: MoveTo's 8 s
    -- timeout is refreshed on every step tick (Roblox Humanoid docs).
    local lastMoveToTarget: any = nil
    local function moveToFallback(humanoid: any, position: any): ()
        if not humanoid or type(humanoid.MoveTo) ~= "function" then
            return
        end
        if lastMoveToTarget and position
            and (position - lastMoveToTarget).Magnitude < 0.5 then
            return
        end
        lastMoveToTarget = position
        pcall(function(): () humanoid:MoveTo(position) end)
    end

    local function setDirection(humanoid: any, root: any, position: any): ()
        if not root or not position then
            desiredDirection = nil
            return
        end
        local delta: any = position - root.Position
        local flat: any = Vector3.new(delta.X, 0, delta.Z)
        if flat.Magnitude < 0.12 then
            desiredDirection = Vector3.zero
        else
            desiredDirection = Vector3.new(flat.X / flat.Magnitude, 0,
                flat.Z / flat.Magnitude)
        end
        if not renderBound then
            moveToFallback(humanoid, position)
        end
    end

    local function stopMovement(): ()
        desiredDirection = Vector3.zero
        lastMoveToTarget = nil
        local _, humanoid: any, root: any = parts()
        if humanoid then
            pcall(function(): () humanoid:Move(Vector3.zero, false) end)
            if root then
                moveToFallback(humanoid, root.Position)
            end
        end
    end

    local function pickups(): {any}
        if type(state.mm2CoinPickups) == "function" then
            local ok: boolean, list: any = pcall(state.mm2CoinPickups)
            if ok and type(list) == "table" then
                return list
            end
        end
        -- Fallback: the game's own tag, then the exact spawn part name.
        local out: {any} = {}
        local collection: any = nil
        pcall(function(): () collection = game:GetService("CollectionService") end)
        if collection then
            local okTagged: boolean, tagged: any = pcall(function(): any
                return collection:GetTagged("CoinVisual")
            end)
            if okTagged and type(tagged) == "table" then
                for _, object: any in ipairs(tagged) do
                    table.insert(out, object)
                end
            end
        end
        if #out == 0 and workspace and type(workspace.GetDescendants) == "function" then
            local okScan: boolean, descendants: any = pcall(function(): any
                return workspace:GetDescendants()
            end)
            if okScan and type(descendants) == "table" then
                for _, object: any in ipairs(descendants) do
                    if object.Name == "Coin_Server" then
                        table.insert(out, object)
                    end
                end
            end
        end
        return out
    end

    local function attribute(part: any, name: string): any
        if not part or type(part.GetAttribute) ~= "function" then
            return nil
        end
        local ok: boolean, value: any = pcall(function(): any
            return part:GetAttribute(name)
        end)
        return (ok and value) or nil
    end

    local function serverPartOf(visual: any): any
        if not visual then
            return nil
        end
        if visual.Name == "Coin_Server" then
            return visual
        end
        local parent: any = visual.Parent
        if parent and parent.Name == "Coin_Server" then
            return parent
        end
        return visual
    end

    local function collectable(part: any, now: number): boolean
        if not part or not part.Parent then
            return false
        end
        if attribute(part, "Collected") == true
            or attribute(part, "Delete") == true then
            return false
        end
        if part.CanTouch == false then
            return false
        end
        local expiry: number? = blacklist[part]
        if expiry and now < expiry then
            return false
        end
        local currency: any = attribute(part, "CoinID")
        if bagActive and bagCurrency and currency ~= nil
            and tostring(currency) ~= bagCurrency then
            return false
        end
        return true
    end

    local function chooseTarget(root: any, now: number): boolean
        local bestScore: number = math.huge
        local bestVisual: any = nil
        local bestServer: any = nil
        local bestPosition: any = nil
        for _, visual: any in ipairs(pickups()) do
            if collectable(visual, now) then
                local server: any = serverPartOf(visual)
                local position: any = server and server.Position or visual.Position
                if position and root and root.Position then
                    local dx: number = position.X - root.Position.X
                    local dz: number = position.Z - root.Position.Z
                    local dy: number = math.abs(position.Y - root.Position.Y)
                    if dy <= 12 then
                        local score: number = math.sqrt(dx * dx + dz * dz)
                            + dy * 2.5
                        if score < bestScore then
                            bestScore = score
                            bestVisual = visual
                            bestServer = server
                            bestPosition = position
                        end
                    end
                end
            end
        end
        if not bestVisual then
            currentVisual, currentServer, currentPosition = nil, nil, nil
            contactSince = 0
            waypoints = {}
            waypointIndex = 1
            return false
        end
        if bestVisual ~= currentVisual then
            currentVisual = bestVisual
            currentServer = bestServer
            currentPosition = bestPosition
            currentSince = now
            contactSince = 0
            waypoints = {}
            waypointIndex = 1
            pathAt = -math.huge
            lastProgressAt = now
            lastProgressPosition = root and root.Position or nil
        end
        return true
    end

    local function computePath(rootPosition: any, destination: any, now: number): ()
        if settings.navigation ~= "Pathfinding" or not pathfinding
            or not rootPosition or not destination then
            return
        end
        if now - pathAt < PATH_INTERVAL then
            return
        end
        pathAt = now
        local myGeneration: number = generation
        task.spawn(function(): ()
            local okCreate: boolean, path: any = pcall(function(): any
                return pathfinding:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                })
            end)
            if not okCreate or not path or generation ~= myGeneration then
                return
            end
            local okCompute: boolean = pcall(function(): ()
                path:ComputeAsync(rootPosition, destination)
            end)
            if not okCompute or generation ~= myGeneration then
                return
            end
            local success: any = nil
            pcall(function(): () success = Enum.PathStatus.Success end)
            if success ~= nil and path.Status ~= success then
                return
            end
            local okPoints: boolean, points: any = pcall(function(): any
                return path:GetWaypoints()
            end)
            if okPoints and type(points) == "table" and #points > 0
                and generation == myGeneration then
                waypoints = points
                waypointIndex = math.min(2, #points)
            end
        end)
    end

    local function nextWaypoint(destination: any): any
        if settings.navigation == "Pathfinding" and #waypoints > 0 then
            local index: number = math.clamp(waypointIndex, 1, #waypoints)
            local point: any = waypoints[index]
            if point and point.Position then
                return point.Position
            end
        end
        return destination
    end

    local function refreshSpawns(now: number): ()
        if now - spawnsAt < 5 or type(core.findMM2Map) ~= "function" then
            return
        end
        spawnsAt = now
        spawns = {}
        local map: any = core.findMM2Map()
        local folder: any = map and type(map.FindFirstChild) == "function"
            and map:FindFirstChild("Spawns") or nil
        if folder and type(folder.GetChildren) == "function" then
            local ok: boolean, children: any = pcall(function(): any
                return folder:GetChildren()
            end)
            if ok and type(children) == "table" then
                for _, child: any in ipairs(children) do
                    if child and child.Position then
                        table.insert(spawns, child.Position)
                    end
                end
            end
        end
    end

    local function antiVoidOwnsRescue(): boolean
        return featureEnabled("Anti Void")
    end

    local function forgetSafe(): ()
        safeCFrame = nil
        safeCharacter = nil
        safeY = nil
    end

    local voidTick = function(character: any, humanoid: any, root: any, now: number): ()
        if not settings.voidRescue or antiVoidOwnsRescue() then
            return
        end
        if lastCharacter ~= character or lastRoot ~= root then
            lastCharacter, lastRoot = character, root
            forgetSafe()
        end
        local velocity: any = root.AssemblyLinearVelocity
        local falling: boolean = velocity ~= nil and type(velocity.Y) == "number"
            and velocity.Y < -1
        if not falling and humanoid.FloorMaterial ~= Enum.Material.Air then
            safeCharacter = character
            safeCFrame = root.CFrame
            safeY = root.Position.Y
            return
        end
        if not safeCFrame or safeCharacter ~= character or safeY == nil
            or not falling or now - lastRescueAt < RESCUE_COOLDOWN
            or root.Position.Y > (safeY :: number) - FALL_MARGIN
            or type(character.PivotTo) ~= "function" then
            return
        end
        if workspace and type(workspace.Raycast) == "function" and RaycastParams then
            local params: any = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character}
            params.RespectCanCollide = true
            local ok: boolean, hit: any = pcall(function(): any
                return workspace:Raycast(root.Position,
                    Vector3.new(0, -120, 0), params)
            end)
            if ok and hit and hit.Position then
                return
            end
        end
        lastRescueAt = now
        local destination: any = safeCFrame
        pcall(function(): () character:PivotTo(destination) end)
        pcall(function(): ()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local function farmTick(deltaTime: number): ()
        if not enabled then
            return
        end
        local dt: number = if type(deltaTime) == "number" and deltaTime > 0
            and deltaTime < 1 then deltaTime else 1 / 60
        activeSeconds += dt
        local now: number = clock()
        local character: any, humanoid: any, root: any = parts()
        if not character or not humanoid or not root or humanoid.Health <= 0 then
            stopMovement()
            setStatus("Waiting · no living character")
            refreshOverlay()
            return
        end
        voidTick(character, humanoid, root, now)

        local context: string = roundContext()
        if context ~= "active" then
            stopMovement()
            setStatus(contextLabel(context))
            refreshOverlay()
            return
        end
        if settings.stopAtFullBag and bagAmount >= bagLimit then
            stopMovement()
            setStatus(string.format("Bag full · %d/%d confirmed", bagAmount, bagLimit))
            refreshOverlay()
            return
        end
        if now - lastStepAt < math.clamp(settings.stepInterval, STEP_MIN, STEP_MAX) then
            refreshOverlay()
            return
        end
        lastStepAt = now
        bindMovement()

        if not chooseTarget(root, now) then
            currentVisual = nil
            refreshSpawns(now)
            if settings.roamWhenEmpty and #spawns > 0 then
                if not roamPosition or now - roamAt > ROAM_INTERVAL then
                    roamAt = now
                    roamPosition = spawns[math.random(1, #spawns)]
                end
                setDirection(humanoid, root, roamPosition)
                setStatus("Roaming · no collectable pickup")
            else
                stopMovement()
                setStatus("Waiting · no collectable pickup")
            end
            refreshOverlay()
            return
        end
        roamPosition = nil

        local position: any = currentPosition
        local server: any = currentServer
        if not position or not server or not server.Parent then
            blacklist[currentVisual] = now + BLACKLIST_SECONDS
            invalidatePickups()
            refreshOverlay()
            return
        end

        local dx: number = position.X - root.Position.X
        local dz: number = position.Z - root.Position.Z
        local horizontal: number = math.sqrt(dx * dx + dz * dz)
        local vertical: number = math.abs(position.Y - root.Position.Y)

        if horizontal <= CONTACT_RADIUS and vertical <= CONTACT_VERTICAL then
            -- Stand inside the server pickup volume and let the game's own
            -- Touched handler pay. No local fake touch is counted as a coin.
            desiredDirection = Vector3.zero
            if contactSince == 0 then
                contactSince = now
            elseif now - contactSince > CONTACT_TIMEOUT then
                blacklist[currentVisual] = now + BLACKLIST_SECONDS
                currentVisual, currentServer, currentPosition = nil, nil, nil
                contactSince = 0
                invalidatePickups()
            end
            setStatus(string.format("Collecting · %d/%d · %s",
                bagAmount, bagLimit, tostring(bagCurrency or "Coin")))
            refreshOverlay()
            return
        end
        contactSince = 0

        if now - lastProgressAt > STUCK_SECONDS then
            local moved: number = 0
            if lastProgressPosition then
                local px: number = root.Position.X - lastProgressPosition.X
                local pz: number = root.Position.Z - lastProgressPosition.Z
                moved = math.sqrt(px * px + pz * pz)
            end
            if moved < 0.6 and horizontal > 3 then
                blacklist[currentVisual] = now + BLACKLIST_SECONDS
                currentVisual, currentServer, currentPosition = nil, nil, nil
                waypoints = {}
                waypointIndex = 1
                invalidatePickups()
                setStatus("Skipped an unreachable pickup")
                refreshOverlay()
                return
            end
            lastProgressAt = now
            lastProgressPosition = root.Position
        end

        computePath(root.Position, position, now)
        local waypoint: any = nextWaypoint(position)
        if settings.navigation == "Pathfinding" and #waypoints > 0
            and waypoint and waypoint ~= position then
            local wx: number = waypoint.X - root.Position.X
            local wz: number = waypoint.Z - root.Position.Z
            if math.sqrt(wx * wx + wz * wz) < 2.2 and waypointIndex < #waypoints then
                waypointIndex += 1
                waypoint = nextWaypoint(position)
            end
        end
        setDirection(humanoid, root, waypoint)

        if settings.jumpForHigh and position.Y - root.Position.Y > 2.5
            and position.Y - root.Position.Y < 8
            and now - lastJumpAt > 0.8 then
            lastJumpAt = now
            pcall(function(): () humanoid.Jump = true end)
        end
        setStatus(string.format("Farming · %s · %d/%d",
            settings.navigation, bagAmount, bagLimit))
        refreshOverlay()
    end

    local function release(): ()
        enabled = false
        generation += 1
        pathGeneration = generation
        disconnectFeatureConnection("MM2AutoFarmTick")
        for _, connection: any in ipairs(signals) do
            if type(connection) == "table" and type(connection.Disconnect) == "function" then
                pcall(function(): () connection:Disconnect() end)
            end
        end
        table.clear(signals)
        stopMovement()
        unbindMovement()
        currentVisual, currentServer, currentPosition = nil, nil, nil
        waypoints = {}
        waypointIndex = 1
        table.clear(blacklist)
        forgetSafe()
        setStatus(nil)
    end

    local function toggleAutoFarm(value: boolean): ()
        if value == true then
            if enabled then
                return
            end
            enabled = true
            generation += 1
            lastStepAt = 0
            lastProgressAt = clock()
            lastProgressPosition = nil
            -- Only one owner of the frame tick, whatever the saved state was.
            disconnectFeatureConnection("MM2AutoFarmTick")
            featureConnections.MM2AutoFarmTick = TaskManager:Connect(farmTick)
            bindMovement()
            setStatus("Starting · waiting for round context")
            farmTick(1 / 60)
        else
            release()
        end
    end

    local AutoFarmFeature: any = host.createUniversalFeature(
        "Auto Farm",
        "Physically walks to real Coin_Server pickups and counts only server-confirmed coins",
        6,
        toggleAutoFarm,
        {
            categoryName = "Utilities",
            parent = MM2Scroll,
            registry = mm2Features,
            -- Moving the character is always an explicit per-session choice.
            restore = false,
        }
    )
    state.mm2AutoFarmFeature = AutoFarmFeature

    if type(state.addSectionOption) == "function" then
        state.addSectionOption(AutoFarmFeature, "Overlay Info")
    end
    if type(state.addStatOption) == "function" then
        coinsStat = state.addStatOption(AutoFarmFeature, "Coins Collected", "0")
        timeStat = state.addStatOption(AutoFarmFeature, "Time", "00:00")
        stateStat = state.addStatOption(AutoFarmFeature, "State", "Idle")
    end

    host.addCycleOption(AutoFarmFeature, "Navigation",
        {"Pathfinding", "Direct"}, 1,
        function(value: string): ()
            settings.navigation = value
            waypoints = {}
            waypointIndex = 1
            pathAt = -math.huge
        end,
        "Pathfinding follows real navigation waypoints; Direct walks straight to the pickup.")
    host.addNumberOption(AutoFarmFeature, "Step interval", 0.4, 0.15, 1,
        function(value: number): ()
            settings.stepInterval = math.clamp(tonumber(value) or 0.4,
                STEP_MIN, STEP_MAX)
        end,
        "How often the farm re-evaluates its target and refreshes MoveTo.", 0.05)
    host.addToggleOption(AutoFarmFeature, "Jump for high pickups", true,
        function(value: boolean): () settings.jumpForHigh = value == true end,
        "Uses the native Humanoid.Jump for pickups a few studs above the floor.")
    host.addToggleOption(AutoFarmFeature, "Roam when empty", true,
        function(value: boolean): () settings.roamWhenEmpty = value == true end,
        "Walks to a real map spawn while no collectable pickup exists.")
    host.addToggleOption(AutoFarmFeature, "Void rescue", true,
        function(value: boolean): () settings.voidRescue = value == true end,
        "One bounded teleport back to the last grounded position during a fall. Yields to the Anti Void card.")
    host.addToggleOption(AutoFarmFeature, "Stop at full bag", true,
        function(value: boolean): () settings.stopAtFullBag = value == true end,
        "Stops walking when CoinCollected reports the server's collection limit.")
    host.addInformationOption(AutoFarmFeature,
        "MM2 credits coins from a server Touched event on Coin_Server. The farm "
            .. "walks into that volume; a local firetouchinterest is not a "
            .. "confirmed coin. Only Innocent, active rounds, living character.")

    -- Read-only state for offline suites and the debug surfaces.
    state.mm2AutoFarmSnapshot = function(): any
        return {
            enabled = enabled,
            navigation = settings.navigation,
            coinsConfirmed = coinsConfirmed,
            bagAmount = bagAmount,
            bagLimit = bagLimit,
            bagCurrency = bagCurrency,
            bagActive = bagActive,
            activeSeconds = activeSeconds,
            status = lastStatus,
            persistentCoins = persistentCoins,
            targetName = currentServer and tostring(currentServer.Name) or nil,
        }
    end

    activeCleanup = function(): ()
        release()
        state.mm2AutoFarmFeature = nil
        state.mm2AutoFarmSnapshot = nil
    end
    Module.Initialized = true
    return AutoFarmFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
