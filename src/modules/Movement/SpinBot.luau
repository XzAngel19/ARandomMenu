--!strict
--
-- SpinBot.
-- Vape-inspired rotation with a direct CFrame mode and a physics angular-
-- velocity mode. Every touched property is restored on disable.

export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

local Module = {
    Name = "SpinBot",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local getCharacterParts: any = context.host.getCharacterParts
    local baselines: any = setmetatable({}, {__mode = "k"})

    local function restore(): ()
        for root: BasePart, baseline: any in pairs(baselines) do
            if root.Parent then
                root.AssemblyAngularVelocity = baseline.angularVelocity
                local humanoid: Humanoid? = root.Parent:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid.AutoRotate = baseline.autoRotate
                end
            end
        end
        baselines = setmetatable({}, {__mode = "k"})
    end

    local card: any
    card = framework.Categories.Fun:CreateModule({
        Name = "SpinBot",
        Category = "Fun",
        ConfigKey = "Universal.SpinBot",
        Order = 40,
        Tooltip = "Rotates your character continuously around the selected axis.",
        Function = function(enabled: boolean): ()
            if not enabled then
                restore()
                card:SetStatus(nil)
                return
            end
            card:SetStatus(card.Options["Mode"].Value)
            card:Loop(function(deltaTime: number): ()
                local _character: Model?, humanoid: Humanoid?, root: BasePart? =
                    getCharacterParts()
                if not humanoid or not root then
                    return
                end
                if not baselines[root] then
                    baselines[root] = {
                        angularVelocity = root.AssemblyAngularVelocity,
                        autoRotate = humanoid.AutoRotate,
                    }
                end
                humanoid.AutoRotate = false
                local speed: number = card.Options["Speed"].Value
                local axisName: string = card.Options["Axis"].Value
                local axis: Vector3 = axisName == "X" and Vector3.new(1, 0, 0)
                    or axisName == "Z" and Vector3.new(0, 0, 1)
                    or Vector3.new(0, 1, 0)
                if card.Options["Mode"].Value == "Velocity" then
                    root.AssemblyAngularVelocity = axis * math.rad(speed)
                else
                    root.AssemblyAngularVelocity = Vector3.zero
                    local angle: number = math.rad(speed) * deltaTime
                    local rotation: CFrame = axisName == "X" and CFrame.Angles(angle, 0, 0)
                        or axisName == "Z" and CFrame.Angles(0, 0, angle)
                        or CFrame.Angles(0, angle, 0)
                    root.CFrame = root.CFrame * rotation
                end
            end)
            card:Clean(restore)
        end,
    })

    card:CreateDropdown({
        Name = "Mode",
        List = {"CFrame", "Velocity"},
        Index = 1,
        Function = function(value: string): ()
            if card then
                card:SetStatus(value)
            end
        end,
    })
    card:CreateDropdown({Name = "Axis", List = {"Y", "X", "Z"}, Index = 1})
    card:CreateSlider({Name = "Speed", Min = 30, Max = 1440, Step = 15, Default = 360})

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        activeCard:Toggle(false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
