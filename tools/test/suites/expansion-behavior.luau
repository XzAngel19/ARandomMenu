--!strict
--
-- Headless tests: Chams, Arrows, NPCESP, WallHop and SpinBot behaviour.
--
-- Registration lives in new-modules.luau. This suite holds the contracts
-- that would otherwise stay as "the card exists": target filters, off-screen
-- arrows, NPC exclusion of Player characters, wall-normal/cooldown hops,
-- property restoration and respawn teardown.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local context: any = ctx.espContext
    local entity: any = ctx.entity
    local enemy: any = ctx.enemy
    local ally: any = ctx.ally

    local inventory: any = ctx.inventory
    local function hasName(name: string): boolean
        return table.find(inventory.names, name) ~= nil
    end
    check("snapshot lists Chams", hasName("Chams"))
    check("snapshot lists Arrows", hasName("Arrows"))
    check("snapshot lists NPCESP", hasName("NPCESP"))
    check("snapshot lists WallHop", hasName("WallHop"))
    check("snapshot lists SpinBot", hasName("SpinBot"))

    local function highlightFor(character: any): any
        for _, child: any in ipairs(world.workspace:GetDescendants()) do
            if child.ClassName == "Highlight" and child.Adornee == character then
                return child
            end
        end
        return nil
    end

    local function layerNamed(name: string): any
        for _, child: any in ipairs(host.ScreenGui.Children) do
            if child.Name == name then
                return child
            end
        end
        return nil
    end

    local function drawingNamed(layer: any, name: string): any
        if layer == nil then
            return nil
        end
        return layer:FindFirstChild(name)
    end

    do
        section("ChamsBehaviour")

        local file: any = require("../../../src/modules/Visuals/Chams")
        Mock.inject(world, file.init)
        local card: any = file.init(context)
        check("Chams card is live", card ~= nil and card.Name == "Chams")

        card:Toggle(true)
        entity:Refresh(true)
        stub.step(0.05)

        local withoutAllies: number = tonumber(card.Status) or 0
        check(
            "Chams skips teammates by default",
            highlightFor(enemy.Character) ~= nil and highlightFor(ally.Character) == nil
        )
        check(
            "Chams status counts at least the enemy",
            withoutAllies >= 1,
            tostring(card.Status)
        )

        card.Options["Teammates"].Value = true
        stub.step(0.05)
        local withAllies: number = tonumber(card.Status) or 0
        check(
            "Chams teammates option reveals allies",
            highlightFor(enemy.Character) ~= nil and highlightFor(ally.Character) ~= nil
        )
        check(
            "Chams status grows when teammates are included",
            withAllies > withoutAllies,
            tostring(withoutAllies) .. " -> " .. tostring(withAllies)
        )

        local through: any = highlightFor(enemy.Character)
        check(
            "Chams through-walls default is AlwaysOnTop",
            through ~= nil
                and through.DepthMode == world.globals.Enum.HighlightDepthMode.AlwaysOnTop
        )
        card.Options["Through walls"].Value = false
        stub.step(0.05)
        through = highlightFor(enemy.Character)
        check(
            "Chams occludes when through-walls is off",
            through ~= nil
                and through.DepthMode == world.globals.Enum.HighlightDepthMode.Occluded
        )

        local enemyHumanoid: any = enemy.Character:FindFirstChildOfClass("Humanoid")
        enemyHumanoid.Health = 0
        stub.step(0.05)
        check("Chams drops a dead player", highlightFor(enemy.Character) == nil)

        local respawned: any = world.replaceCharacter(enemy, world.vector3(0, 0, -30))
        entity:Refresh(true)
        stub.step(0.05)
        local afterRespawn: any = highlightFor(respawned)
        check(
            "Chams re-adorns the respawned character",
            afterRespawn ~= nil and afterRespawn.Adornee == respawned
        )

        card:Toggle(false)
        check("Chams disable destroys leftover highlights", highlightFor(respawned) == nil)
        file.destroy()
        enemyHumanoid = enemy.Character:FindFirstChildOfClass("Humanoid")
        if enemyHumanoid then
            enemyHumanoid.Health = 100
        end
    end

    do
        section("ArrowsBehaviour")

        local file: any = require("../../../src/modules/Visuals/Arrows")
        Mock.inject(world, file.init)
        local card: any = file.init(context)
        local offscreen: any = world.addPlayer("Offscreen", "Red", world.vector3(200, 0, -20))
        entity:Refresh(true)

        card:Toggle(true)
        stub.step(0.05)
        local layer: any = layerNamed("ArrowsLayer")
        check("Arrows layer exists", layer ~= nil)
        local onScreenSet: any = drawingNamed(layer, "Enemy")
        local offScreenSet: any = drawingNamed(layer, "Offscreen")
        local allySet: any = drawingNamed(layer, "Ally")
        check(
            "Arrows hide an on-screen player",
            onScreenSet == nil or onScreenSet.Visible == false
        )
        check(
            "Arrows draw only off-screen players",
            offScreenSet ~= nil
                and offScreenSet.Visible == true
                and offScreenSet:FindFirstChild("Arrow1") ~= nil
                and offScreenSet:FindFirstChild("Arrow1").Visible == true
        )
        check("Arrows skip teammates by default", allySet == nil)
        check(
            "Arrows status counts at least the off-screen target",
            tonumber(card.Status) ~= nil and tonumber(card.Status) >= 1,
            tostring(card.Status)
        )

        local distance: any = offScreenSet and offScreenSet:FindFirstChild("Distance")
        check(
            "Arrows distance label is shown by default",
            distance ~= nil and distance.Visible == true
        )
        card.Options["Distance"].Value = false
        stub.step(0.05)
        check(
            "Arrows can hide the distance label",
            distance ~= nil and distance.Visible == false
        )

        card.Options["Max distance"].Value = 5
        stub.step(0.05)
        check(
            "Arrows max-distance filter hides far targets",
            card.Status == "0",
            tostring(card.Status)
        )

        card:Toggle(false)
        check("Arrows disable releases drawings", layer ~= nil and #layer.Children == 0)
        file.destroy()
        world.removePlayer(offscreen)
        if offscreen.Character then
            offscreen.Character:Destroy()
        end
    end

    do
        section("NPCESPBehaviour")

        local npc: any = Mock.newInstance("Model")
        npc.Name = "DummyNpc"
        npc.Parent = world.workspace
        local npcHumanoid: any = Mock.newInstance("Humanoid")
        npcHumanoid.Name = "Humanoid"
        npcHumanoid.Health = 80
        npcHumanoid.MaxHealth = 100
        npcHumanoid.Parent = npc
        local npcRoot: any = Mock.newInstance("Part")
        npcRoot.Name = "HumanoidRootPart"
        npcRoot.Position = world.vector3(0, 0, -20)
        npcRoot.Parent = npc

        local file: any = require("../../../src/modules/Visuals/NPCESP")
        Mock.inject(world, file.init)
        local card: any = file.init(context)
        card:Toggle(true)
        stub.step(0.05)

        local layer: any = layerNamed("NpcEspLayer")
        check("NPCESP layer exists", layer ~= nil)
        local npcSet: any = drawingNamed(layer, "DummyNpc")
        local playerSet: any = drawingNamed(layer, enemy.Name)
        check(
            "NPCESP draws a non-player humanoid",
            npcSet ~= nil and npcSet.Visible == true
        )
        check("NPCESP excludes Player characters", playerSet == nil)
        check("NPCESP status counts visible NPCs", card.Status == "1", tostring(card.Status))

        local nameTag: any = npcSet and npcSet:FindFirstChild("NameTag")
        check(
            "NPCESP name includes health",
            nameTag ~= nil and string.find(tostring(nameTag.Text), "80", 1, true) ~= nil,
            nameTag and tostring(nameTag.Text) or "missing"
        )

        npcHumanoid.Health = 0
        stub.step(0.05)
        check("NPCESP hides a dead NPC", npcSet == nil or npcSet.Visible == false)

        npcHumanoid.Health = 80
        npcRoot.Position = world.vector3(0, 0, -4000)
        stub.step(0.05)
        check(
            "NPCESP max-distance filter hides a far NPC",
            npcSet == nil or npcSet.Visible == false
        )

        card:Toggle(false)
        check("NPCESP disable releases drawings", layer ~= nil and #layer.Children == 0)
        file.destroy()
        npc:Destroy()
    end

    do
        section("WallHopBehaviour")

        local character: any = world.localPlayer.Character
        local humanoid: any = character:FindFirstChildOfClass("Humanoid")
        local root: any = character:FindFirstChild("HumanoidRootPart")
        root.AssemblyLinearVelocity = world.vector3(0, 0, 0)
        humanoid.Health = 100

        local file: any = require("../../../src/modules/Movement/WallHop")
        Mock.inject(world, file.init)
        local card: any = file.init(context)
        card:Toggle(true)
        check("WallHop starts ready", card.Status == "ready", tostring(card.Status))
        check("WallHop has no implementation-tuning options", next(card.Options) == nil)

        world.raycastResult = nil
        world.fireJumpRequest()
        check("WallHop ignores a jump with no wall", root.AssemblyLinearVelocity.Y == 0)

        local floor: any = {
            Instance = Mock.newInstance("Part"),
            Position = world.vector3(0, -2, 0),
            Normal = world.vector3(0, 1, 0),
        }
        world.raycastResult = floor
        world.fireJumpRequest()
        check("WallHop ignores a floor-like normal", root.AssemblyLinearVelocity.Y == 0)

        local wall: any = {
            Instance = Mock.newInstance("Part"),
            Position = world.vector3(0, 0, -2),
            Normal = world.vector3(0, 0, 1),
        }
        world.raycastResult = wall
        world.fireJumpRequest()
        check("WallHop rejects a fully covered wall", card.Status == "blocked")

        local casts: number = 0
        world.raycastResult = function(): any
            casts += 1
            if casts == 2 then return nil end -- open left edge
            return wall
        end
        local jumpStates: {any} = {}
        humanoid.ChangeState = function(_self: any, state: any): ()
            table.insert(jumpStates, state)
            humanoid.State = state
        end
        world.fireJumpRequest()
        check("a usable edge starts the WallHop sequence", card.Status == "hop")
        stub.step(0.02)
        stub.step(0.04)
        stub.step(0.04)
        check(
            "WallHop finishes with fixed height and outward velocity",
            root.AssemblyLinearVelocity.Y == 52
                and root.AssemblyLinearVelocity.Z > 0
        )
        check(
            "WallHop requests a jump state after its offsets",
            jumpStates[1] == world.globals.Enum.HumanoidStateType.Jumping
        )

        casts = 0
        world.fireJumpRequest()
        check("WallHop cooldown avoids even probing twice", casts == 0)

        stub.step(0.23)
        root.AssemblyLinearVelocity = world.vector3(0, 0, 0)
        casts = 0
        world.fireJumpRequest()
        stub.step(0.02)
        stub.step(0.04)
        stub.step(0.04)
        check("WallHop can run again after cooldown", root.AssemblyLinearVelocity.Y == 52)

        -- A game that swaps Character to another model without destroying the
        -- old one. The pending hop belongs to the old root either way, and
        -- writing its remaining offsets into the new assembly is what turned a
        -- respawn into a launch.
        stub.step(0.23)
        root.AssemblyLinearVelocity = world.vector3(0, 0, 0)
        casts = 0
        world.fireJumpRequest()
        check("the replacement case starts a hop", card.Status == "hop",
            tostring(card.Status))

        local standIn: any = Mock.newInstance("Model")
        standIn.Name = "WallHopStandIn"
        local standInHumanoid: any = Mock.newInstance("Humanoid")
        standInHumanoid.Health = 100
        standInHumanoid.Parent = standIn
        local standInRoot: any = Mock.newInstance("Part")
        standInRoot.Name = "HumanoidRootPart"
        standInRoot.AssemblyLinearVelocity = world.vector3(0, 0, 0)
        standInRoot.Parent = standIn
        standIn.Parent = world.workspace
        local realCharacter: any = world.localPlayer.Character
        world.localPlayer.Character = standIn
        stub.step(0.02)
        stub.step(0.04)
        stub.step(0.04)
        check("a swapped character drops the hop instead of launching the new one",
            standInRoot.AssemblyLinearVelocity.Y == 0,
            "velocity is " .. tostring(standInRoot.AssemblyLinearVelocity.Y))
        check("and the old root gets no further offsets",
            root.AssemblyLinearVelocity.Y == 0,
            "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))
        world.localPlayer.Character = realCharacter
        standIn.Parent = nil

        -- Death between the first offset and the last: the rest of the sequence
        -- is dropped rather than applied to a corpse.
        stub.step(0.23)
        root.AssemblyLinearVelocity = world.vector3(0, 0, 0)
        casts = 0
        world.fireJumpRequest()
        humanoid.Health = 0
        stub.step(0.02)
        stub.step(0.04)
        stub.step(0.04)
        check("a death mid-sequence drops the hop",
            root.AssemblyLinearVelocity.Y == 0,
            "velocity is " .. tostring(root.AssemblyLinearVelocity.Y))
        humanoid.Health = 100

        -- A hop spent just before the card went off must not eat the first jump
        -- request after it comes back.
        stub.step(0.23)
        root.AssemblyLinearVelocity = world.vector3(0, 0, 0)
        casts = 0
        world.fireJumpRequest()
        card:Toggle(false)
        card:Toggle(true)
        casts = 0
        world.fireJumpRequest()
        check("re-enabling clears the cooldown", casts > 0,
            "casts: " .. tostring(casts))

        card:Toggle(false)
        local jumpCount: number = #(world.jumpCallbacks or {})
        root.AssemblyLinearVelocity = world.vector3(0, 0, 0)
        world.fireJumpRequest()
        check("WallHop disable drops the jump callback", jumpCount == 0)
        check("WallHop disable does not keep hopping", root.AssemblyLinearVelocity.Y == 0)
        file.destroy()
        world.raycastResult = nil
    end

    do
        section("SpinBotBehaviour")

        local character: any = world.localPlayer.Character
        local humanoid: any = character:FindFirstChildOfClass("Humanoid")
        local root: any = character:FindFirstChild("HumanoidRootPart")
        humanoid.AutoRotate = true
        root.AssemblyAngularVelocity = world.vector3(0, 0, 0)
        root.CFrame._ry = 0

        local file: any = require("../../../src/modules/Movement/SpinBot")
        Mock.inject(world, file.init)
        local card: any = file.init(context)
        card:Toggle(true)
        check("SpinBot status names the mode", card.Status == "CFrame", tostring(card.Status))
        stub.step(0.016)
        check("SpinBot CFrame mode disables AutoRotate", humanoid.AutoRotate == false)
        check(
            "SpinBot CFrame mode rotates the root",
            (root.CFrame._ry or 0) ~= 0,
            tostring(root.CFrame._ry)
        )

        ctx.setOption(card, "Mode", "Velocity")
        stub.step(0.016)
        check(
            "SpinBot velocity mode writes angular velocity",
            math.abs(root.AssemblyAngularVelocity.Y - math.rad(card.Options["Speed"].Value))
                < 1e-6,
            tostring(root.AssemblyAngularVelocity.Y)
        )

        -- A game that swaps Character without destroying the old model still
        -- owes the old root its properties back.
        local standIn: any = Mock.newInstance("Model")
        standIn.Name = "SpinStandIn"
        local standInHumanoid: any = Mock.newInstance("Humanoid")
        standInHumanoid.Health = 100
        standInHumanoid.AutoRotate = true
        standInHumanoid.Parent = standIn
        local standInRoot: any = Mock.newInstance("Part")
        standInRoot.Name = "HumanoidRootPart"
        standInRoot.Parent = standIn
        standIn.Parent = world.workspace
        local realCharacter: any = world.localPlayer.Character
        world.localPlayer.Character = standIn
        stub.step(0.016)
        check("a swapped character hands the old root its properties back",
            humanoid.AutoRotate == true and root.AssemblyAngularVelocity.Y == 0,
            "autoRotate " .. tostring(humanoid.AutoRotate)
                .. " · angular " .. tostring(root.AssemblyAngularVelocity.Y))
        check("and takes over the new one", standInHumanoid.AutoRotate == false)
        world.localPlayer.Character = realCharacter
        standIn.Parent = nil
        stub.step(0.016)

        -- A game that clamps angular velocity zeroes it between frames. The
        -- write is absolute, so one frame is one turn rate and not the sum of
        -- every frame since the card was enabled.
        root.AssemblyAngularVelocity = world.vector3(0, 0, 0)
        stub.step(0.016)
        check("a clamped assembly is re-asserted, not compounded",
            math.abs(root.AssemblyAngularVelocity.Y
                - math.rad(card.Options["Speed"].Value)) < 1e-6,
            tostring(root.AssemblyAngularVelocity.Y))

        -- A server correction moves the root. CFrame mode composes its rotation
        -- onto wherever the character now is instead of dragging it back.
        ctx.setOption(card, "Mode", "CFrame")
        stub.step(0.016)
        root.CFrame = world.globals.CFrame.new(world.vector3(40, 5, -12))
        stub.step(0.016)
        check("a corrected position survives the spin",
            root.CFrame.Position.X == 40 and root.CFrame.Position.Y == 5,
            tostring(root.CFrame.Position))

        local replaced: any = world.replaceCharacter(
            world.localPlayer,
            world.vector3(0, 0, 0)
        )
        local newHumanoid: any = replaced:FindFirstChildOfClass("Humanoid")
        local newRoot: any = replaced:FindFirstChild("HumanoidRootPart")
        newHumanoid.AutoRotate = true
        stub.step(0.016)
        check(
            "SpinBot takes over a respawned character",
            newHumanoid.AutoRotate == false
        )

        card:Toggle(false)
        check(
            "SpinBot disable restores AutoRotate",
            newHumanoid.AutoRotate == true
        )
        check(
            "SpinBot disable restores angular velocity",
            newRoot.AssemblyAngularVelocity.X == 0
                and newRoot.AssemblyAngularVelocity.Y == 0
                and newRoot.AssemblyAngularVelocity.Z == 0
        )
        file.destroy()
    end
end
