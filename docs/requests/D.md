# Requests for agent D

## Vehicle Speed is now yours, and it already exists

`PhysicsSpeed.luau` is renamed to `VehicleSpeed.luau`, and everything outside
your lane that had to move with it has moved: the manifest, the shell's embedded
fallback list, and the suite that requires it. The gate is green at 680 with the
new name in place, so you can start on the file itself without touching anything
you do not own.

You were right and I was wrong. My brief said Speed "never knew vehicles exist",
and that is true of `Speed.luau` — but the vehicle work was already written, in
a module whose name described what it touched instead of what it was for. Nobody
looking for vehicle handling found it, including me.

What is left inside the file is yours:

- **Strip the character-side duplication.** Four sites read `WalkSpeed` or the
  shared move input and re-implement what `Speed.luau` already does. This module
  moves whatever the character is sitting in; it should not also move the
  character.
- **Re-examine the six modes** — Adaptive, Smooth, Boost, CFrame, Pulse,
  Teleport. Some of those are character-movement modes wearing a vehicle name.
  A mode that only makes sense for a walking player belongs in Speed or nowhere.
- **Keep the restore tables.** `originalVehicleSeats` and `originalMotorHinges`
  record every seat's `MaxSpeed`/`Torque` and every hinge's `MotorMaxTorque` per
  instance and put them back. That is the hard-won part of the file and the
  reason it was not worth rewriting from scratch. A seat left at ten times its
  torque stays broken for everyone who sits in it afterwards.
- **Your multiplier, done the way you described.** Separating the vehicle's own
  base speed from the excess the module adds is right; multiplying an
  already-multiplied velocity every frame compounds and is how a car ends up in
  orbit.

## The MM2 folder literal

`src/games/MM2.luau` hard-codes the storage folder. `getfenv().PRODUCT` is the
right way to reach it — the shell publishes `PRODUCT` into the game module
environment. The harness does not yet, so that one-line change fails the gate
until agent C adds it to `injectGame`. It is requested; park it until then
rather than adding a fallback to the old literal.

## The ESP, in two steps rather than one

Removing `Refresh interval` outright breaks a suite in agent C's lane, and
neither of you can land both halves in one green commit.

So do the part that fixes what the user actually reported: move `PlayerESP` and
`ItemRender` from `:Loop` to `:Render`, and set the option's default to 0.
That alone makes the overlay track the camera. Deleting the option is cosmetic
and can wait for C to drop the suite's dependency on it.

## On not having tested in a real game

You are right not to claim a technique works where it was not run, and saying so
is worth more than a confident guess. Nobody in this project can run Roblox; the
user is the only one who plays it. Write down which technique you expect to win
in which kind of game and why, and the user will bring back the answer.
