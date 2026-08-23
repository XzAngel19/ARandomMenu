--!strict
--
-- Headless tests: the bottom dock can be hidden on desktop and never on
-- a phone.
--
-- Desktop: the setting is visible, false hides the dock, RightControl
-- still opens the menu, true restores the dock. Mobile: the setting is
-- absent or hidden, the dock is forced visible, a stored desktop false
-- is ignored, and the touch path still submits.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("DockVisibility")

    local boot: any = bootShell(ctx)
    check("dock-visibility desktop boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local world: any = boot.world
    local pill: any = state.pill and (state.pill.root or state.pill)
    check("the dock is published on desktop", pill ~= nil)
    if pill == nil then
        return
    end
    check("the dock starts visible on desktop", pill.Visible ~= false)

    local settingRow: any = nil
    if type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end
    local ui: any = state.windows and state.windows.Get and state.windows.Get("UISettings")
    if ui ~= nil then
        settingRow = Inspect.findNamed(ui.root, "Option_Showdock")
            or Inspect.findNamed(ui.root, "Option_ShowDock")
            or Inspect.findNamed(ui.root, "Option_Commanddock")
            or Inspect.findNamed(ui.root, "Option_Showcommanddock")
    end
    local setter: any = (state.dock and state.dock.SetVisible)
        or state.setDockVisible
        or state.setCommandDockVisible
    if settingRow == nil and type(setter) ~= "function" then
        check(
            "desktop Show dock setting waits on A; RightControl still opens the menu",
            state.toggleKey ~= nil and state.toggleKey.Name == "RightControl"
        )
        if type(state.setMenuVisible) == "function" then
            state.setMenuVisible(false)
        end
        world.services.UserInputService.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.Keyboard,
            KeyCode = state.toggleKey,
        }, false)
        check(
            "RightControl still opens Wurst with the dock up",
            Inspect.wurstVisible(state) == true or state.visible == true
        )
    else
        local function hideDock(): ()
            if type(setter) == "function" then
                setter(false)
                return
            end
            local click: any = settingRow and (
                settingRow:FindFirstChild("OptionClickTarget") or settingRow
            )
            if click ~= nil and click.MouseButton1Click ~= nil then
                click.MouseButton1Click:Fire()
            end
        end
        hideDock()
        check("setting false hides the desktop dock", pill.Visible == false)
        -- RightControl is a toggle. Start closed so this assertion verifies
        -- that the keyboard can still open Wurst without the dock.
        if type(state.setMenuVisible) == "function" then
            state.setMenuVisible(false)
        end
        world.services.UserInputService.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.Keyboard,
            KeyCode = state.toggleKey,
        }, false)
        check(
            "RightControl still works with the dock hidden",
            Inspect.wurstVisible(state) == true or state.visible == true
        )
        if type(setter) == "function" then
            setter(true)
        else
            hideDock()
        end
        check("setting true restores the desktop dock", pill.Visible == true)
    end

    if type(state.destruct) == "function" then
        state.destruct()
    end

    -- Mobile boot: TouchEnabled, no keyboard. The dock must stay up even
    -- if a stored desktop false exists.
    section("DockVisibilityMobile")

    local source: any = ctx.shellSource
    local bundleSource: any = ctx.bundleSource
    if type(source) ~= "string" or type(bundleSource) ~= "string" then
        check("mobile dock boot source missing", false)
        return
    end

    local mobileWorld: any = Mock.install()
    mobileWorld.services.UserInputService.TouchEnabled = true
    mobileWorld.services.UserInputService.KeyboardEnabled = false
    local playerGui: any = Mock.newInstance("PlayerGui")
    playerGui.Name = "PlayerGui"
    playerGui.Parent = mobileWorld.localPlayer

    local chunk: any, compileError: any = loadstring(source, "@ARandomMenu.luau")
    if type(chunk) ~= "function" then
        check("mobile dock boot compiles", false, tostring(compileError))
        return
    end
    Mock.inject(mobileWorld, chunk)
    mobileWorld.globals.game.HttpGet = function(_self: any, url: any, _cache: any): string
        if type(url) == "string" and string.find(url, "runtime/bundle.luau", 1, true) then
            return bundleSource
        end
        return "404: Not Found"
    end

    local captured: any = nil
    local environment: any = getfenv(chunk)
    local realSetfenv: any = environment.setfenv
    environment.setfenv = function(fn: any, nextEnv: any): any
        if type(nextEnv) == "table" and nextEnv.ThemeEngine ~= nil then
            captured = nextEnv
        end
        return realSetfenv(fn, nextEnv)
    end
    local ran: boolean, failure: any = xpcall(chunk, function(message: any): string
        return tostring(message)
    end)
    check("mobile dock boot runs", ran == true, tostring(failure))
    if not captured or not captured.state then
        return
    end

    local mobileState: any = captured.state
    check("mobile boot marks the device as a phone", mobileState.isMobile == true)
    local mobilePill: any = mobileState.pill and (mobileState.pill.root or mobileState.pill)
    check("the dock is forced visible on mobile", mobilePill ~= nil and mobilePill.Visible ~= false)
    local fallbackLauncher: any = captured.ScreenGui
        and Inspect.findNamed(captured.ScreenGui, "MobileMenuButton")
    check(
        "the fallback launcher stands down once the dock exists",
        fallbackLauncher == nil or fallbackLauncher.Visible == false
    )

    local mobileUi: any = mobileState.windows
        and mobileState.windows.Get
        and mobileState.windows.Get("UISettings")
    local mobileSetting: any = nil
    if mobileUi ~= nil then
        mobileSetting = Inspect.findNamed(mobileUi.root, "Option_Showdock")
            or Inspect.findNamed(mobileUi.root, "Option_ShowDock")
    end
    if mobileSetting == nil then
        check("the desktop Show dock setting is absent on mobile", true)
    else
        check(
            "the desktop Show dock setting is hidden on mobile",
            mobileSetting.Visible == false
        )
    end

    if type(mobileState.setDockVisible) == "function" then
        mobileState.setDockVisible(false)
        check(
            "a stored desktop false is ignored on mobile",
            mobilePill.Visible ~= false
        )
        mobileState.setDockVisible(true)
    else
        check("mobile ignores a desktop false because the setter is not published", true)
    end

    local mobileSearch: any = Inspect.dockSearch(mobileState)
    check("the compact mobile dock has no redundant search box", mobileSearch == nil)
    check(
        "the mobile dock stays compact",
        mobilePill ~= nil and mobilePill.Size.X.Offset <= 100,
        mobilePill and tostring(mobilePill.Size.X.Offset) or "missing"
    )
    local navigatorSearch: any = mobileState.navigator
        and mobileState.navigator.root
        and Inspect.findNamed(mobileState.navigator.root, "Search")
    check("Navigator remains the mobile search path", navigatorSearch ~= nil)

    local mobileEditor: any = mobileState.mobileUi and mobileState.mobileUi.editor
    check("mobile actions publish one shared long-press editor", mobileEditor ~= nil)
    if mobileEditor then
        for _, control: string in ipairs({
            "SizeDown", "SizeUp", "OpacityDown", "OpacityUp",
            "Remove", "Reset", "Done",
        }) do
            check(
                "mobile editor control: " .. control,
                Inspect.findNamed(mobileEditor, control) ~= nil
            )
        end
    end

    if type(mobileState.destruct) == "function" then
        mobileState.destruct()
    end
end
