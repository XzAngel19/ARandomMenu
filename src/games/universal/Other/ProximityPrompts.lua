export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "ProximityPrompts",
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
    -- Rows default OFF: the card is the master switch and turns every channel
    -- on by itself. A row switched on with the card OFF is a deliberate opt-in
    -- and works on its own, so nobody has to enable the whole card just for the
    -- fast prompt.
    local interactionSettings: InteractionSettings = {
        distance = 32,
        instantPrompts = false,
        proximityPrompts = false,
        clickDetectors = false,
    }
    local originalPrompts: {[ProximityPrompt]: PromptState} =
        setmetatable({}, {__mode = "k"}) :: any
    local originalClickDetectors: {[ClickDetector]: number} =
        setmetatable({}, {__mode = "k"}) :: any
    local interactionExtenderEnabled: boolean = false
    local InteractFeature: any = nil
    local interactionRefreshClock: number = 0

    -- Every channel follows its own row, so a row switched on with the card OFF
    -- works alone and a row switched off with the card ON really stops. The card
    -- is still a master switch: turning it on switches the rows on (visibly, not
    -- behind the scenes) and turning it off switches them off.
    local function promptsChannel(): boolean
        return interactionSettings.proximityPrompts or interactionSettings.instantPrompts
    end

    local function detectorsChannel(): boolean
        return interactionSettings.clickDetectors
    end

    local function anyChannel(): boolean
        return promptsChannel() or detectorsChannel()
    end

    local function updatePrompt(prompt: ProximityPrompt, original: PromptState): ()
        local distance: number = promptsChannel()
                and interactionSettings.distance or original.distance
        local hold: number = promptsChannel() and interactionSettings.instantPrompts
                and 0 or original.holdDuration
        if prompt.MaxActivationDistance ~= distance then prompt.MaxActivationDistance = distance end
        if prompt.HoldDuration ~= hold then prompt.HoldDuration = hold end
    end

    local function updateDetector(detector: ClickDetector, original: number): ()
        local distance: number = detectorsChannel()
                and interactionSettings.distance or original
        if detector.MaxActivationDistance ~= distance then detector.MaxActivationDistance = distance end
    end

    local function refreshInteractionExtender(): ()
        for prompt: ProximityPrompt, original: PromptState in pairs(originalPrompts) do
            if prompt.Parent then updatePrompt(prompt, original) end
        end
        for detector: ClickDetector, original: number in pairs(originalClickDetectors) do
            if detector.Parent then updateDetector(detector, original) end
        end
    end

    local function applyInteractionExtension(instance: Instance): ()
        if not anyChannel() then
            return
        end
        if instance:IsA("ProximityPrompt") then
            if originalPrompts[instance] == nil then
                originalPrompts[instance] = {
                    distance = instance.MaxActivationDistance,
                    holdDuration = instance.HoldDuration,
                }
            end
            updatePrompt(instance :: ProximityPrompt, originalPrompts[instance])
        elseif instance:IsA("ClickDetector") then
            if originalClickDetectors[instance] == nil then
                originalClickDetectors[instance] = instance.MaxActivationDistance
            end
            updateDetector(instance :: ClickDetector, originalClickDetectors[instance])
        end
    end

    -- Put every touched prompt/detector back to the values it had before we
    -- saw it, then forget it. Called when no channel is live any more.
    local function restoreInteractionExtender(): ()
        for prompt: ProximityPrompt, original: PromptState in pairs(originalPrompts) do
            if prompt.Parent then
                if prompt.MaxActivationDistance ~= original.distance then
                    prompt.MaxActivationDistance = original.distance
                end
                if prompt.HoldDuration ~= original.holdDuration then
                    prompt.HoldDuration = original.holdDuration
                end
            end
        end
        for detector: ClickDetector, original: number in pairs(originalClickDetectors) do
            if detector.Parent and detector.MaxActivationDistance ~= original then
                detector.MaxActivationDistance = original
            end
        end
        originalPrompts = setmetatable({}, {__mode = "k"}) :: any
        originalClickDetectors = setmetatable({}, {__mode = "k"}) :: any
    end

    local scanning: boolean = false
    local function startScan(): ()
        if scanning then return end
        scanning = true
        local scanConnection: any = featureConnections.InteractExtender
        task.spawn(function(): ()
            for index: number, instance: Instance in ipairs(workspace:GetDescendants()) do
                if featureConnections.InteractExtender ~= scanConnection then
                    -- Superseded: a newer generation owns the flag now.
                    scanning = false
                    return
                end
                applyInteractionExtension(instance)
                if index % 240 == 0 then
                    task.wait()
                end
            end
            scanning = false
        end)
    end

    -- Keep exactly the hooks the live channels need. Cheap when nothing changed,
    -- so a single row can call it on every click without a rescan.
    local function syncInteractions(): ()
        if not anyChannel() then
            disconnectFeatureConnection("InteractExtender")
            disconnectFeatureConnection("InteractExtenderRefresh")
            -- A scan suspended by this teardown belongs to the old generation;
            -- releasing the flag lets the next activation start its own.
            scanning = false
            restoreInteractionExtender()
            interactionRefreshClock = 0
            if InteractFeature then
                InteractFeature:SetStatus(nil)
            end
            return
        end
        if not featureConnections.InteractExtender then
            featureConnections.InteractExtender =
                workspace.DescendantAdded:Connect(applyInteractionExtension)
        end
        if not featureConnections.InteractExtenderRefresh then
            featureConnections.InteractExtenderRefresh = TaskManager:Connect(
                function(deltaTime: number): ()
                    interactionRefreshClock += deltaTime
                    if interactionRefreshClock >= 0.5 then
                        interactionRefreshClock = 0
                        refreshInteractionExtender()
                    end
                end
            , nil, "Proximity Prompts")
            -- First activation (card or row): pick up what already exists.
            startScan()
        else
            refreshInteractionExtender()
        end
        if InteractFeature and interactionExtenderEnabled then
            InteractFeature:SetStatus(
                tostring(math.round(interactionSettings.distance)) .. " studs"
            )
        end
    end

    -- Keep the checkbox, the saved value and the callback in step when the card
    -- itself switches a row.
    local function setRow(name: string, value: boolean): ()
        local controls: any = nil
        pcall(function(): ()
            if state and type(state.toggleControls) == "table" then
                controls = state.toggleControls
            end
        end)
        local control: any = controls and controls[InteractFeature.configKey .. "." .. name]
        if control and type(control.setChecked) == "function" then
            pcall(control.setChecked, value)
        end
    end

    local function toggleInteractionExtender(enabled: boolean): ()
        interactionExtenderEnabled = enabled
        if enabled then
            interactionSettings.proximityPrompts = true
            interactionSettings.clickDetectors = true
            setRow("Proximityprompts", true)
            setRow("Clickdetectors", true)
            -- The card was switched on: rescan once so nothing that exists right
            -- now is missed, even if the rows were already live.
            syncInteractions()
            startScan()
            return
        else
            interactionSettings.instantPrompts = false
            interactionSettings.proximityPrompts = false
            interactionSettings.clickDetectors = false
            setRow("Instantprompts", false)
            setRow("Proximityprompts", false)
            setRow("Clickdetectors", false)
        end
        syncInteractions()
    end

    InteractFeature = createUniversalFeature(
        "Proximity Prompts",
        "Extend prompt and click interaction range without auto-firing",
        24,
        toggleInteractionExtender,
        {categoryName = "Exploits", configKey = "Universal.InteractExtender"}
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
            syncInteractions()
        end
    )
    addToggleOption(
        InteractFeature,
        "Instant prompts",
        interactionSettings.instantPrompts,
        function(value: boolean): ()
            interactionSettings.instantPrompts = value
            syncInteractions()
        end
    )
    addToggleOption(
        InteractFeature,
        "Proximity prompts",
        interactionSettings.proximityPrompts,
        function(value: boolean): ()
            interactionSettings.proximityPrompts = value
            syncInteractions()
        end
    )
    addToggleOption(
        InteractFeature,
        "Click detectors",
        interactionSettings.clickDetectors,
        function(value: boolean): ()
            interactionSettings.clickDetectors = value
            syncInteractions()
        end
    )

    activeCleanup = function(): ()
        interactionExtenderEnabled = false
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
        activeCleanup()
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
