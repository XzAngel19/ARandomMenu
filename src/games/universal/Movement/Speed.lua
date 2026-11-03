export type Runtime = {framework: any, entity: any, host: any, services: any}

local Module = {Name = "Speed", PlaceId = 0, Events = {} :: {[string]: any}, Initialized = false}
local activeCleanup

function Module.init(context: Runtime): any
    local host, framework = context.host, context.framework
    local player, world = host.LocalPlayer, host.workspace or workspace
    local walk, speed
    local teleportElapsed, lastMode = 0, nil
    local wallParams, wallCharacter, wallGroup

    local function clearWallFilter()
        if wallParams then wallParams.FilterDescendantsInstances = {} end
        wallCharacter = nil
    end

    local function parts()
        local character = player.Character
        return character, character and character:FindFirstChildOfClass("Humanoid"),
            character and character:FindFirstChild("HumanoidRootPart")
    end
    local function restoreWalk()
        if walk then
            if walk.humanoid.Parent and walk.humanoid.WalkSpeed == walk.applied then walk.humanoid.WalkSpeed = walk.base end
            walk = nil
        end
    end
    local function applyWalk(humanoid, value)
        if walk and walk.humanoid ~= humanoid then restoreWalk() end
        if not walk then walk = {humanoid=humanoid,base=humanoid.WalkSpeed} end
        local current = humanoid.WalkSpeed
        if walk.applied ~= nil and current ~= walk.applied then walk.base = current end
        -- Negative WalkSpeed inverts controls (Roblox legacy behavior)
        if current ~= value then humanoid.WalkSpeed = value end
        walk.applied = value
        -- When WalkSpeed is negative, invert the move direction by setting
        -- the Humanoid's MoveDirection opposite to input
        if value < 0 then
            local moveDir = humanoid.MoveDirection
            if moveDir and moveDir.Magnitude > 0.01 and type(humanoid.Move) == "function" then
                humanoid:Move(-moveDir, false)
            end
        end
    end
    local function direction(humanoid)
        local move = humanoid.MoveDirection
        local flat = Vector3.new(move.X,0,move.Z)
        return flat.Magnitude > 1 and flat.Unit or flat
    end
    local function blocked(root, step)
        if step.Magnitude < 0.001 then return step end
        if not wallParams then
            wallParams = RaycastParams.new()
            wallParams.FilterType = Enum.RaycastFilterType.Exclude
            wallParams.RespectCanCollide, wallParams.IgnoreWater = true, true
        end
        if wallCharacter ~= player.Character then
            wallCharacter = player.Character
            wallParams.FilterDescendantsInstances = player.Character and {player.Character} or {}
        end
        if wallGroup ~= root.CollisionGroup then
            wallGroup = root.CollisionGroup
            wallParams.CollisionGroup = wallGroup
        end
        if world.Blockcast then
            local hit = world:Blockcast(root.CFrame,root.Size*0.9,step,wallParams)
            return hit and step.Unit*math.max(0,hit.Distance-0.1) or step
        end
        local hit = world:Raycast(root.Position,step,wallParams)
        return hit and step.Unit*math.max(0,(hit.Position-root.Position).Magnitude-root.Size.Magnitude*0.5-0.1) or step
    end
    local function stepSpeed(dt)
        local _, humanoid, root = parts()
        if not humanoid or not root or humanoid.Health <= 0 then
            restoreWalk()
            if speed.ClearSprint then speed.ClearSprint() end
            return
        end
        if not speed.Enabled and not speed.SprintHeld then restoreWalk(); return end
        local seated = humanoid.SeatPart ~= nil or humanoid.Sit
        if speed.SprintFrame then speed.SprintFrame(speed.SprintHeld and not seated,root) end
        if seated then restoreWalk(); return end
        local fly = framework.GetModule and framework:GetModule("Fly")
        local state = humanoid:GetState()
        if root.Anchored or (fly and fly.Enabled) or state == Enum.HumanoidStateType.Climbing
            or state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Physics
            or state == Enum.HumanoidStateType.PlatformStanding then restoreWalk(); return end
        local opts = speed.Options
        local mode = speed.Enabled and opts.Mode.Value or "WalkSpeed"
        local target = speed.Enabled and opts.Speed.Value or 0
        if speed.SprintHeld then target = math.max(target,30) end
        if mode ~= lastMode then restoreWalk(); teleportElapsed = 0; lastMode = mode end
        if mode == "WalkSpeed" then applyWalk(humanoid,target) else restoreWalk() end
        local move = direction(humanoid)
        if speed.Enabled and opts["Auto jump"].Value and move.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        if mode == "WalkSpeed" and target >= 0 then return end
        local velocity = root.AssemblyLinearVelocity
        if mode == "Velocity" or (mode == "WalkSpeed" and target < 0) then
            root.AssemblyLinearVelocity = Vector3.new(move.X*target,velocity.Y,move.Z*target)
        elseif mode == "Impulse" then
            local difference = Vector3.new(move.X*target-velocity.X,0,move.Z*target-velocity.Z)
            if difference.Magnitude > 0.001 then root:ApplyImpulse(difference*root.AssemblyMass) end
        elseif move.Magnitude > 0.001 then
            local elapsed = math.clamp(dt or 0,0,0.1)
            if mode == "Teleport" then
                teleportElapsed += elapsed
                local interval = opts["Burst delay"].Value
                if teleportElapsed < interval then return end
                teleportElapsed %= interval
                elapsed = interval
            end
            local speedDelta = target < 0 and (target - humanoid.WalkSpeed) or math.max(0, target - humanoid.WalkSpeed)
            local step = move * speedDelta * elapsed
            if opts["Wall check"].Value then step = blocked(root,step) end
            root.CFrame += step
        else teleportElapsed = 0 end
    end
    speed = framework.Categories.Exploits:CreateModule({
        Name="Speed",Category="Exploits",ConfigKey="Universal.Speed",Order=1,
        Tooltip="On-foot movement; inactive while seated.",
        Function=function(enabled)
            restoreWalk(); teleportElapsed, lastMode = 0, nil
            if not enabled then
                clearWallFilter()
                if speed.ClearSprint then speed.ClearSprint() end
                speed:SetStatus(nil)
                if speed.SprintHeld then stepSpeed(0) end
                return
            end
            speed:Clean(function() restoreWalk(); if speed.ClearSprint then speed.ClearSprint() end end)
            speed:Clean(host.RunService.PreSimulation:Connect(stepSpeed))
            speed:SetStatus(speed.Options.Mode.Value)
        end,
    })
    speed.SprintHeld = false
    speed.SetSprintHeld = function(held)
        speed.SprintHeld = held
        stepSpeed(0)
        if not held and speed.ClearSprint then speed.ClearSprint() end
    end
    speed.StepSprint = function(dt) if speed.SprintHeld and not speed.Enabled then stepSpeed(dt) end end
    local function changed()
        restoreWalk(); teleportElapsed, lastMode = 0, nil
        if speed.Enabled then speed:SetStatus(speed.Options.Mode.Value) end
    end
    speed:CreateDropdown({Name="Mode",List={"WalkSpeed","Velocity","Impulse","CFrame","Teleport"},Index=2,Function=changed})
    speed:CreateSlider({Name="Speed",Min=1,Max=250,Default=32})
    speed:CreateToggle({Name="Wall check",Default=true,Show={Option="Mode",Values={"CFrame","Teleport"}}})
    speed:CreateSlider({Name="Burst delay",Min=0.05,Max=1,Default=0.2,Show={Option="Mode",Values={"Teleport"}}})
    speed:CreateToggle({Name="Auto jump",Default=false})
    speed:RefreshVisibility()
    activeCleanup = function()
        speed.SprintHeld = false
        if speed.Enabled then speed:Toggle(false) end
        restoreWalk(); clearWallFilter()
        if speed.ClearSprint then speed.ClearSprint() end
    end
    Module.Initialized = true
    return speed
end
function Module.destroy()
    if activeCleanup then activeCleanup(); activeCleanup = nil end
    Module.Initialized = false
end
return Module
