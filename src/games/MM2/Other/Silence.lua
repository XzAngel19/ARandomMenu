local Module = {
    Name = "MM2 Silence",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local activeCleanup: () -> () = function(): () end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    local core: any = state.mm2Core
    assert(type(core) == "table", "MM2 Silence requires the MM2 core module")
    Module.Runtime = runtime
    local findMM2Map: any = core.findMM2Map

    local mutedRadioSounds = setmetatable({}, {__mode = "k"})
    local mutedTrapSounds = setmetatable({}, {__mode = "k"})

    local function restoreMutedSounds(cache)
        for sound, volume in pairs(cache) do
            if sound and sound.Parent then
                sound.Volume = volume
            end
        end
    end

    local function toggleMuteOtherRadios(enabled)
        disconnectFeatureConnection("MM2MuteRadios")
        restoreMutedSounds(mutedRadioSounds)
        mutedRadioSounds = setmetatable({}, {__mode = "k"})

        if not enabled then
            return
        end

        local function muteRadio(sound)
            if not sound:IsA("Sound") then
                return
            end
            local owner = nil
            local ancestor = sound.Parent
            while ancestor and not owner do
                owner = Players:GetPlayerFromCharacter(ancestor)
                ancestor = ancestor.Parent
            end
            if not owner or owner == LocalPlayer then
                return
            end
            local lowerName = string.lower(sound.Name)
            local parentName = sound.Parent and string.lower(sound.Parent.Name) or ""
            if string.find(lowerName, "radio", 1, true)
                or string.find(lowerName, "music", 1, true)
                or string.find(parentName, "radio", 1, true) then
                if mutedRadioSounds[sound] == nil then
                    mutedRadioSounds[sound] = sound.Volume
                end
                sound.Volume = 0
            end
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                for _, object in ipairs(player.Character:GetDescendants()) do
                    muteRadio(object)
                end
            end
        end
        featureConnections.MM2MuteRadios = workspace.DescendantAdded:Connect(muteRadio)
    end

    local function toggleMuteTrapSounds(enabled)
        disconnectFeatureConnection("MM2MuteTraps")
        restoreMutedSounds(mutedTrapSounds)
        mutedTrapSounds = setmetatable({}, {__mode = "k"})

        if not enabled then
            return
        end

        local function muteTrap(sound)
            if not sound:IsA("Sound") then
                return
            end
            local ancestor = sound:FindFirstAncestor("Trap")
                or sound:FindFirstAncestor("TrapVisual")
            local parentName = sound.Parent and string.lower(sound.Parent.Name) or ""
            if ancestor or string.find(parentName, "trap", 1, true) then
                if mutedTrapSounds[sound] == nil then
                    mutedTrapSounds[sound] = sound.Volume
                end
                sound.Volume = 0
            end
        end

        local map = findMM2Map()
        for _, object in ipairs((map or workspace):GetDescendants()) do
            muteTrap(object)
        end
        featureConnections.MM2MuteTraps = workspace.DescendantAdded:Connect(muteTrap)
    end

    local SilenceFeature = createUniversalFeature(
        "Silence",
        "Radio and trap audio controls",
        8,
        function() end,
        {
            category = true,
            categoryName = "Other",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addToggleOption(SilenceFeature, "Other radios", false, toggleMuteOtherRadios)
    addToggleOption(SilenceFeature, "Trap sounds", false, toggleMuteTrapSounds)

    activeCleanup = function(): ()
        toggleMuteOtherRadios(false)
                toggleMuteTrapSounds(false)
    end
    Module.Events = featureConnections
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    if not Module.Initialized then
        return
    end
    Module.Initialized = false
    pcall(activeCleanup)
    activeCleanup = function(): () end
    Module.Events = {}
    Module.Runtime = nil
end

return Module
