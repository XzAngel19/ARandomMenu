--[[
    WURST TARGET BOT  (diagnostic, standalone -- for YOUR OWN alt account)

    Inject this on the alt account, in the same MM2 server where your
    main account runs ShootProbe. The alt becomes a practice target
    that cycles through every movement pattern the Shoot predictor
    has to handle, using only Humanoid:Move and jumps -- exactly the
    inputs a real player produces, at the game's normal WalkSpeed.

    THE PROGRAM (~75 s loop):
       1. Standing still            (control case)
       2. Straight constant run     (pure constant-velocity lead)
       3. Strafe A/D oscillation    (hard lateral acceleration)
       4. Zigzag +-45 deg           (repeated sharp turns)
       5. Straight run + jumps      (airborne / ballistic phases)
       6. Strafe + jump on landing  (worst case combined)
       7. Stop-start bursts         (instant decel/accel)
       8. Constant-rate circle      (sustained turn)
       9. 180-deg reversals         (maximum turn residual)
      10. Random wander             (unpredictable heading noise,
                                    occasional jumps)

    The bot stays within ~35 studs of where it started (it steers
    back to its anchor), so place the alt somewhere open, stand
    20-40 studs away on your main, and shoot it manually with
    ShootProbe recording (menu Shoot OFF).

    Inject once to start, inject again to stop. On stop (and on
    death) it zeroes its movement input and gives the alt back.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local genv = getgenv()
if genv.WURST_TARGET_BOT and genv.WURST_TARGET_BOT.active then
    genv.WURST_TARGET_BOT.active = false
    print("[TargetBot] stopping (movement input zeroed)")
    return
end

local state = {active = true, dir = Vector3.zero, wantJump = false}
genv.WURST_TARGET_BOT = state

local function characterParts()
    local character = LocalPlayer.Character
    if not character then return nil, nil end
    return character,
        character:FindFirstChildOfClass("Humanoid")
end

local character, humanoid = characterParts()
if not humanoid then
    print("[TargetBot] character not ready -- inject again in game")
    state.active = false
    return
end
local root = character:FindFirstChild("HumanoidRootPart")
local anchor = root and root.Position or Vector3.zero

-- Movement pump: applies the desired direction every physics step,
-- jumps only from the ground, and never lets the alt wander off.
local pump = RunService.Heartbeat:Connect(function()
    if not state.active then return end
    local charNow, humNow = characterParts()
    if not humNow or humNow.Health <= 0 then
        state.dir = Vector3.zero
        return
    end
    local rootNow = charNow:FindFirstChild("HumanoidRootPart")
    local dir = state.dir
    if rootNow then
        local offset = rootNow.Position - anchor
        local flat = Vector3.new(offset.X, 0, offset.Z)
        if flat.Magnitude > 35 then
            dir = (-flat).Unit
            state.dir = dir
        end
    end
    humNow:Move(dir, false)
    if state.wantJump and humNow.FloorMaterial ~= Enum.Material.Air then
        humNow.Jump = true
        state.wantJump = false
    end
end)

local function headingVector(heading)
    return Vector3.new(math.sin(heading), 0, math.cos(heading))
end

local function alive()
    local _, humNow = characterParts()
    return state.active and humNow and humNow.Health > 0
end

-- Run one phase: step() returns false when the phase is over.
local function runPhase(name, seconds, step)
    if not alive() then return end
    print("[TargetBot] phase: " .. name)
    local startedAt = os.clock()
    while alive() and os.clock() - startedAt < seconds do
        if step(os.clock() - startedAt) == false then break end
        task.wait(0.05)
    end
    state.dir = Vector3.zero
    state.wantJump = false
end

print("[TargetBot] started. Anchor set here; cycle ~75 s. "
    .. "Inject again to stop.")

task.spawn(function()
    local baseHeading = math.random() * math.pi * 2
    while alive() do
        -- 1) Standing still.
        runPhase("still (control)", 3, function()
            state.dir = Vector3.zero
            return true
        end)
        -- 2) Straight constant run.
        local heading = baseHeading
        runPhase("straight constant run", 6, function()
            state.dir = headingVector(heading)
            return true
        end)
        -- 3) Strafe oscillation (perpendicular flips).
        runPhase("strafe A/D oscillation", 8, function(t)
            local side = math.floor(t / 0.8) % 2 == 0 and 1 or -1
            state.dir = headingVector(heading + side * math.pi / 2)
            return true
        end)
        -- 4) Zigzag.
        runPhase("zigzag +-45", 8, function(t)
            local side = math.floor(t / 0.7) % 2 == 0 and 1 or -1
            state.dir = headingVector(heading + side * math.pi / 4)
            return true
        end)
        -- 5) Straight run, jump on every landing.
        runPhase("straight run + jumps", 7, function()
            state.dir = headingVector(heading)
            state.wantJump = true
            return true
        end)
        -- 6) Strafe flips with jumps.
        runPhase("strafe + jumps", 8, function(t)
            local side = math.floor(t / 0.9) % 2 == 0 and 1 or -1
            state.dir = headingVector(heading + side * math.pi / 2)
            state.wantJump = true
            return true
        end)
        -- 7) Stop-start bursts.
        runPhase("stop-start bursts", 8, function(t)
            local cycle = t % 1.8
            state.dir = cycle < 1.2
                and headingVector(heading) or Vector3.zero
            return true
        end)
        -- 8) Constant-rate circle.
        runPhase("constant circle", 7, function(t)
            state.dir = headingVector(heading + t * 0.96)
            return true
        end)
        -- 9) 180-degree reversals.
        runPhase("180 reversals", 9, function(t)
            local flip = math.floor(t / 2.2) % 2 == 0 and 0 or math.pi
            state.dir = headingVector(heading + flip)
            if math.random() < 0.06 then
                state.wantJump = true
            end
            return true
        end)
        -- 10) Random wander with the odd jump.
        local wanderHeading = heading
        local nextTurn = 0
        runPhase("random wander", 10, function(t)
            if t >= nextTurn then
                wanderHeading += math.rad(math.random(-140, 140))
                nextTurn = t + math.random(50, 110) / 100
                if math.random() < 0.25 then
                    state.wantJump = true
                end
            end
            state.dir = headingVector(wanderHeading)
            return true
        end)
        baseHeading += math.pi / 3
    end
    -- Give the alt back clean.
    state.dir = Vector3.zero
    local _, humNow = characterParts()
    if humNow then
        pcall(function() humNow:Move(Vector3.zero, false) end)
    end
    if pump then pump:Disconnect() end
    print("[TargetBot] stopped")
end)
