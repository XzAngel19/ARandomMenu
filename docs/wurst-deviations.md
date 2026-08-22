# A's deliberate differences vs official Wurst 7

Classified against Wurst7 `4a22e53`, `ref-wurst-719.jpg` and
`ref-wurst-settings.jpg`. Logical units stay GUI-scale-1. Prototype
`titleHeight` 26 is 13 × 2, not a 1080p invention.

| Difference | Class | Why |
|---|---|---|
| Title bar 26 px (13 logical × GUI scale 2) | exact | Same ratio; drawn at scale 2. spec.wurst.chrome stays 13. |
| Row 22 px (11 logical × 2) | exact | FeatureButton.getDefaultHeight is 11. |
| Window width 200 / 214, packed-to-content in Java | adaptación Roblox aprobable | Roblox text is wider; 160 truncated names. Official pack is still owed. |
| First-run wrap at the viewport edge | exact | A dropped the 4-column cap; eight windows wrap where they fit. |
| Corner radius 0 | exact | Wurst windows are rectangles. |
| Body opacity 0.5 at birth | exact | ClickGUI Opacity default. |
| Category windows: pin + collapse, no close | exact | Window.java. |
| Official eight categories, aliases for old names | exact | Combat, Render, Blocks, Movement, Chat, Fun, Items, Other. |
| HackList Position Left | exact | Official default. Phone still flips (UI-V2). |
| Logo 142×36 (72×18 × 2, aspect of wurst_128) | exact | Logical 72×18 stays in spec.wurst.chrome. |
| Version string `0.1 Beta` | adaptación Roblox aprobable | We are not Wurst 7.19 / MC 1.18.1. |
| WurstLogo only while ClickGUI is open | adaptación Roblox aprobable | Brief asked for it on the GUI screen; official Visibility is Always in-game. |
| WurstLogo stripe y=12..34 at scale 2, alpha 0.5 | exact | Java fill y=6..17. |
| WurstLogo.Background seeded `#000000` | **incorrecta** | Java default is `#FFFFFF` at half alpha. Stripe is right; seed is not. |
| Navigator as its own screen | exact | A landed Open/Close independent of ClickGUI. |
| Navigator keys (Enter, Space, arrows, Escape, Backspace) | exact | Official Navigator keys. |
| RightCtrl opens ClickGUI, RightShift opens Navigator | exact | The mock now carries both keys. Navigator still yields if a stored menu key is RightShift. |
| No TabGUI (default Disabled) | exact | Official default is Disabled; shipping none matches the default. |
| Slider rail 5 / knob 7×11 | **incorrecta** | Java rail 3, knob 8×8 (6 / 16×16 at scale 2). Gate accepts either pair until A switches. |
| Checkbox checkmark `✓` | **incorrecta** | Official box is fill-only. |
| Shortcut chevron `›` | **incorrecta** | Official FeatureButtons have no chevron. |
| Pill as one-button Roblox launcher | adaptación Roblox aprobable | The 5% Roblox. OFF is gone. |
| Monocraft as boot default | adaptación Roblox aprobable | Official font is MC.font bitmap; Monocraft is the vendored stand-in. |
| Grid gap 10 (5 logical × 2) | exact | Wurst first-run gap is 5. |
| Capture palette via ThemeEngine.Set | exact | Defaults stay #404040 / #101010 / #F0F0F0; the magenta/cyan in screenshots is a user palette (or RainbowUI on titles). |
