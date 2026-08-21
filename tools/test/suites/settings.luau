--!strict
--
-- Headless tests: settings.
--
-- Loaded by tools/test/run.luau. Suites share one world through the context
-- so the checks stay under Luau's 200-local ceiling without wrapping
-- sections in do-end.
--
return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section


    section("Settings page")

    -- Eight hundred lines that lived in the shell and that nothing has ever run.
    -- The page is built lazily, the first time the Config. tab is opened, so the
    -- test does what opening that tab does and then checks the controls are there
    -- and do what their names say.
    local SettingsFile: any = require("../../../src/library/SettingsPage")
    Mock.inject(world, SettingsFile.init)
    local settings: any = SettingsFile.init(host)

    check("the library publishes its builder",
        type(host.state.buildSettingsPage) == "function")
    check("nothing is drawn before the tab is opened",
        #host.SettingsPage:GetChildren() == 0,
        "children: " .. tostring(#host.SettingsPage:GetChildren()))

    settings.build()

    local scroll: any = host.SettingsPage:FindFirstChild("SettingsScroll")
    check("opening the tab builds the page", scroll ~= nil)
    -- Rows are label + control across the full width; this page must never be
    -- split into two narrow columns however wide the shell gets.
    check("the page stays one column",
        scroll ~= nil and scroll:GetAttribute("CardGridSingleColumn") == true)

    for _, name: string in ipairs({
        "Text size",
        "Interface font",
        "Blur mode",
        "Interface motion",
        "Menu key",
        "Reinject latest",
        "Destruct",
        "Game check",
        "Mobile action size",
    }) do
        local rowName: string = "Setting_" .. (name:gsub("%W", ""))
        check("row: " .. name, scroll ~= nil and scroll:FindFirstChild(rowName) ~= nil)
    end
    check("every row is registered for restyling",
        type(host.state.settingRows) == "table" and #host.state.settingRows == 9,
        "rows: " .. tostring(host.state.settingRows and #host.state.settingRows))

    -- Blur and motion are the two rows that write straight into the saved config,
    -- so they are the two worth driving rather than merely counting.
    local motionRow: any = scroll:FindFirstChild("Setting_Interfacemotion")
    local motionSwitch: any = motionRow and motionRow:FindFirstChild("OptionSwitch")
    if motionSwitch == nil and motionRow ~= nil then
        for _, child: any in ipairs(motionRow:GetDescendants()) do
            if child.ClassName == "TextButton" then
                motionSwitch = child
                break
            end
        end
    end
    check("the motion row has a control", motionSwitch ~= nil)
    if motionSwitch then
        motionSwitch.MouseButton1Click:Fire()
        check("turning motion off is remembered",
            host.configData.ui.animationsEnabled == false
                and host.state.animationsEnabled == false,
            tostring(host.configData.ui.animationsEnabled))
        motionSwitch.MouseButton1Click:Fire()
        check("turning it back on is remembered",
            host.configData.ui.animationsEnabled == true)
    end

    -- The key slot: click it, then press. Hovering used to be enough, which bound
    -- a key every time the pointer crossed the row.
    local keyRow: any = scroll:FindFirstChild("Setting_Menukey")
    local settingsKeySlot: any = host.state.keybindButton
    check("the menu key row owns the shell's key slot",
        settingsKeySlot ~= nil and keyRow ~= nil and settingsKeySlot:IsDescendantOf(keyRow))
    check("the slot shows the current key",
        settingsKeySlot ~= nil and settingsKeySlot.Text == host.state.toggleKey.Name,
        settingsKeySlot and tostring(settingsKeySlot.Text) or "none")

    -- Destruct removes the menu from the client, so it is the one row where a
    -- mis-wired button is unrecoverable.
    local destructRow: any = scroll:FindFirstChild("Setting_Destruct")
    check("the destruct row exists and has not fired", destructRow ~= nil
        and world.destructed ~= true)
end
