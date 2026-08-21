# Agent D — modules and games

You are joining a project already in flight. This document is everything you
need; read it end to end before running anything, then read
`docs/agents/RULES.md`, which is short and every line of which has already cost
somebody work.

## What this is

A menu for Roblox executors — a single Luau script a player loads with
`loadstring`, which draws a GUI over whatever game they are in and gives them
around 38 features: speed, flight, ESP, aim assist, protection against other
people's exploits, plus per-game modules for Murder Mystery 2, Volleyball
Legends, The Roblox Soccer game, MVSD and BedFight.

It is being rebuilt as a deliberate Roblox port of the **Wurst Client** from
Minecraft — the same relationship `VapeV4ForRoblox` has to Vape. The integrator
is doing that rebuild; it touches the shell and the libraries and **none of your
files**, which is exactly why the split is drawn where it is.

The project's standing goal, in the user's words, is a menu that is *fast,
reliable, overpowered and good looking*. The thing it is fighting is this, also
in the user's words:

> **Code slop** is low-quality, AI-generated code that compiles and passes basic
> tests, but is architecturally thoughtless, bloated, and hard to maintain. Like
> text-based AI spam, it looks polished on the surface but quietly rots a
> project from the inside.

Most of the work so far has been removing exactly that: the main file went from
16,688 lines to 6,848, startup from about eleven seconds to 0.59, and thirteen
real bugs surfaced that a green test suite had been hiding.

## What you own

**`src/modules/**`** and **`src/games/**`**. Nothing else. Not the shell, not
`src/core/`, not `src/library/`, not `tools/`, and never `runtime/bundle.luau`
(it is generated; the integrator regenerates it).

If you need a change in a file you do not own, write it in `docs/requests/D.md`,
**say it in your chat reply as well**, and work around it meanwhile.

## Getting the gate running, first thing

Before writing code, prove you can push (`RULES.md` explains why this matters):

```
git commit --allow-empty -m "wip: probe" && git push origin HEAD
```

Then start the Luau build in the background — `/tmp` does not survive between
turns, so you will redo this most sessions, and it takes 2-4 minutes:

```
export PATH="$HOME/.local/bin:$PATH"
command -v cmake >/dev/null || pip3 install --quiet --break-system-packages cmake
rm -rf /tmp/luau-src && git clone --depth 1 -b 0.732 https://github.com/luau-lang/luau.git /tmp/luau-src
cd /tmp/luau-src && cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target Luau.Compile.CLI Luau.Repl.CLI Luau.Analyze.CLI -j4
```

The gate, which must print `All checks passed.` before every push:

```
LUAU_DIR=/tmp/luau-src/build bash tools/validate.sh
```

21 steps, 662 checks: strict type analysis, a bundle rebuild, eleven contracts,
and a test harness that boots the real shell headless.

## How a module works

A module is one file in `src/modules/<Category>/`, where category is one of
Combat, Movement, Protection, Spoof, Utility, Visuals. It exports `init(context)`
and `destroy()`, builds a card, and hangs its controls off it:

```lua
local card = context.framework.Categories.Movement:CreateModule({
    Name = "Speed",
    Category = "Movement",
    Order = 1,
    Tooltip = "Move faster, by whichever of five methods this game lets through.",
    Function = function(enabled: boolean): ()
        if not enabled then return end
        card:Loop(function(deltaTime: number): ()
            -- runs every Heartbeat while the card is on
        end)
        card:Event(someSignal, function() end)
        card:Clean(function() end)      -- runs when the card turns off
    end,
})

card:CreateDropdown({Name = "Mode", List = {"A", "B"}, Index = 1})
card:CreateSlider({Name = "Speed", Min = 16, Max = 200, Default = 32})
card:CreateToggle({Name = "Wall check", Default = true,
    Show = {Option = "Mode", Values = {"B"}}})   -- only visible while Mode is B
```

Anything registered through `:Loop`, `:Event` or `:Clean` is torn down for you
when the card turns off or the menu is destroyed. Anything you connect yourself
is a leak, and there is a contract that will catch it.

`Show` rules: a list of conditions that must all hold. `Invert = true` flips one.
Omitting `Values` means "while that option is on". A rule naming an option that
starts with `__` is the deliberate always-false sentinel used to retire a row.

**Read `src/modules/Movement/Speed.luau` before writing anything.** It is the
house style at its best: five techniques for the same goal, each documented by
*why it exists and when it fails*, not by what the line below does.
`docs/WRITING-MODULES.md` is the long version.

House style: `--!strict`, 4-space indent, explicit types on locals and
parameters, comments in English explaining *why*, written as though the code had
always looked that way.

## Task 1 — Speed does nothing inside a vehicle

The user reported it: a car with pedal controls does not reach the speed the
slider asks for. This is not tuning. `Speed.luau` only ever touches `Humanoid`
and `HumanoidRootPart`, and seated in a `VehicleSeat` the humanoid is welded to
the seat, so:

- `WalkSpeed` is a no-op — the humanoid is not walking.
- `CFrame` and `Teleport` fight the vehicle's constraints, and either lose or
  win badly and rip the character out of the seat.
- `Velocity` and `Impulse` write to an assembly whose wheel motors overwrite it
  in the same physics step.

All five modes are inert in a car. The module never knew vehicles exist.

What is needed, in the same spirit as the existing five — the game decides which
technique survives, not us:

- **Detect the seat.** `humanoid.SeatPart`, and whether it is a `VehicleSeat`, a
  plain `Seat`, or neither: plenty of games weld the character straight to a
  chassis part. `rootPart:GetRootPart()` returning something outside the
  character is the general signal that you are part of a bigger assembly.
- **Resolve the vehicle**: the assembly root, and the model above it.
- **Push it**, by whichever of these the game leaves open:
  - **a multiplier on the assembly's current velocity** — try this first; it
    respects the player's own steering and reads as a fast car rather than a car
    being dragged;
  - the wheels' `HingeConstraint.AngularVelocity` and `.MotorMaxTorque`;
  - `AssemblyLinearVelocity` on the chassis root, rewritten each frame;
  - `VehicleSeat.MaxSpeed` / `.Torque` / `.TurnSpeed`, last, because it is
    usually clamped or recomputed by the game's own script.
- **Its own control.** A driver wants "2×", not "180 studs per second". Do not
  reuse the walking slider.

My read is that this is a new `src/modules/Movement/VehicleSpeed.luau` rather
than a sixth mode: the two share nothing but the word "speed", and Speed's card
is already at the limit of what one card can explain. Argue if you disagree.

**Report which technique actually worked in which game.** That is the finding,
and it goes in your chat reply, not only in a file.

## Task 2 — Player ESP: your half

The user reported that the ESP is not fluid and the box keeps growing. Two
separate causes, and one of them is not yours.

- **Not fluid.** Every module loop in the menu runs on a single `Heartbeat`
  connection (`ARandomMenu.luau:4041`, the `TaskManager`). Heartbeat fires
  *after* the frame is drawn, so the overlay always shows the previous frame's
  camera and swims behind the world when the player turns. The integrator is
  adding a second bucket on `RenderStepped` and a `Module:Render(callback)`
  beside `Module:Loop`. **Your half:** move `PlayerESP`, `ItemRender` and
  anything else that draws to the screen onto `:Render`, and drop the
  `Refresh interval` accumulator, which throttles the redraw to about 33 Hz on
  top of the lag. Wait for `Module:Render` to exist — do not invent your own
  connection.
- **The box grows.** `Render:ModelRect` projects the eight corners of
  `model:GetBoundingBox()` and takes the screen-space extremes. An oriented 3D
  box seen from close up projects far wider than the silhouette, and its near
  face grows super-linearly as you approach — which is exactly "the square keeps
  getting bigger". The fix is a billboard box: the target's centre and height,
  four corners built from the *camera's* right and up vectors, those projected.
  `Render.luau` is not your file. Confirm the diagnosis, put it in
  `docs/requests/D.md` and in your reply, and the integrator changes it.

## Task 3 — what the HUD list needs from every module

This one is yours alone and it is what will make the menu read as Wurst.

Wurst draws a list down the right edge of the screen of every hack that is
currently on, and the good ones say more than their name:
`AutoTotem [0 totems]`, `Criticals [Packet]`. Ours is being built now and it can
carry the same thing, but only the module knows what its own bracket should say.

Give every module that has a meaningful runtime state an optional short status
string — under about sixteen characters, recomputed no more than a few times a
second, `nil` when there is nothing worth saying:

```
Speed [CFrame ×2]        the mode that is actually running, and the multiplier
Player ESP [12]          how many targets are being drawn
Kill Aura [3 in range]   what it can currently see
Fly [Velocity]           which of the four models is in use
Anti-Fling [standing by] the distinction that matters: armed versus acting
Auto Farm [3 targets]
```

The integrator will publish the exact hook — most likely `card:SetStatus(text)`
plus a `Status` field on the card definition. Wait for it, then do a pass over
all 38 modules. Where a module has nothing true and short to say, say nothing;
a bracket that always reads `[on]` is noise.

While you are in every file anyway, fix the tooltips. Agent C is producing
`docs/wurst-voice.md` from Wurst's own `en_us.json` — a thousand descriptions
written in one voice over eleven years. Ours were written by several hands and
it shows. Match the voice, do not copy the text: their descriptions are about
Minecraft, and a tooltip mentioning bedrock in a Roblox menu is worse than a
plain one.

## Task 4 — whatever the user reports next

The user is the only source of truth for how the menu feels. 662 checks say the
code does what it claims; they say nothing about playing it. A report — game,
feature, expected, actual, console output — goes to the front of your queue,
ahead of everything below.

## Standing work

`docs/notas-B.md` is a card-by-card analysis of MM2 and an audit of TRS and VD
left by your predecessor. It is accurate; read it. From it, in this order,
because it is the order that keeps everything working while it happens:

1. **`Auto Play ID` out of MM2** into `src/modules/Utility/`. It contains no MM2
   fact at all — it is a Utility card in the wrong file. Pure move.
2. **`Sprint` out of MM2.** Pure move.
3. **`Loop All Interact`, `Hide Names`, `Silence`** — these need the game bridge
   to hand over their containers first.
4. **`Role Fling`** last: it needs Fling's motor shared.

MM2 is 4,480 lines and that is the only reason it is being split. What is
genuinely MM2 stays: Shoot, Knife Aura, Trajectory Calibration, Instant Role
Notify, Always Show Timer.

Two dead `state` keys also live in your files —
`state.mm2TrajectoryCalibration` and `state.projectileSettings`. Delete them and
the writes that feed them.

## The rename

The product is becoming **Wurst**. Your files carry the old name in log prefixes
and warnings — `RTM:`, `Random Testing Menu`, `ARandomMenu`. Do not sweep them
yet: the integrator is putting the product name behind a single constant, and
your job afterwards is to read it from there rather than to type a new string
120 times. Wait for it to land.

## Definition of done, for anything

The gate passes, **and** there is a test in `tools/test/suites/` that would fail
if your fix were reverted. If you cannot write it because the mock is missing
something, name the mock and what it is missing — that is agent C's lane and
they only find out if you say so.

## Three traps this repository has already fallen into

- **A green gate proves nothing ran, not that it worked.** Five modules were
  dead for a week, 110 tests were never executed by the runner, and 186 lines
  were unreachable — all green. When you fix something, prove the fixed path is
  reached.
- **Do not call a host function that does not exist.** Those five dead modules
  called `host.addFeatureTooltip`, which was never published, so `init` threw.
  A contract catches it now; read what it tells you instead of arguing with it.
- **A refactor does not change behaviour.** If you move code, the menu does
  exactly what it did before and you say so. A behaviour change is a separate
  commit with a message that says what changed and why. A commit that does both
  is a commit nobody can review.
