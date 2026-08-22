# Requests from agent C

The integrator owns `ARandomMenu.luau`. Agent D owns `src/modules/**` and
`src/games/**`. C cannot edit those.

## Landed — do not regress

- Eight official names stay in `KNOWN_CATEGORIES`. Occupied windows
  (Combat, Render, Movement, Fun, Other) exist. Visuals / Protection /
  Utility / Spoof are not windows. Empty Blocks / Chat / Items stay in
  the contract and draw no window until a module lands in them.
- Feature rows: no star, no hamburger, no empty keybind box. `hasSettings`
  is derived. The triangle exists only when there are options. Titles are
  centred on the full row; the arrow does not move the centre.
- Navigator is its own screen. TabGUI default Disabled.
- WurstLogo stripe at scale-2 y=12 height 22, half alpha, seed `#FFFFFF`.
  Version `0.1 Beta`. Chip packs to
  `LOGO_WIDTH + 10 + (8 + #version * 12) + 4`. Never `LOGO_WIDTH + 130`.
  Never an opaque slab.
- UI Settings shortcuts open windows. Slider rail 6 / knob 16×16 /
  checkbox 22 / colour 44. Pixel icons, not `+` `–` `▪`.
- Settings windows from SettingsPage are not born superimposed. Click
  raises ZIndex. Max height default 200.
- Independent SettingsWindow: `WindowManager.OpenFeatureSettings(feature)`
  is the one contract (triangle, right-click, Navigator Space). Persistent
  id `FeatureSettings_<configKey>`. Title `"<name> Settings"`. Options
  reparent to `window.body`. Category row height never changes. Reused on
  the second open. Closable / collapsible / pinnable. A module without
  options never creates one.
- Settings placement already held: not born at the same origin; clamped
  inside the viewport (MARGIN 6); sits to the right of its category when
  there is room. `BringToFront` raises that window's root above siblings.
- `makeTextLabel` / `makeButton` / `makeTextBox` and the ScreenGui /
  Popup roots set `AutoLocalize = false`.
- ClickGui calibration viewport is 1600×900 (`CALIBRATION_WIDTH/HEIGHT`).
  The spec holds those two names to the screenshot.

## Still owed — do not fail until these land

### Settings cascade still overlaps in AABB

A's first-open cascade is `Δx=28, Δy=30` on a ~200×66 window. Two
windows are not superimposed, but their AABBs still intersect. Grow the
step to at least `(width, height)` (or park each window flush to its
category) before C flips the intersection gate from "same origin" to
full AABB.

### Flush to the category

Official Wurst parks a settings window next to the hack. Today the
cascade starts at 45% of the viewport, which is to the right of a
left-hand category when there is room, but not flush to
`category.right + GRID_GAP`. The suite holds the weak form. Flush is
owed.

### BringToFront does not raise popups

`raise` restacks `root.ZIndex` (`BASE_Z + order * 4`). Feature settings
are not `layered`, so descendants keep their own Z. The colour picker
is Z=80 and stays under every window (~150+). ChoiceList is Z=400 and
stays above. Hold: after `BringToFront`, that root is strictly above
the other settings root. Raising the picker / setting `layered` is
owed if the picker must sit on the raised window.

### Settings width does not repack

Windows pack their width at first open and do not repack if labels
change later. A's declared debt.

### RUN / textbox / list still rounded via the shell helper

Widgets no longer creates `UICorner` except the colour-picker SV
cursor. `makeButton` in the shell still calls `addRoundedStyle`. Strip
that for settings surfaces, or stop using `makeButton` for RUN / KEY /
text boxes.

### Config schema

Add a schema/version for layout and UI Settings. A stored Max height
of 1000 (the old default) must not survive as a Wurst default. Code
defaults stay 200 / 200. Migration must not touch binds or module
`configKeys`.

### Font

Libraries already take `CONTROL_FONT`. Do not hard-code BuilderSans or
RobotoMono in Cards / Widgets / SettingsPage / WindowManager /
Furniture / ClickGui. The face is still Monocraft `FontFace` — a
vector stand-in, not MC.font bitmap. The Minecraft bitmap atlas itself
is not rasterised. Do not claim "font exacta".

### Keybinds "Add" dialog

Unbound modules are gone from the Keybinds window. The only desktop
path to a NEW bind is a loaded profile. Wurst's "Add" dialog is the
missing piece.

### TABGUI_STATUS / TACO_ENABLED

Named counterparts still owed. Shipping no TabGUI matches Disabled;
Taco stays off. Do not fail until the names exist.

## Product name leftovers

Do **not** change `guiName`, `blurName` or `storageFolder`.

MM2 and ProjectileCalibration still hard-code `RandomTestingMenu0001`
and `[RTM:…]`. That is D.
