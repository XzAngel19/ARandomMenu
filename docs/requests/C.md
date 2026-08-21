# Requests from agent C

The integrator owns `ARandomMenu.luau`. Agent D owns `src/modules/**` and
`src/games/**`. These cannot be done from `tools/` or `docs/`.

## Product name leftovers

`PRODUCT` exists on the shell (`name` / `logPrefix` = Wurst) and is now
published on the test host and into `injectGame`, so a game module can read
`PRODUCT.storageFolder` instead of retyping the folder. The name gate still
only scans `tools/`, `docs/` and `README.md`. It cannot be extended to
`ARandomMenu.luau` and `src/` until the previous display names leave those
files — a red gate cannot be pushed.

Do **not** change `guiName`, `blurName` or `storageFolder`. Those three are
not branding: the first two are instance names a game can enumerate, and the
third is the on-disk folder that already holds every existing player's
configs. Renaming it would silently orphan them.

Integrator (shell):

- mobile launcher fallback `Text = "RTM"` (`ARandomMenu.luau`, around the
  MobileMenuButton)
- `print("[RTM] build loader-v3")` (the build stamp that used to live on
  the intro)

Integrator (libraries): the previous display name is still a title fallback
and a warn prefix in

- `src/gui/Current/gui.lua`
- `src/library/Cards.luau`
- `src/library/FloatingWindows.luau`
- `src/library/SettingsPage.luau`
- `src/library/Widgets.luau`

Agent D (unblocked by PRODUCT on the mock):

- `src/games/MM2.luau` still hard-codes `RandomTestingMenu0001` as the
  telemetry folder (`OUTPUT_ROOT`)
- `src/modules/Combat/ProjectileCalibration.luau` does the same
- `[RTM:…]` log prefixes in those two files

## Wordmark asset and Wurst chrome sizes

Furniture.luau already calls `applyAssetImage("wurstLogo", ...)`. The
shell's AssetManager has no `wurstLogo` key — it still has `brandLogo` →
`menu-logo.jpg`. Add:

```
wurstLogo = {
    url = ... "assets/wurst/wurst_128.png",
    fileName = "wurst-128.png",
    assetType = "image/png",
}
```

Do not point the wordmark at `menu-logo.jpg`.

Wurst's own logo blit is **72×18** at (0, 3), chip fill y=6–17. Furniture
currently draws 87×22. Those Wurst numbers are in `spec.json`
`wurst.chrome`; the screenshot measurements that confirm them are in
`wurst.screenshot`. Title bar is **13**, feature row is **11**, HackList
advances **9** — not the prototype's 22/22/13.

The hail layer is gone. `tools/validate.sh` ("No hail over the blur")
and `tools/test/suites/furniture.luau` fail if a `BlurHail` / `HailLayer`
frame, `HAIL_STONE_COUNT` or `HAIL_COLOR` comes back. Do not put a
decoration on top of the blur.

## Furniture the suites are waiting on

`tools/test/suites/furniture.luau` is written. Until these exist it
records the gap and stays green.

- **Wordmark.** Resolve `assets/wurst/wurst_128.png` through the
  `getcustomasset` path. An executor without that function keeps the
  text fallback (`PRODUCT.name`). The shell still loads `brandLogo` →
  `menu-logo.jpg` onto the mobile launcher; that is the old product art.
- **HackList.** Exactly the enabled cards. `card.status` non-nil prints
  `Name [status]`. `nil` prints the bare name. `card:SetStatus` already
  exists.
- **Pill.** Visible with the GUI closed. The mobile launcher is not the
  pill: it is phone-only and hides when the menu is open.
- **Tooltip.** 400 ms, not before. The shell still has
  `task.delay(0.42)` behind `COMPACT_FEATURE_CARDS`, which currently
  skips tooltips entirely.

## ClickGui UIScale is ungrounded

The prototype does **not** declare a reference resolution or an auto
factor. Scale is a user slider: default **1**, min **0.7**, max **1.6**,
two decimals (`numeric(body,"Scale",UI.scale,.7,1.6,2,…)`). Those numbers
are now in `spec.json` `scaleControl`. `referenceHeight` and `autoFactor`
are explicitly null.

ClickGui currently does `(viewport.Y / 1080) * 1.35` clamped to
`SCALE_MINIMUM=0.85` / `SCALE_MAXIMUM=1.6`. The gate prints that as
`ungrounded` and will not copy 1080 or 1.35 into the spec. Delete
`REFERENCE_HEIGHT` and the `* 1.35`. The Scale slider, when UI Settings
lands, is the counterpart of `ThemeEngine.shape.scale` (already 1).

## ClickGUI hooks the harness is waiting on

`ThemeEngine.Bind` / `Apply` and the render bucket landed on live. The
ClickGUI suite asserts those. Still needed:

- `WindowManager` with serialise / restore of position, collapse and pin.
  Until that exists the suite records the gap and stays green.

## UI Settings must take Wurst's defaults, not the prototype's

`docs/wurst-features.md` and `spec.json` `wurst.settings` now hold the
official defaults. Three colours already match (`Theme.surface` `#404040`,
`Theme.accent` `#101010`, `Theme.text` `#F0F0F0`). Three numbers do not:

| Setting | Wurst | What we have today |
|---|---|---|
| Opacity | `0.5` | `ThemeEngine.shape.opacity` **0.86** (prototype) |
| Tooltip opacity | `0.75` | `ThemeEngine.shape.tooltipOpacity` **0.95** |
| Max height | `200` | prototype `--max-h` **340**; `ClickGui.WINDOW_MAX_HEIGHT` **300** |

The shape tokens stay the layout spec. The UI Settings window has to ship
Wurst's slider defaults (`OPACITY`, `TOOLTIP_OPACITY`, `MAX_HEIGHT`,
`MAX_SETTINGS_HEIGHT`). A named constant with the prototype number will
fail the gate.

**GlobalToggle** and **Isolate windows** are not in official Wurst 7. Do
not add them.

## Parity gate

`docs/design/prototype/spec.json` is generated from the prototype (pixels)
and from `tools/wurst_features.py` (Wurst setting defaults). The gate
already checks `ThemeEngine.shape` against the prototype and `Theme.surface`
/ `accent` / `text` against Wurst.

Owed — named constants in `Widgets.luau`, so the remaining prototype numbers
have a counterpart the gate can read. Until they exist the step stays green
and prints them as owed; once a name appears, a wrong value fails and names
both sides. C cannot add them (`src/` is not its lane).

| Constant | Prototype |
|---|---|
| `TITLE_HEIGHT` | 22 |
| `WINDOW_GAP` | 2 |
| `SLIDER_BAR_HEIGHT` | 5 |
| `SLIDER_KNOB_WIDTH` | 7 |
| `SLIDER_KNOB_HEIGHT` | 11 |
| `TITLE_FONT_SIZE` | 11.5 |
| `LABEL_FONT_SIZE` | 11.5 |
| `TOOLTIP_DELAY_MS` | 400 |
| `TRANSITION_FAST` | 0.1 |
| `TRANSITION_SLOW` | 0.18 |
