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
        -- v139: the DescendantAdded watcher must go too, or it keeps forcing
        -- CanCollide=false after the card is switched off.
        disconnectFeatureConnection("NoclipDescendant")
        restoreCollision()

        if not enabled then
            return
        end

        -- v139: this used to run character:GetDescendants() and write
        -- CanCollide on every part 60 times a second (~3000 property writes per
        -- second for a normal avatar, and it never stopped re-setting parts that
        -- were already non-colliding). Now: apply once, catch new parts with the
        -- engine's own event, and only run a cheap safety sweep 5 times a second
        -- in case the humanoid re-enabled something.
        local sweptCharacter: any = nil
        local sweptAt: number = -math.huge
        local addConnection: any = nil

        local function noClipPart(part: any): ()
            if part:IsA("BasePart") then
                if originalCollision[part] == nil then
                    originalCollision[part] = part.CanCollide
                end
                if part.CanCollide then
                    part.CanCollide = false
                end
            end
        end

        local function attach(character: any): ()
            if sweptCharacter == character then
                return
            end
            sweptCharacter = character
            if addConnection then
                pcall(function(): ()
                    addConnection:Disconnect()
                end)
                addConnection = nil
            end
            for _, descendant in ipairs(character:GetDescendants()) do
                noClipPart(descendant)
            end
            local okConnect, connection = pcall(function(): any
                return character.DescendantAdded:Connect(noClipPart)
            end)
            if okConnect then
                addConnection = connection
            end
        end

        featureConnections.Noclip = TaskManager:Connect(function(): ()
            local character = LocalPlayer.Character
            if not character then
                return
            end
            if character ~= sweptCharacter then
                attach(character)
                sweptAt = os.clock()
                return
            end
            -- Safety sweep: only parts that are colliding again are touched.
            if os.clock() - sweptAt < 0.2 then
                return
            end
            sweptAt = os.clock()
            for _, descendant in ipairs(character:GetDescendants()) do
                if descendant:IsA("BasePart") and (descendant :: any).CanCollide then
                    noClipPart(descendant)
                end
            end
        end)
        featureConnections.NoclipDescendant = {
            Disconnect = function(): ()
                if addConnection then
                    pcall(function(): ()
                        addConnection:Disconnect()
                    end)
                    addConnection = nil
                end
                sweptCharacter = nil
            end,
        }
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
