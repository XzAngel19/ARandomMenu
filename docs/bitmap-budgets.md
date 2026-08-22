# Bitmap renderer budgets

Measured 2026-08-22 against `state.bitmapText` on A's `13b48da` tree,
in the headless harness with the atlas armed (`Inspect.armAtlas`).
These are leak ceilings, not targets. Crossing one means a pool is
not releasing.

| Situation | Measured | Ceiling | Why |
|---|---|---|---|
| Idle ClickGUI (menu open, five category windows + UI Settings + titles + rows + version) | 552 glyphs (re-measured 2026-08-22 after the numeric rows gained min/max rail labels and UI Settings the Menu style row) | **700** | ~12 glyphs/title × 5 + feature names + chrome |
| Same + five open Feature Settings | 1273 glyphs / 197 holders | **1600** | labels and values now adopted |
| Navigator open (delta over the current live set) | 348 glyphs | **800** | 3-column grid of adopted cells |
| HackList of enabled names | subset of idle | **250** | one ImageLabel per glyph, plus shadow copies if enabled |
| Open/close one settings window 20 times | created growth ≪ 80 | **80** | the same window is reused |
| Unchanged `draw()` | `skipped` +1, `created` unchanged | — | signature skip |
| `release(holder)` | holder leaves `_live` | — | explicit teardown |
| `state.destruct()` | 0 live holders, 0 glyphs | **0** | ScreenGui gone, weak registry empty |

`lastDrawMs` is wall time of one `draw()`. A single title redraw stays
well under 2 ms on the CLI; the gate records the counter rather than a
machine-specific number.

7.54.1 does not change these numbers: it still draws `MC.font` once
per string. The budget is a Roblox ImageLabel cost, not a Wurst one.
The committed atlas remains the Monocraft OFL fallback; 1.18.1 is the
font baseline and is not vendored.
