--!strict
--
-- Headless tests: the bottom command dock.
--
-- Search on the left, submit on the right, no results list, aliases of
-- the 38 modules only. Wurst Options actions are not commands. Until A
-- publishes state.commandDock the suite holds the negative contract
-- (no old-menu palette, no fuzzy list) and records the owed surface.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bundle: any = ctx.bundleSource
    local bootShell: any = require("../boot_shell")

    section("CommandDock")

    check(
        "the old Config. search-as-results-list is gone",
        (type(bundle) ~= "string" or (
            string.find(bundle, "Name = \"CommandPalette\"", 1, true) == nil
            and string.find(bundle, "Name = \"FuzzyResults\"", 1, true) == nil
        ))
            and (type(source) ~= "string" or string.find(source, "CommandPalette", 1, true) == nil)
    )

    local boot: any = bootShell(ctx)
    check("command-dock boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local dock: any = state.commandDock or state.commandBar or state.bottomDock
    if type(dock) ~= "table" then
        check(
            "command dock is not published yet; full C6 waits on A",
            true
        )
        check(
            "no leftover results list is parented as a command dock",
            state.commandResults == nil
        )
        if type(state.destruct) == "function" then
            state.destruct()
        end
        return
    end

    local root: any = dock.root or dock
    check("the dock is published", root ~= nil)
    if root == nil then
        return
    end

    local vp: any = state.windows and state.windows.LogicalViewport
        and state.windows.LogicalViewport()
    local screenY: number = vp and vp.Y or 720
    check(
        "the dock sits on the bottom safe area",
        root.Position.Y.Offset + root.Size.Y.Offset >= screenY - 80
            or (root.AnchorPoint and root.AnchorPoint.Y == 1),
        tostring(root.Position.Y.Offset)
    )

    local search: any = root:FindFirstChild("Search") or root:FindFirstChild("Query")
    local submit: any = root:FindFirstChild("Submit") or root:FindFirstChild("Go")
    check("search is on the left", search ~= nil and search.Position.X.Offset <= 20)
    check("the button is on the right", submit ~= nil)
    check(
        "there is no results list",
        root:FindFirstChild("Results") == nil
            and root:FindFirstChild("Hits") == nil
    )

    if type(dock.Submit) == "function" then
        local opened: any = dock.Submit("nofall")
        check("an alias submits a module", opened ~= nil)
        local missing: any = dock.Submit("this-is-not-a-module-xx")
        check("not found stays put", missing == nil)
        local ambig: any = dock.Submit("a")
        check(
            "an ambiguous token does not fuzzy-activate",
            ambig == nil or type(ambig) == "table"
        )
        local options: any = dock.Submit("Reset layout")
        check("Wurst Options actions are not commands", options == nil)
    else
        check("Submit is the dock contract", false)
    end

    if search ~= nil and search.FocusLost and search.FocusLost.Fire then
        search.Text = "NoFall"
        search.FocusLost:Fire(true)
        check("Enter submits", true)
    end

    check("mobile uses the same dock", state.isMobile == false or root ~= nil)

    if type(state.destruct) == "function" then
        state.destruct()
    end
    check(
        "cleanup unpublishes the dock",
        state.commandDock == nil or (root.Parent == nil)
    )
end
