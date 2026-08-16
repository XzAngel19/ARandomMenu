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
  a short style-aware loading curtain reports progress until they are ready,
  and opening a tab is never used as the condition for constructing content.
- Two independent fixed-size shells share only module state and callbacks.
  `Default` is the startup shell and has its own headerless aurora panel,
  sidebar search, navigation, clean glass cards, notifications and drag strip.
  `DARK` is opt-in and keeps its separate black header and navigation.
- Settings switches between the shells live and persists an explicit `DARK`
  choice. With no saved choice, every injection opens `Default`.
- The reusable `gui.lua` owns its image catalog, executor-safe asset cache,
  settings, draggable shell, tabs and `createModule()` component API. Game
  modules only provide their controls and callbacks.
- Its asset cache verifies PNG/JPEG signatures, interface assets use the real
  files under `Assets`, and text scaling updates a creation-time registry
  instead of walking the complete GUI during every slider movement.
- Settings includes the persistent GUI selector, text scale, blur, interface
  motion, cache-busted **Reinject latest**, and an idempotent **Destruct** action
  that disables features and releases every tracked runtime connection. The
  Default shell uses simple blue key/action controls; the custom key-slot frame
  remains exclusive to DARK.
- Desktop shells use integer-pixel, aspect-fitted dimensions capped near 60% of
  wide displays instead of scaling the complete canvas, which keeps text and
  strokes crisp while preserving drag boundaries on viewport changes.
- Universal Fly provides Balanced, Direct and Precise response presets,
  independent horizontal/vertical speed and progressive advanced controls.
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

The bootstrap does not use `EditableImage` or a PNG byte decoder. `AssetManager`
selects a compatible executor HTTP alias, validates PNG bytes, retries failed
downloads, writes versioned files under `MenuAssets`, verifies the cache and
resolves local paths with `getcustomasset`/`getsynasset`. Every stage is logged
with the `[RTM:Assets]` prefix. The current GUI also declares Roblox asset IDs
as immediate fallbacks for its header, ornament sheet and mobile toggle.

The aurora background is by Khalil Benihoud and is available under the
[Unsplash License](https://unsplash.com/photos/aurora-borealis-umLAzmGNZbU).
