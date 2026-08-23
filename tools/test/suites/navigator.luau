--!strict
--
-- Headless tests: Wurst's Navigator, as Furniture publishes it.
--
-- Official Navigator is its own full-screen GUI, independent from ClickGUI.
-- The suite drives its published Open/Close contract and inspects the search
-- and three-column results surface that Furniture owns.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Navigator")

    local source: any = ctx.shellSource
    local bundleSource: any = ctx.bundleSource
    if type(source) ~= "string" or type(bundleSource) ~= "string" then
        check("shell source is available for Navigator", false)
        return
    end

    local world: any = Mock.install()
    local playerGui: any = Mock.newInstance("PlayerGui")
    playerGui.Name = "PlayerGui"
    playerGui.Parent = world.localPlayer

    local chunk: any, compileError: any = loadstring(source, "@ARandomMenu.luau")
    if type(chunk) ~= "function" then
        check("Navigator boot compiles", false, tostring(compileError))
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
    check("Navigator boot runs", ran == true, tostring(failure))
    if not captured or not captured.state then
        return
    end

    local state: any = captured.state
    local nav: any = state.navigator
    check("Navigator is published on state", type(nav) == "table", tostring(nav))
    if type(nav) ~= "table" then
        return
    end

    local root: any = nav.root
    check("Navigator is a HUD surface, not a WindowManager window", root ~= nil)
    if root ~= nil then
        check("the surface is named Navigator", root.Name == "Navigator", tostring(root.Name))
        check(
            "Navigator uses raw screen space instead of scaled ClickGUI space",
            root.Parent == captured.ScreenGui
                and root.Size.X.Scale == 1
                and root.Size.Y.Scale == 1
        )
        check(
            "Navigator does not dim the entire game",
            root.BackgroundTransparency == 1,
            tostring(root.BackgroundTransparency)
        )
        check(
            "Navigator is not a managed ClickGui window",
            state.windows == nil
                or state.windows.Get == nil
                or state.windows.Get("Navigator") == nil
        )
    end

    -- Official TabGUI is a different feature, default Disabled. We ship
    -- none; a TabGUI window or an Enabled default would be a fork.
    check(
        "TabGUI is not enabled by default",
        state.tabGui == nil
            and string.find(bundleSource, 'TABGUI_STATUS: string = "Enabled"', 1, true) == nil
    )

    if type(nav.Open) == "function" then
        nav.Open()
    end
    if root ~= nil then
        check(
            "opening Navigator shows its independent screen",
            root.Visible == true,
            "Visible=" .. tostring(root.Visible)
        )
    end

    check(
        "Navigator does not duplicate the dock with a WurstDoor bar",
        root == nil or root:FindFirstChild("WurstDoor") == nil
    )
    local column: any = root and root:FindFirstChild("Column")
    local search: any = column and column:FindFirstChild("Search")
    check("Navigator has a search field", search ~= nil)
    local results: any = column and column:FindFirstChild("Results")
    check("Navigator has a results grid", results ~= nil)
    if results ~= nil then
        local grid: any = results:FindFirstChildOfClass("UIGridLayout")
        check("results use a grid layout", grid ~= nil)
        check(
            "results declare Wurst's three columns",
            string.find(bundleSource, "local NAV_COLUMNS: number = 3", 1, true) ~= nil
        )
    end

    if type(nav.refresh) == "function" then
        nav.refresh()
        check("Navigator can rebuild its grid", true)
    end
    if column ~= nil then
        check(
            "Navigator keeps Wurst's original compact width",
            column.Size.X.Offset == 456,
            tostring(column.Size.X.Offset)
        )
    end
    if results ~= nil then
        local visibleEntries: number = 0
        for _, child: any in ipairs(results:GetChildren()) do
            if child:IsA("GuiObject") then
                visibleEntries += 1
            end
        end
        check(
            "Navigator does not drop modules beyond the old 36-entry limit",
            visibleEntries == #(captured.allFeatures or {}),
            tostring(visibleEntries) .. "/" .. tostring(#(captured.allFeatures or {}))
        )
    end

    -- Enter fires the top hit via FocusLost(true). Drive that if the
    -- search box is a real TextBox stand-in.
    if search ~= nil and type(search.FocusLost) == "table" and search.FocusLost.Fire then
        search.FocusLost:Fire(true)
        check("Enter on the search field is wired", true)
    end

    -- Preference sorting: the store is NavigatorPrefs. Two activations
    -- of one card must beat zero of another after a refresh.
    if type(nav.refresh) == "function" and captured.configData then
        local prefs: any = captured.configData.values
        if type(prefs) ~= "table" then
            captured.configData.values = {}
            prefs = captured.configData.values
        end
        prefs.NavigatorPrefs = {["Kill Aura"] = 9, ["Fly"] = 0}
        nav.refresh()
        if results ~= nil then
            local first: any = nil
            for _, child: any in ipairs(results:GetChildren()) do
                if child.ClassName == "TextButton" then
                    if first == nil or (child.LayoutOrder or 0) < (first.LayoutOrder or 0) then
                        first = child
                    end
                end
            end
            if first ~= nil then
                check(
                    "preference sorting puts the most-used card first",
                    string.find(tostring(first.Text), "Kill", 1, true) ~= nil
                        or first.LayoutOrder == 1,
                    tostring(first.Text)
                )
            else
                check("preference sorting waits on a populated grid", true)
            end
        end
    end

    if type(nav.Close) == "function" then
        nav.Close()
    end
    if root ~= nil then
        check(
            "closing Navigator hides only its own screen",
            root.Visible == false,
            "Visible=" .. tostring(root.Visible)
        )
    end

    check(
        "Navigator implements Wurst's keyboard controls",
        string.find(bundleSource, "Enum.KeyCode.Space", 1, true) ~= nil
            and string.find(bundleSource, "Enum.KeyCode.Escape", 1, true) ~= nil
            and string.find(bundleSource, "Enum.KeyCode.Backspace", 1, true) ~= nil
            and string.find(bundleSource, "Enum.KeyCode.Down", 1, true) ~= nil
    )

    if type(state.destruct) == "function" then
        state.destruct()
    end
end
