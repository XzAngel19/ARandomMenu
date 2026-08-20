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

-- Teardown -------------------------------------------------------------------

section("Teardown")

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
