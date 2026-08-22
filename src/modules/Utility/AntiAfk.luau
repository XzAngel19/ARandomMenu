--!strict
--
-- Anti-AFK.
--
-- Defeats the twenty-minute idle kick by answering the same event Roblox uses
-- to detect it, instead of shaking the camera or spamming input.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "AntiAfk",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local function toggleAntiAfk(enabled)
        disconnectFeatureConnection("AntiAFK")

        if not enabled then
            return
        end

        featureConnections.AntiAFK = LocalPlayer.Idled:Connect(function()
            local virtualUserOk, virtualUser = pcall(function()
                return game:GetService("VirtualUser")
            end)
            if virtualUserOk and virtualUser then
                virtualUser:CaptureController()
                virtualUser:ClickButton2(Vector2.new(0, 0))
            end
        end)
    end

    local AntiAfkFeature = createUniversalFeature(
        "AntiAFK",
        "Prevent the local idle event from disconnecting",
        13,
        toggleAntiAfk,
        {
            noOptions = true,
            configKey = "Universal.AntiAFK",
            categoryName = "Other",
        }
    )
    addFeatureTooltip(AntiAfkFeature, "Responds only to Roblox's local idle event and "
        .. "disconnects immediately when disabled.")

    activeCleanup = function(): ()
        -- "AntiAFK", not "AntiAfk". The connection is registered under the
        -- shouted spelling and the toggle drops it under the same one; this
        -- line named the other casing, so tearing the menu down left the
        -- Idled listener attached to a player whose menu no longer exists.
        disconnectFeatureConnection("AntiAFK")
    end
    Module.Initialized = true
    return AntiAfkFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
