# UI v2 — the ClickGUI

The menu's chrome is being rebuilt. This document is the target.

**Wurst is the reference.** Not "inspired by" — the interaction model, the
density and the customisation surface are copied deliberately, then dressed in
our own type and spacing. The two screenshots the user supplied are in
`docs/design/reference/`:

| File | What to take from it |
|---|---|
| `ref-wurst-719.jpg` | The whole ClickGUI: window grid, accent title bars, filled enabled rows, the HackList down the right, the logo and version top-left |
| `ref-wurst-cyan.jpg` | The Client Settings window — the exact list of things a user is allowed to recolour, and proof the same UI reads completely differently in another palette |
| `ref-wurst-settings.jpg` | Per-feature settings windows popped out on their own, colour rows with a hex and a bar |
| `ref-roblox-pill.jpg` | The floating rounded pill toolbar — this is our launcher |

Matcha stays a secondary reference for the furniture (a stats block, toasts, a
list of what is running), not for the layout.

Our mockups: `mock-clickgui.jpg` (layout — the row *labels* in it are generated
nonsense, read the shapes), `mock-settings.jpg` (a window and the UI Settings
window, legible).

## The shape of it

```
 ARANDOMMENU v2.1      ⌜ ☰ ◷ ▤ ✕ ⚙ ⌝            Speed [CFrame ×2]
 FPS  144                  the pill                   Fly
 PING  28                                          Player ESP
 TIME 01:14                                        Anti-Fling
                                                     HUD list
 ┌ COMBAT ────── – 📌┐  ┌ MOVEMENT ─── – 📌┐
 │ Kill Aura      [V]▸│  │ Speed      [F] ▸│
 │ Aim Assist        ▸│  │ Fly            ▸│
 │ Trigger Bot        │  │ Noclip          │
 └────────────────────┘  │ Spider         ▸│
 ┌ VISUALS ───── – 📌┐  └─────────────────┘
 │ Player ESP     [X]▾│
 │   Boxes    Corner ▾│
 │   Thickness ──●─ 2 │
 │   ☐ Filled box     │
 │   Colour  #F0F0F0  │
 │   ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁  │
 │ Chams              │
 └────────────────────┘
```

- **Wordmark and stats, top-left.** `ARANDOMMENU`, the version, and under it a
  small monospace block: FPS, ping, session time, place. Wurst puts it exactly
  here and it is the cheapest thing in the menu that makes it feel like a client
  rather than a script.
- **The pill, top-centre.** A floating rounded capsule of icons, lifted straight
  from Roblox's own in-game top bar (`ref-roblox-pill.jpg`): open/close the
  GUI, search, configs, keybinds, UI settings, panic. It is the one rounded,
  soft element on screen, and it is the only chrome that stays visible when the
  ClickGUI is closed. On a phone it is also the launcher, which is why it
  replaces the rail from the previous draft.
- **The windows.** One per category plus Favourites, laid out in a grid on first
  run, dragged wherever the player likes afterwards. Dense, flat, 4 px corners,
  1 px border, semi-transparent body. Title bar filled with the accent, name on
  the left, two small buttons on the right: **collapse** (body hides, title bar
  stays) and **pin** (window survives closing the GUI, so a player can keep
  three windows on screen while playing). Height follows content up to
  **Max height**, then the body scrolls.
- **The HUD list, right edge.** Wurst's HackList: every enabled module, right
  aligned, no background, sorted by width, sliding in and out. Each module may
  publish a short status in brackets — `Speed [CFrame ×2]`, `Auto Farm
  [3 targets]`, `Aim Assist [locked]`. That bracket is one of the best ideas in
  Wurst and costs us one optional string per module.
- **Tooltips** on hover, with their own opacity setting.

## The row

Today's card is kept, made denser and given Wurst's read:

- **Enabled is a filled row**, not a small indicator. With 38 modules the
  question "what is on" must be answerable from across the room.
- Name on the left. A **keybind pill** only when a key is bound. A **triangle**
  on the right only when the module has settings.
- Clicking the row toggles. Clicking the triangle expands the settings inline,
  pushing the rows below down. Right-click opens the three-dot menu — keybind,
  favourite, reset, **pop out into its own window** (Wurst does this for X-Ray
  and the HackList; it is how a player builds a HUD of the four things they
  actually use).
- Favourite and three-dot appear on hover, so a resting row is name + state and
  nothing else.

Inside an expansion, the setting lines are Wurst's exactly: label left, value
right. A slider is a thin bar with a square knob and its number at the end. A
checkbox is a small square. A dropdown is a full-width line with a triangle. A
colour is a label, its hex, and a thin bar of that colour underneath.

`Show` rules keep working inside an expansion — lines appear and disappear as
conditions change and the window's height follows. Player ESP has the deepest
rule tree in the menu and is the test case.

## Customisation is the feature

This is the half of Wurst the user actually asked for. One **UI Settings**
window, styled like every other window, live, no reload
(`mock-settings.jpg`, and `ref-wurst-cyan.jpg` for what Wurst exposes):

| Colours | Shape | Behaviour |
|---|---|---|
| Background | Opacity | Animations on/off |
| Accent (chrome) | Tooltip opacity | Isolate windows |
| Enabled (rows) | Corner radius | Tooltips on/off |
| Text | Border thickness | HUD list: mode, position, sort, colour |
| Text muted | Row height | Scale |
| Border | Max height | Snap to edges |
| Tooltip | Font | |

**Accent and Enabled are two separate tokens**, exactly as Wurst separates
"Accent" from "Enabled hacks". Filling 38 rows with the same colour that paints
every title bar is loud; letting the player pick magenta chrome with green rows
is the whole reason Wurst's screenshots look different from each other.

On top of the raw tokens: named presets — **Monochrome** (default),
**Wurst** (magenta chrome, green rows), **Cev** (cyan), **Matcha** (pink),
**Vape**, **Midnight**, **Ember** — and an export/import string so a theme can
be pasted to a friend. Import applies into a copy, validates text-against-
surface contrast, and only then swaps; an import that leaves half the tokens
switched is worse than no import.

Semantic colours are never theme tokens. Health green, danger red and MM2's role
colours label game data; a theme that recolours "murderer" is a theme that lies.

## Three windows that are not categories

- **UI Settings** — the table above.
- **Keybinds** — every bound key in one list, rebindable, conflicts flagged.
- **Configs** — profiles, save, load, autoload per game.

Plus **Search**: fuzzy match over every module name, option name and tooltip.
Enter toggles the top hit, Tab opens its window and scrolls to it. With 38
modules and roughly 400 options this is not a nicety.

## What we do not copy from Wurst

Wurst is a Minecraft mod rendered at Minecraft's density with Minecraft's font.
We keep our type, our spacing rhythm and our 4 px corners, and we keep the
window bodies genuinely translucent rather than tinted. The default palette
stays dark and restrained — Wurst's magenta is a *preset*, not the identity.

## Motion

| | |
|---|---|
| Toggle | row fill wipes in over 0.10 s |
| Expand | height tween 0.16 s, lines fade in |
| Window open | fade and 2 px rise, 0.12 s |
| HUD list | entry slides in from the right edge, 0.15 s |
| Tooltip | fade 0.08 s after a 0.4 s hover |

Nothing bounces, nothing spins, nothing exceeds 0.2 s, and the Animations switch
turns all of it off in one place for low-end phones.

## Mobile

The pill is already the Roblox-native touch affordance, so it stays. Windows
become full-width sheets, one at a time, dragged down to dismiss. The stats
block keeps FPS and ping and drops the rest. The HUD list moves to the top-left
under the wordmark, where a thumb does not cover it. Same rows, same theme,
different placement policy. `MobileActions` is untouched.

## Phases

Each phase ends with a menu that works.

| # | What | Owner |
|---|------|-------|
| 0 | One token set (accent and enabled separate), `Theme:Bind`, every literal colour removed, gate contract. No visible change. | A |
| 1 | `WindowManager`: drag, collapse, pin, max height, scroll, snap, persistence. Today's main window becomes window #1. | A |
| 2 | Category windows, the dense row, inline expansion. The tab strip dies. | A |
| 3 | The pill, wordmark, stats block, HUD list, tooltips, toasts. | A |
| 4 | UI Settings, presets, export/import, Keybinds and Configs windows, Search, motion pass. | A |

Phase 0 is invisible and is most of the risk: 34 `Color3.` literals in the
shell, 19 in `Widgets`, 7 in `SettingsPage`, 6 in `FloatingWindows`, 5 in
`Render`, and a `Theme` table that is read once at build time and therefore
repaints nothing when it changes.

## What is deleted

`createTab` (431 lines), `centerMain` (341), the tab strip, and the four
overlays' private copies of drag, clamp, close and persistence in
`FloatingWindows`. Expect the shell to lose 600-900 lines and `FloatingWindows`
most of its first 600. If those numbers do not move, something got wrapped
instead of replaced.
