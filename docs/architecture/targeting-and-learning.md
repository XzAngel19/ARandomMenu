# Targeting, camera assist and Learning

## Scope

The universal combat path now has two separate layers:

1. `src/library/Targeting.luau` is a read-only selector. It refreshes the
   entity index, applies team and Friend List policy, checks the screen-space
   FOV, optionally checks visibility, and returns a target record.
2. `src/modules/Combat/AimAssist.luau` consumes that record and changes only the
   local camera while it is enabled. It does not fire, aim a tool, edit a
   remote, modify a hitbox or intercept an engine method.

This is an intentional Roblox adaptation, not a general Silent Aim. The
selector is useful to a future supported-game adapter, but a game adapter must
be explicit about its place and weapon contract. It may not become a global
hook hidden behind a universal card.

`Interact Extender` remains the existing adapted Reach surface for
`ProximityPrompt` and `ClickDetector` interactions. Combat reach is not silently
represented by that name: it requires a separate, game-specific contract and
has not been added to the universal core.

## Why a module can still interfere

A file boundary is not a runtime boundary. A module that calls one of these
changes a process-wide or shared engine surface:

| Technique | What it can affect outside the card |
| --- | --- |
| `hookfunction` on `Ray.new` or an instance method | Every caller of that closure, including unrelated weapons, ESP and game code. |
| `hookmetamethod` on `__namecall` or `__index` | Every matching remote/property call in the client, not just the card that installed it. |
| Editing `Mouse.Hit`, `CurrentCamera.CFrame` or shared character parts | The Roblox camera/controller, other modules and the game's own scripts all read the same object. |
| Rewriting remote arguments | The server receives a changed action and other features using that remote can observe or inherit the change. |
| A background screenshot/upload loop | It collects outside the player's explicit action and creates a privacy and data-retention problem. |

That is why “Silent Aim is its own module” is not enough. Ownership in the
source tree does not isolate a hook or a shared Instance. The safe contract is
to keep the effect narrow, explicit, and removable.

## No-interference contract

- `Targeting` writes no game objects; it only refreshes the existing entity index and builds temporary result tables.
- `Aim Assist` runs through the module render task and stops while ClickGUI,
  text input or key capture owns the input surface.
- Disabling Aim Assist disconnects its render task. It does not install an
  input listener, click simulator or hook that another feature has to restore.
- A target is never selected for a teammate or Friend List entry, and a
  visibility failure rejects the target rather than falling through to a wall.
- The FOV, target part, priority, prediction, distance and policy controls are
  read by the selector. No control is decorative.
- A future adapter must use an explicit `GAME_CHECK`/place contract and a
  module-local callback supplied by that game. It must not patch global engine
  methods or use anti-cheat evasion as an integration strategy.

## Learning samples

`src/modules/Utility/Learning.luau` is a manual local sample action. It saves:

- one screenshot through the optional `screenCapture` capability service;
- one small JSON sidecar containing the image path, place id, capture time,
  viewport and whether the menu was visible.

It never starts a capture loop, sends data over HTTP, fires a remote, or hides
the menu before taking the sample. Standard Roblox Luau does not provide a
screen-capture primitive; if the executor has no explicit screenshot function,
the card reports `unavailable` and does nothing.

The service recognizes only executor-provided screenshot functions published by
the shell. The module does not guess a private API and does not silently fall
back to a network transport. The player must press `Capture now` for every
sample.

## Existing game-specific Silent Aim

The repository already contains a pre-existing MVSD-specific `Silent Aim`
path in `src/games/MVSD.luau`. This change does not generalize or extend it.
Its hook-based implementation is intentionally outside the new universal
Aim Assist contract and should not be copied into other games. Any future
MVSD cleanup should migrate it to an explicit, supported shot adapter or
remove it; universal modules must remain hook-free.

## Verification

The focused suite is `tools/test/suites/targeting.luau`. It proves selector
policy, obstruction handling, Friend List filtering, camera-only movement,
no tool activation, manual screenshot invocation and the metadata sidecar.
The full validation command remains:

```text
REQUIRE_LUAU=1 LUAU_DIR=/tmp/luau-src/build ./tools/validate.sh
```
