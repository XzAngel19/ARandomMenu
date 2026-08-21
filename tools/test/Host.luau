--!strict
--
-- Host stand-in for the headless module tests.
--
-- Mirrors the environment `ARandomMenu.luau` hands to downloaded files: the
-- card factory, the option builders, the task manager and the shared `state`
-- helpers. Every option builder records what it was asked for, so a test can
-- assert that a module declared the controls it claims to have — and every
-- builder invokes the module's callback exactly like the real one does, which
-- is how a mismatched default or a callback that throws gets caught here
-- instead of in a game.

local Mock = require("./Roblox")

export type HostStub = {
    env: any,
    features: {any},
    notifications: {string},
    step: (deltaTime: number) -> (),
    taskCount: () -> number,
}

local Host = {}

function Host.create(world: any): HostStub
    local tasks: {any} = {}
    local features: {any} = {}
    local notifications: {string} = {}
    local menuListeners: {any} = {}

    -- Infinite Jump (and anything else that launches on the jump button)
    -- registers here; a suite fires it without an input device.
    world.jumpCallbacks = {}
    world.fireJumpRequest = function(): ()
        for _, callback: any in ipairs(table.clone(world.jumpCallbacks)) do
            callback()
        end
    end

    local function create(className: string, properties: any): any
        local instance: any = Mock.newInstance(className)
        local parent: any = nil
        for key: string, value: any in pairs(properties or {}) do
            if key == "Parent" then
                parent = value
            else
                instance[key] = value
            end
        end
        if parent then
            instance.Parent = parent
        end
        return instance
    end

    local function makeTextLabel(parent: any, text: string, size: number): any
        return create("TextLabel", {
            TextTruncate = "AtEnd",
            Parent = parent,
            Text = text,
            TextSize = size,
        })
    end

    local function makeButton(parent: any, text: string, size: number): any
        return create("TextButton", {
            TextTruncate = "AtEnd",
            Parent = parent,
            Text = text,
            TextSize = size,
        })
    end

    local screenGui: any = Mock.newInstance("ScreenGui")

    local function optionRow(feature: any, label: string): any
        local row: any = create("Frame", {Parent = screenGui, Name = label})
        table.insert(feature.optionRows, row)
        return row
    end

    local host: any = {}
    -- Created first: the option builders publish list controls onto it.
    host.state = {}

    -- The shell's one connection registry, keyed by name so a module can drop
    -- its own listener without holding the handle. Modules that predate the
    -- framework's `Event`/`Clean` pair still use it, and a stub without it
    -- fails only once the module is switched on.
    host.featureConnections = {}
    host.disconnectFeatureConnection = function(name: string): ()
        local connection: any = host.featureConnections[name]
        if connection then
            connection:Disconnect()
            host.featureConnections[name] = nil
        end
    end

    host.createUniversalFeature = function(
        name: string,
        description: string,
        order: number,
        onToggle: any,
        configuration: any
    ): any
        local feature: any = {
            name = name,
            description = description,
            order = order,
            configKey = "Universal." .. name:gsub("%W", ""),
            categoryName = (configuration or {}).categoryName or "General",
            kind = (configuration or {}).kind or "toggle",
            enabled = false,
            onToggle = onToggle,
            optionRows = {},
            options = {},
        }
        function feature.activate(): ()
            -- Action cards run and keep no state, exactly like the real card.
            if feature.kind == "action" then
                onToggle(true)
                return
            end
            feature.enabled = not feature.enabled
            onToggle(feature.enabled)
        end
        table.insert(features, feature)
        return feature
    end

    host.addToggleOption = function(
        feature: any,
        label: string,
        default: boolean,
        callback: any,
        _hint: string?
    ): any
        local button: any = makeButton(optionRow(feature, label), label, 11)
        feature.options[label] = {kind = "toggle", value = default}
        -- The real builder replays the stored value so panels that fold
        -- controls away start in the right shape.
        callback(default)
        return button
    end

    host.addNumberOption = function(
        feature: any,
        label: string,
        default: number,
        minimum: number,
        maximum: number,
        callback: any,
        _hint: string?
    ): any
        assert(
            default >= minimum and default <= maximum,
            label .. ": default " .. tostring(default) .. " is outside its range"
        )
        feature.options[label] = {kind = "number", value = default}
        callback(default)
        return optionRow(feature, label)
    end

    -- Two-handle range row. The stub keeps the pair in one value, exactly
    -- like the real builder, so a test reads `Options.CPS.Value.Min`.
    host.addRangeOption = function(
        feature: any,
        label: string,
        definition: any
    ): any
        local low: number = definition.defaultLow or definition.min or 0
        local high: number = definition.defaultHigh or definition.max or 0
        assert(
            low >= (definition.min or 0) and high <= (definition.max or 0),
            label .. ": defaults are outside the range"
        )
        assert(low <= high, label .. ": minimum default above the maximum")
        feature.options[label] = {kind = "range", low = low, high = high}
        if definition.onChanged then
            definition.onChanged(low, high)
        end
        return optionRow(feature, label)
    end

    host.addCycleOption = function(
        feature: any,
        label: string,
        values: {string},
        index: number,
        callback: any,
        _hint: string?
    ): any
        assert(#values > 0, label .. ": empty cycle list")
        assert(values[index] ~= nil, label .. ": index outside the list")
        feature.options[label] = {kind = "cycle", value = values[index], list = values}
        callback(values[index])
        return makeButton(optionRow(feature, label), values[index], 11)
    end

    host.addKeyOption = function(
        feature: any,
        label: string,
        default: any,
        callback: any,
        _hint: string?
    ): any
        feature.options[label] = {kind = "key", value = default}
        callback(default)
        return makeButton(optionRow(feature, label), "KEY", 9)
    end

    host.addTextOption = function(
        feature: any,
        label: string,
        default: string,
        callback: any,
        _persist: boolean?,
        _hint: string?
    ): any
        feature.options[label] = {kind = "text", value = default}
        callback(default)
        return create("TextBox", {
            Parent = optionRow(feature, label),
            TextTruncate = "AtEnd",
        })
    end

    host.addColorOption = function(
        feature: any,
        label: string,
        default: any,
        callback: any,
        _hint: string?
    ): any
        feature.options[label] = {kind = "colour", value = default, set = callback}
        callback(default)
        return makeButton(optionRow(feature, label), "", 10)
    end

    host.addActionOption = function(
        feature: any,
        label: string,
        callback: any,
        _hint: string?
    ): any
        feature.options[label] = {kind = "action", run = callback}
        return makeButton(optionRow(feature, label), "RUN", 11)
    end

    host.addListOption = function(feature: any, label: string, definition: any): any
        local optionKey: string = feature.configKey .. "." .. label:gsub("%W", "")
        local selected: {[string]: boolean} = {}
        for _, name: string in ipairs(definition.default or {}) do
            selected[name] = true
        end
        local button: any = makeButton(optionRow(feature, label), "", 11)
        local entry: any = {
            kind = "list",
            selected = selected,
            items = definition.items,
            changed = definition.onChanged,
        }
        function entry.set(name: string, on: boolean): ()
            selected[name] = on or nil
            local names: {string} = {}
            for value: string, isOn: boolean in pairs(selected) do
                if isOn then
                    table.insert(names, value)
                end
            end
            table.sort(names)
            if definition.onChanged then
                definition.onChanged(selected, names)
            end
        end
        feature.options[label] = entry
        -- Same controls table the real builder publishes, so a module can tick
        -- an entry it just learned.
        host.state.listControls = host.state.listControls or {}
        host.state.listControls[optionKey] = {
            set = entry.set,
            refresh = function(): ()
                entry.set("", false)
            end,
            selected = selected,
        }
        if definition.onChanged then
            definition.onChanged(selected, {})
        end
        return button
    end

    host.addSectionOption = function(feature: any, label: string): any
        return optionRow(feature, label)
    end

    host.addInformationOption = function(feature: any, text: string): ()
        feature.description = feature.description .. "\n" .. text
    end

    -- Visibility is recorded by row name as well as applied, so a test can
    -- assert that a module folded a control away without reaching into the
    -- instance tree.
    host.state.hiddenOptionRows = {}
    host.setOptionVisible = function(_feature: any, row: any, visible: boolean): ()
        if row then
            row.Visible = visible
            if row.Name then
                host.state.hiddenOptionRows[row.Name] = not visible
            end
        end
    end

    host.TaskManager = {
        Connect = function(_self: any, callback: any): any
            local handle: any = {callback = callback, Connected = true}
            function handle:Disconnect(): ()
                handle.Connected = false
                local index: number? = table.find(tasks, handle)
                if index then
                    table.remove(tasks, index)
                end
            end
            table.insert(tasks, handle)
            return handle
        end,
    }

    host.notify = function(message: string): ()
        table.insert(notifications, message)
    end

    -- The shell publishes these on the environment every downloaded file
    -- runs in. Suites used to each invent a copy, so a module that needed
    -- one and a suite that had not yet been written disagreed about whether
    -- they existed.
    host.getCharacterParts = function(): (any, any, any)
        local character: any = world.localPlayer.Character
        return character,
            character and character:FindFirstChildOfClass("Humanoid"),
            character and character:FindFirstChild("HumanoidRootPart")
    end
    host.addFeatureTooltip = function(_feature: any, _text: string): () end

    host.create = create
    host.makeTextLabel = makeTextLabel
    host.makeButton = makeButton
    host.ScreenGui = screenGui
    host.HttpService = {
        JSONEncode = function(_self: any, value: any): string
            -- Enough of an encoder for a test to prove a file was written.
            return "[" .. tostring(#value) .. " entries]"
        end,
    }
    host.Players = world.players
    host.LocalPlayer = world.localPlayer
    host.workspace = world.workspace
    host.TweenService = world.services.TweenService
    -- One input service for the whole harness, the same as in the game. It
    -- used to be a second hand-written table here, so a module listening
    -- through the host and a library listening through `GetService` watched
    -- two different streams and neither saw the other's events.
    local inputService: any = world.services.UserInputService
    function inputService:IsKeyDown(_key: any): boolean
        return world.keyDown == true
    end
    -- The auto clicker only clicks while the attack is held, so the harness
    -- has to be able to hold it.
    function inputService:IsMouseButtonPressed(_button: any): boolean
        return world.mouseDown == true
    end
    function inputService:GetMouseLocation(): any
        return world.vector2(640, 360)
    end
    inputService.InputBegan = Mock.signal()
    inputService.InputChanged = Mock.signal()
    inputService.InputEnded = Mock.signal()
    host.UserInputService = inputService
    -- The game bridge, exactly as the shell publishes it: a game module
    -- registers roles and its own ESP objects, and the universal modules
    -- listen. The stub keeps the same replay behaviour, because "the game
    -- module loaded first" and "the game module loaded second" have to look
    -- the same to whoever is listening.
    local bridge: any = {roleProvider = nil, extras = {}, listeners = {}}
    local stateTable: any = {
        menuVisible = true,
        gameBridge = bridge,
        onGameBridge = function(listener: (string, any) -> ()): ()
            table.insert(bridge.listeners, listener)
            if bridge.roleProvider then
                listener("roles", bridge.roleProvider)
            end
            for _, extra: any in ipairs(bridge.extras) do
                listener("extra", extra)
            end
        end,
        registerRoleProvider = function(provider: any): ()
            bridge.roleProvider = provider
            for _, listener: any in ipairs(bridge.listeners) do
                listener("roles", provider)
            end
        end,
        registerEspExtra = function(extra: any): ()
            table.insert(bridge.extras, extra)
            for _, listener: any in ipairs(bridge.listeners) do
                listener("extra", extra)
            end
        end,
        playerRole = function(player: any): string?
            local provider: any = bridge.roleProvider
            if not provider then
                return nil
            end
            local ok: boolean, role: any = pcall(provider.Get, player)
            return ok and type(role) == "string" and role or nil
        end,
        -- The window is closed in the harness: modules that stand down while
        -- the menu is open (the executor-level click paths) must still run.
        visible = false,
        setMenuVisible = function(visible: boolean): ()
            host.state.menuVisible = visible
        end,
        keyCaptureCallback = nil,
        waitingForKey = false,
        -- Modules bind their card's key slot through this; the stub records
        -- the pair so a test can arm and release a hold binding directly.
        bindFeatureActivationKey = function(
            feature: any,
            _key: any,
            press: any,
            release: any
        ): ()
            world.bindings = world.bindings or {}
            world.bindings[feature.name] = {press = press, release = release}
        end,
        getAimRay = function(): any
            return world.aimRay
        end,
        getMoveInput = function(): (number, number)
            return 0, 0
        end,
        isJumpHeld = function(): boolean
            return false
        end,
        isProtectedTarget = function(_player: any): boolean
            return false
        end,
        onJumpRequest = function(callback: any): any
            table.insert(world.jumpCallbacks, callback)
            return {
                Connected = true,
                Disconnect = function(self: any): ()
                    self.Connected = false
                    local index: number? = table.find(world.jumpCallbacks, callback)
                    if index then
                        table.remove(world.jumpCallbacks, index :: number)
                    end
                end,
            }
        end,
    }
    for key: string, value: any in pairs(stateTable) do
        host.state[key] = value
    end

    -- The shell primitives the widget library builds its controls out of.
    --
    -- The builders above are a test double: they record what a module asked
    -- for so a test can assert on it in one line. These are something else —
    -- the real `src/library/Widgets.luau` is loaded against them, so the
    -- interface code that actually ships is the code under test. Colour and
    -- geometry are deliberately crude here: the harness proves a control
    -- exists, carries its stored value and calls its module back, and says
    -- nothing about what it looks like.
    --
    -- The real Theme is a fixed set of 22 tokens. A metatable that answered
    -- any name with a grey hid a misspelt token behind a plausible colour;
    -- the game would have handed back nil.
    local rgb: any = world.globals.Color3.fromRGB
    local themeTokens: {[string]: any} = {
        background = rgb(64, 64, 64),
        sidebar = rgb(48, 48, 48),
        surface = rgb(64, 64, 64),
        surfaceRaised = rgb(74, 74, 74),
        surfaceHover = rgb(86, 86, 86),
        surfacePressed = rgb(96, 96, 96),
        button = rgb(56, 56, 56),
        buttonHover = rgb(72, 72, 72),
        buttonPressed = rgb(84, 84, 84),
        outline = rgb(16, 16, 16),
        accent = rgb(16, 16, 16),
        accentDim = rgb(36, 36, 36),
        accentFaint = rgb(56, 56, 56),
        accentSoft = rgb(40, 40, 40),
        accentText = rgb(240, 240, 240),
        enabled = rgb(32, 175, 32),
        enabledText = rgb(240, 240, 240),
        text = rgb(240, 240, 240),
        textMuted = rgb(168, 168, 168),
        tooltip = rgb(24, 24, 24),
        positive = rgb(126, 196, 138),
        negative = rgb(214, 106, 106),
    }
    host.Theme = setmetatable(themeTokens, {
        __index = function(_self: any, key: string): any
            error("unknown theme token '" .. tostring(key) .. "'", 2)
        end,
    })
    world.globals.Theme = host.Theme
    host.CONTROL_FONT = "Control"
    host.THIN_FONT = "Thin"
    host.TITLE_FONT = "Title"
    host.PopupLayer = create("Frame", {Parent = screenGui, Name = "PopupLayer"})
    host.UI_RADIUS = {shell = 8, panel = 5, card = 4, control = 3, chip = 3}
    host.UI_MOTION = {fast = 0.1, base = 0.16, slow = 0.22}
    host.cornerRadius = function(radius: number): any
        return world.globals.UDim.new(0, radius)
    end
    -- The shell releases these with the window; the harness only counts them,
    -- so a builder that leaks a listener per row shows up as a number.
    local uiConnections: {any} = {}
    host.trackUiConnection = function(connection: any): any
        table.insert(uiConnections, connection)
        return connection
    end
    host.uiConnections = uiConnections

    host.makeTextBox = function(parent: any, defaultText: any): any
        local box: any = create("TextBox", {
            Parent = parent,
            Text = tostring(defaultText),
            TextSize = 11,
            TextTruncate = "AtEnd",
        })
        return box
    end

    host.setToggleSwitch = function(button: any, enabled: boolean, _animate: boolean?): ()
        button:SetAttribute("Switched", enabled)
    end
    host.createToggleSwitch = function(parent: any, enabled: boolean, _width: number?): any
        local button: any = create("TextButton", {
            Parent = parent,
            Text = "",
            TextTruncate = "AtEnd",
        })
        host.setToggleSwitch(button, enabled)
        return button
    end
    host.applyKeySlotStyle = function(button: any): ()
        button:SetAttribute("ThemeRole", "KeySlot")
    end
    -- Click the slot, then press a key. The harness stores the callback so a
    -- test can deliver the key press without an input device.
    host.beginKeyCapture = function(button: any, callback: any): ()
        button.Text = "..."
        world.keyCapture = {button = button, callback = callback}
    end
    host.bindActionShortcut = function(
        button: any,
        shortcutId: string,
        label: string,
        callback: any,
        _options: any?
    ): ()
        world.shortcuts = world.shortcuts or {}
        world.shortcuts[shortcutId] = {button = button, label = label, run = callback}
    end
    host.runActionButton = function(
        button: any,
        idleText: string,
        callback: any,
        _successMessage: string,
        _errorPrefix: string
    ): ()
        local ok: boolean, failure: any = pcall(callback)
        button.Text = idleText
        if not ok then
            table.insert(notifications, tostring(failure))
        end
    end

    host.colorFromConfig = function(value: any, fallback: any): any
        if type(value) == "table" then
            return world.globals.Color3.fromRGB(value[1], value[2], value[3])
        end
        return fallback
    end
    host.colorToConfig = function(colour: any): {number}
        return {
            math.round(colour.R * 255),
            math.round(colour.G * 255),
            math.round(colour.B * 255),
        }
    end

    -- The config store, keyed exactly as the shell keys it, so a test can
    -- prove a control wrote its value where the next session will look.
    host.configData = {version = 1, states = {}, values = {}, ui = {}}
    host.saves = 0
    host.queueConfigSave = function(): ()
        host.saves += 1
    end

    -- The Config. tab and the layout helper that files a row into a card
    -- grid. The settings page fills a page the shell owns; the harness owns a
    -- plain frame instead, which is all the page ever writes into.
    host.SettingsPage = create("Frame", {Parent = screenGui, Name = "SettingsPage"})
    host.getFeatureCardParent = function(container: any): any
        return container
    end
    host.setKeySlotCapture = function(button: any, active: boolean): ()
        button:SetAttribute("Capturing", active)
    end
    host.GAME_CHECK = {
        MM2 = 142823291,
        MM2Active = false,
        source = "none",
    }
    host.REPOSITORY_RAW_BASE = "https://example.invalid/"
    host.RUNTIME_SAFETY_SOURCE_URL = "https://example.invalid/ARandomMenu.luau"
    host.RUNTIME_COMPATIBILITY_MARKER = "test-marker"
    host.SOURCE_STAMP = "testtesttesttest"
    -- Every label registered for text scaling. The three make* helpers feed
    -- it in the shell; here it starts empty and the settings page walks it.
    host.registeredText = {}
    -- What the floating overlays draw with: the profile card's fixed height,
    -- the readout typeface, the tab switcher a favourite jumps through, the
    -- live card registry, and the network counters the session panel reads.
    -- Shell pieces the floating layer draws into or through: the sidebar the
    -- profile card sits at the bottom of, the three-line glyph every "open the
    -- settings of this row" button wears, and the asset loader.
    host.state.shells = {
        defaultSidebar = create("Frame", {Parent = screenGui, Name = "Sidebar"}),
    }
    host.state.applyLinesGlyph = function(button: any, _active: boolean?): ()
        button:SetAttribute("Glyph", "lines")
    end
    host.state.applyAssetImage = function(_name: string, _target: any, done: any?): ()
        if done then
            done()
        end
    end
    host.state.activeGameName = nil

    host.PROFILE_CARD_HEIGHT = 62
    host.VALVE_FONT = "Control"
    host.allFeatures = features
    host.setTab = function(name: string): ()
        world.currentTab = name
    end
    host.Stats = {
        Network = {
            ServerStatsItem = {
                ["Data Ping"] = {
                    GetValue = function(): number
                        return world.ping or 42
                    end,
                },
            },
        },
        GetTotalMemoryUsageMb = function(): number
            return 512
        end,
    }
    -- The mobile shortcut layer, as the shell publishes it. The settings page
    -- resizes every placed button when the size slider moves, so the harness
    -- needs the registry even when it is empty.
    host.state.mobileUi = {
        actions = {},
        setActionVisibility = function(_visible: boolean): () end,
        resetActions = function(): () end,
        clampButtonPosition = function(at: any, _size: number): any
            return at
        end,
        saveActionPosition = function(_record: any): () end,
    }
    host.TEXT_BASE_MULTIPLIER = 1.35
    host.TEXT_SCALE_MINIMUM = 0.8
    host.TEXT_SCALE_MAXIMUM = 1.2

    -- The responsive metrics, with the desktop values `computeLayoutMetrics`
    -- produces. Copied whole rather than filled in a field at a time: a
    -- library reading a metric the stub forgot gets nil, and nil in an
    -- arithmetic expression is a stack trace, not a failed assertion.
    host.state.layout = {
        mode = "desktop",
        compact = false,
        touch = false,
        shellWidth = 900,
        shellHeight = 560,
        shellCorner = 8,
        sidebarWidth = 168,
        sidebarCollapsed = false,
        sidebarPadding = 10,
        navRowHeight = 30,
        navIconSize = 22,
        navFontSize = 11,
        brandHeight = 46,
        headerHeight = 44,
        searchHeight = 28,
        searchWidth = 230,
        contentPadding = 14,
        cardSpacing = 6,
        cardColumns = 2,
        cardHeight = 44,
        cardCorner = 4,
        controlHeight = 26,
        optionRowHeight = 34,
        switchWidth = 38,
        switchHeight = 20,
        iconButton = 24,
        keySlotWidth = 46,
        touchTarget = 24,
        titleFontSize = 12,
        bodyFontSize = 10,
        captionFontSize = 9,
        scrollBar = 4,
        launcherHeight = 28,
    }
    host.state.textScale = 1
    host.state.animationsEnabled = true
    host.state.blurEnabled = false
    host.state.mobileButtonSize = 46
    host.state.toggleKey = world.globals.Enum.KeyCode.E
    host.state.onLayout = function(_listener: any): () end
    host.state.fitTextSize = function(_object: any, size: number): number
        return size
    end
    host.state.refitText = function(): () end
    host.state.setBlurVisible = function(_visible: boolean): () end
    host.state.refreshBlurDecoration = function(): () end
    host.state.listInterfaceFonts = function(): {string}
        return {"Menu default", "Monocraft"}
    end
    host.state.applyInterfaceFont = function(_name: string, _persist: boolean?): () end
    host.state.destruct = function(): ()
        world.destructed = true
    end
    host.state.guiStyle = "Default"
    host.state.isMobile = false
    host.state.addMenuVisibilityListener = function(listener: any): ()
        table.insert(menuListeners, listener)
    end
    host.state.setTextMetric = function(_object: any, _size: number): () end

    return {
        env = host,
        features = features,
        notifications = notifications,
        step = function(deltaTime: number): ()
            -- A frame advances time. Without this the mocked clock is frozen,
            -- and anything that coalesces work per frame (the entity cache,
            -- rate limits) would see every step as the same instant.
            world.clock += deltaTime
            for _, handle: any in ipairs(table.clone(tasks)) do
                if handle.Connected then
                    handle.callback(deltaTime)
                end
            end
        end,
        taskCount = function(): number
            return #tasks
        end,
    }
end

return Host
