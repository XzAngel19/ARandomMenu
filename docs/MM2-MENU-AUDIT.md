# MM2 menu audit (v70)

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

35 cards. 31 are the universal set; the MM2 section has **4**:

| Section | Card | Category | Rows |
| --- | --- | --- | --- |
| MM2 | SilentAIM | Combat | 15 (Gun: Auto Shoot, Aim method, Target, WallCheck, Macro, Silent sweep, Silent spawn, Spawn A/B status, Auto lead, Lead offset ms, Prediction status, Reset prediction, Target player; Knife: Knife Throw, Throw with button) |
| MM2 | Fling | Exploits | 5 |
| MM2 | Blurt Roles | World | 5 (Instant Roles, Delay, Repeat on change, Fake Blurt Roles, Blurt now) |
| MM2 | Calibration | Utilities | 5 (Calibration status, Save calibration, Clear MM2 history, TrailESP, Trail color) |

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

1. **Gun ESP and Trap ESP look broken.** Both are toggles inside ItemESP, and
   `ItemRender.lua:191-203` only starts the providers while the ItemESP card
   itself is ON, while `:496-514` lets the toggle be ON with the card OFF.
   The tooltip says "while ItemESP is ON", but a toggle that stays ON and
   does nothing is the worst possible feedback. Either enabling a provider
   turns Item ESP on, or the provider row is disabled while the card is off.
2. **`CoinChams` is a ghost.** `MM2/base.lua:28-31` creates the
   `MM2Effects/CoinChams` folder, `:94-95` defines `coinColor` and
   `coinTransparency`, `:4243` exports the folder, and nothing reads any of
   it: there is no card and no cham. The coin containers at `:766-770`
   (`CoinContainer`, `CoinAreas`, `Coins`) are used only to find the map.
3. **`src/games/MM2.luau` is dead code.** 5,229 lines, not in
   `Wurst.lua`'s module list, not in the bundle (none of its card names
   appear in `bundle.lua`: Gun Visuals, Silence, Auto Play ID, Always Show
   Timer, FriendList, Hide Names, Loop All Interact and Coin Chams are all 0
   hits). It still describes 17 cards that no longer load:
   the old Shoot and Knife cards, Player ESP, Gun Visuals, Instant Role
   Notify, Loop All Interact, Silence, Auto Play ID, Always Show Timer,
   FriendList, Hide Names, Coin Chams and the old Trajectory Calibration.
   Anyone reading the repo will believe those features exist.
4. **Four universal modules compile but never load.** `Manifest.lua` lists 32
   modules; `src/games/universal` has 36 files. Missing from the manifest:
   `Blatant/WallHop.lua`, `Other/LagSwitch.lua`, `Other/RejoinServer.lua`,
   `Other/RemoteLogger.lua`. All four are written into `bundle.lua` (73
   files) and never required, so they cost bytes and documentation noise
   only. Two of them (server hop, lag switch) are hub features users ask for.
5. **Developer capture lives in the player menu.** The Calibration card
   (`TrajectoryCalibration.lua` + `CalibrationTrails.lua`) exposes
   "Save calibration", "Clear MM2 history", "TrailESP" and "Trail colour" in
   Utilities. It is useful for us and meaningless for a player; it belongs
   behind a debug flag or a single "Advanced" section, not beside real
   modules.
6. **Overlapping pairs, candidates to merge:** Gravity vs Anti Void
   ("Velocity limit" applies velocity damping), Freeze Movements vs Disguise
   (both stop the target animation state), and Spider vs the dead WallHop and
   Noclip (three ways to move through geometry).

## What I would do, in this order

1. Fix the provider feedback (Gun ESP / Trap ESP): a toggle that is ON must
   turn Item ESP on, or be visibly unavailable while Item ESP is OFF.
2. Delete `src/games/MM2.luau` and the dead `CoinChams` leftovers, or finish
   the coin ESP; right now it is a half-removed feature.
3. Register `RejoinServer` (a hub feature that already works) and delete
   `RemoteLogger`, `LagSwitch` and `WallHop` unless they are coming back.
4. Move the Calibration card to a debug section.
5. Only then add new modules: god mode, kill all, aura whitelist, no-spread,
   coin counter, auto unbox. Each one needs a server-authority check before
   it is promised in the menu.

Items 1-4 are cleanup, not new surface; they can ship together.
