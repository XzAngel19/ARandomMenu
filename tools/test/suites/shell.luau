--!strict
--
-- Headless tests: the shell.
--
-- ARandomMenu.luau is the window, the rail and the loader, and nothing else
-- in the suite ever executed it. The CLI has no filesystem API, so
-- tools/validate.sh emits tools/test/_shell_source.luau (the bootstrap as a
-- string) before this runs.

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

    local ran: boolean, failure: any = xpcall(chunk, function(message: any): string
        return tostring(message)
    end)
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
