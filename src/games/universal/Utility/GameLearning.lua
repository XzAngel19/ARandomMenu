export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "GameLearning",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeController: any = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local product: any = host.PRODUCT
    local notify: any = host.notify
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local addToggleOption: any = host.addToggleOption
    local addActionOption: any = host.addActionOption
    local addInformationOption: any = host.addInformationOption
    local TaskManager: any = host.TaskManager
    local LocalPlayer: any = host.LocalPlayer
    local PlayersService: any = host.Players or (game :: any):GetService("Players")
    local Stats: any = host.Stats or (game :: any):GetService("Stats")
    local httpService: any = host.HttpService or (game :: any):GetService("HttpService")
    -- Games that author shots (MM2's SilentAIM) publish the last authored
    -- geometry here; nil everywhere else, so this stays a no-op.
    local gameBridge: any = context.services and
        context.services.gameBridge

    -- ---------------------------------------------------------------------------
    -- Game Learning: a passive log of what the server actually accepts.
    --
    -- Every tool activation snapshots the scene (every other player's distance,
    -- angle to the aim, line of sight, and the hitbox geometry at that instant).
    -- Every death is then matched back against the last few shots: a kill whose
    -- line of sight was blocked is a wallshot the server did not validate, a
    -- kill past 80 studs is a range the server did not cap, and a local
    -- teleport that is neither kicked nor snapped back is movement the server
    -- tolerated. Nothing is sent anywhere: the log lives in memory and can be
    -- saved next to the Projectile Calibration data for offline reading.
    -- ---------------------------------------------------------------------------
    local controllerFactory = (function(): any
        type SceneEntry = {
            player: string,
            dist: number,
            angleDeg: number,
            los: string,
            root: {number},
            headOffset: number?,
            torso: {number}?,
        }
        type ShotRecord = {
            id: number,
            t: number,
            clockAt: number,
            pingMs: number,
            tool: string,
            origin: {number},
            aim: {number},
            scene: {SceneEntry},
            outcome: {[string]: any}?,
            silentSpawn: {variant: string, offset: number}?,
        }
        type MovementRecord = {
            t: number,
            kind: string,
            magnitude: number,
            detail: {[string]: any}?,
        }

        local tuning: any = {
            logShots = true,
            logMovement = true,
            logHitboxes = true,
            killWindowSeconds = 4,
            sceneRadius = 80,
            maxEvents = 300,
        }

        local executorEnvironment: {[string]: any} = getfenv() :: any
        local mouse: Mouse = LocalPlayer:GetMouse()
        local outputRoot: string = product.storageFolder
        local outputTelemetry: string = outputRoot .. "/Telemetry"
        local outputFolder: string = outputTelemetry .. "/Universal"
        local outputPath: string = outputFolder
            .. "/Place_"
            .. tostring(game.PlaceId)
            .. "_Game_Learning.json"
        local runtime: any = {
            enabled = false,
            shots = {} :: {ShotRecord},
            movements = {} :: {MovementRecord},
            hits = {} :: {{[string]: any}},
            aggregates = {
                shots = 0,
                kills = 0,
                cleanKills = 0,
                wallshotKills = 0,
                longrangeKills = 0,
                misses = 0,
                unattributedDeaths = 0,
                teleports = 0,
                speedSpikes = 0,
                longAirtime = 0,
                hitboxAnomalies = 0,
                farthestKill = 0,
            },
            shotCounter = 0,
            spawnShots = {} :: {[string]: number},
            spawnKills = {} :: {[string]: number},
            connections = {} :: {RBXScriptConnection},
            observedTools = setmetatable({}, {__mode = "k"}) :: {[Tool]: boolean},
            watchedPlayers = setmetatable({}, {__mode = "k"}) :: {[Player]: boolean},
            anomalyCooldown = setmetatable({}, {__mode = "k"}) :: {[Player]: number},
            movementTask = nil :: any,
            hitboxTask = nil :: any,
        }
        local controller: any
        local saveSnapshot: (reason: string) -> boolean

        -- Assigned before any method is defined on it: `function
        -- controller:foo()` is sugar for controller.foo = function(...).
        controller = {} :: any
        controller.tuning = tuning

        local function vectorArray(value: Vector3): {number}
            return {value.X, value.Y, value.Z}
        end

        local function round1(value: number): number
            return math.floor(value * 10 + 0.5) / 10
        end

        local function round2(value: number): number
            return math.floor(value * 100 + 0.5) / 100
        end

        local function clampTrim(list: {any}, cap: number): ()
            while #list > cap do
                table.remove(list, 1)
            end
        end

        local function getPingMilliseconds(): number
            local pingMs: number = 0
            pcall(function(): ()
                local network: Instance? = Stats:FindFirstChild("Network")
                local serverItems: Instance? = network
                    and network:FindFirstChild("ServerStatsItem")
                local pingItem: any = serverItems
                    and serverItems:FindFirstChild("Data Ping")
                if pingItem and type(pingItem.GetValue) == "function" then
                    pingMs = tonumber(pingItem:GetValue()) or 0
                end
            end)
            return pingMs
        end

        local function findSceneEntry(
            shot: ShotRecord,
            player: Player
        ): SceneEntry?
            for _, entry: SceneEntry in ipairs(shot.scene) do
                if entry.player == player.Name then
                    return entry
                end
            end
            return nil
        end

        local function recordShot(tool: Tool): ()
            local character: Model? = LocalPlayer.Character
            local root: BasePart? = character
                and character:FindFirstChild("HumanoidRootPart")
                :: BasePart?
            local origin: Vector3? = root and root.Position or nil
            if not origin then
                return
            end
            local handle: BasePart? = tool:FindFirstChild("Handle") :: BasePart?
            local shotOrigin: Vector3 = handle and handle.Position or origin
            local aim: Vector3 = Vector3.zero
            pcall(function(): ()
                aim = mouse.Hit.Position
            end)
            local aimDelta: Vector3 = aim - shotOrigin
            local aimDir: Vector3? = aimDelta.Magnitude > 0.01 and aimDelta.Unit or nil

            local scene: {SceneEntry} = {}
            local raycastParams: RaycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.IgnoreWater = true
            raycastParams.FilterDescendantsInstances = {character :: Instance}
            for _, player: Player in ipairs(PlayersService:GetPlayers()) do
                if player ~= LocalPlayer then
                    local targetCharacter: Model? = player.Character
                    local targetRoot: BasePart? = targetCharacter
                        and targetCharacter:FindFirstChild("HumanoidRootPart")
                        :: BasePart?
                    local humanoid: Humanoid? = targetCharacter
                        and targetCharacter:FindFirstChildOfClass("Humanoid")
                        :: Humanoid?
                    if targetRoot
                        and humanoid
                        and humanoid.Health > 0 then
                        local toPlayer: Vector3 = targetRoot.Position - shotOrigin
                        local dist: number = toPlayer.Magnitude
                        if dist <= tuning.sceneRadius and dist > 0.01 then
                            local angleDeg: number = 0
                            if aimDir then
                                angleDeg = math.deg(
                                    math.acs(math.clamp(
                                        toPlayer.Unit:Dot(aimDir),
                                        -1,
                                        1
                                    ))
                                )
                            end
                            local hit: RaycastResult? = workspace:Raycast(
                                shotOrigin,
                                toPlayer,
                                raycastParams
                            )
                            local los: string = "clear"
                            if hit
                                and not hit.Instance:IsDescendantOf(
                                    targetCharacter :: Instance
                                ) then
                                los = "blocked"
                            end
                            local head: BasePart? = targetCharacter
                                and targetCharacter:FindFirstChild("Head")
                                :: BasePart?
                            local torso: BasePart? = targetCharacter
                                and targetCharacter:FindFirstChild("UpperTorso")
                                :: BasePart?
                            table.insert(scene, {
                                player = player.Name,
                                dist = round1(dist),
                                angleDeg = aimDir and round1(angleDeg) or nil,
                                los = los,
                                root = vectorArray(targetRoot.Position),
                                headOffset = head
                                    and round2(
                                        (head.Position
                                            - targetRoot.Position)
                                            .Magnitude
                                    )
                                    or nil,
                                torso = torso
                                    and {
                                        round2(torso.Size.X),
                                        round2(torso.Size.Y),
                                        round2(torso.Size.Z),
                                    }
                                    or nil,
                            })
                        end
                    end
                end
            end

            runtime.shotCounter += 1
            local shot: ShotRecord = {
                id = runtime.shotCounter,
                t = os.time(),
                clockAt = os.clock(),
                pingMs = getPingMilliseconds(),
                tool = tool.Name,
                origin = vectorArray(shotOrigin),
                aim = vectorArray(aim),
                scene = scene,
                outcome = nil,
                silentSpawn = nil,
            }
            -- Tag silent-authored shots with their spawn variant so the log
            -- can compare hit rates per geometry (Front/Through/Top/Behind).
            if gameBridge and type(gameBridge.silentShot) == "function" then
                local okInfo: boolean, info: any = pcall(gameBridge.silentShot)
                if okInfo
                    and type(info) == "table"
                    and info.variant ~= nil
                    and os.clock() - (tonumber(info.at) or 0) < 2 then
                    shot.silentSpawn = {
                        variant = info.variant,
                        offset = tonumber(info.offset) or 0,
                    }
                    local variant: string = info.variant
                    runtime.spawnShots[variant] = (runtime.spawnShots[variant] or 0) + 1
                end
            end
            table.insert(runtime.shots, shot)
            clampTrim(runtime.shots, tuning.maxEvents)
            runtime.aggregates.shots += 1

            -- A few seconds later the shot either produced a kill (handled by
            -- the death watcher) or it missed the only plausible target it had.
            task.delay(tuning.killWindowSeconds + 0.5, function(): ()
                if shot.outcome ~= nil then
                    return
                end
                local candidate: SceneEntry? = nil
                for _, entry: SceneEntry in ipairs(shot.scene) do
                    if entry.dist <= 60
                        and (entry.angleDeg == nil or entry.angleDeg <= 30) then
                        candidate = entry
                    end
                end
                if candidate then
                    shot.outcome = {verdict = "miss"}
                    runtime.aggregates.misses += 1
                end
            end)
        end

        local function recordDeath(player: Player): ()
            local attributed: boolean = false
            for index: number = #runtime.shots, 1, -1 do
                local shot: ShotRecord = runtime.shots[index]
                if os.clock() - shot.clockAt > tuning.killWindowSeconds then
                    break
                end
                if shot.outcome ~= nil then
                    continue
                end
                local entry: SceneEntry? = findSceneEntry(shot, player)
                if entry
                    and entry.dist <= 60
                    and (entry.angleDeg == nil or entry.angleDeg <= 30) then
                    local verdict: string = "clean"
                    if entry.los == "blocked" then
                        verdict = "wallshot"
                    elseif entry.dist > 80 then
                        verdict = "longrange"
                    end
                    shot.outcome = {
                        killed = player.Name,
                        delayMs = math.floor((os.clock() - shot.clockAt) * 1000),
                        verdict = verdict,
                        distance = entry.dist,
                        lineOfSight = entry.los,
                    }
                    runtime.aggregates.kills += 1
                    if verdict == "wallshot" then
                        runtime.aggregates.wallshotKills += 1
                    elseif verdict == "longrange" then
                        runtime.aggregates.longrangeKills += 1
                    else
                        runtime.aggregates.cleanKills += 1
                    end
                    if entry.dist > runtime.aggregates.farthestKill then
                        runtime.aggregates.farthestKill = entry.dist
                    end
                    if shot.silentSpawn then
                        local variant: string = shot.silentSpawn.variant
                        runtime.spawnKills[variant] =
                            (runtime.spawnKills[variant] or 0) + 1
                    end
                    table.insert(runtime.hits, {
                        t = os.time(),
                        killed = player.Name,
                        tool = shot.tool,
                        verdict = verdict,
                        distance = entry.dist,
                        lineOfSight = entry.los,
                        headOffset = entry.headOffset,
                        torso = entry.torso,
                        silentSpawn = shot.silentSpawn,
                    })
                    clampTrim(runtime.hits, tuning.maxEvents)
                    attributed = true
                    break
                end
            end
            if not attributed then
                runtime.aggregates.unattributedDeaths += 1
            end
        end

        local function watchPlayer(player: Player): ()
            if runtime.watchedPlayers[player] then
                return
            end
            runtime.watchedPlayers[player] = true
            local function watchCharacter(character: Model): ()
                local humanoid: Humanoid? = character:FindFirstChildOfClass(
                    "Humanoid"
                ) :: Humanoid?
                if humanoid then
                    table.insert(
                        runtime.connections,
                        humanoid.Died:Connect(function(): ()
                            if runtime.enabled then
                                recordDeath(player)
                            end
                        end)
                    )
                end
            end
            if player.Character then
                watchCharacter(player.Character)
            end
            table.insert(
                runtime.connections,
                player.CharacterAdded:Connect(watchCharacter)
            )
        end

        local function recordMovement(
            kind: string,
            magnitude: number,
            detail: {[string]: any}?
        ): ()
            table.insert(runtime.movements, {
                t = os.time(),
                kind = kind,
                magnitude = round1(magnitude),
                detail = detail,
            } :: MovementRecord)
            clampTrim(runtime.movements, tuning.maxEvents)
        end

        local function observeTool(tool: Tool): ()
            if runtime.observedTools[tool] then
                return
            end
            runtime.observedTools[tool] = true
            table.insert(
                runtime.connections,
                tool.Activated:Connect(function(): ()
                    if runtime.enabled and tuning.logShots then
                        recordShot(tool)
                    end
                end)
            )
        end

        local function observeContainer(container: Instance?): ()
            if not container then
                return
            end
            for _, child: Instance in ipairs(container:GetChildren()) do
                if child:IsA("Tool") then
                    observeTool(child :: Tool)
                end
            end
            table.insert(
                runtime.connections,
                container.ChildAdded:Connect(function(child: Instance): ()
                    if child:IsA("Tool") then
                        observeTool(child :: Tool)
                    end
                end)
            )
        end

        local function startMovementProbe(): ()
            if runtime.movementTask then
                return
            end
            local lastPosition: Vector3? = nil
            local lastAt: number = 0
            local speedSince: number? = nil
            local airSince: number? = nil
            local airConsumed: boolean = false
            local movementElapsed: number = 0
            runtime.movementTask = TaskManager:Connect(function(deltaTime: number): ()
                movementElapsed += deltaTime
                if movementElapsed < 0.05 then
                    return
                end
                movementElapsed = 0
                if not (runtime.enabled and tuning.logMovement) then
                    lastPosition = nil
                    lastAt = 0
                    speedSince = nil
                    airSince = nil
                    airConsumed = false
                    return
                end
                local character: Model? = LocalPlayer.Character
                local root: BasePart? = character
                    and character:FindFirstChild("HumanoidRootPart")
                    :: BasePart?
                local humanoid: Humanoid? = character
                    and character:FindFirstChildOfClass("Humanoid")
                    :: Humanoid?
                if not root or not humanoid then
                    lastPosition = nil
                    lastAt = 0
                    return
                end
                local now: number = os.clock()
                local position: Vector3 = root.Position
                if lastPosition and lastAt > 0 then
                    local elapsed: number = now - lastAt
                    if elapsed >= 0.02 then
                        local jumped: number = (position - lastPosition).Magnitude
                        if jumped > 25 and elapsed < 0.15 then
                            recordMovement("teleport", jumped, {
                                from = vectorArray(lastPosition),
                                to = vectorArray(position),
                            })
                            runtime.aggregates.teleports += 1
                        end
                        local speed: number =
                            root.AssemblyLinearVelocity.Magnitude
                        if speed > 90 then
                            if speedSince == nil then
                                speedSince = now
                            elseif now - speedSince > 0.3 then
                                recordMovement("speed", speed)
                                runtime.aggregates.speedSpikes += 1
                                speedSince = nil
                            end
                        else
                            speedSince = nil
                        end
                    end
                end
                if humanoid.FloorMaterial == Enum.Material.Air then
                    if airSince == nil then
                        airSince = now
                    end
                    if not airConsumed and now - airSince > 2.5 then
                        recordMovement(
                            "airtime",
                            math.floor((now - airSince) * 10) / 10
                        )
                        runtime.aggregates.longAirtime += 1
                        airConsumed = true
                    end
                else
                    airSince = nil
                    airConsumed = false
                end
                lastPosition = position
                lastAt = now
            end)
        end

        local function startHitboxProbe(): ()
            if runtime.hitboxTask then
                return
            end
            local hitboxElapsed: number = 0
            runtime.hitboxTask = TaskManager:Connect(function(deltaTime: number): ()
                hitboxElapsed += deltaTime
                if hitboxElapsed < 1 then
                    return
                end
                hitboxElapsed = 0
                if not (runtime.enabled and tuning.logHitboxes) then
                    return
                end
                for _, player: Player in ipairs(PlayersService:GetPlayers()) do
                    if player ~= LocalPlayer then
                        local character: Model? = player.Character
                        local root: BasePart? = character
                            and character:FindFirstChild("HumanoidRootPart")
                            :: BasePart?
                        local head: BasePart? = character
                            and character:FindFirstChild("Head")
                            :: BasePart?
                        local torso: BasePart? = character
                            and character:FindFirstChild("UpperTorso")
                            :: BasePart?
                        local anomaly: string? = nil
                        local magnitude: number = 0
                        if root and head then
                            local offset: number =
                                (head.Position - root.Position).Magnitude
                            if offset > 3.2 or offset < 0.9 then
                                anomaly = "headOffset"
                                magnitude = round2(offset)
                            end
                        end
                        if not anomaly and root and torso then
                            local torsoY: number = torso.Size.Y
                            if torsoY > 2.6 or torsoY < 0.7 then
                                anomaly = "torsoSize"
                                magnitude = round2(torsoY)
                            end
                        end
                        if anomaly then
                            local lastFlag: number? = runtime.anomalyCooldown[player]
                            if not lastFlag or os.clock() - lastFlag > 2 then
                                runtime.anomalyCooldown[player] = os.clock()
                                recordMovement(anomaly, magnitude, {
                                    player = player.Name,
                                })
                                runtime.aggregates.hitboxAnomalies += 1
                            end
                        end
                    end
                end
            end)
        end

        local function buildInsights(): {string}
            local insights: {string} = {}
            local agg: any = runtime.aggregates
            if agg.wallshotKills > 0 then
                table.insert(
                    insights,
                    "Server accepted "
                        .. tostring(agg.wallshotKills)
                        .. " kill(s) through a blocked line of sight: wallshots are not validated."
                )
            end
            if agg.longrangeKills > 0 then
                table.insert(
                    insights,
                    "Server accepted "
                        .. tostring(agg.longrangeKills)
                        .. " kill(s) beyond 80 studs: no range cap observed."
                )
            end
            if agg.teleports > 0 then
                table.insert(
                    insights,
                    tostring(agg.teleports)
                        .. " local teleport(s) were tolerated (no kick, no snapback)."
                )
            end
            if agg.speedSpikes > 0 then
                table.insert(
                    insights,
                    tostring(agg.speedSpikes)
                        .. " sustained speed spike(s) above 90 studs/s were tolerated."
                )
            end
            if agg.hitboxAnomalies > 0 then
                table.insert(
                    insights,
                    tostring(agg.hitboxAnomalies)
                        .. " abnormal hitbox geometry sample(s) observed on other players."
                )
            end
            local spawnTotal: number = 0
            local spawnParts: {string} = {}
            for _, variant: string in ipairs({"Front", "Through", "Top", "Behind"}) do
                local shotsTaken: number = runtime.spawnShots[variant] or 0
                if shotsTaken > 0 then
                    spawnTotal += shotsTaken
                    table.insert(
                        spawnParts,
                        string.format(
                            "%s %d/%d",
                            variant,
                            runtime.spawnKills[variant] or 0,
                            shotsTaken
                        )
                    )
                end
            end
            if spawnTotal > 0 then
                table.insert(
                    insights,
                    "Silent spawn A/B (kills/shots): "
                        .. table.concat(spawnParts, " · ")
                        .. ". Compare variants before changing the default."
                )
            end
            if #insights == 0 then
                table.insert(
                    insights,
                    "No server-tolerance anomalies recorded yet this session."
                )
            end
            return insights
        end

        saveSnapshot = function(reason: string?): boolean
            if type(executorEnvironment.writefile) ~= "function" then
                return false
            end
            if type(executorEnvironment.makefolder) == "function" then
                pcall(executorEnvironment.makefolder, outputRoot)
                pcall(executorEnvironment.makefolder, outputTelemetry)
                pcall(executorEnvironment.makefolder, outputFolder)
            end
            local merged: {[string]: any} = {}
            local mergedInsights: {string} = {}
            if type(executorEnvironment.readfile) == "function" then
                local okRead: boolean, existingRaw: any = pcall(
                    executorEnvironment.readfile,
                    outputPath
                )
                if okRead and type(existingRaw) == "string" then
                    local okDecode: boolean, existing: any = pcall(
                        httpService.JSONDecode,
                        httpService,
                        existingRaw
                    )
                    if okDecode and type(existing) == "table" then
                        merged = existing
                        mergedInsights = existing.insights or {}
                    end
                end
            end
            local aggregates: any = merged.aggregates or {}
            for key: string, base: number in pairs(runtime.aggregates) do
                aggregates[key] = (tonumber(aggregates[key]) or 0)
                    + (base :: number)
            end
            local spawnShots: any = merged.spawnShots or {}
            for key: string, base: number in pairs(runtime.spawnShots) do
                spawnShots[key] = (tonumber(spawnShots[key]) or 0)
                    + (base :: number)
            end
            local spawnKills: any = merged.spawnKills or {}
            for key: string, base: number in pairs(runtime.spawnKills) do
                spawnKills[key] = (tonumber(spawnKills[key]) or 0)
                    + (base :: number)
            end
            local payload: {[string]: any} = {
                schema = 1,
                kind = "game-learning-log",
                placeId = game.PlaceId,
                savedAt = os.time(),
                savedReason = reason or "manual",
                session = {
                    startedAt = os.time(),
                    uptimeSeconds = math.floor(os.clock()),
                },
                aggregates = aggregates,
                insights = buildInsights(),
                previousInsights = mergedInsights,
                spawnShots = runtime.spawnShots,
                spawnKills = runtime.spawnKills,
                shots = runtime.shots,
                movements = runtime.movements,
                hits = runtime.hits,
            }
            local okEncode: boolean, encoded: any = pcall(
                httpService.JSONEncode,
                httpService,
                payload
            )
            if not okEncode or type(encoded) ~= "string" then
                return false
            end
            local okWrite: boolean = pcall(
                executorEnvironment.writefile,
                outputPath,
                encoded
            )
            if okWrite then
                notify("Game Learning: saved " .. outputPath)
            end
            return okWrite
        end

        local function status(): string
            local agg: any = runtime.aggregates
            local base: string = string.format(
                "Game Learning · shots %d · kills %d (wall %d · far %d) · misses %d · teleports %d · speed %d · anomalies %d",
                agg.shots,
                agg.kills,
                agg.wallshotKills,
                agg.longrangeKills,
                agg.misses,
                agg.teleports,
                agg.speedSpikes,
                agg.hitboxAnomalies
            )
            local spawnParts: {string} = {}
            for _, variant: string in ipairs({"Front", "Through", "Top", "Behind"}) do
                local shotsTaken: number = runtime.spawnShots[variant] or 0
                if shotsTaken > 0 then
                    table.insert(
                        spawnParts,
                        string.format(
                            "%s %d/%d",
                            variant,
                            runtime.spawnKills[variant] or 0,
                            shotsTaken
                        )
                    )
                end
            end
            if #spawnParts > 0 then
                base = base .. " · spawn " .. table.concat(spawnParts, " ")
            end
            return base
        end

        local function deleteLogs(): boolean
            local deleteFile: any = executorEnvironment.delfile
            local isFile: any = executorEnvironment.isfile
            if type(deleteFile) ~= "function" then
                return false
            end
            local exists: boolean = true
            local okCheck: boolean, result: any = pcall(isFile, outputPath)
            if not okCheck then
                exists = false
            else
                exists = result == true
            end
            if not exists then
                return true
            end
            local okDelete: boolean = pcall(deleteFile, outputPath)
            if okDelete then
                notify("Game Learning: log deleted")
            end
            return okDelete
        end

        function controller:setEnabled(enabled: boolean): ()
            if runtime.enabled == enabled then
                return
            end
            if not enabled then
                runtime.enabled = false
                for _, connection: RBXScriptConnection in ipairs(
                    runtime.connections
                ) do
                    connection:Disconnect()
                end
                table.clear(runtime.connections)
                runtime.observedTools = setmetatable({}, {__mode = "k"})
                -- Without this, re-enabling would skip re-watching players whose
                -- connections were just disconnected.
                runtime.watchedPlayers = setmetatable({}, {__mode = "k"})
                if runtime.movementTask then
                    runtime.movementTask:Disconnect()
                    runtime.movementTask = nil
                end
                if runtime.hitboxTask then
                    runtime.hitboxTask:Disconnect()
                    runtime.hitboxTask = nil
                end
                return
            end
            runtime.enabled = true
            startMovementProbe()
            startHitboxProbe()
            observeContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
            observeContainer(LocalPlayer.Character)
            table.insert(
                runtime.connections,
                LocalPlayer.CharacterAdded:Connect(function(character: Model): ()
                    observeContainer(character)
                end)
            )
            for _, player: Player in ipairs(PlayersService:GetPlayers()) do
                watchPlayer(player)
            end
            table.insert(
                runtime.connections,
                PlayersService.PlayerAdded:Connect(watchPlayer)
            )
        end

        controller.save = function(_reason: string?): boolean
            return saveSnapshot("manual")
        end
        controller.delete = function(): boolean
            return deleteLogs()
        end
        controller.status = status
        return controller
    end)()

    local gameLearning: any = controllerFactory

    local GameLearningFeature: any = createUniversalFeature(
        "Game Learning",
        "Passive log of shots, hitboxes and movement: learns what the server "
            .. "accepts or allows by accident (wallshots, range, teleports).",
        16,
        function(_enabled: boolean): () end,
        {category = true, categoryName = "Other"}
    )
    addToggleOption(
        GameLearningFeature,
        "Log shots",
        gameLearning.tuning.logShots,
        function(value: boolean): ()
            gameLearning.tuning.logShots = value
        end,
        "Snapshots every player's distance, angle, line of sight and hitbox "
            .. "geometry on each shot you fire."
    )
    addToggleOption(
        GameLearningFeature,
        "Log movement",
        gameLearning.tuning.logMovement,
        function(value: boolean): ()
            gameLearning.tuning.logMovement = value
        end,
        "Tracks teleports, sustained speed spikes and long airtime on your "
            .. "character: movement the server tolerates."
    )
    addToggleOption(
        GameLearningFeature,
        "Log hitboxes",
        gameLearning.tuning.logHitboxes,
        function(value: boolean): ()
            gameLearning.tuning.logHitboxes = value
        end,
        "Samples other players' head offset and torso size once a second and "
            .. "flags abnormal geometry."
    )
    addNumberOption(
        GameLearningFeature,
        "Kill window",
        gameLearning.tuning.killWindowSeconds,
        1,
        10,
        function(value: number): ()
            gameLearning.tuning.killWindowSeconds = value
        end,
        "Seconds after a shot a death still counts as this shot's result.",
        0.5
    )
    addActionOption(GameLearningFeature, "Show status", function(): ()
        notify(gameLearning:status())
    end)
    addActionOption(GameLearningFeature, "Save logs", function(): ()
        gameLearning:save()
    end)
    addActionOption(GameLearningFeature, "Delete logs", function(): ()
        gameLearning:delete()
    end)
    addInformationOption(
        GameLearningFeature,
        "Local only: nothing is uploaded. Saved next to the Projectile "
            .. "Calibration file as _Game_Learning.json."
    )

    activeController = gameLearning
    gameLearning:setEnabled(true)

    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    if activeController then
        activeController:setEnabled(false)
    end
    activeController = nil
    Module.Events = {}
end

return Module
