--!strict
--
-- Friend list.
--
-- One list of people nothing in the menu is allowed to touch. It used to live
-- inside the MM2 module, which meant the protection vanished the moment you
-- played anything else — so it is universal now, and every combat module
-- (Kill Aura, TriggerBot, Fling, MM2's shoot helpers) asks the same question
-- here: `state.friendList.isProtected(player)`.
--
-- Always-on module: there is nothing to switch on. The list is either empty or
-- it is not.

export type Runtime = {
    framework: any,
    entity: any,
    host: any,
}

local Module = {
    Name = "FriendList",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local activeCleanup: (() -> ())? = nil

local function splitNames(text: string): {[string]: boolean}
    local names: {[string]: boolean} = {}
    for name: string in string.gmatch(string.lower(text), "[^,%s]+") do
        names[name] = true
    end
    return names
end

local function countKeys(map: {[string]: boolean}): number
    local total: number = 0
    for _ in pairs(map) do
        total += 1
    end
    return total
end

function Module.init(context: Runtime): any
    local host: any = context.host
    local framework: any = context.framework
    local players: Players = host.Players
    local localPlayer: Player = host.LocalPlayer
    local state: any = host.state

    local list: any = {
        names = {} :: {[string]: boolean},
        userIds = {} :: {[number]: boolean},
        protectRobloxFriends = true,
        protectTeam = false,
    }

    function list.isProtected(player: Player?): boolean
        if not player then
            return true
        end
        if player == localPlayer then
            return true
        end
        if list.userIds[player.UserId] then
            return true
        end
        if list.protectTeam
            and player.Team ~= nil
            and player.Team == localPlayer.Team
            and not player.Neutral then
            return true
        end
        return list.names[string.lower(player.Name)] == true
            or list.names[string.lower(player.DisplayName)] == true
    end

    function list.count(): number
        return countKeys(list.names) + countKeys(list.userIds :: any)
    end

    -- Roblox friendship is a web request per player, so it is resolved once
    -- per player rather than per attack decision.
    function list.refreshRobloxFriends(): ()
        list.userIds = {}
        if not list.protectRobloxFriends then
            return
        end
        for _, player: Player in ipairs(players:GetPlayers()) do
            if player == localPlayer then
                continue
            end
            local ok: boolean, isFriend: any = pcall(
                localPlayer.IsFriendsWithAsync,
                localPlayer,
                player.UserId
            )
            if ok and isFriend then
                list.userIds[player.UserId] = true
            end
        end
    end

    state.friendList = list
    -- Kept for the game modules that already ask this question by name.
    state.isProtectedTarget = list.isProtected

    local friends: any
    friends = framework.Categories.Utility:CreateModule({
        Name = "Friend List",
        Category = "Utility",
        Order = 1,
        Kind = "group",
        Tooltip = "Players listed here are never targeted by Kill Aura, "
            .. "TriggerBot, Fling or any game module.",
        Function = function(): () end,
    })

    local namesBox: any
    local statusNote: any

    local function publish(): ()
        if statusNote then
            statusNote.Value = list.count()
        end
        if host.notify and list.count() > 0 then
            -- Silent by default: the toast only fires when the list changes
            -- through the Add/Clear actions below.
        end
    end

    namesBox = friends:CreateTextBox({
        Name = "Protected names",
        Default = "",
        Tooltip = "Comma-separated. Matches display names too.",
        Function = function(value: string): ()
            list.names = splitNames(value)
            publish()
        end,
    })

    friends:CreateToggle({
        Name = "Protect Roblox friends",
        Default = true,
        Tooltip = "Everyone in the server you are actually friends with.",
        Function = function(value: boolean): ()
            list.protectRobloxFriends = value
            task.spawn(list.refreshRobloxFriends)
        end,
    })

    friends:CreateToggle({
        Name = "Protect team-mates",
        Default = false,
        Tooltip = "Adds everyone sharing your team, on top of the list.",
        Function = function(value: boolean): ()
            list.protectTeam = value
        end,
    })

    friends:CreateButton({
        Name = "Add nearest player",
        Tooltip = "Puts whoever is closest to you on the list.",
        Function = function(): ()
            local entityLibrary: any = context.entity
            if not entityLibrary then
                return
            end
            entityLibrary:Refresh()
            local closest: any = nil
            local closestDistance: number = math.huge
            for _, entity: any in ipairs(entityLibrary.List) do
                if entity.Distance < closestDistance then
                    closest = entity
                    closestDistance = entity.Distance
                end
            end
            if not closest then
                friends:Notify("nobody nearby")
                return
            end
            list.names[string.lower(closest.Player.Name)] = true
            if namesBox and namesBox.Object then
                local current: string = tostring(namesBox.Value or "")
                namesBox.Value = current == ""
                    and closest.Player.Name
                    or (current .. ", " .. closest.Player.Name)
                pcall(function(): ()
                    namesBox.Object.Text = namesBox.Value
                end)
            end
            friends:Notify(closest.Player.Name .. " protected")
            publish()
        end,
    })

    friends:CreateButton({
        Name = "Clear list",
        Function = function(): ()
            list.names = {}
            if namesBox and namesBox.Object then
                namesBox.Value = ""
                pcall(function(): ()
                    namesBox.Object.Text = ""
                end)
            end
            friends:Notify("list cleared")
            publish()
        end,
    })

    friends:CreateNote(
        "Protection is checked by every targeting module, in every game."
    )

    local connection: RBXScriptConnection = players.PlayerAdded:Connect(function(): ()
        task.defer(list.refreshRobloxFriends)
    end)
    task.spawn(list.refreshRobloxFriends)

    activeCleanup = function(): ()
        pcall(function(): ()
            connection:Disconnect()
        end)
        if state.friendList == list then
            state.friendList = nil
        end
    end
    Module.Initialized = true
    return friends
end

function Module.destroy(): ()
    if activeCleanup then
        pcall(activeCleanup)
    end
    activeCleanup = nil
    Module.Initialized = false
end

return Module
