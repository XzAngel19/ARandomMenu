local Module = {
    Name = "MM2 Blurt Roles",
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
    assert(type(core) == "table", "MM2 Blurt Roles requires the MM2 core module")
    Module.Runtime = runtime
    local findMurderer: any = core.findMurderer
    local findSheriff: any = core.findSheriff
    local hasActiveRoundRoles: any = core.hasActiveRoundRoles
    local mm2Settings: any = core.mm2Settings

    -- ---------------------------------------------------------------------------
    -- Blurt Roles: announce the round's murderer and sheriff in the public chat.
    -- ---------------------------------------------------------------------------
    local blurtEnabled: boolean = false
    local blurtSignature: string = ""
    local blurtPending: boolean = false
    local lastBlurtAt: number = -math.huge

    local function sendPublicChat(message: string): boolean
        local sent: boolean = false

        local textChatOk: boolean = pcall(function(): ()
            local textChatService: TextChatService =
                game:GetService("TextChatService")
            if textChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
                return
            end
            local channels: Instance? = textChatService:FindFirstChild("TextChannels")
            local channel: Instance? = channels
                and (channels:FindFirstChild("RBXGeneral")
                    or channels:FindFirstChildWhichIsA("TextChannel"))
            if channel and channel:IsA("TextChannel") then
                (channel :: TextChannel):SendAsync(message)
                sent = true
            end
        end)

        if sent then
            return true
        end

        local legacyOk: boolean = pcall(function(): ()
            local events: Instance? = game:GetService("ReplicatedStorage")
                :FindFirstChild("DefaultChatSystemChatEvents")
            local say: Instance? = events
                and events:FindFirstChild("SayMessageRequest")
            if say and say:IsA("RemoteEvent") then
                (say :: RemoteEvent):FireServer(message, "All")
                sent = true
            end
        end)

        return sent and (textChatOk or legacyOk)
    end

    local function buildBlurtMessage(): (string?, string?)
        if not hasActiveRoundRoles() then
            return nil, nil
        end
        local murderer: Player? = findMurderer()
        local sheriff: Player? = findSheriff()
        if not murderer and not sheriff then
            return nil, nil
        end
        local murdererName: string = murderer and murderer.Name or "?"
        local sheriffName: string = sheriff and sheriff.Name or "?"
        local message: string = string.format(
            'Murder; "%s" Sheriff; "%s" | Wurst',
            murdererName,
            sheriffName
        )
        return message, murdererName .. "/" .. sheriffName
    end

    local function blurtRoles(manual: boolean): ()
        local message: string?, signature: string? = buildBlurtMessage()
        if not message then
            if manual then
                notify("MM2 · no roles to blurt yet.")
            end
            return
        end
        if not manual then
            if signature == blurtSignature and not mm2Settings.blurtRepeat then
                return
            end
            if os.clock() - lastBlurtAt < 2.5 then
                return
            end
        end
        blurtSignature = signature :: string
        lastBlurtAt = os.clock()
        task.spawn(function(): ()
            if sendPublicChat(message :: string) then
                notify("MM2 · blurted: " .. (message :: string))
            else
                notify("MM2 · the chat refused the message (filtered or disabled).")
            end
        end)
    end

    local function scheduleBlurt(): ()
        if not blurtEnabled or blurtPending then
            return
        end
        local message: string?, signature: string? = buildBlurtMessage()
        if not message then
            return
        end
        if signature == blurtSignature and not mm2Settings.blurtRepeat then
            return
        end
        blurtPending = true
        task.delay(math.max(mm2Settings.blurtDelay, 0), function(): ()
            blurtPending = false
            if blurtEnabled then
                blurtRoles(false)
            end
        end)
    end

    local unsubscribe: () -> () = core.onRoundRoles(function(active: boolean): ()
        if not active then
            blurtSignature = ""
            return
        end
        scheduleBlurt()
    end)

    local function toggleBlurtRoles(enabled: boolean): ()
        blurtEnabled = enabled
        disconnectFeatureConnection("MM2BlurtRoles")
        if not enabled then
            return
        end
        blurtSignature = ""
        local elapsed: number = 0
        featureConnections.MM2BlurtRoles = TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 1 then
                return
            end
            elapsed = 0
            if not hasActiveRoundRoles() then
                blurtSignature = ""
                return
            end
            scheduleBlurt()
        end)
    end

    local BlurtFeature = createUniversalFeature(
        "Blurt Roles",
        "Announces the murderer and sheriff in the public chat once per round",
        3,
        toggleBlurtRoles,
        {
            categoryName = "Fun",
            parent = MM2Scroll,
            registry = mm2Features,
        }
    )
    addNumberOption(
        BlurtFeature,
        "Delay",
        mm2Settings.blurtDelay,
        0,
        15,
        function(value: number): ()
            mm2Settings.blurtDelay = value
        end,
        "Seconds to wait after the roles are known before typing.",
        0.5
    )
    addToggleOption(
        BlurtFeature,
        "Repeat on change",
        mm2Settings.blurtRepeat,
        function(value: boolean): ()
            mm2Settings.blurtRepeat = value
        end,
        "Blurt again when the sheriff dies and the gun changes hands."
    )
    addActionOption(BlurtFeature, "Blurt now", function(): ()
        blurtRoles(true)
    end)
    addInformationOption(
        BlurtFeature,
        "This types in the real public chat: everyone reads it and you will be"
            .. " reported. Roblox also rate-limits and filters messages."
    )

    activeCleanup = function(): ()
        pcall(unsubscribe)
        toggleBlurtRoles(false)
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
