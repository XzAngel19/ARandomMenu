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

-- Record each option builder's callback so a suite can set a value the way
-- the widget would. Four suites each carried a private copy; two of them
-- guessed select(4)/select(6) and recorded nothing, then passed anyway.
host.optionCallbacks = {}
do
    local callbackPosition: {[string]: number} = {
        addToggleOption = 3,
        addKeyOption = 3,
        addTextOption = 3,
        addCycleOption = 4,
        addNumberOption = 5,
    }
    for builder: string, position: number in pairs(callbackPosition) do
        local original: any = host[builder]
        host[builder] = function(feature: any, ...: any): any
            local label: any = select(1, ...)
            local callback: any = select(position, ...)
            if type(callback) == "function" then
                host.optionCallbacks[feature] = host.optionCallbacks[feature] or {}
                host.optionCallbacks[feature][label] = callback
            end
            return original(feature, ...)
        end
    end
end

ctx.setOption = function(module: any, name: string, value: any): ()
    module.Options[name].Value = value
    local feature: any = module.Feature or module
    local callback: any = host.optionCallbacks[feature]
        and host.optionCallbacks[feature][name]
    if callback then
        callback(value)
    end
    if type(module.RefreshVisibility) == "function" then
        module:RefreshVisibility()
    end
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
require("./suites/movement-basics")(ctx)
require("./suites/protection-rescue")(ctx)
require("./suites/utility-misc")(ctx)
require("./suites/visuals-misc")(ctx)
require("./suites/combat-analytics")(ctx)
require("./suites/games")(ctx)
require("./suites/bundle")(ctx)
require("./suites/shell")(ctx)
require("./suites/windows")(ctx)
require("./suites/clickgui")(ctx)
require("./suites/clickgui-boot")(ctx)
require("./suites/ui-settings")(ctx)
require("./suites/teardown")(ctx)

print("")
print(string.format("%d checks passed, %d failed", passed, #failures))
if #failures > 0 then
    for _, failure: string in ipairs(failures) do
        print("  - " .. failure)
    end
    error("module tests failed", 0)
end
