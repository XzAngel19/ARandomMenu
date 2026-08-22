--!strict
--
-- Headless tests: the shell.
--
-- ARandomMenu.luau is the window, the rail and the loader, and nothing else
-- in the suite ever executed it. The CLI has no filesystem API, so
-- tools/validate.sh emits tools/test/_shell_source.luau (the bootstrap as a
-- string) and tools/test/_bundle_source.luau (the stamped bundle as a string)
-- before this runs.
--
-- Two boots. The first feeds the stamped bundle, which is the path a client
-- takes. The second 404s only that one URL and serves every other file from
-- the same bundle's `files` table, which is the recovery path
-- `downloadSourcesParallel` was written for and that nothing had ever run.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Shell")

    local source: any = ctx.shellSource
    check(
        "shell source is available",
        type(source) == "string" and #source > 1000,
        type(source) == "string" and ("bytes: " .. tostring(#source))
            or tostring(ctx.shellSourceError)
    )
    if type(source) ~= "string" then
        return
    end

    local bundleSource: any = ctx.bundleSource
    check(
        "bundle source is available",
        type(bundleSource) == "string" and #bundleSource > 1000,
        type(bundleSource) == "string" and ("bytes: " .. tostring(#bundleSource))
            or tostring(ctx.bundleSourceError)
    )

    local packed: any = require("../../../runtime/bundle")
    local manifest: any = require("../../../src/core/Manifest")
    local expectedModules: number = type(manifest.modules) == "table"
        and #manifest.modules
        or 0

    local function pathFromUrl(url: any): string?
        if type(url) ~= "string" then
            return nil
        end
        local withoutQuery: string = string.match(url, "^([^?]+)") or url
        return string.match(withoutQuery, "/refs/heads/[^/]+/(.+)$")
    end

    -- One boot against one HttpGet. Kept as a helper so the recovery pass
    -- does not duplicate the capture of `state` or sit on the 200-local
    -- ceiling of this file.
    local function bootOnce(httpGet: any): any
        local world: any = Mock.install()
        local playerGui: any = Mock.newInstance("PlayerGui")
        playerGui.Name = "PlayerGui"
        playerGui.Parent = world.localPlayer

        local chunk: any, compileError: any = loadstring(source, "@ARandomMenu.luau")
        if type(chunk) ~= "function" then
            return {
                world = world,
                compiled = false,
                compileError = compileError,
            }
        end

        Mock.inject(world, chunk)
        if type(httpGet) == "function" then
            world.globals.game.HttpGet = httpGet
        end

        local captured: any = nil
        local environment: any = getfenv(chunk)
        local realSetfenv: any = environment.setfenv
        environment.setfenv = function(fn: any, env: any): any
            if type(env) == "table" and env.state ~= nil then
                captured = env.state
            end
            return realSetfenv(fn, env)
        end

        local started: number = os.clock()
        local ran: boolean, failure: any = xpcall(chunk, function(message: any): string
            return tostring(message)
        end)
        return {
            world = world,
            playerGui = playerGui,
            state = captured,
            compiled = true,
            ran = ran,
            failure = failure,
            elapsed = os.clock() - started,
        }
    end

    local function moduleCountOf(boot: any): number
        local state: any = boot.state
        if not state or not state.boot or not state.boot.timing then
            return -1
        end
        return tonumber(state.boot.timing.moduleCount) or -1
    end

    -- Production path: one HttpGet for the stamped bundle, then every file
    -- the manifest names is compiled out of `packed.files`.
    local productionGet: any = nil
    if type(bundleSource) == "string" then
        productionGet = function(_self: any, url: any, _cache: any): string
            if type(url) == "string"
                and string.find(url, "runtime/bundle.luau", 1, true) then
                return bundleSource
            end
            return "404: Not Found"
        end
    end

    -- Wall-clock of the real bootstrap, not the mocked os.clock. A real
    -- client does this in 0.59s; headless also has to compile the bundle.
    -- Raise the number only with a comment saying what got more expensive.
    local BUDGET_BOOT_SECONDS: number = 1.5
    local boot: any = bootOnce(productionGet)
    check("the shell compiles", boot.compiled == true, tostring(boot.compileError))
    if not boot.compiled then
        return
    end
    check("the shell runs", boot.ran == true, tostring(boot.failure))

    local world: any = boot.world
    local playerGui: any = boot.playerGui
    local shellState: any = boot.state
    local gui: any = playerGui:FindFirstChild("RandomTestingMenu0001")
        or world.services.CoreGui:FindFirstChild("RandomTestingMenu0001")
    check("the window is built", gui ~= nil)

    local main: any = gui and gui:FindFirstChild("Main")
    check("the old shell frame is gone", main == nil, main and "Main still exists" or "no Main")
    local bin: any = gui and gui:FindFirstChild("CardBin")
    check("the card bin exists", bin ~= nil, gui and "no CardBin" or "no ScreenGui")

    -- Wurst's layout. The ClickGUI does not draw the cards, it places them, so
    -- what is checked is that every category has a window and that every card
    -- the menu built ended up inside one of them — a card parented anywhere
    -- else is a module the player cannot reach.
    local clickGui: any = shellState and shellState.clickGui
    check("the ClickGUI started", clickGui ~= nil)
    if clickGui then
        local built: number = 0
        local placed: number = 0
        for _, name: string in ipairs(clickGui.order) do
            local record: any = clickGui.categories[name]
            built += 1
            placed += record.count
        end
        -- Five populated official categories at boot (Combat, Render,
        -- Movement, Fun, Other); Blocks, Items and Chat are empty and must
        -- not draw a window.
        check("a window per populated category", built >= 5, tostring(built) .. " windows")
        -- Rejoin Server is one of the frozen 38 universal entries, but Wurst
        -- exposes it as a management action rather than a hack card. The other
        -- 37 entries (plus any game cards) must be in category windows, and
        -- Rejoin must be reachable through Wurst Options.
        local optionActions: {string} = shellState.wurstOptions
            and shellState.wurstOptions.List()
            or {}
        check(
            "every universal entry is reachable as a card or Wurst Options action",
            placed >= 37 and table.find(optionActions, "RejoinServer") ~= nil,
            tostring(placed) .. " cards; Rejoin="
                .. tostring(table.find(optionActions, "RejoinServer") ~= nil)
        )
        check(
            "the grid does not start every window in the same corner",
            clickGui.categories.Combat ~= nil
                and clickGui.categories.Movement ~= nil
                and clickGui.categories.Combat.window.root.Position
                    ~= clickGui.categories.Movement.window.root.Position
        )
    end

    local function findNamed(root: any, name: string): any
        if not root then
            return nil
        end
        if root.Name == name then
            return root
        end
        return root:FindFirstChild(name)
            or (function(): any
                for _, child: any in ipairs(root:GetDescendants()) do
                    if child.Name == name then
                        return child
                    end
                end
                return nil
            end)()
    end

    check(
        "the old rail Universal tab is gone",
        findNamed(gui, "UniversalDefaultTab") == nil
    )
    check(
        "the old rail Spoof tab is gone",
        findNamed(gui, "SpoofDefaultTab") == nil
    )
    check(
        "the old rail Config. tab is gone",
        findNamed(gui, "Config.DefaultTab") == nil
    )

    check("state was captured", shellState ~= nil)
    check(
        "the menu starts hidden",
        shellState ~= nil and shellState.visible == false
    )
    check(
        "destruct is published",
        shellState ~= nil and type(shellState.destruct) == "function"
    )

    section("Shell integration boot")

    -- The assertion that would have caught this morning's bug in the first
    -- minute: five modules called `host.addFeatureTooltip`, the shell had
    -- never published it, and nothing counted the cards that never appeared.
    check(
        "the bootstrap accepted the bundle",
        shellState ~= nil
            and shellState.boot ~= nil
            and type(shellState.boot.bundle) == "table",
        shellState and shellState.boot and "no bundle table" or "no state"
    )
    check(
        "every manifest module started",
        moduleCountOf(boot) == expectedModules,
        string.format("%s/%s", tostring(moduleCountOf(boot)), tostring(expectedModules))
    )
    check(
        "headless boot stays inside the time budget",
        boot.elapsed <= BUDGET_BOOT_SECONDS,
        string.format("%.3fs", boot.elapsed)
    )

    local search: any = shellState and shellState.moduleSearch
    check("module search is published independently of ClickGUI",
        type(search) == "table"
            and type(search.Resolve) == "function"
            and type(search.Execute) == "function")
    check("module search contains exactly the 38-module inventory",
        search ~= nil and #search.entries == 38,
        search and tostring(#search.entries) or "missing")
    for query: string, expected: string in pairs({
        ESP = "PlayerESP",
        PlayerESP = "PlayerESP",
        ItemESP = "ItemESP",
        AutoClicker = "Auto Clicker",
        KillAura = "Killaura",
        Killaura = "Killaura",
        Fly = "Flight",
        Speed = "SpeedHack",
        NoFall = "NoFall",
    }) do
        local result: any = search and search.Resolve(query)
        check("module search alias " .. query,
            result ~= nil and result.status == "success"
                and result.entry.displayName == expected,
            result and result.status or "missing")
    end
    check("module search normalizes spaces, hyphens and underscores",
        search.Resolve("PLAYER_ E-S-P").status == "success")
    check("module search never fuzzy-matches partial input",
        search.Resolve("Fl").status == "not_found")
    check("empty module search does nothing",
        search.Resolve("").status == "not_found")
    check("unknown module search does nothing",
        search.Resolve("definitely-not-a-module").status == "not_found")
    local duplicateA: any = {
        name = "Collision", configKey = "Test.A", kind = "toggle",
        searchable = true, enabled = false, activate = function(): () end,
    }
    local duplicateB: any = {
        name = "Colli-sion", configKey = "Test.B", kind = "toggle",
        searchable = true, enabled = false, activate = function(): () end,
    }
    search.Register(duplicateA)
    search.Register(duplicateB)
    check("duplicate normalized names are ambiguous",
        search.Resolve("collision").status == "ambiguous")
    search.Unregister(duplicateA)
    search.Unregister(duplicateB)
    check("sensitive Wurst Options actions are excluded",
        search.Resolve("Rejoin Server").status == "not_found"
            and search.Resolve("Destruct").status == "not_found"
            and search.Resolve("Reinject latest").status == "not_found")
    check("group cards cannot be executed from quick search",
        search.Execute("Projectile Calibration").status == "not_toggleable")

    local flightBefore: any = search.Resolve("Flight")
    local wasEnabled: boolean = flightBefore.entry.enabled()
    local executed: any = search.Execute("Fly")
    check("Execute toggles one exact module once",
        executed.status == "success"
            and flightBefore.entry.enabled() ~= wasEnabled)
    search.Execute("Flight")
    check("second exact Execute restores the module",
        flightBefore.entry.enabled() == wasEnabled)

    local inputService: any = world.services.UserInputService
    -- Official Wurst: RightCtrl opens ClickGUI, RightShift opens Navigator.
    -- The mock used to omit RightControl, so the shell fell back to
    -- RightShift. Drive whatever key it actually published.
    local toggleKey: any = shellState and shellState.toggleKey
        or world.globals.Enum.KeyCode.RightControl
    local function pressToggle(): ()
        inputService.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.Keyboard,
            KeyCode = toggleKey,
        }, false)
    end

    pressToggle()
    check(
        "the toggle key opens the menu",
        shellState ~= nil and shellState.visible == true
            and clickGui ~= nil and clickGui.categories.Combat ~= nil
            and clickGui.categories.Combat.window.root.Visible == true
    )
    pressToggle()
    check(
        "the toggle key closes the menu",
        shellState ~= nil and shellState.visible == false
            and clickGui ~= nil and clickGui.categories.Combat ~= nil
            and clickGui.categories.Combat.window.root.Visible == false
    )

    if shellState and type(shellState.destruct) == "function" then
        shellState.destruct()
    end
    check("destruct removes module search and its callbacks",
        shellState == nil or shellState.moduleSearch == nil)
    check(
        "destruct removes the window",
        gui == nil or gui.Parent == nil or gui.Destroyed == true
    )
    local blur: any = world.services.Lighting:FindFirstChild("RandomTestingMenu0001Blur")
    check("destruct removes the blur", blur == nil or blur.Parent == nil)
    check(
        "destruct leaves no heartbeat listeners",
        world.services.RunService.Heartbeat:Count() == 0,
        "listeners: " .. tostring(world.services.RunService.Heartbeat:Count())
    )
    check(
        "destruct leaves no input listeners",
        inputService.InputBegan:Count() == 0,
        "listeners: " .. tostring(inputService.InputBegan:Count())
    )

    section("Shell recovery boot")

    -- The bundle is gone. Every other repository file is served from the
    -- same `files` table the production path compiled as one module, which
    -- is what `downloadSourcesParallel` is for. A 404 for anything else
    -- (assets, a game module) is the honest answer: those are not in the
    -- startup bundle.
    local recoveryGet = function(_self: any, url: any, _cache: any): string
        if type(url) == "string"
            and string.find(url, "runtime/bundle.luau", 1, true) then
            return "404: Not Found"
        end
        local path: string? = pathFromUrl(url)
        local files: any = packed.files
        if path and type(files) == "table" and type(files[path]) == "string" then
            return files[path]
        end
        return "404: Not Found"
    end

    local recovered: any = bootOnce(recoveryGet)
    check("recovery compiles", recovered.compiled == true, tostring(recovered.compileError))
    check("recovery runs", recovered.ran == true, tostring(recovered.failure))
    check(
        "recovery refused the missing bundle",
        recovered.state ~= nil
            and recovered.state.boot ~= nil
            and recovered.state.boot.bundle == nil,
        recovered.state and recovered.state.boot and "bundle was accepted" or "no state"
    )
    check(
        "recovery still started every module",
        moduleCountOf(recovered) == expectedModules,
        string.format(
            "%s/%s",
            tostring(moduleCountOf(recovered)),
            tostring(expectedModules)
        )
    )

    if recovered.state and type(recovered.state.destruct) == "function" then
        recovered.state.destruct()
    end
end
