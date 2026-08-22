# Requests for agent C

Work order from A (integrator). Base your branch on the current tip of
`arena/01a0262f-arandommenu` and hand back a hash; A merges into the
integration branch. Never open PRs, never push to main, never force-push.

## Context

New standing verdicts on the integration branch (do not regress them):
Code face permanent (no Font pack row), 16 px type contract
(`layout.titleFontSize`/`bodyFontSize` = 16, secondary text 14), blur
mandatory, toasts on the unscaled shell, and a boot-time **cache sweep**:
`state.sweepStaleSources()` (deletes `ARandomMenu/` cached sources absent
from the accepted bundle, spares `.stamp`) and `state.sweepStaleAssets()`
(deletes files in `<storage>/Assets/` not named by the AssetManager
manifest). Both run in a `task.spawn` right after "Bundle aceptado".

## C1 — Harness: file-system surface

`tools/test/Roblox.luau` mocks `writefile/isfolder/makefolder` but not
`readfile`, `isfile`, `listfiles` or `delfile`, so nothing that loads a
config or sweeps a cache is testable without hand-injected globals. Add
them, backed by `world.files` (listfiles = keys with the folder prefix;
delfile removes the key; readfile returns the stored string). Keep the
`world.*` contract stable for existing suites.

## C2 — Suites for the new behaviours

Permanent checks (new suite or extend visual-rc):

1. **Cache sweep**: boot with seeded stale files in both caches; assert
   stale deleted, shipped/live kept, `.stamp` kept, and that the sweep is
   a no-op when the bundle was not accepted (offline lifeline rule).
2. **Toast placement**: `ToastContainer` is a direct child of the shell
   ScreenGui (not of PopupLayer), AnchorPoint (1,1), position bottom-right.
3. **Type contract**: `state.layout.titleFontSize == 16`; a drawn card
   title's Fallback label renders at 16; no "Font pack" text object exists
   anywhere after boot.
4. **Config font guard**: a config storing `interfaceFont = "Minecraft
   (Monocraft)"` boots into Code (the picker no longer offers it).

## C3 — Size parity re-audit vs ref-wurst-719

The port claims Wurst-at-GUI-scale-2 calibration: window width 200,
TITLE_HEIGHT 26, cardHeight 22, text 16. Audit those against the pinned
Wurst 7.19 source (ClickGuiWindow/HackButton metrics) and report deltas in
`docs/visual/C-size-parity.md`. Report only — surface changes go through A.

## C4 — VISUAL-RC.md refresh

Re-prioritize the capture checklist for the user's next round: (1) ClickGUI
idle showing the 16 px type, (2) toast visible fully inside the corner,
(3) UI Settings without the Font pack row, (4) console line
`[Wurst:Cache] swept …` after an update that removed files.

## Rules

- `bash tools/preflight.sh <your-branch>` before each commit; validate must
  end "All checks passed." with your new checks counted.
- Do not touch shell/library surfaces; tools, tests and docs only.
- Report format: hash, branch, validate counts, new check count, debt.
