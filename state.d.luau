--!strict
-- The shared state table, and what every key in it is for.
--
-- `state` is how the shell, the libraries, the modules and the game modules
-- reach each other. It is one table with a hundred and forty-seven keys, which
-- is a lot — but the cost of that is not the size, it is not knowing what is in
-- it. Two different things ended up under `activeGameModule` once, and one of
-- them silently won.
--
-- So this file is the index. Every `state.x` anything assigns has to be
-- declared here with a line saying what it is for, and every line here has to
-- match something that is actually assigned; `tools/validate.sh` fails on
-- either. Adding a key means naming it in front of everyone else's, which is
-- the only thing that keeps a shared table from turning back into a bag.
--
-- Types are deliberately loose. This is a directory, not a contract about
-- shapes: the value is in knowing the key exists and who owns it.

export type MenuState = {
    -- The window itself
    visible: boolean,                               -- Is the shell on screen right now
    layout: LayoutMetrics,                          -- The responsive metrics for the current viewport
    layoutListeners: {() -> ()},                    -- Everything that must be re-measured when the viewport changes
    onLayout: (() -> ()) -> (),                     -- Register such a listener
    refreshLayout: (boolean?) -> (),                -- Re-measure now; the flag forces it even if the mode has not changed
    setMenuVisible: (boolean) -> (),                -- Open or close the window, animations included
    menuStyle: string,                              -- "Wurst" (ClickGUI windows) or "Navigator" (Navigator as the main surface); stored as UI.MenuStyle
    SetMenuStyle: (string, boolean?) -> (),         -- The one style state machine: persist, close the open surface, optionally open the new one, notify listeners
    menuStyleListeners: {(string) -> ()},           -- Called with the new style after SetMenuStyle lands it
    fontPack: string,                               -- Always "Code" now: the UI row is gone; applyFontPack stays for suites
    openMenuSurface: () -> (),                      -- Open/close whichever surface menuStyle selects; the toggle key and the dock come through here
    invokeModuleSearch: (string) -> boolean,        -- The dock's search resolver: exact/unique match toggles a module, ambiguous/none notify; replaceable by D's registry
    addMenuVisibilityListener: ((boolean) -> ()) -> (), -- Be told when it opens or closes
    destruct: () -> (),                             -- Remove the menu from the client entirely

    -- Reading and writing text
    textScale: number,                              -- The player's text size, 0.8 to 1.2
    fitTextSize: (Instance, number) -> number,      -- Largest size that still fits the box
    setTextMetric: (Instance, number) -> (),        -- Record a label's natural size so it can be rescaled later
    registeredTextIndex: {[Instance]: any},         -- Every label registered for scaling, keyed by object
    listInterfaceFonts: () -> {string},             -- Typefaces the player can choose
    resolveInterfaceFont: (string) -> Font?,        -- Name to font, downloading a repository face if needed
    applyInterfaceFont: (string, boolean?) -> (),   -- Switch the whole interface to a typeface
    customFontAssets: {[string]: any},              -- Downloaded faces, so a second switch costs nothing

    -- Cards and their boards
    universalScroll: Frame,                   -- Compatibility shim: old Universal board, now CardBin until modules migrate
    spoofScroll: Frame,                       -- Compatibility shim: old Spoof board, now CardBin
    mvsdScroll: Frame,                        -- Compatibility shim: per-game boards, now CardBin
    trsScroll: Frame,                         -- Compatibility shim: TRS board, now CardBin
    vdScroll: Frame,                          -- Compatibility shim: VD board, now CardBin
    bedFightScroll: Frame,                    -- Compatibility shim: BedFight board, now CardBin
    movementFeatures: {[string]: any},              -- Card registries, one per board, keyed by card name
    spoofFeatures: {[string]: any},
    mvsdFeatures: {[string]: any},
    trsFeatures: {[string]: any},
    vdFeatures: {[string]: any},
    bedFightFeatures: {[string]: any},
    applyCardSkin: (any, boolean?) -> (),           -- Repaint one card for the active skin and hover state
    restyleAllFeatures: (boolean) -> (),            -- Repaint every card at once, after a skin change
    restyleButtons: (boolean) -> (),                -- The same for loose buttons
    restyleTextBoxes: (boolean) -> (),              -- and for text fields
    applyLinesGlyph: (Instance, boolean?) -> (),    -- Draw the three-line 'open its settings' mark
    featureTooltip: TextLabel,                      -- The single tooltip label every card borrows
    tooltipToken: number,                           -- Guards against a stale tooltip appearing after the pointer left
    tooltipConnections: {RBXScriptConnection},      -- Its listeners, released with the window

    -- Option rows, built by src/library/Widgets.luau
    layoutOptionControl: (Frame, GuiObject, number?) -> (), -- Place a control in the row's shared right-hand band
    addSectionOption: (any, string) -> Frame,       -- A heading inside a panel
    addListOption: (any, string, any) -> TextButton, -- A multi-select row
    addRangeOption: (any, string, any) -> Frame,    -- One track, two handles
    openChoiceList: (...any) -> (),                 -- The single-choice popup, also used by the settings page
    openMultiList: (...any) -> (),                  -- The multi-choice popup
    closeChoiceList: () -> (),                      -- Close whichever is open
    choiceListAnchor: TextButton?,                  -- The row whose popup is open; pressing its arrow toggles it closed
    listControls: {[string]: any},                  -- Per-list handles so a module can tick an entry it just discovered
    listSelections: {[string]: {[string]: boolean}}, -- What each list currently has selected
    colorPicker: any,                               -- The one colour picker; teardown releases its drag listeners
    components: any,                                -- Build a whole card from a declaration table

    -- Keys and shortcuts
    toggleKey: Enum.KeyCode,                        -- The key that opens the menu
    keybindButton: TextButton?,                     -- The settings row's key slot, while it is capturing
    waitingForKey: boolean,                         -- True between clicking a slot and pressing a key
    keyCaptureCallback: ((Enum.KeyCode) -> ())?,    -- Where the next key press goes
    keyCaptureCancel: (() -> ())?,                  -- Abandon the capture
    bindFeatureActivationKey: (...any) -> (),       -- Give a card's key slot its binding
    shortcutBindings: {[string]: any},              -- Every bound shortcut, by id
    globalInputBeganConnection: RBXScriptConnection?, -- The four shell-wide input listeners, held so teardown can drop them
    globalShortcutBeganConnection: RBXScriptConnection?,
    globalShortcutEndedConnection: RBXScriptConnection?,

    -- Movement input, shared so every module reads the same numbers
    getMoveInput: () -> (number, number),           -- Direction, working on keyboard, thumbstick and under PlatformStand
    isJumpHeld: () -> boolean,                      -- Is jump down
    onJumpRequest: (() -> ()) -> RBXScriptConnection, -- Fires on each jump
    getAimRay: () -> Ray?,                          -- Where the player is pointing

    -- The game bridge: how a game teaches the universal modules
    activeGameName: string?,                        -- Name of the recognised game, or nil. Resolves late on a clone
    activeGameModule: any,                          -- The loaded game module table. Not the same thing as the name above
    gameBridge: any,                                -- The registry the two sides meet in
    onGameBridge: ((string, any) -> ()) -> (),      -- Listen; past registrations are replayed
    registerRoleProvider: (any) -> (),              -- A game says how to read a player's role
    registerEspExtra: (any) -> (),                  -- A game adds its own objects to the universal ESP
    playerRole: (Player) -> string?,                -- Ask the current provider
    gameRoleProvider: any,                          -- What that provider is, for the panels that show it
    gameTargetProvider: any,                        -- and how it names the current target
    isProtectedTarget: (Player) -> boolean,         -- Answered by the friend list; false until it loads

    -- Loading
    boot: any,                                      -- Timings, the bundle, and the sources already in hand
    markBoot: (string, number) -> (),               -- Stamp the end of a phase
    summarizeBoot: () -> (),                        -- Print the one timing line a bug report can quote
    fetchRepositoryChunk: (string) -> (any, string?), -- Download, compile and run one repository file
    fetchRepositorySource: (string) -> (string?, string?), -- Its text only
    httpGetPath: (string) -> (string?, string?),    -- One stamped request
    compileRepositorySource: (string, string) -> (any, string?), -- loadstring with the menu's environment
    sourceLooksValid: (any, number) -> boolean,     -- Reject a 404 page or a captive portal answering 200
    downloadSourcesParallel: ({string}) -> (),      -- The fallback when the bundle is missing
    readCachedSource: (string) -> string?,          -- The on-disk copy, if its stamp matches
    writeCachedSource: (string, string) -> (),      -- Keep one for next time
    sweepStaleSources: () -> number,                -- Delete cached sources the current bundle no longer ships
    sweepStaleAssets: () -> number,                 -- Delete cached assets the current manifest no longer names
    ensureSourceFolders: (string) -> (),            -- Create the folders that copy needs
    frameworkEnvironment: any,                      -- The table every downloaded file runs inside
    framework: any,                                 -- The kernel, once started
    renderLibrary: any,                             -- Shared projection and pooled drawing
    weaponLibrary: any,                             -- Shared weapon discovery
    logBootstrap: (string) -> (),                   -- Loading progress, to the console
    logBootstrapError: (string) -> (),              -- and its failures
    cleanupFrameworkRuntime: () -> (),              -- Stop every downloaded module and library
    cleanupTRSRuntime: () -> (),                    -- Per-game teardown, published by that game's module
    cleanupVDRuntime: () -> (),
    cleanupMVSDRuntime: () -> (),
    cleanupBedFightRuntime: () -> (),

    -- Pages that are libraries of their own
    animationsEnabled: boolean,                     -- Whether the interface animates
    mobileButtonSize: number,                       -- Pixel size of placed phone shortcuts
    clickGui: any,                                  -- Wurst's layout: one window per category, cards placed into them
    moduleSearch: any,                              -- GUI-independent exact module registry: Resolve/Execute over the fixed 38-card inventory
    hudList: any,                                   -- Wurst's HackList: the on-screen list of enabled modules and their card.status brackets
    uiShowHackList: boolean,                        -- Show HackList (UI Settings): the overlay's visibility, seeded before Furniture builds
    uiShowDock: boolean,                            -- Show dock (UI Settings, desktop only): the launcher's visibility; touch-primary ignores it
    dock: any,                                      -- The bottom-centre launcher: root frame and SetVisible
    navigator: any,                                 -- Wurst's Navigator adaptation: the search and preference-ordered grid under the logo
    wurstLogo: any,                                 -- The logo chip's live setters, driven by the WurstLogo settings window
    uiMaxHeight: number,                            -- Wurst's ClickGUI "Max height" in pixels; 0 means no limit, read by every category window
    uiMaxSettingsHeight: number,                    -- Wurst's "Max settings height", capping every popped-out feature settings window
    uiSettings: any,                                -- The UI Settings window's current values, readable without walking its rows
    wurstOptions: any,                              -- The Wurst Options action API: RegisterAction/UnregisterAction/InvokeAction/List over one ordered registry
    teleportPersist: any,                           -- Teleport persistence: {supported, enabled, Sync, SetEnabled}; genv flags ARANDOMMENU_STOPPED / ARANDOMMENU_TP_QUEUED
    keyDisplayName: (any) -> string,                -- Short slot names ("RShift"); Enum/config keep the full name
    pill: any,                                      -- The floating pill toolbar: the launcher, and the one chrome that outlives closing the GUI
    refreshLauncher: () -> (),                      -- Re-evaluate the fallback mobile circle; the pill supersedes it while it exists
    windows: any,                                   -- The window manager: drag, collapse, pin, snap, persistence
    surfaceDragOwner: GuiObject?,                   -- Exclusive pointer owner while a window or Custom HackList is moving
    surfaceDragHitTest: ((Vector2) -> boolean)?,    -- Visible-glyph hit test that keeps overlapping windows from taking HackList drags
    floatingUi: any,                                -- Favourites, the overlay menu and the four overlays
    destroySessionTracking: () -> (),               -- Stop counting kills, deaths and time
    sessionInfo: any,                               -- What that count currently says
    mobileUi: any,                                  -- Placed shortcuts: the registry and its helpers
    bindMobileActionPlacement: (...any) -> (),      -- Let a control be dropped onto the screen as a button
    applyAssetImage: (string, Instance, (() -> ())?) -> (), -- Put a downloaded image on an object when it arrives
    resolveAsset: (string) -> (string?, string?),   -- The raw asset id for consumers that are not ImageLabels (the font atlas)
    bitmapText: any,                                -- The bitmap text contract: metrics and the one maker every ClickGUI label will go through

    -- Published by a module, read by another
    mm2KnifeRuntime: any,                           -- MM2 internals other MM2 cards share
    mm2ShotFeedback: any,
    mm2TrajectoryCalibration: any,

}

return nil
