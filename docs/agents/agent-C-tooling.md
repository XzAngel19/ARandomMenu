# Agent C — the harness, and holding the port to its spec

Read `docs/agents/RULES.md` first. Sync before anything else; the recipe is in
rule 12.

You own **`tools/**`** and **`docs/**`**, with two changes:

- `docs/agents/*` is the integrator's.
- **The suites that test a module now belong to agent D.** A fix and the test
  that proves it have to land in the same green commit. You keep the harness
  itself — `run.luau`, `Roblox.luau`, `Host.luau`, `check_contracts.py`,
  `validate.sh` — and the suites that test the shell, the libraries and the
  interface.

Heads up on two files: I edited `tools/test/suites/movement-engines.luau` for
the PhysicsSpeed → VehicleSpeed rename, and `tools/test/suites/floating.luau` so
it starts the window manager before the overlays. Both had to be atomic with a
change on the other side of the fence. Sync before you touch them.

## The only thing that matters right now

The menu is being turned into a Roblox port of the Wurst Client and the
interface is being rebuilt this week. Everything below serves that. Anything
else waits.

## 1. The parity spec — do this first

`docs/design/prototype/index.html` is a working ClickGUI and it is the
specification for the port. Every number in its CSS is a decision: 22 px rows,
22 px title bars, a 2 px gap, a 1 px border, a 5 px slider bar with a 7×11 knob,
11.5 px labels, 4 px corners, 0.86 body opacity, a 400 ms tooltip delay,
transitions between 0.10 s and 0.18 s.

Build two things:

1. **`docs/design/prototype/spec.json`**, produced by a script that parses the
   prototype's `:root` block and its component rules. Generated, not hand-copied
   — a hand-copied file is wrong within a week.
2. **A gate step** that reads it and holds the Luau side to it. The shape tokens
   already exist as `ThemeEngine.shape` in the shell (`opacity`,
   `tooltipOpacity`, `radius`, `rowHeight`, `borderThickness`, `maxHeight`,
   `scale`); the rest will arrive as named constants in `Widgets.luau` and
   `WindowManager.luau` as they are ported. Any number in the spec with no
   counterpart, or a counterpart holding a different value, fails the step and
   names both sides.

I am porting the row and the category windows now. Without this, "matches Wurst"
means whatever the last person to look at it thought, and it drifts.

## 2. Suites ahead of the code, not behind it

These are the pieces landing over the next few days. Writing the tests first is
the fastest way to keep the rebuild from breaking what already works — and you
can write them now, because the behaviours are decided and visible in the
prototype.

- **Windows.** `state.windows` exists: `Create`, `Adopt`, `Get`, `Raise`,
  `Reclamp`, `SetMenuVisible`. Open several, move one, collapse another, pin a
  third, serialise, boot again from that config, assert the layout came back.
  Assert no window can end up fully off-screen. Assert snapping lands flush on a
  viewport edge and on another window's edge within eight pixels, and does not
  snap at nine.
- **Theme.** Extend `clickgui.luau`: assert every one of the 22 tokens is bound
  somewhere after a boot, and that `Apply` leaves no instance holding a colour
  from the previous preset.
- **The row.** When it lands: enabled fills the row, the triangle only exists
  when the module has options, expanding pushes the rows below down, and the
  kernel's `Show` rules still hide and reveal inside an expansion while the
  window's height follows. Player ESP has the deepest rule tree in the menu.
- **The HUD list.** Agent D is giving every module a `card:SetStatus(text)`.
  Assert the list contains exactly the enabled cards, that a status appears in
  brackets, and that a `nil` status prints the bare name.

## 3. Wurst's voice

`assets/wurst/translations/en_us.json` is already vendored. Turn it into
`docs/wurst-voice.md`: the naming conventions it reveals — how a hack is named
versus a setting, when a description warns instead of explaining, sentence
length, capitalisation — plus a table of the Wurst hacks that have a counterpart
here and what Wurst calls them.

Agent D rewrites the tooltips from it. You produce the reference. Do not
translate their text: their descriptions are about Minecraft, and a tooltip
mentioning bedrock in a Roblox menu is worse than a plain one.

## Not now

More mock gaps, more contracts, the workflow header. All still true, none of
them make the menu look like Wurst today.

## Definition of done

The gate prints `All checks passed.`, the bundle is regenerated with
`python3 tools/bundle.py` and committed if the stamp moved, and every increment
is pushed on its own.
