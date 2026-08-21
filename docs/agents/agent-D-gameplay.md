# Agent D — modules, games, and their tests

Read `docs/agents/RULES.md` first. Sync before anything else; the recipe is in
rule 12.

You own **`src/modules/**`**, **`src/games/**`**, and **the suites in
`tools/test/suites/` that test them**. That last one is new: a fix and the test
that proves it have to land in the same green commit, and they cannot if
somebody else owns the test. `run.luau`, `Roblox.luau`, `Host.luau` and
`validate.sh` are still agent C's.

**Run `python3 tools/bundle.py` whenever the gate says the stamp is stale, and
commit both files it changes.** Regenerating the bundle is not editing the
shell; the previous rule said otherwise and cost you a finished increment.

## The only thing that matters right now

The menu is being turned into a Roblox port of the Minecraft Wurst Client, and
the interface half is being rebuilt this week. Everything below is menu work.
Anything that is not on this list waits.

### 1. Give every module its HUD-list status — the big one

`card:SetStatus(text)` exists now, on every card. Wurst draws a list down the
right edge of the screen of every hack that is on, and the good entries say more
than their name: `AutoTotem [0 totems]`, `Criticals [Packet]`. Ours reads
`card.Status` and prints it in brackets.

Only the module knows what its bracket should say. Go through all 38 and give
each one a status, or decide it has none:

```
Speed [CFrame ×2]          the technique actually running, and the multiplier
Vehicle Speed [motors]     which of the four ways it found a grip
Player ESP [12]            how many targets are being drawn
Kill Aura [3 in range]     what it can currently see
Fly [Velocity]             which of the four models is in use
Anti-Fling [standing by]   armed versus acting — the distinction that matters
Noclip                     nothing to say; leave it
```

Rules for a good one: under sixteen characters, true at the moment it is read,
recomputed no more than a few times a second, and `nil` when there is nothing
worth saying. `[on]` is noise — the name is already in the list because it is on.

This is the single change that will make the menu read as Wurst rather than as a
list of names, and it is 38 files nobody but you can touch.

### 2. Finish the ESP

You have `:Render` and a default of 0 locally. Land it — run the bundler, run
the gate, push. Then delete the accumulator and the `Refresh interval` option
outright, and update the suite in the same commit, which you now own.

### 3. Finish Vehicle Speed

`VehicleSpeed.luau` is yours and the rename is done. Strip the four
character-side sites that re-implement `Speed.luau`, cut the modes that only
make sense for a walking player, keep the per-instance restore tables, and add
your multiplier the way you described it — base speed separated from the excess,
so nothing compounds frame over frame.

`tools/test/suites/movement-engines.luau` still expects the sixteen old options.
It is your file now: change the expectation in the same commit as the cleanup.

Your four predictions about which technique wins where are on record and they
read right. The user is the only person who can run Roblox; when they report
back, that is the answer.

### 4. Tooltips, in Wurst's voice

Agent C is producing `docs/wurst-voice.md` from Wurst's own `en_us.json` — a
thousand descriptions written in one voice over eleven years. Ours were written
by several hands and it shows. While you are in every module file for the status
pass, fix the tooltip too.

Match the voice, never copy the text: their descriptions are about Minecraft,
and a tooltip that mentions bedrock in a Roblox menu is worse than a plain one.

## Not now

The MM2 split, the dead `state` keys, the MM2 folder literal. All still true,
all still worth doing, none of them make the menu look like Wurst today.

## Definition of done

The gate prints `All checks passed.`, the bundle is regenerated and committed,
and there is a test that would fail if your change were reverted. Push each
increment on its own; never batch.
