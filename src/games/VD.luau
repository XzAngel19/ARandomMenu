--!strict

local Module = {
    Name = "VD",
    PlaceId = 93978595733734,
    Events = {} :: {[string]: any},
    Initialized = false,
    Menu = nil :: any,
    Runtime = nil :: any,
}

type MarkerRecord = {
    highlight: Highlight,
    billboard: BillboardGui?,
    label: TextLabel?,
}

type SoundState = {
    volume: number,
}

type CollisionState = {
    canCollide: boolean,
}

local VD_KILLER_COLOR: Color3 = Color3.fromRGB(166, 110, 255)
local VD_ALERT_COLOR: Color3 = Color3.fromRGB(255, 190, 88)

local moduleCleanup: () -> () = function(): () end

local function buildVDFeatures(): ()
    local settings: any = {
        generatorDistance = 1800,
        generatorTransparency = 0.82,
        proximityRange = 150,
        autoGeneratorRange = 18,
        autoGeneratorInterval = 0.12,
        autoGeneratorAnimation = true,
        autoGeneratorGetOff = "Manual",
        autoGeneratorMode = "Legit",
        autoParryRange = 18,
        hitAuraRange = 12,
        hitAuraInterval = 0.72,
        hitAuraMode = "Legit",
        hitAuraRun = false,
        hitAuraBlatantReach = 34,
        vaultRange = 7,
        vaultSpeed = 5,
        actionSpeed = 4,
        damageBoost = 5,
        damageBoostDuration = 1,
        walkSpeed = 16,
        lockerRange = 45,
        fov = 85,
    }
    local runtime: any = {
        generatorMarkers = {} :: {[Model]: MarkerRecord},
        lockerMarkers = {} :: {[Player]: MarkerRecord},
        generatorStates = {} :: {[Model]: string},
        lockerAlerts = {} :: {[Player]: number},
        proximityGui = nil :: ScreenGui?,
        cooldownGui = nil :: ScreenGui?,
        visualFolder = nil :: Folder?,
        currentRepairPoint = nil :: BasePart?,
        manualGeneratorBlocked = false,
        manualGeneratorLeft = false,
        manualGeneratorOrigin = nil :: Vector3?,
        repairAnimation = nil :: AnimationTrack?,
        repairAnimationObject = nil :: Animation?,
        lastRepairFire = 0,
        boundKillerAnimator = nil :: Animator?,
        lastParry = 0,
        lastHit = 0,
        lastVaultInput = 0,
        lastVaultPoint = nil :: BasePart?,
        killerBaseWalkSpeed = nil :: number?,
        walkSpeedBase = nil :: number?,
        damageBoostToken = 0,
        damageBoostUntil = 0,
        damageOriginalSpeed = nil :: number?,
        trackedHumanoid = nil :: Humanoid?,
        actionAnimator = nil :: Animator?,
        selectiveCollisions = {} :: {[BasePart]: CollisionState},
        lighting = nil :: any,
        effectStates = {} :: {[Instance]: any},
        soundStates = {} :: {[Sound]: SoundState},
        soundConnections = {} :: {[Sound]: RBXScriptConnection},
        silentStepsEnabled = false,
        cooldownModifierEnabled = false,
        damageBoostEnabled = false,
        walkSpeedEnabled = false,
    }

    local ReplicatedStorageService: ReplicatedStorage =
        game:GetService("ReplicatedStorage")

    local function lower(value: any): string
        return string.lower(tostring(value))
    end

    local function contains(value: any, token: string): boolean
        return string.find(lower(value), token, 1, true) ~= nil
    end

    local function getRoot(model: Model?): BasePart?
        if not model then
            return nil
        end
        return model:FindFirstChild("HumanoidRootPart") :: BasePart?
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function isPlayerInRound(player: Player): boolean
        local team: Team? = player.Team
        if not team then
            return false
        end
        local teamName: string = lower(team.Name)
        return teamName == "survivors" or teamName == "killer"
    end

    local function isLocalKiller(): boolean
        local team: Team? = LocalPlayer.Team
        return team ~= nil and lower(team.Name) == "killer"
    end

    local function isRoundActive(): boolean
        return isPlayerInRound(LocalPlayer)
            and workspace:FindFirstChild("Map") ~= nil
    end

    local function getMap(): Instance?
        if not isRoundActive() then
            return nil
        end
        return workspace:FindFirstChild("Map")
    end

    local function isGenerator(instance: Instance): boolean
        return instance:IsA("Model")
            and lower(instance.Name) == "generator"
            and instance:FindFirstChild("GeneratorBody", true) ~= nil
    end

    local function isKillerCharacter(character: Model?): boolean
        if not character then
            return false
        end
        local player: Player? = Players:GetPlayerFromCharacter(character)
        if player and player.Team and lower(player.Team.Name) == "killer" then
            return true
        end
        local role: any = character:GetAttribute("Role")
        if player and role == nil then
            role = player:GetAttribute("Role")
        end
        if type(role) == "string" and lower(role) == "killer" then
            return true
        end
        if character:GetAttribute("IsKiller") == true then
            return true
        end
        local root: BasePart? = getRoot(character)
        return root ~= nil and root.CollisionGroup == "Killer"
    end

    local function getKiller(): (Player?, Model?)
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if isKillerCharacter(player.Character) then
                return player, player.Character
            end
        end
        return nil, nil
    end

    local function getVisualFolder(): Folder
        if runtime.visualFolder and runtime.visualFolder.Parent then
            return runtime.visualFolder
        end
        local folder: Folder = Instance.new("Folder")
        folder.Name = "RTM_VD_Visuals"
        folder.Parent = ScreenGui
        runtime.visualFolder = folder
        return folder
    end

    local function destroyMarker(record: MarkerRecord?): ()
        if not record then
            return
        end
        record.highlight:Destroy()
        if record.billboard then
            record.billboard:Destroy()
        end
    end

    local function createMarker(
        adornee: Instance,
        root: BasePart,
        color: Color3,
        text: string?,
        maxDistance: number
    ): MarkerRecord
        local highlight: Highlight = Instance.new("Highlight")
        highlight.Name = "RTM_VD_Highlight"
        highlight.Adornee = adornee
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = color
        highlight.FillTransparency = settings.generatorTransparency
        highlight.OutlineColor = color
        highlight.OutlineTransparency = 0.08
        highlight.Parent = getVisualFolder()
        local record: MarkerRecord = {
            highlight = highlight,
            billboard = nil,
            label = nil,
        }
        if text then
            local billboard: BillboardGui = Instance.new("BillboardGui")
            billboard.Name = "RTM_VD_Label"
            billboard.Adornee = root
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = maxDistance
            billboard.Size = UDim2.fromOffset(205, 48)
            billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
            billboard.Parent = getVisualFolder()
            local label: TextLabel = Instance.new("TextLabel")
            label.BackgroundColor3 = Color3.fromRGB(10, 13, 21)
            label.BackgroundTransparency = 0.16
            label.BorderSizePixel = 0
            label.Font = Enum.Font.GothamSemibold
            label.Size = UDim2.fromScale(1, 1)
            label.Text = text
            label.TextColor3 = color
            label.TextSize = 13
            label.TextWrapped = true
            label.Parent = billboard
            local corner: UICorner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 9)
            corner.Parent = label
            record.billboard = billboard
            record.label = label
        end
        return record
    end

    local function readNumberAttribute(instance: Instance, names: {string}): number?
        for _, name: string in ipairs(names) do
            local value: any = instance:GetAttribute(name)
            if type(value) == "number" then
                return value
            end
            local child: Instance? = instance:FindFirstChild(name, true)
            if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
                return child.Value
            end
        end
        return nil
    end

    local function generatorState(generator: Model): (number, string, Color3)
        local progress: number = readNumberAttribute(
            generator,
            {"Progress", "RepairProgress", "CurrentProgress"}
        ) or 0
        if progress <= 1 then
            progress *= 100
        end
        progress = math.clamp(progress, 0, 100)
        local repairers: number = readNumberAttribute(
            generator,
            {"PlayersRepairingCount", "RepairingPlayers"}
        ) or 0
        local regression: Sound? = generator:FindFirstChild("Regression", true) :: Sound?
        local regressing: boolean = generator:GetAttribute("Regressing") == true
            or (regression ~= nil and regression.Playing)
        if progress >= 99.95 then
            return progress, "COMPLETE", Theme.Success
        elseif regressing then
            return progress, "REGRESSING", VD_ALERT_COLOR
        elseif repairers > 0 then
            return progress, "REPAIRING x" .. tostring(repairers), Theme.AccentCyan
        end
        return progress, "IDLE", Color3.fromRGB(244, 190, 88)
    end

    local function toggleGeneratorESP(enabled: boolean): ()
        disconnectFeatureConnection("VDGeneratorESP")
        if not enabled then
            for generator: Model, record: MarkerRecord in pairs(runtime.generatorMarkers) do
                destroyMarker(record)
                runtime.generatorMarkers[generator] = nil
            end
            table.clear(runtime.generatorStates)
            return
        end
        local elapsed: number = 1
        featureConnections.VDGeneratorESP = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.2 then
                return
            end
            elapsed = 0
            local map: Instance? = getMap()
            if not map then
                for generator: Model, record: MarkerRecord in pairs(runtime.generatorMarkers) do
                    destroyMarker(record)
                    runtime.generatorMarkers[generator] = nil
                    runtime.generatorStates[generator] = nil
                end
                return
            end
            for _, descendant: Instance in ipairs(map:GetDescendants()) do
                if isGenerator(descendant) then
                    local generator: Model = descendant :: Model
                    local root: BasePart? = getRoot(generator)
                    if root and not runtime.generatorMarkers[generator] then
                        runtime.generatorMarkers[generator] = createMarker(
                            generator,
                            root,
                            Theme.AccentCyan,
                            "GENERATOR",
                            settings.generatorDistance
                        )
                    end
                end
            end
            local localRoot: BasePart? = getRoot(LocalPlayer.Character)
            for generator: Model, record: MarkerRecord in pairs(runtime.generatorMarkers) do
                if not generator:IsDescendantOf(map) then
                    destroyMarker(record)
                    runtime.generatorMarkers[generator] = nil
                    runtime.generatorStates[generator] = nil
                else
                    local progress: number, status: string, color: Color3 = generatorState(generator)
                    record.highlight.FillColor = color
                    record.highlight.OutlineColor = color
                    record.highlight.FillTransparency = settings.generatorTransparency
                    if record.billboard then
                        record.billboard.MaxDistance = settings.generatorDistance
                    end
                    if record.label then
                        local root: BasePart? = getRoot(generator)
                        local distance: number = if root and localRoot
                            then (root.Position - localRoot.Position).Magnitude
                            else 0
                        record.label.Text = string.format(
                            "GENERATOR · %.1f%%\n%s · %.0f STUDS",
                            progress,
                            status,
                            distance
                        )
                        record.label.TextColor3 = color
                    end
                    local previous: string? = runtime.generatorStates[generator]
                    if previous == "REGRESSING" and status:find("REPAIRING", 1, true) then
                        notify("A survivor touched a regressing generator.")
                    end
                    runtime.generatorStates[generator] = status
                end
            end
        end)
    end

    local function createProximityGui(): ScreenGui
        local gui: ScreenGui = Instance.new("ScreenGui")
        gui.Name = "RTM_VD_Proximity"
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false
        gui.Parent = PlayerGui
        local panel: Frame = Instance.new("Frame")
        panel.Name = "Panel"
        panel.AnchorPoint = Vector2.new(0.5, 1)
        panel.BackgroundColor3 = Color3.fromRGB(10, 13, 21)
        panel.BackgroundTransparency = 0.12
        panel.BorderSizePixel = 0
        panel.Position = UDim2.new(0.5, 0, 1, -28)
        panel.Size = UDim2.fromOffset(320, 55)
        panel.Parent = gui
        local corner: UICorner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 12)
        corner.Parent = panel
        local label: TextLabel = Instance.new("TextLabel")
        label.Name = "Distance"
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamSemibold
        label.Position = UDim2.fromOffset(12, 4)
        label.Size = UDim2.new(1, -24, 0, 25)
        label.Text = "NEAREST SURVIVOR: NO SIGNAL"
        label.TextColor3 = Theme.TextMuted
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = panel
        local track: Frame = Instance.new("Frame")
        track.Name = "Track"
        track.BackgroundColor3 = Theme.SurfaceRaised
        track.BorderSizePixel = 0
        track.Position = UDim2.fromOffset(12, 36)
        track.Size = UDim2.new(1, -24, 0, 8)
        track.Parent = panel
        local trackCorner: UICorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(1, 0)
        trackCorner.Parent = track
        local bar: Frame = Instance.new("Frame")
        bar.Name = "Bar"
        bar.BorderSizePixel = 0
        bar.Size = UDim2.fromScale(0, 1)
        bar.Parent = track
        local barCorner: UICorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(1, 0)
        barCorner.Parent = bar
        return gui
    end

    local function toggleProximity(enabled: boolean): ()
        disconnectFeatureConnection("VDKillerProximity")
        if runtime.proximityGui then
            runtime.proximityGui:Destroy()
            runtime.proximityGui = nil
        end
        if not enabled then
            return
        end
        local gui: ScreenGui = createProximityGui()
        runtime.proximityGui = gui
        local panel: Frame = gui:WaitForChild("Panel") :: Frame
        local label: TextLabel = panel:WaitForChild("Distance") :: TextLabel
        local bar: Frame = (panel:WaitForChild("Track") :: Frame):WaitForChild("Bar") :: Frame
        featureConnections.VDKillerProximity = TaskManager:Connect(function(): ()
            if not isRoundActive() or not isLocalKiller() then
                gui.Enabled = false
                label.Text = "NEAREST SURVIVOR: NO SIGNAL"
                label.TextColor3 = Theme.TextMuted
                bar.Size = UDim2.fromScale(0, 1)
                return
            end
            gui.Enabled = true
            local localRoot: BasePart? = getRoot(LocalPlayer.Character)
            local nearestDistance: number? = nil
            if localRoot then
                for _, player: Player in ipairs(Players:GetPlayers()) do
                    local team: Team? = player.Team
                    local targetRoot: BasePart? = getRoot(player.Character)
                    if player ~= LocalPlayer
                        and team ~= nil
                        and lower(team.Name) == "survivors"
                        and targetRoot ~= nil then
                        local distance: number = (targetRoot.Position - localRoot.Position).Magnitude
                        if nearestDistance == nil or distance < nearestDistance then
                            nearestDistance = distance
                        end
                    end
                end
            end
            if not nearestDistance then
                label.Text = "NEAREST SURVIVOR: NO SIGNAL"
                label.TextColor3 = Theme.TextMuted
                bar.Size = UDim2.fromScale(0, 1)
                return
            end
            local distance: number = nearestDistance
            local color: Color3 = if distance <= 25
                then VD_KILLER_COLOR
                elseif distance <= 60 then Color3.fromRGB(244, 190, 88)
                else Theme.Success
            label.Text = string.format("NEAREST SURVIVOR: %.1f STUDS", distance)
            label.TextColor3 = color
            bar.BackgroundColor3 = color
            bar.Size = UDim2.fromScale(1 - math.clamp(distance / settings.proximityRange, 0, 1), 1)
        end)
    end

    local function survivorStatus(player: Player, character: Model): (string, Color3)
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return "UNKNOWN", Theme.TextMuted
        end
        local hooked: boolean = character:GetAttribute("Hooked") == true
            or character:GetAttribute("IsHooked") == true
            or player:GetAttribute("Hooked") == true
        local downed: boolean = character:GetAttribute("Knocked") == true
            or character:GetAttribute("Downed") == true
            or humanoid.Health <= math.max(1, humanoid.MaxHealth * 0.05)
        local recovery: number? = readNumberAttribute(
            character,
            {"Recovery", "RecoverProgress", "RecoveryProgress"}
        )
        if recovery and recovery <= 1 then
            recovery *= 100
        end
        if hooked then
            return "HOOKED", VD_KILLER_COLOR
        elseif downed then
            return "DOWNED · REC " .. string.format("%.0f%%", recovery or 0), VD_KILLER_COLOR
        elseif humanoid.Health < humanoid.MaxHealth * 0.75 then
            return "INJURED · " .. string.format("%.0f%%", humanoid.Health / humanoid.MaxHealth * 100), Color3.fromRGB(244, 190, 88)
        end
        return "HEALTHY", Theme.Success
    end

    local function findRemoteEvent(folderName: string, eventName: string): RemoteEvent?
        local remotes: Instance? = ReplicatedStorageService:FindFirstChild("Remotes")
        local folder: Instance? = if remotes then remotes:FindFirstChild(folderName) else nil
        local remote: Instance? = if folder then folder:FindFirstChild(eventName) else nil
        return if remote and remote:IsA("RemoteEvent") then remote else nil
    end

    local function getGeneratorForPoint(point: BasePart): Model?
        local parent: Instance? = point.Parent
        return if parent and parent:IsA("Model") and isGenerator(parent)
            then parent
            else nil
    end

    local function nearestGeneratorPoint(root: BasePart): BasePart?
        local map: Instance? = getMap()
        if not map then
            return nil
        end
        local bestPoint: BasePart? = nil
        local bestDistance: number = settings.autoGeneratorRange
        for _, descendant: Instance in ipairs(map:GetDescendants()) do
            if descendant:IsA("BasePart")
                and string.sub(lower(descendant.Name), 1, 14) == "generatorpoint" then
                local generator: Model? = getGeneratorForPoint(descendant)
                if generator then
                    local progress: number = generatorState(generator)
                    local distance: number = (descendant.Position - root.Position).Magnitude
                    if progress < 99.95 and distance <= bestDistance then
                        bestPoint = descendant
                        bestDistance = distance
                    end
                end
            end
        end
        return bestPoint
    end

    local function stopCurrentRepair(repairRemote: RemoteEvent?): ()
        local point: BasePart? = runtime.currentRepairPoint
        runtime.currentRepairPoint = nil
        local animationTrack: AnimationTrack? = runtime.repairAnimation
        if animationTrack then
            animationTrack:Stop(0.12)
            runtime.repairAnimation = nil
        end
        if runtime.repairAnimationObject then
            runtime.repairAnimationObject:Destroy()
            runtime.repairAnimationObject = nil
        end
        if repairRemote and point and point.Parent then
            repairRemote:FireServer(point, false)
        end
    end

    local function maintainRepairAnimation(): ()
        if not settings.autoGeneratorAnimation then
            local current: AnimationTrack? = runtime.repairAnimation
            if current then
                current:Stop(0.12)
                runtime.repairAnimation = nil
            end
            return
        end
        local track: AnimationTrack? = runtime.repairAnimation
        if track and track.IsPlaying then
            return
        end
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = if character
            then character:FindFirstChildOfClass("Humanoid")
            else nil
        local animator: Animator? = if humanoid
            then humanoid:FindFirstChildOfClass("Animator")
            else nil
        if not animator then
            return
        end
        local animation: Animation = Instance.new("Animation")
        animation.Name = "RTM_VD_RepairCrouch"
        animation.AnimationId = "rbxassetid://73650663675588"
        local ok: boolean, loaded: any = pcall(function(): AnimationTrack
            return animator:LoadAnimation(animation)
        end)
        if not ok or not loaded then
            animation:Destroy()
            return
        end
        track = loaded :: AnimationTrack
        track.Looped = true
        track.Priority = Enum.AnimationPriority.Action
        track:Play(0.12, 1, 1)
        runtime.repairAnimationObject = animation
        runtime.repairAnimation = track
    end

    local function killerInsideCriticalRange(root: BasePart): boolean
        local _, killer: Model? = getKiller()
        local killerRoot: BasePart? = getRoot(killer)
        return killerRoot ~= nil
            and (killerRoot.Position - root.Position).Magnitude < 4
    end

    local function toggleAutoGeneratorAura(enabled: boolean): ()
        disconnectFeatureConnection("VDAutoGeneratorAura")
        disconnectFeatureConnection("VDAutoGeneratorCancel")
        local repairRemote: RemoteEvent? = findRemoteEvent("Generator", "RepairEvent")
        stopCurrentRepair(repairRemote)
        runtime.manualGeneratorBlocked = false
        runtime.manualGeneratorLeft = false
        runtime.manualGeneratorOrigin = nil
        if not enabled then
            return
        end
        assert(repairRemote, "VD Remotes.Generator.RepairEvent is unavailable")
        featureConnections.VDAutoGeneratorCancel = UserInputService.InputBegan:Connect(function(
            input: InputObject,
            _gameProcessed: boolean
        ): ()
            if not state.keyCaptureCallback
                and not state.waitingForKey
                and input.KeyCode == Enum.KeyCode.Space
                and settings.autoGeneratorGetOff == "Manual" then
                local currentPoint: BasePart? = runtime.currentRepairPoint
                local root: BasePart? = getRoot(LocalPlayer.Character)
                runtime.manualGeneratorBlocked = true
                runtime.manualGeneratorLeft = false
                runtime.manualGeneratorOrigin = if currentPoint
                    then currentPoint.Position
                    elseif root then root.Position
                    else nil
                stopCurrentRepair(repairRemote)
                notify("Auto Generator paused; move 5 studs away and return.")
            end
        end)
        featureConnections.VDAutoGeneratorAura = TaskManager:Connect(function(): ()
            local team: Team? = LocalPlayer.Team
            local root: BasePart? = getRoot(LocalPlayer.Character)
            if not isRoundActive()
                or not team
                or lower(team.Name) ~= "survivors"
                or not root then
                stopCurrentRepair(repairRemote)
                return
            end
            if settings.autoGeneratorGetOff == "Smart"
                and killerInsideCriticalRange(root) then
                stopCurrentRepair(repairRemote)
                return
            end
            if settings.autoGeneratorGetOff == "Manual"
                and runtime.manualGeneratorBlocked then
                local origin: Vector3? = runtime.manualGeneratorOrigin
                local originDistance: number = if origin
                    then (root.Position - origin).Magnitude
                    else 0
                if not runtime.manualGeneratorLeft and originDistance >= 5 then
                    runtime.manualGeneratorLeft = true
                elseif runtime.manualGeneratorLeft
                    and originDistance <= settings.autoGeneratorRange then
                    runtime.manualGeneratorBlocked = false
                    runtime.manualGeneratorLeft = false
                    runtime.manualGeneratorOrigin = nil
                else
                    stopCurrentRepair(repairRemote)
                    return
                end
            end
            local point: BasePart? = nearestGeneratorPoint(root)
            if point ~= runtime.currentRepairPoint then
                stopCurrentRepair(repairRemote)
                runtime.currentRepairPoint = point
            end
            if not point then
                stopCurrentRepair(repairRemote)
                return
            end
            maintainRepairAnimation()
            if settings.autoGeneratorMode == "Blatant" then
                for _burstIndex: number = 1, 8 do
                    repairRemote:FireServer(point, true)
                end
            elseif os.clock() - runtime.lastRepairFire >= settings.autoGeneratorInterval then
                runtime.lastRepairFire = os.clock()
                repairRemote:FireServer(point, true)
            end
        end)
    end

    local function isAttackTrack(track: AnimationTrack): boolean
        local animation: Animation? = track.Animation
        local descriptor: string = lower(track.Name)
            .. " "
            .. lower(if animation then animation.AnimationId else "")
        for _, excluded: string in ipairs({
            "idle", "walk", "run", "vault", "stun", "carry", "mori", "break",
        }) do
            if contains(descriptor, excluded) then
                return false
            end
        end
        for _, keyword: string in ipairs({
            "attack", "swing", "slash", "stab", "strike", "lunge", "basic", "m1",
        }) do
            if contains(descriptor, keyword) then
                return true
            end
        end
        return track.Priority == Enum.AnimationPriority.Action
            or track.Priority == Enum.AnimationPriority.Action2
            or track.Priority == Enum.AnimationPriority.Action3
            or track.Priority == Enum.AnimationPriority.Action4
    end

    local function bindAutoParryAnimator(
        animator: Animator?,
        parryRemote: RemoteEvent
    ): ()
        if runtime.boundKillerAnimator == animator then
            return
        end
        disconnectFeatureConnection("VDAutoParryAnimation")
        runtime.boundKillerAnimator = animator
        if not animator then
            return
        end
        featureConnections.VDAutoParryAnimation = animator.AnimationPlayed:Connect(function(
            track: AnimationTrack
        ): ()
            if not isAttackTrack(track) or not isRoundActive() then
                return
            end
            local team: Team? = LocalPlayer.Team
            local localRoot: BasePart? = getRoot(LocalPlayer.Character)
            local killer: Model? = animator:FindFirstAncestorOfClass("Model")
            local killerRoot: BasePart? = getRoot(killer)
            if not team
                or lower(team.Name) ~= "survivors"
                or not localRoot
                or not killerRoot
                or (killerRoot.Position - localRoot.Position).Magnitude > settings.autoParryRange
                or os.clock() - runtime.lastParry < 0.22 then
                return
            end
            runtime.lastParry = os.clock()
            parryRemote:FireServer()
        end)
    end

    local function toggleAutoParry(enabled: boolean): ()
        disconnectFeatureConnection("VDAutoParryScan")
        disconnectFeatureConnection("VDAutoParryAnimation")
        runtime.boundKillerAnimator = nil
        if not enabled then
            return
        end
        local parryRemote: RemoteEvent? = nil
        local remotes: Instance? = ReplicatedStorageService:FindFirstChild("Remotes")
        local items: Instance? = if remotes then remotes:FindFirstChild("Items") else nil
        local dagger: Instance? = if items then items:FindFirstChild("Parrying Dagger") else nil
        local candidate: Instance? = if dagger then dagger:FindFirstChild("parry") else nil
        if candidate and candidate:IsA("RemoteEvent") then
            parryRemote = candidate
        end
        assert(parryRemote, "VD Remotes.Items.Parrying Dagger.parry is unavailable")
        local elapsed: number = 1
        featureConnections.VDAutoParryScan = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.1 then
                return
            end
            elapsed = 0
            local _, killer: Model? = getKiller()
            local humanoid: Humanoid? = if killer then killer:FindFirstChildOfClass("Humanoid") else nil
            local animator: Animator? = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
            bindAutoParryAnimator(if getMap() then animator else nil, parryRemote :: RemoteEvent)
        end)
    end

    local function nearestSurvivor(root: BasePart, maximumRange: number): BasePart?
        local best: BasePart? = nil
        local bestDistance: number = maximumRange
        for _, player: Player in ipairs(Players:GetPlayers()) do
            local character: Model? = player.Character
            local humanoid: Humanoid? = if character then character:FindFirstChildOfClass("Humanoid") else nil
            local targetRoot: BasePart? = getRoot(character)
            if player ~= LocalPlayer
                and player.Team ~= nil
                and lower((player.Team :: Team).Name) == "survivors"
                and humanoid
                and humanoid.Health > 0
                and targetRoot then
                local distance: number = (targetRoot.Position - root.Position).Magnitude
                if distance <= bestDistance then
                    best = targetRoot
                    bestDistance = distance
                end
            end
        end
        return best
    end

    local function toggleKillerHitAura(enabled: boolean): ()
        disconnectFeatureConnection("VDKillerHitAura")
        if not enabled then
            local character: Model? = LocalPlayer.Character
            local humanoid: Humanoid? = if character
                then character:FindFirstChildOfClass("Humanoid")
                else nil
            if humanoid and runtime.killerBaseWalkSpeed and not runtime.walkSpeedEnabled then
                humanoid.WalkSpeed = runtime.killerBaseWalkSpeed
            end
            runtime.killerBaseWalkSpeed = nil
            return
        end
        local attackRemote: RemoteEvent? = findRemoteEvent("Attacks", "BasicAttack")
        assert(attackRemote, "VD Remotes.Attacks.BasicAttack is unavailable")
        featureConnections.VDKillerHitAura = TaskManager:Connect(function(): ()
            local team: Team? = LocalPlayer.Team
            local character: Model? = LocalPlayer.Character
            local localRoot: BasePart? = getRoot(LocalPlayer.Character)
            local humanoid: Humanoid? = if character
                then character:FindFirstChildOfClass("Humanoid")
                else nil
            if not isRoundActive()
                or not team
                or lower(team.Name) ~= "killer"
                or not localRoot
                or not humanoid then
                return
            end
            if runtime.killerBaseWalkSpeed == nil then
                runtime.killerBaseWalkSpeed = humanoid.WalkSpeed
            end
            local preventSlowdown: boolean = settings.hitAuraMode == "Blatant"
                or settings.hitAuraRun == true
            if preventSlowdown then
                humanoid.WalkSpeed = math.max(
                    humanoid.WalkSpeed,
                    runtime.killerBaseWalkSpeed :: number
                )
            end
            local attackRange: number = if settings.hitAuraMode == "Blatant"
                then settings.hitAuraBlatantReach
                else settings.hitAuraRange
            local target: BasePart? = nearestSurvivor(localRoot, attackRange)
            if not target then
                return
            end
            if settings.hitAuraMode == "Blatant" then
                for _burstIndex: number = 1, 4 do
                    attackRemote:FireServer()
                end
                runtime.lastHit = os.clock()
            elseif os.clock() - runtime.lastHit >= settings.hitAuraInterval then
                runtime.lastHit = os.clock()
                attackRemote:FireServer()
            end
        end)
    end

    local function isFootstepSound(sound: Sound): boolean
        local name: string = lower(sound.Name)
        return contains(name, "foot")
            or contains(name, "step")
            or contains(name, "running")
            or contains(name, "walking")
            or contains(name, "sprint")
    end

    local function silenceSound(sound: Sound): ()
        if not isFootstepSound(sound) or runtime.soundStates[sound] then
            return
        end
        runtime.soundStates[sound] = {volume = sound.Volume}
        sound.Volume = 0
        sound:Stop()
        runtime.soundConnections[sound] = sound.Played:Connect(function(): ()
            if runtime.silentStepsEnabled then
                sound.Volume = 0
                sound:Stop()
            end
        end)
    end

    local function restoreSilentSounds(): ()
        for sound: Sound, connection: RBXScriptConnection in pairs(runtime.soundConnections) do
            connection:Disconnect()
            runtime.soundConnections[sound] = nil
        end
        for sound: Sound, original: SoundState in pairs(runtime.soundStates) do
            if sound.Parent then
                sound.Volume = original.volume
            end
            runtime.soundStates[sound] = nil
        end
    end

    local function bindSilentCharacter(character: Model): ()
        disconnectFeatureConnection("VDSilentDescendant")
        for _, descendant: Instance in ipairs(character:GetDescendants()) do
            if descendant:IsA("Sound") then
                silenceSound(descendant)
            end
        end
        featureConnections.VDSilentDescendant = character.DescendantAdded:Connect(function(
            descendant: Instance
        ): ()
            if descendant:IsA("Sound") then
                silenceSound(descendant)
            end
        end)
    end

    local function toggleSilentSteps(enabled: boolean): ()
        disconnectFeatureConnection("VDSilentCharacter")
        disconnectFeatureConnection("VDSilentDescendant")
        runtime.silentStepsEnabled = enabled
        restoreSilentSounds()
        if not enabled then
            return
        end
        if LocalPlayer.Character then
            bindSilentCharacter(LocalPlayer.Character)
        end
        featureConnections.VDSilentCharacter = LocalPlayer.CharacterAdded:Connect(function(
            character: Model
        ): ()
            if runtime.silentStepsEnabled then
                bindSilentCharacter(character)
            end
        end)
    end

    local function nearestVault(root: BasePart): BasePart?
        local map: Instance? = getMap()
        local best: BasePart? = nil
        local bestDistance: number = settings.vaultRange
        if not map then
            return nil
        end
        for _, descendant: Instance in ipairs(map:GetDescendants()) do
            if descendant:IsA("BasePart") and lower(descendant.Name) == "vaulttrigger" then
                local distance: number = (descendant.Position - root.Position).Magnitude
                if distance < bestDistance then
                    best = descendant
                    bestDistance = distance
                end
            end
        end
        return best
    end

    local function toggleFastVault(enabled: boolean): ()
        disconnectFeatureConnection("VDFastVault")
        if not enabled then
            return
        end
        local vaultRemote: RemoteEvent? = findRemoteEvent("Window", "VaultEvent")
        local fastVaultRemote: RemoteEvent? = findRemoteEvent("Window", "fastvault")
        local completePartRemote: RemoteEvent? = findRemoteEvent(
            "Window",
            "VaultCompleteEventpart1"
        )
        local completeRemote: RemoteEvent? = findRemoteEvent("Window", "VaultCompleteEvent")
        assert(vaultRemote, "VD Remotes.Window.VaultEvent is unavailable")
        local verifiedVaultRemote: RemoteEvent = vaultRemote :: RemoteEvent
        featureConnections.VDFastVault = TaskManager:Connect(function(): ()
            local character: Model? = LocalPlayer.Character
            local root: BasePart? = getRoot(character)
            local humanoid: Humanoid? = if character then character:FindFirstChildOfClass("Humanoid") else nil
            if not root or not humanoid or humanoid.MoveDirection.Magnitude < 0.2 then
                return
            end
            local trigger: BasePart? = nearestVault(root)
            if not trigger then
                return
            end
            local repeatDelay: number = math.max(0.08, 0.55 / settings.vaultSpeed)
            if trigger ~= runtime.lastVaultPoint
                or os.clock() - runtime.lastVaultInput > repeatDelay then
                runtime.lastVaultInput = os.clock()
                runtime.lastVaultPoint = trigger
                local destination: CFrame = trigger.CFrame * CFrame.new(0, 2, -1)
                root.CFrame = root.CFrame:Lerp(
                    destination,
                    math.clamp(settings.vaultSpeed / 10, 0.25, 1)
                )
                verifiedVaultRemote:FireServer(trigger, true)
                if fastVaultRemote then
                    fastVaultRemote:FireServer(LocalPlayer)
                end
                if completePartRemote then
                    completePartRemote:FireServer()
                end
                if completeRemote then
                    completeRemote:FireServer(trigger, false)
                end
            end
        end)
    end

    local facingParts: {[Player]: Part} = {}
    local function clearFacing(): ()
        for player: Player, part: Part in pairs(facingParts) do
            part:Destroy()
            facingParts[player] = nil
        end
    end

    local function toggleFacingESP(enabled: boolean): ()
        disconnectFeatureConnection("VDFacingESP")
        clearFacing()
        if not enabled then
            return
        end
        featureConnections.VDFacingESP = TaskManager:Connect(function(): ()
            if not getMap() then
                clearFacing()
                return
            end
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and isPlayerInRound(player)
                    and player.Character then
                    local head: BasePart? = player.Character:FindFirstChild("Head") :: BasePart?
                    if head then
                        local line: Part? = facingParts[player]
                        if not line then
                            line = Instance.new("Part")
                            line.Name = "RTM_VD_Facing"
                            line.Anchored = true
                            line.CanCollide = false
                            line.CanQuery = false
                            line.CanTouch = false
                            line.CastShadow = false
                            line.Material = Enum.Material.Neon
                            line.Transparency = 0.28
                            line.Parent = getVisualFolder()
                            facingParts[player] = line
                        end
                        local length: number = 16
                        local origin: Vector3 = head.Position
                        local direction: Vector3 = head.CFrame.LookVector
                        line.Color = if isKillerCharacter(player.Character)
                            then VD_KILLER_COLOR else Theme.AccentCyan
                        line.Size = Vector3.new(0.08, 0.08, length)
                        line.CFrame = CFrame.lookAt(
                            origin + direction * (length / 2),
                            origin + direction * length
                        )
                    end
                end
            end
            for player: Player, part: Part in pairs(facingParts) do
                if not player.Parent or not player.Character then
                    part:Destroy()
                    facingParts[player] = nil
                end
            end
        end)
    end

    local function isHiding(player: Player, character: Model): boolean
        for _, name: string in ipairs({"Hiding", "InLocker", "IsHiding", "Hidden"}) do
            if player:GetAttribute(name) == true or character:GetAttribute(name) == true then
                return true
            end
        end
        local lockerValue: Instance? = character:FindFirstChild("Locker", true)
            or character:FindFirstChild("CurrentLocker", true)
        return lockerValue ~= nil
    end

    local function clearLockerMarkers(): ()
        for player: Player, record: MarkerRecord in pairs(runtime.lockerMarkers) do
            destroyMarker(record)
            runtime.lockerMarkers[player] = nil
        end
    end

    local function toggleLockerDetector(enabled: boolean): ()
        disconnectFeatureConnection("VDLockerDetector")
        table.clear(runtime.lockerAlerts)
        clearLockerMarkers()
        if not enabled then
            return
        end
        local elapsed: number = 1
        featureConnections.VDLockerDetector = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.25 then
                return
            end
            elapsed = 0
            local localRoot: BasePart? = getRoot(LocalPlayer.Character)
            if not getMap() or not localRoot then
                clearLockerMarkers()
                return
            end
            for _, player: Player in ipairs(Players:GetPlayers()) do
                local character: Model? = player.Character
                local root: BasePart? = getRoot(character)
                local record: MarkerRecord? = runtime.lockerMarkers[player]
                local hidingInRange: boolean = player ~= LocalPlayer and character ~= nil and root ~= nil
                    and not isKillerCharacter(character)
                    and isHiding(player, character)
                    and (root.Position - localRoot.Position).Magnitude <= settings.lockerRange
                if hidingInRange and character and root then
                    local distance: number = (root.Position - localRoot.Position).Magnitude
                    local text: string = string.format(
                        "HIDDEN PLAYER\n%s · %.0f STUDS",
                        player.DisplayName,
                        distance
                    )
                    if not record or record.highlight.Adornee ~= character then
                        destroyMarker(record)
                        record = createMarker(character, root, Theme.AccentCyan, text, 600)
                        record.highlight.FillTransparency = 0.3
                        record.highlight.OutlineTransparency = 0
                        runtime.lockerMarkers[player] = record
                    elseif record.label then
                        record.label.Text = text
                    end
                    local lastAlert: number = runtime.lockerAlerts[player] or 0
                    if os.clock() - lastAlert > 8 then
                        runtime.lockerAlerts[player] = os.clock()
                        notify(player.DisplayName .. " entered a nearby locker/hideout.")
                    end
                elseif record then
                    destroyMarker(record)
                    runtime.lockerMarkers[player] = nil
                end
            end
            for player: Player, record: MarkerRecord in pairs(runtime.lockerMarkers) do
                if not player.Parent then
                    destroyMarker(record)
                    runtime.lockerMarkers[player] = nil
                end
            end
        end)
    end

    local function isAcceleratedAction(track: AnimationTrack): boolean
        local animation: Animation? = track.Animation
        local descriptor: string = lower(track.Name)
            .. " "
            .. lower(if animation then animation.AnimationId else "")
        for _, keyword: string in ipairs({
            "vault", "pallet", "break", "hook", "unhook", "rescue",
            "repair", "heal", "interact", "open", "lever", "pickup",
        }) do
            if contains(descriptor, keyword) then
                return true
            end
        end
        return track.Priority == Enum.AnimationPriority.Action
            or track.Priority == Enum.AnimationPriority.Action2
            or track.Priority == Enum.AnimationPriority.Action3
            or track.Priority == Enum.AnimationPriority.Action4
    end

    local function bindActionAnimator(animator: Animator?): ()
        if runtime.actionAnimator == animator then
            return
        end
        disconnectFeatureConnection("VDCooldownAnimation")
        runtime.actionAnimator = animator
        if not animator then
            return
        end
        featureConnections.VDCooldownAnimation = animator.AnimationPlayed:Connect(function(
            track: AnimationTrack
        ): ()
            if runtime.cooldownModifierEnabled and isAcceleratedAction(track) then
                track:AdjustSpeed(settings.actionSpeed)
            end
        end)
        for _, track: AnimationTrack in ipairs(animator:GetPlayingAnimationTracks()) do
            if isAcceleratedAction(track) then
                track:AdjustSpeed(settings.actionSpeed)
            end
        end
    end

    local function toggleCooldownModifier(enabled: boolean): ()
        disconnectFeatureConnection("VDCooldownModifier")
        disconnectFeatureConnection("VDCooldownAnimation")
        runtime.cooldownModifierEnabled = enabled
        runtime.actionAnimator = nil
        if not enabled then
            local character: Model? = LocalPlayer.Character
            local humanoid: Humanoid? = if character
                then character:FindFirstChildOfClass("Humanoid")
                else nil
            local animator: Animator? = if humanoid
                then humanoid:FindFirstChildOfClass("Animator")
                else nil
            if animator then
                for _, track: AnimationTrack in ipairs(animator:GetPlayingAnimationTracks()) do
                    if isAcceleratedAction(track) then
                        track:AdjustSpeed(1)
                    end
                end
            end
            return
        end
        featureConnections.VDCooldownModifier = TaskManager:Connect(function(): ()
            local character: Model? = LocalPlayer.Character
            local humanoid: Humanoid? = if character
                then character:FindFirstChildOfClass("Humanoid")
                else nil
            local animator: Animator? = if humanoid
                then humanoid:FindFirstChildOfClass("Animator")
                else nil
            bindActionAnimator(animator)
        end)
    end

    local function bindDamageHumanoid(humanoid: Humanoid?): ()
        if runtime.trackedHumanoid == humanoid then
            return
        end
        disconnectFeatureConnection("VDDamageHealth")
        runtime.trackedHumanoid = humanoid
        if not humanoid then
            return
        end
        local previousHealth: number = humanoid.Health
        featureConnections.VDDamageHealth = humanoid.HealthChanged:Connect(function(
            health: number
        ): ()
            if runtime.damageBoostEnabled and health < previousHealth and health > 0 then
                runtime.damageBoostToken += 1
                local boostToken: number = runtime.damageBoostToken
                local originalSpeed: number = humanoid.WalkSpeed
                runtime.damageOriginalSpeed = originalSpeed
                runtime.damageBoostUntil = os.clock() + settings.damageBoostDuration
                humanoid.WalkSpeed = math.max(
                    humanoid.WalkSpeed,
                    originalSpeed + settings.damageBoost
                )
                task.delay(settings.damageBoostDuration, function(): ()
                    if runtime.damageBoostEnabled
                        and runtime.damageBoostToken == boostToken
                        and humanoid.Parent
                        and not runtime.walkSpeedEnabled then
                        humanoid.WalkSpeed = originalSpeed
                        runtime.damageOriginalSpeed = nil
                    end
                end)
            end
            previousHealth = health
        end)
    end

    local function toggleDamageBoost(enabled: boolean): ()
        disconnectFeatureConnection("VDDamageBoost")
        disconnectFeatureConnection("VDDamageHealth")
        runtime.damageBoostEnabled = enabled
        runtime.trackedHumanoid = nil
        runtime.damageBoostToken += 1
        runtime.damageBoostUntil = 0
        if not enabled then
            local character: Model? = LocalPlayer.Character
            local humanoid: Humanoid? = if character
                then character:FindFirstChildOfClass("Humanoid")
                else nil
            if humanoid and runtime.damageOriginalSpeed and not runtime.walkSpeedEnabled then
                humanoid.WalkSpeed = runtime.damageOriginalSpeed
            end
            runtime.damageOriginalSpeed = nil
            return
        end
        featureConnections.VDDamageBoost = TaskManager:Connect(function(): ()
            local character: Model? = LocalPlayer.Character
            local humanoid: Humanoid? = if character
                then character:FindFirstChildOfClass("Humanoid")
                else nil
            bindDamageHumanoid(humanoid)
        end)
    end

    local function isSelectiveNoclipPart(part: BasePart): boolean
        local cursor: Instance? = part
        for _depth: number = 1, 4 do
            if not cursor then
                break
            end
            local name: string = lower(cursor.Name)
            if contains(name, "pallet")
                or contains(name, "vault")
                or contains(name, "window") then
                return true
            end
            if cursor:IsA("Model")
                and cursor:FindFirstChild("VaultTrigger") ~= nil then
                return true
            end
            cursor = cursor.Parent
        end
        return false
    end

    local function restoreSelectiveCollisions(): ()
        for part: BasePart, original: CollisionState in pairs(runtime.selectiveCollisions) do
            if part.Parent then
                part.CanCollide = original.canCollide
            end
            runtime.selectiveCollisions[part] = nil
        end
    end

    local function toggleSelectiveNoclip(enabled: boolean): ()
        disconnectFeatureConnection("VDSelectiveNoclip")
        restoreSelectiveCollisions()
        if not enabled then
            return
        end
        local elapsed: number = 1
        featureConnections.VDSelectiveNoclip = TaskManager:Connect(function(
            deltaTime: number
        ): ()
            elapsed += deltaTime
            if elapsed < 0.35 then
                return
            end
            elapsed = 0
            local map: Instance? = getMap()
            if not map then
                restoreSelectiveCollisions()
                return
            end
            for _, descendant: Instance in ipairs(map:GetDescendants()) do
                if descendant:IsA("BasePart")
                    and descendant.CanCollide
                    and isSelectiveNoclipPart(descendant) then
                    if not runtime.selectiveCollisions[descendant] then
                        runtime.selectiveCollisions[descendant] = {
                            canCollide = descendant.CanCollide,
                        }
                    end
                    descendant.CanCollide = false
                end
            end
            for part: BasePart, original: CollisionState in pairs(runtime.selectiveCollisions) do
                if not part:IsDescendantOf(map) then
                    if part.Parent then
                        part.CanCollide = original.canCollide
                    end
                    runtime.selectiveCollisions[part] = nil
                end
            end
        end)
    end

    local function toggleWalkSpeed(enabled: boolean): ()
        disconnectFeatureConnection("VDWalkSpeed")
        runtime.walkSpeedEnabled = enabled
        local character: Model? = LocalPlayer.Character
        local humanoid: Humanoid? = if character
            then character:FindFirstChildOfClass("Humanoid")
            else nil
        if not enabled then
            if humanoid and runtime.walkSpeedBase then
                humanoid.WalkSpeed = runtime.walkSpeedBase
            end
            runtime.walkSpeedBase = nil
            return
        end
        runtime.walkSpeedBase = if humanoid then humanoid.WalkSpeed else settings.walkSpeed
        featureConnections.VDWalkSpeed = TaskManager:Connect(function(): ()
            local currentCharacter: Model? = LocalPlayer.Character
            local currentHumanoid: Humanoid? = if currentCharacter
                then currentCharacter:FindFirstChildOfClass("Humanoid")
                else nil
            if currentHumanoid and isRoundActive() then
                local activeBoost: number = if os.clock() < runtime.damageBoostUntil
                    then settings.damageBoost
                    else 0
                currentHumanoid.WalkSpeed = settings.walkSpeed + activeBoost
            end
        end)
    end

    local function createCooldownGui(): ScreenGui
        local gui: ScreenGui = Instance.new("ScreenGui")
        gui.Name = "RTM_VD_Cooldowns"
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false
        gui.Parent = PlayerGui
        local label: TextLabel = Instance.new("TextLabel")
        label.Name = "Cooldowns"
        label.AnchorPoint = Vector2.new(1, 0.5)
        label.BackgroundColor3 = Color3.fromRGB(10, 13, 21)
        label.BackgroundTransparency = 0.12
        label.BorderSizePixel = 0
        label.Font = Enum.Font.GothamMedium
        label.Position = UDim2.new(1, -22, 0.5, 0)
        label.Size = UDim2.fromOffset(260, 100)
        label.Text = "KILLER POWER\nNO DATA"
        label.TextColor3 = Theme.Text
        label.TextSize = 13
        label.TextWrapped = true
        label.Parent = gui
        local corner: UICorner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 11)
        corner.Parent = label
        return gui
    end

    local function cooldownText(): string
        local killerPlayer: Player?, killer: Model? = getKiller()
        if not killer then
            return "KILLER POWER\nNO SIGNAL"
        end
        local lines: {string} = {"KILLER POWER"}
        local function appendAttributes(instance: Instance): ()
            for name: string, value: any in pairs(instance:GetAttributes()) do
                local key: string = lower(name)
                if (contains(key, "cooldown") or contains(key, "charge") or contains(key, "power"))
                    and (type(value) == "number" or type(value) == "boolean") then
                    table.insert(lines, name .. ": " .. tostring(value))
                    if #lines >= 6 then
                        return
                    end
                end
            end
        end
        appendAttributes(killer)
        if killerPlayer and #lines < 6 then
            appendAttributes(killerPlayer)
        end
        if #lines == 1 then
            table.insert(lines, "READY / NO REPLICATED TIMER")
        end
        return table.concat(lines, "\n")
    end

    local function toggleCooldownTracker(enabled: boolean): ()
        disconnectFeatureConnection("VDCooldownTracker")
        if runtime.cooldownGui then
            runtime.cooldownGui:Destroy()
            runtime.cooldownGui = nil
        end
        if not enabled then
            return
        end
        local gui: ScreenGui = createCooldownGui()
        runtime.cooldownGui = gui
        local label: TextLabel = gui:WaitForChild("Cooldowns") :: TextLabel
        local elapsed: number = 1
        featureConnections.VDCooldownTracker = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed >= 0.15 then
                elapsed = 0
                label.Text = cooldownText()
            end
        end)
    end

    local function toggleFov(enabled: boolean): ()
        disconnectFeatureConnection("VDFOV")
        state.fovController.set("VD", enabled and settings.fov or nil)
        if not enabled then
            return
        end
        featureConnections.VDFOV = TaskManager:Connect(function(): ()
            state.fovController.set("VD", settings.fov)
            state.fovController.apply(workspace.CurrentCamera)
        end)
    end

    local function suppressBlindEffect(effect: Instance): ()
        local name: string = lower(effect.Name)
        if not contains(name, "blind")
            and not contains(name, "flash")
            and not contains(name, "whiteout") then
            return
        end
        if effect:IsA("PostEffect") then
            if runtime.effectStates[effect] == nil then
                runtime.effectStates[effect] = effect.Enabled
            end
            effect.Enabled = false
        elseif effect:IsA("GuiObject") and effect ~= ScreenGui then
            if runtime.effectStates[effect] == nil then
                runtime.effectStates[effect] = effect.Visible
            end
            effect.Visible = false
        end
    end

    local function toggleNoBlind(enabled: boolean): ()
        disconnectFeatureConnection("VDNoBlindLighting")
        disconnectFeatureConnection("VDNoBlindGui")
        disconnectFeatureConnection("VDNoBlindGuard")
        if not enabled then
            for effect: Instance, original: any in pairs(runtime.effectStates) do
                if effect.Parent then
                    if effect:IsA("PostEffect") then
                        effect.Enabled = original
                    elseif effect:IsA("GuiObject") then
                        effect.Visible = original
                    end
                end
                runtime.effectStates[effect] = nil
            end
            return
        end
        for _, root: Instance in ipairs({Lighting, PlayerGui}) do
            for _, descendant: Instance in ipairs(root:GetDescendants()) do
                suppressBlindEffect(descendant)
            end
        end
        featureConnections.VDNoBlindLighting = Lighting.DescendantAdded:Connect(function(
            descendant: Instance
        ): ()
            suppressBlindEffect(descendant)
        end)
        featureConnections.VDNoBlindGui = PlayerGui.DescendantAdded:Connect(function(
            descendant: Instance
        ): ()
            suppressBlindEffect(descendant)
        end)
        featureConnections.VDNoBlindGuard = TaskManager:Connect(function(): ()
            for effect: Instance, _original: any in pairs(runtime.effectStates) do
                if not effect.Parent then
                    runtime.effectStates[effect] = nil
                elseif effect:IsA("PostEffect") then
                    effect.Enabled = false
                elseif effect:IsA("GuiObject") then
                    effect.Visible = false
                end
            end
        end)
    end

    local function toggleVDFullbright(enabled: boolean): ()
        disconnectFeatureConnection("VDFullbright")
        if not enabled then
            if runtime.lighting then
                for property: string, value: any in pairs(runtime.lighting) do
                    (Lighting :: any)[property] = value
                end
                runtime.lighting = nil
            end
            return
        end
        runtime.lighting = {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd,
            GlobalShadows = Lighting.GlobalShadows,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
        }
        featureConnections.VDFullbright = TaskManager:Connect(function(): ()
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(190, 190, 190)
            Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
        end)
    end

    -- The universal Player ESP learns this game's two roles, so its boxes,
    -- chams, tracers and name tags all read Killer or Survivor without VD
    -- having to draw any of them itself.
    registerRoleProvider({
        Name = "VD",
        Roles = {"Killer", "Survivor"},
        Colors = {
            Killer = Color3.fromRGB(226, 72, 72),
            Survivor = Color3.fromRGB(120, 190, 255),
        },
        Get = function(player: Player): string?
            local character: Model? = player.Character
            if not character then
                return nil
            end
            return isKillerCharacter(character) and "Killer" or "Survivor"
        end,
    })

    -- Generators are an option of the universal Player ESP, not a card of
    -- their own: it is the same "mark a thing through a wall" idea, and the
    -- only reason it lives in this file is that nothing universal knows what a
    -- VD generator is. The rows appear only in this game.
    registerEspExtra({
        Name = "Generators",
        Default = false,
        Tooltip = "Match generators with their exact progress, state and "
            .. "distance. workspace.Map only; Lobby and Spectator objects are "
            .. "ignored.",
        Toggle = toggleGeneratorESP,
        Options = {
            {
                Kind = "number",
                Name = "max distance",
                Default = 1800,
                Min = 200,
                Max = 3000,
                Set = function(value: number): ()
                    settings.generatorDistance = value
                end,
            },
            {
                Kind = "number",
                Name = "fill",
                Default = 0.82,
                Min = 0,
                Max = 1,
                Set = function(value: number): ()
                    settings.generatorTransparency = math.clamp(value, 0, 1)
                end,
            },
        },
    })

    local GeneratorAuraFeature: any = createUniversalFeature(
        "Auto Generator",
        "Automatically maintains the native RepairEvent on a nearby generator point",
        3,
        toggleAutoGeneratorAura,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addToggleOption(GeneratorAuraFeature, "Animation", true, function(value: boolean): ()
        settings.autoGeneratorAnimation = value
    end)
    addCycleOption(GeneratorAuraFeature, "Get Off", {"Manual", "Smart"}, 1, function(value: string): ()
        settings.autoGeneratorGetOff = value
        runtime.manualGeneratorBlocked = false
        runtime.manualGeneratorLeft = false
        runtime.manualGeneratorOrigin = nil
    end)
    addNumberOption(GeneratorAuraFeature, "Interaction range", 18, 5, 30, function(value: number): ()
        settings.autoGeneratorRange = math.max(1, value)
    end)
    local GeneratorIntervalOption: Frame = addNumberOption(
        GeneratorAuraFeature,
        "Legit interval",
        0.12,
        0.03,
        0.5,
        function(value: number): ()
            settings.autoGeneratorInterval = math.max(0.01, value)
        end
    )
    addCycleOption(GeneratorAuraFeature, "Mode", {"Legit", "Blatant"}, 1, function(value: string): ()
        settings.autoGeneratorMode = value
        setOptionVisible(GeneratorAuraFeature, GeneratorIntervalOption, value == "Legit")
    end)

    local AutoParryFeature: any = createUniversalFeature(
        "Auto Parry / Auto Block",
        "Fire the dagger parry remote when an in-range Killer attack starts",
        4,
        toggleAutoParry,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(AutoParryFeature, "Parry range", 18, 4, 35, function(value: number): ()
        settings.autoParryRange = math.max(1, value)
    end)

    local HitAuraFeature: any = createUniversalFeature(
        "Killer Hit Aura",
        "Trigger the native BasicAttack without forcing camera or character rotation",
        5,
        toggleKillerHitAura,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    local HitRunButton: TextButton = addToggleOption(
        HitAuraFeature,
        "Run",
        false,
        function(value: boolean): ()
            settings.hitAuraRun = value
        end
    )
    local HitRangeOption: Frame = addNumberOption(
        HitAuraFeature,
        "Legit range",
        12,
        3,
        18,
        function(value: number): ()
            settings.hitAuraRange = math.max(1, value)
        end
    )
    local HitIntervalOption: Frame = addNumberOption(
        HitAuraFeature,
        "Legit cooldown",
        0.72,
        0.2,
        1.5,
        function(value: number): ()
            settings.hitAuraInterval = math.max(0.05, value)
        end
    )
    local BlatantReachOption: Frame = addNumberOption(
        HitAuraFeature,
        "Blatant reach",
        34,
        12,
        60,
        function(value: number): ()
            settings.hitAuraBlatantReach = math.max(1, value)
        end
    )
    addCycleOption(HitAuraFeature, "Mode", {"Legit", "Blatant"}, 1, function(value: string): ()
        settings.hitAuraMode = value
        local legit: boolean = value == "Legit"
        setOptionVisible(HitAuraFeature, HitRunButton.Parent :: GuiObject, legit)
        setOptionVisible(HitAuraFeature, HitRangeOption, legit)
        setOptionVisible(HitAuraFeature, HitIntervalOption, legit)
        setOptionVisible(HitAuraFeature, BlatantReachOption, not legit)
    end)

    local VaultFeature: any = createUniversalFeature(
        "Fast Vault Optimizer",
        "Use VD's verified vault sequence and accelerate local alignment",
        6,
        toggleFastVault,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(VaultFeature, "Activation range", 7, 3, 12, function(value: number): ()
        settings.vaultRange = value
    end)
    addNumberOption(VaultFeature, "Vault speed", 5, 1, 10, function(value: number): ()
        settings.vaultSpeed = math.clamp(value, 1, 10)
    end)

    local ActionFeature: any = createUniversalFeature(
        "Cooldown Modifier",
        "Accelerate vault, pallet, break, rescue and interaction action tracks",
        7,
        toggleCooldownModifier,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(ActionFeature, "Action speed", 4, 1, 10, function(value: number): ()
        settings.actionSpeed = math.clamp(value, 1, 10)
    end)

    local DamageFeature: any = createUniversalFeature(
        "Damage Boost",
        "Apply an immediate configurable WalkSpeed burst after losing health",
        8,
        toggleDamageBoost,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(DamageFeature, "Speed boost", 5, 1, 20, function(value: number): ()
        settings.damageBoost = math.max(0, value)
    end)
    addNumberOption(DamageFeature, "Boost duration", 1, 0.1, 4, function(value: number): ()
        settings.damageBoostDuration = math.max(0.05, value)
    end)

    createUniversalFeature(
        "Noclip (Vaults & Pallets)",
        "Disable collision only on vault/window and pallet descendants, never floors or walls",
        9,
        toggleSelectiveNoclip,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    local currentCharacter: Model? = LocalPlayer.Character
    local currentHumanoid: Humanoid? = if currentCharacter
        then currentCharacter:FindFirstChildOfClass("Humanoid")
        else nil
    local defaultWalkSpeed: number = if currentHumanoid then currentHumanoid.WalkSpeed else 16
    settings.walkSpeed = defaultWalkSpeed
    local WalkSpeedFeature: any = createUniversalFeature(
        "WalkSpeed Hack",
        "Maintain a configurable movement speed from the game's current base up to 50",
        10,
        toggleWalkSpeed,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(WalkSpeedFeature, "WalkSpeed", defaultWalkSpeed, 1, 50, function(value: number): ()
        settings.walkSpeed = math.clamp(value, 1, 50)
    end)

    createUniversalFeature(
        "Silent Steps / Anti-Sound",
        "Stop and mute local running, walking, sprint and footstep sounds as they appear",
        11,
        toggleSilentSteps,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    local ProximityFeature: any = createUniversalFeature(
        "Killer Proximity Visualizer",
        "Killer-only widget showing the nearest active Survivor distance",
        12,
        toggleProximity,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(ProximityFeature, "Safe range", 150, 50, 400, function(value: number): ()
        settings.proximityRange = value
    end)
    local function updateProximityFeatureVisibility(): ()
        ProximityFeature.row.Visible = isLocalKiller()
    end
    updateProximityFeatureVisibility()
    featureConnections.VDProximityVisibility = LocalPlayer:GetPropertyChangedSignal("Team"):Connect(
        updateProximityFeatureVisibility
    )

    createUniversalFeature(
        "Line of Sight ESP",
        "Draw a lightweight facing vector from every active-round character",
        13,
        toggleFacingESP,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    local LockerFeature: any = createUniversalFeature(
        "Locker & Hideout Detector",
        "Show a bright through-wall marker and Toast for nearby hidden Survivors",
        14,
        toggleLockerDetector,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(LockerFeature, "Alert range", 45, 10, 150, function(value: number): ()
        settings.lockerRange = value
    end)

    createUniversalFeature(
        "Killer Power Cooldowns",
        "Show replicated Killer power, charge and cooldown attributes",
        15,
        toggleCooldownTracker,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    local FovFeature: any = createUniversalFeature(
        "VD Field of View",
        "Keep a wider camera view while VD replaces camera properties",
        16,
        toggleFov,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(FovFeature, "Field of view", 85, 50, 120, function(value: number): ()
        settings.fov = math.clamp(value, 50, 120)
    end)

    createUniversalFeature(
        "Optimize Blind / Flash Protection",
        "Disable local flashlight, blind and whiteout overlays as soon as they appear",
        17,
        toggleNoBlind,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    createUniversalFeature(
        "VD Fullbright",
        "Remove local darkness, fog and shadows and restore them when disabled",
        18,
        toggleVDFullbright,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    state.cleanupVDRuntime = function(): ()
        disconnectFeatureConnection("VDProximityVisibility")
        toggleGeneratorESP(false)
        toggleAutoGeneratorAura(false)
        toggleAutoParry(false)
        toggleKillerHitAura(false)
        toggleFastVault(false)
        toggleCooldownModifier(false)
        toggleDamageBoost(false)
        toggleSelectiveNoclip(false)
        toggleWalkSpeed(false)
        toggleSilentSteps(false)
        toggleProximity(false)
        toggleFacingESP(false)
        toggleLockerDetector(false)
        toggleCooldownTracker(false)
        toggleFov(false)
        toggleNoBlind(false)
        toggleVDFullbright(false)
        clearFacing()
        clearLockerMarkers()
        restoreSelectiveCollisions()
        if runtime.visualFolder then
            runtime.visualFolder:Destroy()
            runtime.visualFolder = nil
        end
    end
end

function Module.init(runtime: any): any
    assert(type(runtime) == "table", "VD requires a Runtime table")
    assert(type(runtime.Menu) == "table", "VD requires Runtime.Menu")
    assert(runtime.TaskManager ~= nil, "VD requires Runtime.TaskManager")
    if Module.Initialized then
        return Module
    end
    Module.Menu = runtime.Menu
    Module.Runtime = runtime
    buildVDFeatures()
    if type(state.cleanupVDRuntime) == "function" then
        moduleCleanup = state.cleanupVDRuntime
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
