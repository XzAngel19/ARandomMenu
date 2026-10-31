export type Runtime = {framework: any, entity: any, host: any, services: any}

local Module = {Name = "Jesus", PlaceId = 0, Events = {} :: {[string]: any}, Initialized = false}
local activeCleanup

function Module.init(context: Runtime): any
    local host, framework = context.host, context.framework
    local player = host.LocalPlayer
    
    local settings = {
        mode = "Velocity",
        bounce = 0.5,
    }
    
    local jesus

    local function startJesus()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.RespectCanCollide = false
        params.IgnoreWater = false
        local filteredCharacter = nil

        jesus:Clean(host.RunService.PreSimulation:Connect(function()
            local character = player.Character
            if not character then return end
            
            local root = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChild("Humanoid")
            if not root or not humanoid or humanoid.Health <= 0 then return end

            if filteredCharacter ~= character then
                filteredCharacter = character
                params.FilterDescendantsInstances = {character}
            end
            local rayResult = host.workspace:Raycast(root.Position, Vector3.new(0, -10, 0), params)
            
            if rayResult and rayResult.Material == Enum.Material.Water then
                local waterSurface = rayResult.Position.Y
                
                -- Keep character on water surface
                if root.Position.Y < waterSurface + settings.bounce then
                    if settings.mode == "Velocity" then
                        root.AssemblyLinearVelocity = Vector3.new(
                            root.AssemblyLinearVelocity.X,
                            math.max(0, root.AssemblyLinearVelocity.Y),
                            root.AssemblyLinearVelocity.Z
                        )
                        root.CFrame = CFrame.new(root.Position.X, waterSurface + settings.bounce, root.Position.Z)
                    elseif settings.mode == "Impulse" then
                        local targetY = waterSurface + settings.bounce
                        local diff = targetY - root.Position.Y
                        if diff > 0.1 then
                            root:ApplyImpulse(Vector3.new(0, diff * 50, 0) * root.AssemblyMass)
                        end
                    else -- CFrame
                        root.CFrame = CFrame.new(root.Position.X, waterSurface + settings.bounce, root.Position.Z)
                    end
                end
            end
        end))
    end

    jesus = framework.Categories.Exploits:CreateModule({
        Name = "Jesus",
        Category = "Exploits",
        ConfigKey = "Universal.Jesus",
        Order = 4,
        Tooltip = "Walk on water by preventing you from sinking.",
        Function = function(enabled)
            if not enabled then
                jesus:SetStatus(nil)
                return
            end
            startJesus()
            jesus:SetStatus(settings.mode)
        end,
    })

    jesus:CreateDropdown({Name = "Mode", List = {"Velocity", "Impulse", "CFrame"}, Index = 1,
        Function = function(value)
            settings.mode = value
            if jesus.Enabled then jesus:SetStatus(value) end
        end,
        Tooltip = "Movement method: Velocity (smooth), Impulse (forces), or CFrame (direct position)."
    })
    
    jesus:CreateSlider({Name = "Bounce", Min = 0, Max = 2, Default = 0.5, Decimal = 1,
        Function = function(value)
            settings.bounce = value
        end,
        Tooltip = "How far above water surface to stay (in studs)."
    })

    activeCleanup = function()
        if jesus.Enabled then jesus:Toggle(false) end
    end
    
    Module.Initialized = true
    return jesus
end

function Module.destroy()
    if activeCleanup then activeCleanup(); activeCleanup = nil end
    Module.Initialized = false
end

return Module
