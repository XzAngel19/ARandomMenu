# Wurst 7.19 → 7.54.1 GUI / config delta

**GUI_DELTA_READY**

This file is the only place 7.54.1 is allowed to influence the port.
It compares **global ClickGUI / settings / persistence** only.
It is **not** a permission to port hacks, modules, categories, or
options that belong to features added after 7.19.

The universal inventory stays **exactly 38 modules**. Branding stays
`Wurst` / `0.1 Beta`. The visual font baseline stays Minecraft
**1.18.1** (Wurst 7.19's game). 7.54.1's later Minecraft font stack
is rejected as a baseline.

## Authority pins

| Role | Pin | SHA | Date | Notes |
|---|---|---|---|---|
| Identity / inventory / font / chrome numbers | Wurst **7.19** tag `v7.19` | `dbc25e930434adf20039de32c30e397c17983928` | 2021-12-19 | Ships against Minecraft **1.18.1**. |
| Global GUI / config *improvements only* | Wurst **7.54.1** tag `v7.54.1-MC1.21.11` | `5da852422a558255518a1caa978eae75fd53837f` | 2026-08-04 | Same 7.54.1 GUI across the other 7.54.1 MC tags. |
| Previously cited tree in NOTICE | `4a22e53d774b9a28e395874834f099e779685998` | 2026-08-10 | Later than 7.54.1. **Not** the identity pin. Do not treat it as 7.19. |
| Minecraft font | Java Edition **1.18.1** client | `7e46fb47609401970e2818989fa584fd467cd036` | 2021-12-10 | `docs/minecraft-1.18.1-font.md`. |

Sources (read-only, GPL-3):

- https://github.com/Wurst-Imperium/Wurst7/tree/v7.19
- https://github.com/Wurst-Imperium/Wurst7/tree/v7.54.1-MC1.21.11

Compared classes (GUI / config only):

`clickgui/ClickGui.java`, `Window.java`, `SettingsWindow.java`,
`Component.java`, `Popup.java`, `ComboBoxPopup.java`,
`ClickGuiIcons.java` (7.54.1 only), `components/{FeatureButton,
Checkbox,Slider,Color,ComboBox}Component.java`,
`screens/ClickGuiScreen.java`, `hacks/ClickGuiHack.java`,
`other_features/{HackListOtf,WurstLogoOtf,TabGuiOtf}.java`,
`hud/{HackListHUD,WurstLogo}.java`,
`keybinds/{KeybindList,KeybindsFile}.java`,
`options/{KeybindManagerScreen,KeybindProfilesScreen,WurstOptionsScreen}.java`,
`navigator/{Navigator,NavigatorMainScreen}.java`,
`settings/SettingsFile.java`.

New-hack widgets that appeared in 7.54.1 (`BookOffers*`,
`PlantType*`, `TextFieldEditButton` as a *new-hack* control) were
opened only to classify them **REJECT**. They are not a port list.

## Closed APPLY list

These are the only 7.54.1 GUI/config changes this port may take.
Each is a global window/settings behaviour, not a new hack.

### APPLY-1 — Live Max height / Max settings height

- **Upstream:** `ClickGuiHack` (7.54.1 adds the two sliders);
  `ClickGui.updateColors` / `renderWindow` applies
  `window.setMaxHeight(window instanceof SettingsWindow ? maxSettingsHeight : maxHeight)`.
- **7.19:** no sliders. `SettingsWindow` hard-codes `setMaxHeight(187)`;
  category windows hard-code 187 in `renderWindow`.
- **7.54.1:** sliders default 200, min 0 (no limit), max 1000, step 50.
  Settings windows use 200, not 187.
- **Why:** one live cap instead of a magic number; 0 = unlimited is
  Wurst's own tooltip. Does not add a hack.
- **Contract:** named defaults 200 / 200; a settings window's height
  `<= uiMaxSettingsHeight` when that value is > 0. Already held.
- **Status vs port:** **ALREADY** (sliders / `state.uiMaxSettingsHeight`
  / `state.uiMaxHeight`). Keep 7.19-compatible defaults (200).

### APPLY-2 — Display clamp vs persisted position

- **Upstream:** `Window.getX` / `getY` clamp to keep 1 px on screen
  (`x ∈ [-width+1, scaledWidth-1]`, `y ∈ [-12, scaledHeight-1]`).
  `getActualX` / `getActualY` return the unclamped store.
  `ClickGui.saveWindows` writes actual coords.
- **7.19:** `getX`/`getY` return the raw field; a window dragged
  mostly off-screen stays there and can be lost.
- **7.54.1:** the window *looks* on-screen; the next boot restores
  the user's actual drag.
- **Why:** global window persistence, no new content.
- **Contract:** persist `configData.ui.windows[id].x/y` as the last
  user drag (or last placed slot). Display path clamps. A shrink of
  the viewport must not strand a window (`Reclamp` / `ClampWindow`).
- **Status vs port:** **partial ALREADY**. We clamp on save *and*
  display (`MARGIN=6`, whole window inside). Stricter than 7.54.1's
  "1 px remains". Do **not** loosen the clamp. Optional later: store
  pre-clamp coords as `actualX/Y` without changing the on-screen
  rule. Not required to match 7.54.1's 1-px leak.

### APPLY-3 — Settings first-open beside the category

- **Upstream:** `SettingsWindow.setInitialPosition`: `x = parent.x +
  parent.width + 5`, `y = parent.y + 12 + buttonY + scroll`; if it
  would pass the right edge, `x = parent.x - width - 5`; if it would
  pass the bottom, `y -= height - 14`; then clamp.
- **7.19 and 7.54.1:** same algorithm. 7.54.1 only renamed
  `getScaledWidth` → `getGuiScaledWidth` and 187 → 200.
- **Why:** this is the official "next to the hack" rule. The port's
  `FindFreeRect` (right → left → below → grid) is the same idea with
  an extra collision search. That extra search is a global
  improvement (issue #176: a submenu can still leave the screen).
- **Contract:** `FindFreeRect` / `PlaceWindow` / `ReflowWindow`;
  feature settings pass the category window as `preferredAnchor`;
  AABB gap `PLACEMENT_GAP=10`; second pass after resize.
- **Status vs port:** **ALREADY** (A, `144f06b` / `e40d5e5`). Gate: C2.

### APPLY-4 — Close popups when their owner is gone

- **Upstream 7.54.1:** `closeInvalidPopups`,
  `closePopupsOutsideArea`, `isPopupOwnerVisible`. A ComboBox popup
  dies if its window is closing, invisible, minimized, or the owner
  row has scrolled out of the body clip.
- **7.19:** popups stay until clicked away; a scrolled-away combo
  can linger.
- **Why:** global popup lifetime, no new hack.
- **Contract:** ChoiceList / colour picker close when the owning
  settings window is closed, collapsed, or hidden with the menu.
  Raising another window must not leave a combo attached to a
  clipped row.
- **Status vs port:** **NEEDS_EVIDENCE** for scroll-clip; menu-hide
  already closes ChoiceList. Do not fail scroll-clip until A lands
  it. Test the landed close-on-hide path only.

### APPLY-5 — Pixel title-bar icons

- **Upstream 7.54.1:** new `ClickGuiIcons.java` (minimize arrow, pin,
  cross, radar). 7.19 drew those with immediate-mode triangles inline
  in `ClickGui.renderWindow`.
- **Why:** same sprites, one place. The port already uses
  `drawPixelIcon` for pin / cross / chevron.
- **Status vs port:** **ALREADY**.

## ALREADY (no work)

| Topic | Evidence |
|---|---|
| Independent `<Feature> Settings` window | `OpenFeatureSettings` |
| Category windows: pin + collapse, no close | `ClickGui.categoryWindow` `closable=false` |
| UI Settings shortcuts: WurstLogo, HackList, Keybinds, WurstOptions | SettingsPage |
| Official eight category names | `KNOWN_CATEGORIES` |
| Empty Blocks / Chat / Items draw no window | clickgui-boot |
| Opacity / tooltip opacity / colours as ClickGUI settings | ThemeEngine + UI Settings |
| HackList Mode/Position/Color/Sort/Reverse/Animations | Furniture + settings |
| WurstLogo Background/Text/Visibility | Furniture |
| Navigator as its own screen | Furniture |
| TabGUI default Disabled | TabGuiOtf 7.19 already Disabled |
| windows.json-style persist keyed by id | `configData.ui.windows` |
| Packed settings width | `OpenFeatureSettings` |
| Bitmap text contract + pooling + shadow | `state.bitmapText` |
| One coordinate space + UIScale | `LogicalViewport` / `ScreenToLogical` |

## REJECT (identity / new content)

| Topic | Why |
|---|---|
| Any hack added after 7.19 | Inventory freeze. 38 modules. |
| New categories | Official eight stay. |
| BookOffers / PlantType / new-hack TextField widgets as required chrome | Belong to post-7.19 hacks. |
| RainbowUI driving Accent | A *hack*, not a global ClickGUI setting. Do not invent it. |
| Rebrand to 7.54.1 / change `0.1 Beta` | Identity. |
| Replace 38 modules with the 7.54.1 hack list | Explicitly forbidden. |
| 7.54.1 Minecraft font (`unihex` / Unifont zip) as baseline | Font authority is 1.18.1. |
| Force-English / Count Users / Spoof Vanilla / Wurst links | Minecraft / telemetry / Alexander's URLs. |
| Radar as a ClickGUI window | Radar is a Minecraft hack HUD, not one of the 38. |

## N/A (Minecraft / Fabric only)

- `GuiGraphics` / `MouseButtonEvent` / `Mth` renames.
- `textRenderer` → `MC.font` field rename (same object).
- GL11 → new render pipeline.
- Fabric Loader / mappings / yarn.
- Enchanting-table SGA, Illageralt, force-Unicode font.
- `windows.json` path under `.minecraft/wurst/`.

## NEEDS_EVIDENCE

- Atomic save of `settings.json` / `windows.json`. Both 7.19 and
  7.54.1 write with a plain `BufferedWriter`. No atomic rename in
  either pin. Do **not** require atomic save "because 7.54.1".
- Config schema version in Wurst itself. `SettingsFile` is still
  "parse or start empty". Our own schema (max-height 1000 → 200) is
  a port migration, not an upstream APPLY.
- Keybind conflict UI beyond the existing manager. 7.54.1 manager
  is still Add / Edit / Remove / Reset / Profiles.

## What 7.54.1 must never be used for

- Enumerating new hacks as "owed".
- Changing Manifest.modules.
- Changing PRODUCT.version away from `0.1 Beta`.
- Claiming the font is "whatever current vanilla uses".

Machine-readable pins: `docs/wurst-gui-authority.json`.
