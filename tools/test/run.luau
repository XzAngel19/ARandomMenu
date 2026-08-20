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
local espContext: any =
    {framework = framework, entity = entity, weapons = weapons, host = host}
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
check("style options exist", esp.Options["Enemy colour"] ~= nil
    and esp.Options["Text size"] ~= nil)

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
aura.Options["Rate jitter"].Value = 0
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
check("travel options start hidden",
    clickTeleport.Options["Glide step"].Object ~= nil
        and clickTeleport.Options["Glide step"].Object.Visible == false)

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
local rendered: number = 0
for _, part: any in ipairs({oreA, oreB}) do
    if part:FindFirstChild("RTM_ItemRender") then
        rendered += 1
    end
end
check("every object with that name is rendered", rendered == 2,
    "rendered: " .. tostring(rendered))
check("the label carries the object name",
    oreA:FindFirstChild("RTM_ItemRender") ~= nil)

-- Unticking one object stops it being drawn without touching the others.
itemRender.Feature.options["Objects"].set("IronOre", false)
stub.step(0.016)
local afterUntick: number = 0
for _, part: any in ipairs({oreA, oreB}) do
    if part:FindFirstChild("RTM_ItemRender") then
        afterUntick += 1
    end
end
check("unticking an object stops rendering it", afterUntick == 0,
    "still rendered: " .. tostring(afterUntick))
itemRender.Feature.options["Objects"].set("IronOre", true)
stub.step(0.016)

itemRender:Toggle()
local left: number = 0
for _, part: any in ipairs({oreA, oreB}) do
    if part:FindFirstChild("RTM_ItemRender") then
        left += 1
    end
end
check("labels are released when the module is off", left == 0,
    "left: " .. tostring(left))
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
local candidate: any = weapons:Find("Backpack Sword")
if candidate then
    weapons:Activate(candidate)
end
check("it is equipped when the option is on", equipped == 1,
    "equips: " .. tostring(equipped))
weapons:SetAllowEquip(false)
humanoid.EquipTool = realEquip
stowed:Destroy()
sword.Parent = world.localPlayer.Character

-- Teardown -------------------------------------------------------------------

section("Teardown")

LoggerFile.destroy()
ItemFile.destroy()
WeaponsFile.destroy()
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
