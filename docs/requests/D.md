# Requests for agent D

Work order from A (integrator). Base your branch on the current tip of
`arena/01a0262f-arandommenu` and hand back a hash; A merges into the
integration branch. Never open PRs, never push to main, never force-push.

## Context you must not fight

The user reviewed real captures against real Wurst 7.19
(https://github.com/Wurst-Imperium/Wurst7). Standing verdicts, already
implemented on the integration branch — do not revert any of them:

- The interface face is **Code** (engine vector), permanently. The Font pack
  row is gone; the bitmap machinery survives only for the suites.
- The type contract is **16 px** for module names, window titles and option
  labels (the Wurst 8-logical size at GUI scale 2), 14 px for secondary text
  (dropdown entries, search boxes, end labels). `layout.titleFontSize` /
  `bodyFontSize` are 16 now.
- Blur behind the open menu is mandatory.
- Toasts live on the unscaled shell, bottom-right.
- Inventory frozen at 38 modules; identity frozen (Wurst / 0.1 Beta /
  RandomTestingMenu0001); no new hacks, no new categories.

## D1 — Options audit against Wurst 7.19 (the big one)

The user asked for the module options to be "simpler and more ordered, like
Wurst has them" and doubts the earlier options rework. For every module that
mirrors a real Wurst hack, open the 7.19 source and compare:

- **Names**: our setting label vs Wurst's setting name. Port Wurst's wording
  where the module is a genuine counterpart (e.g. Speed, Fullbright, X-Ray,
  AntiAFK…). Keep ours where the module is Roblox-specific.
- **Order**: Wurst lists settings in declaration order. Ours should read the
  same way: primary toggle behaviour first, numbers after, cosmetic last.
- **Noise**: any option that duplicates another, does nothing observable, or
  exists "just in case" gets removed from the row list (the module keeps its
  config key so old configs do not error).
- Do NOT add options. Simplify only.

Deliverable: per-module table in `docs/visual/D-options-audit.md`
(module → kept / renamed / removed / reordered, with the Wurst source file
you compared against), plus the actual row changes in your lane files.

## D2 — 16 px QA pass on your surfaces

The type contract moved from 11.5 to 16 and the gate only catches hard
clipping. Walk Furniture, SettingsPage, ClickGui and Cards for soft damage:
labels that now truncate too early, rows whose height reads cramped,
buttons whose text crowds the border. Fix heights/insets in your lane;
if a fix needs a Widgets or shell change, file it in
`docs/requests/D-to-A-visual.md` instead of touching A's files.

## D3 — Window order debt

C's audit flagged that after modules load, the ClickGUI window order can
drift from CATEGORY_ORDER (Combat, Render, Blocks, Movement, Chat, Fun,
Items, Other). Prove it or fix it; the eight windows must always read in
Wurst's order on first run and after Reset Layout.

## Rules

- `bash tools/preflight.sh <your-branch>` before each commit;
  `python3 tools/bundle.py` + `LUAU_DIR=... bash tools/validate.sh` after
  source changes — "All checks passed." or it does not ship.
- Suites that pin your surfaces get updated in the same commit.
- Report format: hash, branch, validate counts, what changed, honest debt.
