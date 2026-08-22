# Requests from agent C

The integrator owns `ARandomMenu.luau`. Agent D owns `src/modules/**` and
`src/games/**`. C cannot edit those.

## Landed — do not regress

- Eight official windows, in order: Combat, Render, Blocks, Movement,
  Chat, Fun, Items, Other. Visuals / Protection / Utility / Spoof are
  aliases, not windows. The gate fails if they come back as titles.
- Feature rows: no star, no hamburger, no empty keybind box. `hasSettings`
  is derived. The triangle exists only when there are options.
- Navigator is its own screen: search, three columns, preference sort,
  Enter, Space, arrows, Escape / Backspace, TabGUI default Disabled.
- WurstLogo stripe at scale-2 y=12 height 22 (logical y=6..17), half
  alpha, live `SetBackground`. Version `0.1 Beta`. Never an opaque slab.
- UI Settings order: WurstLogo, HackList, Keybinds, WurstOptions, then
  Background, Accent, Text, Opacity, Tooltip opacity, Max height, Max
  settings height. Shortcuts open windows; they do not toggle.

## Still owed

### WurstLogo seed colour

Furniture still names `WURSTLOGO_BACKGROUND = #000000`. Official default
is `#FFFFFF` at half alpha (`WurstLogo.java`). The stripe draw is right;
switch the constant to white in the same commit. Extract prints the
black seed as ungrounded and will fail the moment the name stays and
the value is still wrong after you change the comment to claim white.

### Slider rail and knob

Java `SliderComponent` (GUI-scale-1): height 22, rail y=15..18 (3 px,
exclusive max), inset 2, knob 8×8. At the port's GUI scale 2 that is
rail 6, knob 16×16. Widgets still ships the prototype 5 / 7×11.

The gate accepts prototype **or** official so you can land the Java
numbers without a red step. A third pair fails. Extract prints the
prototype pair as ungrounded until you switch.

### Checkbox glyph and shortcut chevron

Official checkbox is a filled square, no mark. Official FeatureButtons
have no `›`. Please drop `Text = "✓"` from `OptionCheckbox` and `Text =
"›"` from the UI Settings shortcuts. The gate already fails `+`, `–`,
`▪` as icons; it will fail those two the moment they are gone from the
product, so remove them rather than replacing them with another glyph.

### Packed window width

Official windows pack to `max(font.width(name)+15, title+4)`. The port
uses 200 (category) and 214 (settings). Recorded as a Roblox adaptation
until you pack. Do not invent a 1080p width.

### TabGUI / Taco constants

`TABGUI_STATUS` and `TACO_ENABLED` are still owed names. Shipping no
TabGUI matches the official Disabled default.

## Product name leftovers

Do **not** change `guiName`, `blurName` or `storageFolder`.

MM2 and ProjectileCalibration still hard-code `RandomTestingMenu0001`
and `[RTM:…]`. That is D.
