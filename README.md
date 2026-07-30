# ARandomMenu

Standalone Luau menu with universal tools and support for Murder Mystery 2 and
Realistic Street Soccer.

## Source layout

- `src/gui/Current/gui.lua`: presentation-only GUI factory. It creates the
  window, tabs, responsive layout, animations, and mobile menu control; it does
  not contain game functions.
- `src/Supported/Universal.luau`: features loaded in every experience.
- `src/Supported/Movement.luau`: movement features loaded in every experience.
- `src/Supported/MM2.luau`: Murder Mystery 2 registration.
- `src/Supported/TRS.luau`: Realistic Street Soccer registration.
- `src/Profile/<gameId>.lua`: per-game section and asset selection.
- `src/library`: shared registries and loading utilities.
- `ARandomMenu.luau`: executable bundle built from the source modules.
- `loadstring`: minimal loader for the executable bundle.

## Mobile behavior

Phone detection uses touch capability without a hardware keyboard. Mobile users
receive a circular menu shortcut. In MM2, holding the `Manual key` or
`Get Gun key` control enters placement mode for a draggable circular action
button. Positions and button size are persisted per profile.

The aurora background is by Khalil Benihoud and is available under the
[Unsplash License](https://unsplash.com/photos/aurora-borealis-umLAzmGNZbU).
