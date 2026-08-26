# Agent prompts — UI reliability and combat regression review

These are the follow-up review briefs for the next C/D pass. All code, UI
labels and runtime strings must remain English. Work from the latest
`arena/01a03bca-arandommenu` tip and return a commit hash without opening a PR.

## Agent C — UI and numeric regression gates

> Read `docs/agents/RULES.md`, `docs/architecture/ui-input-and-numeric.md`, and
> `docs/architecture/modules.md`. Test the latest shell against a first-person
> cursor state: opening the menu must force `MouseBehavior.Default` and show
> the icon, repeated game writes of `LockCenter` must be reclaimed, and closing
> or destruct must restore the exact baseline. Test both single-choice and
> multi-choice green-arrow toggles: opening the same popup twice must leave it
> closed, while opening another row must close the first.
>
> Test free finite numeric TextBoxes separately from pointer drags. Typed and
> stored values outside the rail must survive; pointer drags must still snap to
> the rail; NaN and infinity must be rejected. Test normal Aim Assist
> smoothing at 0, a middle value and 100, and verify that the control is hidden
> in Aimbot. Aimbot must use fixed zero smoothing, expose a releasable Sticky
> target control, and use its lock policy rather than merely changing a label.
> Do not make missing behavior a green check, and do not add screenshot uploads
> or global hooks.
>
> Run the full validation command, report the exact count and any mock debt,
> then hand the integrator the commit hash.

## Agent D — combat and module behavior review

> Read `docs/architecture/module-audit-45.md`,
> `docs/architecture/reach-ownership.md`, and
> `docs/architecture/targeting-and-learning.md`. Field-review Kill Aura's
> current single `Reach` contract: it must select without a cursor lock, use
> the full 360-degree default scan, honor Max targets, Friend List, team,
> visibility and NPC policy, and restore all owned highlights and connections
> on disable and character replacement. Confirm that Contact damage and weapon
> discovery are real behavior, not decorative options. If a game rejects the
> activation, report the game-specific adapter requirement instead of adding a
> universal remote or metamethod hook.
>
> Review Aim Assist, TriggerBot, Hitboxes, PlayerESP and NPCESP for shared
> Team/Faction normalization and NPC lifecycle. Check every other universal
> module for teardown, stale property ownership and options that no code reads.
> Keep the inventory fixed. Do not add anti-cheat evasion, silent global hooks,
> remote spoofing or permissive tests.

## Agent A — integration checklist

> Before integrating C/D, run `tools/preflight.sh` with the fixed session
> branch, compare their base tip with the remote branch, and inspect bundle
> freshness. Reconcile conflicts without losing the 45-card inventory,
> alphabetic category ordering, cursor ownership, popup toggle semantics or
> finite free-number contract. Run local validation and GitHub Actions; report
> the exact check count, commit hashes and honest field-test limitations.
