--!strict
--
-- Projectile calibration.
--
-- Watches what leaves your hands and how long it takes to arrive: activation
-- to impact, bucketed by ping, so a predictor has real numbers for this game
-- instead of a constant somebody guessed. It is analytics, not an advantage —
-- nothing here fires, aims or moves anything.
--
-- It used to live in the shell, six hundred lines of it, wedged between the
-- window and the card grid because that is where it was first written. It is a
-- module: it owns a card, a runtime and a teardown, and the shell knows
-- nothing about it beyond loading the file.
--
-- The dataset is deliberately isolated from every game-specific predictor;
-- MM2 never reads or merges these values.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "ProjectileCalibration",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeController: any = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local state: any = host.state
    local notify: any = host.notify
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local addActionOption: any = host.addActionOption
    local addInformationOption: any = host.addInformationOption
    local TaskManager: any = host.TaskManager
    local LocalPlayer: any = host.LocalPlayer
    local HttpService: any = host.HttpService
    local Stats: any = host.Stats

    -- Generic, automatic projectile telemetry. This dataset is intentionally isolated
    -- from every game-specific predictor; MM2 never reads or merges these values.
    local controllerFactory = (function(): any
        type PendingActivation = {
            tool: Tool,
            activatedAt: number,
            origin: Vector3?,
            aim: Vector3?,
            pingMs: number,
        }
        type ProjectileSample = {
            t: number,
            position: {number},
            velocity: {number},
            speed: number,
        }
        type ProjectileTrack = {
            instance: BasePart,
            toolName: string,
            projectileName: string,
            startedAt: number,
            launchDelayMs: number,
            pingMs: number,
            origin: Vector3,
            previousAt: number?,
            previousPosition: Vector3?,
            speeds: {number},
            accelerations: {number},
            verticalAccelerations: {number},
            samples: {ProjectileSample},
            distance: number,
            destroyConnection: RBXScriptConnection?,
        }
        type BucketRecord = {
            count: number,
            speedSum: number,
            speedSquaredSum: number,
            delaySum: number,
        }
        type Controller = {
            setEnabled: (self: Controller, enabled: boolean) -> (),
            save: (self: Controller, reason: string?) -> boolean,
            delete: (self: Controller) -> boolean,
            status: (self: Controller) -> string,
            destroy: (self: Controller) -> (),
            tuning: {[string]: number},
        }

        -- Live-tuning knobs for the analyser. The option panel mutates these
        -- while the tracker keeps running, so a calibration session can be
        -- refined without restarting it.
        local tuning: {[string]: number} = {
            bucketWidthMs = 5,
            maxBucketMs = 250,
            sampleWindowSeconds = 2.5,
            maxSamplesPerTrack = 150,
            minProjectileSpeed = 10,
            matchDistanceStuds = 40,
            maxPendingActivations = 10,
            candidateLifetimeSeconds = 1.1,
        }

        local executorEnvironment: {[string]: any} = getfenv() :: any
        local mouse: Mouse = LocalPlayer:GetMouse()
        local outputRoot: string = "RandomTestingMenu0001"
        local outputTelemetry: string = outputRoot .. "/Telemetry"
        local outputFolder: string = outputTelemetry .. "/Universal"
        local outputPath: string = outputFolder
            .. "/Place_"
            .. tostring(game.PlaceId)
            .. "_Projectile_Calibration.json"
        local runtime: any = {
            enabled = false,
            dirty = false,
            startedAt = os.clock(),
            pending = {} :: {PendingActivation},
            tracks = {} :: {[BasePart]: ProjectileTrack},
            events = {} :: {{[string]: any}},
            buckets = {} :: {[string]: BucketRecord},
            connections = {} :: {RBXScriptConnection},
            observedTools = setmetatable({}, {__mode = "k"}) :: {[Tool]: boolean},
            observedCandidates = setmetatable({}, {__mode = "k"}) :: {[BasePart]: boolean},
            sampler = nil :: any,
            totalActivations = 0,
            totalProjectiles = 0,
            rejectedCandidates = 0,
        }
        local controller: Controller
        local saveSnapshot: (reason: string) -> boolean
        local finishTrack: (part: BasePart, reason: string) -> ()

        local function finite(value: number): boolean
            return value == value and value > -math.huge and value < math.huge
        end

        local function vectorArray(value: Vector3): {number}
            return {value.X, value.Y, value.Z}
        end

        local function median(values: {number}): number?
            if #values == 0 then
                return nil
            end
            local sorted: {number} = table.clone(values)
            table.sort(sorted)
            local middle: number = math.floor((#sorted + 1) / 2)
            if #sorted % 2 == 1 then
                return sorted[middle]
            end
            return (sorted[middle] + sorted[middle + 1]) * 0.5
        end

        local function pingBucketKey(pingMs: number): string
            local width: number = math.max(1, tuning.bucketWidthMs)
            local ceiling: number = math.max(width, tuning.maxBucketMs)
            if pingMs > ceiling then
                return tostring(ceiling) .. "+"
            end
            local lower: number = math.clamp(
                math.floor(pingMs / width) * width,
                0,
                math.max(0, ceiling - width)
            )
            local upper: number = lower + width
            return string.format("%03d-%03d", lower, upper)
        end

        local function ensureBucket(key: string): BucketRecord
            local existing: BucketRecord? = runtime.buckets[key]
            if existing then
                return existing
            end
            local created: BucketRecord = {
                count = 0,
                speedSum = 0,
                speedSquaredSum = 0,
                delaySum = 0,
            }
            runtime.buckets[key] = created
            return created
        end

        local function bucketPayload(): {[string]: any}
            local payload: {[string]: any} = {}
            for key: string, bucket: BucketRecord in pairs(runtime.buckets) do
                local meanSpeed: number = bucket.count > 0
                        and bucket.speedSum / bucket.count
                    or 0
                local variance: number = bucket.count > 1
                        and math.max(
                            0,
                            bucket.speedSquaredSum / bucket.count
                                - meanSpeed * meanSpeed
                        )
                    or 0
                payload[key] = {
                    count = bucket.count,
                    meanSpeed = meanSpeed,
                    speedStdDev = math.sqrt(variance),
                    meanLaunchDelayMs = bucket.count > 0
                            and bucket.delaySum / bucket.count
                        or 0,
                }
            end
            return payload
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
            return math.max(0, pingMs)
        end

        local function appendEvent(event: {[string]: any}): ()
            if #runtime.events >= 180 then
                table.remove(runtime.events, 1)
            end
            table.insert(runtime.events, event)
            runtime.dirty = true
        end

        saveSnapshot = function(reason: string): boolean
            if type(executorEnvironment.writefile) ~= "function" then
                warn("[RTM:UniversalTrajectory] writefile no está disponible.")
                return false
            end
            local payload: {[string]: any} = {
                schema = 1,
                kind = "universal-projectile-analytics",
                placeId = game.PlaceId,
                gameId = game.GameId,
                savedAt = DateTime.now():ToIsoDate(),
                reason = reason,
                bucketSpec = {
                    metric = "Data Ping",
                    widthMs = tuning.bucketWidthMs,
                    minimumMs = 0,
                    maximumMs = tuning.maxBucketMs,
                    overflow = tostring(tuning.maxBucketMs) .. "+",
                },
                summary = {
                    activations = runtime.totalActivations,
                    projectiles = runtime.totalProjectiles,
                    rejectedCandidates = runtime.rejectedCandidates,
                    elapsedSeconds = os.clock() - runtime.startedAt,
                },
                pingBuckets = bucketPayload(),
                projectiles = runtime.events,
            }
            local encodedOk: boolean, encoded: any = pcall(
                HttpService.JSONEncode,
                HttpService,
                payload
            )
            if not encodedOk or type(encoded) ~= "string" then
                warn("[RTM:UniversalTrajectory] JSONEncode falló: " .. tostring(encoded))
                return false
            end
            if type(executorEnvironment.makefolder) == "function" then
                pcall(executorEnvironment.makefolder, outputRoot)
                pcall(executorEnvironment.makefolder, outputTelemetry)
                pcall(executorEnvironment.makefolder, outputFolder)
            end
            local writeOk: boolean, writeError: any = pcall(
                executorEnvironment.writefile,
                outputPath,
                encoded
            )
            if not writeOk then
                warn("[RTM:UniversalTrajectory] writefile falló: " .. tostring(writeError))
                return false
            end
            runtime.dirty = false
            print(
                "[RTM:UniversalTrajectory] Guardado "
                    .. outputPath
                    .. " ("
                    .. tostring(#encoded)
                    .. " bytes)"
            )
            return true
        end

        local function disconnectAll(): ()
            if runtime.sampler then
                runtime.sampler:Disconnect()
                runtime.sampler = nil
            end
            for _, connection: RBXScriptConnection in ipairs(runtime.connections) do
                connection:Disconnect()
            end
            table.clear(runtime.connections)
            for part: BasePart, track: ProjectileTrack in pairs(runtime.tracks) do
                if track.destroyConnection then
                    track.destroyConnection:Disconnect()
                end
                runtime.tracks[part] = nil
            end
            table.clear(runtime.pending)
            runtime.observedTools = setmetatable({}, {__mode = "k"})
            runtime.observedCandidates = setmetatable({}, {__mode = "k"})
        end

        local function compactPending(now: number): ()
            while #runtime.pending > 0
                and now - runtime.pending[1].activatedAt
                    > tuning.candidateLifetimeSeconds do
                table.remove(runtime.pending, 1)
            end
            while #runtime.pending > tuning.maxPendingActivations do
                table.remove(runtime.pending, 1)
            end
        end

        local function isCharacterPart(part: BasePart): boolean
            local model: Model? = part:FindFirstAncestorOfClass("Model")
            return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
        end

        local function hasProjectileHint(part: BasePart): boolean
            local name: string = string.lower(part.Name)
            local parentName: string = part.Parent and string.lower(part.Parent.Name) or ""
            local combined: string = name .. " " .. parentName
            return string.find(combined, "projectile", 1, true) ~= nil
                or string.find(combined, "bullet", 1, true) ~= nil
                or string.find(combined, "arrow", 1, true) ~= nil
                or string.find(combined, "rocket", 1, true) ~= nil
                or string.find(combined, "missile", 1, true) ~= nil
                or string.find(combined, "knife", 1, true) ~= nil
                or string.find(combined, "grenade", 1, true) ~= nil
                or string.find(combined, "shell", 1, true) ~= nil
                or string.find(combined, "bolt", 1, true) ~= nil
                or string.find(combined, "orb", 1, true) ~= nil
                or part:GetAttribute("Projectile") == true
                or part:GetAttribute("ProjectileSpeed") ~= nil
                or part:GetAttribute("ThrowSpeed") ~= nil
        end

        local function resolveCandidate(instance: Instance): BasePart?
            if not instance:IsA("BasePart") then
                return nil
            end
            local part: BasePart = instance
            if part.Anchored
                or isCharacterPart(part)
                or (LocalPlayer.Character and part:IsDescendantOf(LocalPlayer.Character)) then
                return nil
            end
            local root: BasePart = part.AssemblyRootPart or part
            if runtime.observedCandidates[root] or isCharacterPart(root) then
                return nil
            end
            return root
        end

        local function ensureSampler(): ()
            if runtime.sampler then
                return
            end
            runtime.sampler = TaskManager:Connect(function(_deltaTime: number): ()
                local now: number = os.clock()
                local completed: {BasePart} = {}
                for part: BasePart, track: ProjectileTrack in pairs(runtime.tracks) do
                    if not part.Parent
                        or now - track.startedAt >= tuning.sampleWindowSeconds then
                        table.insert(completed, part)
                        continue
                    end
                    local position: Vector3 = part.Position
                    local velocity: Vector3 = part.AssemblyLinearVelocity
                    local speed: number = velocity.Magnitude
                    if track.previousPosition and track.previousAt then
                        local deltaTime: number = now - track.previousAt
                        if deltaTime >= 1 / 240 then
                            local measuredVelocity: Vector3 =
                                (position - track.previousPosition) / deltaTime
                            local measuredSpeed: number = measuredVelocity.Magnitude
                            if measuredSpeed >= 1 and measuredSpeed <= 5000 then
                                table.insert(track.speeds, measuredSpeed)
                                if #track.samples > 0 then
                                    local previousSample: ProjectileSample =
                                        track.samples[#track.samples]
                                    local previousVelocity: Vector3 = Vector3.new(
                                        previousSample.velocity[1],
                                        previousSample.velocity[2],
                                        previousSample.velocity[3]
                                    )
                                    local acceleration: Vector3 =
                                        (measuredVelocity - previousVelocity) / deltaTime
                                    if acceleration.Magnitude <= 10000 then
                                        table.insert(track.accelerations, acceleration.Magnitude)
                                        table.insert(track.verticalAccelerations, acceleration.Y)
                                    end
                                end
                            end
                            track.distance += (position - track.previousPosition).Magnitude
                        end
                    end
                    if #track.samples < tuning.maxSamplesPerTrack then
                        table.insert(track.samples, {
                            t = now - track.startedAt,
                            position = vectorArray(position),
                            velocity = vectorArray(velocity),
                            speed = speed,
                        })
                    end
                    track.previousPosition = position
                    track.previousAt = now
                end
                for _, part: BasePart in ipairs(completed) do
                    finishTrack(part, "sample-window-complete")
                end
                if next(runtime.tracks) == nil and runtime.sampler then
                    runtime.sampler:Disconnect()
                    runtime.sampler = nil
                end
            end)
        end

        finishTrack = function(part: BasePart, reason: string): ()
            local track: ProjectileTrack? = runtime.tracks[part]
            if not track then
                return
            end
            runtime.tracks[part] = nil
            if track.destroyConnection then
                track.destroyConnection:Disconnect()
                track.destroyConnection = nil
            end
            local speed: number? = median(track.speeds)
            if not speed or not finite(speed) or speed < 1 then
                runtime.rejectedCandidates += 1
                return
            end
            local acceleration: number? = median(track.accelerations)
            local verticalAcceleration: number? = median(track.verticalAccelerations)
            local bucketKey: string = pingBucketKey(track.pingMs)
            local bucket: BucketRecord = ensureBucket(bucketKey)
            bucket.count += 1
            bucket.speedSum += speed
            bucket.speedSquaredSum += speed * speed
            bucket.delaySum += track.launchDelayMs
            runtime.totalProjectiles += 1
            appendEvent({
                tool = track.toolName,
                projectile = track.projectileName,
                pingMs = track.pingMs,
                pingBucket = bucketKey,
                launchDelayMs = track.launchDelayMs,
                medianSpeed = speed,
                medianAcceleration = acceleration,
                medianVerticalAcceleration = verticalAcceleration,
                distanceStuds = track.distance,
                durationSeconds = os.clock() - track.startedAt,
                reason = reason,
                samples = track.samples,
            })
        end

        local function considerCandidate(instance: Instance): ()
            if not runtime.enabled or #runtime.pending == 0 then
                return
            end
            local part: BasePart? = resolveCandidate(instance)
            if not part then
                return
            end
            local now: number = os.clock()
            compactPending(now)
            if #runtime.pending == 0 then
                return
            end
            local hinted: boolean = hasProjectileHint(part)
            local speed: number = part.AssemblyLinearVelocity.Magnitude
            if not hinted and speed < tuning.minProjectileSpeed then
                return
            end
            local selectedIndex: number? = nil
            local selectedScore: number = math.huge
            for index: number = #runtime.pending, 1, -1 do
                local pending: PendingActivation = runtime.pending[index]
                if not part:IsDescendantOf(pending.tool) and pending.origin then
                    local offset: Vector3 = part.Position - pending.origin
                    local distance: number = offset.Magnitude
                    if distance <= 40 then
                        local alignmentPenalty: number = 0
                        if pending.aim and distance > 0.01 then
                            local desired: Vector3 = pending.aim - pending.origin
                            if desired.Magnitude > 0.01 then
                                local alignment: number = offset.Unit:Dot(desired.Unit)
                                if alignment < 0.35 and not hinted then
                                    continue
                                end
                                alignmentPenalty = (1 - alignment) * 0.25
                            end
                        end
                        local score: number = now - pending.activatedAt
                            + distance * 0.01
                            + alignmentPenalty
                            + (hinted and 0 or 0.2)
                        if score < selectedScore then
                            selectedScore = score
                            selectedIndex = index
                        end
                    end
                end
            end
            if not selectedIndex then
                runtime.rejectedCandidates += 1
                return
            end
            local pending: PendingActivation = table.remove(runtime.pending, selectedIndex)
            runtime.observedCandidates[part] = true
            local track: ProjectileTrack = {
                instance = part,
                toolName = pending.tool.Name,
                projectileName = part:GetFullName(),
                startedAt = now,
                launchDelayMs = math.max(0, (now - pending.activatedAt) * 1000),
                pingMs = pending.pingMs,
                origin = pending.origin :: Vector3,
                previousAt = now,
                previousPosition = part.Position,
                speeds = {},
                accelerations = {},
                verticalAccelerations = {},
                samples = {},
                distance = 0,
                destroyConnection = nil,
            }
            runtime.tracks[part] = track
            track.destroyConnection = part.Destroying:Connect(function(): ()
                finishTrack(part, "destroyed")
            end)
            ensureSampler()
        end

        local function observeTool(tool: Tool): ()
            if runtime.observedTools[tool] then
                return
            end
            runtime.observedTools[tool] = true
            table.insert(runtime.connections, tool.Activated:Connect(function(): ()
                if not runtime.enabled then
                    return
                end
                local originPart: BasePart? = tool:FindFirstChild("Handle") :: BasePart?
                local characterRoot: BasePart? = LocalPlayer.Character
                    and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    :: BasePart?
                local origin: Vector3? = originPart and originPart:IsA("BasePart")
                        and originPart.Position
                    or characterRoot and characterRoot.Position
                    or nil
                if not origin then
                    return
                end
                local aim: Vector3? = nil
                pcall(function(): ()
                    aim = mouse.Hit.Position
                end)
                runtime.totalActivations += 1
                table.insert(runtime.pending, {
                    tool = tool,
                    activatedAt = os.clock(),
                    origin = origin,
                    aim = aim,
                    pingMs = getPingMilliseconds(),
                })
                compactPending(os.clock())
            end))
        end

        local function observeContainer(container: Instance?): ()
            if not container then
                return
            end
            for _, child: Instance in ipairs(container:GetChildren()) do
                if child:IsA("Tool") then
                    observeTool(child)
                end
            end
            table.insert(runtime.connections, container.ChildAdded:Connect(function(
                child: Instance
            ): ()
                if child:IsA("Tool") then
                    observeTool(child)
                end
            end))
        end

        controller = {} :: Controller
        controller.tuning = tuning

        function controller:setEnabled(enabled: boolean): ()
            if runtime.enabled == enabled then
                return
            end
            if not enabled then
                runtime.enabled = false
                disconnectAll()
                print("[RTM:UniversalTrajectory] Calibración detenida.")
                return
            end
            runtime.enabled = true
            runtime.startedAt = os.clock()
            observeContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
            observeContainer(LocalPlayer.Character)
            table.insert(runtime.connections, LocalPlayer.CharacterAdded:Connect(function(
                character: Model
            ): ()
                observeContainer(character)
            end))
            table.insert(runtime.connections, workspace.DescendantAdded:Connect(
                considerCandidate
            ))
            print(
                "[RTM:UniversalTrajectory] Activa · buckets "
                    .. tostring(tuning.bucketWidthMs)
                    .. " ms · salida "
                    .. outputPath
            )
        end

        function controller:save(reason: string?): boolean
            return saveSnapshot(reason or "manual")
        end

        function controller:delete(): boolean
            local deleteFile: any = executorEnvironment.delfile
            local isFile: any = executorEnvironment.isfile
            if type(deleteFile) ~= "function" then
                warn("[RTM:UniversalTrajectory] delfile no está disponible.")
                return false
            end
            local exists: boolean = true
            if type(isFile) == "function" then
                local checked: boolean, result: any = pcall(isFile, outputPath)
                exists = checked and result == true
            end
            if exists then
                local deleted: boolean, deleteError: any = pcall(deleteFile, outputPath)
                if not deleted then
                    warn(
                        "[RTM:UniversalTrajectory] delfile falló: "
                            .. tostring(deleteError)
                    )
                    return false
                end
            end
            runtime.events = {}
            runtime.buckets = {}
            runtime.totalActivations = 0
            runtime.totalProjectiles = 0
            runtime.rejectedCandidates = 0
            runtime.dirty = false
            print("[RTM:UniversalTrajectory] Dataset de esta sesión eliminado.")
            return true
        end

        function controller:status(): string
            return string.format(
                "Universal · activaciones %d · proyectiles %d · buckets %d",
                runtime.totalActivations,
                runtime.totalProjectiles,
                (function(): number
                    local count: number = 0
                    for _key: string in pairs(runtime.buckets) do
                        count += 1
                    end
                    return count
                end)()
            )
        end

        function controller:destroy(): ()
            self:setEnabled(false)
        end

        return controller
    end)()


    local calibration: any = controllerFactory
    state.universalProjectileCalibration = calibration
    calibration:setEnabled(true)

    local tuning: any = calibration.tuning
    state.projectileSettings = tuning

    local ProjectileCalibrationFeature: any = createUniversalFeature(
        "Projectile Calibration",
        "Automatic per-game projectile analytics with tunable ping buckets",
        17,
        function(_enabled: boolean): () end,
        {category = true}
    )
    tuning =
        calibration.tuning
    addNumberOption(
        ProjectileCalibrationFeature,
        "Bucket width (ms)",
        tuning.bucketWidthMs,
        1,
        25,
        function(value: number): ()
            tuning.bucketWidthMs = math.round(value)
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Bucket ceiling (ms)",
        tuning.maxBucketMs,
        25,
        500,
        function(value: number): ()
            tuning.maxBucketMs = math.round(value)
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Sample window (s)",
        tuning.sampleWindowSeconds,
        1,
        6,
        function(value: number): ()
            tuning.sampleWindowSeconds = value
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Max samples / track",
        tuning.maxSamplesPerTrack,
        30,
        600,
        function(value: number): ()
            tuning.maxSamplesPerTrack = math.round(value)
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Match radius (studs)",
        tuning.matchDistanceStuds,
        10,
        120,
        function(value: number): ()
            tuning.matchDistanceStuds = math.round(value)
        end
    )
    addNumberOption(
        ProjectileCalibrationFeature,
        "Min projectile speed",
        tuning.minProjectileSpeed,
        1,
        100,
        function(value: number): ()
            tuning.minProjectileSpeed = math.round(value)
        end
    )
    addActionOption(ProjectileCalibrationFeature, "Show status", function(): ()
        notify(calibration:status())
    end)
    addActionOption(ProjectileCalibrationFeature, "Save analytics", function(): ()
        if calibration:save("manual") then
            notify("Universal projectile analytics saved in the executor workspace.")
        else
            notify("Universal projectile analytics could not be saved; check F9.")
        end
    end)
    addActionOption(ProjectileCalibrationFeature, "Delete analytics", function(): ()
        if calibration:delete() then
            notify("Universal projectile analytics deleted for this PlaceId.")
        else
            notify("Universal projectile analytics could not be deleted; check F9.")
        end
    end)
    addInformationOption(
        ProjectileCalibrationFeature,
        "Runs automatically. Save writes the current session; Delete clears it. MM2 prediction never consumes this dataset."
    )

    activeController = calibration
    Module.Initialized = true
    return calibration
end

function Module.destroy(): ()
    if activeController and type(activeController.destroy) == "function" then
        pcall(function(): ()
            activeController:destroy()
        end)
    end
    activeController = nil
    Module.Initialized = false
end

return Module
