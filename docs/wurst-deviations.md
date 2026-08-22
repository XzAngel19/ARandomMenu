# A's deliberate differences vs official Wurst 7

Classified against Wurst7 `4a22e53`, `ref-wurst-719.jpg`,
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
| Occupied windows only (empty Blocks/Chat/Items still shown) | **incorrecta** | Official does not open an empty category as a giant window. Hide waits on A. |
| Settings inline in the category row | **incorrecta** | Official opens `<Feature> Settings`. Suite waits. |
| Settings windows stacked on first run | **incorrecta** until positions stay distinct | SettingsPage offsets Y; gate holds that. |
| Window width 200 / packed settings | adaptación Roblox aprobable | Category 200; settings pack via `packedWidth`. |
| WurstLogo stripe y=12..34, alpha 0.5 | exact | Java fill y=6..17. |
| WurstLogo band `LOGO_WIDTH + 130` | **incorrecta** | Must pack to logo + gap + version. |
| WurstLogo.Background seeded `#000000` | **incorrecta** | Java default `#FFFFFF`. |
| AutoLocalize left at Roblox default | **incorrecta** | Capture translated Other/Text/Disabled/Zoom. |
| Titles left-aligned from x=8 | **incorrecta** | Official names are centred; arrow must not shift the centre. |
| RUN / KEY via `makeButton` (rounded in the shell) | **incorrecta** | Official action/combo/textbox are rectangles. |
| addSectionOption uppercase headings | **incorrecta** if DISPLAY/FILTERS/STYLE/FLIGHT | Official has no decorative chips. |
| Keybinds lists unbound modules | **incorrecta** | Official manager is bound keys + menu key. |
| Max height default 200 | exact | Stored 1000 from the old default must migrate. |
| Navigator as its own screen + keys | exact | RightCtrl = ClickGUI, RightShift = Navigator. |
| No TabGUI (default Disabled) | exact | Shipping none matches Disabled. |
| Pill as one-button Roblox launcher | adaptación Roblox aprobable | The 5% Roblox. |
| Monocraft FontFace | adaptación Roblox aprobable | Not MC.font bitmap. Do not claim font exacta. |
| One ClickGui UIScale, user Scale 0.7–1.6 | exact | No 1080 / 1.35 formula. |
