# UI input and numeric contracts

## Cursor ownership

The shell captures `UserInputService.MouseBehavior` and
`MouseIconEnabled` when the Wurst menu opens, applies
`MouseBehavior.Default` and a visible icon, and restores the exact values when
the menu closes or is destroyed. Property-change listeners re-apply the menu
values if a first-person camera script writes `LockCenter` while the menu is
open. Nothing is changed while the menu is hidden.

Navigator is a separate surface and does not claim this cursor ownership unless
it opens the Wurst menu itself.

## Choice popup toggling

`Widgets` tracks the row that owns the active single- or multi-choice popup.
Opening another row closes the first. Pressing the same green arrow while its
popup is already open closes it; it does not construct a second popup. Owner,
menu-hide and outside-click teardown still use the same close path.

## Numeric fields

`Min`, `Max` and `Step` describe the pointer drag rail. The numeric TextBox is a
free finite-number field:

- typed and stored values are not clamped to the drag rail;
- the rail still quantizes and clamps pointer drags, so dragging remains
  predictable;
- NaN and infinities are rejected because they cannot be serialized or used
  safely by a module;
- range controls keep low less than or equal to high while allowing either end
  outside the visual rail.

This keeps deliberate input such as a custom reach or distance intact without
letting pointer noise create long decimal tails.

## Aim Assist smoothing

`Smoothing` now spans 0–100 with distinct behavior:

- `0` snaps to the selected point;
- positive values use a frame-rate-independent exponential response;
- larger values take longer to settle;
- `Aimbot` retains its valid target and uses a modest response boost, while
  normal `Aim Assist` continues to retarget within its cursor FOV.

The two modes therefore differ in target policy and lock retention, not just in
the label on the card.

## Supported Redirect adapters

A game-specific Redirect could be added only behind an explicit place and
weapon adapter contract. The adapter would need a named shot path, target
policy, visibility behavior, cleanup and tests for the exact game. It must stay
under `src/games/**` and remain opt-in.

A universal `Redirect` that replaces `Raycast`, `__namecall`, `Mouse.Hit` or
remote arguments is not an isolated module: it changes every caller in the
client. That kind of global stealth or anti-cheat-evasion hook is not part of
this menu's core.
