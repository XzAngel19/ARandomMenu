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

## PlaceBlock

The second argument is the hotbar slot. Captured as `5` and as `3`. Scaffold
now fires `PlaceBlock(name, variant, position)` instead of pretending it
cannot. Server Scaffold already did.

## Show pass

Framework modules that had a row which only matters under another option now
declare `Show`. Hitboxes moved onto `CreateModule` so transparency can gate
on "Show hitbox". Fly and PhysicsSpeed still build with `addToggleOption`
and hide their advanced block themselves — converting them is a dedicated
pass, not this one. Modules with a single always-relevant slider
(Jump Power, Gravity, FOV, …) have nothing to gate.

## Agent A

`tools/bundle.py` and the stamped loader live on this branch from Agent A.
This pass does not edit them.
