export type Runtime = {framework: any, entity: any, host: any, services: any}

local Module = {Name = "Target Strafe", PlaceId = 0, Events = {} :: {[string]: any}, Initialized = false}
local activeCleanup

function Module.init(context: Runtime): any
    local host, framework = context.host, context.framework
    local player = host.LocalPlayer
    local UserInputService = host.UserInputService or game:GetService("UserInputService")
    local RunService = host.RunService or game:GetService("RunService")
    
    local settings = {
        radius = 5,
        speed = 100,
        mode = "Circle",
        smartDodge = true,
    }
    
    local targetStrafe
    local lastTarget: Model? = nil

    local function getTarget(): Model?
        -- Find the nearest enemy within range using the targeting system
        local targeting = state.targeting
        if not targeting or type(targeting.getNearest) ~= "function" then
            return nil
        end
        local result = targeting.getNearest({
            maxDistance = 100,
            teamCheck = true,
            wallCheck = false,
            aliveOnly = true,
        })
        return result and result.character or nil
    end

    local function toggleTargetStrafe(enabled)
        if not enabled then
            lastTarget = nil
            return
        end
        
        targetStrafe:Clean(RunService.PreSimulation:Connect(function(dt)
            local character = player.Character
            if not character then return end
            
            local root = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChild("Humanoid")
            if not root or not humanoid or humanoid.Health <= 0 then return end

            local target = getTarget()
            if not target or not target.Parent then
                lastTarget = nil
                return
            end

            local targetRoot = target:FindFirstChild("HumanoidRootPart")
            if not targetRoot then return end

            lastTarget = target
            local targetPos = targetRoot.Position
            local myPos = root.Position
            
            -- Calculate vector from target to us
            local toMe = myPos - targetPos
            local horizontal = Vector3.new(toMe.X, 0, toMe.Z)
            
            if horizontal.Magnitude < 0.1 then
                -- We're on top of the target, pick a random direction
                horizontal = Vector3.new(1, 0, 0)
            end
            
            local distance = horizontal.Magnitude
            local direction = horizontal.Unit
            
            -- Strafe mode: move in a circle around the target
            local moveVector: Vector3
            if settings.mode == "Circle" then
                -- Perpendicular to the direction to target (circular motion)
                local perp = Vector3.new(-direction.Z, 0, direction.X)
                -- Adjust radius to maintain desired distance
                local radiusDiff = settings.radius - distance
                local radial = direction * radiusDiff * 2
                moveVector = perp * settings.speed + radial
            elseif settings.mode == "Figure8" then
                -- Figure-8 pattern for unpredictable movement
                local time = os.clock() * 2
                local perp = Vector3.new(-direction.Z, 0, direction.X)
                local figure8 = perp * math.sin(time) * settings.speed + direction * math.cos(time) * settings.speed * 0.5
                local radiusDiff = settings.radius - distance
                moveVector = figure8 + direction * radiusDiff * 2
            else -- ZigZag
                -- Zig-zag pattern
                local perp = Vector3.new(-direction.Z, 0, direction.X)
                local time = os.clock() * 3
                local zigzag = perp * (math.sign(math.sin(time)) * settings.speed)
                local radiusDiff = settings.radius - distance
                moveVector = zigzag + direction * radiusDiff * 2
            end
            
            -- Smart dodge: add random vertical movement to avoid predictable aim
            if settings.smartDodge then
                local state = humanoid:GetState()
                if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
                    -- Add slight vertical variation while airborne
                    local vertical = Vector3.new(0, math.sin(os.clock() * 5) * 20, 0)
                    root.AssemblyLinearVelocity = Vector3.new(moveVector.X, root.AssemblyLinearVelocity.Y + vertical.Y, moveVector.Z)
                    return
                end
            end
            
            -- Apply horizontal movement, preserve vertical
            root.AssemblyLinearVelocity = Vector3.new(moveVector.X, root.AssemblyLinearVelocity.Y, moveVector.Z)
        end))
    end

    targetStrafe = framework.Categories.Combat:CreateModule({
        Name = "Target Strafe",
        Category = "Combat",
        ConfigKey = "Universal.TargetStrafe",
        Order = 4,
        Tooltip = "Automatically strafe around your target in circular, figure-8, or zig-zag patterns. Makes you much harder to hit in combat.",
        Function = function(enabled)
            if not enabled then
                targetStrafe:SetStatus(nil)
                return
            end
            targetStrafe:Clean(function() lastTarget = nil end)
            toggleTargetStrafe(true)
            targetStrafe:SetStatus(settings.mode)
        end,
    })

    targetStrafe:CreateDropdown({
        Name = "Mode",
        List = {"Circle", "Figure8", "ZigZag"},
        Index = 1,
        Function = function(value)
            settings.mode = value
            if targetStrafe.Enabled then targetStrafe:SetStatus(value) end
        end,
        Tooltip = "Circle = constant orbit; Figure8 = unpredictable loops; ZigZag = rapid direction changes."
    })
    
    targetStrafe:CreateSlider({
        Name = "Radius",
        Min = 2,
        Max = 20,
        Default = 5,
        Function = function(value)
            settings.radius = value
        end,
        Tooltip = "Distance to maintain from the target (in studs)."
    })
    
    targetStrafe:CreateSlider({
        Name = "Speed",
        Min = 30,
        Max = 300,
        Default = 100,
        Function = function(value)
            settings.speed = value
        end,
        Tooltip = "How fast to strafe around the target."
    })
    
    targetStrafe:CreateToggle({
        Name = "Smart dodge",
        Default = true,
        Tooltip = "Adds vertical movement variation while airborne to dodge aim."
    })

    activeCleanup = function()
        if targetStrafe.Enabled then targetStrafe:Toggle(false) end
    end
    
    Module.Initialized = true
    return targetStrafe
end

function Module.destroy()
    if activeCleanup then activeCleanup(); activeCleanup = nil end
    Module.Initialized = false
end

return Module
