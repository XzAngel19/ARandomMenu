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
    local fastTime: boolean = false
    local fastElapsed: number = 0

    -- Full 00:00 -> 24:00 sweep in under five seconds, looping while on.
    local FAST_CYCLE_SECONDS: number = 4

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

                card:Loop(function(deltaTime: number): ()
                    if not originalTime then
                        return
                    end
                    if fastTime then
                        fastElapsed += deltaTime
                        if fastElapsed >= FAST_CYCLE_SECONDS then
                            fastElapsed -= FAST_CYCLE_SECONDS
                        end
                        local hour: number =
                            (fastElapsed / FAST_CYCLE_SECONDS) * 24 % 24
                        applyTime(hour)
                        card:SetStatus(string.format("%02d:00", hour))
                    else
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
            if card.Enabled and not fastTime then
                applyTime(value)
                card:SetStatus(string.format("%02d:00", value))
            end
        end,
        Tooltip = "Hour of day (0 = midnight, 12 = noon, 18 = sunset).",
    })
    card:CreateToggle({
        Name = "Fast time",
        Default = false,
        Function = function(value: boolean): ()
            fastTime = value
            fastElapsed = 0
            if card.Enabled and not fastTime then
                applyTime(customTime)
                card:SetStatus(string.format("%02d:00", customTime))
            end
        end,
        Tooltip = "Sweeps the whole day from 00:00 to 24:00 in about "
            .. "four seconds, on repeat, while the module is on.",
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
