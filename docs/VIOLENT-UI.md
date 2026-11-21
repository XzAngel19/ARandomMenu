# Violent — standalone, UI-only reference replica

## Run

Copy **all of `src/ViolentStandalone.luau`** into a Luau-capable executor attached
to a live Roblox client and execute it. The file is self-contained: it doesn't
load the existing Wurst menu, require ModuleScripts, fetch code, or need a Studio
hierarchy. No build step is needed to run the committed standalone file.

- Drag either window by its title/header.
- **RightShift** hides/shows both windows (ignored while typing).
- Click a checkbox row to toggle its local UI state.
- Edit a numeric value directly, or drag horizontally immediately left of its
  value. Selected numeric rows also accept Left/Right to adjust.
- Click a color row to open an RGB editor; Apply updates only the UI swatch.
- Up/Down select rows; Enter/Space activate the selected row.
- The footer chevrons scroll the small reference crop up/down. Mouse wheel and
  touch scrolling work too. No unseen feature list is invented.
- Re-executing replaces the previous copy in the chosen GUI container and
  disconnects its input listeners.

An optional API is returned by executing the chunk: `Gui`, `State`, and
`Destroy()`. `State` is presentation-only. For example, when running the file as
an executor chunk that retains its return value, calling `Destroy()` on that
returned table removes the GUI and its listeners.

## What is reproduced

The layout uses the attachment's 614 × 550 coordinate space: a 305-pixel-wide
menu at (20, 27) and a separate 272 × 313 preview at (342, 26). It preserves the
hot-pink header, outlined title, `VISUALS / HUD`, `29/51`, all ten labeled controls,
checked defaults, numeric defaults `1` and `2.5`, three color swatches, section
headings, pink selected outline-color row, `Release, v1.4`, footer chevrons,
status text, and the clipped detail below Text. The preview includes the exact
note and UI-only silhouette, skeleton, bounding rectangle, glow, and health bar.
It does not draw anything on players or objects.

The attachment contains no navigation sidebar, extra tabs, visible dropdown,
or exposed slider track; none are added to the initial view. `29/51` is the
reference's static indicator, not a claim that 51 controls were provided.
Only the visible crop is recreated. The partially visible shape under Text is
decorative rather than an invented unlabeled feature.

The game world stays visible behind the translucent panels. The sky/baseplate
in the attachment is not painted onto the screen. The canvas scales down to fit
smaller screens, retaining the original size on larger ones. Windows remain
independently draggable. Roblox's built-in condensed bold face approximates
the reference's custom display lettering; no external image/font uploads are
required. The silhouette is a static 2D approximation, not a live avatar render.

## Modules

| File | Responsibility |
| --- | --- |
| `src/violent/modules/Theme.luau` | Palette, fonts, stable GUI identity |
| `src/violent/modules/Core.luau` | Instance helpers, safe mounting, dragging, lifecycle |
| `src/violent/modules/Controls.luau` | Sections, rows, checkboxes, numeric editors, color popup |
| `src/violent/modules/Window.luau` | Reference layout, category strip, keyboard navigation, footer |
| `src/violent/modules/Preview.luau` | Decorative 2D preview window |
| `src/violent/modules/Features.luau` | Ten deliberately empty feature callbacks |
| `src/violent/Main.luau` | Assembly, responsive scale, returned UI handle |
| `src/ViolentStandalone.luau` | Generated executable, with all modules embedded |

The bundler wraps modules as local factory functions and resolves them using
an in-file `import` function. There are no filesystem dependencies at runtime.
Edit the source modules, not the generated executable.

Every feature callback is an empty function. Controls change only local GUI
state and call their corresponding empty hook. There is no gameplay,
automation, combat, movement, ESP, skeleton, highlight, health tracking,
safe-mode, remote invocation, or existing Wurst integration. The initial
checked boxes are visual defaults only. The static preview intentionally does
not track control changes or any live character.

## Parenting and cleanup

Mounting tries `gethui()` if defined, then `CoreGui`, then the local player's
`PlayerGui`. Both lookup and parenting failures are handled independently.
The script doesn't change thread identity, hook metamethods, or assume
executor-specific protection APIs. Normal Roblox client GUI permissions are
sufficient for the PlayerGui fallback. If all candidates fail, it reports a
clear error instead of silently leaving an unparented GUI.

Only previous GUIs with this menu's exact name and owner attribute in the
chosen container are replaced. Destroying the GUI disconnects all tracked
service listeners; popup-only listeners die with their UI instances. No
per-frame loops or background tasks are used.

## Build and check

From the repository root:

```sh
python3 tools/build_violent.py
python3 tools/build_violent.py --check
bash tools/luau/setup.sh
tools/luau/bin/luau-compile src/ViolentStandalone.luau >/dev/null
python3 tools/test_violent_ui.py
```

The tests execute the actual bundled code using mocked Roblox UI services.
They cover the default tree/state, selection, toggling, numeric validation and
dragging, keyboard input, RGB popup/application, scrolling, scaling, dragging,
gethui/CoreGui/PlayerGui fallbacks, denied parenting, repeat execution, and
listener cleanup. They also check the feature hooks remain empty and reject
unexpected non-UI instance classes or gameplay/dependency APIs.

Validation is compilation plus mocked execution, **not** a live-client or
pixel-rendering test. Roblox font rendering, executor permissions, and the
final appearance must still be verified in the target client. The repository's
existing Wurst source/bundle is untouched.
