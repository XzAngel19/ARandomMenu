# ARandomMenu

Standalone strict-Luau menu with a remote, PlaceId-driven game-module runtime.

## Runtime architecture

- `loadstring` downloads the current `ARandomMenu.luau` bootstrap.
- Loader v3 rejects the stale `0/0` runtime, retries a known-good immutable
  snapshot when GitHub's branch CDN has not propagated, and never runs an
  outdated local fallback.
- `ARandomMenu.luau` creates the shared responsive UI, component factory,
  notifications, state and the single-heartbeat `TaskManager`.
- The bootstrap reads `game.PlaceId` and downloads the named game module from
  the repository raw URL. MM2, TRS and VD resolve to their named modules.
- Failed or invalid HTTP responses are logged and may fall back to
  `readfile("ARandomMenu/src/games/<Name>.luau")` when available.
- A game module must return a `Module` table exporting `init(Runtime)`,
  `destroy()`, `Events`, `Name` and `PlaceId`.
- `Runtime.Menu` exposes the live GUI, pages and component API. The module calls
  those shared factories to inject its controls and callbacks into the menu.
- Imported per-frame callbacks use `Runtime.TaskManager`; they are multiplexed
  through one `RunService.Heartbeat` connection and remain alive until cleanup.
- Registered sections initialize asynchronously after the GUI shell appears;
  a staged loading curtain reports progress until they are ready, and opening a
  tab is never used as the condition for constructing content.
- The loading intro is a scripted sequence rather than a spinner that vanishes
  on the last callback: a drifting backdrop glow, the wordmark rising into
  place, a hairline rule drawing out beneath it, then counter-rotating rings
  over a narrated status line and progress bar, and finally a held "Ready"
  before the curtain lifts. Roughly 1.1 s of animation runs before any
  narration, so the intro reads as an intro even when every module loads
  instantly, and a slow load simply keeps the status stage on screen for
  longer — nothing here ever delays a slow load further. The narration yields
  the moment the loader has real `x/y` counts to display, a watchdog lifts the
  curtain if the sequence thread ever dies, and a failed bootstrap keeps the
  curtain up so its error message stays readable.
- **The shell is fixed.** It is anchored at its own centre
  (`AnchorPoint = (0.5, 0.5)`, `Position = fromScale(0.5, 0.5)`) and can never
  be moved: there is no drag strip, no pointer bookkeeping and no persisted
  window geometry. Any `ui.windowPosition` written by an older build is
  dropped when the configuration loads, and a viewport change simply
  re-centres and re-sizes the shell. What *is* movable are the floating tool
  windows (favourites, the overlay manager, the per-overlay settings) and the
  HUD overlays, which keep their own drag handlers and their own saved
  positions in `ui.floatingPositions`.
- The shell itself is a compact, borderless, dark-glass surface: a navigation
  rail, a page header (page name + search) and a scrolling card board. It is
  the only visual theme, so every injection opens the same coherent interface.
- **No faked shadow.** An ambient shadow used to be approximated with stacked
  rounded frames behind the window. `cornerRadius()` caps every radius at
  30 px, so a frame 44 px wider than the shell kept square-ish corners around
  a tightly rounded window and rendered as four grey blocks poking out of the
  corners — the menu looked chipped. A convincing soft shadow needs a 9-slice
  image asset and this runtime downloads none, so the shell has no shadow at
  all. Every full-size surface inside the window (shell, readability layer)
  now also carries the window radius, because `ClipsDescendants` clips to the
  rectangle and not to the rounded corner.
- The interface is deliberately neutral: a single monochrome palette built from
  near-black surfaces, grey outlines and one off-white accent, defined once in
  the `Theme` table. There is no decorative background art, mascot or branded
  watermark, and status colours are reserved for gameplay data (roles, health,
  failures) rather than menu chrome.
- **Design tokens.** `UI_RADIUS` and `UI_MOTION` sit at file scope and are the
  only place radii and animation durations (~0.16 s) are declared. Every square-ish surface still rounds its corners
  through the one `cornerRadius()` helper, so the shell, the tool windows and
  every card share a single, deliberately tight silhouette. Genuine pills and
  circles (switch tracks, knobs, progress bars, radar, blips) keep using
  `UDim.new(1, 0)` and are untouched by the helper.
- **Responsive metrics.** `computeLayoutMetrics(viewport, touch)` returns one
  table — sidebar width, row and control heights, corner radius, card columns,
  touch target size, font sizes, paddings — and `state.layout` is the single
  source of truth for every size in the interface. Three real modes rather
  than one scale factor:
  - *Mobile* (`width < 620` or `height < 430`, so a phone in landscape
    counts): near-fullscreen shell, rail collapsed to monogram chips, finger
    sized controls.
  - *Tablet* (`width < 1100`): reduced rail, one column unless the content
    area is wide.
  - *Desktop*: full rail with labels, two columns whenever the content area
    reaches 560 px, more air between controls.
  Anything that has to react registers through `state.onLayout(listener)`;
  `state.refreshLayout()` recomputes on every viewport change and re-flows the
  rail, header, search, cards, columns, floating windows and the centred
  shell. Game modules never touch it — the shared card and option factories
  size themselves from the table, so a module written once renders correctly
  on every device. `tools/layout-preview.html` renders the same formulas in a
  browser for 360×800, 800×360, 768×1024, 1280×720 and 1920×1080.
- **HUD overlays are chrome-less.** Radar, Target Info, Session Info and the
  Text GUI render their content and nothing else: no panel, no header, no
  close button, so the radar is exactly the circle and the read-outs are bare
  text with their own shadow. They remain movable — the content is the drag
  handle — but they only become an input surface while the menu is open, so a
  transparent overlay can never swallow a click meant for the game, and a
  faint outline appears around them while the menu is open to show they can be
  grabbed. The framed tool windows (favourites, overlay manager, overlay
  settings) keep their compact header and close button.
- Modules are filed under categories (Player, Combat, Visuals, Protection,
  Utility, and a `General` catch-all that always sorts last) and sorted
  alphabetically inside each one. A card publishes its category and sort name
  as attributes; the card grid materialises one **section** per category —
  a header strip plus one or two columns — writes every `LayoutOrder`
  explicitly so the layout never has to break a tie, and hides a section whose
  cards the active search filtered away. Cards are balanced across the columns
  by measured height, so one expanded card cannot leave a column half empty,
  and a category header always spans the full width of its own section, which
  is what lets headers and two-column boards coexist. New cards land in an
  intake column and are redistributed on the next frame, so bootstrap stays
  O(n) instead of re-sorting on every creation.
- Module customisation panels are made of self-contained rows: each setting is
  its own rounded card with a hairline border, a hover highlight and a control
  aligned to a shared right-hand band. Rows are one line — the explanatory
  sentence modules used to pass ("Balanced glides, Direct stops instantly…")
  is ignored by `createOptionRow`, which fixes Fly, Fling, Speed, Hitboxes and
  every game-module panel at once without touching a single call site. Every row in every module shares the same geometry —
  labels end at 48% of the row, controls occupy the exact same 50%→edge
  rectangle whether they are switches, sliders, key slots, text boxes or
  action pairs — so panels with and without keybinds look symmetric. Cycle
  buttons carry an `n/total` counter, numeric fields advertise their accepted
  interval as placeholder text, and long panels can be broken up with section
  headings that fold away together with the controls they label. Fly is the
  reference layout.
- Every interactive Universal/Movement module without its own key option
  automatically receives a standard **Toggle key** row as its final row, and
  every card header carries the same favourite / key-slot / expand trio
  (actions run and categories expand from their key slot too), so no module
  ever looks like the odd one out in the list. The three-dot expander is drawn
  on *every* card, including modules with nothing to configure (Anti-AFK,
  Anti-Void, X-Ray): those simply never open — the dots are dimmed and the
  click is ignored, checked at click time because options can be added after a
  card is built.
- **Fling** was rewritten. It reported "stopped after the 5 second safety
  limit" the instant it was triggered: the loop guarded on
  `targetPlayer.Parent == Players`, but `Players` is a `cloneref` handle that
  never compares equal to the service `Parent` returns, so the body never ran.
  It now tests for an actual parent, re-reads the local character every
  iteration (a respawn cannot strand it), alternates `Stepped`/`Heartbeat` so
  the velocity replicates, always restores position, camera and `AutoRotate`,
  and exposes **Duration**, **Power** and **Return to start** instead of
  hiding the timeout in a constant. The same `cloneref` comparison was fixed in
  MM2's shot-confirmation check, where it confirmed every hit including misses.
- **High Jump** is a one-shot action rather than a state: holding it "enabled"
  made no sense for a feature whose whole job is "press this and jump high".
  It fires from the card, from its key slot or from a placed mobile shortcut,
  and opts out of the per-activation toast so a hotkey can be spammed.
- The reusable `gui.lua` owns its image catalog, executor-safe asset cache,
  settings, draggable shell, tabs and `createModule()` component API. Game
  modules only provide their controls and callbacks.
- Its asset cache verifies PNG/JPEG signatures, interface assets use the real
  files under `Assets`, and text scaling updates a creation-time registry
  instead of walking the complete GUI during every slider movement.
- Settings includes calibrated text scale, blur, interface motion,
  cache-busted **Reinject latest**, and an idempotent **Destruct** action
  that disables features and releases every tracked runtime connection. The
  key/action controls blend into the dark glass surface without image frames.
- Every settings row is a single line: its name, vertically centred, and its
  control. The explanatory second line each row used to carry is gone — it
  doubled the height of the page and the names already say what they do.
  `createSettingRow` still accepts the description argument so existing call
  sites keep working; it is simply never rendered.
- **Blur mode** and **Interface motion** have no switch: like a module card,
  the whole row is the button. A click flips it and the row itself reports the
  state through its accent stripe, its surface and an ON/OFF caption.
- **Destruct** tears the runtime down step by step, each step inside its own
  `pcall`. It used to be one unprotected block, so a single failing step (a
  module cleanup, a stale connection, a toolkit that never finished
  initializing) aborted the rest of the teardown *and* the `ScreenGui:Destroy()`
  that followed it, leaving the menu on screen stuck on "REMOVING…". Failures
  are now logged and the teardown continues; the interface is always removed,
  including any leftover shell or blur left behind in `PlayerGui`/`Lighting`.
- **Blur mode** dims the game only while the menu is on screen. A single
  controller owns the `BlurEffect` and is defined next to the shared state, so
  every path that shows or hides the menu (toggle key, mobile button, mobile
  shortcut placement, destruct) goes through it. The effect is switched off —
  not merely resized to `0` — whenever the menu is hidden, so closing the menu
  can never leave the screen blurred.
- **Falling hail** drifts over the blur, from the top edge of the screen down
  past the bottom, on a full-screen layer below the menu window. It is driven
  entirely by the same blur controller through `state.registerBlurDecoration`,
  so it can never outlive the blur: closing the menu, disabling Blur mode or
  destructing all stop it, disconnect its `RenderStepped` loop and hide the
  layer. It also follows the Animations setting, since it is motion, and the
  per-frame step clamps its delta so a backgrounded client does not teleport
  every stone off screen at once.
- Shell dimensions are integer pixels taken from the responsive metrics rather
  than a scaled canvas, which keeps text and strokes crisp; the shell is then
  re-centred (never clamped) whenever the viewport changes.
- Runtime controls use native Builder Sans through `FontFace` for crisp text at
  small sizes. The cached Candy Fruits font is reserved for the large loading
  title, where a decorative OTF can render cleanly without softening controls.
- The permanent shell and tab pages are ordinary `Frame` instances rather than
  nested `CanvasGroup` textures, preventing Roblox from rasterizing interface
  text at a reduced intermediate resolution.
- Universal Fly provides Balanced, Direct and Precise response presets,
  independent horizontal/vertical speed and progressive advanced controls, each
  annotated with a one-line explanation and grouped under Flight / Advanced
  headings.
  Speed provides Adaptive, Smooth, Boost and Teleport modes plus acceleration,
  air control, sprint, momentum retention, wall safety, auto-jump and vehicle
  tuning. Player ESP, X-Ray, High Jump, Spider, Safe Walk, Zoom Unlocker,
  Interact Extender, a Rejoin action and a rewritten Hitboxes engine extend
  the universal toolkit.
- **Hitboxes** were rewritten around a mode system — Visible (scaled body,
  pinned head), Root (phantom HumanoidRootPart block) and Hybrid — with
  independent head/root sizes, reveal/transparency, collision, mass,
  accessory handling and a tunable refresh interval. Original part states are
  recorded once and restored exactly, and switching modes unwinds the parts
  the new mode no longer targets.
- **Phase Dash** now offers Blink (collision-aware teleport) and Slide
  (velocity burst) modes plus collision padding, flash duration and a
  separate slide speed. **Soft Landing** gained Landing / Feather / Auto
  modes, a glide speed and momentum preservation. **Projectile Calibration**
  exposes live-tunable analysis knobs — ping bucket width and ceiling,
  sample window, per-track sample cap, match radius, minimum projectile
  speed — alongside Save / Delete / Show-status actions.
- Universal runtime toolkits initialize inside isolated function scopes so
  older executor compilers stay safely below Luau's 200-register ceiling.

Initialization logs use the `[RTM:Bootstrap]` prefix and include detected
PlaceId, raw download status, downloaded byte count, UI callback count,
TaskManager callback count and errors captured by `pcall`.

## Source layout

- `tools/layout-preview.html`: development harness that mirrors
  `computeLayoutMetrics` so the Mobile/Tablet/Desktop shells, the collapsed
  rail, the card columns and the chrome-less overlays can be reviewed in a
  browser at the reference viewports. It is never downloaded by the runtime.
- `src/games/Universal.luau`: universal and movement module contract.
- `src/games/MM2.luau`: complete MM2 implementation.
- `src/games/TRS.luau`: complete TRS implementation.
- `src/games/VD.luau`: Violence District survivor, killer and visibility tools.
- `src/gui/Current/gui.lua`: reusable presentation-only GUI controller.
- `src/gui/Current/Images`: optional normal image assets.
- `src/Profile`: compatibility data retained for older loaders.

## Images

The neutral interface draws no decorative artwork, so the runtime resolves only
the two optional display fonts through `AssetManager`. It selects a compatible
executor HTTP alias, validates the font signature, retries failed downloads,
writes versioned files under the cache folder, verifies the result and resolves
local paths with `getcustomasset`/`getsynasset`, falling back to the built-in
Builder Sans face when unavailable. Every stage is logged with the
`[RTM:Assets]` prefix.

The image files under `src/gui/Current` are retained for the standalone
`gui.lua` controller and for older loaders; the current bootstrap does not
download them.
