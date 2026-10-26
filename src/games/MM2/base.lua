local Module = {
    Name = "MM2",
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
    shootMode = "Manual",
    shootWallCheck = true,
    shootRaw = false,
    silentAim = false,
    shootKey = Enum.KeyCode.Unknown,
    shootTarget = "",
    showMissCooldown = false,
    predictionRtt = 0.08,
    silentSweep = 0.5,

    -- Front is the maintained silent construction. Experimental spawn and
    -- sweep controls are internal calibration inputs, not ordinary menu rows.
    silentSpawn = "Front",
    getGunKey = Enum.KeyCode.Unknown,
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
    coinTransparency = 0.35,
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
-- Returns (clear, blocker). `blocker` describes the part that stopped the ray
-- (or the last transparent part that was skipped) so the caller can record what
-- the server disagreed about instead of guessing.
local function isWeaponPathClear(origin: Vector3, endpoint: Vector3, target: Model?, strict: boolean?, options: {ignoreTarget: boolean?, requireTarget: boolean?}?): (boolean, any?)
    local direction: Vector3 = endpoint - origin
    if direction.Magnitude < 0.05 then return true, nil end
    local excluded: {Instance} = {}
    if LocalPlayer.Character then table.insert(excluded, LocalPlayer.Character) end
    -- Projectile endpoints are future poses: the target's present body must
    -- not hide a wall farther along the predicted segment. Hitscan is unchanged.
    if options and options.ignoreTarget and target then table.insert(excluded, target) end
    for _, object: Instance in ipairs(CollectionService:GetTagged("WeaponPassthrough")) do
        table.insert(excluded, object)
    end
    local params: RaycastParams = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    for _ = 1, 32 do
        params.FilterDescendantsInstances = excluded
        local hit: RaycastResult? = workspace:Raycast(origin, direction, params)
        if not hit then return not (options and options.requireTarget == true), nil end
        if target and hit.Instance:IsDescendantOf(target) then return true, nil end
        -- The gun uses the game's rule verbatim: every fully transparent part
        -- is skipped. With strict (knife, and the second gun pass) only
        -- transparent parts that cannot collide are skipped; an invisible
        -- solid barrier stops the ray.
        local part: Instance = hit.Instance
        local info: any = {
            name = nil,
            className = nil,
            transparency = nil,
            canCollide = nil,
            distance = nil,
            skipped = false,
        }
        pcall(function(): ()
            info.name = string.sub(part:GetFullName(), 1, 160)
            info.className = part.ClassName
            local hitPosition: any = (hit :: any).Position
            if hitPosition then
                info.distance = (hitPosition - origin).Magnitude
            end
        end)
        if part:IsA("BasePart") then
            info.transparency = part.Transparency
            info.canCollide = part.CanCollide
        end
        if part:IsA("BasePart") and part.Transparency == 1
            and (not strict or part.CanCollide == false) then
            info.skipped = true
            table.insert(excluded, part)
        else
            return false, info
        end
    end
    return false, { name = "raycast budget", skipped = false } -- conservative
end

-- What the ray meets when nothing is skipped. Recorded on every allowed
-- shot, not only on refusals: five shots of the v61 session passed every check
-- and still stopped 24-56 studs short of the aim, and without this there is no
-- way to tell whether transparent geometry was in the way.
local function describeRayHit(origin: Vector3, endpoint: Vector3, target: Model?): any
    local direction: Vector3 = endpoint - origin
    if direction.Magnitude < 0.05 then
        return nil
    end
    local excluded: {Instance} = {}
    if LocalPlayer.Character then
        table.insert(excluded, LocalPlayer.Character)
    end
    for _, object: Instance in ipairs(CollectionService:GetTagged("WeaponPassthrough")) do
        table.insert(excluded, object)
    end
    local params: RaycastParams = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    params.FilterDescendantsInstances = excluded
    local hit: RaycastResult? = workspace:Raycast(origin, direction, params)
    if not hit then
        return nil
    end
    local part: Instance = hit.Instance
    local info: any = {
        onTarget = target ~= nil and part:IsDescendantOf(target),
    }
    pcall(function(): ()
        info.name = string.sub(part:GetFullName(), 1, 160)
        info.className = part.ClassName
        local position: any = (hit :: any).Position
        if position then
            info.distance = (position - origin).Magnitude
        end
    end)
    if part:IsA("BasePart") then
        info.transparency = part.Transparency
        info.canCollide = part.CanCollide
    end
    return info
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

local function hasValidRoundRoleData(dataTable: any): boolean
    if type(dataTable) ~= "table" then
        return false
    end
    for _, entry: any in pairs(dataTable) do
        if type(entry) == "table" and entry.Dead ~= true then
            local role: any = entry.Role
            if role == "Murderer"
                or role == "Sheriff"
                or role == "Hero"
                or role == "Innocent" then
                return true
            end
        end
    end
    return false
end

local function requestRoleRefresh(force: boolean?): ()
    if not mm2RoleRemote
        or (not force and roleRefreshRunning)
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
            and type(result) == "table"
            and (roundLifecycleActive ~= false or hasValidRoundRoleData(result)) then
            if hasValidRoundRoleData(result) and roundLifecycleActive == nil then
                roundLifecycleActive = true
            end
            mm2RoundData = result
            invalidateRoleCaches()
            if rebuildRoleIndex then
                rebuildRoleIndex()
            end
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
    return string.find(string.lower(tostring(name)), "lobby", 1, true) ~= nil
end

local function isLobbyModel(object: Instance): boolean
    if isLobbyName(object.Name) then
        return true
    end
    if object:FindFirstChild("VotePad1")
        or object:FindFirstChild("VotePads")
        or object:FindFirstChild("VoteIcons") then
        return true
    end
    return false
end

local function isMM2MapModel(object: Instance): boolean
    if not object:IsA("Model") or isLobbyModel(object) then
        return false
    end
    for _, containerName: string in ipairs(MM2_MAP_COIN_CONTAINERS) do
        if object:FindFirstChild(containerName) then
            return true
        end
    end
    if object:FindFirstChild("GunDrop") then
        return true
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
            and not isLobbyModel(object)
            and object:FindFirstChild("Spawns") then
            return object
        end
    end
    return nil
end

local function findMM2Map(): Instance?
    local cached: Instance? = mm2MapCache.map
    if cached and cached.Parent == workspace and isMM2MapModel(cached) then
        return cached
    end
    if os.clock() - mm2MapCache.at < 0.1 then
        return (cached and cached.Parent == workspace) and cached or nil
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

    for _, taggedDrop: Instance in ipairs(CollectionService:GetTagged("GunDrop")) do
        if taggedDrop:IsDescendantOf(workspace)
            and (taggedDrop:IsA("Model") or taggedDrop:IsA("BasePart")) then
            return taggedDrop :: any
        end
    end

    for _, object: Instance in ipairs(workspace:GetChildren()) do
        if object:IsA("Model") or object:IsA("Folder") then
            local childDrop: Instance? = object:FindFirstChild("GunDrop")
            if childDrop and (childDrop:IsA("Model") or childDrop:IsA("BasePart")) then
                return childDrop :: any
            end
        end
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

    if os.clock() - lastGunSweepAt < 1.5 then
        return nil
    end
    lastGunSweepAt = os.clock()
    local deepCandidate: Instance? = (map and map:FindFirstChild("GunDrop", true))
        or workspace:FindFirstChild("GunDrop", true)
    if deepCandidate
        and (deepCandidate:IsA("Model") or deepCandidate:IsA("BasePart")) then
        return deepCandidate :: any
    end
    return nil
end

local function findDroppedGun(): (Model | BasePart)?
    local cached: (Model | BasePart)? = droppedGunCache.gun
    if cached and cached.Parent and cached:IsDescendantOf(workspace) then
        return cached
    end
    -- Negative results are only held for ~3 frames. The old 0.4 s
    -- cache meant a gun dropped just after a scan stayed invisible
    -- to Auto Get Gun for almost half a second; the cheap checks
    -- (direct GunDrop child, Weapon_Gun tags, workspace children)
    -- run first every call and the expensive descendant sweep keeps
    -- its own 3 s gate below.
    if os.clock() - droppedGunCache.at < 0.05 then
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
            or adornee:FindFirstChild("HumanoidRootPart")
            or adornee:FindFirstChild("Handle", true)
            or adornee:FindFirstChildWhichIsA("BasePart", true))
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
        ReplacesTeams = true,
        DeadRoles = {"Dead"},
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

local primeRoundState: () -> ()
local setRoundPhase: (string, string) -> ()
local lastPhase: string = "unknown"

if mm2GameplayRemotes then
    local playerDataChanged = mm2GameplayRemotes:FindFirstChild("PlayerDataChanged")
    if playerDataChanged and playerDataChanged:IsA("RemoteEvent") then
        featureConnections.MM2PlayerDataChanged = playerDataChanged.OnClientEvent:Connect(function(newData)
            if type(newData) == "table" and hasValidRoundRoleData(newData) then
                roundLifecycleActive = true
                mm2MapCache.at = -math.huge
                for key: any, value: any in pairs(newData) do
                    mm2RoundData[key] = value
                end
                lastRoleRefreshAt = os.clock()
                invalidateRoleCaches()
                if rebuildRoleIndex then
                    rebuildRoleIndex()
                end
                if setRoundPhase and findMM2Map() then
                    lastPhase = "map"
                    setRoundPhase("map", "PlayerDataChanged")
                end
            elseif type(newData) ~= "table" or roundLifecycleActive == false then
                mm2RoundData = {}
                invalidateRoleCaches()
            else
                for key: any, value: any in pairs(newData) do
                    mm2RoundData[key] = value
                end
                lastRoleRefreshAt = os.clock()
                invalidateRoleCaches()
                if rebuildRoleIndex then
                    rebuildRoleIndex()
                end
            end
        end)
    end

    local roleSelect = mm2GameplayRemotes:FindFirstChild("RoleSelect")
    if roleSelect and roleSelect:IsA("RemoteEvent") then
        featureConnections.MM2RoleSelect = roleSelect.OnClientEvent:Connect(function(localRole: any)
            roundLifecycleActive = true
            mm2MapCache.at = -math.huge
            if type(localRole) == "string"
                and (localRole == "Murderer"
                    or localRole == "Sheriff"
                    or localRole == "Hero"
                    or localRole == "Innocent") then
                local existing: any = mm2RoundData[LocalPlayer.Name]
                if type(existing) ~= "table" then
                    existing = {
                        Name = LocalPlayer.Name,
                        UserId = LocalPlayer.UserId,
                    }
                    mm2RoundData[LocalPlayer.Name] = existing
                end
                existing.Role = localRole
            end
            invalidateRoleCaches()
            if rebuildRoleIndex then
                rebuildRoleIndex()
            end
            if primeRoundState then
                primeRoundState()
            end
            if setRoundPhase then
                lastPhase = "map"
                setRoundPhase("map", "RoleSelect")
            end
        end)
    end

    for _, remoteName: string in ipairs({"ShowRoleSelect", "ShowRoleSelectNew"}) do
        local showRole = mm2GameplayRemotes:FindFirstChild(remoteName)
        if showRole and showRole:IsA("RemoteEvent") then
            featureConnections["MM2" .. remoteName] = showRole.OnClientEvent:Connect(function()
                roundLifecycleActive = true
                mm2MapCache.at = -math.huge
                invalidateRoleCaches()
                if primeRoundState then
                    primeRoundState()
                end
                if setRoundPhase then
                    lastPhase = "map"
                    setRoundPhase("map", remoteName)
                end
            end)
        end
    end
end

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
            if not duration or duration <= 0 then
                mm2RoundData = {}
                sessionRoundActive = false
            end
            invalidateRoleCaches()
            roundLifecycleActive = duration ~= nil and duration > 0
            roleRefreshGeneration += 1
            if duration and duration > 0 then
                mm2MapCache.at = -math.huge
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
        if isLobbyName(object.Name) or isLobbyModel(object) then
            return object
        end
    end
    return nil
end

local function isRootNearLobby(root: BasePart, lobby: Instance): boolean
    local okRoot: boolean, rootPos: any = pcall(function(): any
        return root.Position
    end)
    if not okRoot or typeof(rootPos) ~= "Vector3" then
        return false
    end
    local votePads: Instance? = lobby:FindFirstChild("VotePads", true)
    local refPart: BasePart? = nil
    if votePads then
        refPart = votePads:FindFirstChildWhichIsA("BasePart", true)
    end
    if not refPart then
        local spawns: Instance? = lobby:FindFirstChild("Spawns", true)
        if spawns then
            refPart = spawns:FindFirstChildWhichIsA("BasePart", true)
        end
    end
    if not refPart then
        refPart = lobby:FindFirstChildWhichIsA("BasePart", true)
    end
    if refPart then
        local okDist: boolean, dist: any = pcall(function(): any
            return (rootPos - refPart.Position).Magnitude
        end)
        if okDist and type(dist) == "number" and dist <= 350 then
            return true
        end
    end
    return false
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
    if lobby and (root:IsDescendantOf(lobby) or isRootNearLobby(root, lobby)) then
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
        for _, delay: number in ipairs({0.05, 0.15, 0.3, 0.5, 0.8, 1.2, 2.0, 3.0}) do
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
if lastPhase == "map" then
    roundLifecycleActive = true
    primeRoundState()
end
featureConnections.MM2RoundPhase = TaskManager:Connect(function(deltaTime: number): ()
    phaseElapsed += deltaTime
    if phaseElapsed < 0.05 then
        return
    end
    phaseElapsed = 0
    local phase: string = detectRoundPhase()
    if phase == lastPhase then
        return
    end
    lastPhase = phase
    if phase == "map" then
        if not hasValidRoundRoleData(mm2RoundData) then
            mm2RoundData = {}
        end
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

local lastLatencyReadAt: number = -math.huge

-- Two engine readings of the same path. They disagree: in the 2026-10-18
-- session GetNetworkPing read 314/342 ms on two shots whose measured
-- confirmation echo was 152/164 ms, and it read 241 ms at session start when
-- Data Ping read 130 and the echo came back in 144. Across 17 recorded shots
-- Data Ping was within 30 ms of the echo in 12, GetNetworkPing in 3.
-- This legacy smoothed fallback takes the lower of the two: over-leading is
-- the failure this data shows, and Prediction's median rejects a one-off dip.
-- The live predictor itself prefers Data Ping when both readings are present.
local function readLatencyReadings(): (number?, number?)
    local engine: number? = nil
    local data: number? = nil
    pcall(function(): ()
        local direct: any = (LocalPlayer :: any).GetNetworkPing
        if type(direct) == "function" then
            local okDirect: boolean, seconds: any = pcall(direct, LocalPlayer)
            if okDirect and predictionMath.finite(seconds)
                and (seconds :: number) > 0.001 and (seconds :: number) <= 2 then
                engine = seconds :: number
            end
        end
        local network: Instance? = Stats:FindFirstChild("Network")
        local serverItems: Instance? = network
            and network:FindFirstChild("ServerStatsItem")
        local pingItem: any = serverItems and serverItems:FindFirstChild("Data Ping")
        if pingItem and type(pingItem.GetValue) == "function" then
            local pingMilliseconds: number? = tonumber(pingItem:GetValue())
            if predictionMath.finite(pingMilliseconds)
                and pingMilliseconds >= 10 and pingMilliseconds <= 2000 then
                data = pingMilliseconds / 1000
            end
        end
    end)
    return engine, data
end

local function getEstimatedLatency(): number
    local now: number = os.clock()
    if now - lastLatencyReadAt < 0.1 then
        return math.clamp(mm2Settings.predictionRtt, 0.02, 0.6)
    end
    local elapsed: number = now - lastLatencyReadAt
    lastLatencyReadAt = now
    local measuredRtt: number = mm2Settings.predictionRtt
    pcall(function(): ()
        local engine: number?, data: number? = readLatencyReadings()
        local lower: number? = nil
        if engine and data then
            lower = math.min(engine, data)
        else
            lower = engine or data
        end
        if lower then
            measuredRtt = lower
        end
    end)
    -- Time-based smoothing: sampling frequency must not change the RTT.
    -- The upper bound covers the 400-500 ms sessions in TestingStuff; the
    -- old 0.3 cap silently under-led every high-ping shot by 200+ ms.
    local alpha: number = 1 - math.exp(-math.min(elapsed, 1) / 0.5)
    mm2Settings.predictionRtt += (measuredRtt - mm2Settings.predictionRtt) * alpha

    return math.clamp(
        mm2Settings.predictionRtt,
        0.02,
        0.6
    )
end

local trajectoryCalibration: any = nil

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
    -- The movement window that ended at the shot. `dt` is negative (seconds
    -- before the shot), unlike TrajectoryPoint's non-negative `dt`, so an
    -- alternative predictor can be replayed from the same inputs offline.
    type HistoryPoint = {
        dt: number,
        position: {number},
        velocity: {number},
        humanoidState: string,
        grounded: boolean,
        -- The replicated control input. It leads the velocity on a turn, so
        -- recording it lets an offline replay test an input-based turn instead
        -- of needing another session.
        moveDirection: {number}?,
        -- Offset from the root to the part the aim fell on. The v64 misses
        -- passed 0.2-0.3 studs below the root, which is under the torso: a
        -- replay needs this to test aiming at the torso instead of the root.
        aimOffset: {number}?,
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
        targetHistory: {HistoryPoint},
        lastTrajectorySampleAt: number,
        confirmedAt: number?,
        latencyMs: number?,
        confirmedEndpoint: Vector3?,
        confirmedHitTarget: boolean?,
        -- Everything below exists so a saved session can answer "did the shot
        -- land, where, and when" without a second session: the server-clock
        -- round trip, the part that was actually hit and its size, and the
        -- target's health before and after.
        serverActivatedAt: number?,
        serverConfirmedAt: number?,
        shotMode: string?,
        silentSpawn: string?,
        confirmedServerOrigin: Vector3?,
        confirmedHitPart: string?,
        confirmedHitPartPosition: Vector3?,
        confirmedHitPartSize: Vector3?,
        rootAtConfirmation: {[string]: any}?,
        lastSeenPosition: Vector3?,
        targetHealthAtAim: number?,
        targetHealthAtConfirmation: number?,
        targetHealthAfter: number?,
        targetHealthDropAt: number?,
        targetHealthDropServerTime: number?,
        targetDiedAt: number?,
        targetDiedServerTime: number?,
        healthConnection: RBXScriptConnection?,
        samplingStoppedAt: number?,
        samplingStoppedReason: string?,
        trajectoryCapped: boolean?,
        rttEngineAtConfirmation: number?,
        rttDataAtConfirmation: number?,
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
        targetHistory: {HistoryPoint},
        lastTrajectorySampleAt: number,
        serverActivatedAt: number?,
        samplingStoppedAt: number?,
        samplingStoppedReason: string?,
        trajectoryCapped: boolean?,
        lastSeenPosition: Vector3?,
        targetHealthAtAim: number?,
        targetHealthAfter: number?,
        healthConnection: RBXScriptConnection?,
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
        targetHistory: {HistoryPoint},
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
        targetHistory: {HistoryPoint}?,
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
        blockedName: string?,
        blockedTransparency: number?,
        blockedCanCollide: boolean?,
        blockedSkipped: boolean?,
        blockedDistance: number?,
        rttEngine: number?,
        rttData: number?,
        occluder: any?,
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
        -- Direct endpoint error of our own predicted point, in studs,
        -- measured against where the target really was at the scoring
        -- instant. This is the number the accuracy question needs; it
        -- used to require an offline replay of aim + trajectory.
        predictionErrorSamples: number,
        predictionErrorMedianStuds: number?,
        predictionErrorMeanStuds: number?,
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
    -- 30 Hz could not resolve a 0.02 s horizon, and the offline question is
    -- exactly how the target moved in the last tens of milliseconds.
    local TRAJECTORY_SAMPLE_HZ: number = 60
    -- 2.5 s of pending life at 60 Hz needs 150; the margin covers a slow
    -- frame without silently truncating the tail.
    local MAX_TRAJECTORY_POINTS: number = 200
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
        sessionGunHitTarget = 0,
        sessionGunKills = 0,
        sessionKnifeAttempts = 0,
        sessionKnifeConfirmed = 0,
        pendingGuns = {} :: {PendingGun},
        lastBlockedAt = 0,
        evictedEvents = 0,
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

    -- Health is the only client-visible proof that a shot did damage. The
    -- `hitPart` of GunFired says a ray touched the target; a drop says the
    -- server applied it. Both are recorded, with both clocks, per shot.
    local function watchPendingHealth(pending: any, target: Player?): ()
        pending.targetHealthAtAim = nil
        pending.targetHealthAfter = nil
        pending.targetHealthDropAt = nil
        pending.targetDiedAt = nil
        local character: Model? = target and target.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return
        end
        pending.targetHealthAtAim = humanoid.Health
        if pending.healthConnection then
            pending.healthConnection:Disconnect()
            pending.healthConnection = nil
        end
        pending.healthConnection = humanoid.HealthChanged:Connect(
            function(health: number): ()
                if not predictionMath.finite(health) then
                    return
                end
                if pending.targetHealthAfter == nil
                    or health < pending.targetHealthAfter then
                    pending.targetHealthAfter = health
                    if pending.targetHealthDropAt == nil then
                        pending.targetHealthDropAt = os.clock()
                        pending.targetHealthDropServerTime =
                            workspace:GetServerTimeNow()
                    end
                    if health <= 0 and pending.targetDiedAt == nil then
                        pending.targetDiedAt = os.clock()
                        pending.targetDiedServerTime =
                            workspace:GetServerTimeNow()
                    end
                end
            end
        )
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
                    and now - pending.lastTrajectorySampleAt
                        >= 1 / TRAJECTORY_SAMPLE_HZ then
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
                    if point then
                        if #pending.targetTrajectory < MAX_TRAJECTORY_POINTS then
                            table.insert(pending.targetTrajectory, point)
                        else
                            pending.trajectoryCapped = true
                        end
                    elseif pending.samplingStoppedAt == nil then
                        -- The only two ways this is nil: the character is gone
                        -- or the humanoid is dead. Either way it is the reason
                        -- a saved trajectory ends early, so it gets written
                        -- down instead of being guessed at later.
                        pending.samplingStoppedAt = now
                        pending.samplingStoppedReason = target
                                and "target-dead-or-missing"
                            or "target-left"
                    end
                    if target then
                        local root: BasePart? = getTargetRoot(target)
                        if root then
                            pending.lastSeenPosition = root.Position
                        end
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
            -- A session that spams the knife (158 authored events on
            -- 2026-10-18) evicted the gun records before their confirmations
            -- could be matched, so a shot could no longer be scored. The knife
            -- noise goes first; the gun record carries the settings.
            local victim: number = 1
            for index: number = 1, #runtime.events do
                local candidate: CalibrationEvent = runtime.events[index]
                if candidate.kind == "knife" and candidate.phase == "authored" then
                    victim = index
                    break
                end
            end
            table.remove(runtime.events, victim)
            runtime.evictedEvents = (runtime.evictedEvents or 0) + 1
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

    -- Pre-shot movement window, straight from the predictor's ring buffer.
    -- Without it a second predictor can only be scored on the shot it took;
    -- with it the same slot can be replayed from the inputs.
    local function captureTargetHistory(
        player: Player?,
        now: number
    ): {HistoryPoint}
        local points: {HistoryPoint} = {}
        if not player or not state.mm2Prediction
            or type(state.mm2Prediction.getHistory) ~= "function" then
            return points
        end
        local ok: boolean, history: any, age: any = pcall(
            state.mm2Prediction.getHistory,
            player,
            0.6
        )
        if not ok or type(history) ~= "table" then
            return points
        end
        -- `at` is relative to the newest predictor sample and `age` is how old
        -- that sample was at the shot. Clocks in the two modules do not share
        -- an epoch, so the subtraction happens on the predictor's side only.
        local sampleAge: number = predictionMath.finite(age) and age or 0
        for _, sample: any in ipairs(history) do
            if #points >= 36 then
                break
            end
            local position: any = sample.position
            local velocity: any = sample.velocity
            if typeof(position) == "Vector3" and typeof(velocity) == "Vector3" then
                local move: any = sample.moveDirection
                local offset: any = sample.aimOffset
                table.insert(points, {
                    dt = (sample.at or 0) - sampleAge,
                    position = {position.X, position.Y, position.Z},
                    velocity = {velocity.X, velocity.Y, velocity.Z},
                    humanoidState = tostring(sample.state or "Running"),
                    grounded = sample.grounded == true,
                    moveDirection = typeof(move) == "Vector3"
                            and {move.X, move.Y, move.Z}
                        or nil,
                    aimOffset = typeof(offset) == "Vector3"
                            and {offset.X, offset.Y, offset.Z}
                        or nil,
                })
            end
        end
        return points
    end

    local function trackConnection(connection: RBXScriptConnection): ()
        table.insert(runtime.connections, connection)
    end

    compactPending = function(queue: {any}, now: number): ()
        local function drop(index: number): ()
            local entry: any = queue[index]
            if entry and entry.healthConnection then
                pcall(function(): ()
                    (entry.healthConnection :: RBXScriptConnection):Disconnect()
                end)
                entry.healthConnection = nil
            end
            table.remove(queue, index)
        end
        while #queue > 0 and now - queue[1].activatedAt > MAX_PENDING_AGE do
            drop(1)
        end
        while #queue > 12 do
            drop(1)
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
    local function endpointErrorStats(): (number, number?, number?)
        local values: {number} = {}
        for _, ev in ipairs(runtime.events) do
            if ev.kind == "gun"
                and predictionMath.finite(ev.endpointErrorStuds) then
                table.insert(values, ev.endpointErrorStuds)
            end
        end
        local mean: number? = nil
        if #values > 0 then
            local total: number = 0
            for _, value in ipairs(values) do
                total += value
            end
            mean = total / #values
        end
        return #values, median(values), mean
    end

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
        local errCount: number, errMedian: number?, errMean: number? =
            endpointErrorStats()
        estimatesCache = {
            predictionErrorSamples = errCount,
            predictionErrorMedianStuds = errMedian,
            predictionErrorMeanStuds = errMean,
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
                silentSpawn = mm2Settings.silentSpawn,
                silentAim = mm2Settings.silentAim,
                silentSweep = mm2Settings.silentSweep,
                wallCheck = mm2Settings.shootWallCheck,
                autoLead = state.mm2Prediction
                    and state.mm2Prediction.settings.autoLead
                    or true,
                leadOffsetSeconds = state.mm2Prediction
                    and state.mm2Prediction.settings.extraLead
                    or 0,
                replicationInterpolationSeconds = state.mm2Prediction
                    and state.mm2Prediction.settings.interpolation
                    or nil,
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
                gunConfirmationMeaning = "matched GunFired signal; hitTarget means the ray reached the target, died means the humanoid reached 0 health",
                evictedEvents = runtime.evictedEvents,
                healthMeaning = "client-observed Humanoid.Health; healthDropServerTime is GetServerTimeNow at the drop",
                knifeConfirmationMeaning = "observed projectile with valid speed; not an impact",
                rawKnifeActivations = runtime.rawKnifeActivations,
                unmatchedGunSignals = runtime.unmatchedGunSignals,
                stabAttempts = runtime.sessionStabAttempts,
                elapsedSeconds = os.clock() - runtime.startedAt,
                predictionError = (function(): {[string]: any}
                    local ok: boolean, n: any, med: any, mean: any =
                        pcall(endpointErrorStats)
                    return {
                        samples = ok and n or 0,
                        medianStuds = ok and med or nil,
                        meanStuds = ok and mean or nil,
                        scope = "own predicted point vs target at scoring instant, confirmed gun shots",
                    }
                end)(),
                gunByMode = (function(): {[string]: any}
                    local modes: {[string]: any} = {}
                    if type(runtime.events) == "table" then
                        for _, ev in ipairs(runtime.events) do
                            if ev.kind == "gun" then
                                if ev.phase == "authored" then
                                    local mode: string = type(ev.settings) == "table"
                                            and tostring(ev.settings.mode or "?")
                                        or "?"
                                    local row: any = modes[mode]
                                        or {attempts = 0, confirmed = 0, hits = 0, kills = 0}
                                    row.attempts += 1
                                    modes[mode] = row
                                elseif ev.phase == "confirmation" then
                                    local mode: string =
                                        tostring(ev.shotMode or "?")
                                    local row: any = modes[mode]
                                        or {attempts = 0, confirmed = 0, hits = 0, kills = 0}
                                    row.confirmed += 1
                                    if ev.hitTarget then row.hits += 1 end
                                    if ev.died then row.kills += 1 end
                                    modes[mode] = row
                                end
                            end
                        end
                    end
                    return modes
                end)(),
                gunAttempts = runtime.sessionGunAttempts,
                gunConfirmed = runtime.sessionGunConfirmed,
                gunHitTarget = runtime.sessionGunHitTarget,
                gunKills = runtime.sessionGunKills,
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

    -- Where the target really was when the server scored the shot, compared
    -- with the point we aimed at, projected on the target's own horizontal
    -- velocity. That projection is the lead error in seconds: positive means
    -- the target was ahead of our aim (we under-led), negative means we led too
    -- far. The server scores roughly one way into the measured round trip, so
    -- the target's root is interpolated between the newest pre-shot sample and
    -- the root captured at confirmation.
    local function measureLeadErrorSeconds(pending: PendingGun): number?
        local history: {HistoryPoint} = pending.targetHistory or {}
        local newest: HistoryPoint? = history[#history]
        local aim: Vector3? = pending.requestedAim
        local latencyMs: any = pending.latencyMs
        local confirmation: any = pending.rootAtConfirmation
        if not newest or not aim or not confirmation then
            return nil
        end
        if not predictionMath.finite(latencyMs) or latencyMs <= 0
            or latencyMs > 1200 then
            return nil
        end
        if not predictionMath.finite(pending.activatedAt) then
            return nil
        end
        local beforeAt: number = pending.activatedAt + (newest.dt or 0)
        local afterAt: number = pending.confirmedAt
                and pending.confirmedAt
            or (pending.activatedAt + latencyMs / 1000)
        if not predictionMath.finite(afterAt) or afterAt <= beforeAt then
            return nil
        end
        -- Score where the server actually scores. The saved sessions
        -- separate hits from misses at the CONFIRMATION instant (a
        -- full round trip after firing), not half-way: scoring at
        -- activatedAt + latency/2 measured the aim ~55 ms AHEAD and
        -- taught the feedback loop a capped -60 ms correction, which
        -- then fought the (correct) full-transport lead on every
        -- shot -- the recorded cause of the chronic under-lead.
        local scoringAt: number = pending.activatedAt + latencyMs / 1000
        local alpha: number = math.clamp(
            (scoringAt - beforeAt) / (afterAt - beforeAt),
            0,
            1
        )
        local p0: {number}? = newest.position
        local p1: {number}? = confirmation.position
        if type(p0) ~= "table" or type(p1) ~= "table"
            or #p0 < 3 or #p1 < 3 then
            return nil
        end
        local rootX: number = p0[1] + (p1[1] - p0[1]) * alpha
        local rootY: number = p0[2] + (p1[2] - p0[2]) * alpha
        local rootZ: number = p0[3] + (p1[3] - p0[3]) * alpha
        local offset: {number}? = newest.aimOffset
        if type(offset) == "table" and #offset >= 3 then
            rootX += offset[1]
            rootY += offset[2]
            rootZ += offset[3]
        end
        local velocity: {number}? = newest.velocity
        if type(velocity) ~= "table" or #velocity < 3 then
            return nil
        end
        local vx: number = velocity[1]
        local vz: number = velocity[3]
        local speed: number = math.sqrt(vx * vx + vz * vz)
        -- A target that is not walking has no lead to correct; its aim error is
        -- noise around a stationary body.
        if speed < 3 then
            return nil
        end
        local along: number = ((rootX - aim.X) * vx + (rootZ - aim.Z) * vz) / speed
        -- Anything past this is not a lead error: a respawn, a teleport or the
        -- aim landing on a different player.
        if math.abs(along) > 6 then
            return nil
        end
        return along / speed
    end

    -- Same scoring-instant interpolation as measureLeadErrorSeconds,
    -- but the full 3D distance between the point we aimed at and where
    -- the target's aim point really was -- the direct endpoint error.
    -- No speed gate: a stationary target's error is real information
    -- here (it isolates geometry/origin problems from lead problems).
    local function measureEndpointErrorStuds(pending: PendingGun): number?
        local history: {HistoryPoint} = pending.targetHistory or {}
        local newest: HistoryPoint? = history[#history]
        local aim: Vector3? = pending.requestedAim
        local latencyMs: any = pending.latencyMs
        local confirmation: any = pending.rootAtConfirmation
        if not newest or not aim or not confirmation then
            return nil
        end
        if not predictionMath.finite(latencyMs) or latencyMs <= 0
            or latencyMs > 1200 then
            return nil
        end
        if not predictionMath.finite(pending.activatedAt) then
            return nil
        end
        local beforeAt: number = pending.activatedAt + (newest.dt or 0)
        local afterAt: number = pending.confirmedAt
                and pending.confirmedAt
            or (pending.activatedAt + latencyMs / 1000)
        if not predictionMath.finite(afterAt) or afterAt <= beforeAt then
            return nil
        end
        local scoringAt: number = pending.activatedAt + latencyMs / 1000
        local alpha: number = math.clamp(
            (scoringAt - beforeAt) / (afterAt - beforeAt),
            0,
            1
        )
        local p0: {number}? = newest.position
        local p1: {number}? = confirmation.position
        if type(p0) ~= "table" or type(p1) ~= "table"
            or #p0 < 3 or #p1 < 3 then
            return nil
        end
        local rootX: number = p0[1] + (p1[1] - p0[1]) * alpha
        local rootY: number = p0[2] + (p1[2] - p0[2]) * alpha
        local rootZ: number = p0[3] + (p1[3] - p0[3]) * alpha
        local offset: {number}? = newest.aimOffset
        if type(offset) == "table" and #offset >= 3 then
            rootX += offset[1]
            rootY += offset[2]
            rootZ += offset[3]
        end
        local dx: number = rootX - aim.X
        local dy: number = rootY - aim.Y
        local dz: number = rootZ - aim.Z
        local distance: number = math.sqrt(dx * dx + dy * dy + dz * dz)
        if not predictionMath.finite(distance) or distance > 30 then
            return nil
        end
        return distance
    end

    finalizeGunCapture = function(pending: PendingGun): ()
        if pending.targetDiedAt then
            runtime.sessionGunKills += 1
        end
        if pending.healthConnection then
            pcall(function(): ()
                (pending.healthConnection :: RBXScriptConnection):Disconnect()
            end)
            pending.healthConnection = nil
        end
        -- The echo lives here on purpose. The shot-feedback handler that used
        -- to feed it depends on a connection made when the feature toggles;
        -- the v61 log shows it never fired (echoDelay nil on all 13 shots
        -- despite 9 confirmations). This handler is the one that produced
        -- those 9 confirmations, so it is the reliable place to measure.
        if state.mm2Prediction and type(state.mm2Prediction.noteEcho) == "function"
            and predictionMath.finite(pending.latencyMs)
            and predictionMath.finite(pending.activatedAt) then
            state.mm2Prediction.noteEcho(
                pending.activatedAt,
                pending.activatedAt + pending.latencyMs / 1000
            )
        end
        -- Feed the measured lead error back into the predictor before the
        -- record is written, so the event can show what the next shot used.
        local leadError: number? = measureLeadErrorSeconds(pending)
        if leadError and state.mm2Prediction
            and type(state.mm2Prediction.noteLeadError) == "function" then
            pcall(state.mm2Prediction.noteLeadError, leadError)
        end
        local leadCorrection: number? = nil
        if state.mm2Prediction
            and type(state.mm2Prediction.getLeadCorrection) == "function" then
            local ok: boolean, value: any = pcall(
                state.mm2Prediction.getLeadCorrection
            )
            if ok and predictionMath.finite(value) then
                leadCorrection = value
            end
        end
        local endpointError: number? = measureEndpointErrorStuds(pending)
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
            clock = os.clock(),
            pingMs = pending.pingMs,
            latencyMs = pending.latencyMs,
            targetUserId = pending.targetUserId,
            targetName = pending.targetName,
            targetState = analysis.initialState,
            targetJumped = analysis.jumped,
            targetTrajectory = pending.targetTrajectory,
            targetHistory = #(pending.targetHistory or {}) > 0
                    and pending.targetHistory
                or nil,
            observedDisplacement = analysis.displacement,
            constantVelocityResidual = analysis.constantVelocityResidual,
            horizontalLeadSeconds = analysis.horizontalLeadSeconds,
            verticalLeadSeconds = analysis.verticalLeadSeconds,
            endpoint = pending.confirmedEndpoint
                    and vectorArray(pending.confirmedEndpoint)
                or nil,
            hitTarget = pending.confirmedHitTarget,
            shotMode = pending.shotMode,
            silentSpawn = pending.silentSpawn,
            -- Server-clock round trip: activation to GunFired, both stamped
            -- with GetServerTimeNow. Independent of GetNetworkPing and of the
            -- engine's Data Ping, so it settles which of them the lead needs.
            serverEchoMs = (pending.serverConfirmedAt
                    and pending.serverActivatedAt)
                    and (pending.serverConfirmedAt - pending.serverActivatedAt)
                        * 1000
                or nil,
            -- Anchor for the server-clock axis: every trajectory point carries
            -- its own serverTime, so serverDt = point.serverTime - this.
            serverActivatedAt = pending.serverActivatedAt,
            serverConfirmedAt = pending.serverConfirmedAt,
            serverOrigin = pending.confirmedServerOrigin
                    and vectorArray(pending.confirmedServerOrigin)
                or nil,
            aimOffsetAtFire = (function(): {number}?
                local history: {HistoryPoint} = pending.targetHistory or {}
                local newest: HistoryPoint? = history[#history]
                return newest and newest.aimOffset or nil
            end)(),
            -- Signed lead error measured from this very confirmation, and the
            -- bounded correction the next shot will apply. Both are written in
            -- seconds so a saved session can be replayed and audited without
            -- rerunning the shot.
            leadErrorSeconds = leadError,
            leadCorrectionSeconds = leadCorrection,
            endpointErrorStuds = endpointError,
            trajectoryPoints = #pending.targetTrajectory,
            trajectorySpanSeconds = (
                    #pending.targetTrajectory > 1
                    and (pending.targetTrajectory[#pending.targetTrajectory].dt
                        - pending.targetTrajectory[1].dt)
                )
                or 0,
            trajectoryCapped = pending.trajectoryCapped == true,
            samplingStoppedReason = pending.samplingStoppedReason,
            samplingStoppedAt = pending.samplingStoppedAt,
            rttEngineAtConfirmation = pending.rttEngineAtConfirmation,
            rttDataAtConfirmation = pending.rttDataAtConfirmation,
            aim = pending.requestedAim and vectorArray(pending.requestedAim) or nil,
            origin = pending.origin and vectorArray(pending.origin) or nil,
            hitPart = pending.confirmedHitPart,
            hitPartPosition = pending.confirmedHitPartPosition
                    and vectorArray(pending.confirmedHitPartPosition)
                or nil,
            hitPartSize = pending.confirmedHitPartSize
                    and vectorArray(pending.confirmedHitPartSize)
                or nil,
            rootAtConfirmation = pending.rootAtConfirmation,
            lastSeenPosition = pending.lastSeenPosition
                    and vectorArray(pending.lastSeenPosition)
                or nil,
            healthAtAim = pending.targetHealthAtAim,
            healthAtConfirmation = pending.targetHealthAtConfirmation,
            healthAfter = pending.targetHealthAfter,
            healthDropAt = pending.targetHealthDropAt,
            healthDropServerTime = pending.targetHealthDropServerTime,
            diedAt = pending.targetDiedAt,
            diedServerTime = pending.targetDiedServerTime,
            died = pending.targetDiedAt ~= nil,
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
        -- Recorded at the moment the signal arrives, on the server clock, so
        -- the round trip can be measured without either engine estimate.
        pending.serverConfirmedAt = workspace:GetServerTimeNow()
        pending.confirmedServerOrigin = eventOrigin
        local engineNow: number?, dataNow: number? = readLatencyReadings()
        pending.rttEngineAtConfirmation = engineNow
        pending.rttDataAtConfirmation = dataNow
        if typeof(hitPartValue) == "Instance" then
            pcall(function(): ()
                pending.confirmedHitPart = string.sub(hitPartValue.Name, 1, 80)
                if hitPartValue:IsA("BasePart") then
                    pending.confirmedHitPartPosition = hitPartValue.Position
                    pending.confirmedHitPartSize = hitPartValue.Size
                end
            end)
        end
        if target then
            local root: BasePart? = getTargetRoot(target)
            local humanoid: Humanoid? = getTargetHumanoid(target)
            if root then
                local stateName: string? = nil
                if humanoid then
                    pcall(function(): ()
                        stateName = humanoid:GetState().Name
                    end)
                end
                pending.rootAtConfirmation = {
                    position = vectorArray(root.Position),
                    velocity = vectorArray(root.AssemblyLinearVelocity),
                    state = stateName,
                }
            end
            if humanoid then
                pending.targetHealthAtConfirmation = humanoid.Health
            end
        end
        if latencyMs >= 30 and latencyMs <= 450 then
            table.insert(runtime.freshGunLatency, {at = now, ms = latencyMs})
            if #runtime.freshGunLatency > 24 then table.remove(runtime.freshGunLatency, 1) end
            estimatesAt = -math.huge
        end
        addSample(runtime.gunAcceptance, latencyMs)
        runtime.sessionGunConfirmed += 1
        if hitTarget then
            runtime.sessionGunHitTarget += 1
        end
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
                targetHistory = #track.targetHistory > 0
                        and track.targetHistory
                    or nil,
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
                targetHistory = pending.targetHistory or {},
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

    -- One constructor for every pending shot. The activation observer and the
    -- authored-shot path used to build this table separately, and on
    -- 2026-10-18 the authored copy was missing the health watcher and the
    -- server-clock pair: 13 confirmations, healthAtAim nil on all of them and
    -- no serverEchoMs. Duplicating the record was the bug; there is one now.
    local function beginPendingShot(kind: string, entry: any, target: Player?): any
        local now: number = entry.activatedAt or os.clock()
        entry.activatedAt = now
        entry.serverActivatedAt = workspace:GetServerTimeNow()
        entry.targetUserId = target and target.UserId or entry.targetUserId
        entry.targetName = target and target.Name or entry.targetName
        if entry.targetTrajectory == nil then
            entry.targetTrajectory = {}
            if target then
                local point: TrajectoryPoint? = captureTrajectoryPoint(
                    target,
                    now,
                    entry.pingMs or 0
                )
                if point then
                    table.insert(entry.targetTrajectory, point)
                end
            end
        end
        if entry.targetHistory == nil then
            entry.targetHistory = captureTargetHistory(target, now)
        end
        entry.lastTrajectorySampleAt = entry.lastTrajectorySampleAt or now
        watchPendingHealth(entry, target)
        local queue: {any} = kind == "gun"
                and runtime.pendingGuns
            or runtime.pendingKnives
        table.insert(queue, entry)
        compactPending(queue, now)
        ensureTrajectorySampler()
        return entry
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
                beginPendingShot("gun", {
                    shotId = shotId,
                    attemptCounted = true,
                    tool = tool,
                    activatedAt = now,
                    origin = toolOrigin(tool),
                    requestedAim = requestedAim,
                    pingMs = pingMs,
                    targetTrajectory = targetTrajectory,
                }, target)
            elseif knife then
                runtime.rawKnifeActivations += 1
                beginPendingShot("knife", {
                    shotId = shotId,
                    attemptCounted = false,
                    tool = tool,
                    activatedAt = now,
                    origin = toolOrigin(tool),
                    requestedAim = requestedAim,
                    pingMs = pingMs,
                    targetTrajectory = targetTrajectory,
                }, target)
            end
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

        if not GAME_CHECK.MM2Active then
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

    -- A shot the client refused. Recorded so the blocker that the server
    -- respects (invisible wall, barrier, tagged part) can be identified
    -- instead of being inferred from a miss. Throttled: a held auto-shoot
    -- would otherwise flood the event ring.
    function controller:noteBlockedShot(blocker: any): ()
        if not runtime.active or type(blocker) ~= "table" then
            return
        end
        local now: number = os.clock()
        if now - runtime.lastBlockedAt < 1 then
            return
        end
        runtime.lastBlockedAt = now
        appendEvent({
            kind = "gun",
            phase = "blocked",
            serverTime = workspace:GetServerTimeNow(),
            pingMs = getPingMilliseconds(),
            reason = "wall",
            blockedName = type(blocker.name) == "string" and blocker.name or nil,
            blockedTransparency = tonumber(blocker.transparency),
            blockedCanCollide = blocker.canCollide == true,
            blockedSkipped = blocker.skipped == true,
            blockedDistance = tonumber(blocker.distance),
        })
    end

    function controller:noteAuthoredShot(info: any): ()
        if not runtime.active or type(info) ~= "table" then
            return
        end
        local kind: string = tostring(info.kind or "gun")
        local shotId: string = nextShotId()
        local now: number = os.clock()
        local pingMs: number = getPingMilliseconds()
        local target: Player? =
            info.target and info.target.Character ~= nil and info.target or nil
        -- Captured before the authored event so the record carries the window
        -- the predictor actually had, not a reconstruction.
        local targetHistory: {HistoryPoint} = captureTargetHistory(target, now)
        if kind ~= "stab" then
            appendEvent({kind = kind, shotId = shotId, phase = "authored",
                serverTime = workspace:GetServerTimeNow(), clock = now,
                pingMs = pingMs,
                settings = info.settings, targetName = info.target and info.target.Name or nil,
                targetHistory = #targetHistory > 0 and targetHistory or nil})
        end
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
                targetHistory = #targetHistory > 0 and targetHistory or nil,
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
                beginPendingShot(isGun and "gun" or "knife", {
                    shotId = shotId,
                    attemptCounted = true,
                    tool = authoredTool,
                    shotMode = type(info.settings) == "table"
                            and info.settings.mode
                        or (info.silent and "Silent" or nil),
                    silentSpawn = info.variant,
                    activatedAt = now,
                    origin = info.originPos,
                    requestedAim = info.aimPos,
                    pingMs = pingMs,
                    targetTrajectory = targetTrajectory,
                    targetHistory = targetHistory,
                }, target)
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

    ambiguous: boolean?,
}

state.mm2ShotFeedback = {

    shootActive = false,
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

state.mm2ShotFeedback.queue = function(
    target: Player?,
    gun: Tool?,
    origin: CFrame?,
    aim: CFrame?
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
        -- A single pending slot cannot disambiguate rapid equal-geometry shots.
        -- Exclude these echoes from statistics instead of guessing.
        ambiguous = state.mm2ShotFeedback.pending ~= nil,
        origin = origin.Position,
        aimPosition = aim and aim.Position,
        healthBefore = targetHumanoid and targetHumanoid.Health or 0,
        targetedMurderer = getPlayerRole(target) == "Murderer",
        queuedAt = os.clock(),
    }
    state.mm2ShotFeedback.pending = candidate

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
            -- Disconnection/role changes are UI heuristics, not shot evidence.
            state.mm2ShotFeedback.hide()
        end

        -- Per-spawn outcomes live in the calibration event stream, which also
        -- records the actual geometry and target motion. A second A/B counter
        -- here duplicated that data with a less informative hits/shots label.
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
    local directionMatches: boolean = false
    if eventOriginPosition and endpointPosition and candidate.aimPosition then
        local eventDelta: Vector3 = endpointPosition - eventOriginPosition
        local expectedDelta: Vector3 =
            candidate.aimPosition - candidate.origin
        if eventDelta.Magnitude > 0.05 and expectedDelta.Magnitude > 0.05 then
            directionMatches = eventDelta.Unit:Dot(expectedDelta.Unit) >= 0.965
        end
    end
    if eventTool and not weaponMatches then return end
    if not originMatches or not directionMatches or endpointPosition == nil then return end

    -- Prediction receives the FireServer -> GunFired round trip only from
    -- finalizeGunCapture. Do not feed a second sample from this feedback
    -- queue: the v64 duplicate source read 318 ms against a measured 150 ms
    -- and produced a 381 ms lead that missed by 3.9 studs.

    state.mm2ShotFeedback.pending = nil
    if candidate.ambiguous then return end
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

-- WallCheck for the gun uses the SAME filter as the game's own WeaponService
-- (ClientServices.WeaponService): own character and every
-- "WeaponPassthrough"-tagged instance are excluded, and hits whose part is
-- fully transparent are skipped so the ray continues through them. The first
-- solid surface or other player blocks the shot. The target is excluded while
-- following the segment because the aim point is a future pose; seeing the
-- wall behind it is the point of the check.
local function validateGunShot(target: Player, character: Model, targetCharacter: Model,
    muzzle: Vector3, origin: Vector3, endpoint: Vector3, walls: boolean): (boolean, string?, any?, any?)
    if LocalPlayer.Character ~= character or not target or target == LocalPlayer
        or target.Character ~= targetCharacter or not isPlayerAlive(target)
        or isProtectedTarget(target) or getPlayerRole(target) ~= "Murderer" then
        return false,"Target changed or is not the murderer."
    end
    if roundLifecycleActive == false then return false,"The round is not active." end
    local roundRole = getRoundRole(target)
    if roundRole and roundRole ~= "Murderer" then return false,"Conflicting target role." end
    if not roundRole and not getPlayerWeapon(target,"Knife") and not hasMurdererCollisionGroup(targetCharacter) then
        return false,"No current murderer evidence."
    end
    local ownHumanoid = character:FindFirstChildOfClass("Humanoid")
    if not ownHumanoid or not predictionMath.finite(ownHumanoid.Health) or ownHumanoid.Health <= 0 then return false,"Your character is not alive." end
    if not predictionMath.finite(muzzle.Magnitude) or not predictionMath.finite(origin.Magnitude)
        or not predictionMath.finite(endpoint.Magnitude) or (endpoint-origin).Magnitude < 0.05
        or (endpoint-muzzle).Magnitude < 0.05 then return false,"Invalid shot geometry." end
    if walls then
        local options = {ignoreTarget = true}
        local clear, blocker = isWeaponPathClear(muzzle,endpoint,targetCharacter,nil,options)
        if not clear then
            return false,"A wall or another body blocks the shot.",blocker
        end
        -- Second pass with the conservative rule: a fully transparent part
        -- that still collides is an invisible barrier. The 2026-10-18 session
        -- confirmed nine shots and five of them stopped 24-56 studs short of
        -- the aim while this first pass was clear, so the skipped geometry is
        -- real to the server even though the client's visual filter ignores it.
        local solidClear, solidBlocker = isWeaponPathClear(muzzle,endpoint,targetCharacter,true,options)
        if not solidClear then
            return false,"An invisible wall blocks the shot.",solidBlocker
        end
        if (origin-muzzle).Magnitude > 0.05 then
            local originClear, originBlocker = isWeaponPathClear(origin,endpoint,targetCharacter,nil,options)
            if not originClear then
                return false,"A wall or another body blocks the shot.",originBlocker
            end
            local originSolid, originSolidBlocker = isWeaponPathClear(origin,endpoint,targetCharacter,true,options)
            if not originSolid then
                return false,"An invisible wall blocks the shot.",originSolidBlocker
            end
        end
    end
    -- Even a clear shot records the first thing the untouched ray meets: if it
    -- is a transparent solid short of the aim, the server may stop the bullet
    -- there while every client check passes.
    local occluder: any = nil
    if walls then
        -- Never let the diagnostic decide a shot: it is wrapped, so a failure
        -- here leaves the shot allowed and only loses the extra field.
        pcall(function(): ()
            local first: any = describeRayHit(muzzle, endpoint, targetCharacter)
            local reach: number = (endpoint - muzzle).Magnitude
            if first and not first.onTarget
                and predictionMath.finite(first.distance)
                and first.distance < reach - 0.5 then
                occluder = first
            end
        end)
    end
    return true,nil,nil,occluder
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
    validateGunShot = validateGunShot,
    predictionMath = predictionMath,
    getEstimatedLatency = getEstimatedLatency,
    getLatencyReadings = readLatencyReadings,
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
