# UI v2 — Rail + Canvas

The menu's chrome is being rebuilt. This document is the target: what it looks
like, what survives from today's menu, what is deleted, and in what order the
work happens so the menu is usable at the end of every phase.

Mockups: `docs/design/mock-canvas.jpg` (layout), `docs/design/mock-themes.jpg`
(the same window under four themes).

## References, and what we take from each

**Wurst Client's ClickGUI** — the interaction model. Independent windows, one
per category, that the player drags where they want. A window has a title bar
with a collapse chevron; a feature is a row; a row with settings expands *in
place* instead of opening a second panel. Nothing is modal, nothing is a page.
Layout is the player's, and it persists.

**The Roblox in-game menu (2023 redesign)** — the surface language. A
persistent left rail of icon + label, translucent near-black panels, 10-12 px
corners, generous padding, thin dividers instead of boxes, one accent, soft
hover. It is the part of Roblox that already looks like it belongs on top of a
Roblox game, which is exactly where this menu lives.

**Today's module row** — kept as-is. The card colour, the toggle, the keybind
pill, the favourite star and the three-dot menu are the one part of the current
menu that is finished. Everything else is scaffolding around them.

## The concept

Two layers, both drawn by the menu, both visible at once.

```
┌────┬──────────────────────────────────────────────────────┐
│    │              ⌜ FPS 144 · 28 ms · MM2 ⌝                │
│ ▣  │   ┌─ Combat ────────── ⌄ ⋯ ┐   ┌─ Movement ── ⌄ ⋯ ┐  │
│ ▤  │   │ ▢ Kill Aura   [R] ⋯     │   │ ▢ Speed    [F] ⋯ │  │
│ ▥  │   │ ▢ Aim Assist      ⋯     │   │ ▣ Fly          ⋯ │  │
│ ▦  │   └─────────────────────────┘   │ ▢ Noclip       ⋯ │  │
│ ▧  │   ┌─ Visuals ───────── ⌄ ⋯ ┐   └──────────────────┘  │
│ ▨  │   │ ▣ Player ESP        ⌃   │                        │
│ ⚙  │   │   ├ Boxes    ─────○──   │                        │
│    │   │   └ Chams    Overlay ⌄  │                        │
└────┴──────────────────────────────────────────────────────┘
  rail                     canvas
```

**The rail** is not a tab bar. Tabs swap one page for another; the rail is a
*launcher*. Clicking `Movement` opens that window if it is closed and brings it
forward if it is open. The rail also carries Home (session/status), Search,
Themes and Settings. It is always on the same side, it never scrolls, and its
width does not change — it is the one fixed thing on screen.

**The canvas** is everything else: the backdrop (optional blur), and the
windows floating on it. A window remembers its position, size, collapsed state,
pin state and z-order, per config profile. Windows snap to the viewport edges
and to each other. Clicking one raises it.

**A row** is today's card. Clicking the row toggles the module. Clicking the
chevron expands its settings inline, pushing the rows below it down — no second
window, no drill-down. Right-click opens the three-dot menu (keybind, favourite,
reset, "pop out into its own window").

**Search** (Wurst's Navigator) — a key opens a fuzzy list of every module *and
every option*, `Enter` toggles, `Tab` jumps to the row in its window. With 38
modules and roughly 400 options this stops being a nicety.

## Theming

The rule the user set stands — the *default* is monochrome, near-black, one
white accent, no blue pills. What changes is that monochrome becomes a
**preset** rather than a constraint compiled into the code.

Every colour in the menu comes from one token table:

```
surface  surfaceRaised  surfaceHover  surfacePressed  stroke  strokeSoft
text     textMuted      textDisabled
accent   accentText     accentSoft
positive negative       warning
backdrop (colour + transparency + blur)
```

plus non-colour tokens that a theme is also allowed to set: corner radius,
surface transparency, stroke thickness, font family, accent glow on/off,
gradient title bars on/off.

Three things have to be true for this to work, and none of them is true today:

1. **No literal colour outside the theme.** There are 34 `Color3.` literals in
   the shell, 19 in `Widgets`, 7 in `SettingsPage`, 6 in `FloatingWindows`,
   5 in `Render`. Each is a pixel a theme cannot reach. A gate contract will
   fail the build on a new one.
2. **The table has to be reactive.** Today a widget reads `Theme.Surface` once,
   at build time, and copies it into a property. Changing the table afterwards
   repaints nothing. `Theme:Bind(instance, "BackgroundColor3", "surface")`
   registers the instance so a preset switch repaints live, with a tween.
3. **The token set has to be one set.** Today there are two overlapping ones
   (`Surface` and `DefaultSurface`, `Text` and `DefaultText`, ...) left over
   from a second GUI style that no longer exists.

Presets shipped: **Monochrome** (default), **Vape** (near-black, white accent),
**Wurst** (dark, magenta accent, gradient title bars), **Midnight** (navy,
cyan), **Ember** (warm charcoal, amber), and **Custom** — every token exposed
to the colour picker, with an export/import string so a theme can be shared as
text.

Semantic colours (health green, danger red, MM2 role colours) are *not* theme
tokens. They label game data, not chrome, and a theme that recolours "murderer"
is a theme that lies.

## Mobile

Six draggable windows do not fit on a phone. The window manager keeps a
**Sheet** layout mode: the rail collapses to icons, one window is visible at a
time, full-width, and dragging a title bar dismisses it instead of moving it.
Same data, same rows, same theme — only the manager's placement policy differs.
`MobileActions` and the launcher button are untouched.

## Phases

Each phase ends with a menu that works. No phase leaves the menu in pieces.

| # | What | Owner |
|---|------|-------|
| 0 | One token set, `Theme:Bind`, every literal colour removed, gate contract. No visible change. | A |
| 1 | `WindowManager`: the existing main window becomes window #1 — draggable, collapsible, persisted, snapping. | A |
| 2 | Category windows and the rail replace the tab strip. Rows expand inline. | E |
| 3 | Presets, the Themes page, custom colours, export/import. | D |
| 4 | Search, scale slider, snapping polish, animation pass. | E + D |

Phases 0 and 1 are the interface everyone else builds on and are done first,
by one person, before D and E start.

## What is deleted

`createTab` (431 lines), `centerMain` (341) and the tab strip in the shell — the
rail and the window manager replace them. The four overlay windows in
`FloatingWindows` become ordinary managed windows and stop carrying their own
copy of drag, clamp and close logic. Expect the shell to lose 600-900 lines and
`FloatingWindows` to lose most of its first 600.
