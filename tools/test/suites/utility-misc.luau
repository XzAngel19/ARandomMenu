--!strict
--
-- Headless tests: the utility cards no suite had loaded.
--
-- AntiAFK, Fling, Gravity, Interact Extender, Lag Switch and Rejoin Server.
-- Six of the cards that spent a week dead in the client because the shell
-- never published two fields they call while building — these are their first
-- runs anywhere, so the checks read like a first inspection.
--
-- Runs from the split runner's context, or from run-b.luau on a fresh world.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local stub: any = ctx.stub
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    local vector3: any = world.vector3
    local character: any = world.localPlayer.Character
    local humanoid: any = character:FindFirstChildOfClass("Humanoid")
    local root: any = character:FindFirstChild("HumanoidRootPart")
    humanoid.FloorMaterial = world.globals.Enum.Material.Plastic

    local context: any = ctx.espContext
    if not context then
        local FrameworkFile: any = require("../../../src/core/Framework")
        Mock.inject(world, FrameworkFile.init)
        local framework: any = FrameworkFile.init(host)
        context = {framework = framework, entity = nil, weapons = nil, render = nil, host = host}
    end
    ctx.espContext = context

    local baseline: number = stub.taskCount()

    section("AntiAFK")

    -- VirtualUser is not a default service; the module talks to it by name.
    local idleSignal: any = world.localPlayer.Idled
    local virtualUser: any = Mock.newInstance("VirtualUser")
    local capturedController: number = 0
    local clicked: number = 0
    function virtualUser:CaptureController(): ()
        capturedController += 1
    end
    function virtualUser:ClickButton2(_position: any): ()
        clicked += 1
    end
    world.services.VirtualUser = virtualUser

    local AntiAfkFile: any = require("../../../src/modules/Utility/AntiAfk")
    Mock.inject(world, AntiAfkFile.init)
    local antiAfk: any = AntiAfkFile.init(context)

    check("card is registered", antiAfk.name == "AntiAFK")
    antiAfk.activate()
    check("the idle listener is attached", idleSignal:Count() == 1)
    idleSignal:Fire()
    check("an idle kick is answered the way Roblox expects",
        capturedController == 1 and clicked == 1,
        "captures: " .. tostring(capturedController) .. ", clicks: " .. tostring(clicked))
    antiAfk.activate()
    check("switching it off detaches the listener", idleSignal:Count() == 0)
    antiAfk.activate()
    AntiAfkFile.destroy()
    check("and so does tearing the module down", idleSignal:Count() == 0,
        "the cleanup used to disconnect a name it never stored")

    section("Fling")

    local FlingFile: any = require("../../../src/modules/Utility/Fling")
    Mock.inject(world, FlingFile.init)
    local fling: any = FlingFile.init(context)

    check("card is registered as a one-shot", fling.name == "Fling")
    for _, name: string in ipairs({
        "Target player",
        "Duration (s)",
        "Power",
        "Return to start",
    }) do
        check("option: " .. name, fling.options ~= nil and fling.options[name] ~= nil)
    end

    local victim: any = world.addPlayer("FlingTarget", "Red", vector3(0, 0, 6))
    victim.Parent = host.Players
    local originalProtection: any = host.state.isProtectedTarget
    host.state.isProtectedTarget = function(_player: any): boolean
        return true
    end
    fling.activate()
    check("a protected player is refused with the reason",
        #stub.notifications > 0
            and stub.notifications[#stub.notifications]
                == "That player is protected by FriendList.",
        "notified: " .. tostring(stub.notifications[#stub.notifications]))
    host.state.isProtectedTarget = originalProtection

    -- In the stand-in there is no RunService, so the orbit loop fails on its
    -- first wait — which is exactly the path worth pinning: restoration runs
    -- even after an error, and nothing is left mid-fling.
    while #stub.notifications > 0 do
        table.remove(stub.notifications)
    end
    root.CFrame = world.globals.CFrame.new(vector3(0, 0, 0))
    root.AssemblyLinearVelocity = vector3(5, 0, 5)
    fling.activate()
    check("a failed fling still puts the character back",
        root.CFrame.Position.Y == 2
            and root.AssemblyLinearVelocity.Magnitude == 0,
        "height " .. tostring(root.CFrame.Position.Y)
            .. ", speed " .. tostring(root.AssemblyLinearVelocity.Magnitude))
    check("and says what happened",
        #stub.notifications > 0
            and string.sub(stub.notifications[#stub.notifications], 1, 13) == "Fling failed:",
        "notified: " .. tostring(stub.notifications[#stub.notifications] ))
    check("the running flag is cleared for the next attempt",
        host.state.flingRunning == false)
    check("no task is held", stub.taskCount() == baseline)

    section("Gravity")

    world.globals.workspace.Gravity = 196.2
    local GravityFile: any = require("../../../src/modules/Utility/Gravity")
    Mock.inject(world, GravityFile.init)
    local gravity: any = GravityFile.init(context)

    check("card is registered", gravity.name == "Gravity")
    check("option: Gravity value",
        gravity.options ~= nil and gravity.options["Gravity value"] ~= nil)

    gravity.activate()
    check("gravity reports its live value", gravity.status == "196")
    stub.step(1 / 60)
    check("gravity is held at the slider value",
        world.globals.workspace.Gravity == gravity.options["Gravity value"].value,
        "gravity is " .. tostring(world.globals.workspace.Gravity))
    gravity.activate()
    check("and put back on disable",
        world.globals.workspace.Gravity == 196.2)

    gravity.activate()
    stub.step(1 / 60)
    GravityFile.destroy()
    check("and on teardown, which used to leave the workspace modified",
        world.globals.workspace.Gravity == 196.2,
        "gravity is " .. tostring(world.globals.workspace.Gravity))

    section("Interact Extender")

    local InteractFile: any = require("../../../src/modules/Utility/InteractExtender")
    Mock.inject(world, InteractFile.init)
    local interact: any = InteractFile.init(context)

    check("card is registered", interact.name == "Interact Extender")
    for _, name: string in ipairs({
        "Interaction distance",
        "Instant prompts",
        "Proximity prompts",
        "Click detectors",
    }) do
        check("option: " .. name, interact.options ~= nil and interact.options[name] ~= nil)
    end

    local prompt: any = Mock.newInstance("ProximityPrompt")
    prompt.MaxActivationDistance = 10
    prompt.HoldDuration = 1.5
    prompt.Parent = world.globals.workspace
    local detector: any = Mock.newInstance("ClickDetector")
    detector.MaxActivationDistance = 8
    detector.Parent = world.globals.workspace

    interact.activate()
    check("the prompt reaches as far as the slider says",
        prompt.MaxActivationDistance == interact.options["Interaction distance"].value,
        "distance is " .. tostring(prompt.MaxActivationDistance))
    check("and so does the click detector",
        detector.MaxActivationDistance == interact.options["Interaction distance"].value)
    check("the hold stays until instant prompts is on",
        prompt.HoldDuration == 1.5)
    interact.activate()
    check("disabling restores both to what the game set",
        prompt.MaxActivationDistance == 10 and prompt.HoldDuration == 1.5
            and detector.MaxActivationDistance == 8)

    section("Lag Switch")

    local networkSettings: any = world.networkSettings
    networkSettings.IncomingReplicationLag = 0

    local LagFile: any = require("../../../src/modules/Utility/LagSwitch")
    Mock.inject(world, LagFile.init)
    local lagSwitch: any = LagFile.init(context)

    check("card is registered", lagSwitch.name == "Lag Switch")
    check("option: Incoming lag",
        lagSwitch.options ~= nil and lagSwitch.options["Incoming lag"] ~= nil)

    lagSwitch.activate()
    stub.step(1 / 60)
    check("replication is held at the slider's lag",
        networkSettings.IncomingReplicationLag
            == lagSwitch.options["Incoming lag"].value,
        "lag is " .. tostring(networkSettings.IncomingReplicationLag))
    lagSwitch.activate()
    check("and released exactly to what it was on disable",
        networkSettings.IncomingReplicationLag == 0)

    -- Without the executor surface the card refuses loudly rather than
    -- pretending to hold replication.
    getfenv(LagFile.init).settings = nil
    world.globals.settings = nil
    local refused: boolean, refusal: any = pcall(function(): ()
        local bareFile: any = require("../../../src/modules/Utility/LagSwitch")
        Mock.inject(world, bareFile.init)
        local bare: any = bareFile.init(context)
        bare.activate()
    end)
    check("a client without NetworkSettings is told so, loudly",
        not refused and string.find(tostring(refusal), "NetworkSettings") ~= nil,
        "raised: " .. tostring(refusal))

    section("Rejoin Server")

    local teleportCalls: {any} = {}
    local teleportService: any = Mock.newInstance("TeleportService")
    function teleportService:TeleportToPlaceInstance(...: any): ()
        table.insert(teleportCalls, {...})
    end
    world.services.TeleportService = teleportService
    if host.cloneReference == nil then
        host.cloneReference = function(reference: any): any
            return reference
        end
    end

    local RejoinFile: any = require("../../../src/modules/Utility/RejoinServer")
    Mock.inject(world, RejoinFile.init)
    local rejoin: any = RejoinFile.init(context)

    check("card is registered as an action", rejoin.name == "Rejoin Server")
    rejoin.activate()
    check("one press asks for the same place and job id",
        #teleportCalls == 1
            and teleportCalls[1][1] == world.globals.game.PlaceId
            and teleportCalls[1][2] == world.globals.game.JobId,
        "calls: " .. tostring(#teleportCalls))

    RejoinFile.destroy()
    local featuresBeforeOptions: number = #stub.features
    local registeredActions: {any} = {}
    local unregisters: number = 0
    host.state.wurstOptions = {
        RegisterAction = function(definition: any): () -> ()
            table.insert(registeredActions, definition)
            return function(): ()
                unregisters += 1
            end
        end,
    }
    local optionsRegistration: any = RejoinFile.init(context)
    check("Wurst Options registers exactly one Rejoin action",
        #registeredActions == 1 and optionsRegistration ~= nil)
    check("Wurst Options path creates no duplicate feature row",
        #stub.features == featuresBeforeOptions)
    check("registered Rejoin is an action with stable identity",
        registeredActions[1].id == "RejoinServer"
            and registeredActions[1].displayName == "Rejoin Server"
            and registeredActions[1].configKey == "Universal.RejoinServer"
            and type(registeredActions[1].callback) == "function")
    registeredActions[1].callback()
    check("the registered action keeps the teleport callback", #teleportCalls == 2)
    RejoinFile.destroy()
    check("teardown unregisters the Wurst Options action", unregisters == 1)
    host.state.wurstOptions = nil

    -- Leave the shared world as the next suite expects it.
    root.AssemblyLinearVelocity = vector3(0, 0, 0)
    while #stub.notifications > 0 do
        table.remove(stub.notifications)
    end
    world.services.VirtualUser = nil
    world.services.TeleportService = nil
end
