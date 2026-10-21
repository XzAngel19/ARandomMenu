--[[
    WURST DISGUISE PROBE  (diagnostic, standalone -- not part of the menu)

    Run this ONCE inside Murder Mystery 2, in a server where the person
    whose animations you want is present and moving around. It takes
    ~10 seconds, briefly pauses your own animations during the mirror
    test, then restores everything.

    It answers, with evidence instead of guesses:
      A. What this place allows: who owns it, your rig, whether your
         character uses a standard "Animate" script at all.
      B. What the target is really playing: their Animate slot ids,
         their live tracks, their joints, their description ids.
      C. Whether the target's idle clip can load on YOUR Animator
         (expect the engine to refuse it -- that is the whole problem).
      D. What the catalog says about that clip (creator, type).
      E. THE MIRROR TEST: for 5 seconds it copies the target's joint
         poses onto your body exactly like the menu does, and MEASURES
         whether your joints actually follow -- and whether something
         (your own Animator?) overwrites them afterwards.

    Result: printed to the console, written to "WurstDisguiseProbe.txt"
    (if writefile exists) and copied to your clipboard (if setclipboard
    exists). Paste the whole thing back to the developer.

    Optional: set getgenv().WURST_PROBE_TARGET = <userId> before running
    to pick the target; otherwise the first other player with a
    character is used.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalPlayer = Players.LocalPlayer

local lines = {}
local function log(fmt, ...)
    local text = string.format(fmt, ...)
    table.insert(lines, text)
    print("[Probe] " .. text)
end
local function idOf(animation)
    if not animation then return "nil" end
    local ok, value = pcall(function() return animation.AnimationId end)
    return ok and tostring(value) or "?"
end

log("=== WURST DISGUISE PROBE ===")
log("PlaceId=%s CreatorId=%s CreatorType=%s",
    tostring(game.PlaceId), tostring(game.CreatorId),
    tostring(game.CreatorType))
log("LocalPlayer=%s (%s)", LocalPlayer.Name, tostring(LocalPlayer.UserId))

local function getCharacter(player)
    local character = player and player.Character
    if not character then return nil, nil end
    return character, character:FindFirstChildOfClass("Humanoid")
end

local myCharacter, myHumanoid = getCharacter(LocalPlayer)
if not myCharacter or not myHumanoid then
    log("ABORT: local character not ready")
    return
end
log("My rig=%s health=%s", tostring(myHumanoid.RigType),
    tostring(myHumanoid.Health))

-- A. My animation setup -------------------------------------------------------
local myAnimate = myCharacter:FindFirstChild("Animate")
if myAnimate then
    log("My Animate: class=%s Disabled=%s Enabled=%s",
        myAnimate.ClassName,
        tostring((function() local o, v = pcall(function() return myAnimate.Disabled end) return o and v or "n/a" end)()),
        tostring((function() local o, v = pcall(function() return myAnimate.Enabled end) return o and v or "n/a" end)()))
else
    log("My Animate: NONE (this game does not use the standard script!)")
end
local myAnimator = myHumanoid:FindFirstChildOfClass("Animator")
log("My Animator present=%s", tostring(myAnimator ~= nil))
if myAnimator then
    local ok, tracks = pcall(function()
        return myAnimator:GetPlayingAnimationTracks()
    end)
    if ok and tracks then
        log("My playing tracks: %d", #tracks)
        for _, track in ipairs(tracks) do
            log("  mine playing: name=%s id=%s len=%s",
                tostring(track.Name), idOf(track.Animation),
                tostring(track.Length))
        end
    end
end
local myJoints = {}
for _, obj in ipairs(myCharacter:GetDescendants()) do
    if obj:IsA("Motor6D") then myJoints[obj.Name] = obj end
end
local myJointCount = 0
for _ in pairs(myJoints) do myJointCount += 1 end
log("My Motor6D joints: %d", myJointCount)

-- Target selection ------------------------------------------------------------
local wantedId = nil
pcall(function() wantedId = getgenv().WURST_PROBE_TARGET end)
local target, targetCharacter, targetHumanoid = nil, nil, nil
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        local character, humanoid = getCharacter(player)
        if character and humanoid
            and (not wantedId or player.UserId == wantedId) then
            target, targetCharacter, targetHumanoid =
                player, character, humanoid
            break
        end
    end
end
if not target then
    log("ABORT: no other player with a character found in this server")
    log("(join a server with the target in it, or set "
        .. "getgenv().WURST_PROBE_TARGET)")
    return
end
log("Target=%s (%s) rig=%s", target.Name, tostring(target.UserId),
    tostring(targetHumanoid.RigType))

-- B. What the target is really playing --------------------------------------
local CATEGORIES =
    {"idle", "walk", "run", "jump", "fall", "climb", "swim", "swimidle"}
local targetSlotIds = {}
local targetAnimate = targetCharacter:FindFirstChild("Animate")
if targetAnimate then
    for _, category in ipairs(CATEGORIES) do
        local container = targetAnimate:FindFirstChild(category)
        local found = nil
        if container then
            if container:IsA("Animation") then
                found = container
            else
                for _, desc in ipairs(container:GetDescendants()) do
                    if desc:IsA("Animation") then found = desc break end
                end
            end
        end
        targetSlotIds[category] = found and idOf(found) or nil
        log("Target slot %-8s = %s", category,
            targetSlotIds[category] or "none")
    end
else
    log("Target Animate: NONE (custom controller!)")
end
local targetAnimator = targetHumanoid:FindFirstChildOfClass("Animator")
local targetPlayingId = nil
if targetAnimator then
    local ok, tracks = pcall(function()
        return targetAnimator:GetPlayingAnimationTracks()
    end)
    if ok and tracks then
        log("Target playing tracks: %d", #tracks)
        for _, track in ipairs(tracks) do
            log("  target playing: name=%s id=%s len=%s playing=%s",
                tostring(track.Name), idOf(track.Animation),
                tostring(track.Length), tostring(track.IsPlaying))
            if not targetPlayingId and track.Length
                and track.Length > 0 then
                targetPlayingId = idOf(track.Animation)
            end
        end
    end
end
local targetJoints = {}
for _, obj in ipairs(targetCharacter:GetDescendants()) do
    if obj:IsA("Motor6D") then targetJoints[obj.Name] = obj end
end
local shared = {}
for name, joint in pairs(myJoints) do
    if targetJoints[name] then
        table.insert(shared, {ours = joint, theirs = targetJoints[name],
            name = name})
    end
end
log("Shared joints by name: %d", #shared)

-- Their description ids (what the menu fetches when they are NOT here --
-- and also when they are).
pcall(function()
    local description =
        Players:GetHumanoidDescriptionFromUserId(target.UserId)
    if description then
        log("Target description: Idle=%s Walk=%s Run=%s Jump=%s "
            .. "Fall=%s Climb=%s Swim=%s SwimIdle=%s",
            tostring(description.IdleAnimation),
            tostring(description.WalkAnimation),
            tostring(description.RunAnimation),
            tostring(description.JumpAnimation),
            tostring(description.FallAnimation),
            tostring(description.ClimbAnimation),
            tostring(description.SwimAnimation),
            tostring(description.SwimIdleAnimation))
        description:Destroy()
    end
end)

-- C+D. Can that clip load on MY animator, and what is it? --------------------
local probeId = targetPlayingId or targetSlotIds.idle
    or targetSlotIds.walk
if probeId and myAnimator then
    local assetNumber = tonumber(string.match(probeId, "%d+"))
    if assetNumber then
        local ok, info = pcall(function()
            return MarketplaceService:GetProductInfo(
                assetNumber, Enum.InfoType.Asset)
        end)
        if ok and type(info) == "table" then
            local creator = info.CreatorId
            if creator == nil and type(info.Creator) == "table" then
                creator = info.Creator.Id or info.Creator.CreatorTargetId
            end
            log("Clip %s catalog: Name=%q AssetTypeId=%s CreatorId=%s "
                .. "IsPublicDomain=%s",
                probeId, tostring(info.Name),
                tostring(info.AssetTypeId), tostring(creator),
                tostring(info.IsPublicDomain))
        else
            log("Clip %s catalog: GetProductInfo FAILED (%s)",
                probeId, tostring(info))
        end
    end
    log("LoadAnimation test on MY animator with %s ...", probeId)
    local animation = Instance.new("Animation")
    animation.AnimationId = probeId
    local ok, track = pcall(function()
        return myAnimator:LoadAnimation(animation)
    end)
    if ok and track then
        pcall(function() track:Play() end)
        for i = 1, 4 do
            task.wait(0.25)
            log("  after %.2fs: Length=%s IsPlaying=%s",
                i * 0.25, tostring(track.Length),
                tostring(track.IsPlaying))
            if track.Length and track.Length > 0 then break end
        end
        pcall(function() track:Stop() end)
        pcall(function() track:Destroy() end)
    else
        log("  LoadAnimation raised: %s", tostring(track))
    end
    animation:Destroy()
else
    log("No target clip found to load-test")
end

-- E. THE MIRROR TEST -----------------------------------------------------------
-- Exactly what the menu does (pause Animate, stop tracks, copy joint
-- Transforms every frame), instrumented: it samples a shared joint on
-- both bodies and reports the biggest gap and whether OUR pose moved
-- at all -- and re-reads our joint AFTER the copy to catch anything
-- overwriting it later in the frame.
log("Mirror test: 5 seconds. Ask the target to run/jump if you can; "
    .. "walk around yourself too.")
local sampleJoint = shared[1]
for _, pair in ipairs(shared) do
    if pair.name == "Root" or pair.name == "Neck" then
        sampleJoint = pair
    end
end
if sampleJoint and myAnimator then
    log("Sampling joint: %s", sampleJoint.name)
    local wasDisabled = nil
    pcall(function() wasDisabled = myAnimate and myAnimate.Disabled end)
    if myAnimate then
        pcall(function() myAnimate.Disabled = true end)
    end
    local ok, tracks = pcall(function()
        return myAnimator:GetPlayingAnimationTracks()
    end)
    if ok and tracks then
        for _, track in ipairs(tracks) do
            pcall(function() track:Stop(0) end)
        end
    end
    local maxGap, moved = 0, 0
    local firstMine = sampleJoint.ours.Transform
    local connection = RunService.RenderStepped:Connect(function()
        for _, pair in ipairs(shared) do
            pcall(function()
                pair.ours.Transform = pair.theirs.Transform
            end)
        end
    end)
    local deadline = os.clock() + 5
    while os.clock() < deadline do
        task.wait(0.25)
        local mine = sampleJoint.ours.Transform
        local theirsNow = sampleJoint.theirs.Transform
        local gap = (mine.Position - theirsNow.Position).Magnitude
            + math.abs(mine.R00 - theirsNow.R00)
        if gap > maxGap then maxGap = gap end
        moved = math.max(moved,
            (mine.Position - firstMine.Position).Magnitude
            + math.abs(mine.R00 - firstMine.R00))
        -- Re-read a frame later: if our joint no longer matches what
        -- we wrote, something else is driving our body.
        local written = mine
        RunService.RenderStepped:Wait()
        local reread = sampleJoint.ours.Transform
        if (reread.Position - written.Position).Magnitude > 0.01 then
            log("  !! our joint was OVERWRITTEN after the copy "
                .. "(something else drives our body)")
        end
    end
    connection:Disconnect()
    if myAnimate then
        pcall(function()
            myAnimate.Disabled = wasDisabled
        end)
    end
    log("Mirror result: max gap to target=%.3f, our joint moved=%.3f",
        maxGap, moved)
    if moved < 0.01 then
        log("VERDICT: mirror did NOT move our body "
            .. "(joints paired=%d, Animate found=%s)",
            #shared, tostring(myAnimate ~= nil))
    elseif maxGap < 0.05 then
        log("VERDICT: mirror WORKS -- our pose follows the target")
    else
        log("VERDICT: mirror moves us but does not track the target "
            .. "(gap %.3f) -- the game drives our body its own way", maxGap)
    end
else
    log("Mirror test skipped: shared joints=%d animator=%s",
        #shared, tostring(myAnimator ~= nil))
end

log("=== END OF PROBE ===")
local report = table.concat(lines, "\n")
pcall(function()
    if writefile then
        writefile("WurstDisguiseProbe.txt", report)
        print("[Probe] written to WurstDisguiseProbe.txt")
    end
end)
pcall(function()
    if setclipboard then
        setclipboard(report)
        print("[Probe] report copied to your clipboard -- paste it back")
    end
end)
