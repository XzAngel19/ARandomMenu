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

local function normalizeHour(hour: number): number
    return (hour % 24 + 24) % 24
end

local function formatTime(hour: number): string
    local normalized: number = normalizeHour(hour)
    local wholeHours: number = math.floor(normalized)
    local minutes: number = math.floor((normalized - wholeHours) * 60 + 0.5)
    if minutes >= 60 then
        wholeHours = (wholeHours + 1) % 24
        minutes = 0
    end
    return string.format("%02d:%02d", wholeHours, minutes)
end

function Module.init(context: Runtime): any
    local framework: any = context.framework
    local host: any = context.host
    local Lighting: Lighting = host.Lighting or (game :: any):GetService("Lighting")

    local originalTime: number? = nil
    local customTime: number = 14

    local function applyTime(hour: number): ()
        local safeHour: number = normalizeHour(hour)
        pcall(function()
            -- ClockTime accepts fractional hours, unlike a formatted string;
            -- this also keeps a 24-hour slider value from producing "24:00:00".
            Lighting.ClockTime = safeHour
        end)
    end

    local card: any
    card = framework.Categories.Render:CreateModule({
        Name = "Time Changer",
        Category = "Render",
        ConfigKey = "Universal.TimeChanger",
        Order = 25,
        Tooltip = "Changes the local visual time only; does not change game or character physics.",
        Function = function(enabled: boolean): ()
            if enabled then
                originalTime = Lighting.ClockTime
                applyTime(customTime)
                card:SetStatus(formatTime(customTime))

                local elapsed: number = 0
                card:Loop(function(deltaTime: number): ()
                    if originalTime == nil or not card.Enabled then
                        return
                    end
                    elapsed += deltaTime
                    -- Some games keep writing Lighting from a day/night loop.
                    -- Reassert at 4 Hz instead of mutating Lighting every frame.
                    if elapsed >= 0.25 then
                        elapsed = 0
                        applyTime(customTime)
                    end
                end)
            else
                if originalTime ~= nil then
                    applyTime(originalTime)
                    originalTime = nil
                end
                card:SetStatus(nil)
            end
        end,
    })

    card:CreateSlider({
        Name = "Time",
        Min = 0,
        Max = 23.75,
        Default = 14,
        Step = 0.25,
        Function = function(value: number): ()
            customTime = normalizeHour(value)
            if card.Enabled then
                applyTime(customTime)
                card:SetStatus(formatTime(customTime))
            end
        end,
        Tooltip = "Local visual hour (0 = midnight, 12 = noon, 18 = sunset); 15-minute steps.",
    })

    activeCard = card
    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCard and activeCard.Enabled then
        pcall(activeCard.Toggle, activeCard, false)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
