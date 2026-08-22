--!strict
--
-- Lag Switch.
--
-- Holds incoming replication so the world stops arriving while you keep
-- moving locally. It is the bluntest thing in this menu and it is honest about
-- it: everything snaps back into place the moment it is switched off.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "LagSwitch",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local lagSwitchSettings = {incomingLag = 999}
    local originalIncomingLag = 0
    local LagSwitchFeature: any = nil

    local function setIncomingReplicationLag(value)
        local success = pcall(function()
            settings():GetService("NetworkSettings").IncomingReplicationLag = value
        end)
        return success
    end

    local function toggleLagSwitch(enabled)
        disconnectFeatureConnection("LagSwitch")

        if not enabled then
            if LagSwitchFeature then LagSwitchFeature:SetStatus(nil) end
            setIncomingReplicationLag(originalIncomingLag)
            return
        end

        LagSwitchFeature:SetStatus(tostring(math.round(lagSwitchSettings.incomingLag)) .. " ms")
        pcall(function()
            originalIncomingLag = settings():GetService(
                "NetworkSettings"
            ).IncomingReplicationLag
        end)

        if not setIncomingReplicationLag(lagSwitchSettings.incomingLag) then
            error("NetworkSettings is not available in this client.")
        end

        featureConnections.LagSwitch = TaskManager:Connect(function()
            setIncomingReplicationLag(lagSwitchSettings.incomingLag)
        end)
    end

    LagSwitchFeature = createUniversalFeature(
        "Lag Switch",
        "Simulate extreme incoming replication delay",
        16,
        toggleLagSwitch,
        {categoryName = "Movement"}
    )
    addNumberOption(
        LagSwitchFeature,
        "Incoming lag",
        lagSwitchSettings.incomingLag,
        1,
        999,
        function(value)
            lagSwitchSettings.incomingLag = value
            if LagSwitchFeature.enabled then
                LagSwitchFeature:SetStatus(tostring(math.round(value)) .. " ms")
            end
        end
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("LagSwitch")
        setIncomingReplicationLag(originalIncomingLag)
    end
    Module.Initialized = true
    return LagSwitchFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
