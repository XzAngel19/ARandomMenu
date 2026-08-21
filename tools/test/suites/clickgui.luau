--!strict
--
-- Headless tests: the ClickGUI contract the rebuild has to keep.
--
-- ThemeEngine.Apply is live: a bound instance must repaint when the preset
-- changes, and the default preset is Wurst's own colours. WindowManager is
-- not published yet, so persistence / off-screen restore is skipped rather
-- than failed. The render bucket is what ESP draws on; a regression there
-- is a frame-rate regression in every game.
--
-- Boots the real shell, the same way the shell suite does, because the
-- palette and the engine live there — not on the host double.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("ClickGUI")

    local source: any = ctx.shellSource
    local bundleSource: any = ctx.bundleSource
    if type(source) ~= "string" or type(bundleSource) ~= "string" then
        check("shell source is available for ClickGUI", false, "no shell/bundle source")
        return
    end

    local world: any = Mock.install()
    local playerGui: any = Mock.newInstance("PlayerGui")
    playerGui.Name = "PlayerGui"
    playerGui.Parent = world.localPlayer

    local chunk: any, compileError: any = loadstring(source, "@ARandomMenu.luau")
    check("ClickGUI boot compiles", type(chunk) == "function", tostring(compileError))
    if type(chunk) ~= "function" then
        return
    end

    Mock.inject(world, chunk)
    world.globals.game.HttpGet = function(_self: any, url: any, _cache: any): string
        if type(url) == "string" and string.find(url, "runtime/bundle.luau", 1, true) then
            return bundleSource
        end
        return "404: Not Found"
    end

    local captured: any = nil
    local environment: any = getfenv(chunk)
    local realSetfenv: any = environment.setfenv
    environment.setfenv = function(fn: any, env: any): any
        if type(env) == "table" and env.ThemeEngine ~= nil then
            captured = env
        end
        return realSetfenv(fn, env)
    end

    local ran: boolean, failure: any = xpcall(chunk, function(message: any): string
        return tostring(message)
    end)
    check("ClickGUI boot runs", ran == true, tostring(failure))
    check("ThemeEngine was published into the module environment", captured ~= nil)

    if not captured then
        return
    end

    local Theme: any = captured.Theme
    local ThemeEngine: any = captured.ThemeEngine
    local rgb: any = world.globals.Color3.fromRGB

    local function channels(colour: any): (number, number, number)
        return math.round(colour.R * 255), math.round(colour.G * 255), math.round(colour.B * 255)
    end

    local function sameColour(colour: any, expected: any): boolean
        local r: number, g: number, b: number = channels(colour)
        local er: number, eg: number, eb: number = channels(expected)
        return r == er and g == eg and b == eb
    end

    -- Wurst's own defaults, taken from its wiki: background #404040, accent
    -- #101010, text #F0F0F0. The magenta most screenshots show is a theme a
    -- user picked, not what the client ships with.
    check("the default preset is named Wurst", ThemeEngine.name == "Wurst")
    check(
        "default surface is Wurst grey, not the old monochrome",
        sameColour(Theme.surface, rgb(64, 64, 64)),
        string.format("%d,%d,%d", channels(Theme.surface))
    )
    check(
        "default accent is Wurst chrome, not magenta",
        sameColour(Theme.accent, rgb(16, 16, 16)),
        string.format("%d,%d,%d", channels(Theme.accent))
    )
    check(
        "default text is Wurst off-white",
        sameColour(Theme.text, rgb(240, 240, 240)),
        string.format("%d,%d,%d", channels(Theme.text))
    )

    local bound: any = Mock.newInstance("Frame")
    bound.BackgroundColor3 = rgb(0, 0, 0)
    ThemeEngine.Bind(bound, "BackgroundColor3", "surface")
    check(
        "Bind paints the instance from the current token",
        sameColour(bound.BackgroundColor3, Theme.surface)
    )

    local positiveBefore: any = Theme.positive
    local applied: boolean = ThemeEngine.Apply("Monochrome")
    check("Apply accepts a named preset", applied == true)
    check("Apply records the preset name", ThemeEngine.name == "Monochrome")
    check(
        "a bound instance repaints instead of keeping a stale colour",
        sameColour(bound.BackgroundColor3, rgb(26, 26, 28)),
        string.format("%d,%d,%d", channels(bound.BackgroundColor3))
    )
    check(
        "semantic colours survive a preset, because a theme that recolours them lies",
        sameColour(Theme.positive, positiveBefore)
    )

    check("an unknown preset is refused", ThemeEngine.Apply("NoSuchPreset") == false)
    check("a refused Apply leaves the current name", ThemeEngine.name == "Monochrome")

    ThemeEngine.Apply("Wurst")
    check(
        "switching back restores the bound instance",
        sameColour(bound.BackgroundColor3, rgb(64, 64, 64))
    )

    -- WindowManager is the ClickGUI's layout store. It is not on the shell
    -- yet; failing here would red the gate for an API nobody has published.
    -- The floating layer already asserts reclamp, which is the off-screen
    -- half of the contract that *does* exist.
    if type(captured.WindowManager) == "table" then
        check("WindowManager is published", true)
    else
        check(
            "WindowManager is not published yet; persistence tests wait on it",
            captured.WindowManager == nil
        )
    end

    -- The render bucket runs before the frame it draws into. Firing it is
    -- what proves ESP (and anything else that moved off Heartbeat) still
    -- fits in a frame.
    local render: any = world.services.RunService.RenderStepped
    check(
        "the render bucket has listeners after boot",
        render:Count() > 0,
        "listeners: " .. tostring(render:Count())
    )
    local BUDGET_RENDER_FRAME_SECONDS: number = 0.010
    local renderPerFrame: number = ctx.measureFrames(function(_dt: number): ()
        render:Fire(0.016)
    end, 20)
    check(
        "RenderStepped stays inside the per-frame time budget",
        renderPerFrame <= BUDGET_RENDER_FRAME_SECONDS,
        string.format("%.4fs/frame", renderPerFrame)
    )

    if captured.state and type(captured.state.destruct) == "function" then
        captured.state.destruct()
    end
end
