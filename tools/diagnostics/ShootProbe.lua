--[[
    WURST SHOOT PROBE  (diagnostic, standalone -- not part of the menu)

    WHY: the menu's Shoot prediction has been tuned for many versions
    from calibration sessions, and it still misses. What we never
    measured directly is the GAME's side of the shot: after you fire,
    when does the server actually score it, and where must the target
    be at that instant? This probe measures exactly that, with no
    menu code involved, so the numbers can be trusted.

    HOW TO RUN IT:
      1. Join MM2 as Sheriff (you need the gun).
      2. IMPORTANT: turn the menu's Shoot / SilentAim OFF. Shoot
         MANUALLY for this test -- the probe reads YOUR camera ray,
         and silent shots do not travel along it.
      3. Inject this script once. Then play normally for a few
         minutes: take ~15-25 shots at MOVING players (also a few
         at far ones and a few at jumpers, if you can).
      4. When done, run it AGAIN (inject a second time) -- the
         second run prints/writes/copies the report and stops.

    FOR EVERY SHOT IT RECORDS:
      - your camera ray and ping at the fire instant,
      - every player's position sampled every frame (a 3 s ring
        buffer per player, so pre- and post-shot motion is kept),
      - the outcome (a health drop on the ray's target = a hit, and
        WHEN it registered),
      - and the decisive number: the "effective lead" of the shot --
        the instant after firing at which the target's real
        trajectory crosses your ray (found by replaying the buffer).
        For a hit, that is the moment the game rewarded. The summary
        turns all your hits into a median effective lead and shows
        how much of it ping explains, plus how far a plain
        constant-velocity prediction would have been off at that
        instant -- the exact quantity the menu's predictor must fix.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

local genv = getgenv()
if genv.WURST_SHOOT_PROBE and genv.WURST_SHOOT_PROBE.active then
    -- Second injection: finish and report.
    genv.WURST_SHOOT_PROBE.finish()
    return
end

local SESSION_SECONDS = 600
local BUFFER_SECONDS = 3.0
local startedAt = os.clock()

local buffers = {}   -- player -> { {t=..., p=Vector3}, ... }
local shots = {}     -- per-shot records
local connections = {}

local function rootOf(player)
    local character = player and player.Character
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end
local function humanoidOf(player)
    local character = player and player.Character
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end
local function pingMs()
    local ok, value = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return ok and value or -1
end

local function sampleAll()
    local now = os.clock()
    for _, player in ipairs(Players:GetPlayers()) do
        local root = rootOf(player)
        if root then
            local buffer = buffers[player]
            if not buffer then
                buffer = {}
                buffers[player] = buffer
            end
            table.insert(buffer, {t = now, p = root.Position})
            local cutoff = now - BUFFER_SECONDS
            while #buffer > 2 and buffer[1].t < cutoff do
                table.remove(buffer, 1)
            end
        end
    end
end

local function positionAt(player, when)
    local buffer = buffers[player]
    if not buffer or #buffer == 0 then return nil end
    if when <= buffer[1].t then return buffer[1].p end
    for i = 2, #buffer do
        local b = buffer[i]
        if b.t >= when then
            local a = buffer[i - 1]
            local span = b.t - a.t
            local alpha = span > 0 and (when - a.t) / span or 0
            return a.p:Lerp(b.p, math.clamp(alpha, 0, 1))
        end
    end
    return buffer[#buffer].p
end

local function velocityAt(player, when)
    local a = positionAt(player, when - 0.08)
    local b = positionAt(player, when + 0.08)
    if not a or not b then return Vector3.zero end
    return (b - a) / 0.16
end

-- Distance from point to the fire ray.
local function rayDistance(origin, direction, point)
    local along = (point - origin):Dot(direction)
    if along < 0 then along = 0 end
    local closest = origin + direction * along
    return (point - closest).Magnitude, along
end

local pending = nil  -- the shot still waiting for its outcome

local function finishShot(shot, hitPlayer, hitAt)
    shot.done = true
    local fireAt = shot.at
    local target = hitPlayer or shot.guess
    shot.target = target
    -- Replay the target's real trajectory against the fire ray and
    -- find when it was closest: for a hit, that instant is the lead
    -- the game scored.
    local bestT, bestDistance = nil, math.huge
    if target then
        local step = 0.01
        local when = fireAt
        while when <= fireAt + 1.2 do
            local position = positionAt(target, when)
            if position then
                local distance = rayDistance(
                    shot.origin, shot.direction, position)
                if distance < bestDistance then
                    bestDistance = distance
                    bestT = when
                end
            end
            when += step
        end
    end
    shot.bestT = bestT
    shot.bestDistance = bestDistance
    shot.hitAt = hitAt
    if target and bestT then
        local velocity = velocityAt(target, fireAt)
        local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
        shot.targetSpeed = horizontal.Magnitude
        shot.targetJumping = velocity.Y > 12 or velocity.Y < -18
        -- Constant-velocity prediction from the fire instant to the
        -- crossing instant: how far off would the plain model be?
        local startPosition = positionAt(target, fireAt)
        local realPosition = positionAt(target, bestT)
        if startPosition and realPosition then
            local predicted = startPosition + velocity * (bestT - fireAt)
            shot.cvError = (realPosition - predicted).Magnitude
        end
    end
end

local function noteShot()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local now = os.clock()
    if pending and not pending.done then
        finishShot(pending, nil, nil)
    end
    -- Who is the ray actually pointing at?
    local origin = camera.CFrame.Position
    local direction = camera.CFrame.LookVector
    local guess, guessDistance = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local root = rootOf(player)
            if root then
                local distance, along = rayDistance(
                    origin, direction, root.Position)
                if along > 0 and distance < guessDistance then
                    guess = player
                    guessDistance = distance
                end
            end
        end
    end
    local myRoot = rootOf(LocalPlayer)
    local shot = {
        at = now,
        origin = origin,
        direction = direction,
        guess = guess,
        guessDistance = guessDistance,
        ping = pingMs(),
        range = myRoot and guess and rootOf(guess)
            and (rootOf(guess).Position - myRoot.Position).Magnitude
            or -1,
        done = false,
    }
    table.insert(shots, shot)
    pending = shot
    -- A shot with no registered hit inside 1.3 s is a miss.
    task.delay(1.3, function()
        if pending == shot and not shot.done then
            finishShot(shot, nil, nil)
            pending = nil
        end
    end)
end

local function watchHumanoids()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local humanoid = humanoidOf(player)
            if humanoid and not humanoid:GetAttribute("__WurstProbe") then
                humanoid:SetAttribute("__WurstProbe", true)
                local lastHealth = humanoid.Health
                table.insert(connections,
                    humanoid.HealthChanged:Connect(function(health)
                        if health < lastHealth - 0.5 and pending
                            and not pending.done
                            and os.clock() - pending.at < 1.3 then
                            finishShot(pending, player, os.clock())
                            pending = nil
                        end
                        lastHealth = health
                    end))
            end
        end
    end
end

-- Fire detection: the gun Tool activating in our hands.
local function watchBackpack()
    local character = LocalPlayer.Character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool")
                and not tool:GetAttribute("__WurstProbe") then
                tool:SetAttribute("__WurstProbe", true)
                table.insert(connections,
                    tool.Activated:Connect(noteShot))
            end
        end
    end
end

table.insert(connections, RunService.RenderStepped:Connect(function()
    sampleAll()
    watchHumanoids()
    watchBackpack()
    if os.clock() - startedAt > SESSION_SECONDS
        and genv.WURST_SHOOT_PROBE then
        genv.WURST_SHOOT_PROBE.finish()
    end
end))

local function median(values)
    if #values == 0 then return nil end
    table.sort(values)
    local middle = math.floor(#values / 2)
    if #values % 2 == 0 then
        return (values[middle] + values[middle + 1]) / 2
    end
    return values[middle + 1]
end

local function finish()
    local probe = genv.WURST_SHOOT_PROBE
    if not probe or not probe.active then return end
    probe.active = false
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    if pending and not pending.done then
        finishShot(pending, nil, nil)
    end
    local lines = {}
    local function log(fmt, ...)
        table.insert(lines, string.format(fmt, ...))
    end
    log("=== WURST SHOOT PROBE REPORT ===")
    log("PlaceId=%s samples of truth: %d shots", tostring(game.PlaceId), #shots)
    local hitLeads, hitCvErrors, hitCount = {}, {}, 0
    for index, shot in ipairs(shots) do
        local isHit = shot.hitAt ~= nil
        if isHit then
            hitCount += 1
            if shot.bestT then
                table.insert(hitLeads,
                    (shot.bestT - shot.at) * 1000)
            end
            if shot.cvError then
                table.insert(hitCvErrors, shot.cvError)
            end
        end
        log("#%d %s target=%s range=%s ping=%s effLead=%s "
            .. "speed=%s jump=%s cvErr=%s closest=%s regDelay=%s",
            index,
            isHit and "HIT " or "MISS",
            shot.target and shot.target.Name or "?",
            shot.range and string.format("%.0f", shot.range) or "?",
            shot.ping and string.format("%.0fms", shot.ping) or "?",
            shot.bestT and string.format("%.0fms",
                (shot.bestT - shot.at) * 1000) or "-",
            shot.targetSpeed and string.format("%.1f",
                shot.targetSpeed) or "-",
            shot.targetJumping and "Y" or "n",
            shot.cvError and string.format("%.2f", shot.cvError) or "-",
            shot.bestDistance and string.format("%.1f",
                shot.bestDistance) or "-",
            shot.hitAt and string.format("%.0fms",
                (shot.hitAt - shot.at) * 1000) or "-")
    end
    log("--- summary ---")
    log("shots=%d hits=%d (%.0f%%)", #shots, hitCount,
        #shots > 0 and hitCount / #shots * 100 or 0)
    local medianLead = median(hitLeads)
    local medianCv = median(hitCvErrors)
    if medianLead then
        log("MEDIAN effective lead on hits: %.0f ms "
            .. "(this is what the game's scoring rewards)", medianLead)
    end
    if medianCv then
        log("MEDIAN constant-velocity error at that instant: %.2f "
            .. "studs (>~0.9 means acceleration/turn handling matters)",
            medianCv)
    end
    log("Read me: if effective lead tracks your ping 1:1, the "
        .. "predictor's full-pipeline horizon is right and the "
        .. "misses live elsewhere (turns, jumps, fit window). If it "
        .. "sits consistently above/below ping, the horizon itself "
        .. "is off by that gap on every shot.")
    log("=== END OF REPORT ===")
    local report = table.concat(lines, "\n")
    print(report)
    pcall(function()
        if writefile then
            writefile("WurstShootProbe.txt", report)
            print("[ShootProbe] written to WurstShootProbe.txt")
        end
    end)
    pcall(function()
        if setclipboard then
            setclipboard(report)
            print("[ShootProbe] report copied to clipboard")
        end
    end)
end

genv.WURST_SHOOT_PROBE = {active = true, finish = finish}
print("[ShootProbe] armed for 10 minutes. Shoot MANUALLY with "
    .. "menu Shoot OFF, then inject this script again for the report.")
