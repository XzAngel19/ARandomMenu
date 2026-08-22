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
| Window width 200 / packed settings | adaptación Roblox aprobable | Category 200; settings pack via `packedWidth`. |
| WurstLogo stripe y=12..34, alpha 0.5 | exact | Java fill y=6..17. |
| WurstLogo band packed to version | exact | `LOGO_WIDTH + 10 + (8 + #version × 12) + 4`. `+ 130` is gone. |
| WurstLogo.Background seeded `#FFFFFF` | exact | Java default, half-alpha stripe y=6..17. |
| AutoLocalize = false on helpers and roots | exact | Capture no longer translates Other/Text/Disabled/Zoom. |
| Titles centred on the full row | exact | Arrow does not move the centre. |
| RUN / KEY via `makeButton` (rounded in the shell) | **incorrecta** | Official action/combo/textbox are rectangles. |
| addSectionOption uppercase headings | **incorrecta** if DISPLAY/FILTERS/STYLE/FLIGHT | Official has no decorative chips. |
| Keybinds lists unbound modules | **incorrecta** | Official manager is bound keys + menu key. |
| Max height default 200 | exact | Stored 1000 from the old default must migrate. |
| Navigator as its own screen + keys | exact | RightCtrl = ClickGUI, RightShift = Navigator. |
| No TabGUI (default Disabled) | exact | Shipping none matches Disabled. |
| Pill as one-button Roblox launcher | adaptación Roblox aprobable | The 5% Roblox. |
| Monocraft atlas (`monocraft-16.png`) | adaptación Roblox aprobable | OFL fallback. 7.54.1 does not change the 1.18.1 font baseline. |
| One ClickGui UIScale, user Scale 0.7–1.6 | exact | No 1080 / 1.35 formula. |
