local Module = {
    Name = "MM2 Instant Role Notify",
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
    assert(type(core) == "table", "MM2 Instant Role Notify requires the MM2 core module")
    Module.Runtime = runtime
    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local mm2Settings: any = core.mm2Settings

    -- The latch lives here now: the core only reports "the round has roles",
    -- every announcement feature decides on its own what to do with that.
    local roleNotificationSent: boolean = false

    local function announceRoles(): ()
        local murderer: Player? = findMurderer()
        local sheriff: Player? = findSheriff()
        if not murderer or not sheriff then
            return
        end
        roleNotificationSent = true
        notify(
            "Roles ready - Murderer: "
                .. murderer.Name
                .. " | Sheriff/Hero: "
                .. sheriff.Name
        )
    end

    local unsubscribe: () -> () = core.onRoundRoles(function(roundActive: boolean): ()
        if not roundActive then
            roleNotificationSent = false
            return
        end
        if mm2Settings.instantRoleNotify and not roleNotificationSent then
            announceRoles()
        end
    end)

    local function toggleInstantRoleNotify(enabled: boolean): ()
        mm2Settings.instantRoleNotify = enabled
        if not enabled then
            return
        end
        -- Enabled mid-round: say it once right away instead of waiting for the
        -- next PlayerDataChanged push.
        if not roleNotificationSent and findMurderer() and findSheriff() then
            announceRoles()
        end
    end

    createUniversalFeature(
        "Instant Role Notify",
        "Notify roles once at the beginning of each round",
        1,
        toggleInstantRoleNotify,
        {
            noOptions = true,
            categoryName = "Fun",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )

    activeCleanup = function(): ()
        pcall(unsubscribe)
        mm2Settings.instantRoleNotify = false
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
