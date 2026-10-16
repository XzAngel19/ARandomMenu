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

    -- Safety net: a previous session that died without restoring (crash,
    -- executor kill, older build) leaves the map translucent forever. Sweep
    -- every map part and clear the modifier. LocalTransparencyModifier is
    -- only used by us here; the local character is excluded because Roblox
    -- itself fades it in first person.
    local function sweepStuckTransparency(): ()
        local localCharacter: Model? = LocalPlayer.Character
        for _, descendant: Instance in ipairs(workspace:GetDescendants()) do
            if descendant:IsA("BasePart")
                and (descendant :: BasePart).LocalTransparencyModifier ~= 0 then
                local part: BasePart = descendant :: BasePart
                if (localCharacter and part:IsDescendantOf(localCharacter :: Model))
                    or part:FindFirstAncestorOfClass("Tool") then
                    continue
                end
                local ancestorModel: Model? =
                    part:FindFirstAncestorOfClass("Model")
                if ancestorModel and ancestorModel:FindFirstChildOfClass("Humanoid") then
                    continue
                end
                part.LocalTransparencyModifier = 0
            end
        end
    end

    -- Clear anything a previous, unloaded session left translucent.
    task.spawn(sweepStuckTransparency)

    local function toggleXray(enabled: boolean): ()
        disconnectFeatureConnection("Xray")
        xrayEnabled = false
        restoreXray()
        if not enabled then
            -- Also sweep: if the capture table ever lost an entry, the map
            -- would stay translucent. Cheap and idempotent.
            task.spawn(sweepStuckTransparency)
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
        {noOptions = true, categoryName = "Render"}
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
