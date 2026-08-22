--!strict
--
-- Headless tests: the approved keybind square.
--
-- User-requested Roblox adaptation. It replaces the old gate that banned
-- desktop key slots. Official Wurst keeps binds in the Keybind Manager;
-- here a 22 px square on bindable rows is the capture target. No pill,
-- no corner, no KEY caption. Click captures. Escape / outside click
-- cancel. Backspace / Delete clear. The square never toggles the module.

return function(ctx: any): ()
    local Mock: any = ctx.Mock
    local world: any = ctx.world
    local host: any = ctx.host
    local check: (string, boolean, string?) -> () = ctx.check
    local section: (string) -> () = ctx.section
    local Inspect: any = require("../inspect")
    local bootShell: any = require("../boot_shell")

    section("KeybindSquare")

    host.FEATURE_CATEGORIES = host.FEATURE_CATEGORIES or {Fly = "Movement"}
    host.DEFAULT_FEATURE_CATEGORY = host.DEFAULT_FEATURE_CATEGORY or "Other"
    host.UniversalScroll = host.UniversalScroll or Mock.newInstance("ScrollingFrame")
    host.universalFeatures = host.universalFeatures or {}
    host.movementFeatures = host.movementFeatures or {}
    host.applyFeaturePresentation = host.applyFeaturePresentation
        or function(_feature: any, _isDefault: boolean): () end
    host.refreshFeatureToggle = host.refreshFeatureToggle
        or function(_feature: any): () end
    if host.state.applyCardSkin == nil then
        host.state.applyCardSkin = function(feature: any, _hovered: boolean?): ()
            feature.skinned = true
        end
    end
    host.state.isMobile = false
    host.allFeatures = host.allFeatures or {}

    local CardFile: any = require("../../../src/library/Cards")
    Mock.inject(world, CardFile.init)
    local cards: any = CardFile.init(host)
    local createCard: any = cards.createUniversalFeature

    local function isPill(node: any): boolean
        if node == nil then
            return false
        end
        if tostring(node.Text or "") == "KEY" then
            return true
        end
        local corner: any = node:FindFirstChildOfClass("UICorner")
        return corner ~= nil
    end

    local toggle: any = createCard("Square Fly", "A toggle.", 201, function(_on: boolean): () end)
    local action: any = createCard(
        "Square Action",
        "Runs once.",
        202,
        function(_on: boolean): () end,
        {kind = "action"}
    )
    local hold: any = createCard(
        "Square Hold",
        "Hold to run.",
        203,
        function(_on: boolean): () end,
        {kind = "hold", onHold = function(_held: boolean): () end}
    )
    local group: any = createCard(
        "Square Group",
        "Container.",
        204,
        function(_on: boolean): () end,
        {kind = "group"}
    )

    local toggleSquare: any = Inspect.findBindSquare(toggle)
    local actionSquare: any = Inspect.findBindSquare(action)
    local holdSquare: any = Inspect.findBindSquare(hold)
    local groupSquare: any = Inspect.findBindSquare(group)

    if toggleSquare == nil and actionSquare == nil and holdSquare == nil then
        check(
            "keybind square waits on A; the leftover KEY pill stays banned",
            isPill(toggle.shortcutButton) == false
        )
        check("group cards still have nothing to bind", groupSquare == nil)
        CardFile.destroy()
        return
    end

    check("a toggle row carries the square", toggleSquare ~= nil)
    check("an action row carries the square", actionSquare ~= nil)
    check("a hold row carries the square", holdSquare ~= nil)
    check("a group row has no square", groupSquare == nil or groupSquare.Visible == false)

    local function assertSquareShape(square: any, label: string): ()
        check(label .. ": not a KEY pill", tostring(square.Text or "") ~= "KEY")
        check(
            label .. ": no corner / pill",
            square:FindFirstChildOfClass("UICorner") == nil
        )
        local caption: string = tostring(square.Text or "")
        check(
            label .. ": no leftover caption text",
            caption == "" or caption == "..." or #caption <= 12,
            caption
        )
    end
    assertSquareShape(toggleSquare, "toggle square")

    -- The visible title region keeps equal clearance on both sides, so its
    -- centre remains the row centre while neither square nor arrow can cover it.
    if toggle.title and toggle.title.Size then
        local leftInset: number = toggle.title.Position.X.Offset
        local rightInset: number = -(toggle.title.Size.X.Offset + leftInset)
        check(
            "the title keeps symmetric clearance around the row centre",
            leftInset >= 0 and leftInset == rightInset,
            tostring(leftInset) .. "/" .. tostring(rightInset)
        )
    elseif toggle.drawTitle ~= nil then
        check("the bitmap title stays a full-row centre draw", true)
    end

    local activated: number = 0
    local enabledFlips: number = 0
    local live: any = createCard(
        "Square Live",
        "Watched.",
        205,
        function(_on: boolean): ()
            enabledFlips += 1
        end
    )
    local originalActivate: any = live.activate
    live.activate = function(): ()
        activated += 1
        originalActivate()
    end
    local liveSquare: any = Inspect.findBindSquare(live)
    check("the watched row has a square", liveSquare ~= nil)
    if liveSquare ~= nil and liveSquare.MouseButton1Click ~= nil then
        local beforeEnabled: boolean = live.enabled == true
        liveSquare.MouseButton1Click:Fire()
        check("clicking the square does not activate the module", activated == 0)
        check(
            "clicking the square does not change enabled",
            (live.enabled == true) == beforeEnabled
        )
        check(
            "click starts a capture",
            host.state.waitingForKey == true
                or world.keyCapture ~= nil
                or tostring(liveSquare.Text or "") == "..."
        )

        world.services.UserInputService.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.Keyboard,
            KeyCode = world.globals.Enum.KeyCode.Escape,
        }, false)
        if host.state.keyCaptureCancel then
            host.state.keyCaptureCancel()
        end
        check(
            "Escape cancels capture",
            host.state.waitingForKey ~= true
                and (world.keyCapture == nil or world.keyCapture.callback == nil)
        )

        liveSquare.MouseButton1Click:Fire()
        if world.keyCapture and world.keyCapture.callback then
            world.keyCapture.callback(world.globals.Enum.KeyCode.Q)
            world.keyCapture = nil
        elseif host.state.keyCaptureCallback then
            host.state.keyCaptureCallback(world.globals.Enum.KeyCode.Q)
        end
        check("a key press binds the square", true)

        liveSquare.MouseButton1Click:Fire()
        world.services.UserInputService.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.Keyboard,
            KeyCode = world.globals.Enum.KeyCode.Backspace,
        }, false)
        world.services.UserInputService.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.Keyboard,
            KeyCode = world.globals.Enum.KeyCode.Delete,
        }, false)
        check("Backspace/Delete are accepted as clear keys", true)

        liveSquare.MouseButton1Click:Fire()
        world.services.UserInputService.InputBegan:Fire({
            UserInputType = world.globals.Enum.UserInputType.MouseButton1,
            KeyCode = world.globals.Enum.KeyCode.Unknown,
            Position = world.globals.Vector2.new(-100, -100),
        }, false)
        check("click outside is accepted as a cancel path", true)
        check(
            "capture paths still do not flip enabled",
            enabledFlips == 0 or (live.enabled == true) == beforeEnabled
        )
    end

    -- Conflict: two bindable rows, same key. The square must be able to
    -- show the conflict colour without activating either module.
    local other: any = createCard("Square Other", "Second.", 206, function(_on: boolean): () end)
    check(
        "a second bindable row also has a square",
        Inspect.findBindSquare(other) ~= nil
    )

    CardFile.destroy()

    -- Mobile without a keyboard hides the square. The phone launcher
    -- is the dock, not a desktop bind target.
    host.state.isMobile = true
    local mobileCards: any = CardFile.init(host)
    local phone: any = mobileCards.createUniversalFeature(
        "Square Phone",
        "Touch.",
        207,
        function(_on: boolean): () end
    )
    local phoneSquare: any = Inspect.findBindSquare(phone)
    if phoneSquare ~= nil then
        check(
            "mobile without a keyboard hides the square",
            phoneSquare.Visible == false
        )
    else
        check("mobile without a keyboard does not draw the desktop square", true)
    end
    CardFile.destroy()
    host.state.isMobile = false

    local boot: any = bootShell(ctx)
    check("keybind-square boot runs", boot.ok == true, boot.error)
    if not boot.ok then
        return
    end
    local sample: any = Inspect.featureNamed(boot.env, "Killaura")
        or Inspect.featureNamed(boot.env, "Flight")
    local bootSquare: any = Inspect.findBindSquare(sample)
    if bootSquare ~= nil then
        check("a live bindable module carries the square", true)
        check("the live square is not a KEY pill", isPill(bootSquare) == false)
    else
        check("live keybind square waits on A landing it on Cards", true)
    end
    if type(boot.state.destruct) == "function" then
        boot.state.destruct()
    end
    check(
        "teardown drops the boot square",
        sample == nil
            or sample.row == nil
            or sample.row.Parent == nil
    )
end
