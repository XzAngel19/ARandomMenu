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
    local UserInputService: any = host.UserInputService or (game :: any):GetService("UserInputService")

    local isMM2: boolean = game.PlaceId == 142823291
    local gameBridge: any = context.services and
        context.services.gameBridge

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
            shotId: string?,
            sessionId: string?,
            buildStamp: string?,
            settings: any?,
            eventSource: string?,
            evidence: any?,
            deathObservation: any?,
            id: number,
            t: number,
            clockAt: number,
            pingMs: number,
            tool: string,
            kind: string?,
            origin: {number},
            aim: {number},
            scene: {SceneEntry},
            outcome: {[string]: any}?,
            silentSpawn: {variant: string, offset: number?}?,

            target: string?,
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
            sceneRadius = 250,
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
            sessionId = httpService:GenerateGUID(false),
            startedAt = os.time(),
            startedClock = os.clock(),
            buildStamp = tostring(host.SOURCE_STAMP or "unknown"),
            historyLoaded = false,
            persistenceBlocked = false,
            historyBackup = nil,
            shots = {} :: {ShotRecord},
            movements = {} :: {MovementRecord},
            hits = {} :: {{[string]: any}},
            aggregates = {
                shots = 0,
                confirmations = 0,
                targetHits = 0,
                projectileObservations = 0,
                unconfirmed = 0,
                deathAssociations = 0,
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
                hitboxKills = 0,
                farthestKill = 0,
            },
            shotCounter = 0,
            spawnShots = {} :: {[string]: number},
            spawnKills = {} :: {[string]: number},
            lastAuthoredAt = 0,
            saveDirty = false,
            revision = 0,
            connections = {} :: {RBXScriptConnection},
            observedTools = setmetatable({}, {__mode = "k"}) :: {[Tool]: boolean},
            watchedPlayers = setmetatable({}, {__mode = "k"}) :: {[Player]: boolean},
            anomalyCooldown = setmetatable({}, {__mode = "k"}) :: {[Player]: number},
            movementTask = nil :: any,
            hitboxTask = nil :: any,
            autosaveTask = nil :: any,
        }
        local controller: any
        local saveSnapshot: (reason: string) -> boolean

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

        local function buildScene(
            shotOrigin: Vector3,
            aimDir: Vector3?
        ): {SceneEntry}
            local scene: {SceneEntry} = {}
            local character: Model? = LocalPlayer.Character
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
                                    math.acos(math.clamp(
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
            return scene
        end

        local function finalizeShot(
            shot: ShotRecord,
            explicitVariant: string?,
            explicitOffset: number?
        ): ()

            local variant: string? = explicitVariant
            local variantOffset: number? = explicitOffset
            if not isMM2 and not variant
                and gameBridge
                and type(gameBridge.silentShot) == "function" then
                local okInfo: boolean, info: any = pcall(gameBridge.silentShot)
                if okInfo
                    and type(info) == "table"
                    and info.variant ~= nil
                    and os.clock() - (tonumber(info.at) or 0) < 2 then
                    variant = info.variant
                    variantOffset = tonumber(info.offset)
                end
            end
            if variant then
                shot.silentSpawn = {variant = variant, offset = variantOffset}
                runtime.spawnShots[variant] = (runtime.spawnShots[variant] or 0) + 1
            end
            table.insert(runtime.shots, shot)
            clampTrim(runtime.shots, tuning.maxEvents)
            runtime.aggregates.shots += 1
            runtime.revision += 1
            runtime.saveDirty = true

            local timerSession = runtime.sessionId
            task.delay(tuning.killWindowSeconds + 0.5, function(): ()
                if timerSession ~= runtime.sessionId then return end
                if shot.outcome ~= nil then
                    return
                end
                shot.outcome = {verdict = "unconfirmed", evidence = "observation-timeout"}
                runtime.aggregates.unconfirmed += 1
                runtime.revision += 1
                runtime.saveDirty = true
            end)
        end

        local function recordShot(tool: Tool): ()
            -- MM2's core is the sole weapon observer; no mouse/Tool double count.
            if isMM2 then return end
            local name = string.lower(tool.Name)
            if not string.find(name, "gun", 1, true) and not string.find(name, "knife", 1, true)
                and not tool:FindFirstChild("Shoot") then return end
            runtime.lastAuthoredAt = os.clock()
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
            runtime.shotCounter += 1
            local shot: ShotRecord = {
                sessionId = runtime.sessionId,
                buildStamp = runtime.buildStamp,
                id = runtime.shotCounter,
                t = os.time(),
                clockAt = os.clock(),
                pingMs = getPingMilliseconds(),
                tool = tool.Name,
                origin = vectorArray(shotOrigin),
                aim = vectorArray(aim),
                scene = buildScene(shotOrigin, aimDir),
                outcome = nil,
                silentSpawn = nil,
            }
            finalizeShot(shot, nil)
        end

        local function recordAuthoredShot(info: any): ()
            if type(info) ~= "table" then
                return
            end
            if info.kind == "knifeActivation" then return end -- activation is not a throw/stab
            if type(info.shotId) == "string" then
                for _, previous in ipairs(runtime.shots) do
                    if previous.shotId == info.shotId then return end
                end
            end
            local character: Model? = LocalPlayer.Character
            local root: BasePart? = character
                and character:FindFirstChild("HumanoidRootPart")
                :: BasePart?
            local shotOrigin: Vector3? =
                typeof(info.originPos) == "Vector3" and info.originPos or root
                    and root.Position
                    or nil
            if not shotOrigin then
                return
            end
            local aim: Vector3 =
                typeof(info.aimPos) == "Vector3" and info.aimPos or Vector3.zero
            if aim == Vector3.zero then
                pcall(function(): ()
                    aim = mouse.Hit.Position
                end)
            end
            local aimDelta: Vector3 = aim - shotOrigin
            local aimDir: Vector3? = aimDelta.Magnitude > 0.01 and aimDelta.Unit or nil
            runtime.lastAuthoredAt = os.clock()
            runtime.shotCounter += 1
            local shot: ShotRecord = {
                shotId = info.shotId,
                sessionId = info.sessionId or runtime.sessionId,
                buildStamp = info.buildStamp or runtime.buildStamp,
                settings = info.settings,
                eventSource = info.eventSource,
                id = runtime.shotCounter,
                t = os.time(),
                clockAt = os.clock(),
                pingMs = getPingMilliseconds(),
                tool = tostring(info.toolName or "Unknown"),
                kind = info.kind,
                origin = vectorArray(shotOrigin),
                aim = vectorArray(aim),
                scene = buildScene(shotOrigin, aimDir),
                outcome = nil,
                silentSpawn = nil,
                target = type(info.targetName) == "string" and info.targetName
                    or (typeof(info.target) == "Instance" and info.target.Name or nil),
            }
            finalizeShot(shot, info.variant, tonumber(info.offset))
        end

        local function recordConfirmation(info: any): ()
            if type(info) ~= "table" or type(info.shotId) ~= "string" then return end
            for index = #runtime.shots, 1, -1 do
                local shot = runtime.shots[index]
                if shot.shotId ~= info.shotId then continue end
                if shot.evidence then return end -- repeated notifications are idempotent
                if shot.outcome and shot.outcome.verdict == "unconfirmed" then
                    runtime.aggregates.unconfirmed = math.max(0, runtime.aggregates.unconfirmed - 1)
                end
                shot.evidence = {source = info.evidence, hitTarget = info.hitTarget,
                    latencyMs = info.latencyMs, targetName = info.targetName}
                local verdict = "projectile-observed"
                if info.kind == "gun" then
                    verdict = info.hitTarget == true and "target-hit" or "shot-confirmed"
                    if info.hitTarget == true then runtime.aggregates.targetHits += 1 end
                else
                    runtime.aggregates.projectileObservations += 1
                end
                runtime.aggregates.confirmations += 1
                shot.outcome = {verdict = verdict, evidence = info.evidence}
                runtime.revision += 1
                runtime.saveDirty = true
                return
            end
        end

        local function recordDeath(player: Player): ()
            -- Temporal association only: another player may have caused the death.
            local attributed = false
            for index = #runtime.shots, 1, -1 do
                local shot = runtime.shots[index]
                if os.clock() - shot.clockAt > tuning.killWindowSeconds then break end
                if shot.target ~= player.Name or shot.deathObservation then continue end
                shot.deathObservation = {player = player.Name,
                    delayMs = math.floor((os.clock() - shot.clockAt) * 1000),
                    evidence = "temporal-association-only"}
                runtime.aggregates.deathAssociations += 1
                table.insert(runtime.hits, {t = os.time(), shotId = shot.shotId,
                    player = player.Name, verdict = "death-associated-not-attributed"})
                clampTrim(runtime.hits, tuning.maxEvents)
                attributed = true
                break
            end
            if not attributed then runtime.aggregates.unattributedDeaths += 1 end
            runtime.revision += 1
            runtime.saveDirty = true
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
            runtime.revision += 1
            runtime.saveDirty = true
        end

        local function observeTool(tool: Tool): ()
            if isMM2 then return end
            if runtime.observedTools[tool] then
                return
            end
            runtime.observedTools[tool] = true
            table.insert(
                runtime.connections,
                tool.Activated:Connect(function(): ()
                    if not (runtime.enabled and tuning.logShots) then
                        return
                    end

                    if os.clock() - runtime.lastAuthoredAt < 0.35 then
                        return
                    end
                    recordShot(tool)
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

                        if jumped > 25 and elapsed < 0.15 and jumped < 3000 then
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
                        if root and head then
                            local offset: number =
                                (head.Position - root.Position).Magnitude
                            if offset > 3.2 or offset < 0.9 then
                                anomaly = "headOffset"
                            end
                        end
                        if not anomaly and root and torso then
                            local torsoY: number = torso.Size.Y
                            if torsoY > 2.6 or torsoY < 0.7 then
                                anomaly = "torsoSize"
                            end
                        end
                        if anomaly then
                            local lastFlag: number? = runtime.anomalyCooldown[player]
                            if not lastFlag or os.clock() - lastFlag > 5 then
                                runtime.anomalyCooldown[player] = os.clock()
                                runtime.aggregates.hitboxAnomalies += 1
                                runtime.revision += 1
                                runtime.saveDirty = true
                            end
                        end
                    end
                end
            end)
        end

        local function buildInsights(): {string}
            local agg = runtime.aggregates
            return {
                string.format("%d attempts; %d observations confirmed; %d intended-target gun impacts.",
                    agg.shots, agg.confirmations, agg.targetHits),
                string.format("%d projectile observations are NOT impact/damage confirmations.", agg.projectileObservations),
                string.format("%d attempts unconfirmed; absence of evidence is NOT a miss.", agg.unconfirmed),
                string.format("%d temporally associated deaths do NOT establish who caused them.", agg.deathAssociations),
                "Local movement/geometry observations do not establish server tolerance or successful hitbox manipulation.",
            }
        end

        local MAX_STORED_EVENTS: number = 3000

        local function loadStoredLogs(): ()
            if runtime.historyLoaded then return end
            runtime.historyLoaded = true
            if type(executorEnvironment.readfile) ~= "function" then
                runtime.persistenceBlocked = true
                return
            end
            local ok, raw = pcall(executorEnvironment.readfile, outputPath)
            if not ok then
                local okExists, exists = pcall(function() return executorEnvironment.isfile(outputPath) end)
                runtime.persistenceBlocked = not (okExists and exists == false)
                return
            end
            if type(raw) ~= "string" then runtime.persistenceBlocked = true; return end
            if #raw == 0 then return end
            local backup = outputPath .. ".before-" .. runtime.sessionId .. ".json"
            local okBackup = type(executorEnvironment.writefile) == "function"
                and pcall(executorEnvironment.writefile, backup, raw)
            local okVerify, backedUp = pcall(executorEnvironment.readfile, backup)
            if not okBackup or not okVerify or backedUp ~= raw then
                runtime.persistenceBlocked = true
                notify("Game Learning: history backup failed; existing file protected")
                return
            end
            runtime.historyBackup = backup
            -- Retained logs stay in the backup, never in this session's counters.
        end

        saveSnapshot = function(reason: string?, silent: boolean?): boolean
            if runtime.persistenceBlocked then return false end
            loadStoredLogs()
            if runtime.persistenceBlocked then return false end
            if type(executorEnvironment.writefile) ~= "function" then
                return false
            end
            if type(executorEnvironment.makefolder) == "function" then
                pcall(executorEnvironment.makefolder, outputRoot)
                pcall(executorEnvironment.makefolder, outputTelemetry)
                pcall(executorEnvironment.makefolder, outputFolder)
            end
            while #runtime.shots > MAX_STORED_EVENTS do
                table.remove(runtime.shots, 1)
            end
            while #runtime.movements > MAX_STORED_EVENTS do
                table.remove(runtime.movements, 1)
            end
            while #runtime.hits > MAX_STORED_EVENTS do
                table.remove(runtime.hits, 1)
            end
            local savedRevision = runtime.revision
            local payload: {[string]: any} = {
                schema = 2,
                buildStamp = runtime.buildStamp,
                sessionId = runtime.sessionId,
                historyBackup = runtime.historyBackup,
                kind = "game-learning-log",
                outcomeContract = "attempts != confirmations != impacts; kills not measured; legacy kill/miss fields are unused",
                placeId = game.PlaceId,
                savedAt = os.time(),
                savedReason = reason or "manual",
                session = {
                    startedAt = runtime.startedAt,
                    countersScope = "this-session-only",
                    uptimeSeconds = math.floor(os.clock() - runtime.startedClock),
                },
                aggregates = runtime.aggregates,
                insights = buildInsights(),
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
                runtime.saveDirty = runtime.revision ~= savedRevision
                if not silent then
                    notify("Game Learning: saved " .. outputPath)
                end
            end
            return okWrite
        end
        local function status(): string
            local agg = runtime.aggregates
            return string.format("%d attempts · %d confirmed · %d target hits · %d unconfirmed",
                agg.shots, agg.confirmations, agg.targetHits, agg.unconfirmed)
        end

        local function deleteLogs(): boolean
            for key in pairs(runtime.aggregates) do runtime.aggregates[key] = 0 end
            runtime.sessionId = httpService:GenerateGUID(false)
            runtime.startedAt = os.time()
            runtime.startedClock = os.clock()
            runtime.spawnShots = {}
            runtime.spawnKills = {}
            runtime.shots = {}
            runtime.hits = {}
            runtime.movements = {}
            runtime.shotCounter = 0
            runtime.saveDirty = false
            local deleteFile: any = executorEnvironment.delfile
            local okDelete: boolean = false
            if type(deleteFile) == "function" then
                okDelete = pcall(deleteFile, outputPath)
            elseif type(executorEnvironment.writefile) == "function" then
                okDelete = pcall(executorEnvironment.writefile, outputPath, "{}")
            end
            notify("Game Learning: history cleared")
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

                runtime.watchedPlayers = setmetatable({}, {__mode = "k"})
                if runtime.movementTask then
                    runtime.movementTask:Disconnect()
                    runtime.movementTask = nil
                end
                if runtime.hitboxTask then
                    runtime.hitboxTask:Disconnect()
                    runtime.hitboxTask = nil
                end
                if runtime.autosaveTask then
                    runtime.autosaveTask:Disconnect()
                    runtime.autosaveTask = nil
                end
                if runtime.saveDirty then

                    saveSnapshot("disabled")
                end
                return
            end
            runtime.enabled = true
            loadStoredLogs()
            startMovementProbe()
            startHitboxProbe()
            if not runtime.autosaveTask then
                local elapsed: number = 0
                runtime.autosaveTask = TaskManager:Connect(function(deltaTime: number): ()
                    elapsed += deltaTime
                    if elapsed < 15 then
                        return
                    end
                    elapsed = 0
                    if runtime.enabled and runtime.saveDirty then
                        saveSnapshot("autosave", true)
                    end
                end)
            end
            observeContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
            observeContainer(LocalPlayer.Character)
            table.insert(
                runtime.connections,
                LocalPlayer.CharacterAdded:Connect(function(character: Model): ()
                    observeContainer(character)
                end)
            )
            table.insert(
                runtime.connections,
                UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean): ()
                    if isMM2 or gameProcessed then
                        return
                    end
                    if input.UserInputType ~= Enum.UserInputType.MouseButton1
                        and input.UserInputType ~= Enum.UserInputType.Touch then
                        return
                    end
                    if not (runtime.enabled and tuning.logShots) then
                        return
                    end
                    local character: Model? = LocalPlayer.Character
                    local equippedTool: Tool? = character and character:FindFirstChildOfClass("Tool")
                    if not equippedTool then
                        return
                    end
                    if os.clock() - runtime.lastAuthoredAt < 0.35 then
                        return
                    end
                    runtime.lastAuthoredAt = os.clock()
                    recordShot(equippedTool)
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
        controller.flush = function(): boolean
            if not runtime.enabled then
                return false
            end
            return saveSnapshot("close")
        end
        controller.noteAuthoringShot = function(selfOrInfo: any, maybeInfo: any): ()
            local info: any = if type(maybeInfo) == "table" then maybeInfo else selfOrInfo
            if runtime.enabled and tuning.logShots and type(info) == "table" then
                recordAuthoredShot(info)
            end
        end
        controller.noteConfirmation = function(info: any): ()
            if runtime.enabled and tuning.logShots then recordConfirmation(info) end
        end
        controller.delete = function(): boolean
            return deleteLogs()
        end
        controller.status = status
        return controller
    end)()

    local gameLearning: any = controllerFactory

    if gameBridge and type(gameBridge.onEvent) == "function" then
        gameBridge.onEvent(function(eventType: string, payload: any): ()
            if eventType == "authoringShot" then
                gameLearning:noteAuthoringShot(payload)
            elseif eventType == "shotConfirmation" then
                gameLearning.noteConfirmation(payload)
            end
        end)
    end

    pcall(function(): ()
        if type((game :: any).BindToClose) == "function" then
            game:BindToClose(function(): ()
                pcall(gameLearning.flush, gameLearning)
            end)
        end
    end)

    local GameLearningFeature: any = state.metricsFeature
    if not GameLearningFeature then
        GameLearningFeature = createUniversalFeature(
            "Metrics",
            "Calibration and game-learning telemetry in one card: projectile "
                .. "analytics, client observations, motion calibration.",
            16,
            function(_enabled: boolean): () end,
            {category = true, categoryName = "Other"}
        )
        state.metricsFeature = GameLearningFeature
    end
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
            .. "character. These are local observations, not proof of server tolerance."
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
        "Observation window",
        gameLearning.tuning.killWindowSeconds,
        1,
        10,
        function(value: number): ()
            gameLearning.tuning.killWindowSeconds = value
        end,
        "Seconds for observing a nearby-in-time death; this does not attribute a kill.",
        0.5
    )
    addActionOption(GameLearningFeature, "Learning status", function(): ()
        notify(gameLearning:status())
    end)
    addActionOption(GameLearningFeature, "Save learning logs", function(): ()
        gameLearning:save()
    end)
    addActionOption(GameLearningFeature, "Clear learning logs", function(): ()
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
