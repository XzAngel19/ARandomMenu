export type Runtime = {framework: any, entity: any, host: any, services: any}

local Module = {Name = "Swim", PlaceId = 0, Events = {} :: {[string]: any}, Initialized = false}
local activeCleanup

function Module.init(context: Runtime): any
    local host, framework = context.host, context.framework
    local player = host.LocalPlayer
    local terrain = host.workspace:FindFirstChildWhichIsA("Terrain")
    local lastpos: Region3? = nil
    local swim

    -- Vape's terrain-water method. This clears Water in the region, including
    -- any water that was already there before the module was enabled.
    local function restoreWater()
        if terrain and lastpos then
            terrain:ReplaceMaterial(lastpos, 4, Enum.Material.Water, Enum.Material.Air)
            lastpos = nil
        end
    end

    swim = framework.Categories.Exploits:CreateModule({
        Name = "Swim",
        Category = "Exploits",
        ConfigKey = "Universal.Swim",
        Order = 3,
        Tooltip = "Swim using local terrain water. Moving or turning off clears existing water in the affected region.",
        Function = function(enabled)
            if not enabled then
                swim:SetStatus(nil)
                return
            end
            swim:Clean(restoreWater)
            swim:Clean(host.RunService.PreSimulation:Connect(function()
                local character = player.Character
                if not character then return end
                local root = character:FindFirstChild("HumanoidRootPart")
                local humanoid = character:FindFirstChild("Humanoid")
                if not root or not humanoid or humanoid.Health <= 0 or not terrain then return end

                local moving = humanoid.MoveDirection ~= Vector3.zero
                local space = host.UserInputService:IsKeyDown(Enum.KeyCode.Space)
                local factor = (moving or space) and Vector3.new(6, 6, 6) or Vector3.new(2, 1, 2)
                local pos = root.Position - Vector3.new(0, 1, 0)
                local newpos = Region3.new(pos - factor, pos + factor):ExpandToGrid(4)
                -- Do not rewrite the same voxels every physics frame.
                if lastpos and lastpos.CFrame.Position == newpos.CFrame.Position and lastpos.Size == newpos.Size then
                    return
                end
                restoreWater()
                terrain:ReplaceMaterial(newpos, 4, Enum.Material.Air, Enum.Material.Water)
                lastpos = newpos
            end))
            swim:SetStatus("Active")
        end,
    })

    activeCleanup = function()
        if swim.Enabled then swim:Toggle(false) end
        restoreWater()
    end
    Module.Initialized = true
    return swim
end

function Module.destroy()
    if activeCleanup then activeCleanup(); activeCleanup = nil end
    Module.Initialized = false
end

return Module
