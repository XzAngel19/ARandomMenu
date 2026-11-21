# VIOLENT — ESP Visuals / HUD menu

A standalone, client-sided Luau GUI that replicates the **VIOLENT** ESP menu
from the reference screenshot: a hot-pink branded main window
(**VISUALS / HUD**) plus a separate **ESP PREVIEW** window with a blocky
avatar, skeleton overlay and rainbow health bar.

Built for **script executors in a live Roblox client** — not Roblox Studio.
No Studio-only assumptions; the `ScreenGui` is parented with a safe fallback
chain (`gethui()` → `CoreGui` → `PlayerGui`, with `syn.protect_gui` when
available) and re-injection destroys the previous instance first.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/76bb1400-arandommenu/src/gui/Violent/Violent.lua"))()
```

After this branch merges into `main`, use the `main` URL instead:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/main/src/gui/Violent/Violent.lua"))()
```

- **Toggle menu:** `RightShift`
- **Drag:** either window by its header
- **Sliders:** drag the value (e.g. `1`, `2.5`) left/right
- **Colors:** click a swatch to open the palette
- **Version:** click `Release, v1.4` to open the dropdown

## What is replicated

| Element | Detail |
|---|---|
| Main header | Hot-pink bar, `VIOLENT` in chunky display type with black outline |
| Meta row | `VISUALS / HUD` · `29/51` |
| Skeleton | `Enable Skeleton` toggle, `Skeleton Thickness` slider (`1`), `Skeleton Color` swatch (white) |
| Highlights | `Hightlight ESP` / `Hightlight Fill` / `Hightlight Outline` toggles, Fill (magenta) + Outline (pink) color swatches |
| Health Bar | `Show Health Bar` toggle, `Healt Bar Size` slider (`2.5`) |
| Text | `Release, v1.4` dropdown with chevron |
| Tooltip bar | Bottom strip with pink top border, e.g. `Set color to: Hightlight Outline Color` |
| Selected row | `Hightlight Outline Color` highlighted pink with dark text (click any row to select it) |
| Preview window | `ESP PREVIEW` + disclaimer text, dark-purple viewport with magenta border/glow, lavender avatar, white skeleton lines, rainbow health bar |

Labels reproduce the screenshot exactly, including its spellings
(`Hightlight …`, `Healt Bar Size`, `doesnt` / `arent`).

## Module map (single self-contained file)

`Violent.lua` is one copy-paste-ready file, organized into clean modules:

- **Util** — instance factory, safe parenting fallback, window dragging
- **Theme** — colors / fonts / sizes (single source of truth)
- **State** — settings table + **empty stub callbacks** (`onToggle`, `onSlider`,
  `onColor`, `onVersion`, `onTab`)
- **Window** — main window + preview window shells (headers, borders)
- **Controls** — toggle / slider / color / dropdown / section / meta-row components
- **Preview** — ESP preview viewport (avatar, skeleton, health bar) + empty `Sync()` hook
- **Navigation** — `VISUALS / HUD` header + tab stub (the screenshot shows a
  single page; add tabs here later)
- **Main** — assembly, control stacking, `RightShift` toggle key

## Stubs

All feature callbacks in `State.Callbacks` are intentionally **empty** — this
builds the full UI only, with no gameplay, farming, combat, movement or
automation logic. Settings are exposed at runtime via `getgenv().Violent`
(`Settings`, `Callbacks`, `ScreenGui`) so features can be wired in later.
