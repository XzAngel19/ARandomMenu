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

## ClickGUI hooks the harness is waiting on

`ThemeEngine.Bind` / `Apply` and the render bucket landed on live. The
ClickGUI suite asserts those. Still needed:

- `WindowManager` with serialise / restore of position, collapse and pin.
  Until that exists the suite records the gap and stays green.

## Parity gate

`docs/design/prototype/spec.json` is generated from the prototype. The gate
already checks `ThemeEngine.shape` against it (7 tokens, currently matching).

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
