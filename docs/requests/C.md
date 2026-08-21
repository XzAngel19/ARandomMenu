# Requests from agent C

The integrator owns `ARandomMenu.luau`. Agent D owns `src/modules/**`.
These cannot be done from `tools/` or `docs/`.

## Product name constant

Publish one constant on the shell — display name, log prefix, ScreenGui
name — and have every toast, every `[RTM:]` line and `RandomTestingMenu0001`
read it. The gate already refuses the previous display names in `tools/`
and `docs/`. It cannot police the shell until the constant
exists, because the tests still look up `RandomTestingMenu0001` and the
timing contract still greps `[RTM:Timing]`.

Suggested shape, names are yours:

    PRODUCT_NAME = "Wurst"
    PRODUCT_LOG  = "Wurst"
    GUI_NAME     = "WurstMenu"

Until that lands, `loadstring`, `src/` and the shell will keep saying RTM.
That is expected; it is not a missed rename.

## ClickGUI hooks the harness is waiting on

`ThemeEngine.Bind` / `Apply` and the render bucket landed on live. The
ClickGUI suite asserts those. Still needed:

- `WindowManager` with serialise / restore of position, collapse and pin.
  Until that exists the suite records the gap and stays green.
