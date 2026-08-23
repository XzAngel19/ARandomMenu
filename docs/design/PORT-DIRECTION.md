# Product direction

ARandomMenu is a Wurst-inspired Roblox port, not a byte-for-byte recreation.

## Visual target

The ClickGUI should be immediately recognizable as Wurst: rectangular windows,
compact rows, centred module names, pixel controls, the Wurst category order,
WurstLogo, HackList and Navigator. The target is roughly 90% visual parity.

The remaining 10% is deliberate Roblox adaptation. Current examples are the
managed blur, touch actions, protected GUI parenting, executor-safe loading,
viewport-aware sizing, the per-row keybind square and the compact mobile
launcher. Adaptations must solve a Roblox problem; they are not permission to
add decorative UI.

## Language

English is the only product language:

- interface labels, tooltips and notifications;
- loader, bootstrap and debug output;
- source comments, documentation, commits and GitHub discussion artifacts;
- stable identifiers and configuration keys.

Spanish is used only in direct conversation with the project owner. Roblox
`AutoLocalize` stays disabled so platform localization cannot silently alter
Wurst terms.

## Change priority

1. Safety and module boundaries.
2. Correct lifecycle, persistence and teardown.
3. Clear English and maintainable authoring contracts.
4. Visible defects and responsive mobile layout.
5. Wurst parity and polish.
6. Optional features.

A green test suite is necessary but does not make an unfinished surface done.
Every visible exception found in a real capture should either be fixed or
recorded as an explicit adaptation in `docs/wurst-deviations.md`.
