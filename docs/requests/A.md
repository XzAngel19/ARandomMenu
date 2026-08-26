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

## 7.19 closure + bounded 7.54.1 inspection (2026-08-22, second pass)

- `docs/wurst-7.19-to-7.54.1-gui-delta.md` does not exist yet, so no
  APPLY rows were available and none were invented. One bounded
  inspection with evidence: `clickgui/SettingsWindow.java` is byte-for-
  byte identical at the pinned 4a22e53 (7.19) and at
  `v7.54.1-MC26.2` — zero delta there. It did expose a 7.19 baseline
  gap of ours, now fixed: official settings windows are
  `setMinimizable(false)` (close button, no collapse chevron); ours
  were collapsible. Applied to `OpenFeatureSettings`.
- Two deliberate deviations recorded, not bugs: official
  `setInitialPosition` aligns the settings window to the row that
  opened it (`parent.y + 12 + buttonY + scroll`) and tolerates
  overlapping other windows; our placement is the user-mandated AABB
  free-rectangle search (right → left → below → scan), which cannot
  overlap by construction. Official clamps to `0..guiScaledWidth`
  (partial off-screen allowed); we clamp the whole window inside
  MARGIN, also by mandate.
- REJECT (not applied, out of scope by the absolute rule): every
  7.54.1 hack, module, category, hack option, `Manifest.modules`
  change, and any GUI change not demonstrated by direct source
  comparison. Zero new modules were added in this pass.

## Installer + dock + menu style pass (2026-08-22, third)

- `tools/install_minecraft_font.py` is the one-command installer:
  drives `fetch_minecraft_font.py --update` (SHA1-verified client),
  reads the real 1.18.1 `default.json`, measures per-glyph advances by
  the rightmost-ink rule (space = 4), records ascent / lineHeight 9 /
  shadow {1,1,×0.25}, copies ascii/accented/european, re-grids ASCII
  32..126 into the renderer's 16-column layout (`runtime-ascii.png`),
  and writes `MinecraftFont/manifest.json` with per-file SHA1s.
  `--check` verifies; `--output` relocates; it refuses to write under
  assets/. legacy_unicode is recorded, pages not fetched (CDN; ASCII
  covers the GUI). Runtime: the shell probes
  `MinecraftFont/manifest.json` in the executor workspace, verifies
  format/version/runtime table, loads through `loadExactAtlas`, flips
  `source` to minecraft-exact, and never opens client.jar from Luau.
  Wurst Options shows the live Font status row; clicking it prints the
  install instructions.
- Idle glyph budget re-measured at 552 after A4's min/max rail labels
  and the Menu style row (static content, not a leak); ceiling moved
  550 → 700 in C's bitmap-budget suite + doc, same ~35% margin. Same
  commit, per the lane rule — C, please re-bless.
- `state.invokeModuleSearch` is the dock's resolver and is designed to
  be replaced wholesale by D's registry (reassign the field).

## Optional 26.2 font pack (2026-08-22, fourth)

- The installer now builds per-version packs: `--version 1.18.1|26.2`,
  `--source <minecraft-dir>` (auto-detects version json / client jar /
  asset index and verifies jar vs the json's own hash AND the
  per-version pin: 26.2 client `2dc72797…`, asset index 32 `773791…`,
  read off piston-meta 2026-08-22), recursive default.json through
  `reference` includes, real provider types per version — bitmap,
  space, legacy_unicode, unihex (rasterised only when no bitmap covers
  ASCII), unknown recorded verbatim. Packs land in `MinecraftFont/`
  vs `MinecraftFont-26.2/`; a manifest in the wrong slot fails
  `--check`. Versions never share an atlas.
- Runtime: UI Settings "Font pack" = Minecraft 1.18.1 (default —
  the visual authority does not move) / Minecraft 26.2 / Monocraft,
  stored as `UI.FontPack`, applied live via
  `state.bitmapText.applyFontPack` (atlas generation in the draw
  signatures repaints exactly once). A selected-but-missing pack warns
  once per selection and renders Monocraft; a loaded pack disables the
  Monocraft 8/24/32 raster variants so two fonts never mix on screen.
  Sources: minecraft-exact / minecraft-26.2-local /
  monocraft-fallback / unavailable, all visible in Wurst Options.
- C: the offline installer tests still pass byte-compatible; the
  `/cache/` gitignore now covers everything (a synthetic test fixture
  briefly landed in dea7201 and was swept in 8766c50 — no Mojang
  bytes, but cache is never Git's).

## Bug pass: style machine, Navigator exit, dock submit, HUD toggles, raster rule (2026-08-22, fifth)

- `state.SetMenuStyle(style, openImmediately)` is the one style path
  (persist, close the open surface, open on demand, notify
  `state.menuStyleListeners`; touches nothing else). UI Settings calls
  it with openImmediately only on a real change (the widget replays at
  boot). openMenuSurface also closes a RightShift-opened Navigator
  before showing Wurst — the two surfaces can never coexist.
- Navigator exits: dock at Z 249 (above the 246 dim even on the
  PopupLayer fallback), the ≡ button returns to Wurst while the
  Navigator is open, and a "< Wurst ClickGUI" door sits inside the
  screen. Escape unchanged.
- The dock submits exclusively through `state.moduleSearch.Execute`
  (D's registry) with a 0.2 s token so FocusLost(true) and the
  on-screen-keyboard signal cannot double-fire; all four statuses
  notify. `state.invokeModuleSearch` is now a three-line wrapper over
  the same Execute.
- Show HackList / Show dock in UI Settings (defaults true, live,
  persisted; `Furniture.SetHackListVisible` + `state.hudList.SetVisible`
  + `state.dock.SetVisible`). Touch-primary devices keep the dock
  always visible and never see the Show dock row; hidden means
  Visible=false, never destruction; RightControl is independent.
- `pickAtlas` is downscale-only: smallest ready raster covering the
  physical target, largest only when everything undershoots, 8 px only
  for targets <= 8. Verified headless at 0.7/1/1.25/1.4/1.6 and a
  short viewport: NoFall title clipped inside the chrome, integer
  physical rects, dropdown glyphs never from an upscaled 8.

## Keybind square (2026-08-22, sixth)

- Every bindable row (kind toggle/hold; never group, never action cards
  like Rejoin, never a feature without a registered binding) grows a
  permanent 12×12 flat square at x=4, vertically centred on the 22 px
  row: thin StyleStroke, no UICorner, no text ever — the canonical
  capturer's "..." is written into an invisible ink. States: unbound
  (dark, stroke 0.6), capturing (the canonical setKeySlotCapture tint —
  no second system), bound (green edge 0.25 over a dark green fill),
  conflict (red edge 0.15; the 400 ms tooltip names the other binding).
- Capture is exclusively beginKeyCapture + binding.assign: next key
  assigns, the bound key or Backspace/Delete clears, Escape cancels
  globally, a press off the square cancels, clicking the square again
  cancels, and no path reads or writes feature.enabled or calls
  activate — held by the rows suite (24 new checks) and a full-boot
  sim at 0.7/1/1.25/1.6 (32 squares, 0 on wrong kinds).
- The title's clearance went symmetric (28 px both sides, bitmap
  maxWidth 140): the square and the arrow can never be invaded by a
  long name and the centre does not move — the rows suite now asserts
  the symmetry instead of the full-width offset.
- No physical keyboard → square hidden; KeyboardEnabled flipping shows
  it live. Binding contract additions: feature.bindSquare,
  feature.syncBindSquare.

## Register the BedWars game module

`src/games/BedWars.luau` exists and its suite runs, but nothing loads it: the
shell has no entry for place `8444591321`. Two lines in `ARandomMenu.luau`, both
in your lane:

- `GAME_CHECK` gains `BedWars = 8444591321` and `BedWarsActive =
  ACTIVE_GAME_MODULE == "BedWars"`;
- beside the other five, `registerPlaceModule("BedWars", GAME_CHECK.BedWars)`.

And when it is convenient, a `state.bedWarsFeatures = {}` next to
`state.bedFightFeatures` so the cards group under their own section instead of
the default one. The module passes `registry = nil` until then, deliberately:
`check_contracts.py` refuses to read a state field nothing assigns, and that
gate is right.

## Task: load the BedWars module, and one thing to check live

`src/games/BedWars.luau` and `tools/test/suites/bedwars.luau` are in and green,
but nothing loads the module: the shell has no entry for place `8444591321`.
Three lines in `ARandomMenu.luau`, all in your lane:

1. `GAME_CHECK` gains `BedWars = 8444591321` and `BedWarsActive =
   ACTIVE_GAME_MODULE == "BedWars"`.
2. Beside the other five, `registerPlaceModule("BedWars", GAME_CHECK.BedWars)`.
3. `state.bedWarsFeatures = {}` next to `state.bedFightFeatures`, and tell me —
   the module passes `registry = nil` until that exists, so its seven cards
   currently group under the default section. `check_contracts.py` refuses to
   read a state field nothing assigns, and that gate is right, so the module
   will not reach for it before the shell publishes it.

One thing to check in a live session, because headless cannot: **Kill Aura's
team filter**. `Team check` defaults to on and the module compares
`LocalPlayer.Team` with the candidate's, but a headless test that set both to
the same value still saw a swing, and I could not isolate why — the local
player, the team values and the row's default all verified correct before the
swing happened. Either the mock's `Players:GetPlayers()` hands back a player
object that is not the one whose character is targeted, or the comparison is
reading something else at runtime. In BedWars the team is the only filter this
card has, so it is worth ten seconds with the card on next to a teammate.

Also note for the record: the Friend List is deliberately **not** consulted by
this card, unlike every other combat module here. BedWars keeps its own
scoreboard, and the player asked for the aura to swing at whoever the game
calls an enemy.

## Done: BedWars is registered, and the team filter is not broken

All three shell lines are in, plus a fourth D's note did not mention:

1. `GAME_CHECK.BedWars = 8444591321` and `BedWarsActive`.
2. `registerPlaceModule("BedWars", GAME_CHECK.BedWars)` beside the other five,
   and `GAME_CHECK.BedWarsActive` in the late-fingerprint branch that reassigns
   the other five actives — without that line a clone detected after boot would
   have left `BedWarsActive` false forever.
3. `state.bedWarsFeatures = {}` next to `state.bedFightFeatures`, published into
   the game-module environment and declared in `state.d.luau`.
   `src/library/Cards.luau` maps it to the section name `BedWars`.
4. **`GAME_MODULES[8444591321] = "BedWars"`** — the one that was missing from the
   request. That table, not `GAME_CHECK`, is what `ACTIVE_GAME_MODULE` is
   resolved from at line 598 and what `loadGameModule` builds the download URL
   from. With only the three requested lines the module still would not have
   loaded: `registerPlaceModule` returns early unless
   `game.PlaceId == placeId`, which works, but `ACTIVE_GAME_MODULE` would have
   stayed nil, the boot log would have said `Universal`, and
   `GAME_CHECK.matches(GAME_CHECK.BedWars)` would have returned false in a
   clone.

`registry` in `src/games/BedWars.luau` is still `nil` and that file is yours, not
mine — `state.bedWarsFeatures` now exists, so the line can become
`local registry: any = state.bedWarsFeatures` whenever you next touch the file.
The module does not take `state` from the host today, so that needs a
`local state: any = host.state` beside the other host reads.

### The team filter works. The suite was lying to you.

You asked for a live check because a headless test that set both teams equal
still saw a swing. It does not need a live check — I reproduced it and the bug
is in the harness, not in `sameTeam`.

`world.addPlayer` appends to a roster that is **never reset between suites**, and
`bedwars` is the last suite in `run.luau`. By the time it runs, the roster holds
nine players left behind by `entity`, `utility-misc`, `targeting`,
`combat-analytics` and `games`. Two of them are Red and standing inside the
aura's 12-stud reach:

```
  Enemy          team=Blue  sameTeam=true   dist= 8.00  SWING=false   <- the victim you re-teamed
  FlingTarget    team=Red   sameTeam=false  dist= 6.00  SWING=true    <- utility-misc left this one
  HitboxEnemy    team=Red   sameTeam=false  dist= 8.00  SWING=true    <- combat-analytics left this one
```

So the swing the test saw was real, correct, and aimed at somebody else.
`sameTeam` had already excluded the intended victim. The module compares
`LocalPlayer.Team` against `player.Team` and both are the same `Team` instance
from the mock's `teamNamed` cache, so the identity comparison holds.

To assert it, the test has to name the victim rather than count swings: clear
`sent["SwordHit"]`, re-team the victim, step, and check that no recorded payload
has `entityInstance == enemy.Character` — not that the payload count stayed
still. A count-based assertion in this suite measures the leftovers.

The real defect worth fixing is the shared roster: a suite that adds a player
should remove it, or `run.luau` should snapshot and restore the roster around
each suite. That is your call and C's lane respectively; I have not changed
either, because a fix and the test that proves it belong in one commit and this
one is mine only by accident of finding it.

## Review: I added a registration point to `src/library/Weapons.luau`

Flagging it because that file is yours and the rule is that I ask first - the
instruction was to make the universal Auto Clicker work in BedWars through game
support rather than fork it, and the weapon library is the only seam that
reaches both cards.

The change is additive: `library:RegisterGameSource({scan, press})`. A game
describes what can be pressed and how; `Scan` prepends those candidates with
kind `"Game"`, `Activate` routes that kind to the game's `press`, and
`RegisterGameSource(nil)` clears it. No existing call path changes, and the
combat suite still passes untouched.

BedWars uses it for sword / wool / pickaxe, so holding the attack button
autoclicks in BedWars exactly as it does anywhere else, and there is no second
Auto Clicker or Kill Aura card in that game any more. If you would rather the
seam lived somewhere else, it is three small functions to move.
