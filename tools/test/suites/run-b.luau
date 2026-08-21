--!strict
--
-- Agent B's suite driver.
--
-- `tools/test/run.luau` does not list suites yet (the split runner lives on
-- another branch), so this file boots the same harness — mock Roblox, stand-in
-- host, real framework — and runs the module and game suites that came out of
-- the Show pass, the MM2 Shoot Redirect deletion and the TRS/VD audit.
--
-- Run from the repository root:  luau tools/test/suites/run-b.luau
--
-- When the split runner lands, its `run.luau` can require these suites with a
-- context of its own instead; each one takes `(ctx)` and needs nothing else.

local Mock = require("../Roblox")
local Host = require("../Host")

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

require("./movement-b")(ctx)
require("./protection-b")(ctx)
require("./games-b")(ctx)

print("")
print(string.format("%d checks passed, %d failed", passed, #failures))
if #failures > 0 then
    for _, failure: string in ipairs(failures) do
        print("  - " .. failure)
    end
    error("module tests failed", 0)
end
