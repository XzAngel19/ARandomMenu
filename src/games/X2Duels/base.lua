-- X2 Duels (MVS) native combat and observed session statistics.
--
-- The supplied Cobalt log captures DefaultGun/DefaultKnife native calls,
-- including fire/showBeam and the respawn/death events.
-- Direct CFrame Gun/Knife requests use the captured weapon LocalScripts.
-- Server acceptance, local projectile behaviour and anticheat are unverified.

local Module = {
    Name = "X2Duels",
    PlaceId = 92876937625630,
    Events = {} :: {[string]: any},
    Initialized = false,
    Runtime = nil :: any,
}

local moduleCleanup: () -> () = function(): () end

local function buildX2Duels(runtime: any): ()
    local host: any = getfenv()
    local state: any = runtime.State or host.state
    local rules: any = state and state.x2duelsRules
    assert(type(rules) == "table", "X2Duels Rules must initialize before base")
    assert(type(host.createUniversalFeature) == "function",
        "X2Duels requires the Wurst card API")
    assert(state.mvsdScroll and state.mvsdFeatures,
        "X2Duels requires the existing MVS menu section")

    local players: Players = game:GetService("Players")
    local replicated: ReplicatedStorage = game:GetService("ReplicatedStorage")
    local collection: CollectionService = game:GetService("CollectionService")
    local inputService: UserInputService = game:GetService("UserInputService")
    local runService: RunService = game:GetService("RunService")
    local localPlayer: Player = players.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    -- Both captured 1v1 and 2v2 places ship MatchState. Do not fall back to
    -- stale lobby attributes while that API has not replicated/loaded yet.
    local nativeMatchRequired: boolean = game.PlaceId == 124848751642883
        or game.PlaceId == 92876937625630 or game.PlaceId == 135856908115931
    local services: any = runtime.Services or {}
    local protectedTargets: any = services.protectedTargets
    local activity: any = services.activity
    local notify: any = host.notify or (runtime.Menu and runtime.Menu.Notify)
        or function(): () end

    local settings: {[string]: any} = {
        autoWin = false,
        safePlace = false,
        rematch = false,
        silentAim = false,
        autoShoot = false,
        knifeThrow = false,
        autoKnifeThrow = true,
        knifeBackend = "CFrame",
        killAura = false,
        hitboxes = false,
        teamCheck = true,
        wallCheck = true,
        maxDistance = 1000,
        silentAimPart = "Head",
        silentAimFov = false,
        silentAimFovRadius = 200,
        mouseCompatibility = false,
        silentBackend = "CFrame",
        autoShootBackend = "CFrame",
        raycastCompatibility = false,
        silentKnifePrediction = false,
        silentKnifeSpeed = 100,
        silentKnifeGravity = 0,
        autoShootTeamCheck = true,
        autoShootWallCheck = true,
        autoShootRange = 1000,
        autoShootCooldown = 0,
        knifeTeamCheck = true,
        knifeWallCheck = true,
        knifeRange = 600,
        knifeCooldown = 0,
        knifePrediction = false,
        knifeProjectileSpeed = 78,
        knifeProjectileGravity = 0,
        hitboxTeamCheck = true,
        killAuraTeamCheck = true,
        killAuraWallCheck = true,
        killAuraInterval = 0.12,
        killAuraRange = 12,
        hitboxSize = 10,
    }

    local runtimeState: {[string]: any} = {
        connections = {},
        selected = nil,
        observedRound = false,
        resultsPending = false,
        resultWinCounted = false,
        lastMatchToken = nil,
        roundSerial = 0,
        lastWinRound = -1,
        wins = 0,
        kills = 0,
        loses = 0,
        lastLossRound = -1,
        killVictims = setmetatable({}, {__mode = "k"}),
        sessionStartedAt = os.clock(),
        duelsWon = 0,
        autoWinElapsed = 0,
        autoWinStartedAt = nil,
        autoWinStatus = "Waiting for match",
        safe = nil,
        rematchVoted = false,
        rematchStatus = "Off",
        clientGlobalsModule = nil,
        clientGlobals = nil,
        globalsLoading = false,
        nextStatsAt = 0,
        nextSelectionAt = 0,
        nextGunAt = 0,
        nextKnifeAt = {["Auto Win"] = 0, ["Knife Throw"] = 0},
        nativeAimUntil = 0,
        gunPending = nil,
        autoAimLease = nil,
        autoAimAttempt = 0,
        gunToken = 0,
        silentAttempt = 0,
        redirectCount = 0,
        mouseShot = nil,
        mouseCastModule = nil,
        mouseCastApi = nil,
        mouseCastLoading = false,
        mouseCastGeneration = 0,
        mouseCastWrappers = {},
        knifeBusy = false,
        knifeToken = 0,
        knifePending = nil,
        nextAuraAt = 0,
        nextHitboxAt = 0,
        nextRemoteAt = 0,
        remoteBound = {},
        matchModule = nil,
        matchApi = nil,
        matchLoading = false,
        closed = false,
        seenResultIds = {},
        deadPlayers = setmetatable({}, {__mode = "k"}),
        hitboxes = {},
        suppressRaycast = false,
        cameraOverride = nil,
        rayHookInstalled = false,
        oldRay = nil,
        rayWrapper = nil,
        raycastHookInstalled = false,
        oldRaycast = nil,
        raycastWrapper = nil,
        mouseHookInstalled = false,
        oldMouseIndex = nil,
        mouseIndexWrapper = nil,
        mouseHookKind = nil,
        mouseMetatable = nil,
        mouseReadonly = nil,
    }

    local autoWinCard: any = nil
    local silentAimCard: any = nil
    local autoShootCard: any = nil
    local knifeThrowCard: any = nil
    local autoWinStats: {[string]: any} = {}
    local combatStatusRows: {[string]: any} = {}
    local combatStatuses: {[string]: string} = {}

    local function setCombatStatus(card: any, name: string, text: string?): ()
        if card and type(card.SetStatus) == "function" and card.status ~= text then
            card:SetStatus(text)
        end
        local normalized: string = text or "Off"
        local row: any = combatStatusRows[name]
        if row and combatStatuses[name] ~= normalized then row.set(normalized) end
        combatStatuses[name] = normalized
    end

    local function addCombatStatusRow(card: any, title: string, initial: string): any
        if type(state.addStatOption) ~= "function" then return nil end
        local status: any = state.addStatOption(card, title, initial)
        if status and status.row and status.label then
            -- Stat rows normally reserve only 38% width and truncate. Combat
            -- rejection reasons must be readable on narrow mobile screens.
            local label: any = status.row:FindFirstChild("OptionLabel")
            if label then label.Size = UDim2.new(1, -12, 0, 18) end
            status.row.Size = UDim2.new(1, 0, 0, 76)
            status.label.AnchorPoint = Vector2.new(0, 0)
            status.label.Position = UDim2.fromOffset(8, 20)
            status.label.Size = UDim2.new(1, -16, 0, 54)
            status.label.TextXAlignment = Enum.TextXAlignment.Left
            status.label.TextYAlignment = Enum.TextYAlignment.Top
            status.label.TextWrapped = true
            status.label.TextTruncate = Enum.TextTruncate.None
            if type(card.updateExpandedSize) == "function" then card.updateExpandedSize() end
        end
        return status
    end

    -- MVS stores the real side in Team/TeamName/etc. Role is deliberately
    -- excluded: a role is not proof that two players share a team.
    local TEAM_ATTRIBUTES: {string} = {
        "Team", "TeamName", "TeamId", "TeamID", "Side", "Faction", "MatchTeam",
    }
    local ROLE_COLORS: {[string]: Color3} = {
        Enemy = Color3.fromRGB(255, 82, 82),
        Teammate = Color3.fromRGB(75, 220, 135),
        Unknown = Color3.fromRGB(255, 190, 75),
        Outside = Color3.fromRGB(255, 190, 75),
    }
    local MATCH_ATTRIBUTES: {string} = {
        "Game", "Match", "MatchId", "MatchID",
    }

    local function track(connection: any): ()
        if connection then
            table.insert(runtimeState.connections, connection)
        end
    end

    local function setAimActivity(active: boolean): ()
        if activity and type(activity.set) == "function" then
            pcall(activity.set, "mvsdSilentAim", active)
        end
    end

    local function firstAttribute(player: Player, names: {string}): any
        local containers: {Instance?} = {player, player.Character}
        for _, container: Instance? in ipairs(containers) do
            if container then
                for _, name: string in ipairs(names) do
                    local ok: boolean, value: any = pcall(
                        container.GetAttribute, container, name
                    )
                    if ok and value ~= nil and value ~= "" then
                        return value
                    end
                end
            end
        end
        return nil
    end

    -- In the 1v1 place the game's MatchState reads PlayerMatches and
    -- RunningGames from ClientGlobals; those are not Player attributes. Load
    -- the existing ModuleScript off the boot path because its dependencies can
    -- wait for PlayerGui/replication. While it is present but still loading,
    -- fail closed rather than target using stale lobby attributes.
    local function discoverMatchState(): ()
        local client: Instance? = replicated:FindFirstChild("Client")
        local modules: Instance? = client and client:FindFirstChild("Modules")
        local candidate: Instance? = modules and modules:FindFirstChild("MatchState")
        if candidate and not candidate:IsA("ModuleScript") then candidate = nil end
        if candidate ~= runtimeState.matchModule then
            runtimeState.matchModule = candidate
            runtimeState.matchApi = nil
            runtimeState.matchLoading = false
            runtimeState.selected = nil
        end
        if not candidate or runtimeState.matchApi or runtimeState.matchLoading then
            return
        end
        runtimeState.matchLoading = true
        task.spawn(function(): ()
            local ok: boolean, api: any = pcall(require, candidate)
            if runtimeState.closed or runtimeState.matchModule ~= candidate then return end
            runtimeState.matchLoading = false
            if ok and type(api) == "table"
                and type(api.getGameId) == "function"
                and type(api.getTeamId) == "function" then
                runtimeState.matchApi = api
                runtimeState.selected = nil
                runtimeState.nextSelectionAt = 0
            end
        end)
    end

    -- GameValues.Rematch is the same replicated state used by the game's
    -- Rematch button. Loading it separately cannot stall the menu or targeting.
    local function discoverClientGlobals(): ()
        if not settings.rematch and not runtimeState.rematchVoted then return end
        local client: Instance? = replicated:FindFirstChild("Client")
        local modules: Instance? = client and client:FindFirstChild("Modules")
        local candidate: Instance? = modules and modules:FindFirstChild("ClientGlobals")
        if candidate and not candidate:IsA("ModuleScript") then candidate = nil end
        if candidate ~= runtimeState.clientGlobalsModule then
            runtimeState.clientGlobalsModule = candidate
            runtimeState.clientGlobals = nil
            runtimeState.globalsLoading = false
        end
        if not candidate or runtimeState.clientGlobals or runtimeState.globalsLoading then return end
        runtimeState.globalsLoading = true
        task.spawn(function(): ()
            local ok: boolean, globals: any = pcall(require, candidate)
            if runtimeState.closed or runtimeState.clientGlobalsModule ~= candidate then return end
            runtimeState.globalsLoading = false
            if ok and type(globals) == "table" then runtimeState.clientGlobals = globals end
        end)
    end

    local function matchApiCall(name: string, player: Player): (boolean, any)
        local api: any = runtimeState.matchApi
        local fn: any = api and api[name]
        if type(fn) ~= "function" then return false, nil end
        return pcall(fn, player)
    end

    local function matchToken(player: Player): string?
        if runtimeState.matchModule or nativeMatchRequired then
            local ok: boolean, value: any = matchApiCall("getGameId", player)
            return ok and rules.normalizeToken(value) or nil
        end
        return rules.normalizeToken(firstAttribute(player, MATCH_ATTRIBUTES))
    end

    local function teamToken(player: Player): string?
        if runtimeState.matchModule or nativeMatchRequired then
            local modeOk: boolean, mode: any = matchApiCall("getMode", player)
            if modeOk and rules.normalizeToken(mode) == "ffa" then
                return nil -- FFA is not a shared team; preserve fail-closed safety.
            end
            local ok: boolean, value: any = matchApiCall("getTeamId", player)
            return ok and rules.normalizeTeamToken(value) or nil
        end
        -- Do not fall back to player.Team here. MVS keeps players on a common
        -- Roblox lobby team in some states; that fallback made everyone green.
        local containers: {Instance?} = {player, player.Character}
        for _, container: Instance? in ipairs(containers) do
            if container then
                for _, name: string in ipairs(TEAM_ATTRIBUTES) do
                    local ok: boolean, value: any = pcall(
                        container.GetAttribute, container, name
                    )
                    local token: string? = ok and rules.normalizeTeamToken(value) or nil
                    if token ~= nil then
                        return token
                    end
                end
            end
        end
        return nil
    end

    local function sharesMatch(other: Player): boolean
        local mine: string? = matchToken(localPlayer)
        local theirs: string? = matchToken(other)
        -- With the native API, nil is a known lobby/not-replicated state, not
        -- evidence that two players share a match.
        if runtimeState.matchModule or nativeMatchRequired then
            return mine ~= nil and mine == theirs
        end
        -- Legacy places without MatchState can still use their attributes.
        if mine ~= nil or theirs ~= nil then
            return mine ~= nil and mine == theirs
        end
        return true
    end

    local function isFreeForAll(): boolean
        local ok: boolean, mode: any = matchApiCall("getMode", localPlayer)
        return ok and rules.normalizeToken(mode) == "ffa"
    end

    local function relation(other: Player): string
        if other == localPlayer then
            return "Local"
        end
        if sharesMatch(other) and isFreeForAll() then return "Enemy" end
        return rules.relation(
            teamToken(localPlayer), teamToken(other), sharesMatch(other)
        )
    end

    local function isAlive(player: Player): boolean
        if runtimeState.deadPlayers[player] == true then return false end
        local nativeOk: boolean, nativeDead: any = matchApiCall("isDead", player)
        if nativeOk then
            if nativeDead == true then return false end
        elseif firstAttribute(player, {"Died", "Dead"}) == true then
            return false
        end
        local character: Model? = player.Character
        if not character or not character.Parent then return false end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        return humanoid ~= nil and humanoid.Health > 0
    end

    local function isProtected(player: Player): boolean
        if not protectedTargets or type(protectedTargets.isProtected) ~= "function" then
            return false
        end
        local ok: boolean, protected: any = pcall(
            protectedTargets.isProtected, player
        )
        return ok and protected == true
    end

    local function isTeammate(other: Player?): boolean
        return other ~= nil and other ~= localPlayer and relation(other) == "Teammate"
    end

    local function isEnemy(
        other: Player?, allowTeammates: boolean?, teamCheckOverride: boolean?
    ): boolean
        if not other or other == localPlayer or not isAlive(other)
            or isProtected(other) then
            return false
        end
        local sameGame: boolean = sharesMatch(other)
        if sameGame and isFreeForAll() then return true end
        local checkTeam: boolean = if teamCheckOverride == nil then settings.teamCheck
            else teamCheckOverride
        return rules.isOpponent(
            teamToken(localPlayer), teamToken(other), sameGame,
            checkTeam and allowTeammates ~= true
        )
    end

    local function rootOf(character: Model?): BasePart?
        if not character then
            return nil
        end
        local root: Instance? = character:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then
            return root :: BasePart
        end
        return character.PrimaryPart
    end

    local function targetPartOf(character: Model?, preferred: string?): BasePart?
        if not character then
            return nil
        end
        if preferred == "Body" then
            -- Actual R15/R6 body parts are preferable to an invisible root;
            -- fall back gracefully when a rig has not replicated its torso.
            for _, name: string in ipairs({"UpperTorso", "Torso"}) do
                local part: Instance? = character:FindFirstChild(name)
                if part and part:IsA("BasePart") then return part :: BasePart end
            end
            return rootOf(character)
        end
        local head: Instance? = character:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            return head :: BasePart
        end
        return rootOf(character)
    end

    local function targetRecord(player: Player, preferred: string?): {[string]: any}?
        local character: Model? = player.Character
        local part: BasePart? = targetPartOf(character, preferred)
        if not character or not part then
            return nil
        end
        return {player = player, character = character, part = part}
    end

    local function hasLineOfSight(target: {[string]: any}, from: Vector3?): (boolean, string?)
        local camera: Camera? = currentWorkspace.CurrentCamera
        local localRoot: BasePart? = rootOf(localPlayer.Character)
        local origin: Vector3? = from or (if camera then camera.CFrame.Position
            elseif localRoot then localRoot.Position else nil)
        if not origin then
            return false, "Wall Check unavailable: no shot origin."
        end
        local direction: Vector3 = target.part.Position - origin
        if direction.Magnitude < 0.05 then
            return true
        end
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.IgnoreWater = true
        parameters.FilterDescendantsInstances = localPlayer.Character
            and {localPlayer.Character} or {}
        runtimeState.suppressRaycast = true
        local ok: boolean, hit: any = pcall(function(): any
            return currentWorkspace:Raycast(origin, direction, parameters)
        end)
        runtimeState.suppressRaycast = false
        if not ok then
            return false, "Wall Check unavailable: raycast failed."
        end
        if hit == nil or (hit.Instance and hit.Instance:IsDescendantOf(target.character)) then
            return true, nil
        end
        return false, "You can't shoot: a wall or another body is blocking the shot."
    end

    -- Aim FOV is a screen-space filter, not the camera's FieldOfView. On a
    -- phone the viewport center is stable even when a finger is over a button;
    -- on desktop ScreenPoint and GetMouseLocation share screen coordinates.
    local function targetScreenDistance(target: {[string]: any}): number?
        local camera: Camera? = currentWorkspace.CurrentCamera
        if not camera then return nil end
        local mobile: boolean = state.isMobile == true
        local ok: boolean, point: any, visible: any = pcall(function(): (any, any)
            if mobile then return camera:WorldToViewportPoint(target.part.Position) end
            return camera:WorldToScreenPoint(target.part.Position)
        end)
        if not ok or visible ~= true or not point or type(point.X) ~= "number"
            or type(point.Y) ~= "number" or (type(point.Z) == "number" and point.Z <= 0) then
            return nil
        end
        local pointer: any
        if mobile then
            local viewport: any = camera.ViewportSize
            if not viewport or type(viewport.X) ~= "number" or type(viewport.Y) ~= "number" then
                return nil
            end
            pointer = Vector2.new(viewport.X / 2, viewport.Y / 2)
        else
            local gotPointer: boolean, value: any = pcall(inputService.GetMouseLocation, inputService)
            if not gotPointer then return nil end
            pointer = value
        end
        if not pointer or type(pointer.X) ~= "number" or type(pointer.Y) ~= "number" then return nil end
        local dx: number, dy: number = point.X - pointer.X, point.Y - pointer.Y
        return math.sqrt(dx * dx + dy * dy)
    end

    local function nearestEnemy(
        maxDistance: number, teamCheckOverride: boolean?, wallCheckOverride: boolean?,
        cacheSelection: boolean?, origin: Vector3?, preferredPart: string?, screenRadius: number?
    ): ({[string]: any}?, string?)
        local checkWall: boolean = if wallCheckOverride == nil then settings.wallCheck
            else wallCheckOverride
        local localRoot: BasePart? = rootOf(localPlayer.Character)
        if not localRoot or not isAlive(localPlayer) then
            if cacheSelection ~= false then runtimeState.selected = nil end
            return nil, "Your character is not alive or ready."
        end
        if (runtimeState.matchModule or nativeMatchRequired) and not matchToken(localPlayer) then
            if cacheSelection ~= false then runtimeState.selected = nil end
            return nil, "No active duel or match data is still loading."
        end
        local best: {[string]: any}? = nil
        local bestScore: number = screenRadius or maxDistance
        local hasOpponent: boolean = false
        local outOfRange: boolean = false
        local outOfFov: boolean = false
        local blockedReason: string? = nil
        for _, player: Player in ipairs(players:GetPlayers()) do
            if isEnemy(player, false, teamCheckOverride) then
                hasOpponent = true
                local target: {[string]: any}? = targetRecord(player, preferredPart)
                if target then
                    local distance: number =
                        (target.part.Position - localRoot.Position).Magnitude
                    if distance > maxDistance then
                        outOfRange = true
                    else
                        local score: number = distance
                        local insideFov: boolean = true
                        if screenRadius ~= nil then
                            local screenDistance: number? = targetScreenDistance(target)
                            if screenDistance == nil or screenDistance > screenRadius then
                                outOfFov = true
                                insideFov = false
                            else
                                score = screenDistance
                            end
                        end
                        if insideFov and score <= bestScore then
                            local clear: boolean, reason: string? = true, nil
                            if checkWall then clear, reason = hasLineOfSight(target, origin) end
                            if not clear then
                                blockedReason = reason
                            else
                                best = target
                                bestScore = score
                            end
                        end
                    end
                end
            end
        end
        if cacheSelection ~= false then runtimeState.selected = best end
        if best then return best, nil end
        if blockedReason then return nil, blockedReason end
        if outOfFov then return nil, "No opponent is inside Aim FOV on screen." end
        if outOfRange then return nil, "The opponent is outside the selected range." end
        if hasOpponent then return nil, "The opponent's character is not ready." end
        return nil, "No eligible opponent (match, team, protection or health)."
    end

    local function candidateTools(): {Tool}
        local result: {Tool} = {}
        local backpack: Instance? = localPlayer:FindFirstChildOfClass("Backpack")
        for _, container: Instance? in ipairs({localPlayer.Character, backpack}) do
            if container then
                for _, child: Instance in ipairs(container:GetChildren()) do
                    if child:IsA("Tool") then
                        table.insert(result, child :: Tool)
                    end
                end
            end
        end
        return result
    end

    local function hasChild(tool: Tool, names: {string}): boolean
        for _, name: string in ipairs(names) do
            if tool:FindFirstChild(name, true) then
                return true
            end
        end
        return false
    end

    local function toolKind(tool: Tool?): string?
        if not tool then
            return nil
        end
        -- MobileKnifeLocalScript identifies arbitrary skins by CollectionService
        -- tag, so a skin need not contain "knife" in its display name.
        local okKnife: boolean, taggedKnife: any = pcall(collection.HasTag, collection, tool, "Knife")
        if okKnife and taggedKnife == true then return "Knife" end
        -- The captured DualWieldGun observer identifies gun skins by this tag.
        local okGun: boolean, taggedGun: any = pcall(collection.HasTag, collection, tool, "Gun")
        if okGun and taggedGun == true then return "Gun" end
        local gunStructure: boolean = hasChild(tool, {"fire", "showBeam", "GunKill"})
        local knifeStructure: boolean = hasChild(tool, {
            "ThrowEvent", "SlashEvent", "MobileKnifeLocalScript", "KnifeKill",
        })
        return rules.classifyTool(tool.Name, gunStructure, knifeStructure)
    end

    local function observedGunSignature(gun: Tool?): boolean
        if not gun or toolKind(gun) ~= "Gun" then return false end
        -- Both names and the direct Tool hierarchy were observed in the 1v1
        -- capture. A name such as "Gun" alone is not enough for anonymous aim.
        local fire: Instance? = gun:FindFirstChild("fire")
        local beam: Instance? = gun:FindFirstChild("showBeam")
        return fire ~= nil and fire:IsA("RemoteEvent")
            and beam ~= nil and beam:IsA("RemoteEvent")
    end

    local function findWeapon(kind: string): Tool?
        for _, tool: Tool in ipairs(candidateTools()) do
            if toolKind(tool) == kind then
                return tool
            end
        end
        return nil
    end

    local function equippedTool(): Tool?
        local character: Model? = localPlayer.Character
        if not character then
            return nil
        end
        for _, child: Instance in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                return child :: Tool
            end
        end
        return nil
    end

    local function equip(tool: Tool?): boolean
        if not tool then
            return false
        end
        local character: Model? = localPlayer.Character
        if not character then
            return false
        end
        if tool.Parent == character then
            return true
        end
        local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return false
        end
        pcall(function(): ()
            humanoid:EquipTool(tool)
        end)
        return tool.Parent == character
    end

    local function restoreCamera(): ()
        local override: any = runtimeState.cameraOverride
        runtimeState.cameraOverride = nil
        if override and override.camera and override.camera.Parent then
            pcall(function(): ()
                -- Never overwrite camera movement made after our short aim.
                if override.applied == nil or override.camera.CFrame == override.applied then
                    override.camera.CFrame = override.cframe
                end
            end)
        end
    end

    local function aimWithCFrame(position: Vector3): ()
        local camera: Camera? = currentWorkspace.CurrentCamera
        if camera then
            local override: any = runtimeState.cameraOverride
            if not override or override.camera ~= camera then
                override = {
                    camera = camera,
                    cframe = camera.CFrame,
                    token = 0,
                }
                runtimeState.cameraOverride = override
            elseif override.applied ~= nil and camera.CFrame ~= override.applied then
                -- Repeated auto shots must retain a newer user/camera update,
                -- not restore the snapshot taken before the first shot.
                override.cframe = camera.CFrame
            end
            override.token += 1
            local token: number = override.token
            local aimed: CFrame = CFrame.lookAt(camera.CFrame.Position, position)
            camera.CFrame = aimed
            override.applied = aimed
            -- Activated handlers can be deferred by Roblox; restoring in an
            -- earlier task.defer could erase the aim before the native gun read
            -- it. This is an aim-lifetime, not a server fire-rate claim.
            task.delay(0.1, function(): ()
                local current: any = runtimeState.cameraOverride
                if current == override and current.token == token then
                    restoreCamera()
                end
            end)
        end
    end

    -- Velocity lead and projectile drop are configurable estimates, not
    -- measured native Knife constants. Fall back to current position if the
    -- model has no intercept or the velocity is unavailable.
    local function predictedKnifePoint(target: {[string]: any}, origin: Vector3,
        speed: number, gravity: number): Vector3?
        local part: any = target and target.part
        if not part or typeof(part.Position) ~= "Vector3" then return nil end
        local root: BasePart? = rootOf(target.character)
        local ok: boolean, velocity: any = pcall(function(): any
            return (root or part).AssemblyLinearVelocity
        end)
        if not ok or typeof(velocity) ~= "Vector3" or velocity.Magnitude > 300 then velocity = Vector3.zero end
        local t: number? = rules.projectileInterceptTime(origin, part.Position, velocity, speed, gravity, 5)
        if not t then return nil end
        return part.Position + velocity * t + Vector3.new(0, 0.5 * gravity * t * t, 0)
    end

    local function activateNative(
        tool: Tool?,
        target: {[string]: any}?,
        aimAtTarget: boolean?,
        aimPosition: Vector3?
    ): boolean
        if not isAlive(localPlayer) or not tool or not equip(tool) then
            return false
        end
        if target and (not target.player or not isAlive(target.player)
            or isProtected(target.player) or not sharesMatch(target.player)
            or target.player.Character ~= target.character
            or not target.part or not target.part.Parent
            or not target.part:IsDescendantOf(target.character)) then
            return false
        end
        local enabledOk: boolean, enabled: any = pcall(function(): any
            return tool.Enabled
        end)
        if enabledOk and enabled == false then
            return false
        end
        if aimAtTarget == true and target then
            if not currentWorkspace.CurrentCamera then return false end
            -- Do not let Silent's independent target override another card's
            -- native shot while its deferred Activated handler reads the aim.
            runtimeState.nativeAimUntil = os.clock() + 0.1
            aimWithCFrame(aimPosition or target.part.Position)
        end
        local ok: boolean = pcall(function(): ()
            tool:Activate()
        end)
        return ok
    end

    local function validSilentTarget(target: any): {[string]: any}?
        if not target or not target.player or not target.part or not target.character
            or not isAlive(localPlayer) or not isEnemy(target.player) then
            return nil
        end
        if target.player.Character ~= target.character
            or not target.part.Parent or not target.character.Parent
            or not target.part:IsDescendantOf(target.character) then
            return nil
        end
        local root: BasePart? = rootOf(localPlayer.Character)
        if not root or (target.part.Position - root.Position).Magnitude > settings.maxDistance then
            return nil
        end
        if settings.silentAimFov then
            local screenDistance: number? = targetScreenDistance(target)
            if screenDistance == nil or screenDistance > settings.silentAimFovRadius then return nil end
        end
        if settings.wallCheck and not hasLineOfSight(target) then return nil end
        return target
    end

    local function selectedTarget(): {[string]: any}?
        return validSilentTarget(runtimeState.selected)
    end

    local function gunOrigin(gun: Tool?): Vector3?
        local character: Model? = localPlayer.Character
        if gun and gun.Parent == character then
            local handle: Instance? = gun:FindFirstChild("Handle", true)
            if handle and handle:IsA("BasePart") then return (handle :: BasePart).Position end
        end
        local root: BasePart? = rootOf(character)
        return root and root.Position or nil
    end

    -- X2 is not MM2: its captured Gun uses Net.RE/GunKill, not Gun.Shoot.
    -- This reproduces only the observed client argument shape, not server
    -- acceptance. In particular the selected part centre is not a ray hit.
    local function fireCFrameGun(gun: Tool, target: any, teamCheck: boolean): (boolean, string?)
        local character: Model? = localPlayer.Character
        local root: BasePart? = rootOf(character)
        if not root or gun.Parent ~= character or not isAlive(localPlayer)
            or not target or not target.player or not isEnemy(target.player, false, teamCheck)
            or target.player.Character ~= target.character or not target.part or not target.part.Parent
            or not target.part:IsDescendantOf(target.character) then
            return false, "Shot canceled: character, match or target changed."
        end
        local enabledOk: boolean, enabled: any = pcall(function(): any return gun.Enabled end)
        if not enabledOk or enabled == false then return false, "The gun is disabled or not ready." end
        if os.clock() < (runtimeState.nextCFrameGunAt or 0) then
            return false, "Gun cooldown (2.5s conservative)."
        end
        local handle: Instance? = gun:FindFirstChild("Handle")
        local fire: Instance? = gun:FindFirstChild("fire")
        local beam: Instance? = gun:FindFirstChild("showBeam")
        local packages: Instance? = replicated:FindFirstChild("Packages")
        local net: Instance? = packages and packages:FindFirstChild("Net")
        local kill: Instance? = net and net:FindFirstChild("RE/GunKill")
        if not handle or not handle:IsA("BasePart") or not fire or not fire:IsA("RemoteEvent")
            or not beam or not beam:IsA("RemoteEvent") or not kill or not kill:IsA("RemoteEvent") then
            return false, "CFrame gun unavailable: observed Gun remotes or Handle missing."
        end
        local impact: Vector3 = target.part.Position
        local start: Vector3 = root.Position
        local muzzle: Vector3 = (handle :: BasePart).Position
        if (impact - muzzle).Magnitude < 0.05 then return false, "Target is too close to the gun." end
        local direction: Vector3 = CFrame.lookAt(muzzle, impact).LookVector
        -- Fire and beam are the native client's order; sending them is NOT a
        -- confirmation that the server accepted the subsequent GunKill call.
        local okFire: boolean = pcall(function(): () (fire :: RemoteEvent):FireServer() end)
        if not okFire then return false, "Gun fire request failed." end
        runtimeState.nextCFrameGunAt = os.clock() + 2.5
        local okBeam: boolean = pcall(function(): () (beam :: RemoteEvent):FireServer(impact, start, handle) end)
        local okKill: boolean = pcall(function(): ()
            (kill :: RemoteEvent):FireServer("72376a93-74c0-4fc7-b968-b3def980891c", target.player, direction, start, impact)
        end)
        if not okKill then return false, "Gun request failed after fire; hit not confirmed." end
        return true, okBeam and "CFrame request sent; hit not confirmed." or "Gun request sent; beam failed; hit not confirmed."
    end

    local ensureAutoOth: () -> boolean = function(): boolean return false end
    local function cancelGun(owner: string?): ()
        if owner == nil or owner == "Silent AIM" then runtimeState.mouseShot = nil end
        local lease: any = runtimeState.autoAimLease
        if owner == nil or (lease and lease.owner == owner) then
            runtimeState.autoAimLease = nil
            runtimeState.autoAimAttempt += 1
        end
        local pending: any = runtimeState.gunPending
        if owner ~= nil and (not pending or pending.owner ~= owner) then return end
        runtimeState.gunToken += 1
        runtimeState.gunPending = nil
    end

    local function fireGun(
        target: {[string]: any}?, noAim: boolean?, options: {[string]: any}?
    ): (boolean, boolean, string?)
        local gun: Tool? = findWeapon("Gun")
        if not gun then return false, false, "No gun is available in your inventory." end
        if not target then return false, true, "No eligible opponent." end
        if runtimeState.knifeBusy then return false, true, "Waiting for the knife throw." end
        if runtimeState.gunPending or runtimeState.autoAimLease then
            return false, true, "A gun action is already pending."
        end
        local character: Model? = localPlayer.Character
        if not character or not isAlive(localPlayer) then
            return false, true, "Your character is not alive or ready."
        end
        local opts: {[string]: any} = options or {}
        local function activate(): (boolean, string?)
            -- TriggerBot deliberately uses the crosshair, not the independent
            -- Silent target, even when both modules are enabled.
            if noAim == true then runtimeState.nativeAimUntil = os.clock() + 0.1
            elseif not currentWorkspace.CurrentCamera and settings.autoShootBackend ~= "CFrame" then return false, "Camera unavailable: cannot aim." end
            if opts.wallCheck == true then
                -- The native gun may use a camera ray, while a muzzle may be
                -- obstructed independently. Check both without hooking either.
                local shotRoot: BasePart? = rootOf(character)
                local from: Vector3? = settings.autoShootBackend == "CFrame" and shotRoot
                    and shotRoot.Position or gunOrigin(gun)
                local clear: boolean, why: string? = hasLineOfSight(target, from)
                if not clear then return false, why end
                if settings.autoShootBackend ~= "CFrame" then
                    clear, why = hasLineOfSight(target)
                    if not clear then return false, why end
                end
            end
            if (opts.owner == "Auto Shoot" or opts.owner == "Auto Win")
                and settings.autoShootBackend == "CFrame" and noAim ~= true then
                return fireCFrameGun(gun, target, opts.teamCheck ~= false)
            end
            if (opts.owner == "Auto Shoot" or (opts.owner == "Auto Win"
                and (settings.autoShoot or settings.silentAim))) and noAim ~= true then
                -- The captured Gun uses a cached mobile Mouse.Hit. Moving the
                -- camera does not reliably change it, and produces aim-lock.
                -- Instead arm only the identified native 10,000-stud gun ray.
                if type(host.getcallingscript) ~= "function" or not ensureAutoOth() then
                    return false, "Gun aim unavailable: Oth and weapon caller required; camera unchanged."
                end
                if gun.Name == "MimicGlare" and os.clock() < (runtimeState.nextMimicGunAt or 0) then
                    return false, "Gun cooling down (observed 2.5 seconds)."
                end
                runtimeState.autoAimAttempt += 1
                local attempt: number = runtimeState.autoAimAttempt
                local before: number = runtimeState.autoRedirectSerial or 0
                local lease: any = {gun = gun, target = target, character = character, owner = opts.owner,
                    gameToken = matchToken(localPlayer), teamCheck = opts.teamCheck, wallCheck = opts.wallCheck,
                    range = opts.range or math.huge, expires = os.clock() + 0.35}
                runtimeState.autoAimLease = lease
                local ok: boolean = activateNative(gun, target, false)
                if not ok and runtimeState.autoAimLease == lease then runtimeState.autoAimLease = nil end
                if ok then
                    if gun.Name == "MimicGlare" then runtimeState.nextMimicGunAt = os.clock() + 2.5 end
                    task.delay(0.4, function(): ()
                        if runtimeState.closed or runtimeState.autoAimAttempt ~= attempt then return end
                        if runtimeState.autoAimLease == lease then runtimeState.autoAimLease = nil end
                        if lease.owner == "Auto Shoot" and settings.autoShoot then
                            runtimeState.autoShootOutcome = (runtimeState.autoRedirectSerial or 0) > before
                                and "Native gun ray redirected; hit not confirmed."
                                or "No gun ray redirected; Oth or weapon may be unsupported."
                            setCombatStatus(autoShootCard, "Auto Shoot", runtimeState.autoShootOutcome)
                        end
                    end)
                end
                return ok, if ok then nil else "The gun is disabled, reloading or not ready."
            end
            local ok: boolean = activateNative(gun, target, noAim ~= true)
            return ok, if ok then nil else "The gun is disabled, reloading or not ready."
        end
        if gun.Parent == character then
            local ok: boolean, reason: string? = activate()
            return ok, true, reason
        end
        if not equip(gun) then return false, true, "Could not equip the gun." end
        runtimeState.gunToken += 1
        local token: number = runtimeState.gunToken
        local gameToken: string? = matchToken(localPlayer)
        runtimeState.gunPending = {token = token, owner = opts.owner or "external", tool = gun}
        task.spawn(function(): ()
            local ok: boolean, failure: any = pcall(function(): ()
                -- EquipTool reparents immediately, but the Tool's Equipped/local
                -- handlers and grip may not be ready until the next Heartbeat.
                runService.Heartbeat:Wait()
                local pending: any = runtimeState.gunPending
                if not pending or pending.token ~= token or runtimeState.closed then return end
                local active: boolean = true
                if type(opts.isActive) == "function" then
                    local activeOk: boolean, value: any = pcall(opts.isActive)
                    active = activeOk and value == true
                end
                local root: BasePart? = rootOf(character)
                local sameTarget: boolean = target.player ~= nil
                    and target.player.Character == target.character and target.part ~= nil
                    and target.part.Parent ~= nil and target.part:IsDescendantOf(target.character)
                local valid: boolean = active and localPlayer.Character == character
                    and gun.Parent == character and isAlive(localPlayer)
                    and matchToken(localPlayer) == gameToken and sameTarget
                    and isEnemy(target.player, false, opts.teamCheck)
                    and root ~= nil and (target.part.Position - root.Position).Magnitude <= (opts.range or math.huge)
                if valid then
                    local fired: boolean, reason: string? = activate()
                    if opts.owner == "Auto Shoot" and settings.autoShoot then
                        setCombatStatus(autoShootCard, "Auto Shoot", fired
                            and (reason or "Native activation attempted; hit not confirmed.")
                            or (reason or "The gun is not ready."))
                    end
                elseif active and opts.owner == "Auto Shoot" and settings.autoShoot then
                    setCombatStatus(autoShootCard, "Auto Shoot", "Shot canceled: character, match or target changed.")
                end
            end)
            local pending: any = runtimeState.gunPending
            if pending and pending.token == token then runtimeState.gunPending = nil end
            if not ok and not runtimeState.closed and opts.owner == "Auto Shoot" and settings.autoShoot then
                setCombatStatus(autoShootCard, "Auto Shoot", "Gun action failed: " .. tostring(failure))
            end
        end)
        return true, true, "Gun equipped; shot queued."
    end

    local function mobileThrowMode(): BoolValue?
        -- The new decompiled MobileKnifeLocalScript toggles this BoolValue;
        -- there is no evidence for a ForceThrow Tool attribute in this place.
        local gui: Instance? = localPlayer:FindFirstChildOfClass("PlayerGui")
            or localPlayer:FindFirstChild("PlayerGui")
        local main: Instance? = gui and gui:FindFirstChild("Main")
        local mobile: Instance? = main and main:FindFirstChild("MobileKnifeGui")
        local mode: Instance? = mobile and mobile:FindFirstChild("ThrowMode")
        return mode and mode:IsA("BoolValue") and mode :: BoolValue or nil
    end

    local function restoreThrowMode(pending: any): ()
        local mode: BoolValue? = pending and pending.throwMode
        if mode and mode.Parent then
            pcall(function(): ()
                -- Do not overwrite a newer change made by the native GUI.
                if mode.Value == true then mode.Value = pending.previousThrowMode end
            end)
        end
    end

    local function cancelKnifeThrow(owner: string?): ()
        local pending: any = runtimeState.knifePending
        if owner ~= nil and (not pending or pending.owner ~= owner) then return end
        runtimeState.knifeToken = (runtimeState.knifeToken or 0) + 1
        runtimeState.knifePending = nil
        runtimeState.knifeBusy = false
        if pending then
            if pending.rightDown and type(host.mouse2release) == "function" then
                pending.rightDown = false
                pcall(host.mouse2release)
            end
            restoreThrowMode(pending)
            if pending.projectile then pcall(function(): () pending.projectile:Destroy() end) end
        end
        restoreCamera()
    end

    local function fireKnife(
        target: {[string]: any}?, noAim: boolean?, options: {[string]: any}?
    ): boolean
        if not target or runtimeState.knifeBusy then
            return false
        end
        local knife: Tool? = findWeapon("Knife")
        if not knife or not equip(knife) then
            return false
        end
        local enabledOk: boolean, enabled: any = pcall(function(): any
            return knife.Enabled
        end)
        if enabledOk and enabled == false then
            return false
        end

        local throwMode: BoolValue? = mobileThrowMode()
        local canMouse: boolean = type(host.mouse2press) == "function"
            and type(host.mouse2release) == "function"
        if not throwMode and not canMouse then return false end
        local useTouch: boolean = throwMode ~= nil
            and (inputService.TouchEnabled or not canMouse)
        local opts: {[string]: any} = options or {}
        local teamCheck: boolean = if opts.teamCheck == nil then settings.teamCheck else opts.teamCheck
        local wallCheck: boolean = if opts.wallCheck == nil then settings.wallCheck else opts.wallCheck
        local wasEnemy: boolean = isEnemy(target.player, false, teamCheck)
        local token: number = (runtimeState.knifeToken or 0) + 1
        runtimeState.knifeToken = token
        runtimeState.knifeBusy = true
        local pending: {[string]: any} = {
            tool = knife, rightDown = false, owner = opts.owner or "external",
        }
        runtimeState.knifePending = pending

        local function stillValid(): boolean
            local currentRoot: BasePart? = rootOf(localPlayer.Character)
            return token == runtimeState.knifeToken
                and (opts.range == nil or (currentRoot ~= nil
                    and (target.part.Position - currentRoot.Position).Magnitude <= opts.range))
                and knife.Parent == localPlayer.Character
                and target.player.Character == target.character
                and target.character.Parent ~= nil
                and target.part.Parent ~= nil
                and target.part:IsDescendantOf(target.character)
                and isAlive(localPlayer) and isAlive(target.player)
                and not isProtected(target.player)
                and sharesMatch(target.player)
                and (not wasEnemy or isEnemy(target.player, false, teamCheck))
                and (not wallCheck or hasLineOfSight(target))
        end

        task.spawn(function(): ()
            local ok: boolean, failure: any = pcall(function(): ()
                if not stillValid() then return end
                local aimAtTarget: boolean = noAim ~= true
                local function knifeAimPoint(): Vector3
                    if opts.owner == "Knife Throw" and settings.knifePrediction then
                        local camera: Camera? = currentWorkspace.CurrentCamera
                        local root: BasePart? = rootOf(localPlayer.Character)
                        local origin: Vector3? = camera and camera.CFrame.Position or (root and root.Position)
                        if origin then
                            local prediction: Vector3? = predictedKnifePoint(target, origin,
                                settings.knifeProjectileSpeed, settings.knifeProjectileGravity)
                            if prediction then return prediction end
                        end
                    end
                    return target.part.Position
                end
                if aimAtTarget then aimWithCFrame(knifeAimPoint()) end
                if useTouch and throwMode then
                    pending.throwMode = throwMode
                    pending.previousThrowMode = throwMode.Value
                    throwMode.Value = true
                    if stillValid() then activateNative(knife, target, aimAtTarget, aimAtTarget and knifeAimPoint() or nil) end
                    task.wait()
                elseif canMouse then
                    local pressed: boolean = pcall(host.mouse2press)
                    if pressed then
                        pending.rightDown = true
                        -- Preserve the pre-existing desktop native windup.
                        task.wait(0.2)
                        if stillValid() then activateNative(knife, target, aimAtTarget, aimAtTarget and knifeAimPoint() or nil) end
                        if pending.rightDown then
                            pending.rightDown = false
                            pcall(host.mouse2release)
                        end
                    end
                end
            end)

            if token == runtimeState.knifeToken then
                if pending.rightDown and type(host.mouse2release) == "function" then
                    pending.rightDown = false
                    pcall(host.mouse2release)
                end
                restoreThrowMode(pending)
                runtimeState.knifePending = nil
                runtimeState.knifeBusy = false
                if type(opts.cooldown) == "number" then
                    -- The user delay starts after native windup/release; it
                    -- does not run concurrently with the required input hold.
                    runtimeState.nextKnifeAt[pending.owner] = os.clock() + math.max(0, opts.cooldown)
                end
            end
            if not ok then runtimeState.lastKnifeError = tostring(failure) end
        end)
        return true
    end

    -- Replays the captured X2 ThrowEvent shape and invokes the weapon's own
    -- local projectile handler. It never fabricates a KnifeKill: the native
    -- handler performs collision checks and decides whether to send that call.
    local function queueCFrameKnife(target: any, options: {[string]: any}): (boolean, string?)
        if not target or runtimeState.knifeBusy or runtimeState.gunPending or runtimeState.autoAimLease then
            return false, "Another weapon action is pending."
        end
        local knife: Tool? = findWeapon("Knife")
        local character: Model? = localPlayer.Character
        if not knife or not character or not isAlive(localPlayer) then return false, "Knife or character unavailable." end
        if os.clock() < (runtimeState.nextCFrameKnifeAt or 0) then return false, "Knife cooldown." end
        local wasEquipped: boolean = knife.Parent == character
        if not equip(knife) then return false, "Could not equip the knife." end
        local token: number = runtimeState.knifeToken + 1
        runtimeState.knifeToken = token
        local match: string? = matchToken(localPlayer)
        local pending: any = {tool = knife, owner = options.owner}
        runtimeState.knifeOutcome = nil
        runtimeState.knifePending, runtimeState.knifeBusy = pending, true
        task.spawn(function(): ()
            local function active(): boolean
                if runtimeState.closed or token ~= runtimeState.knifeToken
                    or knife.Parent ~= character or localPlayer.Character ~= character
                    or matchToken(localPlayer) ~= match or not isAlive(localPlayer)
                    or not isEnemy(target.player, false, options.teamCheck)
                    or target.player.Character ~= target.character or not target.part or not target.part.Parent
                    or not target.part:IsDescendantOf(target.character) then return false end
                if type(options.isActive) == "function" then
                    local ok: boolean, value: any = pcall(options.isActive)
                    if not ok or value ~= true then return false end
                end
                if runtimeState.resultsPending then return false end
                local gameOk: boolean, gameData: any = matchApiCall("getGame", localPlayer)
                if gameOk and type(gameData) == "table" and (gameData.CurrentRoundEnded == true
                    or (gameData.Phase ~= nil and gameData.Phase ~= "InGame")) then return false end
                -- RoundStarted in the decompiled Knife contradicts other game
                -- state; do not reinterpret that field without live evidence.
                local zombieOk: boolean, zombie: any = matchApiCall("isInfectionZombie", localPlayer)
                if zombieOk and zombie == true then return false end
                local root: BasePart? = rootOf(character)
                return root ~= nil and (target.part.Position - root.Position).Magnitude <= (options.range or math.huge)
            end
            local function report(message: string): ()
                if options.owner == "Knife Throw" and settings.knifeThrow then
                    runtimeState.knifeOutcome = message
                    setCombatStatus(knifeThrowCard, "Knife Throw", message)
                end
            end
            local ok: boolean, failure: any = pcall(function(): ()
                if not wasEquipped then runService.Heartbeat:Wait() end
                if not active() then report("Throw canceled: character, match or target changed."); return end
                local enabledOk: boolean, enabled: any = pcall(function(): any return knife.Enabled end)
                if not enabledOk or enabled == false then report("Knife disabled or not ready."); return end
                local packages: Instance? = replicated:FindFirstChild("Packages")
                local net: Instance? = packages and packages:FindFirstChild("Net")
                local remote: Instance? = net and net:FindFirstChild("RE/ThrowEvent")
                local handle: Instance? = knife:FindFirstChild("Handle")
                local makerModule: Instance? = knife:FindFirstChild("MakeLocalFlyingHandle")
                local activation: Instance? = knife:FindFirstChild("ActivateThrowing")
                local handler: Instance? = knife:FindFirstChild("ThrowingKinfeHandlerScript", true)
                if not remote or not remote:IsA("RemoteEvent") or not handle or not handle:IsA("BasePart")
                    or not makerModule or not makerModule:IsA("ModuleScript")
                    or not activation or not activation:IsA("BindableEvent")
                    or not handler or not handler:IsA("LocalScript") then
                    report("CFrame Knife unavailable: native projectile components missing."); return
                end
                local loaded: boolean, maker: any = pcall(require, makerModule)
                if not loaded or type(maker) ~= "function" then report("Knife projectile module unavailable."); return end
                -- The native source reads this flag to choose the origin.
                -- Do not silently guess when its AB module is unavailable.
                local userGenerated: Instance? = replicated:FindFirstChild("UserGenerated")
                local abModule: Instance? = userGenerated and userGenerated:FindFirstChild("ABTests")
                if not abModule or not abModule:IsA("ModuleScript") then
                    report("CFrame Knife unavailable: ABTests module missing."); return
                end
                local loadedAB: boolean, ab: any = pcall(require, abModule)
                if not loadedAB or type(ab) ~= "table" or type(ab.GetJobAttribute) ~= "function" then
                    report("CFrame Knife unavailable: ABTests could not load."); return
                end
                local got: boolean, value: any = pcall(ab.GetJobAttribute, "NormalKnifeThrow", false)
                if not got or type(value) ~= "boolean" then
                    report("CFrame Knife unavailable: throw mode unknown."); return
                end
                local normal: boolean = value
                if not active() then report("Throw canceled before request."); return end
                local origin: Vector3 = (handle :: BasePart).Position
                if normal then
                    local hand: Instance? = character:FindFirstChild("RightHand")
                    local grip: Instance? = hand and hand:FindFirstChild("RightGripAttachment")
                    if grip and grip:IsA("Attachment") then origin = (grip :: Attachment).WorldCFrame.Position end
                end
                if options.wallCheck then
                    local clear: boolean, reason: string? = hasLineOfSight(target, origin)
                    if not clear then report(reason or "Wall Check unavailable."); return end
                end
                local aim: Vector3 = target.part.Position
                if settings.knifePrediction and options.owner == "Knife Throw" then
                    aim = predictedKnifePoint(target, origin, settings.knifeProjectileSpeed,
                        settings.knifeProjectileGravity) or aim
                end
                if (aim - origin).Magnitude < 0.05 then report("Target too close for knife."); return end
                local endpoint: CFrame = CFrame.new(aim)
                local made: boolean, projectile: any = pcall(maker, handle, origin, endpoint, normal)
                if not made or typeof(projectile) ~= "Instance" or not projectile:IsA("BasePart") then
                    report("Local knife projectile could not be created."); return
                end
                pending.projectile = projectile
                local velocity: Instance? = projectile:FindFirstChild("VelocityV")
                local visualVelocity: Instance? = projectile:FindFirstChild("VelocityVClient")
                if not velocity or not velocity:IsA("Vector3Value") or not visualVelocity or not visualVelocity:IsA("Vector3Value") then
                    report("Local knife projectile is missing velocity values."); return
                end
                local direction: Vector3 = (aim - projectile.Position).Unit
                local velocityValue: any = velocity
                local visualVelocityValue: any = visualVelocity
                velocityValue.Value = direction
                visualVelocityValue.Value = direction
                local cloned: any = handler:Clone()
                local creator: Instance? = cloned and cloned:FindFirstChild("creator")
                if not cloned or not creator or not creator:IsA("ObjectValue") then
                    if cloned then cloned:Destroy() end
                    report("Native knife collision handler is incomplete."); return
                end
                local creatorValue: any = creator
                creatorValue.Value = localPlayer
                cloned.Parent = projectile
                cloned.Disabled = false
                if not active() then report("Throw canceled before request."); return end
                if handle.Parent ~= knife or knife.Enabled == false then
                    report("Knife disabled or Handle changed before request."); return
                end
                if options.wallCheck then
                    local clear: boolean, reason: string? = hasLineOfSight(target, origin)
                    if not clear then report(reason or "Wall Check unavailable."); return end
                end
                local sent: boolean = pcall(function(): ()
                    (remote :: RemoteEvent):FireServer("959d5e90-231d-4f6e-8861-050e2c22b938", endpoint, origin)
                end)
                if not sent then report("Knife throw request failed."); return end
                local debounce: Instance? = knife:FindFirstChild("Debounce")
                local nativeDelay: number = 1
                if debounce and (debounce:IsA("NumberValue") or debounce:IsA("IntValue")) then
                    nativeDelay = math.clamp((debounce :: any).Value - 0.3, 0.25, 10)
                end
                runtimeState.nextCFrameKnifeAt = os.clock() + nativeDelay + math.max(0, options.cooldown or 0)
                local rendered: Instance? = currentWorkspace:FindFirstChild("RenderedObjects")
                projectile.Parent = rendered or currentWorkspace
                local eventOk: boolean = pcall(function(): () (activation :: BindableEvent):Fire(projectile, localPlayer) end)
                pending.projectile = nil -- native handler now owns the launched projectile
                pcall(function(): () game:GetService("Debris"):AddItem(projectile, 7) end)
                report(eventOk and "CFrame throw sent; hit not confirmed."
                    or "Throw sent, but local collision handler failed; hit unconfirmed.")
            end)
            -- Even a canceled task can resume after require/maker yielded.
            if pending.projectile then pcall(function(): () pending.projectile:Destroy() end) end
            if token == runtimeState.knifeToken then
                runtimeState.knifePending, runtimeState.knifeBusy = nil, false
                runtimeState.nextKnifeAt[options.owner] = math.max(runtimeState.nextCFrameKnifeAt or 0, os.clock() + 0.25)
                if not ok then report("Knife action failed: " .. tostring(failure)) end
            end
        end)
        return true, "CFrame throw queued; hit not confirmed."
    end

    local function isWeaponCaller(tool: Tool): (boolean, boolean)
        local getCaller: any = host.getcallingscript
        if type(getCaller) == "function" then
            local ok: boolean, caller: any = pcall(getCaller)
            if ok and typeof(caller) == "Instance" then
                if caller.IsDescendantOf(caller, tool) then return true, false end
                -- An explicitly identified foreign script wins over an
                -- incidental weapon-looking stack or anonymous compatibility.
                -- MouseCast is the shared module whose stack may identify Gun.
                if caller ~= runtimeState.mouseCastModule then return false, true end
            end
        end
        -- A shared ModuleScript such as MouseCast can be the immediate caller.
        -- Only accept a stack source naming THIS local player's actual Tool and
        -- one of its LocalScripts; a generic camera ray or ping is not proof.
        local debugApi: any = host.debug
        local info: any = type(debugApi) == "table" and debugApi.info or nil
        if type(info) ~= "function" then return false, false end
        local scripts: {string} = {}
        for _, child: Instance in ipairs(tool:GetDescendants()) do
            if child:IsA("LocalScript") then table.insert(scripts, child.Name) end
        end
        if #scripts == 0 then return false, false end
        for level: number = 2, 18 do
            local ok: boolean, source: any = pcall(info, level, "s")
            if not ok or type(source) ~= "string" then break end
            for _, scriptName: string in ipairs(scripts) do
                local equippedSuffix: string = localPlayer.Name .. "." .. tool.Name .. "." .. scriptName
                local backpackSuffix: string = localPlayer.Name .. ".Backpack." .. tool.Name .. "." .. scriptName
                for _, suffix: string in ipairs({equippedSuffix, backpackSuffix}) do
                    local first: number? = string.find(source, suffix, 1, true)
                    if first then
                        local previous: string = string.sub(source, first - 1, first - 1)
                        local following: string = string.sub(source, first + #suffix, first + #suffix)
                        if (first == 1 or previous == "." or previous == "/" or previous == "@")
                            and (following == "" or following == ":" or following == "]" or following == "\"") then
                            return true, false
                        end
                    end
                end
            end
        end
        return false, false
    end

    local function redirectRay(origin: Vector3, direction: Vector3, allowUnattributed: boolean?): Vector3?
        if runtimeState.suppressRaycast or os.clock() < runtimeState.nativeAimUntil
            or not settings.silentAim then
            return nil
        end
        local equipped: Tool? = equippedTool()
        -- MouseCast is also used for pings. A weapon being equipped and a ray
        -- near the camera do not prove that the ray belongs to a weapon.
        if not equipped or toolKind(equipped) == nil then return nil end
        local identified: boolean, foreign: boolean = isWeaponCaller(equipped)
        if not identified then
            if not allowUnattributed or not settings.raycastCompatibility then return nil end
            -- Even in compatibility mode, known camera and ping callers are
            -- unrelated to a weapon and must remain untouched.
            if foreign and type(host.getcallingscript) == "function" then
                local ok: boolean, caller: any = pcall(host.getcallingscript)
                if ok and typeof(caller) == "Instance" then
                    local lower: string = string.lower(caller.Name)
                    if string.find(lower, "camera", 1, true) or string.find(lower, "ping", 1, true) then return nil end
                end
            end
        end
        local target: {[string]: any}? = selectedTarget()
        if not target or direction.Magnitude < 0.05 then
            return nil
        end
        local camera: Camera? = currentWorkspace.CurrentCamera
        local root: BasePart? = rootOf(localPlayer.Character)
        local nearCamera: boolean = camera ~= nil
            and (origin - camera.CFrame.Position).Magnitude <= 35
        local nearCharacter: boolean = root ~= nil
            and (origin - root.Position).Magnitude <= 35
        if not nearCamera and not nearCharacter and not (allowUnattributed and settings.raycastCompatibility) then
            return nil
        end
        if settings.wallCheck and not hasLineOfSight(target, origin) then return nil end
        local aimPosition: Vector3 = target.part.Position
        if toolKind(equipped) == "Knife" and settings.silentKnifePrediction then
            aimPosition = predictedKnifePoint(target, origin, settings.silentKnifeSpeed, settings.silentKnifeGravity)
                or aimPosition
        end
        local offset: Vector3 = aimPosition - origin
        if offset.Magnitude < 0.05 or offset.Magnitude > direction.Magnitude then
            return nil -- preserve the native ray's range, never extend it
        end
        runtimeState.redirectCount += 1
        return offset.Unit * direction.Magnitude
    end

    -- The captured MouseCast module has five methods returning a real
    -- RaycastResult and a 500-stud endpoint. It is shared with PingsController,
    -- so replace its methods only for a provably local weapon call. The gun's
    -- complete LocalScript is missing from the capture: using MouseCast here is
    -- an adapter, not proof that this particular gun actually calls it.
    local function mouseCastShot(method: string, api: any, arguments: any): (boolean, any, Vector3?)
        if runtimeState.closed or not settings.silentAim or runtimeState.suppressRaycast
            or os.clock() < runtimeState.nativeAimUntil or arguments[1] ~= api then
            return false, nil, nil
        end
        local gun: Tool? = equippedTool()
        if not gun or toolKind(gun) ~= "Gun" or not isWeaponCaller(gun) then
            return false, nil, nil
        end
        local target: {[string]: any}? = selectedTarget()
        local camera: Camera? = currentWorkspace.CurrentCamera
        if not target or not camera then return false, nil, nil end
        local position: any
        local filters: any
        if method == "WithPositionExclude" or method == "WithPositionInclude" then
            position, filters = arguments[2], arguments[3]
        else
            position = inputService:GetMouseLocation()
            filters = arguments[2]
        end
        if typeof(position) ~= "Vector2" then return false, nil, nil end
        local ray: Ray = camera:ViewportPointToRay(position.X, position.Y)
        local origin: Vector3 = ray.Origin
        local delta: Vector3 = target.part.Position - origin
        if delta.Magnitude < 0.05 or delta.Magnitude > 500 then return false, nil, nil end
        if settings.wallCheck and (not hasLineOfSight(target, origin)
            or not hasLineOfSight(target, gunOrigin(gun))) then return false, nil, nil end
        local parameters: any = filters
        if method ~= "WithParams" then
            if type(filters) ~= "table" then return false, nil, nil end
            parameters = RaycastParams.new()
            parameters.FilterType = (method == "Include" or method == "WithPositionInclude")
                and Enum.RaycastFilterType.Include or Enum.RaycastFilterType.Exclude
            parameters.FilterDescendantsInstances = filters
        end
        local direction: Vector3 = delta.Unit * 500
        runtimeState.suppressRaycast = true
        local ok: boolean, result: any = pcall(
            currentWorkspace.Raycast, currentWorkspace, origin, direction, parameters
        )
        runtimeState.suppressRaycast = false
        if not ok then return false, nil, nil end
        runtimeState.redirectCount += 1
        return true, result, origin + direction
    end

    local function uninstallMouseCast(): ()
        runtimeState.mouseCastGeneration += 1
        runtimeState.mouseCastLoading = false
        local api: any = runtimeState.mouseCastApi
        for name: string, record: any in pairs(runtimeState.mouseCastWrappers) do
            record.active = false
            if api then
                pcall(function(): ()
                    -- A later third-party wrapper owns the current slot; leave it
                    -- installed and let our disabled wrapper simply pass through.
                    if api[name] == record.wrapper then api[name] = record.original end
                end)
            end
        end
        table.clear(runtimeState.mouseCastWrappers)
        runtimeState.mouseCastApi = nil
    end

    local function discoverMouseCast(): ()
        local client: Instance? = replicated:FindFirstChild("Client")
        local modules: Instance? = client and client:FindFirstChild("Modules")
        local candidate: Instance? = modules and modules:FindFirstChild("MouseCast")
        if candidate and not candidate:IsA("ModuleScript") then candidate = nil end
        if candidate ~= runtimeState.mouseCastModule then
            uninstallMouseCast()
            runtimeState.mouseCastModule = candidate
            runtimeState.mouseCastLoading = false
        end
        if not settings.silentAim or settings.silentBackend ~= "Legacy" or not candidate or runtimeState.mouseCastApi
            or runtimeState.mouseCastLoading then return end
        runtimeState.mouseCastLoading = true
        local generation: number = runtimeState.mouseCastGeneration
        task.spawn(function(): ()
            local ok: boolean, api: any = pcall(require, candidate)
            if runtimeState.closed or not settings.silentAim
                or generation ~= runtimeState.mouseCastGeneration
                or candidate ~= runtimeState.mouseCastModule then return end
            runtimeState.mouseCastLoading = false
            if not ok or type(api) ~= "table" then return end
            local installed: number = 0
            for _, name: string in ipairs({
                "WithParams", "Exclude", "Include", "WithPositionExclude", "WithPositionInclude",
            }) do
                local original: any = api[name]
                if type(original) == "function" then
                    local record: any = {original = original, active = true}
                    local wrapper: any = function(...: any): any
                        if not record.active then return original(...) end
                        local arguments: any = table.pack(...)
                        local redirectedOk: boolean, redirected: any, result: any, endpoint: any =
                            pcall(mouseCastShot, name, api, arguments)
                        if redirectedOk and redirected == true then return result, endpoint end
                        return original(unpack(arguments, 1, arguments.n))
                    end
                    record.wrapper = wrapper
                    local replaced: boolean = pcall(function(): () api[name] = wrapper end)
                    if replaced and api[name] == wrapper then
                        runtimeState.mouseCastWrappers[name] = record
                        installed += 1
                    end
                end
            end
            if installed > 0 then runtimeState.mouseCastApi = api end
        end)
    end

    local function redirectKnifeThrow(remote: Instance, arguments: {[any]: any}): Vector3?
        if os.clock() < runtimeState.nativeAimUntil or not settings.silentAim
            or arguments.n ~= 3 then return nil end
        local knife: Tool? = equippedTool()
        if not knife or toolKind(knife) ~= "Knife" or not isWeaponCaller(knife) then return nil end
        local packages: Instance? = replicated:FindFirstChild("Packages")
        local net: Instance? = packages and packages:FindFirstChild("Net")
        if not net or remote.Parent ~= net or not remote:IsA("RemoteEvent")
            or string.sub(remote.Name, 1, 3) ~= "RE/" then return nil end
        local guid: any = arguments[1]
        local origin: any = arguments[2]
        local destination: any = arguments[3]
        if type(guid) ~= "string" or #guid ~= 36
            or not string.match(guid, "^%x+%-%x+%-%x+%-%x+%-%x+$")
            or typeof(origin) ~= "CFrame" or typeof(destination) ~= "Vector3" then return nil end
        local root: BasePart? = rootOf(localPlayer.Character)
        if not root or (origin.Position - root.Position).Magnitude > 35 then return nil end
        local target: {[string]: any}? = selectedTarget()
        if not target or (settings.wallCheck and not hasLineOfSight(target, origin.Position)) then
            return nil
        end
        -- Preserve the real remote, GUID and CFrame; only substitute the native
        -- destination. Never create or replay a server call of our own.
        return target.part.Position
    end

    local function installKnifeHook(wrap: any): ()
        local hook: any = host.hookmetamethod
        local method: any = host.getnamecallmethod
        if runtimeState.knifeHookInstalled or type(hook) ~= "function"
            or type(method) ~= "function" then return end
        local predecessor: any = nil
        local lease: any = {active = true}
        local wrapper: any = wrap(function(remote: any, ...: any): any
            if predecessor == nil then return nil end
            if not lease.active then return predecessor(remote, ...) end
            if typeof(remote) == "Instance" then
                local okMethod: boolean, name: any = pcall(method)
                if okMethod and name == "FireServer" then
                    local arguments: any = table.pack(...)
                    local ok: boolean, redirected: any = pcall(redirectKnifeThrow, remote, arguments)
                    if ok and typeof(redirected) == "Vector3" then
                        arguments[3] = redirected
                        return predecessor(remote, unpack(arguments, 1, arguments.n))
                    end
                end
            end
            return predecessor(remote, ...)
        end)
        local ok: boolean, old: any = pcall(hook, game, "__namecall", wrapper)
        if ok and type(old) == "function" then
            predecessor = old
            runtimeState.knifeHookInstalled = true
            runtimeState.oldNamecall = old
            runtimeState.knifeWrapper = wrapper
            runtimeState.knifeHookLease = lease
        end
    end

    -- Published X2 examples commonly intercept the local Mouse's Hit/Target
    -- without caller attribution. On executors that cannot identify the gun
    -- script, limit this fallback to the observed Gun signature and a native
    -- (non-executor) access. By default it is armed only briefly by our own
    -- action button; continuous native-shot compatibility requires opt-in.
    local function anonymousMouseTarget(gun: Tool, key: any): {[string]: any}?
        if (key ~= "Hit" and key ~= "Target") or not observedGunSignature(gun)
            or type(host.checkcaller) ~= "function" then return nil end
        local ok: boolean, executorCaller: any = pcall(host.checkcaller)
        if not ok or executorCaller ~= false then return nil end
        local shot: any = runtimeState.mouseShot
        if shot and os.clock() < shot.expires and shot.gun == gun
            and localPlayer.Character == shot.character
            and matchToken(localPlayer) == shot.match then
            return validSilentTarget(shot.target)
        end
        if settings.mouseCompatibility then return selectedTarget() end
        return nil
    end

    -- Raw metatable fallback for executors without a working hookmetamethod.
    -- Preserve the original read-only state and never replace a newer wrapper.
    local function replaceRawMouseIndex(meta: any, expected: any, replacement: any, readonly: boolean): boolean
        local readable: boolean, current: any = pcall(function(): any return meta.__index end)
        if not readable or current ~= expected then return false end
        local opened: boolean = pcall(host.setreadonly, meta, false)
        if not opened then return false end
        local changed: boolean = pcall(function(): ()
            if meta.__index == expected then meta.__index = replacement end
        end)
        local restored: boolean = pcall(host.setreadonly, meta, readonly)
        local checked: boolean, installed: any = pcall(function(): any return meta.__index end)
        return changed and restored and checked and installed == replacement
    end

    local function installMouseIndexHook(wrap: any): ()
        if runtimeState.mouseHookInstalled then return end
        local mouseOk: boolean, mouse: any = pcall(function(): any return localPlayer:GetMouse() end)
        if not mouseOk or mouse == nil then return end
        local predecessor: any = nil
        local lease: any = {active = true}
        local wrapper: any = wrap(function(object: any, key: any): any
            if predecessor == nil then return nil end
            if not lease.active then return predecessor(object, key) end
            if object == mouse and (key == "Hit" or key == "Target" or key == "UnitRay")
                and settings.silentAim and os.clock() >= runtimeState.nativeAimUntil then
                local ok: boolean, value: any = pcall(function(): any
                    local gun: Tool? = equippedTool()
                    if not gun or toolKind(gun) ~= "Gun" then return nil end
                    local identified: boolean, foreign: boolean = isWeaponCaller(gun)
                    if foreign then return nil end
                    local target: {[string]: any}? = if identified then selectedTarget()
                        else anonymousMouseTarget(gun, key)
                    if not target or (settings.wallCheck and not hasLineOfSight(target, gunOrigin(gun))) then
                        return nil
                    end
                    if key == "Hit" then
                        runtimeState.redirectCount += 1
                        return CFrame.new(target.part.Position)
                    elseif key == "Target" then
                        runtimeState.redirectCount += 1
                        return target.part
                    end
                    local oldRay: any = predecessor(object, key)
                    if typeof(oldRay) ~= "Ray" or host.Ray == nil then return nil end
                    local delta: Vector3 = target.part.Position - oldRay.Origin
                    if delta.Magnitude < 0.05 then return nil end
                    runtimeState.redirectCount += 1
                    return host.Ray.new(oldRay.Origin, delta.Unit)
                end)
                if ok and value ~= nil then return value end
            end
            return predecessor(object, key)
        end)
        local hook: any = host.hookmetamethod
        if type(hook) == "function" then
            local ok: boolean, old: any = pcall(hook, game, "__index", wrapper)
            if ok and type(old) == "function" then
                predecessor = old
                runtimeState.oldMouseIndex = old
                runtimeState.mouseIndexWrapper = wrapper
                runtimeState.mouseHookLease = lease
                runtimeState.mouseHookKind = "hookmetamethod"
                runtimeState.mouseHookInstalled = true
                return
            end
        end
        if type(host.getrawmetatable) == "function" and type(host.setreadonly) == "function"
            and type(host.isreadonly) == "function" then
            local gotMeta: boolean, meta: any = pcall(host.getrawmetatable, game)
            local gotReadonly: boolean, readonly: any = false, nil
            if gotMeta and type(meta) == "table" then
                gotReadonly, readonly = pcall(host.isreadonly, meta)
            end
            local gotOld: boolean, old: any = false, nil
            if gotReadonly and type(readonly) == "boolean" then
                gotOld, old = pcall(function(): any return meta.__index end)
            end
            if gotOld and type(old) == "function" then
                predecessor = old
                if replaceRawMouseIndex(meta, old, wrapper, readonly) then
                    runtimeState.oldMouseIndex = old
                    runtimeState.mouseIndexWrapper = wrapper
                    runtimeState.mouseHookLease = lease
                    runtimeState.mouseHookKind = "raw"
                    runtimeState.mouseMetatable = meta
                    runtimeState.mouseReadonly = readonly
                    runtimeState.mouseHookInstalled = true
                    return
                end
                -- A partial failure must not leave an active anonymous hook.
                lease.active = false
                replaceRawMouseIndex(meta, wrapper, old, readonly)
            end
        end
        lease.active = false
    end

    local function redirectAutoGunRay(origin: Vector3, direction: Vector3, params: any): Vector3?
        local lease: any = runtimeState.autoAimLease
        if not lease or not ((lease.owner == "Auto Shoot" and settings.autoShoot)
                or (lease.owner == "Auto Win" and settings.autoWin)) or os.clock() > lease.expires
            or runtimeState.suppressRaycast or lease.gun.Parent ~= localPlayer.Character
            or lease.character ~= localPlayer.Character or matchToken(localPlayer) ~= lease.gameToken then return nil end
        if typeof(params) ~= "RaycastParams" or params.FilterType ~= Enum.RaycastFilterType.Exclude
            or math.abs(direction.Magnitude - 10000) > 25 then return nil end
        -- Unlike broad Silent compatibility, automation never falls back to
        -- stack guesses or anonymous callers for a camera-sensitive cast.
        local gotCaller: boolean, caller: any = pcall(host.getcallingscript)
        if not gotCaller or typeof(caller) ~= "Instance"
            or not caller.IsDescendantOf(caller, lease.gun) then return nil end
        local target: any = lease.target
        local root: BasePart? = rootOf(localPlayer.Character)
        if not root or (origin - root.Position).Magnitude > 8 or not target or not target.player
            or target.player.Character ~= target.character or not target.part or not target.part.Parent
            or not target.part.IsDescendantOf(target.part, target.character)
            or not isEnemy(target.player, false, lease.teamCheck)
            or (target.part.Position - root.Position).Magnitude > lease.range then return nil end
        if lease.wallCheck then
            runtimeState.suppressRaycast = true
            local ok: boolean, clear: any = pcall(hasLineOfSight, target, origin)
            runtimeState.suppressRaycast = false
            if not ok or not clear then return nil end
        end
        local offset: Vector3 = target.part.Position - origin
        if offset.Magnitude < 0.05 or offset.Magnitude > direction.Magnitude then return nil end
        return offset.Unit * direction.Magnitude
    end

    -- One OTH __namecall bridge is shared by Silent and the optional passive
    -- probe. No __index / direct-function hooks or legacy fallback are added.
    local function installOthRaycast(forSilent: boolean?): boolean
        local record: any = runtimeState.othRaycast
        if record then
            if forSilent ~= false then record.active = true end
            return true
        end
        local othApi: any = host.oth
        if type(othApi) ~= "table" or type(othApi.hook) ~= "function"
            or type(host.getrawmetatable) ~= "function" or type(host.getnamecallmethod) ~= "function"
            or type(host.checkcaller) ~= "function" then return false end
        local got: boolean, meta: any = pcall(host.getrawmetatable, game)
        if not got or type(meta) ~= "table" or type(meta.__namecall) ~= "function" then return false end
        local predecessor: any = nil
        record = {active = forSilent ~= false, target = meta.__namecall}
        local callback: any = function(object: any, ...: any): any
            if not predecessor then return nil end
            local observer: any = runtimeState.othProbeObserver
            local autoLease: any = runtimeState.autoAimLease
            local autoActive: boolean = autoLease ~= nil and not autoLease.consumed and os.clock() <= autoLease.expires
                and ((autoLease.owner == "Auto Shoot" and settings.autoShoot)
                    or (autoLease.owner == "Auto Win" and settings.autoWin))
            if runtimeState.closed or (not record.active and not autoActive and type(observer) ~= "function") then
                return predecessor(object, ...)
            end
            local methodOk: boolean, method: any = pcall(host.getnamecallmethod)
            if not methodOk or (type(observer) ~= "function" and (method ~= "Raycast" or object ~= currentWorkspace)) then
                return predecessor(object, ...)
            end
            local args: any = table.pack(...)
            local interesting: boolean = method == "Raycast" or method == "FindPartOnRay"
                or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist"
                or method == "ScreenPointToRay" or method == "ViewportPointToRay"
                or method == "FireServer" or method == "InvokeServer"
            if not methodOk or not interesting or runtimeState.suppressRaycast then
                return predecessor(object, unpack(args, 1, args.n))
            end
            local callerOk: boolean, executorCaller: any = pcall(host.checkcaller)
            if not callerOk or executorCaller ~= false then return predecessor(object, unpack(args, 1, args.n)) end
            if type(observer) == "function" then pcall(observer, object, method, args, false) end
            if object == currentWorkspace and method == "Raycast"
                and typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
                -- Camera and ping casts are returned immediately when caller
                -- identification is available, including in compatibility mode.
                local callerKnown: boolean = false
                if type(host.getcallingscript) == "function" then
                    local gotCaller: boolean, caller: any = pcall(host.getcallingscript)
                    if gotCaller and typeof(caller) == "Instance" then
                        callerKnown = true
                        -- CameraModule has child modules such as ZoomController;
                        -- check ancestors too, not only the immediate script name.
                        local ancestor: Instance? = caller
                        for _ = 1, 32 do
                            if not ancestor then break end
                            local callerName: string = string.lower(tostring(ancestor.Name or ""))
                            if string.find(callerName, "camera", 1, true) or string.find(callerName, "ping", 1, true) then
                                return predecessor(object, unpack(args, 1, args.n))
                            end
                            ancestor = ancestor.Parent
                        end
                    end
                end
                -- Anonymous compatibility cannot distinguish a camera ray.
                if not autoActive and settings.raycastCompatibility and not callerKnown then
                    return predecessor(object, unpack(args, 1, args.n))
                end
                local ok: boolean, direction: any = false, nil
                if autoActive then
                    ok, direction = pcall(redirectAutoGunRay, args[1], args[2], args[3])
                elseif record.active and settings.silentAim then
                    ok, direction = pcall(redirectRay, args[1], args[2], true)
                end
                if ok and typeof(direction) == "Vector3" then
                    args[2] = direction
                    if autoActive then
                        runtimeState.autoRedirectSerial = (runtimeState.autoRedirectSerial or 0) + 1
                        if runtimeState.autoAimLease == autoLease then autoLease.consumed = true end
                    else runtimeState.othRedirectSerial = (runtimeState.othRedirectSerial or 0) + 1 end
                    if type(observer) == "function" then pcall(observer, object, method, args, true) end
                end
            end
            return predecessor(object, unpack(args, 1, args.n))
        end
        local ok: boolean, old: any = pcall(othApi.hook, record.target, callback)
        if not ok or type(old) ~= "function" then record.active = false; return false end
        predecessor, record.callback, record.predecessor = old, callback, old
        runtimeState.othRaycast = record
        return true
    end

    ensureAutoOth = function(): boolean return installOthRaycast(false) end

    local function installHooks(): boolean
        if settings.silentBackend == "Oth" then return installOthRaycast() end
        local hookFunction: any = host.hookfunction
        local debugApi: any = host.debug
        local canIdentifyCaller: boolean = type(host.getcallingscript) == "function"
            or (type(debugApi) == "table" and type(debugApi.info) == "function")
        local newClosure: any = host.newcclosure
        local function wrap(callback: any): any
            if type(newClosure) == "function" then
                local ok: boolean, wrapped: any = pcall(newClosure, callback)
                if ok and type(wrapped) == "function" then return wrapped end
            end
            return callback
        end
        installMouseIndexHook(wrap)
        -- Shared ray/MouseCast/Knife paths still require provenance; only the
        -- tightly scoped Mouse fallback can operate without this capability.
        if not canIdentifyCaller then return runtimeState.mouseHookInstalled end
        installKnifeHook(wrap)
        if type(hookFunction) ~= "function" then return runtimeState.mouseHookInstalled end

        if not runtimeState.rayHookInstalled and host.Ray ~= nil then
            local predecessor: any = nil
            local lease: any = {active = true}
            local callback: any = function(origin: any, direction: any): any
                if predecessor == nil then
                    return nil
                end
                if not lease.active then return predecessor(origin, direction) end
                if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    local redirected: Vector3? = redirectRay(origin, direction)
                    if redirected then
                        return predecessor(origin, redirected)
                    end
                end
                return predecessor(origin, direction)
            end
            local wrapper: any = wrap(callback)
            local ok: boolean, old: any = pcall(hookFunction, host.Ray.new, wrapper)
            if ok and old ~= nil then
                runtimeState.oldRay = old
                runtimeState.rayWrapper = wrapper
                runtimeState.rayHookLease = lease
                runtimeState.rayHookInstalled = true
                predecessor = old
            end
        end

        if not runtimeState.raycastHookInstalled then
            local method: any = currentWorkspace.Raycast
            if type(method) == "function" then
                local predecessor: any = nil
                local lease: any = {active = true}
                local callback: any = function(self: any, ...: any): any
                    if predecessor == nil then
                        return nil
                    end
                    if not lease.active then return predecessor(self, ...) end
                    if runtimeState.suppressRaycast then
                        return predecessor(self, ...)
                    end
                    local arguments: {any} = {...}
                    local origin: any = arguments[1]
                    local direction: any = arguments[2]
                    if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                        local redirected: Vector3? = redirectRay(origin, direction)
                        if redirected then
                            arguments[2] = redirected
                            return predecessor(self, unpack(arguments))
                        end
                    end
                    return predecessor(self, ...)
                end
                local wrapper: any = wrap(callback)
                local ok: boolean, old: any = pcall(hookFunction, method, wrapper)
                if ok and old ~= nil then
                    runtimeState.oldRaycast = old
                    runtimeState.raycastWrapper = wrapper
                    runtimeState.raycastHookLease = lease
                    runtimeState.raycastHookInstalled = true
                    predecessor = old
                end
            end
        end
        return runtimeState.mouseHookInstalled
            or runtimeState.rayHookInstalled or runtimeState.raycastHookInstalled
    end

    local function uninstallHooks(): ()
        if settings.silentBackend == "Oth" then
            -- OTH unhook semantics differ by executor; some remove all later
            -- hooks even when given a callback. Keep one inert, reusable node
            -- instead of displacing a foreign hook. Rejoin clears it.
            local record: any = runtimeState.othRaycast
            if record then record.active = false end
            return
        end
        -- Wrappers retained inside a later foreign hook must stay inert even if
        -- Silent is enabled again; never resurrect a retired chain node.
        for _, key: string in ipairs({"mouseHookLease", "knifeHookLease", "rayHookLease", "raycastHookLease"}) do
            local lease: any = runtimeState[key]
            if lease then lease.active = false end
        end
        if runtimeState.mouseHookInstalled and runtimeState.mouseHookKind == "raw"
            and runtimeState.mouseMetatable and type(host.setreadonly) == "function" then
            replaceRawMouseIndex(runtimeState.mouseMetatable, runtimeState.mouseIndexWrapper,
                runtimeState.oldMouseIndex, runtimeState.mouseReadonly)
        elseif runtimeState.mouseHookInstalled and runtimeState.mouseHookKind == "hookmetamethod"
            and type(host.hookmetamethod) == "function" then
            local ok: boolean, displaced: any = pcall(
                host.hookmetamethod, game, "__index", runtimeState.oldMouseIndex
            )
            if ok and displaced ~= runtimeState.mouseIndexWrapper and type(displaced) == "function" then
                pcall(host.hookmetamethod, game, "__index", displaced)
            end
            if ok then
                runtimeState.mouseHookInstalled = false
                runtimeState.oldMouseIndex = nil
                runtimeState.mouseIndexWrapper = nil
            end
        end
        if runtimeState.knifeHookInstalled and type(host.hookmetamethod) == "function" then
            local ok: boolean, displaced: any = pcall(
                host.hookmetamethod, game, "__namecall", runtimeState.oldNamecall
            )
            if ok and displaced ~= runtimeState.knifeWrapper and type(displaced) == "function" then
                pcall(host.hookmetamethod, game, "__namecall", displaced)
            end
            if ok then
                runtimeState.knifeHookInstalled = false
                runtimeState.oldNamecall = nil
                runtimeState.knifeWrapper = nil
            end
        end
        local hookFunction: any = host.hookfunction
        if type(hookFunction) == "function" and runtimeState.rayHookInstalled and host.Ray ~= nil then
            local ok: boolean, displaced: any = pcall(
                hookFunction, host.Ray.new, runtimeState.oldRay
            )
            -- If another script hooked after us, put its hook back instead of
            -- deleting it while removing ours from the chain.
            if ok and displaced ~= runtimeState.rayWrapper
                and type(displaced) == "function" then
                pcall(hookFunction, host.Ray.new, displaced)
            end
            if ok then
                runtimeState.rayHookInstalled = false
                runtimeState.oldRay = nil
                runtimeState.rayWrapper = nil
            end
        end
        if type(hookFunction) == "function" and runtimeState.raycastHookInstalled then
            local ok: boolean, displaced: any = pcall(
                hookFunction, currentWorkspace.Raycast, runtimeState.oldRaycast
            )
            if ok and displaced ~= runtimeState.raycastWrapper
                and type(displaced) == "function" then
                pcall(hookFunction, currentWorkspace.Raycast, displaced)
            end
            if ok then
                runtimeState.raycastHookInstalled = false
                runtimeState.oldRaycast = nil
                runtimeState.raycastWrapper = nil
            end
        end
        -- A failed restoration leaves an inert node behind, not a falsely
        -- advertised live adapter. A later enable can install a fresh node.
        runtimeState.mouseHookInstalled = false
        runtimeState.knifeHookInstalled = false
        runtimeState.rayHookInstalled = false
        runtimeState.raycastHookInstalled = false
        runtimeState.oldMouseIndex, runtimeState.mouseIndexWrapper, runtimeState.mouseHookLease = nil, nil, nil
        runtimeState.mouseHookKind, runtimeState.mouseMetatable, runtimeState.mouseReadonly = nil, nil, nil
        runtimeState.oldNamecall, runtimeState.knifeWrapper, runtimeState.knifeHookLease = nil, nil, nil
        runtimeState.oldRay, runtimeState.rayWrapper, runtimeState.rayHookLease = nil, nil, nil
        runtimeState.oldRaycast, runtimeState.raycastWrapper, runtimeState.raycastHookLease = nil, nil, nil
    end

    local function registerWin(): boolean
        if runtimeState.lastWinRound == runtimeState.roundSerial
            or runtimeState.lastLossRound == runtimeState.roundSerial then
            return false
        end
        runtimeState.lastWinRound = runtimeState.roundSerial
        runtimeState.wins += 1
        return true
    end

    local function registerLoss(): boolean
        if runtimeState.lastLossRound == runtimeState.roundSerial
            or runtimeState.lastWinRound == runtimeState.roundSerial then
            return false
        end
        runtimeState.lastLossRound = runtimeState.roundSerial
        runtimeState.loses += 1
        return true
    end

    local function formatTimePlayed(seconds: number): string
        local total: number = math.max(0, math.floor(seconds))
        local hours: number = math.floor(total / 3600)
        local minutes: number = math.floor((total % 3600) / 60)
        local remainder: number = total % 60
        return string.format("%02d:%02d:%02d", hours, minutes, remainder)
    end

    local function currentGameMode(): string
        if not matchToken(localPlayer) then return "Lobby / unknown" end
        local gameOk: boolean, gameData: any = matchApiCall("getGame", localPlayer)
        if not gameOk or type(gameData) ~= "table" then return "Lobby / unknown" end
        local ok: boolean, mode: any = matchApiCall("getMode", localPlayer)
        if ok and rules.normalizeToken(mode) == "ffa" then return "FFA" end
        if game.PlaceId == 124848751642883 then return "1v1" end
        if game.PlaceId == 92876937625630 then return "2v2" end
        return ok and type(mode) == "string" and mode or "Unknown"
    end

    local function updateStats(): ()
        local elapsed: number = runtimeState.autoWinElapsed
        if settings.autoWin and runtimeState.autoWinStartedAt then
            elapsed += math.max(0, os.clock() - runtimeState.autoWinStartedAt)
        end
        if autoWinStats.time then autoWinStats.time.set(formatTimePlayed(elapsed)) end
        if autoWinStats.won then autoWinStats.won.set(tostring(runtimeState.duelsWon)) end
        if autoWinStats.mode then autoWinStats.mode.set(currentGameMode()) end
        if autoWinStats.status then
            autoWinStats.status.set(settings.autoWin and runtimeState.autoWinStatus or "Off")
        end
        if autoWinStats.safe then
            autoWinStats.safe.set(not settings.safePlace and "Off"
                or (not settings.autoWin and "Enable Auto Win"
                    or (runtimeState.safe and "Holding" or "Unavailable")))
        end
        if autoWinStats.rematch then autoWinStats.rematch.set(runtimeState.rematchStatus) end
        if autoWinCard and type(autoWinCard.SetStatus) == "function" then
            autoWinCard:SetStatus(settings.autoWin and runtimeState.autoWinStatus or nil)
        end
    end

    local function setAutoWinStatus(text: string): ()
        if settings.safePlace and not runtimeState.safe then
            text ..= " · Safe Place unavailable"
        end
        if runtimeState.autoWinStatus ~= text then
            runtimeState.autoWinStatus = text
            updateStats()
        end
    end

    local function localMatchId(): string?
        local ok: boolean, id: any = matchApiCall("getMatchId", localPlayer)
        if ok and (type(id) == "string" or type(id) == "number") and tostring(id) ~= "" then
            return tostring(id)
        end
        return nil
    end

    local function leaveSafePlace(returnToOrigin: boolean): ()
        local safe: any = runtimeState.safe
        runtimeState.safe = nil
        if not safe then return end
        if safe.hold then pcall(function(): () safe.hold:Destroy() end) end
        local maps: Instance? = currentWorkspace:FindFirstChild("ActiveMaps")
        if returnToOrigin and safe.matchId == localMatchId()
            and safe.gameId == matchToken(localPlayer) and safe.map
            and maps and safe.map.Parent == maps
            and safe.root and safe.root.Parent and localPlayer.Character == safe.character
            and isAlive(localPlayer) then
            pcall(function(): ()
                safe.root.CFrame = safe.original
                safe.root.AssemblyLinearVelocity = Vector3.zero
                safe.root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end

    local function safeHeight(map: Instance, root: BasePart): number?
        local highest: number? = nil
        for _, instance: Instance in ipairs(map:GetDescendants()) do
            if instance:IsA("BasePart") then
                local part: BasePart = instance :: BasePart
                local position: Vector3 = part.Position
                local size: Vector3 = part.Size
                if typeof(position) == "Vector3" and typeof(size) == "Vector3"
                    and (position - root.Position).Magnitude <= 1000 then
                    local frame: CFrame = part.CFrame
                    local extent: number = (math.abs(frame.RightVector.Y) * size.X
                        + math.abs(frame.UpVector.Y) * size.Y
                        + math.abs(frame.LookVector.Y) * size.Z) * 0.5
                    local top: number = position.Y + extent
                    if top == top then
                        -- Do not silently ignore an extremely high roof and
                        -- call a position below it safe; fail closed instead.
                        if top >= root.Position.Y + 400 then return nil end
                        highest = highest and math.max(highest, top) or top
                    end
                end
            end
        end
        if not highest then return nil end
        return math.max(highest, root.Position.Y) + 35
    end

    local function updateSafePlace(): ()
        if not settings.autoWin or not settings.safePlace then
            leaveSafePlace(true)
            return
        end
        local matchId: string? = localMatchId()
        local gameId: string? = matchToken(localPlayer)
        local gameOk: boolean, gameData: any = matchApiCall("getGame", localPlayer)
        local character: Model? = localPlayer.Character
        local root: BasePart? = rootOf(character)
        local maps: Instance? = currentWorkspace:FindFirstChild("ActiveMaps")
        local map: Instance? = maps and matchId and maps:FindFirstChild(matchId)
        if not matchId or not gameId or not gameOk or type(gameData) ~= "table"
            or gameData.Phase ~= "InGame" or runtimeState.resultsPending
            or not map or not root or root.Anchored == true or not isAlive(localPlayer) then
            leaveSafePlace(false)
            return
        end
        local safe: any = runtimeState.safe
        if safe and safe.matchId == matchId and safe.gameId == gameId and safe.map == map
            and safe.root == root and safe.hold and safe.hold.Parent == root then return end
        leaveSafePlace(false)
        local now: number = os.clock()
        if now < (runtimeState.nextSafeAt or 0) then return end
        runtimeState.nextSafeAt = now + 1
        local height: number? = safeHeight(map, root)
        if not height then return end
        local position: Vector3 = Vector3.new(root.Position.X, height, root.Position.Z)
        local ok: boolean, hold: any = pcall(function(): any
            local body: BodyPosition = Instance.new("BodyPosition")
            body.Name = "WurstX2SafePlace"
            body.Position = position
            body.MaxForce = Vector3.new(200000, 200000, 200000)
            body.P = 15000
            body.D = 1500
            body.Parent = root
            return body
        end)
        if not ok or not hold then return end
        runtimeState.safe = {
            hold = hold, root = root, character = character, map = map,
            matchId = matchId, gameId = gameId, original = root.CFrame,
        }
        local moved: boolean = pcall(function(): ()
            root.CFrame = CFrame.new(position)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        if not moved then leaveSafePlace(false) end
    end

    local function resultIdentity(): {[string]: any}
        return {
            player = localPlayer,
            userId = localPlayer.UserId,
            name = localPlayer.Name,
            displayName = localPlayer.DisplayName,
            team = teamToken(localPlayer),
        }
    end

    local function playerFromEventValue(value: any): Player?
        if typeof(value) ~= "Instance" then
            return nil
        end
        if value:IsA("Player") then
            return value :: Player
        end
        if value:IsA("Model") then
            local ok: boolean, player: any = pcall(function(): any
                return players:GetPlayerFromCharacter(value :: Model)
            end)
            if ok and player then
                return player :: Player
            end
        end
        return nil
    end

    local function playerFromEvent(arguments: {any}): Player?
        -- Cobalt captured PlayerRespawned with different argument layouts,
        -- including nil, Player. Never assume the Player is argument one.
        for _, value: any in pairs(arguments) do
            local player: Player? = playerFromEventValue(value)
            if player then
                return player
            end
        end
        return nil
    end

    local function onMatchResults(...: any): ()
        local arguments: {any} = {...}
        local resultId: any = arguments[1]
        local outcome: string? = rules.matchResultOutcome(arguments)
        if type(resultId) == "string" then
            local seen: any = runtimeState.seenResultIds[resultId]
            if seen == "final" or (seen and outcome == nil) then return end
            -- An incomplete/unknown schema must not prevent a later genuine
            -- final outcome for the same match from being counted.
            runtimeState.seenResultIds[resultId] = outcome ~= nil and "final" or "other"
        end
        leaveSafePlace(true)
        runtimeState.resultsPending = true
        runtimeState.observedRound = false
        runtimeState.selected = nil
        cancelKnifeThrow()
        if outcome == "Win" and settings.autoWin then
            -- MatchResults has a match ID and a local final outcome. This is
            -- deliberately separate from per-round WinNotification counts.
            runtimeState.duelsWon += 1
        end
        if outcome == "Win" or (outcome == nil
            and rules.didLocalWin(arguments, resultIdentity(), false)) then
            runtimeState.resultWinCounted = true
            registerWin()
        elseif outcome == "Loss" then
            registerLoss()
        end
        updateStats()
    end

    local function onRemovePlayer(...: any): ()
        local arguments: {any} = {...}
        local removed: Player? = playerFromEvent(arguments)
        if removed and removed ~= localPlayer then
            return
        end
        -- RemovePlayer ends a round; it is not itself a victory or loss.
        leaveSafePlace(false)
        runtimeState.resultsPending = true
        runtimeState.observedRound = false
        runtimeState.selected = nil
        cancelKnifeThrow()
    end

    local function onWinNotification(...: any): ()
        if not runtimeState.observedRound or runtimeState.resultsPending then return end
        local count: number = select("#", ...)
        local value: any = select(1, ...)
        -- InGameUI uses p36 == nil for RoundWon and either boolean for
        -- RoundLost. A Player death alone does not mean a team lost its round.
        if count == 0 or (count == 1 and value == nil) then
            if registerWin() then runtimeState.resultWinCounted = true end
        elseif count == 1 and type(value) == "boolean" then
            registerLoss()
        elseif rules.didLocalWin({...}, resultIdentity(), true) then
            if registerWin() then runtimeState.resultWinCounted = true end
        end
        updateStats()
    end

    local function onSetDead(...: any): ()
        local arguments: {any} = {...}
        local dead: Player? = playerFromEvent(arguments)
        if not dead then
            return
        end
        runtimeState.deadPlayers[dead] = true
        local selected: any = runtimeState.selected
        if selected and selected.player == dead then
            runtimeState.selected = nil
        end
        if dead == localPlayer then
            -- A team can still win after this player dies; SetDead is not a
            -- round-loss event. WinNotification/MatchResults own outcomes.
            leaveSafePlace(false)
            cancelKnifeThrow()
            restoreCamera()
            updateStats()
        end
    end

    local function countLocalKill(killer: Player?, victim: Player?): ()
        if killer == localPlayer and victim and victim ~= localPlayer
            and runtimeState.killVictims[victim] ~= runtimeState.roundSerial then
            runtimeState.killVictims[victim] = runtimeState.roundSerial
            runtimeState.kills += 1
            updateStats()
        end
    end

    local function onKilled(...: any): ()
        -- The new log and InGameUI both use Killed(killer, victim).
        local arguments: {any} = {...}
        countLocalKill(playerFromEventValue(arguments[1]), playerFromEventValue(arguments[2]))
    end

    local function onDestroyBody(...: any): ()
        -- DestroyBody(victim, character, killer) follows Killed in the log.
        -- Both events share the same per-victim/round deduplication.
        local arguments: {any} = {...}
        countLocalKill(playerFromEventValue(arguments[3]), playerFromEventValue(arguments[1]))
    end

    local function onPlayerRespawned(...: any): ()
        local arguments: {any} = {...}
        local respawned: Player? = playerFromEvent(arguments)
        if not respawned then return end
        runtimeState.deadPlayers[respawned] = nil
        runtimeState.killVictims[respawned] = nil
        if respawned ~= localPlayer then
            -- Another player's respawn must not reset our session statistics.
            return
        end
        local character: any = arguments[1]
        local now: number = os.clock()
        if typeof(character) == "Instance" and character == runtimeState.lastRespawnCharacter
            and now - (runtimeState.lastRespawnAt or 0) < 0.5 then return end
        runtimeState.lastRespawnCharacter = character
        runtimeState.lastRespawnAt = now
        leaveSafePlace(false)
        runtimeState.nextSafeAt = 0
        runtimeState.lastMatchToken = matchToken(localPlayer)
        runtimeState.roundSerial += 1
        runtimeState.observedRound = true
        runtimeState.resultsPending = false
        runtimeState.resultWinCounted = false
        runtimeState.nextGunAt = 0
        runtimeState.nextKnifeAt["Auto Win"] = 0
        runtimeState.nextKnifeAt["Knife Throw"] = 0
        cancelKnifeThrow()
    end

    local function findRemote(path: string): Instance?
        -- The captured place uses Packages.Networking["RE/Match/SetDead"],
        -- not Networking.RE.Match.SetDead. Keep nested folders as a fallback.
        local prefix: string = "Packages/Networking/"
        if string.sub(path, 1, #prefix) == prefix then
            local packages: Instance? = replicated:FindFirstChild("Packages")
            local networking: Instance? = packages and packages:FindFirstChild("Networking")
            local flat: Instance? = networking
                and networking:FindFirstChild(string.sub(path, #prefix + 1))
            if flat then return flat end
        end
        local current: Instance? = replicated
        for segment: string in string.gmatch(path, "[^/]+") do
            current = current and current:FindFirstChild(segment)
        end
        return current
    end

    local function processRematch(now: number): ()
        if not settings.rematch and not runtimeState.rematchVoted then
            runtimeState.rematchStatus = "Off"
            return
        end
        local globals: any = runtimeState.clientGlobals
        local values: any = globals and globals.GameValues
        local status: string = not settings.rematch and "Off"
            or (not settings.autoWin and "Enable Auto Win" or "Waiting for state")
        runtimeState.rematchStatus = status
        if not values or type(values.TryIndex) ~= "function" then return end
        local ok: boolean, rematch: any = pcall(values.TryIndex, values, {"Rematch"})
        if not ok or type(rematch) ~= "table" then return end
        if rematch.active ~= true then
            runtimeState.rematchVoted = false
            if settings.autoWin and settings.rematch then runtimeState.rematchStatus = "Waiting" end
            return
        end
        if not settings.autoWin or not settings.rematch then return end
        if rematch.cancelled == true then
            runtimeState.rematchStatus = "Cancelled"
            return
        end
        local voters: any = rematch.voters
        if type(voters) == "table"
            and (voters[localPlayer.UserId] or voters[tostring(localPlayer.UserId)]) then
            runtimeState.rematchVoted = true
            runtimeState.rematchStatus = "Already voted"
            return
        end
        if runtimeState.rematchVoted then
            runtimeState.rematchStatus = "Vote sent"
            return
        end
        if now < (runtimeState.nextRematchAt or 0) then
            runtimeState.rematchStatus = "Retrying"
            return
        end
        runtimeState.nextRematchAt = now + 2
        local remote: Instance? = findRemote("Packages/Networking/RE/Rematch/RematchVote")
        if remote and remote:IsA("RemoteEvent") then
            -- MatchmakingController and the captured log both send zero args,
            -- once per active rematch. This is not the combat hit remote.
            local sent: boolean = pcall(function(): () (remote :: any):FireServer() end)
            if sent then
                runtimeState.rematchVoted = true
                runtimeState.rematchStatus = "Vote sent"
            else
                runtimeState.rematchStatus = "Vote failed"
            end
        else
            runtimeState.rematchStatus = "Remote unavailable"
        end
    end

    local function connectRemote(path: string, callback: any): ()
        local remote: Instance? = findRemote(path)
        local bound: any = runtimeState.remoteBound[path]
        if bound and bound.remote == remote and bound.connection.Connected then return end
        if bound then
            pcall(function(): () bound.connection:Disconnect() end)
            runtimeState.remoteBound[path] = nil
        end
        if not remote or not remote:IsA("RemoteEvent") then return end
        local ok: boolean, connection: any = pcall(function(): any
            return (remote :: any).OnClientEvent:Connect(callback)
        end)
        if ok and connection then
            runtimeState.remoteBound[path] = {remote = remote, connection = connection}
            track(connection)
        end
    end

    local function ensureRemoteEvents(): ()
        connectRemote("Packages/Networking/RE/Match/MatchResults", onMatchResults)
        connectRemote("Packages/Networking/RE/Match/RemovePlayer", onRemovePlayer)
        connectRemote("Packages/Networking/RE/Match/WinNotification", onWinNotification)
        connectRemote("Packages/Networking/RE/Match/SetDead", onSetDead)
        connectRemote("Packages/Networking/RE/Match/PlayerRespawned", onPlayerRespawned)
        connectRemote("Packages/Networking/RE/Combat/Killed", onKilled)
        connectRemote("Packages/Networking/RE/Combat/DestroyBody", onDestroyBody)
    end

    local function activeRound(): boolean
        if not matchToken(localPlayer) or runtimeState.resultsPending or not isAlive(localPlayer) then
            return false
        end
        local ok: boolean, gameData: any = matchApiCall("getGame", localPlayer)
        return ok and type(gameData) == "table" and gameData.Phase == "InGame"
            and gameData.RoundStarted == true and gameData.CurrentRoundEnded ~= true
    end

    local function runGun(
        maxDistance: number, cooldown: number?, teamCheck: boolean, wallCheck: boolean, owner: string
    ): (boolean, boolean, string?)
        if cooldown ~= nil then
            local gun: Tool? = findWeapon("Gun")
            local nativeInterval: number = owner == "Auto Shoot" and gun and gun.Name == "MimicGlare" and 2.5 or 0
            runtimeState.nextGunAt = os.clock() + math.max(0, cooldown, nativeInterval)
        end
        local localRoot: BasePart? = rootOf(localPlayer.Character)
        local origin: Vector3? = settings.autoShootBackend == "CFrame" and localRoot
            and localRoot.Position or gunOrigin(findWeapon("Gun"))
        local target: {[string]: any}?, why: string? = nearestEnemy(
            maxDistance, teamCheck, wallCheck, false, origin
        )
        if not target then return false, findWeapon("Gun") ~= nil, why end
        local fired: boolean, hasGun: boolean, reason: string? = fireGun(target, false, {
            owner = owner, teamCheck = teamCheck, wallCheck = wallCheck, range = maxDistance,
            isActive = function(): boolean
                return owner == "Auto Shoot" and settings.autoShoot
                    or owner == "Auto Win" and settings.autoWin and activeRound()
            end,
        })
        return fired, hasGun, reason
    end

    local function runKnifeThrow(
        maxDistance: number, cooldown: number, teamCheck: boolean, wallCheck: boolean, owner: string
    ): (boolean, boolean, string?)
        if settings.knifeBackend == "CFrame" then
            local knife: Tool? = findWeapon("Knife")
            local handle: Instance? = knife and knife:FindFirstChild("Handle")
            local root: BasePart? = rootOf(localPlayer.Character)
            local origin: Vector3? = handle and handle:IsA("BasePart") and (handle :: BasePart).Position
                or (root and root.Position)
            local target: any, why: string? = nearestEnemy(maxDistance, teamCheck, wallCheck, false, origin)
            if not target then return false, false, why end
            local queued: boolean, message: string? = queueCFrameKnife(target, {
                owner = owner, teamCheck = teamCheck, wallCheck = wallCheck, range = maxDistance, cooldown = cooldown,
                isActive = function(): boolean
                    return owner == "Knife Throw" and settings.knifeThrow
                        or owner == "Auto Win" and settings.autoWin and activeRound()
                end,
            })
            return queued, target ~= nil, message
        end
        if settings.silentAim then return false, false, "Paused: Silent AIM protects the camera." end
        local target: {[string]: any}?, why: string? = nearestEnemy(maxDistance, teamCheck, wallCheck, false)
        local queued: boolean = fireKnife(target, false, {
            owner = owner, teamCheck = teamCheck, wallCheck = wallCheck,
            range = maxDistance, cooldown = cooldown,
        })
        return queued, target ~= nil, why
    end

    local function runKillAura(): ()
        runtimeState.nextAuraAt = os.clock() + settings.killAuraInterval
        local knife: Tool? = findWeapon("Knife")
        if not knife then
            return
        end
        local target: {[string]: any}? = nearestEnemy(
            settings.killAuraRange, settings.killAuraTeamCheck, settings.killAuraWallCheck, false
        )
        if target and equip(knife) then
            activateNative(knife, target)
        end
    end

    local function restoreHitbox(player: Player): ()
        local record: any = runtimeState.hitboxes[player]
        runtimeState.hitboxes[player] = nil
        if record and record.part then
            pcall(function(): ()
                record.part.Size = record.size
                record.part.Transparency = record.transparency
                record.part.CanCollide = record.canCollide
                record.part.CanQuery = record.canQuery
            end)
        end
    end

    local function restoreAllHitboxes(): ()
        for player: Player, _record: any in pairs(runtimeState.hitboxes) do
            restoreHitbox(player)
        end
        table.clear(runtimeState.hitboxes)
    end

    local function updateHitboxes(): ()
        if not isAlive(localPlayer) then
            restoreAllHitboxes()
            return
        end
        local seen: {[Player]: boolean} = {}
        local desiredSize: Vector3 = Vector3.new(
            settings.hitboxSize, settings.hitboxSize, settings.hitboxSize
        )
        for _, player: Player in ipairs(players:GetPlayers()) do
            if isEnemy(player, false, settings.hitboxTeamCheck) then
                local root: BasePart? = rootOf(player.Character)
                if root then
                    seen[player] = true
                    local record: any = runtimeState.hitboxes[player]
                    if not record or record.part ~= root then
                        restoreHitbox(player)
                        record = {
                            part = root,
                            size = root.Size,
                            transparency = root.Transparency,
                            canCollide = root.CanCollide,
                            canQuery = root.CanQuery,
                        }
                        runtimeState.hitboxes[player] = record
                    end
                    if root.Size ~= desiredSize then
                        root.Size = desiredSize
                    end
                    root.Transparency = 0.65
                    root.CanCollide = false
                    -- A non-queryable root cannot be found by native raycasts.
                    root.CanQuery = true
                end
            end
        end
        for player: Player, _record: any in pairs(runtimeState.hitboxes) do
            if not seen[player] then
                restoreHitbox(player)
            end
        end
    end

    local function updateMatchToken(): ()
        local token: string? = matchToken(localPlayer)
        if token ~= runtimeState.lastMatchToken then
            leaveSafePlace(false)
            runtimeState.nextSafeAt = 0
            runtimeState.nextKnifeAt["Auto Win"] = 0
            runtimeState.nextKnifeAt["Knife Throw"] = 0
            cancelGun()
            cancelKnifeThrow()
            table.clear(runtimeState.deadPlayers)
            table.clear(runtimeState.killVictims)
            if token ~= nil then
                -- Respawn and replicated GameId can arrive in either order.
                -- Do not create a second serial for the same new round.
                if not runtimeState.observedRound or runtimeState.resultsPending
                    or runtimeState.lastWinRound == runtimeState.roundSerial
                    or runtimeState.lastLossRound == runtimeState.roundSerial then
                    runtimeState.roundSerial += 1
                end
                runtimeState.resultsPending = false
                runtimeState.resultWinCounted = false
                runtimeState.observedRound = true
                runtimeState.nextGunAt = 0
            else
                runtimeState.observedRound = false
                runtimeState.selected = nil
            end
            runtimeState.lastMatchToken = token
        end
    end

    local function update(_deltaTime: number): ()
        local now: number = os.clock()
        if runtimeState.calibration then runtimeState.calibration.tick(now) end
        if now >= runtimeState.nextRemoteAt then
            runtimeState.nextRemoteAt = now + 2
            discoverMatchState()
            discoverClientGlobals()
            discoverMouseCast()
            ensureRemoteEvents()
        end
        updateMatchToken()
        local autoRound: boolean = settings.autoWin and activeRound()
        if now >= (runtimeState.nextRematchCheckAt or 0) then
            runtimeState.nextRematchCheckAt = now + 0.25
            processRematch(now)
        end
        if settings.autoWin then
            updateSafePlace()
            if not autoRound then
                setAutoWinStatus(runtimeState.resultsPending and "Waiting for rematch" or "Waiting for round")
            end
        end
        if runtimeState.mouseShot and now >= runtimeState.mouseShot.expires then
            runtimeState.mouseShot = nil
        end
        if settings.silentAim and settings.silentBackend ~= "CFrame" and now >= runtimeState.nextSelectionAt then
            runtimeState.nextSelectionAt = now + 0.06
            nearestEnemy(settings.maxDistance, nil, nil, nil, nil, settings.silentAimPart,
                settings.silentAimFov and settings.silentAimFovRadius or nil)
        elseif not settings.silentAim then
            runtimeState.selected = nil
        end

        -- One arbiter owns equipping and activation. A Gun takes priority
        -- while Auto Shoot/Auto Win need it; a pending throw finishes first.
        local wantsGun: boolean = settings.autoShoot or autoRound
        local wantsKnife: boolean = settings.knifeThrow or autoRound
        local gunAvailable: boolean = wantsGun and findWeapon("Gun") ~= nil
        if settings.autoShoot and not gunAvailable then
            setCombatStatus(autoShootCard, "Auto Shoot", "Waiting for gun")
        end
        if gunAvailable then
            if settings.knifeThrow then
                setCombatStatus(knifeThrowCard, "Knife Throw", "Paused while gun is active")
            end
            if not runtimeState.knifeBusy then
                local usedGun: boolean = false
                if settings.autoShoot and now >= runtimeState.nextGunAt then
                    local fired: boolean, _hasGun: boolean, reason: string? = runGun(
                        settings.autoShootRange, settings.autoShootCooldown,
                        settings.autoShootTeamCheck, settings.autoShootWallCheck, "Auto Shoot"
                    )
                    usedGun = fired
                    if reason ~= "A gun action is already pending." then
                        setCombatStatus(autoShootCard, "Auto Shoot", fired and (reason or runtimeState.autoShootOutcome or "Shot attempted / queued")
                            or (reason or "Gun not ready."))
                    end
                end
                if autoRound then
                    if usedGun then
                        setAutoWinStatus("Gun shared with Auto Shoot")
                    else
                        -- Auto Win does not inherit the other card's filters or
                        -- cooldown. If Auto Shoot cannot act, it gets its own
                        -- safe target search without double-firing this tick.
                        local fired: boolean, _hasGun: boolean, reason: string? =
                            runGun(1000, nil, true, true, "Auto Win")
                        setAutoWinStatus(fired and "Shot attempted / queued"
                            or (reason or "Gun not ready."))
                    end
                end
            elseif autoRound then
                setAutoWinStatus("Waiting for knife throw")
            end
        elseif wantsKnife and not runtimeState.knifeBusy and not runtimeState.gunPending then
            local knifeAvailable: boolean = findWeapon("Knife") ~= nil
            local usedKnife: boolean = false
            if settings.knifeThrow and settings.autoKnifeThrow then
                if not knifeAvailable then
                    setCombatStatus(knifeThrowCard, "Knife Throw", "Waiting for knife")
                elseif now >= runtimeState.nextKnifeAt["Knife Throw"] then
                    local queued: boolean, hasTarget: boolean, reason: string? = runKnifeThrow(
                        settings.knifeRange, settings.knifeCooldown,
                        settings.knifeTeamCheck, settings.knifeWallCheck, "Knife Throw"
                    )
                    usedKnife = queued
                    setCombatStatus(knifeThrowCard, "Knife Throw", queued and (runtimeState.knifeOutcome or reason or "Throw attempted")
                        or (reason or (hasTarget and "Knife/input not ready" or "No eligible opponent.")))
                end
            end
            if autoRound then
                if not knifeAvailable then
                    setAutoWinStatus("Waiting for knife")
                elseif usedKnife then
                    setAutoWinStatus("Knife shared with Knife Throw")
                elseif now >= runtimeState.nextKnifeAt["Auto Win"] then
                    local queued: boolean, hasTarget: boolean, reason: string? =
                        runKnifeThrow(600, 0, true, true, "Auto Win")
                    setAutoWinStatus(queued and "Throw attempted"
                        or (hasTarget and "Knife/input not ready" or reason or "No eligible opponent."))
                end
            end
        end
        if settings.killAura and not runtimeState.knifeBusy and not runtimeState.gunPending
            and not gunAvailable and not wantsKnife and now >= runtimeState.nextAuraAt then
            runKillAura()
        end
        if settings.hitboxes and now >= runtimeState.nextHitboxAt then
            runtimeState.nextHitboxAt = now + 0.2
            updateHitboxes()
        end
        if now >= runtimeState.nextStatsAt then
            runtimeState.nextStatsAt = now + 0.25
            if settings.silentAim and settings.silentBackend == "Oth"
                and (runtimeState.othRedirectSerial or 0) > (runtimeState.othReportedSerial or 0) then
                runtimeState.othReportedSerial = runtimeState.othRedirectSerial
                setCombatStatus(silentAimCard, "Silent AIM", "Oth Raycast redirected; hit not confirmed.")
            end
            updateStats()
        end
    end

    local core: any = nil
    local teamProvider: any = nil
    local roleProvider: any = nil

    moduleCleanup = function(): ()
        runtimeState.closed = true
        if runtimeState.calibration then runtimeState.calibration.stop("Menu unloaded") end
        if runtimeState.autoWinStartedAt then
            runtimeState.autoWinElapsed += math.max(0, os.clock() - runtimeState.autoWinStartedAt)
            runtimeState.autoWinStartedAt = nil
        end
        leaveSafePlace(true)
        settings.autoWin = false
        runtimeState.matchApi = nil
        runtimeState.clientGlobals = nil
        settings.silentAim = false
        settings.autoShoot = false
        settings.knifeThrow = false
        settings.killAura = false
        settings.hitboxes = false
        updateStats()
        setAimActivity(false)
        restoreAllHitboxes()
        cancelGun()
        cancelKnifeThrow()
        restoreCamera()
        uninstallMouseCast()
        uninstallHooks()
        if host.featureConnections.X2DuelsCore then
            host.disconnectFeatureConnection("X2DuelsCore")
        end
        for _, connection: any in ipairs(runtimeState.connections) do
            pcall(function(): () connection:Disconnect() end)
        end
        table.clear(runtimeState.connections)
        table.clear(runtimeState.remoteBound)
        table.clear(runtimeState.deadPlayers)
        if roleProvider and state.gameBridge
            and state.gameBridge.roleProvider == roleProvider then
            if type(state.unregisterRoleProvider) == "function" then
                state.unregisterRoleProvider(roleProvider)
            else
                state.gameBridge.roleProvider = nil
            end
        end
        if teamProvider and state.gameBridge
            and state.gameBridge.teamProvider == teamProvider then
            state.gameBridge.teamProvider = nil
            state.teamProvider = nil
        end
        if state.x2duelsCore == core then
            state.x2duelsCore = nil
        end
        if state.mvsdCore == core then
            state.mvsdCore = nil
        end
    end


    core = {
        settings = settings,
        RoleColors = ROLE_COLORS,
        teamOf = teamToken,
        matchIdOf = matchToken,
        relation = relation,
        inSameMatch = sharesMatch,
        isAlive = isAlive,
        isTeammate = isTeammate,
        isEnemy = isEnemy,
        nearestEnemy = nearestEnemy,
        targetFor = targetRecord,
        findGun = function(): Tool? return findWeapon("Gun") end,
        findKnife = function(): Tool? return findWeapon("Knife") end,
        equippedTool = equippedTool,
        toolKind = toolKind,
        equip = equip,
        activateNative = activateNative,
        fireGun = fireGun,
        fireKnife = fireKnife,
        getWins = function(): number return runtimeState.wins end,
        getStats = function(): {[string]: any}
            return {
                Wins = runtimeState.wins,
                TimePlayed = math.max(0, os.clock() - runtimeState.sessionStartedAt),
                Kills = runtimeState.kills,
                Loses = runtimeState.loses,
                DuelsWon = runtimeState.duelsWon,
                AutoWinTime = runtimeState.autoWinElapsed + (
                    runtimeState.autoWinStartedAt and math.max(0, os.clock() - runtimeState.autoWinStartedAt) or 0
                ),
                CurrentGameMode = currentGameMode(),
            }
        end,
    }
    state.x2duelsCore = core
    state.mvsdCore = core

    local function playerFromInstance(instance: Instance): Player?
        if instance:IsA("Player") then
            return instance :: Player
        end
        if instance:IsA("Model") then
            local ok: boolean, player: any = pcall(function(): any
                return players:GetPlayerFromCharacter(instance :: Model)
            end)
            return ok and player or nil
        end
        return nil
    end

    teamProvider = {
        Name = "X2Duels",
        Get = function(instance: Instance): string?
            local player: Player? = playerFromInstance(instance)
            return player and teamToken(player) or nil
        end,
        GetRelation = function(instance: Instance): string
            local player: Player? = playerFromInstance(instance)
            return player and relation(player) or "Unknown"
        end,
        IsFriendly = function(player: Player?): boolean
            return isTeammate(player)
        end,
    }
    if type(host.registerTeamProvider) == "function" then
        host.registerTeamProvider(teamProvider)
    end

    -- Supply the same palette to universal PlayerESP/Chams/Nametags without
    -- disabling their teammate filters. ReplacesTeams stays false: Team Check
    -- must still reject confirmed teammates and fail closed on Unknown.
    roleProvider = {
        Name = "X2Duels",
        ReplacesTeams = false,
        Roles = {"Enemy", "Teammate", "Unknown", "Outside"},
        Colors = ROLE_COLORS,
        Get = function(player: Player): string?
            local current: string = relation(player)
            return current ~= "Local" and current or nil
        end,
        GetColor = function(roleName: string): Color3?
            return ROLE_COLORS[roleName]
        end,
    }
    if type(host.registerRoleProvider) == "function" then
        host.registerRoleProvider(roleProvider)
    end

    local parentConfiguration: {[string]: any} = {
        parent = state.mvsdScroll,
        registry = state.mvsdFeatures,
    }
    local function card(
        name: string,
        description: string,
        order: number,
        callback: any,
        category: string?
    ): any
        local configuration: {[string]: any} = table.clone(parentConfiguration)
        configuration.categoryName = category
        -- Do not silently re-arm an experimental hook from an old profile.
        if name == "Silent AIM" then configuration.restore = false end
        return host.createUniversalFeature(name, description, order, callback, configuration)
    end

    local configData: any = host.configData
    if type(configData) == "table" and type(configData.states) == "table"
        and type(configData.values) == "table"
        and configData.values["X2Duels.layout"] ~= "v143" then
        local states: any = configData.states
        local values: any = configData.values
        if states["MVSD.Hitbox"] == nil and states["MVSD.Hitboxes"] ~= nil then
            states["MVSD.Hitbox"] = states["MVSD.Hitboxes"] == true
        end
        -- Auto Win used to be statistics-only and the two automations used to
        -- be nested. Migrating a saved profile must never turn them into live
        -- combat on injection: the user explicitly enables the new cards.
        states["MVSD.AutoWin"] = false
        states["MVSD.AutoShoot"] = false
        states["MVSD.KnifeThrow"] = false
        states["MVSD.AutoWin.SafePlace"] = false
        states["MVSD.AutoWin.Revancha"] = false
        states["MVSD.SilentAIM.AutoShoot"] = nil
        states["MVSD.SilentAIM.KnifeThrow"] = nil
        states["MVSD.AutoWin.PlayAgain"] = nil
        states["MVSD.PlayAgain"] = nil
        states["MVSD.TeamESP"] = nil
        states["MVSD.TriggerBot"] = nil
        if values["X2Duels.layout"] ~= "v119" then
            states["MVSD.AutoFarm"] = false
        end
        for _, name: string in ipairs({"AutoShoot", "KnifeThrow", "Hitbox", "KillAura"}) do
            local key: string = "MVSD." .. name .. ".TeamCheck"
            if states[key] == nil and states["MVSD.SilentAIM.TeamCheck"] ~= nil then
                states[key] = states["MVSD.SilentAIM.TeamCheck"] == true
            end
        end
        for _, name: string in ipairs({"AutoShoot", "KnifeThrow", "KillAura"}) do
            local key: string = "MVSD." .. name .. ".WallCheck"
            if states[key] == nil and states["MVSD.SilentAIM.WallCheck"] ~= nil then
                states[key] = states["MVSD.SilentAIM.WallCheck"] == true
            end
        end
        if values["MVSD.AutoShoot.Range"] == nil then
            values["MVSD.AutoShoot.Range"] = values["MVSD.SilentAIM.Range"]
        end
        if values["MVSD.AutoShoot.Cooldown"] == nil then
            values["MVSD.AutoShoot.Cooldown"] = values["MVSD.SilentAIM.Fireinterval"]
                or values["MVSD.AutoShoot.Fireinterval"]
        end
        values["X2Duels.layout"] = "v143"
        if type(host.queueConfigSave) == "function" then host.queueConfigSave() end
    end

    autoWinCard = card(
        "Auto Win",
        "Automatically attempt to fight during active duels",
        2,
        function(enabled: boolean): ()
            if enabled and not settings.autoWin then
                if runtimeState.calibration then runtimeState.calibration.stop("Probe stopped for combat; turn OFF") end
                runtimeState.autoWinStartedAt = os.clock()
                runtimeState.nextKnifeAt["Auto Win"] = 0
            elseif not enabled and settings.autoWin then
                if runtimeState.autoWinStartedAt then
                    runtimeState.autoWinElapsed += math.max(0, os.clock() - runtimeState.autoWinStartedAt)
                end
                runtimeState.autoWinStartedAt = nil
                leaveSafePlace(true)
                cancelGun("Auto Win")
                cancelKnifeThrow("Auto Win")
            end
            settings.autoWin = enabled
            runtimeState.nextStatsAt = 0
            updateStats()
        end,
        "Utilities"
    )
    if type(state.addStatOption) == "function" then
        autoWinStats.time = state.addStatOption(autoWinCard, "Time Spent", "00:00")
        autoWinStats.won = state.addStatOption(autoWinCard, "Duels Won", "0")
        autoWinStats.mode = state.addStatOption(autoWinCard, "Current Game mode", "Lobby / unknown")
        autoWinStats.status = addCombatStatusRow(autoWinCard, "Combat status", "Off")
        autoWinStats.safe = state.addStatOption(autoWinCard, "Safe Place status", "Off")
        autoWinStats.rematch = state.addStatOption(autoWinCard, "Revancha status", "Off")
    end
    host.addToggleOption(autoWinCard, "Safe Place", false, function(value: boolean): ()
        settings.safePlace = value
        runtimeState.nextSafeAt = 0
        if not value then leaveSafePlace(true) end
        updateStats()
    end, "Hold above the active map; server physics, ceilings and anti-cheat may prevent this.")
    host.addToggleOption(autoWinCard, "Revancha", false, function(value: boolean): ()
        settings.rematch = value
        runtimeState.nextRematchCheckAt = 0
        if value then discoverClientGlobals() end
        runtimeState.rematchStatus = value and (settings.autoWin and "Waiting for state" or "Enable Auto Win") or "Off"
        updateStats()
    end, "Votes once for an active rematch; the other players must also vote.")
    host.addInformationOption(
        autoWinCard,
        "Counts final MatchResults wins while enabled, not round wins. Native server validation decides damage and results."
    )
    updateStats()

    local function silentAdapterAvailable(gun: Tool?): boolean
        if settings.silentBackend == "Oth" then
            return runtimeState.othRaycast ~= nil and runtimeState.othRaycast.active == true
        end
        local debugApi: any = host.debug
        local canIdentifyCaller: boolean = type(host.getcallingscript) == "function"
            or (type(debugApi) == "table" and type(debugApi.info) == "function")
        local attributed: boolean = canIdentifyCaller and (runtimeState.mouseCastApi ~= nil
            or runtimeState.mouseHookInstalled or runtimeState.rayHookInstalled
            or runtimeState.raycastHookInstalled)
        local buttonFallback: boolean = runtimeState.mouseHookInstalled
            and type(host.checkcaller) == "function" and observedGunSignature(gun)
        return attributed or buttonFallback
    end

    -- Old profiles may have saved the visible camera-lock mode. Do not silently
    -- re-enable it: the X2 Silent card now has one camera-free behaviour.
    if type(configData) == "table" and type(configData.values) == "table"
        and configData.values["MVSD.SilentAIM.Mode"] ~= nil then
        configData.values["MVSD.SilentAIM.Mode"] = nil
        if type(host.queueConfigSave) == "function" then host.queueConfigSave() end
    end

    silentAimCard = card(
        "Silent AIM",
        "CFrame button equips the gun and sends an experimental aim request without camera movement",
        3,
        function(enabled: boolean): ()
            settings.silentAim = enabled
            setAimActivity(enabled)
            runtimeState.silentAttempt += 1
            if enabled then
                if runtimeState.calibration then runtimeState.calibration.stop("Probe stopped for combat; turn OFF") end
                cancelGun("Auto Win") -- cancel a queued camera-aim action before Silent starts
                if settings.knifeBackend ~= "CFrame" then cancelKnifeThrow() end
                if settings.silentBackend == "CFrame" then
                    setCombatStatus(silentAimCard, "Silent AIM", "CFrame button ready; gun request is experimental.")
                else
                installHooks()
                discoverMouseCast()
                setCombatStatus(silentAimCard, "Silent AIM", silentAdapterAvailable(findWeapon("Gun"))
                    and (settings.silentBackend == "Oth" and "Oth Raycast installed; weapon compatibility unconfirmed." or "Adapter loaded; weapon compatibility unconfirmed.")
                    or (settings.silentBackend == "Oth" and "Oth Raycast unavailable: requires oth.hook, getrawmetatable, getnamecallmethod and checkcaller." or "Waiting for a compatible silent aim adapter or gun."))
                end
            else
                cancelGun("Silent AIM")
                runtimeState.selected = nil
                uninstallMouseCast()
                uninstallHooks()
                if not runtimeState.knifeBusy and not settings.autoShoot and not settings.autoWin then
                    restoreCamera()
                end
                setCombatStatus(silentAimCard, "Silent AIM", nil)
            end
        end,
        "Combat"
    )
    host.addToggleOption(silentAimCard, "Wall Check", true, function(value: boolean): ()
        settings.wallCheck = value
        runtimeState.selected = nil
    end, "Stops the action button when a wall or another body blocks the gun or camera.")
    host.addToggleOption(silentAimCard, "Team Check", true, function(value: boolean): ()
        settings.teamCheck = value
        runtimeState.selected = nil
    end)
    host.addCycleOption(silentAimCard, "Target Part", {"Head", "Body"}, 1, function(value: string): ()
        settings.silentAimPart = value
        runtimeState.selected = nil
        runtimeState.nextSelectionAt = 0
        runtimeState.mouseShot = nil
    end, "Body prefers UpperTorso/Torso and falls back to the root if needed.")
    host.addToggleOption(silentAimCard, "Aim FOV", false, function(value: boolean): ()
        settings.silentAimFov = value
        runtimeState.selected = nil
        runtimeState.nextSelectionAt = 0
        runtimeState.mouseShot = nil
    end, "Select only on-screen opponents near the cursor on PC or screen center on mobile; this does not change camera FOV.")
    host.addNumberOption(silentAimCard, "Aim FOV Radius", 200, 20, 1000, function(value: number): ()
        settings.silentAimFovRadius = math.max(1, value)
        runtimeState.selected = nil
        runtimeState.nextSelectionAt = 0
        runtimeState.mouseShot = nil
    end, "Screen-space radius in pixels; used only while Aim FOV is enabled.")
    host.addNumberOption(silentAimCard, "Range", 1000, 50, 1500, function(value: number): ()
        settings.maxDistance = math.max(0, value)
    end)
    combatStatusRows["Silent AIM"] = addCombatStatusRow(
        silentAimCard, "Status", combatStatuses["Silent AIM"] or "Off"
    )
    host.addInformationOption(
        silentAimCard,
        "CFrame button only: direct observed X2 Gun requests, no aim hook or camera rotation. This is not automatic redirection of native taps. Server acceptance and anticheat safety are unverified."
    )

    local function pressSenderButton(): ()
        local function report(message: string): ()
            setCombatStatus(silentAimCard, "Silent AIM", message)
            pcall(notify, "X2 Duels · " .. message)
        end
        if not settings.silentAim then
            pcall(notify, "X2 Duels · Enable Silent AIM first.")
            return
        end
        if runtimeState.knifeBusy then report("Waiting for the knife throw."); return end
        if runtimeState.gunPending then report("A gun action is already pending."); return end
        if os.clock() < runtimeState.nativeAimUntil then
            report("Waiting for another gun action to finish."); return
        end
        local character: Model? = localPlayer.Character
        if not character or not isAlive(localPlayer) then
            report("Your character is not alive or ready."); return
        end
        local gun: Tool? = findWeapon("Gun")
        if not gun then report("No gun is available in your inventory."); return end
        runtimeState.gunToken += 1
        local token: number = runtimeState.gunToken
        local gameToken: string? = matchToken(localPlayer)
        runtimeState.gunPending = {token = token, owner = "Silent AIM", tool = gun}
        runtimeState.silentAttempt += 1
        local attempt: number = runtimeState.silentAttempt
        task.spawn(function(): ()
            local ok: boolean, failure: any = pcall(function(): ()
                if gun.Parent ~= character then
                    if not equip(gun) then report("Could not equip the gun."); return end
                    setCombatStatus(silentAimCard, "Silent AIM", "Equipping gun...")
                    runService.Heartbeat:Wait()
                end
                local pending: any = runtimeState.gunPending
                if not pending or pending.token ~= token or runtimeState.closed or not settings.silentAim then return end
                if localPlayer.Character ~= character or not isAlive(localPlayer)
                    or matchToken(localPlayer) ~= gameToken then
                    report("Your character or duel changed before the shot."); return
                end
                if gun.Parent ~= character then
                    report("The gun was unequipped before it was ready."); return
                end
                local enabledOk: boolean, enabled: any = pcall(function(): any return gun.Enabled end)
                if not enabledOk or enabled == false then
                    report("The gun is disabled, reloading or not ready."); return
                end
                local localRoot: BasePart? = rootOf(character)
                local shotOrigin: Vector3? = settings.silentBackend == "CFrame" and localRoot
                    and localRoot.Position or gunOrigin(gun)
                local target: {[string]: any}?, why: string? = nearestEnemy(
                    settings.maxDistance, settings.teamCheck, settings.wallCheck, true,
                    shotOrigin, settings.silentAimPart,
                    settings.silentAimFov and settings.silentAimFovRadius or nil
                )
                if not target then report(why or "No eligible opponent."); return end
                if settings.wallCheck and settings.silentBackend ~= "CFrame" then
                    local clear: boolean, reason: string? = hasLineOfSight(target)
                    if not clear then report(reason or "Wall Check unavailable."); return end
                end
                if settings.silentBackend == "CFrame" then
                    local sent: boolean, why: string? = fireCFrameGun(gun, target, settings.teamCheck)
                    if not sent then report(why or "CFrame request failed."); return end
                    setCombatStatus(silentAimCard, "Silent AIM", why or "CFrame request sent; hit not confirmed.")
                    return
                end
                if not silentAdapterAvailable(gun) then discoverMouseCast() end
                if not silentAdapterAvailable(gun) then
                    report(runtimeState.mouseCastLoading
                        and "Silent aim adapter is still loading; no shot was fired."
                        or "Silent aim is unavailable on this executor or gun; no shot was fired.")
                    return
                end
                local before: number = runtimeState.redirectCount
                if runtimeState.mouseHookInstalled and observedGunSignature(gun)
                    and type(host.checkcaller) == "function" then
                    -- Activated handlers may run on a later scheduler turn.
                    -- This is a bounded aim lease, not a fire-rate cooldown.
                    runtimeState.mouseShot = {
                        gun = gun, target = target, character = character,
                        match = gameToken, expires = os.clock() + 0.2,
                    }
                end
                if not activateNative(gun, target, false) then
                    runtimeState.mouseShot = nil
                    report("The gun could not be activated."); return
                end
                setCombatStatus(silentAimCard, "Silent AIM", "Native shot attempted; aim not yet confirmed.")
                task.delay(0.35, function(): ()
                    if runtimeState.closed or not settings.silentAim
                        or runtimeState.silentAttempt ~= attempt then return end
                    if runtimeState.redirectCount > before then
                        setCombatStatus(silentAimCard, "Silent AIM", "Aim input redirected; hit not confirmed.")
                    else
                        report("No aim redirection observed; this gun or executor may be unsupported.")
                    end
                end)
            end)
            local pending: any = runtimeState.gunPending
            if pending and pending.token == token then runtimeState.gunPending = nil end
            if not ok and settings.silentAim and runtimeState.silentAttempt == attempt then
                report("Shoot failed: " .. tostring(failure))
            end
        end)
    end
    if type(state.bindFeatureActivationKey) == "function" then
        state.bindFeatureActivationKey(silentAimCard, Enum.KeyCode.Unknown, pressSenderButton)
    end

    autoShootCard = card(
        "Auto Shoot", "Automatically send experimental CFrame gun requests without moving the camera", 4,
        function(enabled: boolean): ()
            settings.autoShoot = enabled
            runtimeState.autoShootOutcome = nil
            if enabled then
                if runtimeState.calibration then runtimeState.calibration.stop("Probe stopped for combat; turn OFF") end
                cancelGun("Auto Win")
            end
            runtimeState.nextGunAt = 0
            if not enabled then cancelGun("Auto Shoot") end
            setCombatStatus(autoShootCard, "Auto Shoot", enabled and "Waiting for gun" or nil)
        end,
        "Combat"
    )
    host.addToggleOption(autoShootCard, "Wall Check", true, function(value: boolean): ()
        settings.autoShootWallCheck = value
    end, "Stops automatic attempts when a wall or another body blocks the path.")
    host.addToggleOption(autoShootCard, "Team Check", true, function(value: boolean): ()
        settings.autoShootTeamCheck = value
    end)
    host.addNumberOption(autoShootCard, "Range", 1000, 50, 1500, function(value: number): ()
        settings.autoShootRange = math.max(0, value)
    end)
    host.addNumberOption(autoShootCard, "Cooldown", 0, 0, 2, function(value: number): ()
        settings.autoShootCooldown = math.clamp(value, 0, 10)
    end, "Seconds between activation attempts; the gun/server controls its own cooldown.", 0.01)
    combatStatusRows["Auto Shoot"] = addCombatStatusRow(
        autoShootCard, "Status", combatStatuses["Auto Shoot"] or "Off"
    )
    host.addInformationOption(autoShootCard,
        "Independent of Silent AIM. Sends the observed X2 Gun request with CFrame direction, without hooks or camera rotation. Conservative 2.5s interval; server hits and anticheat safety are not confirmed.")

    knifeThrowCard = card(
        "Knife Throw", "CFrame knife button with optional automatic throws; no camera lock", 5,
        function(enabled: boolean): ()
            settings.knifeThrow = enabled
            if enabled and runtimeState.calibration then runtimeState.calibration.stop("Probe stopped for combat; turn OFF") end
            runtimeState.nextKnifeAt["Knife Throw"] = 0
            if not enabled then cancelKnifeThrow("Knife Throw") end
            setCombatStatus(knifeThrowCard, "Knife Throw", enabled and "Waiting for knife" or nil)
        end,
        "Combat"
    )
    if type(state.bindFeatureActivationKey) == "function" then
        state.bindFeatureActivationKey(knifeThrowCard, Enum.KeyCode.Unknown, function(): ()
            if not settings.knifeThrow then
                pcall(notify, "X2 Duels · Enable Knife Throw first.")
                return
            end
            local queued: boolean, _hasTarget: boolean, why: string? = runKnifeThrow(
                settings.knifeRange, settings.knifeCooldown, settings.knifeTeamCheck, settings.knifeWallCheck, "Knife Throw")
            setCombatStatus(knifeThrowCard, "Knife Throw", queued and (runtimeState.knifeOutcome or why or "Throw queued; hit not confirmed.")
                or (why or "Knife not ready."))
        end)
    end
    host.addToggleOption(knifeThrowCard, "Auto Throw", true, function(value: boolean): ()
        settings.autoKnifeThrow = value
        if not value then cancelKnifeThrow("Knife Throw") end
        runtimeState.nextKnifeAt["Knife Throw"] = 0
    end, "Automatically throw while the card is enabled. Disable for button-only use.")
    host.addToggleOption(knifeThrowCard, "Wall Check", true, function(value: boolean): ()
        settings.knifeWallCheck = value
        cancelKnifeThrow("Knife Throw")
    end, "Stops automatic attempts when a wall or another body blocks the path.")
    host.addToggleOption(knifeThrowCard, "Team Check", true, function(value: boolean): ()
        settings.knifeTeamCheck = value
        cancelKnifeThrow("Knife Throw")
    end)
    host.addNumberOption(knifeThrowCard, "Range", 600, 50, 1500, function(value: number): ()
        settings.knifeRange = math.max(0, value)
        cancelKnifeThrow("Knife Throw")
    end)
    host.addNumberOption(knifeThrowCard, "Cooldown", 0, 0, 2, function(value: number): ()
        settings.knifeCooldown = math.clamp(value, 0, 10)
    end, "Seconds between throw attempts, in addition to the native windup.", 0.01)
    host.addToggleOption(knifeThrowCard, "Projectile Prediction", false, function(value: boolean): ()
        settings.knifePrediction = value
    end, "Experimental lead during automatic native Knife Throw; independent of Silent AIM.")
    host.addNumberOption(knifeThrowCard, "Projectile Speed", 78, 1, 1000, function(value: number): ()
        settings.knifeProjectileSpeed = math.clamp(value, 1, 10000)
    end, "Local source moves approximately 78 studs/second; server behaviour is unverified.")
    host.addNumberOption(knifeThrowCard, "Projectile Gravity", 0, 0, 200, function(value: number): ()
        settings.knifeProjectileGravity = math.clamp(value, 0, 10000)
    end, "Estimated projectile gravity; Wall Check tests a direct line, not the full arc.")
    combatStatusRows["Knife Throw"] = addCombatStatusRow(
        knifeThrowCard, "Status", combatStatuses["Knife Throw"] or "Off"
    )
    host.addInformationOption(knifeThrowCard,
        "Button and Auto Throw use the captured ThrowEvent and native local collision handler without moving the camera. Server acceptance and damage are not confirmed.")

    local auraCard: any = card(
        "Kill Aura",
        "Use native knife activation on a nearby valid target",
        5,
        function(enabled: boolean): ()
            settings.killAura = enabled
            if enabled and runtimeState.calibration then runtimeState.calibration.stop("Probe stopped for combat; turn OFF") end
            runtimeState.nextAuraAt = 0
        end,
        "Combat"
    )
    host.addToggleOption(auraCard, "Team Check", true, function(value: boolean): ()
        settings.killAuraTeamCheck = value
    end)
    host.addToggleOption(auraCard, "Wall Check", true, function(value: boolean): ()
        settings.killAuraWallCheck = value
    end)
    host.addNumberOption(auraCard, "Reach", 12, 3, 25, function(value: number): ()
        settings.killAuraRange = math.max(0, value)
    end)
    host.addNumberOption(auraCard, "Swing interval", 0.12, 0.05, 0.6, function(value: number): ()
        settings.killAuraInterval = value
    end)

    local hitboxCard: any = card(
        "Hitbox",
        "Expand only valid target roots and restore their original properties when disabled",
        6,
        function(enabled: boolean): ()
            settings.hitboxes = enabled
            runtimeState.nextHitboxAt = 0
            if not enabled then restoreAllHitboxes() end
        end,
        "Exploits"
    )
    host.addToggleOption(hitboxCard, "Team Check", true, function(value: boolean): ()
        settings.hitboxTeamCheck = value
        restoreAllHitboxes()
        runtimeState.nextHitboxAt = 0
    end)
    host.addNumberOption(hitboxCard, "Size", 10, 2, 30, function(value: number): ()
        settings.hitboxSize = math.clamp(value, 2, 100)
        restoreAllHitboxes()
        runtimeState.nextHitboxAt = 0
    end)
    host.addInformationOption(hitboxCard,
        "Client-side enlargement only; detection is possible and the server can reject hits outside the real target. No anticheat exemption is verified.")

    -- Temporary passive diagnostic: unlike Silent AIM it never changes aim or
    -- fires. Only OTH hooks are used; missing APIs never fall back to legacy.
    do
        local probe: any = {active = false, guard = false, events = {}, dropped = 0, links = {}}
        local calibrationCard: any = nil
        local statusRow: any = nil
        local function report(text: string): ()
            if calibrationCard and type(calibrationCard.SetStatus) == "function" then calibrationCard:SetStatus(text) end
            if statusRow then statusRow.set(text) end
        end
        local function record(kind: string, details: any?): ()
            if not probe.active then return end
            -- Keep the most recent evidence: camera rays can fill the buffer
            -- before a later manual shot. Report how many events were evicted.
            if #probe.events >= 400 then table.remove(probe.events, 1); probe.dropped += 1 end
            table.insert(probe.events, {t = math.floor((os.clock() - probe.started) * 1000) / 1000,
                event = kind, detail = details})
        end
        local function aimSnapshot(): {[string]: any}
            return {backend = settings.silentBackend == "Oth" and "Oth namecall Raycast" or "Legacy",
                enabled = settings.silentAim, compatibility = settings.raycastCompatibility,
                wallCheck = settings.wallCheck, teamCheck = settings.teamCheck, targetPart = settings.silentAimPart,
                range = settings.maxDistance, fov = settings.silentAimFov, fovRadius = settings.silentAimFovRadius}
        end
        -- A bare filename targets the executor's own workspace root on both
        -- desktop and mobile. Never assume an OS-specific absolute directory.
        local reportPath: string = "X2Duels-calibration.json"
        local function executorFunction(name: string): any
            local direct: any = host[name]
            if type(direct) == "function" then return direct end
            if type(host.getgenv) == "function" then
                local ok: boolean, env: any = pcall(host.getgenv)
                if ok and type(env) == "table" and type(env[name]) == "function" then return env[name] end
            end
            return nil
        end
        local function writeWorkspace(path: string, data: string): (boolean, string)
            local write: any = executorFunction("writefile")
            if not write then return false, "writefile unavailable" end
            local ok: boolean, result: any = pcall(write, path, data)
            if not ok or result == false then
                return false, "writefile: " .. string.sub(tostring(result), 1, 100)
            end
            local read: any = executorFunction("readfile")
            if read then
                local readOk: boolean, content: any = pcall(read, path)
                if readOk and type(content) == "string" then
                    if content ~= data then return false, "readfile content differs" end
                    return true, "content verified"
                end
            end
            local exists: any = executorFunction("isfile")
            if exists then
                local existsOk: boolean, present: any = pcall(exists, path)
                if existsOk and present == true then return true, "file exists (content unverified)" end
                if existsOk and present == false then return false, "file not visible to isfile" end
            end
            return true, "write returned; unverified"
        end
        local function save(): (boolean, string)
            local output: any = {
                version = 3, backend = "Oth shared namecall", placeId = game.PlaceId,
                touch = inputService.TouchEnabled == true, keyboard = inputService.KeyboardEnabled == true,
                elapsed = math.max(0, (probe.stoppedAt or os.clock()) - (probe.started or os.clock())),
                namecallHook = probe.namecallInstalled == true,
                limitations = {"Mouse property reads, direct function calls and Ray.new are not intercepted"},
                aim = aimSnapshot(),
                checkcaller = type(host.checkcaller) == "function", getcallingscript = type(host.getcallingscript) == "function",
                decompile = executorFunction("decompile") ~= nil, gun = probe.gunInfo,
                dropped = probe.dropped, events = probe.events, sources = probe.sources or {},
                note = "Passive observations, not all APIs. Calls may be unrelated; missing events do not prove an API is unused. Silent AIM may alter rays. This is not proof of hits.",
            }
            local ok: boolean, encoded: any = pcall(function(): string return game:GetService("HttpService"):JSONEncode(output) end)
            if not ok or type(encoded) ~= "string" then
                return false, "JSONEncode: " .. string.sub(tostring(encoded), 1, 100)
            end
            return writeWorkspace(reportPath, encoded)
        end
        local function stop(reason: string): ()
            if not probe.active then return end
            record("stop", reason)
            probe.active = false
            runtimeState.othProbeObserver = nil
            probe.stoppedAt = os.clock()
            if probe.lease then probe.lease.active = false end
            if probe.inputLink then pcall(function(): () probe.inputLink:Disconnect() end); probe.inputLink = nil end
            for _, link: any in ipairs(probe.links) do pcall(function(): () link:Disconnect() end) end
            table.clear(probe.links)
            -- Leave inert reusable OTH nodes; unhook semantics vary and may
            -- otherwise remove a hook installed later by another script.
            local saved: boolean, message: string = save()
            probe.saveFailed, probe.saveMessage = not saved, message
            report(reason .. (saved and " · workspace/" .. reportPath .. " · " .. message or " · save failed: " .. message))
        end
        local function bindGun(gun: Tool?): ()
            if probe.gun == gun then return end
            for _, link: any in ipairs(probe.links) do pcall(function(): () link:Disconnect() end) end
            table.clear(probe.links)
            probe.gun = gun
            if not gun then record("gun_missing"); return end
            local children: {any} = {}
            for _, item: Instance in ipairs(gun:GetDescendants()) do
                if #children >= 100 then break end
                table.insert(children, {name = string.sub(item.Name, 1, 80), class = item.ClassName})
            end
            probe.gunInfo = {name = string.sub(gun.Name, 1, 80), children = children}
            record("gun_found", {name = gun.Name, equipped = gun.Parent == localPlayer.Character})
            local ok: boolean, link: any = pcall(function(): any
                return gun.Activated:Connect(function(): () record("tool_activated", {silent = settings.silentAim}) end)
            end)
            if ok and link then table.insert(probe.links, link) end
        end
        local function tick(now: number): ()
            if not probe.active then return end
            if now >= probe.expires then stop("60 seconds elapsed; turn OFF before restarting"); return end
            if now < (probe.nextTick or 0) then return end
            probe.nextTick = now + 0.1
            local gun: Tool? = findWeapon("Gun")
            bindGun(gun)
            local aim: any = aimSnapshot()
            local aimKey: string = table.concat({aim.backend, tostring(aim.enabled), tostring(aim.compatibility),
                tostring(aim.wallCheck), tostring(aim.teamCheck), aim.targetPart, tostring(aim.range),
                tostring(aim.fov), tostring(aim.fovRadius)}, "|")
            if aimKey ~= probe.aimKey then probe.aimKey = aimKey; record("aim_configuration", aim) end
            if now >= (probe.nextSaveAt or 0) then
                probe.nextSaveAt = now + 3
                if #probe.events ~= probe.savedCount or probe.dropped ~= probe.savedDropped then
                    local saved: boolean, message: string = save()
                    probe.saveFailed, probe.saveMessage = not saved, message
                    if saved then probe.savedCount, probe.savedDropped = #probe.events, probe.dropped end
                end
            end
            report((not gun and "Waiting for gun" or (gun.Parent == localPlayer.Character and "Gun equipped" or "Gun in inventory"))
                .. " · Oth namecall " .. (probe.namecallInstalled and "OK" or "unavailable")
                .. " · " .. tostring(#probe.events) .. " events"
                .. (probe.saveFailed and (" · save failed: " .. tostring(probe.saveMessage))
                    or (" · workspace/" .. reportPath .. " · " .. tostring(probe.saveMessage or "pending"))))
        end
        local function observeCall(object: any, method: string, args: any, redirected: boolean): ()
            if not probe.active or probe.guard then return end
            probe.guard = true
            pcall(function(): ()
                local gun: Tool? = probe.gun
                if not gun or gun.Parent ~= localPlayer.Character then return end
                if method == "Raycast" or method == "FindPartOnRay"
                    or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                    if object ~= currentWorkspace then return end
                elseif method == "ScreenPointToRay" or method == "ViewportPointToRay" then
                    if object ~= currentWorkspace.CurrentCamera then return end
                elseif typeof(object) ~= "Instance" or not (object.IsA(object, "RemoteEvent")
                    or object.IsA(object, "UnreliableRemoteEvent") or object.IsA(object, "RemoteFunction")) then return end
                local types: {string} = {}
                for i: number = 1, math.min(args.n, 12) do table.insert(types, typeof(args[i])) end
                local caller: any = nil
                if type(host.getcallingscript) == "function" then
                    local ok: boolean, script: any = pcall(host.getcallingscript)
                    if ok and typeof(script) == "Instance" then caller = script.Name end
                end
                local detail: any = {method = method, object = object.Name, caller = caller or "unknown",
                    argumentTypes = types, silent = settings.silentAim, redirected = redirected}
                local origin: any = args[1]
                local direction: any = args[2]
                if method ~= "Raycast" and typeof(args[1]) == "Ray" then
                    origin, direction = args[1].Origin, args[1].Direction
                end
                if (method == "Raycast" or string.sub(method, 1, 13) == "FindPartOnRay")
                    and typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                    detail.origin = {origin.X, origin.Y, origin.Z}
                    detail.direction = {direction.X, direction.Y, direction.Z}
                end
                -- Filter metadata is descriptive; never change the RaycastParams.
                if method == "Raycast" and typeof(args[3]) == "RaycastParams" then
                    local ok: boolean, filter: any = pcall(function(): any return args[3].FilterType end)
                    if ok then detail.filterType = tostring(filter) end
                end
                record("namecall", detail)
            end)
            probe.guard = false
        end
        local function start(): ()
            if probe.active then return end
            if settings.silentAim or settings.autoShoot or settings.autoWin or settings.knifeThrow or settings.killAura then
                report("Probe blocked during combat; turn OFF to retry")
                return
            end
            probe.active, probe.guard = true, false
            probe.started, probe.expires, probe.nextTick, probe.stoppedAt = os.clock(), os.clock() + 60, 0, nil
            probe.nextSaveAt, probe.savedCount, probe.savedDropped, probe.saveFailed = 0, -1, -1, false
            probe.events, probe.dropped, probe.gun, probe.gunInfo, probe.sources, probe.aimKey = {}, 0, nil, nil, {}, nil
            probe.namecallInstalled = false
            local lease: any = {active = true}
            probe.lease = lease
            record("start", {touch = inputService.TouchEnabled == true, silent = settings.silentAim})
            -- Try a minimal snapshot before installing the hook, in case hook
            -- installation itself interrupts the session. Later saves replace it.
            local initialSaved: boolean, initialMessage: string = save()
            probe.saveFailed, probe.saveMessage = not initialSaved, initialMessage
            local inputOk: boolean, inputLink: any = pcall(function(): any
                return inputService.InputBegan:Connect(function(input: any, processed: boolean): ()
                    if not lease.active or not probe.gun or probe.gun.Parent ~= localPlayer.Character then return end
                    local inputType: any = input.UserInputType
                    if inputType == Enum.UserInputType.Touch or inputType == Enum.UserInputType.MouseButton1 then
                        record("input_began", {input = tostring(inputType), processed = processed == true})
                    end
                end)
            end)
            if inputOk then probe.inputLink = inputLink end
            runtimeState.othProbeObserver = observeCall
            probe.namecallInstalled = installOthRaycast(false)
            if not probe.namecallInstalled then runtimeState.othProbeObserver = nil end
            tick(os.clock())
        end
        local configuration: any = table.clone(parentConfiguration)
        configuration.categoryName, configuration.restore = "Combat", false
        calibrationCard = host.createUniversalFeature("Gun Probe", "Temporary passive Oth gun diagnostics (60 seconds)", 3,
            function(enabled: boolean): () if enabled then start() else stop("Stopped") end end, configuration)
        statusRow = addCombatStatusRow(calibrationCard, "Status", "Off")
        host.addActionOption(calibrationCard, "Equip gun", function(): ()
            if not probe.active then report("Enable Gun Probe first"); return end
            local gun: Tool? = findWeapon("Gun")
            if gun and equip(gun) then record("equip_requested"); tick(os.clock()) else report("No gun found or equip failed") end
        end)
        host.addActionOption(calibrationCard, "Save report", function(): ()
            if not probe.started then report("No probe session to save") return end
            local saved: boolean, message: string = save()
            probe.saveFailed, probe.saveMessage = not saved, message
            report(saved and ("workspace/" .. reportPath .. " · " .. message) or ("save failed: " .. message))
        end)
        host.addActionOption(calibrationCard, "Test workspace", function(): ()
            -- This diagnostic deliberately does not start Gun Probe or install hooks.
            local path: string = "X2Duels-workspace-test.txt"
            local saved: boolean, message: string = writeWorkspace(path, "ARandomMenu workspace test\n")
            report(saved and ("workspace/" .. path .. " · " .. message) or ("workspace test failed: " .. message))
        end, "Test executor workspace without enabling Gun Probe or installing hooks.")
        local function saveWeaponSources(kind: string): ()
            -- No Probe or hook is required. The gun can be equipped or in the
            -- Backpack. Decompile is executor-provided and may fail or be detected.
            local weapon: Tool? = findWeapon(kind)
            if not weapon then report("No " .. string.lower(kind) .. " found in inventory or equipped"); return end
            local decompile: any = executorFunction("decompile")
            if not decompile then report(kind .. " sources: decompile unavailable"); return end
            if not executorFunction("writefile") then report(kind .. " sources: writefile unavailable"); return end
            report("Saving " .. string.lower(kind) .. " sources without Probe; please wait...")
            probe.sourceGeneration = (probe.sourceGeneration or 0) + 1
            local generation: number = probe.sourceGeneration
            local captureId: string = tostring(os.time()) .. "-" .. tostring(generation)
            local session: any = probe.active and probe.lease or nil
            task.spawn(function(): ()
                local saved: number = 0
                local attempted: number = 0
                local lastIssue: string? = nil
                local files: {any} = {}
                for _, item: Instance in ipairs(weapon:GetDescendants()) do
                    if runtimeState.closed or generation ~= probe.sourceGeneration then return end
                    if item:IsA("LocalScript") or item:IsA("ModuleScript") then
                        attempted += 1
                        local ok: boolean, source: any = pcall(decompile, item)
                        if runtimeState.closed or generation ~= probe.sourceGeneration then return end
                        if ok and type(source) == "string" and #source > 0 then
                            -- Distinct capture names prevent a failed new run
                            -- from masquerading as a previous successful one.
                            local filename: string = "X2Duels-" .. string.lower(kind) .. "-source-" .. captureId .. "-" .. tostring(attempted) .. ".luau"
                            local written: boolean, writeMessage: string = writeWorkspace(filename, source)
                            if written then
                                saved += 1
                                table.insert(files, {file = filename, name = item.Name, class = item.ClassName})
                            else
                                lastIssue = "write failed: " .. writeMessage
                            end
                        else
                            lastIssue = ok and "decompile returned empty" or "decompile failed"
                        end
                        if attempted >= 20 then break end
                    end
                end
                if runtimeState.closed or generation ~= probe.sourceGeneration then return end
                local manifest: any = {version = 1, captureId = captureId, weapon = weapon.Name, attempted = attempted, saved = saved,
                    sources = files, note = "Review sources for private data before sharing. No hooks installed by this action."}
                local encodedOk: boolean, encoded: any = pcall(function(): string
                    return game:GetService("HttpService"):JSONEncode(manifest)
                end)
                local manifestOk: boolean = false
                local manifestMessage: string = "JSONEncode unavailable"
                if encodedOk and type(encoded) == "string" then
                    manifestOk, manifestMessage = writeWorkspace("X2Duels-" .. string.lower(kind) .. "-sources.json", encoded)
                end
                if runtimeState.closed or generation ~= probe.sourceGeneration then return end
                if session and session.active and probe.active and session == probe.lease then
                    probe.sources = files
                    save()
                end
                local detail: string = if manifestOk then "manifest saved" else "manifest failed: " .. manifestMessage
                local problem: string = if attempted == 0 then " · no LocalScript/ModuleScript found"
                    elseif lastIssue then " · " .. lastIssue else ""
                report(kind .. " sources " .. tostring(saved) .. "/" .. tostring(attempted) .. " · " .. detail .. problem .. "; review before sharing")
            end)
        end
        host.addActionOption(calibrationCard, "Save gun sources", function(): () saveWeaponSources("Gun") end,
            "Save local Gun scripts without enabling Probe; decompile availability and safety vary by executor.")
        host.addActionOption(calibrationCard, "Save knife sources", function(): () saveWeaponSources("Knife") end,
            "Save local Knife scripts without enabling Probe; review the files before sharing.")
        host.addInformationOption(calibrationCard, "Passive shared Oth namecall probe: enable, equip Gun and shoot normally. Mouse property reads and direct function calls are not captured. Ray coordinates and script/remote names may be sensitive; review local files before sharing. Detection remains possible.")
        runtimeState.calibration = {tick = tick, stop = stop}
    end

    discoverMatchState()
    discoverClientGlobals()
    runtimeState.lastMatchToken = matchToken(localPlayer)
    runtimeState.observedRound = runtimeState.lastMatchToken ~= nil
    ensureRemoteEvents()
    track(localPlayer.CharacterAdded:Connect(function(): ()
        leaveSafePlace(false)
        runtimeState.deadPlayers[localPlayer] = nil
        runtimeState.selected = nil
        runtimeState.nextGunAt = 0
        runtimeState.nextKnifeAt["Auto Win"] = 0
        runtimeState.nextKnifeAt["Knife Throw"] = 0
        cancelGun()
        cancelKnifeThrow()
        restoreCamera()
    end))
    track(players.PlayerRemoving:Connect(function(player: Player): ()
        runtimeState.deadPlayers[player] = nil
        if runtimeState.selected and runtimeState.selected.player == player then
            runtimeState.selected = nil
        end
        restoreHitbox(player)
    end))

    host.featureConnections.X2DuelsCore = runtime.TaskManager:Connect(update)

end

function Module.init(runtime: any): any
    if Module.Initialized then
        return Module
    end
    assert(type(runtime) == "table" and runtime.TaskManager,
        "X2Duels requires Runtime.TaskManager")
    Module.Runtime = runtime
    local ok: boolean, failure: any = pcall(buildX2Duels, runtime)
    if not ok then
        moduleCleanup()
        Module.Runtime = nil
        error(failure)
    end
    Module.Initialized = true
    return Module
end

function Module.destroy(): ()
    moduleCleanup()
    moduleCleanup = function(): () end
    Module.Runtime = nil
    Module.Initialized = false
end

return Module
