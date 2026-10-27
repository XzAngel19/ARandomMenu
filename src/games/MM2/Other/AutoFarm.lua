-- v151 · MM2 Auto Farm: "Below Map" by default, manual control preserved.
--
-- Live feedback on v150: the farm did not move the character and, while ON,
-- stole all user controls. Causes found in that build:
--   * A permanent render-step binding ran after the default controls EVERY
--     frame, even when there was no target, and wrote a zero-move command.
--   * The old route solver produced no usable path on MM2's `GlitchProof`
--     multi-level maps, so the actuator never received a direction.
--   * `roundContext()` demanded a confirmed `Innocent` role; if MM2 did not
--     publish the role early enough, the farm stayed "Waiting" forever.
--
-- v151 removes all of those. The default mode is called `Below Map`: the
-- character is parked under the real `Coin_Server` part, then its whole model
-- is pivoted into the coin's physical volume from below. A bounded contact
-- refresh keeps the root inside the server pickup while waiting for the real
-- `CoinCollected` event. `state.fireTouchInterest` is only an optional local
-- nudge after that physical overlap; it is NEVER counted as a coin.
--
-- There is no RenderStep binding and no `Humanoid:Move` writer. `Direct` mode
-- uses native `Humanoid:MoveTo` refreshed on the shared Heartbeat. In Below
-- Map, WASD/jump input pauses farm placements for 1.2 s, so the user keeps
-- manual control. OFF cancels the native MoveTo and leaves the default
-- PlayerModule untouched. No hitbox resize, no velocity constraint, no
-- per-frame CFrame writer, no pathfinding and no fake coin counter.
--
-- Place evidence remains the one recorded in docs/FIXES-v150.md:
-- `Coin_Server` is anchored, CanTouch=true, CanCollide=false, 1.2x2x2, has a
-- TouchInterest and pays only through the server's own Touched handler.
-- `CoinsStarted` / `CoinCollected` are the only payment confirmations.

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
    pcall(function(): ()
        replicated = game:GetService("ReplicatedStorage")
    end)
    if replicated and type(replicated.FindFirstChild) == "function" then
        pcall(function(): ()
            inventory = replicated:FindFirstChild("Remotes")
                and replicated.Remotes:FindFirstChild("Inventory")
        end)
    end

    local STEP_MIN: number = 0.1
    local STEP_MAX: number = 0.6
    local BELOW_OFFSET: number = 4
    local CONTACT_OFFSET: number = 0.6
    local PARK_DWELL: number = 0.08
    local CONTACT_REFRESH: number = 0.12
    local CONTACT_TIMEOUT: number = 1.6
    local BLACKLIST_SECONDS: number = 8
    local DIRECT_CONTACT_RADIUS: number = 2.2
    local DIRECT_CONTACT_VERTICAL: number = 3.2
    local DIRECT_CONTACT_TIMEOUT: number = 2.5
    local MANUAL_PAUSE: number = 1.2
    local FALL_MARGIN: number = 18
    local RESCUE_COOLDOWN: number = 1.5

    local settings = {
        mode = "Below Map",
        stepInterval = 0.18,
        jumpForHigh = true,
        roamWhenEmpty = true,
        voidRescue = true,
        stopAtFullBag = true,
        manualOverride = true,
    }

    local enabled: boolean = false
    local generation: number = 0
    local signals: {any} = {}
    local lastStepAt: number = 0
    local manualUntil: number = -math.huge
    local lastMoveToTarget: any = nil
    local lastJumpAt: number = -math.huge
    local lastPlacedAt: number = -math.huge
    local lastContactRefreshAt: number = -math.huge

    local pickupCache: {any} = {}
    local pickupCacheAt: number = -math.huge
    local currentVisual: any = nil
    local currentServer: any = nil
    local currentPosition: any = nil
    local currentSince: number = 0
    local belowPhase: string = "park" -- park -> contact -> wait
    local phaseAt: number = 0
    local contactSince: number = 0
    local touchPulsed: boolean = false
    local blacklist: {[any]: number} = {}
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
        pickupCache = {}
        pickupCacheAt = -math.huge
        if type(state.mm2InvalidateCoinPickups) == "function" then
            pcall(state.mm2InvalidateCoinPickups)
        end
    end

    local function clearTarget(): ()
        currentVisual, currentServer, currentPosition = nil, nil, nil
        currentSince = 0
        belowPhase = "park"
        phaseAt = 0
        contactSince = 0
        touchPulsed = false
        lastPlacedAt = -math.huge
        lastContactRefreshAt = -math.huge
    end

    local function resetRoundMemory(): ()
        generation += 1
        clearTarget()
        roamPosition = nil
        spawns = {}
        spawnsAt = -math.huge
        table.clear(blacklist)
        bagActive = false
        bagCurrency = nil
        bagAmount = 0
        previousBagAmount = 0
        bagLimit = 50
        manualUntil = -math.huge
        lastMoveToTarget = nil
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
        clearTarget()
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

    local function pickups(): {any}
        local now: number = clock()
        if now - pickupCacheAt < 0.3 then
            return pickupCache
        end
        pickupCacheAt = now
        local out: {any} = {}
        if type(state.mm2CoinPickups) == "function" then
            local ok: boolean, list: any = pcall(state.mm2CoinPickups)
            if ok and type(list) == "table" then
                out = list
            end
        end
        -- Fallback: the game's own tag, then the exact server spawn part name.
        if #out == 0 then
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
        pickupCache = out
        return out
    end

    -- No role gate: MM2 can delay or omit the local role, and that made v150
    -- sit still. A confirmed round, map/timer or live coin event is enough.
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
        local explicitInactive: boolean = type(core.isRoundLifecycleActive) == "function"
            and core.isRoundLifecycleActive() ~= true
        local hasMap: boolean = type(core.findMM2Map) == "function"
            and core.findMM2Map() ~= nil
        local hasCoins: boolean = #pickups() > 0
        if explicitInactive and not (bagActive and hasCoins) then
            return "lobby"
        end
        if not hasMap and not hasCoins then
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
            return "Waiting · MM2 round not confirmed"
        elseif context == "dead" then
            return "Waiting · no living character"
        elseif context == "busy" then
            return "Paused · another physics feature owns the character"
        end
        return "Farming"
    end

    local function parts(): (any, any, any)
        return getCharacterParts()
    end

    -- Cancels only the farm's own native autopilot. It deliberately does NOT
    -- write Humanoid:Move(Vector3.zero): that call froze user input in v150.
    local function releaseMovement(): ()
        if lastMoveToTarget then
            local _, humanoid: any, root: any = parts()
            if humanoid and root and type(humanoid.MoveTo) == "function" then
                pcall(function(): () humanoid:MoveTo(root.Position) end)
            end
        end
        lastMoveToTarget = nil
    end

    local function moveTo(humanoid: any, position: any): ()
        if not humanoid or not position or type(humanoid.MoveTo) ~= "function" then
            return
        end
        if lastMoveToTarget and (position - lastMoveToTarget).Magnitude < 0.5 then
            return
        end
        lastMoveToTarget = position
        pcall(function(): () humanoid:MoveTo(position) end)
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
        local server: any = serverPartOf(part)
        for _, source: any in ipairs({part, server}) do
            if attribute(source, "Collected") == true
                or attribute(source, "Delete") == true
                or attribute(source, "RoundEnd") == true then
                return false
            end
        end
        if part.Transparency == 1 or (server and server.Transparency == 1) then
            return false
        end
        if (server and server.CanTouch == false) or part.CanTouch == false then
            return false
        end
        local expiry: number? = blacklist[part]
        if expiry and now < expiry then
            return false
        end
        local currency: any = attribute(server, "CoinID")
        if currency == nil then
            currency = attribute(part, "CoinID")
        end
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
                    if dy <= 45 then
                        local score: number = math.sqrt(dx * dx + dz * dz) + dy
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
            clearTarget()
            return false
        end
        if bestVisual ~= currentVisual then
            currentVisual = bestVisual
            currentServer = bestServer
            currentPosition = bestPosition
            currentSince = now
            belowPhase = "park"
            phaseAt = now
            contactSince = 0
            touchPulsed = false
            lastPlacedAt = -math.huge
            lastContactRefreshAt = -math.huge
        end
        return true
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

    -- Direct mode only: an intentional farm placement below the map is not a
    -- void fall and must not be fought by this optional rescue.
    local function voidTick(character: any, humanoid: any, root: any, now: number): ()
        if settings.mode == "Below Map" or not settings.voidRescue
            or antiVoidOwnsRescue() then
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

    local function manualControlActive(humanoid: any): boolean
        if not settings.manualOverride then
            return false
        end
        local move: any = humanoid and humanoid.MoveDirection or nil
        if move and type(move.Magnitude) == "number" and move.Magnitude > 0.12 then
            return true
        end
        return humanoid and humanoid.Jump == true
    end

    -- One whole-model placement at a coin-relative position. No root CFrame
    -- writer, no hitbox resize and no velocity/constraint motor.
    local function placeCharacter(character: any, root: any, position: any, now: number): boolean
        if not character or not root or not position
            or type(character.PivotTo) ~= "function" then
            return false
        end
        local look: any = Vector3.new(0, 0, -1)
        pcall(function(): ()
            local frame: any = root.CFrame
            if frame and frame.LookVector and frame.LookVector.X == frame.LookVector.X then
                look = frame.LookVector
            end
        end)
        local destination: any = nil
        pcall(function(): ()
            destination = CFrame.lookAt(position, position + look)
        end)
        if not destination then
            destination = CFrame.new(position)
        end
        local ok: boolean = pcall(function(): () character:PivotTo(destination) end)
        if not ok then
            return false
        end
        pcall(function(): ()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        lastPlacedAt = now
        return true
    end

    local function pulseTouchInterest(root: any, server: any): ()
        if touchPulsed or not root or not server then
            return
        end
        touchPulsed = true
        local fire: any = state.fireTouchInterest
        if type(fire) == "function" then
            pcall(fire, root, server, 0)
            pcall(fire, root, server, 1)
        end
    end

    local function parkPosition(position: any): any
        return position - Vector3.new(0, BELOW_OFFSET, 0)
    end

    local function contactPosition(position: any): any
        return position - Vector3.new(0, CONTACT_OFFSET, 0)
    end

    local function skipTarget(now: number, reason: string): ()
        if currentVisual then
            blacklist[currentVisual] = now + BLACKLIST_SECONDS
        end
        clearTarget()
        invalidatePickups()
        setStatus(reason)
    end

    local function belowMapTick(character: any, humanoid: any, root: any, now: number): ()
        -- A live contact is refreshed at 0.12 s, not every frame, so the
        -- character stays inside Coin_Server without a CFrame-per-frame loop.
        if belowPhase == "wait" and currentPosition and currentServer then
            if now - lastContactRefreshAt >= CONTACT_REFRESH then
                placeCharacter(character, root, contactPosition(currentPosition), now)
                lastContactRefreshAt = now
            end
            if now - contactSince > CONTACT_TIMEOUT then
                skipTarget(now, "Skipped pickup · server did not confirm")
                return
            end
            setStatus(string.format("Below Map · collecting · %d/%d",
                bagAmount, bagLimit))
            return
        end
        if now - lastStepAt < math.clamp(settings.stepInterval, STEP_MIN, STEP_MAX) then
            return
        end
        lastStepAt = now
        if not chooseTarget(root, now) then
            setStatus("Waiting · no collectable pickup")
            return
        end
        local position: any = currentPosition
        local server: any = currentServer
        if not position or not server or not server.Parent then
            skipTarget(now, "Skipped missing server pickup")
            return
        end
        if belowPhase == "park" then
            if placeCharacter(character, root, parkPosition(position), now) then
                belowPhase = "contact"
                phaseAt = now
                setStatus("Below Map · moving under coin")
            else
                skipTarget(now, "Skipped pickup · placement failed")
            end
        elseif belowPhase == "contact" and now - phaseAt >= PARK_DWELL then
            if placeCharacter(character, root, contactPosition(position), now) then
                pulseTouchInterest(root, server)
                belowPhase = "wait"
                contactSince = now
                lastContactRefreshAt = now
                setStatus(string.format("Below Map · collecting · %d/%d",
                    bagAmount, bagLimit))
            else
                skipTarget(now, "Skipped pickup · contact failed")
            end
        end
    end

    local function directTick(character: any, humanoid: any, root: any, now: number): ()
        if now - lastStepAt < math.clamp(settings.stepInterval, STEP_MIN, STEP_MAX) then
            return
        end
        lastStepAt = now
        if not chooseTarget(root, now) then
            refreshSpawns(now)
            if settings.roamWhenEmpty and #spawns > 0 then
                if not roamPosition or now - roamAt > 2.5 then
                    roamAt = now
                    roamPosition = spawns[math.random(1, #spawns)]
                end
                moveTo(humanoid, roamPosition)
                setStatus("Roaming · no collectable pickup")
            else
                releaseMovement()
                setStatus("Waiting · no collectable pickup")
            end
            return
        end
        roamPosition = nil
        local position: any = currentPosition
        local server: any = currentServer
        if not position or not server or not server.Parent then
            skipTarget(now, "Skipped missing server pickup")
            return
        end
        local dx: number = position.X - root.Position.X
        local dz: number = position.Z - root.Position.Z
        local horizontal: number = math.sqrt(dx * dx + dz * dz)
        local vertical: number = math.abs(position.Y - root.Position.Y)
        if horizontal <= DIRECT_CONTACT_RADIUS and vertical <= DIRECT_CONTACT_VERTICAL then
            releaseMovement()
            if contactSince == 0 then
                contactSince = now
                pulseTouchInterest(root, server)
            elseif now - contactSince > DIRECT_CONTACT_TIMEOUT then
                skipTarget(now, "Skipped pickup · server did not confirm")
                return
            end
            setStatus(string.format("Collecting · %d/%d · %s",
                bagAmount, bagLimit, tostring(bagCurrency or "Coin")))
            return
        end
        contactSince = 0
        touchPulsed = false
        moveTo(humanoid, position)
        if settings.jumpForHigh and position.Y - root.Position.Y > 2.5
            and position.Y - root.Position.Y < 8
            and now - lastJumpAt > 0.8 then
            lastJumpAt = now
            pcall(function(): () humanoid.Jump = true end)
        end
        setStatus(string.format("Direct · walking · %d/%d", bagAmount, bagLimit))
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
            releaseMovement()
            setStatus("Waiting · no living character")
            refreshOverlay()
            return
        end
        voidTick(character, humanoid, root, now)
        local context: string = roundContext()
        if context ~= "active" then
            releaseMovement()
            setStatus(contextLabel(context))
            refreshOverlay()
            return
        end
        if settings.stopAtFullBag and bagAmount >= bagLimit then
            releaseMovement()
            setStatus(string.format("Bag full · %d/%d confirmed", bagAmount, bagLimit))
            refreshOverlay()
            return
        end
        -- Only Below Map checks MoveDirection: Direct's MoveTo itself produces
        -- a MoveDirection and would otherwise look like manual input.
        if settings.mode == "Below Map" and manualControlActive(humanoid) then
            manualUntil = now + MANUAL_PAUSE
            releaseMovement()
            clearTarget()
        end
        if now < manualUntil then
            setStatus("Paused · manual movement")
            refreshOverlay()
            return
        end
        if settings.mode == "Below Map" then
            belowMapTick(character, humanoid, root, now)
        else
            directTick(character, humanoid, root, now)
        end
        refreshOverlay()
    end

    local function release(): ()
        enabled = false
        generation += 1
        disconnectFeatureConnection("MM2AutoFarmTick")
        for _, connection: any in ipairs(signals) do
            if type(connection) == "table" and type(connection.Disconnect) == "function" then
                pcall(function(): () connection:Disconnect() end)
            end
        end
        table.clear(signals)
        releaseMovement()
        clearTarget()
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
            manualUntil = -math.huge
            disconnectFeatureConnection("MM2AutoFarmTick")
            featureConnections.MM2AutoFarmTick = TaskManager:Connect(farmTick)
            setStatus("Starting · waiting for round context")
            farmTick(1 / 60)
        else
            release()
        end
    end

    local AutoFarmFeature: any = host.createUniversalFeature(
        "Auto Farm",
        "Below Map: physically overlaps real Coin_Server pickups from below",
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

    host.addCycleOption(AutoFarmFeature, "Farm mode",
        {"Below Map", "Direct"}, 1,
        function(value: string): ()
            settings.mode = if value == "Direct" then "Direct" else "Below Map"
            clearTarget()
            lastStepAt = -math.huge
            releaseMovement()
        end,
        "Below Map parks under a coin and rises into its real server volume. Direct walks with Humanoid:MoveTo. The old route solver is gone.")
    host.addNumberOption(AutoFarmFeature, "Step interval", 0.18, STEP_MIN, STEP_MAX,
        function(value: number): ()
            settings.stepInterval = math.clamp(tonumber(value) or 0.18,
                STEP_MIN, STEP_MAX)
        end,
        "Seconds between farm decisions. Contact refresh has its own 0.12 s bound.", 0.02)
    host.addToggleOption(AutoFarmFeature, "Manual override", true,
        function(value: boolean): () settings.manualOverride = value == true end,
        "WASD or jump pauses Below Map placements for 1.2 s so you keep control.")
    host.addToggleOption(AutoFarmFeature, "Jump for high pickups", true,
        function(value: boolean): () settings.jumpForHigh = value == true end,
        "Direct mode only: uses the native Humanoid.Jump for pickups above the floor.")
    host.addToggleOption(AutoFarmFeature, "Roam when empty", true,
        function(value: boolean): () settings.roamWhenEmpty = value == true end,
        "Direct mode only: walks to a real map spawn while no pickup exists.")
    host.addToggleOption(AutoFarmFeature, "Void rescue", true,
        function(value: boolean): () settings.voidRescue = value == true end,
        "Direct mode only: one bounded teleport back to the last grounded position. Disabled while Below Map is selected.")
    host.addToggleOption(AutoFarmFeature, "Stop at full bag", true,
        function(value: boolean): () settings.stopAtFullBag = value == true end,
        "Stops walking when CoinCollected reports the server's collection limit.")
    host.addInformationOption(AutoFarmFeature,
        "Below Map uses real Coin_Server positions and physically overlaps the "
            .. "server pickup from below; only CoinCollected increments Coins "
            .. "Collected. No route solver, no render-step lock and no grown hitbox.")

    -- Read-only state for offline suites and the debug surfaces.
    state.mm2AutoFarmSnapshot = function(): any
        return {
            enabled = enabled,
            mode = settings.mode,
            navigation = settings.mode,
            belowMap = settings.mode == "Below Map",
            manualOverride = settings.manualOverride,
            manualPause = math.max(0, manualUntil - clock()),
            coinsConfirmed = coinsConfirmed,
            bagAmount = bagAmount,
            bagLimit = bagLimit,
            bagCurrency = bagCurrency,
            bagActive = bagActive,
            activeSeconds = activeSeconds,
            status = lastStatus,
            persistentCoins = persistentCoins,
            targetName = currentServer and tostring(currentServer.Name) or nil,
            belowPhase = belowPhase,
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
