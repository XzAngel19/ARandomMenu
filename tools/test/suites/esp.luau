--!strict
--
-- Headless tests: esp.
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
    local framework: any = ctx.framework
    local entity: any = ctx.entity
    local enemy: any = ctx.enemy

    section("Player ESP")

    local EspFile: any = require("../../../src/modules/Visuals/PlayerESP")
    Mock.inject(world, EspFile.init)
    local WeaponsFile: any = require("../../../src/library/Weapons")
    Mock.inject(world, WeaponsFile.init)
    local weapons: any = WeaponsFile.init(host)
    local RenderFile: any = require("../../../src/library/Render")
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

    section("Item Render")

    local ItemFile: any = require("../../../src/modules/Visuals/ItemRender")
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

    ctx.EspFile = EspFile
    ctx.WeaponsFile = WeaponsFile
    ctx.weapons = weapons
    ctx.RenderFile = RenderFile
    ctx.render = render
    ctx.espContext = espContext
    ctx.esp = esp
    ctx.ItemFile = ItemFile
end
