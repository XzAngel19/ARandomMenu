# UI v2 — Rail + Canvas

The menu's chrome is being rebuilt. This document is the target: what it looks
like, what survives from today's menu, what is deleted, and in what order the
work happens so the menu is usable at the end of every phase.

Mockups: `docs/design/mock-hero.jpg` (the layout and the accent),
`docs/design/mock-home.jpg` (the Home window), `docs/design/mock-themes.jpg`
(one window under four themes). `mock-canvas.jpg` is the earlier, colder
version — kept because the *structure* in it is still right and the comparison
is the whole point of this document.

## References, and what each one is for

**Wurst Client's ClickGUI** — the interaction model. Independent windows, one
per category, dragged where the player wants them. A title bar with a collapse
chevron. A feature is a row, and a row with settings expands *in place* rather
than opening a second panel. Nothing is modal, nothing is a page, the layout
belongs to the player and it persists.

**The Roblox in-game menu** — the surface language. A fixed left rail of icon +
label, translucent near-black panels, 10-12 px corners, thin dividers instead of
boxes, generous padding, soft hover. It is the part of Roblox already designed
to sit on top of a Roblox game.

**Matcha** — the part the first draft was missing. Matcha is dark and simple and
still does not look like a debug tool, and the reason is that it spends its one
accent colour *generously* and it surrounds the content with furniture: a
full-width status strip with FPS, ping and a clock; a build stamp along the
bottom; toasts in the corner; a list of what is currently enabled. None of that
is decoration for its own sake — every piece of it answers a question the player
actually has.

**Today's module row** — kept as-is. The card, the toggle, the keybind pill, the
favourite and the three-dot menu are the one part of the current menu that is
finished.

## The correction: alive, not decorated

The first draft was monochrome to the point of being furniture-grade. It read as
careful and it read as dead. The fix is not more colour everywhere; it is **one
saturated accent that carries meaning**, and enough chrome around the content
that the menu feels inhabited.

The accent is never decorative. It means *this is on, this is where you are,
this is what you are changing*:

| Accent appears | Because |
|---|---|
| The indicator square of an enabled module, filled, with a soft glow | On/off is the single most-read piece of state in the menu |
| The rail item you are looking at, as a bar down its left edge | Where you are |
| The fill of a slider, left of the knob | How much of the range you have taken |
| A keybind pill, outlined, only when a key is actually bound | Bound and unbound must differ at a glance |
| A hairline along the top edge of the focused window | Which window has focus, without a heavy border |
| The count badge on a rail category | How many modules are running in there |

Everything else stays near-black and grey. Two competing hues at once is the
thing that makes a menu look like a skin pack.

Semantic colours are not the accent and never become it. Health green, danger
red and MM2's role colours label game data; a theme that recolours "murderer"
is a theme that lies.

## The chrome

```
┌──────────────────────────────────────────────────────────────┐
│ ◈ ARANDOMMENU │ Player123          FPS 144 │ 28 MS │ 12:34 PM │  status strip
├────┬─────────────────────────────────────────────────────────┤
│ ▣  │  ┌─ Combat ───────── ⌃ ┐   ┌─ Visuals ─────────── ⌄ ┐    │
│ ▤  │  │ ■ Aimbot    [V] ⋯   │   │ ■ ESP          [X] ⋯   │    │
│ ▥ ③│  │ □ Triggerbot    ⋯   │   │ ⌄ □ Chams          ⋯   │    │
│ ▦  │  └─────────────────────┘   │     Transparency        │    │
│ ⚙  │                            │     ──────●─────        │    │
└────┴────────────────────────────┴─────────────────────────┴───┘
  Ready · v2.1 · Default profile        ┌ ! Game update detected ┐
```

- **Status strip**, full width, top: wordmark, your name, FPS, ping, clock, and
  the active game module. Numbers in the accent.
- **Rail**, left, fixed width, a launcher rather than a tab bar — clicking a
  category opens its window if closed and raises it if open. Badge = modules
  running in that category.
- **Canvas**: the windows, draggable, snapping to edges and to each other,
  remembering position, size, collapse, pin and z-order per profile.
- **Status line**, bottom left: build stamp, profile, ready state.
- **Toasts**, bottom right: keybind fired, config saved, game module loaded,
  something failed. Three seconds, stacked, dismissable.
- **Home window** (`mock-home.jpg`): a `ViewportFrame` with your own character
  in it, your ping/FPS/session time, the game, the profile, and the list of what
  is enabled. This is the window that makes the menu feel like a place instead
  of a settings dialog, and it is cheap — a clone of the character and a camera.

## Layout inside a window

A narrow window is one column of rows. A window the player has dragged wider
**flows its groups into two or three columns**, the way Matcha's tabs do, so a
card like Player ESP with forty controls stops being a mile of scrolling. The
column count follows the width; the player never picks it.

A row with settings expands in place: the chevron on the right, the rows below
pushed down, the module's own controls indented under a hairline that ties them
to their parent. The kernel's `Show` rules keep working inside an expanded row —
controls appear and disappear as conditions change and the window's height
follows. Player ESP has the deepest rule tree in the menu and is the test case.

## Motion

Everything moves, briefly, and nothing performs.

| | |
|---|---|
| Toggle | indicator scales 0.9 → 1 over 0.12 s, glow fades in |
| Row expand | height tween 0.16 s, content fades in behind it |
| Window open | scale 0.98 → 1 and fade, 0.15 s |
| Rail hover | the accent bar grows from its centre, 0.1 s |
| Toast | slides 12 px and fades, 0.18 s |

Nothing bounces, nothing spins, nothing lasts longer than 0.2 s. A "reduced
motion" switch in settings turns all of it off in one place for low-end phones.

## Theming

The default stays dark and restrained — that is a product decision. What changes
is that it becomes a **preset** rather than a palette compiled into the code.

Every colour comes from one token table:

```
surface  surfaceRaised  surfaceHover  surfacePressed  stroke  strokeSoft
text     textMuted      textDisabled
accent   accentGlow     accentText   accentSoft
positive negative       warning
backdrop (colour + transparency + blur)
```

plus the shape tokens a theme is also allowed to set — corner radius, surface
transparency, stroke thickness, font, accent glow on/off, gradient title bars.
A theme that can only change colours is a palette; the four windows in
`mock-themes.jpg` differ as much by shape as by hue.

Three things must be true and none of them is true today:

1. **No literal colour outside the theme.** 34 `Color3.` literals in the shell,
   19 in `Widgets`, 7 in `SettingsPage`, 6 in `FloatingWindows`, 5 in `Render`.
   Each one is a pixel no theme can reach. A gate contract will fail the build
   on a new one.
2. **The table must be reactive.** A widget reads `Theme.Surface` once at build
   time and copies it into a property, so changing the table repaints nothing.
   `Theme:Bind(instance, "BackgroundColor3", "surface")` registers it so a
   preset switch repaints live, with a tween.
3. **One token set.** There are two overlapping ones today (`Surface` and
   `DefaultSurface`, `Text` and `DefaultText`) left from a GUI style that no
   longer exists.

Presets: **Monochrome** (white accent), **Vape**, **Matcha** (pink), **Wurst**
(magenta, gradient title bars, glow on), **Mint**, **Midnight** (cyan),
**Ember** (amber), and **Custom** with every token exposed and an export/import
string so a theme can be pasted to a friend. Import applies into a copy,
validates text-against-surface contrast, and only then swaps — an import that
leaves half the tokens switched is worse than no import.

## Mobile

Six draggable windows do not fit on a phone. The window manager keeps a **Sheet**
mode: the rail collapses to icons, one window at a time, full width, dragging
the title bar dismisses instead of moves. The status strip keeps FPS and ping
and drops the rest. Same rows, same theme, different placement policy.
`MobileActions` and the launcher button are untouched.

## Phases

Each phase ends with a menu that works.

| # | What | Owner |
|---|------|-------|
| 0 | One token set, `Theme:Bind`, every literal colour removed, gate contract. No visible change. | A |
| 1 | `WindowManager`: today's main window becomes window #1 — draggable, collapsible, snapping, persisted. | A |
| 2 | Rail, status strip, status line, toasts. The tab strip dies. | A |
| 3 | Category windows, rows that expand in place, multi-column flow, Home window. | A |
| 4 | Presets, Themes page, custom colours, export/import, motion pass. | A |

## What is deleted

`createTab` (431 lines), `centerMain` (341) and the tab strip. The four overlays
in `FloatingWindows` become ordinary managed windows and stop carrying their own
copies of drag, clamp, close and persistence. Expect the shell to lose 600-900
lines and `FloatingWindows` most of its first 600. If those numbers do not move,
the migration did not happen — something got wrapped instead of replaced.
