local Module = {Name = "Fullbright", PlaceId = 0, Initialized = false}
local card

function Module.init(context)
    local lighting = context.host.Lighting
    local original, applied = {}, {}
    local originalTime, appliedTime, elapsed
    local function write(key, value)
        if applied[key] ~= nil and lighting[key] ~= applied[key] then original[key] = lighting[key] end
        if original[key] == nil then original[key] = lighting[key] end
        lighting[key], applied[key] = value, value
    end
    local function restoreTime()
        if appliedTime ~= nil and lighting.ClockTime == appliedTime then lighting.ClockTime = originalTime end
        originalTime, appliedTime = nil, nil
    end
    local function restore()
        restoreTime()
        for key, value in pairs(original) do if lighting[key] == applied[key] then lighting[key] = value end end
        table.clear(original); table.clear(applied)
    end
    local function tick(dt)
        write("Brightness",card.Options.Brightness.Value)
        write("GlobalShadows",false)
        write("FogEnd",100000)
        write("Ambient",Color3.fromRGB(178,178,178))
        write("OutdoorAmbient",Color3.fromRGB(178,178,178))
        if card.Options["Time Changer"].Value then
            if appliedTime ~= nil and lighting.ClockTime ~= appliedTime then originalTime = lighting.ClockTime end
            if originalTime == nil then originalTime = lighting.ClockTime end
            elapsed = (elapsed + math.max(0,dt or 0)) % 4
            appliedTime = (card.Options["Fast time"].Value and elapsed * 6 or card.Options.Time.Value) % 24
            lighting.ClockTime = appliedTime
        else restoreTime() end
    end
    card = context.framework.Categories.Render:CreateModule({Name="Fullbright",Category="Render",ConfigKey="Universal.Fullbright",
        Tooltip="Bright lighting; optionally control the time of day.",Function=function(enabled)
            if not enabled then restore(); return end
            elapsed = 0
            card:Clean(restore)
            tick(0);card:Loop(tick)
        end})
    card:CreateSlider({Name="Brightness",Min=0,Max=10,Default=3})
    card:CreateToggle({Name="Time Changer",Default=false,Function=function(value) if not value then restoreTime() end end})
    card:CreateSlider({Name="Time",Min=0,Max=24,Default=14,Show={Option="Time Changer",Values={true}}})
    card:CreateToggle({Name="Fast time",Default=false,Show={Option="Time Changer",Values={true}},Tooltip="Loop a full day every four seconds."})
    Module.Initialized=true
    return card
end
function Module.destroy()
    if card and card.Enabled then card:Toggle(false) end
    card=nil;Module.Initialized=false
end
return Module
