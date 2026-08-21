# Agent E — windows, the rail, and the row

Read `docs/agents/RULES.md` and `docs/design/UI-V2.md` first. The mockup in
`docs/design/mock-canvas.jpg` is the target.

You own **`src/library/FloatingWindows.luau`** and **`src/library/Cards.luau`**.
Nothing else. `WindowManager.luau` and `Widgets.luau` belong to agent A — you
are their biggest consumer, so review their interfaces and say what is missing,
but do not edit them.

Do not start until agent A has pushed phase 1: `WindowManager` with the main
window already migrated onto it. You are building on that, not beside it.

## The job

Turn a menu of tabs into a canvas of windows.

### Category windows

One window per category — Combat, Movement, Protection, Visuals, Utility, Spoof
— plus the active game, plus Favourites. Each is a `WindowManager` window, so
drag, resize, snap, z-order and persistence are not your problem; what is yours
is what a category window *contains* and how it behaves when it is nearly empty
or very full (Visuals with the ESP expanded is taller than the screen — it
scrolls inside the window, the window does not grow past the viewport).

Closed by default except the ones the player left open. First run opens Combat
and Movement, tiled from the top-left, and nothing else.

### The rail

A launcher, not a tab bar. Clicking a category opens its window if closed and
raises it if open; the icon shows an open/closed state and a count of enabled
modules in that category. Home, Search, Themes and Settings are rail entries
that open their own windows. Fixed width, always the same side, never scrolls.

The current tab strip and its `createTab` in the shell die when the rail lands.
Coordinate the deletion with A in the same integration — do not leave both.

### The row

This is the part the user already likes and it must survive intact: the card
colour, the toggle, the keybind pill, the favourite, the three-dot menu. What
changes is only what happens when it has settings.

Today settings live elsewhere. In Wurst they expand in place, and that is what
we want: a chevron on the right, clicking it pushes the rows below down and
reveals the module's own controls, indented, with a hairline on the left tying
them to their parent. Collapsing is instant; expanding is a short tween on
height only. Expansion state persists per module.

The `Show` rules already in the kernel keep working inside an expanded row —
rows appear and disappear as their conditions change, and the window's height
follows. That interaction is the one most likely to look broken; test it with
Player ESP, which has the deepest rule tree in the menu.

Right-click on a row opens the three-dot menu directly. "Pop out" makes that
single module its own window — that is how a player builds a HUD of the four
things they actually use.

### Search

A rail entry and a hotkey. Fuzzy match over every module name, every option name
and every tooltip. `Enter` toggles the top hit, `Tab` opens its window and
scrolls to it. With 38 modules and roughly 400 options this is not a nicety.

## What to delete

`FloatingWindows` currently carries its own drag, clamp, close and persistence
for five different window kinds. All of that moves to `WindowManager`; the four
overlays become ordinary managed windows with an unusual body. Expect the file
to lose most of its first 600 lines. If it does not shrink, the migration did
not happen — you wrapped it.

## Definition of done

- Every window drags, snaps, collapses, and comes back where it was after a
  reload, on a fresh profile and on an existing one.
- Nothing in the menu is reachable only through a tab.
- On a phone the manager's Sheet mode is used and no window can be dragged
  off-screen or made smaller than its content.
- A suite boots the shell headless, opens every category window, expands every
  row with settings, and asserts `destruct` leaves no connection behind.
