--!strict
local Module = {
    Name = "TRS",
    PlaceId = 14315258385,
    Events = {} :: {[string]: any},
    Initialized = false,
    Menu = nil :: any,
    Runtime = nil :: any,
}

local moduleCleanup: () -> () = function(): () end

local function buildTRSFeatures()
    local settings = {
        tackleRange = 8,
        tackleLead = 0.12,
        tackleAimlock = true,
        tackleBox = true,
        opponentsOnly = true,
        dribbleRange = 10,
        dribblePrediction = 0.18,
        dribblePreempt = true,
        dribbleStyle = "Normal",
        power = false,
        powerValue = 1,
        shootKey = Enum.KeyCode.G,
        powerShotKey = Enum.KeyCode.T,
        longShotKey = Enum.KeyCode.R,
        shootGoalRange = 120,
        powerShotRange = 120,
        shootTargetHeight = 4,
        goalVisualRange = 100,
        goalVisualSize = 2.5,
        goalVisualCurve = 5,
        goalVisualLine = true,
        pickupMode = "Automatic",
        pickupKey = Enum.KeyCode.H,
        pickupReach = 18,
        pickupMaxHeight = 12,
        pickupReportedDistance = 2.8,
        pickupDelay = 0.1,
        pickupDeke = true,
        passMode = "Manual",
        passKey = Enum.KeyCode.V,
        passRange = 150,
        passPressureRange = 9,
        passForwardOnly = true,
        trajectoryTime = 2.4,
        goalkeeperRange = 32,
        goalkeeperMinSpeed = 8,
        goalkeeperHighBall = 5,
        headerRange = 7,
        headerGoalRange = 50,
    }
    local tackleBox = nil
    local dribbleBox = nil
    local lastTackle = 0
    local lastDribble = 0
    local lastPass = 0
    local lastPickup = 0
    local lastShot = 0
    local nativeShotContext = nil
    local nativeHeaderContext = nil
    local shotHookInstalled = false
    local originalNamecall = nil
    local shotHookWrapper = nil
    local pickupRemote = nil
    local trajectoryParts = {}
    local landingMarker = nil
    local lastGoalkeeperAction = 0
    local lastHeaderAction = 0
    local autoTackleEnabled = false
    local autoPickupEnabled = false
    local goalVisualObjects = {}

    local function getWorldBools()
        return workspace:FindFirstChild("Bools")
    end

    local function boolEnabled(folder, name)
        local value = folder and folder:FindFirstChild(name)
        return value and value.Value == true
    end

    local function isLocalGoalkeeper(worldBools)
        local apg = worldBools and worldBools:FindFirstChild("APG")
        local hpg = worldBools and worldBools:FindFirstChild("HPG")
        return (apg and apg.Value == LocalPlayer)
            or (hpg and hpg.Value == LocalPlayer)
    end

    local function getOpponentGoal()
        if LocalPlayer.TeamColor == BrickColor.new(23) then
            return workspace:FindFirstChild("HomeGoalDetector")
        end
        if LocalPlayer.TeamColor == BrickColor.new(141) then
            return workspace:FindFirstChild("AwayGoalDetector")
        end
        return nil
    end

    local function getOwnGoal()
        if LocalPlayer.TeamColor == BrickColor.new(23) then
            return workspace:FindFirstChild("AwayGoalDetector")
        end
        if LocalPlayer.TeamColor == BrickColor.new(141) then
            return workspace:FindFirstChild("HomeGoalDetector")
        end
        return nil
    end

    local function localActionBlocked(character, checkDribble)
        local localBools = character and character:FindFirstChild("Bools")
        local worldBools = getWorldBools()
        if not localBools
            or boolEnabled(localBools, "Tackled")
            or boolEnabled(localBools, "Tackling")
            or boolEnabled(localBools, "Debounce")
            or boolEnabled(localBools, "iframe")
            or boolEnabled(worldBools, "Penalty")
            or boolEnabled(worldBools, "Kickoff")
            or boolEnabled(worldBools, "FreeKick") then
            return true
        end
        if checkDribble
            and (boolEnabled(localBools, "dribbleDebounce")
                or boolEnabled(localBools, "dribbleDelay")) then
            return true
        end
        return false
    end

    local function getBall()
        local ball = workspace:FindFirstChild("ball")
        if ball and ball:IsA("BasePart") then
            return ball
        end
        return nil
    end

    local function getBallOwner()
        local ball = getBall()
        local creator = ball and ball:FindFirstChild("creator")
        if ball
            and ball:FindFirstChild("playerWeld")
            and creator
            and creator:IsA("ObjectValue")
            and creator.Value
            and creator.Value:IsA("Player") then
            return creator.Value, ball
        end
        return nil, ball
    end

    local function clearTackleBox()
        if tackleBox then
            tackleBox:Destroy()
            tackleBox = nil
        end
    end

    local function showTackleTarget(player)
        if not settings.tackleBox then
            clearTackleBox()
            return
        end
        local root = player
            and player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then
            clearTackleBox()
            return
        end
        if not tackleBox then
            tackleBox = Instance.new("BoxHandleAdornment")
            tackleBox.Name = "RTM_TRS_BallCarrier"
            tackleBox.AlwaysOnTop = true
            tackleBox.ZIndex = 20
            tackleBox.Size = Vector3.new(4.5, 6, 2.5)
            tackleBox.Color3 = Color3.fromRGB(35, 150, 125)
            tackleBox.Transparency = 0.45
            tackleBox.Parent = ScreenGui
        end
        tackleBox.Adornee = root
    end

    local function clearDribbleBox()
        if dribbleBox then
            dribbleBox:Destroy()
            dribbleBox = nil
        end
    end

    local function showDribbleThreat(player)
        local root = player
            and player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then
            clearDribbleBox()
            return
        end
        if not dribbleBox then
            dribbleBox = Instance.new("BoxHandleAdornment")
            dribbleBox.Name = "RTM_TRS_DribbleThreat"
            dribbleBox.AlwaysOnTop = true
            dribbleBox.ZIndex = 21
            dribbleBox.Size = Vector3.new(4.5, 6, 2.5)
            dribbleBox.Color3 = Color3.fromRGB(215, 125, 35)
            dribbleBox.Transparency = 0.35
            dribbleBox.Parent = ScreenGui
        end
        dribbleBox.Adornee = root
    end

    local function validCarrier(owner)
        if not owner
            or owner == LocalPlayer
            or Module.Runtime.Services.protectedTargets.isProtected(owner)
            or not owner.Character then
            return false
        end
        if settings.opponentsOnly and owner.TeamColor == LocalPlayer.TeamColor then
            return false
        end
        local humanoid = owner.Character:FindFirstChildOfClass("Humanoid")
        return humanoid ~= nil and humanoid.Health > 0
    end

    local function findDribbleThreat(root, rangeOverride, predictionOverride)
        local triggerRange = rangeOverride or settings.dribbleRange
        local usePrediction = predictionOverride
        if usePrediction == nil then
            usePrediction = settings.dribblePreempt
        end
        local bestPlayer = nil
        local bestDistance = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local targetRoot = character
                and character:FindFirstChild("HumanoidRootPart")
            local targetHumanoid = character
                and character:FindFirstChildOfClass("Humanoid")
            if player ~= LocalPlayer
                and player.TeamColor ~= LocalPlayer.TeamColor
                and targetRoot
                and targetHumanoid
                and targetHumanoid.Health > 0 then
                local offset = root.Position - targetRoot.Position
                local distance = offset.Magnitude
                if distance <= triggerRange + 4 and distance > 0.05 then
                    local targetBools = character:FindFirstChild("Bools")
                    local tackling = boolEnabled(targetBools, "Tackling")
                        or boolEnabled(targetBools, "TackleDebounce")
                    local relativeVelocity = targetRoot.AssemblyLinearVelocity
                        - root.AssemblyLinearVelocity
                    local closingSpeed = -offset.Unit:Dot(relativeVelocity)
                    local futureOffset = offset
                        - relativeVelocity * settings.dribblePrediction
                    local predictedDistance = futureOffset.Magnitude
                    local facing = targetRoot.CFrame.LookVector:Dot(offset.Unit) > 0.05
                    local imminent = usePrediction
                        and facing
                        and closingSpeed > 2
                        and predictedDistance <= triggerRange
                    if (tackling or imminent)
                        and distance < bestDistance then
                        bestPlayer = player
                        bestDistance = distance
                    end
                end
            end
        end
        return bestPlayer, bestDistance
    end

    local function pointToSegmentDistance(point, startPoint, endPoint)
        local segment = endPoint - startPoint
        local lengthSquared = segment:Dot(segment)
        if lengthSquared <= 0.001 then
            return (point - startPoint).Magnitude
        end
        local alpha = math.clamp(
            (point - startPoint):Dot(segment) / lengthSquared,
            0,
            1
        )
        return (point - (startPoint + segment * alpha)).Magnitude
    end

    local function getBestPassTarget(root)
        local opponentGoal = getOpponentGoal()
        local worldBools = getWorldBools()
        local apg = worldBools and worldBools:FindFirstChild("APG")
        local hpg = worldBools and worldBools:FindFirstChild("HPG")
        local currentGoalDistance = opponentGoal
            and (root.Position - opponentGoal.Position).Magnitude
            or 0
        local bestPlayer = nil
        local bestScore = -math.huge

        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local targetRoot = character
                and character:FindFirstChild("HumanoidRootPart")
            local targetHumanoid = character
                and character:FindFirstChildOfClass("Humanoid")
            if player ~= LocalPlayer
                and player.TeamColor == LocalPlayer.TeamColor
                and (not apg or apg.Value ~= player)
                and (not hpg or hpg.Value ~= player)
                and targetRoot
                and targetHumanoid
                and targetHumanoid.Health > 0 then
                local distance = (targetRoot.Position - root.Position).Magnitude
                local targetGoalDistance = opponentGoal
                    and (targetRoot.Position - opponentGoal.Position).Magnitude
                    or currentGoalDistance
                local progress = currentGoalDistance - targetGoalDistance
                if distance <= settings.passRange
                    and (not settings.passForwardOnly or progress > 1) then
                    local blockers = 0
                    for _, opponent in ipairs(Players:GetPlayers()) do
                        local opponentRoot = opponent.Character
                            and opponent.Character:FindFirstChild("HumanoidRootPart")
                        if opponent.TeamColor ~= LocalPlayer.TeamColor
                            and opponentRoot
                            and pointToSegmentDistance(
                                opponentRoot.Position,
                                root.Position,
                                targetRoot.Position
                            ) < 4.5 then
                            blockers = blockers + 1
                        end
                    end
                    local score = progress - distance * 0.08 - blockers * 18
                    if score > bestScore then
                        bestScore = score
                        bestPlayer = player
                    end
                end
            end
        end
        return bestPlayer
    end

    local function getGoalCandidates(goal, targetHeight)
        if not goal or not goal:IsA("BasePart") then
            return {}
        end

        local modelName = goal.Name == "HomeGoalDetector"
            and "HomeGoal"
            or "AwayGoal"
        local goalModel = workspace:FindFirstChild(modelName)
        local targets = goalModel and goalModel:FindFirstChild("Targets")
        local positions = {}
        if targets then
            for _, target in ipairs(targets:GetChildren()) do
                if target:IsA("BasePart") then
                    table.insert(positions, target.Position)
                end
            end
        end

        local center = goal.Position + Vector3.new(0, targetHeight, 0)
        if #positions < 3 then
            positions = {
                center - goal.CFrame.RightVector * 5,
                center,
                center + goal.CFrame.RightVector * 5,
            }
        else
            table.sort(positions, function(a, b)
                return (a - goal.Position):Dot(goal.CFrame.RightVector)
                    < (b - goal.Position):Dot(goal.CFrame.RightVector)
            end)
            positions = {
                positions[1],
                positions[math.ceil(#positions / 2)],
                positions[#positions],
            }
        end
        return positions
    end

    local function goalPathBlocked(startPosition, targetPosition, character, goal)
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local excluded = {}
        if character then
            table.insert(excluded, character)
        end
        local ball = getBall()
        if ball then
            table.insert(excluded, ball)
        end
        local goalModel = workspace:FindFirstChild(
            goal.Name == "HomeGoalDetector" and "HomeGoal" or "AwayGoal"
        )
        if goalModel then
            table.insert(excluded, goalModel)
        end
        rayParams.FilterDescendantsInstances = excluded
        rayParams.IgnoreWater = true
        local result = workspace:Raycast(
            startPosition,
            targetPosition - startPosition,
            rayParams
        )
        return result ~= nil
            and (result.Position - targetPosition).Magnitude > 4
    end

    local function selectGoalTarget(goal, startPosition, targetHeight, character)
        local candidates = getGoalCandidates(goal, targetHeight)
        if #candidates == 0 then
            return nil, candidates, {}
        end

        local modelName = goal.Name == "HomeGoalDetector"
            and "HomeGoal"
            or "AwayGoal"
        local worldBools = getWorldBools()
        local goalkeeperValue = worldBools
            and worldBools:FindFirstChild(
                modelName == "HomeGoal" and "HPG" or "APG"
            )
        local goalkeeper = goalkeeperValue and goalkeeperValue.Value
        local goalkeeperRoot = goalkeeper
            and goalkeeper.Character
            and goalkeeper.Character:FindFirstChild("HumanoidRootPart")
        local blocked = {}
        local bestPosition = candidates[2] or candidates[1]
        local bestScore = -math.huge
        for index, position in ipairs(candidates) do
            blocked[index] = goalPathBlocked(
                startPosition,
                position,
                character,
                goal
            )
            local separation = goalkeeperRoot
                and (position - goalkeeperRoot.Position).Magnitude
                or 8
            local score = separation - (blocked[index] and 1000 or 0)
            if index == 2 then
                score = score + 0.25
            end
            if score > bestScore then
                bestScore = score
                bestPosition = position
            end
        end
        return bestPosition, candidates, blocked
    end

    local function toggleAutoTackle(enabled)
        autoTackleEnabled = enabled
        disconnectFeatureConnection("TRSAutoTackle")
        clearTackleBox()
        if not enabled then
            return
        end

        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local action = remotes and remotes:FindFirstChild("Action")
        local disarm = remotes and remotes:FindFirstChild("SoftDisPlayer")
        featureConnections.TRSAutoTackle = TaskManager:Connect(function()
            local owner, ball = getBallOwner()
            local character, humanoid, root = getCharacterParts()
            local targetRoot = validCarrier(owner)
                and owner.Character:FindFirstChild("HumanoidRootPart")
            if not ball
                or not character
                or not humanoid
                or not root
                or not targetRoot then
                clearTackleBox()
                return
            end

            local predictedTarget = targetRoot.Position
                + targetRoot.AssemblyLinearVelocity * settings.tackleLead
            local offset = predictedTarget - root.Position
            local distance = offset.Magnitude
            if distance > settings.tackleRange then
                clearTackleBox()
                return
            end
            showTackleTarget(owner)

            if settings.tackleAimlock and distance > 0.1 then
                root.CFrame = CFrame.lookAt(
                    root.Position,
                    Vector3.new(predictedTarget.X, root.Position.Y, predictedTarget.Z)
                )
            end
            if os.clock() - lastTackle < 0.85 then
                return
            end

            local bools = character:FindFirstChild("Bools")
            if localActionBlocked(character, false)
                or boolEnabled(bools, "TackleDebounce")
                or not action
                or not action:IsA("RemoteEvent") then
                return
            end

            lastTackle = os.clock()
            action:FireServer("TackIe")
            local velocity = Instance.new("BodyVelocity")
            velocity.Name = "RTM_TRS_TackleVelocity"
            velocity.MaxForce = Vector3.new(50000000, 0, 50000000)
            velocity.Velocity = (
                distance > 0.1 and offset.Unit or root.CFrame.LookVector
            ) * 42
            velocity.Parent = root
            game:GetService("Debris"):AddItem(velocity, 0.32)

            if disarm and disarm:IsA("RemoteEvent") then
                for _, delayTime in ipairs({0.06, 0.16}) do
                    task.delay(delayTime, function()
                        if not autoTackleEnabled then
                            return
                        end
                        local currentOwner, currentBall = getBallOwner()
                        if currentOwner == owner
                            and currentBall
                            and (targetRoot.Position - root.Position).Magnitude
                                <= settings.tackleRange + 2 then
                            disarm:FireServer(
                                owner,
                                (root.Position - currentBall.Position).Magnitude,
                                false,
                                currentBall.Size
                            )
                        end
                    end)
                end
            end
        end)
    end

    local function toggleAutoDribble(enabled)
        disconnectFeatureConnection("TRSAutoDribble")
        clearDribbleBox()
        if not enabled then
            return
        end

        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local action = remotes and remotes:FindFirstChild("Action")
        local passRemote = remotes and remotes:FindFirstChild("Pass")
        featureConnections.TRSAutoDribble = TaskManager:Connect(function()
            local owner, ball = getBallOwner()
            local character, humanoid, root = getCharacterParts()
            if owner ~= LocalPlayer
                or not character
                or not humanoid
                or not root
                or not action
                or not action:IsA("RemoteEvent")
                or os.clock() - lastDribble < 0.52
                or localActionBlocked(character, true)
                or isLocalGoalkeeper(getWorldBools()) then
                clearDribbleBox()
                return
            end

            local threat = findDribbleThreat(root)
            if not threat then
                clearDribbleBox()
                return
            end
            showDribbleThreat(threat)
            lastDribble = os.clock()
            if settings.dribbleStyle == "Assist" then
                local teammate = getBestPassTarget(root)
                if teammate and passRemote and passRemote:IsA("RemoteEvent") then
                    passRemote:FireServer(teammate, ball.CFrame)
                end
            else
                action:FireServer("Deke")
            end
        end)
    end

    local uninstallShotHook: () -> () = function(): () end

    local function installShotHook()
        if shotHookInstalled then
            return true
        end
        if type(hookmetamethod) ~= "function"
            or type(getnamecallmethod) ~= "function" then
            return false
        end

        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local shoot = remotes
            and (remotes:FindFirstChild("ShootTheBaII")
                or remotes:FindFirstChild("ShootTheBall"))
        if not shoot then
            return false
        end
        local predecessor = nil
        local callback = function(self, ...)
            local method = getnamecallmethod()
            if self == shoot and method == "FireServer" then
                local arguments = {...}
                local context = nativeShotContext or nativeHeaderContext
                local ball = getBall()
                if context and ball and context.target then
                    local offset = context.target - ball.Position
                    if offset.Magnitude > 0.1 then
                        local direction = offset.Unit
                        local magnitude = typeof(arguments[4]) == "Vector3"
                            and arguments[4].Magnitude
                            or 1
                        arguments[1] = direction
                        arguments[4] = direction * math.max(magnitude, 1)
                        arguments[7] = context.curve
                        arguments[10] = context.side
                        if context.kind == "Power" or context.kind == "Long" then
                            arguments[3] = math.max(
                                tonumber(arguments[3]) or 0,
                                1
                            )
                            arguments[9] = true
                        end
                    end
                    if context == nativeShotContext then
                        nativeShotContext = nil
                    else
                        nativeHeaderContext = nil
                    end
                elseif settings.power and getBallOwner() == LocalPlayer then
                    arguments[3] = settings.powerValue
                end
                return predecessor(self, unpack(arguments))
            end
            return predecessor(self, ...)
        end
        if type(newcclosure) == "function" then
            callback = newcclosure(callback)
        end
        shotHookWrapper = callback
        predecessor = hookmetamethod(game, "__namecall", callback)
        originalNamecall = predecessor
        shotHookInstalled = originalNamecall ~= nil
        return shotHookInstalled
    end

    uninstallShotHook = function(): ()
        local restored: boolean = not shotHookInstalled
        if shotHookInstalled
            and originalNamecall
            and type(hookmetamethod) == "function" then
            local hookSucceeded, displaced = pcall(
                hookmetamethod,
                game,
                "__namecall",
                originalNamecall
            )
            restored = hookSucceeded and displaced == shotHookWrapper
            if hookSucceeded and not restored and type(displaced) == "function" then
                pcall(hookmetamethod, game, "__namecall", displaced)
            end
        end
        if restored then
            shotHookInstalled = false
            originalNamecall = nil
            shotHookWrapper = nil
        end
    end

    local function releaseShotHookIfIdle(): ()
        if not settings.power
            and nativeShotContext == nil
            and nativeHeaderContext == nil then
            uninstallShotHook()
        end
    end

    local function toggleMaxPower(enabled)
        settings.power = enabled
        if enabled and not installShotHook() then
            settings.power = false
            error("This executor does not support the local ShootTheBall hook.")
        elseif not enabled then
            releaseShotHookIfIdle()
        end
    end

    local function getMobileButton(name)
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local mobile = playerGui and playerGui:FindFirstChild("MobileCTRL")
        local frame = mobile and mobile:FindFirstChild("TouchControlFrame")
        local jumpButton = frame and frame:FindFirstChild("JumpButton")
        if name == "JumpButton" then
            return jumpButton
        end
        return jumpButton and jumpButton:FindFirstChild(name)
    end

    local function fireNativeSignal(signal)
        if not signal then
            return false
        end
        if type(firesignal) == "function" then
            firesignal(signal)
            return true
        end
        if type(getconnections) == "function" then
            local fired = false
            for _, connection in ipairs(getconnections(signal)) do
                if connection.Fire then
                    connection:Fire()
                    fired = true
                elseif connection.Function then
                    task.spawn(connection.Function)
                    fired = true
                end
            end
            return fired
        end
        return false
    end

    local function fireGoalShot(kind, showFailure)
        local owner, ball = getBallOwner()
        local character, humanoid, root = getCharacterParts()
        local goal = getOpponentGoal()
        if owner ~= LocalPlayer
            or not ball
            or not character
            or not humanoid
            or not root
            or not goal
            or localActionBlocked(character, false)
            or isLocalGoalkeeper(getWorldBools())
            or os.clock() - lastShot < 0.18 then
            return false
        end

        local goalDistance = (root.Position - goal.Position).Magnitude
        local maximumRange = kind == "Normal"
            and settings.shootGoalRange
            or kind == "Power" and settings.powerShotRange
            or math.huge
        if goalDistance > maximumRange then
            if showFailure then
                notify(
                    kind == "Normal"
                        and "Shoot Assist: move closer to the opponent goal."
                        or "Power Shot: move closer to the opponent goal."
                )
            end
            return false
        end
        local powerDebounce = LocalPlayer:FindFirstChild("PowerShootDebounce")
        if kind ~= "Normal" and powerDebounce and powerDebounce.Value then
            if showFailure then
                notify(kind .. " Shot: power shot is still on cooldown.")
            end
            return false
        end

        local grabTick = character:FindFirstChild("GrabTick")
        if grabTick
            and tonumber(grabTick.Value)
            and tick() - grabTick.Value <= 0.35 then
            return false
        end

        local targetPosition = selectGoalTarget(
            goal,
            ball.Position,
            settings.shootTargetHeight,
            character
        )
        local direction = targetPosition and (targetPosition - ball.Position)
        if not direction or direction.Magnitude <= 0.1 then
            return false
        end

        local localTarget = goal.CFrame:PointToObjectSpace(targetPosition)
        local side = localTarget.X >= 0 and "Right" or "Left"
        local curve = side
        local bools = character:FindFirstChild("Bools")
        local curveValue = bools and bools:FindFirstChild("Curve")
        if curveValue then
            curveValue.Value = curve
        end

        if not installShotHook() then
            if showFailure then
                notify("Native shot redirect requires hookmetamethod.")
            end
            return false
        end
        local button = kind == "Normal"
            and getMobileButton("JumpButton")
            or getMobileButton("PowerShoot")
        if not button then
            if showFailure then
                notify("TRS MobileCTRL shot button was not found.")
            end
            return false
        end

        nativeHeaderContext = nil
        nativeShotContext = {
            target = targetPosition,
            curve = curve,
            side = side,
            kind = kind,
        }
        lastShot = os.clock()
        local fired = false
        if kind == "Normal" then
            fired = fireNativeSignal(button.MouseButton1Down)
            if fired then
                task.delay(0.62, function()
                    if button.Parent then
                        fireNativeSignal(button.MouseButton1Up)
                    end
                end)
            end
        else
            fired = fireNativeSignal(button.MouseButton1Click)
        end
        if not fired then
            nativeShotContext = nil
            if showFailure then
                notify("The executor cannot fire native GUI signals.")
            end
            return false
        end
        local context = nativeShotContext
        task.delay(2, function()
            if nativeShotContext == context then
                nativeShotContext = nil
            end
        end)
        return true
    end

    local function connectShotKey(connectionName, keySetting, kind)
        disconnectFeatureConnection(connectionName)
        featureConnections[connectionName] = UserInputService.InputBegan:Connect(
            function(input, processed)
                if processed
                    or state.keyCaptureCallback
                    or state.waitingForKey
                    or UserInputService:GetFocusedTextBox() then
                    return
                end
                if input.UserInputType == Enum.UserInputType.Keyboard
                    and input.KeyCode == settings[keySetting] then
                    fireGoalShot(kind, true)
                end
            end
        )
    end

    local function toggleShootAssist(enabled)
        disconnectFeatureConnection("TRSShootKey")
        if enabled then
            connectShotKey("TRSShootKey", "shootKey", "Normal")
        else
            nativeShotContext = nil
            releaseShotHookIfIdle()
        end
    end

    local function togglePowerShot(enabled)
        disconnectFeatureConnection("TRSPowerShotKey")
        if enabled then
            connectShotKey("TRSPowerShotKey", "powerShotKey", "Power")
        else
            nativeShotContext = nil
            releaseShotHookIfIdle()
        end
    end

    local function toggleLongShot(enabled)
        disconnectFeatureConnection("TRSLongShotKey")
        if enabled then
            connectShotKey("TRSLongShotKey", "longShotKey", "Long")
        else
            nativeShotContext = nil
            releaseShotHookIfIdle()
        end
    end

    local function clearGoalVisual()
        if goalVisualObjects.folder then
            goalVisualObjects.folder:Destroy()
        end
        goalVisualObjects = {}
    end

    local function createGoalVisual()
        if goalVisualObjects.folder and goalVisualObjects.folder.Parent then
            return
        end

        local folder = Instance.new("Folder")
        folder.Name = "RTM_TRS_GoalVisual"
        folder.Parent = workspace
        local origin = Instance.new("Part")
        origin.Name = "RTM_TRS_GoalVisualOrigin"
        origin.Anchored = true
        origin.CanCollide = false
        origin.CanQuery = false
        origin.CanTouch = false
        origin.Transparency = 1
        origin.Size = Vector3.one * 0.1
        origin.Parent = folder

        local originAttachment = Instance.new("Attachment")
        originAttachment.Parent = origin
        local markers = {}
        local attachments = {}
        local billboards = {}
        local labels = {}
        for index = 1, 3 do
            local marker = Instance.new("Part")
            marker.Name = "RTM_TRS_GoalEntry" .. index
            marker.Anchored = true
            marker.CanCollide = false
            marker.CanQuery = false
            marker.CanTouch = false
            marker.CastShadow = false
            marker.Shape = Enum.PartType.Ball
            marker.Material = Enum.Material.Neon
            marker.Transparency = 1
            marker.Parent = folder
            local attachment = Instance.new("Attachment")
            attachment.Parent = marker
            local billboard = Instance.new("BillboardGui")
            billboard.Adornee = marker
            billboard.AlwaysOnTop = true
            billboard.Enabled = false
            billboard.Size = UDim2.fromOffset(100, 28)
            billboard.StudsOffset = Vector3.new(0, 2.1, 0)
            billboard.Parent = marker
            local label = Instance.new("TextLabel")
            label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            label.BackgroundTransparency = 0.2
            label.BorderSizePixel = 0
            label.Font = Enum.Font.GothamBold
            label.Size = UDim2.fromScale(1, 1)
            label.TextColor3 = Color3.new(1, 1, 1)
            label.TextSize = 11
            label.Parent = billboard
            markers[index] = marker
            attachments[index] = attachment
            billboards[index] = billboard
            labels[index] = label
        end

        local beam = Instance.new("Beam")
        beam.Name = "RTM_TRS_GoalAimLine"
        beam.Attachment0 = originAttachment
        beam.Attachment1 = attachments[2]
        beam.FaceCamera = true
        beam.Segments = 24
        beam.Width0 = 0.09
        beam.Width1 = 0.05
        beam.Transparency = NumberSequence.new(0.16)
        beam.Parent = origin

        goalVisualObjects.folder = folder
        goalVisualObjects.origin = origin
        goalVisualObjects.markers = markers
        goalVisualObjects.attachments = attachments
        goalVisualObjects.billboards = billboards
        goalVisualObjects.labels = labels
        goalVisualObjects.beam = beam
    end

    local function hideGoalVisual()
        for _, marker in ipairs(goalVisualObjects.markers or {}) do
            marker.Transparency = 1
        end
        if goalVisualObjects.beam then
            goalVisualObjects.beam.Enabled = false
        end
        for _, billboard in ipairs(goalVisualObjects.billboards or {}) do
            billboard.Enabled = false
        end
    end

    local function toggleGoalTargetVisual(enabled)
        disconnectFeatureConnection("TRSGoalTargetVisual")
        clearGoalVisual()
        if not enabled then
            return
        end

        createGoalVisual()
        local elapsed = 1
        featureConnections.TRSGoalTargetVisual = TaskManager:Connect(
            function(deltaTime)
                elapsed = elapsed + deltaTime
                if elapsed < 0.06 then
                    return
                end
                elapsed = 0

                local owner, ball = getBallOwner()
                local character, _, root = getCharacterParts()
                local goal = getOpponentGoal()
                if owner ~= LocalPlayer
                    or not ball
                    or not root
                    or not goal
                    or (root.Position - goal.Position).Magnitude
                        > settings.goalVisualRange then
                    hideGoalVisual()
                    return
                end

                local targetPosition, candidates, blocked = selectGoalTarget(
                    goal,
                    ball.Position,
                    settings.shootTargetHeight,
                    character
                )
                if not targetPosition then
                    hideGoalVisual()
                    return
                end

                local goalDistance = (root.Position - goal.Position).Magnitude

                goalVisualObjects.origin.Position = ball.Position
                local bestIndex = 1
                for index, position in ipairs(candidates) do
                    local isBest = (position - targetPosition).Magnitude < 0.1
                    if isBest then
                        bestIndex = index
                    end
                    local marker = goalVisualObjects.markers[index]
                    local billboard = goalVisualObjects.billboards[index]
                    local label = goalVisualObjects.labels[index]
                    local color = blocked[index]
                        and Color3.fromRGB(190, 55, 55)
                        or isBest and Color3.fromRGB(45, 190, 95)
                        or Color3.fromRGB(225, 175, 35)
                    marker.Position = position
                    marker.Size = Vector3.one * settings.goalVisualSize
                    marker.Color = color
                    marker.Transparency = isBest and 0.15 or 0.42
                    billboard.Enabled = true
                    label.Text = blocked[index] and "BLOCKED"
                        or isBest and "BEST"
                        or index == 1 and "LEFT"
                        or index == 2 and "CENTER"
                        or "RIGHT"
                    label.TextColor3 = color
                end
                goalVisualObjects.beam.Attachment1 =
                    goalVisualObjects.attachments[bestIndex]
                goalVisualObjects.beam.Enabled = settings.goalVisualLine
                goalVisualObjects.beam.Color = ColorSequence.new(
                    goalDistance <= settings.shootGoalRange
                        and Color3.fromRGB(45, 190, 95)
                        or Color3.fromRGB(225, 175, 35)
                )
                goalVisualObjects.beam.CurveSize0 = settings.goalVisualCurve
                goalVisualObjects.beam.CurveSize1 = -settings.goalVisualCurve
            end
        )
    end

    local function performAssistedPass(showFailure)
        local owner, ball = getBallOwner()
        local character, humanoid, root = getCharacterParts()
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local passRemote = remotes and remotes:FindFirstChild("Pass")
        if owner ~= LocalPlayer
            or not ball
            or not character
            or not humanoid
            or not root
            or localActionBlocked(character, false)
            or isLocalGoalkeeper(getWorldBools())
            or not passRemote
            or not passRemote:IsA("RemoteEvent")
            or os.clock() - lastPass < 0.7 then
            return false
        end

        local grabTick = character:FindFirstChild("GrabTick")
        if grabTick
            and tonumber(grabTick.Value)
            and tick() - grabTick.Value <= 0.35 then
            return false
        end

        local target = getBestPassTarget(root)
        if not target then
            if showFailure then
                notify("Pass Assist: no safe teammate was found.")
            end
            return false
        end

        lastPass = os.clock()
        passRemote:FireServer(target, ball.CFrame)
        return true
    end

    local function togglePassAssist(enabled)
        disconnectFeatureConnection("TRSPassKey")
        disconnectFeatureConnection("TRSPassPressure")
        if not enabled then
            return
        end

        featureConnections.TRSPassKey = UserInputService.InputBegan:Connect(
            function(input, processed)
                if processed
                    or state.keyCaptureCallback
                    or state.waitingForKey
                    or UserInputService:GetFocusedTextBox() then
                    return
                end
                if input.UserInputType == Enum.UserInputType.Keyboard
                    and input.KeyCode == settings.passKey then
                    performAssistedPass(true)
                end
            end
        )

        local elapsed = 1
        featureConnections.TRSPassPressure = TaskManager:Connect(
            function(deltaTime)
                if settings.passMode ~= "Under pressure" then
                    return
                end
                elapsed = elapsed + deltaTime
                if elapsed < 0.08 then
                    return
                end
                elapsed = 0

                local owner = getBallOwner()
                local _, _, root = getCharacterParts()
                if owner ~= LocalPlayer or not root then
                    return
                end
                local threat, distance = findDribbleThreat(
                    root,
                    settings.passPressureRange,
                    true
                )
                if threat and distance <= settings.passPressureRange then
                    performAssistedPass(false)
                end
            end
        )
    end

    local function getPickupRemote()
        if pickupRemote and pickupRemote.Parent then
            return pickupRemote
        end
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        if not remotes then
            return nil
        end
        for _, remote in ipairs(remotes:GetChildren()) do
            if remote:IsA("RemoteEvent")
                and remote:GetAttribute("Attribute") ~= nil then
                pickupRemote = remote
            end
        end
        return pickupRemote
    end

    local function performAutoPickup(showFailure)
        local ball = getBall()
        local character, humanoid, root = getCharacterParts()
        local worldBools = getWorldBools()
        local remote = getPickupRemote()
        if not ball
            or ball:FindFirstChild("playerWeld")
            or not character
            or not humanoid
            or humanoid.Health <= 0
            or not root
            or isLocalGoalkeeper(worldBools)
            or boolEnabled(worldBools, "cantGrab")
            or boolEnabled(worldBools, "Penalty")
            or localActionBlocked(character, false)
            or not remote
            or os.clock() - lastPickup < settings.pickupDelay then
            return false
        end

        local offset = ball.Position - root.Position
        local distance = offset.Magnitude
        if distance > settings.pickupReach
            or offset.Y > settings.pickupMaxHeight then
            if showFailure then
                notify("Auto Pickup: the ball is outside the configured reach or height.")
            end
            return false
        end

        lastPickup = os.clock()
        local grabTick = character:FindFirstChild("GrabTick")
        if grabTick and grabTick:IsA("NumberValue") then
            grabTick.Value = tick()
        end
        remote:FireServer(
            math.min(distance, settings.pickupReportedDistance)
        )

        if settings.pickupDeke then
            task.delay(0.06, function()
                if not autoPickupEnabled then
                    return
                end
                local owner = getBallOwner()
                local currentCharacter = LocalPlayer.Character
                local localBools = currentCharacter
                    and currentCharacter:FindFirstChild("Bools")
                local remotes = game:GetService("ReplicatedStorage")
                    :FindFirstChild("Remotes")
                local action = remotes and remotes:FindFirstChild("Action")
                if owner == LocalPlayer
                    and not boolEnabled(localBools, "dribbleDebounce")
                    and action
                    and action:IsA("RemoteEvent") then
                    action:FireServer("Deke")
                end
            end)
        end
        return true
    end

    local function toggleAutoPickup(enabled)
        autoPickupEnabled = enabled
        disconnectFeatureConnection("TRSPickupKey")
        disconnectFeatureConnection("TRSPickupLoop")
        if not enabled then
            return
        end

        featureConnections.TRSPickupKey = UserInputService.InputBegan:Connect(
            function(input, processed)
                if processed
                    or state.keyCaptureCallback
                    or state.waitingForKey
                    or UserInputService:GetFocusedTextBox() then
                    return
                end
                if input.UserInputType == Enum.UserInputType.Keyboard
                    and input.KeyCode == settings.pickupKey then
                    performAutoPickup(true)
                end
            end
        )

        local elapsed = 1
        featureConnections.TRSPickupLoop = TaskManager:Connect(
            function(deltaTime)
                if settings.pickupMode ~= "Automatic" then
                    return
                end
                elapsed = elapsed + deltaTime
                if elapsed >= 0.05 then
                    elapsed = 0
                    performAutoPickup(false)
                end
            end
        )
    end

    local function clearTrajectory()
        for _, part in ipairs(trajectoryParts) do
            if part then
                part:Destroy()
            end
        end
        trajectoryParts = {}
        if landingMarker then
            landingMarker:Destroy()
            landingMarker = nil
        end
    end

    local function getTrajectoryPart(index)
        if trajectoryParts[index] then
            return trajectoryParts[index]
        end
        local part = Instance.new("Part")
        part.Name = "RTM_TRS_Trajectory"
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(35, 190, 155)
        part.Transparency = 0.2
        part.Size = Vector3.new(0.08, 0.08, 1)
        part.Parent = workspace
        trajectoryParts[index] = part
        return part
    end

    local function toggleTrajectory(enabled)
        disconnectFeatureConnection("TRSTrajectory")
        clearTrajectory()
        if not enabled then
            return
        end

        local elapsed = 1
        featureConnections.TRSTrajectory = TaskManager:Connect(
            function(deltaTime)
                elapsed = elapsed + deltaTime
                if elapsed < 0.08 then
                    return
                end
                elapsed = 0

                local ball = getBall()
                if not ball then
                    for _, part in ipairs(trajectoryParts) do
                        part.Transparency = 1
                    end
                    if landingMarker then
                        landingMarker.Transparency = 1
                    end
                    return
                end

                local velocity = ball.AssemblyLinearVelocity
                local position = ball.Position
                local gravity = Vector3.new(0, -workspace.Gravity, 0)
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Exclude
                local excluded = {ball}
                if LocalPlayer.Character then
                    table.insert(excluded, LocalPlayer.Character)
                end
                rayParams.FilterDescendantsInstances = excluded
                rayParams.IgnoreWater = true

                local steps = 20
                local stepTime = settings.trajectoryTime / steps
                local hitPosition = nil
                local used = 0
                for index = 1, steps do
                    local timeValue = index * stepTime
                    local nextPosition = ball.Position
                        + velocity * timeValue
                        + gravity * (0.5 * timeValue * timeValue)
                    local result = workspace:Raycast(
                        position,
                        nextPosition - position,
                        rayParams
                    )
                    if result then
                        nextPosition = result.Position
                        hitPosition = result.Position
                    end

                    local segment = getTrajectoryPart(index)
                    local distance = (nextPosition - position).Magnitude
                    segment.Transparency = 0.2
                    segment.Size = Vector3.new(0.08, 0.08, math.max(distance, 0.05))
                    segment.CFrame = CFrame.lookAt(
                        (position + nextPosition) / 2,
                        nextPosition
                    )
                    used = index
                    position = nextPosition
                    if result then
                        break
                    end
                end
                for index = used + 1, #trajectoryParts do
                    trajectoryParts[index].Transparency = 1
                end

                if not landingMarker then
                    landingMarker = Instance.new("Part")
                    landingMarker.Name = "RTM_TRS_LandingPoint"
                    landingMarker.Anchored = true
                    landingMarker.CanCollide = false
                    landingMarker.CanQuery = false
                    landingMarker.CanTouch = false
                    landingMarker.CastShadow = false
                    landingMarker.Shape = Enum.PartType.Cylinder
                    landingMarker.Material = Enum.Material.Neon
                    landingMarker.Color = Color3.fromRGB(235, 185, 40)
                    landingMarker.Size = Vector3.new(0.12, 3, 3)
                    landingMarker.Parent = workspace
                end
                landingMarker.Transparency = hitPosition and 0.35 or 1
                if hitPosition then
                    landingMarker.CFrame = CFrame.new(hitPosition + Vector3.new(0, 0.08, 0))
                        * CFrame.Angles(0, 0, math.rad(90))
                end
            end
        )
    end

    local function toggleGoalkeeperAssist(enabled)
        disconnectFeatureConnection("TRSGoalkeeper")
        if not enabled then
            return
        end

        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local action = remotes and remotes:FindFirstChild("Action")
        featureConnections.TRSGoalkeeper = TaskManager:Connect(function()
            local ball = getBall()
            local character, humanoid, root = getCharacterParts()
            local worldBools = getWorldBools()
            local ownGoal = getOwnGoal()
            if not isLocalGoalkeeper(worldBools)
                or not ball
                or not character
                or not humanoid
                or not root
                or not ownGoal
                or not action
                or not action:IsA("RemoteEvent")
                or getBallOwner() == LocalPlayer
                or os.clock() - lastGoalkeeperAction < 1.1 then
                return
            end

            local distance = (ball.Position - root.Position).Magnitude
            local velocity = ball.AssemblyLinearVelocity
            local speed = velocity.Magnitude
            if distance > settings.goalkeeperRange
                or speed < settings.goalkeeperMinSpeed
                or (root.Position - ball.Position):Dot(velocity) <= 0
                or (ownGoal.Position - ball.Position):Dot(velocity) <= 0 then
                return
            end

            local travelTime = math.clamp(distance / speed, 0.05, 0.65)
            local predicted = ball.Position
                + velocity * travelTime
                + Vector3.new(
                    0,
                    -0.5 * workspace.Gravity * travelTime * travelTime,
                    0
                )
            local localPoint = root.CFrame:PointToObjectSpace(predicted)
            if math.abs(localPoint.X) > 13
                or localPoint.Y < -2
                or localPoint.Y > 11 then
                return
            end
            lastGoalkeeperAction = os.clock()
            if localPoint.Y >= settings.goalkeeperHighBall
                and math.abs(localPoint.X) < 4 then
                action:FireServer("GKJump")
            elseif localPoint.X > 2 then
                action:FireServer("RightDive", root.CFrame)
            elseif localPoint.X < -2 then
                action:FireServer("LeftDive", root.CFrame)
            else
                action:FireServer("FrontDive")
            end
        end)
    end

    local function toggleAutoHeader(enabled)
        disconnectFeatureConnection("TRSAutoHeader")
        if not enabled then
            nativeHeaderContext = nil
            releaseShotHookIfIdle()
            return
        end

        featureConnections.TRSAutoHeader = TaskManager:Connect(function()
            local owner, ball = getBallOwner()
            local character, humanoid, root = getCharacterParts()
            local worldBools = getWorldBools()
            local opponentGoal = getOpponentGoal()
            local ownGoal = getOwnGoal()
            if not ball
                or owner == LocalPlayer
                or not character
                or not humanoid
                or not root
                or not opponentGoal
                or not ownGoal
                or isLocalGoalkeeper(worldBools)
                or os.clock() - lastHeaderAction < 1.1
                or localActionBlocked(character, false) then
                return
            end

            local distance = (ball.Position - root.Position).Magnitude
            local relativeHeight = ball.Position.Y - root.Position.Y
            local attacking = (root.Position - opponentGoal.Position).Magnitude
                <= settings.headerGoalRange
            local defending = (root.Position - ownGoal.Position).Magnitude
                <= settings.headerGoalRange
            if distance > settings.headerRange
                or relativeHeight < 1.2
                or relativeHeight > 9
                or (not attacking and not defending) then
                return
            end

            local targetPosition = nil
            if defending then
                local teammate = getBestPassTarget(root)
                local teammateRoot = teammate
                    and teammate.Character
                    and teammate.Character:FindFirstChild("HumanoidRootPart")
                if teammateRoot then
                    targetPosition = teammateRoot.Position
                        + teammateRoot.AssemblyLinearVelocity * 0.15
                end
            else
                targetPosition = selectGoalTarget(
                    opponentGoal,
                    ball.Position,
                    settings.shootTargetHeight,
                    character
                )
            end
            if not targetPosition or not installShotHook() then
                return
            end

            local localPoint = root.CFrame:PointToObjectSpace(targetPosition)
            local side = localPoint.X >= 0 and "Right" or "Left"
            nativeShotContext = nil
            nativeHeaderContext = {
                target = targetPosition,
                curve = side,
                side = side,
                kind = "Header",
            }
            local button = getMobileButton("Header")
            if not button or not fireNativeSignal(button.MouseButton1Click) then
                nativeHeaderContext = nil
                return
            end
            lastHeaderAction = os.clock()
            local context = nativeHeaderContext
            task.delay(2, function()
                if nativeHeaderContext == context then
                    nativeHeaderContext = nil
                end
            end)
        end)
    end

    local TackleFeature = createUniversalFeature(
        "Auto Tackle",
        "Track only the ball carrier, face them, tackle, and retry the steal",
        1,
        toggleAutoTackle,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(TackleFeature, "Reach", 8, 3, 16, function(value)
        settings.tackleRange = value
    end)
    addNumberOption(TackleFeature, "Movement prediction", 0.12, 0, 0.3, function(value)
        settings.tackleLead = value
    end)
    addToggleOption(TackleFeature, "Aimlock", true, function(value)
        settings.tackleAimlock = value
    end)
    addToggleOption(TackleFeature, "Show carrier", true, function(value)
        settings.tackleBox = value
        if not value then
            clearTackleBox()
        end
    end)
    addToggleOption(TackleFeature, "Opponents only", true, function(value)
        settings.opponentsOnly = value
    end)

    local DribbleFeature = createUniversalFeature(
        "Auto Dribble",
        "React to real tackles and predict fast incoming tackle attempts",
        2,
        toggleAutoDribble,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(DribbleFeature, "Reaction reach", 10, 4, 16, function(value)
        settings.dribbleRange = value
    end)
    addNumberOption(DribbleFeature, "Prediction time", 0.18, 0, 0.35, function(value)
        settings.dribblePrediction = value
    end)
    addToggleOption(DribbleFeature, "Predict incoming tackles", true, function(value)
        settings.dribblePreempt = value
    end)
    addCycleOption(
        DribbleFeature,
        "Style",
        {"Normal", "Assist"},
        1,
        function(value)
            settings.dribbleStyle = value
        end
    )
    addInformationOption(
        DribbleFeature,
        "Normal uses the original Deke. Assist passes to a safe teammate. Orange box = incoming tackle."
    )

    local PickupFeature = createUniversalFeature(
        "Auto Pickup",
        "Grab nearby loose balls through the game's own pickup remote",
        3,
        toggleAutoPickup,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addCycleOption(
        PickupFeature,
        "Mode",
        {"Automatic", "Manual"},
        1,
        function(value)
            settings.pickupMode = value
        end
    )
    addKeyOption(PickupFeature, "Pickup key", settings.pickupKey, function(value)
        settings.pickupKey = value
    end)
    addNumberOption(PickupFeature, "Pickup reach", 18, 3, 180, function(value)
        settings.pickupReach = value
    end)
    addNumberOption(PickupFeature, "Maximum ball height", 12, 2, 50, function(value)
        settings.pickupMaxHeight = value
    end)
    addNumberOption(PickupFeature, "Reported distance", 2.8, 0.5, 10, function(value)
        settings.pickupReportedDistance = value
    end)
    addNumberOption(PickupFeature, "Fire delay", 0.1, 0.05, 0.5, function(value)
        settings.pickupDelay = value
    end)
    addToggleOption(PickupFeature, "Deke after pickup", true, function(value)
        settings.pickupDeke = value
    end)
    addInformationOption(
        PickupFeature,
        "The pickup remote is found by its instance attribute, not by name — no "
            .. "capture ever named it. If a match does nothing, that identification "
            .. "is the first thing to check."
    )

    local PassFeature = createUniversalFeature(
        "Pass Assist",
        "Choose a safe forward teammate manually or when a tackle is incoming",
        4,
        togglePassAssist,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addCycleOption(
        PassFeature,
        "Mode",
        {"Manual", "Under pressure"},
        1,
        function(value)
            settings.passMode = value
        end
    )
    addKeyOption(PassFeature, "Pass key", settings.passKey, function(value)
        settings.passKey = value
    end)
    addNumberOption(PassFeature, "Maximum pass range", 150, 30, 190, function(value)
        settings.passRange = value
    end)
    addNumberOption(PassFeature, "Pressure reach", 9, 4, 15, function(value)
        settings.passPressureRange = value
    end)
    addToggleOption(PassFeature, "Forward teammates only", true, function(value)
        settings.passForwardOnly = value
    end)
    addToggleOption(PassFeature, "Maximum power", false, toggleMaxPower)
    addNumberOption(PassFeature, "Maximum power value", 1, 0.85, 1, function(value)
        settings.powerValue = value
    end)
    addInformationOption(
        PassFeature,
        "Pass range: 30-190. Pressure: 4-15. Maximum power affects your normal shots."
    )

    local ShootFeature = createUniversalFeature(
        "Shoot Assist",
        "Use TRS's native mobile shot and redirect only its target and curve",
        5,
        toggleShootAssist,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addKeyOption(ShootFeature, "Shot key", settings.shootKey, function(value)
        settings.shootKey = value
    end)
    addNumberOption(ShootFeature, "Goal range", 120, 60, 180, function(value)
        settings.shootGoalRange = value
    end)
    addInformationOption(
        ShootFeature,
        "Range: 60-180 studs. Key: G. Native charge/release; only aim and curve are changed."
    )

    local PowerShotFeature = createUniversalFeature(
        "Power Shot",
        "Full-power curved shot from a practical attacking distance",
        6,
        togglePowerShot,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addKeyOption(PowerShotFeature, "Power shot key", settings.powerShotKey, function(value)
        settings.powerShotKey = value
    end)
    addNumberOption(PowerShotFeature, "Goal range", 120, 50, 180, function(value)
        settings.powerShotRange = value
    end)
    addInformationOption(
        PowerShotFeature,
        "Range: 50-180 studs. Key: T. Activates TRS's native mobile PowerShoot button."
    )

    local LongShotFeature = createUniversalFeature(
        "Large Shoot",
        "Activate the native mobile PowerShoot and redirect it from any distance",
        7,
        toggleLongShot,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addKeyOption(LongShotFeature, "Long shot key", settings.longShotKey, function(value)
        settings.longShotKey = value
    end)
    addInformationOption(
        LongShotFeature,
        "Key: R. No artificial bar check; the native PowerShoot callback controls the shot."
    )

    local GoalVisualFeature = createUniversalFeature(
        "Best Goal Visual",
        "Show left, center, and right entries; prefer the clearest side away from the keeper",
        8,
        toggleGoalTargetVisual,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(GoalVisualFeature, "Display range", 100, 25, 180, function(value)
        settings.goalVisualRange = value
    end)
    addNumberOption(GoalVisualFeature, "Target margin size", 2.5, 0.5, 6, function(value)
        settings.goalVisualSize = value
    end)
    addNumberOption(GoalVisualFeature, "Visual curve", 5, -20, 20, function(value)
        settings.goalVisualCurve = value
    end)
    addToggleOption(GoalVisualFeature, "Show aim line", true, function(value)
        settings.goalVisualLine = value
    end)
    addInformationOption(
        GoalVisualFeature,
        "Green means the keeper cannot reach that entry; red means blocked."
    )

    local TrajectoryFeature = createUniversalFeature(
        "Ball Trajectory",
        "Show the predicted flight path and first landing point",
        9,
        toggleTrajectory,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(TrajectoryFeature, "Prediction time", 2.4, 0.8, 4, function(value)
        settings.trajectoryTime = value
    end)

    local GoalkeeperFeature = createUniversalFeature(
        "Goalkeeper Assist",
        "Predict shots toward your own goal and choose Dive, FrontDive, or GKJump",
        10,
        toggleGoalkeeperAssist,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(GoalkeeperFeature, "Assist range", 32, 12, 45, function(value)
        settings.goalkeeperRange = value
    end)
    addNumberOption(GoalkeeperFeature, "Minimum ball speed", 8, 4, 30, function(value)
        settings.goalkeeperMinSpeed = value
    end)
    addNumberOption(GoalkeeperFeature, "High ball height", 5, 3, 9, function(value)
        settings.goalkeeperHighBall = value
    end)

    local HeaderFeature = createUniversalFeature(
        "Auto Header",
        "Use the native mobile Header; near your own goal redirect it to a teammate",
        11,
        toggleAutoHeader,
        {
            parent = state.trsScroll,
            registry = state.trsFeatures,
        }
    )
    addNumberOption(HeaderFeature, "Ball reach", 7, 3, 10, function(value)
        settings.headerRange = value
    end)
    addNumberOption(HeaderFeature, "Goal activation range", 50, 25, 60, function(value)
        settings.headerGoalRange = value
    end)
    addInformationOption(
        HeaderFeature,
        "Ball reach: 3-10. Goal zone: 25-60. PassBV remains controlled by the native button."
    )

    state.cleanupTRSRuntime = function()
        settings.power = false
        autoTackleEnabled = false
        autoPickupEnabled = false
        nativeShotContext = nil
        nativeHeaderContext = nil
        uninstallShotHook()
        disconnectFeatureConnection("TRSAutoTackle")
        disconnectFeatureConnection("TRSAutoDribble")
        disconnectFeatureConnection("TRSPickupKey")
        disconnectFeatureConnection("TRSPickupLoop")
        disconnectFeatureConnection("TRSPassKey")
        disconnectFeatureConnection("TRSPassPressure")
        disconnectFeatureConnection("TRSShootKey")
        disconnectFeatureConnection("TRSPowerShotKey")
        disconnectFeatureConnection("TRSLongShotKey")
        disconnectFeatureConnection("TRSTrajectory")
        disconnectFeatureConnection("TRSGoalTargetVisual")
        disconnectFeatureConnection("TRSGoalkeeper")
        disconnectFeatureConnection("TRSAutoHeader")
        clearTackleBox()
        clearDribbleBox()
        clearTrajectory()
        clearGoalVisual()
    end
end

function Module.init(runtime: any): any
    assert(type(runtime) == "table", "TRS requires a Runtime table")
    assert(type(runtime.Menu) == "table", "TRS requires Runtime.Menu")
    assert(runtime.TaskManager ~= nil, "TRS requires Runtime.TaskManager")
    if Module.Initialized then
        return Module
    end

    Module.Menu = runtime.Menu
    Module.Runtime = runtime
    buildTRSFeatures()
    if type(state.cleanupTRSRuntime) == "function" then
        moduleCleanup = state.cleanupTRSRuntime
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
