--!strict
--
-- BedWars (place 8444591321).
--
-- Everything here comes from two records, not from guessing:
--
--   * `reference/remote-logs/8444591321-1787702434.json` — a live Remote Logger
--     capture of 17 remotes with their real argument shapes;
--   * `reference/bedwars-vape-6872274481.lua.txt` — a third-party client for
--     this exact place, read for behaviour only. Nothing is copied from it.
--
-- Three facts decide the shape of this file, and all three are different from
-- the BedFight module next door:
--
--   * Remotes are `@rbxts.net` managed and live under one long path. Most take a
--     single table, so a payload is built in one place and validated before it
--     is sent; a field the capture does not have is a refusal, not a guess.
--   * Blocks and beds are enumerated through CollectionService tags `'block'`
--     and `'bed'`. Nothing here sweeps the workspace, and streaming is handled
--     by the added/removed signals the tag already provides.
--   * `SwordHit` carries a `validate` block: the client's own position, camera
--     position, cursor direction and the target position. The server holds all
--     four, so the only honest reach is a payload built from where the
--     character actually stands. This module never invents one.
--
-- What the saved place in `reference/places/` is *not* useful for: it is the
-- asset library, not a live map. It carries 341 item and block meshes
-- (`wool_white`, `clay_tan`, `desert_pot`, the `bed_*` skins) and no beds,
-- generators or kits, because those stream in at runtime. The block names it
-- does carry are what `PlaceBlock` asks for.

export type Runtime = {
    Services: any,
    State: any,
}

local Module = {
    Name = "BedWars",
    PlaceId = 8444591321,
    Events = {} :: {[string]: any},
    Initialized = false,
}

local runtimeState: any = {
    connections = {} :: {[string]: any},
    remoteCache = {} :: {[string]: Instance?},
}

-- Every remote here is published under `ReplicatedStorage`, most of them below
-- `rbxts_include.node_modules.@rbxts.net.out._NetManaged` and two
-- (`PlaceBlock`, `DamageBlock`) one level deeper behind
-- `@easy-games.block-engine`. They are found by name and cached rather than by
-- path, so a reorganisation on the game's side costs nothing.
local function remote(name: string): Instance?
    local cached: Instance? = runtimeState.remoteCache[name]
    if cached and cached.Parent then
        return cached
    end
    local replicated: Instance? = game:GetService("ReplicatedStorage")
    if not replicated then
        return nil
    end
    local found: Instance? = nil
    for _, child: Instance in ipairs(replicated:GetDescendants()) do
        if child.Name == name
            and (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) then
            -- The name is unique in the capture; taking the first match keeps
            -- this from walking the tree twice when both prefixes are tried.
            found = child
            break
        end
    end
    if found == nil then
        return nil
    end
    runtimeState.remoteCache[name] = found
    return found :: Instance
end

-- One send path for the whole module. A remote that is not there is a refusal
-- the caller can report, never an error: a game update that renames a remote
-- should cost a feature, not the menu.
local function fire(name: string, ...: any): boolean
    local target: Instance? = remote(name)
    if not target then
        return false
    end
    local resolved: Instance = target :: Instance
    -- Packed first: `...` is not visible inside the closure pcall runs, and a
    -- send that silently dropped its arguments would look like a server that
    -- ignored the call.
    local args: any = table.pack(...)
    if resolved:IsA("RemoteFunction") then
        return pcall(function(): ()
            (resolved :: any):InvokeServer(table.unpack(args, 1, args.n))
        end)
    end
    return pcall(function(): ()
        (resolved :: any):FireServer(table.unpack(args, 1, args.n))
    end)
end

-- Sword cooldowns are per weapon: 0.30 s for wooden, iron, diamond, void and
-- light swords, 0.33 s for sparkler, 0.40 s for ice, 0.25 s for daggers and the
-- rageblade. Expressed as the ceiling in registered hits per ten seconds,
-- because that is the unit a BedWars player measures hitreg in.
local WEAPON_CEILING: {[string]: number} = {
    ice_sword = 25,
    sparkler = 30,
    sparkler_sword = 30,
    diamond_dagger = 40,
    iron_dagger = 40,
    rageblade = 40,
}

local DEFAULT_CEILING: number = 33

function Module.init(runtime: any): any
    local environment: any = getfenv()
    local host: any = environment
    local createUniversalFeature: any = host.createUniversalFeature
    local addToggleOption: any = host.addToggleOption
    local addNumberOption: any = host.addNumberOption
    local create: any = host.create
    local makeTextLabel: any = host.makeTextLabel
    local TaskManager: any = host.TaskManager
    local Players: any = host.Players
    local LocalPlayer: Player = host.LocalPlayer
    local _services: any = runtime.Services or (host.services or {})
    -- No registry table of its own yet: the shell publishes one per game
    -- (`state.bedFightFeatures` and friends) and BedWars does not have one
    -- until the shell registers this place module. Reading a field nothing
    -- assigns is exactly what the contracts gate refuses, so these cards group
    -- under the default section until the shell says otherwise. The two lines
    -- needed are requested in `docs/requests/A.md`.
    local registry: any = nil

    local function characterParts(): (Model?, Humanoid?, BasePart?)
        local own: Model? = LocalPlayer.Character
        if not own then
            return nil, nil, nil
        end
        return own,
            own:FindFirstChildOfClass("Humanoid") :: Humanoid?,
            own:FindFirstChild("HumanoidRootPart") :: BasePart?
    end

    local function camera(): Camera?
        return workspace.CurrentCamera
    end

    -- The equipped weapon, as the game names it. Weapons are Accessory
    -- instances under `ReplicatedStorage.Inventories.<player>.<item>`; there is
    -- no Tool in this game, which is the same trap BedFight has.
    local function equippedWeapon(): Instance?
        local own: Model? = LocalPlayer.Character
        if not own then
            return nil
        end
        for _, child: Instance in ipairs(own:GetChildren()) do
            if child:IsA("Accessory") then
                return child
            end
        end
        return nil
    end

    local function weaponCeiling(weapon: Instance?): number
        if not weapon then
            return DEFAULT_CEILING
        end
        return WEAPON_CEILING[(weapon :: Instance).Name] or DEFAULT_CEILING
    end

    -- Deliberately not consulting the Friend List, unlike every other combat
    -- card in this menu. BedWars is a team game with its own scoreboard: who
    -- is on your side is the game's answer, not a list maintained beside it,
    -- and the player asked for the aura to swing at whoever the game calls an
    -- enemy. The team check below is that answer, and it is on by default.
    local function isProtected(player: Player): boolean
        return player == LocalPlayer
    end

    local function sameTeam(player: Player): boolean
        return LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
    end

    -- Declared before the builders that read them: each toggle callback closes
    -- over its own feature to publish a status, and a local declared on the
    -- same line as the call is not visible to the closure inside it.
    -- Every connection this module owns, by the key it is stored under. One
    -- list so destroy can empty it without knowing which cards were enabled.
    local ownedConnections: {string} = {
        "BedWarsAura", "BedWarsClicker", "BedWarsPlace", "BedWarsNuke",
        "BedWarsEspAdded", "BedWarsEspRemoved", "BedWarsChest", "BedWarsAutoTool",
        "BedWarsInventory",
    }
    runtimeState.disconnectAll = function(): ()
        for _, key: string in ipairs(ownedConnections) do
            host.disconnectFeatureConnection(key)
        end
        -- Panels are parented to the ScreenGui, not to a connection, so
        -- dropping the listeners alone would leave them on screen.
        if type(runtimeState.cleanupPanels) == "function" then
            pcall(runtimeState.cleanupPanels)
        end
    end

    local AuraFeature: any = nil
    local ClickerFeature: any = nil
    local InventoryFeature: any = nil
    local PlaceFeature: any = nil
    local NukeFeature: any = nil
    local EspFeature: any = nil
    local ChestFeature: any = nil
    local AutoToolFeature: any = nil

    -- ------------------------------------------------------------------ aura
    --
    -- Deliberately small. The universal Kill Aura carries nineteen rows because
    -- it has to work in games nobody has looked at; this one has been looked
    -- at, so every row that did not change an outcome is gone. Four rows:
    -- reach, the hitreg band, how many targets, and the team check.
    local auraSettings: any = {
        reach = 12,
        minHits = 35,
        maxHits = 36,
        maxTargets = 1,
        -- On by default: in a team game the default answer to "should I swing
        -- at this player" is the scoreboard's, not ours.
        teamCheck = true,
    }
    local auraRuntime: any = {
        nextSwingAt = 0,
        hits = {} :: {number},
        highlights = {} :: {[Instance]: Highlight},
    }

    local function clearHighlights(): ()
        for key: Instance, highlight: Highlight in pairs(auraRuntime.highlights) do
            pcall(function(): ()
                highlight:Destroy()
            end)
            auraRuntime.highlights[key] = nil
        end
    end

    -- Registered hits in the last ten seconds, measured from the swings this
    -- module actually sent. A band the server refuses has to be visible; a
    -- status that echoes the setting back is decoration.
    local function registerHit(now: number): number
        local list: {number} = auraRuntime.hits
        table.insert(list, now)
        while #list > 0 and now - list[1] > 10 do
            table.remove(list, 1)
        end
        return #list
    end

    local function markTarget(targetCharacter: Model, colour: Color3): ()
        local existing: Highlight? = auraRuntime.highlights[targetCharacter]
        if not existing or not (existing :: Highlight).Parent then
            local created: Highlight = create("Highlight", {
                Name = "Wurst_BedWarsTarget",
                FillTransparency = 0.75,
                Parent = targetCharacter,
            }) :: Highlight
            auraRuntime.highlights[targetCharacter] = created
            existing = created
        end
        local highlight: Highlight = existing :: Highlight
        highlight.Adornee = targetCharacter
        highlight.FillColor = colour
        highlight.OutlineColor = colour
    end

    -- The payload is built from what is true right now: the character's own
    -- position, the camera the player is looking through, and the target's
    -- position. Anything else is a claim the server can contradict.
    local function swordHitPayload(targetRoot: BasePart): {[string]: any}?
        local _own: Model?, _humanoid: Humanoid?, root: BasePart? = characterParts()
        local view: Camera? = camera()
        if not root or not view then
            return nil
        end
        local weapon: Instance? = equippedWeapon()
        if not weapon then
            return nil
        end
        local origin: Vector3 = (view :: Camera).CFrame.Position
        local target: Vector3 = targetRoot.Position
        local direction: Vector3 = target - origin
        return {
            entityInstance = targetRoot.Parent,
            chargedAttack = {chargeRatio = 0},
            validate = {
                targetPosition = {value = target},
                selfPosition = {value = (root :: BasePart).Position},
                raycast = {
                    cameraPosition = {value = origin},
                    cursorDirection = {
                        value = direction.Magnitude > 0.001
                            and direction.Unit
                            or (view :: Camera).CFrame.LookVector,
                    },
                },
            },
            weapon = weapon,
        }
    end

    AuraFeature = createUniversalFeature(
        "Kill Aura",
        "Swings at players in reach on the weapon's own hitreg",
        1,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsAura")
            auraRuntime.nextSwingAt = 0
            auraRuntime.hits = {}
            clearHighlights()
            if not enabled then
                if AuraFeature then
                    AuraFeature:SetStatus(nil)
                end
                return
            end
            AuraFeature:SetStatus("0/10s")
            host.featureConnections.BedWarsAura =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < auraRuntime.nextSwingAt then
                        return
                    end
                    local own: Model?, humanoid: Humanoid?, root: BasePart? =
                        characterParts()
                    if not own or not humanoid or not root
                        or (humanoid :: Humanoid).Health <= 0 then
                        return
                    end

                    local origin: Vector3 = (root :: BasePart).Position
                    local reach: number = auraSettings.reach
                    local best: BasePart? = nil
                    local bestCharacter: Model? = nil
                    local bestDistance: number = reach
                    local hitCount: number = 0

                    for _, player: Player in ipairs(Players:GetPlayers()) do
                        if hitCount >= auraSettings.maxTargets then
                            break
                        end
                        if isProtected(player) then
                            continue
                        end
                        if auraSettings.teamCheck and sameTeam(player) then
                            continue
                        end
                        local other: Model? = player.Character
                        local otherHumanoid: Humanoid? = other
                            and other:FindFirstChildOfClass("Humanoid") :: Humanoid?
                        local otherRoot: BasePart? = other
                            and other:FindFirstChild("HumanoidRootPart") :: BasePart?
                        if not other or not otherHumanoid or not otherRoot
                            or (otherHumanoid :: Humanoid).Health <= 0 then
                            continue
                        end
                        local distance: number =
                            ((otherRoot :: BasePart).Position - origin).Magnitude
                        if distance > bestDistance then
                            continue
                        end
                        -- One swing, one target: the capture shows a single
                        -- entityInstance per SwordHit, so "multi" here would be
                        -- several remotes in one frame, which is a different
                        -- and much louder thing.
                        best = otherRoot :: BasePart
                        bestCharacter = other
                        bestDistance = distance
                        hitCount += 1
                    end

                    if not best or not bestCharacter then
                        clearHighlights()
                        AuraFeature:SetStatus(tostring(#auraRuntime.hits) .. "/10s")
                        return
                    end

                    local payload: {[string]: any}? =
                        swordHitPayload(best :: BasePart)
                    if not payload then
                        -- No weapon in hand, or no camera: nothing to claim.
                        clearHighlights()
                        return
                    end

                    local ceiling: number = weaponCeiling(equippedWeapon())
                    local low: number = math.clamp(auraSettings.minHits, 1, ceiling)
                    local high: number =
                        math.clamp(math.max(auraSettings.maxHits, low), 1, ceiling)
                    local drawn: number = low + (math.random() * (high - low))
                    auraRuntime.nextSwingAt = now + (10 / drawn)

                    local sent: boolean = fire("SwordHit", payload :: any)
                    markTarget(bestCharacter :: Model, Color3.fromRGB(235, 110, 110))
                    local registered: number = sent and registerHit(now) or 0
                    AuraFeature:SetStatus(tostring(registered) .. "/10s")
                end)
        end,
        {categoryName = "Combat", registry = registry}
    )
    addNumberOption(AuraFeature, "Reach", auraSettings.reach, 5, 30, function(value: number): ()
        auraSettings.reach = value
    end)
    -- Two rows, not a range control: hitreg is the one setting here a player
    -- tunes by feel, and min/max are the words the game's own community uses.
    -- 35-36 registered hits per ten seconds is above a 0.30 s sword's nominal
    -- ceiling of 33, which is the whole point - it sits in the margin the
    -- server leaves. The card clamps the pair to the equipped weapon, so an
    -- ice sword at 0.40 s cannot be asked for a rate it will refuse.
    addNumberOption(AuraFeature, "Hitreg min", auraSettings.minHits, 1, 40,
        function(value: number): ()
            auraSettings.minHits = value
            if auraSettings.maxHits < value then
                auraSettings.maxHits = value
            end
        end)
    addNumberOption(AuraFeature, "Hitreg max", auraSettings.maxHits, 1, 40,
        function(value: number): ()
            auraSettings.maxHits = math.max(value, auraSettings.minHits)
        end)
    addNumberOption(AuraFeature, "Max targets", auraSettings.maxTargets, 1, 5,
        function(value: number): ()
            auraSettings.maxTargets = math.round(value)
        end)
    addToggleOption(AuraFeature, "Team check", auraSettings.teamCheck,
        function(value: boolean): ()
            auraSettings.teamCheck = value
        end)

    -- `PlaceBlock` wants the block type, the placement position and a
    -- `mouseBlockInfo` table. The capture shows all three, with `blockData` at
    -- zero for every placement it recorded. Declared here, above both cards
    -- that place: a closure naming a local declared further down reads a
    -- global instead, and that global is nil.
    local placeSettings: any = {block = "wool_white", rate = 8}

    local function placeAt(position: Vector3): boolean
        return fire("PlaceBlock", {
            mouseBlockInfo = {placementPosition = position},
            blockType = placeSettings.block,
            blockData = 0,
            position = position,
        })
    end

    -- ------------------------------------------------------------- clicker
    --
    -- An autoclicker for this game has to know what is in the hand, because
    -- the three things worth clicking do three different things: a sword
    -- swings, wool places, a pickaxe mines. Anything else in hand is not
    -- clicked at all - a BedWars inventory is full of pearls, potions and
    -- armour, and clicking those is how a player wastes a stack.
    local clickSettings: any = {rate = 8, woolOnly = true, pickaxe = true}

    -- What is being held, by the only three names this card cares about.
    local function heldKind(): string?
        local own: Model? = LocalPlayer.Character
        if not own then
            return nil
        end
        local inventory: Instance? = game:GetService("ReplicatedStorage")
        inventory = inventory and inventory:FindFirstChild("Inventories") :: Instance?
        inventory = inventory and inventory:FindFirstChild(LocalPlayer.Name) :: Instance?
        local candidates: {Instance} = {}
        for _, child: Instance in ipairs((own :: Model):GetChildren()) do
            if child:IsA("Accessory") then
                table.insert(candidates, child)
            end
        end
        if inventory then
            for _, child: Instance in ipairs((inventory :: Instance):GetChildren()) do
                table.insert(candidates, child)
            end
        end
        for _, item: Instance in ipairs(candidates) do
            local name: string = item.Name
            if name:find("sword") then
                return "sword"
            end
        end
        for _, item: Instance in ipairs(candidates) do
            if item.Name:find("wool") then
                return "wool"
            end
        end
        if clickSettings.pickaxe then
            for _, item: Instance in ipairs(candidates) do
                if item.Name:find("pickaxe") then
                    return "pickaxe"
                end
            end
        end
        return nil
    end

    ClickerFeature = createUniversalFeature(
        -- Not "Auto Clicker": that card already exists in the universal set,
        -- and two rows with one name is how a player enables the wrong one.
        "Smart Clicker",
        "Clicks for the item in hand: sword, wool or pickaxe",
        7,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsClicker")
            if not enabled then
                if ClickerFeature then
                    ClickerFeature:SetStatus(nil)
                end
                return
            end
            ClickerFeature:SetStatus("idle")
            local nextAt: number = 0
            host.featureConnections.BedWarsClicker =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    local kind: string? = heldKind()
                    if not kind then
                        ClickerFeature:SetStatus("idle")
                        return
                    end
                    local own: Model?, humanoid: Humanoid?, root: BasePart? =
                        characterParts()
                    local view: Camera? = camera()
                    if not own or not humanoid or not root or not view
                        or (humanoid :: Humanoid).Health <= 0 then
                        return
                    end
                    nextAt = now + 1 / math.max(clickSettings.rate, 0.5)
                    ClickerFeature:SetStatus(kind :: string)

                    if kind == "sword" then
                        -- No target in reach is a real whiff, and the game
                        -- reports those too: SwordSwingMiss is in the capture.
                        fire("SwordSwingMiss", {
                            chargeRatio = 0,
                            weapon = equippedWeapon(),
                        })
                        return
                    end

                    local origin: Vector3 = (view :: Camera).CFrame.Position
                    local direction: Vector3 = (view :: Camera).CFrame.LookVector
                    local parameters: RaycastParams = RaycastParams.new()
                    parameters.FilterType = Enum.RaycastFilterType.Exclude
                    parameters.FilterDescendantsInstances = {own :: Model}
                    local hit: RaycastResult? =
                        workspace:Raycast(origin, direction * 20, parameters)
                    if not hit then
                        return
                    end
                    if kind == "wool" then
                        -- "Wool only" is the whole point of the row: a stack of
                        -- wool is cheap and replaceable, and the blocks a
                        -- player is saving for a bridge defence are not.
                        placeAt((hit :: RaycastResult).Position)
                        return
                    end
                    local position: Vector3 = (hit :: RaycastResult).Position
                    fire("DamageBlock", {
                        blockRef = {blockPosition = position},
                        hitPosition = position,
                        hitNormal = (hit :: RaycastResult).Normal,
                    })
                end)
        end,
        {categoryName = "Combat", registry = registry}
    )
    addNumberOption(ClickerFeature, "Clicks per second", clickSettings.rate, 1, 20,
        function(value: number): ()
            clickSettings.rate = value
        end)
    addToggleOption(ClickerFeature, "Wool only", clickSettings.woolOnly,
        function(value: boolean): ()
            clickSettings.woolOnly = value
            placeSettings.block = value and "wool_white" or placeSettings.block
        end)
    addToggleOption(ClickerFeature, "Pickaxe", clickSettings.pickaxe,
        function(value: boolean): ()
            clickSettings.pickaxe = value
        end)

    -- ----------------------------------------------------------------- place
    --
    -- `PlaceBlock` wants the block type, the placement position and a
    -- `mouseBlockInfo` table. The capture shows all three, with `blockData` at
    -- zero for every placement it recorded.
    PlaceFeature = createUniversalFeature(
        "Fast Place",
        "Places the selected block at the aimed position",
        2,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsPlace")
            if not enabled then
                if PlaceFeature then
                    PlaceFeature:SetStatus(nil)
                end
                return
            end
            PlaceFeature:SetStatus(placeSettings.block)
            local nextAt: number = 0
            host.featureConnections.BedWarsPlace =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    local view: Camera? = camera()
                    local own: Model?, humanoid: Humanoid?, root: BasePart? =
                        characterParts()
                    if not view or not own or not root or not humanoid
                        or (humanoid :: Humanoid).Health <= 0 then
                        return
                    end
                    local origin: Vector3 = (view :: Camera).CFrame.Position
                    local direction: Vector3 = (view :: Camera).CFrame.LookVector
                    local parameters: RaycastParams = RaycastParams.new()
                    parameters.FilterType = Enum.RaycastFilterType.Exclude
                    parameters.FilterDescendantsInstances = {own :: Model}
                    local hit: RaycastResult? =
                        workspace:Raycast(origin, direction * 20, parameters)
                    if not hit then
                        return
                    end
                    nextAt = now + 1 / math.max(placeSettings.rate, 0.5)
                    placeAt((hit :: RaycastResult).Position)
                end)
        end,
        {categoryName = "Blocks", registry = registry}
    )
    addNumberOption(PlaceFeature, "Blocks per second", placeSettings.rate, 1, 20,
        function(value: number): ()
            placeSettings.rate = value
        end)

    -- ------------------------------------------------------------------ nuke
    --
    -- Beds carry the CollectionService tag `'bed'`, and breaking one is
    -- `DamageBlock` with the block's own position. No bed container to find and
    -- no map to sweep: the tag is the index.
    local nukeSettings: any = {range = 20, rate = 6}

    NukeFeature = createUniversalFeature(
        "Nuker",
        "Breaks tagged beds inside range",
        3,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsNuke")
            if not enabled then
                if NukeFeature then
                    NukeFeature:SetStatus(nil)
                end
                return
            end
            NukeFeature:SetStatus("0 beds")
            local nextAt: number = 0
            host.featureConnections.BedWarsNuke =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    local _own: Model?, humanoid: Humanoid?, root: BasePart? =
                        characterParts()
                    if not root or not humanoid or (humanoid :: Humanoid).Health <= 0 then
                        return
                    end
                    local collectionService: any = game:GetService("CollectionService")
                    local origin: Vector3 = (root :: BasePart).Position
                    local nearest: BasePart? = nil
                    local nearestDistance: number = nukeSettings.range
                    local seen: number = 0
                    for _, tagged: Instance in ipairs(collectionService:GetTagged("bed")) do
                        if not tagged:IsA("BasePart") then
                            continue
                        end
                        seen += 1
                        local part: BasePart = tagged :: BasePart
                        local distance: number = (part.Position - origin).Magnitude
                        if distance < nearestDistance then
                            nearest = part
                            nearestDistance = distance
                        end
                    end
                    NukeFeature:SetStatus(tostring(seen) .. " beds")
                    if not nearest then
                        return
                    end
                    nextAt = now + 1 / math.max(nukeSettings.rate, 0.5)
                    local position: Vector3 = (nearest :: BasePart).Position
                    fire("DamageBlock", {
                        blockRef = {blockPosition = position},
                        hitPosition = position,
                        hitNormal = (origin - position).Unit,
                    })
                end)
        end,
        {categoryName = "Blocks", registry = registry}
    )
    addNumberOption(NukeFeature, "Range", nukeSettings.range, 5, 60,
        function(value: number): ()
            nukeSettings.range = value
        end)

    -- ------------------------------------------------------------------- esp
    --
    -- One card, two tags. Beds and desert pots are both blocks with a
    -- CollectionService tag, and the only difference worth a row is which of
    -- them is drawn.
    local espSettings: any = {beds = true, pots = true}
    local espMarks: {[Instance]: any} = {}

    local function clearEspMarks(): ()
        for instance: Instance, mark: any in pairs(espMarks) do
            pcall(function(): ()
                mark:Destroy()
            end)
            espMarks[instance] = nil
        end
    end

    local function markBlock(instance: Instance, label: string): ()
        if espMarks[instance] or not instance:IsA("BasePart") then
            return
        end
        local billboard: any = create("BillboardGui", {
            Name = "Wurst_BedWars_" .. label,
            Size = UDim2.fromOffset(72, 20),
            StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
            AlwaysOnTop = true,
            Adornee = instance,
            Parent = instance,
        })
        makeTextLabel(billboard, label, 14)
        espMarks[instance] = billboard
    end

    EspFeature = createUniversalFeature(
        "Objective ESP",
        "Marks tagged beds and desert pots through walls",
        4,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsEspAdded")
            host.disconnectFeatureConnection("BedWarsEspRemoved")
            clearEspMarks()
            if not enabled then
                if EspFeature then
                    EspFeature:SetStatus(nil)
                end
                return
            end
            local collectionService: any = game:GetService("CollectionService")

            local function add(instance: Instance): ()
                if espSettings.beds and collectionService:HasTag(instance, "bed") then
                    markBlock(instance, "Bed")
                elseif espSettings.pots and instance.Name == "desert_pot" then
                    markBlock(instance, "Pot")
                end
            end
            local function remove(instance: Instance): ()
                local mark: any = espMarks[instance]
                if mark then
                    pcall(function(): ()
                        mark:Destroy()
                    end)
                    espMarks[instance] = nil
                end
            end

            for _, instance: Instance in ipairs(collectionService:GetTagged("bed")) do
                add(instance)
            end
            for _, instance: Instance in ipairs(collectionService:GetTagged("block")) do
                add(instance)
            end
            host.featureConnections.BedWarsEspAdded =
                collectionService:GetInstanceAddedSignal("block"):Connect(add)
            host.featureConnections.BedWarsEspRemoved =
                collectionService:GetInstanceRemovedSignal("block"):Connect(remove)
            EspFeature:SetStatus("on")
        end,
        {categoryName = "Render", registry = registry}
    )
    addToggleOption(EspFeature, "Beds", espSettings.beds, function(value: boolean): ()
        espSettings.beds = value
    end)
    addToggleOption(EspFeature, "Desert pots", espSettings.pots, function(value: boolean): ()
        espSettings.pots = value
    end)

    -- -------------------------------------------------------------- economy
    --
    -- `SetObservedChest` takes no arguments at all, which is what makes chest
    -- stealing this cheap: the server opens whatever chest the client says it
    -- is looking at.
    ChestFeature = createUniversalFeature(
        "Chest Steal",
        "Opens nearby chests without walking to them",
        5,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsChest")
            if not enabled then
                if ChestFeature then
                    ChestFeature:SetStatus(nil)
                end
                return
            end
            ChestFeature:SetStatus("on")
            local nextAt: number = 0
            host.featureConnections.BedWarsChest =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 0.5
                    fire("Inventory/SetObservedChest")
                end)
        end,
        {categoryName = "Other", registry = registry}
    )

    -- `SetInvItem` moves an item into the hand. The capture shows it taking a
    -- table with a `hand` key holding the Accessory itself.
    AutoToolFeature = createUniversalFeature(
        "Auto Tool",
        "Puts the matching item in hand before you need it",
        6,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsAutoTool")
            if not enabled then
                if AutoToolFeature then
                    AutoToolFeature:SetStatus(nil)
                end
                return
            end
            AutoToolFeature:SetStatus("on")
            host.featureConnections.BedWarsAutoTool =
                TaskManager:Connect(function(): ()
                    local inventory: Instance? = game:GetService("ReplicatedStorage")
                    inventory = inventory
                        and inventory:FindFirstChild("Inventories") :: Instance?
                    inventory = inventory
                        and inventory:FindFirstChild(LocalPlayer.Name) :: Instance?
                    if not inventory then
                        return
                    end
                    local wanted: Instance? = nil
                    for _, child: Instance in ipairs((inventory :: Instance):GetChildren()) do
                        if child.Name:find("pickaxe") or child.Name:find("axe") then
                            wanted = child
                            break
                        end
                    end
                    if wanted then
                        fire("SetInvItem", {hand = wanted})
                    end
                end)
        end,
        {categoryName = "Other", registry = registry}
    )

    -- -------------------------------------------------------- inventory esp
    --
    -- Inventories are readable client-side under
    -- `ReplicatedStorage.Inventories.<player>`, one child per item. No remote,
    -- no hook, nothing written: this card only reads what the game already
    -- replicated and draws it. It shows whoever the camera is nearest to, which
    -- is the player a BedWars fight is actually about.
    local inventorySettings: any = {range = 60, maxRows = 12}
    local inventoryRuntime: any = {panel = nil, signature = ""}

    local function destroyInventoryPanel(): ()
        if inventoryRuntime.panel then
            pcall(function(): ()
                inventoryRuntime.panel:Destroy()
            end)
            inventoryRuntime.panel = nil
        end
        inventoryRuntime.signature = ""
    end

    -- The player the camera is closest to, inside the slider's range. Camera
    -- aim rather than character aim: this is a read-out, and you look at the
    -- player you are reading.
    local function aimedPlayer(): Player?
        local view: Camera? = camera()
        if not view then
            return nil
        end
        local origin: Vector3 = (view :: Camera).CFrame.Position
        local direction: Vector3 = (view :: Camera).CFrame.LookVector
        local best: Player? = nil
        local bestScore: number = inventorySettings.range
        for _, player: Player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then
                continue
            end
            local character: Model? = player.Character
            local humanoid: Humanoid? = character
                and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
            local part: BasePart? = character
                and character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not humanoid or not part or (humanoid :: Humanoid).Health <= 0 then
                continue
            end
            local offset: Vector3 = (part :: BasePart).Position - origin
            local distance: number = offset.Magnitude
            if distance > inventorySettings.range then
                continue
            end
            -- Off to the side is not "aimed at": reject anything more than
            -- about 30 degrees from where the camera points.
            if distance > 0.001 and offset.Unit:Dot(direction) < 0.86 then
                continue
            end
            if distance < bestScore then
                best = player
                bestScore = distance
            end
        end
        return best
    end

    local function inventoryOf(player: Player): Instance?
        local replicated: Instance? = game:GetService("ReplicatedStorage")
        local inventories: Instance? = replicated
            and replicated:FindFirstChild("Inventories") :: Instance?
        return inventories
            and inventories:FindFirstChild(player.Name) :: Instance?
    end

    local function renderInventory(player: Player, folder: Instance): ()
        local names: {string} = {}
        for _, item: Instance in ipairs(folder:GetChildren()) do
            table.insert(names, item.Name)
        end
        table.sort(names)
        local signature: string = player.Name .. "|" .. table.concat(names, ",")
        if signature == inventoryRuntime.signature and inventoryRuntime.panel then
            return
        end
        inventoryRuntime.signature = signature
        destroyInventoryPanel()

        local rows: number = math.min(#names, inventorySettings.maxRows)
        local root: Frame = create("Frame", {
            Parent = host.ScreenGui,
            Name = "Wurst_BedWarsInventory",
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor3 = Color3.fromRGB(14, 14, 16),
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -18, 0, 90),
            Size = UDim2.fromOffset(196, 34 + rows * 18),
            ZIndex = 60,
        }) :: Frame
        create("UICorner", {Parent = root, CornerRadius = UDim.new(0, 4)})
        makeTextLabel(root, player.Name, 14)
        for index: number = 1, rows do
            makeTextLabel(root, names[index], 14)
        end
        if #names > rows then
            makeTextLabel(root, "+" .. tostring(#names - rows) .. " more", 14)
        end
        inventoryRuntime.panel = root
    end

    InventoryFeature = createUniversalFeature(
        "Inventory ESP",
        "Reads the inventory of the player you are looking at",
        8,
        function(enabled: boolean): ()
            host.disconnectFeatureConnection("BedWarsInventory")
            destroyInventoryPanel()
            if not enabled then
                if InventoryFeature then
                    InventoryFeature:SetStatus(nil)
                end
                return
            end
            InventoryFeature:SetStatus("searching")
            local nextAt: number = 0
            host.featureConnections.BedWarsInventory =
                TaskManager:Connect(function(): ()
                    local now: number = os.clock()
                    if now < nextAt then
                        return
                    end
                    nextAt = now + 0.25
                    local player: Player? = aimedPlayer()
                    if not player then
                        destroyInventoryPanel()
                        InventoryFeature:SetStatus("searching")
                        return
                    end
                    local folder: Instance? = inventoryOf(player :: Player)
                    if not folder then
                        destroyInventoryPanel()
                        InventoryFeature:SetStatus("no data")
                        return
                    end
                    renderInventory(player :: Player, folder :: Instance)
                    InventoryFeature:SetStatus((player :: Player).Name)
                end)
        end,
        {categoryName = "Render", registry = registry}
    )
    addNumberOption(InventoryFeature, "Range", inventorySettings.range, 10, 200,
        function(value: number): ()
            inventorySettings.range = value
        end)

    runtimeState.cleanupPanels = function(): ()
        destroyInventoryPanel()
    end

    Module.Initialized = true
    return {
        aura = AuraFeature,
        clicker = ClickerFeature,
        place = PlaceFeature,
        nuke = NukeFeature,
        esp = EspFeature,
        chest = ChestFeature,
        autoTool = AutoToolFeature,
        inventory = InventoryFeature,
    }
end

function Module.destroy(): ()
    if type(runtimeState.disconnectAll) == "function" then
        pcall(runtimeState.disconnectAll)
    end
    runtimeState.disconnectAll = nil
    runtimeState.remoteCache = {}
    Module.Initialized = false
end

return Module
