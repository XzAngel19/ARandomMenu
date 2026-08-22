# Requests from agent C

The integrator owns `ARandomMenu.luau`. Agent D owns `src/modules/**` and
`src/games/**`. C cannot edit those.

## Landed — do not regress

- Eight official names stay in `KNOWN_CATEGORIES`. Occupied windows
  (Combat, Render, Movement, Fun, Other) exist. Visuals / Protection /
  Utility / Spoof are not windows.
- Feature rows: no star, no hamburger, no empty keybind box. `hasSettings`
  is derived. The triangle exists only when there are options.
- Navigator is its own screen. TabGUI default Disabled.
- WurstLogo stripe at scale-2 y=12 height 22, half alpha, live setters.
  Version `0.1 Beta`. Never an opaque slab.
- UI Settings shortcuts open windows. Slider rail 6 / knob 16×16 /
  checkbox 22 / colour 44. Pixel icons, not `+` `–` `▪`.
- Settings windows from SettingsPage are not born superimposed. Click
  raises ZIndex. Max height default 200.

## Still owed — do not fail until these land

### Independent SettingsWindow

Cards still parents `Options` to the category row. Opening settings
grows the category window. The suite `settings-window.luau` waits.

Land:

- `"<Feature> Settings"` as a WindowManager window
- opening does not change the category row height or canvas
- options are not descendants of the category body
- triangle and right-click open the same window
- open twice reuses it
- close, collapse, pin, reopen
- Max settings height
- drag + persist
- teardown without leftover tasks
- a module without options never creates the window

The suite flips to blocking the moment that window exists.

### Hide empty Blocks / Chat / Items

They stay in `KNOWN_CATEGORIES`. They must not be visible windows with
zero modules. clickgui-boot and chrome no longer require those three
as visible windows — you can hide them without a red gate. A Chat
module must still create Chat in official order.

### AutoLocalize = false

`makeTextLabel` / `makeButton` / `makeTextBox` and the ScreenGui /
Popup roots have to set `AutoLocalize = false`. The capture translated
Other / Text / Disabled / Zoom. The suite waits. Setting
`AutoLocalize = true` already fails.

### RUN / textbox / list still rounded via the shell helper

Widgets no longer creates `UICorner` except the colour-picker SV
cursor. `makeButton` in the shell still calls `addRoundedStyle`. Strip
that for settings surfaces, or stop using `makeButton` for RUN / KEY /
text boxes.

### Keybinds lists unbound modules

`rebuildKeybinds` still walks every `shortcutBindings` entry, including
`Unknown`. Official manager only lists bound keys plus the menu key.
Drop the empty pills. Pack the width. Do not truncate `RightControl`.

### Titles centred

Category rows still left-align from x=8 and shrink for the arrow.
Official names are centred; the arrow must not move the centre.

### WurstLogo band width

Chip is still `LOGO_WIDTH + 130`. Pack to logo + gap + real version
width so the band does not reach other HUD elements. Migrate a stored
incompatible colour/width.

### Config schema

Add a schema/version for layout and UI Settings. A stored Max height
of 1000 (the old default) must not survive as a Wurst default. Code
defaults stay 200 / 200. Migration must not touch binds or module
`configKeys`.

### Font

Libraries already take `CONTROL_FONT`. Do not hard-code BuilderSans or
RobotoMono in Cards / Widgets / SettingsPage / WindowManager /
Furniture / ClickGui. The face is still Monocraft `FontFace` — a
vector stand-in, not MC.font bitmap. Do not claim "font exacta".

## Product name leftovers

Do **not** change `guiName`, `blurName` or `storageFolder`.

MM2 and ProjectileCalibration still hard-code `RandomTestingMenu0001`
and `[RTM:…]`. That is D.
