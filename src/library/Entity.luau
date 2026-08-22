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
    Player: Player,
    Character: Model,
    Humanoid: Humanoid,
    RootPart: BasePart,
    Head: BasePart?,
    Health: number,
    MaxHealth: number,
    Distance: number,
    Team: Team?,
    IsFriendly: boolean,
}

export type RangeQuery = {
    Range: number,
    Limit: number?,
    IgnoreTeam: boolean?,
    IgnoreWalls: boolean?,
    IgnoreFriends: boolean?,
    Angle: number?,
    Sort: string?,
}

export type EntityQuery = {
    -- Maximum angular distance from the ray, in pixels of screen space.
    Radius: number?,
    MaxDistance: number?,
    IgnoreTeam: boolean?,
    IgnoreWalls: boolean?,
    Part: string?,
}

export type EntityLibrary = {
    List: {Entity},
    ByPlayer: {[Player]: Entity},
    LocalEntity: Entity?,
    IsAlive: (self: EntityLibrary) -> boolean,
    Refresh: (self: EntityLibrary) -> {Entity},
    Get: (self: EntityLibrary, player: Player) -> Entity?,
    ForEach: (self: EntityLibrary, callback: (Entity) -> ()) -> (),
    IsFriendly: (self: EntityLibrary, player: Player) -> boolean,
    IsProtected: (self: EntityLibrary, player: Player) -> boolean,
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
        LocalEntity = nil,
        Connections = {},
        -- Four modules can each ask for a refresh in the same frame. Doing the
        -- work once per frame instead of four times is the single biggest
        -- saving in the whole visual stack.
        lastRefresh = -1,
        pool = setmetatable({}, {__mode = "k"}),
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

    function library:IsFriendly(player: Player): boolean
        -- Neutral teams are not friends: in most shooters everybody sits on
        -- "Neutral" until a round starts, and treating that as friendly makes
        -- every combat module refuse to work.
        local team: Team? = player.Team
        local localTeam: Team? = localPlayer.Team
        if not team or not localTeam then
            return false
        end
        if player.Neutral or localPlayer.Neutral then
            return false
        end
        return team == localTeam
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
        return list
    end

    function library:IsAlive(): boolean
        local _, humanoid, root = characterParts(localPlayer)
        return humanoid ~= nil and root ~= nil and humanoid.Health > 0
    end

    function library:Get(player: Player): Entity?
        return library.ByPlayer[player]
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
    function library:IsProtected(player: Player): boolean
        local friendList: any = host.state and host.state.friendList
        if friendList and type(friendList.isProtected) == "function" then
            return friendList.isProtected(player) == true
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

        for _, entity: Entity in ipairs(library.List) do
            if entity.Distance > query.Range then
                continue
            end
            if not query.IgnoreTeam and entity.IsFriendly then
                continue
            end
            if not query.IgnoreFriends and library:IsProtected(entity.Player) then
                continue
            end
            if halfAngle then
                local delta: Vector3 = (entity.RootPart.Position - resolvedOrigin.Position)
                    * Vector3.new(1, 0, 1)
                if delta.Magnitude > 0.001 and facing.Magnitude > 0.001 then
                    local dot: number = facing.Unit:Dot(delta.Unit)
                    if math.acos(math.clamp(dot, -1, 1)) > halfAngle then
                        continue
                    end
                end
            end
            if not query.IgnoreWalls and not library:VisibleFrom(entity) then
                continue
            end
            table.insert(candidates, entity)
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

        for _, entity: Entity in ipairs(library.List) do
            if not options.IgnoreTeam and entity.IsFriendly then
                continue
            end
            if entity.Distance > maxDistance then
                continue
            end
            local part: BasePart = entity.RootPart
            if options.Part == "Head" and entity.Head then
                part = entity.Head :: BasePart
            end
            local offset: Vector3 = part.Position - origin
            local along: number = offset:Dot(unit)
            if along <= 0 then
                continue
            end
            -- Perpendicular distance from the ray, which is the same ordering
            -- a screen-space check gives without needing the camera.
            local perpendicular: number = (offset - unit * along).Magnitude
            if perpendicular < bestScore then
                if options.IgnoreWalls or library:VisibleFrom(entity) then
                    best = entity
                    bestScore = perpendicular
                end
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
        local ray: Ray? = host.state and host.state.getAimRay and host.state.getAimRay()
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
        library.LocalEntity = nil
        if activeLibrary == library then
            activeLibrary = nil
        end
    end

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
