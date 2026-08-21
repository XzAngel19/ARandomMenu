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
  type. *(README's MM2 Shoot bullet still describes the hook — needs
  Agent A's pass.)*


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
interval only for Pulse, Air control only for Adaptive, Motor torque only
under Custom properties, Auto-jump velocity only under Auto jump). Modules
with a single always-relevant slider (Jump Power, Gravity, FOV, …) have
nothing to gate.

Physics Speed's card was also renamed from "Speed" to "Physics Speed": it
and Speed.luau both created a feature named "Speed", so the two cards shared
the `Universal.Speed` configKey and overwrote each other's saved values.
Its saved options move from `Universal.Speed.*` to `Universal.PhysicsSpeed.*`.

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

## Agent A

`tools/bundle.py` and the stamped loader live on this branch from Agent A.
This pass does not edit them.
