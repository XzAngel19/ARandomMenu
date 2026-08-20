# Reference sources

Third-party code kept for reading, not for running. Nothing in this directory
is downloaded by the menu, compiled by the validation workflow or referenced by
`src/core/Manifest.luau`.

- `vape-v4-universal.lua` — the bundled universal build of
  [VapeV4ForRoblox](https://github.com/7GrandDadPGN/VapeV4ForRoblox). It is the
  worked example behind this repository's own module architecture: a kernel that
  owns categories and modules, per-module option builders, and a cleanup list
  that empties when a module is switched off. The split-engine Fly (a horizontal
  method and a vertical "float" method chosen independently), the Speed method
  list and the entity-library approach used by ESP and TriggerBot all come from
  reading it.

- `bedfight-place-dump.rbxmx.zip` — a saved place from BedFight, the worked
  example behind `src/library/Weapons.luau`. It contains **no `Tool` instances
  at all**: its swords are view models under `workspace.CurrentCamera.ViewModel`,
  its inventory is a `HotbarHandler` module driving GuiButtons in
  `PlayerGui.BackpackGui`, and on touch the swing comes from
  `PlayerGui.MobileGui.ButtonsFrame.Sword`, whose `MouseButton1Down` and
  `MouseButton1Click` the game listens on. Every one of those three shapes is
  something the weapon library now looks for.

The equivalents in this repository are `src/core/Framework.luau`,
`src/library/Entity.luau` and `src/modules/<Category>/*.luau`; they are written
from scratch against this menu's own card and option API rather than copied.
