--!strict
--
-- Freeze Movements.
--
-- Two ways of standing still: anchoring the root, which stops physics dead,
-- and zeroing the humanoid's own controls, which leaves you subject to the
-- world. A game that fights one usually accepts the other.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "FreezeMovements",
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
    local addCycleOption: any = host.addCycleOption
    local addInformationOption: any = host.addInformationOption
    local movementFeatures: any = host.state.movementFeatures
    local MovementScroll: any = host.state.universalScroll
    local freezeSettings = {mode = "Anchor"}
    local FreezeFeature: any = nil
    local originalFreezeState = setmetatable({}, {__mode = "k"})

    local function restoreFreezeMovements()
        for humanoid, original in pairs(originalFreezeState) do
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = original.walkSpeed
                humanoid.JumpPower = original.jumpPower
                humanoid.AutoRotate = original.autoRotate
                if original.root and original.root.Parent then
                    original.root.Anchored = original.rootAnchored
                end
            end
        end
        originalFreezeState = setmetatable({}, {__mode = "k"})
    end

    local function toggleFreezeMovements(enabled)
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()

        if not enabled then
            if FreezeFeature then
                FreezeFeature:SetStatus(nil)
            end
            return
        end

        FreezeFeature:SetStatus(freezeSettings.mode)
        featureConnections.FreezeMovements = TaskManager:Connect(function()
            local _, humanoid, root = getCharacterParts()
            if not humanoid or not root then
                return
            end

            if not originalFreezeState[humanoid] then
                originalFreezeState[humanoid] = {
                    walkSpeed = humanoid.WalkSpeed,
                    jumpPower = humanoid.JumpPower,
                    autoRotate = humanoid.AutoRotate,
                    root = root,
                    rootAnchored = root.Anchored,
                }
            end

            local original = originalFreezeState[humanoid]
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.AutoRotate = false
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.Anchored = freezeSettings.mode == "Anchor"
                and true
                or original.rootAnchored
        end)
    end

    FreezeFeature = createUniversalFeature(
        "Freeze Movements",
        "Prevent the local character from moving",
        1,
        toggleFreezeMovements,
        {
            parent = MovementScroll,
            registry = movementFeatures,
        }
    )
    addCycleOption(
        FreezeFeature,
        "Freeze mode",
        {"Anchor", "Humanoid"},
        1,
        function(value)
            freezeSettings.mode = value
            if FreezeFeature.enabled then
                FreezeFeature:SetStatus(value)
            end
        end
    )
    addInformationOption(
        FreezeFeature,
        "Anchor stops all physics; Humanoid only blocks character controls."
    )



    activeCleanup = function(): ()
        disconnectFeatureConnection("FreezeMovements")
        restoreFreezeMovements()
    end
    Module.Initialized = true
    return FreezeFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
