# D surface report

Base: `b47dd40`; A core APIs: `52a02ee`.

## D1 — Wurst ClickGUI composition

Category reset layout now re-enters WindowManager's clamp/snap contract after every `nextSlot`. Top-row ownership, schema 3 and category ordering are unchanged.

## D2 — Feature rows

No geometry changes. The existing 38-row inventory, canonical settings arrow, no empty desktop key slot and stable category-row height remain under A's implementation.

## D3 — Settings windows

The 38-module audit still covers open/close/reopen, reuse, values, Show, enabled state, category height, row height, tasks, connections and teardown. Internal notes are in `docs/requests/D-to-A-visual.md`.

## D4 — Management windows

UI Settings drives the central menu-style state machine and live persisted Show HackList / Show dock settings. Touch forces the dock visible. Rejoin remains a single Wurst Options action.

## D5 — Navigator

Navigator keeps Escape/RightShift behaviour and exposes a Wurst ClickGUI exit action. Switching persists Wurst, closes Navigator and opens ClickGUI immediately.

## D6 — Furniture

The bottom dock is above Navigator and below the tooltip layer. Command submit uses only `state.moduleSearch`, exact aliases and one-submit debounce. HackList and dock visibility do not alter modules or statuses.

## D7 — Themes

No ThemeEngine or theme geometry changes. Tooltip text uses A's bitmap measure/wrap/draw APIs and inherits current theme colours.

## D8 — Module surface sweep

Exactly 38 universal modules. No gameplay changes, new modules, categories or settings. No module depends on legacy page/scroll/tab/card-grid hosts; all options use canonical builders.

## D9 — Readiness

Three P1 composition defects from A's report are addressed:

1. category Retile passes through manager pixel snap;
2. keybind tooltip no longer estimates width with `#text * 8`;
3. dock tooltip no longer estimates width with `#text * 5.5`.

Pending only real-Roblox capture review; headless validation covers contracts and geometry, not engine raster output.

`D_SURFACES_READY`
