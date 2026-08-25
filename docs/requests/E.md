# Agent prompts — targeting, Reach and Learning follow-up

These prompts are ready to paste into the project agents. They are written for
this repository's fixed integration branch. All code, UI text and runtime
strings produced by an agent remain English.

## Agent C — regression and data-contract audit

> You are agent C on `XzAngel19/ARandomMenu`, owning tests and tooling. Work
> only on your assigned branch and never push to `main`. Start by reading
> `docs/agents/RULES.md`, `docs/architecture/modules.md`, and
> `docs/architecture/targeting-and-learning.md`.
>
> Audit the current `Aim Assist`, `Targeting` library and `Learning` module.
> Add focused headless tests for: target sorting, FOV rejection, teammate and
> Friend List rejection, visibility rejection, menu/input pause, camera-only
> writes, complete teardown, unavailable screenshot capability, manual-only
> capture and metadata path handling. Keep the tests strict: do not turn a
> missing executor capability into a passing fake capture.
>
> Verify the manifest, fallback manifest, bundle stamp, inventory snapshot and
> parity matrix stay synchronized. Do not add hooks, remote rewriting,
> screenshot uploads or anti-cheat bypass logic. Report the exact check count,
> failures, and any mock debt. Hand back a commit hash for the integrator.

## Agent D — Reach ownership and supported-game review

> You are agent D on `XzAngel19/ARandomMenu`, owning gameplay modules. Read
> `docs/agents/RULES.md`, `docs/agents/agent-D-gameplay.md`, and
> `docs/architecture/targeting-and-learning.md` before changing code.
>
> Review the requested Reach behavior against `Hitboxes`, `KillAura`,
> `InteractExtender`, `Weapons`, and the game modules. Do not add a duplicate
> card. `Interact Extender` currently owns ProximityPrompt and ClickDetector
> reach; decide whether that name should stay or be migrated with a compatibility
> key. If combat Reach is proposed, define an explicit supported-game adapter
> contract first and document the server/physics limitations. Do not implement
> `hookfunction`, `hookmetamethod`, remote spoofing, wallbang, hitbox inflation
> or anti-cheat evasion in the universal core.
>
> Field-review WallHop and SpinBot again after the targeting changes. Prove
> character replacement, death, server correction and teardown. Keep settings
> lean and do not change the frozen inventory without an integrator-approved
> snapshot update. Hand back a commit hash, validation count and honest field
> debt.

## Agent C — full 45-module audit

> Run the complete manifest against the headless boot, settings reopen and
> teardown suites. For every card, compare the declared options with the code
> path that reads them, verify that disable/destruct restores borrowed
> properties, and record real field-test debt instead of adding permissive
> checks. Pay special attention to the new alphabetic category order, Other
> placement for Anti-Fling/Fling/Lag Switch, NPC target policy and Team/Faction
> normalization. Do not change gameplay semantics in the test lane and do not
> add global hooks, remote spoofing or screenshot upload behavior.
>
## Agent A — integration and isolation review

> You are agent A on `XzAngel19/ARandomMenu`, the integrator. Stay on
> `arena/01a02c8a-arandommenu`, run preflight before committing, and read
> `docs/architecture/targeting-and-learning.md`.
>
> Integrate C/D commits only after checking that `Targeting` remains read-only
> with respect to game objects, Aim Assist remains camera-only, and Learning
> remains manual, local and upload-free. Inspect every new `host`/service field
> against `Framework.luau`, the runtime environment and `tools/test/Host.luau`.
> Keep the existing MVSD-specific Silent Aim isolated; do not generalize its
> hooks into a universal module. Run the complete validation command, record
> the exact pass/fail count and push only the fixed session branch.
