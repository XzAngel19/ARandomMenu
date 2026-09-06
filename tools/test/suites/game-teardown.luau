--!strict
--
-- Headless tests: shell teardown of per-game runtimes and failed-init rollback.
--
-- Game modules are not in the bundle: the shell fetches `src/games/<Name>.luau`
-- per-URL. Two things used to go wrong there and nothing pinned them:
--
--   1. BedWars was registered but the runtime teardown loop never named it,
--      so its `Module.destroy` never ran on menu close.
--   2. When a game module's init failed after creating cards, the rollback
--      destroyed the rows but left the cards in the module-search registry
--      and the keybind slots in the shortcut table, both pointing at the
--      half-initialised module.
--
-- Boot A proves the teardown loop reaches every per-game state slot (spies
-- are installed where the shell would have put the real destroyers; MM2's
-- destroyer is a shell local and is pinned statically). Boot B loads a
-- deliberately broken game module served over the mock HTTP and proves the
-- rollback leaves no card or binding behind.

return function(ctx: any): ()

    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inventory: any = require("../inventory")

    section("Game teardown")

    -- Boot A: no game is active (PlaceId 0), so no real destroyer is assigned
    -- yet. Install a spy in every per-game slot and prove the teardown loop
    -- that runs on menu close reaches all six of them.
    local bootA: any = bootShell(ctx)
    check("game-teardown boot A runs", bootA.ok == true, bootA.error)
    if not bootA.ok then
        return
    end

    -- MM2 is the one game whose destroyer lives in a shell local rather than a
    -- state slot, so it cannot be spied here; the static contract pins it.
    local SLOTS: {string} = {
        "cleanupTRSRuntime",
        "cleanupVDRuntime",
        "cleanupMVSDRuntime",
        "cleanupBedFightRuntime",
        "cleanupBedWarsRuntime",
    }
    local fired: {[string]: number} = {}
    local stateA: any = bootA.state
    for _, slot: string in ipairs(SLOTS) do
        stateA[slot] = function(): ()
            fired[slot] = (fired[slot] or 0) + 1
        end
    end
    local destructed: boolean, destructError: any = pcall(function(): ()
        stateA.destruct()
    end)
    check("game-teardown destruct runs", destructed == true, tostring(destructError))
    for _, slot: string in ipairs(SLOTS) do
        check(
            "menu close reaches " .. slot,
            (fired[slot] or 0) == 1,
            "fired: " .. tostring(fired[slot] or 0)
        )
    end

    -- Boot B: the BedWars place id, with a game module that creates a card and
    -- binds a shortcut and then fails to initialise. The rollback has to
    -- remove what the card factory already published.
    local FAKE_MODULE: string = [==[
--!strict
-- Deliberately broken: publishes a card and a shortcut, then fails.
local Module = {
    Name = "FakeGame",
    PlaceId = 0,
    Events = {},
}
function Module.init(): ()
    local host: any = getfenv()
    host.createUniversalFeature(
        "Crashing Card",
        "created before the failure",
        22,
        function(_enabled: boolean): ()
        end,
        { categoryName = "Other" }
    )
    if type(host.bindActionShortcut) == "function" then
        host.bindActionShortcut(
            nil,
            "Universal.CrashingCard",
            "Crashing Card",
            function(): ()
            end
        )
    end
    error("deliberate init failure")
end
function Module.destroy(): ()
end
return Module
]==]

    local served: string? = nil
    local bootB: any = bootShell({
        Mock = ctx.Mock,
        shellSource = ctx.shellSource,
        bundleSource = ctx.bundleSource,
        prepareWorld = function(world: any): ()
            world.globals.game.PlaceId = 8444591321
        end,
        httpGet = function(url: any): (string?)
            if type(url) == "string" and string.find(
                url,
                "src/games/BedWars.luau",
                1,
                true
            ) then
                served = FAKE_MODULE
                return served
            end
            return nil
        end,
    })
    check("broken game module was served", served ~= nil, served)
    check("game-teardown boot B runs", bootB.ok == true, bootB.error)
    if not bootB.ok then
        return
    end

    local stateB: any = bootB.state
    local envB: any = bootB.env
    local expected: number = Inventory.count
    check(
        "failed init leaves the module-search registry intact",
        type(stateB.moduleSearch) == "table"
            and #stateB.moduleSearch.entries == expected,
        tostring(stateB.moduleSearch and #stateB.moduleSearch.entries or -1)
            .. " vs "
            .. tostring(expected)
    )
    check(
        "failed init removes the crashed card from allFeatures",
        envB.allFeatures ~= nil,
        envB.allFeatures and "list missing" or "no list"
    )
    if type(envB.allFeatures) == "table" then
        local found: boolean = false
        for _, feature: any in ipairs(envB.allFeatures) do
            if tostring(feature.name) == "Crashing Card" then
                found = true
                break
            end
        end
        check("failed init leaves no card behind", found == false)
    end
    check(
        "failed init removes the crashed shortcut binding",
        stateB.shortcutBindings ~= nil
            and stateB.shortcutBindings["Universal.CrashingCard"] == nil
    )
    local active: any = stateB.activeGameModule
    if type(active) == "table" then
        check(
            "failed init never publishes the broken game module",
            active.Name ~= "FakeGame"
        )
    else
        check("failed init never publishes the broken game module", true)
    end
end
