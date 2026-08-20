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
entity:Refresh()

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
local espContext: any = {framework = framework, entity = entity, host = host}
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
esp.Options["Skeleton"].Value = true
esp.Options["Boxes"].Value = "Full"
esp.Options["Chams"].Value = "Overlay"
stub.step(0.016)

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
stub.step(0.016)
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
check("delay option exists", trigger.Options["Delay"] ~= nil)
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
trigger.Options["Delay"].Value = 0.1
trigger.Options["Delay jitter"].Value = 0
trigger.Options["Aim radius"].Value = 0

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
    "Minimum CPS",
    "Maximum CPS",
    "Activation",
    "Hold key",
    "Press",
    "Button name",
    "Require tool",
}) do
    check("option: " .. name, clicker.Options[name] ~= nil)
end

-- Tool mode: presses whatever is equipped, at the configured rate.
clicker.Options["Press"].Value = "Tool"
clicker.Options["Minimum CPS"].Value = 10
clicker.Options["Maximum CPS"].Value = 10
local toolBefore: number = sword.Activations or 0
clicker:Toggle()
world.clock += 1
stub.step(0.016)
check("presses the equipped tool", (sword.Activations or 0) > toolBefore,
    "activations: " .. tostring(sword.Activations))

local rateBefore: number = sword.Activations or 0
stub.step(0.016)
check("respects the click rate", (sword.Activations or 0) == rateBefore)

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

clicker.Options["Press"].Value = "Screen button"
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

-- Teardown -------------------------------------------------------------------

section("Teardown")

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
