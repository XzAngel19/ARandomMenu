--!strict
--
-- Entity library.
--
-- Every visual and combat module needs the same three answers: who is alive,
-- where are their parts, and which of them is under the crosshair. Written per
-- module that becomes four slightly different `Players:GetPlayers()` loops with
-- four slightly different bugs — the ESP that kept drawing dead players, the
-- aim helper that happily targeted teammates. Vape solves it with one entity
-- library; this is the same idea with this menu's conventions.
--
-- The cache is rebuilt from Roblox signals (PlayerAdded / CharacterAdded /
-- AncestryChanged) rather than polled, and `refresh` only recomputes the cheap
-- per-frame numbers (health, distance).

export type Entity = {
    Player: Player?,
    Character: Model,
    Humanoid: Humanoid,
    RootPart: BasePart,
    Head: BasePart?,
    Health: number,
    MaxHealth: number,
    Distance: number,
    Team: Team?,
    IsFriendly: boolean,
    IsNPC: boolean,
    Name: string,
}

export type RangeQuery = {
    Range: number,
    Limit: number?,
    IgnoreTeam: boolean?,
    IgnoreWalls: boolean?,
    IgnoreFriends: boolean?,
    Angle: number?,
    Sort: string?,
    IncludeNPCs: boolean?,
}

export type EntityQuery = {
    -- Maximum angular distance from the ray, in pixels of screen space.
    Radius: number?,
    MaxDistance: number?,
    IgnoreTeam: boolean?,
    IgnoreWalls: boolean?,
    IgnoreFriends: boolean?,
    Part: string?,
    IncludeNPCs: boolean?,
}

export type EntityLibrary = {
    List: {Entity},
    ByPlayer: {[Player]: Entity},
    NPCList: {Entity},
    ByModel: {[Model]: Entity},
    LocalEntity: Entity?,
    IsAlive: (self: EntityLibrary) -> boolean,
    Refresh: (self: EntityLibrary) -> {Entity},
    Get: (self: EntityLibrary, player: Player) -> Entity?,
    GetNpc: (self: EntityLibrary, model: Model) -> Entity?,
    ForEach: (self: EntityLibrary, callback: (Entity) -> ()) -> (),
    IsFriendly: (self: EntityLibrary, player: Player?) -> boolean,
    IsFriendlyModel: (self: EntityLibrary, model: Model) -> boolean,
    IsProtected: (self: EntityLibrary, player: Player?) -> boolean,
    InRange: (self: EntityLibrary, query: RangeQuery) -> {Entity},
    ClosestToRay: (
        self: EntityLibrary,
        origin: Vector3,
        direction: Vector3,
        query: EntityQuery?
    ) -> Entity?,
    ClosestToCursor: (self: EntityLibrary, query: EntityQuery?) -> Entity?,
    VisibleFrom: (self: EntityLibrary, entity: Entity) -> boolean,
    Rig: (self: EntityLibrary, entity: Entity) -> {{BasePart}},
    Destroy: (self: EntityLibrary) -> (),
}

local Module = {
    Name = "Entity",
    PlaceId = 0,
    Events = {} :: {[string]: any},
    Initialized = false,
}

-- Bone pairs for both official rigs. R15 is listed first because a missing
-- lookup falls through to R6, and R6 characters have none of these parts.
local R15_BONES: {{string}} = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
}

local R6_BONES: {{string}} = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"},
}

local activeLibrary: EntityLibrary? = nil

function Module.init(context: any): EntityLibrary
    local host: any = context
    local players: Players = host.Players
    local localPlayer: Player = host.LocalPlayer
    local currentWorkspace: Workspace = host.workspace or workspace

    local library: any = {
        List = {},
        ByPlayer = {},
        NPCList = {},
        ByModel = {},
        LocalEntity = nil,
        Connections = {},
        -- Four modules can each ask for a refresh in the same frame. Doing the
        -- work once per frame instead of four times is the single biggest
        -- saving in the whole visual stack.
        lastRefresh = -1,
        pool = setmetatable({}, {__mode = "k"}),
        npcPool = setmetatable({}, {__mode = "k"}),
        npcModels = setmetatable({}, {__mode = "k"}),
        rigs = setmetatable({}, {__mode = "k"}),
    }

    local function characterParts(player: Player): (Model?, Humanoid?, BasePart?)
        local character: Model? = player.Character
        if not character or not character.Parent then
            return nil, nil, nil
        end
        local humanoid: Humanoid? =
            character:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? =
            character:FindFirstChild("HumanoidRootPart") :: BasePart?
        return character, humanoid, root
    end

    local function localRoot(): BasePart?
        local _, _, root = characterParts(localPlayer)
        return root
    end

    -- Experiences do not agree on how an NPC declares its faction. Prefer
    -- explicit attributes, then Team/TeamColor-like properties, and compare a
    -- normalized name or value with the local player. Missing metadata is
    -- neutral rather than friendly: an unlabelled training dummy must not make
    -- every NPC disappear when Team check is enabled.
    local TEAM_ATTRIBUTE_NAMES: {string} = {
        "Team",
        "TeamId",
        "TeamID",
        "Faction",
        "FactionId",
        "FactionID",
    }

    local function normalizeTeamValue(value: any): string?
        if value == nil then
            return nil
        end
        if typeof(value) == "Instance" then
            return "name:" .. string.lower((value :: Instance).Name)
        end
        if type(value) == "table" and type(value.Name) == "string" then
            return "name:" .. string.lower(value.Name)
        end
        if type(value) == "table"
            and type(value.R) == "number"
            and type(value.G) == "number"
            and type(value.B) == "number" then
            return string.format(
                "colour:%d:%d:%d",
                math.round(value.R * 255),
                math.round(value.G * 255),
                math.round(value.B * 255)
            )
        end
        if type(value) == "table" and value.Color ~= nil then
            local nested: string? = normalizeTeamValue(value.Color)
            if nested then
                return nested
            end
        end
        if type(value) == "string" then
            return "name:" .. string.lower(value)
        end
        local text: string = tostring(value)
        if text == "" or text == "nil" then
            return nil
        end
        return "value:" .. string.lower(text)
    end

    local function teamToken(instance: Instance): string?
        for _, attributeName: string in ipairs(TEAM_ATTRIBUTE_NAMES) do
            local ok: boolean, value: any = pcall(
                instance.GetAttribute,
                instance,
                attributeName
            )
            if ok then
                local normalized: string? = normalizeTeamValue(value)
                if normalized then
                    return normalized
                end
            end
        end

        local direct: any = (instance :: any).Team
        local normalizedDirect: string? = normalizeTeamValue(direct)
        if normalizedDirect then
            return normalizedDirect
        end
        local colour: any = (instance :: any).TeamColor
        local normalizedColour: string? = normalizeTeamValue(colour)
        if normalizedColour then
            return normalizedColour
        end
        local child: Instance? = instance:FindFirstChild("Team")
        if child then
            local childValue: any = (child :: any).Value
            return normalizeTeamValue(childValue or child.Name)
        end
        return nil
    end

    local function localTeamToken(): string?
        return teamToken(localPlayer)
    end

    function library:IsFriendly(player: Player?): boolean
        if not player or player == localPlayer then
            return false
        end
        -- Neutral players are deliberately not assigned to a team.
        if player.Neutral == true or localPlayer.Neutral == true then
            return false
        end
        local localToken: string? = localTeamToken()
        local targetToken: string? = teamToken(player)
        return localToken ~= nil and targetToken ~= nil and localToken == targetToken
    end

    function library:IsFriendlyModel(model: Model): boolean
        if model == localPlayer.Character then
            return false
        end
        local localToken: string? = localTeamToken()
        local targetToken: string? = teamToken(model)
        return localToken ~= nil and targetToken ~= nil and localToken == targetToken
    end

    local function npcParts(model: Model): (Humanoid?, BasePart?)
        local humanoid: Humanoid? =
            model:FindFirstChildOfClass("Humanoid") :: Humanoid?
        local root: BasePart? =
            model:FindFirstChild("HumanoidRootPart") :: BasePart?
                or model.PrimaryPart
                or model:FindFirstChildWhichIsA("BasePart") :: BasePart?
        return humanoid, root
    end

    local function isNpcModel(model: Model): boolean
        if not model.Parent or model == localPlayer.Character then
            return false
        end
        if players:GetPlayerFromCharacter(model) ~= nil then
            return false
        end
        local humanoid: Humanoid?, root: BasePart? = npcParts(model)
        return humanoid ~= nil and root ~= nil
    end

    local function modelFor(instance: Instance): Model?
        if instance:IsA("Model") then
            return instance :: Model
        end
        return instance:FindFirstAncestorOfClass("Model") :: Model?
    end

    local function indexNpc(instance: Instance): ()
        local model: Model? = modelFor(instance)
        if model and isNpcModel(model) then
            library.npcModels[model] = true
        end
    end

    local function unindexNpc(instance: Instance): ()
        local model: Model? = modelFor(instance)
        if model and (instance == model or not model.Parent) then
            library.npcModels[model] = nil
            library.ByModel[model] = nil
        end
    end

    local function refreshNpcs(originPosition: Vector3): ()
        local list: {Entity} = library.NPCList
        local byModel: {[Model]: Entity} = library.ByModel
        table.clear(list)
        table.clear(byModel)
        for model: Model in pairs(library.npcModels) do
            if not isNpcModel(model) then
                library.npcModels[model] = nil
                continue
            end
            local humanoid: Humanoid?, root: BasePart? = npcParts(model)
            if not humanoid or not root or humanoid.Health <= 0 then
                continue
            end
            local entity: any = library.npcPool[model]
            if not entity then
                entity = {}
                library.npcPool[model] = entity
            end
            entity.Player = nil
            entity.Character = model
            entity.Humanoid = humanoid
            entity.RootPart = root
            entity.Head = model:FindFirstChild("Head") :: BasePart?
            entity.Health = humanoid.Health
            entity.MaxHealth = math.max(humanoid.MaxHealth, 1)
            entity.Distance = (originPosition - root.Position).Magnitude
            entity.Team = nil
            entity.IsFriendly = library:IsFriendlyModel(model)
            entity.IsNPC = true
            entity.Name = model.Name
            byModel[model] = entity
            table.insert(list, entity)
        end
    end

    function library:Refresh(force: boolean?): {Entity}
        -- Coalesced: repeated calls inside one frame return the list that was
        -- already built. ESP, Kill Aura and TriggerBot all ask on the same
        -- frame, and rebuilding the world three times shows up as frame time.
        local now: number = os.clock()
        if not force and now - library.lastRefresh < 0.015 then
            return library.List
        end
        library.lastRefresh = now

        local origin: BasePart? = localRoot()
        local originPosition: Vector3 = origin and origin.Position or Vector3.zero
        local list: {Entity} = library.List
        table.clear(list)
        local byPlayer: {[Player]: Entity} = library.ByPlayer
        table.clear(byPlayer)

        for _, player: Player in ipairs(players:GetPlayers()) do
            local character, humanoid, root = characterParts(player)
            if not character or not humanoid or not root then
                continue
            end
            if humanoid.Health <= 0 then
                continue
            end
            -- One table per player, reused every frame: an ESP that allocates
            -- a fresh table per player per frame is an ESP that keeps the
            -- collector busy for as long as it is on.
            local entity: any = library.pool[player]
            if not entity then
                entity = {}
                library.pool[player] = entity
            end
            entity.Player = player
            entity.Character = character
            entity.Humanoid = humanoid
            entity.RootPart = root
            entity.Head = character:FindFirstChild("Head") :: BasePart?
            entity.Health = humanoid.Health
            entity.MaxHealth = math.max(humanoid.MaxHealth, 1)
            entity.Distance = (originPosition - root.Position).Magnitude
            entity.Team = player.Team
            entity.IsFriendly = library:IsFriendly(player)
            entity.IsNPC = false
            entity.Name = player.Name

            byPlayer[player] = entity
            if player == localPlayer then
                library.LocalEntity = entity
            else
                table.insert(list, entity)
            end
        end

        if not byPlayer[localPlayer] then
            library.LocalEntity = nil
        end
        refreshNpcs(originPosition)
        return list
    end

    function library:IsAlive(): boolean
        local _, humanoid, root = characterParts(localPlayer)
        return humanoid ~= nil and root ~= nil and humanoid.Health > 0
    end

    function library:Get(player: Player): Entity?
        return library.ByPlayer[player]
    end

    function library:GetNpc(model: Model): Entity?
        return library.ByModel[model]
    end

    function library:ForEach(callback: (Entity) -> ()): ()
        for _, entity: Entity in ipairs(library.List) do
            callback(entity)
        end
    end

    function library:VisibleFrom(entity: Entity): boolean
        local camera: Camera? = currentWorkspace.CurrentCamera
        if not camera then
            return false
        end
        local parameters: RaycastParams = RaycastParams.new()
        parameters.FilterType = Enum.RaycastFilterType.Exclude
        parameters.IgnoreWater = true
        parameters.FilterDescendantsInstances = {
            entity.Character,
            localPlayer.Character :: any,
            camera,
        }
        local origin: Vector3 = camera.CFrame.Position
        local target: Vector3 = entity.RootPart.Position
        local result: RaycastResult? = currentWorkspace:Raycast(
            origin,
            target - origin,
            parameters
        )
        return result == nil
    end

    -- Bones are resolved once per character and kept: a rig does not change
    -- shape between frames, and fourteen FindFirstChild pairs per player per
    -- frame is pure waste.
    function library:Rig(entity: Entity): {{BasePart}}
        local character: Model = entity.Character
        local cached: any = library.rigs[character]
        if cached then
            return cached
        end
        local bones: {{BasePart}} = {}
        local definitions: {{string}} =
            character:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
        for _, pair: {string} in ipairs(definitions) do
            local first: BasePart? = character:FindFirstChild(pair[1]) :: BasePart?
            local second: BasePart? = character:FindFirstChild(pair[2]) :: BasePart?
            if first and second then
                table.insert(bones, {first, second})
            end
        end
        library.rigs[character] = bones
        return bones
    end

    -- The friend list is universal and may not be loaded yet, so the question
    -- is asked through `state` rather than captured at init.
    function library:IsProtected(player: Player?): boolean
        if not player then
            return false
        end
        local targets: any = host.services and host.services.protectedTargets
        if targets and type(targets.isProtected) == "function" then
            return targets.isProtected(player) == true
        end
        return false
    end

    -- Everything a melee module needs in one query: who is close enough, in
    -- front of you, not a friend, not behind a wall — already sorted.
    function library:InRange(query: RangeQuery): {Entity}
        local origin: BasePart? = localRoot()
        if not origin then
            return {}
        end
        local resolvedOrigin: BasePart = origin :: BasePart
        local facing: Vector3 = resolvedOrigin.CFrame.LookVector
            * Vector3.new(1, 0, 1)
        local halfAngle: number? = query.Angle and math.rad(query.Angle) / 2 or nil
        local candidates: {Entity} = {}

        local function consider(entity: Entity): ()
            if entity.Distance > query.Range then
                return
            end
            if not query.IgnoreTeam and entity.IsFriendly then
                return
            end
            if not query.IgnoreFriends and library:IsProtected(entity.Player) then
                return
            end
            if halfAngle then
                local delta: Vector3 = (entity.RootPart.Position - resolvedOrigin.Position)
                    * Vector3.new(1, 0, 1)
                if delta.Magnitude > 0.001 and facing.Magnitude > 0.001 then
                    local dot: number = facing.Unit:Dot(delta.Unit)
                    if math.acos(math.clamp(dot, -1, 1)) > halfAngle then
                        return
                    end
                end
            end
            if not query.IgnoreWalls and not library:VisibleFrom(entity) then
                return
            end
            table.insert(candidates, entity)
        end

        for _, entity: Entity in ipairs(library.List) do
            consider(entity)
        end
        if query.IncludeNPCs then
            for _, entity: Entity in ipairs(library.NPCList) do
                consider(entity)
            end
        end

        local sortMode: string = query.Sort or "Distance"
        table.sort(candidates, function(first: Entity, second: Entity): boolean
            if sortMode == "Health" then
                return first.Health < second.Health
            end
            if sortMode == "Threat" then
                -- Whoever is closest to looking at you first: the one most
                -- likely to be shooting back.
                return first.Distance / math.max(first.Health, 1)
                    > second.Distance / math.max(second.Health, 1)
            end
            return first.Distance < second.Distance
        end)

        local limit: number = query.Limit or #candidates
        while #candidates > limit do
            table.remove(candidates)
        end
        return candidates
    end

    function library:ClosestToRay(
        origin: Vector3,
        direction: Vector3,
        query: EntityQuery?
    ): Entity?
        local options: EntityQuery = query or {}
        local unit: Vector3 = direction.Magnitude > 0
            and direction.Unit
            or Vector3.new(0, 0, -1)
        local maxDistance: number = options.MaxDistance or math.huge
        local best: Entity? = nil
        local bestScore: number = math.huge

        local function consider(entity: Entity): ()
            if not options.IgnoreTeam and entity.IsFriendly then
                return
            end
            if entity.Distance > maxDistance then
                return
            end
            if not options.IgnoreFriends and library:IsProtected(entity.Player) then
                return
            end
            local part: BasePart = entity.RootPart
            if options.Part == "Head" and entity.Head then
                part = entity.Head :: BasePart
            end
            local offset: Vector3 = part.Position - origin
            local along: number = offset:Dot(unit)
            if along <= 0 then
                return
            end
            -- Perpendicular distance from the ray, which is the same ordering
            -- a screen-space check gives without needing the camera.
            local perpendicular: number = (offset - unit * along).Magnitude
            if perpendicular < bestScore
                and (options.IgnoreWalls or library:VisibleFrom(entity)) then
                best = entity
                bestScore = perpendicular
            end
        end
        for _, entity: Entity in ipairs(library.List) do
            consider(entity)
        end
        if options.IncludeNPCs then
            for _, entity: Entity in ipairs(library.NPCList) do
                consider(entity)
            end
        end

        local radius: number? = options.Radius
        if radius and bestScore > radius then
            return nil
        end
        return best
    end

    function library:ClosestToCursor(query: EntityQuery?): Entity?
        local camera: Camera? = currentWorkspace.CurrentCamera
        if not camera then
            return nil
        end
        local ray: Ray? = host.services and host.services.aim.getRay()
        local origin: Vector3 = ray and ray.Origin or camera.CFrame.Position
        local direction: Vector3 = ray and ray.Direction or camera.CFrame.LookVector
        return library:ClosestToRay(origin, direction, query)
    end

    function library:Destroy(): ()
        for _, connection: RBXScriptConnection in ipairs(library.Connections) do
            pcall(function(): ()
                connection:Disconnect()
            end)
        end
        library.Connections = {}
        library.List = {}
        library.ByPlayer = {}
        library.NPCList = {}
        library.ByModel = {}
        library.npcModels = setmetatable({}, {__mode = "k"})
        library.LocalEntity = nil
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

    -- NPCs are indexed from workspace signals as well. Their entities stay
    -- outside `List`, so ESP that is explicitly player-only keeps its existing
    -- contract, while combat queries can opt in without a full descendant scan
    -- each frame.
    for _, descendant: Instance in ipairs(currentWorkspace:GetDescendants()) do
        indexNpc(descendant)
    end
    table.insert(
        library.Connections,
        currentWorkspace.DescendantAdded:Connect(indexNpc)
    )
    table.insert(
        library.Connections,
        currentWorkspace.DescendantRemoving:Connect(unindexNpc)
    )

    -- Signal-driven invalidation. `Refresh` is cheap enough to call per frame,
    -- but a spawn or a leave should be reflected immediately rather than on
    -- whatever frame a consumer happens to ask next.
    table.insert(
        library.Connections,
        players.PlayerAdded:Connect(function(player: Player): ()
            table.insert(
                library.Connections,
                player.CharacterAdded:Connect(function(): ()
                    library:Refresh(true)
                end)
            )
            library:Refresh(true)
        end)
    )
    table.insert(
        library.Connections,
        players.PlayerRemoving:Connect(function(player: Player): ()
            library.ByPlayer[player] = nil
            library:Refresh(true)
        end)
    )
    for _, player: Player in ipairs(players:GetPlayers()) do
        table.insert(
            library.Connections,
            player.CharacterAdded:Connect(function(): ()
                library:Refresh(true)
            end)
        )
    end
    library:Refresh(true)

    activeLibrary = (library :: any) :: EntityLibrary
    Module.Initialized = true
    return (library :: any) :: EntityLibrary
end

function Module.destroy(): ()
    local library: EntityLibrary? = activeLibrary
    if library then
        library:Destroy()
    end
    activeLibrary = nil
    Module.Initialized = false
end

return Module
