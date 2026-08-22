# Agent D — Wurst's names, and what every module says it is doing

Read `docs/agents/RULES.md` first, then sync (rule 12).

You own `src/modules/**`, `src/games/**`, and the suites that test them. Run
`python3 tools/bundle.py` when the stamp goes stale and commit both files.

## The decision that changes your queue

The menu is a port of Wurst now, the way `VapeV4ForRoblox` is a port of Vape —
the same names, the same behaviours, the same defaults, not an interpretation.
The interface is being rebuilt for that. Your half is what the interface
displays.

## 1. Finish the status pass — 31 modules to go

`card:SetStatus(text)` works on all thirty-eight now; the stand-in card has it
too, so the legacy twenty no longer throw. Seven are done and they read right.

Keep the bar you set: under sixteen characters, true at the moment it is read,
and `nil` when there is nothing worth saying. Wurst's own list is the model —
`AutoTotem [0 totems]`, `Criticals [Packet]`. It says the *mode* or the *count*,
never that the module is on.

## 2. Wurst's names for our modules

This is the one that will make the menu read as Wurst, and only you can do it.

`assets/wurst/translations/en_us.json` is vendored and contains every hack name
in the client. Agent C is turning it into `docs/wurst-features.md`. Go through
our thirty-eight cards and, where Wurst has the same idea, **take Wurst's
name**: what we call Fly, Wurst calls Flight; what we call Player ESP is closer
to its PlayerESP; No Fall is NoFall; Anti-AFK is AntiAFK. Wurst runs its names
together and does not space them, and that is part of how its window looks.

Three rules:

- A rename changes the display name, not the `configKey`. Changing the key
  orphans every saved config, and the player's settings are not ours to lose.
- Where Wurst has no counterpart, keep our name and say so in your reply.
- Where the mapping is a stretch, do not force it. A Roblox-only module wearing
  a Minecraft name is worse than an honest one.

Every rename lands with its suite in the same commit, since both are yours.

## 3. Finish Vehicle Speed

Still open: strip the four character-side sites that re-implement `Speed.luau`,
cut the modes that only make sense for a walking player, keep the per-instance
restore tables, and add the multiplier with base speed separated from the excess
so nothing compounds frame over frame. The suite's sixteen old option
expectations are yours to change in the same commit.

## 4. Finish the ESP

Land what you have, then delete the accumulator and the `Refresh interval`
option, suite included.

## Not now

The MM2 split, the dead `state` keys, the MM2 folder literal, migrating the
twenty legacy modules to `CreateModule`. All real, none of them make the menu
Wurst today.
