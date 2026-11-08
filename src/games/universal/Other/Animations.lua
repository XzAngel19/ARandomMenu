export type Runtime = {
    framework: any,
    host: any,
}

local Module = {
    Name = "Animations",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCard: any = nil
local activeCleanup: (() -> ())? = nil

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local Players: Players = host.Players or (game :: any):GetService("Players")
    local LocalPlayer: Player = host.LocalPlayer or Players.LocalPlayer
    local TaskManager: any = host.TaskManager
    local featureConnections: any = host.featureConnections
    local disconnectFeatureConnection: any = host.disconnectFeatureConnection
    local configData: any = host.configData

    local savedKey: string = "Universal.Animations.Saved"
    local savedAnims: {string} = {}
    if configData and configData.values and type(configData.values[savedKey]) == "table" then
        local stored: any = configData.values[savedKey]
        for _, v: any in ipairs(stored) do
            if type(v) == "string" and string.match(v, "^%d+$") then
                table.insert(savedAnims, v)
            elseif type(v) == "number" then
                table.insert(savedAnims, tostring(v))
            end
        end
    end

    local currentTrack: AnimationTrack? = nil
    local currentAnim: Animation? = nil
    local currentId: string = ""
    local currentSpeed: number = 1
    local isPlaying: boolean = false

    local function getAnimator(): Animator?
        local character: Model? = LocalPlayer and LocalPlayer.Character
        if not character then return nil end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then return nil end
        local animator: Animator? = humanoid:FindFirstChildOfClass("Animator") :: Animator?
        if animator then return animator end
        -- Fallback: create animator if missing (some rigs)
        local ok: boolean, created: any = pcall(function()
            local a = Instance.new("Animator")
            a.Parent = humanoid
            return a
        end)
        if ok and created then return created :: Animator end
        return nil
    end

    local function stopCurrent(): ()
        if currentTrack then
            pcall(function() currentTrack:Stop(0.1) end)
            pcall(function() currentTrack:Destroy() end)
            currentTrack = nil
        end
        if currentAnim then
            pcall(function() currentAnim:Destroy() end)
            currentAnim = nil
        end
        isPlaying = false
    end

    local function playAnimation(id: string, speed: number): ()
        local animator: Animator? = getAnimator()
        if not animator then
            if activeCard then activeCard:Notify("No animator found (respawn?)") end
            return
        end
        local numericId: string? = string.match(tostring(id or ""), "%d+")
        if not numericId then
            if activeCard then activeCard:Notify("Enter a valid animation ID") end
            return
        end
        stopCurrent()
        local anim: Animation = Instance.new("Animation")
        anim.Name = "Wurst_Animation_" .. numericId
        anim.AnimationId = "rbxassetid://" .. numericId
        local success: boolean, result: any = pcall(function()
            return animator:LoadAnimation(anim)
        end)
        if not success or not result then
            pcall(function() anim:Destroy() end)
            if activeCard then activeCard:Notify("Failed to load anim: " .. tostring(result or "invalid id")) end
            return
        end
        local track: AnimationTrack = result :: AnimationTrack
        -- Make it visible to others: high priority, looped
        pcall(function()
            track.Priority = Enum.AnimationPriority.Action
            track.Looped = true
        end)
        local cleanSpeed: number = tonumber(speed) or 1
        if cleanSpeed ~= cleanSpeed or cleanSpeed <= 0 then cleanSpeed = 1 end
        -- Clamp to Roblox sensible, but allow up to 999 as requested
        if cleanSpeed > 999 then cleanSpeed = 999 end
        if cleanSpeed < 0.1 then cleanSpeed = 0.1 end
        track:Play()
        track:AdjustSpeed(cleanSpeed)
        -- Loop forever: when stopped, replay if still enabled
        local myTrack: AnimationTrack = track
        local conn: RBXScriptConnection? = nil
        conn = track.Stopped:Connect(function()
            if conn then
                pcall(function() conn:Disconnect() end)
                conn = nil
            end
            if isPlaying and myTrack == currentTrack and activeCard and activeCard.Enabled then
                -- replay
                pcall(function()
                    myTrack:Play()
                    myTrack:AdjustSpeed(cleanSpeed)
                end)
            end
        end)
        if activeCard then
            activeCard:Clean(function()
                if conn then pcall(function() conn:Disconnect() end) end
            end)
        end
        currentTrack = track
        currentAnim = anim
        currentId = numericId
        currentSpeed = cleanSpeed
        isPlaying = true
        if activeCard then
            activeCard:SetStatus("Playing " .. numericId .. " · " .. tostring(cleanSpeed) .. "x")
        end
    end

    local function saveCurrent(): ()
        local id: string? = string.match(tostring(currentId or activeCard and activeCard.Options["Animation ID"].Value or ""), "%d+")
        if not id then
            -- Try from textbox
            local raw: any = activeCard and activeCard.Options["Animation ID"] and activeCard.Options["Animation ID"].Value or ""
            id = string.match(tostring(raw or ""), "%d+")
        end
        if not id then
            if activeCard then activeCard:Notify("Enter an animation ID first") end
            return
        end
        for _, existing: string in ipairs(savedAnims) do
            if existing == id then
                if activeCard then activeCard:Notify("Already saved: " .. id) end
                return
            end
        end
        table.insert(savedAnims, 1, id)
        -- Keep max 20
        while #savedAnims > 20 do table.remove(savedAnims) end
        if configData and configData.values then
            configData.values[savedKey] = savedAnims
            if host.queueConfigSave then pcall(host.queueConfigSave) end
        end
        if activeCard and activeCard.Options["Saved Animations"] then
            pcall(function() activeCard.Options["Saved Animations"]:Refresh() end)
        end
        if activeCard then activeCard:Notify("Saved " .. id) end
    end

    local function refreshSavedList(card: any): ()
        -- The list is a CreateList; its Items function reads savedAnims
        if card and card.Options["Saved Animations"] then
            pcall(function() card.Options["Saved Animations"]:Refresh() end)
        end
    end

    local card: any = framework.Categories.World:CreateModule({
        Name = "Animations",
        Category = "World",
        ConfigKey = "Universal.Animations",
        Tooltip = "Plays any animation ID on your character with Animator, visible to others. Save IDs and click to replay.",
        Function = function(enabled: boolean): ()
            if not enabled then
                stopCurrent()
                if activeCard then activeCard:SetStatus(nil) end
                return
            end
            local id: string = tostring(card.Options["Animation ID"].Value or "")
            local speed: number = tonumber(card.Options["Speed"].Value) or 1
            if string.match(id, "%d+") then
                playAnimation(id, speed)
            else
                if activeCard then activeCard:SetStatus("Enter an ID and press Save or Play") end
            end
        end,
    })

    activeCard = card

    card:CreateTextBox({
        Name = "Animation ID",
        Placeholder = "rbxassetid or numbers only, e.g. 507777826",
        Default = "",
        Tooltip = "Animation asset ID (numbers only). Works with any Roblox animation. Example: 507777826 (walk).",
    })

    card:CreateSlider({
        Name = "Speed",
        Min = 1,
        Max = 5,
        Step = 0.1,
        Default = 1,
        Tooltip = "Playback speed: 1 = normal, 0.5 = half, 5 = 5x, up to 999 if typed manually. Roblox allows high values.",
    })

    -- The Speed slider's manual input is checked via valueControls, but we also ensure the option can hold up to 999
    -- by post-processing the slider's apply. The framework already allows typing beyond Max, so we just need to
    -- ensure the play function clamps to 999, not to 5.

    card:CreateButton({
        Name = "Play Animation",
        Tooltip = "Play the ID above at the selected speed (visible to others via Animator).",
        Function = function()
            local id: string = tostring(card.Options["Animation ID"].Value or "")
            local speed: number = tonumber(card.Options["Speed"].Value) or 1
            if not string.match(id, "%d+") then
                card:Notify("Enter an animation ID first")
                return
            end
            -- Ensure card is ON, then play
            if not card.Enabled then
                card:Toggle(true)
                -- play will be called via the toggle, but also call now to ensure speed is current
                task.defer(function()
                    if card.Enabled then playAnimation(id, speed) end
                end)
            else
                playAnimation(id, speed)
            end
        end,
    })

    card:CreateButton({
        Name = "Save Animation",
        Tooltip = "Save the current ID to the list below. Max 20, persists via config.",
        Function = saveCurrent,
    })

    -- Saved list: clicking an entry replays it (via selection callback)
    local savedList: any = card:CreateList({
        Name = "Saved Animations",
        Items = function(): {string}
            local out: {string} = {}
            for _, id: string in ipairs(savedAnims) do
                table.insert(out, id)
            end
            return out
        end,
        Default = {},
        EmptyText = "No saved yet. Enter an ID and press Save Animation.",
        Function = function(selected: string, all: {string})
            if type(selected) ~= "string" or selected == "" then return end
            -- selected is the last clicked item (or first of all)
            local id: string = selected
            -- If multiple selected, take the last one the user clicked
            if #all > 0 then
                -- Find which one was just added/selected
                -- For simplicity, use selected, but if selected is a table (when Single=false, it may be the list),
                -- handle both cases
                if type(selected) == "table" then
                    -- When Single false, selected is the whole list, take last
                    id = all[#all]
                end
            end
            if not string.match(id or "", "%d+") then return end
            local speed: number = tonumber(card.Options["Speed"].Value) or 1
            -- Fill textbox for visibility
            if card.Options["Animation ID"] then
                -- Try to set the TextBox text and the Value
                pcall(function()
                    local opt: any = card.Options["Animation ID"]
                    if opt.Object then
                        local tb: any = opt.Object:FindFirstChildOfClass("TextBox")
                            or opt.Object:FindFirstChild("TextBox")
                            or opt.Object:FindFirstChild("Input", true)
                        if tb then tb.Text = id end
                    end
                    opt.Value = id
                end)
            end
            currentId = id
            if not card.Enabled then
                card:Toggle(true)
                -- defer play until toggle completes
                task.defer(function()
                    if card.Enabled then playAnimation(id, speed) end
                end)
            else
                playAnimation(id, speed)
            end
            -- Deselect so next click on same ID still fires
            task.defer(function()
                pcall(function() savedList:Set(id, false) end)
            end)
        end,
        OnRemove = function(id: string)
            for i: number, v: string in ipairs(savedAnims) do
                if v == id then
                    table.remove(savedAnims, i)
                    break
                end
            end
            if configData and configData.values then
                configData.values[savedKey] = savedAnims
                if host.queueConfigSave then pcall(host.queueConfigSave) end
            end
            refreshSavedList(card)
        end,
        Tooltip = "Click an ID to play it. Saved IDs persist across sessions.",
    })

    -- Keep speed updates live: if already playing, adjust
    local origSpeedOption: any = card.Options["Speed"]
    if origSpeedOption and origSpeedOption.Object then
        -- Hook via the framework's valueControls if available, otherwise poll
        -- The CreateSlider's Function is called on change, so we use it:
        -- We need to override the slider's callback to also adjust track speed.
        -- Instead, we connect via the option's callback if possible.
        -- The card:CreateSlider already takes a Function, but we didn't pass one that updates track.
        -- So we add a listener via the host's valueControls or via a loop.
        -- Simplest: connect to the slider's change via polling in a Render loop.
        local lastSpeed: number = tonumber(origSpeedOption.Value) or 1
        card:Render(function()
            if not card.Enabled or not currentTrack then return end
            local now: number = tonumber(card.Options["Speed"].Value) or lastSpeed
            if now ~= lastSpeed then
                lastSpeed = now
                local clean: number = math.clamp(now, 0.1, 999)
                pcall(function() currentTrack:AdjustSpeed(clean) end)
                currentSpeed = clean
                if card then card:SetStatus("Playing " .. currentId .. " · " .. tostring(clean) .. "x") end
            end
        end)
    end

    -- Handle respawn: replay if still enabled
    if LocalPlayer and LocalPlayer.CharacterAdded then
        local conn: RBXScriptConnection = LocalPlayer.CharacterAdded:Connect(function()
            if card.Enabled and currentId ~= "" then
                task.wait(1)
                if card.Enabled then
                    playAnimation(currentId, currentSpeed)
                end
            end
        end)
        card:Clean(function() pcall(function() conn:Disconnect() end) end)
    end

    -- Also handle Humanoid died: stop
    card:Clean(function()
        stopCurrent()
    end)

    activeCleanup = function()
        stopCurrent()
        if card and card.Enabled then pcall(function() card:Toggle(false) end) end
    end

    Module.Initialized = true
    return card
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
        activeCleanup = nil
    end
    if activeCard and activeCard.Enabled then
        pcall(function() activeCard:Toggle(false) end)
    end
    activeCard = nil
    Module.Initialized = false
end

return Module
