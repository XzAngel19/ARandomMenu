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

local moduleCleanup: () -> () = function(): () end

local function buildVDFeatures(): ()
    local settings: any = {
        generatorDistance = 1800,
        generatorTransparency = 0.82,
        proximityRange = 150,
        proximityScale = 1,
        showFacing = true,
        worldAuras = true,
        survivorAuras = true,
        killerAura = true,
        skillTolerance = 5,
        skillDelayMin = 0.02,
        skillDelayMax = 0.08,
        vaultRange = 7,
        vaultAlignment = 0.35,
        lockerRange = 45,
        fov = 85,
        noBlindStrength = 1,
    }
    local runtime: any = {
        generatorMarkers = {} :: {[Model]: MarkerRecord},
        auraMarkers = {} :: {[Instance]: MarkerRecord},
        survivorMarkers = {} :: {[Player]: MarkerRecord},
        generatorStates = {} :: {[Model]: string},
        lockerAlerts = {} :: {[Player]: number},
        proximityGui = nil :: ScreenGui?,
        cooldownGui = nil :: ScreenGui?,
        visualFolder = nil :: Folder?,
        lastSkillInput = 0,
        lastVaultInput = 0,
        originalFov = nil :: number?,
        lighting = nil :: any,
        effectStates = {} :: {[Instance]: any},
    }

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

    local function getMap(): Instance?
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
            return progress, "REGRESSING", Theme.Danger
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
            if map then
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
            end
            for generator: Model, record: MarkerRecord in pairs(runtime.generatorMarkers) do
                if not generator.Parent then
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
                        record.label.Text = string.format("GENERATOR  %.1f%%\\n%s", progress, status)
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
        label.Text = "KILLER: NO SIGNAL"
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
            local localRoot: BasePart? = getRoot(LocalPlayer.Character)
            local _, killer: Model? = getKiller()
            local killerRoot: BasePart? = getRoot(killer)
            if not localRoot or not killerRoot then
                label.Text = "KILLER: NO SIGNAL"
                label.TextColor3 = Theme.TextMuted
                bar.Size = UDim2.fromScale(0, 1)
                return
            end
            local distance: number = (killerRoot.Position - localRoot.Position).Magnitude
            local color: Color3 = if distance <= 25
                then Theme.Danger
                elseif distance <= 60 then Color3.fromRGB(244, 190, 88)
                else Theme.Success
            label.Text = string.format("KILLER: %.1f STUDS", distance)
            label.TextColor3 = color
            bar.BackgroundColor3 = color
            bar.Size = UDim2.fromScale(1 - math.clamp(distance / settings.proximityRange, 0, 1), 1)
        end)
    end

    local function worldCategory(instance: Instance): (string?, Color3?)
        local name: string = lower(instance.Name)
        if isGenerator(instance) then
            return "GENERATOR", Theme.AccentCyan
        elseif instance:IsA("Model") and contains(name, "pallet") then
            return "PALLET", Color3.fromRGB(244, 190, 88)
        elseif instance:IsA("BasePart") and name == "vaulttrigger" then
            return "VAULT", Theme.AccentViolet
        elseif instance:IsA("Model") and name == "hook" then
            return "HOOK", Theme.Danger
        elseif (instance:IsA("Model") or instance:IsA("BasePart"))
            and (contains(name, "locker") or contains(name, "wardrobe")) then
            return "LOCKER", Theme.Success
        elseif (instance:IsA("Model") or instance:IsA("BasePart"))
            and contains(name, "chest") then
            return "CHEST", Color3.fromRGB(244, 205, 92)
        elseif (instance:IsA("Model") or instance:IsA("BasePart"))
            and (contains(name, "exitgate") or name == "gate") then
            return "EXIT", Color3.fromRGB(110, 235, 180)
        end
        return nil, nil
    end

    local function clearAuraMarkers(): ()
        for target: Instance, record: MarkerRecord in pairs(runtime.auraMarkers) do
            destroyMarker(record)
            runtime.auraMarkers[target] = nil
        end
    end

    local function toggleWorldAuras(enabled: boolean): ()
        disconnectFeatureConnection("VDWorldAuras")
        clearAuraMarkers()
        if not enabled then
            return
        end
        local elapsed: number = 1
        featureConnections.VDWorldAuras = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.8 then
                return
            end
            elapsed = 0
            local map: Instance? = getMap()
            if map then
                for _, descendant: Instance in ipairs(map:GetDescendants()) do
                    local category: string?, color: Color3? = worldCategory(descendant)
                    if category and color and not runtime.auraMarkers[descendant] then
                        local root: BasePart? = if descendant:IsA("Model")
                            then getRoot(descendant)
                            elseif descendant:IsA("BasePart") then descendant
                            else nil
                        if root then
                            runtime.auraMarkers[descendant] = createMarker(
                                descendant,
                                root,
                                color,
                                category,
                                1200
                            )
                        end
                    end
                end
            end
            for target: Instance, record: MarkerRecord in pairs(runtime.auraMarkers) do
                if not target.Parent then
                    destroyMarker(record)
                    runtime.auraMarkers[target] = nil
                end
            end
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
            return "HOOKED", Theme.Danger
        elseif downed then
            return "DOWNED · REC " .. string.format("%.0f%%", recovery or 0), Theme.Danger
        elseif humanoid.Health < humanoid.MaxHealth * 0.75 then
            return "INJURED · " .. string.format("%.0f%%", humanoid.Health / humanoid.MaxHealth * 100), Color3.fromRGB(244, 190, 88)
        end
        return "HEALTHY", Theme.Success
    end

    local function clearSurvivorMarkers(): ()
        for player: Player, record: MarkerRecord in pairs(runtime.survivorMarkers) do
            destroyMarker(record)
            runtime.survivorMarkers[player] = nil
        end
    end

    local function toggleEntityAuras(enabled: boolean): ()
        disconnectFeatureConnection("VDEntityAuras")
        clearSurvivorMarkers()
        if not enabled then
            return
        end
        local elapsed: number = 1
        featureConnections.VDEntityAuras = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.12 then
                return
            end
            elapsed = 0
            local killerPlayer: Player?, killerCharacter: Model? = getKiller()
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local character: Model? = player.Character
                    local root: BasePart? = getRoot(character)
                    local record: MarkerRecord? = runtime.survivorMarkers[player]
                    if character and root then
                        local killer: boolean = player == killerPlayer or character == killerCharacter
                        if (killer and settings.killerAura)
                            or (not killer and settings.survivorAuras) then
                            local status: string
                            local color: Color3
                            if killer then
                                status = "KILLER"
                                color = Theme.Danger
                            else
                                status, color = survivorStatus(player, character)
                            end
                            if not record or record.highlight.Adornee ~= character then
                                destroyMarker(record)
                                record = createMarker(
                                    character,
                                    root,
                                    color,
                                    player.DisplayName .. "\\n" .. status,
                                    2000
                                )
                                runtime.survivorMarkers[player] = record
                            end
                            record.highlight.FillColor = color
                            record.highlight.OutlineColor = color
                            if record.label then
                                record.label.TextColor3 = color
                                record.label.Text = player.DisplayName .. "\\n" .. status
                            end
                        elseif record then
                            destroyMarker(record)
                            runtime.survivorMarkers[player] = nil
                        end
                    elseif record then
                        destroyMarker(record)
                        runtime.survivorMarkers[player] = nil
                    end
                end
            end
        end)
    end

    local function pressSpace(): boolean
        local environment: any = getfenv()
        if type(environment.keypress) == "function"
            and type(environment.keyrelease) == "function" then
            environment.keypress(0x20)
            task.delay(0.035, function(): ()
                environment.keyrelease(0x20)
            end)
            return true
        end
        local ok: boolean, virtualInput: any = pcall(function(): any
            return game:GetService("VirtualInputManager")
        end)
        if ok and virtualInput then
            virtualInput:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            task.delay(0.035, function(): ()
                virtualInput:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
            return true
        end
        return false
    end

    local function angularDistance(first: number, second: number): number
        return math.abs((first - second + 180) % 360 - 180)
    end

    local function findSkillObjects(): (GuiObject?, GuiObject?)
        local needle: GuiObject? = nil
        local zone: GuiObject? = nil
        for _, descendant: Instance in ipairs(PlayerGui:GetDescendants()) do
            if descendant:IsA("GuiObject") and descendant.Visible then
                local name: string = lower(descendant.Name)
                local parentName: string = if descendant.Parent then lower(descendant.Parent.Name) else ""
                local skillRelated: boolean = contains(name, "skill")
                    or contains(parentName, "skill")
                    or contains(parentName, "calibration")
                if skillRelated then
                    if contains(name, "needle")
                        or contains(name, "pointer")
                        or contains(name, "indicator") then
                        needle = descendant
                    elseif contains(name, "great")
                        or contains(name, "perfect")
                        or contains(name, "success") then
                        zone = descendant
                    end
                end
            end
        end
        return needle, zone
    end

    local function toggleAutoGreat(enabled: boolean): ()
        disconnectFeatureConnection("VDAutoGreat")
        if not enabled then
            return
        end
        featureConnections.VDAutoGreat = TaskManager:Connect(function(): ()
            if os.clock() - runtime.lastSkillInput < 0.45 then
                return
            end
            local needle: GuiObject?, zone: GuiObject? = findSkillObjects()
            if not needle or not zone then
                return
            end
            if angularDistance(needle.AbsoluteRotation, zone.AbsoluteRotation)
                <= settings.skillTolerance then
                runtime.lastSkillInput = os.clock()
                local delayTime: number = settings.skillDelayMin
                    + math.random() * math.max(0, settings.skillDelayMax - settings.skillDelayMin)
                task.delay(delayTime, function(): ()
                    if not pressSpace() then
                        notify("VD Auto-Great needs keypress or VirtualInputManager.")
                    end
                end)
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
            local target: Vector3 = Vector3.new(trigger.Position.X, root.Position.Y, trigger.Position.Z)
            local desired: CFrame = CFrame.lookAt(root.Position, target)
            root.CFrame = root.CFrame:Lerp(desired, settings.vaultAlignment)
            if os.clock() - runtime.lastVaultInput > 0.65 then
                runtime.lastVaultInput = os.clock()
                pressSpace()
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
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
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
                            then Theme.Danger else Theme.AccentCyan
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

    local function toggleLockerDetector(enabled: boolean): ()
        disconnectFeatureConnection("VDLockerDetector")
        table.clear(runtime.lockerAlerts)
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
            if not localRoot then
                return
            end
            for _, player: Player in ipairs(Players:GetPlayers()) do
                local character: Model? = player.Character
                local root: BasePart? = getRoot(character)
                if player ~= LocalPlayer and character and root
                    and not isKillerCharacter(character)
                    and isHiding(player, character)
                    and (root.Position - localRoot.Position).Magnitude <= settings.lockerRange then
                    local lastAlert: number = runtime.lockerAlerts[player] or 0
                    if os.clock() - lastAlert > 8 then
                        runtime.lockerAlerts[player] = os.clock()
                        notify(player.DisplayName .. " entered a nearby locker/hideout.")
                    end
                end
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
        label.Text = "KILLER POWER\\nNO DATA"
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
            return "KILLER POWER\\nNO SIGNAL"
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
        return table.concat(lines, "\\n")
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
        local camera: Camera? = workspace.CurrentCamera
        if not enabled then
            if camera and runtime.originalFov then
                camera.FieldOfView = runtime.originalFov
            end
            runtime.originalFov = nil
            return
        end
        runtime.originalFov = if camera then camera.FieldOfView else 70
        featureConnections.VDFOV = TaskManager:Connect(function(): ()
            local current: Camera? = workspace.CurrentCamera
            if current then
                current.FieldOfView = settings.fov
            end
        end)
    end

    local function toggleNoBlind(enabled: boolean): ()
        disconnectFeatureConnection("VDNoBlind")
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
        featureConnections.VDNoBlind = TaskManager:Connect(function(): ()
            for _, root: Instance in ipairs({Lighting, PlayerGui}) do
                for _, descendant: Instance in ipairs(root:GetDescendants()) do
                    local name: string = lower(descendant.Name)
                    if contains(name, "blind") or contains(name, "flash") or contains(name, "stun") then
                        if descendant:IsA("PostEffect") then
                            if runtime.effectStates[descendant] == nil then
                                runtime.effectStates[descendant] = descendant.Enabled
                            end
                            descendant.Enabled = false
                        elseif descendant:IsA("GuiObject") and descendant ~= ScreenGui then
                            if runtime.effectStates[descendant] == nil then
                                runtime.effectStates[descendant] = descendant.Visible
                            end
                            descendant.Visible = false
                        end
                    end
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

    local GeneratorFeature: any = createUniversalFeature(
        "Generator Progress ESP",
        "Show every generator through walls with exact progress and repair/regression state",
        1,
        toggleGeneratorESP,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(GeneratorFeature, "Maximum distance", 1800, 200, 3000, function(value: number): ()
        settings.generatorDistance = value
    end)
    addNumberOption(GeneratorFeature, "Fill transparency", 0.82, 0, 1, function(value: number): ()
        settings.generatorTransparency = math.clamp(value, 0, 1)
    end)
    addInformationOption(
        GeneratorFeature,
        "Reads VD's replicated Progress, PlayersRepairingCount and Regression sound. Notifications report when a survivor touches a regressing generator."
    )

    local ProximityFeature: any = createUniversalFeature(
        "Killer Proximity Visualizer",
        "Display exact killer distance with a color-changing danger meter",
        2,
        toggleProximity,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(ProximityFeature, "Safe range", 150, 50, 400, function(value: number): ()
        settings.proximityRange = value
    end)

    local EntityFeature: any = createUniversalFeature(
        "Entity Aura ESP",
        "Track killer and survivor health, downed recovery and hook state through walls",
        3,
        toggleEntityAuras,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addToggleOption(EntityFeature, "Killer aura", true, function(value: boolean): ()
        settings.killerAura = value
    end)
    addToggleOption(EntityFeature, "Survivor auras", true, function(value: boolean): ()
        settings.survivorAuras = value
    end)

    createUniversalFeature(
        "Line of Sight ESP",
        "Draw a lightweight facing vector from every remote character",
        4,
        toggleFacingESP,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    createUniversalFeature(
        "World Aura ESP",
        "Highlight pallets, vaults, hooks, lockers, chests, gates and generators",
        5,
        toggleWorldAuras,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    local SkillFeature: any = createUniversalFeature(
        "Generator Auto-Great",
        "Press the native skill-check input when VD's visible needle reaches the Great zone",
        6,
        toggleAutoGreat,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(SkillFeature, "Angular tolerance", 5, 1, 18, function(value: number): ()
        settings.skillTolerance = value
    end)
    addNumberOption(SkillFeature, "Minimum delay", 0.02, 0, 0.3, function(value: number): ()
        settings.skillDelayMin = math.max(0, value)
    end)
    addNumberOption(SkillFeature, "Maximum delay", 0.08, 0, 0.5, function(value: number): ()
        settings.skillDelayMax = math.max(settings.skillDelayMin, value)
    end)
    addInformationOption(
        SkillFeature,
        "Uses the normal Space input and never fabricates SkillCheckResultEvent arguments. Delay is randomized between the configured values."
    )

    local VaultFeature: any = createUniversalFeature(
        "Fast Vault Optimizer",
        "Align toward VD VaultTrigger parts and send the native vault input at close range",
        7,
        toggleFastVault,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(VaultFeature, "Activation range", 7, 3, 12, function(value: number): ()
        settings.vaultRange = value
    end)
    addNumberOption(VaultFeature, "Alignment strength", 0.35, 0.05, 1, function(value: number): ()
        settings.vaultAlignment = math.clamp(value, 0.05, 1)
    end)

    local LockerFeature: any = createUniversalFeature(
        "Locker & Hideout Detector",
        "Notify when a replicated survivor hiding state appears nearby",
        8,
        toggleLockerDetector,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(LockerFeature, "Alert range", 45, 10, 150, function(value: number): ()
        settings.lockerRange = value
    end)

    createUniversalFeature(
        "Killer Power Cooldowns",
        "Show replicated killer power, charge and cooldown attributes in a compact widget",
        9,
        toggleCooldownTracker,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    local FovFeature: any = createUniversalFeature(
        "VD Field of View",
        "Keep a wider camera view while VD replaces camera properties",
        10,
        toggleFov,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )
    addNumberOption(FovFeature, "Field of view", 85, 50, 120, function(value: number): ()
        settings.fov = math.clamp(value, 50, 120)
    end)

    createUniversalFeature(
        "No Blind / Flash Protection",
        "Suppress local blind, flashlight and stun overlays without touching server state",
        11,
        toggleNoBlind,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    createUniversalFeature(
        "VD Fullbright",
        "Remove local darkness, fog and shadows and restore them when disabled",
        12,
        toggleVDFullbright,
        {parent = state.vdScroll, registry = state.vdFeatures}
    )

    state.cleanupVDRuntime = function(): ()
        toggleGeneratorESP(false)
        toggleProximity(false)
        toggleWorldAuras(false)
        toggleEntityAuras(false)
        toggleFacingESP(false)
        toggleAutoGreat(false)
        toggleFastVault(false)
        toggleLockerDetector(false)
        toggleCooldownTracker(false)
        toggleFov(false)
        toggleNoBlind(false)
        toggleVDFullbright(false)
        clearFacing()
        clearAuraMarkers()
        clearSurvivorMarkers()
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
