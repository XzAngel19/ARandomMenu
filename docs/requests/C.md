# Requests from agent C

The integrator owns `ARandomMenu.luau`. Agent D owns `src/modules/**` and
`src/games/**`. These cannot be done from `tools/` or `docs/`.

## Rows are FeatureButtons, not cards

Wurst's row is a name and, when the feature has settings, an 11 px
arrow. Cards.luau still draws a favourite star, a hamburger on every
row, and a keybind box even when the key is empty. Drop the leftovers.
A no-options row must not reserve space for an arrow.

The triangle that remains has to open that feature's settings window
(already the panel today). Enabled rows paint `Theme.enabled`, not the
accent. No `UICorner` on a row.

## Title bar

Category windows: collapse + pin, no close. Settings windows add close.
Each button is 11 GUI-scale-1 px of a 13 px bar. Prototype layout stays
`TITLE_HEIGHT` 22 until A chooses to switch the layout spec to Wurst's
13 — do not invent a 26/22-at-1080 rule.

## WurstLogo background

`WURSTLOGO_BACKGROUND` is seeded `#000000`. Official Wurst always fills
the chip (`WurstLogo.java` `fill(0, 6, width, 17)`) with the setting,
default `#FFFFFF` at half alpha. The magenta/cyan in the screenshots is
a user palette, not a reason to hide the chip. Restore the constant to
`#FFFFFF` and draw it at 50% alpha. The gate prints the mismatch as
ungrounded and does not fail.

## Launcher

The pill still has an `OFF` panic glyph. Wurst's HUD has no such
control. Panic belongs on a keybind, not on the Roblox launcher.

## Font

ClickGUI, settings, tooltips, HackList and KeybindList still resolve
through `TITLE_FONT` / `CONTROL_FONT` (BuilderSans) and RobotoMono on
the leftover stats label. Point those surfaces at `minecraftFont`
(Monocraft) or one central fallback. Do not scatter BuilderSans.

## Official category windows

Combat / Render / Blocks / Movement / Chat / Fun / Items / Other.
We open Combat / Movement / Visuals / Protection / Utility / Spoof.
The map is `docs/wurst-categories.md`. Do not open empty Wurst windows.

## Navigator

Not a window under the logo. Navigator is a full-screen GUI. TabGUI is
the left-edge HUD, default Disabled. The version string (`0.1 Beta`)
sits next to the sausage.

## Product name leftovers

Do **not** change `guiName`, `blurName` or `storageFolder`.

- mobile launcher fallback `Text = "RTM"`
- `print("[RTM] build loader-v3")`
- previous display names in Cards / FloatingWindows / SettingsPage / Widgets
- MM2 and ProjectileCalibration still hard-code `RandomTestingMenu0001`

## Wordmark

Landed: `wurstLogo` → `assets/wurst/wurst_128.png`. Do not point it at
`menu-logo.jpg` or `brandLogo`. The phone circle may keep `brandLogo`
until that circle goes away.

Logo blit is **72×18**. Furniture draws 87×22 (or 118×30 after A's
later pass — check the constant). Wurst numbers stay in
`spec.json` `wurst.chrome`.
