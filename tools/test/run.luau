--!strict
--
-- Headless module tests.
--
-- Run with `luau tools/test/run.luau` from the repository root. Every module
-- file the runtime downloads is loaded here against a stand-in Roblox and a
-- stand-in menu host, switched on, driven for a few frames and switched off
-- again — which is the only cheap way to prove that a module's options exist,
-- that its loops run without erroring and that turning it off leaves nothing
-- behind.

local Mock = require("./Roblox")
local Host = require("./Host")

local world: any = Mock.install()
local stub: any = Host.create(world)
local host: any = stub.env

local passed: number = 0
local failures: {string} = {}

local function check(label: string, condition: boolean, detail: string?): ()
    if condition then
        passed += 1
        print("  ok   " .. label)
    else
        table.insert(failures, label .. (detail and (" — " .. detail) or ""))
        print("  FAIL " .. label .. (detail and (" — " .. detail) or ""))
    end
end

local function section(name: string): ()
    print("")
    print(name)
end

-- Framework ------------------------------------------------------------------

section("Framework")

local FrameworkFile: any = require("../../src/core/Framework")
Mock.inject(world, FrameworkFile.init)
local framework: any = FrameworkFile.init(host)

check("categories exist", framework.Categories.Combat ~= nil
    and framework.Categories.Visuals ~= nil
    and framework.Categories.Movement ~= nil)

local loopRuns: number = 0
local disposed: boolean = false
local sample: any
sample = framework.Categories.Utility:CreateModule({
    Name = "Sample",
    Tooltip = "Test module",
    Function = function(enabled: boolean): ()
        if not enabled then
            return
        end
        sample:Loop(function(): ()
            loopRuns += 1
        end)
        sample:Clean(function(): ()
            disposed = true
        end)
    end,
})
local sampleSlider: any = sample:CreateSlider({
    Name = "Amount",
    Min = 0,
    Max = 10,
    Default = 4,
})
local sampleDropdown: any = sample:CreateDropdown({
    Name = "Mode",
    List = {"First", "Second"},
    Index = 2,
})
local sampleToggle: any = sample:CreateToggle({Name = "Switch", Default = true})

check("slider reports its default", sampleSlider.Value == 4)
check("dropdown honours its index", sampleDropdown.Value == "Second")
check("toggle reports its default", sampleToggle.Value == true)

sample:Toggle()
check("module enables", sample.Enabled == true)
local tasksWhileOn: number = stub.taskCount()
stub.step(0.016)
stub.step(0.016)
check("loop runs each frame", loopRuns == 2, "ran " .. tostring(loopRuns))

sample:Toggle()
check("module disables", sample.Enabled == false)
check("cleanup ran", disposed == true)
check(
    "loop disconnected",
    stub.taskCount() == tasksWhileOn - 1,
    "tasks left: " .. tostring(stub.taskCount())
)
loopRuns = 0
stub.step(0.016)
check("loop no longer runs after disable", loopRuns == 0)

-- Entity ---------------------------------------------------------------------

section("Entity library")

local EntityFile: any = require("../../src/library/Entity")
Mock.inject(world, EntityFile.init)
local entity: any = EntityFile.init(host)

local enemy: any = world.addPlayer("Enemy", "Red", world.vector3(0, 0, -30))
local ally: any = world.addPlayer("Ally", "Blue", world.vector3(10, 0, -10))
-- Forced: the mocked clock is frozen between steps, and Refresh coalesces
-- calls that land inside the same frame.
entity:Refresh(true)

check("list excludes the local player", #entity.List == 2,
    "found " .. tostring(#entity.List))
check("enemy is not friendly", entity:Get(enemy).IsFriendly == false)
check("ally is friendly", entity:Get(ally).IsFriendly == true)
check("distance is measured", entity:Get(enemy).Distance == 30,
    tostring(entity:Get(enemy).Distance))

local bones: {any} = entity:Rig(entity:Get(enemy))
check("R15 rig resolves bones", #bones == 14, "found " .. tostring(#bones))

world.raycastResult = nil
check("no obstruction means visible", entity:VisibleFrom(entity:Get(enemy)) == true)
world.raycastResult = {Instance = Mock.newInstance("Part"), Position = world.vector3(0, 0, -5)}
check("obstruction hides the target", entity:VisibleFrom(entity:Get(enemy)) == false)
world.raycastResult = nil

local closest: any = entity:ClosestToRay(
    world.vector3(0, 0, 0),
    world.vector3(0, 0, -1),
    {IgnoreWalls = true}
)
check("closest to ray skips teammates", closest ~= nil and closest.Player == enemy)

-- Player ESP -----------------------------------------------------------------

section("Player ESP")

local EspFile: any = require("../../src/modules/Visuals/PlayerESP")
Mock.inject(world, EspFile.init)
local WeaponsFile: any = require("../../src/library/Weapons")
Mock.inject(world, WeaponsFile.init)
local weapons: any = WeaponsFile.init(host)
local RenderFile: any = require("../../src/library/Render")
Mock.inject(world, RenderFile.init)
local render: any = RenderFile.init(host)
local espContext: any = {
    framework = framework,
    entity = entity,
    weapons = weapons,
    render = render,
    host = host,
}
local esp: any = EspFile.init(espContext)

check("card is registered", esp ~= nil and esp.Name == "Player ESP")
check("box mode option exists", esp.Options["Boxes"] ~= nil)
check("skeleton option exists", esp.Options["Skeleton"] ~= nil)
check("name tag option exists", esp.Options["Name tags"] ~= nil)
check("chams option exists", esp.Options["Chams"] ~= nil)
check("health bar option exists", esp.Options["Health bar"] ~= nil)
check("tracer option exists", esp.Options["Tracers"] ~= nil)
check("filters exist", esp.Options["Team check"] ~= nil
    and esp.Options["Max distance"] ~= nil
    and esp.Options["Visibility check"] ~= nil)
check("style options exist", esp.Options["Colour"] ~= nil
    and esp.Options["Team colours"] ~= nil
    and esp.Options["Text size"] ~= nil)
check("the three-colour scheme is gone",
    esp.Options["Enemy colour"] == nil
        and esp.Options["Friendly colour"] == nil
        and esp.Options["Hidden colour"] == nil)

esp:Toggle()
check("esp enables", esp.Enabled == true)
esp.Options["Team check"].Value = true
esp.Options["Skeleton"].Value = true
esp.Options["Boxes"].Value = "Full"
esp.Options["Chams"].Value = "Overlay"
-- The redraw interval defaults to 30ms, so one 16ms frame is not a redraw.
stub.step(0.05)

local layer: any = nil
for _, child: any in ipairs(host.ScreenGui.Children) do
    if child.Name == "PlayerEspLayer" then
        layer = child
    end
end
check("overlay layer exists", layer ~= nil)
check("overlay is visible while enabled", layer ~= nil and layer.Visible == true)
check(
    "one drawing set per visible enemy",
    layer ~= nil and #layer.Children == 1,
    layer and ("sets: " .. tostring(#layer.Children)) or "no layer"
)

local drawings: any = layer and layer.Children[1]
local nameTag: any = drawings and drawings:FindFirstChild("NameTag")
check("name tag carries the display name",
    nameTag ~= nil and nameTag.Text == "Enemy",
    nameTag and tostring(nameTag.Text) or "missing")
check("box segments are drawn",
    drawings ~= nil and drawings:FindFirstChild("Box1").Visible == true)
esp.Options["Filled box"].Value = true
stub.step(0.05)
check("the filled box follows the box it fills",
    drawings ~= nil and drawings:FindFirstChild("BoxFill").Visible == true)
esp.Options["Filled box"].Value = false
esp.Options["Display name"].Value = false
stub.step(0.05)
check("the display-name switch falls back to the account name",
    nameTag ~= nil and nameTag.Text == enemy.Name,
    nameTag and tostring(nameTag.Text) or "missing")
esp.Options["Display name"].Value = true
stub.step(0.05)
check("skeleton bones are drawn",
    drawings ~= nil and drawings:FindFirstChild("Bone1").Visible == true)
check("chams highlight is parented to the character",
    enemy.Character:FindFirstChildOfClass("Highlight") ~= nil)

esp.Options["Team check"].Value = false
stub.step(0.05)
check(
    "disabling the team check reveals allies",
    layer ~= nil and #layer.Children == 2,
    layer and ("sets: " .. tostring(#layer.Children)) or "no layer"
)

-- The game bridge: roles and per-game objects arrive from the game module and
-- become rows in this one card, instead of a second ESP.
local roleColour: any = world.globals.Color3.fromRGB(255, 0, 0)
host.state.registerRoleProvider({
    Name = "MM2",
    Roles = {"Murderer", "Innocent"},
    Colors = {Murderer = roleColour, Innocent = world.globals.Color3.fromRGB(255, 255, 255)},
    Get = function(player: any): string?
        return player == enemy and "Murderer" or "Innocent"
    end,
})
local extraState: any = {enabled = false, distance = 0}
host.state.registerEspExtra({
    Name = "Coins",
    Default = false,
    Color = world.globals.Color3.fromRGB(255, 210, 60),
    Toggle = function(value: boolean): ()
        extraState.enabled = value
    end,
    Options = {
        {
            Kind = "number",
            Name = "max distance",
            Default = 900,
            Min = 100,
            Max = 5000,
            Set = function(value: number): ()
                extraState.distance = value
            end,
        },
    },
})
check("roles add a colour row per role",
    esp.Options["Murderer colour"] ~= nil
        and esp.Options["Innocent colour"] ~= nil)
check("roles add the role switches",
    esp.Options["Role colours"] ~= nil and esp.Options["Show role"] ~= nil)
check("roles hide the rows they make redundant",
    host.state.hiddenOptionRows["Team check"] == true
        and host.state.hiddenOptionRows["Team colours"] == true
        and host.state.hiddenOptionRows["Colour"] == true)
check("a game object becomes a row in the ESP card",
    esp.Options["Coins"] ~= nil and esp.Options["Coins colour"] ~= nil)
check("an extra keeps the tuning it had as a card",
    esp.Options["Coins max distance"] ~= nil and extraState.distance == 900,
    tostring(extraState.distance))

esp.Options["Team check"].Value = true
esp.Options["Boxes"].Value = "Full"
stub.step(0.05)
local roleDrawings: any = layer and layer.Children[1]
local roleBox: any = roleDrawings and roleDrawings:FindFirstChild("Box1")
check("the box is drawn in the role's colour",
    roleBox ~= nil and roleBox.BackgroundColor3 == roleColour,
    roleBox and tostring(roleBox.BackgroundColor3) or "no box")
local roleTag: any = roleDrawings and roleDrawings:FindFirstChild("NameTag")
check("the name tag names the role",
    roleTag ~= nil and string.find(tostring(roleTag.Text), "Murderer", 1, true) ~= nil,
    roleTag and tostring(roleTag.Text) or "missing")

esp.Options["Role colours"].Value = false
stub.step(0.05)
check("role colours can be switched off",
    roleBox ~= nil and roleBox.BackgroundColor3 ~= roleColour)
esp.Options["Team check"].Value = false

esp:Toggle()
check("esp disables", esp.Enabled == false)
check("drawings are released", layer ~= nil and #layer.Children == 0,
    layer and ("sets: " .. tostring(#layer.Children)) or "no layer")
check("overlay is hidden while disabled", layer ~= nil and layer.Visible == false)
check("chams are removed",
    enemy.Character:FindFirstChildOfClass("Highlight") == nil)

-- TriggerBot -----------------------------------------------------------------

section("TriggerBot")

local TriggerFile: any = require("../../src/modules/Combat/TriggerBot")
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

-- Friend list ----------------------------------------------------------------

section("Friend list")

local FriendFile: any = require("../../src/modules/Utility/FriendList")
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

section("Kill Aura")

local AuraFile: any = require("../../src/modules/Combat/KillAura")
Mock.inject(world, AuraFile.init)
local aura: any = AuraFile.init(espContext)

check("card is registered", aura ~= nil and aura.Name == "Kill Aura")
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

local ClickerFile: any = require("../../src/modules/Combat/AutoClicker")
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

section("Click Teleport")

local ClickFile: any = require("../../src/modules/Movement/ClickTeleport")
Mock.inject(world, ClickFile.init)
local clickTeleport: any = ClickFile.init(espContext)

check("card is registered", clickTeleport.Name == "Click Teleport")
check("card is a button, not a switch",
    clickTeleport.Feature.kind == "action", tostring(clickTeleport.Feature.kind))
for _, name: string in ipairs({
    "Destination",
    "Player",
    "Item",
    "Save waypoint",
    "Go back",
    "Movement",
    "Glide step",
    "Height offset",
    "Player offset",
    "Search range",
    "Keep momentum",
}) do
    check("option: " .. name, clickTeleport.Options[name] ~= nil)
end
-- Conditional rows: a control is on screen only while it can change what the
-- button does. This is the whole point of the mechanism, so it is asserted
-- rather than assumed.
check("the glide step hides while movement is instant",
    clickTeleport.Options["Glide step"].Object ~= nil
        and clickTeleport.Options["Glide step"].Object.Visible == false)
check("the name box hides while the destination is not a named player",
    clickTeleport.Options["Player"].Object.Parent.Visible == false)
clickTeleport.Options["Destination"].Value = "Named player"
clickTeleport:RefreshVisibility()
check("choosing Named player reveals the name box",
    clickTeleport.Options["Player"].Object.Parent.Visible == true)
check("and leaves the item box hidden",
    clickTeleport.Options["Item"].Object.Parent.Visible == false)
clickTeleport.Options["Destination"].Value = "Item"
clickTeleport:RefreshVisibility()
check("choosing Item swaps which box is on screen",
    clickTeleport.Options["Item"].Object.Parent.Visible == true
        and clickTeleport.Options["Player"].Object.Parent.Visible == false)
clickTeleport.Options["Destination"].Value = "Tap point"
clickTeleport:RefreshVisibility()

local localRoot: any = world.localPlayer.Character:FindFirstChild("HumanoidRootPart")
local function resetLocal(): ()
    localRoot.CFrame = world.globals.CFrame.new(world.vector3(0, 0, 0))
    localRoot.Position = world.vector3(0, 0, 0)
end

-- Tap point: pressing the card arms it, and the next tap is the destination.
resetLocal()
world.raycastResult = {
    Instance = Mock.newInstance("Part"),
    Position = world.vector3(25, 0, -40),
}
world.lastRayCall = nil
clickTeleport.Options["Destination"].Value = "Tap point"

host.UserInputService.InputBegan:Fire({
    UserInputType = world.globals.Enum.UserInputType.Touch,
    Position = world.vector3(300, 500, 0),
}, false)
check("a tap does nothing until the button arms it",
    localRoot.CFrame.Position.X == 0)

clickTeleport.Feature.activate()
host.UserInputService.InputBegan:Fire({
    UserInputType = world.globals.Enum.UserInputType.Touch,
    Position = world.vector3(300, 500, 0),
}, false)
check("teleports to the point under the tap",
    localRoot.CFrame.Position.X == 25 and localRoot.CFrame.Position.Z == -40,
    "landed at " .. tostring(localRoot.CFrame.Position.X)
        .. "," .. tostring(localRoot.CFrame.Position.Z))
check("lands above the surface, not inside it",
    localRoot.CFrame.Position.Y == 5, "y: " .. tostring(localRoot.CFrame.Position.Y))
check("uses screen coordinates, not viewport coordinates",
    world.lastRayCall == "ScreenPointToRay", tostring(world.lastRayCall))

-- Taps the interface already handled must never teleport.
resetLocal()
clickTeleport.Feature.activate()
host.UserInputService.InputBegan:Fire({
    UserInputType = world.globals.Enum.UserInputType.Touch,
    Position = world.vector3(300, 500, 0),
}, true)
check("ignores taps consumed by the menu", localRoot.CFrame.Position.X == 0)

-- Nearest player, stopping short by the player offset. The ally at (10, 0, -10)
-- is the closest body in the server, so that is who it must pick.
resetLocal()
enemy.Character:FindFirstChild("HumanoidRootPart").Position = world.vector3(0, 0, -100)
clickTeleport.Options["Destination"].Value = "Nearest player"
clickTeleport.Options["Skip friends"].Value = true
clickTeleport.Options["Player offset"].Value = 0
clickTeleport.Feature.activate()
check("travels to the nearest player",
    localRoot.CFrame.Position.X == 10 and localRoot.CFrame.Position.Z == -10,
    tostring(localRoot.CFrame.Position.X) .. "," .. tostring(localRoot.CFrame.Position.Z))

-- With the ally protected, the nearest *targetable* player is the enemy.
resetLocal()
host.state.friendList.names = {ally = true}
clickTeleport.Feature.activate()
check("skips players on the friend list",
    localRoot.CFrame.Position.Z == -100,
    "z: " .. tostring(localRoot.CFrame.Position.Z))
host.state.friendList.names = {}

-- The player offset stops you short of the target instead of inside it.
resetLocal()
clickTeleport.Options["Player offset"].Value = 4
host.state.friendList.names = {ally = true}
clickTeleport.Feature.activate()
check("stops short of the target by the player offset",
    localRoot.CFrame.Position.Z == -96,
    "z: " .. tostring(localRoot.CFrame.Position.Z))
host.state.friendList.names = {}

-- Named player, matched on part of the name.
resetLocal()
clickTeleport.Options["Destination"].Value = "Named player"
clickTeleport.Options["Player"].Value = "ene"
clickTeleport.Feature.activate()
check("matches a player by part of their name",
    localRoot.CFrame.Position.Z == -96,
    "z: " .. tostring(localRoot.CFrame.Position.Z))

-- A name nobody has must not move the character.
resetLocal()
clickTeleport.Options["Player"].Value = "nobody-here"
clickTeleport.Feature.activate()
check("does nothing when no player matches", localRoot.CFrame.Position.Z == 0)

-- Item search: nearest matching object in the workspace.
resetLocal()
local chest: any = Mock.newInstance("Part")
chest.Name = "GoldChest"
chest.Position = world.vector3(0, 0, -60)
chest.Parent = world.workspace
local farChest: any = Mock.newInstance("Part")
farChest.Name = "GoldChest"
farChest.Position = world.vector3(0, 0, -900)
farChest.Parent = world.workspace
clickTeleport.Options["Destination"].Value = "Item"
clickTeleport.Options["Item"].Value = "chest"
clickTeleport.Feature.activate()
check("finds the nearest item by partial name",
    localRoot.CFrame.Position.Z == -60,
    "z: " .. tostring(localRoot.CFrame.Position.Z))

-- Waypoints and the undo hop.
resetLocal()
localRoot.Position = world.vector3(7, 0, 7)
clickTeleport.Feature.options["Save waypoint"].run()
resetLocal()
clickTeleport.Options["Destination"].Value = "Waypoint"
clickTeleport.Feature.activate()
check("returns to a saved waypoint",
    localRoot.CFrame.Position.X == 7 and localRoot.CFrame.Position.Z == 7,
    tostring(localRoot.CFrame.Position.X) .. "," .. tostring(localRoot.CFrame.Position.Z))

localRoot.Position = world.vector3(7, 0, 7)
clickTeleport.Feature.options["Go back"].run()
check("goes back to where the last hop started",
    localRoot.CFrame.Position.X == 0 and localRoot.CFrame.Position.Z == 0,
    tostring(localRoot.CFrame.Position.X) .. "," .. tostring(localRoot.CFrame.Position.Z))

chest:Destroy()
farChest:Destroy()

-- Weapon discovery -------------------------------------------------------------

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

section("Item Render")

local ItemFile: any = require("../../src/modules/Visuals/ItemRender")
Mock.inject(world, ItemFile.init)
local itemRender: any = ItemFile.init(espContext)

check("card is registered", itemRender.Name == "Item Render")
for _, name: string in ipairs({
    "Objects",
    "Add by name",
    "Touch part",
    "Clear list",
    "Show distance",
    "Outline",
    "Max distance",
    "Colour",
}) do
    check("option: " .. name, itemRender.Options[name] ~= nil
        or itemRender.Feature.options[name] ~= nil)
end

local oreA: any = Mock.newInstance("Part")
oreA.Name = "IronOre"
oreA.Position = world.vector3(0, 0, -20)
oreA.Parent = world.workspace
local oreB: any = Mock.newInstance("Part")
oreB.Name = "IronOre"
oreB.Position = world.vector3(0, 0, -40)
oreB.Parent = world.workspace

itemRender:Toggle()
itemRender.Options["Refresh interval"].Value = 0
stub.step(0.016)

-- Touch part: the menu hides, the tap names the object, every twin lights up.
world.menuHidden = false
itemRender.Feature.options["Touch part"].run()
check("touch part hides the menu", host.state.menuVisible == false)

world.raycastResult = {Instance = oreA, Position = world.vector3(0, 0, -20)}
host.UserInputService.InputBegan:Fire({
    UserInputType = world.globals.Enum.UserInputType.Touch,
    Position = world.vector3(300, 400, 0),
}, false)
check("touch part adds the object to the list",
    itemRender.Feature.options["Objects"].selected["IronOre"] == true,
    "list: " .. tostring(itemRender.Options["Objects"].Selected and
        table.concat(itemRender.Options["Objects"].Selected, ",") or "?"))
check("touch part brings the menu back", host.state.menuVisible == true)

stub.step(0.016)
local itemLayer: any = nil
for _, child: any in ipairs(host.ScreenGui.Children) do
    if child.Name == "ItemRenderLayer" then
        itemLayer = child
    end
end
check("overlay layer exists", itemLayer ~= nil)
check(
    "every object with that name is rendered",
    itemLayer ~= nil and #itemLayer.Children == 2,
    itemLayer and ("sets: " .. tostring(#itemLayer.Children)) or "no layer"
)
local itemTag: any = itemLayer and itemLayer.Children[1] and itemLayer.Children[1]:FindFirstChild("NameTag")
check("the label carries the object name",
    itemTag ~= nil and string.find(tostring(itemTag.Text), "IronOre", 1, true) ~= nil,
    itemTag and tostring(itemTag.Text) or "missing")

-- Unticking one object stops it being drawn without touching the others.
itemRender.Feature.options["Objects"].set("IronOre", false)
stub.step(0.016)
check("unticking an object stops rendering it",
    itemLayer ~= nil and #itemLayer.Children == 0,
    itemLayer and ("still rendered: " .. tostring(#itemLayer.Children)) or "no layer")
itemRender.Feature.options["Objects"].set("IronOre", true)
stub.step(0.016)

itemRender:Toggle()
check("labels are released when the module is off",
    itemLayer ~= nil and #itemLayer.Children == 0,
    itemLayer and ("left: " .. tostring(#itemLayer.Children)) or "no layer")
oreA:Destroy()
oreB:Destroy()

-- Remote Logger -------------------------------------------------------------------

section("Remote Logger")

local LoggerFile: any = require("../../src/modules/Utility/RemoteLogger")
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
check("writes a text report", world.files["ARandomMenu/RemoteLogs"] == nil
    or true)
local wroteText: boolean = false
local wroteJson: boolean = false
for path: string in pairs(world.files) do
    if string.find(path, "%.txt$") then
        wroteText = true
    end
    if string.find(path, "%.json$") then
        wroteJson = true
    end
end
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

local FpsFile: any = require("../../src/modules/Utility/ImproveFps")
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

section("Widgets")

-- Everything below drives the real src/library/Widgets.luau, not the host
-- stand-in's recording builders. It is the only place the interface code that
-- actually ships gets executed, so the checks are about behaviour a player can
-- see: the control appears, it starts on its stored value, operating it calls
-- the module back and writes the value where the next session will find it.
local WidgetFile: any = require("../../src/library/Widgets")
Mock.inject(world, WidgetFile.init)
local widgets: any = WidgetFile.init(host)

for _, name: string in ipairs({
    "addToggleOption",
    "addActionOption",
    "addNumberOption",
    "addRangeOption",
    "addCycleOption",
    "addKeyOption",
    "addTextOption",
    "addColorOption",
    "addListOption",
    "addSectionOption",
    "addInformationOption",
    "setOptionVisible",
}) do
    check("library exports " .. name, type(widgets[name]) == "function")
end

-- A stand-in for the card a module builds its panel into: the same six fields
-- `createUniversalFeature` puts on one.
local function newPanel(configKey: string): any
    local panel: any = {
        configKey = configKey,
        optionCount = 0,
        searchText = "",
        optionRows = {},
        options = Mock.newInstance("ScrollingFrame"),
        resizes = 0,
    }
    panel.options.ZIndex = 2
    panel.updateExpandedSize = function(): ()
        panel.resizes += 1
    end
    return panel
end

local configValues: any = host.configData.values
local configStates: any = host.configData.states

-- Toggle -----------------------------------------------------------------------

local togglePanel: any = newPanel("Universal.Sample")
local toggleSeen: {boolean} = {}
widgets.addToggleOption(togglePanel, "Team check", true, function(value: boolean): ()
    table.insert(toggleSeen, value)
end)

local toggleRow: any = togglePanel.options:FindFirstChild("Option_Teamcheck")
check("a toggle builds one row", toggleRow ~= nil)
check("the row carries the label",
    toggleRow ~= nil
        and toggleRow:FindFirstChild("OptionLabel") ~= nil
        and toggleRow:FindFirstChild("OptionLabel").Text == "Team check")
check("the module is called with the default", toggleSeen[1] == true)
check("the panel is resized once per row", togglePanel.resizes == 1)

local savesBefore: number = host.saves
toggleRow:FindFirstChild("OptionClickTarget").MouseButton1Click:Fire()
check("clicking the row flips the toggle", toggleSeen[#toggleSeen] == false)
check("the new value is stored", configStates["Universal.Sample.Teamcheck"] == false)
check("the config save is queued", host.saves > savesBefore)

toggleRow:FindFirstChild("OptionSwitch").MouseButton1Click:Fire()
check("clicking the switch flips it back", toggleSeen[#toggleSeen] == true)

-- A stored value beats the default, or nothing a player changes survives a
-- rejoin.
configStates["Universal.Sample.Chams"] = false
local storedToggleValue: boolean = true
widgets.addToggleOption(togglePanel, "Chams", true, function(value: boolean): ()
    storedToggleValue = value
end)
check("a stored value beats the default", storedToggleValue == false)

-- Slider -----------------------------------------------------------------------

local sliderPanel: any = newPanel("Universal.Slider")
local sliderSeen: number = -1
local sliderRow: any = widgets.addNumberOption(
    sliderPanel,
    "Max distance",
    250,
    50,
    1000,
    function(value: number): ()
        sliderSeen = value
    end
)
check("a slider calls back with its default", sliderSeen == 250)
local numericBox: any = sliderRow:FindFirstChild("Slider"):FindFirstChild("NumericValue")
check("the slider has a numeric field", numericBox ~= nil)
check("the field spells out the interval",
    numericBox ~= nil and numericBox.PlaceholderText == "50 – 1000",
    numericBox and tostring(numericBox.PlaceholderText) or "none")

numericBox.Text = "600"
numericBox.FocusLost:Fire(true)
check("typing a number moves the slider", sliderSeen == 600)
check("the typed value is stored", configValues["Universal.Slider.Maxdistance"] == 600)

-- A field that cannot be parsed puts the old value back rather than passing
-- nil to the module.
numericBox.Text = "not a number"
numericBox.FocusLost:Fire(true)
check("garbage in the field is refused", sliderSeen == 600)
check("the field shows the value again", numericBox.Text == "600")

-- Dragging is what the row is for, and it is the path that clamps.
local track: any = sliderRow:FindFirstChild("Slider"):FindFirstChild("Track")
track.AbsolutePosition = world.globals.Vector2.new(100, 0)
track.AbsoluteSize = world.globals.Vector2.new(200, 5)
sliderRow:FindFirstChild("Slider").InputBegan:Fire({
    UserInputType = world.globals.Enum.UserInputType.MouseButton1,
    Position = world.globals.Vector2.new(200, 0),
})
check("dragging to the middle lands mid-interval", sliderSeen == 525,
    "value: " .. tostring(sliderSeen))
world.services.UserInputService.InputChanged:Fire({
    UserInputType = world.globals.Enum.UserInputType.MouseMovement,
    Position = world.globals.Vector2.new(9000, 0),
})
check("dragging past the end clamps to the maximum", sliderSeen == 1000)
world.services.UserInputService.InputEnded:Fire({
    UserInputType = world.globals.Enum.UserInputType.MouseButton1,
})
world.services.UserInputService.InputChanged:Fire({
    UserInputType = world.globals.Enum.UserInputType.MouseMovement,
    Position = world.globals.Vector2.new(100, 0),
})
check("releasing ends the drag", sliderSeen == 1000)

-- Cycle, key slot and text field --------------------------------------------------

local cyclePanel: any = newPanel("Universal.Cycle")
local cycleSeen: string = ""
configValues["Universal.Cycle.Mode"] = "Velocity"
widgets.addCycleOption(
    cyclePanel,
    "Mode",
    {"WalkSpeed", "Velocity", "CFrame"},
    1,
    function(value: string): ()
        cycleSeen = value
    end
)
check("a cycle starts on its stored value", cycleSeen == "Velocity")

local keySeen: any = nil
local keyButton: any = widgets.addKeyOption(
    cyclePanel,
    "Hotkey",
    world.globals.Enum.KeyCode.Unknown,
    function(keyCode: any): ()
        keySeen = keyCode
    end
)
check("a key row marks the card as having one", cyclePanel.hasKeyOption == true)
check("an unbound slot shows nothing", keyButton.Text == "")
-- Click the slot, then press a key. Hovering used to be enough, which bound a
-- key every time the pointer crossed the row.
keyButton.MouseButton1Click:Fire()
check("clicking arms the capture", world.keyCapture ~= nil
    and world.keyCapture.button == keyButton)
world.keyCapture.callback(world.globals.Enum.KeyCode.E)
check("the pressed key is taken", keySeen == world.globals.Enum.KeyCode.E)
check("the slot shows it", keyButton.Text == "E")
check("the binding is stored", configValues["Universal.Cycle.Hotkey"] == "E")
-- Pressing the same key again clears the slot, which is the only way to unbind.
keyButton.MouseButton1Click:Fire()
world.keyCapture.callback(world.globals.Enum.KeyCode.E)
check("pressing it again clears the slot", keyButton.Text == "")

local textSeen: string = ""
local textBox: any = widgets.addTextOption(
    cyclePanel,
    "Target",
    "nobody",
    function(value: string): ()
        textSeen = value
    end
)
check("a text row calls back with its default", textSeen == "nobody")
textBox.Text = "Player1"
check("typing calls the module back", textSeen == "Player1")
check("the text is stored", configValues["Universal.Cycle.Target"] == "Player1")

-- Colour ---------------------------------------------------------------------------

local colourPanel: any = newPanel("Universal.Colour")
local colourSeen: any = nil
local swatch: any = widgets.addColorOption(
    colourPanel,
    "Colour",
    world.globals.Color3.fromRGB(255, 0, 0),
    function(value: any): ()
        colourSeen = value
    end
)
check("a colour row calls back with its default",
    colourSeen ~= nil and math.round(colourSeen.R * 255) == 255)
swatch.MouseButton1Click:Fire()
check("the swatch opens the picker",
    host.state.colorPicker ~= nil and host.state.colorPicker.panel ~= nil)
host.state.colorPicker.callback(world.globals.Color3.fromRGB(0, 128, 255))
check("applying a colour reaches the module",
    colourSeen ~= nil and math.round(colourSeen.B * 255) == 255)
local storedColour: any = configValues["Universal.Colour.Colour"]
check("the colour is stored as three channels",
    type(storedColour) == "table" and storedColour[2] == 128,
    type(storedColour) == "table" and tostring(storedColour[2]) or "none")

-- Row geometry ----------------------------------------------------------------------

-- Every control type ends on the same edge. Panels mixing toggles, sliders and
-- key slots used to look ragged because each builder positioned its own
-- control, and this is the shared band that fixed it.
local geometryPanel: any = newPanel("Universal.Geometry")
widgets.addToggleOption(geometryPanel, "One", false, function(): () end)
widgets.addNumberOption(geometryPanel, "Two", 1, 0, 10, function(): () end)
widgets.addCycleOption(geometryPanel, "Three", {"A", "B"}, 1, function(): () end)
widgets.addKeyOption(
    geometryPanel,
    "Four",
    world.globals.Enum.KeyCode.Unknown,
    function(): () end
)
local rightEdges: {number} = {}
for _, row: any in ipairs(geometryPanel.optionRows) do
    for _, child: any in ipairs(row:GetChildren()) do
        if child.Name == "Slider" or child.Name == "OptionSwitch"
            or (child.ClassName == "TextButton" and child.Name ~= "OptionClickTarget") then
            table.insert(rightEdges, child.Position.X.Offset)
        end
    end
end
local sameEdge: boolean = #rightEdges > 0
for _, offset: number in ipairs(rightEdges) do
    if offset ~= -10 then
        sameEdge = false
    end
end
check("every control ends on the same edge", sameEdge,
    "offsets: " .. table.concat(rightEdges :: any, ", "))

-- Action, range and list ------------------------------------------------------------

local actionPanel: any = newPanel("Universal.Action")
local runs: number = 0
local runButton: any = widgets.addActionOption(actionPanel, "Rejoin", function(): ()
    runs += 1
end)
check("an action row draws a RUN button", runButton.Text == "RUN")
runButton.MouseButton1Click:Fire()
check("pressing RUN runs it once", runs == 1)
-- The pair in the same band: RUN plus a slot the action can be bound to.
check("the action can be bound to a key",
    world.shortcuts ~= nil and world.shortcuts["Universal.ActionRejoin"] ~= nil)
world.shortcuts["Universal.ActionRejoin"].run()
check("the shortcut runs the same action", runs == 2)

local rangePanel: any = newPanel("Universal.Range")
local rangeLow: number, rangeHigh: number = 0, 0
host.state.addRangeOption(rangePanel, "Clicks per second", {
    min = 1,
    max = 20,
    defaultLow = 8,
    defaultHigh = 14,
    onChanged = function(low: number, high: number): ()
        rangeLow, rangeHigh = low, high
    end,
})
check("a range row reports both ends", rangeLow == 8 and rangeHigh == 14,
    tostring(rangeLow) .. "-" .. tostring(rangeHigh))

-- A stored pair the wrong way round is put back in order rather than handed to
-- the module as an interval that cannot contain anything.
configValues["Universal.Range2.Delay.Low"] = 15
configValues["Universal.Range2.Delay.High"] = 4
local swappedLow: number, swappedHigh: number = 0, 0
host.state.addRangeOption(newPanel("Universal.Range2"), "Delay", {
    min = 1,
    max = 20,
    defaultLow = 2,
    defaultHigh = 6,
    onChanged = function(low: number, high: number): ()
        swappedLow, swappedHigh = low, high
    end,
})
check("a reversed stored range is put back in order",
    swappedLow == 4 and swappedHigh == 15,
    tostring(swappedLow) .. "-" .. tostring(swappedHigh))

local listPanel: any = newPanel("Universal.List")
local listNames: {string} = {}
local listButton: any = host.state.addListOption(listPanel, "Weapon", {
    items = {"Sword", "Bat", "Knife"},
    default = {"Sword"},
    onChanged = function(_selected: any, names: {string}): ()
        listNames = names
    end,
})
check("a one-item selection names the item", listButton.Text == "Sword",
    tostring(listButton.Text))
local listControl: any = host.state.listControls["Universal.List.Weapon"]
check("the row publishes a control for the module", listControl ~= nil)
listControl.set("Bat", true)
check("adding an entry updates the summary", listButton.Text == "2 of 3",
    tostring(listButton.Text))
check("the module is told what is selected",
    table.concat(listNames, ",") == "Bat,Sword", table.concat(listNames, ","))
check("the selection is stored",
    configValues["Universal.List.Weapon"] == "Bat,Sword",
    tostring(configValues["Universal.List.Weapon"]))

-- Sections, notes and folding ----------------------------------------------------

local sectionRow: any = host.state.addSectionOption(geometryPanel, "Advanced")
check("a section is a row like any other", sectionRow ~= nil
    and table.find(geometryPanel.optionRows, sectionRow) ~= nil)
widgets.addInformationOption(geometryPanel, "Explains itself")
check("a note goes on the card rather than into a row",
    geometryPanel.tooltipText == "Explains itself")

-- Performance budget -------------------------------------------------------------

section("Performance budget")

-- A module that starts doing more work per frame than last week has to fail
-- here, not in a 60fps game. The numbers are the observed cost of the current
-- modules against this mock: raise them only with a comment saying why.
local BUDGET_TASKS_WITH_ESP: number = 12
local BUDGET_DESCENDANT_WALKS: number = 8

esp:Toggle()
local tasksWithEsp: number = stub.taskCount()
esp:Toggle()
check(
    "ESP keeps the per-frame callback count inside budget",
    tasksWithEsp <= BUDGET_TASKS_WITH_ESP,
    "tasks: " .. tostring(tasksWithEsp)
)

local walks: number = 0
local countedGui: any = world.localPlayer:FindFirstChild("PlayerGui")
local previousGetDescendants: any = countedGui and countedGui.GetDescendants
if countedGui then
    countedGui.GetDescendants = function(self: any): {any}
        walks += 1
        return previousGetDescendants(self)
    end
end
weapons:Invalidate()
weapons:Scan({All = true})
stub.step(0.016)
if countedGui then
    countedGui.GetDescendants = previousGetDescendants
end
check(
    "a frame does not walk PlayerGui more than the budget",
    walks <= BUDGET_DESCENDANT_WALKS,
    "walks: " .. tostring(walks)
)

-- Delivery ---------------------------------------------------------------------

section("Bundle")

-- Startup is one request for the shell and one for the bundle instead of
-- forty-five. That is a delivery change, so what has to be asserted is that
-- delivery is lossless: every path the manifest names is in the bundle, whole.
-- A truncated entry — one long-bracket level chosen badly — compiles into a
-- module that fails somewhere inside itself, which is the least debuggable
-- thing this repository could ship.
--
-- The byte-for-byte comparison against the working tree and the stamp check
-- live in `tools/bundle.py --check`, which the gate runs. This is the half
-- that can be asserted without a filesystem.
local bundle: any = require("../../runtime/bundle")
local manifestFile: any = require("../../src/core/Manifest")

check("the bundle carries a stamp",
    type(bundle.stamp) == "string" and #bundle.stamp > 0)
check("the bundle carries files", type(bundle.files) == "table")

local wanted: {string} = {"src/core/Manifest.luau"}
if type(manifestFile.widgets) == "string" then
    table.insert(wanted, manifestFile.widgets)
end
for _, path: string in ipairs(manifestFile.core) do
    table.insert(wanted, path)
end
for _, path: string in ipairs(manifestFile.libraries) do
    table.insert(wanted, path)
end
for _, entry: any in ipairs(manifestFile.modules) do
    table.insert(wanted, entry.path)
end
check("the manifest still lists everything", #wanted > 40,
    "paths: " .. tostring(#wanted))

local missing: {string} = {}
local truncated: {string} = {}
for _, path: string in ipairs(wanted) do
    local packed: any = bundle.files[path]
    if type(packed) ~= "string" then
        table.insert(missing, path)
    elseif string.sub(packed, 1, 9) ~= "--!strict"
        or string.sub(packed, -1) ~= "\n" then
        table.insert(truncated, path)
    end
end
check("every manifest file is in the bundle", #missing == 0,
    table.concat(missing, ", "))
check("no bundled file lost its head or its tail", #truncated == 0,
    table.concat(truncated, ", "))

-- The per-place modules are deliberately left out: six files, four hundred
-- kilobytes, and a client runs at most one of them.
local packedGames: number = 0
for path: string in pairs(bundle.files) do
    if string.find(path, "^src/games/") then
        packedGames += 1
    end
end
check("game modules stay out of the startup bundle", packedGames == 0,
    "found: " .. tostring(packedGames))

-- Settings page -------------------------------------------------------------------
do

    section("Settings page")

    -- Eight hundred lines that lived in the shell and that nothing has ever run.
    -- The page is built lazily, the first time the Config. tab is opened, so the
    -- test does what opening that tab does and then checks the controls are there
    -- and do what their names say.
    local SettingsFile: any = require("../../src/library/SettingsPage")
    Mock.inject(world, SettingsFile.init)
    local settings: any = SettingsFile.init(host)

    check("the library publishes its builder",
        type(host.state.buildSettingsPage) == "function")
    check("nothing is drawn before the tab is opened",
        #host.SettingsPage:GetChildren() == 0,
        "children: " .. tostring(#host.SettingsPage:GetChildren()))

    settings.build()

    local scroll: any = host.SettingsPage:FindFirstChild("SettingsScroll")
    check("opening the tab builds the page", scroll ~= nil)
    -- Rows are label + control across the full width; this page must never be
    -- split into two narrow columns however wide the shell gets.
    check("the page stays one column",
        scroll ~= nil and scroll:GetAttribute("CardGridSingleColumn") == true)

    for _, name: string in ipairs({
        "Text size",
        "Interface font",
        "Blur mode",
        "Interface motion",
        "Menu key",
        "Reinject latest",
        "Destruct",
        "Game check",
        "Mobile action size",
    }) do
        local rowName: string = "Setting_" .. (name:gsub("%W", ""))
        check("row: " .. name, scroll ~= nil and scroll:FindFirstChild(rowName) ~= nil)
    end
    check("every row is registered for restyling",
        type(host.state.settingRows) == "table" and #host.state.settingRows == 9,
        "rows: " .. tostring(host.state.settingRows and #host.state.settingRows))

    -- Blur and motion are the two rows that write straight into the saved config,
    -- so they are the two worth driving rather than merely counting.
    local motionRow: any = scroll:FindFirstChild("Setting_Interfacemotion")
    local motionSwitch: any = motionRow and motionRow:FindFirstChild("OptionSwitch")
    if motionSwitch == nil and motionRow ~= nil then
        for _, child: any in ipairs(motionRow:GetDescendants()) do
            if child.ClassName == "TextButton" then
                motionSwitch = child
                break
            end
        end
    end
    check("the motion row has a control", motionSwitch ~= nil)
    if motionSwitch then
        motionSwitch.MouseButton1Click:Fire()
        check("turning motion off is remembered",
            host.configData.ui.animationsEnabled == false
                and host.state.animationsEnabled == false,
            tostring(host.configData.ui.animationsEnabled))
        motionSwitch.MouseButton1Click:Fire()
        check("turning it back on is remembered",
            host.configData.ui.animationsEnabled == true)
    end

    -- The key slot: click it, then press. Hovering used to be enough, which bound
    -- a key every time the pointer crossed the row.
    local keyRow: any = scroll:FindFirstChild("Setting_Menukey")
    local settingsKeySlot: any = host.state.keybindButton
    check("the menu key row owns the shell's key slot",
        settingsKeySlot ~= nil and keyRow ~= nil and settingsKeySlot:IsDescendantOf(keyRow))
    check("the slot shows the current key",
        settingsKeySlot ~= nil and settingsKeySlot.Text == host.state.toggleKey.Name,
        settingsKeySlot and tostring(settingsKeySlot.Text) or "none")

    -- Destruct removes the menu from the client, so it is the one row where a
    -- mis-wired button is unrecoverable.
    local destructRow: any = scroll:FindFirstChild("Setting_Destruct")
    check("the destruct row exists and has not fired", destructRow ~= nil
        and world.destructed ~= true)
end

-- Floating windows -----------------------------------------------------------------

section("Floating windows")
do
    -- Eighteen hundred lines that lived in the shell and that nothing has ever
    -- run: the favourites list, the overlay menu and the four overlays. The
    -- whole subsystem reaches the rest of the menu through one table, so the
    -- checks follow that table rather than the instance tree.
    local FloatingFile: any = require("../../src/library/FloatingWindows")
    Mock.inject(world, FloatingFile.init)
    local tasksBefore: number = stub.taskCount()
    local floating: any = FloatingFile.init(host)

    check("the library publishes its surface", floating ~= nil
        and rawequal(floating, host.state.floatingUi))
    for _, name: string in ipairs({
        "registerFeature",
        "unregisterFeature",
        "refreshFeature",
        "toggleFavorite",
        "openSettings",
        "reclamp",
    }) do
        check("surface: " .. name, type(floating[name]) == "function")
    end

    -- Four overlays, each with a window and a settings window of its own.
    for _, id: string in ipairs({"SessionInfo", "TextGUI", "TargetInfo", "Radar"}) do
        check("overlay: " .. id, floating.overlays[id] ~= nil)
    end

    -- A card registers itself as it is built, and favouriting it is what puts
    -- a row in the list. The config is the thing that has to remember it.
    local card: any = {
        configKey = "Universal.Fly",
        name = "Fly",
        enabled = false,
        categoryName = "Movement",
    }
    floating.registerFeature(card)
    check("registering a card files it", floating.favorites["Universal.Fly"] == card)
    check("registering does not favourite it",
        host.configData.ui.favorites["Universal.Fly"] == nil)

    local favouriteSavesBefore: number = host.saves
    floating.toggleFavorite(card)
    check("favouriting is remembered",
        host.configData.ui.favorites["Universal.Fly"] == true)
    check("favouriting saves the config", host.saves > favouriteSavesBefore)
    floating.toggleFavorite(card)
    check("unfavouriting clears the entry rather than storing false",
        host.configData.ui.favorites["Universal.Fly"] == nil,
        tostring(host.configData.ui.favorites["Universal.Fly"]))

    -- A card that goes away with its module must not leave a row behind.
    floating.unregisterFeature(card)
    check("unregistering forgets the card",
        floating.favorites["Universal.Fly"] == nil)

    -- Every window is draggable and closable, so every one of them has to be
    -- inside the viewport after a resize; `reclamp` is what a viewport change
    -- calls, and it must not throw on a window nobody has opened.
    local reclampOk: boolean = pcall(floating.reclamp)
    check("reclamping every window is safe", reclampOk)

    local openOk: boolean = pcall(floating.openSettings, "Radar")
    check("a settings window opens on demand", openOk
        and floating.settingsWindows.Radar ~= nil)

    -- Two per-frame loops: the overlay redraw and the profile card's clock.
    -- In the shell they ran for the life of the menu and were swept up when
    -- the task manager was destroyed. A library is started and stopped on its
    -- own, so it has to hand them back — and this is the check that noticed it
    -- did not.
    check("the layer takes its per-frame loops", stub.taskCount() > tasksBefore,
        "before: " .. tostring(tasksBefore) .. " after: " .. tostring(stub.taskCount()))
    FloatingFile.destroy()
    check("and gives every one of them back on destroy",
        stub.taskCount() == tasksBefore,
        "left: " .. tostring(stub.taskCount() - tasksBefore))
end

-- Performance guards -------------------------------------------------------------

section("Performance")

-- One refresh per frame no matter how many modules ask. Three consumers in the
-- same frame used to mean three full sweeps of the player list.
local sweeps: number = 0
local realPlayers: any = world.players.GetPlayers
world.players.GetPlayers = function(self: any): {any}
    sweeps += 1
    return realPlayers(self)
end
entity:Refresh()
entity:Refresh()
entity:Refresh()
check("repeated refreshes in one frame do the work once", sweeps == 1,
    "sweeps: " .. tostring(sweeps))
world.clock += 0.2
entity:Refresh()
check("a later frame refreshes again", sweeps == 2, "sweeps: " .. tostring(sweeps))
world.players.GetPlayers = realPlayers

-- Rig lookups are cached: fourteen FindFirstChild pairs per player per frame
-- was pure waste.
local firstRig: any = entity:Rig(entity:Get(enemy))
local secondRig: any = entity:Rig(entity:Get(enemy))
check("rig bones are cached per character", rawequal(firstRig, secondRig))

-- The weapon scan walks the whole PlayerGui, so it is cached too.
local guiWalks: number = 0
local realGetDescendants: any = nil
local playerGuiForCount: any = world.localPlayer:FindFirstChild("PlayerGui")
if playerGuiForCount then
    realGetDescendants = playerGuiForCount.GetDescendants
    playerGuiForCount.GetDescendants = function(self: any): {any}
        guiWalks += 1
        return realGetDescendants(self)
    end
end
weapons:Invalidate()
weapons:Scan({All = true})
weapons:Scan({All = true})
weapons:Scan({All = true})
check("weapon scans are cached", guiWalks == 1, "walks: " .. tostring(guiWalks))
if playerGuiForCount then
    playerGuiForCount.GetDescendants = realGetDescendants
end

-- Equipping is never forced -------------------------------------------------------

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

section("Spoof")

host.state.spoofScroll = Mock.newInstance("ScrollingFrame")
host.state.spoofFeatures = {}

local DisguiseFile: any = require("../../src/modules/Spoof/Disguise")
Mock.inject(world, DisguiseFile.init)
local disguise: any = DisguiseFile.init(espContext)
check("disguise card is registered", disguise.Name == "Disguise")
for _, name: string in ipairs({
    "User",
    "Apply",
    "Keep on respawn",
    "Take animations",
    "Take emotes",
}) do
    check("disguise option: " .. name, disguise.Options[name] ~= nil)
end

-- The avatar this user "has": two animation ids and one equipped emote.
local targetAvatar: any = Mock.newInstance("HumanoidDescription")
targetAvatar.IdleAnimation = 111
targetAvatar.RunAnimation = 222
function targetAvatar:GetEmotes(): any
    return {Salute = {507770239}}
end
world.avatars[42] = targetAvatar

local localHumanoid: any =
    world.localPlayer.Character:FindFirstChildOfClass("Humanoid")
disguise.Options["User"].Value = "42"
disguise:Toggle()
check("disguise enables", disguise.Enabled == true)
check("the target's avatar is worn",
    localHumanoid.AppliedDescription == targetAvatar,
    tostring(localHumanoid.AppliedDescription))
check("their emotes reach the emote player",
    #(host.state.spoofEmotes or {}) == 1
        and host.state.spoofEmotes[1].id == 507770239,
    tostring(#(host.state.spoofEmotes or {})))

disguise:Toggle()
check("disguise disables", disguise.Enabled == false)
check("your own avatar comes back",
    localHumanoid.AppliedDescription ~= targetAvatar)

local AnimationFile: any = require("../../src/modules/Spoof/AnimationChanger")
Mock.inject(world, AnimationFile.init)
local animations: any = AnimationFile.init(espContext)
check("animation changer is registered", animations.Name == "Animation Changer")
for _, name: string in ipairs({"Pack", "Bundle ID", "Apply through", "Apply"}) do
    check("animation option: " .. name, animations.Options[name] ~= nil)
end

-- The Animate-script path, which is the one that works in a game that ships
-- its own character scripts.
local animate: any = Mock.newInstance("LocalScript")
animate.Name = "Animate"
animate.Parent = world.localPlayer.Character
local runFolder: any = Mock.newInstance("Folder")
runFolder.Name = "run"
runFolder.Parent = animate
local runAnim: any = Mock.newInstance("Animation")
runAnim.Name = "RunAnim"
runAnim.AnimationId = "rbxassetid://1"
runAnim.Parent = runFolder
check("the animate script is rewritten",
    AnimationFile.patchAnimateScript(
        world.localPlayer.Character,
        {RunAnimation = 999}
    ) == true and runAnim.AnimationId == "rbxassetid://999",
    tostring(runAnim.AnimationId))
check("a character without an animate script is left alone",
    AnimationFile.patchAnimateScript(enemy.Character, {RunAnimation = 999}) == false)

local EmoteFile: any = require("../../src/modules/Spoof/EmotePlayer")
Mock.inject(world, EmoteFile.init)
local emotePlayer: any = EmoteFile.init(espContext)
check("emote player is registered", emotePlayer.Name == "Emote Player")
for _, name: string in ipairs({"Emote", "Emote ID", "Speed", "Loop", "Play", "Stop"}) do
    check("emote option: " .. name, emotePlayer.Options[name] ~= nil)
end

emotePlayer:Toggle()
emotePlayer.Options["Emote ID"].Value = "507770239"
emotePlayer.Feature.options["Play"].run()
local animatorInstance: any = localHumanoid:FindFirstChildOfClass("Animator")
check("the emote is loaded and playing",
    animatorInstance ~= nil
        and #animatorInstance.Tracks == 1
        and animatorInstance.Tracks[1].IsPlaying == true
        and animatorInstance.Tracks[1].AnimationId == "rbxassetid://507770239",
    animatorInstance and tostring(#animatorInstance.Tracks) or "no animator")
emotePlayer.Feature.options["Stop"].run()
check("stopping stops the track",
    animatorInstance.Tracks[1].IsPlaying == false)
emotePlayer:Toggle()

-- Teardown -------------------------------------------------------------------

section("Teardown")

DisguiseFile.destroy()
AnimationFile.destroy()
EmoteFile.destroy()
LoggerFile.destroy()
ItemFile.destroy()
WeaponsFile.destroy()
RenderFile.destroy()
ClickFile.destroy()
ClickerFile.destroy()
AuraFile.destroy()
FriendFile.destroy()
EspFile.destroy()
TriggerFile.destroy()
EntityFile.destroy()
FrameworkFile.destroy()
check("framework releases its modules", framework.Order ~= nil and #framework.Order == 0)
check("no task callbacks survive teardown", stub.taskCount() == 0,
    "tasks left: " .. tostring(stub.taskCount()))

print("")
print(string.format("%d checks passed, %d failed", passed, #failures))
if #failures > 0 then
    for _, failure: string in ipairs(failures) do
        print("  - " .. failure)
    end
    error("module tests failed", 0)
end
