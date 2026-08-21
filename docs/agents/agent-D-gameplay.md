# Agent D — gameplay: modules and games

Read `docs/agents/RULES.md` first, in full. This brief is the rest.

You own **`src/modules/**`** and **`src/games/**`**, and nothing else. You do
not touch the shell, `src/core/`, `src/library/`, `tools/`, or
`runtime/bundle.luau`. The menu's chrome is being rebuilt in parallel by the
integrator; every file you own is untouched by that work, which is why these are
your files.

Your predecessor's analysis is in `docs/notas-B.md` — a card-by-card
classification of MM2 and an audit of TRS and VD. It is still accurate, read it.

## Context you need in one paragraph

This is a Roblox executor menu. A module is a file in `src/modules/<Category>/`
exporting `init(context)` and `destroy()`; it builds a card through
`framework.Categories.<Category>:CreateModule{...}` and adds controls with
`:CreateToggle`, `:CreateSlider`, `:CreateDropdown`, `:CreateColor`,
`:CreateSection`, `:CreateNote`. Work happens inside `Function = function(enabled)`,
loops through `module:Loop(fn)`, connections through `module:Event(signal, fn)`,
cleanup through `module:Clean(fn)` — anything registered that way is torn down
for you. A control can be hidden by another control's value with
`Show = {Option = "Mode", Values = {"CFrame"}}`. `docs/WRITING-MODULES.md` is
the long version. Read `src/modules/Movement/Speed.luau` before writing
anything; it is the house style at its best.

## Task 1 — Speed does nothing in a vehicle

Reported by the user: a car with pedal controls does not reach the speed the
slider asks for. It is not a tuning problem. `Speed.luau` only ever touches
`Humanoid` and `HumanoidRootPart`. Seated in a `VehicleSeat` the humanoid is
welded to the seat, so:

- `WalkSpeed` is a no-op — the humanoid is not walking.
- `CFrame` and `Teleport` fight the vehicle's constraints and usually lose, or
  win badly and rip the character out of the seat.
- `Velocity` and `Impulse` write to an assembly whose wheel motors overwrite it
  in the same physics step.

So all five modes are inert inside a car. The module never knew vehicles exist.

What is needed, in the same spirit as the existing five modes — the game decides
which technique survives, not us:

- **Detect the seat.** `humanoid.SeatPart`, and whether it is a `VehicleSeat`, a
  plain `Seat`, or neither: plenty of games weld the character to a chassis part
  with no seat at all. `rootPart:GetRootPart()` returning something outside the
  character is the general signal that you are attached to a bigger assembly.
- **Resolve the vehicle**: the assembly root, and the model above it.
- **Then push it**, by whichever of these the game leaves open:
  - `VehicleSeat.MaxSpeed` / `.Torque` / `.TurnSpeed` — the naive one, usually
    clamped or recomputed by the game's own script.
  - the wheels' `HingeConstraint.AngularVelocity` and `.MotorMaxTorque` — works
    on most community car chassis.
  - `AssemblyLinearVelocity` on the chassis root, rewritten each frame.
  - **a multiplier on the assembly's current velocity** — this is the one that
    respects the player's own steering and reads as a fast car rather than a car
    being dragged. Try it first.
- **Its own control.** A driver wants "2×", not "180 studs per second". Do not
  reuse the walking slider.

My read is that this is a new `src/modules/Movement/VehicleSpeed.luau` rather
than a sixth mode: the two share nothing but the word "speed", and Speed's card
is already at the limit of what one card can explain. Argue if you disagree.

Report **which technique actually worked in which game**. That is the finding,
and it belongs in your chat reply, not only in a file.

## Task 2 — Player ESP: your half

Two causes, and one of them is the integrator's.

- **It is not fluid.** Every module loop runs on one `Heartbeat` connection
  (`ARandomMenu.luau:4041`, `TaskManager`). Heartbeat fires *after* the frame is
  drawn, so the overlay always shows the previous frame's camera and swims
  behind the world when the player turns. The integrator is adding a second
  bucket on `RenderStepped` and a `Module:Render(callback)` beside
  `Module:Loop`. **Your half**: move `PlayerESP`, `ItemRender` and anything else
  that draws to the screen onto `:Render`, and drop the `Refresh interval`
  accumulator, which throttles the redraw to ~33 Hz on top of the lag. Wait for
  `Module:Render` to exist — do not invent your own connection.
- **The box grows.** `Render:ModelRect` projects the eight corners of
  `model:GetBoundingBox()` and takes the screen extremes. An oriented 3D box
  seen from close up projects far wider than the silhouette, and its near face
  grows super-linearly as you approach — which is exactly "the square keeps
  getting bigger". The fix is a billboard box: the target's centre and height,
  four corners built from the *camera's* right and up vectors, those projected.
  `Render.luau` is not your file — confirm the diagnosis, then say so in your
  reply and in `docs/requests/D.md`, and the integrator changes it.

## Task 3 — whatever the user reports next

The user is the only source of truth for how the menu feels. A report — game,
feature, expected, actual, console output — goes to the front of your queue,
ahead of everything below.

## Standing work

From `docs/notas-B.md`, in this order, because it is the order that keeps
everything working while it happens:

1. **`Auto Play ID` out of MM2** into `src/modules/Utility/`. It contains no MM2
   fact at all — it is a Utility card that ended up in the wrong file. Pure move.
2. **`Sprint` out of MM2.** Pure move.
3. **`Loop All Interact`, `Hide Names`, `Silence`** — these need the game bridge
   to hand over their containers first.
4. **`Role Fling`** last: it needs Fling's motor shared.

MM2 is 4,480 lines and that is the only reason it needs splitting. Do not split
what is genuinely MM2 — Shoot, Knife Aura, Trajectory Calibration, Instant Role
Notify and Always Show Timer stay.

Also: two dead `state` keys live in your files, `state.mm2TrajectoryCalibration`
and `state.projectileSettings`. Delete them and the writes that feed them.

## Definition of done for any change

The gate passes:

```
LUAU_DIR=/tmp/luau-src/build bash tools/validate.sh    # must print "All checks passed."
```

…and there is a test in `tools/test/suites/` that would fail if you reverted
your fix. If you cannot write the test because the mock is missing something,
say which mock and what it is missing — that is agent C's job and they only find
out if you tell them.

## Two things that will bite you

- A green gate proves nothing ran, not that it worked. This repository has
  shipped five dead modules, 110 tests nobody executed and 186 unreachable
  lines, all green. When you fix something, prove it is reached.
- Do not call a host function that does not exist. Five modules were dead for a
  week because they called `host.addFeatureTooltip`, which was never published,
  and threw in `init`. There is a contract that catches it now — read what it
  says instead of arguing with it.
