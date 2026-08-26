# Agent prompts — BedWars adapter round

New game: **Roblox BedWars, place `8444591321`**. The material is at the
repository root of `arena/01a02c8a-arandommenu`:

- `8444591321-1787702434.json` / `.txt` — a live Remote Logger capture, 17
  remotes, real argument shapes.
- `Place_8444591321_partes.7z.001` + `.002` — the saved place. Concatenate the
  two parts and unpack: the payload is one `Place_8444591321.rbxlx`, 170 MB of
  XML. It contains 1558 `RemoteEvent` references, 281 `RemoteFunction`
  references, 279 `ProximityPrompt`s and 795 `Highlight`s. No agent has mined it
  yet; do not commit the unpacked file.

All code, UI labels and runtime strings stay English. Work from the current
`arena/01a02c8a-arandommenu` tip, push to your own session branch, never open a
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

Verified from `8444591321-1787702434.json`. Everything below is a real capture,
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
   and rageblade 0.25 s. That is **2.5–4.0 hits per second**, and the community
   ceiling is about **33–34 registered hits per 10 seconds**. The "36 hits per
   second" figure in the original request is roughly ten times the real number
   and must not become a slider maximum: a card that offers 36 swings a second
   in a game whose fastest sword allows 4 is a card that gets the player kicked.

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
- **Needs a definition before anyone writes it** — `PotESP` ("dessert pots":
  confirm the item and where it lives) and `Statespoofer`. A state spoofer that
  exists to defeat an anti-cheat check is out of scope for this repository; if
  the intent is something else, name the behaviour and it can be judged.
- **`Redirect (Silent Aim)`** — stays inside `src/games/BedWars.luau`, is off by
  default, and says what it is. Prefer redirecting the *payload*
  (`validate.raycast.cursorDirection` and `cameraPosition`) over hooking
  `Ray.new` the way MVSD does: the payload path needs no process-wide hook, and
  a hook is the one thing `tools/check_module_conformance.py` will fail on if it
  ever leaks into `src/modules/**`.

### Kill Aura hitreg

One control, `CreateTwoSlider`, in **hits per second**, drawn per swing by
`GetRandomValue()` so the interval is never machine-exact:

- rail 2.0–4.0, default band 2.8–3.2;
- the module clamps the drawn rate to the equipped weapon's cooldown when it can
  read the weapon, and to 4.0 when it cannot;
- the card's status shows the drawn rate, the way Wurst shows a mode or a count;
- the tooltip states the real ceiling (about 33 hits in 10 s) so nobody reads a
  slider maximum as a promise.

`Autoclicker (detect tool)` is the same rate contract with a hand on the mouse:
detect the equipped `Accessory` under `Inventories.<localPlayer>` instead of a
`Tool`, and hold the same cooldown.

## Agent C — gates

Read `docs/agents/RULES.md` and `docs/architecture/modules.md`. Add focused
headless tests for the new game module, in your lane, landing with D's commit:

- place gating: nothing is built for any other place id;
- every remote call goes through a fixture that records the payload, and each
  payload matches the captured shape field for field;
- the hitreg rail: a drawn rate never leaves 2.0–4.0, and a weapon with a 0.4 s
  cooldown clamps it to 2.5;
- teardown: no connection, task or property survives disable, death or a
  character replacement;
- the payload validator refuses an inconsistent `SwordHit` rather than sending
  it.

Do not turn a missing executor capability into a passing check, and do not add
screenshot uploads, remote rewriting or anti-cheat bypass logic to make a test
green. Report the exact check count and any mock debt.

## Agent A — integration, and the desktop dock

1. Integration checklist as written in `docs/requests/F.md`: preflight against
   your session branch, compare each agent's base tip with the remote, inspect
   bundle freshness, regenerate `runtime/bundle.luau` and the stamp instead of
   picking a side, keep the 45-card inventory and the alphabetic category
   ordering, and report the exact check count with the hashes.
2. **New session, new integration branch.** The previous integrator session is
   gone. Your Arena session is pinned to its own `arena/<id>-arandommenu`
   branch, so you cannot push to `arena/01a02c8a-arandommenu`; seed yourself by
   merging that tip (`main` is an ancestor of it, so the merge fast-forwards)
   and treat your own session branch as the integration branch from then on.
   Update `docs/agents/RULES.md` and the `docs/requests/*.md` headers that name
   the old branch, and tell C and D the new name in your reply, not only in a
   file.
3. **Option to hide the desktop dock search.** The dock already collapses its
   search field on touch: `src/library/Furniture.luau:1276-1284` computes
   `dockSearchWidth` as `touchPrimary and 0 or DOCK_SEARCH_WIDTH` and the field
   at line 1515 is sized from it. Desktop needs the same zero, behind a stored
   preference, with the row in the UI Settings panel that
   `src/library/SettingsPage.luau:1501` builds. The seam exists; what is missing
   is the preference and a rebuild path so the row is not decorative. It must
   not add a second door to the Navigator and must not bring back the wide
   launcher surface.
4. Repository hygiene: the two 7z parts put 24 MB of binary in git and the
   unpacked place is 170 MB. Decide where large captures live — `reference/`
   holds `bedfight-place-dump.rbxmx.zip` at 1.3 MB, which is the precedent — and
   record it before the next capture lands.

## Rules

A suite that pins a surface updates in the same commit as the change. Report:
hash, branch, exact validation count, per-item summary, and honest field debt.
Validation must end `All checks passed.`
