--!strict
--
-- Requested universal modules: declaration, lifecycle and option contracts.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local context: any = ctx.espContext

    section("RequestedModules")

    local definitions: {any} = {
        {
            path = "../../../src/modules/Visuals/Chams",
            name = "Chams",
            options = {"Fill colour", "Outline colour", "Fill transparency", "Outline transparency", "Through walls", "Teammates"},
        },
        {
            path = "../../../src/modules/Visuals/Arrows",
            name = "Arrows",
            options = {"Colour", "Distance", "Max distance", "Teammates"},
        },
        {
            path = "../../../src/modules/Visuals/NPCESP",
            name = "NPCESP",
            options = {"Box", "Highlight", "Through walls", "Name", "Health", "Colour", "Max distance"},
        },
        {
            path = "../../../src/modules/Movement/WallHop",
            name = "WallHop",
            options = {},
        },
        {
            path = "../../../src/modules/Movement/SpinBot",
            name = "SpinBot",
            options = {"Mode", "Axis", "Speed"},
        },
    }

    for _, definition: any in ipairs(definitions) do
        local file: any = require(definition.path)
        Mock.inject(ctx.world, file.init)
        local card: any = file.init(context)
        check(definition.name .. " registers", card ~= nil and card.Name == definition.name)
        for _, optionName: string in ipairs(definition.options) do
            check(
                definition.name .. " option: " .. optionName,
                card ~= nil and card.Options[optionName] ~= nil
            )
        end
        if card ~= nil then
            card:Toggle(true)
            check(definition.name .. " enables", card.Enabled == true)
            card:Toggle(false)
            check(definition.name .. " disables", card.Enabled == false)
        end
        file.destroy()
    end
end
