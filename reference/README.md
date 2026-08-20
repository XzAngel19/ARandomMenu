# Reference sources

Third-party code kept for reading, not for running. Nothing in this directory
is downloaded by the menu, compiled by the validation workflow or referenced by
`src/core/Manifest.luau`.

- `vape-v4-universal.lua.txt` — the bundled universal build of
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

- `remote-logs/` — Remote Logger output captured live in BedFight. These are
  the argument shapes no decompiler can give you, because they are the values a
  specific action produced: `PlaceBlock("Green Wool", 5, Vector3(-237, 60, 6))`,
  `SwordHit(«Model PlayersContainer.someone», "Wooden Sword")`,
  `PurchaseItemShopItem(«Part …ItemShopPrompt», "Blocks", "Wool")`,
  `EquipTool("Wooden Sword")`, `WearArmor("", "Pants")`. `src/games/BedFight.luau`
  calls them exactly as recorded.

The equivalents in this repository are `src/core/Framework.luau`,
`src/library/Entity.luau` and `src/modules/<Category>/*.luau`; they are written
from scratch against this menu's own card and option API rather than copied.

The Vape dump carries a `.txt` suffix on purpose. It is third-party source kept
for reading, not code this repository compiles or lints, and its first line is
its own cache watermark rather than `--!strict` — so a checker that walks every
`.lua` file in the repository would either fail on it or force us to edit
somebody else's file.
