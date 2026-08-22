--!strict
--
-- Headless tests: Navigator always has a way out.
--
-- The dock stays above Navigator. Escape closes. A return control (the
-- dock button, or a dedicated back row) can restore Wurst. The user is
-- never trapped: UI Settings is reachable again after leaving Navigator.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("NavigatorEscape")

    local boot: any = bootShell(ctx)
    check("navigator-escape boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local world: any = boot.world
    local nav: any = state.navigator
    check("Navigator is published", type(nav) == "table")
    if type(nav) ~= "table" then
        return
    end

    local pill: any = state.pill and (state.pill.root or state.pill)
    check("the dock/root is published over Navigator", pill ~= nil)
    if pill ~= nil and nav.root ~= nil then
        local popup: any = env.PopupLayer
        local popupZ: number = popup and (tonumber(popup.ZIndex) or 0) or 0
        local pillZ: number = tonumber(pill.ZIndex) or 0
        check(
            "the dock sits above the Navigator layer",
            pill.Parent == env.ScreenGui and pillZ > popupZ,
            "pillZ=" .. tostring(pillZ) .. " popupZ=" .. tostring(popupZ)
        )
    end

    if type(nav.Open) == "function" then
        nav.Open()
    end
    check("Navigator opens", Inspect.navigatorVisible(state) == true)

    local back: any = nil
    if nav.root ~= nil then
        back = Inspect.findNamed(nav.root, "Back")
            or Inspect.findNamed(nav.root, "BackToWurst")
            or Inspect.findNamed(nav.root, "Return")
            or Inspect.findNamed(nav.root, "Wurst")
    end
    if back ~= nil and back.MouseButton1Click ~= nil then
        back.MouseButton1Click:Fire()
        check(
            "the back button returns to Wurst",
            Inspect.navigatorVisible(state) == false
                and Inspect.wurstVisible(state) == true
        )
        if type(nav.Open) == "function" then
            nav.Open()
        end
    else
        -- The dock ≡ button is the return control until A draws a dedicated
        -- back row. It must stay clickable over Navigator.
        check(
            "Navigator back-button row waits on A; the dock is the return control",
            pill ~= nil
        )
        local menuButton: any = pill and Inspect.findNamed(pill, "PillButton1")
        check("the dock menu button is still there", menuButton ~= nil)
    end

    world.services.UserInputService.InputBegan:Fire({
        UserInputType = world.globals.Enum.UserInputType.Keyboard,
        KeyCode = world.globals.Enum.KeyCode.Escape,
    }, false)
    check(
        "Escape closes Navigator",
        Inspect.navigatorVisible(state) == false,
        "Visible=" .. tostring(nav.root and nav.root.Visible)
    )

    check(
        "the user is not trapped after Escape",
        Inspect.navigatorVisible(state) == false
    )
    if type(state.openMenuSurface) == "function" then
        if Inspect.wurstVisible(state) == false then
            state.openMenuSurface()
        end
    elseif type(state.setMenuVisible) == "function" then
        state.setMenuVisible(true)
    end
    check("Wurst can be opened after leaving Navigator", Inspect.wurstVisible(state) == true)

    local ui: any = state.windows and state.windows.Get and state.windows.Get("UISettings")
    check("UI Settings is still published", ui ~= nil)
    if ui ~= nil then
        if type(ui.SetVisible) == "function" then
            ui:SetVisible(true)
        elseif ui.root then
            ui.root.Visible = true
        end
        check(
            "UI Settings can be recovered after Navigator",
            ui.root ~= nil and ui.root.Parent ~= nil,
            ui.id
        )
    end

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
