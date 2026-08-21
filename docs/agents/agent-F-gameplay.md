# Agent F — gameplay: modules and games

Read `docs/agents/RULES.md` first. This brief is the rest.

You own **`src/modules/**` and `src/games/**`**, and nothing else. You do not
touch the shell, the libraries, `tools/`, or `runtime/bundle.luau`.

You are the replacement for agent B, whose analysis is in `docs/notas-B.md`.
Read it — it is a card-by-card classification of MM2 and an audit of TRS and VD,
and it is still accurate.

## Your first three tasks, in order

These are bugs the user hit while playing. They are ranked by how much they hurt.

### 1. Speed does nothing in a vehicle

`src/modules/Movement/Speed.luau` only ever touches `Humanoid` and
`HumanoidRootPart`. Seated in a `VehicleSeat` the humanoid is welded to the
seat, so `WalkSpeed` is a no-op, `CFrame`/`Teleport` fight the vehicle's
constraints, and `Velocity` writes to an assembly whose wheel motors overwrite
it the same frame. Every car game with pedal controls is therefore unaffected by
the entire module.

What is needed is vehicle awareness, not a sixth mode bolted on:

- Detect the seat: `humanoid.SeatPart`, and whether it is a `VehicleSeat`, a
  plain `Seat`, or a custom driver part (many games weld the character to a
  chassis part with no seat at all — check `RootPart:GetRootPart()` and the
  assembly the character belongs to).
- Resolve the vehicle: the seat's assembly root part, and the model above it.
- Take network ownership where the executor allows it
  (`sethiddenproperty` / `setnetworkowner` equivalents are not available
  client-side; what usually works is that the driver already owns the assembly).
- Then drive it by whichever of these the game leaves open, same philosophy as
  the existing five modes — the game decides which one survives:
  - `VehicleSeat.MaxSpeed` / `.Torque` / `.TurnSpeed` (naive, often clamped)
  - the wheels' `HingeConstraint.AngularVelocity` and `.MotorMaxTorque`
  - a `LinearVelocity` / `AssemblyLinearVelocity` write on the chassis root
  - a multiplier applied to the assembly's current velocity, which is the one
    that respects the player's own steering and reads as "faster car" rather
    than "car being dragged"
- Give it its own multiplier control, not the walking speed slider. "2×" is what
  a driver wants; "180 studs/s" is not.

Decide with the user whether this is a `Vehicle` section inside `Speed` or a new
`src/modules/Movement/VehicleSpeed.luau`. My read: a new module. The two share
nothing but the word "speed", and Speed's five modes are already at the limit of
what one card should explain.

Report which technique actually worked in which game. That is the finding.

### 2. Player ESP is not fluid, and the box grows

Two separate causes, and the first one is not in your files — coordinate.

- **Not fluid.** Every module loop runs on one `Heartbeat` connection
  (`ARandomMenu.luau:4041`, `TaskManager`). Heartbeat fires *after* the frame is
  drawn, so the overlay always shows the previous frame's camera — it swims
  behind the world whenever the player turns. The fix is a second bucket on
  `RenderStepped` and a `Module:Render(callback)` beside `Module:Loop`. That is
  the shell and `src/core/Framework.luau`, so **agent A does it**; your part is
  moving `PlayerESP`, `ItemRender` and anything else that draws to the screen
  onto `:Render`, and dropping the `Refresh interval` accumulator (which
  throttles the redraw to ~33 Hz on top of the lag) to a "draw every frame"
  default.
- **The box grows.** `Render:ModelRect` (agent A's file, but the diagnosis is
  yours to confirm) projects the eight corners of `model:GetBoundingBox()` and
  takes the screen-space extremes. An oriented 3D box seen from close up
  projects far wider than the character's silhouette, and the near face grows
  super-linearly as you approach — which is exactly "the square keeps getting
  bigger". A billboard box fixes it: take the target's centre and height, build
  four corners from the *camera's* right and up vectors, project those. It scales
  smoothly with distance, stays screen-aligned, and cannot balloon.

### 3. Whatever else the user reports from playing

The user is the only source of truth we have for feel. When a report arrives —
game, feature, expected, actual — it goes to the front of your queue.

## Standing work, after those

From `docs/notas-B.md`, in this order because it is the order that keeps
everything working:

1. `Auto Play ID` out of MM2 into `src/modules/Utility/` — it contains no MM2
   fact at all, it is a Utility card in the wrong file. Pure move.
2. `Sprint` out of MM2. Pure move.
3. `Loop All Interact`, `Hide Names`, `Silence` — need the game bridge to hand
   over their containers.
4. `Role Fling` last, it needs Fling's motor shared.

Also: two dead `state` keys left in your files, `state.mm2TrajectoryCalibration`
and `state.projectileSettings`. Delete them and the writes that feed them.

## Definition of done for any change

The gate passes, and there is a test in `tools/test/suites/` that would fail if
you reverted your fix. If the test cannot be written because the mock is
missing something, say so in your reply — the missing mock is agent C's job and
they need to hear about it.
