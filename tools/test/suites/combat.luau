--!strict
--
-- Headless tests: combat.
--
-- Loaded by tools/test/run.luau. Suites share one world through the context
-- so the checks stay under Luau's 200-local ceiling without wrapping
-- sections in do-end.
--
return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local espContext: any = ctx.espContext
    local enemy: any = ctx.enemy
    local ally: any = ctx.ally
    local weapons: any = ctx.weapons

    section("TriggerBot")

    local TriggerFile: any = require("../../../src/modules/Combat/TriggerBot")
    Mock.inject(world, TriggerFile.init)
    local trigger: any = TriggerFile.init(espContext)

    check("card is registered", trigger ~= nil and trigger.Name == "TriggerBot")
    check("activation option exists", trigger.Options["Activation"] ~= nil)
    check("reaction option exists", trigger.Options["Reaction"] ~= nil)
    check("target part option exists", trigger.Options["Target part"] ~= nil)
    check("wall check exists", trigger.Options["Wall check"] ~= nil)

    local tool: any = Mock.newInstance("Tool")
    tool.Name = "Rifle"
    tool.Parent = world.localPlayer.Character

    world.aimRay = {
        Origin = world.vector3(0, 0, 0),
        Direction = world.vector3(0, 0, -1),
    }
    world.raycastResult = {
        Instance = enemy.Character:FindFirstChild("Head"),
        Position = world.vector3(0, 0, -30),
    }
    trigger.Options["Reaction"].Value = 0.1
    trigger.Options["Aim tolerance"].Value = 0
    trigger.Options["Team check"].Value = true

    trigger:Toggle()
    check("trigger enables", trigger.Enabled == true)

    stub.step(0.016)
    check("nothing fires before the delay elapses", (tool.Activations or 0) == 0)

    world.clock += 0.2
    stub.step(0.016)
    check("fires once the delay elapses", (tool.Activations or 0) == 1,
        "activations: " .. tostring(tool.Activations))

    world.clock += 0.5
    stub.step(0.016)
    check("single mode does not re-fire on the same acquisition",
        (tool.Activations or 0) == 1,
        "activations: " .. tostring(tool.Activations))

    -- Head-only filtering: a torso hit must be rejected.
    world.raycastResult = {
        Instance = enemy.Character:FindFirstChild("UpperTorso"),
        Position = world.vector3(0, 0, -30),
    }
    trigger.Options["Target part"].Value = "Head"
    world.clock += 1
    stub.step(0.016)
    world.clock += 1
    stub.step(0.016)
    check("head filter rejects a torso hit", (tool.Activations or 0) == 1,
        "activations: " .. tostring(tool.Activations))

    -- Team check: an ally under the crosshair must never trigger.
    trigger.Options["Target part"].Value = "Any"
    world.raycastResult = {
        Instance = ally.Character:FindFirstChild("Head"),
        Position = world.vector3(10, 0, -10),
    }
    world.clock += 1
    stub.step(0.016)
    world.clock += 1
    stub.step(0.016)
    check("team check rejects an ally", (tool.Activations or 0) == 1,
        "activations: " .. tostring(tool.Activations))

    trigger:Toggle()
    check("trigger disables", trigger.Enabled == false)
    world.raycastResult = {
        Instance = enemy.Character:FindFirstChild("Head"),
        Position = world.vector3(0, 0, -30),
    }
    world.clock += 1
    stub.step(0.016)
    check("nothing fires while disabled", (tool.Activations or 0) == 1,
        "activations: " .. tostring(tool.Activations))

    -- Wall-clock, not the mocked os.clock. Raise only with a comment saying
    -- what got more expensive.
    local BUDGET_TRIGGER_FRAME_SECONDS: number = 0.010
    trigger:Toggle()
    local triggerPerFrame: number = ctx.measureFrames(stub.step, 20)
    trigger:Toggle()
    check(
        "TriggerBot stays inside the per-frame time budget",
        triggerPerFrame <= BUDGET_TRIGGER_FRAME_SECONDS,
        string.format("%.4fs/frame", triggerPerFrame)
    )

    -- Friend list ----------------------------------------------------------------

    section("Friend list")

    local FriendFile: any = require("../../../src/modules/Utility/FriendList")
    Mock.inject(world, FriendFile.init)
    local friendList: any = FriendFile.init(espContext)

    check("card is always-on", friendList.Feature.kind == "group")
    check("list is published on state", host.state.friendList ~= nil)
    check("the local player is always protected",
        host.state.friendList.isProtected(world.localPlayer) == true)
    check("an unlisted player is not protected",
        host.state.friendList.isProtected(enemy) == false)

    friendList.Options["Protected names"].Value = "Enemy"
    host.state.friendList.names = {enemy = true}
    check("a listed player is protected",
        host.state.friendList.isProtected(enemy) == true)
    host.state.friendList.names = {}

    -- Kill Aura ------------------------------------------------------------------

    section("Killaura")

    local AuraFile: any = require("../../../src/modules/Combat/KillAura")
    Mock.inject(world, AuraFile.init)
    local aura: any = AuraFile.init(espContext)

    check("card is registered", aura ~= nil and aura.Name == "Killaura")
    for _, name: string in ipairs({
        "Swing range",
        "Max targets",
        "Mode",
        "Priority",
        "Swings per second",
        "Attack range",
        "Field of view",
        "Rotation",
        "Contact damage",
        "Wall check",
        "Team check",
        "Highlight targets",
    }) do
        check("option: " .. name, aura.Options[name] ~= nil)
    end
    check("the jitter row is gone, the jitter is not",
        aura.Options["Rate jitter"] == nil)
    check("one highlight colour replaced the pair",
        aura.Options["Highlight colour"] ~= nil
            and aura.Options["Attack colour"] == nil
            and aura.Options["Reach colour"] == nil)
    check("advanced rows start hidden",
        aura.Options["Rotation"].Object ~= nil
            and aura.Options["Rotation"].Object.Parent.Visible == false)

    -- The enemy sits 30 studs away; bring them into reach.
    enemy.Character:FindFirstChild("HumanoidRootPart").Position = world.vector3(0, 0, -8)
    world.raycastResult = nil
    -- The TriggerBot test left a rifle equipped; the melee tests need the sword to
    -- be the first tool the character finds.
    tool:Destroy()
    local swordHandle: any = Mock.newInstance("Part")
    swordHandle.Name = "Handle"
    local sword: any = Mock.newInstance("Tool")
    sword.Name = "Sword"
    swordHandle.Parent = sword
    sword.Parent = world.localPlayer.Character

    aura.Options["Swings per second"].Value = 20
    aura.Options["Field of view"].Value = 360
    -- Nothing is enabled at startup any more, so the checks under test are turned
    -- on explicitly here.
    aura.Options["Highlight targets"].Value = true
    aura.Options["Team check"].Value = true
    world.touchFires = 0

    aura:Toggle()
    check("aura enables", aura.Enabled == true)
    world.clock += 1
    stub.step(0.016)
    check("swings at a target in range", (sword.Activations or 0) >= 1,
        "activations: " .. tostring(sword.Activations))
    check("fires contact damage", world.touchFires > 0,
        "touches: " .. tostring(world.touchFires))
    check("highlights the target",
        enemy.Character:FindFirstChild("RTM_KillAuraTarget") ~= nil)
    check("the HUD status counts targets in range",
        aura.Status == "1 in range", tostring(aura.Status))

    -- Rate limit: a second step in the same instant must not swing again.
    local beforeRate: number = sword.Activations or 0
    stub.step(0.016)
    check("respects the swing rate", (sword.Activations or 0) == beforeRate,
        "activations: " .. tostring(sword.Activations))

    -- Friend protection has to win over an in-range target.
    host.state.friendList.names = {enemy = true}
    world.clock += 1
    local beforeFriend: number = sword.Activations or 0
    stub.step(0.016)
    check("never swings at a protected player",
        (sword.Activations or 0) == beforeFriend,
        "activations: " .. tostring(sword.Activations))
    check("clears the highlight of a protected player",
        enemy.Character:FindFirstChild("RTM_KillAuraTarget") == nil)
    check("the HUD count drops when no target remains",
        aura.Status == "0 in range", tostring(aura.Status))
    host.state.friendList.names = {}

    -- Out of range is out of range.
    enemy.Character:FindFirstChild("HumanoidRootPart").Position = world.vector3(0, 0, -400)
    world.clock += 1
    local beforeRange: number = sword.Activations or 0
    stub.step(0.016)
    check("ignores targets beyond the swing range",
        (sword.Activations or 0) == beforeRange)

    aura:Toggle()
    check("aura disables", aura.Enabled == false)

    -- Wall-clock, not the mocked os.clock. Raise only with a comment saying
    -- what got more expensive.
    local BUDGET_AURA_FRAME_SECONDS: number = 0.010
    enemy.Character:FindFirstChild("HumanoidRootPart").Position = world.vector3(0, 0, -8)
    aura:Toggle()
    local auraPerFrame: number = ctx.measureFrames(stub.step, 20)
    aura:Toggle()
    check(
        "Kill Aura stays inside the per-frame time budget",
        auraPerFrame <= BUDGET_AURA_FRAME_SECONDS,
        string.format("%.4fs/frame", auraPerFrame)
    )

    -- Kill Aura weapon detection --------------------------------------------------

    section("Kill Aura weapon detection")

    -- A game that hands you two tools and calls the sword something unexpected is
    -- the case the old FindFirstChildOfClass could not survive.
    local shield: any = Mock.newInstance("Tool")
    shield.Name = "WoodenShield"
    local shieldHandle: any = Mock.newInstance("Part")
    shieldHandle.Name = "Handle"
    shieldHandle.Parent = shield
    shield.Parent = world.localPlayer.Character
    -- Parented first, so it is the tool a naive search finds.
    sword.Parent = nil
    sword.Parent = world.localPlayer.Character

    enemy.Character:FindFirstChild("HumanoidRootPart").Position = world.vector3(0, 0, -8)
    aura.Options["Weapon name"].Value = ""
    world.clock += 5
    aura:Toggle()

    -- Swinging the sword by hand teaches the module which tool to use.
    sword.Activated:Fire()
    local shieldBefore: number = shield.Activations or 0
    local swordBefore: number = sword.Activations or 0
    world.clock += 1
    stub.step(0.016)
    check("uses the weapon the player swung by hand",
        (sword.Activations or 0) > swordBefore
            and (shield.Activations or 0) == shieldBefore,
        "sword: " .. tostring(sword.Activations) .. " shield: " .. tostring(shield.Activations))

    -- A typed name wins over what was learned.
    aura.Options["Weapon name"].Value = "shield"
    local shieldBefore2: number = shield.Activations or 0
    world.clock += 1
    stub.step(0.016)
    check("a typed weapon name takes priority",
        (shield.Activations or 0) > shieldBefore2,
        "shield: " .. tostring(shield.Activations))
    aura.Options["Weapon name"].Value = ""

    -- Swing only: the tool is pressed, no touch events are fired.
    aura.Options["Swing only"].Value = true
    world.touchFires = 0
    local swordBefore3: number = sword.Activations or 0
    world.clock += 1
    stub.step(0.016)
    check("swing only presses the weapon", (sword.Activations or 0) > swordBefore3)
    check("swing only fires no contact events", world.touchFires == 0,
        "touches: " .. tostring(world.touchFires))
    aura.Options["Swing only"].Value = false
    aura:Toggle()
    shield:Destroy()

    -- Auto Clicker -----------------------------------------------------------------

    section("Auto Clicker")

    local ClickerFile: any = require("../../../src/modules/Combat/AutoClicker")
    Mock.inject(world, ClickerFile.init)
    local clicker: any = ClickerFile.init(espContext)

    check("card is registered", clicker.Name == "Auto Clicker")
    for _, name: string in ipairs({
        "CPS",
        "Activation",
        "Hold key",
        "Click",
        "Weapons only",
        "Button name",
    }) do
        check("option: " .. name, clicker.Options[name] ~= nil)
    end

    -- Tool mode: presses whatever is equipped, at the configured rate — but only
    -- while the attack is actually held down.
    clicker.Options["Click"].Value = "Tool"
    clicker.Options["CPS"].Value = {Min = 10, Max = 10}
    local toolBefore: number = sword.Activations or 0
    clicker:Toggle()
    check("auto clicker reports its CPS band",
        clicker.Status == "10-10 CPS", tostring(clicker.Status))
    world.mouseDown = false
    world.clock += 1
    stub.step(0.016)
    check("nothing is pressed while the attack is not held",
        (sword.Activations or 0) == toolBefore,
        "activations: " .. tostring(sword.Activations))

    world.mouseDown = true
    world.clock += 1
    stub.step(0.016)
    check("presses the equipped tool", (sword.Activations or 0) > toolBefore,
        "activations: " .. tostring(sword.Activations))

    local rateBefore: number = sword.Activations or 0
    stub.step(0.016)
    check("respects the click rate", (sword.Activations or 0) == rateBefore)

    -- The rate is drawn inside the band, never outside it.
    clicker.Options["CPS"].Value = {Min = 4, Max = 16}
    local lowest: number = math.huge
    local highest: number = -math.huge
    for _ = 1, 40 do
        local drawn: number = clicker.Options["CPS"]:GetRandomValue()
        lowest = math.min(lowest, drawn)
        highest = math.max(highest, drawn)
    end
    check("the CPS range stays inside its band", lowest >= 4 and highest <= 16,
        tostring(lowest) .. " .. " .. tostring(highest))

    -- Hold key: the SpeedAutoClicker shape. The mouse is not held at all here;
    -- only the key is, and only while it is down does anything get pressed.
    clicker.Options["CPS"].Value = {Min = 10, Max = 10}
    clicker.Options["Activation"].Value = "Hold key"
    clicker.Options["Hold key"].Value = world.globals.Enum.KeyCode.E
    world.mouseDown = false
    world.keyDown = false
    local holdBefore: number = sword.Activations or 0
    world.clock += 1
    stub.step(0.016)
    check("hold key does nothing while the key is up",
        (sword.Activations or 0) == holdBefore)

    world.keyDown = true
    world.clock += 1
    stub.step(0.016)
    check("hold key clicks while the key is down",
        (sword.Activations or 0) > holdBefore,
        "activations: " .. tostring(sword.Activations))
    world.keyDown = false
    clicker.Options["Activation"].Value = "Hold click"
    world.mouseDown = true

    -- Screen button mode: the game's own touch button, pressed the way a finger
    -- presses it.
    local gameGui: any = Mock.newInstance("ScreenGui")
    gameGui.Name = "TouchAttackGui"
    local playerGui: any = Mock.newInstance("PlayerGui")
    playerGui.Name = "PlayerGui"
    playerGui.Parent = world.localPlayer
    gameGui.Parent = playerGui
    local attackButton: any = Mock.newInstance("TextButton")
    attackButton.Name = "AttackButton"
    attackButton.Parent = gameGui
    local buttonPresses: number = 0
    attackButton.MouseButton1Click:Connect(function(): ()
        buttonPresses += 1
    end)

    clicker.Options["Click"].Value = "Screen button"
    clicker.Options["Button name"].Value = "attack"
    world.clock += 1
    stub.step(0.016)
    check("presses the game's own screen button", buttonPresses > 0,
        "presses: " .. tostring(buttonPresses))

    -- Learning: press Learn button, then tap the game's button.
    clicker.Options["Button name"].Value = ""
    clicker.Feature.options["Learn button"].run()
    playerGui.HitTest = {attackButton}
    host.UserInputService.InputBegan:Fire({
        UserInputType = world.globals.Enum.UserInputType.Touch,
        Position = world.vector3(200, 400, 0),
    }, false)
    check("learns the button under the tap",
        clicker.Options["Button name"].Value == "AttackButton",
        tostring(clicker.Options["Button name"].Value))

    -- The menu's own buttons must never be learned or clicked.
    local menuButton: any = Mock.newInstance("TextButton")
    menuButton.Name = "MenuButton"
    menuButton.Parent = host.ScreenGui
    clicker.Feature.options["Learn button"].run()
    playerGui.HitTest = {menuButton}
    host.UserInputService.InputBegan:Fire({
        UserInputType = world.globals.Enum.UserInputType.Touch,
        Position = world.vector3(200, 400, 0),
    }, false)
    check("ignores the menu's own buttons while learning",
        clicker.Options["Button name"].Value == "AttackButton")

    clicker:Toggle()
    check("clicker disables", clicker.Enabled == false)
    local afterDisable: number = buttonPresses
    world.clock += 1
    stub.step(0.016)
    check("nothing is pressed while disabled", buttonPresses == afterDisable)

    -- Wall-clock, not the mocked os.clock. Raise only with a comment saying
    -- what got more expensive.
    local BUDGET_CLICKER_FRAME_SECONDS: number = 0.010
    world.mouseDown = true
    clicker:Toggle()
    local clickerPerFrame: number = ctx.measureFrames(stub.step, 20)
    clicker:Toggle()
    check(
        "Auto Clicker stays inside the per-frame time budget",
        clickerPerFrame <= BUDGET_CLICKER_FRAME_SECONDS,
        string.format("%.4fs/frame", clickerPerFrame)
    )

    -- Kill Aura target readout ------------------------------------------------------

    section("Kill Aura show target")

    world.raycastResult = nil
    world.localPlayer.Character:FindFirstChild("HumanoidRootPart").Position =
        world.vector3(0, 0, 0)
    enemy.Character:FindFirstChild("HumanoidRootPart").Position = world.vector3(0, 0, -8)
    aura.Options["Show target"].Value = true
    aura.Options["Team check"].Value = true
    aura:Toggle()
    world.clock += 2
    stub.step(0.016)

    local panel: any = nil
    for _, child: any in ipairs(host.ScreenGui.Children) do
        if child.Name == "KillAuraTarget" then
            panel = child
        end
    end
    check("target panel exists while a target is held", panel ~= nil and panel.Visible == true)
    check("panel names the target",
        panel ~= nil and panel:FindFirstChild("TargetName").Text == "Enemy",
        panel and tostring(panel:FindFirstChild("TargetName").Text) or "no panel")
    check("panel reports health and distance",
        panel ~= nil
            and string.find(panel:FindFirstChild("TargetDetail").Text, "hp", 1, true) ~= nil,
        panel and tostring(panel:FindFirstChild("TargetDetail").Text) or "no panel")

    -- Out of reach: the readout goes away rather than lying about the target.
    enemy.Character:FindFirstChild("HumanoidRootPart").Position = world.vector3(0, 0, -400)
    world.clock += 1
    stub.step(0.016)
    check("panel hides when there is no target", panel ~= nil and panel.Visible == false)
    aura:Toggle()

    -- Click Teleport ---------------------------------------------------------------

    section("Weapon discovery (no-Tool games)")

    -- A BedFight-shaped game: no Tool anywhere, a view model under the camera, an
    -- inventory slot and a mobile attack button.
    local viewModel: any = Mock.newInstance("Model")
    viewModel.Name = "ViewModel"
    viewModel.Parent = world.camera
    local bladeModel: any = Mock.newInstance("Model")
    bladeModel.Name = "Emerald Sword"
    bladeModel.Parent = viewModel

    local mobileGui: any = Mock.newInstance("ScreenGui")
    mobileGui.Name = "MobileGui"
    mobileGui.Parent = world.localPlayer:FindFirstChild("PlayerGui")
    local buttonsFrame: any = Mock.newInstance("Frame")
    buttonsFrame.Name = "ButtonsFrame"
    buttonsFrame.Parent = mobileGui
    local mobileSword: any = Mock.newInstance("ImageButton")
    mobileSword.Name = "Sword"
    mobileSword.Parent = buttonsFrame
    local mobileSwings: number = 0
    mobileSword.MouseButton1Click:Connect(function(): ()
        mobileSwings += 1
    end)

    local hotbar: any = Mock.newInstance("Frame")
    hotbar.Name = "HotbarList"
    hotbar.Parent = mobileGui
    local slot: any = Mock.newInstance("ImageButton")
    slot.Name = "Iron Sword"
    slot.Visible = true
    slot.Parent = hotbar

    -- Junk the picker must never list: a hotbar is full of blocks, emotes and
    -- cosmetics sitting next to the sword.
    local junkNames: {string} = {
        "EmoteWheel",
        "AnimationPack",
        "Wool Block",
        "Oak Plank",
        "KitButton",
        "ShopButton",
    }
    for index: number, junk: string in ipairs(junkNames) do
        local button: any = Mock.newInstance("ImageButton")
        button.Name = junk
        button.Visible = true
        button.Parent = hotbar
        if index == 1 then
            button.Parent = buttonsFrame
        end
    end

    local labels: {string} = weapons:Labels({All = true})
    local function hasLabel(needle: string): boolean
        for _, label: string in ipairs(labels) do
            if string.find(label, needle, 1, true) then
                return true
            end
        end
        return false
    end
    check("finds a view-model weapon", hasLabel("Emerald Sword"),
        table.concat(labels, " | "))
    check("finds the game's mobile attack button", hasLabel("Sword  ·  Button"),
        table.concat(labels, " | "))
    check("finds an inventory slot", hasLabel("Iron Sword"),
        table.concat(labels, " | "))

    for _, junk: string in ipairs(junkNames) do
        local listed: boolean = false
        for _, label: string in ipairs(labels) do
            if string.find(label, junk, 1, true) then
                listed = true
            end
        end
        check("does not list " .. junk, not listed, table.concat(labels, " | "))
    end

    -- Melee only.
    --
    -- A view model is the whole first-person rig, and a hotbar holds the bow next
    -- to the sword: the picker used to list "RightUpperArm", "Sneak", "Blocks" and
    -- "Crossbow" as things Kill Aura could swing.
    local rigNames: {string} = {"RightUpperArm", "Sneak", "Blocks", "IdleTrack"}
    for _, rigName: string in ipairs(rigNames) do
        local rigPart: any = Mock.newInstance("Model")
        rigPart.Name = rigName
        rigPart.Parent = viewModel
    end
    local bow: any = Mock.newInstance("ImageButton")
    bow.Name = "Crossbow"
    bow.Visible = true
    bow.Parent = hotbar

    local meleeLabels: {string} = weapons:Labels({All = true, Melee = true})
    local function hasMelee(needle: string): boolean
        for _, label: string in ipairs(meleeLabels) do
            if string.find(label, needle, 1, true) then
                return true
            end
        end
        return false
    end
    check("melee list keeps the view-model sword", hasMelee("Emerald Sword"),
        table.concat(meleeLabels, " | "))
    check("melee list keeps the inventory sword", hasMelee("Iron Sword"),
        table.concat(meleeLabels, " | "))
    for _, rigName: string in ipairs(rigNames) do
        check("melee list drops " .. rigName, not hasMelee(rigName),
            table.concat(meleeLabels, " | "))
    end
    check("melee list drops the crossbow", not hasMelee("Crossbow"),
        table.concat(meleeLabels, " | "))
    check("a sword is melee", weapons:IsMelee("Wooden Sword"))
    check("a bow is not melee", not weapons:IsMelee("Bow"))
    check("a rig part is not melee", not weapons:IsMelee("RightUpperLeg"))

    local candidate: any = weapons:Find("Sword  ·  Button")
    check("activating a button candidate presses it",
        candidate ~= nil and weapons:Activate(candidate) and mobileSwings > 0,
        "swings: " .. tostring(mobileSwings))

    -- Kill Aura swings the ticked candidate even with no Tool in sight.
    enemy.Character:FindFirstChild("HumanoidRootPart").Position = world.vector3(0, 0, -8)
    -- Nothing between us and the target, and the local player back at the origin:
    -- the teleport tests left the character seven studs away, which is enough to
    -- put the enemy outside the aura's twelve-stud reach.
    world.raycastResult = nil
    world.localPlayer.Character:FindFirstChild("HumanoidRootPart").Position =
        world.vector3(0, 0, 0)
    sword.Parent = nil
    aura.Feature.options["Weapons"].set("Sword  ·  Button", true)
    local swingsBefore: number = mobileSwings
    aura:Toggle()
    world.clock += 2
    stub.step(0.016)
    check("Kill Aura swings a ticked non-Tool weapon", mobileSwings > swingsBefore,
        "swings: " .. tostring(mobileSwings))
    aura:Toggle()
    aura.Feature.options["Weapons"].set("Sword  ·  Button", false)

    -- Nothing ticked, no Tool in the character: the aura must still find the
    -- game's own button and press it. This is the case that used to outline the
    -- target and then do nothing at all.
    -- Either attack button counts: the point is that something was pressed.
    local autoBefore: number = mobileSwings + buttonPresses
    aura:Toggle()
    world.clock += 2
    stub.step(0.016)
    check("swings automatically when nothing is ticked and no tool exists",
        mobileSwings + buttonPresses > autoBefore,
        "presses: " .. tostring(mobileSwings + buttonPresses))
    aura:Toggle()

    sword.Parent = world.localPlayer.Character

    -- Item Render -------------------------------------------------------------------

    section("Remote Logger")

    local LoggerFile: any = require("../../../src/modules/Utility/RemoteLogger")
    Mock.inject(world, LoggerFile.init)
    local logger: any = LoggerFile.init(espContext)

    check("card is registered", logger.Name == "Remote Logger")
    for _, name: string in ipairs({"Only containing", "Max remotes", "Announce new"}) do
        check("option: " .. name, logger.Options[name] ~= nil)
    end
    for _, name: string in ipairs({
        "Save to file",
        "Print to console",
        "Copy to clipboard",
        "Clear log",
    }) do
        check("action: " .. name, logger.Feature.options[name] ~= nil)
    end

    logger:Toggle()
    check("logger enables", logger.Enabled == true)
    check("hook was installed", world.namecallHook ~= nil)

    -- A game firing one of its own remotes, exactly as the hook sees it.
    local remote: any = Mock.newInstance("RemoteEvent")
    remote.Name = "SwordHit"
    remote.Parent = world.workspace
    world.namecallMethod = "FireServer"
    world.namecallHook(remote, "Wooden Sword", world.vector3(1, 2, 3), 42)
    -- Deferred by design: the hook only queues, so the work lands on the next
    -- frame rather than inside the game's own call.
    stub.step(0.016)

    local entries: {any} = host.state.remoteLog.entries()
    check("records the call", #entries == 1, "entries: " .. tostring(#entries))
    check("records the method", entries[1] ~= nil and entries[1].method == "FireServer")
    check("records the argument values",
        entries[1] ~= nil
            and string.find(table.concat(entries[1].arguments, ","), "Wooden Sword", 1, true) ~= nil,
        entries[1] and table.concat(entries[1].arguments, " | ") or "none")

    -- Saving writes a readable report and a machine-readable one.
    logger.Feature.options["Save to file"].run()
    local wroteText: boolean = false
    local wroteJson: boolean = false
    local usedStorageFolder: boolean = true
    for path: string in pairs(world.files) do
        if string.find(path, "RemoteLogs", 1, true) then
            usedStorageFolder = usedStorageFolder
                and string.sub(path, 1, #host.PRODUCT.storageFolder)
                    == host.PRODUCT.storageFolder
        end
        if string.find(path, "%.txt$") then
            wroteText = true
        end
        if string.find(path, "%.json$") then
            wroteJson = true
        end
    end
    check("saved under PRODUCT.storageFolder", usedStorageFolder)
    check("saved a readable log", wroteText)
    check("saved a machine-readable log", wroteJson)

    -- The menu's own traffic must never be logged.
    world.callerIsMenu = true
    world.namecallHook(remote, "menu-call")
    world.callerIsMenu = false
    stub.step(0.016)
    check("ignores the menu's own calls", #host.state.remoteLog.entries() == 1)

    logger.Feature.options["Clear log"].run()
    check("clears the log", #host.state.remoteLog.entries() == 0)
    logger:Toggle()

    -- Improve FPS --------------------------------------------------------------------

    section("Improve FPS")

    local FpsFile: any = require("../../../src/modules/Utility/ImproveFps")
    Mock.inject(world, FpsFile.init)
    local improveFps: any = FpsFile.init(espContext)

    check("card is registered", improveFps.name == "Improve FPS")
    for _, name: string in ipairs({
        "Remove textures",
        "Disable particles",
        "Disable shadows",
        "Simple materials",
    }) do
        check("option: " .. name, improveFps.options[name] ~= nil)
    end

    local decal: any = Mock.newInstance("Decal")
    decal.Transparency = 0
    decal.Parent = world.workspace
    local emitter: any = Mock.newInstance("ParticleEmitter")
    emitter.Enabled = true
    emitter.Parent = world.workspace
    local scenery: any = Mock.newInstance("Part")
    scenery.CastShadow = true
    scenery.Material = world.globals.Enum.Material.Plastic
    scenery.Reflectance = 0.5
    scenery.Parent = world.workspace

    improveFps.activate()
    check("decals are hidden", decal.Transparency == 1)
    check("emitters are switched off", emitter.Enabled == false)
    check("shadows are dropped", scenery.CastShadow == false)
    -- Simple materials is off by default, so the look of the map is left alone.
    check("materials are left alone",
        scenery.Material == world.globals.Enum.Material.Plastic
            and scenery.Reflectance == 0.5)

    -- Parts that stream in after the sweep get the same treatment; without this
    -- the optimisation only ever covered whatever happened to be loaded.
    local latecomer: any = Mock.newInstance("Decal")
    latecomer.Transparency = 0.25
    latecomer.Parent = world.workspace
    world.workspace.DescendantAdded:Fire(latecomer)
    check("late arrivals are optimised too", latecomer.Transparency == 1)

    improveFps.activate()
    check("decals come back", decal.Transparency == 0)
    check("emitters come back", emitter.Enabled == true)
    check("shadows come back", scenery.CastShadow == true)
    check("late arrivals are restored as well", latecomer.Transparency == 0.25)

    -- Widget library -----------------------------------------------------------------

    section("Nothing is taken out of your hands")

    -- A stowed tool in the backpack, nothing held.
    sword.Parent = nil
    local stowed: any = Mock.newInstance("Tool")
    stowed.Name = "Backpack Sword"
    local stowedHandle: any = Mock.newInstance("Part")
    stowedHandle.Name = "Handle"
    stowedHandle.Parent = stowed
    stowed.Parent = world.localPlayer:FindFirstChild("Backpack")

    local equipped: number = 0
    local humanoid: any = world.localPlayer.Character:FindFirstChildOfClass("Humanoid")
    local realEquip: any = humanoid.EquipTool
    humanoid.EquipTool = function(self: any, tool: any): ()
        equipped += 1
        realEquip(self, tool)
    end

    weapons:Invalidate()
    weapons:SetAllowEquip(false)
    weapons:Swing()
    check("a stowed tool is not equipped by default", equipped == 0,
        "equips: " .. tostring(equipped))

    -- And when the player does ask for it, it happens.
    weapons:Invalidate()
    weapons:SetAllowEquip(true)
    local stowedSword: any = weapons:Find("Backpack Sword")
    if stowedSword then
        weapons:Activate(stowedSword)
    end
    check("it is equipped when the option is on", equipped == 1,
        "equips: " .. tostring(equipped))
    weapons:SetAllowEquip(false)
    humanoid.EquipTool = realEquip
    stowed:Destroy()
    sword.Parent = world.localPlayer.Character

    -- Spoof ------------------------------------------------------------------------

    ctx.TriggerFile = TriggerFile
    ctx.FriendFile = FriendFile
    ctx.AuraFile = AuraFile
    ctx.aura = aura
    ctx.sword = sword
    ctx.ClickerFile = ClickerFile
    ctx.LoggerFile = LoggerFile
end
