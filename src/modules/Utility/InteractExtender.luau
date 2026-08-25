--!strict
--
-- Interact Extender.
--
-- Raises the activation distance of every ProximityPrompt and ClickDetector in
-- the place, and can drop their hold time to nothing. Both are client-side
-- properties of the prompt: the server still runs the same handler it always
-- would, you are simply allowed to reach it from further away.
--
-- This is the menu's Reach, and the name says what it reaches. Wurst's Reach
-- extends how far you can use a block; the Roblox equivalent of "use a block"
-- is a ProximityPrompt or a ClickDetector, and that is the whole of it. Combat
-- reach is a different thing with a different owner — `docs/architecture/
-- reach-ownership.md` records why it is not this card, and why it is not a
-- universal card at all.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "InteractExtender",
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
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    type InteractionSettings = {
        distance: number,
        instantPrompts: boolean,
        proximityPrompts: boolean,
        clickDetectors: boolean,
    }
    type PromptState = {distance: number, holdDuration: number}
    local interactionSettings: InteractionSettings = {
        distance = 32,
        instantPrompts = false,
        proximityPrompts = true,
        clickDetectors = true,
    }
    local originalPrompts: {[ProximityPrompt]: PromptState} =
        setmetatable({}, {__mode = "k"}) :: any
    local originalClickDetectors: {[ClickDetector]: number} =
        setmetatable({}, {__mode = "k"}) :: any
    local interactionExtenderEnabled: boolean = false
    local InteractFeature: any = nil
    local interactionRefreshClock: number = 0

    local function refreshInteractionExtender(): ()
        for prompt: ProximityPrompt, original: PromptState in pairs(originalPrompts) do
            if not prompt.Parent then
                continue
            end
            local wantedDistance: number = interactionExtenderEnabled
                    and interactionSettings.proximityPrompts
                    and interactionSettings.distance
                or original.distance
            local wantedHold: number = interactionExtenderEnabled
                    and interactionSettings.proximityPrompts
                    and interactionSettings.instantPrompts
                    and 0
                or original.holdDuration
            -- Only write what changed. This sweep runs twice a second over every
            -- prompt in the place, and a property write the engine already has
            -- is still a write the game's own scripts can observe.
            if prompt.MaxActivationDistance ~= wantedDistance then
                prompt.MaxActivationDistance = wantedDistance
            end
            if prompt.HoldDuration ~= wantedHold then
                prompt.HoldDuration = wantedHold
            end
        end
        for detector: ClickDetector, originalDistance: number in pairs(originalClickDetectors) do
            if not detector.Parent then
                continue
            end
            local wantedDistance: number = interactionExtenderEnabled
                    and interactionSettings.clickDetectors
                    and interactionSettings.distance
                or originalDistance
            if detector.MaxActivationDistance ~= wantedDistance then
                detector.MaxActivationDistance = wantedDistance
            end
        end
    end

    local function applyInteractionExtension(instance: Instance): ()
        if not interactionExtenderEnabled then
            return
        end
        if instance:IsA("ProximityPrompt") then
            if originalPrompts[instance] == nil then
                originalPrompts[instance] = {
                    distance = instance.MaxActivationDistance,
                    holdDuration = instance.HoldDuration,
                }
            end
            local original: PromptState = originalPrompts[instance]
            instance.MaxActivationDistance = interactionSettings.proximityPrompts
                    and interactionSettings.distance
                or original.distance
            instance.HoldDuration = interactionSettings.proximityPrompts
                    and interactionSettings.instantPrompts
                    and 0
                or original.holdDuration
        elseif instance:IsA("ClickDetector") then
            if originalClickDetectors[instance] == nil then
                originalClickDetectors[instance] = instance.MaxActivationDistance
            end
            instance.MaxActivationDistance = interactionSettings.clickDetectors
                    and interactionSettings.distance
                or originalClickDetectors[instance]
        end
    end

    local function restoreInteractionExtender(): ()
        interactionExtenderEnabled = false
        refreshInteractionExtender()
        originalPrompts = setmetatable({}, {__mode = "k"}) :: any
        originalClickDetectors = setmetatable({}, {__mode = "k"}) :: any
    end

    local function toggleInteractionExtender(enabled: boolean): ()
        disconnectFeatureConnection("InteractExtender")
        disconnectFeatureConnection("InteractExtenderRefresh")
        restoreInteractionExtender()
        interactionRefreshClock = 0
        if not enabled then
            if InteractFeature then InteractFeature:SetStatus(nil) end
            return
        end
        InteractFeature:SetStatus(tostring(math.round(interactionSettings.distance)) .. " studs")
        interactionExtenderEnabled = true
        featureConnections.InteractExtender = workspace.DescendantAdded:Connect(
            applyInteractionExtension
        )
        featureConnections.InteractExtenderRefresh = TaskManager:Connect(
            function(deltaTime: number): ()
                interactionRefreshClock += deltaTime
                if interactionRefreshClock >= 0.5 then
                    interactionRefreshClock = 0
                    refreshInteractionExtender()
                end
            end
        )
        task.spawn(function(): ()
            for index: number, instance: Instance in ipairs(workspace:GetDescendants()) do
                if not interactionExtenderEnabled then
                    return
                end
                applyInteractionExtension(instance)
                if index % 240 == 0 then
                    task.wait()
                end
            end
        end)
    end


    InteractFeature = createUniversalFeature(
        "Interact Extender",
        "Extend prompt and click interaction range without auto-firing",
        24,
        toggleInteractionExtender,
        {categoryName = "Other"}
    )
    addNumberOption(
        InteractFeature,
        "Interaction distance",
        interactionSettings.distance,
        8,
        250,
        function(value: number): ()
            interactionSettings.distance = value
            if InteractFeature.enabled then
                InteractFeature:SetStatus(tostring(math.round(value)) .. " studs")
            end
            refreshInteractionExtender()
        end
    )
    addToggleOption(
        InteractFeature,
        "Instant prompts",
        interactionSettings.instantPrompts,
        function(value: boolean): ()
            interactionSettings.instantPrompts = value
            refreshInteractionExtender()
        end
    )
    addToggleOption(
        InteractFeature,
        "Proximity prompts",
        interactionSettings.proximityPrompts,
        function(value: boolean): ()
            interactionSettings.proximityPrompts = value
            refreshInteractionExtender()
        end
    )
    addToggleOption(
        InteractFeature,
        "Click detectors",
        interactionSettings.clickDetectors,
        function(value: boolean): ()
            interactionSettings.clickDetectors = value
            refreshInteractionExtender()
        end
    )

    -- Teardown has to undo the properties, not just drop the listener: the
    -- sweep connection and every extended prompt outlived the card, so a
    -- client that unloaded the menu left the whole place reaching 32 studs.
    activeCleanup = function(): ()
        disconnectFeatureConnection("InteractExtender")
        disconnectFeatureConnection("InteractExtenderRefresh")
        restoreInteractionExtender()
        interactionRefreshClock = 0
        if InteractFeature then
            InteractFeature:SetStatus(nil)
        end
    end
    Module.Initialized = true
    return InteractFeature
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
