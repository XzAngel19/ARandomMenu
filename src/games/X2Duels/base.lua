-- X2 Duels (MVS) native combat and observed session statistics.
--
-- The supplied Cobalt log captures DefaultGun/DefaultKnife native calls,
-- including fire/showBeam and the respawn/death events. Combat still goes
-- through the game's own Tool:Activate() path; no remote arguments are guessed.

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
        silentMode = "Legit",
        autoShoot = false,
        knifeThrow = false,
        killAura = false,
        hitboxes = false,
        teamCheck = true,
        wallCheck = true,
        maxDistance = 1000,
        autoShootTeamCheck = true,
        autoShootWallCheck = true,
        autoShootRange = 1000,
        autoShootCooldown = 0,
        knifeTeamCheck = true,
        knifeWallCheck = true,
        knifeRange = 600,
        knifeCooldown = 0,
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

    local function targetPartOf(character: Model?): BasePart?
        if not character then
            return nil
        end
        local head: Instance? = character:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            return head :: BasePart
        end
        return rootOf(character)
    end

    local function targetRecord(player: Player): {[string]: any}?
        local character: Model? = player.Character
        local part: BasePart? = targetPartOf(character)
        if not character or not part then
            return nil
        end
        return {player = player, character = character, part = part}
    end

    local function hasLineOfSight(target: {[string]: any}, from: Vector3?): boolean
        local camera: Camera? = currentWorkspace.CurrentCamera
        local localRoot: BasePart? = rootOf(localPlayer.Character)
        local origin: Vector3? = from or (if camera then camera.CFrame.Position
            elseif localRoot then localRoot.Position else nil)
        if not origin then
            return false
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
            return false
        end
        return hit == nil or hit.Instance:IsDescendantOf(target.character)
    end

    local function nearestEnemy(
        maxDistance: number, teamCheckOverride: boolean?, wallCheckOverride: boolean?,
        cacheSelection: boolean?
    ): {[string]: any}?
        local checkWall: boolean = if wallCheckOverride == nil then settings.wallCheck
            else wallCheckOverride
        local localRoot: BasePart? = rootOf(localPlayer.Character)
        if not localRoot or not isAlive(localPlayer) then
            if cacheSelection ~= false then runtimeState.selected = nil end
            return nil
        end
        local best: {[string]: any}? = nil
        local bestDistance: number = maxDistance
        for _, player: Player in ipairs(players:GetPlayers()) do
            if isEnemy(player, false, teamCheckOverride) then
                local target: {[string]: any}? = targetRecord(player)
                if target then
                    local distance: number =
                        (target.part.Position - localRoot.Position).Magnitude
                    if distance <= bestDistance
                        and (not checkWall or hasLineOfSight(target)) then
                        best = target
                        bestDistance = distance
                    end
                end
            end
        end
        if cacheSelection ~= false then runtimeState.selected = best end
        return best
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
        local gunStructure: boolean = hasChild(tool, {"fire", "showBeam", "GunKill"})
        local knifeStructure: boolean = hasChild(tool, {
            "ThrowEvent", "SlashEvent", "MobileKnifeLocalScript", "KnifeKill",
        })
        return rules.classifyTool(tool.Name, gunStructure, knifeStructure)
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

    local function activateNative(
        tool: Tool?,
        target: {[string]: any}?,
        aimAtTarget: boolean?
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
            -- Do not let Silent's independent target override another card's
            -- native shot while its deferred Activated handler reads the aim.
            runtimeState.nativeAimUntil = os.clock() + 0.1
            aimWithCFrame(target.part.Position)
        end
        local ok: boolean = pcall(function(): ()
            tool:Activate()
        end)
        return ok
    end

    local function selectedTarget(): {[string]: any}?
        local target: any = runtimeState.selected
        if not target or not isAlive(localPlayer) or not isEnemy(target.player) then
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
        if settings.wallCheck and not hasLineOfSight(target) then return nil end
        return target
    end

    local function fireGun(target: {[string]: any}?, noAim: boolean?): (boolean, boolean)
        local gun: Tool? = findWeapon("Gun")
        if not gun then
            return false, false
        end
        if not target or runtimeState.knifeBusy then
            return false, true
        end
        return activateNative(gun, target, noAim ~= true), true
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
                if aimAtTarget then aimWithCFrame(target.part.Position) end
                if useTouch and throwMode then
                    pending.throwMode = throwMode
                    pending.previousThrowMode = throwMode.Value
                    throwMode.Value = true
                    if stillValid() then activateNative(knife, target, aimAtTarget) end
                    task.wait()
                elseif canMouse then
                    local pressed: boolean = pcall(host.mouse2press)
                    if pressed then
                        pending.rightDown = true
                        -- Preserve the pre-existing desktop native windup.
                        task.wait(0.2)
                        if stillValid() then activateNative(knife, target, aimAtTarget) end
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

    local function isWeaponCaller(tool: Tool): boolean
        local getCaller: any = host.getcallingscript
        if type(getCaller) ~= "function" then return false end
        local ok: boolean, caller: any = pcall(getCaller)
        return ok and typeof(caller) == "Instance" and caller:IsDescendantOf(tool)
    end

    local function redirectRay(origin: Vector3, direction: Vector3): Vector3?
        if runtimeState.suppressRaycast or os.clock() < runtimeState.nativeAimUntil
            or not settings.silentAim or settings.silentMode ~= "Silent" then
            return nil
        end
        local equipped: Tool? = equippedTool()
        -- MouseCast is also used for pings. A weapon being equipped and a ray
        -- near the camera do not prove that the ray belongs to a weapon.
        if not equipped or toolKind(equipped) == nil or not isWeaponCaller(equipped) then
            return nil
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
        if not nearCamera and not nearCharacter then
            return nil
        end
        if settings.wallCheck and not hasLineOfSight(target, origin) then return nil end
        local offset: Vector3 = target.part.Position - origin
        if offset.Magnitude < 0.05 then
            return nil
        end
        local reach: number = math.max(direction.Magnitude, offset.Magnitude + 5)
        return offset.Unit * reach
    end

    local function redirectKnifeThrow(remote: Instance, arguments: {[any]: any}): Vector3?
        if os.clock() < runtimeState.nativeAimUntil or not settings.silentAim
            or settings.silentMode ~= "Silent" or arguments.n ~= 3 then return nil end
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
        local wrapper: any = wrap(function(remote: any, ...: any): any
            if predecessor == nil then return nil end
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
        end
    end

    local function installHooks(): boolean
        local hookFunction: any = host.hookfunction
        if type(hookFunction) ~= "function" or type(host.getcallingscript) ~= "function" then
            return false
        end
        local newClosure: any = host.newcclosure
        local function wrap(callback: any): any
            return type(newClosure) == "function" and newClosure(callback) or callback
        end

        if not runtimeState.rayHookInstalled and host.Ray ~= nil then
            local predecessor: any = nil
            local callback: any = function(origin: any, direction: any): any
                if predecessor == nil then
                    return nil
                end
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
                runtimeState.rayHookInstalled = true
                predecessor = old
            end
        end

        if not runtimeState.raycastHookInstalled then
            local method: any = currentWorkspace.Raycast
            if type(method) == "function" then
                local predecessor: any = nil
                local callback: any = function(self: any, ...: any): any
                    if predecessor == nil then
                        return nil
                    end
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
                    runtimeState.raycastHookInstalled = true
                    predecessor = old
                end
            end
        end
        local installed: boolean = runtimeState.rayHookInstalled or runtimeState.raycastHookInstalled
        if installed then installKnifeHook(wrap) end
        return installed
    end

    local function uninstallHooks(): ()
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
        if type(hookFunction) ~= "function" then
            return
        end
        if runtimeState.rayHookInstalled and host.Ray ~= nil then
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
        if runtimeState.raycastHookInstalled then
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

    local function runGun(
        maxDistance: number, cooldown: number?, teamCheck: boolean, wallCheck: boolean
    ): (boolean, boolean, boolean)
        if cooldown ~= nil then runtimeState.nextGunAt = os.clock() + math.max(0, cooldown) end
        local target: {[string]: any}? = nearestEnemy(maxDistance, teamCheck, wallCheck, false)
        local fired: boolean, hasGun: boolean = fireGun(target)
        return fired, hasGun, target ~= nil
    end

    local function runKnifeThrow(
        maxDistance: number, cooldown: number, teamCheck: boolean, wallCheck: boolean, owner: string
    ): (boolean, boolean)
        local target: {[string]: any}? = nearestEnemy(maxDistance, teamCheck, wallCheck, false)
        local queued: boolean = fireKnife(target, false, {
            owner = owner, teamCheck = teamCheck, wallCheck = wallCheck,
            range = maxDistance, cooldown = cooldown,
        })
        return queued, target ~= nil
    end

    local function activeRound(): boolean
        if not matchToken(localPlayer) or runtimeState.resultsPending or not isAlive(localPlayer) then
            return false
        end
        local ok: boolean, gameData: any = matchApiCall("getGame", localPlayer)
        return ok and type(gameData) == "table" and gameData.Phase == "InGame"
            and gameData.RoundStarted == true and gameData.CurrentRoundEnded ~= true
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
        if now >= runtimeState.nextRemoteAt then
            runtimeState.nextRemoteAt = now + 2
            discoverMatchState()
            discoverClientGlobals()
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
        if settings.silentAim and now >= runtimeState.nextSelectionAt then
            runtimeState.nextSelectionAt = now + 0.06
            nearestEnemy(settings.maxDistance)
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
                    local fired: boolean, _hasGun: boolean, hasTarget: boolean = runGun(
                        settings.autoShootRange, settings.autoShootCooldown,
                        settings.autoShootTeamCheck, settings.autoShootWallCheck
                    )
                    usedGun = fired
                    setCombatStatus(autoShootCard, "Auto Shoot", fired and "Shot attempted"
                        or (hasTarget and "Gun not ready" or "Waiting for target / clear path"))
                end
                if autoRound then
                    if usedGun then
                        setAutoWinStatus("Gun shared with Auto Shoot")
                    else
                        -- Auto Win does not inherit the other card's filters or
                        -- cooldown. If Auto Shoot cannot act, it gets its own
                        -- safe target search without double-firing this tick.
                        local fired: boolean, _hasGun: boolean, hasTarget: boolean =
                            runGun(1000, nil, true, true)
                        setAutoWinStatus(fired and "Shot attempted"
                            or (hasTarget and "Gun not ready" or "Waiting for target / clear path"))
                    end
                end
            elseif autoRound then
                setAutoWinStatus("Waiting for knife throw")
            end
        elseif wantsKnife and not runtimeState.knifeBusy then
            local knifeAvailable: boolean = findWeapon("Knife") ~= nil
            local usedKnife: boolean = false
            if settings.knifeThrow then
                if not knifeAvailable then
                    setCombatStatus(knifeThrowCard, "Knife Throw", "Waiting for knife")
                elseif now >= runtimeState.nextKnifeAt["Knife Throw"] then
                    local queued: boolean, hasTarget: boolean = runKnifeThrow(
                        settings.knifeRange, settings.knifeCooldown,
                        settings.knifeTeamCheck, settings.knifeWallCheck, "Knife Throw"
                    )
                    usedKnife = queued
                    setCombatStatus(knifeThrowCard, "Knife Throw", queued and "Throw attempted"
                        or (hasTarget and "Knife/input not ready" or "Waiting for target / clear path"))
                end
            end
            if autoRound then
                if not knifeAvailable then
                    setAutoWinStatus("Waiting for knife")
                elseif usedKnife then
                    setAutoWinStatus("Knife shared with Knife Throw")
                elseif now >= runtimeState.nextKnifeAt["Auto Win"] then
                    local queued: boolean, hasTarget: boolean =
                        runKnifeThrow(600, 0, true, true, "Auto Win")
                    setAutoWinStatus(queued and "Throw attempted"
                        or (hasTarget and "Knife/input not ready" or "Waiting for target / clear path"))
                end
            end
        end
        if settings.killAura and not runtimeState.knifeBusy and not gunAvailable
            and not wantsKnife and now >= runtimeState.nextAuraAt then
            runKillAura()
        end
        if settings.hitboxes and now >= runtimeState.nextHitboxAt then
            runtimeState.nextHitboxAt = now + 0.2
            updateHitboxes()
        end
        if now >= runtimeState.nextStatsAt then
            runtimeState.nextStatsAt = now + 0.25
            updateStats()
        end
    end

    local function render(deltaTime: number): ()
        if not settings.silentAim or settings.silentMode ~= "Legit"
            or os.clock() < runtimeState.nativeAimUntil then
            return
        end
        local camera: Camera? = currentWorkspace.CurrentCamera
        local target: {[string]: any}? = selectedTarget()
        if not camera or not target then
            return
        end
        local desired: CFrame = CFrame.lookAt(camera.CFrame.Position, target.part.Position)
        camera.CFrame = camera.CFrame:Lerp(
            desired, math.clamp(deltaTime * 18, 0.05, 1)
        )
    end

    local core: any = nil
    local teamProvider: any = nil
    local roleProvider: any = nil

    moduleCleanup = function(): ()
        runtimeState.closed = true
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
        cancelKnifeThrow()
        restoreCamera()
        uninstallHooks()
        if host.featureConnections.X2DuelsCore then
            host.disconnectFeatureConnection("X2DuelsCore")
        end
        if host.featureConnections.X2DuelsLegitAim then
            host.disconnectFeatureConnection("X2DuelsLegitAim")
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
                runtimeState.autoWinStartedAt = os.clock()
                runtimeState.nextKnifeAt["Auto Win"] = 0
            elseif not enabled and settings.autoWin then
                if runtimeState.autoWinStartedAt then
                    runtimeState.autoWinElapsed += math.max(0, os.clock() - runtimeState.autoWinStartedAt)
                end
                runtimeState.autoWinStartedAt = nil
                leaveSafePlace(true)
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
        autoWinStats.status = state.addStatOption(autoWinCard, "Combat status", "Off")
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

    silentAimCard = card(
        "Silent AIM",
        "Aim at an opponent and fire using the assigned action button or key",
        3,
        function(enabled: boolean): ()
            settings.silentAim = enabled
            setAimActivity(enabled)
            if enabled and settings.silentMode == "Silent" and not installHooks() then
                pcall(notify, "X2 Duels · sin hooks Silent; el botón todavía intenta disparar con el arma nativa")
            end
            if not enabled then
                runtimeState.selected = nil
                uninstallHooks()
                if not runtimeState.knifeBusy and not settings.autoShoot and not settings.autoWin then
                    restoreCamera()
                end
            end
            setCombatStatus(silentAimCard, "Silent AIM", enabled and (
                settings.silentMode == "Silent" and not runtimeState.rayHookInstalled
                    and not runtimeState.raycastHookInstalled
                    and "Button only: hooks unavailable" or "Ready · assign action key"
            ) or nil)
        end,
        "Combat"
    )
    if type(state.addStatOption) == "function" then
        combatStatusRows["Silent AIM"] = state.addStatOption(
            silentAimCard, "Status", combatStatuses["Silent AIM"] or "Off"
        )
    end
    host.addCycleOption(
        silentAimCard, "Mode", {"Legit", "Silent"}, 1,
        function(value: string): ()
            settings.silentMode = value
            if value == "Silent" then
                if settings.silentAim and not installHooks() then
                    setCombatStatus(silentAimCard, "Silent AIM", "Button only: hooks unavailable")
                    pcall(notify, "X2 Duels · los hooks Silent no están disponibles; botón nativo disponible")
                end
            else
                uninstallHooks()
                if settings.silentAim then setCombatStatus(silentAimCard, "Silent AIM", "Ready · assign action key") end
            end
        end
    )
    host.addToggleOption(silentAimCard, "Team Check", true, function(value: boolean): ()
        settings.teamCheck = value
        runtimeState.selected = nil
    end)
    host.addToggleOption(silentAimCard, "Wall Check", true, function(value: boolean): ()
        settings.wallCheck = value
        runtimeState.selected = nil
    end)
    host.addNumberOption(silentAimCard, "Range", 1000, 50, 1500, function(value: number): ()
        settings.maxDistance = math.max(0, value)
    end)
    host.addInformationOption(
        silentAimCard,
        "Enable the module and use its assigned key/mobile action button to fire. Legit aims the camera; Silent redirects only proven weapon calls when supported by the executor."
    )

    local function pressSenderButton(): ()
        if not settings.silentAim then return end
        if runtimeState.knifeBusy then
            setCombatStatus(silentAimCard, "Silent AIM", "Waiting for knife throw")
            return
        end
        local target: {[string]: any}? = nearestEnemy(settings.maxDistance)
        local fired: boolean, hasGun: boolean = fireGun(target)
        setCombatStatus(silentAimCard, "Silent AIM", fired and "Shot attempted"
            or (not hasGun and "Waiting for gun" or "Waiting for target / gun ready"))
    end
    if type(state.bindFeatureActivationKey) == "function" then
        state.bindFeatureActivationKey(silentAimCard, Enum.KeyCode.Unknown, pressSenderButton)
    end

    autoShootCard = card(
        "Auto Shoot", "Automatically aim and activate the native gun independently of Silent AIM", 4,
        function(enabled: boolean): ()
            settings.autoShoot = enabled
            runtimeState.nextGunAt = 0
            setCombatStatus(autoShootCard, "Auto Shoot", enabled and "Waiting for gun" or nil)
        end,
        "Combat"
    )
    if type(state.addStatOption) == "function" then
        combatStatusRows["Auto Shoot"] = state.addStatOption(
            autoShootCard, "Status", combatStatuses["Auto Shoot"] or "Off"
        )
    end
    host.addToggleOption(autoShootCard, "Team Check", true, function(value: boolean): ()
        settings.autoShootTeamCheck = value
    end)
    host.addToggleOption(autoShootCard, "Wall Check", true, function(value: boolean): ()
        settings.autoShootWallCheck = value
    end)
    host.addNumberOption(autoShootCard, "Range", 1000, 50, 1500, function(value: number): ()
        settings.autoShootRange = math.max(0, value)
    end)
    host.addNumberOption(autoShootCard, "Cooldown", 0, 0, 2, function(value: number): ()
        settings.autoShootCooldown = math.clamp(value, 0, 10)
    end, "Seconds between activation attempts; the gun/server controls its own cooldown.", 0.01)
    host.addInformationOption(autoShootCard,
        "Works without Silent AIM. Native Tool activation is used; the server decides hits.")

    knifeThrowCard = card(
        "Knife Throw", "Automatically attempt native knife throws independently of Silent AIM", 5,
        function(enabled: boolean): ()
            settings.knifeThrow = enabled
            runtimeState.nextKnifeAt["Knife Throw"] = 0
            if not enabled then cancelKnifeThrow("Knife Throw") end
            setCombatStatus(knifeThrowCard, "Knife Throw", enabled and "Waiting for knife" or nil)
        end,
        "Combat"
    )
    if type(state.addStatOption) == "function" then
        combatStatusRows["Knife Throw"] = state.addStatOption(
            knifeThrowCard, "Status", combatStatuses["Knife Throw"] or "Off"
        )
    end
    host.addToggleOption(knifeThrowCard, "Team Check", true, function(value: boolean): ()
        settings.knifeTeamCheck = value
        cancelKnifeThrow("Knife Throw")
    end)
    host.addToggleOption(knifeThrowCard, "Wall Check", true, function(value: boolean): ()
        settings.knifeWallCheck = value
        cancelKnifeThrow("Knife Throw")
    end)
    host.addNumberOption(knifeThrowCard, "Range", 600, 50, 1500, function(value: number): ()
        settings.knifeRange = math.max(0, value)
        cancelKnifeThrow("Knife Throw")
    end)
    host.addNumberOption(knifeThrowCard, "Cooldown", 0, 0, 2, function(value: number): ()
        settings.knifeCooldown = math.clamp(value, 0, 10)
    end, "Seconds between throw attempts, in addition to the native windup.", 0.01)
    host.addInformationOption(knifeThrowCard,
        "Uses desktop right-click or the game's mobile ThrowMode and native Tool activation; release requires live verification.")

    local auraCard: any = card(
        "Kill Aura",
        "Use native knife activation on a nearby valid target",
        5,
        function(enabled: boolean): ()
            settings.killAura = enabled
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
        "Client-side enlargement only; the server can reject hits outside the real target.")

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
    host.featureConnections.X2DuelsLegitAim = runtime.TaskManager:Connect(render, "render")

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
