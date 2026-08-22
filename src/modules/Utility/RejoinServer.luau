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


    local feature: any = createUniversalFeature(
        "Rejoin Server",
        "Reconnect to the current server instance",
        22,
        rejoinCurrentServer,
        {action = true, noOptions = true, categoryName = "Other"}
    )

    activeCleanup = function(): ()
        -- Nothing to undo: teleporting is one call.
    end
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
