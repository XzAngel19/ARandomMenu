# ARandomMenu

Standalone strict-Luau menu with a remote, PlaceId-driven game-module runtime.

## Runtime architecture

- `loadstring` downloads the current `ARandomMenu.luau` bootstrap.
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
  a short darkcore loading curtain reports progress until they are ready, and
  opening a tab is never used as the condition for constructing its content.
- The desktop window uses a fixed responsive footprint (72% × 78% of the
  viewport), can only be dragged, and keeps itself inside the visible screen.
- The content panel is solid black. Feature rows stay quiet while idle and use
  a brighter stripe, surface and outline when enabled.
- The reusable `gui.lua` owns its image catalog, executor-safe asset cache,
  settings, draggable shell, tabs and `createModule()` component API. Game
  modules only provide their controls and callbacks.
- Universal Fly uses one stable camera-relative velocity preset. The UI exposes
  only speed and the ascend/descend keys; orientation and smoothing are handled
  automatically.

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
