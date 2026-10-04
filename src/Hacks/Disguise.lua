export type Runtime = {
    framework: any,
    entity: any,
    host: any,
    services: any,
}

local Module = {
    Name = "Disguise",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function looksNumeric(text: string): boolean
    return string.match(text, "^%s*%d+%s*$") ~= nil
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local localPlayer: Player = host.LocalPlayer
    local spoofAvatar: any = context.services.spoofAvatar

    local runtime: any = {
        original = nil :: HumanoidDescription?,
        applied = nil :: HumanoidDescription?,
        userId = 0,
        busy = false,
    }

    local function currentHumanoid(): Humanoid?
        local character: Model? = localPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    end

    local function rememberOriginal(humanoid: Humanoid): ()
        if runtime.original then
            return
        end
        local ok: boolean, description: any = pcall(function(): any
            return humanoid:GetAppliedDescription()
        end)
        if ok and typeof(description) == "Instance" then
            runtime.original = description :: HumanoidDescription
        end
    end

    local function applyDescription(description: HumanoidDescription): boolean
        local humanoid: Humanoid? = currentHumanoid()
        if not humanoid then
            return false
        end
        rememberOriginal(humanoid :: Humanoid)
        local applied: boolean = pcall(function(): ()
            (humanoid :: Humanoid):ApplyDescription(description)
        end)
        return applied
    end

    local function publishEmotes(description: HumanoidDescription): number
        local collected: {any} = {}
        local ok: boolean, emotes: any = pcall(function(): any
            return (description :: any):GetEmotes()
        end)
        if ok and type(emotes) == "table" then
            for name: string, ids: any in pairs(emotes) do
                if type(ids) == "table" and type(ids[1]) == "number" then
                    table.insert(collected, {name = name, id = ids[1]})
                end
            end
        end
        table.sort(collected, function(left: any, right: any): boolean
            return left.name < right.name
        end)
        spoofAvatar.setEmotes(collected)
        return #collected
    end

    local disguise: any
    disguise = framework.Categories.Utility:CreateModule({
        Name = "Disguise",
        Category = "Fun",
        Order = 1,
        ConfigKey = "Universal.Disguise",
        Tooltip = "Wear another player's avatar, animations and emotes. "
            .. "Local only: the server and everyone else still see you.",
        Function = function(enabled: boolean): ()
            if not enabled then
                disguise:SetStatus(nil)
                local original: HumanoidDescription? = runtime.original
                runtime.applied = nil
                spoofAvatar.setDescription(nil)
                if original then
                    applyDescription(original :: HumanoidDescription)
                end
                return
            end
            local user: string = tostring(disguise.Options["User"].Value or "")
            disguise:SetStatus(user ~= "" and string.sub(user, 1, 15) or "waiting")

            disguise:Event(localPlayer.CharacterAdded, function(): ()
                if not disguise.Options["Keep on respawn"].Value then
                    return
                end
                local description: HumanoidDescription? = runtime.applied
                if not description then
                    return
                end
                task.spawn(function(): ()

                    task.wait(0.35)
                    applyDescription(description :: HumanoidDescription)
                end)
            end)

            task.spawn(function(): ()
                Module.wear(context, disguise, runtime, applyDescription, publishEmotes)
            end)
        end,
    })

    disguise:CreateTextBox({
        Name = "User",
        Default = "",
        Tooltip = "A user id or a username. Turning the module on wears them; "
            .. "Apply re-reads the box without switching off.",
    })
    disguise:CreateButton({
        Name = "Apply",
        Tooltip = "Fetch the avatar in the box and wear it now.",
        Function = function(): ()
            if not disguise.Enabled then
                disguise:Notify("switch the module on first")
                return
            end
            task.spawn(function(): ()
                Module.wear(context, disguise, runtime, applyDescription, publishEmotes)
            end)
        end,
    })
    disguise:CreateToggle({
        Name = "Keep on respawn",
        Default = true,
        Tooltip = "Re-apply the disguise every time you respawn.",
    })
    disguise:CreateToggle({
        Name = "Take animations",
        Default = true,
        Tooltip = "Wear the animation set that came with their bundle too. "
            .. "Off keeps your own walk and idle.",
    })
    disguise:CreateToggle({
        Name = "Take emotes",
        Default = true,
        Tooltip = "Read the emotes they have equipped into the emote player.",
    })
    disguise:CreateNote(
        "Local only. `ApplyDescription` changes what this client renders; the "
            .. "server, and every other player's screen, still show you."
    )

    activeCleanup = function(): ()
        local original: HumanoidDescription? = runtime.original
        if original then
            pcall(function(): ()
                local humanoid: Humanoid? = currentHumanoid()
                if humanoid then
                    (humanoid :: Humanoid):ApplyDescription(
                        original :: HumanoidDescription
                    )
                end
            end)
        end
        runtime.original = nil
        runtime.applied = nil
        spoofAvatar.setDescription(nil)
        spoofAvatar.setEmotes({})
    end
    Module.Initialized = true
    return disguise
end

function Module.wear(
    context: Runtime,
    disguise: any,
    runtime: any,
    applyDescription: (HumanoidDescription) -> boolean,
    publishEmotes: (HumanoidDescription) -> number
): ()
    if runtime.busy then
        return
    end
    local host: any = context.host
    local players: Players = host.Players
    local spoofAvatar: any = context.services.spoofAvatar
    local text: string = tostring(disguise.Options["User"].Value or "")
    if string.match(text, "^%s*$") then
        disguise:Notify("paste a user id or a name")
        return
    end

    runtime.busy = true
    local userId: number = 0
    if looksNumeric(text) then
        userId = tonumber(text) or 0
    else
        local resolved: boolean, id: any = pcall(function(): number
            return players:GetUserIdFromNameAsync(
                (string.gsub(text, "^%s*(.-)%s*$", "%1"))
            )
        end)
        if resolved and type(id) == "number" then
            userId = id
        end
    end
    if userId <= 0 then
        runtime.busy = false
        disguise:Notify("no such user")
        return
    end

    local fetched: boolean, description: any = pcall(function(): any
        return players:GetHumanoidDescriptionFromUserId(userId)
    end)
    runtime.busy = false
    if not fetched or typeof(description) ~= "Instance" then
        disguise:Notify("could not read that avatar")
        return
    end
    local target: HumanoidDescription = description :: HumanoidDescription

    if not disguise.Options["Take animations"].Value and runtime.original then
        local mine: any = runtime.original
        local copy: any = target
        for _, field: string in
            ipairs({
                "IdleAnimation",
                "WalkAnimation",
                "RunAnimation",
                "JumpAnimation",
                "FallAnimation",
                "ClimbAnimation",
                "SwimAnimation",
                "MoodAnimation",
            })
        do
            pcall(function(): ()
                copy[field] = mine[field]
            end)
        end
    end

    if not applyDescription(target) then
        disguise:Notify("no character to dress yet")
        return
    end
    runtime.userId = userId
    runtime.applied = target
    spoofAvatar.setDescription(target)

    local emoteCount: number = 0
    if disguise.Options["Take emotes"].Value then
        emoteCount = publishEmotes(target)
    end
    disguise:Notify(
        "wearing " .. tostring(userId)
            .. (emoteCount > 0 and (" · " .. tostring(emoteCount) .. " emotes") or "")
    )
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
