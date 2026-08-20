--!strict

local Module = {
    Name = "MVSD",
    PlaceId = 135856908115931,
    Events = {} :: {[string]: any},
    Initialized = false,
    Menu = nil :: any,
    Runtime = nil :: any,
}

-- MVSD combat module (Murderers vs Sheriffs Duels).
--
-- Reverse-engineered from the live game (PlaceId 135856908115931):
--   * Real team values are attributes: player:GetAttribute("Team") returns
--     "TeamRed" / "TeamBlue" (or a non-team value in FFA). Same value = teammate.
--     player:GetAttribute("Game") is the running match id, player:GetAttribute("Died")
--     is a boolean, player:GetAttribute("Spectating") the match being watched.
--   * The client aims with MouseCast: Camera:ViewportPointToRay(mouse) ->
--     workspace:Raycast(cameraPos, dir * 500, params). The gun reuses this aim,
--     so redirecting camera-origin raycasts redirects the weapon.
--   * The server computes the final hit and echoes the beam via Remotes.Beam.
--
-- Silent aim avoids __namecall entirely: it hooks Ray.new (hookfunction on the
-- constructor) and hooks workspace.Raycast by replacing the instance method
-- closure with hookfunction. Both redirect the ray direction onto the predicted
-- target part. Wall check OFF swaps the params to an Include filter containing
-- only the target part, which makes the ray ignore every map wall.
--
-- The game client has no dedicated anticheat (no client-side detection/kick
-- scripts); the only Kick is inside the admin "conch" console. The module never
-- sets player attributes or fires fake remotes, so it does not feed the
-- server-side validation. Input is simulated with mouse1press/mouse1release.

type AimSettings = {
    teamCheck: boolean,
    aimEnabled: boolean,
    autoShootEnabled: boolean,
    triggerCueEnabled: boolean,
    showCircle: boolean,
    dynamicFov: boolean,
    infiniteRange: boolean,
    wallCheck: boolean,
    aimOnClick: boolean,
    hitChance: number,
    headshotChance: number,
    maxAimAngle: number,
    targetMode: string,
    targetPart: string,
    fovRadius: number,
    maxDistance: number,
    projectileSpeed: number,
    predictionMultiplier: number,
    shotDelay: number,
    humanizeDelay: number,
    triggerTolerance: number,
    triggerDelay: number,
}

type MotionRecord = {
    velocity: Vector3,
    acceleration: Vector3,
}

type TargetRecord = {
    player: Player,
    character: Model,
    part: BasePart,
    screenPosition: Vector2,
    predictedPosition: Vector3,
    distance: number,
    cursorDistance: number,
}

type RedirectResult = {
    origin: Vector3,
    direction: Vector3,
    wallParams: RaycastParams?,
}

type VisualRecord = {
    root: Frame,
    circle: Frame,
    circleStroke: UIStroke,
    marker: Frame,
    markerStroke: UIStroke,
    status: TextLabel,
}

type AimRuntime = {
    visuals: VisualRecord?,
    motion: {[Player]: MotionRecord},
    selected: TargetRecord?,
    triggerEnteredAt: number?,
    rayHookInstalled: boolean,
    oldRay: any,
    rayHookWrapper: any,
    raycastHookInstalled: boolean,
    oldRaycast: any,
    raycastHookWrapper: any,
    suppressRaycast: boolean,
    autoShootHeld: boolean,
    autoShootNextAt: number,
}

local moduleCleanup: () -> () = function(): () end

local function buildMVSDFeatures(): ()
    local settings: AimSettings = {
        teamCheck = true,
        aimEnabled = false,
        autoShootEnabled = false,
        triggerCueEnabled = false,
        showCircle = true,
        dynamicFov = true,
        infiniteRange = false,
        wallCheck = true,
        aimOnClick = false,
        hitChance = 95,
        headshotChance = 75,
        maxAimAngle = 25,
        targetMode = "Closest to Cursor",
        targetPart = "Head",
        fovRadius = 180,
        maxDistance = 600,
        projectileSpeed = 350,
        predictionMultiplier = 1,
        shotDelay = 0,
        humanizeDelay = 0.04,
        triggerTolerance = 11,
        triggerDelay = 0,
    }
    local runtime: AimRuntime = {
        visuals = nil,
        motion = {},
        selected = nil,
        triggerEnteredAt = nil,
        rayHookInstalled = false,
        oldRay = nil,
        rayHookWrapper = nil,
        raycastHookInstalled = false,
        oldRaycast = nil,
        raycastHookWrapper = nil,
        suppressRaycast = false,
        autoShootHeld = false,
        autoShootNextAt = 0,
    }

    local function getRoot(character: Model?): BasePart?
        if not character then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart") :: BasePart?
            or character.PrimaryPart
    end

    local function getTargetPart(character: Model): BasePart?
        if settings.targetPart == "Head" then
            local head: Instance? = character:FindFirstChild("Head")
            if head and head:IsA("BasePart") then
                return head
            end
        end
        return getRoot(character)
    end

    -- Real game team/round/died logic. Same Team attribute string = teammate.
    local function isSameTeam(a: Player, b: Player): boolean
        local aTeam: any = a:GetAttribute("Team")
        local bTeam: any = b:GetAttribute("Team")
        return type(aTeam) == "string"
            and type(bTeam) == "string"
            and aTeam == bTeam
    end

    local function isInMatch(player: Player): boolean
        local localGame: any = LocalPlayer:GetAttribute("Game")
        local playerGame: any = player:GetAttribute("Game")
        if type(localGame) ~= "string" then
            return false
        end
        if type(playerGame) ~= "string" then
            return false
        end
        return playerGame == localGame
    end

    -- Valid opponent for combat features (silent aim / auto shoot).
    local function isActiveOpponent(player: Player): boolean
        if player == LocalPlayer or player:GetAttribute("Died") == true then
            return false
        end
        if not isInMatch(player) then
            return false
        end
        if settings.teamCheck and isSameTeam(LocalPlayer, player) then
            return false
        end
        local character: Model? = player.Character
        local humanoid: Humanoid? = if character
            then character:FindFirstChildOfClass("Humanoid")
            else nil
        return character ~= nil
            and humanoid ~= nil
            and humanoid.Health > 0
            and getTargetPart(character) ~= nil
    end

    local function getPingSeconds(): number
        local network: Instance? = Stats:FindFirstChild("Network")
        local serverStats: Instance? = if network
            then network:FindFirstChild("ServerStatsItem")
            else nil
        local pingItem: Instance? = if serverStats
            then serverStats:FindFirstChild("Data Ping")
            else nil
        if not pingItem then
            return 0.05
        end
        local okValue: boolean, rawValue: any = pcall(function(): any
            return (pingItem :: any):GetValue()
        end)
        if okValue and type(rawValue) == "number" then
            return math.clamp(rawValue / 1000, 0, 0.5)
        end
        local okText: boolean, rawText: any = pcall(function(): any
            return (pingItem :: any):GetValueString()
        end)
        if okText and type(rawText) == "string" then
            local milliseconds: number? = tonumber(string.match(rawText, "[%d%.]+"))
            if milliseconds then
                return math.clamp(milliseconds / 1000, 0, 0.5)
            end
        end
        return 0.05
    end

    local function getCrosshair(camera: Camera): Vector2
        return Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5)
    end

    local function getFovRadius(camera: Camera, ping: number): number
        if not settings.dynamicFov then
            return settings.fovRadius
        end
        local cameraScale: number = math.clamp(camera.FieldOfView / 70, 0.7, 1.4)
        local latencyScale: number = 1 + math.clamp(ping * 0.55, 0, 0.22)
        return math.clamp(settings.fovRadius * cameraScale * latencyScale, 35, 520)
    end

    local function updateMotion(
        player: Player,
        part: BasePart,
        deltaTime: number
    ): MotionRecord
        local velocity: Vector3 = part.AssemblyLinearVelocity
        local previous: MotionRecord? = runtime.motion[player]
        local acceleration: Vector3 = Vector3.zero
        if previous and deltaTime > 0 then
            local rawAcceleration: Vector3 = (velocity - previous.velocity) / deltaTime
            if rawAcceleration.Magnitude > 180 then
                rawAcceleration = rawAcceleration.Unit * 180
            end
            acceleration = previous.acceleration:Lerp(rawAcceleration, 0.22)
        end
        local record: MotionRecord = {
            velocity = velocity,
            acceleration = acceleration,
        }
        runtime.motion[player] = record
        return record
    end

    -- Predicted impact point: pos + vel*leadTime + 0.5*acc*leadTime^2.
    -- Lead time = (ping + travel time) * multiplier, scaled by target state
    -- (airborne / sprint / direction change) like newvape's prediction library.
    local function projectTarget(
        part: BasePart,
        motion: MotionRecord,
        origin: Vector3,
        ping: number
    ): Vector3
        local distance: number = (part.Position - origin).Magnitude
        local travelTime: number = distance / math.max(settings.projectileSpeed, 1)
        local leadTime: number = math.clamp(
            (ping + travelTime) * settings.predictionMultiplier,
            0,
            0.75
        )

        local velocity: Vector3 = motion.velocity
        local acceleration: Vector3 = motion.acceleration
        local horizontalSpeed: number = (velocity * Vector3.new(1, 0, 1)).Magnitude
        local verticalSpeed: number = math.abs(velocity.Y)
        local accelMagnitude: number = acceleration.Magnitude

        local stateScale: number = 1
        if verticalSpeed > 12 then
            stateScale = 1.35
        elseif horizontalSpeed > 22 then
            stateScale = 1.15
        end
        if accelMagnitude > 60 then
            stateScale = math.min(stateScale * 1.35, 1.9)
        end
        leadTime = leadTime * stateScale

        local projected: Vector3 = part.Position
            + velocity * leadTime
            + acceleration * (0.5 * leadTime * leadTime)
        if verticalSpeed > 12 and velocity.Y > 0 then
            projected = projected + Vector3.new(0, math.min(0.25 * leadTime * velocity.Y, 3), 0)
        end
        return projected
    end

    local function hasLineOfSight(
        camera: Camera,
        character: Model,
        position: Vector3
    ): boolean
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.IgnoreWater = true
        local excluded: {Instance} = {}
        if LocalPlayer.Character then
            table.insert(excluded, LocalPlayer.Character)
        end
        parameters.FilterDescendantsInstances = excluded
        local direction: Vector3 = position - camera.CFrame.Position
        runtime.suppressRaycast = true
        local ok: boolean, result: any = pcall(function(): any
            return workspace:Raycast(
                camera.CFrame.Position,
                direction,
                parameters
            )
        end)
        runtime.suppressRaycast = false
        if not ok then
            return true
        end
        return result == nil or result.Instance:IsDescendantOf(character)
    end

    -- Selects the best valid opponent inside the FOV circle, updated every frame
    -- on the single Heartbeat task so the silent-aim hook always has a fresh lock.
    local function selectTarget(
        camera: Camera,
        deltaTime: number,
        ping: number,
        radius: number
    ): TargetRecord?
        local crosshair: Vector2 = getCrosshair(camera)
        local localRoot: BasePart? = getRoot(LocalPlayer.Character)
        local best: TargetRecord? = nil
        local bestScore: number = math.huge
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isActiveOpponent(player) then
                local character: Model = player.Character :: Model
                local part: BasePart? = getTargetPart(character)
                if part then
                    local origin: Vector3 = if localRoot
                        then localRoot.Position
                        else camera.CFrame.Position
                    local distance: number = (part.Position - origin).Magnitude
                    if settings.infiniteRange or distance <= settings.maxDistance then
                        local point: Vector3, onScreen: boolean = camera:WorldToViewportPoint(
                            part.Position
                        )
                        if onScreen and point.Z > 0 then
                            local screen: Vector2 = Vector2.new(point.X, point.Y)
                            local cursorDistance: number = (screen - crosshair).Magnitude
                            if cursorDistance <= radius then
                                local visible: boolean = true
                                if settings.wallCheck then
                                    visible = hasLineOfSight(
                                        camera,
                                        character,
                                        part.Position
                                    )
                                end
                                if visible then
                                    local motion: MotionRecord = updateMotion(
                                        player,
                                        part,
                                        math.max(deltaTime, 1 / 240)
                                    )
                                    local score: number = if settings.targetMode == "Closest Distance"
                                        then distance
                                        else cursorDistance
                                    if score < bestScore then
                                        bestScore = score
                                        best = {
                                            player = player,
                                            character = character,
                                            part = part,
                                            screenPosition = screen,
                                            predictedPosition = projectTarget(
                                                part,
                                                motion,
                                                camera.CFrame.Position,
                                                ping
                                            ),
                                            distance = distance,
                                            cursorDistance = cursorDistance,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    -- Redirects a ray's direction onto the locked target. Follows newvape.
    local function redirectRay(
        origin: Vector3,
        direction: Vector3
    ): RedirectResult?
        if not settings.aimEnabled then
            return nil
        end
        local target: TargetRecord? = runtime.selected
        if not target then
            return nil
        end
        local camera: Camera? = workspace.CurrentCamera
        if not camera then
            return nil
        end
        -- Only camera-origin rays: those are the gun / mouse casts.
        if (origin - camera.CFrame.Position).Magnitude > 12 then
            return nil
        end
        if direction.Magnitude < 1 then
            return nil
        end
        -- Plausibility: hit chance occasionally lets a real shot pass through
        -- unredirected, so not every shot is a perfect hit.
        if (math.random() * 100) > settings.hitChance then
            return nil
        end
        -- Plausibility: only redirect when the target is near the crosshair
        -- direction. Redirecting to a target far off to the side is the classic
        -- impossible-shot pattern the server validation flags.
        local toTarget: Vector3 = target.predictedPosition - origin
        local toUnit: Vector3 = toTarget.Unit
        local look: Vector3 = camera.CFrame.LookVector
        local dot: number = math.clamp(look:Dot(toUnit), -1, 1)
        local degrees: number = math.deg(math.acos(dot))
        if degrees > settings.maxAimAngle then
            return nil
        end
        -- Headshot chance: downgrade to the root part occasionally so the hit
        -- distribution stays plausible instead of 100% headshots.
        local aimPart: BasePart = target.part
        if settings.targetPart == "Head"
            and (math.random() * 100) > settings.headshotChance then
            local rootPart: BasePart? = getRoot(target.character)
            if rootPart then
                aimPart = rootPart
            end
        end
        local aimPoint: Vector3
        if aimPart == target.part then
            aimPoint = target.predictedPosition
        else
            local motion: MotionRecord? = runtime.motion[target.player]
            if motion then
                aimPoint = projectTarget(aimPart, motion, origin, getPingSeconds())
            else
                aimPoint = aimPart.Position
            end
        end
        local reach: number = math.max(
            direction.Magnitude,
            (aimPoint - origin).Magnitude + 5
        )
        local newDirection: Vector3 = CFrame.lookAt(origin, aimPoint).LookVector * reach
        local wallParams: RaycastParams? = nil
        if not settings.wallCheck then
            local wp: RaycastParams = RaycastParams.new()
            wp.FilterType = Enum.RaycastFilterType.Include
            wp.FilterDescendantsInstances = {target.part}
            wp.IgnoreWater = true
            wp.RespectCanCollide = false
            wallParams = wp
        end
        return { origin = origin, direction = newDirection, wallParams = wallParams }
    end

    local function installRayHook(): boolean
        if runtime.rayHookInstalled then
            return true
        end
        if type(hookfunction) ~= "function" or Ray == nil then
            return false
        end
        local predecessor: any = nil
        local callback = function(origin: any, direction: any)
            if predecessor ~= nil then
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    local redirected: any = redirectRay(origin, direction)
                    if redirected and redirected.direction then
                        return predecessor(origin, redirected.direction)
                    end
                end
                return predecessor(origin, direction)
            end
            return nil
        end
        local wrapped: any = callback
        if type(newcclosure) == "function" then
            wrapped = newcclosure(callback)
        end
        predecessor = hookfunction(Ray.new, wrapped)
        if predecessor == nil then
            return false
        end
        runtime.oldRay = predecessor
        runtime.rayHookWrapper = wrapped
        runtime.rayHookInstalled = true
        return true
    end

    -- Hooks workspace.Raycast by replacing the instance method closure with
    -- hookfunction (no __namecall / no getnamecallmethod). All
    -- workspace:Raycast(...) calls from the game (including the weapon's
    -- MouseCast) resolve through this closure, so a dot/colon call with
    -- (self, origin, direction, params) reaches the redirect.
    local function installRaycastHook(): boolean
        if runtime.raycastHookInstalled then
            return true
        end
        if type(hookfunction) ~= "function" then
            return false
        end
        local raycastMethod: any = workspace and workspace.Raycast
        if type(raycastMethod) ~= "function" then
            return false
        end
        local predecessor: any = nil
        local callback = function(self, ...)
            if predecessor == nil then
                return nil
            end
            if not runtime.suppressRaycast then
                local args: {any} = {...}
                local origin: any = args[1]
                local direction: any = args[2]
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    local redirected: any = redirectRay(origin, direction)
                    if redirected and redirected.direction then
                        args[2] = redirected.direction
                        if redirected.wallParams ~= nil then
                            args[3] = redirected.wallParams
                        end
                        return predecessor(self, unpack(args))
                    end
                end
            end
            return predecessor(self, ...)
        end
        local wrapped: any = callback
        if type(newcclosure) == "function" then
            wrapped = newcclosure(callback)
        end
        predecessor = hookfunction(raycastMethod, wrapped)
        if predecessor == nil then
            return false
        end
        runtime.oldRaycast = predecessor
        runtime.raycastHookWrapper = wrapped
        runtime.raycastHookInstalled = true
        return true
    end

    local function uninstallHooks(): ()
        local rayRestored: boolean = not runtime.rayHookInstalled
        if runtime.rayHookInstalled and runtime.oldRay ~= nil and type(hookfunction) == "function" then
            local restored: boolean, displaced: any = pcall(
                hookfunction,
                Ray.new,
                runtime.oldRay
            )
            rayRestored = restored and displaced == runtime.rayHookWrapper
            if restored and not rayRestored and type(displaced) == "function" then
                pcall(hookfunction, Ray.new, displaced)
            end
        end
        if rayRestored then
            runtime.rayHookInstalled = false
            runtime.oldRay = nil
            runtime.rayHookWrapper = nil
        end
        local raycastRestored: boolean = not runtime.raycastHookInstalled
        if runtime.raycastHookInstalled and runtime.oldRaycast ~= nil
            and type(hookfunction) == "function"
            and workspace and workspace.Raycast then
            local restored: boolean, displaced: any = pcall(
                hookfunction,
                workspace.Raycast,
                runtime.oldRaycast
            )
            raycastRestored = restored and displaced == runtime.raycastHookWrapper
            if restored and not raycastRestored and type(displaced) == "function" then
                pcall(hookfunction, workspace.Raycast, displaced)
            end
        end
        if raycastRestored then
            runtime.raycastHookInstalled = false
            runtime.oldRaycast = nil
            runtime.raycastHookWrapper = nil
        end
    end

    local function makeRounded(frame: GuiObject, radius: number): ()
        local corner: UICorner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius)
        corner.Parent = frame
    end

    local function createVisuals(): VisualRecord
        local root: Frame = Instance.new("Frame")
        root.Name = "RTM_MVSD_AimOverlay"
        root.Active = false
        root.BackgroundTransparency = 1
        root.BorderSizePixel = 0
        root.Size = UDim2.fromScale(1, 1)
        root.ZIndex = 300
        root.Parent = ScreenGui

        local circle: Frame = Instance.new("Frame")
        circle.Name = "FOV"
        circle.AnchorPoint = Vector2.new(0.5, 0.5)
        circle.BackgroundTransparency = 1
        circle.BorderSizePixel = 0
        circle.ZIndex = 301
        circle.Parent = root
        makeRounded(circle, 1000)
        local circleStroke: UIStroke = Instance.new("UIStroke")
        circleStroke.Color = Theme.AccentCyan
        circleStroke.Thickness = 1.5
        circleStroke.Transparency = 0.18
        circleStroke.Parent = circle

        local marker: Frame = Instance.new("Frame")
        marker.Name = "PredictionMarker"
        marker.AnchorPoint = Vector2.new(0.5, 0.5)
        marker.BackgroundColor3 = Theme.Surface
        marker.BackgroundTransparency = 0.12
        marker.BorderSizePixel = 0
        marker.Size = UDim2.fromOffset(16, 16)
        marker.Visible = false
        marker.ZIndex = 303
        marker.Parent = root
        makeRounded(marker, 1000)
        local markerStroke: UIStroke = Instance.new("UIStroke")
        markerStroke.Color = Theme.AccentCyan
        markerStroke.Thickness = 2
        markerStroke.Transparency = 0.02
        markerStroke.Parent = marker

        local status: TextLabel = Instance.new("TextLabel")
        status.Name = "TargetStatus"
        status.AnchorPoint = Vector2.new(0.5, 0)
        status.BackgroundColor3 = Theme.Surface
        status.BackgroundTransparency = 0.12
        status.BorderSizePixel = 0
        status.Font = Enum.Font.GothamSemibold
        status.Position = UDim2.new(0.5, 0, 0, 22)
        status.Size = UDim2.fromOffset(330, 38)
        status.Text = "MVSD · NO VISIBLE TARGET"
        status.TextColor3 = Theme.TextMuted
        status.TextSize = 12
        status.Visible = false
        status.ZIndex = 304
        status.Parent = root
        makeRounded(status, 10)

        return {
            root = root,
            circle = circle,
            circleStroke = circleStroke,
            marker = marker,
            markerStroke = markerStroke,
            status = status,
        }
    end

    local function getVisuals(): VisualRecord
        local existing: VisualRecord? = runtime.visuals
        if existing and existing.root.Parent then
            return existing
        end
        local created: VisualRecord = createVisuals()
        runtime.visuals = created
        return created
    end

    local function hideTargetVisuals(visuals: VisualRecord): ()
        visuals.marker.Visible = false
        runtime.selected = nil
        runtime.triggerEnteredAt = nil
    end

    -- The game weapon exposes cooldown attributes on the equipped tool. Respecting
    -- them stops auto shoot from firing faster than the game allows, which is a
    -- detectable macro pattern.
    local function weaponCanFire(): boolean
        local character: Model? = LocalPlayer.Character
        local tool: Tool? = character and character:FindFirstChildWhichIsA("Tool") or nil
        if not tool then
            return true
        end
        if tool:GetAttribute("CanShoot") == false then
            return false
        end
        return true
    end

    -- Instant triggerbot: holds/releases fire while a valid opponent is locked
    -- in the FOV. Zero delay (default) toggles the click every frame for max RoF.
    local function releaseAutoShoot(): boolean
        if not runtime.autoShootHeld then
            runtime.autoShootNextAt = os.clock()
            return true
        end
        if type(mouse1release) ~= "function" then
            return false
        end
        local released: boolean = false
        for _attempt: number = 1, 3 do
            if pcall(mouse1release) then
                released = true
                break
            end
        end
        if not released then
            return false
        end
        runtime.autoShootHeld = false
        runtime.autoShootNextAt = os.clock()
        return true
    end

    local function updateAutoShoot(): ()
        if not settings.autoShootEnabled then
            releaseAutoShoot()
            return
        end

        local canFire: boolean = runtime.selected ~= nil and weaponCanFire()
        if canFire then
            local now: number = os.clock()
            if now >= runtime.autoShootNextAt then
                if not runtime.autoShootHeld then
                    if type(mouse1press) == "function"
                        and type(mouse1release) == "function" then
                        local releaseReady: boolean = pcall(mouse1release)
                        if releaseReady and pcall(mouse1press) then
                            runtime.autoShootHeld = true
                        end
                    end
                else
                    if not releaseAutoShoot() then
                        return
                    end
                    -- Humanize: small random jitter between bursts so the fire
                    -- rate is not a constant machine-gun pattern.
                    local delay: number = math.max(settings.shotDelay, 0)
                        + math.random() * math.max(settings.humanizeDelay, 0)
                    runtime.autoShootNextAt = now + delay
                end
            end
        else
            releaseAutoShoot()
        end
    end

    local function updateCore(deltaTime: number): ()
        local visuals: VisualRecord = getVisuals()
        local camera: Camera? = workspace.CurrentCamera
        if not camera or type(LocalPlayer:GetAttribute("Game")) ~= "string" then
            visuals.circle.Visible = false
            visuals.status.Visible = settings.aimEnabled
                or settings.autoShootEnabled
                or settings.triggerCueEnabled
            visuals.status.Text = "MVSD · WAITING FOR ACTIVE MATCH"
            visuals.status.TextColor3 = Theme.TextMuted
            hideTargetVisuals(visuals)
            updateAutoShoot()
            return
        end

        local ping: number = getPingSeconds()
        local radius: number = getFovRadius(camera, ping)
        local crosshair: Vector2 = getCrosshair(camera)
        visuals.circle.Position = UDim2.fromOffset(crosshair.X, crosshair.Y)
        visuals.circle.Size = UDim2.fromOffset(radius * 2, radius * 2)
        visuals.circle.Visible = (settings.aimEnabled or settings.autoShootEnabled)
            and settings.showCircle
        visuals.status.Visible = settings.aimEnabled
            or settings.autoShootEnabled
            or settings.triggerCueEnabled

        if not settings.aimEnabled
            and not settings.autoShootEnabled
            and not settings.triggerCueEnabled then
            hideTargetVisuals(visuals)
            updateAutoShoot()
            return
        end

        local target: TargetRecord? = selectTarget(camera, deltaTime, ping, radius)
        runtime.selected = target
        if not target then
            visuals.status.Text = string.format(
                "MVSD · NO VISIBLE TARGET · PING %.0f MS",
                ping * 1000
            )
            visuals.status.TextColor3 = Theme.TextMuted
            hideTargetVisuals(visuals)
            updateAutoShoot()
            return
        end

        local predictedPoint: Vector3, predictedOnScreen: boolean =
            camera:WorldToViewportPoint(target.predictedPosition)
        if not predictedOnScreen or predictedPoint.Z <= 0 then
            hideTargetVisuals(visuals)
            updateAutoShoot()
            return
        end
        local predictedScreen: Vector2 = Vector2.new(predictedPoint.X, predictedPoint.Y)
        visuals.marker.Position = UDim2.fromOffset(predictedScreen.X, predictedScreen.Y)
        visuals.marker.Visible = settings.aimEnabled

        local insideTrigger: boolean = target.cursorDistance <= settings.triggerTolerance
        if settings.triggerCueEnabled and insideTrigger then
            if runtime.triggerEnteredAt == nil then
                runtime.triggerEnteredAt = os.clock()
            end
        else
            runtime.triggerEnteredAt = nil
        end
        local triggerReady: boolean = settings.triggerCueEnabled
            and insideTrigger
            and runtime.triggerEnteredAt ~= nil
            and os.clock() - (runtime.triggerEnteredAt :: number) >= settings.triggerDelay

        updateAutoShoot()

        local modeText: string = if settings.aimEnabled then "SILENT AIM" else "AUTO SHOOT"
        local accent: Color3 = if triggerReady then Theme.Success else Theme.AccentCyan
        visuals.markerStroke.Color = accent
        visuals.circleStroke.Color = accent
        visuals.status.TextColor3 = accent
        visuals.status.Text = string.format(
            "%s · %s · %s · %.0f STUDS · %.0f MS%s",
            modeText,
            target.player.DisplayName,
            tostring(target.player:GetAttribute("Team") or "FFA"),
            target.distance,
            ping * 1000,
            if triggerReady then " · SHOT WINDOW" else ""
        )
    end

    local function anyFeatureEnabled(): boolean
        return settings.aimEnabled
            or settings.autoShootEnabled
            or settings.triggerCueEnabled
    end

    local function syncCoreTask(): ()
        disconnectFeatureConnection("MVSDAimCore")
        if not anyFeatureEnabled() then
            releaseAutoShoot()
            uninstallHooks()
            if runtime.visuals then
                runtime.visuals.root:Destroy()
                runtime.visuals = nil
            end
            runtime.selected = nil
            table.clear(runtime.motion)
            return
        end
        if settings.aimEnabled and not (runtime.rayHookInstalled or runtime.raycastHookInstalled) then
            local rayOk: boolean = installRayHook()
            local raycastOk: boolean = installRaycastHook()
            if not rayOk and not raycastOk then
                notify("MVSD · Silent Aim requiere hookfunction")
                settings.aimEnabled = false
            end
        elseif not settings.aimEnabled and (runtime.rayHookInstalled or runtime.raycastHookInstalled) then
            uninstallHooks()
        end
        getVisuals()
        featureConnections.MVSDAimCore = TaskManager:Connect(updateCore)
    end

    -- No ESP card here.
    --
    -- This one drew boxes, names, health and distance over players — which is
    -- the universal Player ESP, minus its corner boxes, skeletons, chams,
    -- tracers and name plates. Two ESPs in one menu is one too many, so this
    -- game contributes its team split to the shared one instead and the
    -- duplicate is gone.
    registerRoleProvider({
        Name = "MVSD",
        Roles = {"Enemy", "Teammate"},
        Colors = {
            Enemy = Color3.fromRGB(226, 72, 72),
            Teammate = Color3.fromRGB(120, 220, 140),
        },
        Get = function(player: Player): string?
            if not isInMatch(player) then
                return nil
            end
            return isSameTeam(LocalPlayer, player) and "Teammate" or "Enemy"
        end,
    })

    local SilentAimFeature: any = createUniversalFeature(
        "Silent Aim",
        "Blatant silent aim: redirects the weapon raycast to the predicted target part",
        2,
        function(enabled: boolean): ()
            settings.aimEnabled = enabled
            syncCoreTask()
        end,
        {parent = state.mvsdScroll, registry = state.mvsdFeatures}
    )
    addToggleOption(SilentAimFeature, "Team check", true, function(value: boolean): ()
        settings.teamCheck = value
    end)
    addToggleOption(SilentAimFeature, "Show FOV circle", true, function(value: boolean): ()
        settings.showCircle = value
    end)
    addToggleOption(SilentAimFeature, "Dynamic FOV", true, function(value: boolean): ()
        settings.dynamicFov = value
    end)
    addToggleOption(SilentAimFeature, "Infinite range", false, function(value: boolean): ()
        settings.infiniteRange = value
    end)
    addToggleOption(SilentAimFeature, "Wall check", true, function(value: boolean): ()
        settings.wallCheck = value
    end)
    addNumberOption(SilentAimFeature, "Hit chance", 95, 1, 100, function(value: number): ()
        settings.hitChance = math.clamp(value, 1, 100)
    end)
    addNumberOption(SilentAimFeature, "Headshot chance", 75, 1, 100, function(value: number): ()
        settings.headshotChance = math.clamp(value, 1, 100)
    end)
    addNumberOption(SilentAimFeature, "Max aim angle", 25, 1, 180, function(value: number): ()
        settings.maxAimAngle = math.clamp(value, 1, 180)
    end)
    addCycleOption(
        SilentAimFeature,
        "Target selection",
        {"Closest to Cursor", "Closest Distance"},
        1,
        function(value: string): ()
            settings.targetMode = value
        end
    )
    addCycleOption(SilentAimFeature, "Target part", {"Head", "HumanoidRootPart"}, 1, function(value: string): ()
        settings.targetPart = value
    end)
    addNumberOption(SilentAimFeature, "FOV radius", 180, 35, 520, function(value: number): ()
        settings.fovRadius = math.clamp(value, 20, 800)
    end)
    addNumberOption(SilentAimFeature, "Maximum distance", 600, 50, 3000, function(value: number): ()
        settings.maxDistance = math.max(1, value)
    end)
    addNumberOption(SilentAimFeature, "Projectile speed", 350, 50, 3000, function(value: number): ()
        settings.projectileSpeed = math.max(1, value)
    end)
    addNumberOption(SilentAimFeature, "Prediction multiplier", 1, 0, 3, function(value: number): ()
        settings.predictionMultiplier = math.clamp(value, 0, 8)
    end)
    addInformationOption(
        SilentAimFeature,
        "Hooks Ray.new and workspace:Raycast. Hit/headshot chance and max aim angle keep shots plausible."
    )

    local AutoShootFeature: any = createUniversalFeature(
        "Auto Shoot",
        "Instant triggerbot: fires the weapon the moment a valid enemy enters the FOV",
        3,
        function(enabled: boolean): ()
            settings.autoShootEnabled = enabled
            if not enabled then
                releaseAutoShoot()
            end
            syncCoreTask()
        end,
        {parent = state.mvsdScroll, registry = state.mvsdFeatures}
    )
    addToggleOption(AutoShootFeature, "Team check", true, function(value: boolean): ()
        settings.teamCheck = value
    end)
    addNumberOption(AutoShootFeature, "Shot delay", 0, 0, 1, function(value: number): ()
        settings.shotDelay = math.clamp(value, 0, 2)
    end)
    addNumberOption(AutoShootFeature, "Humanize delay", 0.04, 0, 0.2, function(value: number): ()
        settings.humanizeDelay = math.clamp(value, 0, 0.5)
    end)
    addInformationOption(
        AutoShootFeature,
        "Simulates mouse clicks. Combine with Silent Aim for guaranteed redirect hits."
    )

    local TriggerFeature: any = createUniversalFeature(
        "Trigger Opportunity",
        "Show a SHOT WINDOW cue when a visible opponent overlaps the center reticle",
        4,
        function(enabled: boolean): ()
            settings.triggerCueEnabled = enabled
            syncCoreTask()
        end,
        {parent = state.mvsdScroll, registry = state.mvsdFeatures}
    )
    addNumberOption(TriggerFeature, "Reticle tolerance", 11, 2, 40, function(value: number): ()
        settings.triggerTolerance = math.clamp(value, 1, 100)
    end)
    addNumberOption(TriggerFeature, "Cue delay", 0, 0, 0.5, function(value: number): ()
        settings.triggerDelay = math.clamp(value, 0, 2)
    end)

    state.cleanupMVSDRuntime = function(): ()
        disconnectFeatureConnection("MVSDAimCore")
        releaseAutoShoot()
        uninstallHooks()
        if runtime.visuals then
            runtime.visuals.root:Destroy()
            runtime.visuals = nil
        end
        destroyAllEsp()
        runtime.selected = nil
        table.clear(runtime.motion)
    end
end

function Module.init(runtime: any): any
    assert(type(runtime) == "table", "MVSD requires a Runtime table")
    assert(type(runtime.Menu) == "table", "MVSD requires Runtime.Menu")
    assert(runtime.TaskManager ~= nil, "MVSD requires Runtime.TaskManager")
    if Module.Initialized then
        return Module
    end
    Module.Menu = runtime.Menu
    Module.Runtime = runtime
    buildMVSDFeatures()
    if type(state.cleanupMVSDRuntime) == "function" then
        moduleCleanup = state.cleanupMVSDRuntime
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
    moduleCleanup()
    Module.Events = {}
    Module.Menu = nil
    Module.Runtime = nil
end

return Module
