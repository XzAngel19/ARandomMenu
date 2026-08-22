# Wurst's feature list, as shipped

The menu is a port, not an interpretation. This file is the inventory of
what official Wurst 7 actually puts on screen: every window the brief
named, every setting inside it, the exact label, the type, the default,
and the in-game description.

Sources, in order of authority:

1. Wurst7 at `4a22e53d774b9a28e395874834f099e779685998` — the Java the
   client compiles (`ClickGuiHack`, `HackListOtf`, `WurstLogoOtf`,
   `ClickGui.init`, `KeybindList`, `TacoCmd`, `NavigatorHack`).
2. `assets/wurst/translations/en_us.json` at that same commit.
3. [wiki.wurstclient.net](https://wurst.wiki/), used only where it
   restates the Java.

The defaults are copied into `docs/design/prototype/spec.json` by
`tools/extract_prototype_spec.py`. A UI Settings window that ships the
wrong one fails the gate and names both sides.

## How to read a row

| Column | Meaning |
|---|---|
| Name | The label on the row. Title Case, as Wurst prints it. |
| Type | `Color`, `Slider`, `Enum`, `Checkbox`, `Text`, `Action`. |
| Default | What a fresh install shows. Hex is `#RRGGBB`. Sliders are the stored number, then the display. |
| Description | The tooltip, verbatim. `(none)` means the Java constructor passed no description. |
| Here | `has` — a counterpart already exists. `none` — owed. `meaningless` — Minecraft / server / Fabric, written down so nobody "rediscovers" it. `absent` — not in official Wurst 7.x. |

Minecraft colour codes (`§l`, `§r`, `§6`) are stripped from the
description column. They only change weight and colour in the tooltip.

---

## ClickGUI

A hack with no category. Description: “Window-based ClickGUI.”
Default keybind: `right.control` → `clickgui`. Opening it does not stay
enabled: `onEnable` opens `ClickGuiScreen` and immediately
`setEnabled(false)`.

It draws one window per `Category` (`Blocks`, `Movement`, `Combat`,
`Render`, `Chat`, `Fun`, `Items`, `Other`), plus the **UI Settings**
window below, plus Radar's own window. Features with `category == null`
(ClickGUI itself, Navigator, HackList, WurstLogo, Keybinds, …) do **not**
get a category window; they only appear in Navigator or as buttons inside
UI Settings.

Window chrome is not a setting. Every window can be dragged by its title
bar, minimised, and pinned. A pinned window stays on screen after
ClickGUI closes and cannot be clicked until ClickGUI is open again.
Settings windows (the ones the arrow next to a feature opens) are
closable; category windows are not. First-run layout is left-to-right
from `(5, 5)` with a 5 px gap, wrapping when the next window would pass
the scaled width. Positions, `minimized` and `pinned` persist in
`windows.json`.

| Name | Type | Default | Description | Here |
|---|---|---|---|---|
| Background | Color | `#404040` | Background color | has — `Theme.surface` / `Theme.background` |
| Accent | Color | `#101010` | Accent color | has — `Theme.accent` / `Theme.outline` |
| Text | Color | `#F0F0F0` | Text color | has — `Theme.text` |
| Opacity | Slider | `0.5` (50%), min `0.15`, max `0.85`, step `0.01` | (none) | none — `ThemeEngine.shape.opacity` is **0.86**, the prototype token, not this slider |
| Tooltip opacity | Slider | `0.75` (75%), min `0.15`, max `1`, step `0.01` | (none) | none — `ThemeEngine.shape.tooltipOpacity` is **0.95** |
| Max height | Slider | `200` px, min `0` (no limit), max `1000`, step `50` | Maximum window height / 0 = no limit | none — prototype `--max-h` is **340**; `ClickGui.WINDOW_MAX_HEIGHT` is **300** |
| Max settings height | Slider | `200` px, min `0`, max `1000`, step `50` | Maximum height for settings windows / 0 = no limit | none |

Background paints the body of every ClickGUI and Navigator window.
Accent paints title bars and the border around buttons and sliders.
Text paints ClickGUI, Navigator and TabGUI labels. The magenta in most
screenshots is a colour a user picked; it is not the default.

---

## UI Settings

Not a feature. A ClickGUI window titled `UI Settings`, built in
`ClickGui.init()` in this order:

1. Feature button → **WurstLogo**
2. Feature button → **HackList**
3. Feature button → **Keybinds** (opens the Keybind Manager)
4. Feature button → **WurstOptions** (opens the Wurst Options screen)
5. Every setting of the ClickGUI hack, in the table above

The four buttons are shortcuts. Their tooltips are the feature
descriptions. There is no setting that belongs only to this window.

| Name | Type | Default | Description | Here |
|---|---|---|---|---|
| WurstLogo | Action | — | Shows the Wurst logo and version on the screen. | has — Furniture draws the chip; the shell still has no `wurstLogo` → `wurst_128.png` mapping |
| HackList | Action | — | Shows a list of active hacks on the screen. | has — Furniture publishes `state.hudList`; Position default is **Right** on purpose |
| Keybinds | Action | — | This is just a shortcut to let you open the Keybind Manager from within the GUI. Normally you would go to Wurst Options > Keybinds. | none — each card has a key slot; there is no manager |
| WurstOptions | Action | — | The main settings menu of Wurst. If you ever lock yourself out of the GUI by deleting your keybinds, this is the place to go to restore them. | none |

`Location` on WurstOptions itself (not shown in this window) is an Enum,
default `Game Menu`, values `Game Menu` / `Statistics`, description
“Where to show the "Wurst Options" button.” Meaningless here: we have no
pause screen and no Statistics screen.

---

## HackList

An Other Feature, no category. Description: “Shows a list of active
hacks on the screen.” No default keybind. Reached from UI Settings or
Navigator.

| Name | Type | Default | Description | Here |
|---|---|---|---|---|
| Mode | Enum | `Auto` (`Auto`, `Count`, `Hidden`) | **Auto** mode renders the whole list if it fits onto the screen. **Count** mode only renders the number of active hacks. **Hidden** mode renders nothing. | none — Furniture implements Auto only |
| Position | Enum | `Left` (`Left`, `Right`) | Which side of the screen the HackList should be shown on. Change this to **Right** when using TabGUI. | has — port default **Right**; `HACKLIST_POSITION` not named yet |
| Color | Color | `#FFFFFF` | Color of the HackList text. Only visible when RainbowUI is disabled. | has — `HACKLIST_COLOR` |
| Sort by | Enum | `Name` (`Name`, `Width`) | Determines how the HackList entries are sorted. Only visible when Mode is set to Auto. | none — Furniture sorts by Name |
| Reverse sorting | Checkbox | off | (none) | has — `HACKLIST_REVERSE` |
| Animations | Checkbox | on | When enabled, entries slide into and out of the HackList as hacks are enabled and disabled. | has — `HACKLIST_ANIMATIONS` |

A status string a hack publishes (Flight's speed, Freecam's camera
speed) is appended to the name in the list. That is `card:SetStatus` on
our side. Furniture now publishes `state.hudList`. Position's official
default is Left (under the logo); this port's default is Right, because
the prototype gives the top-left to the wordmark and the stats.

`Width` sorting is the rendered pixel width of the name, so it has to
be recomputed every tick. Meaningless as a *pixel* sort on Roblox until
the list exists; the enum value still has to be there.

---

## WurstLogo

An Other Feature, no category. Description: “Shows the Wurst logo and
version on the screen.” No default keybind.

| Name | Type | Default | Description | Here |
|---|---|---|---|---|
| Background | Color | `#FFFFFF` | Background color. Only visible when RainbowUI is disabled. | has — `WURSTLOGO_BACKGROUND`; do not reuse ClickGUI's `#404040` |
| Text | Color | `#000000` | Text color. | has — `WURSTLOGO_TEXT`; do not reuse ClickGUI's `#F0F0F0` |
| Visibility | Enum | `Always` (`Always`, `Only when outdated`) | (none) | meaningless — we do not ship a Wurst updater |

The logo is `wurst_128.png` with the version string next to it
(`v7.x MC1.x`). Background is applied at half alpha (`getColorI(128)`).
`Only when outdated` asks `Updater.isOutdated()` for *this* Minecraft
version; a newer Wurst for a newer Minecraft does not count.

---

## Navigator

A hack with no category and no settings. Description: “A searchable GUI
that learns your preferences over time.” Default keybind: `right.shift`
→ `navigator`. Same enable trick as ClickGUI: open the screen, then
disable itself.

It is the only GUI that lists uncategorised features. The list is one
flat grid, three columns, sorted by how often the user has activated
each feature (`preferences.json`, a counter per name). Typing in the
search bar (focused on open, 128 characters, no border) filters that
list; an empty query restores the preference order.

| Key | What it does |
|---|---|
| Enter | Primary action of the selected feature (toggle a hack, run a command). Same as left-click. Increments that feature's preference. |
| Space | Expands the selected feature (opens its settings screen). Same as the green arrow. |
| ↑ / ↓ | Move the selection by one row (three items). |
| ← / →, Tab / Shift+Tab | Move the selection by one item. |
| Escape, Backspace, Mouse 4 | Close Navigator. |

Left-click is the primary action. The arrow expands. There is no
setting for any of this. Search, sort-by-preference and Enter-toggles
are the behaviour; a port that only opens ClickGUI is missing Navigator,
not missing a Navigator checkbox.

Here: none. The shell search box filters the old page of cards. It is
not Navigator.

---

## Keybinds

The Other Feature is named **Keybinds**, not “Keybind Manager”.
Description: “This is just a shortcut to let you open the Keybind
Manager from within the GUI. Normally you would go to Wurst Options >
Keybinds.” No settings of its own. Primary action: “Open Keybind
Manager”.

The manager is a full screen, not a ClickGUI window.

Buttons: **Add**, **Edit** (disabled with no selection), **Remove**
(same), **Back**, **Reset Keybinds** (restores the 14 defaults, does
not delete profiles), **Profiles…**.

A keybind is `(key, commands)`. Several commands are separated by `;`.
A command is a hack name, a Wurst `.command`, or either with the leading
dot stripped. `.say /give @s stone` is how a vanilla command is bound.
The stored key is a Minecraft translation key,
`key.keyboard.<name>`.

### Default keybinds (Wurst 7)

Stored lowercase. The wiki's Title Case is display, not the file.

| Key | Commands | Here |
|---|---|---|
| `key.keyboard.b` | `fastplace;fastbreak` | meaningless — those hacks do not exist here |
| `key.keyboard.c` | `fullbright` | none — Fullbright has no default key |
| `key.keyboard.g` | `flight` | none — Fly has no default key |
| `key.keyboard.semicolon` | `speednuker` | meaningless |
| `key.keyboard.h` | `say /home` | meaningless — no `/home` |
| `key.keyboard.j` | `jesus` | meaningless |
| `key.keyboard.k` | `multiaura` | meaningless |
| `key.keyboard.n` | `nuker` | meaningless |
| `key.keyboard.r` | `killaura` | none — Kill Aura has no default key |
| `key.keyboard.right.control` | `clickgui` | none — the menu key defaults to **RightShift** |
| `key.keyboard.right.shift` | `navigator` | none — RightShift opens ClickGUI, because Navigator does not exist |
| `key.keyboard.u` | `freecam` | meaningless |
| `key.keyboard.x` | `x-ray` | none |
| `key.keyboard.y` | `sneak` | meaningless |

Chat management is `.binds` (`add`, `remove`, `list`, `remove-all`,
`load-profile`, `save-profile`). Any `.binds` invocation can itself be
bound.

Here: each card has one key slot. There is no manager, no Reset, no
multi-command `;`, no `.binds`.

---

## Presets / Profiles

Wurst does not have a “theme preset” and does not snapshot hack
on/off state under this name. What it has is **Keybind Profiles**.

A profile is a `.json` of the current keybind set, in
`.minecraft/wurst/keybinds/`. The Profiles screen offers **Open Folder**,
**New Profile**, **Load**, **Cancel**. New Profile asks for a file name
and appends `.json` if needed. Load replaces the live list with that
file. There is no default profile file; a fresh install has the 14
defaults in `keybinds.json` and an empty profiles folder.

Reset Keybinds restores the 14 defaults and does **not** delete
profiles.

Here: `storageFolder/Profiles/Game_<id>.Config` stores module state and
UI geometry. That is a different object. Do not rename it to look like
Wurst's keybind profiles, and do not pretend the two are the same.

---

## GlobalToggle

**Absent from official Wurst 7.** Not a class, not a setting, not a
wiki page, at the pinned commit and not on `master` either.

The name appears on third-party “Wurst Modified” forks, where it is a
per-hack master switch (an above-ground filter and similar). It is not
ours to invent.

Closest official things, so they are not rediscovered as “the missing
GlobalToggle”:

| Official | What it actually is |
|---|---|
| DisableWurst | Other Feature. “To disable Wurst, go to the Statistics screen and press the Disable Wurst button.” Setting **Hide enable button**, checkbox, default off: “Removes the Enable Wurst button as soon as you close the Statistics screen. You will have to restart the game to re-enable Wurst.” Meaningless here. |
| TooManyHax | A hack that blocks other hacks. Not a global toggle. |
| Panic | Disables every enabled hack at once. A panic button, not a setting. |

---

## Isolate windows

**Absent from official Wurst 7.** Same fork as GlobalToggle. Official
ClickGUI always paints every non-minimised window; there is no setting
that hides the others when one is focused.

What official Wurst *does* have, so it is not mistaken for Isolate:

- **Pin** — the window stays visible after ClickGUI closes.
- **Minimise** — only the title bar remains.
- **Closable settings windows** — one feature's options in their own
  window, closed with the X. Other category windows stay up.

---

## The taco

Not a window and not a setting. A command in category **Fun**.

| | |
|---|---|
| Name | `.taco` |
| Type | Command (toggle) |
| Default | off |
| Description | Spawns a dancing taco on your hotbar. "I love that little guy. So cute!" -WiZARD |
| Syntax | `.taco` — no arguments (“Tacos don't need arguments!”). |
| Primary action | “Be a BOSS!” (toggles it). |
| Default keybind | none |

Four frames, 8 ticks each, cycling `dancingtaco1.png` … `dancingtaco4.png`,
drawn 64×32 just to the right of the hotbar. RainbowUI recolours it;
otherwise it is white. The four PNGs are already vendored under
`assets/wurst/`.

Here: none. The assets are on disk. Nothing draws them.

---

## TabGUI (not in the brief, on the same screen)

Other Feature. Description: “Allows you to quickly toggle hacks while
playing. Use the arrow keys to navigate. Change the HackList Position
setting to Right to prevent TabGUI from overlapping with the HackList.”

| Name | Type | Default | Description | Here |
|---|---|---|---|---|
| Status | Enum | `Disabled` (`Enabled`, `Disabled`) | (none) | none |

No default keybind. Arrow keys navigate categories and hacks. It is not
in the UI Settings window; it lives in Navigator / the Other category.

---

## Wurst Options (opened from UI Settings)

A vanilla-style screen, three columns.

**Settings**

| Name | Type | Default | Description | Here |
|---|---|---|---|---|
| Click Friends | Checkbox | on (`Middle click friends`) | Add/remove friends by clicking them with the middle mouse button. | none — Friend List exists; middle-click add does not |
| Count Users | Checkbox | on | Counts how many people are using Wurst and which versions are the most popular. … These statistics are completely anonymous, never sold, and stay in the EU … | meaningless — do not phone home |
| Spoof Vanilla | Checkbox | off | Bypasses anti-Fabric plugins by pretending to be a vanilla client. | meaningless — Fabric handshake |
| Translations | Checkbox | off on this screen | The button is inverted: it shows ON when **Force English** is unchecked. Force English itself defaults **on**, so Translations shows OFF. “Allows text in Wurst to be displayed in other languages than English. … This is an experimental feature!” | meaningless — we are not translating the menu |

**Managers**

| Name | Opens | Description | Here |
|---|---|---|---|
| Keybinds | Keybind Manager | Keybinds allow you to toggle any hack or command by simply pressing a button. | none |
| X-Ray Blocks | X-Ray block list | Manager for the blocks that X-Ray will show. | meaningless — Minecraft block ids |
| Zoom | Zoom Manager | The Zoom Manager allows you to change the zoom key and how far it will zoom in. | none — Zoom Unlocker is a different card |

Zoom's own settings, for when that window is built: **Zoom level**
slider default `3`× (min 1, max 50, step 0.1); **Use mouse wheel**
checkbox, default on; **Zoom in screens** checkbox, default off;
**Keybind** text, default `key.keyboard.v`.

**Links** (Official Website, Wurst Wiki, WurstForum, Twitter, Donate)
are Alexander's URLs. Do not put them on a Roblox screen.

---

## Chrome and font

Window chrome is not a setting. The numbers live in
`spec.json` `wurst.chrome` (GUI-scale-1 pixels, from the Java) and
`wurst.screenshot` (what `ref-wurst-719.jpg` actually measures).

| What | Wurst (GUI-scale-1) | Screenshot (1600×900) | This port today |
|---|---|---|---|
| Title bar | **13** (`Window` height = inner + 13) | 13 × 10/6 ≈ 22 | prototype `TITLE_HEIGHT` **22** |
| Feature row | **11** (`FeatureButton.getDefaultHeight`) | 11 × 10/6 ≈ 18 | prototype row **22** |
| Settings arrow | **11** (`x3 = x2 - 11`) | — | prototype row |
| Logo blit | **72×18** at (0, 3), texture `wurst:wurst_128.png` | sausage measures **124×27** (Java predicts 120×30; JPEG fringe) | Furniture **87×22** |
| Logo chip fill | y=6–17 (11 px), width = `font.width(version) + 76` | — | chip is `LOGO_WIDTH + 46` × `LOGO_HEIGHT + 8` |
| HackList line | **9** (`posY += 9`) | clusters every **17** (Java predicts 15) | Furniture `HACKLIST_LINE_HEIGHT` **18** |
| Window width | packed to `max(child + 4, title + 4)` | — | prototype **160** |

`ref-wurst-719.jpg` is 1600×900 = a 1920×1080 framebuffer at GUI scale 2,
scaled by 5/6. One Wurst pixel is 10/6 screenshot pixels. The magenta in
that shot is a user palette (Background `#000000`, Text `#FF66CC`); the
defaults are grey/white. `ref-wurst-cyan.jpg` is a fork (Isolate windows,
GlobalToggle, Presets) and is not a source for chrome.

### The font

Wurst does not ship a font. Every label is drawn with
`WurstClient.MC.font` — Minecraft **1.18.1**'s default font
(`net.minecraft.client.gui.Font`). There is no TTF or OTF in the Wurst7
tree.

1.18.1 `assets/minecraft/font/default.json` is a **four-provider**
stack, first match wins: `nonlatin_european.png` (h=8, a=7),
`accented.png` (h=12, a=10), `ascii.png` (h=8, a=7, 16×16 cells,
rows 2–7 = `U+0020`–`U+007E`), then `legacy_unicode`
(`glyph_sizes.bin` + `unicode_page_%s.png`). There is no `space`,
`ttf`, `unihex` or `include` provider. Advance is the last opaque
column + 1, **not** a constant 6. `Font.lineHeight` is 9. Shadow is
`+1,+1` at quarter RGB.

The authority, official URLs/SHA1s, and the redistribution reading
are `docs/minecraft-1.18.1-font.md`. The pin is
`assets/font/minecraft-1.18.1.manifest.json`.

The closest face this repository vendors is Monocraft (OFL), rasterised
to `assets/font/monocraft-16.png`. That is the CI fallback. It is
**not** Minecraft exact (cell 11×17 / advance 11 vs 8-tall scanned
widths). Do not vendor Mojang sheets.

---

## What this file is not

It is not a list of the 158 hacks. `docs/wurst-voice.md` already maps
the ones that have a counterpart here.

It is not a rewrite of our Settings page. The old menu's blur, hail,
text scale, interface font and mobile launcher size are not Wurst, and
they are going away with that page. A test that pins them is a test
that will have to be deleted with them.

The prototype's pixel numbers (`docs/design/prototype/spec.json`
`shape` / `chrome` / `components`) stay the layout spec. The numbers
in this file are the *setting defaults*. They disagree on purpose
today — Opacity 50% vs `--opacity: .86`, Max height 200 vs
`--max-h: 340` — and the UI Settings window has to take Wurst's side.
The gate will say so the moment those defaults exist as named
counterparts.
