local Module = {
    Name = "MM2 Auto Play ID",
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
    assert(type(core) == "table", "MM2 Auto Play ID requires the MM2 core module")
    Module.Runtime = runtime
    local mm2Settings: any = core.mm2Settings

    local AutoPlaySound = Instance.new("Sound")
    AutoPlaySound.Name = "Wurst_MM2_AutoPlay"
    AutoPlaySound.Looped = true
    AutoPlaySound.Volume = 0.6
    AutoPlaySound.Parent = game:GetService("SoundService")
    local autoPlayLoadConnection: RBXScriptConnection? = nil
    local autoPlayGeneration: number = 0
    local autoPlayInput: TextBox? = nil
    local autoPlayConfigKey = "MM2.AutoPlayID.PlayID"
    local autoPlayStateKey = "MM2.AutoPlayID"

    local function stopAutoPlaySound(): ()
        autoPlayGeneration += 1
        if autoPlayLoadConnection then
            autoPlayLoadConnection:Disconnect()
            autoPlayLoadConnection = nil
        end
        AutoPlaySound:Stop()
        AutoPlaySound.SoundId = ""
    end

    local function clearAutoPlaySetting(message: string): ()
        stopAutoPlaySound()
        mm2Settings.autoPlayId = ""
        if type(configData) == "table" then
            if type(configData.values) == "table" then
                configData.values[autoPlayConfigKey] = nil
            end
            if type(configData.states) == "table" then
                configData.states[autoPlayStateKey] = false
            end
        end
        if autoPlayInput and autoPlayInput.Parent then
            autoPlayInput.Text = ""
        end
        queueConfigSave()
        notify(message)
    end

    local function playConfiguredSound(): ()
        stopAutoPlaySound()
        local numericId = string.match(mm2Settings.autoPlayId, "%d+")
        if not numericId then
            clearAutoPlaySetting("Invalid audio ID; playback disabled")
            return
        end

        AutoPlaySound.SoundId = "rbxassetid://" .. numericId
        local generation: number = autoPlayGeneration
        local function playWhenLoaded(): ()
            if generation ~= autoPlayGeneration or not AutoPlaySound.Parent then
                return
            end
            if not AutoPlaySound.IsLoaded then
                return
            end
            if autoPlayLoadConnection then
                autoPlayLoadConnection:Disconnect()
                autoPlayLoadConnection = nil
            end
            pcall(AutoPlaySound.Play, AutoPlaySound)
        end

        if AutoPlaySound.IsLoaded then
            playWhenLoaded()
            return
        end

        autoPlayLoadConnection = AutoPlaySound.Loaded:Connect(playWhenLoaded)
        task.delay(4, function(): ()
            if generation == autoPlayGeneration and not AutoPlaySound.IsLoaded then
                clearAutoPlaySetting("Audio ID is not authorized or unavailable")
            end
        end)
    end

    local function toggleAutoPlayId(enabled: boolean): ()
        if not enabled then
            stopAutoPlaySound()
            return
        end
        playConfiguredSound()
    end

    local AutoPlayFeature = createUniversalFeature(
        "Auto Play ID",
        "Loop a local Roblox audio asset",
        9,
        toggleAutoPlayId,
        {
            categoryName = "Other",
            parent = MM2Scroll,
            registry = mm2Features,
            restore = false,
        }
    )
    autoPlayInput = addTextOption(AutoPlayFeature, "Play ID", mm2Settings.autoPlayId, function(value)
        mm2Settings.autoPlayId = value
        if AutoPlaySound.Playing then
            playConfiguredSound()
        end
    end)

    activeCleanup = function(): ()
        toggleAutoPlayId(false)
                if AutoPlaySound then
                    stopAutoPlaySound()
                    AutoPlaySound:Destroy()
                end
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
