--!strict
export type Runtime = {
    framework: any,
    host: any,
    services: any,
}

local Module = {
    Name = "TimeChanger",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local Lighting: Lighting = host.Lighting or (game :: any):GetService("Lighting")

    local originalTime: string? = nil
    local customTime: number = 14

    local function applyTime(hour: number): ()
        local timeString: string = string.format("%02d:00:00", math.floor(hour))
        pcall(function()
            Lighting.TimeOfDay = timeString
        end)
    end

    local card: any
    card = framework.Categories.Render:CreateModule({
        Name = "Time Changer",
        Category = "Render",
        ConfigKey = "Universal.TimeChanger",
        Order = 25,
        Tooltip = "Changes the client time of day in the current world.",
        Function = function(enabled: boolean): ()
            if enabled then
                originalTime = Lighting.TimeOfDay
                applyTime(customTime)
                card:SetStatus(string.format("%02d:00", customTime))

                card:Loop(function(): ()
                    if originalTime then
                        applyTime(customTime)
                    end
                end)
            else
                if originalTime then
                    pcall(function()
                        Lighting.TimeOfDay = originalTime
                    end)
                    originalTime = nil
                end
                card:SetStatus(nil)
            end
        end,
    })

    card:CreateSlider({
        Name = "Time",
        Min = 0,
        Max = 24,
        Default = 14,
        Step = 1,
        Function = function(value: number): ()
            customTime = value
            if card.Enabled then
                applyTime(value)
                card:SetStatus(string.format("%02d:00", value))
            end
        end,
        Tooltip = "Hour of day (0 = midnight, 12 = noon, 18 = sunset).",
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        pcall(activeCard.Toggle, false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
