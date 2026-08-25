--!strict
--
-- Targeting, Aim Assist and Learning contracts.
--
-- The selector reads entities and may raycast for visibility. It must not
-- mutate camera, tools, remotes or input. Aim Assist is the only writer, and
-- it writes only the local camera. Learning never invents a capture when the
-- executor has no screenshot capability.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local entity: any = ctx.entity
    local enemy: any = ctx.enemy
    local ally: any = ctx.ally
    local framework: any = ctx.framework
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local inventory: any = ctx.inventory

    section("Targeting service")

    check("snapshot lists Aim Assist", table.find(inventory.names, "Aim Assist") ~= nil)
    check("snapshot lists Learning", table.find(inventory.names, "Learning") ~= nil)
    check(
        "snapshot names match the inventory count",
        #inventory.names == inventory.count,
        tostring(#inventory.names)
    )

    local TargetingFile: any = require("../../../src/library/Targeting")
    Mock.inject(world, TargetingFile.init)
    local targeting: any = TargetingFile.init(host)

    do
        local cameraBefore: any = world.workspace.CurrentCamera.CFrame
        local candidates: {any} = targeting:List(entity, {
            FOV = 220,
            MaxDistance = 100,
            TargetPart = "Head",
            TeamCheck = true,
            VisibilityCheck = false,
            Priority = "Cursor",
        })
        check("Targeting selects an enemy", #candidates == 1 and candidates[1].player == enemy)
        check("Targeting skips teammates", candidates[1] ~= nil and candidates[1].player ~= ally)
        check(
            "Targeting returns screen-space distance",
            candidates[1] ~= nil and type(candidates[1].cursorDistance) == "number"
        )
        check(
            "Targeting does not write the camera",
            world.workspace.CurrentCamera.CFrame == cameraBefore
        )
        local selected: any = targeting:Select(entity, {
            FOV = 220,
            MaxDistance = 100,
            TargetPart = "Head",
            VisibilityCheck = false,
        })
        check(
            "Select returns the first listed target",
            selected ~= nil and selected.player == candidates[1].player
        )
    end

    do
        local wide: any = world.addPlayer("Wide", "Red", world.vector3(40, 0, -20))
        entity:Refresh(true)
        local tight: {any} = targeting:List(entity, {
            FOV = 80,
            MaxDistance = 200,
            TargetPart = "Head",
            TeamCheck = true,
            VisibilityCheck = false,
        })
        check(
            "FOV rejection drops a target far from the cursor",
            #tight == 1 and tight[1].player == enemy
        )
        local open: {any} = targeting:List(entity, {
            FOV = 500,
            MaxDistance = 200,
            TargetPart = "Head",
            TeamCheck = true,
            VisibilityCheck = false,
        })
        local sawWide: boolean = false
        for _, item: any in ipairs(open) do
            if item.player == wide then
                sawWide = true
            end
        end
        check("a wide FOV can still accept the off-cursor enemy", sawWide)
        world.removePlayer(wide)
        if wide.Character then
            wide.Character:Destroy()
        end
        entity:Refresh(true)
    end

    do
        local closeOff: any = world.addPlayer("CloseOff", "Red", world.vector3(20, 0, -6))
        local farOn: any = world.addPlayer("FarOn", "Red", world.vector3(0, 0, -45))
        entity:Refresh(true)
        local byCursor: {any} = targeting:List(entity, {
            FOV = 500,
            MaxDistance = 200,
            TargetPart = "Head",
            TeamCheck = true,
            VisibilityCheck = false,
            Priority = "Cursor",
        })
        check(
            "Cursor priority prefers the target nearest the pointer",
            #byCursor >= 2 and byCursor[1].player == enemy
        )
        local byDistance: {any} = targeting:List(entity, {
            FOV = 500,
            MaxDistance = 200,
            TargetPart = "Head",
            TeamCheck = true,
            VisibilityCheck = false,
            Priority = "Distance",
        })
        check(
            "Distance priority prefers the nearer world target",
            #byDistance >= 2 and byDistance[1].player == closeOff
        )
        world.removePlayer(closeOff)
        world.removePlayer(farOn)
        if closeOff.Character then
            closeOff.Character:Destroy()
        end
        if farOn.Character then
            farOn.Character:Destroy()
        end
        entity:Refresh(true)
    end

    world.raycastResult = {
        Instance = Mock.newInstance("Part"),
        Position = world.vector3(0, 2, -5),
    }
    local blocked: {any} = targeting:List(entity, {
        FOV = 220,
        MaxDistance = 100,
        TargetPart = "Head",
        TeamCheck = true,
        VisibilityCheck = true,
    })
    check("visibility policy rejects an obstructed target", #blocked == 0)
    world.raycastResult = nil

    host.services.protectedTargets.setProvider(function(player: any): boolean
        return player == enemy
    end)
    local protected: {any} = targeting:List(entity, {
        FOV = 220,
        MaxDistance = 100,
        TargetPart = "Head",
        VisibilityCheck = false,
    })
    check("Friend List policy is shared by Targeting", #protected == 0)
    host.services.protectedTargets.setProvider(nil)
    TargetingFile.destroy()
    check("Targeting destroy unpublishes the active library", TargetingFile.Initialized == false)

    section("Aim Assist")

    local targetingAgain: any = TargetingFile.init(host)
    local AimFile: any = require("../../../src/modules/Combat/AimAssist")
    Mock.inject(world, AimFile.init)
    local camera: any = world.workspace.CurrentCamera
    local originalLook: any = camera.CFrame.LookVector
    local context: any = {
        framework = framework,
        entity = entity,
        weapons = nil,
        render = nil,
        libraries = {targeting = targetingAgain},
        host = host,
        services = host.services,
    }
    local aim: any = AimFile.init(context)
    check("Aim Assist card is registered", aim ~= nil and aim.Name == "Aim Assist")
    check("Aim Assist has no hook option", aim.Options["Hook"] == nil)
    check("Aim Assist has no remote option", aim.Options["Remote"] == nil)
    host.state.visible = false
    host.state.keyCaptureCallback = nil
    host.state.waitingForKey = false
    world.focusedTextBox = nil
    local clicksBefore: number = world.mouseClicks or 0
    local touchBefore: number = world.touchFires or 0
    local hookBefore: any = world.namecallHook
    local root: any = enemy.Character:FindFirstChild("HumanoidRootPart")
    local velocityBefore: any = root.AssemblyLinearVelocity
    local tasksBefore: number = stub.taskCount()
    aim:Toggle(true)
    check("Aim Assist enable takes one render task", stub.taskCount() == tasksBefore + 1)
    stub.step(0.016)
    local changed: boolean = camera.CFrame.LookVector ~= originalLook
    check("Aim Assist only moves the local camera", changed)
    check(
        "Aim Assist reports the selected target",
        string.find(tostring(aim.Status), "Enemy", 1, true) ~= nil,
        tostring(aim.Status)
    )
    check(
        "Aim Assist does not rewrite the target's velocity",
        root.AssemblyLinearVelocity == velocityBefore
    )
    check("Aim Assist does not activate tools", (world.mouseClicks or 0) == clicksBefore)
    check("Aim Assist does not fire touch interest", (world.touchFires or 0) == touchBefore)
    check("Aim Assist does not install a namecall hook", world.namecallHook == hookBefore)

    host.services.activity.set("mvsdSilentAim", true)
    stub.step(0.016)
    check("Aim Assist yields to a game-specific aim adapter", aim.Status == "paused", tostring(aim.Status))
    host.services.activity.set("mvsdSilentAim", false)

    local lockedLook: any = camera.CFrame.LookVector
    host.state.visible = true
    stub.step(0.016)
    check("Aim Assist pauses while the menu is visible", aim.Status == "paused", tostring(aim.Status))
    check(
        "a paused Aim Assist does not keep steering the camera",
        camera.CFrame.LookVector == lockedLook
    )
    host.state.visible = false

    host.state.waitingForKey = true
    stub.step(0.016)
    check("Aim Assist pauses while a key is being captured", aim.Status == "paused")
    host.state.waitingForKey = false

    world.focusedTextBox = Mock.newInstance("TextBox")
    stub.step(0.016)
    check("Aim Assist pauses while a text box is focused", aim.Status == "paused")
    world.focusedTextBox = nil

    stub.step(0.016)
    check(
        "Aim Assist resumes after input surfaces release",
        string.find(tostring(aim.Status), "Enemy", 1, true) ~= nil,
        tostring(aim.Status)
    )

    camera.CFrame = world.globals.CFrame.new(world.vector3(0, 5, 0))
    aim.Options["Mode"].Value = "Aim Assist"
    aim.Options["Target NPCs"].Value = false
    aim.Options["Smoothing"].Value = 0
    stub.step(0.016)
    local snapLook: any = camera.CFrame.LookVector
    camera.CFrame = world.globals.CFrame.new(world.vector3(0, 5, 0))
    aim.Options["Smoothing"].Value = 100
    stub.step(0.016)
    local slowLook: any = camera.CFrame.LookVector
    check("zero smoothing snaps instead of behaving like a preset", snapLook ~= slowLook)
    aim.Options["Smoothing"].Value = 35

    local npc: any = Mock.newInstance("Model")
    npc.Name = "AimDummy"
    local npcHumanoid: any = Mock.newInstance("Humanoid")
    npcHumanoid.Name = "Humanoid"
    npcHumanoid.Health = 100
    npcHumanoid.MaxHealth = 100
    npcHumanoid.Parent = npc
    local npcRoot: any = Mock.newInstance("Part")
    npcRoot.Name = "HumanoidRootPart"
    npcRoot.Position = world.vector3(0, 0, -25)
    npcRoot.Parent = npc
    npc.PrimaryPart = npcRoot
    local npcHead: any = Mock.newInstance("Part")
    npcHead.Name = "Head"
    npcHead.Position = world.vector3(0, 2, -25)
    npcHead.Parent = npc
    npc:SetAttribute("Team", "Red")
    npc.Parent = world.workspace
    entity:Refresh(true)
    aim.Options["Mode"].Value = "Aimbot"
    aim.Options["Target NPCs"].Value = true
    aim.Options["FOV"].Value = 15
    stub.step(0.016)
    check(
        "Aimbot can lock an NPC outside the Assist FOV",
        string.find(tostring(aim.Status), "AimDummy", 1, true) ~= nil,
        tostring(aim.Status)
    )
    npc:Destroy()
    entity:Refresh(true)
    aim.Options["Mode"].Value = "Aim Assist"
    aim.Options["Target NPCs"].Value = false

    aim:Toggle(false)
    local lookAfterDisable: any = camera.CFrame.LookVector
    stub.step(0.016)
    check("Aim Assist disable removes its frame task", aim.Enabled == false)
    check("Aim Assist disable returns to the previous task count", stub.taskCount() == tasksBefore)
    check("a disabled Aim Assist does not keep writing the camera", camera.CFrame.LookVector == lookAfterDisable)
    AimFile.destroy()
    TargetingFile.destroy()
    check("Aim Assist destroy clears the active card", AimFile.Initialized == false)

    section("Learning")

    local LearningFile: any = require("../../../src/modules/Utility/Learning")
    Mock.inject(world, LearningFile.init)
    local learning: any = LearningFile.init({
        framework = framework,
        host = host,
        services = host.services,
    })
    check("Learning card is registered", learning ~= nil and learning.Name == "Learning")
    check("Learning is a group card", learning.Feature.kind == "group")
    local callback: any = learning.Feature.options["Capture now"]
        and learning.Feature.options["Capture now"].run
    check("Learning exposes a manual capture action", type(callback) == "function")

    local function learningFiles(): ({string}, {string})
        local images: {string} = {}
        local sidecars: {string} = {}
        for path: string, _contents: any in pairs(world.files) do
            if string.find(path, "Learning/", 1, true) then
                if string.find(path, "%.png$") then
                    table.insert(images, path)
                elseif string.find(path, "%.json$") then
                    table.insert(sidecars, path)
                end
            end
        end
        return images, sidecars
    end

    local capturesAtRest: number = world.screenCaptures
    learning:Toggle(true)
    check("enabling Learning does not capture", world.screenCaptures == capturesAtRest)
    learning:Toggle(false)

    world.screenCaptureAvailable = false
    local filesBeforeUnavailable: number = 0
    for _path: string in pairs(world.files) do
        filesBeforeUnavailable += 1
    end
    if callback then
        callback()
    end
    check(
        "a missing screenshot capability does not invent a capture",
        world.screenCaptures == capturesAtRest
    )
    check("Learning reports unavailable when the executor has no API", learning.Status == "unavailable")
    local filesAfterUnavailable: number = 0
    for _path: string in pairs(world.files) do
        filesAfterUnavailable += 1
    end
    check(
        "unavailable capture writes no Learning files",
        filesAfterUnavailable == filesBeforeUnavailable
    )
    local sawUnavailable: boolean = false
    for _, message: string in ipairs(stub.notifications) do
        if string.find(message, "unavailable", 1, true) then
            sawUnavailable = true
        end
    end
    check("unavailable capture notifies instead of faking success", sawUnavailable)

    local originalCapture: any = host.services.screenCapture.capture
    world.screenCaptureAvailable = true
    host.services.screenCapture.capture = nil
    if callback then
        callback()
    end
    check(
        "an incomplete capture service is still unavailable",
        learning.Status == "unavailable" and world.screenCaptures == capturesAtRest
    )
    host.services.screenCapture.capture = originalCapture

    if callback then
        callback()
    end
    check("Learning captures only after the action", world.screenCaptures == capturesAtRest + 1)
    local images: {string}, sidecars: {string} = learningFiles()
    check("Learning writes one local screenshot", #images == 1, tostring(#images))
    check("Learning writes a local metadata sidecar", #sidecars == 1, tostring(#sidecars))
    local folder: string = tostring(host.PRODUCT.storageFolder) .. "/Learning/"
    check(
        "Learning paths stay under the product storage folder",
        #images == 1
            and #sidecars == 1
            and string.sub(images[1], 1, #folder) == folder
            and string.sub(sidecars[1], 1, #folder) == folder
    )
    local metadata: string = #sidecars == 1 and world.files[sidecars[1]] or ""
    check(
        "Learning metadata names the sample schema",
        string.find(metadata, "learning-screen-sample", 1, true) ~= nil
            and string.find(metadata, '"schema":1', 1, true) ~= nil
    )
    check(
        "Learning metadata records a manual source",
        string.find(metadata, "manual Capture now action", 1, true) ~= nil
    )
    check(
        "Learning metadata points at the screenshot path",
        #images == 1 and string.find(metadata, images[1], 1, true) ~= nil
    )
    check(
        "Learning never uploads or copies the sample",
        world.clipboard == nil
    )

    local originalWrite: any = host.services.screenCapture.writeText
    host.services.screenCapture.writeText = function(_path: string, _contents: string): boolean
        return false
    end
    if callback then
        callback()
    end
    check(
        "a metadata write failure keeps the image and reports it",
        learning.Status == "image saved" and world.screenCaptures == capturesAtRest + 2
    )
    host.services.screenCapture.writeText = originalWrite

    LearningFile.destroy()
    check("Learning destroy clears the active card", LearningFile.Initialized == false)
end
