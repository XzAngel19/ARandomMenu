--!strict
--
-- Rejoin Server.
--
-- Back into the same server instance, for when a round breaks rather than the
-- game. One action, no settings.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "RejoinServer",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local createUniversalFeature: any = host.createUniversalFeature
    local cloneReference: any = host.cloneReference
    local function rejoinCurrentServer(): ()
        local teleportService: TeleportService = cloneReference(
            game:GetService("TeleportService")
        )
        teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end
    local actionId: string = "RejoinServer"
    local wurstOptions: any = host.state
        and rawget(host.state, "wurstOptions")
    if wurstOptions and type(wurstOptions.RegisterAction) == "function" then
        local registered: boolean, registration: any = pcall(
            wurstOptions.RegisterAction,
            actionId,
            "Rejoin Server",
            rejoinCurrentServer,
            {
                description = "Reconnect to the current server instance",
                configKey = "Universal.RejoinServer",
            }
        )
        if not registered then
            error("Wurst Options refused Rejoin Server: " .. tostring(registration))
        end
        activeCleanup = function(): ()
            if type(registration) == "table"
                and type(registration.Unregister) == "function" then
                registration.Unregister()
            elseif type(wurstOptions.UnregisterAction) == "function" then
                pcall(wurstOptions.UnregisterAction, actionId)
            end
        end
        Module.Initialized = true
        return registration
    end

    -- Until A's Wurst Options registry is present, keep the existing action
    -- reachable. It remains an action (never a persistent toggle), and this
    -- branch disappears automatically as soon as RegisterAction is published.
    local feature: any = createUniversalFeature(
        "Rejoin Server",
        "Reconnect to the current server instance",
        22,
        rejoinCurrentServer,
        {action = true, noOptions = true, categoryName = "Other"}
    )

    activeCleanup = function(): () end
    Module.Initialized = true
    return feature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
