--[[
    WURST DISGUISE PROBE 2 -- "what are this rig's joints, really?"

    Probe 1 proved the menu's core assumption wrong: in MM2 your
    character has ZERO Motor6D descendants, so the pose mirror paired
    nothing and silently gave up -- and the target's clips actually
    LOAD fine (Length > 0) because these are new-style animation
    assets. Before the menu is touched again, this probe maps the
    real joint structure of both characters:

      A. A census of EVERY descendant class in your character and
         the target's (class name -> count).
      B. For each joint-like class found (Motor6D, Motor,
         AnimationConstraint, Bone, Weld, WeldConstraint): every
         instance's name, parent, and whether a readable/writable
         Transform (or C0/C1) exists.
      C. A write test: nudging one of YOUR joints and reading it
         back, to learn whether pose copying is even possible on
         this rig, and through which property.
      D. Whether pausing your Animate works via Enabled (LocalScript)
         vs Disabled -- probe 1 showed Disabled does not exist here.

    Run inside MM2 with the target in the same server. Takes ~4
    seconds. Report is printed, written to WurstDisguiseProbe2.txt
    and copied to the clipboard.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local lines = {}
local function log(fmt, ...)
    local text = string.format(fmt, ...)
    table.insert(lines, text)
    print("[Probe2] " .. text)
end

log("=== WURST DISGUISE PROBE 2: JOINT CENSUS ===")
log("PlaceId=%s LocalPlayer=%s", tostring(game.PlaceId), LocalPlayer.Name)

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
local target, targetCharacter, targetHumanoid = nil, nil, nil
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        local character, humanoid = getCharacter(player)
        if character and humanoid then
            target, targetCharacter, targetHumanoid =
                player, character, humanoid
            break
        end
    end
end
log("Me: rig=%s | Target: %s rig=%s",
    tostring(myHumanoid.RigType),
    target and target.Name or "NONE",
    targetHumanoid and tostring(targetHumanoid.RigType) or "-")

-- A. Class census ---------------------------------------------------------------
local function census(character, label)
    local counts = {}
    local total = 0
    for _, obj in ipairs(character:GetDescendants()) do
        counts[obj.ClassName] = (counts[obj.ClassName] or 0) + 1
        total += 1
    end
    local names = {}
    for className in pairs(counts) do
        table.insert(names, className)
    end
    table.sort(names)
    log("%s census (%d descendants):", label, total)
    for _, className in ipairs(names) do
        log("  %-28s x%d", className, counts[className])
    end
    return counts
end
census(myCharacter, "MY character")
if targetCharacter then
    census(targetCharacter, "TARGET character")
end

-- B. Joint-like classes in detail ------------------------------------------------
local JOINT_CLASSES = {
    Motor6D = true, Motor = true, AnimationConstraint = true,
    Bone = true, Weld = true, WeldConstraint = true,
}
local function jointDetails(character, label)
    log("%s joint-like instances:", label)
    local found = 0
    for _, obj in ipairs(character:GetDescendants()) do
        if JOINT_CLASSES[obj.ClassName] then
            found += 1
            local hasTransform, transformType = false, "-"
            pcall(function()
                local value = obj.Transform
                hasTransform = value ~= nil
                transformType = typeof(value)
            end)
            local parentName = obj.Parent and obj.Parent.Name or "nil"
            log("  %s %q parent=%s Transform=%s(%s)",
                obj.ClassName, obj.Name, parentName,
                tostring(hasTransform), transformType)
        end
    end
    if found == 0 then
        log("  (none at all)")
    end
    return found
end
local myJointTotal = jointDetails(myCharacter, "MY")

-- Body-part children: what actually lives inside UpperTorso / Head?
for _, partName in ipairs(
    {"UpperTorso", "LowerTorso", "Head", "HumanoidRootPart", "Torso"}
) do
    local part = myCharacter:FindFirstChild(partName)
    if part then
        local kids = {}
        for _, child in ipairs(part:GetChildren()) do
            table.insert(kids,
                child.ClassName .. ":" .. child.Name)
        end
        log("Children of my %s: %s", partName,
            #kids > 0 and table.concat(kids, ", ") or "(none)")
    end
end

-- C. Write test on one of my joints ---------------------------------------------
local testJoint = nil
for _, obj in ipairs(myCharacter:GetDescendants()) do
    if JOINT_CLASSES[obj.ClassName] then
        local ok = pcall(function() return obj.Transform end)
        if ok then
            testJoint = obj
            break
        end
    end
end
if testJoint then
    local before = nil
    pcall(function() before = testJoint.Transform end)
    local wrote = false
    if before then
        local nudged = before * CFrame.Angles(0.35, 0, 0)
        wrote = pcall(function() testJoint.Transform = nudged end)
        local after = nil
        pcall(function() after = testJoint.Transform end)
        if wrote and after then
            local delta = (after.Position - before.Position).Magnitude
                + math.abs(after.R00 - before.R00)
            log("Write test on my %s %q: wrote=%s deltaAfterWrite=%.3f "
                .. "(>0 means Transform is writable)",
                testJoint.ClassName, testJoint.Name,
                tostring(wrote), delta)
            pcall(function() testJoint.Transform = before end)
        else
            log("Write test on my %s %q: wrote=%s (readback failed)",
                testJoint.ClassName, testJoint.Name, tostring(wrote))
        end
        -- Does something overwrite it a frame later?
        task.wait(0.3)
        local later = nil
        pcall(function() later = testJoint.Transform end)
        if later and before then
            local drift = (later.Position - before.Position).Magnitude
                + math.abs(later.R00 - before.R00)
            log("Same joint 0.3s later vs original: drift=%.3f "
                .. "(large = my own animation keeps driving it)",
                drift)
        end
    end
else
    log("Write test skipped: no joint with a readable Transform "
        .. "(joint-like total=%d)", myJointTotal)
end

-- D. Pausing my Animate: Enabled vs Disabled --------------------------------------
local myAnimate = myCharacter:FindFirstChild("Animate")
if myAnimate then
    local canReadEnabled, enabledNow = pcall(function()
        return myAnimate.Enabled
    end)
    local canReadDisabled, disabledNow = pcall(function()
        return (myAnimate :: any).Disabled
    end)
    log("My Animate class=%s Enabled readable=%s(%s) "
        .. "Disabled readable=%s(%s)",
        myAnimate.ClassName,
        tostring(canReadEnabled), tostring(enabledNow),
        tostring(canReadDisabled), tostring(disabledNow))
    if canReadEnabled then
        pcall(function() myAnimate.Enabled = false end)
        task.wait(0.2)
        local afterOk, afterValue = pcall(function()
            return myAnimate.Enabled
        end)
        log("  set Enabled=false -> now %s (script paused=%s)",
            tostring(afterOk and afterValue),
            tostring(afterOk and afterValue == false))
        pcall(function() myAnimate.Enabled = true end)
    end
else
    log("My Animate: NONE")
end

log("=== END OF PROBE 2 ===")
local report = table.concat(lines, "\n")
pcall(function()
    if writefile then
        writefile("WurstDisguiseProbe2.txt", report)
        print("[Probe2] written to WurstDisguiseProbe2.txt")
    end
end)
pcall(function()
    if setclipboard then
        setclipboard(report)
        print("[Probe2] report copied to clipboard -- paste it back")
    end
end)
