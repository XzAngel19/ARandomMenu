export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "JumpPower",
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
    local getCharacterParts: any = host.getCharacterParts
    local createUniversalFeature: any = host.createUniversalFeature
    local addNumberOption: any = host.addNumberOption
    local jumpPowerSettings = {value = 80}
    local JumpPowerFeature: any = nil
    local originalJumpPower = setmetatable({}, {__mode = "k"})

    local function restoreJumpPower()
        for humanoid, original in pairs(originalJumpPower) do
            if humanoid and humanoid.Parent then
                humanoid.JumpPower = original.jumpPower
                humanoid.UseJumpPower = original.useJumpPower
            end
        end
        originalJumpPower = setmetatable({}, {__mode = "k"})
    end

    local function toggleJumpPower(enabled)
        disconnectFeatureConnection("JumpPower")
        restoreJumpPower()

        if not enabled then
            if JumpPowerFeature then
                JumpPowerFeature:SetStatus(nil)
            end
            return
        end

        JumpPowerFeature:SetStatus(tostring(math.round(jumpPowerSettings.value)))
        featureConnections.JumpPower = TaskManager:Connect(function()
            local _, humanoid = getCharacterParts()
            if not humanoid then
                return
            end

            if not originalJumpPower[humanoid] then
                originalJumpPower[humanoid] = {
                    jumpPower = humanoid.JumpPower,
                    useJumpPower = humanoid.UseJumpPower,
                }
            end

            humanoid.UseJumpPower = true
            humanoid.JumpPower = jumpPowerSettings.value
        end)
    end

    JumpPowerFeature = createUniversalFeature(
        "Jump Power",
        "Keep character jump power at a custom value",
        6,
        toggleJumpPower,
        {categoryName = "Blatant"}
    )
    addNumberOption(JumpPowerFeature, "Power", jumpPowerSettings.value, 0, 500, function(value)
        jumpPowerSettings.value = value
        if JumpPowerFeature.enabled then
            JumpPowerFeature:SetStatus(tostring(math.round(value)))
        end
    end)

    activeCleanup = function(): ()
        disconnectFeatureConnection("JumpPower")
        restoreJumpPower()
    end
    Module.Initialized = true
    return JumpPowerFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
