local Module = {
    Name = "MM2 Role Fling",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Role Fling requires the MM2 core module")
    Module.Runtime = runtime
    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local playerFromRoundKey: any = core.playerFromRoundKey
    local getRoundData: any = core.getRoundData

    local FlingGroup = createUniversalFeature(
        "Role Fling",
        "Role-based fling actions",
        15,
        function() end,
        {
            category = true,
            categoryName = "Fun",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addActionOption(FlingGroup, "Fling Murderer", function()
        local target = findMurderer()
        if target then
            performFling(target)
        else
            notify("No murderer was found.")
        end
    end)
    addActionOption(FlingGroup, "Fling Sheriff", function()
        local target = findSheriff()
        if target then
            performFling(target)
        else
            notify("No sheriff or hero was found.")
        end
    end)
    addActionOption(FlingGroup, "Fling All Innocents", function()
        task.spawn(function()
            for key, data in pairs(getRoundData()) do
                if type(data) == "table" and data.Role == "Innocent" then
                    local target = playerFromRoundKey(key, data)
                    if target and target ~= LocalPlayer then
                        performFling(target)

                        repeat
                            task.wait(0.05)
                        until not Module.Runtime.Services.activity.isActive("fling")
                    end
                end
            end
        end)
    end)

    activeCleanup = function(): ()
        -- nothing persistent to undo
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
