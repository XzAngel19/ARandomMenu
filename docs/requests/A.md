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

## Atlas increment (2026-08-22, late)

- `tools/make_font_atlas.py` rasterises Monocraft (OFL) into
  `assets/font/monocraft-16.png` + metrics JSON (fixed 11×17 cells,
  advance 11, 16 columns, ASCII 32..126). `--check` verifies both are
  current — C may want it in the gate.
- Runtime: `state.bitmapText.atlas` (metrics + ready flag),
  `state.bitmapText.draw(parent, segments, opts)` renders glyph
  ImageLabels from the atlas once `state.resolveAsset("bitmapFontAtlas")`
  lands, TextLabel/Monocraft until then, `onReady` for surfaces that
  re-render. The HackList draws through it end to end.
- Debt: every other surface (titles, rows, settings labels, keybinds,
  navigator, tooltips, version) still renders TextLabels through the
  contract's `make`; migrating them to `draw` is mechanical but not done.
  ImageLabel cost is ~1 per glyph — fine for the HackList's ~300, worth
  measuring before the 38-row category windows move over.

## Minecraft 1.18.1 font pipeline (2026-08-22)

- Wurst 7.19 targets Minecraft 1.18.1, so the exact font is that
  version's `assets/minecraft/font/default.json` provider stack, not
  Monocraft. The shared authority is
  `assets/font/minecraft-1.18.1.manifest.json`, documented in
  `docs/minecraft-1.18.1-font.md` and checked offline by
  `tools/check_font_authority.py`.
- `tools/fetch_minecraft_font.py --update` is the only network path. It
  downloads the official client jar pinned at sha1
  `7e46fb47609401970e2818989fa584fd467cd036`, verifies it, and extracts
  font inputs under the gitignored `cache/minecraft-1.18.1/` directory.
- **No Mojang texture is committed.** A locally derived exact atlas also
  remains unversioned. Monocraft (`assets/font/monocraft-16.png`, OFL)
  is the committed fallback and must never be labelled "Minecraft exact".
- Normal validation is offline. The explicit update command is run only
  on a machine that can reach Mojang's distribution servers.

## Universal placement + bitmap renderer (2026-08-22, later)

- WindowManager now owns placement for every window: one coordinate
  space (logical = screen / the layer's UIScale; helpers
  LogicalViewport / ScreenToLogical / LogicalToScreen / MeasureWindow /
  AbsoluteRect published), FindFreeRect (AABB with a 10 px gap,
  obstacles measured at fullHeight, anchor right → left → below → grid
  scan → clamped fallback), PlaceWindow (manual positions win),
  ReflowWindow (the mandatory second placement after real measures).
  Feature settings anchor to their category window; the SettingsPage
  management windows anchor to UI Settings and place on first open;
  Reset layout forgets userMoved and re-places what is visible.
- `state.bitmapText` extended: pooling per holder (signature skip,
  in-place reuse, surplus hidden), ascent 14, Minecraft shadow,
  Left/Center/Right, maxWidth clipping, newline handling, transparency,
  measure(), MeasuredWidth attribute, release(), stats
  (draws/skips/created/reused/lastDrawMs), auto re-render of every live
  draw when the atlas resolves.
- Migrated off TextLabels at runtime: version chip, window titles
  (theme-change re-tint via ThemeEngine.OnChange), category feature
  rows (applyCardSkin recolours by pooled redraw), HackList (already).
  The TextLabel branches that remain are harness stand-ins only — the
  host stub does not publish the contract.
- **Still owed on the migration list (in order):** settings labels and
  values (OptionLabel is load-bearing: WindowManager packing reads its
  Text/TextBounds, widgets reposition it, suites read it — needs its
  own careful checkpoint), Keybinds rows, Navigator cells, tooltips.
  Each will stop creating its TextLabel when it moves.
- Also owed: settings windows re-pack width only on the first deferred
  pass (pre-existing); the A2 downloader cannot run inside the sandbox
  (TLS to piston-meta blocked) — exercised on real machines, lock
  hashes pinned from the official manifest.
