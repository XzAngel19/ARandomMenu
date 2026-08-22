# Agent B — notes

## Remotes that were never captured

- **DestroyBlock** does not exist in BedFight. The destroy path that *was*
  captured is `ItemsRemotes.MineBlock` (`tool name`, block part, grid
  position, origin, direction). There was never a DestroyBlock feature to
  delete. Bed Nuker's default path still swings the game's own control;
  `Mine remote` is the captured call, opt-in, because beds are not in
  `PlayersBlocksContainer`.
- **KnifeThrown** was never captured in MM2. Knife Redirect needed
  `hookfunction` to rewrite aim and, without a payload, would have been
  inventing one. The option (and the two rows that only served it — Target
  closest to mouse, Prediction envelope) were deleted rather than left on
  as a switch that does nothing. Knife Aura stays: it fires
  `HandleTouched:FireServer(root)`, which is the game's own stab.
- **Shoot Redirect (MM2), deleted.** Same disease as KnifeThrown. The hook
  had to replace a WeaponService *aim accessor* by name, and nothing ever
  captured what those are called: `reference/remote-logs/` is all BedFight
  traffic (place 71480482338212), and there is no MM2 place dump. The code
  guessed seven names (`GetMouseTargetCFrame`, `GetTargetCFrame`, …) and
  when none matched — the common case, and always on executors without
  `hookfunction` — `triggerManualShot` silently fell through to the same
  `Shoot:FireServer(origin, aim)` that Manual fires, so the mode was a
  second switch for the same behaviour. What was evidence-backed stayed:
  the `Shoot` remote's `(origin, aim)` payload (Manual/Custom both fire it)
  and `WeaponService.GunFired`, which is one of the five place fingerprints
  and now connects as a plain observer for the miss feedback instead of
  riding along on the redirect installer. To bring Redirect back it needs a
  live capture naming the accessor the client actually calls per input
  type.

## PlaceBlock

The second argument is the hotbar slot. Captured as `5` and as `3`. Scaffold
now fires `PlaceBlock(name, variant, position)` instead of pretending it
cannot. Server Scaffold already did.

## Show pass

Framework modules that had a row which only matters under another option now
declare `Show`. Hitboxes moved onto `CreateModule` so transparency can gate
on "Show hitbox". Fly and PhysicsSpeed are done: both build through the
kernel now, the advanced block is declared (`Show = {Option = "Advanced
settings"}`), and the rows that belong to one mode say so (Fly's Response
multiplier only for Velocity/Constraint/Pulse; Physics Speed's Burst
interval only for Pulse, Air control only in Adaptive, Motor torque only
under Custom properties, Auto-jump velocity only under Auto jump). Modules
with a single always-relevant slider (Jump Power, Gravity, FOV, …) have
nothing to gate.

Physics Speed's card was also renamed from "Speed" to "Physics Speed": it
and Speed.luau both created a feature named "Speed", so the two cards shared
the `Universal.Speed` configKey and overwrote each other's saved values.
Its saved options move from `Universal.Speed.*` to `Universal.PhysicsSpeed.*`.

**Ordering caveat — resolved by Agent A.** The kernel used to re-read `Show`
rules only when an option's *value* changed, and `register()` attaches a
row's rule *after* its builder ran, so the last gated row of a panel started
visible until something else triggered the pass. Every module worked around
it by ending its panel with an ungated row (Fly and Physics Speed put the
switch after the block, Kill-Aura style; Phase Dash and No Fall end on
Cooldown / Ground scan) and Infinite Jump — whose every row is gated —
closed with one explicit `RefreshVisibility()`. `register()` now runs the
pass itself whenever a rule arrives, so none of those arrangements is load
bearing any more; they are harmless where they stand and can be undone when
their files are next touched. `tools/test/suites/movement-engines` asserts
the folded initial state, so the regression is pinned either way.

## Suites

Suites take `(ctx)` the way the split runner's do, so wiring one in is a
single `require` line in `tools/test/run.luau`.

- `movement-engines` — Fly, Physics Speed, Phase Dash, Infinite Jump: option
  contracts, the Show rules per mode, enable/disable task accounting,
  WalkSpeed restoration, the dash cooldown, the jump interval floor.
- `protection` — No Fall: mode-owned rows, the Impact brake clamping a
  mocked fall, State mode never touching velocity.
- `games` — VD's Blatant rate caps measured against counting remotes
  (and the deleted FOV/Fullbright cards staying deleted), TRS firing the
  pickup remote the attribute scan actually settles on with the clamped
  reported distance, MM2 initialising with no Redirect left in Shoot's
  mode list.

Mock and host gaps the suites shim, worth absorbing into the real files when
their owners can (each one cost a debugging round): `Vector3:Lerp` (the
suites patch it in), `Theme`, `TweenService`, `CollectionService`'s tag
surface, `Enum.Font`, `Sound:Play/Stop`, `Player:GetMouse`,
`host.getCharacterParts`, `feature.row` on the harness card, and option
callbacks being unreachable from a test (the suites wrap the builders to
record them).

## Module audit (every card under src/modules)

No option anywhere was doing nothing — the deletion passes before this one
(TriggerBot "nine rows became six", MM2's ESP regrouping, Knife Redirect's
two rows) had already cleared the dead weight, and the build's dead-option
contract keeps it clear. What the audit did find: three legacy cards whose
rows only exist under one mode of the card, with no way to say so. They are
kernel modules now, and their rows declare `Show = {Option = "Mode",
Values = {...}}`:

- **Phase Dash** — Dash distance, Exit speed, Collision padding and
  Preserve velocity are Blink's; Slide speed is Slide's. Cooldown and Flash
  duration are the only always-rows left.
- **Infinite Jump** — Jump power exists for Normal/Impulse/Stack (Rise and
  Fall never launch you), Jump interval for every repeat mode except Rise,
  Rise speed only for Rise.
- **No Fall** — Safe landing speed is the Impact brake (dead in State),
  Reset fall record is the State trick (dead in Impact). Ground scan stays
  always: both paths brake near the floor.

Cards with a single always-relevant control (Gravity, FOV, Jump Power,
Safe Walk, High Jump, Lag Switch, …) still have nothing to gate, and the
one-option toggles (Noclip, X-Ray, Anti-Void, Anti-AFK, Rejoin) have
nothing to declare.

## TRS and VD audit

Neither game has a capture or a place dump in `reference/` — everything
below is read from the code's own coherence, which is evidence of a kind
but not proof. What would settle each open question is one Remote Logger
session in the live game; the Remote Logger card already exists for
exactly that.

### TRS (football, PlaceId 14315258385)

Grounded — the world model hangs together the way observed games do, and
the remote names carry the game's own typos (`TackIe`, `SoftDisPlayer`,
`ShootTheBaII` with a capital I), which nobody invents:

- `Remotes.Action` → `TackIe`, `Deke`, `GKJump`, `RightDive`/`LeftDive`
  (with `root.CFrame`), `FrontDive`.
- `Remotes.Pass` → `(teammate, ball.CFrame)`; `Remotes.SoftDisPlayer` →
  `(owner, distance, false, ball.Size)`.
- The `Bools` state model (Tackled/Tackling/Debounce/iframe/Penalty/
  Kickoff/FreeKick/dribbleDebounce), `ball` with `playerWeld` + `creator`
  ObjectValue, per-character `GrabTick`, `HomeGoalDetector`/
  `AwayGoalDetector`, TeamColor 23/141 — consistent across every feature.

Guessed or device-limited, said so on the card now where it wasn't:

- **Auto Pickup's remote is not known by name.** It is found by scanning
  `Remotes` for the last RemoteEvent carrying an instance attribute
  literally called "Attribute", then fired with one number (the clamped
  "Reported distance"). The payload and the local `GrabTick` write look
  observed, the *identification* does not; the card's note says so. A
  capture naming the pickup remote would replace the scan with a lookup.
- **Shoot Assist / Power Shot / Large Shoot / Auto Header press the
  game's own `MobileCTRL.TouchControlFrame` buttons** (JumpButton,
  PowerShoot, Header) through `firesignal`/`getconnections`. If the game
  only builds that GUI on touch clients, all four cards fail on desktop
  with "TRS MobileCTRL shot button was not found" — loud, but whether
  desktop clients have the frame at all is unknown from here.
- The shot redirect rewrites `ShootTheBaII` args 1/3/4/7/9/10 (direction,
  power, vector, curve, flag, side). Positions this specific were
  presumably read once and could only be confirmed by a capture.
- Every TRS card that repeated its own sliders' min/max in an information
  note lost the note; the ones that say something the rows don't (Deke vs
  Assist, native button, colour meaning) kept it.

### VD (asymmetric horror, PlaceId 93978595733734)

Grounded — every remote is looked up by exact path and *asserted* when
missing, so a wrong path kills the feature loudly instead of letting it
lie: `Remotes.Generator.RepairEvent(point, bool)`,
`Remotes.Items.Parrying Dagger.parry()`, `Remotes.Attacks.BasicAttack()`,
`Remotes.Window.VaultEvent(trigger, true)` plus the optional `fastvault`,
`VaultCompleteEventpart1`, `VaultCompleteEvent(trigger, false)` — names
too awkward to be invented.

Deleted:

- **"VD Field of View"** and **"VD Fullbright"** were the universal FOV
  and Fullbright cards rebuilt inside the game module — same per-frame
  loop, same shared `state.fovController` / same six Lighting properties,
  with fewer options. The universal cards already work in VD; two cards
  doing one job is what the standard deletes.

Fixed:

- **Both "Blatant" modes fired remotes without any rate limit** — the
  generator aura sent 8 `RepairEvent`s *per frame* (~480/s) and the hit
  aura 4 `BasicAttack`s per frame (~240/s). The repo's own rule is that
  anything talking to a server stays inside the band the game produces;
  an unbounded flood is a server-side detector's easiest catch. Blatant
  is now bounded: repairs every 0.03 s, attacks every 0.12 s — still
  well past legit, no longer a shout.

Heuristics that can only fail quietly (show nothing), never lie:
killer detection (team name / Role attribute / Killer collision group),
hidden-player detection (four guessed attribute names + Locker children),
generator progress (three guessed attribute names, falls back to IDLE),
killer-power cooldowns (scans whatever attributes replicate), footstep
and attack animation name matching. If a capture ever lands, the guessed
name lists are the first thing to replace.

## The MM2 module, feature by feature (4,480 lines — analysis, nothing cut)

The question put to this pass: which of MM2's cards are universal mechanics
wearing a game condition, and which are irreducibly MM2. Twelve cards and
three ESP extras, classified.

### Irreducibly MM2 — the card needs a fact only MM2 has

- **Shoot.** The Gun tool's `Shoot` RemoteEvent and its captured
  `(origin, aim)` payload, WeaponService.GunFired for shot confirmation,
  role-priority targeting. Every input is an MM2 fact.
- **Knife Aura.** `HandleTouched:FireServer(root)` is MM2's own stab path.
- **Trajectory Calibration.** Built on MM2's GunFired/knife events and round
  windows; the card says so itself.
- **Instant Role Notify.** Reads MM2's Gameplay round pipeline and role
  assignment.
- **Always Show Timer.** Replays MM2's `RoundStart` client handler and drives
  `MainGUI.Game.Timer` — the whole trick is that specific listener.
- **Role Fling** *(hybrid)*. The motor — spin, orbit, press, restore — is the
  universal Fling physics, duplicated here; what MM2 adds is role targeting
  (Fling Murderer / Sheriff / All Innocents). If the motor were shared with
  `src/modules/Utility/Fling.luau`, this card would be four buttons and a
  target picker.
- **Teleport to Map / Lobby / Get Gun** *(hybrid)*. Teleporting is universal;
  MM2 supplies the map container (`findMM2Map`, CoinAreas), the lobby and the
  dropped-gun lookup. Auto Get Gun is the same teleport on a timer.

### Universal with a game condition — the mechanic knows nothing about MM2

- **Sprint.** A hold that re-applies WalkSpeed 30 with a trail. Not one MM2
  fact in it; it lives here because it was written here. The README already
  calls it the reference `hold` module — the universal kind.
- **Loop All Interact.** fireproximityprompt/fireclickdetector over prompts
  in a container. The sweep scope (the MM2 map) is the only game fact; the
  mechanic is Interact Extender's sibling.
- **Hide Names.** Replace names in local UI and leaderboards with Anon. The
  idea works anywhere; MM2 supplies its leaderboard and name-label paths.
- **Silence** (Other radios / Trap sounds). Muting Sound instances under
  name-matched models. Universal muting, MM2's containers.
- **Auto Play ID.** Loops a local Roblox audio asset by ID. There is no MM2
  fact at all — this is a Utility card that lives in the wrong file.
- **ESP extras** (Coins, Traps, Sheriff gun, role colours). Already the right
  shape: the universal Player ESP draws them, MM2 only registers what a
  "coin" and a "Murderer" are through the bridge.

### Where that leaves a split, when one is wanted

Nothing above is cut. If the owner takes the split, the order that keeps
every card working is: Auto Play ID first (pure move), Sprint second (pure
move), then the conditioned ones (Loop All Interact, Hide Names, Silence)
which need the game bridge to hand over their containers, and Role Fling
last, which needs Fling's motor extracted or shared. Shoot, Knife Aura,
Trajectory Calibration, Instant Role Notify and Always Show Timer stay in
the game file no matter how far the split goes.

## Suites, second pass: the twenty-one no suite loaded

Five suites, written and validated but stranded when the session lost its
network — recorded here so the work is not lost if the commit is not:

- `movement-basics` — Speed, Freeze Movements, High Jump, Jump Power, Noclip,
  Spider.
- `protection-rescue` — Anti-Fling, Anti-Void, Safe Walk.
- `utility-misc` — Anti-AFK, Fling, Gravity, Interact Extender, Lag Switch,
  Rejoin Server. The six that were dead for a week run here for the first
  time anywhere.
- `visuals-misc` — Field of View, Fullbright, X-Ray, Zoom Unlocker.
- `combat-analytics` — Hitboxes, Projectile Calibration.

Three module bugs the third question caught:

- **Anti-AFK** stored its Idled listener under `"AntiAFK"` and its teardown
  asked for `"AntiAfk"` — the listener outlived the module and kept answering
  idle kicks after teardown. *(Fixed on the live branch.)*
- **Gravity**'s teardown only disconnected: unloading the menu with the card
  on left the workspace at the slider's gravity. It restores now. *(Fixed on
  the live branch.)*
- **Fling** called `addTextOption` as a bare global while taking every other
  builder from `host.` — the mirror image of the five dead modules: it works
  only because the shell happens to publish that one global. Style, not a
  defect; still worth taking from `host.` like the rest.

New mock gaps those suites shim (for whoever owns the Host): the harness host
has no `addFeatureTooltip`, `state.isProtectedTarget`, or `RunService`;
`workspace.FallenPartsDestroyHeight` and default part `Size`s are unset; the
mock player has no `Idled`/`GetMouse` and the camera is not parented to
workspace (restore paths read `Parent`); `Enum.CameraMode`/`Enum.Font` don't
exist; `settings()` is absent. Also recorded: the option builders' callback
sits at a different vararg position per builder (toggle/key/text 3, cycle 4,
number 5) — the suites wrap the builders to record them, and the first
wrapper had the number position wrong until Hitboxes exposed it.
