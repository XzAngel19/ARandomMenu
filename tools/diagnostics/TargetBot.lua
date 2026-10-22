--[[
    WURST TARGET BOT v3  (diagnostic, standalone -- for YOUR OWN alt)

    What the probes proved about moving a body in MM2:
      - Humanoid:Move is ignored (MoveDirection stays 0.00).
      - Humanoid:MoveTo works (MoveDirection 1.00, full speed).
    So v3 drives with MoveTo only, through a STEERING layer: the
    heading turns at a limited rate (deg/sec) like a person's hand
    on the keys -- no instant 180 flips, no velocity glitches.

    The movement is relative to YOU (the nearest other player, i.e.
    the shooter): it strafes perpendicular to your line of sight,
    zigzags in and out, orbits you, rushes and retreats -- the way a
    real player dodges a sheriff. That is what makes it genuinely
    hard to hit, and exactly the data ShootProbe needs.

    A small menu on the alt's screen controls it:
      [Activo]    start / stop button
      Dificultad  Normal / Dificil / Caotico
                    turn rate, strafe-flip rhythm, jump chance
      Saltos      Sin / Normal / Frecuentes
      Distancia   Cerca / Media / Lejos   (orbit distance to you)
    plus a status line naming the current behaviour.

    Place the alt somewhere open; it stays within ~40 studs of its
    anchor and re-anchors where it respawns. Inject once to start,
    again to remove the bot and its menu entirely.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local genv = getgenv()
if genv.WURST_TARGET_BOT and genv.WURST_TARGET_BOT.active then
    genv.WURST_TARGET_BOT.active = false
    if genv.WURST_TARGET_BOT.gui then
        pcall(function() genv.WURST_TARGET_BOT.gui:Destroy() end)
    end
    print("[TargetBot] removed")
    return
end

local SETTINGS = {
    running = true,
    difficulty = "Dificil",   -- Normal | Dificil | Caotico
    jumps = "Normal",         -- Sin | Normal | Frecuentes
    distance = "Media",       -- Cerca | Media | Lejos
}
local DIFFICULTY = {
    Normal = {turn = 200, flipMin = 0.9, flipMax = 1.6, jump = 0.15},
    Dificil = {turn = 320, flipMin = 0.55, flipMax = 1.0, jump = 0.30},
    Caotico = {turn = 460, flipMin = 0.35, flipMax = 0.7, jump = 0.45},
}
local JUMP_MULT = {Sin = 0, Normal = 1, Frecuentes = 1.8}
local DISTANCE = {Cerca = 16, Media = 26, Lejos = 38}

local state = {
    active = true,
    heading = math.random() * math.pi * 2,
    targetHeading = 0,
    wantJump = false,
    behavior = "still",
    mode = "moveto",
    stuckSince = nil,
    lastMoveTo = 0,
    gui = nil,
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
local anchor = root0.Position

-- The opponent: the nearest other player with a body (the shooter).
local function opponentRoot()
    local best, bestDistance = nil, math.huge
    local myRoot = select(3, characterParts())
    if not myRoot then return nil end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local root =
                player.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local distance =
                    (root.Position - myRoot.Position).Magnitude
                if distance < bestDistance then
                    best, bestDistance = root, distance
                end
            end
        end
    end
    return best
end

local function wrapAngle(angle)
    while angle > math.pi do angle -= math.pi * 2 end
    while angle < -math.pi do angle += math.pi * 2 end
    return angle
end
local function headingVector(heading)
    return Vector3.new(math.sin(heading), 0, math.cos(heading))
end

-- Behaviour brain: picks a target heading (and jumps) relative to
-- the opponent. Runs on a 0.1 s tick; the steering layer below
-- turns toward it at the difficulty's rate, which is what keeps
-- every change of direction smooth and human.
local brain = task.spawn(function()
    local phaseUntil = 0
    local flipAt = 0
    local side = 1
    local behaviors = {
        "strafe", "zigzagIn", "orbit", "zigzagOut",
        "rush", "wander", "strafe",
    }
    local behaviorIndex = 0
    while state.active do
        task.wait(0.1)
        local _, humNow, rootNow = characterParts()
        local opp = opponentRoot()
        local now = os.clock()
        if not SETTINGS.running or not humNow
            or humNow.Health <= 0 or not rootNow then
            state.targetHeading = state.heading
        else
            if now >= phaseUntil then
                behaviorIndex = behaviorIndex % #behaviors + 1
                state.behavior = behaviors[behaviorIndex]
                phaseUntil = now + math.random(70, 120) / 10
                flipAt = now
                print("[TargetBot] behavior: " .. state.behavior)
            end
            local diff = DIFFICULTY[SETTINGS.difficulty]
            local toOpp = state.heading
            local orbitRadius = DISTANCE[SETTINGS.distance]
            if opp then
                local away = rootNow.Position - opp.Position
                toOpp = math.atan2(away.X, away.Z) -- heading away
            end
            local behavior = state.behavior
            if behavior == "still" then
                state.targetHeading = state.heading
            elseif behavior == "strafe" then
                if now >= flipAt then
                    side = -side
                    flipAt = now + math.random(
                        diff.flipMin * 100, diff.flipMax * 100) / 100
                    if math.random() < diff.jump
                        * JUMP_MULT[SETTINGS.jumps] then
                        state.wantJump = true
                    end
                end
                -- Perpendicular to the line of sight, flipping.
                state.targetHeading = toOpp + side * math.pi / 2
                    + math.rad(math.random(-12, 12))
            elseif behavior == "zigzagIn" then
                if now >= flipAt then
                    side = -side
                    flipAt = now + math.random(60, 110) / 100
                end
                state.targetHeading = toOpp + math.pi
                    + side * math.rad(math.random(30, 55))
            elseif behavior == "zigzagOut" then
                if now >= flipAt then
                    side = -side
                    flipAt = now + math.random(60, 110) / 100
                    if math.random() < diff.jump * 0.7
                        * JUMP_MULT[SETTINGS.jumps] then
                        state.wantJump = true
                    end
                end
                state.targetHeading = toOpp
                    + side * math.rad(math.random(30, 55))
            elseif behavior == "orbit" then
                -- Hold a ring around the opponent: tangent heading
                -- corrected by how far off the ring we are.
                if opp then
                    local away = rootNow.Position - opp.Position
                    local flat = Vector3.new(away.X, 0, away.Z)
                    local radialError = flat.Magnitude - orbitRadius
                    local correction = math.clamp(
                        -radialError * 0.04, -0.7, 0.7)
                    state.targetHeading = toOpp
                        + side * (math.pi / 2 + correction)
                    if now >= flipAt then
                        if math.random() < 0.3 then side = -side end
                        flipAt = now + math.random(200, 400) / 100
                    end
                else
                    state.targetHeading = toOpp + side * math.pi / 2
                end
            elseif behavior == "rush" then
                state.targetHeading = toOpp + math.pi
                    + math.rad(math.random(-18, 18))
                if math.random() < diff.jump * 0.5
                    * JUMP_MULT[SETTINGS.jumps] then
                    state.wantJump = true
                end
            else -- wander: smooth heading noise
                if now >= flipAt then
                    flipAt = now + math.random(40, 90) / 100
                    state.targetHeading = state.heading
                        + math.rad(math.random(-70, 70))
                    if math.random() < diff.jump * 0.6
                        * JUMP_MULT[SETTINGS.jumps] then
                        state.wantJump = true
                    end
                end
            end
            -- Keep the alt near its anchor no matter what.
            local flat = Vector3.new(
                rootNow.Position.X - anchor.X, 0,
                rootNow.Position.Z - anchor.Z)
            if flat.Magnitude > 40 then
                state.targetHeading =
                    math.atan2(-flat.X, -flat.Z)
            end
        end
    end
end)

-- Steering + actuation pump.
local pump = RunService.Heartbeat:Connect(function()
    if not state.active then return end
    local _, humNow, rootNow = characterParts()
    if not humNow or not rootNow or humNow.Health <= 0 then
        return
    end
    if not SETTINGS.running then
        humNow:Move(Vector3.zero, false)
        return
    end
    local diff = DIFFICULTY[SETTINGS.difficulty]
    local delta = wrapAngle(state.targetHeading - state.heading)
    local maxTurn = math.rad(diff.turn) * (1 / 60)
    state.heading = state.heading
        + math.clamp(delta, -maxTurn, maxTurn)
    local now = os.clock()
    if now - state.lastMoveTo > 0.12 then
        state.lastMoveTo = now
        humNow:MoveTo(
            rootNow.Position + headingVector(state.heading) * 14)
    end
    if state.wantJump
        and humNow.FloorMaterial ~= Enum.Material.Air then
        humNow.Jump = true
        state.wantJump = false
    end
    -- Safety net only: if MoveTo ever stops moving this body,
    -- fall back to direct velocity and say so once.
    local velocity = rootNow.AssemblyLinearVelocity
    local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    if flatSpeed < 1 and state.mode == "moveto" then
        state.stuckSince = state.stuckSince or now
        if now - state.stuckSince > 2 then
            state.mode = "push"
            print("[TargetBot] MoveTo stopped working; "
                .. "velocity push fallback on")
        end
    elseif flatSpeed >= 1 then
        state.stuckSince = nil
    end
    if state.mode == "push" then
        local speed = humNow.WalkSpeed > 0 and humNow.WalkSpeed or 16
        local dir = headingVector(state.heading)
        rootNow.AssemblyLinearVelocity =
            Vector3.new(dir.X * speed, velocity.Y, dir.Z * speed)
    end
end)

-- Re-anchor where the alt respawns.
local anchorConnection =
    LocalPlayer.CharacterAdded:Connect(function(character)
        task.wait(1)
        local rootNow = character:FindFirstChild("HumanoidRootPart")
        if rootNow then
            anchor = rootNow.Position
            print("[TargetBot] re-anchored at respawn")
        end
    end)
table.insert(state, anchorConnection)

--------------------------------------------------------------------------
-- Mini menu
--------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "WurstTargetBot"
gui.ResetOnSpawn = false
state.gui = gui
local parentOk = pcall(function()
    gui.Parent = gethui()
end)
if not parentOk or not gui.Parent then
    pcall(function()
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end)
end

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(190, 208)
frame.Position = UDim2.new(0, 12, 0.5, -104)
frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
frame.BackgroundTransparency = 0.12
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
title.Text = "  TargetBot"
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
RunService.RenderStepped:Connect(function()
    if dragging and dragStart then
        local mouse = LocalPlayer:GetMouse()
        local delta = Vector2.new(
            mouse.X - dragStart.X, mouse.Y - dragStart.Y)
        frame.Position = UDim2.new(
            frameStart.X.Scale, frameStart.X.Offset + delta.X,
            frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
    end
end)

local statusLabel = Instance.new("TextLabel")
statusLabel.Position = UDim2.fromOffset(8, 28)
statusLabel.Size = UDim2.new(1, -16, 0, 18)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(170, 220, 170)
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 13
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "..."
statusLabel.Parent = frame

local function makeButton(y, label)
    local button = Instance.new("TextButton")
    button.Position = UDim2.fromOffset(8, y)
    button.Size = UDim2.new(1, -16, 0, 26)
    button.BackgroundColor3 = Color3.fromRGB(45, 45, 54)
    button.BorderSizePixel = 0
    button.TextColor3 = Color3.fromRGB(235, 235, 235)
    button.Font = Enum.Font.SourceSansBold
    button.TextSize = 14
    button.Text = label
    button.Parent = frame
    return button
end

local function cycle(value, list)
    for index, item in ipairs(list) do
        if item == value then
            return list[index % #list + 1]
        end
    end
    return list[1]
end

local runButton = makeButton(52, "Activo: SI")
runButton.MouseButton1Click:Connect(function()
    SETTINGS.running = not SETTINGS.running
    runButton.Text = SETTINGS.running and "Activo: SI" or "Activo: NO"
end)
local diffButton = makeButton(84, "Dificultad: " .. SETTINGS.difficulty)
diffButton.MouseButton1Click:Connect(function()
    SETTINGS.difficulty = cycle(
        SETTINGS.difficulty, {"Normal", "Dificil", "Caotico"})
    diffButton.Text = "Dificultad: " .. SETTINGS.difficulty
end)
local jumpButton = makeButton(116, "Saltos: " .. SETTINGS.jumps)
jumpButton.MouseButton1Click:Connect(function()
    SETTINGS.jumps = cycle(
        SETTINGS.jumps, {"Sin", "Normal", "Frecuentes"})
    jumpButton.Text = "Saltos: " .. SETTINGS.jumps
end)
local distButton = makeButton(148, "Distancia: " .. SETTINGS.distance)
distButton.MouseButton1Click:Connect(function()
    SETTINGS.distance = cycle(
        SETTINGS.distance, {"Cerca", "Media", "Lejos"})
    distButton.Text = "Distancia: " .. SETTINGS.distance
end)
local stopButton = makeButton(180, "DETENER Y QUITAR")
stopButton.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
stopButton.MouseButton1Click:Connect(function()
    state.active = false
    local _, humNow = characterParts()
    if humNow then
        pcall(function() humNow:Move(Vector3.zero, false) end)
    end
    gui:Destroy()
    print("[TargetBot] removed from the menu button")
end)

task.spawn(function()
    while state.active do
        statusLabel.Text = (SETTINGS.running and "Moviendo: " or "Pausa: ")
            .. state.behavior .. "  [" .. state.mode .. "]"
        task.wait(0.25)
    end
end)

print("[TargetBot v3] started (MoveTo + steering). "
    .. "Menu on screen. Inject again to remove.")
