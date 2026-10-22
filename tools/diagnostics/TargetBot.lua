--[[
    WURST TARGET BOT v4  (diagnostic, standalone -- for YOUR OWN alt)

    Built from the v3 live results:
      - Humanoid:Move is ignored here; Humanoid:MoveTo works.
      - v3 crashed into walls (it had no eyes), ignored its
        distance setting outside orbit, and could lock onto one
        heading forever when MoveTo pushed it into geometry.
      - v3 jumped with Humanoid.Jump, which this controller does
        not honour either; v4 jumps with ChangeState(Jumping).

    v4 therefore has:
      * EYES: raycast probes ahead (and a floor probe) score a fan
        of candidate headings every step; the MoveTo point follows
        the best-scoring clear heading, so walls and ledges bend
        the path instead of eating it.
      * ANTI-STUCK: real displacement is measured; a body that is
        told to move but does not travel jumps, reverses toward the
        clearest heading, and if it happens twice, forces a new
        behaviour. It cannot grind one wall forever.
      * REAL DISTANCE: every behaviour composes its direction from
        a tangential dodge + a radial correction toward the ring
        distance set in the menu (Cerca/Media/Lejos) around the
        rival, not just the orbit behaviour.
      * A RIVAL PICKER: "Rival: Auto" (nearest) or a named player,
        so another passer-by cannot steal the reference.
      * IMPOSIBLE difficulty: besides the steering chaos, it adds
        velocity dash bursts and a flight behaviour (LinearVelocity
        hover with PlatformStand) for a few seconds at a time.
        Those patterns are NOT what real players do -- they exist
        as a stress test; ShootProbe data from them should be read
        as such.

    Menu: Activo, Modo (Realista/Dificil/Caotico/Imposible),
    Saltos, Distancia, Velocidad, Rival, Reanclar, Detener.
    Inject once to start; inject again (or the red button) to
    remove bot, menu and every physics object it created.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local genv = getgenv()
if genv.WURST_TARGET_BOT and genv.WURST_TARGET_BOT.active then
    local old = genv.WURST_TARGET_BOT
    if old.cleanup then
        pcall(old.cleanup)
    else
        old.active = false
        if old.gui then pcall(function() old.gui:Destroy() end) end
    end
    print("[TargetBot] removed")
    return
end

local SETTINGS = {
    running = true,
    difficulty = "Dificil",
    jumps = "Normal",
    distance = "Media",
    speed = "Normal",
    opponent = "Auto",
}
local DIFFICULTY = {
    Realista = {turn = 240, flipMin = 1.0, flipMax = 1.7,
        jumpMin = 2.8, jumpMax = 4.5, dashMin = 0, dashMax = 0},
    Dificil = {turn = 360, flipMin = 0.65, flipMax = 1.1,
        jumpMin = 1.4, jumpMax = 2.6, dashMin = 3.5, dashMax = 6},
    Caotico = {turn = 540, flipMin = 0.38, flipMax = 0.72,
        jumpMin = 0.65, jumpMax = 1.3, dashMin = 1.6, dashMax = 3.2},
    Imposible = {turn = 760, flipMin = 0.22, flipMax = 0.5,
        jumpMin = 0.35, jumpMax = 0.8, dashMin = 0.8, dashMax = 1.8},
}
local JUMP_MULT = {Sin = 0, Normal = 1, Frecuentes = 0.55}
local DISTANCE = {Cerca = 14, Media = 24, Lejos = 36}
local SPEEDS = {Normal = 16, Rapida = 22, Extrema = 30}

local state = {
    active = true,
    heading = math.random() * math.pi * 2,
    targetHeading = 0,
    behavior = "strafe",
    behaviorLabel = "Strafe lateral",
    jumpQueued = false,
    nextJumpAt = os.clock() + 2,
    jumpAttempts = 0,
    jumpsDone = 0,
    jumpCheckAt = nil,
    nextDashAt = os.clock() + 4,
    flying = false,
    flightUntil = 0,
    flightBaseY = 0,
    flightAttachment = nil,
    flightVelocity = nil,
    standUntil = 0,
    forceBehaviorSwitch = false,
    recoveryUntil = 0,
    recoveryHeading = 0,
    lastMoveTo = 0,
    gui = nil,
    cleanup = nil,
}
state.targetHeading = state.heading
genv.WURST_TARGET_BOT = state

local function characterParts()
    local character = LocalPlayer.Character
    if not character then return nil, nil, nil end
    return character,
        character:FindFirstChildOfClass("Humanoid"),
        character:FindFirstChild("HumanoidRootPart")
end

local _, humanoid0, root0 = characterParts()
if not humanoid0 or not root0 then
    print("[TargetBot] character not ready -- inject again in game")
    state.active = false
    return
end
local originalWalkSpeed = humanoid0.WalkSpeed
local anchor = root0.Position

local function getOpponent()
    if SETTINGS.opponent ~= "Auto" then
        local named = Players:FindFirstChild(SETTINGS.opponent)
        if named and named ~= LocalPlayer and named.Character then
            local root =
                named.Character:FindFirstChild("HumanoidRootPart")
            if root then return named, root end
        end
    end
    local myRoot = select(3, characterParts())
    if not myRoot then return nil, nil end
    local best, bestRoot, bestDistance = nil, nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local root =
                player.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local distance =
                    (root.Position - myRoot.Position).Magnitude
                if distance < bestDistance then
                    best, bestRoot, bestDistance = player, root, distance
                end
            end
        end
    end
    return best, bestRoot
end

local function wrapAngle(angle)
    while angle > math.pi do angle -= math.pi * 2 end
    while angle < -math.pi do angle += math.pi * 2 end
    return angle
end
local function wrapHeading()
    state.heading = wrapAngle(state.heading)
    state.targetHeading = wrapAngle(state.targetHeading)
end
local function headingVector(heading)
    return Vector3.new(math.sin(heading), 0, math.cos(heading))
end
local function randomBetween(a, b)
    return a + math.random() * (b - a)
end

--------------------------------------------------------------------------
-- Flight (Imposible only). Everything it instances is named and
-- removed by setFlight(false) / cleanup.
--------------------------------------------------------------------------
local function setFlight(enabled, humNow, rootNow)
    if enabled then
        if not rootNow or not humNow then return end
        if not state.flightAttachment
            or not state.flightAttachment.Parent then
            state.flightAttachment = Instance.new("Attachment")
            state.flightAttachment.Name = "TargetBotFlightAttachment"
            state.flightAttachment.Parent = rootNow
        end
        if not state.flightVelocity
            or not state.flightVelocity.Parent then
            state.flightVelocity = Instance.new("LinearVelocity")
            state.flightVelocity.Name = "TargetBotFlightVelocity"
            state.flightVelocity.Attachment0 = state.flightAttachment
            state.flightVelocity.RelativeTo =
                Enum.ActuatorRelativeTo.World
            state.flightVelocity.VelocityConstraintMode =
                Enum.VelocityConstraintMode.Vector
            state.flightVelocity.MaxForce = 100000
            state.flightVelocity.Parent = rootNow
        end
        humNow.PlatformStand = true
        state.flying = true
    else
        if state.flightVelocity then
            pcall(function() state.flightVelocity:Destroy() end)
            state.flightVelocity = nil
        end
        if state.flightAttachment then
            pcall(function() state.flightAttachment:Destroy() end)
            state.flightAttachment = nil
        end
        if humNow then
            pcall(function() humNow.PlatformStand = false end)
        end
        state.flying = false
    end
end

--------------------------------------------------------------------------
-- Eyes: score a fan of candidate headings by wall clearance and
-- floor presence, preferring the one closest to the wanted heading.
--------------------------------------------------------------------------
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function refreshRaycastFilter(characterNow)
    local filter = {}
    if characterNow then table.insert(filter, characterNow) end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(filter, player.Character)
        end
    end
    raycastParams.FilterDescendantsInstances = filter
end

local function probeClearance(rootNow, heading, probeLength)
    local direction = headingVector(heading)
    local origin = rootNow.Position + Vector3.new(0, 2, 0)
    local hit = workspace:Raycast(
        origin, direction * probeLength, raycastParams)
    return hit and hit.Distance or probeLength
end

local function hasFloor(rootNow, heading)
    local ahead = rootNow.Position
        + headingVector(heading) * 5 + Vector3.new(0, 3, 0)
    local hit = workspace:Raycast(
        ahead, Vector3.new(0, -10, 0), raycastParams)
    return hit ~= nil
end

local function chooseMovementHeading(rootNow, characterNow)
    if os.clock() < state.recoveryUntil then
        return state.recoveryHeading
    end
    refreshRaycastFilter(characterNow)
    local probeLength = 9
    local offsets = {0, 0.45, -0.45, 0.9, -0.9, 1.5, -1.5, 2.4, -2.4, math.pi}
    local bestHeading, bestScore = state.heading, -math.huge
    for _, offset in ipairs(offsets) do
        local candidate = state.heading + offset
        local clearance = probeClearance(rootNow, candidate, probeLength)
        local score = clearance - math.abs(offset) * 2.2
        if clearance <= 1.6 then score -= 25 end
        if not state.flying and not hasFloor(rootNow, candidate) then
            score -= 7
        end
        if score > bestScore then
            bestScore, bestHeading = score, candidate
        end
    end
    return bestHeading
end

--------------------------------------------------------------------------
-- Brain: target heading from behaviour + rival-relative geometry.
--------------------------------------------------------------------------
local BEHAVIOR_LABELS = {
    strafe = "Strafe lateral", orbit = "Orbitando",
    zigzagIn = "Zigzag hacia ti", zigzagOut = "Zigzag alejandose",
    rush = "Rusheando", wander = "Deambulando",
    stopGo = "Paradas y arranques", fly = "VOLANDO",
    airChaos = "Caos aereo",
}

task.spawn(function()
    local behaviorUntil = 0
    local flipAt = 0
    local side = 1
    local index = 0
    local stopStanding = false
    local stopSwitchAt = 0
    while state.active do
        task.wait(0.08)
        local _, humNow, rootNow = characterParts()
        local now = os.clock()
        if not SETTINGS.running or not humNow
            or humNow.Health <= 0 or not rootNow then
            state.targetHeading = state.heading
            state.flying = false
        else
            local diff = DIFFICULTY[SETTINGS.difficulty]
            if now >= behaviorUntil or state.forceBehaviorSwitch then
                state.forceBehaviorSwitch = false
                local pool = {"strafe", "orbit", "zigzagIn",
                    "zigzagOut", "rush", "wander", "stopGo", "strafe"}
                if SETTINGS.difficulty == "Imposible" then
                    pool = {"strafe", "fly", "zigzagIn", "airChaos",
                        "orbit", "rush", "strafe", "fly"}
                end
                index = index % #pool + 1
                state.behavior = pool[index]
                state.behaviorLabel =
                    BEHAVIOR_LABELS[state.behavior] or state.behavior
                behaviorUntil = now + randomBetween(7, 12)
                flipAt = now
                if state.behavior == "fly" then
                    state.flightBaseY = rootNow.Position.Y + 9
                    state.flightUntil = behaviorUntil
                elseif state.behavior == "stopGo" then
                    state.standUntil = now + randomBetween(0.4, 0.9)
                end
                print("[TargetBot] behavior: " .. state.behavior)
            end
            state.flying = state.behavior == "fly"
                and now < state.flightUntil

            local oppPlayer, oppRoot = getOpponent()
            local behavior = state.behavior
            if behavior == "stopGo" then
                if now >= stopSwitchAt then
                    stopStanding = not stopStanding
                    stopSwitchAt = now + (stopStanding
                        and randomBetween(0.35, 0.85)
                        or randomBetween(0.8, 1.7))
                    state.standUntil = stopStanding
                        and stopSwitchAt or 0
                end
                if stopStanding then
                    state.targetHeading = state.heading
                end
            end
            if behavior == "stopGo" and now < state.standUntil then
                state.targetHeading = state.heading
            elseif oppRoot then
                local away = rootNow.Position - oppRoot.Position
                local flat = Vector3.new(away.X, 0, away.Z)
                local dist = flat.Magnitude
                local awayUnit = dist > 0.01
                    and flat.Unit or headingVector(state.heading)
                local towardUnit = -awayUnit
                local tangent = Vector3.new(
                    awayUnit.Z, 0, -awayUnit.X)
                local desired = DISTANCE[SETTINGS.distance]
                -- +1 = too far (close in), -1 = too close (back off)
                local radial = math.clamp((dist - desired) / 10, -1, 1)

                local tangentWeight, radialWeight = 1, 0.75
                if behavior == "zigzagIn" then
                    radial = math.max(radial, 0.8)
                    tangentWeight = 0.9
                elseif behavior == "zigzagOut" then
                    radial = math.min(radial, -0.8)
                    tangentWeight = 0.9
                elseif behavior == "rush" then
                    radial = 1
                    tangentWeight = 0.25
                elseif behavior == "orbit" then
                    radialWeight = 1.3
                elseif behavior == "wander" then
                    tangentWeight = 0.4
                    radialWeight = 0.3
                end
                if behavior == "strafe" or behavior == "zigzagIn"
                    or behavior == "zigzagOut"
                    or behavior == "orbit" then
                    if now >= flipAt then
                        side = -side
                        flipAt = now + randomBetween(
                            diff.flipMin, diff.flipMax)
                        if behavior == "orbit"
                            and math.random() > 0.3 then
                            side = -side -- orbit mostly holds its side
                        end
                    end
                end
                local move = tangent * (side * tangentWeight)
                    + towardUnit * (radial * radialWeight)
                if behavior == "wander" and now >= flipAt then
                    flipAt = now + randomBetween(0.4, 0.9)
                    state.targetHeading = state.heading
                        + math.rad(math.random(-70, 70))
                elseif move.Magnitude > 0.05 then
                    state.targetHeading =
                        math.atan2(move.X, move.Z)
                end
            else
                -- No rival visible: smooth wander around the anchor.
                if now >= flipAt then
                    flipAt = now + randomBetween(0.5, 1.0)
                    state.targetHeading = state.heading
                        + math.rad(math.random(-80, 80))
                end
            end

            -- Anchor leash overrides everything but flight.
            if not state.flying then
                local flat = Vector3.new(
                    rootNow.Position.X - anchor.X, 0,
                    rootNow.Position.Z - anchor.Z)
                if flat.Magnitude > 55 then
                    state.targetHeading = math.atan2(-flat.X, -flat.Z)
                    state.behaviorLabel = "Volviendo al ancla"
                elseif behavior ~= "stopGo" or now >= state.standUntil then
                    state.behaviorLabel =
                        BEHAVIOR_LABELS[behavior] or behavior
                end
            end

            -- Jump schedule (independent of behaviours, so it
            -- cannot silently starve like v3's flip-tied jumps).
            local jumpMult = JUMP_MULT[SETTINGS.jumps]
            if jumpMult > 0 and not state.flying
                and now >= state.nextJumpAt then
                state.jumpQueued = true
                local interval = randomBetween(
                    diff.jumpMin, diff.jumpMax) * jumpMult
                state.nextJumpAt = now + interval
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Steering + actuation pump.
--------------------------------------------------------------------------
local pumpConnection
local progressPos, progressAt, stuckCount = root0.Position, os.clock(), 0

local function queueJump()
    state.jumpQueued = true
end

pumpConnection = RunService.Heartbeat:Connect(function(dt)
    if not state.active then return end
    local characterNow, humNow, rootNow = characterParts()
    if not humNow or not rootNow then return end
    if humNow.Health <= 0 then
        setFlight(false, humNow, rootNow)
        return
    end
    if not SETTINGS.running then
        setFlight(false, humNow, rootNow)
        humNow:MoveTo(rootNow.Position)
        return
    end

    local now = os.clock()
    local diff = DIFFICULTY[SETTINGS.difficulty]

    -- WalkSpeed from the menu (the game may reset it; re-assert).
    if not state.flying then
        local wanted = SPEEDS[SETTINGS.speed]
        if wanted and math.abs(humNow.WalkSpeed - wanted) > 0.5 then
            humNow.WalkSpeed = wanted
        end
    end

    -- Turn the logical heading toward the target at the capped rate.
    wrapHeading()
    local delta = wrapAngle(state.targetHeading - state.heading)
    local step = math.rad(diff.turn) * math.max(dt, 1 / 240)
    state.heading = state.heading + math.clamp(delta, -step, step)
    wrapHeading()

    state.flying = state.flying
        and SETTINGS.difficulty == "Imposible"

    if state.flying then
        if not state.flightVelocity
            or not state.flightVelocity.Parent then
            setFlight(true, humNow, rootNow)
            state.flightBaseY = rootNow.Position.Y + 9
        end
        local dir = headingVector(state.heading)
        local cruise = (SPEEDS[SETTINGS.speed] or 16) * 1.7
        local targetY = state.flightBaseY
            + math.sin(now * 1.7) * 1.6
        local vy = math.clamp((targetY - rootNow.Position.Y) * 3.5,
            -20, 20)
        state.flightVelocity.VectorVelocity = Vector3.new(
            dir.X * cruise, vy, dir.Z * cruise)
        humNow:MoveTo(rootNow.Position) -- keep MoveDirection quiet
    else
        if state.flightVelocity or state.flightAttachment then
            setFlight(false, humNow, rootNow)
        end
        local standing = now < state.standUntil
        if standing then
            humNow:MoveTo(rootNow.Position)
        else
            if now - state.lastMoveTo > 0.12 then
                state.lastMoveTo = now
                local moveHeading =
                    chooseMovementHeading(rootNow, characterNow)
                humNow:MoveTo(rootNow.Position
                    + headingVector(moveHeading) * 13)
            end
            -- Dash bursts (Caotico+): a short, hard lateral shove.
            if diff.dashMax > 0 and now >= state.nextDashAt then
                state.nextDashAt = now
                    + randomBetween(diff.dashMin, diff.dashMax)
                local dir = headingVector(
                    state.heading + (math.random() < 0.5
                        and -math.pi / 2 or math.pi / 2))
                local v = rootNow.AssemblyLinearVelocity
                rootNow.AssemblyLinearVelocity = Vector3.new(
                    v.X + dir.X * 20, v.Y, v.Z + dir.Z * 20)
                queueJump()
            end
        end

        -- Jump execution: ChangeState is what this controller
        -- honours; Humanoid.Jump is the fallback whisper.
        if state.jumpQueued then
            state.jumpQueued = false
            if humNow.FloorMaterial ~= Enum.Material.Air then
                state.jumpAttempts += 1
                state.jumpCheckAt = now + 0.3
                pcall(function()
                    humNow:ChangeState(
                        Enum.HumanoidStateType.Jumping)
                end)
                pcall(function() humNow.Jump = true end)
            end
        end
        if state.jumpCheckAt and now >= state.jumpCheckAt then
            state.jumpCheckAt = nil
            local vy = rootNow.AssemblyLinearVelocity.Y
            local name = ""
            pcall(function() name = humNow:GetState().Name end)
            if vy > 8 or name == "Jumping" or name == "Freefall" then
                state.jumpsDone += 1
            end
        end

        -- Anti-stuck: measured travel, not hopeful speed.
        if not standing and now - progressAt >= 0.8 then
            local traveled = (rootNow.Position - progressPos).Magnitude
            progressPos = rootNow.Position
            progressAt = now
            if traveled < 0.45 then
                stuckCount += 1
                queueJump()
                -- Score escape headings around the reverse direction
                -- (not blindly into whatever is behind us): swap the
                -- logical heading just for the probe, then restore it.
                local savedHeading = state.heading
                state.heading = savedHeading + math.pi * 0.8
                state.recoveryHeading = chooseMovementHeading(
                    rootNow, characterNow)
                state.heading = savedHeading
                state.recoveryUntil = now + 0.8
                if stuckCount >= 2 then
                    stuckCount = 0
                    state.forceBehaviorSwitch = true
                    print("[TargetBot] stuck twice -- new behavior")
                end
            else
                stuckCount = 0
            end
        end
    end
end)

local anchorConnection =
    LocalPlayer.CharacterAdded:Connect(function(character)
        task.wait(1)
        local rootNow = character:FindFirstChild("HumanoidRootPart")
        if rootNow then
            anchor = rootNow.Position
            progressPos = rootNow.Position
            progressAt = os.clock()
            print("[TargetBot] re-anchored at respawn")
        end
    end)

local function cleanup()
    state.active = false
    SETTINGS.running = false
    local _, humNow, rootNow = characterParts()
    setFlight(false, humNow, rootNow)
    if pumpConnection then pumpConnection:Disconnect() end
    if anchorConnection then anchorConnection:Disconnect() end
    if humNow then
        pcall(function() humNow.WalkSpeed = originalWalkSpeed end)
        pcall(function() humNow.PlatformStand = false end)
        if rootNow then
            pcall(function() humNow:MoveTo(rootNow.Position) end)
        end
    end
    if state.gui then
        pcall(function() state.gui:Destroy() end)
    end
end
state.cleanup = cleanup

--------------------------------------------------------------------------
-- Mini menu
--------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "WurstTargetBot"
gui.ResetOnSpawn = false
state.gui = gui
local parentOk = pcall(function() gui.Parent = gethui() end)
if not parentOk or not gui.Parent then
    pcall(function()
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end)
end

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(196, 344)
frame.Position = UDim2.new(0, 12, 0.5, -172)
frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
frame.BackgroundTransparency = 0.12
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
title.Text = "  TargetBot v4"
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.SourceSansBold
title.TextSize = 15
title.Parent = frame

local dragging, dragStart, frameStart = false, nil, nil
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        frameStart = frame.Position
    end
end)
title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
local dragConnection = RunService.RenderStepped:Connect(function()
    if dragging and dragStart then
        local mouse = LocalPlayer:GetMouse()
        frame.Position = UDim2.new(
            frameStart.X.Scale,
            frameStart.X.Offset + (mouse.X - dragStart.X),
            frameStart.Y.Scale,
            frameStart.Y.Offset + (mouse.Y - dragStart.Y))
    end
end)
table.insert(state, dragConnection)

local function makeLabel(y, height, color, size)
    local label = Instance.new("TextLabel")
    label.Position = UDim2.fromOffset(8, y)
    label.Size = UDim2.new(1, -16, 0, height)
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.Font = Enum.Font.SourceSans
    label.TextSize = size
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = "..."
    label.Parent = frame
    return label
end
local status1 = makeLabel(28, 16, Color3.fromRGB(170, 220, 170), 13)
local status2 = makeLabel(44, 16, Color3.fromRGB(190, 190, 200), 12)

local function makeButton(y, text)
    local button = Instance.new("TextButton")
    button.Position = UDim2.fromOffset(8, y)
    button.Size = UDim2.new(1, -16, 0, 25)
    button.BackgroundColor3 = Color3.fromRGB(45, 45, 54)
    button.BorderSizePixel = 0
    button.TextColor3 = Color3.fromRGB(235, 235, 235)
    button.Font = Enum.Font.SourceSansBold
    button.TextSize = 13
    button.Text = text
    button.Parent = frame
    return button
end

local function cycleIn(list, value)
    for index, item in ipairs(list) do
        if item == value then return list[index % #list + 1] end
    end
    return list[1]
end

local runButton = makeButton(66, "Activo: SI")
runButton.MouseButton1Click:Connect(function()
    SETTINGS.running = not SETTINGS.running
    runButton.Text = SETTINGS.running and "Activo: SI" or "Activo: NO"
end)
local diffButton = makeButton(97, "Modo: Dificil")
diffButton.MouseButton1Click:Connect(function()
    SETTINGS.difficulty = cycleIn(
        {"Realista", "Dificil", "Caotico", "Imposible"},
        SETTINGS.difficulty)
    diffButton.Text = "Modo: " .. SETTINGS.difficulty
    if SETTINGS.difficulty ~= "Imposible" then
        state.flying = false
        state.flightUntil = 0
    end
end)
local jumpButton = makeButton(128, "Saltos: Normal")
jumpButton.MouseButton1Click:Connect(function()
    SETTINGS.jumps = cycleIn(
        {"Sin", "Normal", "Frecuentes"}, SETTINGS.jumps)
    jumpButton.Text = "Saltos: " .. SETTINGS.jumps
end)
local distButton = makeButton(159, "Distancia: Media")
distButton.MouseButton1Click:Connect(function()
    SETTINGS.distance = cycleIn(
        {"Cerca", "Media", "Lejos"}, SETTINGS.distance)
    distButton.Text = "Distancia: " .. SETTINGS.distance
end)
local speedButton = makeButton(190, "Velocidad: Normal")
speedButton.MouseButton1Click:Connect(function()
    SETTINGS.speed = cycleIn(
        {"Normal", "Rapida", "Extrema"}, SETTINGS.speed)
    speedButton.Text = "Velocidad: " .. SETTINGS.speed
end)
local oppButton = makeButton(221, "Rival: Auto")
oppButton.MouseButton1Click:Connect(function()
    local choices = {"Auto"}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(choices, player.Name)
        end
    end
    SETTINGS.opponent = cycleIn(choices, SETTINGS.opponent)
    local label = SETTINGS.opponent
    if #label > 14 then label = string.sub(label, 1, 14) end
    oppButton.Text = "Rival: " .. label
end)
local anchorButton = makeButton(252, "Reanclar aqui")
anchorButton.MouseButton1Click:Connect(function()
    local rootNow = select(3, characterParts())
    if rootNow then
        anchor = rootNow.Position
        print("[TargetBot] anchor moved here")
    end
end)
local stopButton = makeButton(283, "DETENER Y QUITAR")
stopButton.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
stopButton.MouseButton1Click:Connect(function()
    cleanup()
    print("[TargetBot] removed from the menu button")
end)
makeLabel(314, 16, Color3.fromRGB(140, 140, 150), 11).Text =
    "Imposible = vuelo + dashes (test extremo)"

task.spawn(function()
    while state.active do
        local _, _, rootNow = characterParts()
        local oppPlayer, oppRoot = getOpponent()
        local distText = "-"
        if rootNow and oppRoot then
            distText = string.format("%.0f",
                (oppRoot.Position - rootNow.Position).Magnitude)
        end
        status1.Text = (SETTINGS.running and "" or "PAUSA · ")
            .. state.behaviorLabel
            .. (os.clock() < state.recoveryUntil and " [desatasco]" or "")
        status2.Text = string.format(
            "Rival %s a %s · Saltos %d/%d",
            oppPlayer and oppPlayer.Name or "?",
            distText, state.jumpsDone, state.jumpAttempts)
        task.wait(0.25)
    end
end)

print("[TargetBot v4] started. Menu on screen. "
    .. "Inject again to remove everything.")
