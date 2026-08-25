# Reach ownership

"Reach" is one word for four different distances in this menu. This file records
which card owns which one, why there is no universal combat-Reach card, and what
a game has to declare before it gets one.

## The decision

1. **No new card.** Nothing is added to the inventory, and the frozen count does
   not move.
2. **`Interact Extender` keeps its name and its config key.** It is the adapted
   counterpart of Wurst's `Reach` — Wurst extends how far you can use a block,
   and the Roblox equivalent of "use a block" is a `ProximityPrompt` or a
   `ClickDetector`. Renaming it to `Reach` in a menu that also ships Kill Aura,
   Hitboxes and TriggerBot would promise combat reach it cannot deliver, and
   would orphan `Universal.InteractExtender` in every saved profile for no
   behaviour at all. The authoring brief already says not to force a Minecraft
   name onto a Roblox-only module.
3. **Kill Aura owns one reach, not two.** `Swing range` and `Attack range` were
   two rows for one distance, and at the shipped defaults (12 and 14) the second
   one never fired: every target inside 12 studs was already inside 14. They are
   now a single `Reach`.
4. **`Hitboxes` is size, not distance,** and stays a separate card. Expanding the
   part an enemy is hit on is a different mechanism with different visibility:
   everybody in the server can see the hits landing.
5. **Game modules keep their own reach numbers.** They are gated by the game's
   own remote or button, which is the only place a combat distance can honestly
   live.

## Who owns which distance

| Surface | Distance it owns | Mechanism | Server sees |
| --- | --- | --- | --- |
| `Interact Extender` | prompt / click-detector activation range | `MaxActivationDistance`, optionally `HoldDuration = 0` | the same handler it always ran, from further away |
| Kill Aura `Reach` | target selection **and** contact firing | `Entity:InRange`, then the tool's `Activate` and optional `firetouchinterest` | the weapon's own swing; the touch is client-side |
| `Hitboxes` | none — part size | `BasePart.Size`, `CanCollide`, `Massless` | a character whose root is 18 studs wide |
| `Weapons` | none | activation only: tools, view models, hotbar slots, on-screen buttons | whatever the game's own button sends |
| VD Hit Aura | 34 studs in Blatant mode | the game's `attackRemote:FireServer()` | a real attack from a distance the game does not allow |
| TRS Tackle / Pickup / Pass / Header | 3–180 studs per action | the game's own action path | the game's own action |
| BedFight Scaffold | 6 studs below the feet | block placement | a placed block |
| MVSD Silent Aim | the ray's own length | `hookfunction` on `Ray.new` | a normal shot; only the client's ray was redirected |

The last four are the shape a combat reach has to take: inside the game module,
against a named remote or button, with the distance the game actually validates.

## Why combat reach is not universal

A client can only make an attack land further in three ways:

- **inflate the hitbox** — that is `Hitboxes`, it is visible to everyone in the
  server, and it does not change what the server allows;
- **forge the game's attack remote with a longer distance** — remote spoofing,
  which `docs/architecture/targeting-and-learning.md` rules out of the shared
  core, and which breaks the moment a server checks the sender's position;
- **hook the engine's raycast** — a process-wide hook, which
  `tools/check_module_conformance.py` now blocks in `src/modules/**`.

There is no fourth way. A universal card called `Reach` that promised combat
distance would have to pick one of those three, so it does not exist.

## Supported-game adapter contract

A game module may add combat reach when all of this is true and written down in
the module:

1. **Place contract.** The feature is built behind the game's own place check,
   the way every other feature in `src/games/**` is. Nothing about it is
   reachable from a universal card.
2. **Weapon contract.** It names the remote, tool or on-screen button it presses
   (`VD`: `attackRemote`; `BedFight`: the hotbar slot or mobile button). If the
   module cannot name it, the feature does not ship.
3. **Rate contract.** The press is clock-gated. VD's Blatant mode holds
   `os.clock() - lastHit >= 0.12` for exactly this reason; an ungated burst was
   hundreds of attacks a second.
4. **Honest label.** If the distance is one the game does not allow, the option
   says so. `Blatant reach` is the model: the word is in the row.
5. **No global hooks.** The adapter presses the game's own inputs. MVSD's
   `Ray.new` hook is the standing exception, it is isolated to that file, and it
   is not a pattern to copy.

Server and physics limits that no client-side reach can remove:

- the server owns the authoritative position; a distance check that runs there
  rejects the hit and may kick;
- network ownership means a character you do not own cannot be moved or rotated
  reliably, so reach built on moving *you* is weaker than reach built on the
  game's own remote;
- streaming and replication delay mean the target the client sees is where the
  target was, so a long reach multiplies the error;
- anything that inflates a part or fabricates a touch is visible to other
  clients and to any server that logs it.

## What changed here

- Kill Aura: `Swing range` + `Attack range` → `Reach` (5–60, default 12). A saved
  `Universal.KillAura.Swingrange` is copied to `Universal.KillAura.Reach` the
  first time the card builds and the new key has never been written; the old key
  is left in place so an older build still reads the profile.
- Kill Aura: `Mode` (Multi/Single) removed — `Max targets = 1` is the same
  decision. `Swing only` removed — it was `Contact damage` inverted.
- Kill Aura: the target highlight lost its dimmed "in swing range but not being
  hit yet" state, which only existed because there were two ranges.
- `Hitboxes`: Friend List entries are skipped, matching every other combat card.
- `Hitboxes`: a property the game rewrote mid-round becomes the new baseline, so
  a restore puts back the game's size and not the one the module first saw.
- `Interact Extender`: teardown restores every prompt and detector and drops the
  refresh sweep. Both used to outlive the card.
- `Remote Logger`: the `__namecall` hook is actually removed on disable. The old
  restore called `restorefunction` on the value `hookmetamethod` returned, which
  is not a hooked function, so the hook stayed installed for the session. Where
  an executor will not give the metamethod back, the card now says so instead of
  reporting a clean disable.
- `tools/check_module_conformance.py`: process-wide hooks in `src/modules/**`
  fail the gate unless the file is listed with an owner and a removal condition.

## Field debt

Headless tests cannot reach any of this. It needs a live place.

WallHop:

- sloped `MeshPart` and `UnionOperation` normals — the probe gate is
  `abs(normal.Y) <= 0.28`, which is a guess about what counts as a wall;
- moving or unanchored walls, where the normal at probe time is stale by the
  third offset;
- games that rewrite `AssemblyLinearVelocity` after a `Humanoid` state change,
  which is exactly where the final stage writes;
- ownership changes under latency: the offsets are CFrame writes, and a client
  that does not own the assembly has them discarded;
- touch `JumpRequest` cadence, which repeats while the button is held and can
  start a second hop the moment the 0.22 s cooldown expires.

SpinBot:

- server-owned assemblies and games that clamp angular velocity — Velocity mode
  writes an absolute value every frame, so a clamp reads as "it does not spin";
- seated characters and vehicle welds, where rotating the root fights the seat;
- first-person camera controllers, which read the root's orientation directly;
- ragdoll systems that replace the `Humanoid` or the root inside a frame;
- anti-cheat that distinguishes a CFrame rotation from a physics one. CFrame mode
  is detectable by exactly that difference and is not presented as anything else.
