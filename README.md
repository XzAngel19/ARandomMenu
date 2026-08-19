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
- The fixed-size headerless shell owns sidebar search, navigation,
  translucent cards, notifications and a drag strip. It is the only visual
  theme, so every injection opens the same coherent interface.
- The interface is deliberately neutral: a single monochrome palette built from
  near-black surfaces, grey outlines and one off-white accent, defined once in
  the `Theme` table. There is no decorative background art, mascot or branded
  watermark, and status colours are reserved for gameplay data (roles, health,
  failures) rather than menu chrome.
- Every square-ish surface rounds its corners through one `cornerRadius()`
  helper instead of hard-coding `UDim.new(0, n)`, so the shell, the overlay
  windows and every card share a single silhouette. The curve is deliberately
  restrained — corners read as circular arcs, never as pills. Genuine
  pills and circles (switch tracks, knobs, progress bars, radar, blips) keep
  using `UDim.new(1, 0)` and are untouched by the helper.
- Modules are filed under categories (Player, Combat, Visuals, Protection,
  Utility, and a `General` catch-all that always sorts last) and sorted
  alphabetically inside each one. A card publishes its category and sort name
  as attributes; the card grid materialises one header strip per category,
  writes every `LayoutOrder` explicitly so the layout never has to break a tie,
  and hides a header whose cards the active search filtered away. Pages with
  headers stay single-column, since a header labels everything that follows it.
- Module customisation panels are made of self-contained rows: each setting is
  its own rounded card with a hairline border and a hover highlight, an
  optional second line explaining what it does, and a control aligned to a
  shared right-hand band. Cycle buttons carry an `n/total` counter, numeric
  fields advertise their accepted interval as placeholder text, and long panels
  can be broken up with section headings that fold away together with the
  controls they label. Fly is the reference layout.
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
- Desktop shells use integer-pixel, aspect-fitted dimensions capped near 60% of
  wide displays instead of scaling the complete canvas, which keeps text and
  strokes crisp while preserving drag boundaries on viewport changes.
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
  Interact Extender, collision-aware Phase Dash, Soft Landing and a Rejoin
  action extend the universal toolkit.
- Universal runtime toolkits initialize inside isolated function scopes so
  older executor compilers stay safely below Luau's 200-register ceiling.

Initialization logs use the `[RTM:Bootstrap]` prefix and include detected
PlaceId, raw download status, downloaded byte count, UI callback count,
TaskManager callback count and errors captured by `pcall`.

## Source layout

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
