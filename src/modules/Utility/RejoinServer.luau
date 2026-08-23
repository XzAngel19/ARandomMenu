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
        local placeId: number = game.PlaceId
        local jobId: string = tostring(game.JobId or "")
        -- Same instance when the id exists, any instance otherwise. The
        -- old call errored silently whenever JobId was empty (solo
        -- servers, some private ones) — "Rejoin does nothing" reported
        -- from the field. A refused same-instance teleport also falls
        -- back to a plain rejoin of the place.
        local rejoined: boolean = false
        if jobId ~= "" then
            rejoined = pcall(function(): ()
                teleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
            end)
        end
        if not rejoined then
            local ok: boolean, teleportError: any = pcall(function(): ()
                teleportService:Teleport(placeId, LocalPlayer)
            end)
            if not ok then
                warn("[Wurst] Rejoin failed: " .. tostring(teleportError))
            end
        end
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
        local search: any = rawget(host.state, "moduleSearch")
        local searchFeature: any = {
            name = "Rejoin Server",
            configKey = "Universal.RejoinServer",
            kind = "action",
            searchable = false,
            enabled = false,
            activate = rejoinCurrentServer,
        }
        if search and type(search.Register) == "function" then
            search.Register(searchFeature)
        end
        activeCleanup = function(): ()
            if search and type(search.Unregister) == "function" then
                search.Unregister(searchFeature)
            end
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
        {
            action = true,
            noOptions = true,
            categoryName = "Other",
            searchable = false,
        }
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
