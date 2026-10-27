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
    local activity: any = context.services and context.services.activity
    local toggleNoclip: (boolean) -> ()
    do
    local originalCollision = setmetatable({}, {__mode = "k"})

    -- Walking the whole character with GetDescendants() every frame was pure
    -- garbage: the part list is built once per character and kept in sync with
    -- DescendantAdded. The frame path only checks the cached list.
    local cachedCharacter = nil
    local cachedParts = {}
    local addedConnection = nil

    local function restoreCollision()
        for part, canCollide in pairs(originalCollision) do
            if part and part.Parent then
                part.CanCollide = canCollide
            end
        end
        originalCollision = setmetatable({}, {__mode = "k"})
    end

    local function forgetCharacter()
        if addedConnection then
            pcall(function(): ()
                addedConnection:Disconnect()
            end)
            addedConnection = nil
        end
        cachedCharacter = nil
        cachedParts = {}
    end

    local function collectParts(character: Model)
        local parts: {BasePart} = {}
        for _, descendant: Instance in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") then
                table.insert(parts, descendant :: BasePart)
            end
        end
        cachedParts = parts
    end

    local function partsOf(character: Model): {BasePart}
        if character ~= cachedCharacter then
            forgetCharacter()
            cachedCharacter = character
            collectParts(character)
            local added = (character :: any).DescendantAdded
            if added and type(added.Connect) == "function" then
                addedConnection = added:Connect(function(object: Instance): ()
                    if object:IsA("BasePart") then
                        table.insert(cachedParts, object :: BasePart)
                    end
                end)
            end
        end
        return cachedParts
    end

    function toggleNoclip(enabled: boolean): ()
        disconnectFeatureConnection("Noclip")
        restoreCollision()
        forgetCharacter()

        if not enabled then
            return
        end

        featureConnections.Noclip = TaskManager:Connect(function()
            -- Fling owns contact collisions while its session is active.
            -- Fighting it here every Heartbeat both cancels Touch and creates
            -- needless property/physics work.
            if activity and type(activity.isActive) == "function"
                and activity.isActive("fling") then
                return
            end
            local character = LocalPlayer.Character
            if not character then
                return
            end

            local parts = partsOf(character)
            for index = 1, #parts do
                local part = parts[index]
                if part.Parent and part.CanCollide then
                    if originalCollision[part] == nil then
                        originalCollision[part] = true
                    end
                    part.CanCollide = false
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
        {noOptions = true, categoryName = "Exploits"}
    )
    addFeatureTooltip(NoclipFeature, "Disables collisions for every local character part. "
        .. "Original collision states are restored when turned off.")

    activeCleanup = function(): ()

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
