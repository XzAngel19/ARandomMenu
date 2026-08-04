--!strict

local Module = {
    Name = "MVSD",
    PlaceId = 135856908115931,
    Events = {} :: {[string]: any},
    Initialized = false,
    Menu = nil :: any,
    Runtime = nil :: any,
}

type AimSettings = {
    aimEnabled: boolean,
    triggerCueEnabled: boolean,
    outlineEnabled: boolean,
    weaponHudEnabled: boolean,
    showCircle: boolean,
    dynamicFov: boolean,
    infiniteRange: boolean,
    targetMode: string,
    targetPart: string,
    fovRadius: number,
    maxDistance: number,
    projectileSpeed: number,
    predictionMultiplier: number,
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
    visible: boolean,
}

type VisualRecord = {
    root: Frame,
    circle: Frame,
    circleStroke: UIStroke,
    marker: Frame,
    markerStroke: UIStroke,
    trajectory: Frame,
    status: TextLabel,
    weapon: TextLabel,
    highlight: Highlight,
}

type AimRuntime = {
    visuals: VisualRecord?,
    motion: {[Player]: MotionRecord},
    selected: TargetRecord?,
    triggerEnteredAt: number?,
}

local moduleCleanup: () -> () = function(): () end

local function buildMVSDFeatures(): ()
    local settings: AimSettings = {
        aimEnabled = false,
        triggerCueEnabled = false,
        outlineEnabled = false,
        weaponHudEnabled = false,
        showCircle = true,
        dynamicFov = true,
        infiniteRange = false,
        targetMode = "Closest to Cursor",
        targetPart = "Head",
        fovRadius = 180,
        maxDistance = 600,
        projectileSpeed = 350,
        predictionMultiplier = 1,
        triggerTolerance = 11,
        triggerDelay = 0,
    }
    local runtime: AimRuntime = {
        visuals = nil,
        motion = {},
        selected = nil,
        triggerEnteredAt = nil,
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

    local function isActiveOpponent(player: Player): boolean
        if player == LocalPlayer or player:GetAttribute("Died") == true then
            return false
        end
        local localGame: any = LocalPlayer:GetAttribute("Game")
        local playerGame: any = player:GetAttribute("Game")
        if type(localGame) ~= "string" or playerGame ~= localGame then
            return false
        end
        local localTeam: any = LocalPlayer:GetAttribute("Team")
        local playerTeam: any = player:GetAttribute("Team")
        if type(localTeam) == "string"
            and type(playerTeam) == "string"
            and localTeam == playerTeam then
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
            0.65
        )
        return part.Position
            + motion.velocity * leadTime
            + motion.acceleration * (0.5 * leadTime * leadTime)
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
        local result: RaycastResult? = workspace:Raycast(
            camera.CFrame.Position,
            direction,
            parameters
        )
        return result == nil or result.Instance:IsDescendantOf(character)
    end

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
                                local visible: boolean = hasLineOfSight(
                                    camera,
                                    character,
                                    part.Position
                                )
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
                                            visible = true,
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

        local trajectory: Frame = Instance.new("Frame")
        trajectory.Name = "Trajectory"
        trajectory.AnchorPoint = Vector2.new(0, 0.5)
        trajectory.BackgroundColor3 = Theme.AccentViolet
        trajectory.BackgroundTransparency = 0.28
        trajectory.BorderSizePixel = 0
        trajectory.Size = UDim2.fromOffset(0, 2)
        trajectory.Visible = false
        trajectory.ZIndex = 302
        trajectory.Parent = root
        makeRounded(trajectory, 1000)

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

        local weapon: TextLabel = Instance.new("TextLabel")
        weapon.Name = "WeaponStatus"
        weapon.AnchorPoint = Vector2.new(1, 1)
        weapon.BackgroundColor3 = Theme.Surface
        weapon.BackgroundTransparency = 0.12
        weapon.BorderSizePixel = 0
        weapon.Font = Enum.Font.GothamMedium
        weapon.Position = UDim2.new(1, -20, 1, -20)
        weapon.Size = UDim2.fromOffset(260, 54)
        weapon.Text = "WEAPON · NONE"
        weapon.TextColor3 = Theme.TextMuted
        weapon.TextSize = 12
        weapon.Visible = false
        weapon.ZIndex = 304
        weapon.Parent = root
        makeRounded(weapon, 10)

        local highlight: Highlight = Instance.new("Highlight")
        highlight.Name = "RTM_MVSD_VisibleTarget"
        highlight.DepthMode = Enum.HighlightDepthMode.Occluded
        highlight.Enabled = false
        highlight.FillColor = Theme.AccentViolet
        highlight.FillTransparency = 0.76
        highlight.OutlineColor = Theme.AccentCyan
        highlight.OutlineTransparency = 0.08
        highlight.Parent = root

        return {
            root = root,
            circle = circle,
            circleStroke = circleStroke,
            marker = marker,
            markerStroke = markerStroke,
            trajectory = trajectory,
            status = status,
            weapon = weapon,
            highlight = highlight,
        }
    end

    local function getVisuals(): VisualRecord
        local visuals: VisualRecord? = runtime.visuals
        if visuals and visuals.root.Parent then
            return visuals
        end
        visuals = createVisuals()
        runtime.visuals = visuals
        return visuals
    end

    local function equippedTool(): Tool?
        local character: Model? = LocalPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChildWhichIsA("Tool")
    end

    local function formatWeaponStatus(): string
        local tool: Tool? = equippedTool()
        if not tool then
            return "WEAPON · NONE EQUIPPED"
        end
        local details: {string} = {string.upper(tool.Name)}
        for _, name: string in ipairs({"Ammo", "Bullets", "Cooldown", "Reloading", "CanShoot"}) do
            local value: any = tool:GetAttribute(name)
            if value ~= nil then
                table.insert(details, string.upper(name) .. "=" .. tostring(value))
            end
        end
        return table.concat(details, " · ")
    end

    local function hideTargetVisuals(visuals: VisualRecord): ()
        visuals.marker.Visible = false
        visuals.trajectory.Visible = false
        visuals.highlight.Enabled = false
        visuals.highlight.Adornee = nil
        runtime.selected = nil
        runtime.triggerEnteredAt = nil
    end

    local function drawTrajectory(
        visuals: VisualRecord,
        startPoint: Vector2,
        endPoint: Vector2
    ): ()
        local offset: Vector2 = endPoint - startPoint
        local length: number = offset.Magnitude
        visuals.trajectory.Position = UDim2.fromOffset(startPoint.X, startPoint.Y)
        visuals.trajectory.Size = UDim2.fromOffset(length, 2)
        visuals.trajectory.Rotation = math.deg(math.atan2(offset.Y, offset.X))
        visuals.trajectory.Visible = length > 2
    end

    local function updateCore(deltaTime: number): ()
        local visuals: VisualRecord = getVisuals()
        local camera: Camera? = workspace.CurrentCamera
        if not camera or type(LocalPlayer:GetAttribute("Game")) ~= "string" then
            visuals.circle.Visible = false
            visuals.status.Visible = settings.aimEnabled or settings.triggerCueEnabled
            visuals.status.Text = "MVSD · WAITING FOR ACTIVE MATCH"
            visuals.status.TextColor3 = Theme.TextMuted
            visuals.weapon.Visible = settings.weaponHudEnabled
            visuals.weapon.Text = formatWeaponStatus()
            hideTargetVisuals(visuals)
            return
        end

        local ping: number = getPingSeconds()
        local radius: number = getFovRadius(camera, ping)
        local crosshair: Vector2 = getCrosshair(camera)
        visuals.circle.Position = UDim2.fromOffset(crosshair.X, crosshair.Y)
        visuals.circle.Size = UDim2.fromOffset(radius * 2, radius * 2)
        visuals.circle.Visible = settings.aimEnabled and settings.showCircle
        visuals.status.Visible = settings.aimEnabled or settings.triggerCueEnabled
        visuals.weapon.Visible = settings.weaponHudEnabled
        visuals.weapon.Text = formatWeaponStatus()

        if not settings.aimEnabled
            and not settings.triggerCueEnabled
            and not settings.outlineEnabled then
            hideTargetVisuals(visuals)
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
            return
        end

        local predictedPoint: Vector3, predictedOnScreen: boolean =
            camera:WorldToViewportPoint(target.predictedPosition)
        if not predictedOnScreen or predictedPoint.Z <= 0 then
            hideTargetVisuals(visuals)
            return
        end
        local predictedScreen: Vector2 = Vector2.new(predictedPoint.X, predictedPoint.Y)
        visuals.marker.Position = UDim2.fromOffset(predictedScreen.X, predictedScreen.Y)
        visuals.marker.Visible = settings.aimEnabled
        drawTrajectory(visuals, crosshair, predictedScreen)
        visuals.trajectory.Visible = settings.aimEnabled and visuals.trajectory.Visible

        visuals.highlight.Adornee = target.character
        visuals.highlight.Enabled = settings.outlineEnabled and target.visible
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
        local accent: Color3 = if triggerReady then Theme.Success else Theme.AccentCyan
        visuals.markerStroke.Color = accent
        visuals.circleStroke.Color = accent
        visuals.status.TextColor3 = accent
        visuals.status.Text = string.format(
            "%s · %s · %.0f STUDS · %.0f MS%s",
            target.player.DisplayName,
            tostring(target.player:GetAttribute("Team") or "FFA"),
            target.distance,
            ping * 1000,
            if triggerReady then " · SHOT WINDOW" else ""
        )
    end

    local function anyFeatureEnabled(): boolean
        return settings.aimEnabled
            or settings.triggerCueEnabled
            or settings.outlineEnabled
            or settings.weaponHudEnabled
    end

    local function syncCoreTask(): ()
        disconnectFeatureConnection("MVSDAimCore")
        if not anyFeatureEnabled() then
            if runtime.visuals then
                runtime.visuals.root:Destroy()
                runtime.visuals = nil
            end
            runtime.selected = nil
            table.clear(runtime.motion)
            return
        end
        getVisuals()
        featureConnections.MVSDAimCore = TaskManager:Connect(updateCore)
    end

    local AimFeature: any = createUniversalFeature(
        "Aim Prediction Assistant",
        "Visual FOV and latency-aware movement prediction for visible match opponents",
        1,
        function(enabled: boolean): ()
            settings.aimEnabled = enabled
            syncCoreTask()
        end,
        {parent = state.mvsdScroll, registry = state.mvsdFeatures}
    )
    addToggleOption(AimFeature, "Show FOV circle", true, function(value: boolean): ()
        settings.showCircle = value
    end)
    addToggleOption(AimFeature, "Dynamic FOV", true, function(value: boolean): ()
        settings.dynamicFov = value
    end)
    addToggleOption(AimFeature, "Infinite visual range", false, function(value: boolean): ()
        settings.infiniteRange = value
    end)
    addCycleOption(
        AimFeature,
        "Target selection",
        {"Closest to Cursor", "Closest Distance"},
        1,
        function(value: string): ()
            settings.targetMode = value
        end
    )
    addCycleOption(AimFeature, "Target part", {"Head", "HumanoidRootPart"}, 1, function(value: string): ()
        settings.targetPart = value
    end)
    addNumberOption(AimFeature, "FOV radius", 180, 35, 520, function(value: number): ()
        settings.fovRadius = math.clamp(value, 20, 800)
    end)
    addNumberOption(AimFeature, "Maximum distance", 600, 50, 3000, function(value: number): ()
        settings.maxDistance = math.max(1, value)
    end)
    addNumberOption(AimFeature, "Projectile speed", 350, 50, 3000, function(value: number): ()
        settings.projectileSpeed = math.max(1, value)
    end)
    addNumberOption(AimFeature, "Prediction multiplier", 1, 0, 3, function(value: number): ()
        settings.predictionMultiplier = math.clamp(value, 0, 8)
    end)
    addInformationOption(
        AimFeature,
        "Prediction is visual only. It never changes camera, weapon raycasts, clicks or RemoteEvent arguments."
    )

    local TriggerFeature: any = createUniversalFeature(
        "Trigger Opportunity",
        "Show a SHOT WINDOW cue when a visible opponent overlaps the center reticle",
        2,
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

    createUniversalFeature(
        "Visible Target Outline",
        "Apply an occluded Highlight only while the selected opponent has real line of sight",
        3,
        function(enabled: boolean): ()
            settings.outlineEnabled = enabled
            syncCoreTask()
        end,
        {parent = state.mvsdScroll, registry = state.mvsdFeatures}
    )

    createUniversalFeature(
        "Weapon Status HUD",
        "Display the equipped tool and any replicated ammo, reload or cooldown attributes",
        4,
        function(enabled: boolean): ()
            settings.weaponHudEnabled = enabled
            syncCoreTask()
        end,
        {parent = state.mvsdScroll, registry = state.mvsdFeatures}
    )

    state.cleanupMVSDRuntime = function(): ()
        disconnectFeatureConnection("MVSDAimCore")
        if runtime.visuals then
            runtime.visuals.root:Destroy()
            runtime.visuals = nil
        end
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
