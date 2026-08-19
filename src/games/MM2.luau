--!strict
local Module = {
    Name = "MM2",
    PlaceId = 142823291,
    Events = {} :: {[string]: any},
    Initialized = false,
    Menu = nil :: any,
    Runtime = nil :: any,
}

local moduleCleanup: () -> () = function(): () end

local function buildMM2Features()
local MM2Effects = create("Folder", {
    Parent = ScreenGui,
    Name = "MM2Effects",
})
local RoleEffects = create("Folder", {
    Parent = MM2Effects,
    Name = "RoleESP",
})
local GunEffects = create("Folder", {
    Parent = MM2Effects,
    Name = "GunESP",
})
local TrapEffects = create("Folder", {
    Parent = MM2Effects,
    Name = "TrapESP",
})
local CoinEffects = create("Folder", {
    Parent = MM2Effects,
    Name = "CoinChams",
})

local mm2RoundData: {[any]: any} = {}
local mm2GameplayRemotes: Instance? = nil
local mm2RoleRemote: RemoteFunction? = nil
local roleRefreshRunning: boolean = false
local lastRoleRefreshAt: number = -math.huge
local roundLifecycleActive: boolean? = nil
local roleRefreshGeneration: number = 0

pcall(function()
    local replicatedStorage: ReplicatedStorage =
        game:GetService("ReplicatedStorage")
    local remotes: Instance? = replicatedStorage:WaitForChild("Remotes", 5)
    local gameplay: Instance? = remotes and remotes:WaitForChild("Gameplay", 5)
    if not gameplay then
        return
    end
    mm2GameplayRemotes = gameplay
    local getCurrentPlayerData: Instance? = gameplay:FindFirstChild(
        "GetCurrentPlayerData"
    )
    if getCurrentPlayerData and getCurrentPlayerData:IsA("RemoteFunction") then
        mm2RoleRemote = getCurrentPlayerData
        local success: boolean, result: any = pcall(
            getCurrentPlayerData.InvokeServer,
            getCurrentPlayerData
        )
        if success and type(result) == "table" then
            mm2RoundData = result
            lastRoleRefreshAt = os.clock()
        end
    end
end)

local mm2Settings = {
    autoGetGunDelay = 0.25,
    shootMode = "Manual",
    shootKey = Enum.KeyCode.Q,
    shootTarget = "",
    showMissCooldown = true,
    predictionRtt = 0.08,
    gunLeadBias = 0,
    getGunKey = Enum.KeyCode.G,
    instantRoleNotify = false,
    roleEspAll = false,
    roleEspInnocent = false,
    roleEspMurderer = false,
    roleEspSheriff = false,
    innocentColor = Color3.fromRGB(35, 120, 60),
    innocentTransparency = 0.62,
    deadColor = Color3.fromRGB(105, 105, 105),
    deadTransparency = 0.58,
    murdererColor = Color3.fromRGB(145, 25, 25),
    murdererTransparency = 0.55,
    sheriffColor = Color3.fromRGB(45, 65, 155),
    sheriffTransparency = 0.55,
    heroColor = Color3.fromRGB(180, 145, 25),
    heroTransparency = 0.55,
    coinColor = Color3.fromRGB(230, 220, 65),
    coinTransparency = 0.8,
    trapColor = Color3.fromRGB(145, 25, 25),
    trapTransparency = 0.7,
    gunColor = Color3.fromRGB(160, 65, 215),
    gunTransparency = 0.5,
    autoPlayId = "",
}

local friendSettings = {
    names = {},
    protectRobloxFriends = true,
    friendUserIds = {},
}

local function refreshFriendProtection()
    friendSettings.friendUserIds = {}
    if friendSettings.protectRobloxFriends then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local success, friend = pcall(
                    LocalPlayer.IsFriendsWithAsync,
                    LocalPlayer,
                    player.UserId
                )
                if success and friend then
                    friendSettings.friendUserIds[player.UserId] = true
                end
            end
        end
    end
end

state.isProtectedTarget = function(player)
    if not player or player == LocalPlayer then
        return true
    end
    if friendSettings.friendUserIds[player.UserId] then
        return true
    end
    local name = string.lower(player.Name)
    local displayName = string.lower(player.DisplayName)
    return friendSettings.names[name] == true
        or friendSettings.names[displayName] == true
end

featureConnections.MM2FriendPlayerAdded = Players.PlayerAdded:Connect(function()
    task.defer(refreshFriendProtection)
end)
task.spawn(refreshFriendProtection)

local function clearEffects(folder)
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("ObjectValue") and child.Value then
            child.Value:Destroy()
        end
        child:Destroy()
    end
end

local function getWeaponFromContainer(
    container: Instance?,
    weaponName: string,
    weaponTag: string
): Tool?
    if not container then
        return nil
    end

    for _, child: Instance in ipairs(container:GetChildren()) do
        if child:IsA("Tool") then
            if CollectionService:HasTag(child, weaponTag) then
                return child
            end

            if child.Name == weaponName then
                if weaponName == "Gun" then
                    local shootRemote: Instance? = child:FindFirstChild("Shoot")
                    if shootRemote and shootRemote:IsA("RemoteEvent") then
                        return child
                    end
                elseif weaponName == "Knife" then
                    local events: Instance? = child:FindFirstChild("Events")
                    local knifeThrown: Instance? = events
                        and events:FindFirstChild("KnifeThrown")
                    local knifeStabbed: Instance? = events
                        and events:FindFirstChild("KnifeStabbed")
                    if knifeThrown and knifeThrown:IsA("RemoteEvent")
                        and knifeStabbed and knifeStabbed:IsA("RemoteEvent") then
                        return child
                    end
                end
            end
        end
    end
    return nil
end

local function getPlayerWeapon(
    player: Player,
    weaponName: string,
    equippedOnly: boolean?
): Tool?
    local tag: string = "Weapon_" .. weaponName
    local equipped: Tool? = getWeaponFromContainer(player.Character, weaponName, tag)
    if equipped or equippedOnly then
        return equipped
    end
    return getWeaponFromContainer(
        player:FindFirstChildOfClass("Backpack"),
        weaponName,
        tag
    )
end

local function isPlayerAlive(player: Player): boolean
    local humanoid: Humanoid? = player.Character
        and player.Character:FindFirstChildOfClass("Humanoid")
        :: Humanoid?
    return humanoid ~= nil and humanoid.Health > 0
end

local function findMM2Role(toolName: string, excludedPlayer: Player?): Player?
    for _, player: Player in ipairs(Players:GetPlayers()) do
        if player ~= excludedPlayer
            and isPlayerAlive(player)
            and getPlayerWeapon(player, toolName) then
            return player
        end
    end
    return nil
end

local function playerFromRoundKey(key: any, data: any): Player?
    if typeof(key) == "Instance" and key:IsA("Player") then
        return key
    end

    local player: Player? = nil
    local namedPlayer: Instance? = Players:FindFirstChild(tostring(key))
    if namedPlayer and namedPlayer:IsA("Player") then
        player = namedPlayer
    end

    if type(data) == "table" then
        if data.Name then
            local namedFromData: Instance? =
                Players:FindFirstChild(tostring(data.Name))
            player = namedFromData and namedFromData:IsA("Player")
                and namedFromData
                or nil
        end
        if not player and data.UserId then
            local userId = tonumber(data.UserId)
            if userId then
                local success, resolvedPlayer = pcall(
                    Players.GetPlayerByUserId,
                    Players,
                    userId
                )
                player = success and resolvedPlayer or nil
            end
        end
    end

    return player
end

local function getRoundRole(player: Player): string?
    for key: any, data: any in pairs(mm2RoundData) do
        if playerFromRoundKey(key, data) == player and type(data) == "table" then
            local role: any = data.Role
            if role == "Murderer"
                or role == "Sheriff"
                or role == "Hero"
                or role == "Innocent" then
                return role
            end
        end
    end
    return nil
end

local function requestRoleRefresh(): ()
    if not mm2RoleRemote
        or roleRefreshRunning
        or os.clock() - lastRoleRefreshAt < 0.8 then
        return
    end

    roleRefreshRunning = true
    local generation: number = roleRefreshGeneration
    task.spawn(function(): ()
        local success: boolean, result: any = pcall(
            mm2RoleRemote.InvokeServer,
            mm2RoleRemote
        )
        roleRefreshRunning = false
        lastRoleRefreshAt = os.clock()
        if success
            and generation == roleRefreshGeneration
            and roundLifecycleActive ~= false
            and type(result) == "table" then
            mm2RoundData = result
        end
    end)
end

local function hasMurdererCollisionGroup(player: Player): boolean
    local character: Model? = player.Character
    if not character then
        return false
    end
    for _, child: Instance in ipairs(character:GetChildren()) do
        if child:IsA("BasePart") and child.CollisionGroup == "Murderer" then
            return true
        end
    end
    return false
end

local function getPlayerRole(player: Player): string?
    local roundRole: string? = getRoundRole(player)
    if hasMurdererCollisionGroup(player) or getPlayerWeapon(player, "Knife") then
        return "Murderer"
    end
    if getPlayerWeapon(player, "Gun") then
        return roundRole == "Hero" and "Hero" or "Sheriff"
    end
    return roundRole
end

local function findPlayerByRoundRole(role: string): Player?
    for key, data in pairs(mm2RoundData) do
        if type(data) == "table" and data.Role == role then
            local player: Player? = playerFromRoundKey(key, data)
            if player and isPlayerAlive(player) then
                return player
            end
        end
    end
    return nil
end

local function hasActiveRoundRoles(): boolean
    if roundLifecycleActive == false then
        return false
    end
    if findMM2Role("Knife") or findMM2Role("Gun") then
        roundLifecycleActive = true
        return true
    end
    requestRoleRefresh()

    -- A table containing only Innocents can be residual countdown/lobby data.
    -- Requiring a round-defining role keeps every cham off in the lobby.
    for key, data in pairs(mm2RoundData) do
        if playerFromRoundKey(key, data)
            and type(data) == "table"
            and (data.Role == "Murderer"
                or data.Role == "Sheriff"
                or data.Role == "Hero") then
            return true
        end
    end
    return false
end

local function findMurderer(): Player?
    requestRoleRefresh()
    for _, player: Player in ipairs(Players:GetPlayers()) do
        if isPlayerAlive(player) and hasMurdererCollisionGroup(player) then
            return player
        end
    end
    return findMM2Role("Knife") or findPlayerByRoundRole("Murderer")
end

local function findSheriff(): Player?
    requestRoleRefresh()
    return findMM2Role("Gun")
        or findPlayerByRoundRole("Sheriff")
        or findPlayerByRoundRole("Hero")
end

local function findMM2Map(): Instance?
    for _, object: Instance in ipairs(workspace:GetChildren()) do
        if object:FindFirstChild("CoinContainer")
            and object:FindFirstChild("Spawns") then
            return object
        end
    end
    return nil
end

local function findDroppedGun(): (Model | BasePart)?
    local map: Instance? = findMM2Map()
    local candidate: Instance? = (map and map:FindFirstChild("GunDrop", true))
        or workspace:FindFirstChild("GunDrop", true)
    if candidate and candidate:IsA("Model") then
        return candidate
    end
    if candidate and candidate:IsA("BasePart") then
        return candidate
    end
    return nil
end

local function createMM2Marker(folder, adornee, labelText, color, transparency)
    local highlight = Instance.new("Highlight")
    highlight.Name = labelText .. "Highlight"
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.FillTransparency = transparency or 0.68
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0
    highlight.Parent = adornee

    local highlightReference = Instance.new("ObjectValue")
    highlightReference.Name = labelText .. "HighlightReference"
    highlightReference.Value = highlight
    highlightReference.Parent = folder

    local head = adornee:IsA("Model")
        and (adornee:FindFirstChild("Head")
            or adornee:FindFirstChild("HumanoidRootPart"))
        or adornee

    if head and head:IsA("BasePart") then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = labelText .. "Label"
        billboard.Adornee = head
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(130, 28)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.Parent = head

        local billboardReference = Instance.new("ObjectValue")
        billboardReference.Name = labelText .. "LabelReference"
        billboardReference.Value = billboard
        billboardReference.Parent = folder

        local text = Instance.new("TextLabel")
        text.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        text.BackgroundTransparency = 0.2
        text.BorderColor3 = color
        text.BorderSizePixel = 1
        text.Font = Enum.Font.GothamBold
        text.Size = UDim2.fromScale(1, 1)
        text.Text = labelText
        text.TextColor3 = color
        text.TextSize = 13
        text.Parent = billboard
    end
end

local function createMM2Cham(folder, adornee, color, transparency)
    local highlight = Instance.new("Highlight")
    highlight.Name = "RTMCham"
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.FillTransparency = transparency
    highlight.OutlineColor = color
    highlight.OutlineTransparency = math.clamp(transparency + 0.15, 0, 1)
    highlight.Parent = adornee

    local reference = Instance.new("ObjectValue")
    reference.Name = "ChamReference"
    reference.Value = highlight
    reference.Parent = folder
end

local function rebuildRoleEsp()
    clearEffects(RoleEffects)
    if not hasActiveRoundRoles() then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local role: string? = getPlayerRole(player) or "Innocent"

            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            local isDead = humanoid and humanoid.Health <= 0
            local show = mm2Settings.roleEspAll
                and ((role == "Innocent" and mm2Settings.roleEspInnocent)
                or (role == "Murderer" and mm2Settings.roleEspMurderer)
                or ((role == "Sheriff" or role == "Hero")
                    and mm2Settings.roleEspSheriff))

            if show and isDead then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.deadColor,
                    mm2Settings.deadTransparency
                )
            elseif show and role == "Murderer" then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.murdererColor,
                    mm2Settings.murdererTransparency
                )
            elseif show and role == "Sheriff" then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.sheriffColor,
                    mm2Settings.sheriffTransparency
                )
            elseif show and role == "Hero" then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.heroColor,
                    mm2Settings.heroTransparency
                )
            elseif show and role == "Innocent" then
                createMM2Cham(
                    RoleEffects,
                    player.Character,
                    mm2Settings.innocentColor,
                    mm2Settings.innocentTransparency
                )
            end
        end
    end
end

local function refreshRoleEspConnection()
    disconnectFeatureConnection("MM2RoleESP")
    clearEffects(RoleEffects)

    if not mm2Settings.roleEspAll
        or not (mm2Settings.roleEspInnocent
            or mm2Settings.roleEspMurderer
            or mm2Settings.roleEspSheriff) then
        return
    end

    rebuildRoleEsp()
    local elapsed = 0
    featureConnections.MM2RoleESP = TaskManager:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed >= 0.75 then
            elapsed = 0
            rebuildRoleEsp()
        end
    end)
end

local function toggleRoleEsp(enabled)
    mm2Settings.roleEspAll = enabled
    refreshRoleEspConnection()
end

local function toggleInnocentEsp(enabled)
    mm2Settings.roleEspInnocent = enabled
    refreshRoleEspConnection()
end

local function toggleMurdererEsp(enabled)
    mm2Settings.roleEspMurderer = enabled
    refreshRoleEspConnection()
end

local function toggleSheriffEsp(enabled)
    mm2Settings.roleEspSheriff = enabled
    refreshRoleEspConnection()
end

local roleNotificationSent = false

if mm2GameplayRemotes then
    local playerDataChanged = mm2GameplayRemotes:FindFirstChild("PlayerDataChanged")
    if playerDataChanged and playerDataChanged:IsA("RemoteEvent") then
        featureConnections.MM2PlayerDataChanged = playerDataChanged.OnClientEvent:Connect(function(newData)
            if type(newData) == "table" and roundLifecycleActive ~= false then
                mm2RoundData = newData
                lastRoleRefreshAt = os.clock()
            else
                mm2RoundData = {}
            end
            rebuildRoleEsp()

            local roundActive = hasActiveRoundRoles()
            if not roundActive then
                roleNotificationSent = false
            elseif mm2Settings.instantRoleNotify and not roleNotificationSent then
                local murderer = findMurderer()
                local sheriff = findSheriff()
                if murderer and sheriff then
                    roleNotificationSent = true
                    notify(
                        "Roles ready - Murderer: "
                            .. murderer.Name
                            .. " | Sheriff/Hero: "
                            .. sheriff.Name
                    )
                end
            end
        end)
    end
end

local function toggleGunEsp(enabled)
    disconnectFeatureConnection("MM2GunESP")
    clearEffects(GunEffects)

    if not enabled then
        return
    end

    local elapsed = 1
    featureConnections.MM2GunESP = TaskManager:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.5 then
            return
        end
        elapsed = 0
        clearEffects(GunEffects)
        local gun = findDroppedGun()
        if gun then
            createMM2Marker(
                GunEffects,
                gun,
                "Dropped Gun",
                mm2Settings.gunColor,
                mm2Settings.gunTransparency
            )
        end
    end)
end

local function toggleTrapEsp(enabled)
    disconnectFeatureConnection("MM2TrapAdded")
    clearEffects(TrapEffects)

    if not enabled then
        return
    end

    local marked = setmetatable({}, {__mode = "k"})
    local function addTrap(object)
        if marked[object] then
            return
        end
        if (object.Name == "TrapVisual" or object.Name == "Trap")
            and (object:IsA("Model") or object:IsA("BasePart")) then
            marked[object] = true
            createMM2Cham(
                TrapEffects,
                object,
                mm2Settings.trapColor,
                mm2Settings.trapTransparency
            )
        end
    end

    local map = findMM2Map()
    for _, object in ipairs((map or workspace):GetDescendants()) do
        addTrap(object)
    end
    featureConnections.MM2TrapAdded = workspace.DescendantAdded:Connect(addTrap)
end

local coinChamsEnabled: boolean = false

type CoinChamRecord = {
    highlight: Highlight,
    billboard: BillboardGui,
    connections: {RBXScriptConnection},
}

local coinBoxes: {[BasePart]: CoinChamRecord} =
    setmetatable({}, {__mode = "k"}) :: any

local function normalizedCoinName(object: Instance): string
    return string.gsub(string.lower(object.Name), "[^%w]", "")
end

local function hasCoinName(object: Instance): boolean
    return string.find(normalizedCoinName(object), "coin", 1, true) ~= nil
end

local function isCoinServerName(object: Instance): boolean
    return string.find(
        normalizedCoinName(object),
        "coinserver",
        1,
        true
    ) ~= nil
end

local function isLiveCoin(coin: BasePart): boolean
    return coin:IsDescendantOf(workspace)
        and coin:GetAttribute("Delete") ~= true
        and coin:GetAttribute("Collected") ~= true
end

local function findCoinPartInContainer(container: Instance): BasePart?
    for _, descendant: Instance in ipairs(container:GetDescendants()) do
        if descendant:IsA("BasePart") and isCoinServerName(descendant) then
            return descendant
        end
    end

    if container:IsA("Model") and container.PrimaryPart then
        return container.PrimaryPart
    end
    for _, preferredName: string in ipairs({
        "CoinVisual",
        "MainCoin",
        "Coin",
    }) do
        local preferred: Instance? =
            container:FindFirstChild(preferredName, true)
        if preferred and preferred:IsA("BasePart") then
            return preferred
        end
    end
    return container:FindFirstChildWhichIsA("BasePart", true)
end

local function getCoinServer(object: Instance?): BasePart?
    if not object or object:GetAttribute("Delete") == true then
        return nil
    end

    local coinContainer: Instance? = nil
    local cursor: Instance? = object
    for _index: number = 1, 10 do
        if not cursor or cursor == workspace then
            break
        end
        if cursor:IsA("BasePart") and isCoinServerName(cursor) then
            return isLiveCoin(cursor) and cursor or nil
        end
        if (cursor:IsA("Model") or cursor:IsA("Folder"))
            and hasCoinName(cursor) then
            coinContainer = cursor
        end
        cursor = cursor.Parent
    end

    if coinContainer then
        local containerPart: BasePart? =
            findCoinPartInContainer(coinContainer)
        if containerPart and isLiveCoin(containerPart) then
            return containerPart
        end
    end

    if object:IsA("BasePart") and hasCoinName(object) then
        return isLiveCoin(object) and object or nil
    end

    if object:IsA("TouchTransmitter") or object.Name == "TouchInterest" then
        local parent: Instance? = object.Parent
        if parent and parent:IsA("BasePart") then
            local ancestor: Instance? = parent
            while ancestor and ancestor ~= workspace do
                if hasCoinName(ancestor) then
                    return isLiveCoin(parent) and parent or nil
                end
                ancestor = ancestor.Parent
            end
        end
    end
    return nil
end

local function getCoinVisual(coin: BasePart): BasePart
    local mainCoin: Instance? = coin:FindFirstChild("MainCoin", true)
    if mainCoin and mainCoin:IsA("BasePart") then
        return mainCoin
    end
    local coinVisual: Instance? = coin:FindFirstChild("CoinVisual", true)
    if coinVisual and coinVisual:IsA("BasePart") then
        return coinVisual
    end
    return coin
end

local function removeCoinBox(coin: BasePart): ()
    local record: CoinChamRecord? = coinBoxes[coin]
    if not record then
        return
    end
    coinBoxes[coin] = nil
    for _, connection: RBXScriptConnection in ipairs(record.connections) do
        connection:Disconnect()
    end
    record.highlight:Destroy()
    record.billboard:Destroy()
end

local function clearCoinBoxes(): ()
    for coin: BasePart in pairs(coinBoxes) do
        removeCoinBox(coin)
    end
    clearEffects(CoinEffects)
    coinBoxes = setmetatable({}, {__mode = "k"}) :: any
end

local function createCoinBillboard(adornee: BasePart): BillboardGui
    local billboard: BillboardGui = Instance.new("BillboardGui")
    billboard.Name = "RTM_CoinMarker"
    billboard.Adornee = adornee
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Size = UDim2.fromOffset(36, 36)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 0.25, 0)
    billboard.Parent = CoinEffects

    local marker: Frame = Instance.new("Frame")
    marker.Name = "Marker"
    marker.AnchorPoint = Vector2.new(0.5, 0.5)
    marker.BackgroundColor3 = mm2Settings.coinColor
    marker.BackgroundTransparency = 0.18
    marker.BorderSizePixel = 0
    marker.Position = UDim2.fromScale(0.5, 0.5)
    marker.Rotation = 45
    marker.Size = UDim2.fromOffset(20, 20)
    marker.Parent = billboard

    local corner: UICorner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 2)
    corner.Parent = marker

    local stroke: UIStroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 248, 170)
    stroke.Thickness = 2
    stroke.Transparency = 0.08
    stroke.Parent = marker
    return billboard
end

local function addCoinBox(object: Instance): ()
    local coin: BasePart? = getCoinServer(object)
    if not coin then
        return
    end

    local visual: BasePart = getCoinVisual(coin)
    local existing: CoinChamRecord? = coinBoxes[coin]
    if existing then
        existing.highlight.Adornee = visual
        existing.billboard.Adornee = visual
        return
    end

    local highlight: Highlight = Instance.new("Highlight")
    highlight.Name = "RTM_CoinHighlight"
    highlight.Adornee = visual
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = mm2Settings.coinColor
    highlight.FillTransparency = math.clamp(
        mm2Settings.coinTransparency * 0.65,
        0.15,
        0.62
    )
    highlight.OutlineColor = Color3.fromRGB(255, 246, 135)
    highlight.OutlineTransparency = 0.04
    highlight.Parent = coin

    local record: CoinChamRecord = {
        highlight = highlight,
        billboard = createCoinBillboard(visual),
        connections = {},
    }
    coinBoxes[coin] = record
    table.insert(record.connections, coin.AncestryChanged:Connect(function(): ()
        if not isLiveCoin(coin) then
            removeCoinBox(coin)
        end
    end))
    for _, attributeName: string in ipairs({"Collected", "Delete"}) do
        table.insert(
            record.connections,
            coin:GetAttributeChangedSignal(attributeName):Connect(function(): ()
                if not isLiveCoin(coin) then
                    removeCoinBox(coin)
                end
            end)
        )
    end
end

local function isPotentialCoinObject(object: Instance): boolean
    return hasCoinName(object)
        or object:IsA("TouchTransmitter")
        or object.Name == "TouchInterest"
        or CollectionService:HasTag(object, "CoinVisual")
end

local function scanCoins(container: Instance): ()
    if isPotentialCoinObject(container) then
        addCoinBox(container)
    end
    for _, object: Instance in ipairs(container:GetDescendants()) do
        if isPotentialCoinObject(object) then
            addCoinBox(object)
        end
    end
end

local function toggleCoinChams(enabled: boolean): ()
    coinChamsEnabled = enabled
    disconnectFeatureConnection("MM2CoinAdded")
    disconnectFeatureConnection("MM2CoinTagged")
    disconnectFeatureConnection("MM2CoinCollected")
    disconnectFeatureConnection("MM2CoinMapAdded")
    clearCoinBoxes()

    if not enabled then
        return
    end

    scanCoins(workspace)
    for _, object: Instance in ipairs(
        CollectionService:GetTagged("CoinVisual")
    ) do
        addCoinBox(object)
    end

    featureConnections.MM2CoinTagged = CollectionService
        :GetInstanceAddedSignal("CoinVisual")
        :Connect(addCoinBox)
    featureConnections.MM2CoinAdded = workspace.DescendantAdded:Connect(function(
        object: Instance
    ): ()
        if isPotentialCoinObject(object) then
            addCoinBox(object)
        end
    end)
    featureConnections.MM2CoinMapAdded = workspace.ChildAdded:Connect(function(
        object: Instance
    ): ()
        task.defer(function(): ()
            if coinChamsEnabled then
                scanCoins(object)
            end
        end)
    end)

    for _, rescanDelay: number in ipairs({0.5, 1.5, 3}) do
        task.delay(rescanDelay, function(): ()
            if coinChamsEnabled then
                scanCoins(workspace)
            end
        end)
    end

    local coinCollected: Instance? = mm2GameplayRemotes
        and mm2GameplayRemotes:FindFirstChild("CoinCollected")
    if coinCollected and coinCollected:IsA("RemoteEvent") then
        featureConnections.MM2CoinCollected = coinCollected.OnClientEvent:Connect(
            function(coinId: any): ()
                for coin: BasePart in pairs(coinBoxes) do
                    if coin:GetAttribute("CoinID") == coinId then
                        removeCoinBox(coin)
                    end
                end
            end
        )
    end
end
local autoGetGunBusy = false

local function toggleAutoGetGun(enabled)
    disconnectFeatureConnection("MM2AutoGetGun")
    autoGetGunBusy = false

    if not enabled then
        return
    end

    local elapsed = 0
    featureConnections.MM2AutoGetGun = TaskManager:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.5 or autoGetGunBusy then
            return
        end
        elapsed = 0

        local character = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local gunDrop = findDroppedGun()
        if not character or not gunDrop
            or (backpack and backpack:FindFirstChild("Gun"))
            or character:FindFirstChild("Gun") then
            return
        end

        autoGetGunBusy = true
        task.spawn(function()
            local savedCFrame = character:GetPivot()
            character:PivotTo(gunDrop:GetPivot() + Vector3.new(0, 2, 0))
            task.wait(mm2Settings.autoGetGunDelay)
            if character.Parent then
                character:PivotTo(savedCFrame)
            end
            autoGetGunBusy = false
        end)
    end)
end

local function toggleInstantRoleNotify(enabled)
    mm2Settings.instantRoleNotify = enabled
    if enabled and findMurderer() and findSheriff() then
        -- Do not repeat the alert when this option is enabled mid-round.
        roleNotificationSent = true
    end
end

local function toggleLoopAllInteract(enabled)
    disconnectFeatureConnection("MM2LoopInteract")
    if not enabled then
        return
    end

    local activeMap = nil
    local interactables = {}
    local elapsed = 0
    featureConnections.MM2LoopInteract = TaskManager:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.5 then
            return
        end
        elapsed = 0

        local map = findMM2Map()
        if map ~= activeMap then
            activeMap = map
            interactables = {}
            if map then
                for _, object in ipairs(map:GetDescendants()) do
                    if object:IsA("ProximityPrompt")
                        or object:IsA("ClickDetector") then
                        table.insert(interactables, object)
                    end
                end
            end
        end

        for _, object in ipairs(interactables) do
            if object:IsDescendantOf(activeMap) then
                if object:IsA("ProximityPrompt")
                    and object.Enabled
                    and type(fireproximityprompt) == "function" then
                    pcall(fireproximityprompt, object)
                elseif object:IsA("ClickDetector")
                    and type(fireclickdetector) == "function" then
                    pcall(fireclickdetector, object)
                end
            end
        end
    end)
end

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

local AutoPlaySound = Instance.new("Sound")
AutoPlaySound.Name = "RTM_MM2_AutoPlay"
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
        clearAutoPlaySetting("Audio ID inválido; reproducción desactivada")
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
            clearAutoPlaySetting("Audio ID no autorizado o no disponible")
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

local sprintTrailObjects: {Instance} = {}
local sprintSpeedOriginal: {[Humanoid]: number} =
    setmetatable({}, {__mode = "k"}) :: any
local sprintTouchActive: boolean = false

local function clearSprintTrail(): ()
    for _, object: Instance in ipairs(sprintTrailObjects) do
        if object.Parent then
            object:Destroy()
        end
    end
    table.clear(sprintTrailObjects)
end

local function ensureSprintTrail(root: BasePart): Trail
    local existing: Instance? = root:FindFirstChild("RTM_SprintTail")
    if existing and existing:IsA("Trail") then
        return existing
    end

    clearSprintTrail()
    local left: Attachment = Instance.new("Attachment")
    left.Name = "RTM_SprintLeft"
    left.Position = Vector3.new(-0.8, -0.5, 0.75)
    left.Parent = root

    local right: Attachment = Instance.new("Attachment")
    right.Name = "RTM_SprintRight"
    right.Position = Vector3.new(0.8, -0.5, 0.75)
    right.Parent = root

    local trail: Trail = Instance.new("Trail")
    trail.Name = "RTM_SprintTail"
    trail.Attachment0 = left
    trail.Attachment1 = right
    trail.Color = ColorSequence.new(
        Color3.fromRGB(255, 220, 55),
        Color3.fromRGB(175, 115, 20)
    )
    trail.Lifetime = 0.38
    trail.LightEmission = 0.25
    trail.FaceCamera = true
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Enabled = false
    trail.Parent = root
    sprintTrailObjects = {trail, left, right}
    return trail
end

local function toggleSprint(enabled: boolean): ()
    disconnectFeatureConnection("MM2Sprint")
    clearSprintTrail()
    for humanoid: Humanoid, speed: number in pairs(sprintSpeedOriginal) do
        if humanoid and humanoid.Parent then
            humanoid.WalkSpeed = speed
        end
    end
    sprintSpeedOriginal = setmetatable({}, {__mode = "k"}) :: any
    sprintTouchActive = state.isMobile and enabled

    if not enabled then
        return
    end

    featureConnections.MM2Sprint = TaskManager:Connect(function(): ()
        local _, humanoid, root = getCharacterParts()
        if not humanoid or not root
            or not humanoid:IsA("Humanoid")
            or not root:IsA("BasePart") then
            return
        end
        if sprintSpeedOriginal[humanoid] == nil then
            sprintSpeedOriginal[humanoid] = humanoid.WalkSpeed
        end

        local trail: Trail = ensureSprintTrail(root)
        local direction: Vector3 = humanoid.MoveDirection
        local sprinting: boolean =
            (sprintTouchActive
                or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl))
            and direction.Magnitude > 0.05
        trail.Enabled = sprinting

        if sprinting then
            humanoid.WalkSpeed = 30
            local velocity: Vector3 = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(
                direction.X * 30,
                velocity.Y,
                direction.Z * 30
            )
        elseif humanoid.WalkSpeed == 30 then
            humanoid.WalkSpeed = sprintSpeedOriginal[humanoid]
        else
            sprintSpeedOriginal[humanoid] = humanoid.WalkSpeed
        end
    end)
end

local fpsSettings = {
    textures = true,
    particles = true,
    shadows = true,
    materials = false,
}
local fpsModeEnabled = false
local fpsVisualCache = setmetatable({}, {__mode = "k"})

local function cacheFpsProperty(object, property)
    local data = fpsVisualCache[object]
    if not data then
        data = {}
        fpsVisualCache[object] = data
    end
    if data[property] == nil then
        data[property] = object[property]
    end
end

local function applyFpsObject(object)
    if fpsSettings.textures and (object:IsA("Decal") or object:IsA("Texture")) then
        cacheFpsProperty(object, "Transparency")
        object.Transparency = 1
    elseif fpsSettings.textures and object:IsA("MeshPart") then
        cacheFpsProperty(object, "TextureID")
        object.TextureID = ""
    end

    if fpsSettings.particles
        and (object:IsA("ParticleEmitter")
            or object:IsA("Trail")
            or object:IsA("Beam")
            or object:IsA("Smoke")
            or object:IsA("Fire")
            or object:IsA("Sparkles")) then
        cacheFpsProperty(object, "Enabled")
        object.Enabled = false
    end

    if object:IsA("BasePart") then
        if fpsSettings.shadows then
            cacheFpsProperty(object, "CastShadow")
            object.CastShadow = false
        end
        if fpsSettings.materials then
            cacheFpsProperty(object, "Material")
            cacheFpsProperty(object, "Reflectance")
            object.Material = Enum.Material.SmoothPlastic
            object.Reflectance = 0
        end
    end
end

local function restoreFpsObjects()
    for object, properties in pairs(fpsVisualCache) do
        if object and object.Parent then
            for property, value in pairs(properties) do
                pcall(function()
                    object[property] = value
                end)
            end
        end
    end
    fpsVisualCache = setmetatable({}, {__mode = "k"})
end

local function toggleImproveFps(enabled)
    fpsModeEnabled = enabled
    disconnectFeatureConnection("MM2ImproveFPS")
    restoreFpsObjects()

    if not enabled then
        return
    end

    task.spawn(function()
        for index, object in ipairs(workspace:GetDescendants()) do
            if not fpsModeEnabled then
                return
            end
            applyFpsObject(object)
            if index % 250 == 0 then
                task.wait()
            end
        end
    end)
    featureConnections.MM2ImproveFPS = workspace.DescendantAdded:Connect(function(object)
        if fpsModeEnabled then
            applyFpsObject(object)
        end
    end)
end

local TimerDisplay: Frame = create("Frame", {
    Parent = ScreenGui,
    Name = "MM2RoundTimer",
    BackgroundColor3 = Color3.fromRGB(24, 24, 24),
    BackgroundTransparency = 0.12,
    BorderColor3 = state.headerColor,
    BorderSizePixel = 1,
    Position = UDim2.new(1, -205, 0, 58),
    Size = UDim2.fromOffset(180, 34),
    Visible = false,
    ZIndex = 30,
}) :: Frame
local TimerText = makeTextLabel(TimerDisplay, "ROUND 0:00", 14)
TimerText.Font = Enum.Font.GothamBold
TimerText.TextXAlignment = Enum.TextXAlignment.Center
TimerText.Size = UDim2.fromScale(1, 1)
TimerText.ZIndex = 31
local timerEndsAt = nil
local timerRemotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
local timerGameplay = timerRemotes and timerRemotes:FindFirstChild("Gameplay")
local timerRoundStart = timerGameplay and timerGameplay:FindFirstChild("RoundStart")
local timerRoundEnd = timerGameplay and timerGameplay:FindFirstChild("RoundEndFade")
local sessionRoundActive = false

if timerRoundStart and timerRoundStart:IsA("RemoteEvent") then
    featureConnections.MM2TimerTrackerStart = timerRoundStart.OnClientEvent:Connect(
        function(duration)
            duration = tonumber(duration)
            timerEndsAt = duration and os.clock() + duration or nil
            mm2RoundData = {}
            roundLifecycleActive = duration ~= nil and duration > 0
            if not duration or duration <= 0 then
                sessionRoundActive = false
            end
            roleRefreshGeneration += 1
            if duration and duration > 0
                and not sessionRoundActive
                and state.sessionInfo
                and state.sessionInfo.addRound then
                sessionRoundActive = true
                state.sessionInfo.addRound()
            end
        end
    )
end
if timerRoundEnd and timerRoundEnd:IsA("RemoteEvent") then
    featureConnections.MM2TimerTrackerEnd = timerRoundEnd.OnClientEvent:Connect(function()
        timerEndsAt = nil
        sessionRoundActive = false
        roundLifecycleActive = false
        roleRefreshGeneration += 1
        mm2RoundData = {}
        TimerDisplay.Visible = false
    end)
end

local function toggleAlwaysShowTimer(enabled)
    disconnectFeatureConnection("MM2AlwaysTimer")
    TimerDisplay.Visible = false

    if not enabled then
        return
    end

    local getTimer = timerRemotes and timerRemotes:FindFirstChild("GetTimer", true)
    if getTimer and getTimer:IsA("RemoteFunction") then
        task.spawn(function()
            pcall(function()
                local remaining = tonumber(getTimer:InvokeServer())
                if remaining and remaining > 0 then
                    timerEndsAt = os.clock() + remaining
                end
            end)
        end)
    end

    local elapsed = 1
    featureConnections.MM2AlwaysTimer = TaskManager:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.1 then
            return
        end
        elapsed = 0

        local remaining = timerEndsAt and math.max(0, math.ceil(timerEndsAt - os.clock()))
        TimerDisplay.Visible = remaining ~= nil and remaining > 0
        if TimerDisplay.Visible then
            local minutes = math.floor(remaining / 60)
            TimerText.Text = string.format("ROUND %d:%02d", minutes, remaining % 60)
            TimerText.TextColor3 = remaining <= 30
                and Color3.fromRGB(190, 55, 55)
                or Color3.fromRGB(220, 220, 220)
        end
    end)
end

type MotionSample = {
    character: Model?,
    position: Vector3,
    sampledAt: number,
    velocity: Vector3,
    acceleration: Vector3,
    stability: number,
    grounded: boolean,
}

local motionSamples: {[Player]: MotionSample} =
    setmetatable({}, {__mode = "k"}) :: any

local function getPointerPosition(): Vector2
    local camera: Camera? = workspace.CurrentCamera
    if state.isMobile and camera then
        -- A touch action button is not an aiming cursor. Mobile targeting uses
        -- the camera center so tapping SHOOT/GUN cannot pull selection toward
        -- the button's screen position.
        return camera.ViewportSize / 2
    end
    return UserInputService:GetMouseLocation()
end

local function getFilteredVelocity(player: Player, root: BasePart): Vector3
    local now: number = os.clock()
    local velocity: Vector3 = root.AssemblyLinearVelocity
    if velocity.Magnitude > 110 then
        velocity = velocity.Unit * 110
    end
    local sample: MotionSample? = motionSamples[player]
    local acceleration: Vector3 = Vector3.zero
    local stability: number = 1
    local character: Model? = player.Character
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid")
        :: Humanoid?
    local grounded: boolean = humanoid ~= nil
        and humanoid.FloorMaterial ~= Enum.Material.Air

    if sample and sample.character == character then
        local deltaTime: number = now - sample.sampledAt
        if deltaTime < 0.012 then
            return velocity
        end
        if deltaTime < 0.5 then
            acceleration = (velocity - sample.velocity) / deltaTime
            if acceleration.Magnitude > 250 then
                acceleration = acceleration.Unit * 250
            end

            local previousHorizontal: Vector3 = Vector3.new(
                sample.velocity.X,
                0,
                sample.velocity.Z
            )
            local currentHorizontal: Vector3 = Vector3.new(
                velocity.X,
                0,
                velocity.Z
            )
            if previousHorizontal.Magnitude > 1
                and currentHorizontal.Magnitude > 1 then
                stability = math.clamp(
                    previousHorizontal.Unit:Dot(currentHorizontal.Unit),
                    0,
                    1
                )
            end
        end
    end

    motionSamples[player] = {
        character = character,
        position = root.Position,
        sampledAt = now,
        velocity = velocity,
        acceleration = acceleration,
        stability = stability,
        grounded = grounded,
    }
    return velocity
end

local function getEstimatedLatency(): number
    local measuredRtt: number = mm2Settings.predictionRtt
    pcall(function(): ()
        local network: Instance? = Stats:FindFirstChild("Network")
        local serverItems: Instance? = network
            and network:FindFirstChild("ServerStatsItem")
        local pingItem: any = serverItems and serverItems:FindFirstChild("Data Ping")
        if pingItem and type(pingItem.GetValue) == "function" then
            local pingMilliseconds: number? = tonumber(pingItem:GetValue())
            if pingMilliseconds then
                measuredRtt = pingMilliseconds / 1000
            end
        end
    end)
    mm2Settings.predictionRtt +=
        (measuredRtt - mm2Settings.predictionRtt) * 0.18

    return math.clamp(
        mm2Settings.predictionRtt,
        0.03,
        0.3
    )
end

local function getGunLeadSeconds(): (number, number)
    local roundTripTime: number = getEstimatedLatency()
    -- Schema 2 telemetry: 2,105 motion samples and 15 confirmed shots place
    -- server acceptance about one render frame beyond the reported ping.
    local horizontalLead: number = math.clamp(
        roundTripTime * 0.98 + (1 / 60) + mm2Settings.gunLeadBias,
        0.025,
        0.3
    )
    local verticalLead: number = math.clamp(
        roundTripTime * 0.92 + (1 / 60) + mm2Settings.gunLeadBias,
        0.02,
        0.25
    )
    return horizontalLead, verticalLead
end

-- Correct zero-gravity branch adapted from prediction.lua. MM2 throwing knives
-- move linearly; their tagged projectile reports ThrowSpeed, with 96 as fallback.
local function solveLinearIntercept(
    origin: Vector3,
    projectileSpeed: number,
    targetPosition: Vector3,
    targetVelocity: Vector3,
    latency: number
): (Vector3?, number?)
    local compensatedPosition: Vector3 = targetPosition + targetVelocity * latency
    local displacement: Vector3 = compensatedPosition - origin
    local a: number = targetVelocity:Dot(targetVelocity)
        - projectileSpeed * projectileSpeed
    local b: number = 2 * displacement:Dot(targetVelocity)
    local c: number = displacement:Dot(displacement)
    local travelTime: number? = nil

    if math.abs(a) < 1e-6 then
        if math.abs(b) > 1e-6 then
            local linearTime: number = -c / b
            travelTime = linearTime > 0 and linearTime or nil
        end
    else
        local discriminant: number = b * b - 4 * a * c
        if discriminant >= 0 then
            local root: number = math.sqrt(discriminant)
            local first: number = (-b - root) / (2 * a)
            local second: number = (-b + root) / (2 * a)
            if first > 0 and second > 0 then
                travelTime = math.min(first, second)
            elseif first > 0 then
                travelTime = first
            elseif second > 0 then
                travelTime = second
            end
        end
    end

    if not travelTime then
        return nil, nil
    end
    return compensatedPosition + targetVelocity * travelTime, travelTime
end

local function getGunOriginCFrame(character: Model, _gun: Tool?): CFrame?
    local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local attachment: Attachment? = root
        and root:FindFirstChild("GunRaycastAttachment")
        :: Attachment?
    if attachment and attachment:IsA("Attachment") then
        return attachment.WorldCFrame
    end
    return nil
end

-- Event-driven adaptation of MM2 Trajectory Extractor 0001. It observes only
-- local gun activations confirmed by WeaponService.GunFired and locally-owned
-- ThrowingKnife projectiles. It never rewrites a ray, CFrame, or remote payload.
local function createTrajectoryCalibration(): any
    type TrajectoryPoint = {
        dt: number,
        serverTime: number,
        pingMs: number,
        position: {number},
        velocity: {number},
        moveDirection: {number},
        humanoidState: string,
        grounded: boolean,
        jumping: boolean,
    }
    type RunningStats = {
        count: number,
        mean: number,
        m2: number,
        minimum: number,
        maximum: number,
    }
    type PendingGun = {
        tool: Tool,
        activatedAt: number,
        origin: Vector3?,
        requestedAim: Vector3?,
        pingMs: number,
        targetUserId: number?,
        targetName: string?,
        targetTrajectory: {TrajectoryPoint},
        lastTrajectorySampleAt: number,
        confirmedAt: number?,
        latencyMs: number?,
        confirmedEndpoint: Vector3?,
        confirmedHitTarget: boolean?,
    }
    type PendingKnife = {
        tool: Tool,
        activatedAt: number,
        origin: Vector3?,
        requestedAim: Vector3?,
        pingMs: number,
        targetUserId: number?,
        targetName: string?,
        targetTrajectory: {TrajectoryPoint},
        lastTrajectorySampleAt: number,
    }
    type KnifeTrack = {
        startedAt: number,
        previousAt: number?,
        previousPosition: Vector3?,
        speeds: {number},
        rawSpeed: number?,
        spawnDelayMs: number,
        pingMs: number,
        targetUserId: number?,
        targetName: string?,
        targetTrajectory: {TrajectoryPoint},
        lastTrajectorySampleAt: number,
        destroyConnection: RBXScriptConnection?,
    }
    type CalibrationEvent = {
        kind: string,
        serverTime: number,
        pingMs: number,
        latencyMs: number?,
        speed: number?,
        rawSpeed: number?,
        samples: number?,
        reason: string?,
        targetUserId: number?,
        targetName: string?,
        targetState: string?,
        targetJumped: boolean?,
        targetTrajectory: {TrajectoryPoint}?,
        observedDisplacement: {number}?,
        constantVelocityResidual: {number}?,
        horizontalLeadSeconds: number?,
        verticalLeadSeconds: number?,
        endpoint: {number}?,
        hitTarget: boolean?,
        pingBucket: string?,
        bestMotionModel: string?,
        motionModelErrors: {[string]: number}?,
        evaluationSeconds: number?,
    }
    type Estimates = {
        gunAcceptanceMs: number?,
        knifeSpeed: number?,
        confirmedShots: number,
        confirmedThrows: number,
    }
    type Controller = {
        start: (self: Controller) -> (),
        save: (self: Controller, reason: string?) -> boolean,
        reset: (self: Controller) -> (),
        destroy: (self: Controller) -> (),
        status: (self: Controller) -> string,
        getEstimates: (self: Controller) -> Estimates,
    }

    local OUTPUT_ROOT: string = "RandomTestingMenu0001"
    local OUTPUT_FOLDER: string = OUTPUT_ROOT .. "/Telemetry"
    local OUTPUT_PATH: string = OUTPUT_FOLDER
        .. "/MM2_Trajectory_Calibration.json"
    local MAX_EVENTS: number = 240
    local MAX_PENDING_AGE: number = 2.5
    local environment: {[string]: any} = getfenv() :: any
    local playerMouse: Mouse = LocalPlayer:GetMouse()
    local runtime: any = {
        active = false,
        dirty = false,
        saveScheduled = false,
        startedAt = os.clock(),
        sessionGunAttempts = 0,
        sessionGunConfirmed = 0,
        sessionKnifeAttempts = 0,
        sessionKnifeConfirmed = 0,
        pendingGuns = {} :: {PendingGun},
        pendingKnives = {} :: {PendingKnife},
        tracks = {} :: {[Instance]: KnifeTrack},
        observedTools = setmetatable({}, {__mode = "k"}) :: {[Tool]: boolean},
        connections = {} :: {RBXScriptConnection},
        events = {} :: {CalibrationEvent},
        gunAcceptance = nil :: RunningStats?,
        knifeSpeed = nil :: RunningStats?,
        knifeSpawnDelay = nil :: RunningStats?,
        motionBuckets = {} :: {[string]: any},
        trajectorySampler = nil :: any,
    }
    local controller: Controller
    local saveSnapshot: (reason: string) -> boolean
    local compactPending: (queue: {any}, now: number) -> ()
    local finalizeGunCapture: (pending: PendingGun) -> ()

    local function newStats(): RunningStats
        return {
            count = 0,
            mean = 0,
            m2 = 0,
            minimum = math.huge,
            maximum = -math.huge,
        }
    end

    runtime.gunAcceptance = newStats()
    runtime.knifeSpeed = newStats()
    runtime.knifeSpawnDelay = newStats()

    local function finite(value: number): boolean
        return value == value and value > -math.huge and value < math.huge
    end

    local function vectorArray(value: Vector3): {number}
        return {value.X, value.Y, value.Z}
    end

    local function pingBucketKey(pingMs: number): string
        if pingMs > 250 then
            return "250+"
        end
        local lower: number = math.clamp(math.floor(pingMs / 5) * 5, 0, 245)
        return string.format("%03d-%03d", lower, lower + 5)
    end

    local function getTargetRoot(player: Player?): BasePart?
        return player
            and player.Character
            and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    end

    local function getTargetHumanoid(player: Player?): Humanoid?
        return player
            and player.Character
            and player.Character:FindFirstChildOfClass("Humanoid") :: Humanoid?
    end

    local function captureTrajectoryPoint(
        player: Player,
        activatedAt: number,
        pingMs: number
    ): TrajectoryPoint?
        local root: BasePart? = getTargetRoot(player)
        local humanoid: Humanoid? = getTargetHumanoid(player)
        if not root or not humanoid or humanoid.Health <= 0 then
            return nil
        end
        local stateName: string = humanoid:GetState().Name
        local grounded: boolean = humanoid.FloorMaterial ~= Enum.Material.Air
        local jumping: boolean = stateName == "Jumping"
            or stateName == "Freefall"
            or not grounded
        return {
            dt = os.clock() - activatedAt,
            serverTime = workspace:GetServerTimeNow(),
            pingMs = pingMs,
            position = vectorArray(root.Position),
            velocity = vectorArray(root.AssemblyLinearVelocity),
            moveDirection = vectorArray(humanoid.MoveDirection),
            humanoidState = stateName,
            grounded = grounded,
            jumping = jumping,
        }
    end

    local function findKnifeAnalysisTarget(aimPosition: Vector3?): Player?
        local selected: Player? = nil
        local selectedScore: number = math.huge
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
                and isPlayerAlive(player)
                and getPlayerRole(player) ~= "Murderer"
                and not state.isProtectedTarget(player) then
                local root: BasePart? = getTargetRoot(player)
                if root then
                    local score: number = aimPosition
                            and (root.Position - aimPosition).Magnitude
                        or (root.Position - (LocalPlayer.Character
                                and LocalPlayer.Character:GetPivot().Position
                            or Vector3.zero)).Magnitude
                    if score < selectedScore then
                        selected = player
                        selectedScore = score
                    end
                end
            end
        end
        return selected
    end

    local function getRequestedAim(): Vector3?
        local aim: Vector3? = nil
        pcall(function(): ()
            aim = playerMouse.Hit.Position
        end)
        return aim
    end

    local function samplePendingTrajectories(): ()
        local now: number = os.clock()
        local function sampleQueue(queue: {any}): ()
            for _, pending: any in ipairs(queue) do
                if pending.targetUserId
                    and now - pending.lastTrajectorySampleAt >= 1 / 30 then
                    local target: Player? = Players:GetPlayerByUserId(
                        pending.targetUserId
                    )
                    local point: TrajectoryPoint? = target
                        and captureTrajectoryPoint(
                            target,
                            pending.activatedAt,
                            pending.pingMs
                        )
                        or nil
                    if point and #pending.targetTrajectory < 120 then
                        table.insert(pending.targetTrajectory, point)
                    end
                    pending.lastTrajectorySampleAt = now
                end
            end
        end
        sampleQueue(runtime.pendingGuns)
        sampleQueue(runtime.pendingKnives)
        for index: number = #runtime.pendingGuns, 1, -1 do
            local pending: PendingGun = runtime.pendingGuns[index]
            if pending.confirmedAt and now - pending.confirmedAt >= 0.5 then
                table.remove(runtime.pendingGuns, index)
                finalizeGunCapture(pending)
            end
        end
        if #runtime.pendingGuns == 0 and #runtime.pendingKnives == 0
            and runtime.trajectorySampler then
            runtime.trajectorySampler:Disconnect()
            runtime.trajectorySampler = nil
        end
    end

    local function ensureTrajectorySampler(): ()
        if runtime.trajectorySampler then
            return
        end
        runtime.trajectorySampler = TaskManager:Connect(function(
            _deltaTime: number
        ): ()
            compactPending(runtime.pendingGuns, os.clock())
            compactPending(runtime.pendingKnives, os.clock())
            samplePendingTrajectories()
        end)
    end

    local function addSample(stats: RunningStats, value: number): ()
        if not finite(value) then
            return
        end
        stats.count += 1
        local delta: number = value - stats.mean
        stats.mean += delta / stats.count
        stats.m2 += delta * (value - stats.mean)
        stats.minimum = math.min(stats.minimum, value)
        stats.maximum = math.max(stats.maximum, value)
    end

    local function statsPayload(stats: RunningStats): {[string]: number}
        return {
            count = stats.count,
            mean = stats.mean,
            m2 = stats.m2,
            minimum = stats.count > 0 and stats.minimum or 0,
            maximum = stats.count > 0 and stats.maximum or 0,
        }
    end

    local function restoreStats(value: any): RunningStats
        local restored: RunningStats = newStats()
        if type(value) ~= "table" then
            return restored
        end
        local count: number = math.max(0, math.floor(tonumber(value.count) or 0))
        local mean: number = tonumber(value.mean) or 0
        local m2: number = math.max(0, tonumber(value.m2) or 0)
        if count > 0 and finite(mean) and finite(m2) then
            restored.count = count
            restored.mean = mean
            restored.m2 = m2
            restored.minimum = tonumber(value.minimum) or mean
            restored.maximum = tonumber(value.maximum) or mean
        end
        return restored
    end

    local function getPingMilliseconds(): number
        local pingMs: number = 0
        pcall(function(): ()
            local network: Instance? = Stats:FindFirstChild("Network")
            local serverItems: Instance? = network
                and network:FindFirstChild("ServerStatsItem")
            local pingItem: any = serverItems
                and serverItems:FindFirstChild("Data Ping")
            if pingItem and type(pingItem.GetValue) == "function" then
                pingMs = tonumber(pingItem:GetValue()) or 0
            end
        end)
        return math.max(0, pingMs)
    end

    local function worldPosition(value: any): Vector3?
        if typeof(value) == "Vector3" then
            return value
        elseif typeof(value) == "CFrame" then
            return value.Position
        elseif typeof(value) == "Instance" then
            if value:IsA("Attachment") then
                return value.WorldPosition
            elseif value:IsA("BasePart") then
                return value.Position
            elseif value:IsA("Model") then
                return value:GetPivot().Position
            end
        end
        return nil
    end

    local function projectilePosition(projectile: Instance): Vector3?
        local visual: Instance? = projectile:FindFirstChild("KnifeVisual", true)
        if visual and visual:IsA("BasePart") then
            return visual.Position
        end
        local blade: Instance? = projectile:FindFirstChild("BladePosition", true)
        local bladePosition: Vector3? = worldPosition(blade)
        if bladePosition then
            return bladePosition
        end
        return worldPosition(projectile)
    end

    local function toolOrigin(tool: Tool): Vector3?
        local handle: Instance? = tool:FindFirstChild("Handle")
        return worldPosition(handle)
    end

    local function appendEvent(record: CalibrationEvent): ()
        if #runtime.events >= MAX_EVENTS then
            table.remove(runtime.events, 1)
        end
        table.insert(runtime.events, record)
        runtime.dirty = true
        if runtime.saveScheduled then
            return
        end
        runtime.saveScheduled = true
        task.delay(0.8, function(): ()
            runtime.saveScheduled = false
            if runtime.active and runtime.dirty then
                saveSnapshot("autosave")
            end
        end)
    end

    local function trackConnection(connection: RBXScriptConnection): ()
        table.insert(runtime.connections, connection)
    end

    compactPending = function(queue: {any}, now: number): ()
        while #queue > 0 and now - queue[1].activatedAt > MAX_PENDING_AGE do
            table.remove(queue, 1)
        end
        while #queue > 12 do
            table.remove(queue, 1)
        end
    end

    local function vectorFromArray(value: {number}): Vector3
        return Vector3.new(value[1] or 0, value[2] or 0, value[3] or 0)
    end

    local function analyzeTargetTrajectory(
        trajectory: {TrajectoryPoint},
        pingMs: number,
        eventKind: string,
        evaluationSeconds: number?
    ): {[string]: any}
        if #trajectory < 2 then
            return {
                pingBucket = pingBucketKey(pingMs),
                sampleCount = #trajectory,
            }
        end
        local first: TrajectoryPoint = trajectory[1]
        local last: TrajectoryPoint = trajectory[#trajectory]
        if evaluationSeconds then
            local desiredDt: number = first.dt + evaluationSeconds
            local closestDistance: number = math.huge
            for _, point: TrajectoryPoint in ipairs(trajectory) do
                local distance: number = math.abs(point.dt - desiredDt)
                if distance < closestDistance then
                    last = point
                    closestDistance = distance
                end
            end
        end
        local initialPosition: Vector3 = vectorFromArray(first.position)
        local finalPosition: Vector3 = vectorFromArray(last.position)
        local initialVelocity: Vector3 = vectorFromArray(first.velocity)
        local duration: number = math.max(0.0001, last.dt - first.dt)
        local displacement: Vector3 = finalPosition - initialPosition
        local residual: Vector3 = displacement - initialVelocity * duration
        local constantVelocityPrediction: Vector3 = initialPosition
            + initialVelocity * duration
        local observedAcceleration: Vector3 = Vector3.zero
        if #trajectory >= 3 then
            local second: TrajectoryPoint = trajectory[2]
            local accelerationDelta: number = math.max(
                1 / 240,
                second.dt - first.dt
            )
            observedAcceleration = (
                vectorFromArray(second.velocity) - initialVelocity
            ) / accelerationDelta
            if observedAcceleration.Magnitude > 500 then
                observedAcceleration = observedAcceleration.Unit * 500
            end
        end
        local accelerationPrediction: Vector3 = initialPosition
            + initialVelocity * duration
            + observedAcceleration * (0.5 * duration * duration)
        local ballisticPrediction: Vector3 = initialPosition
            + initialVelocity * duration
            + Vector3.new(0, -workspace.Gravity, 0)
                * (0.5 * duration * duration)
        local modelErrors: {[string]: number} = {
            constantVelocity = (constantVelocityPrediction - finalPosition).Magnitude,
            observedAcceleration = (accelerationPrediction - finalPosition).Magnitude,
            airborneBallistic = (ballisticPrediction - finalPosition).Magnitude,
        }
        local bestMotionModel: string = "constantVelocity"
        local bestMotionError: number = modelErrors.constantVelocity
        for modelName: string, modelError: number in pairs(modelErrors) do
            if modelError < bestMotionError then
                bestMotionModel = modelName
                bestMotionError = modelError
            end
        end
        local horizontalVelocity: Vector3 = Vector3.new(
            initialVelocity.X,
            0,
            initialVelocity.Z
        )
        local horizontalDisplacement: Vector3 = Vector3.new(
            displacement.X,
            0,
            displacement.Z
        )
        local horizontalLead: number? = nil
        if horizontalVelocity.Magnitude > 0.75 then
            horizontalLead = math.clamp(
                horizontalDisplacement:Dot(horizontalVelocity)
                    / horizontalVelocity:Dot(horizontalVelocity),
                -0.15,
                0.6
            )
        end
        local verticalLead: number? = nil
        if math.abs(initialVelocity.Y) > 0.75 then
            verticalLead = math.clamp(
                displacement.Y / initialVelocity.Y,
                -0.15,
                0.6
            )
        end
        local jumped: boolean = false
        for _, point: TrajectoryPoint in ipairs(trajectory) do
            if point.jumping then
                jumped = true
                break
            end
        end
        local stateName: string = jumped and "Airborne" or "Grounded"
        local bucketKey: string = eventKind
            .. ":"
            .. pingBucketKey(pingMs)
            .. ":"
            .. stateName
        local bucket: any = runtime.motionBuckets[bucketKey]
        if type(bucket) ~= "table" then
            bucket = {
                count = 0,
                horizontalLeadSum = 0,
                horizontalLeadCount = 0,
                verticalLeadSum = 0,
                verticalLeadCount = 0,
                residualXSum = 0,
                residualYSum = 0,
                residualZSum = 0,
                durationSum = 0,
                constantVelocityErrorSum = 0,
                observedAccelerationErrorSum = 0,
                airborneBallisticErrorSum = 0,
            }
            runtime.motionBuckets[bucketKey] = bucket
        end
        bucket.count += 1
        bucket.durationSum += duration
        bucket.residualXSum += residual.X
        bucket.residualYSum += residual.Y
        bucket.residualZSum += residual.Z
        bucket.constantVelocityErrorSum += modelErrors.constantVelocity
        bucket.observedAccelerationErrorSum += modelErrors.observedAcceleration
        bucket.airborneBallisticErrorSum += modelErrors.airborneBallistic
        if horizontalLead then
            bucket.horizontalLeadSum += horizontalLead
            bucket.horizontalLeadCount += 1
        end
        if verticalLead then
            bucket.verticalLeadSum += verticalLead
            bucket.verticalLeadCount += 1
        end
        return {
            pingBucket = pingBucketKey(pingMs),
            sampleCount = #trajectory,
            initialState = first.humanoidState,
            finalState = last.humanoidState,
            jumped = jumped,
            durationSeconds = duration,
            evaluationSeconds = evaluationSeconds or duration,
            displacement = vectorArray(displacement),
            constantVelocityResidual = vectorArray(residual),
            horizontalLeadSeconds = horizontalLead,
            verticalLeadSeconds = verticalLead,
            bestMotionModel = bestMotionModel,
            motionModelErrors = modelErrors,
        }
    end

    local function motionModelPayload(): {[string]: any}
        local payload: {[string]: any} = {}
        for key: string, bucket: any in pairs(runtime.motionBuckets) do
            local count: number = math.max(1, tonumber(bucket.count) or 1)
            local horizontalCount: number = math.max(
                1,
                tonumber(bucket.horizontalLeadCount) or 0
            )
            local verticalCount: number = math.max(
                1,
                tonumber(bucket.verticalLeadCount) or 0
            )
            payload[key] = {
                count = bucket.count,
                meanDurationSeconds = bucket.durationSum / count,
                meanHorizontalLeadSeconds = bucket.horizontalLeadCount > 0
                        and bucket.horizontalLeadSum / horizontalCount
                    or nil,
                meanVerticalLeadSeconds = bucket.verticalLeadCount > 0
                        and bucket.verticalLeadSum / verticalCount
                    or nil,
                meanConstantVelocityResidual = {
                    bucket.residualXSum / count,
                    bucket.residualYSum / count,
                    bucket.residualZSum / count,
                },
                meanModelError = {
                    constantVelocity = bucket.constantVelocityErrorSum / count,
                    observedAcceleration = bucket.observedAccelerationErrorSum / count,
                    airborneBallistic = bucket.airborneBallisticErrorSum / count,
                },
            }
        end
        return payload
    end

    local function median(values: {number}): number?
        if #values == 0 then
            return nil
        end
        local sorted: {number} = table.clone(values)
        table.sort(sorted)
        local middle: number = math.floor((#sorted + 1) / 2)
        if #sorted % 2 == 1 then
            return sorted[middle]
        end
        return (sorted[middle] + sorted[middle + 1]) * 0.5
    end

    local function estimates(): Estimates
        local gunStats: RunningStats = runtime.gunAcceptance
        local speedStats: RunningStats = runtime.knifeSpeed
        return {
            gunAcceptanceMs = gunStats.count > 0 and gunStats.mean or nil,
            knifeSpeed = speedStats.count > 0 and speedStats.mean or nil,
            confirmedShots = gunStats.count,
            confirmedThrows = speedStats.count,
        }
    end

    saveSnapshot = function(reason: string): boolean
        if type(environment.writefile) ~= "function" then
            warn("[RTM:MM2:Trajectory] writefile no está disponible; no se pudo guardar.")
            return false
        end
        local payload: {[string]: any} = {
            schema = 2,
            kind = "mm2-trajectory-analytics",
            placeId = game.PlaceId,
            savedAt = DateTime.now():ToIsoDate(),
            reason = reason,
            aggregate = {
                gunAcceptanceMs = statsPayload(runtime.gunAcceptance),
                knifeSpeedStudsPerSecond = statsPayload(runtime.knifeSpeed),
                knifeSpawnDelayMs = statsPayload(runtime.knifeSpawnDelay),
            },
            estimator = estimates(),
            analytics = {
                bucketSpec = {
                    metric = "Data Ping",
                    widthMs = 5,
                    minimumMs = 0,
                    maximumMs = 250,
                    states = {"Grounded", "Airborne"},
                },
                motionModel = motionModelPayload(),
            },
            session = {
                elapsedSeconds = os.clock() - runtime.startedAt,
                gunAttempts = runtime.sessionGunAttempts,
                gunConfirmed = runtime.sessionGunConfirmed,
                knifeAttempts = runtime.sessionKnifeAttempts,
                knifeConfirmed = runtime.sessionKnifeConfirmed,
                events = runtime.events,
            },
        }
        local encodedOk: boolean, encoded: any = pcall(
            HttpService.JSONEncode,
            HttpService,
            payload
        )
        if not encodedOk or type(encoded) ~= "string" then
            warn("[RTM:MM2:Trajectory] JSONEncode falló: " .. tostring(encoded))
            return false
        end
        if type(environment.makefolder) == "function" then
            pcall(environment.makefolder, OUTPUT_ROOT)
            pcall(environment.makefolder, OUTPUT_FOLDER)
        end
        local writeOk: boolean, writeError: any = pcall(
            environment.writefile,
            OUTPUT_PATH,
            encoded
        )
        if not writeOk then
            warn("[RTM:MM2:Trajectory] writefile falló: " .. tostring(writeError))
            return false
        end
        runtime.dirty = false
        print(
            "[RTM:MM2:Trajectory] Guardado "
                .. OUTPUT_PATH
                .. " ("
                .. tostring(#encoded)
                .. " bytes)"
        )
        return true
    end

    local function loadSnapshot(): ()
        if type(environment.readfile) ~= "function" then
            return
        end
        if type(environment.isfile) == "function" then
            local existsOk: boolean, exists: any = pcall(environment.isfile, OUTPUT_PATH)
            if not existsOk or exists ~= true then
                return
            end
        end
        local readOk: boolean, encoded: any = pcall(environment.readfile, OUTPUT_PATH)
        if not readOk or type(encoded) ~= "string" or encoded == "" then
            return
        end
        local decodeOk: boolean, decoded: any = pcall(
            HttpService.JSONDecode,
            HttpService,
            encoded
        )
        if not decodeOk
            or type(decoded) ~= "table"
            or decoded.placeId ~= game.PlaceId
            or decoded.schema ~= 2
            or decoded.kind ~= "mm2-trajectory-analytics" then
            if decodeOk
                and type(decoded) == "table"
                and decoded.placeId == game.PlaceId
                and decoded.schema == 1
                and type(environment.writefile) == "function" then
                pcall(
                    environment.writefile,
                    OUTPUT_FOLDER
                        .. "/MM2_Trajectory_Calibration.schema1.backup.json",
                    encoded
                )
            end
            warn(
                "[RTM:MM2:Trajectory] Caché schema 1 ignorada; schema 2 inicia limpio."
            )
            return
        end
        local aggregate: any = decoded.aggregate
        if type(aggregate) == "table" then
            runtime.gunAcceptance = restoreStats(aggregate.gunAcceptanceMs)
            runtime.knifeSpeed = restoreStats(aggregate.knifeSpeedStudsPerSecond)
            runtime.knifeSpawnDelay = restoreStats(aggregate.knifeSpawnDelayMs)
        end
        local analytics: any = decoded.analytics
        if type(analytics) == "table"
            and type(analytics.motionModel) == "table" then
            for key: string, bucket: any in pairs(analytics.motionModel) do
                local count: number = math.max(0, tonumber(bucket.count) or 0)
                local residual: any = bucket.meanConstantVelocityResidual
                local errors: any = bucket.meanModelError
                runtime.motionBuckets[key] = {
                    count = count,
                    horizontalLeadSum = (tonumber(bucket.meanHorizontalLeadSeconds) or 0)
                        * count,
                    horizontalLeadCount = bucket.meanHorizontalLeadSeconds ~= nil
                            and count
                        or 0,
                    verticalLeadSum = (tonumber(bucket.meanVerticalLeadSeconds) or 0)
                        * count,
                    verticalLeadCount = bucket.meanVerticalLeadSeconds ~= nil
                            and count
                        or 0,
                    residualXSum = type(residual) == "table"
                            and (tonumber(residual[1]) or 0) * count
                        or 0,
                    residualYSum = type(residual) == "table"
                            and (tonumber(residual[2]) or 0) * count
                        or 0,
                    residualZSum = type(residual) == "table"
                            and (tonumber(residual[3]) or 0) * count
                        or 0,
                    durationSum = (tonumber(bucket.meanDurationSeconds) or 0) * count,
                    constantVelocityErrorSum = type(errors) == "table"
                            and (tonumber(errors.constantVelocity) or 0) * count
                        or 0,
                    observedAccelerationErrorSum = type(errors) == "table"
                            and (tonumber(errors.observedAcceleration) or 0) * count
                        or 0,
                    airborneBallisticErrorSum = type(errors) == "table"
                            and (tonumber(errors.airborneBallistic) or 0) * count
                        or 0,
                }
            end
        end
        print("[RTM:MM2:Trajectory] Perfil acumulativo restaurado.")
    end

    local function normalizeGun(value: any): Tool?
        if typeof(value) ~= "Instance" then
            return nil
        end
        if value:IsA("Tool") then
            return value
        end
        return value:FindFirstAncestorOfClass("Tool")
    end

    finalizeGunCapture = function(pending: PendingGun): ()
        local analysis: {[string]: any} = analyzeTargetTrajectory(
            pending.targetTrajectory,
            pending.pingMs,
            "gun",
            (pending.latencyMs or 0) / 1000
        )
        appendEvent({
            kind = "gun",
            serverTime = workspace:GetServerTimeNow(),
            pingMs = pending.pingMs,
            latencyMs = pending.latencyMs,
            targetUserId = pending.targetUserId,
            targetName = pending.targetName,
            targetState = analysis.initialState,
            targetJumped = analysis.jumped,
            targetTrajectory = pending.targetTrajectory,
            observedDisplacement = analysis.displacement,
            constantVelocityResidual = analysis.constantVelocityResidual,
            horizontalLeadSeconds = analysis.horizontalLeadSeconds,
            verticalLeadSeconds = analysis.verticalLeadSeconds,
            endpoint = pending.confirmedEndpoint
                    and vectorArray(pending.confirmedEndpoint)
                or nil,
            hitTarget = pending.confirmedHitTarget,
            pingBucket = analysis.pingBucket,
            bestMotionModel = analysis.bestMotionModel,
            motionModelErrors = analysis.motionModelErrors,
            evaluationSeconds = analysis.evaluationSeconds,
        })
    end

    local function handleGunFired(
        eventGun: any,
        eventOriginValue: any,
        endpointValue: any,
        hitPartValue: any
    ): ()
        if not runtime.active then
            return
        end
        local now: number = os.clock()
        compactPending(runtime.pendingGuns, now)
        local eventTool: Tool? = normalizeGun(eventGun)
        local eventOrigin: Vector3? = worldPosition(eventOriginValue)
        local selectedIndex: number? = nil
        for index: number = #runtime.pendingGuns, 1, -1 do
            local pending: PendingGun = runtime.pendingGuns[index]
            local toolMatches: boolean = not pending.confirmedAt
                and eventTool == pending.tool
            local originMatches: boolean = eventOrigin ~= nil
                and pending.origin ~= nil
                and (eventOrigin - pending.origin).Magnitude <= 8
            if not pending.confirmedAt
                and (toolMatches or (eventTool == nil and originMatches)) then
                selectedIndex = index
                break
            end
        end
        if not selectedIndex then
            return
        end
        local pending: PendingGun = runtime.pendingGuns[selectedIndex]
        local latencyMs: number = math.max(0, (now - pending.activatedAt) * 1000)
        local target: Player? = pending.targetUserId
            and Players:GetPlayerByUserId(pending.targetUserId)
            or nil
        if target then
            local finalPoint: TrajectoryPoint? = captureTrajectoryPoint(
                target,
                pending.activatedAt,
                pending.pingMs
            )
            if finalPoint then
                table.insert(pending.targetTrajectory, finalPoint)
            end
        end
        local endpoint: Vector3? = worldPosition(endpointValue)
        local targetCharacter: Model? = target and target.Character
        local hitTarget: boolean = typeof(hitPartValue) == "Instance"
            and targetCharacter ~= nil
            and hitPartValue:IsDescendantOf(targetCharacter)
        addSample(runtime.gunAcceptance, latencyMs)
        runtime.sessionGunConfirmed += 1
        pending.confirmedAt = now
        pending.latencyMs = latencyMs
        pending.confirmedEndpoint = endpoint
        pending.confirmedHitTarget = hitTarget
        ensureTrajectorySampler()
    end

    local finishKnifeTrack: (projectile: Instance, reason: string) -> ()
    local function stopKnifeSamplerIfIdle(): ()
        if next(runtime.tracks) == nil then
            disconnectFeatureConnection("MM2TrajectorySampler")
        end
    end

    finishKnifeTrack = function(projectile: Instance, reason: string): ()
        local track: KnifeTrack? = runtime.tracks[projectile]
        if not track then
            return
        end
        runtime.tracks[projectile] = nil
        if track.destroyConnection then
            track.destroyConnection:Disconnect()
            track.destroyConnection = nil
        end
        local measuredSpeed: number? = median(track.speeds)
        local resolvedSpeed: number? = track.rawSpeed or measuredSpeed
        if resolvedSpeed and resolvedSpeed >= 24 and resolvedSpeed <= 300 then
            local analysis: {[string]: any} = analyzeTargetTrajectory(
                track.targetTrajectory,
                track.pingMs,
                "knife",
                nil
            )
            addSample(runtime.knifeSpeed, resolvedSpeed)
            runtime.sessionKnifeConfirmed += 1
            appendEvent({
                kind = "knife",
                serverTime = workspace:GetServerTimeNow(),
                pingMs = track.pingMs,
                latencyMs = track.spawnDelayMs,
                speed = resolvedSpeed,
                rawSpeed = track.rawSpeed,
                samples = #track.speeds,
                reason = reason,
                targetUserId = track.targetUserId,
                targetName = track.targetName,
                targetState = analysis.initialState,
                targetJumped = analysis.jumped,
                targetTrajectory = track.targetTrajectory,
                observedDisplacement = analysis.displacement,
                constantVelocityResidual = analysis.constantVelocityResidual,
                horizontalLeadSeconds = analysis.horizontalLeadSeconds,
                verticalLeadSeconds = analysis.verticalLeadSeconds,
                pingBucket = analysis.pingBucket,
                bestMotionModel = analysis.bestMotionModel,
                motionModelErrors = analysis.motionModelErrors,
                evaluationSeconds = analysis.evaluationSeconds,
            })
        end
        stopKnifeSamplerIfIdle()
    end

    local function ensureKnifeSampler(): ()
        if featureConnections.MM2TrajectorySampler then
            return
        end
        featureConnections.MM2TrajectorySampler = TaskManager:Connect(function(
            _deltaTime: number
        ): ()
            local now: number = os.clock()
            local completed: {Instance} = {}
            for projectile: Instance, track: KnifeTrack in pairs(runtime.tracks) do
                if not projectile.Parent or now - track.startedAt >= 1.25 then
                    table.insert(completed, projectile)
                    continue
                end
                local position: Vector3? = projectilePosition(projectile)
                if position and track.previousPosition and track.previousAt then
                    local sampleDelta: number = now - track.previousAt
                    local displacement: number = (position - track.previousPosition).Magnitude
                    if sampleDelta >= 1 / 240 and displacement >= 0.01 then
                        local speed: number = displacement / sampleDelta
                        if speed >= 24 and speed <= 300 then
                            table.insert(track.speeds, speed)
                        end
                    end
                end
                if position then
                    track.previousPosition = position
                    track.previousAt = now
                end
                if track.targetUserId
                    and now - track.lastTrajectorySampleAt >= 1 / 30 then
                    local target: Player? = Players:GetPlayerByUserId(
                        track.targetUserId
                    )
                    local point: TrajectoryPoint? = target
                        and captureTrajectoryPoint(
                            target,
                            track.startedAt - track.spawnDelayMs / 1000,
                            track.pingMs
                        )
                        or nil
                    if point and #track.targetTrajectory < 120 then
                        table.insert(track.targetTrajectory, point)
                    end
                    track.lastTrajectorySampleAt = now
                end
            end
            for _, projectile: Instance in ipairs(completed) do
                finishKnifeTrack(projectile, "sample-window-complete")
            end
        end)
    end

    local function resolveKnifeProjectile(projectile: Instance): ()
        task.spawn(function(): ()
            local linkedHandle: Instance? = nil
            for _attempt: number = 1, 20 do
                if not runtime.active or not projectile.Parent then
                    return
                end
                local handleLink: Instance? = projectile:FindFirstChild(
                    "HandleLink",
                    true
                )
                if handleLink and handleLink:IsA("ObjectValue") and handleLink.Value then
                    linkedHandle = handleLink.Value
                    break
                end
                task.wait(0.05)
            end
            if not linkedHandle then
                return
            end
            local now: number = os.clock()
            compactPending(runtime.pendingKnives, now)
            local selectedIndex: number? = nil
            for index: number = #runtime.pendingKnives, 1, -1 do
                local pending: PendingKnife = runtime.pendingKnives[index]
                local handle: Instance? = pending.tool:FindFirstChild("Handle")
                if linkedHandle == handle
                    or linkedHandle:IsDescendantOf(pending.tool) then
                    selectedIndex = index
                    break
                end
            end
            if not selectedIndex or runtime.tracks[projectile] then
                return
            end
            local pending: PendingKnife = table.remove(
                runtime.pendingKnives,
                selectedIndex
            )
            local spawnDelayMs: number = math.max(
                0,
                (now - pending.activatedAt) * 1000
            )
            addSample(runtime.knifeSpawnDelay, spawnDelayMs)
            local rawSpeed: number? = tonumber(projectile:GetAttribute("ThrowSpeed"))
            if rawSpeed and (rawSpeed < 24 or rawSpeed > 300) then
                rawSpeed = nil
            end
            local track: KnifeTrack = {
                startedAt = now,
                previousAt = now,
                previousPosition = projectilePosition(projectile),
                speeds = {},
                rawSpeed = rawSpeed,
                spawnDelayMs = spawnDelayMs,
                pingMs = pending.pingMs,
                targetUserId = pending.targetUserId,
                targetName = pending.targetName,
                targetTrajectory = pending.targetTrajectory,
                lastTrajectorySampleAt = now,
                destroyConnection = nil,
            }
            runtime.tracks[projectile] = track
            track.destroyConnection = projectile.Destroying:Connect(function(): ()
                finishKnifeTrack(projectile, "destroyed")
            end)
            ensureKnifeSampler()
        end)
    end

    local function isGun(tool: Tool): boolean
        return tool.Name == "Gun"
            or CollectionService:HasTag(tool, "Weapon_Gun")
            or tool:FindFirstChild("Shoot") ~= nil
    end

    local function isKnife(tool: Tool): boolean
        return tool.Name == "Knife"
            or CollectionService:HasTag(tool, "Weapon_Knife")
            or tool:FindFirstChild("Events") ~= nil
    end

    local function observeTool(tool: Tool): ()
        if runtime.observedTools[tool] then
            return
        end
        local gun: boolean = isGun(tool)
        local knife: boolean = isKnife(tool)
        if not gun and not knife then
            return
        end
        runtime.observedTools[tool] = true
        trackConnection(tool.Activated:Connect(function(): ()
            if not runtime.active then
                return
            end
            local now: number = os.clock()
            local requestedAim: Vector3? = getRequestedAim()
            local pingMs: number = getPingMilliseconds()
            local target: Player? = gun
                    and findMurderer()
                or findKnifeAnalysisTarget(requestedAim)
            local targetTrajectory: {TrajectoryPoint} = {}
            if target then
                local initialPoint: TrajectoryPoint? = captureTrajectoryPoint(
                    target,
                    now,
                    pingMs
                )
                if initialPoint then
                    table.insert(targetTrajectory, initialPoint)
                end
            end
            if gun then
                runtime.sessionGunAttempts += 1
                table.insert(runtime.pendingGuns, {
                    tool = tool,
                    activatedAt = now,
                    origin = toolOrigin(tool),
                    requestedAim = requestedAim,
                    pingMs = pingMs,
                    targetUserId = target and target.UserId or nil,
                    targetName = target and target.Name or nil,
                    targetTrajectory = targetTrajectory,
                    lastTrajectorySampleAt = now,
                })
                compactPending(runtime.pendingGuns, now)
            elseif knife then
                runtime.sessionKnifeAttempts += 1
                table.insert(runtime.pendingKnives, {
                    tool = tool,
                    activatedAt = now,
                    origin = toolOrigin(tool),
                    requestedAim = requestedAim,
                    pingMs = pingMs,
                    targetUserId = target and target.UserId or nil,
                    targetName = target and target.Name or nil,
                    targetTrajectory = targetTrajectory,
                    lastTrajectorySampleAt = now,
                })
                compactPending(runtime.pendingKnives, now)
            end
            ensureTrajectorySampler()
        end))
    end

    local function observeContainer(container: Instance?): ()
        if not container then
            return
        end
        for _, child: Instance in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then
                observeTool(child)
            end
        end
        trackConnection(container.ChildAdded:Connect(function(child: Instance): ()
            if child:IsA("Tool") then
                observeTool(child)
            end
        end))
    end

    local function installGunConfirmation(): ()
        task.spawn(function(): ()
            local clientServices: Instance? = nil
            local weaponModule: Instance? = nil
            for _attempt: number = 1, 20 do
                if not runtime.active then
                    return
                end
                clientServices = game:GetService("ReplicatedStorage")
                    :FindFirstChild("ClientServices")
                weaponModule = clientServices
                    and clientServices:FindFirstChild("WeaponService")
                if weaponModule then
                    break
                end
                task.wait(0.25)
            end
            if not weaponModule then
                warn("[RTM:MM2:Trajectory] WeaponService no apareció; Knife sigue activo.")
                return
            end
            local loaded: boolean, weaponService: any = pcall(
                state.requireModule,
                weaponModule
            )
            if not loaded or type(weaponService) ~= "table" then
                warn(
                    "[RTM:MM2:Trajectory] No se pudo observar WeaponService: "
                        .. tostring(weaponService)
                )
                return
            end
            local connected: boolean, connection: any = pcall(function(): any
                return weaponService.GunFired.OnClientEvent:Connect(handleGunFired)
            end)
            if connected and connection then
                trackConnection(connection :: RBXScriptConnection)
                print("[RTM:MM2:Trajectory] Confirmación GunFired conectada.")
            else
                warn(
                    "[RTM:MM2:Trajectory] GunFired no es compatible: "
                        .. tostring(connection)
                )
            end
        end)
    end

    controller = {} :: Controller

    function controller:start(): ()
        if runtime.active then
            return
        end
        if game.PlaceId ~= Module.PlaceId then
            warn("[RTM:MM2:Trajectory] Inicio omitido fuera de MM2.")
            return
        end
        runtime.active = true
        runtime.startedAt = os.clock()
        loadSnapshot()
        observeContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
        observeContainer(LocalPlayer.Character)
        trackConnection(LocalPlayer.CharacterAdded:Connect(function(
            character: Model
        ): ()
            observeContainer(character)
        end))
        trackConnection(
            CollectionService:GetInstanceAddedSignal("ThrowingKnife"):Connect(
                resolveKnifeProjectile
            )
        )
        installGunConfirmation()
        print("[RTM:MM2:Trajectory] Calibración pasiva iniciada en segundo plano.")
    end

    function controller:save(reason: string?): boolean
        return saveSnapshot(reason or "manual")
    end

    function controller:reset(): ()
        runtime.gunAcceptance = newStats()
        runtime.knifeSpeed = newStats()
        runtime.knifeSpawnDelay = newStats()
        runtime.motionBuckets = {}
        runtime.events = {}
        runtime.sessionGunAttempts = 0
        runtime.sessionGunConfirmed = 0
        runtime.sessionKnifeAttempts = 0
        runtime.sessionKnifeConfirmed = 0
        runtime.dirty = true
        saveSnapshot("reset")
    end

    function controller:getEstimates(): Estimates
        return estimates()
    end

    function controller:status(): string
        local current: Estimates = estimates()
        local knifeText: string = current.knifeSpeed
                and string.format("%.2f studs/s", current.knifeSpeed)
            or "learning"
        local bucketCount: number = 0
        for _key: string in pairs(runtime.motionBuckets) do
            bucketCount += 1
        end
        return string.format(
            "MM2 analytics · shots %d · throws %d · motion buckets %d · knife %s",
            current.confirmedShots,
            current.confirmedThrows,
            bucketCount,
            knifeText
        )
    end

    function controller:destroy(): ()
        if not runtime.active then
            return
        end
        if runtime.dirty then
            saveSnapshot("module-destroy")
        end
        runtime.active = false
        disconnectFeatureConnection("MM2TrajectorySampler")
        if runtime.trajectorySampler then
            runtime.trajectorySampler:Disconnect()
            runtime.trajectorySampler = nil
        end
        for projectile: Instance, track: KnifeTrack in pairs(runtime.tracks) do
            if track.destroyConnection then
                track.destroyConnection:Disconnect()
            end
            runtime.tracks[projectile] = nil
        end
        for _, connection: RBXScriptConnection in ipairs(runtime.connections) do
            connection:Disconnect()
        end
        table.clear(runtime.connections)
        table.clear(runtime.pendingGuns)
        table.clear(runtime.pendingKnives)
    end

    return controller
end

local trajectoryCalibration: any = createTrajectoryCalibration()
state.mm2TrajectoryCalibration = trajectoryCalibration
trajectoryCalibration:start()

type GunPrediction = {
    aimPart: BasePart,
    targetPosition: Vector3,
    endpoint: Vector3,
    velocity: Vector3,
    leadSeconds: number,
    confidence: number,
}

local function computeGunAim(
    target: Player,
    origin: CFrame
): (CFrame?, GunPrediction?)
    local character: Model? = target.Character
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid")
        :: Humanoid?
    local root: BasePart? = character
        and character:FindFirstChild("HumanoidRootPart")
        :: BasePart?
    if not character or not humanoid or humanoid.Health <= 0 or not root then
        return nil, nil
    end

    local velocity: Vector3 = getFilteredVelocity(target, root)
    local sample: MotionSample? = motionSamples[target]
    local stability: number = sample and sample.stability or 1
    local acceleration: Vector3 = sample and sample.acceleration or Vector3.zero
    local grounded: boolean = sample and sample.grounded or false
    local horizontalVelocity: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
    local leadSeconds: number, verticalLeadSeconds: number =
        getGunLeadSeconds()
    if horizontalVelocity.Magnitude < 1.5 and math.abs(velocity.Y) < 1.5 then
        leadSeconds = math.min(leadSeconds, 0.04)
        verticalLeadSeconds = math.min(verticalLeadSeconds, 0.04)
    end

    local moveDirection: Vector3 = humanoid.MoveDirection
    if horizontalVelocity.Magnitude < 1.5
        and moveDirection.Magnitude > 0.05 then
        local desiredSpeed: number = humanoid.WalkSpeed
        local desiredVelocity: Vector3 = moveDirection.Unit * desiredSpeed
        velocity = Vector3.new(
            desiredVelocity.X,
            velocity.Y,
            desiredVelocity.Z
        )
    end

    local raycastParams: RaycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    local ignored: {Instance} = {}
    if LocalPlayer.Character then
        table.insert(ignored, LocalPlayer.Character)
    end
    raycastParams.FilterDescendantsInstances = ignored
    local localHead: BasePart? = LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChild("Head")
        :: BasePart?
    if localHead and localHead:IsA("BasePart") then
        local muzzleBlocked: RaycastResult? = workspace:Raycast(
            localHead.Position,
            origin.Position - localHead.Position,
            raycastParams
        )
        if muzzleBlocked then
            return nil, nil
        end
    end

    local candidates: {string} = {
        "UpperTorso",
        "Torso",
        "HumanoidRootPart",
        "Head",
    }
    local leadScales: {number} = {1, 0.82, 0.6, 0.35, 0}
    for _, leadScale: number in ipairs(leadScales) do
        local scaledLead: number = leadSeconds * leadScale
        local scaledVerticalLead: number =
            verticalLeadSeconds * leadScale
        for _, partName: string in ipairs(candidates) do
            local part: BasePart? = character:FindFirstChild(partName) :: BasePart?
            if part and part:IsA("BasePart") then
                local horizontalAcceleration: Vector3 = Vector3.new(
                    acceleration.X,
                    0,
                    acceleration.Z
                )
                local displacement: Vector3 = Vector3.new(
                    velocity.X * scaledLead,
                    0,
                    velocity.Z * scaledLead
                ) + horizontalAcceleration * (
                    0.25 * scaledLead * scaledLead
                )
                if grounded then
                    displacement = Vector3.new(
                        displacement.X,
                        math.clamp(velocity.Y, -2.5, 2.5)
                            * scaledVerticalLead,
                        displacement.Z
                    )
                else
                    displacement = Vector3.new(
                        displacement.X,
                        velocity.Y * scaledVerticalLead
                            - 0.5
                                * workspace.Gravity
                                * scaledVerticalLead
                                * scaledVerticalLead,
                        displacement.Z
                    )
                end

                local predicted: Vector3 = part.Position + displacement
                local delta: Vector3 = predicted - origin.Position
                if delta.Magnitude > 0.05 then
                    local direction: Vector3 = delta.Unit
                    local endpoint: Vector3 = predicted
                    local result: RaycastResult? = workspace:Raycast(
                        origin.Position,
                        predicted - origin.Position,
                        raycastParams
                    )
                    if not result or result.Instance:IsDescendantOf(character) then
                        local confidence: number = math.clamp(
                            stability
                                * (1 - math.min(acceleration.Magnitude / 240, 0.45)),
                            0.2,
                            1
                        )
                        return CFrame.lookAt(
                            endpoint,
                            endpoint + direction
                        ), {
                            aimPart = part,
                            targetPosition = predicted,
                            endpoint = endpoint,
                            velocity = velocity,
                            leadSeconds = scaledLead,
                            confidence = confidence,
                        }
                    end
                end
            end
        end
    end
    return nil, nil
end

local function getSelectedShootTarget(): Player?
    local target
    if mm2Settings.shootMode == "Custom"
        and mm2Settings.shootTarget ~= "" then
        target = findPlayerByText(mm2Settings.shootTarget)
    else
        target = findMurderer()
    end
    if not target
        or target == LocalPlayer
        or not isPlayerAlive(target)
        or state.isProtectedTarget(target) then
        return nil
    end
    if mm2Settings.shootMode ~= "Custom"
        and getPlayerRole(target) ~= "Murderer" then
        return nil
    end
    return target
end

local function fireGunAtTarget(target: Player?): boolean
    local character, humanoid = getCharacterParts()
    if not target or not target.Character then
        notify("No selected shoot target was found.")
        return false
    end
    if not character or not humanoid then
        notify("Your character is not available.")
        return false
    end

    local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun")
    local backpack: Backpack? = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not gun and backpack then
        notify("You do not have the sheriff gun.")
        return false
    end
    if gun and gun.Parent == backpack and humanoid:IsA("Humanoid") then
        humanoid:EquipTool(gun)
        task.wait()
    end

    gun = getPlayerWeapon(LocalPlayer, "Gun", true) or gun
    local remote: Instance? = gun and gun:FindFirstChild("Shoot")
    local origin: CFrame? = getGunOriginCFrame(character, gun)

    local aim: CFrame? = nil
    local prediction: GunPrediction? = nil
    if origin then
        aim, prediction = computeGunAim(target, origin)
    end

    if not remote
        or not remote:IsA("RemoteEvent")
        or not origin
        or not aim then
        notify("The murderer is unavailable or obstructed.")
        return false
    end

    state.mm2ShotFeedback.queue(target, gun, origin, aim, prediction, true)
    remote:FireServer(origin, aim)
    return true
end

local function shootMurderer(): ()
    fireGunAtTarget(getSelectedShootTarget())
end

local shootFeatureActive: boolean = false
local shootHookInstalled: boolean = false
local shootTouchHookInstalled: boolean = false
local shootHookOriginal: any = nil
local shootTouchHookOriginal: any = nil
local shootHookWrapper: any = nil
local shootTouchHookWrapper: any = nil
local weaponServiceModule: any = nil
type PendingShot = {
    target: Player,
    targetCharacter: Model?,
    gun: Tool,
    origin: Vector3,
    aimPosition: Vector3?,
    healthBefore: number,
    targetedMurderer: boolean,
    queuedAt: number,
}

state.mm2ShotFeedback = {
    pending = nil :: PendingShot?,
    lastAccepted = nil :: PendingShot?,
    token = 0,
    defaultDuration = 5,
    gunFiredConnected = false,
    theme = {
        Background = Color3.fromRGB(14, 14, 18),
        Accent = Color3.fromRGB(205, 82, 42),
        Outline = Color3.fromRGB(220, 115, 58),
        Text = Color3.fromRGB(255, 232, 208),
    },
    resolve = function(_candidate: PendingShot, _directHit: boolean): () end,
    showMiss = function(_gun: Tool, _candidate: PendingShot): () end,
}
state.mm2ShotFeedback.root = create("Frame", {
    Parent = ScreenGui,
    Name = "MM2ShotCooldown",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = state.mm2ShotFeedback.theme.Background,
    BackgroundTransparency = 0.38,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.fromScale(0.5, 0.62),
    Size = UDim2.fromOffset(320, 36),
    Visible = false,
    ZIndex = 240,
}) :: Frame
create("UICorner", {
    Parent = state.mm2ShotFeedback.root,
    CornerRadius = UDim.new(0, 7),
})
create("UIStroke", {
    Parent = state.mm2ShotFeedback.root,
    Color = state.mm2ShotFeedback.theme.Outline,
    Transparency = 0.35,
    Thickness = 1,
})
state.mm2ShotFeedback.fill = create("Frame", {
    Parent = state.mm2ShotFeedback.root,
    Name = "Fill",
    BackgroundColor3 = state.mm2ShotFeedback.theme.Accent,
    BackgroundTransparency = 0.46,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(0, 1),
    ZIndex = 241,
}) :: Frame
create("UICorner", {
    Parent = state.mm2ShotFeedback.fill,
    CornerRadius = UDim.new(0, 7),
})
state.mm2ShotFeedback.text = create("TextLabel", {
    Parent = state.mm2ShotFeedback.root,
    Name = "Countdown",
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Size = UDim2.fromScale(1, 1),
    Text = "",
    TextColor3 = state.mm2ShotFeedback.theme.Text,
    TextSize = 13,
    ZIndex = 242,
}) :: TextLabel

state.mm2ShotFeedback.hide = function(): ()
    disconnectFeatureConnection("MM2ShootCooldown")
    state.mm2ShotFeedback.token += 1
    state.mm2ShotFeedback.root.Visible = false
    state.mm2ShotFeedback.fill.Size = UDim2.fromScale(0, 1)
    state.mm2ShotFeedback.text.Text = ""
end

state.mm2ShotFeedback.getDuration = function(gun: Tool?): number
    if gun then
        for _, attributeName: string in ipairs({
            "Cooldown",
            "ReloadTime",
            "ShotCooldown",
        }) do
            local value: number? = tonumber(gun:GetAttribute(attributeName))
            if value and value >= 0.5 and value <= 15 then
                return value
            end
        end
    end
    return state.mm2ShotFeedback.defaultDuration
end

state.mm2ShotFeedback.queue = function(
    target: Player?,
    gun: Tool?,
    origin: CFrame?,
    aim: CFrame?,
    _prediction: GunPrediction?,
    knownFired: boolean
): ()
    if not target or not gun or not origin then
        return
    end

    local targetCharacter: Model? = target.Character
    local targetHumanoid: Humanoid? = targetCharacter
        and targetCharacter:FindFirstChildOfClass("Humanoid")
        :: Humanoid?
    local candidate: PendingShot = {
        target = target,
        targetCharacter = targetCharacter,
        gun = gun,
        origin = origin.Position,
        aimPosition = aim and aim.Position,
        healthBefore = targetHumanoid and targetHumanoid.Health or 0,
        targetedMurderer = getPlayerRole(target) == "Murderer",
        queuedAt = os.clock(),
    }
    state.mm2ShotFeedback.pending = candidate

    -- Aim getters may be queried without a shot reaching the server. Expiry is
    -- therefore cleanup-only; only a correlated GunFired event may show a miss.
    task.delay(1.8, function(): ()
        if state.mm2ShotFeedback.pending == candidate then
            state.mm2ShotFeedback.pending = nil
        end
    end)
    if knownFired and not state.mm2ShotFeedback.gunFiredConnected then
        task.delay(math.max(0.35, mm2Settings.predictionRtt + 0.18), function(): ()
            if state.mm2ShotFeedback.pending ~= candidate
                or state.mm2ShotFeedback.gunFiredConnected then
                return
            end
            state.mm2ShotFeedback.pending = nil
            state.mm2ShotFeedback.resolve(candidate, false)
        end)
    end
end

state.mm2ShotFeedback.showMiss = function(
    gun: Tool,
    candidate: PendingShot
): ()
    state.mm2ShotFeedback.hide()
    local duration: number = state.mm2ShotFeedback.getDuration(gun)
    local cooldownEndsAt: number = candidate.queuedAt + duration
    local initialRemaining: number = cooldownEndsAt - os.clock()
    if initialRemaining <= 0 then
        return
    end

    disconnectFeatureConnection("MM2ShootCooldown")
    state.mm2ShotFeedback.token += 1
    local token: number = state.mm2ShotFeedback.token
    state.mm2ShotFeedback.root.Visible = true

    local function updateCountdown(): ()
        if token ~= state.mm2ShotFeedback.token then
            disconnectFeatureConnection("MM2ShootCooldown")
            state.mm2ShotFeedback.root.Visible = false
            return
        end

        local remaining: number = math.max(0, cooldownEndsAt - os.clock())
        if remaining <= 0 then
            state.mm2ShotFeedback.hide()
            return
        end

        local progress: number = math.clamp(remaining / duration, 0, 1)
        state.mm2ShotFeedback.fill.Size = UDim2.fromScale(progress, 1)
        state.mm2ShotFeedback.text.Text =
            string.format("Miss cooldown - %.1fs", remaining)
    end

    updateCountdown()
    featureConnections.MM2ShootCooldown =
        TaskManager:Connect(updateCountdown)
end

state.mm2ShotFeedback.toPosition = function(value: any): Vector3?
    if typeof(value) == "Vector3" then
        return value
    end
    if typeof(value) == "CFrame" then
        return value.Position
    end
    if typeof(value) == "Instance" then
        if value:IsA("Attachment") then
            return value.WorldPosition
        end
        if value:IsA("BasePart") then
            return value.Position
        end
    end
    return nil
end

state.mm2ShotFeedback.resolve = function(
    candidate: PendingShot,
    directHit: boolean
): ()
    state.mm2ShotFeedback.hide()
    state.mm2ShotFeedback.lastAccepted = candidate
    local confirmationDelay: number = math.clamp(
        math.max(0.18, mm2Settings.predictionRtt + 0.12),
        0.18,
        0.55
    )
    task.delay(confirmationDelay, function(): ()
        if state.mm2ShotFeedback.lastAccepted ~= candidate then
            return
        end
        state.mm2ShotFeedback.lastAccepted = nil

        local targetCharacter: Model? = candidate.targetCharacter
        local currentHumanoid: Humanoid? = targetCharacter
            and targetCharacter:FindFirstChildOfClass("Humanoid")
            :: Humanoid?
        local hitConfirmed: boolean = directHit
            or candidate.target.Parent ~= Players
            or targetCharacter == nil
            or targetCharacter.Parent == nil
            or currentHumanoid == nil
            or currentHumanoid.Health <= 0
            or currentHumanoid.Health < candidate.healthBefore
            or (
                candidate.targetedMurderer
                and getPlayerRole(candidate.target) ~= "Murderer"
            )

        if hitConfirmed then
            state.mm2ShotFeedback.hide()
        end

        if not hitConfirmed and mm2Settings.showMissCooldown then
            state.mm2ShotFeedback.showMiss(candidate.gun, candidate)
        end
    end)
end

state.mm2ShotFeedback.handleGunFired = function(
    firedGun: any,
    eventOrigin: any,
    endpoint: any,
    hitPart: any
): ()
    if not shootFeatureActive then
        return
    end

    local candidate: PendingShot? = state.mm2ShotFeedback.pending
    if not candidate then
        return
    end
    if os.clock() - candidate.queuedAt > 1.6 then
        state.mm2ShotFeedback.pending = nil
        return
    end

    local eventObject: Instance? = typeof(firedGun) == "Instance"
        and firedGun
        or nil
    local eventTool: Tool? = nil
    if eventObject then
        if eventObject:IsA("Tool") then
            eventTool = eventObject
        else
            eventTool = eventObject:FindFirstAncestorOfClass("Tool")
        end
    end
    local weaponMatches: boolean = eventTool == candidate.gun
        or eventObject == candidate.gun
        or (
            eventObject ~= nil
            and eventObject:IsDescendantOf(candidate.gun)
        )
    local eventOriginPosition: Vector3? =
        state.mm2ShotFeedback.toPosition(eventOrigin)
    local originMatches: boolean = eventOriginPosition ~= nil
        and (eventOriginPosition - candidate.origin).Magnitude <= 3.5
    local endpointPosition: Vector3? =
        state.mm2ShotFeedback.toPosition(endpoint)
    local directionMatches: boolean = true
    if eventOriginPosition and endpointPosition and candidate.aimPosition then
        local eventDelta: Vector3 = endpointPosition - eventOriginPosition
        local expectedDelta: Vector3 =
            candidate.aimPosition - candidate.origin
        if eventDelta.Magnitude > 0.05 and expectedDelta.Magnitude > 0.05 then
            directionMatches = eventDelta.Unit:Dot(expectedDelta.Unit) >= 0.965
        end
    end
    if eventTool then
        if not weaponMatches then
            return
        end
    elseif not weaponMatches and (not originMatches or not directionMatches) then
        return
    end

    state.mm2ShotFeedback.pending = nil
    local targetCharacter: Model? = candidate.targetCharacter
    local hitTarget: boolean = typeof(hitPart) == "Instance"
        and targetCharacter ~= nil
        and hitPart:IsDescendantOf(targetCharacter)
    state.mm2ShotFeedback.resolve(candidate, hitTarget)
end

type KnifeSettings = {
    redirect: boolean,
    aura: boolean,
    auraRange: number,
    showTarget: boolean,
    targetClosestToMouse: boolean,
}

type KnifeRuntimeState = {
    visual: BoxHandleAdornment?,
    redirectTarget: Player?,
    redirectScore: number,
    redirectLockedAt: number,
    velocityTarget: Player?,
    velocity: Vector3,
    velocitySampleAt: number,
    observedProjectileSpeed: number,
    lastAuraSwing: number,
}

local knifeSettings: KnifeSettings = {
    redirect = false,
    aura = false,
    auraRange = 14,
    showTarget = true,
    targetClosestToMouse = true,
}
state.mm2KnifeRuntime = {
    visual = nil,
    redirectTarget = nil,
    redirectScore = math.huge,
    redirectLockedAt = 0,
    velocityTarget = nil,
    velocity = Vector3.zero,
    velocitySampleAt = 0,
    observedProjectileSpeed = 96,
    lastAuraSwing = -math.huge,
} :: KnifeRuntimeState

local function getEquippedWeapon(name: string, _tag: string): Tool?
    return getPlayerWeapon(LocalPlayer, name, true)
end

local KNIFE_TARGET_HYSTERESIS_PIXELS: number = 6
local KNIFE_TARGET_MAX_LOCK_SECONDS: number = 0.12

local function getKnifeProjectileSpeed(knife: Tool): number
    local localCharacter: Model? = LocalPlayer.Character
    local knifeHandle: BasePart? = knife:FindFirstChild("Handle") :: BasePart?
    for _, projectile: Instance in ipairs(
        CollectionService:GetTagged("ThrowingKnife")
    ) do
        local handleLink: Instance? = projectile:FindFirstChild("HandleLink")
        local linkedHandle: Instance? = handleLink
                and handleLink:IsA("ObjectValue")
                and handleLink.Value
            or nil
        local belongsToLocalKnife: boolean = linkedHandle ~= nil
            and (
                linkedHandle == knifeHandle
                or linkedHandle:IsDescendantOf(knife)
                or (
                    localCharacter ~= nil
                    and linkedHandle:IsDescendantOf(localCharacter)
                )
            )
        if belongsToLocalKnife then
            local speed: number? =
                tonumber(projectile:GetAttribute("ThrowSpeed"))
            if speed and speed >= 24 and speed <= 300 then
                state.mm2KnifeRuntime.observedProjectileSpeed = speed
                break
            end
        end
    end
    return state.mm2KnifeRuntime.observedProjectileSpeed
end

local function canUseEquippedKnife(): (Tool?, BasePart?)
    local character: Model? = LocalPlayer.Character
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid")
        :: Humanoid?
    local root: BasePart? = character
        and character:FindFirstChild("HumanoidRootPart")
        :: BasePart?
    local knife: Tool? = getEquippedWeapon("Knife", "Weapon_Knife")
    if not character
        or not humanoid
        or humanoid.Health <= 0
        or not root
        or not knife
        or knife:GetAttribute("Disabled") == true
        or getPlayerRole(LocalPlayer) ~= "Murderer" then
        return nil, nil
    end
    return knife, root
end

local function isValidKnifeTarget(player: Player): boolean
    if player == LocalPlayer
        or state.isProtectedTarget(player)
        or not isPlayerAlive(player)
        or getPlayerRole(player) == "Murderer" then
        return false
    end
    return player.Character ~= nil
        and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getKnifeCandidateScore(
    player: Player,
    localRoot: BasePart,
    pointer: Vector2,
    camera: Camera
): (number?, boolean)
    local targetCharacter: Model? = player.Character
    local root: BasePart? = targetCharacter
        and targetCharacter:FindFirstChild("HumanoidRootPart")
        :: BasePart?
    if not root then
        return nil, false
    end

    if not knifeSettings.targetClosestToMouse then
        return (root.Position - localRoot.Position).Magnitude, true
    end

    local viewport: Vector3, visible: boolean =
        camera:WorldToViewportPoint(root.Position)
    if not visible then
        return nil, false
    end
    return (
        pointer - Vector2.new(viewport.X, viewport.Y)
    ).Magnitude, true
end

local function findKnifeRedirectCandidate(
    localRoot: BasePart
): (Player?, number)
    local camera: Camera? = workspace.CurrentCamera
    if not camera then
        return nil, math.huge
    end

    local pointer: Vector2 = getPointerPosition()
    local closest: Player? = nil
    local closestScore: number = math.huge
    for _, player: Player in ipairs(Players:GetPlayers()) do
        if isValidKnifeTarget(player) then
            local score: number?, eligible: boolean = getKnifeCandidateScore(
                player,
                localRoot,
                pointer,
                camera
            )
            if eligible and score and score < closestScore then
                closest = player
                closestScore = score
            end
        end
    end
    return closest, closestScore
end

local function getLockedKnifeRedirectTarget(localRoot: BasePart): Player?
    local acquired: Player?, acquiredScore: number =
        findKnifeRedirectCandidate(localRoot)
    local current: Player? = state.mm2KnifeRuntime.redirectTarget
    local currentScore: number = math.huge
    local camera: Camera? = workspace.CurrentCamera
    if current and isValidKnifeTarget(current) and camera then
        local score: number?, eligible: boolean = getKnifeCandidateScore(
            current,
            localRoot,
            getPointerPosition(),
            camera
        )
        if eligible and score then
            currentScore = score
        else
            current = nil
        end
    else
        current = nil
    end

    local now: number = os.clock()
    local shouldSwitch: boolean = current == nil
        or acquired == nil
        or acquired == current
        or acquiredScore + KNIFE_TARGET_HYSTERESIS_PIXELS < currentScore
        or now - state.mm2KnifeRuntime.redirectLockedAt
            >= KNIFE_TARGET_MAX_LOCK_SECONDS
    local selected: Player? = shouldSwitch and acquired or current
    local selectedScore: number = selected == acquired
        and acquiredScore
        or currentScore

    if selected ~= state.mm2KnifeRuntime.redirectTarget then
        state.mm2KnifeRuntime.redirectTarget = selected
        state.mm2KnifeRuntime.redirectLockedAt = now
        state.mm2KnifeRuntime.velocityTarget = nil
        state.mm2KnifeRuntime.velocity = Vector3.zero
        state.mm2KnifeRuntime.velocitySampleAt = 0
    end
    state.mm2KnifeRuntime.redirectScore = selectedScore
    return selected
end

local function findKnifeAuraTarget(
    localRoot: BasePart,
    maxDistance: number
): Player?
    local closest: Player? = nil
    local closestDistance: number = maxDistance
    for _, player: Player in ipairs(Players:GetPlayers()) do
        if isValidKnifeTarget(player) then
            local targetRoot: BasePart? = player.Character
                and player.Character:FindFirstChild("HumanoidRootPart")
                :: BasePart?
            if targetRoot then
                local distance: number =
                    (targetRoot.Position - localRoot.Position).Magnitude
                if distance <= closestDistance then
                    closest = player
                    closestDistance = distance
                end
            end
        end
    end
    return closest
end

local function clearKnifeAuraVisuals(): ()
    local visual: BoxHandleAdornment? = state.mm2KnifeRuntime.visual
    if visual then
        visual:Destroy()
        state.mm2KnifeRuntime.visual = nil
    end
end

local function updateKnifeAuraVisual(
    target: Player?,
    predictedCFrame: CFrame?,
    _travelTime: number?
): ()
    local knife: Tool? = canUseEquippedKnife()
    local character: Model? = target and target.Character
    local root: BasePart? = target
        and character
        and character:FindFirstChild("HumanoidRootPart")
        :: BasePart?
    if not knife
        or not target
        or not character
        or not root
        or not knifeSettings.showTarget then
        clearKnifeAuraVisuals()
        return
    end

    local visual: BoxHandleAdornment? = state.mm2KnifeRuntime.visual
    if not visual then
        local box: BoxHandleAdornment = Instance.new("BoxHandleAdornment")
        box.Name = "RTM_KnifePredictionEnvelope"
        box.AlwaysOnTop = true
        box.ZIndex = 20
        box.Color3 = Color3.fromRGB(180, 45, 35)
        box.Transparency = 0.48
        box.Size = Vector3.new(5.5, 7, 5.5)
        box.Parent = ScreenGui
        state.mm2KnifeRuntime.visual = box
        visual = box
    end
    if visual then
        local predictedPosition: Vector3 = predictedCFrame
                and predictedCFrame.Position
            or root.Position
        local localPosition: Vector3 =
            root.CFrame:PointToObjectSpace(predictedPosition)
        local desiredCFrame: CFrame = CFrame.new(localPosition)
        local sameAdornee: boolean = visual.Adornee == root
        visual.Adornee = root
        visual.CFrame = sameAdornee
                and visual.CFrame:Lerp(desiredCFrame, 0.45)
            or desiredCFrame
    end
end

local function getStableKnifeVelocity(
    target: Player,
    targetRoot: BasePart
): Vector3
    local now: number = os.clock()
    local rawVelocity: Vector3 = targetRoot.AssemblyLinearVelocity
    if rawVelocity.Magnitude > 110 then
        rawVelocity = rawVelocity.Unit * 110
    end

    local previousTarget: Player? = state.mm2KnifeRuntime.velocityTarget
    local previousVelocity: Vector3 = state.mm2KnifeRuntime.velocity
    local previousSampleAt: number = state.mm2KnifeRuntime.velocitySampleAt
    local deltaTime: number = now - previousSampleAt
    if previousTarget ~= target or deltaTime <= 0 or deltaTime > 0.35 then
        state.mm2KnifeRuntime.velocityTarget = target
        state.mm2KnifeRuntime.velocity = rawVelocity
        state.mm2KnifeRuntime.velocitySampleAt = now
        return rawVelocity
    end
    if deltaTime < 1 / 120 then
        return previousVelocity
    end

    local alpha: number = 1 - math.exp(-deltaTime * 10)
    local velocity: Vector3 = previousVelocity:Lerp(
        rawVelocity,
        math.clamp(alpha, 0.08, 0.65)
    )
    state.mm2KnifeRuntime.velocity = velocity
    state.mm2KnifeRuntime.velocitySampleAt = now
    return velocity
end

local function getKnifeAcceleration(target: Player): Vector3
    local sample: MotionSample? = motionSamples[target]
    if not sample then
        return Vector3.zero
    end
    if not sample.grounded then
        return Vector3.new(0, -workspace.Gravity, 0)
    end

    local horizontal: Vector3 = Vector3.new(
        sample.acceleration.X,
        0,
        sample.acceleration.Z
    ) * sample.stability
    if horizontal.Magnitude > 70 then
        horizontal = horizontal.Unit * 70
    end
    return horizontal
end

-- prediction.lua solves the same interception equation through polynomial roots.
-- MM2 knives have zero projectile gravity, so a short fixed-point refinement is
-- both cheaper and able to include the target's acceleration and one-way RTT.
local function solveKnifeIntercept(
    origin: Vector3,
    projectileSpeed: number,
    targetPosition: Vector3,
    targetVelocity: Vector3,
    targetAcceleration: Vector3,
    latency: number
): (Vector3?, number?)
    if projectileSpeed <= 0 then
        return nil, nil
    end

    local releasePosition: Vector3 = targetPosition
        + targetVelocity * latency
        + targetAcceleration * (0.5 * latency * latency)
    local releaseVelocity: Vector3 =
        targetVelocity + targetAcceleration * latency
    local linearAim: Vector3?, linearTime: number? = solveLinearIntercept(
        origin,
        projectileSpeed,
        releasePosition,
        releaseVelocity,
        0
    )
    local travelTime: number = linearTime
        or (releasePosition - origin).Magnitude / projectileSpeed
    if travelTime <= 0 or travelTime > 3 then
        return nil, nil
    end

    local predicted: Vector3 = linearAim or releasePosition
    for _iteration: number = 1, 5 do
        local totalTime: number = latency + travelTime
        predicted = targetPosition
            + targetVelocity * totalTime
            + targetAcceleration * (0.5 * totalTime * totalTime)
        local refinedTime: number =
            (predicted - origin).Magnitude / projectileSpeed
        if refinedTime <= 0 or refinedTime > 3 then
            return nil, nil
        end
        if math.abs(refinedTime - travelTime) < 0.0015 then
            travelTime = refinedTime
            break
        end
        travelTime += (refinedTime - travelTime) * 0.72
    end
    return predicted, travelTime
end

local function redirectedKnifeCFrame(updateVisual: boolean?): CFrame?
    local knife: Tool?, localRoot: BasePart? = canUseEquippedKnife()
    local target: Player? = localRoot
        and getLockedKnifeRedirectTarget(localRoot)
        or nil
    local targetRoot: BasePart? = target
        and target.Character
        and target.Character:FindFirstChild("HumanoidRootPart")
        :: BasePart?
    if not knife or not localRoot or not target or not targetRoot then
        if updateVisual then
            clearKnifeAuraVisuals()
        end
        return nil
    end

    local handle: BasePart? = knife:FindFirstChild("Handle") :: BasePart?
    if not handle or not handle:IsA("BasePart") then
        if updateVisual then
            clearKnifeAuraVisuals()
        end
        return nil
    end

    local origin: Vector3 = handle.Position
    local targetVelocity: Vector3 = getStableKnifeVelocity(target, targetRoot)
    local targetAcceleration: Vector3 = getKnifeAcceleration(target)
    local latency: number = math.clamp(
        getEstimatedLatency() * 0.5 + (1 / 60),
        0.025,
        0.18
    )
    local projectileSpeed: number = getKnifeProjectileSpeed(knife)
    local predictedRoot: Vector3?, rootTravelTime: number? =
        solveKnifeIntercept(
            origin,
            projectileSpeed,
            targetRoot.Position,
            targetVelocity,
            targetAcceleration,
            latency
        )
    if not predictedRoot then
        if updateVisual then
            clearKnifeAuraVisuals()
        end
        return nil
    end

    local selectedAim: Vector3? = nil
    local targetCharacter: Model = target.Character :: Model
    for _, partName: string in ipairs({
        "UpperTorso",
        "Torso",
        "HumanoidRootPart",
        "Head",
    }) do
        local targetPart: BasePart? =
            targetCharacter:FindFirstChild(partName) :: BasePart?
        if targetPart and targetPart:IsA("BasePart") then
            local predictedPart: Vector3? = solveKnifeIntercept(
                origin,
                projectileSpeed,
                targetPart.Position,
                targetVelocity,
                targetAcceleration,
                latency
            )
            if predictedPart then
                selectedAim = predictedPart
                break
            end
        end
    end
    if not selectedAim then
        if updateVisual then
            clearKnifeAuraVisuals()
        end
        return nil
    end
    if updateVisual then
        updateKnifeAuraVisual(
            target,
            CFrame.new(predictedRoot),
            rootTravelTime
        )
    end

    local throwDirection: Vector3 = selectedAim - origin
    if throwDirection.Magnitude <= 0.001 then
        return CFrame.new(selectedAim)
    end
    return CFrame.lookAt(selectedAim, selectedAim + throwDirection.Unit)
end
local function redirectedTargetCFrame(): (
    CFrame?,
    Player?,
    Tool?,
    CFrame?,
    GunPrediction?
)
    local target: Player? = getSelectedShootTarget()
    local character: Model? = LocalPlayer.Character
    local gun: Tool? = getEquippedWeapon("Gun", "Weapon_Gun")
    local origin: CFrame? = character and getGunOriginCFrame(character, gun)
    if target and origin and gun then
        local aim: CFrame?, prediction: GunPrediction? =
            computeGunAim(target, origin)
        return aim, target, gun, origin, prediction
    end
    return nil, nil, gun, origin, nil
end

local function getRedirectedWeaponCFrame(): CFrame?
    if shootFeatureActive then
        local targetCFrame: CFrame?,
            target: Player?,
            gun: Tool?,
            origin: CFrame?,
            prediction: GunPrediction? = redirectedTargetCFrame()
        if target and gun and origin and targetCFrame then
            state.mm2ShotFeedback.queue(
                target,
                gun,
                origin,
                targetCFrame,
                prediction,
                false
            )
            return targetCFrame
        end
    end

    if knifeSettings.redirect then
        return redirectedKnifeCFrame()
    end
    return nil
end

local function getWeaponServiceModule(): any
    if type(weaponServiceModule) == "table" then
        return weaponServiceModule
    end

    local loaded: boolean, result: any = pcall(function(): any
        return state.requireModule(
            game:GetService("ReplicatedStorage")
                :WaitForChild("ClientServices")
                :WaitForChild("WeaponService")
        )
    end)
    if loaded and type(result) == "table" then
        weaponServiceModule = result
        return result
    end
    return nil
end

local function connectGunFiredSignal(weaponService: any): boolean
    if featureConnections.MM2GunFired then
        state.mm2ShotFeedback.gunFiredConnected = true
        return true
    end

    local gunFired: any = weaponService.GunFired
    local connected: boolean, connection: any = pcall(function(): any
        return gunFired.OnClientEvent:Connect(
            state.mm2ShotFeedback.handleGunFired
        )
    end)
    if connected and connection then
        featureConnections.MM2GunFired = connection
        state.mm2ShotFeedback.gunFiredConnected = true
        return true
    end
    state.mm2ShotFeedback.gunFiredConnected = false
    return false
end

local function installShootRedirectHook(): boolean
    local weaponService: any = getWeaponServiceModule()
    if type(weaponService) ~= "table" then
        return false
    end
    connectGunFiredSignal(weaponService)

    local touchPreferred: boolean =
        UserInputService.PreferredInput == Enum.PreferredInput.Touch
    if shootHookInstalled then
        return not touchPreferred or shootTouchHookInstalled
    end
    if type(state.hookFunction) ~= "function"
        or type(weaponService.GetMouseTargetCFrame) ~= "function" then
        return false
    end

    local mouseHooked: boolean = pcall(function(): ()
        local predecessor: any = nil
        local wrapper: any = nil
        wrapper = function(self: any, ...: any): any
            local targetCFrame: CFrame? = getRedirectedWeaponCFrame()
            if targetCFrame then
                return targetCFrame
            end
            return predecessor(self, ...)
        end
        predecessor = state.hookFunction(
            weaponService.GetMouseTargetCFrame,
            wrapper
        )
        shootHookOriginal = predecessor
        shootHookWrapper = wrapper
    end)
    if not mouseHooked or type(shootHookOriginal) ~= "function" then
        return false
    end

    shootHookInstalled = true
    if type(weaponService.GetTargetPosition) == "function" then
        shootTouchHookInstalled = pcall(function(): ()
            local predecessor: any = nil
            local wrapper: any = nil
            wrapper = function(self: any, ...: any): any
                local targetCFrame: CFrame? = getRedirectedWeaponCFrame()
                if targetCFrame then
                    return targetCFrame.Position
                end
                return predecessor(self, ...)
            end
            predecessor = state.hookFunction(
                weaponService.GetTargetPosition,
                wrapper
            )
            shootTouchHookOriginal = predecessor
            shootTouchHookWrapper = wrapper
        end)
        shootTouchHookInstalled = shootTouchHookInstalled
            and type(shootTouchHookOriginal) == "function"
    end

    return not touchPreferred or shootTouchHookInstalled
end

local function mm2RoleProvider(player: Player): string?
    if roundLifecycleActive == false then
        return nil
    end
    return getPlayerRole(player)
end

local function mm2TargetProvider(): any
    if not hasActiveRoundRoles() then
        return nil
    end
    local localRole: string? = getPlayerRole(LocalPlayer)
    local target: Player? = nil
    local source: string = "MM2 role priority"
    if localRole == "Sheriff" or localRole == "Hero" then
        target = findMurderer()
        source = "Sheriff priority · Murderer"
    elseif localRole == "Murderer" then
        target = findSheriff()
        source = target and "Murderer priority · Sheriff/Hero" or "Murderer priority"
        if not target then
            local redirected: Player? = state.mm2KnifeRuntime
                and state.mm2KnifeRuntime.redirectTarget
                or nil
            if redirected
                and isPlayerAlive(redirected)
                and not state.isProtectedTarget(redirected) then
                target = redirected
                source = "Knife lock"
            end
        end
        if not target then
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and isPlayerAlive(player)
                    and not state.isProtectedTarget(player) then
                    target = player
                    break
                end
            end
        end
    else
        target = findMurderer()
        source = "Threat priority · Murderer"
    end
    if state.mm2ShotFeedback then
        local pending: any = state.mm2ShotFeedback.pending
            or state.mm2ShotFeedback.lastAccepted
        local pendingRole: string? = pending and pending.target
            and getPlayerRole(pending.target)
            or nil
        local preservesRolePriority: boolean = localRole ~= "Sheriff"
            and localRole ~= "Hero"
            or pendingRole == "Murderer"
        local selectedRole: string? = target and getPlayerRole(target) or nil
        if localRole == "Murderer"
            and (selectedRole == "Sheriff" or selectedRole == "Hero") then
            preservesRolePriority = pendingRole == "Sheriff" or pendingRole == "Hero"
        end
        if pending
            and pending.target
            and isPlayerAlive(pending.target)
            and preservesRolePriority then
            target = pending.target
            source = "Recent shot target"
        end
    end
    if not target then
        return nil
    end
    local role: string? = getPlayerRole(target)
    return {
        player = target,
        role = role,
        source = source,
        accent = role == "Murderer"
            and Theme.Danger
            or ((role == "Sheriff" or role == "Hero")
                and Theme.AccentCyan
                or Theme.Success),
    }
end

state.gameRoleProvider = mm2RoleProvider
state.gameTargetProvider = mm2TargetProvider
moduleCleanup = function(): ()
    if state.gameRoleProvider == mm2RoleProvider then
        state.gameRoleProvider = nil
    end
    if state.gameTargetProvider == mm2TargetProvider then
        state.gameTargetProvider = nil
    end
end

local function uninstallShootRedirectHook(): ()
    local weaponService: any = weaponServiceModule
    local touchRestored: boolean = not shootTouchHookInstalled
    local mouseRestored: boolean = not shootHookInstalled
    if type(state.hookFunction) == "function" and type(weaponService) == "table" then
        if shootTouchHookInstalled
            and shootTouchHookOriginal
            and type(weaponService.GetTargetPosition) == "function" then
            local restored: boolean, displaced: any = pcall(
                state.hookFunction,
                weaponService.GetTargetPosition,
                shootTouchHookOriginal
            )
            touchRestored = restored and displaced == shootTouchHookWrapper
            if restored and not touchRestored and type(displaced) == "function" then
                pcall(state.hookFunction, weaponService.GetTargetPosition, displaced)
            end
        end
        if shootHookInstalled
            and shootHookOriginal
            and type(weaponService.GetMouseTargetCFrame) == "function" then
            local restored: boolean, displaced: any = pcall(
                state.hookFunction,
                weaponService.GetMouseTargetCFrame,
                shootHookOriginal
            )
            mouseRestored = restored and displaced == shootHookWrapper
            if restored and not mouseRestored and type(displaced) == "function" then
                pcall(state.hookFunction, weaponService.GetMouseTargetCFrame, displaced)
            end
        end
    end
    if touchRestored then
        shootTouchHookInstalled = false
        shootTouchHookOriginal = nil
        shootTouchHookWrapper = nil
    end
    if mouseRestored then
        shootHookInstalled = false
        shootHookOriginal = nil
        shootHookWrapper = nil
    end
    disconnectFeatureConnection("MM2GunFired")
    state.mm2ShotFeedback.gunFiredConnected = false
end
local function processKnifeAura(): ()
    local knife: Tool?, localRoot: BasePart? = canUseEquippedKnife()
    if not knife or not localRoot then
        if not knifeSettings.redirect then
            clearKnifeAuraVisuals()
        end
        return
    end

    local target: Player? =
        findKnifeAuraTarget(localRoot, knifeSettings.auraRange)
    local targetCharacter: Model? = target and target.Character
    local targetRoot: BasePart? = targetCharacter
        and targetCharacter:FindFirstChild("HumanoidRootPart")
        :: BasePart?
    if not target
        or not targetCharacter
        or not targetRoot
        or (targetRoot.Position - localRoot.Position).Magnitude
            > knifeSettings.auraRange
        or os.clock() - state.mm2KnifeRuntime.lastAuraSwing < 0.86 then
        return
    end

    local handle: BasePart? = knife:FindFirstChild("Handle") :: BasePart?
    if not handle or not handle:IsA("BasePart") then
        return
    end

    state.mm2KnifeRuntime.lastAuraSwing = os.clock()
    local events: Instance? = knife:FindFirstChild("Events")
    local handleTouched: Instance? = events
        and events:FindFirstChild("HandleTouched")
    knife:Activate()
    task.delay(0.025, function(): ()
        local currentKnife: Tool?, currentLocalRoot: BasePart? =
            canUseEquippedKnife()
        local currentCharacter: Model? = target.Character
        local currentRoot: BasePart? = currentCharacter
            and currentCharacter:FindFirstChild("HumanoidRootPart")
            :: BasePart?
        local currentHandle: BasePart? =
            knife:FindFirstChild("Handle") :: BasePart?
        if not knifeSettings.aura
            or currentKnife ~= knife
            or not currentLocalRoot
            or not currentCharacter
            or not currentRoot
            or not currentHandle
            or not currentHandle:IsA("BasePart")
            or (currentRoot.Position - currentLocalRoot.Position).Magnitude
                > knifeSettings.auraRange then
            return
        end

        -- Restore the game's normal stab payload. Aura only expands the local
        -- acquisition distance; it never substitutes a predicted body part,
        -- moves either character, or alters the thrown-knife CFrame.
        if handleTouched and handleTouched:IsA("RemoteEvent") then
            handleTouched:FireServer(currentRoot)
        elseif type(state.fireTouchInterest) == "function" then
            pcall(state.fireTouchInterest, currentHandle, currentRoot, 0)
            pcall(state.fireTouchInterest, currentHandle, currentRoot, 1)
        end
    end)
end

local function refreshKnifeController(): ()
    disconnectFeatureConnection("MM2KnifeVirtualHitbox")
    disconnectFeatureConnection("MM2KnifeAura")
    disconnectFeatureConnection("MM2KnifeController")
    if not knifeSettings.redirect and not knifeSettings.aura then
        state.mm2KnifeRuntime.redirectTarget = nil
        state.mm2KnifeRuntime.redirectScore = math.huge
        state.mm2KnifeRuntime.redirectLockedAt = 0
        state.mm2KnifeRuntime.velocityTarget = nil
        state.mm2KnifeRuntime.velocity = Vector3.zero
        state.mm2KnifeRuntime.velocitySampleAt = 0
        clearKnifeAuraVisuals()
        return
    end

    local elapsed: number = 0
    featureConnections.MM2KnifeController =
        TaskManager:Connect(function(deltaTime: number): ()
            elapsed += deltaTime
            if elapsed < 0.05 then
                return
            end
            elapsed %= 0.05

            local knife: Tool? = canUseEquippedKnife()
            if not knife then
                state.mm2KnifeRuntime.redirectTarget = nil
                state.mm2KnifeRuntime.redirectScore = math.huge
                state.mm2KnifeRuntime.redirectLockedAt = 0
                state.mm2KnifeRuntime.velocityTarget = nil
                clearKnifeAuraVisuals()
                return
            end
            if knifeSettings.redirect then
                getKnifeProjectileSpeed(knife)
                if not redirectedKnifeCFrame(true) then
                    clearKnifeAuraVisuals()
                end
            end
            if knifeSettings.aura then
                processKnifeAura()
                if not knifeSettings.redirect then
                    clearKnifeAuraVisuals()
                end
            elseif not knifeSettings.redirect then
                clearKnifeAuraVisuals()
            end
        end)
end

local function toggleKnifeRedirect(enabled: boolean): ()
    knifeSettings.redirect = enabled
    if enabled and not installShootRedirectHook() then
        notify("Knife Redirect is unavailable in this executor.")
    end
    if not enabled then
        state.mm2KnifeRuntime.redirectTarget = nil
        state.mm2KnifeRuntime.redirectScore = math.huge
        state.mm2KnifeRuntime.redirectLockedAt = 0
        state.mm2KnifeRuntime.velocityTarget = nil
        state.mm2KnifeRuntime.velocity = Vector3.zero
        state.mm2KnifeRuntime.velocitySampleAt = 0
    end
    refreshKnifeController()
    if not enabled and not shootFeatureActive then
        uninstallShootRedirectHook()
    end
end

local function toggleKnifeAura(enabled: boolean): ()
    knifeSettings.aura = enabled
    state.mm2KnifeRuntime.lastAuraSwing = -math.huge
    if enabled and not knifeSettings.redirect then
        clearKnifeAuraVisuals()
    end
    refreshKnifeController()
end

local function triggerManualShot(): ()
    local _, humanoid: Humanoid? = getCharacterParts()
    local backpack: Backpack? = LocalPlayer:FindFirstChildOfClass("Backpack")
    local gun: Tool? = getPlayerWeapon(LocalPlayer, "Gun")
    local touchPreferred: boolean =
        UserInputService.PreferredInput == Enum.PreferredInput.Touch
    local activationHookReady: boolean = shootHookInstalled
        and (not touchPreferred or shootTouchHookInstalled)

    if gun
        and humanoid
        and humanoid:IsA("Humanoid")
        and activationHookReady then
        if gun.Parent == backpack then
            humanoid:EquipTool(gun)
            task.wait()
        end
        gun:Activate()
    else
        shootMurderer()
    end
end
local function toggleShootMurderer(enabled: boolean): ()
    disconnectFeatureConnection("MM2ShootKey")
    disconnectFeatureConnection("MM2MotionTracker")
    shootFeatureActive = enabled

    if not enabled then
        state.mm2ShotFeedback.pending = nil
        state.mm2ShotFeedback.lastAccepted = nil
        state.mm2ShotFeedback.hide()
        if not knifeSettings.redirect then
            uninstallShootRedirectHook()
        end
        return
    end

    installShootRedirectHook()
    local motionElapsed: number = 0
    featureConnections.MM2MotionTracker = TaskManager:Connect(function(
        deltaTime: number
    ): ()
        motionElapsed += deltaTime
        if motionElapsed < 1 / 30 then
            return
        end
        motionElapsed = 0

        for _, player: Player in ipairs(Players:GetPlayers()) do
            local root: BasePart? = player.Character
                and player.Character:FindFirstChild("HumanoidRootPart")
                :: BasePart?
            if root and isPlayerAlive(player) then
                getFilteredVelocity(player, root)
            end
        end
    end)

    featureConnections.MM2ShootKey = UserInputService.InputBegan:Connect(function(
        input,
        processed
    )
        if not processed
            and not state.keyCaptureCallback
            and not state.waitingForKey
            and not UserInputService:GetFocusedTextBox()
            and (mm2Settings.shootMode == "Manual"
                or mm2Settings.shootMode == "Custom")
            and input.KeyCode == mm2Settings.shootKey then
            triggerManualShot()
        end
    end)
end

local function teleportToMap()
    local map = findMM2Map()
    local spawns = map and map:FindFirstChild("Spawns")
    local character = LocalPlayer.Character
    if not spawns or not character then
        notify("No active MM2 map was found.")
        return
    end

    local spawnList = spawns:GetChildren()
    local target = spawnList[math.random(1, math.max(1, #spawnList))]
    if target and target:IsA("BasePart") then
        character:PivotTo(target.CFrame + Vector3.new(0, 3, 0))
    end
end

local function teleportToLobby()
    local lobby = workspace:FindFirstChild("Lobby")
    local spawns = lobby and lobby:FindFirstChild("Spawns")
    local spawn = spawns and spawns:FindFirstChildWhichIsA("SpawnLocation")
    local character = LocalPlayer.Character
    if spawn and character then
        character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
    else
        notify("The MM2 lobby spawn was not found.")
    end
end

local function teleportToDroppedGun()
    local gunDrop = findDroppedGun()
    local character = LocalPlayer.Character
    if gunDrop and character then
        local savedCFrame = character:GetPivot()
        character:PivotTo(gunDrop:GetPivot() + Vector3.new(0, 2, 0))
        task.wait(mm2Settings.autoGetGunDelay)
        if character.Parent then
            character:PivotTo(savedCFrame)
        end
    else
        notify("No dropped gun was found.")
    end
end

local _InstantRolesFeature = createUniversalFeature(
    "Instant Role Notify",
    "Notify roles once at the beginning of each round",
    1,
    toggleInstantRoleNotify,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

local RoleEspFeature = createUniversalFeature(
    "Player ESP",
    "Role highlights, coins, and traps",
    2,
    toggleRoleEsp,
    {
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addToggleOption(RoleEspFeature, "Innocent ESP", false, toggleInnocentEsp)
addColorOption(RoleEspFeature, "Innocent ESP color", mm2Settings.innocentColor, function(value)
    mm2Settings.innocentColor = value
end)
addNumberOption(RoleEspFeature, "Innocent transparency", 6.2, 0, 10, function(value)
    mm2Settings.innocentTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addColorOption(RoleEspFeature, "Dead ESP color", mm2Settings.deadColor, function(value)
    mm2Settings.deadColor = value
end)
addNumberOption(RoleEspFeature, "Dead transparency", 5.8, 0, 10, function(value)
    mm2Settings.deadTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addToggleOption(RoleEspFeature, "Murderer ESP", false, toggleMurdererEsp)
addColorOption(RoleEspFeature, "Murderer color", mm2Settings.murdererColor, function(value)
    mm2Settings.murdererColor = value
end)
addNumberOption(RoleEspFeature, "Murderer transparency", 5.5, 0, 10, function(value)
    mm2Settings.murdererTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addToggleOption(RoleEspFeature, "Sheriff ESP", false, toggleSheriffEsp)
addColorOption(RoleEspFeature, "Sheriff color", mm2Settings.sheriffColor, function(value)
    mm2Settings.sheriffColor = value
end)
addNumberOption(RoleEspFeature, "Sheriff transparency", 5.5, 0, 10, function(value)
    mm2Settings.sheriffTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addColorOption(RoleEspFeature, "Hero color", mm2Settings.heroColor, function(value)
    mm2Settings.heroColor = value
end)
addNumberOption(RoleEspFeature, "Hero transparency", 5.5, 0, 10, function(value)
    mm2Settings.heroTransparency = value / 10
    if mm2Settings.roleEspAll then
        rebuildRoleEsp()
    end
end)
addToggleOption(RoleEspFeature, "Coin Chams", false, toggleCoinChams)
addColorOption(RoleEspFeature, "Coin color", mm2Settings.coinColor, function(value)
    mm2Settings.coinColor = value
    if coinChamsEnabled then
        toggleCoinChams(true)
    end
end)
addNumberOption(RoleEspFeature, "Coin transparency", 8, 0, 10, function(value)
    mm2Settings.coinTransparency = value / 10
    if coinChamsEnabled then
        toggleCoinChams(true)
    end
end)
addToggleOption(RoleEspFeature, "Trap ESP", false, toggleTrapEsp)
addColorOption(RoleEspFeature, "Trap color", mm2Settings.trapColor, function(value)
    mm2Settings.trapColor = value
end)
addNumberOption(RoleEspFeature, "Trap transparency", 7, 0, 10, function(value)
    mm2Settings.trapTransparency = value / 10
end)

local GunVisualsFeature = createUniversalFeature(
    "Gun Visuals",
    "Highlight the dropped sheriff gun",
    3,
    toggleGunEsp,
    {
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addColorOption(GunVisualsFeature, "Gun color", mm2Settings.gunColor, function(value)
    mm2Settings.gunColor = value
end)
addNumberOption(GunVisualsFeature, "Gun transparency", 5, 0, 10, function(value)
    mm2Settings.gunTransparency = value / 10
end)

local ShootFeature = createUniversalFeature(
    "Shoot",
    "Hitscan aim with filtered motion, RTT compensation, and miss feedback",
    4,
    toggleShootMurderer,
    {
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
local ShootKeyButton
local ShootTargetBox
local function refreshShootOptions(): ()
    if ShootKeyButton then
        setOptionVisible(
            ShootFeature,
            ShootKeyButton.Parent :: GuiObject,
            mm2Settings.shootMode == "Manual"
                or mm2Settings.shootMode == "Custom"
        )
    end
    if ShootTargetBox then
        setOptionVisible(
            ShootFeature,
            ShootTargetBox.Parent :: GuiObject,
            mm2Settings.shootMode == "Custom"
        )
    end
end
addCycleOption(
    ShootFeature,
    "Mode",
    {"Manual", "Redirect", "Custom"},
    1,
    function(value: string): ()
        mm2Settings.shootMode = value
        if shootFeatureActive
            and value == "Redirect"
            and not installShootRedirectHook() then
            notify("Shoot Redirect is unavailable; Manual mode still works.")
        end
        refreshShootOptions()
    end
)
ShootKeyButton = addKeyOption(
    ShootFeature,
    "Manual key",
    mm2Settings.shootKey,
    function(value: Enum.KeyCode): ()
        mm2Settings.shootKey = value
    end
)
if state.bindMobileActionPlacement then
    state.bindMobileActionPlacement(
        ShootKeyButton,
        "MM2ManualShoot",
        "SHOOT",
        triggerManualShot
    )
end
ShootTargetBox = addTextOption(ShootFeature, "Target player", "", function(
    value: string
): ()
    mm2Settings.shootTarget = value
end, false)
addToggleOption(
    ShootFeature,
    "Miss cooldown",
    mm2Settings.showMissCooldown,
    function(value: boolean): ()
        mm2Settings.showMissCooldown = value
        if not value then
            state.mm2ShotFeedback.pending = nil
            state.mm2ShotFeedback.lastAccepted = nil
            state.mm2ShotFeedback.hide()
        end
    end
)
refreshShootOptions()

local TrajectoryFeature: any = createUniversalFeature(
    "Trajectory Calibration",
    "MM2-only target motion, jump, ping, endpoint and knife-flight analytics",
    5,
    function(): () end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addActionOption(TrajectoryFeature, "Show learned profile", function(): ()
    notify(trajectoryCalibration:status())
end)
addActionOption(TrajectoryFeature, "Save calibration", function(): ()
    if trajectoryCalibration:save("manual") then
        notify("Trajectory calibration saved in the executor workspace.")
    else
        notify("Trajectory calibration could not be saved; check F9.")
    end
end)
addActionOption(TrajectoryFeature, "Reset calibration", function(): ()
    trajectoryCalibration:reset()
    notify("Trajectory calibration was reset.")
end)
addInformationOption(
    TrajectoryFeature,
    "Schema 2 records 30 Hz target windows only around your shots/throws. It stays isolated from Universal analytics and never changes weapon arguments."
)

local KnifeFeature = createUniversalFeature(
    "Knife",
    "Normal projectile redirect and extended native stab detection",
    6,
    function(): () end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addToggleOption(KnifeFeature, "Redirect", false, toggleKnifeRedirect)
addToggleOption(KnifeFeature, "Knife Aura", false, toggleKnifeAura)
addNumberOption(KnifeFeature, "Aura detection range", 14, 7, 30, function(
    value: number
): ()
    knifeSettings.auraRange = value
end)
addToggleOption(KnifeFeature, "Target closest to mouse", true, function(
    value: boolean
): ()
    knifeSettings.targetClosestToMouse = value
    state.mm2KnifeRuntime.redirectTarget = nil
    state.mm2KnifeRuntime.redirectScore = math.huge
    state.mm2KnifeRuntime.redirectLockedAt = 0
    state.mm2KnifeRuntime.velocityTarget = nil
end)
addToggleOption(KnifeFeature, "Prediction envelope", true, function(
    value: boolean
): ()
    knifeSettings.showTarget = value
    if not value then
        clearKnifeAuraVisuals()
    end
end)

createUniversalFeature(
    "Loop All Interact",
    "Continuously activate prompts and click detectors",
    7,
    toggleLoopAllInteract,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

local SilenceFeature = createUniversalFeature(
    "Silence",
    "Radio and trap audio controls",
    8,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addToggleOption(SilenceFeature, "Other radios", false, toggleMuteOtherRadios)
addToggleOption(SilenceFeature, "Trap sounds", false, toggleMuteTrapSounds)

local AutoPlayFeature = createUniversalFeature(
    "Auto Play ID",
    "Loop a local Roblox audio asset",
    9,
    toggleAutoPlayId,
    {
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

createUniversalFeature(
    "Sprint",
    "Hold LeftControl while moving for 30 speed and a yellow trail",
    10,
    toggleSprint,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

local FpsFeature = createUniversalFeature(
    "Improve FPS",
    "Apply only the selected reversible optimizations",
    11,
    toggleImproveFps,
    {
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addToggleOption(FpsFeature, "Remove textures", true, function(value)
    fpsSettings.textures = value
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end)
addToggleOption(FpsFeature, "Disable particles", true, function(value)
    fpsSettings.particles = value
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end)
addToggleOption(FpsFeature, "Disable shadows", true, function(value)
    fpsSettings.shadows = value
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end)
addToggleOption(FpsFeature, "Simple materials", false, function(value)
    fpsSettings.materials = value
    if fpsModeEnabled then
        toggleImproveFps(true)
    end
end)
createUniversalFeature(
    "Always Show Timer",
    "Show the RoundStart timer above the coin bag",
    13,
    toggleAlwaysShowTimer,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

local TeleportFeature = createUniversalFeature(
    "Teleport",
    "Map, lobby, and temporary gun pickup",
    14,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addActionOption(TeleportFeature, "Teleport to Map", teleportToMap)
addActionOption(TeleportFeature, "Teleport to Lobby", teleportToLobby)
addActionOption(TeleportFeature, "Get Gun", teleportToDroppedGun)
local GetGunKeyButton: TextButton = addKeyOption(
    TeleportFeature,
    "Get Gun key",
    mm2Settings.getGunKey,
    function(value: Enum.KeyCode): ()
        mm2Settings.getGunKey = value
    end
)
if state.bindMobileActionPlacement then
    state.bindMobileActionPlacement(
        GetGunKeyButton,
        "MM2GetGun",
        "GUN",
        teleportToDroppedGun
    )
end
featureConnections.MM2GetGunKey = UserInputService.InputBegan:Connect(
    function(input, gameProcessed)
        if gameProcessed
            or state.keyCaptureCallback
            or state.waitingForKey
            or UserInputService:GetFocusedTextBox() then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == mm2Settings.getGunKey then
            task.spawn(teleportToDroppedGun)
        end
    end
)
addToggleOption(TeleportFeature, "Auto Get Gun", false, toggleAutoGetGun)
addNumberOption(
    TeleportFeature,
    "Gun pickup delay",
    mm2Settings.autoGetGunDelay,
    0.05,
    2,
    function(value)
        mm2Settings.autoGetGunDelay = value
    end
)

local FlingGroup = createUniversalFeature(
    "Fling",
    "Role-based fling actions",
    15,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addActionOption(FlingGroup, "Fling Murderer", function()
    local target = findMurderer()
    if target then
        performFling(target)
    else
        notify("No murderer was found.")
    end
end)
addActionOption(FlingGroup, "Fling Sheriff", function()
    local target = findSheriff()
    if target then
        performFling(target)
    else
        notify("No sheriff or hero was found.")
    end
end)
addActionOption(FlingGroup, "Fling All Innocents", function()
    task.spawn(function()
        for key, data in pairs(mm2RoundData) do
            if type(data) == "table" and data.Role == "Innocent" then
                local target = playerFromRoundKey(key, data)
                if target and target ~= LocalPlayer then
                    performFling(target)
                    repeat
                        task.wait(0.05)
                    until not flingRunning
                end
            end
        end
    end)
end)

local FriendFeature = createUniversalFeature(
    "FriendList",
    "Protect listed players from targeting and damage helpers",
    16,
    function() end,
    {
        category = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)
addTextOption(FriendFeature, "Protected names", "", function(value)
    friendSettings.names = {}
    for name in string.gmatch(string.lower(value), "[^,%s]+") do
        friendSettings.names[name] = true
    end
end)
addToggleOption(FriendFeature, "Protect Roblox friends", true, function(value)
    friendSettings.protectRobloxFriends = value
    task.spawn(refreshFriendProtection)
end)
addInformationOption(
    FriendFeature,
    "Separate names with commas. Shoot, Knife Aura and Fling will ignore them."
)

local hiddenNameLabels = setmetatable({}, {__mode = "k"})
local function toggleHideNames(enabled)
    disconnectFeatureConnection("MM2HideNames")
    if not enabled then
        for label, originalText in pairs(hiddenNameLabels) do
            if label and label.Parent and label.Text == "Anon" then
                label.Text = originalText
            end
        end
        hiddenNameLabels = setmetatable({}, {__mode = "k"})
        return
    end

    local elapsed = 1
    featureConnections.MM2HideNames = TaskManager:Connect(function(deltaTime)
        elapsed = elapsed + deltaTime
        if elapsed < 0.25 then
            return
        end
        elapsed = 0

        local names = {}
        for _, player in ipairs(Players:GetPlayers()) do
            names[player.Name] = true
            names[player.DisplayName] = true
            names["@" .. player.Name] = true
            names[player.DisplayName .. " (@" .. player.Name .. ")"] = true
        end
        local roots = {}
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            table.insert(roots, playerGui)
        end
        pcall(function()
            local robloxGui = game:GetService("CoreGui"):FindFirstChild("RobloxGui")
            local playerList = robloxGui
                and robloxGui:FindFirstChild("PlayerList", true)
            if playerList then
                table.insert(roots, playerList)
            end
        end)

        for _, root in ipairs(roots) do
            for _, object in ipairs(root:GetDescendants()) do
                if (object:IsA("TextLabel") or object:IsA("TextButton"))
                    and names[object.Text] then
                    if hiddenNameLabels[object] == nil then
                        hiddenNameLabels[object] = object.Text
                    end
                    object.Text = "Anon"
                end
            end
        end
    end)
end

createUniversalFeature(
    "Hide Names",
    "Replace player names in local UI and leaderboards with Anon",
    18,
    toggleHideNames,
    {
        noOptions = true,
        parent = MM2Scroll,
        registry = mm2Features,
    }
)

cleanupMM2Runtime = function()
    if state.gameRoleProvider == mm2RoleProvider then
        state.gameRoleProvider = nil
    end
    if state.gameTargetProvider == mm2TargetProvider then
        state.gameTargetProvider = nil
    end
    trajectoryCalibration:destroy()
    toggleShootMurderer(false)
    state.mm2ShotFeedback.hide()
    toggleKnifeAura(false)
    toggleKnifeRedirect(false)
    uninstallShootRedirectHook()
    toggleRoleEsp(false)
    toggleGunEsp(false)
    toggleLoopAllInteract(false)
    toggleSprint(false)
    toggleHideNames(false)
    toggleAutoGetGun(false)
    toggleImproveFps(false)
    toggleAlwaysShowTimer(false)
    toggleCoinChams(false)
    toggleTrapEsp(false)
    toggleMuteOtherRadios(false)
    toggleMuteTrapSounds(false)
    for _, connectionName: string in ipairs({
        "MM2FriendPlayerAdded",
        "MM2PlayerDataChanged",
        "MM2TimerTrackerStart",
        "MM2TimerTrackerEnd",
        "MM2GetGunKey",
    }) do
        disconnectFeatureConnection(connectionName)
    end
    state.isProtectedTarget = function(player: Player?): boolean
        return player == nil or player == LocalPlayer
    end
    if AutoPlaySound then
        stopAutoPlaySound()
        AutoPlaySound:Destroy()
    end
end
end

function Module.init(runtime: any): any
    assert(type(runtime) == "table", "MM2 requires a Runtime table")
    assert(type(runtime.Menu) == "table", "MM2 requires Runtime.Menu")
    assert(runtime.TaskManager ~= nil, "MM2 requires Runtime.TaskManager")
    if Module.Initialized then
        return Module
    end

    Module.Menu = runtime.Menu
    Module.Runtime = runtime
    local success: boolean, buildError: any = pcall(buildMM2Features)
    if not success then
        moduleCleanup()
        error(buildError, 0)
    end
    local environment: any = getfenv()
    if type(environment.cleanupMM2Runtime) == "function" then
        moduleCleanup = environment.cleanupMM2Runtime
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
    moduleCleanup()
    Module.Events = {}
    Module.Menu = nil
    Module.Runtime = nil
end

return Module
