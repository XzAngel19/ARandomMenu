# ARandomMenu

Standalone strict-Luau menu with a remote, PlaceId-driven game-module runtime.

## Runtime architecture

- `loadstring` downloads the current `ARandomMenu.luau` bootstrap.
- `ARandomMenu.luau` creates the shared responsive UI, component factory,
  notifications, state and the single-heartbeat `TaskManager`.
- The bootstrap reads `game.PlaceId` and downloads the named game module from
  the repository raw URL. MM2 and TRS resolve to `MM2.luau` and `TRS.luau`.
- Failed or invalid HTTP responses are logged and may fall back to
  `readfile("ARandomMenu/src/games/<Name>.luau")` when available.
- A game module must return a `Module` table exporting `init(Runtime)`,
  `destroy()`, `Events`, `Name` and `PlaceId`.
- `Runtime.Menu` exposes the live GUI, pages and component API. The module calls
  those shared factories to inject its controls and callbacks into the menu.
- Imported per-frame callbacks use `Runtime.TaskManager`; they are multiplexed
  through one `RunService.Heartbeat` connection and remain alive until cleanup.

Initialization logs use the `[RTM:Bootstrap]` prefix and include detected
PlaceId, raw download status, downloaded byte count, UI callback count,
TaskManager callback count and errors captured by `pcall`.

## Source layout

- `src/games/Universal.luau`: universal and movement module contract.
- `src/games/MM2.luau`: complete MM2 implementation.
- `src/games/TRS.luau`: complete TRS implementation.
- `src/gui/Current/gui.lua`: reusable presentation-only GUI controller.
- `src/gui/Current/Images`: optional normal image assets.
- `src/Profile`: compatibility data retained for older loaders.

## Images

The bootstrap does not use `EditableImage` or a PNG byte decoder. Optional
images use the normal `Image` property and executor-local asset registration;
the text UI remains usable when an image cannot be loaded.

The aurora background is by Khalil Benihoud and is available under the
[Unsplash License](https://unsplash.com/photos/aurora-borealis-umLAzmGNZbU).
