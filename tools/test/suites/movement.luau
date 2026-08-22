--!strict
--
-- Headless tests: movement.
--
-- Loaded by tools/test/run.luau. Suites share one world through the context
-- so the checks stay under Luau's 200-local ceiling without wrapping
-- sections in do-end.
--
return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local espContext: any = ctx.espContext
    local enemy: any = ctx.enemy

    section("Click Teleport")

    local ClickFile: any = require("../../../src/modules/Movement/ClickTeleport")
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

    ctx.ClickFile = ClickFile
end
