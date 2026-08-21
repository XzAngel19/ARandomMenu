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
-- The loader used to be tested against a stub HttpGet that compiled into an
-- empty module. Five of thirty-eight modules then died on a real client for a
-- week because they called a host field the shell never published, and every
-- check here stayed green. Feeding the real bundle is what makes
-- `moduleCount == #manifest.modules` a question this suite can answer.

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

    local world: any = Mock.install()
    local playerGui: any = Mock.newInstance("PlayerGui")
    playerGui.Name = "PlayerGui"
    playerGui.Parent = world.localPlayer

    local chunk: any, compileError: any = loadstring(source, "@ARandomMenu.luau")
    check("the shell compiles", type(chunk) == "function", tostring(compileError))
    if type(chunk) ~= "function" then
        return
    end

    Mock.inject(world, chunk)
    local environment: any = getfenv(chunk)
    local shellState: any = nil
    local realSetfenv: any = environment.setfenv
    environment.setfenv = function(fn: any, env: any): any
        if type(env) == "table" and env.state ~= nil then
            shellState = env.state
        end
        return realSetfenv(fn, env)
    end

    -- Production path: one HttpGet for the stamped bundle, then every file
    -- the manifest names is compiled out of `packed.files`. The stub that
    -- used to sit here compiled into `{stamp="", files={}}`, which the
    -- loader rejected, so kernel, libraries and the 38 modules never ran.
    if type(bundleSource) == "string" then
        local originalHttpGet: any = world.globals.game.HttpGet
        world.globals.game.HttpGet = function(self: any, url: any, cache: any): string
            if type(url) == "string"
                and string.find(url, "runtime/bundle.luau", 1, true) then
                return bundleSource
            end
            return originalHttpGet(self, url, cache)
        end
    end

    -- Wall-clock of the real bootstrap, not the mocked os.clock. A real
    -- client does this in 0.59s; headless also has to compile the bundle.
    -- Raise the number only with a comment saying what got more expensive.
    local BUDGET_BOOT_SECONDS: number = 1.5
    local bootStarted: number = os.clock()
    local ran: boolean, failure: any = xpcall(chunk, function(message: any): string
        return tostring(message)
    end)
    local bootElapsed: number = os.clock() - bootStarted
    check("the shell runs", ran == true, tostring(failure))

    local gui: any = playerGui:FindFirstChild("RandomTestingMenu0001")
        or world.services.CoreGui:FindFirstChild("RandomTestingMenu0001")
    check("the window is built", gui ~= nil)

    local main: any = gui and gui:FindFirstChild("Main")
    check("the shell frame exists", main ~= nil, gui and "no Main" or "no ScreenGui")

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
        "the rail has the Universal tab",
        findNamed(gui, "UniversalDefaultTab") ~= nil
    )
    check(
        "the rail has the Spoof tab",
        findNamed(gui, "SpoofDefaultTab") ~= nil
    )
    check(
        "the rail has the Config. tab",
        findNamed(gui, "Config.DefaultTab") ~= nil
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
    local manifest: any = require("../../../src/core/Manifest")
    local expectedModules: number = type(manifest.modules) == "table"
        and #manifest.modules
        or 0
    local startedModules: number = shellState
        and shellState.boot
        and tonumber(shellState.boot.timing.moduleCount)
        or -1
    check(
        "the bootstrap accepted the bundle",
        shellState ~= nil
            and shellState.boot ~= nil
            and type(shellState.boot.bundle) == "table",
        shellState and shellState.boot and "no bundle table" or "no state"
    )
    check(
        "every manifest module started",
        startedModules == expectedModules,
        string.format("%s/%s", tostring(startedModules), tostring(expectedModules))
    )
    check(
        "headless boot stays inside the time budget",
        bootElapsed <= BUDGET_BOOT_SECONDS,
        string.format("%.3fs", bootElapsed)
    )

    local inputService: any = world.services.UserInputService
    local function pressToggle(): ()
        inputService.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.Keyboard,
            KeyCode = world.globals.Enum.KeyCode.RightShift,
        }, false)
    end

    pressToggle()
    check(
        "the toggle key opens the menu",
        shellState ~= nil and shellState.visible == true
            and main ~= nil and main.Visible == true
    )
    pressToggle()
    check(
        "the toggle key closes the menu",
        shellState ~= nil and shellState.visible == false
            and main ~= nil and main.Visible == false
    )

    if shellState and type(shellState.destruct) == "function" then
        shellState.destruct()
    end
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
end
