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

- `bedwars-vape-6872274481.lua.txt` — a third-party Vape script for Roblox
  BedWars, place `8444591321`: 21,452 lines and 182 modules, including every
  feature the BedWars round asks for. It is the behavioural reference for
  `src/games/BedWars.luau` in the same role `vape-v4-universal.lua.txt` plays for
  the universal cards, and the same rule applies: read it for contracts, never
  copy code. Two things it settles that no decompile would: blocks and beds are
  enumerated through the CollectionService tags `'block'` and `'bed'`, and many
  actions are the game's own client controllers (`ItemDropController.dropItemInHand`,
  `UserInputController.getUserInputType`) rather than a forged remote. Where it
  and `remote-logs/8444591321-*.json` disagree, the capture wins: the script may
  be written against an older client.

- `bedfight-place-dump.rbxmx.zip` — a saved place from BedFight, the worked
  example behind `src/library/Weapons.luau`. It contains **no `Tool` instances
  at all**: its swords are view models under `workspace.CurrentCamera.ViewModel`,
  its inventory is a `HotbarHandler` module driving GuiButtons in
  `PlayerGui.BackpackGui`, and on touch the swing comes from
  `PlayerGui.MobileGui.ButtonsFrame.Sword`, whose `MouseButton1Down` and
  `MouseButton1Click` the game listens on. Every one of those three shapes is
  something the weapon library now looks for.

- `places/` — saved places, compressed, one directory per capture round.
  `Place_8444591321_partes.7z.001` + `.002` is Roblox BedWars, place
  `8444591321`: concatenate the two parts and unpack to get one
  `Place_8444591321.rbxlx`. See "Where a large capture goes" below before adding
  another.

- `remote-logs/` — Remote Logger output captured live in BedFight and BedWars.
  These are
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

## Where a large capture goes

Decided when the BedWars round landed 24 MB of 7z parts and a 5 KB remote log
loose in the repository root, which is where nothing else in this project lives.

- **Remote logs go in `reference/remote-logs/`**, named
  `<placeId>-<timestamp>.json` and `.txt`, both parts. They are small — the
  BedWars pair is 15 KB — text, and they are the only record of an argument
  shape that no decompile can reproduce, so they are committed without
  discussion.
- **Saved places go in `reference/places/`**, compressed, never expanded. The
  precedent is `bedfight-place-dump.rbxmx.zip` at 1.3 MB. Keep the archive the
  capture arrived as: the BedWars place is two 7z parts because that is how it
  was split to upload, and re-packing it would break the checksum the user can
  verify against their own copy.
- **The unpacked place is never committed.** `Place_8444591321.rbxlx` is 170 MB
  of XML; `.gitignore` refuses `*.rbxlx`, `*.rbxl` and `*.rbxmx` under
  `reference/places/` so an unpack in the working tree cannot be staged by
  accident. Unpack it, mine it, write the facts into the game module's header,
  delete it.
- **Above roughly 50 MB compressed, do not commit at all.** Git stores every
  version forever and this repository is cloned by every agent session; the
  BedWars parts already put 24 MB of permanent binary in the history, which is
  half of what `.git` weighs. A capture that size arrives as a link the user
  posts in chat, and the facts mined from it live in the module header.
