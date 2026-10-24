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
    local localPlayer: Player = players.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace
    local services: any = runtime.Services or {}
    local protectedTargets: any = services.protectedTargets
    local activity: any = services.activity
    local notify: any = host.notify or (runtime.Menu and runtime.Menu.Notify)
        or function(): () end

    local settings: {[string]: any} = {
        -- Auto Win is now a session-statistics card, not a combat driver.
        stats = false,
        silentAim = false,
        silentMode = "Legit",
        autoShoot = false,
        knifeThrow = false,
        killAura = false,
        hitboxes = false,
        teamCheck = true,
        wallCheck = true,
        senderMode = "CFrame",
        maxDistance = 1000,
        shotInterval = 0.035,
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
        lastWinAt = -math.huge,
        wins = 0,
        kills = 0,
        loses = 0,
        lastLossRound = -1,
        killVictims = setmetatable({}, {__mode = "k"}),
        sessionStartedAt = os.clock(),
        nextStatsAt = 0,
        nextSelectionAt = 0,
        nextGunAt = 0,
        knifeBusy = false,
        knifeToken = 0,
        knifePending = nil,
        nextAuraAt = 0,
        nextHitboxAt = 0,
        nextRemoteAt = 0,
        remoteBound = {},
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

    local function forceCardOff(card: any): ()
        if not card then
            return
        end
        task.defer(function(): ()
            card.enabled = false
            if host.configData and card.configKey then
                host.configData.states[card.configKey] = false
            end
            if type(host.refreshFeatureToggle) == "function" then
                pcall(host.refreshFeatureToggle, card)
            end
            if type(host.flushConfigSave) == "function" then
                pcall(host.flushConfigSave)
            end
        end)
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

    local function matchToken(player: Player): string?
        return rules.normalizeToken(firstAttribute(player, MATCH_ATTRIBUTES))
    end

    local function teamToken(player: Player): string?
        -- Do not fall back to player.Team here. MVS keeps players on a common
        -- Roblox lobby team in some states; that fallback made everyone green.
        -- Read every supported attribute so an FFA sentinel can be followed by
        -- a real replicated side instead of hiding it.
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
        -- Once either side has a match id, a missing/different id is not the
        -- same round. With no match API at all, retain manual-team compatibility.
        if mine ~= nil or theirs ~= nil then
            return mine ~= nil and mine == theirs
        end
        return true
    end

    local function relation(other: Player): string
        if other == localPlayer then
            return "Local"
        end
        return rules.relation(
            teamToken(localPlayer), teamToken(other), sharesMatch(other)
        )
    end

    local function isAlive(player: Player): boolean
        if runtimeState.deadPlayers[player] == true
            or firstAttribute(player, {"Died", "Dead"}) == true then
            return false
        end
        local character: Model? = player.Character
        local humanoid: Humanoid? = character
            and character:FindFirstChildOfClass("Humanoid")
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

    local function isEnemy(other: Player?, allowTeammates: boolean?): boolean
        if not other or other == localPlayer or not isAlive(other)
            or isProtected(other) then
            return false
        end
        return rules.isOpponent(
            teamToken(localPlayer), teamToken(other), sharesMatch(other),
            settings.teamCheck and allowTeammates ~= true
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

    local function hasLineOfSight(target: {[string]: any}): boolean
        local camera: Camera? = currentWorkspace.CurrentCamera
        local localRoot: BasePart? = rootOf(localPlayer.Character)
        local origin: Vector3? = if camera then camera.CFrame.Position
            elseif localRoot then localRoot.Position else nil
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

    local function nearestEnemy(maxDistance: number): {[string]: any}?
        local localRoot: BasePart? = rootOf(localPlayer.Character)
        if not localRoot then
            return nil
        end
        local best: {[string]: any}? = nil
        local bestDistance: number = maxDistance
        for _, player: Player in ipairs(players:GetPlayers()) do
            if isEnemy(player) then
                local target: {[string]: any}? = targetRecord(player)
                if target then
                    local distance: number =
                        (target.part.Position - localRoot.Position).Magnitude
                    if distance <= bestDistance
                        and (not settings.wallCheck or hasLineOfSight(target)) then
                        best = target
                        bestDistance = distance
                    end
                end
            end
        end
        runtimeState.selected = best
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
                override.camera.CFrame = override.cframe
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
            end
            override.token += 1
            local token: number = override.token
            camera.CFrame = CFrame.lookAt(camera.CFrame.Position, position)
            task.defer(function(): ()
                local current: any = runtimeState.cameraOverride
                if current == override and current.token == token then
                    restoreCamera()
                end
            end)
        end

        local root: BasePart? = rootOf(localPlayer.Character)
        if root then
            local flat: Vector3 = Vector3.new(position.X, root.Position.Y, position.Z)
            if (flat - root.Position).Magnitude > 0.05 then
                root.CFrame = CFrame.lookAt(root.Position, flat)
            end
        end
    end

    local function activateNative(
        tool: Tool?,
        target: {[string]: any}?
    ): boolean
        if not tool or not equip(tool) then
            return false
        end
        local enabledOk: boolean, enabled: any = pcall(function(): any
            return tool.Enabled
        end)
        if enabledOk and enabled == false then
            return false
        end
        if settings.senderMode == "CFrame" and target then
            aimWithCFrame(target.part.Position)
        end
        local ok: boolean = pcall(function(): ()
            tool:Activate()
        end)
        return ok
    end

    local function selectedTarget(): {[string]: any}?
        local target: any = runtimeState.selected
        if not target or not isEnemy(target.player) then
            return nil
        end
        if not target.part.Parent or not target.character.Parent then
            return nil
        end
        return target
    end

    local function fireGun(target: {[string]: any}?): (boolean, boolean)
        local gun: Tool? = findWeapon("Gun")
        if not gun then
            return false, false
        end
        if not target then
            return false, true
        end
        -- The exact same target drives Legit rendering, Silent ray rewriting
        -- and native activation; no hidden crosshair/mouse packet is involved.
        runtimeState.selected = target
        return activateNative(gun, target), true
    end

    local function cancelKnifeThrow(): ()
        runtimeState.knifeToken = (runtimeState.knifeToken or 0) + 1
        local pending: any = runtimeState.knifePending
        runtimeState.knifePending = nil
        runtimeState.knifeBusy = false
        if pending then
            if pending.rightDown and type(host.mouse2release) == "function" then
                pcall(host.mouse2release)
            end
            if pending.forceThrow and pending.tool then
                pcall(function(): ()
                    pending.tool:SetAttribute("ForceThrow", pending.previousForceThrow)
                end)
            end
        end
        restoreCamera()
    end

    local function fireKnife(target: {[string]: any}?): boolean
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

        local token: number = (runtimeState.knifeToken or 0) + 1
        runtimeState.knifeToken = token
        runtimeState.knifeBusy = true
        local pending: {[string]: any} = {
            tool = knife,
            rightDown = false,
            forceThrow = false,
            previousForceThrow = nil,
        }
        runtimeState.knifePending = pending

        task.spawn(function(): ()
            local ok: boolean, failure: any = pcall(function(): ()
                if token ~= runtimeState.knifeToken then return end
                if settings.senderMode == "CFrame" then
                    aimWithCFrame(target.part.Position)
                end

                local usedMouse: boolean = false
                if type(host.mouse2press) == "function"
                    and type(host.mouse2release) == "function" then
                    local pressed: boolean = pcall(host.mouse2press)
                    if pressed then
                        usedMouse = true
                        pending.rightDown = true
                        -- X2's desktop LocalScript enters its throwing state
                        -- from MouseButton2 before Tool:Activate().
                        task.wait(0.2)
                        if token ~= runtimeState.knifeToken then return end
                        if target.part.Parent then
                            activateNative(knife, target)
                        end
                        pending.rightDown = false
                        pcall(host.mouse2release)
                    end
                end

                if not usedMouse then
                    -- The touch/ForceThrow path is read by the same native
                    -- controller. It does not manufacture remote arguments.
                    pending.previousForceThrow = knife:GetAttribute("ForceThrow")
                    knife:SetAttribute("ForceThrow", true)
                    pending.forceThrow = true
                    if token ~= runtimeState.knifeToken then return end
                    if target.part.Parent then
                        activateNative(knife, target)
                    end
                    task.wait()
                end
            end)

            if token == runtimeState.knifeToken then
                if pending.rightDown and type(host.mouse2release) == "function" then
                    pcall(host.mouse2release)
                end
                if pending.forceThrow then
                    pcall(function(): ()
                        knife:SetAttribute("ForceThrow", pending.previousForceThrow)
                    end)
                end
                runtimeState.knifePending = nil
                runtimeState.knifeBusy = false
                restoreCamera()
            end
            if not ok then
                runtimeState.lastKnifeError = tostring(failure)
            end
        end)
        return true
    end

    local function redirectRay(origin: Vector3, direction: Vector3): Vector3?
        if runtimeState.suppressRaycast or not settings.silentAim
            or settings.silentMode ~= "Silent" then
            return nil
        end
        local equipped: Tool? = equippedTool()
        if not equipped or toolKind(equipped) == nil then
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
        local offset: Vector3 = target.part.Position - origin
        if offset.Magnitude < 0.05 then
            return nil
        end
        local reach: number = math.max(direction.Magnitude, offset.Magnitude + 5)
        return offset.Unit * reach
    end

    local function installHooks(): boolean
        local hookFunction: any = host.hookfunction
        if type(hookFunction) ~= "function" then
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
        return runtimeState.rayHookInstalled or runtimeState.raycastHookInstalled
    end

    local function uninstallHooks(): ()
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
        local now: number = os.clock()
        if runtimeState.lastWinRound == runtimeState.roundSerial then
            return false
        end
        if now - runtimeState.lastWinAt < 0.5 then
            return false
        end
        runtimeState.lastWinAt = now
        runtimeState.lastWinRound = runtimeState.roundSerial
        runtimeState.wins += 1
        return true
    end

    local function registerLoss(): boolean
        if runtimeState.lastLossRound == runtimeState.roundSerial
            or runtimeState.resultWinCounted then
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

    local function updateStats(): ()
        if not autoWinCard or type(autoWinCard.SetStatus) ~= "function" then
            return
        end
        if not settings.stats then
            autoWinCard:SetStatus(nil)
            return
        end
        local played: number = os.clock() - runtimeState.sessionStartedAt
        autoWinCard:SetStatus(string.format(
            "Wins: %d | Time Played: %s | Kills: %d | Loses: %d",
            runtimeState.wins,
            formatTimePlayed(played),
            runtimeState.kills,
            runtimeState.loses
        ))
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
        runtimeState.resultsPending = true
        runtimeState.observedRound = false
        runtimeState.resultWinCounted = false
        runtimeState.selected = nil
        cancelKnifeThrow()
        local arguments: {any} = {...}
        if rules.didLocalWin(arguments, resultIdentity(), false) then
            runtimeState.resultWinCounted = true
            registerWin()
            updateStats()
        end
    end

    local function onRemovePlayer(...: any): ()
        local arguments: {any} = {...}
        local removed: Player? = playerFromEvent(arguments)
        if removed and removed ~= localPlayer then
            return
        end
        -- RemovePlayer ends a round; it is not itself a victory or loss.
        runtimeState.resultsPending = true
        runtimeState.observedRound = false
        runtimeState.selected = nil
        cancelKnifeThrow()
    end

    local function onWinNotification(...: any): ()
        local arguments: {any} = {...}
        if rules.didLocalWin(arguments, resultIdentity(), true) then
            if registerWin() then
                runtimeState.resultWinCounted = true
            end
            updateStats()
        end
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
            -- SetDead is a death signal, never a win signal. Count one local
            -- loss per round and leave the other combat preferences alone.
            registerLoss()
            cancelKnifeThrow()
            restoreCamera()
            updateStats()
        end
    end

    local function onDestroyBody(...: any): ()
        local arguments: {any} = {...}
        -- The captured MVS DestroyBody shape is victim, optional data, killer.
        -- Only that observed third Player value is accepted as a local kill;
        -- a remote name or a victim alone never fabricates a kill.
        local victim: Player? = playerFromEventValue(arguments[1])
        local killer: Player? = playerFromEventValue(arguments[3])
        if victim and killer == localPlayer
            and runtimeState.killVictims[victim] ~= runtimeState.roundSerial then
            runtimeState.killVictims[victim] = runtimeState.roundSerial
            runtimeState.kills += 1
            updateStats()
        end
    end

    local function onPlayerRespawned(...: any): ()
        local arguments: {any} = {...}
        local respawned: Player? = playerFromEvent(arguments)
        if respawned then
            runtimeState.deadPlayers[respawned] = nil
            runtimeState.killVictims[respawned] = nil
        end
        if respawned and respawned ~= localPlayer then
            -- Another player's respawn must not reset our session statistics.
            return
        end
        runtimeState.deadPlayers[localPlayer] = nil
        runtimeState.roundSerial += 1
        runtimeState.observedRound = true
        runtimeState.resultsPending = false
        runtimeState.resultWinCounted = false
        runtimeState.nextGunAt = 0
        cancelKnifeThrow()
    end

    local function findRemote(path: string): Instance?
        local current: Instance? = replicated
        for segment: string in string.gmatch(path, "[^/]+") do
            current = current and current:FindFirstChild(segment)
        end
        return current
    end

    local function connectRemote(path: string, callback: any): ()
        if runtimeState.remoteBound[path] then
            return
        end
        local remote: Instance? = findRemote(path)
        if not remote then
            return
        end
        local ok: boolean, connection: any = pcall(function(): any
            return (remote :: any).OnClientEvent:Connect(callback)
        end)
        if ok and connection then
            runtimeState.remoteBound[path] = true
            track(connection)
        end
    end

    local function ensureRemoteEvents(): ()
        connectRemote("Packages/Networking/RE/Match/MatchResults", onMatchResults)
        connectRemote("Packages/Networking/RE/Match/RemovePlayer", onRemovePlayer)
        connectRemote("Packages/Networking/RE/Match/WinNotification", onWinNotification)
        connectRemote("Packages/Networking/RE/Match/SetDead", onSetDead)
        connectRemote("Packages/Networking/RE/Match/PlayerRespawned", onPlayerRespawned)
        connectRemote("Packages/Networking/RE/Combat/DestroyBody", onDestroyBody)
    end

    local function runGun(maxDistance: number, interval: number): (boolean, boolean)
        runtimeState.nextGunAt = os.clock() + interval
        local target: {[string]: any}? = nil
        if settings.silentAim then
            target = selectedTarget()
        end
        if not target then
            target = nearestEnemy(maxDistance)
        end
        return fireGun(target)
    end

    local function runKnifeThrow(maxDistance: number): ()
        -- No user interval: try on every scheduler tick. fireKnife only holds
        -- the short native windup, so a new attempt starts as soon as it ends.
        local target: {[string]: any}? = nearestEnemy(maxDistance)
        fireKnife(target)
    end

    local function runKillAura(): ()
        runtimeState.nextAuraAt = os.clock() + settings.killAuraInterval
        local knife: Tool? = findWeapon("Knife")
        if not knife then
            return
        end
        local target: {[string]: any}? = nearestEnemy(settings.killAuraRange)
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
        local seen: {[Player]: boolean} = {}
        local desiredSize: Vector3 = Vector3.new(
            settings.hitboxSize, settings.hitboxSize, settings.hitboxSize
        )
        for _, player: Player in ipairs(players:GetPlayers()) do
            if isEnemy(player) then
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
                        }
                        runtimeState.hitboxes[player] = record
                    end
                    if root.Size ~= desiredSize then
                        root.Size = desiredSize
                    end
                    root.Transparency = 0.65
                    root.CanCollide = false
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
            table.clear(runtimeState.deadPlayers)
            if token ~= nil then
                -- A lobby transition clears the old token before the next
                -- match arrives. That still starts a new win-counting round.
                runtimeState.resultsPending = false
                runtimeState.resultWinCounted = false
                runtimeState.observedRound = true
                runtimeState.roundSerial += 1
                runtimeState.nextGunAt = 0
            else
                runtimeState.observedRound = false
                runtimeState.selected = nil
            end
            runtimeState.lastMatchToken = token
        end
    end

    local function update(_deltaTime: number): ()
        updateMatchToken()
        local now: number = os.clock()
        if now >= runtimeState.nextRemoteAt then
            runtimeState.nextRemoteAt = now + 2
            ensureRemoteEvents()
        end
        if settings.silentAim and now >= runtimeState.nextSelectionAt then
            runtimeState.nextSelectionAt = now + 0.06
            nearestEnemy(settings.maxDistance)
        elseif not settings.silentAim then
            runtimeState.selected = nil
        end

        if settings.silentAim and settings.autoShoot
            and now >= runtimeState.nextGunAt then
            runGun(settings.maxDistance, settings.shotInterval)
        end
        if settings.silentAim and settings.knifeThrow then
            runKnifeThrow(600)
        end
        if settings.killAura and now >= runtimeState.nextAuraAt then
            runKillAura()
        end
        if settings.hitboxes and now >= runtimeState.nextHitboxAt then
            runtimeState.nextHitboxAt = now + 0.2
            updateHitboxes()
        end
        if settings.stats and now >= runtimeState.nextStatsAt then
            runtimeState.nextStatsAt = now + 0.25
            updateStats()
        end
    end

    local function render(deltaTime: number): ()
        if not settings.silentAim or settings.silentMode ~= "Legit" then
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
        settings.stats = false
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
        getStats = function(): {[string]: number}
            return {
                Wins = runtimeState.wins,
                TimePlayed = math.max(0, os.clock() - runtimeState.sessionStartedAt),
                Kills = runtimeState.kills,
                Loses = runtimeState.loses,
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
    if type(configData) == "table"
        and configData.values["X2Duels.layout"] ~= "v119" then
        local states: any = configData.states
        local values: any = configData.values
        if states["MVSD.SilentAIM.AutoShoot"] == nil
            and states["MVSD.AutoShoot"] ~= nil then
            states["MVSD.SilentAIM.AutoShoot"] = states["MVSD.AutoShoot"] == true
            if states["MVSD.AutoShoot"] == true then
                states["MVSD.SilentAIM"] = true
            end
        end
        if states["MVSD.SilentAIM.KnifeThrow"] == nil
            and states["MVSD.KnifeThrow"] ~= nil then
            states["MVSD.SilentAIM.KnifeThrow"] = states["MVSD.KnifeThrow"] == true
            if states["MVSD.KnifeThrow"] == true then
                states["MVSD.SilentAIM"] = true
            end
        end
        for _, optionKey: string in ipairs({"Sender", "Fireinterval"}) do
            local oldKey: string = "MVSD.AutoShoot." .. optionKey
            local newKey: string = "MVSD.SilentAIM." .. optionKey
            if values[newKey] == nil and values[oldKey] ~= nil then
                values[newKey] = values[oldKey]
            end
        end
        if states["MVSD.Hitbox"] == nil and states["MVSD.Hitboxes"] ~= nil then
            states["MVSD.Hitbox"] = states["MVSD.Hitboxes"] == true
        end
        -- The former Auto Win was a combat driver. Restore it as an opt-in
        -- statistics card, never as the old automation or its GUI options.
        states["MVSD.AutoFarm"] = false
        states["MVSD.AutoWin"] = false
        states["MVSD.TriggerBot"] = nil
        states["MVSD.AutoShoot"] = nil
        states["MVSD.KnifeThrow"] = nil
        states["MVSD.TeamESP"] = nil
        states["MVSD.AutoWin.PlayAgain"] = nil
        states["MVSD.PlayAgain"] = nil
        values["MVSD.AutoShoot.Throwinterval"] = nil
        values["MVSD.SilentAIM.Throwinterval"] = nil
        values["X2Duels.layout"] = "v119"
        if type(host.queueConfigSave) == "function" then
            host.queueConfigSave()
        end
    end

    local refreshAutoShootMode: () -> () = function(): () end

    autoWinCard = card(
        "Auto Win",
        "Session statistics only: Wins, Time Played, Kills and Loses",
        2,
        function(enabled: boolean): ()
            settings.stats = enabled
            runtimeState.nextStatsAt = 0
            updateStats()
        end,
        "Utilities"
    )
    host.addInformationOption(
        autoWinCard,
        "Status only. No automatic combat, rematch clicks or invented results; counters come from observed MVS events."
    )

    silentAimCard = card(
        "Silent AIM",
        "Nearest-player Gun/Knife combat with Legit camera aim or Silent local ray redirection",
        3,
        function(enabled: boolean): ()
            settings.silentAim = enabled
            setAimActivity(enabled)
            if enabled and settings.silentMode == "Silent" and not installHooks() then
                settings.silentAim = false
                setAimActivity(false)
                pcall(notify, "X2 Duels · Silent requiere hookfunction; Legit no lo necesita")
                forceCardOff(silentAimCard)
            end
            if not settings.silentAim then
                runtimeState.selected = nil
                cancelKnifeThrow()
                uninstallHooks()
                restoreCamera()
            end
            refreshAutoShootMode()
        end,
        "Combat"
    )
    local autoShootOptionLabel: TextLabel? = nil
    refreshAutoShootMode = function(): ()
        if autoShootOptionLabel then
            autoShootOptionLabel.Text = "Auto Shoot · " .. settings.silentMode
        end
        if silentAimCard and type(silentAimCard.SetStatus) == "function" then
            silentAimCard:SetStatus(
                settings.silentAim and settings.autoShoot and settings.silentMode or nil
            )
        end
    end
    if type(host.addSectionOption) == "function" then
        host.addSectionOption(silentAimCard, "Gun")
    end
    local autoShootButton: TextButton = host.addToggleOption(
        silentAimCard,
        "Auto Shoot",
        false,
        function(enabled: boolean): ()
            settings.autoShoot = enabled
            runtimeState.nextGunAt = 0
            if not enabled then
                restoreCamera()
            end
            refreshAutoShootMode()
        end,
        "Runs only while Silent AIM is ON; the same Legit/Silent mode is used for every shot.",
        true
    )
    if autoShootButton.Parent then
        autoShootOptionLabel = autoShootButton.Parent:FindFirstChild("OptionLabel") :: TextLabel?
    end
    refreshAutoShootMode()
    host.addCycleOption(
        silentAimCard, "Mode", {"Legit", "Silent"}, 1,
        function(value: string): ()
            settings.silentMode = value
            if value == "Silent" then
                if settings.silentAim and not installHooks() then
                    settings.silentAim = false
                    setAimActivity(false)
                    pcall(notify, "X2 Duels · no se pudieron instalar los hooks Silent")
                    forceCardOff(silentAimCard)
                end
            else
                uninstallHooks()
            end
            refreshAutoShootMode()
        end
    )
    host.addCycleOption(
        silentAimCard, "Sender", {"CFrame", "Button"}, 1,
        function(value: string): ()
            settings.senderMode = value
            restoreCamera()
        end
    )
    host.addNumberOption(
        silentAimCard, "Fire interval", 0.035, 0.02, 0.25,
        function(value: number): ()
            settings.shotInterval = value
        end
    )
    host.addToggleOption(silentAimCard, "Team Check", true, function(value: boolean): ()
        settings.teamCheck = value
        runtimeState.selected = nil
        restoreAllHitboxes()
    end)
    host.addToggleOption(silentAimCard, "Wall Check", true, function(value: boolean): ()
        settings.wallCheck = value
        runtimeState.selected = nil
    end)
    host.addNumberOption(silentAimCard, "Range", 1000, 50, 1500, function(value: number): ()
        settings.maxDistance = value
    end)
    host.addInformationOption(
        silentAimCard,
        "Team Check rejects confirmed teammates and unknown sides. Wall Check never redirects a ray through geometry."
    )
    host.addInformationOption(
        silentAimCard,
        "CFrame aims before native Tool:Activate() and needs no action button. Button preserves your camera; the assigned key fires without toggling Silent AIM."
    )

    local function pressSenderButton(): ()
        -- This is an action key, not the Silent AIM master toggle. CFrame is
        -- driven by Auto Shoot/native activation and never needs this button.
        if not settings.silentAim or settings.senderMode ~= "Button" then
            return
        end
        local target: {[string]: any}? = selectedTarget()
            or nearestEnemy(settings.maxDistance)
        fireGun(target)
    end
    if type(state.bindFeatureActivationKey) == "function" then
        state.bindFeatureActivationKey(
            silentAimCard, Enum.KeyCode.Unknown, pressSenderButton
        )
    end

    if type(host.addSectionOption) == "function" then
        host.addSectionOption(silentAimCard, "Knife")
    end
    host.addToggleOption(
        silentAimCard,
        "Knife Throw",
        false,
        function(enabled: boolean): ()
            settings.knifeThrow = enabled
            if not enabled then cancelKnifeThrow() end
        end,
        "Requires Silent AIM ON. Attempts the native throw on every frame; there is no interval setting.",
        true
    )
    host.addInformationOption(
        silentAimCard,
        "Knife Throw uses the native right-click/ForceThrow path and waits only for the native windup."
    )

    local auraCard: any = card(
        "Kill Aura",
        "Use native knife activation on a nearby valid target",
        5,
        function(enabled: boolean): ()
            settings.killAura = enabled
            runtimeState.nextAuraAt = 0
            if not enabled then restoreCamera() end
        end,
        "Combat"
    )
    host.addNumberOption(auraCard, "Reach", 12, 3, 25, function(value: number): ()
        settings.killAuraRange = value
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
    host.addNumberOption(hitboxCard, "Size", 10, 2, 30, function(value: number): ()
        settings.hitboxSize = value
        restoreAllHitboxes()
    end)

    runtimeState.lastMatchToken = matchToken(localPlayer)
    ensureRemoteEvents()
    track(localPlayer.CharacterAdded:Connect(function(): ()
        runtimeState.deadPlayers[localPlayer] = nil
        runtimeState.selected = nil
        runtimeState.nextGunAt = 0
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
