# ARandomMenu

Standalone strict-Luau menu with a remote, PlaceId-driven game-module runtime.

## Runtime architecture

- `loadstring` downloads the current `ARandomMenu.luau` bootstrap.
- `ARandomMenu.luau` creates the shared responsive UI, component factory,
  notifications, state and the single-heartbeat `TaskManager`.
- The bootstrap reads `game.PlaceId` and downloads only
  `src/games/<PlaceId>.luau` from the repository raw URL.
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

- `src/games/142823291.luau`: MM2 implementation.
- `src/games/14315258385.luau`: TRS implementation.
- `src/gui/Current/gui.lua`: reusable presentation-only GUI controller.
- `src/gui/Current/Images`: raw and EditableImage-ready UI assets.
- `src/library/RemoteImageParser.luau`: asynchronous HTTP/PNG/EditableImage
  bridge with a non-blocking fallback.
- `src/vendor/png-luau`: vendored MIT `png-luau` v0.2.1 decoder.
- `src/Supported` and `src/Profile`: compatibility metadata for older loaders.

## Remote images

`RemoteImageParser` downloads bytes with `HttpService:GetAsync` inside `pcall`,
falls back to the executor HTTP method when necessary, decodes PNG bytes, writes
them into an `EditableImage`, and assigns `Content.fromObject(image)` to the
target's `ImageContent`. A failed image never blocks the menu bootstrap.

The aurora background is by Khalil Benihoud and is available under the
[Unsplash License](https://unsplash.com/photos/aurora-borealis-umLAzmGNZbU).
