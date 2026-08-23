--!strict
--
-- Focused lifecycle and target-policy tests for the five expansion modules.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local context: any = ctx.espContext
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local enemy: any = ctx.enemy
    local ally: any = ctx.ally

    section("Chams ownership")

    local oldModeKey: string = "Universal.PlayerESP.Chams"
    local newEnabledKey: string = "Universal.Chams"
    local fillKey: string = "Universal.Chams.Filltransparency"
    host.configData.values[oldModeKey] = "Outline"
    host.configData.states[newEnabledKey] = nil
    host.configData.values[fillKey] = nil

    local ChamsFile: any = require("../../../src/modules/Visuals/Chams")
    Mock.inject(world, ChamsFile.init)
    local chams: any = ChamsFile.init(context)
    check("old PlayerESP Chams enables the standalone owner",
        host.configData.states[newEnabledKey] == true)
    check("Outline migrates without becoming a filled overlay",
        host.configData.values[fillKey] == 1)
    if not chams.Enabled then chams:Toggle(true) end
    stub.step(0.02)
    local function hasChamFor(character: any): boolean
        for _, child: any in ipairs(world.workspace:GetChildren()) do
            if child:IsA("Highlight")
                and child.Name == "Wurst_Chams"
                and child.Adornee == character then
                return true
            end
        end
        return false
    end
    check("one live enemy receives a Highlight", hasChamFor(enemy.Character))
    check("teammates are excluded by default", not hasChamFor(ally.Character))
    host.services.protectedTargets.setProvider(function(player: any): boolean
        return player == enemy
    end)
    stub.step(0.02)
    check("Friend List protection removes an existing Highlight",
        not hasChamFor(enemy.Character))
    host.services.protectedTargets.setProvider(nil)
    stub.step(0.02)

    local enemyHumanoid: any = enemy.Character:FindFirstChildOfClass("Humanoid")
    enemyHumanoid.Health = 0
    stub.step(0.02)
    check("dead players lose their Highlight immediately",
        not hasChamFor(enemy.Character))
    enemyHumanoid.Health = 100
    chams:Toggle(false)
    check("disable destroys every standalone Highlight",
        world.workspace:FindFirstChild("Wurst_Chams") == nil)
    ChamsFile.destroy()
    host.configData.values[oldModeKey] = nil
    host.configData.states[newEnabledKey] = nil
    host.configData.values[fillKey] = nil

    section("Arrows target policy")

    local camera: any = world.workspace.CurrentCamera
    local originalProjection: any = camera.WorldToViewportPoint
    camera.WorldToViewportPoint = function(_self: any, _position: any): (any, boolean)
        return world.vector3(1200, 360, 10), false
    end
    local ArrowsFile: any = require("../../../src/modules/Visuals/Arrows")
    Mock.inject(world, ArrowsFile.init)
    local arrows: any = ArrowsFile.init(context)
    arrows:Toggle(true)
    stub.step(0.02)
    local arrowsLayer: any = host.ScreenGui:FindFirstChild("ArrowsLayer")
    check("an off-screen enemy gets an arrow",
        arrowsLayer and arrowsLayer:FindFirstChild(enemy.Name) ~= nil)
    host.services.protectedTargets.setProvider(function(player: any): boolean
        return player == enemy
    end)
    stub.step(0.02)
    check("a protected player loses its arrow",
        arrowsLayer and arrowsLayer:FindFirstChild(enemy.Name) == nil)
    host.services.protectedTargets.setProvider(nil)
    stub.step(0.02)
    check("a teammate gets no arrow by default",
        arrowsLayer and arrowsLayer:FindFirstChild(ally.Name) == nil)
    enemyHumanoid.Health = 0
    stub.step(0.02)
    check("a dead target releases its render set",
        arrowsLayer and arrowsLayer:FindFirstChild(enemy.Name) == nil)
    enemyHumanoid.Health = 100
    arrows:Toggle(false)
    check("disable releases all arrow render sets",
        arrowsLayer and #arrowsLayer:GetChildren() == 0)
    ArrowsFile.destroy()
    camera.WorldToViewportPoint = originalProjection

    section("NPCESP streaming")

    local function npc(name: string, position: any): any
        local model: any = Mock.newInstance("Model")
        model.Name = name
        local humanoid: any = Mock.newInstance("Humanoid")
        humanoid.Name = "Humanoid"
        humanoid.Health = 100
        humanoid.MaxHealth = 100
        humanoid.Parent = model
        local root: any = Mock.newInstance("Part")
        root.Name = "HumanoidRootPart"
        root.Position = position
        root.CFrame = world.globals.CFrame.new(position)
        root.Parent = model
        model.PrimaryPart = root
        return model, humanoid
    end

    local firstNpc: any, firstNpcHumanoid: any = npc("TrainingDummy", world.vector3(0, 0, -20))
    firstNpc.Parent = world.workspace
    local NpcFile: any = require("../../../src/modules/Visuals/NPCESP")
    Mock.inject(world, NpcFile.init)
    local npcEsp: any = NpcFile.init(context)
    npcEsp:Toggle(true)
    stub.step(0.02)
    local npcLayer: any = host.ScreenGui:FindFirstChild("NpcEspLayer")
    check("a non-player Humanoid model is classified as an NPC",
        npcLayer and npcLayer:FindFirstChild("TrainingDummy") ~= nil)

    local streamedNpc: any = npc("StreamedDummy", world.vector3(5, 0, -25))
    streamedNpc.Parent = world.workspace
    stub.step(0.02)
    check("streamed descendants are added without a polling delay",
        npcLayer and npcLayer:FindFirstChild("StreamedDummy") ~= nil)
    firstNpcHumanoid.Health = 0
    stub.step(0.02)
    local deadSet: any = npcLayer and npcLayer:FindFirstChild("TrainingDummy")
    check("dead NPC drawings are hidden", deadSet ~= nil and deadSet.Visible == false)
    streamedNpc.Parent = nil
    check("streaming an NPC out releases its render set",
        npcLayer and npcLayer:FindFirstChild("StreamedDummy") == nil)
    npcEsp:Toggle(false)
    check("disable releases NPC drawings", npcLayer and #npcLayer:GetChildren() == 0)
    NpcFile.destroy()
    firstNpc.Parent = nil

    section("WallHop lifecycle")

    local WallHopFile: any = require("../../../src/modules/Movement/WallHop")
    Mock.inject(world, WallHopFile.init)
    local wallHop: any = WallHopFile.init(context)
    local root: any = world.localPlayer.Character:FindFirstChild("HumanoidRootPart")
    root.AssemblyLinearVelocity = world.vector3(2, -5, 3)
    world.raycastResult = {
        Instance = Mock.newInstance("Part"),
        Position = root.Position + world.vector3(0, 0, -2),
        Normal = world.vector3(0, 0, 1),
    }
    local jumpBaseline: number = #world.jumpCallbacks
    wallHop:Toggle(true)
    check("WallHop owns one filtered jump callback",
        #world.jumpCallbacks == jumpBaseline + 1)
    world.jumpCallbacks[#world.jumpCallbacks]()
    check("a vertical wall adds height and outward velocity",
        root.AssemblyLinearVelocity.Y == wallHop.Options["Height"].Value
            and root.AssemblyLinearVelocity.Z > 3)
    wallHop:Toggle(false)
    check("disable disconnects the jump callback",
        #world.jumpCallbacks == jumpBaseline)
    WallHopFile.destroy()
    world.raycastResult = nil

    section("SpinBot restoration")

    local SpinFile: any = require("../../../src/modules/Movement/SpinBot")
    Mock.inject(world, SpinFile.init)
    local spin: any = SpinFile.init(context)
    local localHumanoid: any = world.localPlayer.Character:FindFirstChildOfClass("Humanoid")
    local baselineAngular: any = world.vector3(1, 2, 3)
    root.AssemblyAngularVelocity = baselineAngular
    localHumanoid.AutoRotate = true
    ctx.setOption(spin, "Mode", "Velocity")
    spin:Toggle(true)
    stub.step(0.02)
    check("Velocity mode owns AutoRotate", localHumanoid.AutoRotate == false)
    check("Velocity mode writes angular velocity",
        root.AssemblyAngularVelocity.Y ~= baselineAngular.Y)
    spin:Toggle(false)
    check("disable restores angular velocity exactly",
        root.AssemblyAngularVelocity.X == baselineAngular.X
            and root.AssemblyAngularVelocity.Y == baselineAngular.Y
            and root.AssemblyAngularVelocity.Z == baselineAngular.Z)
    check("disable restores AutoRotate", localHumanoid.AutoRotate == true)

    spin:Toggle(true)
    stub.step(0.02)
    localHumanoid.Health = 0
    stub.step(0.02)
    check("death restores SpinBot properties",
        localHumanoid.AutoRotate == true
            and root.AssemblyAngularVelocity.Y == baselineAngular.Y)
    localHumanoid.Health = 100
    spin:Toggle(false)
    SpinFile.destroy()
end
