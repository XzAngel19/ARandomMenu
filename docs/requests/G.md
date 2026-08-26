# Agent prompts — BedWars adapter round

New game: **Roblox BedWars, place `8444591321`**. The material is in
`reference/` on `arena/01a03bca-arandommenu` — it landed in the repository root
and the integrator moved it, so a path from an older copy of this file is stale:

- `reference/remote-logs/8444591321-1787702434.json` / `.txt` — a live Remote
  Logger capture, 17 remotes, real argument shapes.
- `reference/places/Place_8444591321_partes.7z.001` + `.002` — the saved place.
  Concatenate the two parts and unpack: the payload is one
  `Place_8444591321.rbxlx`, 170 MB of XML. It contains 1558 `RemoteEvent`
  references, 281 `RemoteFunction` references, 279 `ProximityPrompt`s and 795
  `Highlight`s. No agent has mined it yet; `.gitignore` now refuses the unpacked
  file, so unpack it, mine it, and delete it.

All code, UI labels and runtime strings stay English. Work from the current
`arena/01a03bca-arandommenu` tip, push to your own session branch, never open a
PR, never touch `main`.

## Read first

`docs/agents/RULES.md`, `docs/agents/agent-D-gameplay.md`,
`docs/architecture/reach-ownership.md` (the supported-game adapter contract),
`docs/architecture/targeting-and-learning.md`, and `src/games/BedFight.luau`.

**BedFight is the sibling, not a duplicate.** It targets place
`71480482338212`, a different BedWars-shaped game with different remotes
(`SwordHit(model, weapon)`, `PlaceBlock(name, count, pos)`, `MineBlock`). The
new game uses `@rbxts.net` `_NetManaged` remotes with table payloads. Two game
modules, one genre. Copy BedFight's *discipline* — every argument shape quoted
from a capture, nothing guessed — and none of its payload shapes.

## The captured contract

Verified from `reference/remote-logs/8444591321-1787702434.json`. Everything below is a real capture,
not an inference:

| Remote | Kind | Arguments |
| --- | --- | --- |
| `SwordHit` | RemoteEvent | `{entityInstance, chargedAttack={chargeRatio}, validate={targetPosition, raycast={cursorDirection, cameraPosition}, selfPosition}, weapon}` |
| `SwordSwingMiss` | RemoteEvent | `{chargeRatio, weapon}` |
| `ProjectileFire` | RemoteFunction | `weapon, itemType, itemType, origin, origin2, velocity, projectileId, {drawDurationSec, shotId}, timestamp` |
| `ProjectileHit` | RemoteEvent | `projectileId` |
| `PlaceBlock` | RemoteFunction | `{mouseBlockInfo={placementPosition}, blockType, blockData, position}` |
| `DamageBlock` | RemoteFunction | `{blockRef={blockPosition}, hitPosition, hitNormal}` |
| `GroundHit` | RemoteEvent | `part, position, timestamp` |
| `AckKnockback` | RemoteEvent | `{knockbackId, playerPosition}` |
| `PickupItemDrop` | RemoteFunction | `{itemDrop}` |
| `SetInvItem` | RemoteFunction | `{hand = accessory}` |
| `Inventory/SetObservedChest` | RemoteEvent | (none) |
| `BedwarsPurchaseItem` | RemoteFunction | `{shopItem={currency, itemType, amount, price, category, disabledInQueue}, shopId}` |
| `RequestPurchaseTeamUpgrade` | RemoteFunction | `"ARMOR"` |
| `RequestPurchaseBedTeamUpgrade` | RemoteFunction | `"bed_alarm"` |
| `GetMatchStats` | RemoteFunction | (none) |
| `TridentUnanchor` | RemoteFunction | (none) |

Weapons and items are `Accessory` instances under
`ReplicatedStorage.Inventories.<player>.<item>` — e.g.
`…Inventories.Angelitohajaj.stone_sword`, `…wool_blue`, `…telepearl`. There is
no `Tool`, exactly like BedFight.

### The two limits that decide the design

1. **`SwordHit` is validated.** The client sends its own `selfPosition`,
   `cameraPosition`, `cursorDirection` and `targetPosition`, and the server has
   all four. A hit that names a victim the ray cannot reach is a hit the server
   can refuse — and a pattern it can log. So "reach" here means producing a
   *self-consistent* payload from where the character actually stands, never
   inventing one. Where the payload cannot be made consistent, the feature does
   not ship. This is the contract in `reach-ownership.md`, and it is the reason
   there is no universal Reach card.
2. **The rate is the weapon's, not ours.** Measured cooldowns: wooden, iron,
   diamond, void and light swords 0.30 s; sparkler 0.33 s; ice 0.40 s; daggers
   and rageblade 0.25 s. A player swinging by hand lands about 27–33 registered
   hits per 10 seconds; the hitreg method the request asks for targets
   **35–36 per 10 seconds**, which is above the 0.30 s sword's own ceiling of
   33.3 and therefore sits deliberately inside the margin the server leaves. It
   is a real target, not a typo — but it is per 10 seconds, never per second,
   and no slider may offer a rate the weapon's cooldown cannot produce.

## The reference script

`6872274481.lua` at the repository root is a third-party Vape/CatVape BedWars
script: 21,452 lines, **182 modules**, and it already implements everything the
request lists. It is a behavioural reference in exactly the same role as
`reference/vape-v4-universal.lua.txt`, and the same rules apply:

- read it for **behaviour and contracts**, never copy code into this repository;
- move it to `reference/` beside the other dumps; its loader prelude
  (`downloadFile`, the `catvape.dev` fetch, the cache watermark) is not something
  this project reproduces in any form;
- where it and the Remote Logger capture disagree, the capture wins: the script
  may be written against an older client.

### What it answers

Four items were listed as needing a definition. They are defined:

- **PotESP / "dessert pots"** — the block is `desert_pot`. Blocks are enumerated
  through CollectionService, not by walking the workspace:
  `GetTagged('block')`, `GetInstanceAddedSignal('block')`,
  `GetInstanceRemovedSignal('block')`, filtered on `Name == 'desert_pot'`. The
  icon mesh template is the first `MeshPart` under
  `ReplicatedStorage.Assets.Blocks.desert_pot`.
- **BedPlates / BedESP** — beds carry the CollectionService tag `'bed'`, same
  three signals. That is also how `Nuker` finds a bed without mining the place
  for a container name.
- **Statespoofer** — the reference calls it `DeviceSpoofer`. It replaces
  `bedwars.UserInputController.getUserInputType` and fires the game's own
  `SendUserInputType` handler with `{userInputType = 'MOBILE'|'PC'|'GAMEPAD'}`,
  restoring both on disable. That remote is **not** in our capture, so it needs
  a live capture before it ships.
- **FastDrop** — no remote at all: it calls the game's own
  `bedwars.ItemDropController.dropItemInHand` while a key is held, no textbox has
  focus and no inventory is open.

### The two facts that change the design

1. **CollectionService tags `'block'` and `'bed'` are the enumeration path.** No
   workspace sweep, no cached NPC-style scan, and streaming is handled by the
   added/removed signals. BedFight has no such tags, which is why it walks the
   tree; BedWars does not need to.
2. **Prefer the game's own client controllers over forged payloads.** The script
   reaches `bedwars.ItemDropController`, `bedwars.UserInputController` and
   `bedwars.Handler:Get(name):Fire('SendToServer', ...)`. Calling the game's own
   controller produces a payload the game itself built, which is the strongest
   form of the `SwordHit` consistency rule above. Forge a payload only where no
   controller exists, and say so in the module header.

One calibration note: the reference AutoClicker offers CPS 1–9 (default 7) and a
separate Block CPS 1–12. Those are **clicks**, not registered hits — clicking a
0.30 s sword at 7 CPS still lands about 3.3 hits a second. Our hitreg row is in
registered hits per 10 seconds and must not be relabelled to match.

## Agent D — the game module

Build `src/games/BedWars.luau` behind the place check for `8444591321`. You own
`src/games/**`, `src/modules/**` and their suites. Keep the universal inventory
frozen at 45: everything here is a game feature, not a universal card.

Mine the place first and write the facts down the way BedFight's header does,
before writing a line of feature code. Needed: the bed container and what a bed
model looks like, generator containers, the item-shop prompt parts, the kit
definitions (which kit grants which item — the request's example is
`bees` → `beekeeper`), and where a player's inventory is readable from.

Requested features, triaged against the capture:

- **Evidenced now** — build these first, in this order:
  `Kill Aura` (hitreg, below) · `FastPlace` and `Scaffold` (`PlaceBlock`) ·
  `Nuker` (`DamageBlock`, beds are blocks) · `ShopClicker`
  (`BedwarsPurchaseItem`, which arrives with the whole `shopItem` table, so a
  purchase needs no price lookup) · `Chest steal` (`SetObservedChest`) ·
  `Autotool` and `fast drop` (`SetInvItem {hand = accessory}`) ·
  `Projectile aimbot` and `Projectile tracers` (`ProjectileFire` gives origin,
  velocity, `shotId` and `drawDurationSec`; `ProjectileHit` closes it) ·
  `Inventory ESP` (read `ReplicatedStorage.Inventories.<target>`) ·
  `Nofall (custom)` (`GroundHit` is the landing report) ·
  `Velocity / Knockback` (`AckKnockback {knockbackId, playerPosition}` is the
  client's own answer to a knockback — decide honestly whether suppressing it is
  a movement feature or a desync, and say which in the tooltip).
- **No remote needed** — `Speed`, `Fly`, `Phase`, `Target strafe`, `Noslow`,
  `Hitboxes`, `AimAssist`: these are the universal cards. Do not fork them into
  the game module; if one needs a BedWars-specific default, expose it as a game
  feature that adjusts the universal card, not a copy.
- **Needs the place mining pass first** — `BedESP`, `KitESP`, `BedPlates`.
- **Not captured, needs a live session** — the drop remote behind `fast drop`
  (`PickupItemDrop` is the pickup, not the drop), and every argument shape the
  log's 17 remotes did not cover. Do not guess these; ask for another capture.
- **Defined by the reference script** — `PotESP` (`desert_pot`), `BedPlates`
  and `BedESP` (tag `'bed'`), `Statespoofer` (device spoofing, needs a capture of
  `SendUserInputType`) and `fast drop` (`ItemDropController.dropItemInHand`). See
  "What it answers" above. A device spoofer that exists only to defeat an
  anti-cheat check stays out of scope; this one reports an input type to the
  game's own handler and restores it, which is a different thing, but it does not
  ship until the remote is captured.
- **`Redirect (Silent Aim)`** — stays inside `src/games/BedWars.luau`, is off by
  default, and says what it is. Prefer redirecting the *payload*
  (`validate.raycast.cursorDirection` and `cameraPosition`) over hooking
  `Ray.new` the way MVSD does: the payload path needs no process-wide hook, and
  a hook is the one thing `tools/check_module_conformance.py` will fail on if it
  ever leaks into `src/modules/**`.

### Order of work

1. Mine the place and write the facts into the module header the way BedFight
   does: bed container and bed model shape, generator containers, item-shop
   prompt parts, kit-to-item definitions, and where an inventory is readable.
   Nothing guessed; if the dump does not answer it, it goes on the capture list.
2. The remote layer: one helper per remote, each with a payload builder that
   refuses to send a shape the capture does not have. This is what every feature
   below is built on, so it lands first and alone.
3. `Kill Aura` with the hitreg row, then `Autoclicker`'s BedWars detection on the
   same rate contract.
4. The block features: `FastPlace`, `Scaffold`, `Nuker`.
5. The economy features: `ShopClicker`, `Chest steal`, `Autotool`, `fast drop`.
6. The projectile features: `Projectile aimbot`, `Projectile tracers`.
7. The read-only features: `Inventory ESP`, then `BedESP` and `KitESP` once the
   mining pass answers them.
8. The movement and knockback features: `Velocity`, `Nofall (custom)`,
   `Target strafe`, `Noslow`, `Phase` — each one only where the universal card
   genuinely cannot do the job, and never as a fork of it.
9. The desktop dock search option. `src/library/Furniture.luau` and
   `src/library/SettingsPage.luau` are D's lane: the preference, the row in the
   UI Settings panel, the rebuild path that makes the row real, and the suite
   that proves the field is gone and the Navigator door is untouched.

Each step is its own commit with its suite. Steps 3-8 are blocked on step 2;
steps 7's `BedESP` and `KitESP` are blocked on step 1.

### Kill Aura hitreg

The unit the player thinks in is **hits per 10 seconds**, and that is the unit
the row uses. One `CreateTwoSlider`, drawn per swing by `GetRandomValue()` so the
interval is never machine-exact:

- rail 30–37, default band **35–36**;
- the drawn value converts to an interval as `10 / hits` — 35 is 0.2857 s, 36 is
  0.2778 s — and the swing waits that long, plus no human reaction time;
- the card's status shows the **registered** rate over a rolling window, not the
  drawn one, so a band the server refuses is visible instead of silently
  optimistic;
- the tooltip says what the number is and what it is not.

Why 35–36 is the target and also the edge: a 0.30 s sword cooldown allows
`10 / 0.30 = 33.3` hits per 10 s, so 35 sits 4.8 % under the nominal cooldown
and 36 sits 7.4 % under. Whether those register is the server's decision, not
the module's — it depends on whether the cooldown is enforced on the client, on
the server's own clock, or against the timestamp in the payload. So the module
aims at the band, measures what actually lands, and clamps down when it does
not. Per weapon the ceiling is:

| Weapon | Cooldown | Ceiling per 10 s |
| --- | --- | --- |
| daggers, rageblade | 0.25 s | 40 |
| wooden, iron, diamond, void, light | 0.30 s | 33 |
| sparkler | 0.33 s | 30 |
| ice | 0.40 s | 25 |

When the module can read the equipped weapon it clamps the band to that ceiling;
35–36 on an ice sword is not a setting, it is a request the game will ignore.
When it cannot read the weapon, it clamps to the 0.30 s case and says so.

`Autoclicker (detect tool)` is the same rate contract with a hand on the mouse:
detect the equipped `Accessory` under `Inventories.<localPlayer>` instead of a
`Tool`, express the row in the same hits-per-10-seconds unit, and hold the same
clamp.

## Agent C — gates

Read `docs/agents/RULES.md` and `docs/architecture/modules.md`. Your lane is the
suites and the tooling; land each gate in the same commit as the code it pins.
In order:

1. **Place gating.** Nothing in `src/games/BedWars.luau` is built for any other
   place id. Assert it by initialising the module against a different
   `game.PlaceId` and requiring zero features and zero connections.
2. **Payload parity.** Every remote call goes through a fixture that records the
   payload, and each recorded payload matches the captured shape in this file
   field for field — `PlaceBlock`, `DamageBlock`, `SwordHit`, `ProjectileFire`,
   `BedwarsPurchaseItem`, `SetInvItem`, `AckKnockback`. A field the capture does
   not have is a failure, not a tolerance.
3. **The hitreg rail.** A drawn value never leaves 30–37 hits per 10 seconds, the
   interval is `10 / hits`, and the per-weapon clamp holds: 0.40 s caps at 25,
   0.30 s caps at 33, 0.25 s allows the full rail. Assert the *interval*, not the
   label.
4. **The registered rate is measured, not claimed.** With a fixture that rejects
   every third hit, the status must fall below the drawn band. A card that
   reports the band it asked for is the failure this check exists to catch.
5. **The payload validator refuses an inconsistent `SwordHit`** — a
   `targetPosition` the `raycast` block cannot reach, or a `selfPosition` that is
   not the character's — and sends nothing.
6. **Teardown.** No connection, task, drawing or borrowed property survives
   disable, death, or a character replacement.

Do not turn a missing executor capability into a passing check, and do not add
screenshot uploads, remote rewriting or anti-cheat bypass logic to make a test
green. Report the exact check count and any mock debt.

## Agent A — integration, and the desktop dock

1. Integration checklist as written in `docs/requests/F.md`: preflight against
   your session branch, compare each agent's base tip with the remote, inspect
   bundle freshness, regenerate `runtime/bundle.luau` and the stamp instead of
   picking a side, keep the 45-card inventory and the alphabetic category
   ordering, and report the exact check count with the hashes.
2. **New session, new integration branch — done.** The previous integrator
   session was gone and its branch `arena/01a02c8a-arandommenu` could not be
   pushed to, because an Arena session is pinned to the branch Arena created
   for it. The current integrator merged that tip (`24b4c9d`) into its own
   branch — a fast-forward, `main` being an ancestor — so
   **`arena/01a03bca-arandommenu` is the integration branch** and contains the
   old one whole. `docs/agents/RULES.md` §2a records the move; every other
   document here now names the new branch. C and D: fetch, base and hand work
   back against `arena/01a03bca-arandommenu`.
3. **Desktop dock search option** — D implements it, since
   `src/library/Furniture.luau` and `src/library/SettingsPage.luau` are D's lane
   (the seam is `Furniture.luau:1276-1284`, where `dockSearchWidth` is already
   `0` on touch, and the field sized from it at line 1515; the row belongs in
   the UI Settings panel `SettingsPage.luau:1501` builds). Your job is to review
   that it adds no second door to the Navigator and does not bring back the wide
   launcher surface.
4. **Repository hygiene — done.** Remote logs go in
   `reference/remote-logs/`, compressed saved places in `reference/places/`,
   the unpacked `.rbxlx` is git-ignored and never committed, and a capture over
   roughly 50 MB compressed arrives as a link instead of a commit. The rule and
   its reasoning are in `reference/README.md`; the four BedWars files were moved
   out of the repository root to match it.

## Rules

A suite that pins a surface updates in the same commit as the change. Report:
hash, branch, exact validation count, per-item summary, and honest field debt.
Validation must end `All checks passed.`
