# Agent C — tooling, tests and docs

Read `docs/agents/RULES.md` first. You have been on this repository before; this
brief is the current queue, not an introduction.

You own **`tools/**`** and **`docs/**`** (except `docs/agents/*`, which is the
integrator's). You do not touch `src/` or the shell — when a test needs a
product change, file it in `docs/requests/C.md` and say it in your reply.

## Queue

### 1. The test-helper duplication

Three suites each carry their own copy of the wrapper that records builder
callbacks, and two of them guessed the callback position wrong (`select(4)`,
`select(6)`) — they recorded nothing and passed anyway. The correct positions:

```
addToggleOption = 3   addKeyOption    = 3   addTextOption = 3
addCycleOption  = 4   addNumberOption = 5
```

Two copies are fixed. There are still three. It belongs once, on `run.luau`'s
`ctx`, and the duplicates deleted. A grep-based gate step should fail on a new
local copy.

### 2. The mock gaps

Every one of these is currently shimmed inside individual suites, which means
each suite has its own idea of what Roblox is. They belong in
`tools/test/Roblox.luau` and `tools/test/Host.luau`. From `docs/notas-B.md`:

`Vector3:Lerp`, `Theme`, `TweenService`, the `CollectionService` tag surface,
`Enum.Font`, `Sound:Play/Stop`, `Player:GetMouse`, `host.getCharacterParts`,
`feature.row`, `host.addFeatureTooltip`, `state.isProtectedTarget`,
`RunService`, `workspace.FallenPartsDestroyHeight`, default part `Size`s,
`Player.Idled`, camera not parented to workspace, `Enum.CameraMode`,
`settings()`.

Absorb them one at a time, deleting the suite-local shim in the same commit. A
mock that two suites disagree about is a mock that is lying to one of them.

### 3. What UI v2 needs from the harness

Read `docs/design/UI-V2.md`. The rebuild lands over the next weeks and it needs
tests that do not exist:

- **Theme.** Boot headless, apply each preset, assert every bound instance
  changed and none kept a stale colour. Assert Monochrome is byte-identical to
  the current palette.
- **Windows.** Boot, open every category window, move one, collapse another,
  serialise the layout, boot again from that config, assert the layout came
  back. Assert no window can be positioned fully off-screen.
- **Rows.** Expand every row that has settings, assert the `Show` rules still
  hide and reveal correctly inside an expanded row, assert the window's height
  tracks.
- **RenderStepped budget.** A second per-frame budget for the new render bucket,
  same shape as the Heartbeat one. The ESP is moving onto `RenderStepped`; a
  regression there is a frame-rate regression in every game.

Write these *before* the code they test where you can. They are the only thing
that will catch the rebuild breaking something that used to work.

### 4. The two loose ends nobody has touched

- `Captura de pantalla 2026-08-20 130752.png` (104 KB) is tracked at the repo
  root. It is not an asset. Remove it and add a rule that fails the gate on a
  tracked image outside `reference/` and `docs/`.
- `.github/workflows/validate.yml` carries a stale instruction header. It is the
  one file we cannot push; write the corrected copy into
  `tools/workflow-validate.yml` and the user will mirror it, as they did before.

## Not wanted

More gate contracts. There are 21 steps and 662 checks; the last few cost more
in maintenance than they catch. If you find a class of bug that keeps recurring,
say so and we will decide — but the default answer to a new idea for a contract
is no.
