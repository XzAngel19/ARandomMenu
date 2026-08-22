--!strict
--
-- Headless tests: framework.
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

    section("Framework")

    local FrameworkFile: any = require("../../../src/core/Framework")
    Mock.inject(world, FrameworkFile.init)
    local framework: any = FrameworkFile.init(host)

    check("categories exist", framework.Categories.Combat ~= nil
        and framework.Categories.Render ~= nil
        and framework.Categories.Movement ~= nil
        and framework.Categories.Other ~= nil)
    -- The old port names keep answering — with the official category they
    -- map to — so modules D has not refiled yet cannot die on a nil index.
    check("an old port name answers with its official category",
        framework.Categories.Visuals ~= nil
            and framework.Categories.Visuals.Name == "Render"
            and framework.Categories.Utility ~= nil
            and framework.Categories.Utility.Name == "Other")

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
    local callbackValue: number = 0
    local sampleSlider: any = sample:CreateSlider({
        Name = "Amount",
        Min = 0,
        Max = 10,
        Step = 0.5,
        Default = 4,
        Function = function(value: number): ()
            callbackValue = value
        end,
    })
    local sampleDropdown: any = sample:CreateDropdown({
        Name = "Mode",
        List = {"First", "Second"},
        Index = 2,
    })
    local sampleToggle: any = sample:CreateToggle({Name = "Switch", Default = true})
    local sampleRange: any = sample:CreateTwoSlider({
        Name = "Band", Min = 1, Max = 20, Step = 1, DefaultMin = 8, DefaultMax = 12,
    })
    local sampleBind: any = sample:CreateBind({
        Name = "Key", Default = world.globals.Enum.KeyCode.Unknown,
    })
    local sampleColor: any = sample:CreateColor({
        Name = "Colour", Default = world.globals.Color3.fromRGB(1, 2, 3),
    })
    local sampleText: any = sample:CreateTextBox({Name = "Query", Default = "abc"})
    local sampleAction: any = sample:CreateButton({Name = "Run", Function = function(): () end})

    check("slider reports its default", sampleSlider.Value == 4)
    check("dropdown honours its index", sampleDropdown.Value == "Second")
    check("toggle reports its default", sampleToggle.Value == true)
    check("option metadata is ordered with the real builders",
        #sample.OptionMetadata == 8
            and sample.OptionMetadata[1] == sampleSlider.Metadata
            and sample.Feature.optionMetadata == sample.OptionMetadata)
    check("slider metadata is complete",
        sampleSlider.Metadata.id == "Amount"
            and sampleSlider.Metadata.configKey == sample.Feature.configKey .. ".Amount"
            and sampleSlider.Metadata.label == "Amount"
            and sampleSlider.Metadata.type == "slider"
            and sampleSlider.Metadata.default == 4
            and sampleSlider.Metadata.current == 4
            and sampleSlider.Metadata.min == 0
            and sampleSlider.Metadata.max == 10
            and sampleSlider.Metadata.step == 0.5
            and sampleSlider.Metadata.callback ~= nil
            and callbackValue == 4)
    check("dropdown metadata keeps its values",
        sampleDropdown.Metadata.type == "dropdown"
            and table.concat(sampleDropdown.Metadata.values, ",") == "First,Second")
    check("range metadata keeps both handles",
        sampleRange.Metadata.type == "range"
            and sampleRange.Metadata.rangeLow == 8
            and sampleRange.Metadata.rangeHigh == 12
            and sampleRange.Metadata.min == 1
            and sampleRange.Metadata.max == 20
            and sampleRange.Metadata.step == 1)
    check("special option kinds are explicit",
        sampleBind.Metadata.bind == true
            and sampleColor.Metadata.color == true
            and sampleText.Metadata.type == "text"
            and sampleAction.Metadata.action == true)

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

    ctx.FrameworkFile = FrameworkFile
    ctx.framework = framework
end
