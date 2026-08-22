# Requests from agent C

The integrator owns `ARandomMenu.luau`. Agent D owns `src/modules/**` and
`src/games/**`. C cannot edit those.

## Visual RC (C1 classification)

Integrator note: the three A→D P1s are consumed. Verified blocking, not
re-listed as debt. See `docs/visual/VISUAL-RC.md`.

| Item | Status |
|---|---|
| A P1 Retile clamp | **resuelto + test bloqueante** |
| A P1 keybind tooltip measure | **resuelto + test bloqueante** |
| A P1 dock tooltip measure | **resuelto + test bloqueante** |
| A P2 widgets disabled API | **deuda demostrada** — no blocking test |
| Capturas reales Roblox | **deuda demostrada** — headless no rasteriza |
| SetColor crash (`row.label`) | **defecto pequeño** — `hudColor` + `forceHudRefresh()` |
| `closeInvalidPopups` unpublished | **deuda demostrada** — menu-hide blocking; owner/scroll wait |

## Landed — do not regress

- Eight official names stay in `KNOWN_CATEGORIES`. Occupied windows
  (Combat, Render, Movement, Fun, Other) exist. Visuals / Protection /
  Utility / Spoof are not windows. Empty Blocks / Chat / Items stay in
  the contract and draw no window until a module lands in them.
- Feature rows: no star, no hamburger. The keybind square is an approved
  user-requested adaptation and replaces the old ban on desktop key
  slots. `hasSettings` is derived. The triangle exists only when there
  are options. Titles are centred on the full row; the arrow does not
  move the centre. The leftover KEY pill stays forbidden.
- Navigator is its own screen. TabGUI default Disabled.
- WurstLogo stripe at scale-2 y=12 height 22, half alpha, seed `#FFFFFF`.
  Version `0.1 Beta`. Chip packs to
  `LOGO_WIDTH + 10 + (8 + #version * 12) + 4`. Never `LOGO_WIDTH + 130`.
  Never an opaque slab.
- UI Settings shortcuts open windows. Slider rail 6 / knob 16×16 /
  checkbox 22 / colour 44. Pixel icons, not `+` `–` `▪`.
- Independent SettingsWindow: `WindowManager.OpenFeatureSettings(feature)`
  is the one contract. Persistent id `FeatureSettings_<configKey>`.
- Placement: `FindFreeRect` / `PlaceWindow` / `ReflowWindow` are
  blocking. AABB after content and the second layout must be empty.
  Feature settings sit to the right of their category when there is room.
  Manual positions win; Reset layout forgets `userMoved` and re-places.
  An invalid persisted position is clamped (MARGIN 6).
- `makeTextLabel` / `makeButton` / `makeTextBox` and the ScreenGui /
  Popup roots set `AutoLocalize = false`.
- ClickGui calibration viewport is 1600×900 (`CALIBRATION_WIDTH/HEIGHT`).
- Font authority is Minecraft 1.18.1 (`docs/minecraft-1.18.1-font.md`).
  Wurst 7.54.1 is **not** the font baseline.
- Universal inventory is frozen at 38
  (`tools/inventory_snapshot.json` / `tools/check_inventory.py`).
- 7.54.1 GUI APPLY list is closed in
  `docs/wurst-7.19-to-7.54.1-gui-delta.md`. No new hacks.
- Bitmap contract (A `13b48da`): `state.bitmapText.draw` / `adopt` /
  `adoptTree` / `release`. Migrated surfaces: version, titles, feature
  rows, HackList, settings OptionLabel / combo / hex, Keybinds, Add
  Keybind, Profiles, Wurst Options, UI Settings, Navigator, tooltips.
  Slider `NumericValue` stays a TextBox (typed input). The harness
  stand-in is the only TextLabel title branch. C4 fails a regression
  to a second visible TextLabel on those surfaces.
- Bitmap budgets (C5) are measured, not guessed: see
  `docs/bitmap-budgets.md`. Idle < 550 glyphs; five settings < 1600;
  Navigator delta < 800; open/close 20× does not leak; destruct leaves
  zero live records.
- APPLY-1 live Max height / Max settings height = 200.
- APPLY-2 persist + display clamp, keep MARGIN 6.
- APPLY-3 settings beside the category via FindFreeRect.
- APPLY-4 menu-hide closes ChoiceList (blocking). Owner-window close
  and scroll-clip become blocking the moment A publishes
  `closeInvalidPopups` / `closePopupsOutsideArea`.
- APPLY-5 pixel title-bar icons.
- Keybinds "Add" dialog exists (`KeybindAdd`). Dynamic packing
  (`repack` / `repackWidth`) is live. Config schema 2 drops a stored
  Max height of 1000.

- NoFall Settings title stays in the header, clipped, one holder,
  no body/chrome invasion, at scales 0.7 / 1 / 1.25 / 1.6.
- Monocraft fallback: OFL, checksum, 176×102, ASCII 32..126, cell
  11×17 / advance 11, Pixelated, integer glyph offsets. Never labelled
  Minecraft exact.
- Exact font installer (`tools/install_minecraft_font.py`) is offline.
  `--check` is the gate. A transferred pack becomes `minecraft-exact`
  under `cache/`; corrupt / incomplete packs are rejected.
- Numeric slider: min/max visible, current editable, FocusLost,
  invalid / NaN / inf rejected, drag clamps. Speed is a single value.
  CPS is an ordered low/high range.
- Menu style: default Wurst, RightControl selected, RightShift is
  Navigator only. Theme switch does not toggle modules. The open
  gesture (`state.openMenuSurface`) follows the stored style and
  never leaves both surfaces up. The cycle callback itself still
  only writes `UI.MenuStyle`.
- Categories sit at the logo height, do not overlap it, wrap, and
  keep manual positions across reflow. Reset layout clears `userMoved`.
- The bottom dock is the pill (`state.pill`): search left, ≡ right,
  FocusLost(true) submits. `state.moduleSearch.Execute` is the
  38-module registry (Killaura / ESP / AutoClicker aliases).
- HackList `SetMode("Hidden")` clears the overlay and leaves modules
  and statuses intact; `SetMode("Auto")` rebuilds the list.
- Escape closes Navigator. The dock sits above the Navigator layer.
  UI Settings is recoverable after leaving Navigator.
- Bitmap glyphs snap to integer physical pixels at scales
  0.7 / 1 / 1.25 / 1.6. The Mode combo stays a ComboValue.

- Capability matrix: full executor, getsynasset-only, no filesystem,
  no HTTP assets, mobile full, mobile limited. Each boot falls back
  and tears down. Never labelled minecraft-exact without a pack.
- Private font URLs: HTTPS only, hash required, 32 MiB pack cap,
  corrupt rollback, no loadstring of remote bytes, cache outside
  `assets/`, no Mojang pixels in git
  (`tools/check_private_font.py`).

## Still owed — do not fail until these land

### Keybind square

Landed on Cards as `BindSquare`. The suite is blocking. Do not regress
the 12 px square, the symmetric title clearance, or the capture path.

### APPLY-4 owner-window + scroll-clip

Menu-hide is blocking. Publish `state.closeInvalidPopups` and
`state.closePopupsOutsideArea` (7.54.1 names). C8 flips those two
checks the moment the functions exist. Do **not** add those functions
from C.

### ClickGui.order follows module-load, not CATEGORY_ORDER

Libraries start before modules, so the official pre-pass sees an
empty `allFeatures` and the first window created is whichever
module loads first (Other). Retile then follows that order.
Re-run the CATEGORY_ORDER pass after modules exist (or rebuild
`ClickGui.order` from it) so Combat, Render, … tile left to right.

### Bottom command dock

Landed. The pill submits through `state.moduleSearch.Execute`
(FocusLost + on-screen Return). Do not regress aliases.

### Menu style cycle does not switch surfaces

Landed as `state.SetMenuStyle(style, openImmediately)`. The suite
is blocking. Never leave both surfaces up.

### Navigator back row

Landed as `WurstDoor` (`< Wurst ClickGUI`). Escape still closes.

### Show dock (desktop only)

Landed as `state.dock.SetVisible`. Mobile still forces the dock.

### HackList settings crash on SetColor

Fixed in Furniture: `SetColor` writes `hudColor` and calls
`forceHudRefresh()`. Opening HackList settings is blocking.

### pickAtlas ceiling

Landed. Downscale-only: ≤8→8, 9..16→16, 17..24→24, 25..32→32,
else the largest ready member.

### RUN / textbox / list still rounded via the shell helper

Widgets no longer creates `UICorner` except the colour-picker SV
cursor. `makeButton` in the shell still calls `addRoundedStyle`.
Strip that for settings surfaces, or stop using `makeButton` for RUN
/ KEY / text boxes.

### Font — see `docs/minecraft-1.18.1-font.md`

1.18.1 is a four-provider stack, not `ascii.png` / advance 6.
Official client SHA1 `7e46fb47609401970e2818989fa584fd467cd036`.
Do not vendor Mojang pixels. Monocraft (`assets/font/monocraft-16.png`,
OFL) is the committed fallback. Do not label it "Minecraft exact".

### TABGUI_STATUS / TACO_ENABLED

Named counterparts still owed. Shipping no TabGUI matches Disabled;
Taco stays off. Do not fail until the names exist.

### Furniture pill tooltip

Landed. `showPillTip` uses `bitmap.measure` / `wrap` / `draw` with
`ellipsis=true`. The `#text * 8` path is only the no-contract fallback.

## Product name leftovers

Do **not** change `guiName`, `blurName` or `storageFolder`.

MM2 and ProjectileCalibration still hard-code `RandomTestingMenu0001`
and `[RTM:…]`. That is D.
