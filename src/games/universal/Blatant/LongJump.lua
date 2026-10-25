export type Runtime = {framework: any, entity: any, host: any, services: any}

local Module = {Name = "LongJump", PlaceId = 0, Events = {} :: {[string]: any}, Initialized = false}
local activeCleanup

function Module.init(context: Runtime): any
    local host, framework = context.host, context.framework
    local player = host.LocalPlayer
    
    local settings = {
        mode = "Velocity",
        speed = 50,
        autoDisable = false,
    }
    
    local longjump

    local function toggleLongJump(enabled)
        if not enabled then
            return
        end
        
        local enableTime = os.clock() + 0.1
        
        longjump:Clean(host.RunService.PreSimulation:Connect(function(dt)
            local character = player.Character
            if not character then return end
            
            local root = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChild("Humanoid")
            if not root or not humanoid or humanoid.Health <= 0 then return end

            -- Jump if on ground
            if humanoid.FloorMaterial ~= Enum.Material.Air then
                if enableTime < os.clock() and settings.autoDisable then
                    if longjump.Enabled then
                        longjump:Toggle(false)
                    end
                    return
                end
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end

            -- Apply horizontal boost
            local dir = humanoid.MoveDirection * settings.speed
            
            if settings.mode == "Velocity" then
                root.AssemblyLinearVelocity = dir + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
            elseif settings.mode == "Impulse" then
                local diff = (dir - root.AssemblyLinearVelocity) * Vector3.new(1, 0, 1)
                if diff.Magnitude > (dir == Vector3.zero and 10 or 2) then
                    root:ApplyImpulse(diff * root.AssemblyMass)
                end
            else -- CFrame
                root.CFrame += dir * dt
            end
        end))
    end

    longjump = framework.Categories.Exploits:CreateModule({
        Name = "LongJump",
        Category = "Exploits",
        ConfigKey = "Universal.LongJump",
        Order = 5,
        Tooltip = "Lets you jump farther with horizontal speed boost.",
        Function = function(enabled)
            if not enabled then
                longjump:SetStatus(nil)
                return
            end
            longjump:Clean(function() end)
            toggleLongJump(true)
            longjump:SetStatus(settings.mode)
        end,
    })

    longjump:CreateDropdown({Name = "Mode", List = {"Velocity", "Impulse", "CFrame"}, Index = 1,
        Function = function(value)
            settings.mode = value
            if longjump.Enabled then longjump:SetStatus(value) end
        end,
        Tooltip = "Movement method: Velocity (smooth), Impulse (forces), or CFrame (direct position)."
    })
    
    longjump:CreateSlider({Name = "Speed", Min = 1, Max = 150, Default = 50,
        Function = function(value)
            settings.speed = value
        end,
        Tooltip = "Horizontal boost speed in studs/second."
    })
    
    longjump:CreateToggle({Name = "Auto Disable", Default = false,
        Function = function(value)
            settings.autoDisable = value
        end,
        Tooltip = "Automatically disable after first jump."
    })

    activeCleanup = function()
        if longjump.Enabled then longjump:Toggle(false) end
    end
    
    Module.Initialized = true
    return longjump
end

function Module.destroy()
    if activeCleanup then activeCleanup(); activeCleanup = nil end
    Module.Initialized = false
end

return Module
