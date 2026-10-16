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
local host: any = getfenv()
local trajectoryLogPrefix: string = "[" .. tostring(host.PRODUCT.logPrefix)
    .. ":MM2:Trajectory]"
local MM2Effects = create("Folder", {
    Parent = ScreenGui,
    Name = "MM2Effects",
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
    end
end)

local mm2Settings = {
    autoGetGunDelay = 0.25,
    shootMode = "Manual",
    shootWallCheck = true,
    silentAim = false,
    shootKey = Enum.KeyCode.Q,
    shootTarget = "",
    showMissCooldown = false,
    predictionRtt = 0.08,
    gunLeadBias = 0,
    autoTuneLead = false,

    motionSampleHz = 60,
    silentSweep = 0.5,

    silentSpawn = "Through",
    getGunKey = Enum.KeyCode.G,
    instantRoleNotify = false,
    roleEspAll = false,

    roleEspRoundOnly = false,
    roleEspInnocent = false,
    roleEspMurderer = false,
    roleEspSheriff = false,

    innocentColor = Color3.fromRGB(0, 255, 8),
    innocentTransparency = 0.62,
    deadColor = Color3.fromRGB(170, 170, 180),
    deadTransparency = 0.72,
    murdererColor = Color3.fromRGB(255, 0, 4),
    murdererTransparency = 0.5,
    sheriffColor = Color3.fromRGB(0, 153, 255),
    sheriffTransparency = 0.5,
    heroColor = Color3.fromRGB(255, 196, 0),
    heroTransparency = 0.5,
    roleTagsAll = false,
    blurtDelay = 1.5,
    blurtRepeat = false,
    blurtFake = false,
    coinColor = Color3.fromRGB(230, 220, 65),
    coinTransparency = 0.8,
    trapColor = Color3.fromRGB(145, 25, 25),
    trapTransparency = 0.7,

    gunColor = Color3.fromRGB(255, 215, 0),
    gunTransparency = 0.55,
    autoPlayId = "",
}

local function isProtectedTarget(player: Player?): boolean
    local runtime: any = Module.Runtime
    local targets: any = runtime and runtime.Services and runtime.Services.protectedTargets
    return targets ~= nil and targets.isProtected(player) == true
end

local function clearEffects(folder)
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("ObjectValue") and child.Value then
            child.Value:Destroy()
        end
        child:Destroy()
    end
end

-- Match the recovered client's cursor filters, not an assertion about server rules.
local function isWeaponPathClear(origin: Vector3, endpoint: Vector3, target: Model?): boolean
    local direction: Vector3 = endpoint - origin
    if direction.Magnitude < 0.05 then return true end
    local excluded: {Instance} = {}
    if LocalPlayer.Character then table.insert(excluded, LocalPlayer.Character) end
    for _, object: Instance in ipairs(CollectionService:GetTagged("WeaponPassthrough")) do
        table.insert(excluded, object)
    end
    local params: RaycastParams = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    for _ = 1, 32 do
        params.FilterDescendantsInstances = excluded
        local hit: RaycastResult? = workspace:Raycast(origin, direction, params)
        if not hit then return true end
        if target and hit.Instance:IsDescendantOf(target) then return true end
        if hit.Instance:IsA("BasePart") and hit.Instance.Transparency == 1 then
            table.insert(excluded, hit.Instance)
        else
            return false
        end
    end
    return false -- bounded work, conservative if a map has many transparent layers
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

            if namedFromData and namedFromData:IsA("Player") then
                player = namedFromData :: Player
            end
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

local roundRolesListeners: {(boolean) -> ()} = {}
local publishedRoundRolesActive: boolean = false
local function emitRoundRoles(active: boolean): ()
    publishedRoundRolesActive = active
    for _, listener: (boolean) -> () in ipairs(roundRolesListeners) do
        pcall(listener, active)
    end
end
local function onRoundRoles(listener: (boolean) -> ()): () -> ()
    table.insert(roundRolesListeners, listener)

    task.defer(function(): ()
        if table.find(roundRolesListeners, listener) then
            pcall(listener, publishedRoundRolesActive)
        end
    end)
    return function(): ()
        local index: number? = table.find(roundRolesListeners, listener)
        if index then
            table.remove(roundRolesListeners, index)
        end
    end
end

local invalidateRoleCaches: () -> ()
local rebuildRoleIndex: () -> ()

local function requestRoleRefresh(force: boolean?): ()
    if not mm2RoleRemote
        or roleRefreshRunning
        or (not force and os.clock() - lastRoleRefreshAt < 0.8) then
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
            invalidateRoleCaches()
        end
    end)
end

local roleIndex: {
    roles: {[Player]: string?},
    murderer: Player?,
    sheriff: Player?,
    rolesKnown: boolean,
    gunHolders: {[Player]: boolean}?,
} = {roles = {}, murderer = nil, sheriff = nil, rolesKnown = false, gunHolders = {}}
local roleIndexDirty: boolean = true
local roleIndexAt: number = -math.huge
local roleIndexRefreshQueued: boolean = false
local roleWatchers: {[Player]: {RBXScriptConnection}} = {}

function invalidateRoleCaches(): ()
    roleIndexDirty = true

    if type(state.clearRoleMemo) == "function" then
        state.clearRoleMemo()
    end

    if roleIndexRefreshQueued then
        return
    end
    roleIndexRefreshQueued = true
    task.defer(function(): ()
        roleIndexRefreshQueued = false
        if roleIndexDirty and rebuildRoleIndex then
            rebuildRoleIndex()
        end
    end)
end

local function hasMurdererCollisionGroup(character: Model?): boolean
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

local function buildRoundRoleMap(): {[Player]: string}
    local map: {[Player]: string} = {}
    for key: any, data: any in pairs(mm2RoundData) do
        if type(data) == "table" then
            local role: any = data.Role
            if role == "Murderer"
                or role == "Sheriff"
                or role == "Hero"
                or role == "Innocent" then
                local player: Player? = playerFromRoundKey(key, data)
                if player then
                    map[player] = role
                end
            end
        end
    end
    return map
end

rebuildRoleIndex = function(): ()
    roleIndexDirty = false
    roleIndexAt = os.clock()

    local roles: {[Player]: string?} = {}
    local roundRoleByPlayer: {[Player]: string} = buildRoundRoleMap()
    local murderer: Player? = nil
    local sheriff: Player? = nil
    local alive: {[Player]: boolean} = {}
    local special: {[Player]: string} = {}
    local gunHolders: {[Player]: boolean} = {}

    for _, player: Player in ipairs(Players:GetPlayers()) do
        local character: Model? = player.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
        local isAlive: boolean = humanoid ~= nil and humanoid.Health > 0
        alive[player] = isAlive

        local roundRole: string? = roundRoleByPlayer[player]
        local resolved: string? = nil
        if hasMurdererCollisionGroup(character)
            or getPlayerWeapon(player, "Knife") then
            resolved = "Murderer"
        elseif getPlayerWeapon(player, "Gun") then
            gunHolders[player] = true
            -- The sheriff spawns WITH the gun; anyone else holding one
            -- mid-round picked it up after the sheriff died, which makes
            -- them the Hero. The round data can lag behind the pickup
            -- ("si alguien agarra la gun los nametags seguiran siendo de
            -- Inocente"), so possession decides until the data catches up.
            if roundRole == "Innocent" or roundRole == "Hero" then
                resolved = "Hero"
            else
                resolved = "Sheriff"
            end
        elseif roundRole and roundRole ~= "Innocent" then
            resolved = roundRole
        end

        if resolved then
            special[player] = resolved

            if resolved == "Murderer" then
                if not murderer or (isAlive and not alive[murderer]) then
                    murderer = player
                end
            elseif resolved == "Sheriff" or resolved == "Hero" then
                if not sheriff or (isAlive and not alive[sheriff]) then
                    sheriff = player
                end
            end
        end
    end

    local rolesKnown: boolean = next(special) ~= nil
    if roundLifecycleActive == false then
        rolesKnown = false
    end

    for _, player: Player in ipairs(Players:GetPlayers()) do
        local resolved: string? = special[player]
        if not resolved and rolesKnown then
            resolved = alive[player] and "Innocent" or "Dead"
        end
        roles[player] = resolved
    end

    local rolesChanged: boolean = roleIndex.rolesKnown ~= rolesKnown
        or roleIndex.murderer ~= murderer
        or roleIndex.sheriff ~= sheriff
    if not rolesChanged then
        for player: Player, role: string? in pairs(roles) do
            if roleIndex.roles[player] ~= role then
                rolesChanged = true
                break
            end
        end
    end
    if not rolesChanged then
        for player: Player in pairs(roleIndex.roles) do
            if roles[player] == nil and roleIndex.roles[player] ~= nil then
                rolesChanged = true
                break
            end
        end
    end

    roleIndex.roles = roles
    roleIndex.murderer = murderer
    roleIndex.sheriff = sheriff
    roleIndex.rolesKnown = rolesKnown

    -- A gun changing hands (sheriff died, someone picked it up) must
    -- re-sync the round data: the server knows the new Hero long before
    -- our cached copy does, and only a fresh remote read promotes the
    -- picker from "Innocent" and demotes the dead sheriff.
    local gunHoldersChanged: boolean = false
    do
        local previous: {[Player]: boolean} = roleIndex.gunHolders or {}
        for player in pairs(gunHolders) do
            if not previous[player] then
                gunHoldersChanged = true
            end
        end
        for player in pairs(previous) do
            if not gunHolders[player] then
                gunHoldersChanged = true
            end
        end
    end
    roleIndex.gunHolders = gunHolders
    if gunHoldersChanged and roundLifecycleActive ~= false then
        requestRoleRefresh()
    end

    if rolesChanged then

        if type(state.invalidateGameRoles) == "function" then
            state.invalidateGameRoles()
        elseif type(state.clearRoleMemo) == "function" then
            state.clearRoleMemo()
        end
        emitRoundRoles(rolesKnown)
    end

    if not rolesKnown and roundLifecycleActive ~= false then
        requestRoleRefresh()
    end
end

local function ensureRoleIndex(): ()

    if roleIndexDirty or os.clock() - roleIndexAt > 1 then
        rebuildRoleIndex()
    end
end

local function unwatchPlayer(player: Player): ()
    local connections: {RBXScriptConnection}? = roleWatchers[player]
    if not connections then
        return
    end
    roleWatchers[player] = nil
    for _, connection: RBXScriptConnection in ipairs(connections) do
        pcall(function(): ()
            connection:Disconnect()
        end)
    end
end

local function watchPlayer(player: Player): ()
    unwatchPlayer(player)
    local connections: {RBXScriptConnection} = {}
    local watchedTools: {[Tool]: boolean} = setmetatable({}, {__mode = "k"}) :: any

    local function watchTool(tool: Tool): ()
        if watchedTools[tool] then
            return
        end
        watchedTools[tool] = true

        table.insert(
            connections,
            tool.DescendantAdded:Connect(invalidateRoleCaches)
        )
        table.insert(
            connections,
            tool.DescendantRemoving:Connect(invalidateRoleCaches)
        )
    end

    local function watchContainer(container: Instance?): ()
        if not container then
            return
        end
        for _, child: Instance in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then
                watchTool(child)
            end
        end
        table.insert(
            connections,
            container.ChildAdded:Connect(function(child: Instance): ()
                if child:IsA("Tool") then
                    watchTool(child)
                end
                invalidateRoleCaches()
            end)
        )
        table.insert(connections, container.ChildRemoved:Connect(invalidateRoleCaches))
    end

    local function watchCharacter(character: Model): ()
        invalidateRoleCaches()
        watchContainer(character)

        local function watchCollisionPart(part: BasePart): ()
            table.insert(
                connections,
                part:GetPropertyChangedSignal("CollisionGroup")
                    :Connect(invalidateRoleCaches)
            )
        end
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("BasePart") then
                watchCollisionPart(child)
            end
        end
        table.insert(
            connections,
            character.ChildAdded:Connect(function(child: Instance): ()
                if child:IsA("BasePart") then
                    watchCollisionPart(child)
                end
            end)
        )

        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            table.insert(
                connections,
                humanoid.Died:Connect(invalidateRoleCaches)
            )
        end
    end

    table.insert(connections, player.CharacterAdded:Connect(watchCharacter))
    table.insert(connections, player.CharacterRemoving:Connect(invalidateRoleCaches))
    table.insert(
        connections,
        player.ChildAdded:Connect(function(child: Instance): ()
            if child:IsA("Backpack") then
                watchContainer(child)
                invalidateRoleCaches()
            end
        end)
    )
    watchContainer(player:FindFirstChildOfClass("Backpack"))
    if player.Character then
        watchCharacter(player.Character)
    end
    roleWatchers[player] = connections
end

for _, player: Player in ipairs(Players:GetPlayers()) do
    watchPlayer(player)
end
featureConnections.MM2RoleWatchAdded = Players.PlayerAdded:Connect(function(player: Player): ()
    watchPlayer(player)
    invalidateRoleCaches()
end)
featureConnections.MM2RoleWatchRemoving = Players.PlayerRemoving:Connect(function(player: Player): ()
    unwatchPlayer(player)
    invalidateRoleCaches()
end)
for _, weaponTag: string in ipairs({"Weapon_Knife", "Weapon_Gun"}) do
    featureConnections["MM2RoleTagAdded" .. weaponTag] = CollectionService
        :GetInstanceAddedSignal(weaponTag)
        :Connect(invalidateRoleCaches)
    featureConnections["MM2RoleTagRemoved" .. weaponTag] = CollectionService
        :GetInstanceRemovedSignal(weaponTag)
        :Connect(invalidateRoleCaches)
end

local function roundRolesKnown(): boolean
    ensureRoleIndex()
    return roleIndex.rolesKnown
end

local function getPlayerRole(player: Player): string?
    ensureRoleIndex()
    return roleIndex.roles[player]
end

local function findMM2Role(toolName: string, excludedPlayer: Player?): Player?
    ensureRoleIndex()
    local wanted: string = toolName == "Knife" and "Murderer" or "Sheriff"
    for player: Player, role: string? in pairs(roleIndex.roles) do
        if player ~= excludedPlayer
            and (role == wanted or (wanted == "Sheriff" and role == "Hero")) then
            return player
        end
    end
    return nil
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
    return roundRolesKnown()
end

local function findMurderer(): Player?
    ensureRoleIndex()
    return roleIndex.murderer or findPlayerByRoundRole("Murderer")
end

local function findSheriff(): Player?
    ensureRoleIndex()
    return roleIndex.sheriff
        or findPlayerByRoundRole("Sheriff")
        or findPlayerByRoundRole("Hero")
end

local MM2_MAP_COIN_CONTAINERS: {string} = {
    "CoinContainer",
    "CoinAreas",
    "Coins",
}

local LOBBY_MODEL_NAMES: {string} = {
    "Lobby",
    "MainLobby",
    "RegularLobby",
}

local function isLobbyName(name: string): boolean
    for _, candidate: string in ipairs(LOBBY_MODEL_NAMES) do
        if name == candidate then
            return true
        end
    end
    return false
end

local function isMM2MapModel(object: Instance): boolean
    if not object:IsA("Model") or isLobbyName(object.Name) then
        return false
    end
    for _, containerName: string in ipairs(MM2_MAP_COIN_CONTAINERS) do
        if object:FindFirstChild(containerName) then
            return true
        end
    end
    return false
end

local mm2MapCache: {map: Instance?, at: number} = {map = nil, at = -math.huge}

local function findMM2MapUncached(): Instance?
    for _, object: Instance in ipairs(workspace:GetChildren()) do
        if isMM2MapModel(object) then
            return object
        end
    end

    for _, object: Instance in ipairs(workspace:GetChildren()) do
        if object:IsA("Model")
            and not isLobbyName(object.Name)
            and object:FindFirstChild("Spawns") then
            return object
        end
    end
    return nil
end

local function findMM2Map(): Instance?
    local cached: Instance? = mm2MapCache.map
    if cached and cached.Parent == workspace then
        return cached
    end
    if os.clock() - mm2MapCache.at < 1 then
        return cached
    end
    mm2MapCache.at = os.clock()
    mm2MapCache.map = findMM2MapUncached()
    return mm2MapCache.map
end

local droppedGunCache: {gun: (Model | BasePart)?, at: number} =
    {gun = nil, at = -math.huge}
local lastGunSweepAt: number = -math.huge

local function isLooseGun(object: Instance): boolean
    if not object:IsA("Tool") then
        return false
    end
    if object.Name ~= "Gun" and not CollectionService:HasTag(object, "Weapon_Gun") then
        return false
    end

    return object:IsDescendantOf(workspace)
        and not object:FindFirstAncestorOfClass("Backpack")
        and (object.Parent == workspace or object.Parent == findMM2Map()
            or object.Parent ~= nil and not object.Parent:FindFirstChildOfClass("Humanoid"))
end

local function resolveGunPart(object: Instance): (Model | BasePart)?
    if object:IsA("Model") or object:IsA("BasePart") then
        return object :: any
    end
    local handle: Instance? = object:FindFirstChild("Handle")
        or object:FindFirstChildWhichIsA("BasePart")
    return (handle and handle:IsA("BasePart")) and handle or nil
end

local function findDroppedGunUncached(): (Model | BasePart)?
    local map: Instance? = findMM2Map()
    local candidate: Instance? = map and map:FindFirstChild("GunDrop")
    if not candidate then
        candidate = workspace:FindFirstChild("GunDrop")
    end
    if candidate and (candidate:IsA("Model") or candidate:IsA("BasePart")) then
        return candidate :: any
    end

    for _, object: Instance in ipairs(CollectionService:GetTagged("Weapon_Gun")) do
        if isLooseGun(object) then
            local part: (Model | BasePart)? = resolveGunPart(object)
            if part then
                return part
            end
        end
    end

    for _, object: Instance in ipairs(workspace:GetChildren()) do
        if isLooseGun(object) then
            local part: (Model | BasePart)? = resolveGunPart(object)
            if part then
                return part
            end
        end
    end

    if os.clock() - lastGunSweepAt < 3 then
        return nil
    end
    lastGunSweepAt = os.clock()
    local deepCandidate: Instance? = (map and map:FindFirstChild("GunDrop", true))
        or workspace:FindFirstChild("GunDrop", true)
    if deepCandidate
        and (deepCandidate:IsA("Model") or deepCandidate:IsA("BasePart")) then
        return deepCandidate :: any
    end
    for _, object: Instance in ipairs(workspace:GetDescendants()) do
        if isLooseGun(object) then
            local part: (Model | BasePart)? = resolveGunPart(object)
            if part then
                return part
            end
        end
    end
    return nil
end

local function findDroppedGun(): (Model | BasePart)?
    local cached: (Model | BasePart)? = droppedGunCache.gun
    if cached and cached.Parent and cached:IsDescendantOf(workspace) then
        return cached
    end
    if os.clock() - droppedGunCache.at < 0.4 then
        return nil
    end
    droppedGunCache.at = os.clock()
    droppedGunCache.gun = findDroppedGunUncached()
    return droppedGunCache.gun
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
        billboard.LightInfluence = 0
        billboard.MaxDistance = 1500
        billboard.Size = UDim2.fromOffset(150, 22)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.Parent = head

        local billboardReference = Instance.new("ObjectValue")
        billboardReference.Name = labelText .. "LabelReference"
        billboardReference.Value = billboard
        billboardReference.Parent = folder

        local text = Instance.new("TextLabel")
        text.BackgroundTransparency = 1
        text.BorderSizePixel = 0
        text.Font = Enum.Font.GothamBold
        text.Size = UDim2.fromScale(1, 1)
        text.Text = labelText
        text.TextColor3 = color
        text.TextSize = 14
        text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        text.TextStrokeTransparency = 0.3
        text.Parent = billboard
    end
end

local function createMM2Cham(folder, adornee, color, transparency)
    local highlight = Instance.new("Highlight")
    highlight.Name = "WurstCham"
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

local function getPlayerPerk(player: Player): string?
    local char: Model? = player.Character
    if char then
        local perkAttr: any = char:GetAttribute("Perk") or player:GetAttribute("Perk")
        if type(perkAttr) == "string" and perkAttr ~= "" then
            return perkAttr
        end
    end
    for key: any, data: any in pairs(mm2RoundData) do
        if playerFromRoundKey(key, data) == player and type(data) == "table" then
            local perk: any = data.Perk or data.EquippedPerk or data.perk
            if type(perk) == "string" and perk ~= "" then
                return perk
            end
        end
    end
    if char then
        if char:FindFirstChild("Trap") or (player:FindFirstChild("Backpack") and player.Backpack:FindFirstChild("Trap")) then
            return "Trap"
        end
        if char:FindFirstChild("FakeGun") or (player:FindFirstChild("Backpack") and player.Backpack:FindFirstChild("FakeGun")) then
            return "FakeGun"
        end
    end
    return nil
end

local function registerMM2Roles(): ()
    registerRoleProvider({
        Name = "MM2",
        Roles = {"Murderer", "Sheriff", "Hero", "Innocent", "Dead"},
        Colors = {
            Murderer = mm2Settings.murdererColor,
            Sheriff = mm2Settings.sheriffColor,
            Hero = mm2Settings.heroColor,
            Innocent = mm2Settings.innocentColor,
            Dead = mm2Settings.deadColor,
        },
        Get = function(player: Player): string?
            return getPlayerRole(player)
        end,
        GetPerk = function(player: Player): string?
            return getPlayerPerk(player)
        end,
        GetColor = function(roleName: string): Color3?
            if roleName == "Murderer" then return mm2Settings.murdererColor end
            if roleName == "Sheriff" then return mm2Settings.sheriffColor end
            if roleName == "Hero" then return mm2Settings.heroColor end
            if roleName == "Innocent" then return mm2Settings.innocentColor end
            if roleName == "Dead" then return mm2Settings.deadColor end
            return nil
        end,
        SetColor = function(roleName: string, colour: Color3): ()
            if roleName == "Murderer" then
                mm2Settings.murdererColor = colour
            elseif roleName == "Sheriff" then
                mm2Settings.sheriffColor = colour
            elseif roleName == "Hero" then
                mm2Settings.heroColor = colour
            elseif roleName == "Innocent" then
                mm2Settings.innocentColor = colour
            elseif roleName == "Dead" then
                mm2Settings.deadColor = colour
            end
        end,
    })
end

if mm2GameplayRemotes then
    local playerDataChanged = mm2GameplayRemotes:FindFirstChild("PlayerDataChanged")
    if playerDataChanged and playerDataChanged:IsA("RemoteEvent") then
        featureConnections.MM2PlayerDataChanged = playerDataChanged.OnClientEvent:Connect(function(newData)
            invalidateRoleCaches()
            if type(newData) ~= "table" or roundLifecycleActive == false then
                mm2RoundData = {}
            else

                for key: any, value: any in pairs(newData) do
                    mm2RoundData[key] = value
                end
                lastRoleRefreshAt = os.clock()
            end

        end)
    end
end

local primeRoundState: () -> ()
local setRoundPhase: (string, string) -> ()
local lastPhase: string = "unknown"

local roundTimer: {endsAt: number?} = {endsAt = nil}
local timerRemotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
local timerGameplay = timerRemotes and timerRemotes:FindFirstChild("Gameplay")
local timerRoundStart = timerGameplay and timerGameplay:FindFirstChild("RoundStart")
local timerRoundEnd = timerGameplay and timerGameplay:FindFirstChild("RoundEndFade")
local sessionRoundActive = false

if timerRoundStart and timerRoundStart:IsA("RemoteEvent") then
    featureConnections.MM2TimerTrackerStart = timerRoundStart.OnClientEvent:Connect(
        function(duration)
            duration = tonumber(duration)
            roundTimer.endsAt = duration and os.clock() + duration or nil
            mm2RoundData = {}
            invalidateRoleCaches()
            roundLifecycleActive = duration ~= nil and duration > 0
            if not duration or duration <= 0 then
                sessionRoundActive = false
            end
            roleRefreshGeneration += 1
            if duration and duration > 0 then

                primeRoundState()
                lastPhase = "map"
                setRoundPhase("map", "RoundStart")
            end
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
        roundTimer.endsAt = nil
        sessionRoundActive = false
        roundLifecycleActive = false
        invalidateRoleCaches()
        roleRefreshGeneration += 1
        mm2RoundData = {}
        setRoundPhase("lobby", "RoundEndFade")
    end)
end

local roundPhase: string = "unknown"
local roundPhaseListeners: {(string, string) -> ()} = {}

local function emitRoundPhase(phase: string, reason: string): ()
    for _, listener: (string, string) -> () in ipairs(roundPhaseListeners) do
        pcall(listener, phase, reason)
    end
end

setRoundPhase = function(phase: string, reason: string): ()
    if roundPhase == phase then
        return
    end
    roundPhase = phase
    emitRoundPhase(phase, reason)
end

local function onRoundPhase(listener: (string, string) -> ()): () -> ()
    table.insert(roundPhaseListeners, listener)
    task.defer(function(): ()
        if table.find(roundPhaseListeners, listener) then
            pcall(listener, roundPhase, "subscribe")
        end
    end)
    return function(): ()
        local index: number? = table.find(roundPhaseListeners, listener)
        if index then
            table.remove(roundPhaseListeners, index)
        end
    end
end

local function findLobbyModel(): Instance?
    for _, object: Instance in ipairs(workspace:GetChildren()) do
        if isLobbyName(object.Name) then
            return object
        end
    end
    return nil
end

local function detectRoundPhase(): string
    local character: Model? = LocalPlayer.Character
    if not character then
        return "lobby"
    end
    local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then
        return "lobby"
    end

    local lobby: Instance? = findLobbyModel()
    if lobby and root:IsDescendantOf(lobby) then
        return "lobby"
    end
    if findMM2Map() then
        return "map"
    end

    return roundPhase == "map" and "map" or "lobby"
end

primeRoundState = function(): ()
    roleRefreshGeneration += 1
    local generation: number = roleRefreshGeneration
    requestRoleRefresh(true)
    task.spawn(function(): ()

        for _, delay: number in ipairs({0.2, 0.6}) do
            task.wait(delay)
            if generation ~= roleRefreshGeneration or roundRolesKnown() then
                break
            end
            requestRoleRefresh(true)
        end
    end)
end

local phaseElapsed: number = 0
lastPhase = detectRoundPhase()
featureConnections.MM2RoundPhase = TaskManager:Connect(function(deltaTime: number): ()
    phaseElapsed += deltaTime
    if phaseElapsed < 0.2 then
        return
    end
    phaseElapsed = 0
    local phase: string = detectRoundPhase()
    if phase == lastPhase then
        return
    end
    lastPhase = phase
    if phase == "map" then

        mm2RoundData = {}
        roundLifecycleActive = true
        invalidateRoleCaches()
        primeRoundState("map")
        setRoundPhase("map", "teleport")
    else
        mm2RoundData = {}
        roundLifecycleActive = false
        roundTimer.endsAt = nil
        invalidateRoleCaches()
        roleRefreshGeneration += 1
        setRoundPhase("lobby", "teleport")
    end
end)
setRoundPhase(lastPhase, "boot")

local roundTimerPartCache: {part: Instance?, at: number} =
    {part = nil, at = -math.huge}

local function findRoundTimerPart(): Instance?
    local cached: Instance? = roundTimerPartCache.part
    if cached and cached.Parent then
        return cached
    end
    if os.clock() - roundTimerPartCache.at < 1 then
        return cached
    end
    roundTimerPartCache.at = os.clock()
    local found: Instance? = workspace:FindFirstChild("RoundTimerPart")
    roundTimerPartCache.part = found
    return found
end

local function readRoundTimerPartSeconds(): number?
    local part: Instance? = findRoundTimerPart()
    if not part then
        return nil
    end
    local remaining: number? = tonumber(part:GetAttribute("Time") :: any)
    if not remaining or remaining <= 0 or remaining > 600 then
        return nil
    end
    return remaining
end

local hudTimerCache: {frame: Instance?, label: Instance?, at: number} =
    {frame = nil, label = nil, at = -math.huge}

local function findHudTimerLabel(): Instance?
    local cached: Instance? = hudTimerCache.label
    if cached and cached.Parent then
        return cached
    end
    if os.clock() - hudTimerCache.at < 1 then
        return cached
    end
    hudTimerCache.at = os.clock()
    local playerGui: PlayerGui? = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local mainGui: Instance? = playerGui and playerGui:FindFirstChild("MainGUI")
    local gameFrame: Instance? = mainGui and mainGui:FindFirstChild("Game")
    local frame: Instance? = gameFrame and gameFrame:FindFirstChild("Timer")

    if not frame then
        frame = mainGui and mainGui:FindFirstChild("Timer", true)
    end
    hudTimerCache.frame = (frame and frame:IsA("GuiObject")) and frame or nil

    local label: Instance? = frame
        and (frame:FindFirstChild("XPText")
            or frame:FindFirstChild("Timer")
            or frame:FindFirstChildWhichIsA("TextLabel", true))
    hudTimerCache.label = (label and label:IsA("TextLabel")) and label or nil
    return hudTimerCache.label
end

local function parseHudTimerSeconds(text: string?): number?
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local minutes: string?, seconds: string? = text:match("^%s*(%d+):(%d%d)s?%s*$")
    if minutes and seconds then
        return tonumber(minutes) * 60 + tonumber(seconds)
    end
    local whole: string? = text:match("^%s*(%d%d?)s?%s*$")
    if whole then
        return tonumber(whole)
    end
    return nil
end

local function isHudTimerVisible(label: Instance): boolean

    local ancestor: Instance? = label
    while ancestor do
        if ancestor:IsA("GuiObject") and ancestor.Visible == false then
            return false
        end
        ancestor = ancestor.Parent
    end
    return true
end

local function readHudTimerSeconds(): number?
    local label: Instance? = findHudTimerLabel()
    if not label then
        return nil
    end
    if not isHudTimerVisible(label) then
        return nil
    end
    local remaining: number? = parseHudTimerSeconds((label :: any).Text)
    if not remaining or remaining <= 0 or remaining > 600 then
        return nil
    end
    return remaining
end

local lastAttributeRemaining: number? = nil
local lastAttributeChangeAt: number = -math.huge
local clockElapsed: number = 0
featureConnections.MM2RoundClock = TaskManager:Connect(function(deltaTime: number): ()
    clockElapsed += deltaTime
    if clockElapsed < 0.25 then
        return
    end
    clockElapsed = 0
    local remaining: number? = readRoundTimerPartSeconds()
        or readHudTimerSeconds()
    if not remaining or roundPhase == "lobby" then

        lastAttributeRemaining = nil
        return
    end

    if lastAttributeRemaining == nil
        or math.abs(remaining - lastAttributeRemaining) > 0.01 then
        lastAttributeChangeAt = os.clock()
    end
    lastAttributeRemaining = remaining
    if os.clock() - lastAttributeChangeAt > 3 then
        return
    end
    roundTimer.endsAt = os.clock() + remaining
    if roundLifecycleActive == nil then
        roundLifecycleActive = true
    end
end)

requestRoleRefresh(true)

-- Pure prediction helpers: shared by Shoot/Knife and exercised without Roblox.
local predictionMath = {}
function predictionMath.finite(value: any): boolean
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function predictionMath.sampleDue(elapsed: number, deltaTime: number, hz: number): (boolean, number)
    local interval: number = 1 / math.clamp(hz, 1, 120)
    local total: number = elapsed + math.max(0, deltaTime)
    if total + 1e-9 < interval then
        return false, total
    end
    -- Preserve fractional frames, but never issue catch-up shots after a stall.
    return true, math.max(0, total - math.floor((total + 1e-9) / interval) * interval)
end

function predictionMath.interceptTime(offset: Vector3, velocity: Vector3, speed: number): number?
    if not predictionMath.finite(speed) or speed <= 1 then return nil end
    local a: number = velocity:Dot(velocity) - speed * speed
    local b: number = 2 * offset:Dot(velocity)
    local c: number = offset:Dot(offset)
    if not predictionMath.finite(a) or not predictionMath.finite(b)
        or not predictionMath.finite(c) then return nil end
    if c < 1e-8 then return 0 end
    local time: number? = nil
    if math.abs(a) < 1e-6 then
        if b < -1e-6 then time = -c / b end
    else
        local discriminant: number = b * b - 4 * a * c
        if discriminant >= 0 then
            local root: number = math.sqrt(discriminant)
            local first: number = (-b - root) / (2 * a)
            local second: number = (-b + root) / (2 * a)
            if first >= 0 then time = first end
            if second >= 0 and (not time or second < time) then time = second end
        end
    end
    -- A long/unsolvable trajectory is not a reliable shot; do not clamp it
    -- into a fictitious intercept. Covers the configured 400-stud knife range.
    return time and predictionMath.finite(time) and time <= 5 and time or nil
end

function predictionMath.closestCrossing(samples: {{t: number, p: Vector3}}, point: Vector3): (number?, number)
    local bestTime: number? = nil
    local bestDistance: number = math.huge
    for index: number = 2, #samples do
        local first, last = samples[index - 1], samples[index]
        local step: Vector3 = last.p - first.p
        local lengthSquared: number = step:Dot(step)
        if last.t > first.t and lengthSquared > 1e-8 then
            local alpha: number = math.clamp((point - first.p):Dot(step) / lengthSquared, 0, 1)
            local distance: number = (first.p + step * alpha - point).Magnitude
            if distance < bestDistance then
                bestDistance = distance
                bestTime = first.t + (last.t - first.t) * alpha
            end
        end
    end
    return bestTime, bestDistance
end

local function isMotionGrounded(humanoid: Humanoid?, velocity: Vector3): boolean
    -- Remote FloorMaterial can lag a jump (also visible in TestingStuff logs).
    return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
        and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
        and math.abs(velocity.Y) <= 6
end

type MotionSample = {
    character: Model?,
    position: Vector3,
    sampledAt: number,
    velocity: Vector3,
    acceleration: Vector3,
    stability: number,
    grounded: boolean,

    turnRate: number?,
    turnReferenceAt: number?,
}

local motionSamples: {[Player]: MotionSample} =
    setmetatable({}, {__mode = "k"}) :: any

local GUN_LEAD = {
    replicationRate = 20,
    serverFrame = 1 / 60,
    minimumHorizon = 0,
    maximumHorizon = 0.25,
    maximumManualBias = 0.15,
    maximumAutoCorrection = 0.1,

    -- Radians/second. The turn rate itself is measured per motion sample in
    -- getFilteredVelocity; these are only its bounds and its fallback.
    defaultTurnRate = math.pi * 0.5,
    maxTurnRate = math.pi * 1.5,
}
local autoLeadCorrection: number = 0

local function getActiveAutoLeadCorrection(): number
    return mm2Settings.autoTuneLead and autoLeadCorrection or 0
end

local function resetAutoLeadCorrection(): ()
    autoLeadCorrection = 0
end

local function getFilteredVelocity(player: Player, root: BasePart): Vector3
    local now: number = os.clock()
    local velocity: Vector3 = root.AssemblyLinearVelocity
    if not predictionMath.finite(velocity.X) or not predictionMath.finite(velocity.Y)
        or not predictionMath.finite(velocity.Z) then
        motionSamples[player] = nil
        return Vector3.zero
    end
    if velocity.Magnitude > 110 then
        velocity = velocity.Unit * 110
    end
    local sample: MotionSample? = motionSamples[player]
    local acceleration: Vector3 = Vector3.zero
    local stability: number = 1
    local turnRate: number? = nil
    local turnReferenceAt: number? = nil
    local character: Model? = player.Character
    local humanoid: Humanoid? = character
        and character:FindFirstChildOfClass("Humanoid")
        :: Humanoid?
    local grounded: boolean = isMotionGrounded(humanoid, velocity)

    if sample and sample.character == character then
        local deltaTime: number = now - sample.sampledAt
        if deltaTime + 1e-9 < 1 / 120 then
            return velocity
        end
        -- Teleports/respawns must not seed an acceleration estimate.
        if deltaTime < 0.25 and (root.Position - sample.position).Magnitude < 32 then
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

            -- Time-normalized turn rate in radians/second. Measured over the
            -- window since the last direction change, so it stays the same
            -- whether Motion Hz is 20 or 120: replication updates are chunky
            -- and per-sample deltas would scale with the sampling frequency.
            local referenceAt: number = sample.turnReferenceAt
                or sample.sampledAt
            if stability < 0.99999 then
                local window: number = now - referenceAt
                if window >= 1 / 240 then
                    turnRate = math.clamp(
                        math.acos(stability) / window,
                        0,
                        GUN_LEAD.maxTurnRate
                    )
                end
                turnReferenceAt = now
            else
                turnRate = sample.turnRate
                turnReferenceAt = referenceAt
                -- Straight-line motion decays any stale turn estimate.
                if now - referenceAt > 0.2 then
                    turnRate = 0
                end
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
        turnRate = turnRate,
        turnReferenceAt = turnReferenceAt,
    }
    return velocity
end

local lastLatencyReadAt: number = -math.huge
local function getEstimatedLatency(): number
    local now: number = os.clock()
    if now - lastLatencyReadAt < 0.1 then
        return math.clamp(mm2Settings.predictionRtt, 0.03, 0.3)
    end
    local elapsed: number = now - lastLatencyReadAt
    lastLatencyReadAt = now
    local measuredRtt: number = mm2Settings.predictionRtt
    pcall(function(): ()
        local network: Instance? = Stats:FindFirstChild("Network")
        local serverItems: Instance? = network
            and network:FindFirstChild("ServerStatsItem")
        local pingItem: any = serverItems and serverItems:FindFirstChild("Data Ping")
        if pingItem and type(pingItem.GetValue) == "function" then
            local pingMilliseconds: number? = tonumber(pingItem:GetValue())
            if predictionMath.finite(pingMilliseconds) and pingMilliseconds >= 0 then
                measuredRtt = pingMilliseconds / 1000
            end
        end
    end)
    -- Time-based smoothing: changing Motion/Throw Hz must not change the RTT.
    local alpha: number = 1 - math.exp(-math.min(elapsed, 1) / 0.5)
    mm2Settings.predictionRtt += (measuredRtt - mm2Settings.predictionRtt) * alpha

    return math.clamp(
        mm2Settings.predictionRtt,
        0.03,
        0.3
    )
end

local trajectoryCalibration: any = nil

local function getGunHorizonSeconds(): number
    -- Three field reports, one per direction:
    --  * v24: leading by the FULL ~277 ms acceptance window missed AHEAD
    --    (shots landing where the target could never be).
    --  * v24.1: aiming at the raw observed position missed BEHIND moving
    --    targets ("apunta a donde estaba hace 1 segundo").
    --  * v26 (0.6xRTT): hits still landed slightly BEHIND fast movers, and
    --    on fast strafes the aim trailed to the CENTER of the strafe path
    --    ("le da como en el centro y no al murder"). The miss always points
    --    along the target's movement.
    -- Reconciliation: the victim's physics replicates victim->server->us, so
    -- what we see is his position from ~1 RTT ago, and the server processes
    -- our shot ~half an RTT after we send it. The full staleness is the RTT
    -- itself: lead by exactly that - no more (the acceptance window is a
    -- REWIND of past positions and must not be spent as forward lead), no
    -- less (undershoot keeps aiming at the recent past).
    local staleness: number = math.clamp(
        getEstimatedLatency() * 1.0,
        0,
        0.15
    )
    local manualBias: number = math.clamp(
        mm2Settings.gunLeadBias,
        -GUN_LEAD.maximumManualBias,
        GUN_LEAD.maximumManualBias
    )
    local autoCorrection: number = math.clamp(
        getActiveAutoLeadCorrection(),
        -GUN_LEAD.maximumAutoCorrection,
        GUN_LEAD.maximumAutoCorrection
    )
    return math.clamp(
        staleness + manualBias + autoCorrection,
        GUN_LEAD.minimumHorizon,
        GUN_LEAD.maximumHorizon
    )
end

local function getGunTurnRate(sample: MotionSample?): number
    -- Reads the time-normalized turn rate measured in getFilteredVelocity
    -- (radians/second), so the lead discount no longer changes meaning when
    -- Motion Hz changes. A missing or stale sample keeps the conservative
    -- default.
    if type(sample) ~= "table" then
        return GUN_LEAD.defaultTurnRate
    end
    local measured: any = (sample :: any).turnRate
    if type(measured) ~= "number" then
        return GUN_LEAD.defaultTurnRate
    end
    return math.clamp(measured, 0, GUN_LEAD.maxTurnRate)
end

local function getGunTurnDiscount(horizon: number, turnRate: number?): number

    local rate: number = turnRate or GUN_LEAD.defaultTurnRate
    return math.clamp(
        math.cos(math.min(horizon * rate * 0.5, math.pi * 0.5)),
        0.25,
        1
    )
end

local function getGunLeadSensitivity(horizon: number, turnRate: number?): number

    local rate: number = turnRate or GUN_LEAD.defaultTurnRate
    local angle: number = horizon * rate * 0.5
    if angle >= math.pi * 0.5 then
        return 0.25
    end
    local rawDiscount: number = math.cos(angle)
    if rawDiscount <= 0.25 then
        return 0.25
    end
    return rawDiscount - horizon * math.sin(angle) * rate * 0.5
end

local function getGunLeadStatus(): {[string]: any}
    return {
        manualBias = math.clamp(
            mm2Settings.gunLeadBias,
            -GUN_LEAD.maximumManualBias,
            GUN_LEAD.maximumManualBias
        ),
        autoCorrection = getActiveAutoLeadCorrection(),
        storedAutoCorrection = autoLeadCorrection,
        autoTuneEnabled = mm2Settings.autoTuneLead,
        horizon = getGunHorizonSeconds(),
    }
end

local function getGunOriginCFrame(character: Model, gun: Tool?): CFrame?
    local root: BasePart? = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local attachment: Attachment? = root
        and root:FindFirstChild("GunRaycastAttachment")
        :: Attachment?
    if attachment and attachment:IsA("Attachment") then
        return attachment.WorldCFrame
    end

    if gun then
        for _, partName: string in ipairs({"Muzzle", "Handle"}) do
            local part: Instance? = gun:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                return part.CFrame
            end
        end
    end
    for _, partName: string in ipairs({"RightHand", "Right Arm", "Head"}) do
        local part: Instance? = character:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            return part.CFrame
        end
    end
    local camera: Camera? = workspace.CurrentCamera
    if camera and root then
        return CFrame.new(root.Position + Vector3.new(0, 1.5, 0))
            * (camera.CFrame - camera.CFrame.Position)
    end
    return root and root.CFrame or nil
end

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
        shotId: string?,
        attemptCounted: boolean?,
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
        shotId: string?,
        attemptCounted: boolean?,
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
        shotId: string?,
        attemptCounted: boolean?,
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
        shotId: string?,
        settings: any?,
        phase: string?,
        sessionId: string?,
        buildStamp: string?,
        kind: string,
        serverTime: number,
        pingMs: number,
        latencyMs: number?,
        distance: number?,
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
        origin: {number}?,
        observedTargetPosition: {number}?,
        endpointToObservedTarget: number?,
        shotRange: number?,
        hitPartPath: string?,
        evidence: string?,
        targetPositionScope: string?,
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
        liveGunAcceptanceMs: number?,
        liveGunSamples: number,
        maxStabDistance: number?,
        knifeSpawnDelayMs: number?,
        confirmedSpawnDelays: number,
    }
    type Controller = {
        start: (self: Controller) -> (),
        save: (self: Controller, reason: string?) -> boolean,
        reset: (self: Controller) -> (),
        destroy: (self: Controller) -> (),
        status: (self: Controller) -> string,
        getEstimates: (self: Controller) -> Estimates,
        noteAuthoredShot: (self: Controller, info: any) -> (),
        noteTracerData: (self: Controller, info: any) -> (),
    }

    local OUTPUT_ROOT: string = host.PRODUCT.storageFolder
    local OUTPUT_FOLDER: string = OUTPUT_ROOT .. "/Telemetry"
    local OUTPUT_PATH: string = OUTPUT_FOLDER
        .. "/MM2_Trajectory_Calibration.json"
    local MAX_EVENTS: number = 2400
    local MAX_PENDING_AGE: number = 2.5
    local environment: {[string]: any} = getfenv() :: any
    local playerMouse: Mouse = LocalPlayer:GetMouse()
    local runtime: any = {
        active = false,
        dirty = false,
        revision = 0,
        saveScheduled = false,
        startedAt = os.clock(),
        startedAtUnix = os.time(),
        sessionId = HttpService:GenerateGUID(false),
        buildStamp = tostring(host.SOURCE_STAMP or "unknown"),
        shotSequence = 0,
        historyBackup = nil :: string?,
        persistenceBlocked = false,
        rawKnifeActivations = 0,
        unmatchedGunSignals = 0,
        sessionStabAttempts = 0,
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
        freshGunLatency = {} :: {{at: number, ms: number}},
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

    local function nextShotId(): string
        runtime.shotSequence += 1
        return runtime.sessionId .. ":" .. tostring(runtime.shotSequence)
    end
    local function emitShot(eventType: string, info: any): ()
        info.sessionId = runtime.sessionId
        info.buildStamp = runtime.buildStamp
        if type(state.emitGameBridgeEvent) == "function" then
            state.emitGameBridgeEvent(eventType, info)
        end
    end

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

    local function applyStatsPayload(
        stats: RunningStats,
        payload: {[string]: number}
    ): ()
        stats.count = tonumber(payload.count) or 0
        stats.mean = tonumber(payload.mean) or 0
        stats.m2 = tonumber(payload.m2) or 0
        stats.minimum = stats.count > 0
            and (tonumber(payload.minimum) or 0)
            or math.huge
        stats.maximum = stats.count > 0
            and (tonumber(payload.maximum) or 0)
            or -math.huge
    end

    local function restoreMotionBucket(bucket: any): any
        local count: number = tonumber(bucket.count) or 0
        local residual: any = bucket.meanConstantVelocityResidual or {}
        local errors: any = bucket.meanModelError or {}
        return {
            count = count,
            durationSum = bucket.durationSum or (bucket.meanDurationSeconds or 0) * count,
            horizontalLeadCount = bucket.horizontalLeadCount or (bucket.meanHorizontalLeadSeconds and count or 0),
            horizontalLeadSum = bucket.horizontalLeadSum or (bucket.meanHorizontalLeadSeconds or 0) * count,
            verticalLeadCount = bucket.verticalLeadCount or (bucket.meanVerticalLeadSeconds and count or 0),
            verticalLeadSum = bucket.verticalLeadSum or (bucket.meanVerticalLeadSeconds or 0) * count,
            residualXSum = bucket.residualXSum or (residual[1] or 0) * count,
            residualYSum = bucket.residualYSum or (residual[2] or 0) * count,
            residualZSum = bucket.residualZSum or (residual[3] or 0) * count,
            constantVelocityErrorSum = bucket.constantVelocityErrorSum or (errors.constantVelocity or 0) * count,
            observedAccelerationErrorSum = bucket.observedAccelerationErrorSum or (errors.observedAcceleration or 0) * count,
            airborneBallisticErrorSum = bucket.airborneBallisticErrorSum or (errors.airborneBallistic or 0) * count,
        }
    end

    local function loadSavedHistory(): ()
        if type(environment.readfile) ~= "function" then
            runtime.persistenceBlocked = true
            return
        end
        local okRead: boolean, raw: any = pcall(environment.readfile, OUTPUT_PATH)
        if not okRead then
            local okExists, exists = pcall(function() return environment.isfile(OUTPUT_PATH) end)
            runtime.persistenceBlocked = not (okExists and exists == false)
            return
        end
        if type(raw) ~= "string" then runtime.persistenceBlocked = true; return end
        if #raw == 0 then return end
        local backup: string = OUTPUT_PATH .. ".before-" .. runtime.sessionId .. ".json"
        local okBackup: boolean = type(environment.writefile) == "function"
            and pcall(environment.writefile, backup, raw)
        local okVerify, backedUp = pcall(environment.readfile, backup)
        if not okBackup or not okVerify or backedUp ~= raw then
            runtime.persistenceBlocked = true
            warn(trajectoryLogPrefix .. " History backup failed; existing file will not be overwritten.")
            return
        end
        runtime.historyBackup = backup
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(decoded) ~= "table" then return end
        -- Only plausible statistical estimates are portable. Counts such as
        -- 10^57, old events and old motion buckets never become session data.
        local aggregate: any = type(decoded.aggregate) == "table" and decoded.aggregate or {}
        local function importStats(stats: RunningStats, payload: any, low: number, high: number): ()
            if type(payload) ~= "table" then return end
            for _, key in ipairs({"count", "mean", "m2", "minimum", "maximum"}) do
                if not predictionMath.finite(payload[key]) then return end
            end
            if payload.count < 1 or payload.count > 1000000 or payload.count % 1 ~= 0
                or payload.m2 < 0 or payload.m2 > payload.count * (high - low) ^ 2
                or payload.minimum < low or payload.maximum > high
                or payload.mean < payload.minimum or payload.mean > payload.maximum then return end
            applyStatsPayload(stats, payload)
        end
        importStats(runtime.gunAcceptance, aggregate.gunAcceptanceMs, 0, 2500)
        importStats(runtime.knifeSpeed, aggregate.knifeSpeedStudsPerSecond, 24, 300)
        importStats(runtime.knifeSpawnDelay, aggregate.knifeSpawnDelayMs, 0, 5000)
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
                and not isProtectedTarget(player) then
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
        record.sessionId = runtime.sessionId
        record.buildStamp = runtime.buildStamp
        if #runtime.events >= MAX_EVENTS then
            table.remove(runtime.events, 1)
        end
        table.insert(runtime.events, record)
        runtime.revision += 1
        runtime.dirty = true
        if runtime.saveScheduled then
            return
        end
        runtime.saveScheduled = true
        task.delay(10, function(): ()
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

    local function motionModelPayload(buckets: {[string]: any}): {[string]: any}
        local payload: {[string]: any} = {}
        for key: string, bucket: any in pairs(buckets) do
            if type(bucket) == "table" then
                local count: number = math.max(1, tonumber(bucket.count) or 1)
                local horizontalCount: number = math.max(
                    1,
                    tonumber(bucket.horizontalLeadCount) or 0
                )
                local verticalCount: number = math.max(
                    1,
                    tonumber(bucket.verticalLeadCount) or 0
                )

                local meanDuration: number = tonumber(bucket.meanDurationSeconds)
                    or (bucket.durationSum and (bucket.durationSum / count))
                    or 0

                local meanHorizLead: number? = nil
                if bucket.horizontalLeadSum and horizontalCount > 0 then
                    meanHorizLead = bucket.horizontalLeadSum / horizontalCount
                elseif bucket.meanHorizontalLeadSeconds then
                    meanHorizLead = bucket.meanHorizontalLeadSeconds
                end

                local meanVertLead: number? = nil
                if bucket.verticalLeadSum and verticalCount > 0 then
                    meanVertLead = bucket.verticalLeadSum / verticalCount
                elseif bucket.meanVerticalLeadSeconds then
                    meanVertLead = bucket.meanVerticalLeadSeconds
                end

                local meanResidual: {number}
                if type(bucket.meanConstantVelocityResidual) == "table" then
                    meanResidual = bucket.meanConstantVelocityResidual
                else
                    meanResidual = {
                        (tonumber(bucket.residualXSum) or 0) / count,
                        (tonumber(bucket.residualYSum) or 0) / count,
                        (tonumber(bucket.residualZSum) or 0) / count,
                    }
                end

                local meanModelErr: {[string]: number}
                if type(bucket.meanModelError) == "table" then
                    meanModelErr = bucket.meanModelError
                else
                    meanModelErr = {
                        constantVelocity = (tonumber(bucket.constantVelocityErrorSum) or 0) / count,
                        observedAcceleration = (tonumber(bucket.observedAccelerationErrorSum) or 0) / count,
                        airborneBallistic = (tonumber(bucket.airborneBallisticErrorSum) or 0) / count,
                    }
                end

                payload[key] = {
                    durationSum = bucket.durationSum,
                    horizontalLeadSum = bucket.horizontalLeadSum,
                    horizontalLeadCount = bucket.horizontalLeadCount,
                    verticalLeadSum = bucket.verticalLeadSum,
                    verticalLeadCount = bucket.verticalLeadCount,
                    residualXSum = bucket.residualXSum,
                    residualYSum = bucket.residualYSum,
                    residualZSum = bucket.residualZSum,
                    constantVelocityErrorSum = bucket.constantVelocityErrorSum,
                    observedAccelerationErrorSum = bucket.observedAccelerationErrorSum,
                    airborneBallisticErrorSum = bucket.airborneBallisticErrorSum,
                    count = tonumber(bucket.count) or 0,
                    meanDurationSeconds = meanDuration,
                    meanHorizontalLeadSeconds = meanHorizLead,
                    meanVerticalLeadSeconds = meanVertLead,
                    meanConstantVelocityResidual = meanResidual,
                    meanModelError = meanModelErr,
                }
            end
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

    local estimatesCache: Estimates? = nil
    local estimatesAt: number = -math.huge
    local function estimates(): Estimates
        local now: number = os.clock()
        if estimatesCache and now - estimatesAt < 0.25 then return estimatesCache end
        local fresh: {number} = {}
        for _, sample in ipairs(runtime.freshGunLatency) do
            if now - sample.at <= 60 then table.insert(fresh, sample.ms) end
        end
        local gunStats: RunningStats = runtime.gunAcceptance
        local speedStats: RunningStats = runtime.knifeSpeed
        local spawnDelayStats: RunningStats = runtime.knifeSpawnDelay
        local maxStab: number? = nil
        for _, ev in ipairs(runtime.events) do
            if ev.kind == "stab" and ev.hitTarget == true
                and predictionMath.finite(ev.distance) then
                if not maxStab or ev.distance > maxStab then
                    maxStab = ev.distance
                end
            end
        end
        estimatesCache = {
            gunAcceptanceMs = gunStats.count > 0 and gunStats.mean or nil,
            knifeSpeed = speedStats.count > 0 and speedStats.mean or nil,
            confirmedShots = gunStats.count,
            confirmedThrows = speedStats.count,
            maxStabDistance = maxStab,
            liveGunAcceptanceMs = #fresh >= 6 and median(fresh) or nil,
            liveGunSamples = #fresh,
            knifeSpawnDelayMs = spawnDelayStats.count > 0
                and spawnDelayStats.mean
                or nil,
            confirmedSpawnDelays = spawnDelayStats.count,
        }
        estimatesAt = now
        return estimatesCache :: Estimates
    end

    saveSnapshot = function(reason: string): boolean
        if runtime.persistenceBlocked then return false end
        if type(environment.writefile) ~= "function" then
            warn(trajectoryLogPrefix .. " writefile is unavailable; data was not saved.")
            return false
        end

        -- History is loaded once. Re-merging the on-disk totals at each save
        -- used to double counters/buckets and read/decode a large JSON per shot.
        local savedRevision: number = runtime.revision
        local mergedGun = statsPayload(runtime.gunAcceptance)
        local mergedKnife = statsPayload(runtime.knifeSpeed)
        local mergedDelay = statsPayload(runtime.knifeSpawnDelay)
        local payload: {[string]: any} = {
            schema = 4,
            kind = "mm2-trajectory-analytics",
            buildStamp = runtime.buildStamp,
            sessionId = runtime.sessionId,
            historyBackup = runtime.historyBackup,
            settings = {
                motionSampleHz = mm2Settings.motionSampleHz,
                silentSpawn = mm2Settings.silentSpawn,
                silentAim = mm2Settings.silentAim,
                silentSweep = mm2Settings.silentSweep,
                wallCheck = mm2Settings.shootWallCheck,
                leadBias = mm2Settings.gunLeadBias,
                autoTuneLead = mm2Settings.autoTuneLead,
            },
            placeId = game.PlaceId,
            savedAt = DateTime.now():ToIsoDate(),
            reason = reason,
            aggregateScope = "validated-history-plus-this-session; not a hit-rate denominator",
            aggregate = {
                gunAcceptanceMs = mergedGun,
                knifeSpeedStudsPerSecond = mergedKnife,
                knifeSpawnDelayMs = mergedDelay,
            },
            estimator = {
                gunAcceptanceMs = mergedGun.count > 0 and mergedGun.mean or nil,
                knifeSpeed = mergedKnife.count > 0 and mergedKnife.mean or nil,
                confirmedShots = mergedGun.count,
                confirmedThrows = mergedKnife.count,
            },
            analytics = {
                bucketSpec = {
                    metric = "Data Ping",
                    widthMs = 5,
                    minimumMs = 0,
                    maximumMs = 250,
                    states = {"Grounded", "Airborne"},
                },
                motionModel = motionModelPayload(runtime.motionBuckets),
            },
            session = {
                startedAt = runtime.startedAtUnix,
                countersScope = "this-session-only",
                gunConfirmationMeaning = "matched GunFired signal; not necessarily damage or death",
                knifeConfirmationMeaning = "observed projectile with valid speed; not an impact",
                rawKnifeActivations = runtime.rawKnifeActivations,
                unmatchedGunSignals = runtime.unmatchedGunSignals,
                stabAttempts = runtime.sessionStabAttempts,
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
            warn(trajectoryLogPrefix .. " JSONEncode failed: " .. tostring(encoded))
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
            warn(trajectoryLogPrefix .. " writefile failed: " .. tostring(writeError))
            return false
        end

        -- A yielding executor write must not clear events recorded meanwhile.
        runtime.dirty = runtime.revision ~= savedRevision
        print(
            trajectoryLogPrefix .. " Saved "
                .. OUTPUT_PATH
                .. " ("
                .. tostring(#encoded)
                .. " bytes)"
        )
        return true
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
            shotId = pending.shotId,
            phase = "confirmation",
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
        -- Match the OLDEST unconfirmed attempt whose tool and origin geometry
        -- agree with the signal. Iterating newest-first let a signal confirm
        -- a younger shot and feed a wrong latency into the adaptive horizon.
        local selectedIndex: number? = nil
        local fallbackIndex: number? = nil
        for index: number = 1, #runtime.pendingGuns do
            local pending: PendingGun = runtime.pendingGuns[index]
            if not pending.confirmedAt then
                local toolMatches: boolean = eventTool ~= nil
                    and eventTool == pending.tool
                local originMatches: boolean = eventOrigin ~= nil
                    and pending.origin ~= nil
                    and (eventOrigin - pending.origin).Magnitude <= 8
                if toolMatches and originMatches then
                    selectedIndex = index
                    break
                end
                if fallbackIndex == nil then
                    if toolMatches
                        and (eventOrigin == nil or pending.origin == nil) then
                        fallbackIndex = index
                    elseif eventTool == nil and originMatches then
                        fallbackIndex = index
                    end
                end
            end
        end
        if not selectedIndex then
            selectedIndex = fallbackIndex
        end
        if not selectedIndex then
            local character: Model? = LocalPlayer.Character
            local root: BasePart? = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
            local isLocalShooter: boolean = false
            if eventTool and eventTool.Parent == character then
                isLocalShooter = true
            elseif root and eventOrigin and (eventOrigin - root.Position).Magnitude <= 20 then
                isLocalShooter = true
            end
            if isLocalShooter then
                runtime.unmatchedGunSignals += 1
                appendEvent({kind = "gun", phase = "unmatched-signal",
                    serverTime = workspace:GetServerTimeNow(), pingMs = getPingMilliseconds()})
            end
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
        if latencyMs >= 30 and latencyMs <= 450 then
            table.insert(runtime.freshGunLatency, {at = now, ms = latencyMs})
            if #runtime.freshGunLatency > 24 then table.remove(runtime.freshGunLatency, 1) end
            estimatesAt = -math.huge
        end
        addSample(runtime.gunAcceptance, latencyMs)
        runtime.sessionGunConfirmed += 1
        pending.confirmedAt = now
        pending.latencyMs = latencyMs
        pending.confirmedEndpoint = endpoint
        pending.confirmedHitTarget = hitTarget
        emitShot("shotConfirmation", {
            shotId = pending.shotId, kind = "gun", hitTarget = hitTarget,
            targetName = pending.targetName, latencyMs = latencyMs,
            endpoint = endpoint, evidence = "GunFired.hitPart",
        })
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
                shotId = track.shotId,
                phase = "projectile-observed",
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
        local sessionId = runtime.sessionId
        task.spawn(function(): ()
            local linkedHandle: Instance? = nil
            for _attempt: number = 1, 20 do
                if not runtime.active or runtime.sessionId ~= sessionId or not projectile.Parent then
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
            if not pending.attemptCounted then
                runtime.sessionKnifeAttempts += 1
                emitShot("authoringShot", {shotId = pending.shotId, kind = "knife",
                    toolName = pending.tool.Name, originPos = pending.origin,
                    aimPos = pending.requestedAim, targetName = pending.targetName,
                    eventSource = "observed-projectile"})
            end
            emitShot("shotConfirmation", {shotId = pending.shotId, kind = "knife",
                evidence = "projectile-observed", targetName = pending.targetName})
            local track: KnifeTrack = {
                shotId = pending.shotId,
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
            or (tool:FindFirstChild("Events") ~= nil
                and tool.Events:FindFirstChild("KnifeThrown") ~= nil)
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
            local shotId: string = nextShotId()
            appendEvent({shotId = shotId, kind = gun and "gun" or "knifeActivation",
                phase = gun and "attempt" or "activation",
                serverTime = workspace:GetServerTimeNow(), pingMs = pingMs,
                targetName = target and target.Name or nil})
            emitShot("authoringShot", {shotId = shotId, kind = gun and "gun" or "knifeActivation",
                toolName = tool.Name, originPos = toolOrigin(tool), aimPos = requestedAim,
                targetName = target and target.Name or nil, eventSource = "tool-activation"})
            if gun then
                runtime.sessionGunAttempts += 1
                table.insert(runtime.pendingGuns, {
                    shotId = shotId,
                    attemptCounted = gun,
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
                runtime.rawKnifeActivations += 1
                table.insert(runtime.pendingKnives, {
                    shotId = shotId,
                    attemptCounted = gun,
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
                warn(trajectoryLogPrefix .. " WeaponService did not appear; Knife remains active.")
                return
            end
            local loaded: boolean, weaponService: any = pcall(
                state.requireModule,
                weaponModule
            )
            if not loaded or type(weaponService) ~= "table" then
                warn(
                    trajectoryLogPrefix .. " Could not observe WeaponService: "
                        .. tostring(weaponService)
                )
                return
            end
            local connected: boolean, connection: any = pcall(function(): any
                return weaponService.GunFired.OnClientEvent:Connect(handleGunFired)
            end)
            if connected and connection then
                trackConnection(connection :: RBXScriptConnection)
                print(trajectoryLogPrefix .. " GunFired confirmation connected.")
            else
                warn(
                    trajectoryLogPrefix .. " GunFired no es compatible: "
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

        if not (GAME_CHECK.MM2Active or game.PlaceId == Module.PlaceId) then
            warn(trajectoryLogPrefix .. " Inicio omitido fuera de MM2.")
            return
        end
        runtime.active = true
        runtime.startedAt = os.clock()
        runtime.startedAtUnix = os.time()
        loadSavedHistory()
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
        print(trajectoryLogPrefix .. " Passive calibration started in the background.")
    end

    local function clearHistory(): ()
        runtime.gunAcceptance = newStats()
        runtime.knifeSpeed = newStats()
        runtime.knifeSpawnDelay = newStats()
        runtime.motionBuckets = {}
        runtime.events = {}
        runtime.freshGunLatency = {}
        estimatesCache = nil
        estimatesAt = -math.huge
        runtime.sessionGunAttempts = 0
        runtime.sessionGunConfirmed = 0
        runtime.sessionKnifeAttempts = 0
        runtime.sessionKnifeConfirmed = 0
        runtime.rawKnifeActivations = 0
        runtime.unmatchedGunSignals = 0
        runtime.sessionStabAttempts = 0
        runtime.startedAt = os.clock()
        runtime.startedAtUnix = os.time()
        for _, track in pairs(runtime.tracks) do
            if track.destroyConnection then track.destroyConnection:Disconnect() end
        end
        table.clear(runtime.tracks)
        disconnectFeatureConnection("MM2TrajectorySampler")
        runtime.sessionId = HttpService:GenerateGUID(false)
        runtime.shotSequence = 0
        table.clear(runtime.pendingGuns)
        table.clear(runtime.pendingKnives)
    end

    function controller:save(reason: string?): boolean
        return saveSnapshot(reason or "manual")
    end

    function controller:reset(): ()
        clearHistory()
        runtime.dirty = false
        if type(environment.delfile) == "function" then
            pcall(environment.delfile, OUTPUT_PATH)
        elseif type(environment.writefile) == "function" then
            pcall(environment.writefile, OUTPUT_PATH, "{}")
        end
        print(trajectoryLogPrefix .. " History cleared.")
    end

    function controller:getEstimates(): Estimates
        return estimates()
    end

    -- Separate feedback event: never count an echo as another authored shot
    -- or use endpoint-to-client-position distance as proof of a server miss.
    function controller:noteTracerData(info: any): ()
        if not runtime.active or type(info) ~= "table" then return end
        local function validVector(value: any): boolean
            return typeof(value) == "Vector3"
                and predictionMath.finite(value.X) and predictionMath.finite(value.Y)
                and predictionMath.finite(value.Z) and value.Magnitude < 1e7
        end
        if not validVector(info.origin) or not validVector(info.endpoint) then return end
        local function pack(value: Vector3): {number}
            return {value.X, value.Y, value.Z}
        end
        local shotId: string? = nil
        local now: number = os.clock()
        for index: number = #runtime.pendingGuns, 1, -1 do
            local pending: PendingGun = runtime.pendingGuns[index]
            if now - pending.activatedAt <= 2.5 and pending.origin
                and (pending.origin - info.origin).Magnitude <= 8 then
                shotId = pending.shotId
                break
            end
        end
        local target: any = info.target
        local targetPosition: Vector3? = validVector(info.targetPosition) and info.targetPosition or nil
        local path: string? = nil
        local hitTarget: boolean? = nil
        if typeof(info.hitPart) == "Instance" then
            pcall(function(): () path = string.sub(info.hitPart:GetFullName(), 1, 512) end)
            if target and target.Character then
                hitTarget = info.hitPart:IsDescendantOf(target.Character)
            end
        end
        appendEvent({kind = "gun", phase = "tracer-data", shotId = shotId,
            serverTime = workspace:GetServerTimeNow(), pingMs = getPingMilliseconds(),
            origin = pack(info.origin), endpoint = pack(info.endpoint),
            shotRange = (info.endpoint - info.origin).Magnitude,
            targetUserId = target and target.UserId or nil,
            targetName = target and target.Name or nil,
            observedTargetPosition = targetPosition and pack(targetPosition) or nil,
            endpointToObservedTarget = targetPosition and (info.endpoint - targetPosition).Magnitude or nil,
            targetPositionScope = "client-observed-at-GunFired-receipt; not server impact-time position",
            hitPartPath = path, hitTarget = hitTarget, evidence = "GunFired endpoint/hitPart",
        })
    end

    function controller:noteAuthoredShot(info: any): ()
        if not runtime.active or type(info) ~= "table" then
            return
        end
        local kind: string = tostring(info.kind or "gun")
        local shotId: string = nextShotId()
        if kind ~= "stab" then
            appendEvent({kind = kind, shotId = shotId, phase = "authored",
                serverTime = workspace:GetServerTimeNow(), pingMs = getPingMilliseconds(),
                settings = info.settings, targetName = info.target and info.target.Name or nil})
        end
        local now: number = os.clock()
        local pingMs: number = getPingMilliseconds()
        local target: Player? =
            info.target and info.target.Character ~= nil and info.target or nil
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
        if kind == "stab" then
            runtime.sessionStabAttempts += 1
            local targetRoot: BasePart? = getTargetRoot(target)
            local localRoot: BasePart? =
                LocalPlayer.Character
                and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                :: BasePart?
            local distance: number? = targetRoot
                and localRoot
                and (targetRoot.Position - localRoot.Position).Magnitude
            appendEvent({
                kind = "stab", shotId = shotId, phase = "attempt",
                serverTime = workspace:GetServerTimeNow(),
                pingMs = pingMs,
                distance = distance and math.floor(distance * 10 + 0.5) / 10 or nil,
                targetUserId = target and target.UserId or nil,
                targetName = target and target.Name or nil,
                targetState = targetTrajectory[1]
                    and targetTrajectory[1].humanoidState
                    or nil,
                targetTrajectory = #targetTrajectory > 0 and targetTrajectory or nil,
            })
        else
            local isGun: boolean = kind ~= "knife"
            local authoredTool: Tool? = nil
            if typeof(info.tool) == "Instance" and info.tool:IsA("Tool") then
                authoredTool = info.tool :: Tool
            end

            if isGun or authoredTool ~= nil then
                if isGun then
                    runtime.sessionGunAttempts += 1
                else
                    runtime.sessionKnifeAttempts += 1
                end
                local queue: {any} =
                    isGun and runtime.pendingGuns or runtime.pendingKnives
                table.insert(queue, {
                    shotId = shotId,
                    attemptCounted = true,
                    tool = authoredTool,
                    activatedAt = now,
                    origin = info.originPos,
                    requestedAim = info.aimPos,
                    pingMs = pingMs,
                    targetUserId = target and target.UserId or nil,
                    targetName = target and target.Name or nil,
                    targetTrajectory = targetTrajectory,
                    lastTrajectorySampleAt = now,
                })
                compactPending(queue, now)
                ensureTrajectorySampler()
            end
        end

        if type(state.emitGameBridgeEvent) == "function" then
            emitShot("authoringShot", {
                shotId = shotId,
                eventSource = "authored",
                settings = info.settings,
                kind = kind,
                toolName = tostring(info.toolName or (kind == "knife" and "Knife" or "Gun")),
                originPos = info.originPos,
                aimPos = info.aimPos,
                targetName = target and target.Name or nil,
                silent = info.silent == true,
                variant = info.variant,
                offset = info.offset,
            })
        end
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
            "MM2 session observations · guns %d · knives %d · motion buckets %d · knife %s",
            runtime.sessionGunConfirmed,
            runtime.sessionKnifeConfirmed,
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

trajectoryCalibration = createTrajectoryCalibration()
state.mm2TrajectoryCalibration = trajectoryCalibration
trajectoryCalibration:start()

pcall(function(): ()
    if type((game :: any).BindToClose) == "function" then
        game:BindToClose(function(): ()
            if type(trajectoryCalibration.save) == "function" then
                pcall(trajectoryCalibration.save, trajectoryCalibration, "close")
            end
        end)
    end
end)

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

    aimRootOffset: Vector3?,
    leadSeconds: number?,
    leadSensitivity: number?,
    velocity: Vector3?,
    trajectory: {{t: number, p: Vector3}}?,

    silentSpawn: string?,
}

type GunPrediction = {
    aimRootOffset: Vector3?,
    targetPosition: Vector3?,
    endpoint: Vector3?,
    velocity: Vector3?,
    errorRadius: number?,
    leadSeconds: number?,
    leadSensitivity: number?,
}

state.mm2ShotFeedback = {

    shootActive = false,
    pending = nil :: PendingShot?,
    lastAccepted = nil :: PendingShot?,

    spawnStats = {} :: {[string]: {shots: number, hits: number, misses: number}},
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
    TextTruncate = Enum.TextTruncate.AtEnd,
    ClipsDescendants = true,
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

local leadTracking: PendingShot? = nil

local function stopLeadTracking(): ()
    leadTracking = nil
    disconnectFeatureConnection("MM2LeadTuner")
end

local function startLeadTracking(candidate: PendingShot): ()
    if not mm2Settings.autoTuneLead then
        return
    end
    local root: BasePart? = candidate.targetCharacter
        and candidate.targetCharacter:FindFirstChild("HumanoidRootPart")
        :: BasePart?
    if not root or candidate.velocity == nil then
        return
    end
    stopLeadTracking()
    leadTracking = candidate
    local samples: {{t: number, p: Vector3}} = {{t = os.clock(), p = root.Position}}
    candidate.trajectory = samples
    local elapsed: number = 0
    featureConnections.MM2LeadTuner = TaskManager:Connect(function(
        deltaTime: number
    ): ()
        if leadTracking ~= candidate then
            return
        end
        if state.mm2ShotFeedback.pending ~= candidate
            and state.mm2ShotFeedback.lastAccepted ~= candidate then
            stopLeadTracking()
            return
        end
        local due: boolean
        due, elapsed = predictionMath.sampleDue(elapsed, deltaTime, 30)
        if not due then return end
        table.insert(samples, {t = os.clock(), p = root.Position})
        if #samples > 64 then
            table.remove(samples, 1)
        end
    end)
end

local function tuneFromConfirmedShot(candidate: PendingShot): ()
    if not mm2Settings.autoTuneLead or not candidate.aimPosition or candidate.silentSpawn then
        return
    end
    local samples: {{t: number, p: Vector3}}? = candidate.trajectory
    local velocity: Vector3? = candidate.velocity
    local leadSeconds: number? = candidate.leadSeconds
    local leadSensitivity: number? = candidate.leadSensitivity
    if not samples
        or #samples < 6
        or velocity == nil
        or leadSeconds == nil
        or leadSensitivity == nil
        or leadSensitivity < 0.15 then
        return
    end
    local horizontal: Vector3 = Vector3.new(velocity.X, 0, velocity.Z)
    if horizontal.Magnitude < 8 then
        return
    end
    -- Interpolate between 30 Hz samples instead of quantizing to a frame.
    local rootAim: Vector3 = candidate.aimPosition - (candidate.aimRootOffset or Vector3.zero)
    local crossedAt: number?, closestDistance: number = predictionMath.closestCrossing(samples, rootAim)
    if crossedAt == nil or closestDistance > 1 then return end
    local leadMeasured: number = crossedAt - candidate.queuedAt
    if leadMeasured < 0.03 or leadMeasured > 1.2 then
        return
    end

    local firstSample: {t: number, p: Vector3} = samples[1]
    local lastSample: {t: number, p: Vector3} = samples[#samples]
    local span: number = lastSample.t - firstSample.t
    if span < 0.05 then
        return
    end
    local sampledVelocity: Vector3 = (lastSample.p - firstSample.p) / span
    local sampledHorizontal: Vector3 = Vector3.new(
        sampledVelocity.X,
        0,
        sampledVelocity.Z
    )
    if sampledHorizontal.Magnitude < 8 then
        return
    end
    if sampledHorizontal.Unit:Dot(horizontal.Unit) < 0.75 then
        return
    end

    local residual: number = (leadMeasured - leadSeconds) / leadSensitivity
    local delta: number = residual * 0.25
    autoLeadCorrection = math.clamp(
        autoLeadCorrection + math.clamp(delta, -0.03, 0.03),
        -GUN_LEAD.maximumAutoCorrection,
        GUN_LEAD.maximumAutoCorrection
    )
end

state.mm2ShotFeedback.queue = function(
    target: Player?,
    gun: Tool?,
    origin: CFrame?,
    aim: CFrame?,
    prediction: GunPrediction?
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
        leadSeconds = prediction and prediction.leadSeconds or nil,
        leadSensitivity = prediction and prediction.leadSensitivity or nil,
        velocity = prediction and prediction.velocity or nil,
        aimRootOffset = prediction and prediction.aimRootOffset or nil,
    }
    state.mm2ShotFeedback.pending = candidate
    startLeadTracking(candidate)

    task.delay(1.8, function(): ()
        if state.mm2ShotFeedback.pending == candidate then
            state.mm2ShotFeedback.pending = nil
        end
    end)
    if not state.mm2ShotFeedback.gunFiredConnected then
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
            or candidate.target.Parent == nil
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
            -- Disconnection/role changes are UI heuristics, not tuning evidence.
            if directHit then tuneFromConfirmedShot(candidate) end
            state.mm2ShotFeedback.hide()
        end

        local variant: string? = candidate.silentSpawn
        if variant then
            local stats: any = state.mm2ShotFeedback.spawnStats[variant]
                or {shots = 0, hits = 0, misses = 0}
            stats.shots += 1
            -- Only the server's own hit evidence counts as a hit here.
            -- Disconnects, role changes and health drops are ambiguous: they
            -- count as neither hit nor miss, so the A/B label stays honest.
            if directHit then
                stats.hits += 1
            elseif not hitConfirmed then
                stats.misses += 1
            end
            state.mm2ShotFeedback.spawnStats[variant] = stats
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
    if not state.mm2ShotFeedback.shootActive then
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
    aura: boolean,
    auraRange: number,
}

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
            for _, player: Player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer
                    and isPlayerAlive(player)
                    and not isProtectedTarget(player) then
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
            and Theme.negative
            or ((role == "Sheriff" or role == "Hero")
                and Theme.accent
                or Theme.positive),
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

local function disconnectGunFiredObserver(): ()
    disconnectFeatureConnection("MM2GunFired")
    state.mm2ShotFeedback.gunFiredConnected = false
end

registerMM2Roles()

state.mm2Core = {
    settings = mm2Settings,
    mm2Settings = mm2Settings,

    MM2Effects = MM2Effects,
    GunEffects = GunEffects,
    TrapEffects = TrapEffects,
    CoinEffects = CoinEffects,
    clearEffects = clearEffects,
    createMM2Marker = createMM2Marker,
    createMM2Cham = createMM2Cham,

    mm2GameplayRemotes = mm2GameplayRemotes,
    getRoundData = function(): {[any]: any}
        return mm2RoundData
    end,
    isRoundLifecycleActive = function(): boolean?
        return roundLifecycleActive
    end,
    onRoundRoles = onRoundRoles,
    onRoundPhase = onRoundPhase,
    getRoundPhase = function(): string
        return roundPhase
    end,
    roundTimer = roundTimer,
    findRoundTimerPart = findRoundTimerPart,
    readRoundTimerPartSeconds = readRoundTimerPartSeconds,

    getPlayerWeapon = getPlayerWeapon,
    isPlayerAlive = isPlayerAlive,
    findMM2Role = findMM2Role,
    playerFromRoundKey = playerFromRoundKey,
    getRoundRole = getRoundRole,
    getPlayerRole = getPlayerRole,
    getPlayerPerk = getPlayerPerk,
    invalidateRoleCaches = invalidateRoleCaches,
    roundRolesKnown = roundRolesKnown,
    hasActiveRoundRoles = hasActiveRoundRoles,
    findMurderer = findMurderer,
    findSheriff = findSheriff,
    isProtectedTarget = isProtectedTarget,

    findMM2Map = findMM2Map,
    findDroppedGun = findDroppedGun,

    isWeaponPathClear = isWeaponPathClear,
    predictionMath = predictionMath,
    isMotionGrounded = isMotionGrounded,
    motionSamples = motionSamples,
    getFilteredVelocity = getFilteredVelocity,
    getEstimatedLatency = getEstimatedLatency,
    getGunHorizonSeconds = getGunHorizonSeconds,
    getGunTurnDiscount = getGunTurnDiscount,
    getGunTurnRate = getGunTurnRate,
    getGunLeadSensitivity = getGunLeadSensitivity,
    getGunLeadStatus = getGunLeadStatus,
    resetAutoLeadCorrection = resetAutoLeadCorrection,
    getGunOriginCFrame = getGunOriginCFrame,
    trajectoryCalibration = trajectoryCalibration,

    getWeaponServiceModule = getWeaponServiceModule,
    connectGunFiredSignal = connectGunFiredSignal,
    disconnectGunFiredObserver = disconnectGunFiredObserver,
}

cleanupMM2Runtime = function()

    if state.gameRoleProvider == mm2RoleProvider then
        state.gameRoleProvider = nil
    end
    if state.gameTargetProvider == mm2TargetProvider then
        state.gameTargetProvider = nil
    end
    trajectoryCalibration:destroy()
    stopLeadTracking()
    disconnectGunFiredObserver()
    state.mm2ShotFeedback.hide()
    for player: Player, _ in pairs(roleWatchers) do
        unwatchPlayer(player)
    end
    table.clear(roleIndex.roles)
    for _, connectionName: string in ipairs({
        "MM2PlayerDataChanged",
        "MM2TimerTrackerStart",
        "MM2TimerTrackerEnd",
        "MM2RoundPhase",
        "MM2RoundClock",
        "MM2RoleWatchAdded",
        "MM2RoleWatchRemoving",
        "MM2RoleTagAddedWeapon_Knife",
        "MM2RoleTagRemovedWeapon_Knife",
        "MM2RoleTagAddedWeapon_Gun",
        "MM2RoleTagRemovedWeapon_Gun",
    }) do
        disconnectFeatureConnection(connectionName)
    end
    state.isProtectedTarget = function(player: Player?): boolean
        return player == nil or player == LocalPlayer
    end
    table.clear(roundRolesListeners)
    table.clear(roundPhaseListeners)
    state.mm2Core = nil
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
