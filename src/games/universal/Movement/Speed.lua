export type Runtime = {framework: any, entity: any, host: any, services: any}

local Module = {Name = "Speed", PlaceId = 0, Events = {} :: {[string]: any}, Initialized = false}
local activeCleanup

function Module.init(context: Runtime): any
    local host, framework = context.host, context.framework
    local player, world = host.LocalPlayer, host.workspace or workspace
    local walk, vehicle, speed
    local teleportElapsed, lastMode = 0, nil

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
        if walk.applied and humanoid.WalkSpeed ~= walk.applied then walk.base = humanoid.WalkSpeed end
        -- Negative WalkSpeed inverts controls (Roblox legacy behavior)
        humanoid.WalkSpeed = value
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
    local function write(record, object, property, value)
        local field = record[property]
        if not field then field = {base=object[property]}; record[property] = field end
        if field.applied ~= nil and object[property] ~= field.applied then field.base = object[property] end
        object[property], field.applied = value, value
    end
    local function restoreRecord(object, record)
        if not object.Parent then return end
        for property, field in pairs(record) do
            if object[property] == field.applied then object[property] = field.base end
        end
    end
    local function restoreVehicle()
        if not vehicle then return end
        if vehicle.connection then vehicle.connection:Disconnect() end
        for object, record in pairs(vehicle.properties) do restoreRecord(object,record) end
        vehicle = nil
    end
    local function resolveVehicle(humanoid, character)
        local seat = humanoid.SeatPart
        -- Passengers and characters standing on an assembly are not drivers.
        if not seat or not seat:IsA("VehicleSeat") or seat.Occupant ~= humanoid then return end
        local assembly = seat.AssemblyRootPart or seat
        if assembly:IsDescendantOf(character) then assembly = seat end
        if assembly.Anchored then return end
        local model = seat:FindFirstAncestorOfClass("Model")
        while model and not assembly:IsDescendantOf(model) do model = model:FindFirstAncestorOfClass("Model") end
        return seat, assembly, model
    end
    local function vehicleStep(humanoid, character)
        local seat, assembly, model = resolveVehicle(humanoid,character)
        if not seat then restoreVehicle(); return false end
        local opts, mode = speed.Options, speed.Options["Vehicle mode"].Value
        if vehicle and (vehicle.seat ~= seat or vehicle.model ~= model or vehicle.mode ~= mode or vehicle.assembly ~= assembly) then restoreVehicle() end
        if not vehicle then vehicle = {seat=seat,assembly=assembly,model=model,mode=mode,properties={}} end
        local function record(object)
            vehicle.properties[object] = vehicle.properties[object] or {}
            return vehicle.properties[object]
        end
        local multiplier = opts["Vehicle multiplier"].Value
        if mode == "Multiplier" then
            local captured = record(seat)
            local baseSpeed = captured.MaxSpeed and captured.MaxSpeed.base or seat.MaxSpeed
            local baseTorque = captured.Torque and captured.Torque.base or seat.Torque
            if captured.MaxSpeed and seat.MaxSpeed ~= captured.MaxSpeed.applied then baseSpeed = seat.MaxSpeed end
            if captured.Torque and seat.Torque ~= captured.Torque.applied then baseTorque = seat.Torque end
            write(captured,seat,"MaxSpeed",baseSpeed*multiplier)
            write(captured,seat,"Torque",baseTorque*multiplier)
        elseif mode == "Seat" then
            write(record(seat),seat,"MaxSpeed",opts["Vehicle speed value"].Value)
        elseif mode == "Velocity" then
            local throttle = math.clamp(seat.ThrottleFloat,-1,1)
            if math.abs(throttle) > 0.01 then
                local look = seat.CFrame.LookVector
                local flat = Vector3.new(look.X,0,look.Z)
                if flat.Magnitude > 0.001 then
                    local current = assembly.AssemblyLinearVelocity
                    local horizontal = flat.Unit * (opts["Vehicle speed value"].Value*throttle)
                    assembly.AssemblyLinearVelocity = Vector3.new(horizontal.X,current.Y,horizontal.Z)
                end
            end
        elseif mode == "Motors" and model then
            -- Discover once per vehicle. Newly added wheel motors are picked up
            -- by DescendantAdded, not by scanning the whole car every frame.
            if not vehicle.motors then
                vehicle.motors = {}
                local owner = vehicle
                local function discover(object)
                    if object:IsA("HingeConstraint") and object.ActuatorType == Enum.ActuatorType.Motor then owner.motors[object] = true end
                end
                for _, object in ipairs(model:GetDescendants()) do discover(object) end
                owner.connection = model.DescendantAdded:Connect(discover)
            end
            for motor in pairs(vehicle.motors) do
                if not motor.Parent or not motor:IsDescendantOf(model) or motor.ActuatorType ~= Enum.ActuatorType.Motor then
                    if vehicle.properties[motor] then restoreRecord(motor,vehicle.properties[motor]) end
                    vehicle.properties[motor], vehicle.motors[motor] = nil, nil
                    continue
                end
                local captured = record(motor)
                local angular = captured.AngularVelocity
                local base = angular and angular.base or motor.AngularVelocity
                if angular and motor.AngularVelocity ~= angular.applied then base = motor.AngularVelocity end
                if math.abs(seat.ThrottleFloat) < 0.01 then base = 0 end
                -- Store the controller's latest command, never multiply our
                -- previous write. Zero and reverse commands remain meaningful.
                if angular then angular.base = base end
                write(captured,motor,"AngularVelocity",base*multiplier)
                captured.AngularVelocity.base = base
                local torque = captured.MotorMaxTorque
                local baseTorque = torque and torque.base or motor.MotorMaxTorque
                if torque and motor.MotorMaxTorque ~= torque.applied then baseTorque = motor.MotorMaxTorque end
                write(captured,motor,"MotorMaxTorque",math.max(baseTorque,opts["Motor torque"].Value))
            end
        end
        return true
    end
    local function direction(humanoid)
        local move = humanoid.MoveDirection
        local flat = Vector3.new(move.X,0,move.Z)
        return flat.Magnitude > 1 and flat.Unit or flat
    end
    local function blocked(root, step)
        if step.Magnitude < 0.001 then return step end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {player.Character}
        params.RespectCanCollide, params.IgnoreWater = true, true
        params.CollisionGroup = root.CollisionGroup
        if world.Blockcast then
            local hit = world:Blockcast(root.CFrame,root.Size*0.9,step,params)
            return hit and step.Unit*math.max(0,hit.Distance-0.1) or step
        end
        local hit = world:Raycast(root.Position,step,params)
        return hit and step.Unit*math.max(0,(hit.Position-root.Position).Magnitude-root.Size.Magnitude*0.5-0.1) or step
    end
    local function stepSpeed(dt)
        local character, humanoid, root = parts()
        if not humanoid or not root or humanoid.Health <= 0 then
            restoreWalk(); restoreVehicle()
            if speed.ClearSprint then speed.ClearSprint() end
            return
        end
        if not speed.Enabled and not speed.SprintHeld then restoreWalk(); restoreVehicle(); return end
        local seated = humanoid.SeatPart ~= nil or humanoid.Sit
        if speed.SprintFrame then speed.SprintFrame(speed.SprintHeld and not seated,root) end
        if seated then
            restoreWalk()
            if speed.Enabled and speed.Options["Vehicle speed"].Value then vehicleStep(humanoid,character) else restoreVehicle() end
            return
        end
        restoreVehicle()
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
        Tooltip="On-foot movement and driver-only vehicle controls.",
        Function=function(enabled)
            restoreWalk(); restoreVehicle(); teleportElapsed, lastMode = 0, nil
            if not enabled then
                if speed.ClearSprint then speed.ClearSprint() end
                speed:SetStatus(nil)
                if speed.SprintHeld then stepSpeed(0) end
                return
            end
            speed:Clean(function() restoreWalk(); restoreVehicle(); if speed.ClearSprint then speed.ClearSprint() end end)
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
        restoreWalk(); restoreVehicle(); teleportElapsed, lastMode = 0, nil
        if speed.Enabled then speed:SetStatus(speed.Options.Mode.Value) end
    end
    speed:CreateDropdown({Name="Mode",List={"WalkSpeed","Velocity","Impulse","CFrame","Teleport"},Index=1,Function=changed})
    speed:CreateSlider({Name="Speed",Min=1,Max=250,Default=32})
    speed:CreateToggle({Name="Wall check",Default=true,Show={Option="Mode",Values={"CFrame","Teleport"}}})
    speed:CreateSlider({Name="Burst delay",Min=0.05,Max=1,Default=0.2,Show={Option="Mode",Values={"Teleport"}}})
    speed:CreateToggle({Name="Auto jump",Default=false})
    speed:CreateToggle({Name="Vehicle speed",Default=false,Function=changed,
        Tooltip="Only the occupied driver VehicleSeat; never passengers or platforms."})
    speed:CreateDropdown({Name="Vehicle mode",List={"Multiplier","Motors","Velocity","Seat"},Index=1,Function=changed,
        Show={Option="Vehicle speed",Values={true}},
        Tooltip="Multiplier: native seat engine. Motors: active hinge controller. Velocity: throttle-directed chassis speed. Seat: absolute native speed limit."})
    speed:CreateSlider({Name="Vehicle multiplier",Min=1,Max=10,Default=2,Function=changed,
        Show={{Option="Vehicle speed",Values={true}},{Option="Vehicle mode",Values={"Multiplier","Motors"}}}})
    speed:CreateSlider({Name="Vehicle speed value",Min=1,Max=300,Default=80,
        Show={{Option="Vehicle speed",Values={true}},{Option="Vehicle mode",Values={"Velocity","Seat"}}},
        Tooltip="Vehicle speed in studs per second, independent of on-foot Speed."})
    speed:CreateSlider({Name="Motor torque",Min=1000,Max=250000,Default=50000,
        Show={{Option="Vehicle speed",Values={true}},{Option="Vehicle mode",Values={"Motors"}}}})
    speed:RefreshVisibility()
    activeCleanup = function()
        speed.SprintHeld = false
        if speed.Enabled then speed:Toggle(false) end
        restoreWalk(); restoreVehicle()
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
