# A's deliberate differences vs official Wurst 7

Classified against Wurst 7.19 `v7.19` / `dbc25e9` (identity) and the
7.54.1 GUI APPLY list in `docs/wurst-7.19-to-7.54.1-gui-delta.md`.
`4a22e53` is a later tree, not the identity pin. Also
`ref-wurst-719.jpg`,
`ref-wurst-settings.jpg` and the new Roblox capture. Logical units stay
GUI-scale-1. Prototype `titleHeight` 26 is 13 × 2, not a 1080p invention.

| Difference | Class | Why |
|---|---|---|
| Title bar 26 px (13 logical × GUI scale 2) | exact | spec.wurst.chrome stays 13. |
| Row 22 px (11 logical × 2) | exact | FeatureButton.getDefaultHeight is 11. |
| Slider rail 6 / knob 16×16 / checkbox 22 / colour 44 | exact | Java 3 / 8×8 / 11 / 22 at scale 2. |
| Pixel icons (triangle, pin, cross, check) | exact | ClickGuiIcons, not Unicode. |
| Category windows: pin + collapse, no close | exact | Window.java. |
| Official eight names in KNOWN_CATEGORIES | exact | Combat, Render, Blocks, Movement, Chat, Fun, Items, Other. |
| Occupied windows only (empty Blocks/Chat/Items hidden) | exact | Empty official categories stay in the contract and draw no window. |
| Independent `<Feature> Settings` window | exact | `OpenFeatureSettings`; options reparent; row height unchanged. |
| Settings cascade step 28×30 | exact (replaced) | `FindFreeRect` + `ReflowWindow`; AABB after the second pass is empty. |
| Window width 200 / packed settings | Roblox adaptation | Category 200; settings pack via `packedWidth`. |
| WurstLogo stripe y=12..34, alpha 0.5 | exact | Java fill y=6..17. |
| WurstLogo band packed to version | exact | `LOGO_WIDTH + 10 + (8 + #version × 12) + 4`. `+ 130` is gone. |
| WurstLogo.Background seeded `#FFFFFF` | exact | Java default, half-alpha stripe y=6..17. |
| AutoLocalize = false on helpers and roots | exact | Capture no longer translates Other/Text/Disabled/Zoom. |
| Titles centred on the full row | exact | Arrow does not move the centre. |
| RUN / KEY via `makeButton` (rounded in the shell) | **incorrect** | Official action/combo/textbox controls are rectangles. |
| addSectionOption uppercase headings | **incorrect** for DISPLAY/FILTERS/STYLE/FLIGHT | Official Wurst has no decorative section chips. |
| Keybinds lists unbound modules | exact (replaced) | Manager lists bound keys + menu key. Add dialog (`KeybindAdd`) is the desktop path to a NEW bind. |
| Internal height cap 200 | intentional adaptation | The impossible 0–1000 user slider is gone; viewport-aware layout owns the cap. |
| Navigator as its own screen | exact shape, adapted entry | It opens only from the dock magnifier and owns its search. |
| No TabGUI (default Disabled) | exact | Shipping none matches Disabled. |
| Keybind square on bindable rows | requested Roblox adaptation | Official Wurst binds only in Keybind Manager. The 18 px square shows the compact assigned key; group cards have none. It is not a KEY pill. |
| Compact touch launcher | Roblox adaptation | Mobile keeps only Menu and Navigator; the shell fallback disappears once the dock exists. |
| Full-screen responsive Navigator | Roblox adaptation | Raw ScreenGui space avoids ClickGUI scaling; three columns expand across the phone and repaint with the live theme. |
| Editable mobile actions | Roblox adaptation | Long press opens one shared Size / Opacity / Remove panel; position and appearance persist per button. |
| Monocraft atlas (`monocraft-16.png`) | Roblox adaptation | OFL fallback. 7.54.1 does not change the 1.18.1 font baseline. |
| One ClickGui UIScale, user Scale 0.7–1.6 | exact | No 1080 / 1.35 formula. |
- **Menu blur (user mandate, capture review 2026-08-22):** Wurst draws
  nothing between the player and the game; this port now does — one
  BlurEffect under `PRODUCT.blurName`, enabled exactly while the GUI is
  open, destroyed at destruct. Reversed from the earlier ban at the
  user's explicit order after real captures.

## Code face and 16 px type (user order, 2026-08-22)

The interface face is the engine's `Code` vector font, permanently: the
Font pack row and the Monocraft/Minecraft picker entries are removed, and
the bitmap pipeline survives only as a suite-tested internal. Type sits on
the 16 px contract (Wurst's 8-logical at GUI scale 2) with 14 px secondary
text. Toasts moved off the scaled popup layer onto the shell so they land
inside the physical bottom-right corner. Boot sweeps both disk caches
against the shipped truth (bundle + asset manifest) so removed files never
outlive an update. All of it is the user's explicit order from real
captures, overriding bitmap-font purity.
