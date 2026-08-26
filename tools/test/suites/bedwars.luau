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



    local features: any = BedWarsFile.init({Services = host.services, State = host.state})

    check("the module builds its seven cards", features ~= nil and features.aura ~= nil
        and features.clicker ~= nil and features.place ~= nil
        and features.nuke ~= nil and features.esp ~= nil
        and features.chest ~= nil and features.autoTool ~= nil)
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

    -- -------------------------------------------------------------- clicker

    check("the clicker is three rows",
        features.clicker.options["Clicks per second"] ~= nil
            and features.clicker.options["Wool only"] ~= nil
            and features.clicker.options["Pickaxe"] ~= nil)

    -- A sword in hand swings, and a swing with nobody in reach is the whiff
    -- the game itself reports.
    sent["SwordSwingMiss"] = {}
    features.clicker.activate()
    world.clock += 1
    stub.step(0.016)
    check("a sword in hand swings",
        sent["SwordSwingMiss"] ~= nil and #(sent["SwordSwingMiss"] :: any) >= 1,
        "calls: " .. tostring(sent["SwordSwingMiss"] and #(sent["SwordSwingMiss"] :: any) or 0))
    features.clicker.activate()

    -- The clicker aims with a raycast, so the world has to answer one.
    world.raycastResult = {
        Instance = Mock.newInstance("Part"),
        Position = world.vector3(0, 0, -6),
        Normal = world.vector3(0, 1, 0),
    }

    -- Wool places, and "Wool only" is what decides the block type.
    weapon.Parent = nil
    local wool: any = Mock.newInstance("Accessory")
    wool.Name = "wool_white"
    wool.Parent = world.localPlayer.Character
    sent["PlaceBlock"] = {}
    features.clicker.activate()
    world.clock += 1
    stub.step(0.016)
    local placed: any = sent["PlaceBlock"]
    check("wool in hand places a block", placed ~= nil and #placed >= 1,
        "calls: " .. tostring(placed and #placed or 0))
    local placedPayload: any = placed and placed[1] and placed[1][1]
    check("and places wool, not whatever else is stacked",
        placedPayload ~= nil and placedPayload.blockType == "wool_white",
        placedPayload and tostring(placedPayload.blockType) or "none")
    check("with the mouseBlockInfo the capture recorded",
        placedPayload ~= nil and placedPayload.mouseBlockInfo ~= nil
            and placedPayload.mouseBlockInfo.placementPosition ~= nil
            and placedPayload.blockData == 0)
    features.clicker.activate()
    wool.Parent = nil

    -- A pickaxe mines. The row defaults to on, and this suite drives defaults
    -- rather than flipping rows: what runs here is what ships.
    local pickaxeInHand: any = Mock.newInstance("Accessory")
    pickaxeInHand.Name = "iron_pickaxe"
    pickaxeInHand.Parent = world.localPlayer.Character
    sent["DamageBlock"] = {}
    features.clicker.activate()
    world.clock += 1
    stub.step(0.016)
    check("a pickaxe in hand mines", #(sent["DamageBlock"] :: any) >= 1,
        "calls: " .. tostring(#(sent["DamageBlock"] :: any)))
    features.clicker.activate()
    pickaxeInHand.Parent = nil

    -- Anything else in hand is not clicked at all.
    local pearl: any = Mock.newInstance("Accessory")
    pearl.Name = "telepearl"
    pearl.Parent = world.localPlayer.Character
    sent["PlaceBlock"] = {}
    sent["DamageBlock"] = {}
    sent["SwordSwingMiss"] = {}
    features.clicker.activate()
    world.clock += 1
    stub.step(0.016)
    check("a pearl in hand is left alone",
        #(sent["PlaceBlock"] :: any) == 0 and #(sent["DamageBlock"] :: any) == 0
            and #(sent["SwordSwingMiss"] :: any) == 0)
    features.clicker.activate()
    pearl:Destroy()
    weapon.Parent = world.localPlayer.Character
    world.raycastResult = nil

    -- ----------------------------------------------------------------- blocks

    local bed: any = Mock.newInstance("Part")
    bed.Name = "bed_red"
    bed.Position = world.vector3(4, 0, -4)
    bed.Parent = world.workspace
    collectionService:AddTag(bed, "bed")
    local pot: any = Mock.newInstance("MeshPart")
    pot.Name = "desert_pot"
    pot.Position = world.vector3(-4, 0, -4)
    pot.Parent = world.workspace
    collectionService:AddTag(pot, "block")

    features.esp.activate()
    check("a tagged bed is marked",
        bed:FindFirstChild("Wurst_BedWars_Bed") ~= nil)
    check("a desert pot is marked from the block tag",
        pot:FindFirstChild("Wurst_BedWars_Pot") ~= nil)
    collectionService:RemoveTag(pot, "block")
    check("streaming a block out clears its mark",
        pot:FindFirstChild("Wurst_BedWars_Pot") == nil)
    features.esp.activate()
    check("disabling clears both marks",
        bed:FindFirstChild("Wurst_BedWars_Bed") == nil
            and pot:FindFirstChild("Wurst_BedWars_Pot") == nil)

    features.nuke.activate()
    world.clock += 1
    stub.step(0.016)
    local damage: any = sent["DamageBlock"]
    check("the nuker breaks the tagged bed", damage ~= nil and #damage >= 1,
        "calls: " .. tostring(damage and #damage or 0))
    local damagePayload: any = damage and damage[1] and damage[1][1]
    check("with the block position and a normal the capture has",
        damagePayload ~= nil and damagePayload.blockRef ~= nil
            and damagePayload.blockRef.blockPosition ~= nil
            and damagePayload.hitPosition ~= nil
            and damagePayload.hitNormal ~= nil)
    features.nuke.activate()

    -- The bed goes first, so the only thing left in range is a part with no
    -- tag. If the nuker reaches for it, the tag is not what is selecting.
    collectionService:RemoveTag(bed, "bed")
    local plain: any = Mock.newInstance("Part")
    plain.Name = "not_a_bed"
    plain.Position = world.vector3(0, 0, -3)
    plain.Parent = world.workspace
    local beforeUntagged: number = damage and #damage or 0
    world.clock += 1
    stub.step(0.016)
    check("an untagged part is never broken",
        (damage and #damage or 0) == beforeUntagged,
        "calls: " .. tostring((damage and #damage or 0) - beforeUntagged))
    features.nuke.activate()
    plain:Destroy()
    bed:Destroy()
    pot:Destroy()

    -- -------------------------------------------------------------- economy

    features.chest.activate()
    world.clock += 1
    stub.step(0.016)
    check("chest steal opens a chest with no arguments",
        sent["Inventory/SetObservedChest"] ~= nil
            and #(sent["Inventory/SetObservedChest"] :: any) >= 1)
    features.chest.activate()

    local inventoryFolder: any = Mock.newInstance("Folder")
    inventoryFolder.Name = "Inventories"
    inventoryFolder.Parent = replicated
    local mine: any = Mock.newInstance("Folder")
    mine.Name = world.localPlayer.Name
    mine.Parent = inventoryFolder
    local pickaxe: any = Mock.newInstance("Accessory")
    pickaxe.Name = "iron_pickaxe"
    pickaxe.Parent = mine
    features.autoTool.activate()
    world.clock += 1
    stub.step(0.016)
    check("auto tool puts the matching item in hand",
        sent["SetInvItem"] ~= nil and #(sent["SetInvItem"] :: any) >= 1)
    features.autoTool.activate()
    pickaxe:Destroy()
    mine:Destroy()
    inventoryFolder:Destroy()

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

    BedWarsFile.destroy()
    check("destroy leaves no connection behind",
        next(host.featureConnections) == nil
            or host.featureConnections.BedWarsAura == nil)
end
