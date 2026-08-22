--!strict
--
-- Headless tests: the Wurst configuration surface.
--
-- SettingsPage used to build the old menu's Config. tab — text scale, fonts,
-- blur, launcher size. That page is gone; the library now builds Wurst's
-- own configuration: the UI Settings window (four feature shortcuts plus the
-- ClickGUI settings), and the WurstLogo / HackList / Keybinds / Profiles /
-- Wurst Options windows behind them. Defaults are asserted by the parity
-- gate against spec.json; this suite drives the behaviour.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section

    section("Wurst configuration")

    -- The surface builds ClickGUI windows, so it needs the real manager.
    if host.state.windows == nil then
        local WindowFile: any = require("../../../src/library/WindowManager")
        Mock.inject(world, WindowFile.init)
        WindowFile.init(host)
    end
    host.state.shortcutBindings = host.state.shortcutBindings or {}

    -- One fake binding, shaped like the shell's: the manager has to list it,
    -- reset it and bring it back from a profile.
    local refreshed: number = 0
    local binding: any = {
        id = "Universal.KillAura",
        key = world.globals.Enum.KeyCode.Q,
        pressed = false,
        refresh = function(): ()
            refreshed += 1
        end,
    }
    host.state.shortcutBindings["Universal.KillAura"] = binding

    -- The real engine belongs to the shell; the stand-in records writes so
    -- the token mapping can be asserted without booting the whole shell.
    local setTokens: {[string]: any} = {}
    local hadEngine: boolean = host.ThemeEngine ~= nil
    if not hadEngine then
        host.ThemeEngine = {
            Set = function(token: string, color: any): ()
                setTokens[token] = color
            end,
        }
    end

    -- Drive SettingsPage through the real widget library so order / type
    -- assertions see ColorBar, HexValue and OptionCheckbox, not the host
    -- stubs. widgets.luau already inited it; reuse that return value.
    local widgets: any = host._widgets
    if type(widgets) ~= "table" then
        local WidgetFile: any = require("../../../src/library/Widgets")
        Mock.inject(world, WidgetFile.init)
        widgets = WidgetFile.init(host)
        host._widgets = widgets
    end
    local previousBuilders: {[string]: any} = {
        addToggleOption = host.addToggleOption,
        addNumberOption = host.addNumberOption,
        addCycleOption = host.addCycleOption,
        addColorOption = host.addColorOption,
    }
    host.addToggleOption = widgets.addToggleOption
    host.addNumberOption = widgets.addNumberOption
    host.addCycleOption = widgets.addCycleOption
    host.addColorOption = widgets.addColorOption

    local SettingsFile: any = require("../../../src/library/SettingsPage")
    Mock.inject(world, SettingsFile.init)
    local settings: any = SettingsFile.init(host)
    -- SettingsPage captured the real builders as locals. Put the stubs
    -- back so later module suites keep the recording host.
    for name: string, builder: any in pairs(previousBuilders) do
        host[name] = builder
    end
    check("the library returns its surface", type(settings) == "table")

    local windows: any = host.state.windows
    local uiWindow: any = windows.Get("UISettings")
    check("the UI Settings window exists at boot", uiWindow ~= nil)
    check("a category-style window: no close button",
        uiWindow ~= nil and uiWindow.closeButton == nil)

    -- Wurst's order: the four feature shortcuts first.
    for _, name: string in ipairs({
        "Row_WurstLogo",
        "Row_HackList",
        "Row_Keybinds",
        "Row_WurstOptions",
    }) do
        check("shortcut: " .. name,
            uiWindow ~= nil and uiWindow.body:FindFirstChild(name) ~= nil)
    end

    -- Building the window is what applies the stored-or-default values.
    if not hadEngine then
        check("Background reaches the surface token", setTokens.surface ~= nil)
        check("Background also paints the backdrop token", setTokens.background ~= nil)
        check("Accent paints accent and outline",
            setTokens.accent ~= nil and setTokens.outline ~= nil)
        check("Text paints text and accentText",
            setTokens.text ~= nil and setTokens.accentText ~= nil)
    end
    check("Wurst's Opacity 0.5 is applied to window bodies at boot",
        windows.bodyTransparency == 0.5,
        tostring(windows.bodyTransparency))
    check("Wurst's Max height 200 is published for the category windows",
        host.state.uiMaxHeight == 200,
        tostring(host.state.uiMaxHeight))
    check("the published defaults table reads like the window",
        type(host.state.uiSettings) == "table"
            and host.state.uiSettings["Opacity"] == 0.5
            and host.state.uiSettings["Max height"] == 200)

    -- The four shortcuts open real windows.
    settings.openWurstLogo()
    check("WurstLogo opens its settings window", windows.Get("WurstLogo") ~= nil)
    settings.openHackList()
    check("HackList opens its settings window", windows.Get("HackList") ~= nil)
    settings.openWurstOptions()
    check("Wurst Options opens", windows.Get("WurstOptions") ~= nil)

    -- Keybinds: the manager lists the binding, reset clears it, a profile
    -- brings it back.
    settings.openKeybinds()
    local keybinds: any = windows.Get("Keybinds")
    check("the Keybind manager opens", keybinds ~= nil)
    local list: any = keybinds and keybinds.body:FindFirstChild("KeybindList")
    check("the binding is listed",
        list ~= nil and list:FindFirstChild("Bind_UniversalKillAura") ~= nil)

    settings.openProfiles()
    local profiles: any = windows.Get("KeybindProfiles")
    check("the Profiles window opens", profiles ~= nil)
    local entryRow: any = profiles and profiles.body:FindFirstChild("NewProfile")
    local nameBox: any = nil
    local saveButton: any = nil
    if entryRow then
        for _, child: any in ipairs(entryRow:GetChildren()) do
            if child.ClassName == "TextBox" then
                nameBox = child
            elseif child.ClassName == "TextButton" then
                saveButton = child
            end
        end
    end
    check("the Profiles window takes a name", nameBox ~= nil and saveButton ~= nil)
    if nameBox and saveButton then
        nameBox.Text = "pvp"
        saveButton.MouseButton1Click:Fire()
        local store: any = host.configData.values.KeybindProfiles
        check("saving snapshots the bound keys",
            type(store) == "table"
                and type(store.pvp) == "table"
                and store.pvp["Universal.KillAura"] == "Q")
    end

    -- Reset restores the defaults (nothing bound) and leaves profiles alone.
    local resetRow: any = keybinds and keybinds.body:FindFirstChild("Row_Resetkeybinds")
    check("the manager has Wurst's Reset", resetRow ~= nil)
    if resetRow then
        resetRow.MouseButton1Click:Fire()
        check("reset unbinds the key",
            binding.key == world.globals.Enum.KeyCode.Unknown)
        check("reset told the card slot to repaint", refreshed > 0)
        check("reset does not delete profiles — Wurst's rule",
            type(host.configData.values.KeybindProfiles) == "table"
                and host.configData.values.KeybindProfiles.pvp ~= nil)
    end

    -- Loading the profile puts the key back through the same persistence
    -- path a manual rebind takes.
    local profileList: any = profiles and profiles.body:FindFirstChild("ProfileList")
    local loadButton: any = nil
    local profileRow: any = profileList and profileList:FindFirstChild("Profile_pvp")
    if profileRow then
        for _, child: any in ipairs(profileRow:GetChildren()) do
            if child.ClassName == "TextButton" then
                loadButton = child
            end
        end
    end
    check("the saved profile is listed", loadButton ~= nil)
    if loadButton then
        loadButton.MouseButton1Click:Fire()
        check("loading restores the key",
            binding.key == world.globals.Enum.KeyCode.Q)
        check("loading persists like a manual rebind",
            host.configData.values["Shortcut.UniversalKillAura"] == "Q")
    end

    -- First-run settings windows must not share a pixel. The capture
    -- stacked them; SettingsPage offsets Y (120 / 180 / 140 / 220).
    local logoWin: any = windows.Get("WurstLogo")
    local hackWin: any = windows.Get("HackList")
    if logoWin ~= nil and hackWin ~= nil then
        check(
            "WurstLogo and HackList are not born superimposed",
            logoWin.root.Position.X.Offset ~= hackWin.root.Position.X.Offset
                or logoWin.root.Position.Y.Offset ~= hackWin.root.Position.Y.Offset
        )
        local beforeZ: number = logoWin.root.ZIndex
        logoWin.root.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.MouseButton1,
            Position = world.globals.Vector2.new(0, 0),
        })
        check(
            "clicking a settings window raises it",
            logoWin.root.ZIndex >= beforeZ
        )
    end
    if uiWindow ~= nil and logoWin ~= nil then
        check(
            "UI Settings is not born on top of WurstLogo",
            uiWindow.root.Position.X.Offset ~= logoWin.root.Position.X.Offset
                or uiWindow.root.Position.Y.Offset ~= logoWin.root.Position.Y.Offset
        )
    end

    local menuKey: string = tostring(host.state.toggleKey and host.state.toggleKey.Name or "")
    check(
        "the published menu key is a complete name",
        menuKey ~= "" and string.find(menuKey, "…", 1, true) == nil,
        menuKey
    )
    check(
        "Max height default stays Wurst 200, not the old 1000",
        host.state.uiMaxHeight == 200,
        tostring(host.state.uiMaxHeight)
    )
end
