--!nocheck
--[[
    Speed Hub X — entry point
    The bundle registers every module from Features/Shared.luau through
    Components.luau, then runs this file last.
]]

local App = require("App")

App.start()

return true
