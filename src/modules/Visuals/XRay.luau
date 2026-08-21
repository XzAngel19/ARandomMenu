--!strict
--
-- X-Ray.
--
-- Turns the world translucent from this client only: it writes
-- `LocalTransparencyModifier`, which the server neither sees nor replicates,
-- and every part's original value is remembered so switching it off puts the
-- map back exactly as it was.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "XRay",
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
    local originalXrayTransparency: {[BasePart]: number} =
        setmetatable({}, {__mode = "k"}) :: any
    local xrayEnabled: boolean = false
    local feature: any = nil

    local function restoreXray(): ()
        for part: BasePart, transparency: number in pairs(originalXrayTransparency) do
            if part.Parent then
                part.LocalTransparencyModifier = transparency
            end
        end
        originalXrayTransparency = setmetatable({}, {__mode = "k"}) :: any
    end

    local function toggleXray(enabled: boolean): ()
        disconnectFeatureConnection("Xray")
        xrayEnabled = false
        restoreXray()
        if not enabled then
            if feature then feature:SetStatus(nil) end
            return
        end

        feature:SetStatus("72%")
        xrayEnabled = true
        local function applyToInstance(descendant: Instance): ()
            if not xrayEnabled or not descendant:IsA("BasePart") then
                return
            end
            local localCharacter: Model? = LocalPlayer.Character
            local ancestorModel: Model? = descendant:FindFirstAncestorOfClass("Model")
            if (localCharacter and descendant:IsDescendantOf(localCharacter))
                or descendant:FindFirstAncestorOfClass("Tool")
                or (ancestorModel and ancestorModel:FindFirstChildOfClass("Humanoid")) then
                return
            end
            if originalXrayTransparency[descendant] == nil then
                originalXrayTransparency[descendant] = descendant.LocalTransparencyModifier
            end
            descendant.LocalTransparencyModifier = math.max(
                descendant.LocalTransparencyModifier,
                0.72
            )
        end

        featureConnections.Xray = workspace.DescendantAdded:Connect(applyToInstance)
        task.spawn(function(): ()
            for index: number, descendant: Instance in ipairs(workspace:GetDescendants()) do
                if not xrayEnabled then
                    return
                end
                applyToInstance(descendant)
                if index % 240 == 0 then
                    task.wait()
                end
            end
        end)
    end


    feature = createUniversalFeature(
        "X-Ray",
        "Fade map geometry locally while keeping your character clear",
        18,
        toggleXray,
        {noOptions = true}
    )

    activeCleanup = function(): ()
        disconnectFeatureConnection("Xray")
        restoreXray()
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
