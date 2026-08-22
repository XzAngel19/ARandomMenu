# Requests from agent A

## Add Furniture.luau to the parity gate's constant scan

`tools/extract_prototype_spec.py` reads named ALL_CAPS constants only from
`Widgets.luau`, `WindowManager.luau`, `SettingsPage.luau` and
`ClickGui.luau`. The furniture now lives in `src/library/Furniture.luau`
and carries constants the gate should be holding to Wurst's defaults the
moment it can see them:

- `HACKLIST_COLOR` = `#FFFFFF`
- `HACKLIST_REVERSE` = `false`
- `HACKLIST_ANIMATIONS` = `true`
- `TOOLTIP_DELAY_MS` = `400` (also defined in the shell's
  `addFeatureTooltip`; the shell is not scanned either)

Please add the file to the scan list so a drifted value fails and names
both sides.

One deliberate deviation to record so the gate does not later demand it
silently: Wurst's `HackList.Position` default is `Left`, under its logo.
Our prototype gives the top-left corner to the wordmark and the stats
block, so the list hangs on the **right** edge (and moves top-left under
the stats on a phone, per UI-V2's mobile section). When the HackList
settings window ships and `HACKLIST_POSITION` becomes a named constant,
the spec row for it should carry our default, not upstream's — otherwise
the gate will force a Left default that contradicts the prototype.

## For C, after the fidelity pass (2026-08-21)

- The mock's TextButton carries no `MouseButton2Click`; the row's
  right-click had to go through `InputBegan` + `UserInputType.MouseButton2`
  (which is also what real Roblox prefers). If the harness ever grows the
  signal, the suites can drive right-click directly.
- spec.json regenerated from the prototype: `titleHeight` 26 (Wurst's 13
  logical at GUI scale 2), `radius` 0. `TITLE_HEIGHT=26` now exists in
  WindowManager, ClickGui and SettingsPage; the gate holds all three.
- New surfaces worth measuring/testing: the Navigator under the logo
  (search + 3-column grid, preference-ordered, Enter fires the top hit),
  the 22 px settings arrow that only exists when a module has options,
  and the logo at 144×36.

## For C and D, after the category contract (2026-08-22)

- **D:** the eight official windows exist and the aliases hold your
  modules where they are (Visuals→Render, Protection→Movement,
  Utility→Other, Spoof→Fun). `docs/wurst-categories.md` is the per-card
  map; refile each `framework.Categories.X` / `categoryName` at your own
  pace — nothing falls into General any more (General itself now
  resolves to Other). `feature.hasSettings` is live metadata derived
  from real option rows, if you need it.
- **C:** the Enum stand-in carries no RightControl, Backspace, Tab,
  Return or arrow keys; the shell falls back to RightShift for the menu
  default under the mock, and Navigator's key handling compares against
  nil harmlessly. Adding those KeyCodes would let a suite drive the
  Navigator keyboard for real. The Navigator screen itself is
  state.navigator (root/Open/Close/refresh) — worth a suite: search
  filters, preference order, Enter activates, Space expands, Escape
  closes.

## After the settings-window rebuild (2026-08-22, evening)

- **C:** `WindowManager.OpenFeatureSettings(feature)` is the one contract
  for popped-out settings (triangle, right-click and Navigator Space all
  route through it; lazy, reused, cascaded, capped by
  `state.uiMaxSettingsHeight`, packed width, persistent id
  `FeatureSettings_<configKey>`). Worth a suite. `state.bitmapText` is
  the text contract (16/18/12 px = 8/9/6 logical); the HackList is the
  first full surface on it. `CALIBRATION_WIDTH/HEIGHT = 1600/900` in
  ClickGui is the user-mandated fit reference — please bless it in the
  spec so the gate holds it instead of printing it ungrounded.
- **Deuda declarada:** (1) the Minecraft bitmap atlas itself is not
  rasterised — Monocraft renders behind the contract; (2) with unbound
  modules gone from the Keybinds window, the only desktop path to a NEW
  bind is a loaded profile — Wurst's "Add" dialog is the missing piece;
  (3) settings windows pack their width at first open and do not repack
  if labels change later; (4) the colour picker keeps its circular SV
  cursor (a position marker, not chrome).
