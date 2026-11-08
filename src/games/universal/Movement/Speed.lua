export type Runtime = {framework: any, entity: any, host: any, services: any}

local Module = {Name = "Speed Settings", PlaceId = 0, Events = {} :: {[string]: any}, Initialized = false}
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
        if current ~= value then humanoid.WalkSpeed = value end
        walk.applied = value
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
        local opts = speed.Options
        local mode = speed.Enabled and opts.Mode.Value or "WalkSpeed"
        local target = speed.Enabled and opts.Speed.Value or 0
        if speed.SprintHeld then target = math.max(target,30) end
        if mode ~= lastMode then restoreWalk(); teleportElapsed = 0; lastMode = mode end

        -- Vehicle handling: Velocity/Impulse/CFrame/Teleport work in any vehicle/seat
        local seat: any = humanoid.SeatPart
        local isSeated: boolean = seat ~= nil or humanoid.Sit
        if isSeated then
            if speed.SprintFrame then speed.SprintFrame(speed.SprintHeld and false, root) end
            -- WalkSpeed cannot drive a vehicle
            if mode == "WalkSpeed" then restoreWalk(); return end
            local vehicle: any = seat
            -- Fallback: if SeatPart is Vehicleseat but root is still character, try seat parent
            if not vehicle or not vehicle.Parent then restoreWalk(); return end
            -- Prevent affecting WalkSpeed while seated
            restoreWalk()
            local fly = framework.GetModule and framework:GetModule("Fly")
            if vehicle.Anchored or (fly and fly.Enabled) then return end
            local move = direction(humanoid)
            -- Apply vehicle multiplier
            local vehicleMul: number = opts["Vehicle multiplier"] and opts["Vehicle multiplier"].Value or 1.2
            local vehicleTarget: number = target * vehicleMul
            local response: number = opts["Response"] and opts["Response"].Value or 1
            local keepY: boolean = opts["Keep vertical"] == nil or opts["Keep vertical"].Value
            if mode == "Velocity" or (mode == "WalkSpeed" and target < 0) then
                local vel: Vector3 = vehicle.AssemblyLinearVelocity
                local targetVel: Vector3 = Vector3.new(move.X*vehicleTarget, keepY and vel.Y or 0, move.Z*vehicleTarget)
                if response >= 1 then
                    vehicle.AssemblyLinearVelocity = targetVel
                else
                    -- Smooth response: lerp
                    local lerpAlpha: number = math.clamp(response * (dt or 1/60) * 12, 0, 1)
                    local curXZ: Vector3 = Vector3.new(vel.X, 0, vel.Z)
                    local tarXZ: Vector3 = Vector3.new(targetVel.X, 0, targetVel.Z)
                    local newXZ: Vector3 = Vector3.new(curXZ.X + (tarXZ.X - curXZ.X) * lerpAlpha, 0, curXZ.Z + (tarXZ.Z - curXZ.Z) * lerpAlpha)
                    vehicle.AssemblyLinearVelocity = Vector3.new(newXZ.X, targetVel.Y, newXZ.Z)
                    if move.Magnitude < 0.01 then
                        -- Braking when no input
                        local brake: number = opts["Braking"] and opts["Braking"].Value or 0.8
                        if brake < 0.99 then
                            local brakeAlpha: number = math.clamp((1-brake) * (dt or 1/60) * 10, 0, 1)
                            local curV: Vector3 = vehicle.AssemblyLinearVelocity
                            vehicle.AssemblyLinearVelocity = Vector3.new(curV.X * (1-brakeAlpha), curV.Y, curV.Z * (1-brakeAlpha))
                            if vehicle.AssemblyLinearVelocity.Magnitude < 0.5 then vehicle.AssemblyLinearVelocity = Vector3.new(0, curV.Y, 0) end
                        end
                    end
                end
            elseif mode == "Impulse" then
                local vel: Vector3 = vehicle.AssemblyLinearVelocity
                local targetVelXZ: Vector3 = Vector3.new(move.X*vehicleTarget, 0, move.Z*vehicleTarget)
                local diff: Vector3 = Vector3.new(targetVelXZ.X - vel.X, 0, targetVelXZ.Z - vel.Z)
                -- Response scales impulse
                diff *= math.clamp(response, 0.2, 2)
                if diff.Magnitude > 0.001 then vehicle:ApplyImpulse(diff * vehicle.AssemblyMass) end
            elseif move.Magnitude > 0.001 then
                local elapsed = math.clamp(dt or 0,0,0.1)
                if mode == "Teleport" then
                    teleportElapsed += elapsed
                    local interval = opts["Burst delay"].Value
                    if teleportElapsed < interval then return end
                    teleportElapsed %= interval
                    elapsed = interval
                end
                local step = move * vehicleTarget * elapsed
                if opts["Wall check"].Value then step = blocked(vehicle, step) end
                -- Move vehicle, not character
                vehicle.CFrame += step
                -- Also move character root to stay with vehicle
                if root and root.Parent then
                    root.CFrame = vehicle.CFrame * CFrame.new(0, 2, 0)
                end
            else teleportElapsed = 0 end
            if speed.Enabled and opts["Auto jump"].Value and move.Magnitude > 0.05 then
                -- Auto jump not applicable while seated
            end
            return
        end
        -- On-foot handling
        if speed.SprintFrame then speed.SprintFrame(speed.SprintHeld and not isSeated,root) end
        local fly = framework.GetModule and framework:GetModule("Fly")
        local state = humanoid:GetState()
        if root.Anchored or (fly and fly.Enabled) or state == Enum.HumanoidStateType.Climbing
            or state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Physics
            or state == Enum.HumanoidStateType.PlatformStanding then restoreWalk(); return end
        if mode == "WalkSpeed" then applyWalk(humanoid,target) else restoreWalk() end
        local move = direction(humanoid)
        if speed.Enabled and opts["Auto jump"].Value and move.Magnitude > 0.05 and humanoid.FloorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        if mode == "WalkSpeed" and target >= 0 then return end
        local velocity = root.AssemblyLinearVelocity
        local response: number = opts["Response"] and opts["Response"].Value or 1
        local keepY: boolean = opts["Keep vertical"] == nil or opts["Keep vertical"].Value
        local braking: number = opts["Braking"] and opts["Braking"].Value or 0.8
        if mode == "Velocity" or (mode == "WalkSpeed" and target < 0) then
            local targetVel: Vector3 = Vector3.new(move.X*target, keepY and velocity.Y or 0, move.Z*target)
            if response >= 1 or move.Magnitude < 0.01 and braking >= 0.99 then
                root.AssemblyLinearVelocity = targetVel
            else
                local lerpAlpha: number = math.clamp(response * (dt or 1/60) * 12, 0, 1)
                local curXZ: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
                local tarXZ: Vector3 = Vector3.new(targetVel.X, 0, targetVel.Z)
                local newXZ: Vector3 = Vector3.new(curXZ.X + (tarXZ.X - curXZ.X) * lerpAlpha, 0, curXZ.Z + (tarXZ.Z - curXZ.Z) * lerpAlpha)
                root.AssemblyLinearVelocity = Vector3.new(newXZ.X, keepY and velocity.Y or targetVel.Y, newXZ.Z)
                if move.Magnitude < 0.01 then
                    if braking < 0.99 then
                        local brakeAlpha: number = math.clamp((1-braking) * (dt or 1/60) * 10, 0, 1)
                        local curV: Vector3 = root.AssemblyLinearVelocity
                        root.AssemblyLinearVelocity = Vector3.new(curV.X * (1-brakeAlpha), curV.Y, curV.Z * (1-brakeAlpha))
                        if root.AssemblyLinearVelocity.Magnitude < 0.5 and keepY then root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
                        elseif root.AssemblyLinearVelocity.Magnitude < 0.5 then root.AssemblyLinearVelocity = Vector3.zero end
                    end
                end
            end
        elseif mode == "Impulse" then
            local diff = Vector3.new(move.X*target-velocity.X,0,move.Z*target-velocity.Z)
            diff *= math.clamp(response, 0.2, 2)
            if diff.Magnitude > 0.001 then root:ApplyImpulse(diff*root.AssemblyMass) end
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
            -- Response scales CFrame step
            step *= math.clamp(response, 0.5, 2)
            if opts["Wall check"].Value then step = blocked(root,step) end
            root.CFrame += step
        else teleportElapsed = 0 end
    end
    speed = framework.Categories.Exploits:CreateModule({
        Name="Speed Settings",Category="Exploits",ConfigKey="Universal.Speed",Order=1,
        Tooltip="Movement with full vehicle support. WalkSpeed on foot only; Velocity/Impulse/CFrame/Teleport work in any vehicle or object using velocity.",
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
    speed:CreateSlider({Name="Speed",Min=1,Max=250,Default=32, Tooltip="Speed in studs/s. WalkSpeed sets Humanoid.WalkSpeed, Velocity/Impulse drive AssemblyLinearVelocity, CFrame/Teleport move CFrame."})
    speed:CreateSlider({Name="Response",Min=0.2,Max=2,Step=0.1,Default=1, Show={Option="Mode",Values={"Velocity","Impulse","CFrame"}}, Tooltip="Response: how fast velocity reaches target. 0.2 sluggish, 1 default balanced, 2 instant."})
    speed:CreateSlider({Name="Braking",Min=0,Max=1,Step=0.05,Default=0.8, Show={Option="Mode",Values={"Velocity"}}, Tooltip="Braking when no input: 0 = instant stop, 0.8 default smooth, 1 = keep momentum."})
    speed:CreateSlider({Name="Vehicle multiplier",Min=0.5,Max=3,Step=0.1,Default=1.2, Tooltip="Scales Speed when in a vehicle/seat (Velocity/Impulse/CFrame/Teleport only). 1 = same as on foot, 1.2 default slightly faster in vehicle."})
    speed:CreateToggle({Name="Keep vertical",Default=true, Show={Option="Mode",Values={"Velocity","Impulse"}}, Tooltip="Preserve Y velocity (gravity/jump). OFF = full 3D velocity control (also affects vehicles)."})
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
