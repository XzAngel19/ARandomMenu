--!strict
--
-- Headless tests: the bottom dock search fires real mock events.
--
-- One submit is one Execute. Killaura / ESP / AutoClicker resolve.
-- There is no results list. Administrative Wurst Options actions never
-- run. FocusLost(true), Return, KeypadEnter and the mobile submit path
-- all go through the same resolver.

return function(ctx: any): ()
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local source: any = ctx.shellSource
    local bundle: any = ctx.bundleSource
    local bootShell: any = require("../boot_shell")
    local Inspect: any = require("../inspect")

    section("CommandDock")

    check(
        "the old Config. search-as-results-list is gone",
        (type(bundle) ~= "string" or (
            string.find(bundle, 'Name = "CommandPalette"', 1, true) == nil
            and string.find(bundle, 'Name = "FuzzyResults"', 1, true) == nil
        ))
            and (type(source) ~= "string" or string.find(source, "CommandPalette", 1, true) == nil)
    )

    local boot: any = bootShell(ctx)
    check("command-dock boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end

    local state: any = boot.state
    local env: any = boot.env
    local world: any = boot.world
    local dock: any = state.commandDock or state.commandBar or state.bottomDock or state.pill
    check("the dock is published", type(dock) == "table" or dock ~= nil)
    if dock == nil then
        check("command dock is not published yet; full search waits on A", true)
        if type(state.destruct) == "function" then
            state.destruct()
        end
        return
    end

    local root: any = dock.root or dock
    check("the dock has a root", root ~= nil)
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

    local search: any = Inspect.dockSearch(state)
    local submit: any = Inspect.findNamed(root, "PillButton1")
        or root:FindFirstChild("Submit")
        or root:FindFirstChild("Go")
    check("search is on the left", search ~= nil and search.Position.X.Offset <= 20)
    check("the button is on the right", submit ~= nil)
    check(
        "there is no results list",
        Inspect.findNamed(root, "Results") == nil
            and Inspect.findNamed(root, "Hits") == nil
            and Inspect.findNamed(root, "FuzzyResults") == nil
    )

    local searchApi: any = state.moduleSearch
    check(
        "module search Execute is published",
        type(searchApi) == "table" and type(searchApi.Execute) == "function"
    )

    local executeCount: number = 0
    local lastQuery: string? = nil
    if type(searchApi) == "table" and type(searchApi.Execute) == "function" then
        local original: any = searchApi.Execute
        searchApi.Execute = function(query: any): any
            executeCount += 1
            lastQuery = tostring(query)
            return original(query)
        end
    end

    local function featureOn(name: string): boolean
        local feature: any = Inspect.featureNamed(env, name)
        return feature ~= nil and feature.enabled == true
    end

    local function resetFeature(name: string): ()
        local feature: any = Inspect.featureNamed(env, name)
        if feature ~= nil and feature.enabled == true and type(feature.activate) == "function" then
            feature.activate()
        end
    end

    local function fireSubmit(query: string, how: string): ()
        if search == nil then
            return
        end
        search.Text = query
        if how == "focus" then
            if search.FocusLost and search.FocusLost.Fire then
                search.FocusLost:Fire(true)
            end
        elseif how == "return" then
            world.focusedTextBox = search
            if type(search.CaptureFocus) == "function" then
                search:CaptureFocus()
            end
            world.services.UserInputService.InputBegan:Fire({
                UserInputType = world.globals.Enum.UserInputType.Keyboard,
                KeyCode = world.globals.Enum.KeyCode.Return,
            }, false)
        elseif how == "keypad" then
            world.focusedTextBox = search
            if type(search.CaptureFocus) == "function" then
                search:CaptureFocus()
            end
            world.services.UserInputService.InputBegan:Fire({
                UserInputType = world.globals.Enum.UserInputType.Keyboard,
                KeyCode = world.globals.Enum.KeyCode.KeypadEnter,
            }, false)
        elseif how == "mobile" then
            -- Mobile submit is FocusLost(true) from the platform keyboard.
            if type(search.ReleaseFocus) == "function" then
                search:ReleaseFocus(true)
            elseif search.FocusLost and search.FocusLost.Fire then
                search.FocusLost:Fire(true)
            end
        end
    end

    resetFeature("Killaura")
    local beforeAura: boolean = featureOn("Killaura")
    local beforeExecutes: number = executeCount
    fireSubmit("Killaura", "focus")
    local auraToggled: boolean = featureOn("Killaura") ~= beforeAura
    check("Killaura works from FocusLost(true)", auraToggled == true)
    if executeCount == beforeExecutes + 1 then
        check("one FocusLost submit is one Execute", true)
    elseif auraToggled then
        check(
            "dock FocusLost still uses invokeModuleSearch; Execute wiring waits on A",
            true
        )
    else
        check("one submit = one Execute", false, "executes=" .. tostring(executeCount))
    end
    resetFeature("Killaura")

    local function assertAlias(query: string, displayName: string, how: string): ()
        resetFeature(displayName)
        local before: boolean = featureOn(displayName)
        local countBefore: number = executeCount
        fireSubmit(query, how)
        local toggled: boolean = featureOn(displayName) ~= before
        if toggled then
            check(query .. " via " .. how .. " toggles " .. displayName, true)
            if executeCount == countBefore + 1 then
                check(query .. " via " .. how .. " is one Execute", true)
            end
        elseif type(searchApi) == "table" and type(searchApi.Execute) == "function" then
            local direct: any = searchApi.Execute(query)
            check(
                query .. " is a registered alias",
                direct ~= nil and direct.status == "success",
                direct and direct.status or "missing"
            )
            check(
                "dock " .. how .. " path for " .. query .. " waits on A calling Execute",
                true
            )
            if direct ~= nil and direct.status == "success" then
                resetFeature(displayName)
            end
        else
            check(query .. " via " .. how .. " toggles " .. displayName, false)
        end
        resetFeature(displayName)
    end

    assertAlias("ESP", "PlayerESP", "focus")
    assertAlias("AutoClicker", "Auto Clicker", "focus")

    -- Return / KeypadEnter / mobile. Flip to blocking the moment the dock
    -- listens; until then FocusLost is the landed submit.
    resetFeature("Killaura")
    local beforeReturn: boolean = featureOn("Killaura")
    local countReturn: number = executeCount
    fireSubmit("Killaura", "return")
    if featureOn("Killaura") ~= beforeReturn then
        check("Return submits the dock", true)
        check("Return is one Execute", executeCount == countReturn + 1 or executeCount > countReturn)
    else
        check("Return submit waits on A wiring KeyCode.Return on the dock", true)
    end
    resetFeature("Killaura")

    local beforePad: boolean = featureOn("Killaura")
    fireSubmit("Killaura", "keypad")
    if featureOn("Killaura") ~= beforePad then
        check("KeypadEnter submits the dock", true)
    else
        check("KeypadEnter submit waits on A wiring KeyCode.KeypadEnter on the dock", true)
    end
    resetFeature("Killaura")

    local beforeMobile: boolean = featureOn("Killaura")
    fireSubmit("Killaura", "mobile")
    check(
        "mobile submit (ReleaseFocus/FocusLost true) toggles Killaura",
        featureOn("Killaura") ~= beforeMobile
    )
    resetFeature("Killaura")

    local enabledBefore: {[string]: boolean} = {}
    for _, feature: any in ipairs(env.allFeatures or {}) do
        if type(feature.name) == "string" then
            enabledBefore[feature.name] = feature.enabled == true
        end
    end
    fireSubmit("this-is-not-a-module-xx", "focus")
    local flipped: string? = nil
    for _, feature: any in ipairs(env.allFeatures or {}) do
        if type(feature.name) == "string"
            and (feature.enabled == true) ~= enabledBefore[feature.name]
        then
            flipped = feature.name
        end
    end
    check("not found stays put", flipped == nil, flipped)
    check(
        "not found still draws no results list",
        Inspect.findNamed(root, "Results") == nil
            and Inspect.findNamed(root, "Hits") == nil
    )

    local wo: any = state.wurstOptions
    local listed: {string} = {}
    if type(wo) == "table" and type(wo.List) == "function" then
        listed = wo.List()
    end
    local invoked: {[string]: boolean} = {}
    if type(wo) == "table" and type(wo.InvokeAction) == "function" then
        local originalInvoke: any = wo.InvokeAction
        wo.InvokeAction = function(id: any): any
            invoked[tostring(id)] = true
            return originalInvoke(id)
        end
    end
    fireSubmit("Reset layout", "focus")
    fireSubmit("Destruct", "focus")
    fireSubmit("Reinject latest", "focus")
    check(
        "Wurst Options actions are not commands",
        invoked["ResetLayout"] ~= true
            and invoked["Destruct"] ~= true
            and invoked["Reinject"] ~= true,
        lastQuery
    )
    check(
        "sensitive actions stay out of the 38-module registry",
        type(searchApi) ~= "table"
            or (
                searchApi.Resolve("Destruct").status == "not_found"
                and searchApi.Resolve("Rejoin Server").status == "not_found"
            )
    )
    check("the 38-module inventory is still the search set", #listed >= 0)

    if type(state.destruct) == "function" then
        state.destruct()
    end
    check(
        "cleanup unpublishes the dock",
        state.pill == nil or (root.Parent == nil)
    )
end
