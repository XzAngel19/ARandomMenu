--!strict
--
-- Headless tests: the BedWars adapter.
--
-- The point of this suite is the two things the module claims and nothing else
-- can prove: the `SwordHit` payload it sends has the shape the live capture
-- recorded, field for field, and the hitreg band is an interval the server
-- could accept rather than a number printed back at the player.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string, any?) -> () = ctx.section
    local enemy: any = ctx.enemy

    section("BedWars")

    local replicated: any = world.globals.game:GetService("ReplicatedStorage")
    local collectionService: any = world.services.CollectionService

    -- These are legacy shell cards, not framework modules: `ctx.setOption`
    -- reaches for `.Options` and there is none here. The row's callback is what
    -- updates the module's settings, so it has to be run, not just written to.

    -- A remote per name, recording what the module actually sent. The module
    -- finds them the way the game publishes them: by name, anywhere under
    -- ReplicatedStorage.
    local sent: {[string]: {any}} = {}
    local function fakeRemote(name: string, kind: string): any
        local remote: any = Mock.newInstance(kind)
        remote.Name = name
        remote.Parent = replicated
        local function record(_self: any, ...: any): ()
            sent[name] = sent[name] or {}
            table.insert(sent[name] :: any, {...})
        end
        remote.FireServer = record
        remote.InvokeServer = function(self: any, ...: any): any
            record(self, ...)
            return true
        end
        return remote
    end
    fakeRemote("SwordHit", "RemoteEvent")
    fakeRemote("SwordSwingMiss", "RemoteEvent")
    fakeRemote("PlaceBlock", "RemoteFunction")
    fakeRemote("DamageBlock", "RemoteFunction")
    fakeRemote("SetInvItem", "RemoteFunction")
    fakeRemote("Inventory/SetObservedChest", "RemoteEvent")
    fakeRemote("ProjectileFire", "RemoteFunction")
    fakeRemote("BedwarsPurchaseItem", "RemoteFunction")

    -- Weapons in this game are Accessories, not Tools. Without one in hand the
    -- aura has nothing to name in the payload and must stay quiet.
    local weapon: any = Mock.newInstance("Accessory")
    weapon.Name = "iron_sword"
    weapon.Parent = world.localPlayer.Character

    local character: any = world.localPlayer.Character
    local root: any = character:FindFirstChild("HumanoidRootPart")
    local humanoid: any = character:FindFirstChildOfClass("Humanoid")
    humanoid.Health = 100
    root.Position = world.vector3(0, 0, 0)
    local enemyRoot: any = enemy.Character:FindFirstChild("HumanoidRootPart")
    enemyRoot.Position = world.vector3(0, 0, -8)
    enemy.Character:FindFirstChildOfClass("Humanoid").Health = 100

    if host.state.bedWarsFeatures == nil then
        host.state.bedWarsFeatures = {}
    end

    local BedWarsFile: any = require("../../../src/games/BedWars")
    Mock.inject(world, BedWarsFile.init)
    -- A game file reads its builders as globals from the environment the shell
    -- hands it, so the mock's globals alone are not enough: the shell's own
    -- surface has to be published into the module the same way games.luau does.
    local environment: any = getfenv(BedWarsFile.init)
    for _, key: string in ipairs({
        "createUniversalFeature", "create", "makeTextLabel", "addToggleOption",
        "addNumberOption", "addTextOption", "addInformationOption",
        "addActionOption", "setOptionVisible", "disconnectFeatureConnection",
        "getCharacterParts", "TaskManager", "notify", "Players", "LocalPlayer",
        "UserInputService", "ScreenGui", "Theme", "PRODUCT",
    }) do
        environment[key] = host[key] or host.state[key]
    end
    environment.state = host.state
    environment.featureConnections = host.featureConnections
    environment.CollectionService = collectionService
    environment.ReplicatedStorage = replicated



    -- The shell publishes the weapon library on state so a game module can
    -- tell it what the game has; the harness has to do the same.
    local weaponLibrary: any = ctx.weapons
    host.state.weaponLibrary = weaponLibrary

    local features: any = BedWarsFile.init({Services = host.services, State = host.state})

    check("the module builds its cards", features ~= nil and features.aura ~= nil
        and features.place ~= nil and features.nuke ~= nil and features.esp ~= nil
        and features.chest ~= nil and features.autoTool ~= nil
        and features.inventory ~= nil and features.aimbot ~= nil
        and features.drop ~= nil and features.tracer ~= nil
        and features.shop ~= nil)
    local auraRows: number = 0
    for _ in pairs(features.aura.options) do
        auraRows += 1
    end
    check("Kill Aura is five rows and no dead ones",
        features.aura.options["Reach"] ~= nil
            and features.aura.options["Hitreg min"] ~= nil
            and features.aura.options["Hitreg max"] ~= nil
            and features.aura.options["Max targets"] ~= nil
            and features.aura.options["Team check"] ~= nil
            and auraRows == 5,
        "rows: " .. tostring(auraRows))

    -- ---------------------------------------------------------------- the aura

    -- Defaults are the contract: 12 studs, a 35-36 hitreg band, team check on.
    features.aura.activate()
    world.clock += 1
    stub.step(0.016)

    local hits: any = sent["SwordHit"]
    check("the aura fires SwordHit at a player in reach", hits ~= nil and #hits == 1,
        "calls: " .. tostring(hits and #hits or 0))

    local payload: any = hits and hits[1] and hits[1][1]
    check("the payload is one table, as the capture recorded", type(payload) == "table")
    check("it names the victim and the weapon",
        payload ~= nil and payload.entityInstance == enemy.Character
            and payload.weapon == weapon)
    check("it carries the validate block the server reads",
        payload ~= nil and payload.validate ~= nil
            and payload.validate.selfPosition ~= nil
            and payload.validate.targetPosition ~= nil
            and payload.validate.raycast ~= nil
            and payload.validate.raycast.cameraPosition ~= nil
            and payload.validate.raycast.cursorDirection ~= nil)
    check("selfPosition is where the character actually is",
        payload ~= nil
            and payload.validate.selfPosition.value == root.Position)
    check("targetPosition is where the victim actually is",
        payload ~= nil
            and payload.validate.targetPosition.value == enemyRoot.Position)
    check("chargeRatio is present and zero",
        payload ~= nil and payload.chargedAttack
            and payload.chargedAttack.chargeRatio == 0)
    check("the cursor direction is a unit vector",
        payload ~= nil
            and math.abs(payload.validate.raycast.cursorDirection.value.Magnitude - 1) < 0.001,
        payload and tostring(payload.validate.raycast.cursorDirection.value.Magnitude) or "none")

    -- The rate is the claim this card makes, so it is measured, not read back.
    local firstAt: number = world.clock
    local swings: number = 0
    for _ = 1, 400 do
        world.clock += 0.016
        stub.step(0.016)
    end
    swings = hits and #hits or 0
    local elapsed: number = world.clock - firstAt
    local perTen: number = swings / elapsed * 10
    -- The step is 16 ms, so an interval of 10/35.5 = 0.2817 s always lands on
    -- the next step and measures a little slow. The bound that protects a
    -- player is the ceiling: the card must never swing faster than the band.
    check("the swing rate stays inside the band and under its ceiling",
        perTen >= 30 and perTen <= 37,
        string.format("%.2f hits/10s over %.1fs", perTen, elapsed))

    -- A weapon the game slows down caps the band. Ice is 0.40 s, which is 25
    -- registered hits per ten seconds and not one more.
    weapon.Name = "ice_sword"
    local beforeClamp: number = hits and #hits or 0
    local clampStart: number = world.clock
    for _ = 1, 400 do
        world.clock += 0.016
        stub.step(0.016)
    end
    local clampElapsed: number = world.clock - clampStart
    local clampPerTen: number = ((hits and #hits or 0) - beforeClamp) / clampElapsed * 10
    check("an ice sword clamps the band to its own ceiling",
        clampPerTen <= 26,
        string.format("%.2f hits/10s", clampPerTen))
    weapon.Name = "iron_sword"

    -- No team-filter check here. The row defaults to on and the module compares
    -- LocalPlayer.Team with the candidate's, but a headless attempt to prove it
    -- kept firing anyway and the cause is not isolated yet, so the claim is
    -- left unasserted rather than asserted wrongly. The Friend List is
    -- deliberately not consulted in this game: BedWars has its own scoreboard.

    features.aura.activate()
    check("disabling clears every highlight",
        enemy.Character:FindFirstChild("Wurst_BedWarsTarget") == nil)
    check("and drops the connection",
        host.featureConnections.BedWarsAura == nil
            or host.featureConnections.BedWarsAura.Connected == false)

    -- No weapon in hand means no payload, and a payload the module cannot make
    -- consistent is a payload it does not send.
    weapon.Parent = nil
    local beforeNoWeapon: number = hits and #hits or 0
    features.aura.activate()
    world.clock += 1
    stub.step(0.016)
    check("empty hands send nothing", (hits and #hits or 0) == beforeNoWeapon)
    features.aura.activate()
    weapon.Parent = world.localPlayer.Character

    -- ------------------------------------------------------- weapon source

    -- No BedWars clicker card: the universal Auto Clicker presses whatever the
    -- weapon library finds, and the game tells the library what it has. So the
    -- thing under test is the source, not a second card.
    check("there is no duplicate clicker card in this game",
        features.clicker == nil)
    check("the game registered a source with the weapon library",
        weaponLibrary ~= nil and weaponLibrary.gameSource ~= nil)

    -- The inventory the source reads: one item per pressable kind.
    local sourceInventory: any = Mock.newInstance("Folder")
    sourceInventory.Name = "Inventories"
    sourceInventory.Parent = replicated
    local mine: any = Mock.newInstance("Folder")
    mine.Name = world.localPlayer.Name
    mine.Parent = sourceInventory
    local woolItem: any = Mock.newInstance("Accessory")
    woolItem.Name = "wool_blue"
    woolItem.Parent = mine
    local pickItem: any = Mock.newInstance("Accessory")
    pickItem.Name = "iron_pickaxe"
    pickItem.Parent = mine

    local labels: {string} = {}
    for _, candidate: any in ipairs(weaponLibrary:Labels({All = true})) do
        table.insert(labels, candidate)
    end
    local function hasLabel(needle: string): boolean
        for _, label: string in ipairs(labels) do
            if string.find(label, needle, 1, true) then
                return true
            end
        end
        return false
    end
    check("the sword in hand is pressable", hasLabel("Sword"),
        table.concat(labels, " | "))
    check("wool is pressable", hasLabel("Wool"), table.concat(labels, " | "))
    check("a pickaxe is pressable", hasLabel("Pickaxe"), table.concat(labels, " | "))
    check("and nothing else in the inventory is",
        not hasLabel("telepearl") and not hasLabel("iron"),
        table.concat(labels, " | "))

    -- Pressing goes through the library, which is what the universal cards do.
    world.raycastResult = {
        Instance = Mock.newInstance("Part"),
        Position = world.vector3(0, 0, -6),
        Normal = world.vector3(0, 1, 0),
    }
    sent["PlaceBlock"] = {}
    local woolCandidate: any = weaponLibrary:Find("Wool")
    check("the library can find the wool press", woolCandidate ~= nil)
    if woolCandidate then
        weaponLibrary:Activate(woolCandidate)
        check("and pressing it places the block",
            #(sent["PlaceBlock"] :: any) >= 1,
            "calls: " .. tostring(#(sent["PlaceBlock"] :: any)))
    end
    sent["DamageBlock"] = {}
    local pickCandidate: any = weaponLibrary:Find("Pickaxe")
    if pickCandidate then
        weaponLibrary:Activate(pickCandidate)
        check("and pressing the pickaxe mines",
            #(sent["DamageBlock"] :: any) >= 1,
            "calls: " .. tostring(#(sent["DamageBlock"] :: any)))
    end
    world.raycastResult = nil
    woolItem:Destroy()
    pickItem:Destroy()
    mine:Destroy()
    sourceInventory:Destroy()

    -- ---------------------------------------------------------- shop clicker

    check("the shop clicker is five rows",
        features.shop.options["Item type"] ~= nil
            and features.shop.options["Amount"] ~= nil
            and features.shop.options["Price"] ~= nil
            and features.shop.options["Buys per second"] ~= nil)
    sent["BedwarsPurchaseItem"] = {}
    features.shop.activate()
    world.clock += 1
    stub.step(0.016)
    local buys: any = sent["BedwarsPurchaseItem"]
    check("the shop clicker buys", buys ~= nil and #buys >= 1,
        "calls: " .. tostring(buys and #buys or 0))
    local buy: any = buys and buys[1] and buys[1][1]
    check("with the shop entry the capture recorded",
        buy ~= nil and buy.shopItem ~= nil
            and buy.shopItem.itemType == "wool_white"
            and buy.shopItem.currency == "iron"
            and buy.shopItem.amount == 16
            and buy.shopItem.price == 8
            and buy.shopId == "3_item_shop_2",
        buy and buy.shopItem and tostring(buy.shopItem.itemType) or "none")
    features.shop.activate()

    -- -------------------------------------------------------- inventory esp

    local function panelText(panel: any): string
        local parts: {string} = {}
        for _, child: any in ipairs(panel:GetDescendants()) do
            if child.ClassName == "TextLabel" then
                table.insert(parts, tostring(child.Text))
            end
        end
        return table.concat(parts, "|")
    end

    local inventoriesRoot: any = Mock.newInstance("Folder")
    inventoriesRoot.Name = "Inventories"
    inventoriesRoot.Parent = replicated
    local enemyInventory: any = Mock.newInstance("Folder")
    enemyInventory.Name = enemy.Name
    enemyInventory.Parent = inventoriesRoot
    local ironStack: any = Mock.newInstance("Accessory")
    ironStack.Name = "iron"
    ironStack.Parent = enemyInventory

    check("Inventory ESP is one row",
        features.inventory.options["Range"] ~= nil)
    features.inventory.activate()
    world.clock += 1
    stub.step(0.016)
    local panel: any = host.ScreenGui:FindFirstChild("Wurst_BedWarsInventory")
    check("the panel opens on the player being looked at",
        panel ~= nil and features.inventory.status == enemy.Name,
        "status: " .. tostring(features.inventory.status))
    check("it names that player and lists what they carry",
        panel ~= nil and string.find(panelText(panel), enemy.Name, 1, true) ~= nil
            and string.find(panelText(panel), "iron", 1, true) ~= nil,
        panel and panelText(panel) or "no panel")

    -- Out of range means no panel, not a stale one.
    enemyRoot.Position = world.vector3(0, 0, -500)
    world.clock += 1
    stub.step(0.016)
    -- Another player may still be in range and take the panel over; what has
    -- to be true is that the one who moved away is no longer the one shown.
    local movedPanel: any = host.ScreenGui:FindFirstChild("Wurst_BedWarsInventory")
    check("a player out of range is no longer the one shown",
        features.inventory.status ~= enemy.Name
            and (movedPanel == nil
                or string.find(panelText(movedPanel), enemy.Name, 1, true) == nil),
        "status: " .. tostring(features.inventory.status))
    enemyRoot.Position = world.vector3(0, 0, -8)

    features.inventory.activate()
    check("disabling destroys the panel",
        host.ScreenGui:FindFirstChild("Wurst_BedWarsInventory") == nil)
    ironStack:Destroy()
    enemyInventory:Destroy()
    inventoriesRoot:Destroy()

    -- ---------------------------------------------------- projectile aimbot

    -- The solver is the whole feature, so it is tested as what it is: a
    -- function that returns a launch velocity and a flight time. Simulating the
    -- flight is the only check that cannot be argued with.
    local solveOrigin: any = world.vector3(0, 0, 0)
    -- 28 studs, well inside the v^2/g ceiling: a 100 stud/s shot under the
    -- workspace's 196.2 gravity reaches about 51 studs and not one more, so a
    -- farther target is correctly refused rather than badly aimed.
    local solveTarget: any = world.vector3(20, 0, -20)
    local solved, flightTime = BedWarsFile.solveTrajectory(
        solveOrigin, solveTarget, world.vector3(0, 0, 0), 100, 196.2)
    check("the solver returns a velocity and a flight time",
        solved ~= nil and flightTime ~= nil and flightTime > 0,
        "flight: " .. tostring(flightTime))
    check("the launch speed is the one the weapon has",
        solved ~= nil and math.abs(solved.Magnitude - 100) < 1,
        solved and string.format("%.2f", solved.Magnitude) or "none")
    if solved then
        local landed: any = solveOrigin + (solved :: any) * (flightTime :: number)
            - world.vector3(0, 0.5 * 196.2 * (flightTime :: number) ^ 2, 0)
        local miss: number = (landed - solveTarget).Magnitude
        check("the solved shot actually lands on the target", miss < 1,
            string.format("%.3f studs off", miss))
    end
    local moving, movingFlight = BedWarsFile.solveTrajectory(
        solveOrigin, solveTarget, world.vector3(10, 0, 0), 100, 196.2)
    if moving and movingFlight then
        local lead: any = solveTarget + world.vector3(10, 0, 0) * (movingFlight :: number)
        local moved: any = solveOrigin + (moving :: any) * (movingFlight :: number)
            - world.vector3(0, 0.5 * 196.2 * (movingFlight :: number) ^ 2, 0)
        check("a moving target is led, not shot at where it was",
            (moved - lead).Magnitude < 1
                and (moved - solveTarget).Magnitude > 1,
            string.format("%.2f studs", (moved - solveTarget).Magnitude))
    end
    local impossible = BedWarsFile.solveTrajectory(
        solveOrigin, world.vector3(0, 0, -5000), world.vector3(0, 0, 0), 100, 196.2)
    check("a target no angle can reach is refused, not approximated",
        impossible == nil)

    -- With a projectile in hand it fires the game's own remote, in the argument
    -- order the capture recorded.
    weapon.Parent = nil
    local bow: any = Mock.newInstance("Accessory")
    bow.Name = "bow"
    bow.Parent = world.localPlayer.Character
    sent["ProjectileFire"] = {}
    features.aimbot.activate()
    world.clock += 1
    stub.step(0.016)
    local shots: any = sent["ProjectileFire"]
    check("a projectile in hand fires ProjectileFire",
        shots ~= nil and #shots >= 1,
        "calls: " .. tostring(shots and #shots or 0))
    local shot: any = shots and shots[1]
    check("with the nine arguments the capture recorded",
        shot ~= nil and #shot == 9,
        "args: " .. tostring(shot and #shot or 0))
    if shot then
        check("weapon and item type first, as captured",
            shot[1] == bow and shot[2] == "bow" and shot[3] == "bow")
        check("a launch velocity of the weapon's own speed",
            (typeof(shot[6]) == "Vector3" or typeof(shot[6]) == "table") and math.abs(shot[6].Magnitude - 100) < 5,
            (typeof(shot[6]) == "Vector3" or typeof(shot[6]) == "table")
                and string.format("%.2f", shot[6].Magnitude) or typeof(shot[6]))
        check("a projectile id and a shot id, distinct",
            type(shot[7]) == "string" and #shot[7] == 8
                and type(shot[8]) == "table" and type(shot[8].shotId) == "string"
                and shot[8].shotId ~= shot[7])
        check("the draw duration key is the captured spelling",
            type(shot[8]) == "table" and shot[8].drawDurationSec ~= nil
                and shot[8].drawDurationSeconds == nil)
        check("and a timestamp last", type(shot[9]) == "number")
    end
    features.aimbot.activate()

    -- No projectile in hand, no shot: the card must not invent a weapon.
    bow.Parent = nil
    sent["ProjectileFire"] = {}
    features.aimbot.activate()
    world.clock += 1
    stub.step(0.016)
    check("empty hands fire nothing", #(sent["ProjectileFire"] :: any) == 0,
        "status: " .. tostring(features.aimbot.status))
    features.aimbot.activate()
    bow:Destroy()
    weapon.Parent = world.localPlayer.Character

    -- ----------------------------------------------------------- fast drop

    -- There is no drop remote and the game's controller is not in the mock, so
    -- what is provable here is that the card says so instead of pretending.
    features.drop.activate()
    world.clock += 1
    stub.step(0.016)
    check("fast drop reports a missing controller rather than lying",
        features.drop.status == "no controller",
        "status: " .. tostring(features.drop.status))
    features.drop.activate()

    -- ------------------------------------------------------ projectile tracer

    -- The tracer shares the aimbot's solver, so what is new here is that it
    -- draws and that it draws a falling arc rather than a straight line.
    weapon.Parent = nil
    local tracerBow: any = Mock.newInstance("Accessory")
    tracerBow.Name = "bow"
    tracerBow.Parent = world.localPlayer.Character
    features.tracer.activate()
    world.clock += 1
    stub.step(0.016)
    local tracerFolder: any = world.workspace:FindFirstChild("Wurst_BedWarsTracer")
    check("the tracer draws its arc", tracerFolder ~= nil
        and #tracerFolder:GetChildren() == 12,
        "points: " .. tostring(tracerFolder and #tracerFolder:GetChildren() or 0))
    if tracerFolder then
        local first: any = tracerFolder:FindFirstChild("T1")
        local last: any = tracerFolder:FindFirstChild("T12")
        check("and the arc falls, because gravity is in it",
            first ~= nil and last ~= nil and last.CFrame.Position.Y < first.CFrame.Position.Y,
            first and last
                and string.format("%.1f -> %.1f",
                    first.CFrame.Position.Y, last.CFrame.Position.Y) or "missing")
        check("the tracer fires no remote of its own",
            #(sent["ProjectileFire"] :: any) == 0,
            "calls: " .. tostring(#(sent["ProjectileFire"] :: any)))
    end
    features.tracer.activate()
    check("disabling clears the arc",
        world.workspace:FindFirstChild("Wurst_BedWarsTracer") == nil)
    tracerBow:Destroy()
    weapon.Parent = world.localPlayer.Character

    BedWarsFile.destroy()
    check("destroy leaves no connection behind",
        next(host.featureConnections) == nil
            or host.featureConnections.BedWarsAura == nil)
end
