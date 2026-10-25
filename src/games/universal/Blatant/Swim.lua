export type Runtime = {framework: any, entity: any, host: any, services: any}

local Module = {Name = "Swim", PlaceId = 0, Events = {} :: {[string]: any}, Initialized = false}
local activeCleanup

function Module.init(context: Runtime): any
    local host, framework = context.host, context.framework
    local player = host.LocalPlayer
    
    local terrain = workspace:FindFirstChildWhichIsA("Terrain")
    local lastpos = nil
    
    local swim

    local function toggleSwim(enabled)
        if not enabled then
            -- Restore terrain when disabled
            if terrain and lastpos then
                pcall(function()
                    terrain:ReplaceMaterial(lastpos, 4, Enum.Material.Water, Enum.Material.Air)
                end)
                lastpos = nil
            end
            return
        end
        
        swim:Clean(host.RunService.PreSimulation:Connect(function(dt)
            local character = player.Character
            if not character then return end
            
            local root = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChild("Humanoid")
            if not root or not humanoid or humanoid.Health <= 0 then return end

            local moving = humanoid.MoveDirection ~= Vector3.zero
            local space = host.UserInputService:IsKeyDown(Enum.KeyCode.Space)

            if terrain then
                local factor = (moving or space) and Vector3.new(6, 6, 6) or Vector3.new(2, 1, 2)
                local pos = root.Position - Vector3.new(0, 1, 0)
                local newpos = Region3.new(pos - factor, pos + factor)
                
                -- Restore previous position
                if lastpos then
                    pcall(function()
                        terrain:ReplaceMaterial(lastpos, 4, Enum.Material.Water, Enum.Material.Air)
                    end)
                end
                
                -- Create water at new position
                pcall(function()
                    terrain:ReplaceMaterial(newpos, 4, Enum.Material.Air, Enum.Material.Water)
                end)
                
                lastpos = newpos
            end
        end))
    end

    swim = framework.Categories.Exploits:CreateModule({
        Name = "Swim",
        Category = "Exploits",
        ConfigKey = "Universal.Swim",
        Order = 3,
        Tooltip = "Lets you swim midair by converting terrain to water around your character.",
        Function = function(enabled)
            if not enabled then
                swim:SetStatus(nil)
                return
            end
            swim:Clean(function()
                if terrain and lastpos then
                    pcall(function()
                        terrain:ReplaceMaterial(lastpos, 4, Enum.Material.Water, Enum.Material.Air)
                    end)
                    lastpos = nil
                end
            end)
            toggleSwim(true)
            swim:SetStatus("Active")
        end,
    })

    activeCleanup = function()
        if swim.Enabled then swim:Toggle(false) end
        if terrain and lastpos then
            pcall(function()
                terrain:ReplaceMaterial(lastpos, 4, Enum.Material.Water, Enum.Material.Air)
            end)
            lastpos = nil
        end
    end
    
    Module.Initialized = true
    return swim
end

function Module.destroy()
    if activeCleanup then activeCleanup(); activeCleanup = nil end
    Module.Initialized = false
end

return Module
