# MM2 menu audit (v70, executed in v71)

> **v71 state.** Items 1-4 below are done. The menu now has 36 cards and the
> MM2 section has 5 (SilentAIM, Coin ESP, Fling, Blurt Roles, and Calibration
> only when `WURST_DEBUG` is on). Deleted: `src/games/MM2.luau` and the four
> other legacy monoliths (`TRS`, `VD`, `MVSD`, `Universal`, 10,502 lines that
> no longer loaded), plus `WallHop`, `LagSwitch` and `RemoteLogger`.
> `Rejoin Server` is registered. Coin ESP is a real module built on what used
> to be the dead `CoinChams` leftovers (folder, colour, transparency), and
> Kill Aura gained an "Ignore players" list. The provider rows now turn Item
> ESP on instead of staying ON and dead. The details of what is still missing
> (god mode, kill all, no-spread, auto unbox) and why are at the bottom.

The question was whether the MM2 side of the menu is complete next to Eclipse
Hub, OverDrive H and similar hubs, and which modules are useless or broken.

The inventory below is not a grep. `python3 tools/audit_menu.py` boots the
real bundle in the mocked executor (the same prelude `validate.sh` uses) and
prints every card and every row the user actually sees, in order:

```
LUAU=/home/user/.tools/bin/luau python3 tools/audit_menu.py
LUAU=/home/user/.tools/bin/luau python3 tools/audit_menu.py --json
```

A module can compile, ship in `bundle.lua` and never be registered. Only the
booted menu can answer "is this feature there?".

## What the menu has

36 cards. 31 are the universal set; the MM2 section has **5** (4 in a release
boot, where the debug-only Calibration card does not exist):

| Section | Card | Category | Rows |
| --- | --- | --- | --- |
| MM2 | SilentAIM | Combat | 15 (Gun: Auto Shoot, Aim method, Target, WallCheck, Macro, Silent sweep, Silent spawn, Spawn A/B status, Auto lead, Lead offset ms, Prediction status, Reset prediction, Target player; Knife: Knife Throw, Throw with button) |
| MM2 | Fling | Exploits | 5 |
| MM2 | Blurt Roles | World | 5 (Instant Roles, Delay, Repeat on change, Fake Blurt Roles, Blurt now) |
| MM2 | Coin ESP | Render | 2 (Coin colour, Coin transparency) + live count in the card status |
| MM2 | Calibration | Utilities | 5, **debug only** (`WURST_DEBUG`) |

The other MM2 controls are real but live **inside universal cards**, so they
are invisible to anyone scanning the MM2 section:

| MM2 control | Lives in | Source |
| --- | --- | --- |
| Gun ESP, Trap ESP | ItemESP (Render) | `Render/RoundEsp.lua:96-104` registers them as item providers |
| Murderer / Sheriff / Hero / Innocent / Dead colours and ESP | PlayerESP, Chams, Nametags, HP | role provider in `MM2/base.lua` |
| Knife Aura, Aura Range | KillAura (Combat) | `Blatant/KnifeAura.lua:222-240` rewrites the card and filters its rows |
| Sprint | Speed (Exploits) | `Movement/Sprint.lua` |
| Teleport to Map / Lobby / Player, Get Gun, Get Gun key, Auto Get Gun, Gun pickup delay | Teleport (Utilities) | `Movement/Teleport.lua` |
| TrailESP, Trail colour | Calibration (Utilities) | `Other/CalibrationTrails.lua` |

## Missing next to Eclipse / OverDrive

Verified absent from the booted menu and from the source: no card, no option,
no dead code path that would bring them back.

| Hub feature | Status here |
| --- | --- |
| God mode | missing |
| One-click kill all | missing |
| Aura whitelist / friend check | missing (KillAura has Team check and Target NPCs only) |
| No-spread ("sharp shooter") | missing |
| Coin ESP, coin/token counter, dropped-item value | missing (the `CoinChams` leftovers are described below) |
| See dead chat | missing |
| Radio mute, radio auto-play | missing (only in the dead `MM2.luau`) |
| Loop all interact | missing (only in the dead `MM2.luau`) |
| Free emotes (sit / ninja / dab / ...) | missing; Disguise only copies the target's emotes |
| Auto open mystery boxes (`ReplicateToy:InvokeServer("FakeBomb")` exists in the game) | missing |
| Coin / XP farm, webhook, end-round / hop rules | missing |
| Server hop | the module exists (`Other/RejoinServer.lua`) and is never registered |
| Remove barriers | missing |
| Hardcore camera unlock | partial: Zoom has "Unlock forced first person" |
| Bring player | missing |
| Anti-steal, desync, auto end round | missing |
| Hit logs, chat spoofer | missing |
| Hide names, friend list, always-show timer, gun visuals | missing (they only exist in the dead `MM2.luau`) |

Already covered, do not rebuild: role ESP for every role (PlayerESP, Chams,
Nametags, HP), gun ESP, trap ESP, silent aim with visible check and
prediction, auto shoot, wall check, auto lead, knife throw, knife aura,
kill aura, fling, teleport set, get gun, sprint, infinite ghost, anti void,
X-Ray, fullbright, FPS work, zoom, anti-AFK, blurt roles, instant role
notify ("Instant Roles"), config save/load.

## Useless, broken or dead

1. ~~**Gun ESP and Trap ESP look broken.**~~ **Fixed in v71.**
   A provider only draws while Item ESP is ON (`ItemRender.lua:191-203`), and
   the row used to stay ON with the card OFF. Now the row's callback goes
   through `setProviderEnabled`: ON with the card OFF activates the card's own
   switch, ON with the card ON enables the provider, OFF disables it.
2. ~~**`CoinChams` is a ghost.**~~ **Fixed in v71.** `CoinEsp.lua` now uses
   `MM2Effects/CoinChams`, `coinColor` and `coinTransparency`: one Highlight
   per coin under the map's coin containers, a refresh loop that follows
   pickups, and the live count in the card status. The containers at
   `MM2/base.lua:766-770` still identify the map; the same list drives the
   highlight.
3. ~~**`src/games/MM2.luau` is dead code.**~~ **Deleted in v71**, together
   with `src/games/{TRS,VD,MVSD,Universal}.luau` (10,502 lines in total, none
   of them loaded or bundled). It was 5,229 lines, not in
   `Wurst.lua`'s module list, not in the bundle (none of its card names
   appear in `bundle.lua`: Gun Visuals, Silence, Auto Play ID, Always Show
   Timer, FriendList, Hide Names, Loop All Interact and Coin Chams are all 0
   hits). It still describes 17 cards that no longer load:
   the old Shoot and Knife cards, Player ESP, Gun Visuals, Instant Role
   Notify, Loop All Interact, Silence, Auto Play ID, Always Show Timer,
   FriendList, Hide Names, Coin Chams and the old Trajectory Calibration.
   Anyone reading the repo will believe those features exist.
4. ~~**Four universal modules compile but never load.**~~ **Fixed in v71.**
   `Rejoin Server` is registered (33 modules, and the fallback manifest in
   `Wurst.lua` is now generated from the same list and asserted equal by
   `tools/test_manifest_sync.py`). `WallHop`, `LagSwitch` and `RemoteLogger`
   were deleted: no menu entry, no caller, no plan.
5. ~~**Developer capture lives in the player menu.**~~ **Fixed in v71.**
   The Calibration card and its TrailESP rows exist only when
   `WURST_DEBUG == true`; a release boot does not build them. The recorder in
   `base.lua` still runs, because the prediction needs it.
6. **Overlapping pairs, candidates to merge:** Gravity vs Anti Void
   ("Velocity limit" applies velocity damping), Freeze Movements vs Disguise
   (both stop the target animation state), and Spider vs the dead WallHop and
   Noclip (three ways to move through geometry).

## What is done, and what is refused

Done in v71: provider feedback, dead code deletion, `Rejoin Server`, debug-only
Calibration, Coin ESP + live counter (it uses what used to be the dead
`CoinChams` leftovers), and the Kill Aura ignore list.

Not shipped, on purpose:

- **God mode.** Damage in MM2 is applied by the server. Writing
  `Humanoid.Health` client-side is overwritten by the next replication and
  never stops a death. A toggle that does nothing is the dead code this
  cleanup just removed, so it is not in the menu.
- **Kill all.** It needs a remote that applies damage to arbitrary players.
  The captured traffic has `Shoot`, `KnifeThrown` and `GunFired`; there is no
  damage remote in any log or in the place dump. The gun fires one projectile
  at one target, so "kill all" would have to be a sequence of real shots, not
  a button.
- **No-spread.** Spread is decided by the server when it processes the shot;
  the client sends origin and destination. There is nothing client-side to
  tighten.
- **Auto unbox.** The mystery boxes are paid products. Automating
  `MarketplaceService` purchases would spend Robux without a confirmation
  screen; it is not going in the menu.

If any of those gets a verified remote or a server check, it can be added with
a test that proves it does something.
