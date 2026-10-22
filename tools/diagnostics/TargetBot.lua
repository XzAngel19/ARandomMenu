--[[
    WURST TARGET BOT  (diagnostic, standalone -- for YOUR OWN alt account)
    Version 2: self-diagnosing movement.

    v1 printed its phases but the body never moved in MM2:
    Humanoid:Move is only a *request* to the character controller,
    and this game evidently does not honour it the way a stock rig
    does. v2 escalates through three actuation methods on its own
    and reports which one your character actually obeys:

      mode "move"   -> Humanoid:Move(direction) every physics step
                       (what a player's own control script does)
      mode "moveto" -> Humanoid:MoveTo(point ahead) refreshed 5x/s
                       (what NPCs use; controllers rarely block it)
      mode "push"   -> direct horizontal velocity on the root part
                       (last resort; looks like walking, proves the
                       body *can* move here at all)

    Every 1-1.5 s of trying-but-not-moving (real root speed < 1
    while a direction is requested) escalates to the next mode and
    prints why. It also prints a state snapshot at start (WalkSpeed,
    PlatformStand, Anchored, humanoid state, MoveDirection) -- if
    even "push" fails, that snapshot says what this game does to
    characters, which is the answer either way.

    Same program as v1 otherwise (~75 s loop): still, straight,
    strafe, zigzag, runs with jumps, stop-start, circle, 180
    reversals, random wander. Alt stays within ~35 studs of its
    anchor. Inject once to start, again to stop.
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

local state = {
    active = true,
    dir = Vector3.zero,
    wantJump = false,
    mode = "move",
    stuckSince = nil,
    lastMoveTo = 0,
}
genv.WURST_TARGET_BOT = state

local function characterParts()
    local character = LocalPlayer.Character
    if not character then return nil, nil, nil end
    return character,
        character:FindFirstChildOfClass("Humanoid"),
        character:FindFirstChild("HumanoidRootPart")
end

local _, humanoid, root = characterParts()
if not humanoid or not root then
    print("[TargetBot] character not ready -- inject again in game")
    state.active = false
    return
end
local anchor = root.Position

local function snapshot(tag)
    local _, humNow, rootNow = characterParts()
    if not humNow or not rootNow then
        print("[TargetBot] " .. tag .. ": no character")
        return
    end
    local velocity = rootNow.AssemblyLinearVelocity
    local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    local stateName = "?"
    pcall(function()
        stateName = humNow:GetState().Name
    end)
    print(string.format(
        "[TargetBot] %s: mode=%s speed=%.1f WalkSpeed=%s "
            .. "PlatformStand=%s Anchored=%s State=%s MoveDir=%.2f",
        tag, state.mode, flatSpeed,
        tostring(humNow.WalkSpeed),
        tostring(humNow.PlatformStand),
        tostring(rootNow.Anchored),
        stateName,
        humNow.MoveDirection.Magnitude))
end

snapshot("start")

-- Movement pump: applies the desired direction in the current
-- mode, jumps only from the ground, escalates when the body does
-- not actually move, and never lets the alt wander off.
local pump = RunService.Heartbeat:Connect(function()
    if not state.active then return end
    local characterNow, humNow, rootNow = characterParts()
    if not humNow or not rootNow or humNow.Health <= 0 then
        state.dir = Vector3.zero
        return
    end
    local dir = state.dir
    local offset = rootNow.Position - anchor
    local flat = Vector3.new(offset.X, 0, offset.Z)
    if flat.Magnitude > 35 and dir.Magnitude > 0 then
        dir = (-flat).Unit
        state.dir = dir
    end

    local velocity = rootNow.AssemblyLinearVelocity
    local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

    if dir.Magnitude > 0 then
        if state.mode == "move" then
            humNow:Move(dir, false)
        elseif state.mode == "moveto" then
            local now = os.clock()
            if now - state.lastMoveTo > 0.2 then
                state.lastMoveTo = now
                humNow:MoveTo(rootNow.Position + dir * 12)
            end
        elseif state.mode == "push" then
            local speed = humNow.WalkSpeed > 0
                and humNow.WalkSpeed or 16
            rootNow.AssemblyLinearVelocity = Vector3.new(
                dir.X * speed, velocity.Y, dir.Z * speed)
        end
        -- Trying but not moving? Escalate and say so.
        if flatSpeed < 1 then
            state.stuckSince = state.stuckSince or os.clock()
            local stuckFor = os.clock() - state.stuckSince
            if state.mode == "move" and stuckFor > 1.2 then
                state.mode = "moveto"
                state.stuckSince = nil
                print("[TargetBot] Humanoid:Move is ignored here; "
                    .. "switching to MoveTo")
                snapshot("escalation")
            elseif state.mode == "moveto" and stuckFor > 1.5 then
                state.mode = "push"
                state.stuckSince = nil
                print("[TargetBot] MoveTo is ignored too; "
                    .. "switching to direct velocity push")
                snapshot("escalation")
            elseif state.mode == "push" and stuckFor > 1.5 then
                state.stuckSince = nil
                print("[TargetBot] even velocity push does not "
                    .. "move this body -- see snapshot:")
                snapshot("cannot-move")
            end
        else
            state.stuckSince = nil
        end
    else
        state.stuckSince = nil
        if state.mode == "moveto" then
            humNow:Move(rootNow and state.dir or Vector3.zero, false)
        end
    end

    if state.wantJump and humNow.FloorMaterial ~= Enum.Material.Air then
        humNow.Jump = true
        state.wantJump = false
    end
end)

task.delay(2.5, function()
    if state.active then snapshot("check 2.5s") end
end)

local function headingVector(heading)
    return Vector3.new(math.sin(heading), 0, math.cos(heading))
end

local function alive()
    local _, humNow = characterParts()
    return state.active and humNow and humNow.Health > 0
end

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
        runPhase("still (control)", 3, function()
            state.dir = Vector3.zero
            return true
        end)
        local heading = baseHeading
        runPhase("straight constant run", 6, function()
            state.dir = headingVector(heading)
            return true
        end)
        runPhase("strafe A/D oscillation", 8, function(t)
            local side = math.floor(t / 0.8) % 2 == 0 and 1 or -1
            state.dir = headingVector(heading + side * math.pi / 2)
            return true
        end)
        runPhase("zigzag +-45", 8, function(t)
            local side = math.floor(t / 0.7) % 2 == 0 and 1 or -1
            state.dir = headingVector(heading + side * math.pi / 4)
            return true
        end)
        runPhase("straight run + jumps", 7, function()
            state.dir = headingVector(heading)
            state.wantJump = true
            return true
        end)
        runPhase("strafe + jumps", 8, function(t)
            local side = math.floor(t / 0.9) % 2 == 0 and 1 or -1
            state.dir = headingVector(heading + side * math.pi / 2)
            state.wantJump = true
            return true
        end)
        runPhase("stop-start bursts", 8, function(t)
            local cycle = t % 1.8
            state.dir = cycle < 1.2
                and headingVector(heading) or Vector3.zero
            return true
        end)
        runPhase("constant circle", 7, function(t)
            state.dir = headingVector(heading + t * 0.96)
            return true
        end)
        runPhase("180 reversals", 9, function(t)
            local flip = math.floor(t / 2.2) % 2 == 0 and 0 or math.pi
            state.dir = headingVector(heading + flip)
            if math.random() < 0.06 then
                state.wantJump = true
            end
            return true
        end)
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
    state.dir = Vector3.zero
    local _, humNow, rootNow = characterParts()
    if humNow then
        pcall(function() humNow:Move(Vector3.zero, false) end)
        if rootNow then
            pcall(function()
                humNow:MoveTo(rootNow.Position)
            end)
        end
    end
    if pump then pump:Disconnect() end
    snapshot("final")
    print("[TargetBot] stopped")
end)
