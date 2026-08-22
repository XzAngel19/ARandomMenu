# Bitmap renderer budgets

Measured against `state.bitmapText` counters (`created`, `reused`,
`skips`, `lastDrawMs`) and the surfaces A has migrated (version,
titles, feature rows, HackList).

These are leak ceilings, not targets. A healthy ClickGUI sits far
below them. Crossing one means a pool is not releasing.

| Situation | Glyph instances | Why |
|---|---|---|
| Idle ClickGUI, five occupied category windows | < 800 | ~12 glyphs/title × 5 + ~20 feature names × ~10 + chrome |
| Same + five open settings windows | < 1200 | settings labels still TextLabel today; budget is for when they move |
| Navigator open | < 1000 | 36 cells × ~10 glyphs if migrated; today TextButtons |
| HackList of 20 names | < 400 | one ImageLabel per glyph, plus shadow copies if enabled |
| Open/close a settings window 20 times | `created` growth ≤ `release` | no leak |
| Unchanged frame | `skips` increases, `created` does not | signature skip |

`lastDrawMs` is wall time of one `draw()`. A single title redraw
should stay well under 2 ms on the CLI; the gate records the counter
exists rather than a machine-specific number.

7.54.1 does not change these numbers: it still draws `MC.font` once
per string. The budget is a Roblox ImageLabel cost, not a Wurst one.
