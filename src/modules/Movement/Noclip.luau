--!strict
--
-- Noclip.
--
-- Collision off on the character's own parts, restored per part from what it
-- was rather than from an assumption, because a rig with a non-colliding
-- accessory must not come back colliding.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "Noclip",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local LocalPlayer: any = host.LocalPlayer
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local createUniversalFeature: any = host.createUniversalFeature
    local addFeatureTooltip: any = host.addFeatureTooltip
    local toggleNoclip: (boolean) -> ()
    do
    local originalCollision = setmetatable({}, {__mode = "k"})

    local function restoreCollision()
        for part, canCollide in pairs(originalCollision) do
            if part and part.Parent then
                part.CanCollide = canCollide
            end
        end
        originalCollision = setmetatable({}, {__mode = "k"})
    end

    function toggleNoclip(enabled: boolean): ()
        disconnectFeatureConnection("Noclip")
        restoreCollision()

        if not enabled then
            return
        end

        featureConnections.Noclip = TaskManager:Connect(function()
            local character = LocalPlayer.Character
            if not character then
                return
            end

            for _, descendant in ipairs(character:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    if originalCollision[descendant] == nil then
                        originalCollision[descendant] = descendant.CanCollide
                    end
                    descendant.CanCollide = false
                end
            end
        end)
    end
    end

    local NoclipFeature = createUniversalFeature(
        "Noclip",
        "Disable character collisions",
        11,
        toggleNoclip,
        {noOptions = true}
    )
    addFeatureTooltip(NoclipFeature, "Disables collisions for every local character part. "
        .. "Original collision states are restored when turned off.")

    activeCleanup = function(): ()
        -- Through the toggle, not through `restoreCollision`: that one is a
        -- local of the inner block and naming it out here would read a global
        -- that is nil at runtime.
        toggleNoclip(false)
    end
    Module.Initialized = true
    return NoclipFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
