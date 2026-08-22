# A's deliberate differences vs official Wurst 7

Classified against Wurst7 `4a22e53` and `ref-wurst-719.jpg`.
Logical units stay GUI-scale-1. Prototype `titleHeight` 26 is 13 × 2,
not a 1080p invention.

| Difference | Class | Why |
|---|---|---|
| Title bar 26 px (13 logical × GUI scale 2) | exact | Same ratio; drawn at scale 2. spec.wurst.chrome stays 13. |
| Row 22 px (11 logical × 2) | exact | FeatureButton.getDefaultHeight is 11. |
| Window width 200, packed-to-content in Java | adaptación Roblox aprobable | Roblox text is wider; 160 truncated names. |
| First-run wrap at 4 columns | adaptación Roblox aprobable | Wurst wraps at the screen edge; seven 200 px windows became a strip the user rejected. |
| Corner radius 0 | exact | Wurst windows are rectangles. |
| Body opacity 0.5 at birth | exact | ClickGUI Opacity default. |
| Category windows: pin + collapse, no close | exact | Window.java. |
| HackList Position Left | exact | Official default. Phone still flips (UI-V2). |
| Logo 142×36 (72×18 × 2, aspect of wurst_128) | exact | Logical 72×18 stays in spec.wurst.chrome. |
| Version string `0.1 Beta` | adaptación Roblox aprobable | We are not Wurst 7.19 / MC 1.18.1. |
| WurstLogo only while ClickGUI is open | adaptación Roblox aprobable | Brief asked for it on the GUI screen; official Visibility is Always in-game. |
| WurstLogo.Background seeded `#000000`, chip Transparency 1 until stored | **incorrecta** | Java always `fill(0, 6, width, 17)` with the setting, default `#FFFFFF` at half alpha. Restore `#FFFFFF` and 50% alpha. The magenta/cyan in screenshots is a user palette. |
| Version text in Theme.accent, not WurstLogo.Text `#000000` | **incorrecta** until the chip is back | Black on no chip is invisible; the official pair is white chip + black text. |
| Navigator on the ClickGUI, not its own screen | adaptación Roblox aprobable | Recorded in Furniture.luau. |
| Navigator not auto-focused | adaptación Roblox aprobable | A stolen keyboard walks the character. |
| RightShift opens ClickGUI (which shows Navigator), not Navigator alone | adaptación Roblox aprobable | Official RightShift is Navigator, RightCtrl is ClickGUI. One menu key on Roblox. |
| No Space / arrows / Escape-as-Navigator-close | **incorrecta** if we claim Navigator parity | Official Navigator keys. Requested of A. |
| No TabGUI (default Disabled) | exact | Official default is Disabled; shipping none matches the default. |
| Categories Visuals / Protection / Utility / Spoof | **incorrecta** | Official windows are Combat, Render, Blocks, Movement, Chat, Fun, Items, Other. Remap is in docs/requests/C.md. |
| Pill as one-button Roblox launcher | adaptación Roblox aprobable | The 5% Roblox. OFF is gone. |
| Monocraft as boot default | adaptación Roblox aprobable | Official font is MC.font bitmap; Monocraft is the vendored stand-in. |
| Grid gap 10 (5 logical × 2) | exact | Wurst first-run gap is 5. |
