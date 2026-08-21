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

    ctx.FrameworkFile = FrameworkFile
    ctx.framework = framework
end
