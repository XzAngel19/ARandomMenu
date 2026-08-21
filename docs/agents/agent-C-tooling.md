# Agent C — tooling, tests, licensing and assets

You own **`tools/**`** and **`docs/**`** (except `docs/agents/*`, which belongs to
the integrator). You do not edit `src/`, `ARandomMenu.luau`, or
`runtime/bundle.luau`. When a test needs a product change, write it in
`docs/requests/C.md` **and say it in your chat reply**, then keep going.

Read `docs/agents/RULES.md` in full before anything else. Then
`docs/design/UI-V2.md`, and open `docs/design/prototype/index.html` in a browser
— that prototype is the specification for the interface being built.

## What changed, and why your queue is different now

The menu is being rebuilt as a deliberate Roblox port of the **Wurst Client**,
the way `VapeV4ForRoblox` is a port of Vape. Same reading: 95% Wurst, 5% Roblox
in the layout and the polish. That decision drags three things into your lane
that were not there before — a licence, an asset pipeline, and a rename.

## 1. The licence, before anything else

Wurst7 is **GPL-3.0**, and its README is explicit: *"You can only use this code
in open-source clients that you release under the same license."* This
repository currently has **no LICENSE file at all**.

Nothing from Wurst may land in the repo until:

- `LICENSE` — the full GPL-3.0 text.
- `NOTICE.md` — what came from Wurst-Imperium, which files, which commit of
  `Wurst-Imperium/Wurst7` they came from, and their copyright line
  (`Copyright (c) 2014-2026 Wurst-Imperium and contributors`).
- `README.md` — a "this is an unofficial port" paragraph at the top. Not
  affiliated, not endorsed, GPL-3.0, link to the original.
- A gate step that fails if `LICENSE` or `NOTICE.md` is missing or if a file
  under `assets/wurst/` is not listed in `NOTICE.md`.

This is not paperwork for its own sake. GPL-3 is the condition under which we
are allowed to do the thing the project has decided to do.

## 2. The asset pipeline

Wurst's assets are small and I have already listed them. From
`Wurst-Imperium/Wurst7`, `src/main/resources/assets/wurst/`:

| File | Use |
|---|---|
| `wurst_128.png` | The logo. Goes top-left, next to the wordmark. |
| `icon.png` | Small mark, for the pill and the loading screen. |
| `colorpalette.png` | The colour-picker texture. Ours is drawn in code; compare and decide. |
| `dancingtaco1..4.png` | The taco easter egg. Four frames. Keep it — it is part of what the client *is*. |
| `translations/en_us.json` | Every hack name, description and setting label in the client. The most useful file in the list: it is the naming and tooltip voice we are copying. |

Skip `shaders/` and `post_effect/` — Minecraft-specific, useless to us.

Write **`tools/fetch_wurst_assets.py`**:

- Downloads those files at a **pinned commit sha**, not `master`.
- Writes them to `assets/wurst/`, each with its sha256 recorded in
  `assets/wurst/manifest.json` alongside its upstream path and the pinned sha.
- Is idempotent, and prints a diff rather than silently overwriting.
- A gate step re-verifies every checksum, so a corrupted or edited asset fails
  the build instead of shipping.

Note for context, not for you to implement: the runtime already knows how to
show these. `ARandomMenu.luau` downloads a PNG, `writefile`s it and resolves it
through `getcustomasset`/`getsynasset`, with a text fallback when the executor
has neither. Your job ends at "the bytes are vendored, verified and attributed".

## 3. The rename

The product becomes **Wurst** (the repo may stay as it is; that is the user's
call on GitHub). Two things make this less trivial than a search and replace:

- **Do not rename `ARandomMenu.luau`.** It is the loader entry point and its raw
  URL is inside every user's script. The *file* keeps its name; the *product
  name* changes.
- There are roughly 120 occurrences of `ARandomMenu`, `A Random Menu`,
  `Random Testing Menu` and the `RTM:` log prefix across 21 files.

Your part: `README.md`, `docs/`, `tools/`, and **one gate step** that fails when
a product name is hard-coded anywhere outside the single constant the shell
exports. That step is what stops the next rename from being another 120-line
grep. The integrator does the shell and the libraries; agent D does the modules.

## 4. The test-helper duplication

Three suites each carry a private copy of the wrapper that records builder
callbacks, and two of them guessed the callback position wrong (`select(4)`,
`select(6)`) — they recorded nothing and passed anyway. Correct positions:

```
addToggleOption = 3   addKeyOption    = 3   addTextOption = 3
addCycleOption  = 4   addNumberOption = 5
```

Two copies are fixed; three still exist. It belongs once, on `run.luau`'s `ctx`,
with the duplicates deleted and a grep-based gate step that fails on a new local
copy.

## 5. The mock gaps

Each of these is currently shimmed inside individual suites, so every suite has
its own private idea of what Roblox is. They belong in `tools/test/Roblox.luau`
and `tools/test/Host.luau`:

`Vector3:Lerp`, `Theme`, `TweenService`, the `CollectionService` tag surface,
`Enum.Font`, `Sound:Play/Stop`, `Player:GetMouse`, `host.getCharacterParts`,
`feature.row`, `host.addFeatureTooltip`, `state.isProtectedTarget`,
`RunService`, `workspace.FallenPartsDestroyHeight`, default part `Size`s,
`Player.Idled`, camera not parented to workspace, `Enum.CameraMode`,
`settings()`.

Absorb them one at a time, deleting the suite-local shim in the same commit. A
mock two suites disagree about is a mock that is lying to one of them.

## 6. What the ClickGUI will need from the harness

Write these before the code they test where you can — they are the only thing
that will catch the rebuild breaking something that already worked.

- **Theme.** Boot the shell headless, apply each preset, assert every bound
  instance changed and none kept a stale colour. Assert the default preset is
  identical to the palette shipped today.
- **Windows.** Boot, open every category window, move one, collapse another,
  pin a third, serialise the layout, boot again from that config, assert it came
  back. Assert no window can end up fully off-screen.
- **Rows.** Expand every row that has settings and assert the `Show` rules still
  hide and reveal correctly inside an expansion, and that the window's height
  follows. Player ESP has the deepest rule tree in the menu; use it.
- **RenderStepped budget.** A per-frame budget for the new render bucket, the
  same shape as the existing Heartbeat one. The ESP is moving onto
  `RenderStepped`; a regression there is a frame-rate regression in every game.

## 7. Two loose ends nobody has touched

- `Captura de pantalla 2026-08-20 130752.png` (104 KB) is tracked at the repo
  root and is not an asset. Remove it, and add a rule that fails the gate on a
  tracked image outside `assets/`, `reference/` and `docs/`.
- `.github/workflows/validate.yml` carries a stale instruction header. It is the
  one file we cannot push; write the corrected copy to
  `tools/workflow-validate.yml` and the user mirrors it, as they did before.

## Not wanted

More gate contracts beyond the ones named here. There are already 21 steps and
662 checks, and the last few cost more in maintenance than they catch. If you
find a class of bug that keeps recurring, say so and we will decide — but the
default answer to a new idea for a contract is no.
