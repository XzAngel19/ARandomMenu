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
--
-- The suites live under tools/test/suites/ because a single file of this many
-- checks sits on Luau's 200-local ceiling; splitting them is what keeps the
-- next section compilable.

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

local ctx: any = {
    Mock = Mock,
    world = world,
    stub = stub,
    host = host,
    check = check,
    section = section,
}

-- Emitted by tools/validate.sh next to this file. Required here rather than
-- from a suite so the path is the same `./` the rest of the harness uses.
local shellSourceOk: boolean, shellSource: any = pcall(function(): any
    return require("./_shell_source")
end)
ctx.shellSource = shellSourceOk and shellSource or nil
ctx.shellSourceError = shellSourceOk and nil or shellSource

local bundleSourceOk: boolean, bundleSource: any = pcall(function(): any
    return require("./_bundle_source")
end)
ctx.bundleSource = bundleSourceOk and bundleSource or nil
ctx.bundleSourceError = bundleSourceOk and nil or bundleSource

-- Wall-clock of one module's per-frame work. The mocked os.clock does not
-- move unless a test nudges it, so the budget has to read the CLI's clock.
ctx.measureFrames = function(step: (number) -> (), samples: number?): number
    local count: number = samples or 20
    local started: number = os.clock()
    for _ = 1, count do
        step(0.016)
    end
    return (os.clock() - started) / count
end

-- Later suites read world state (the sword, the friend list, the ESP card)
-- that earlier ones built, so this order is the dependency order.
require("./suites/framework")(ctx)
require("./suites/entity")(ctx)
require("./suites/esp")(ctx)
require("./suites/combat")(ctx)
require("./suites/movement")(ctx)
require("./suites/movement-engines")(ctx)
require("./suites/protection")(ctx)
require("./suites/spoof")(ctx)
require("./suites/widgets")(ctx)
require("./suites/cards")(ctx)
require("./suites/settings")(ctx)
require("./suites/floating")(ctx)
require("./suites/games")(ctx)
require("./suites/bundle")(ctx)
require("./suites/shell")(ctx)
require("./suites/teardown")(ctx)

print("")
print(string.format("%d checks passed, %d failed", passed, #failures))
if #failures > 0 then
    for _, failure: string in ipairs(failures) do
        print("  - " .. failure)
    end
    error("module tests failed", 0)
end
