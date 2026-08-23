# Requests for agent D — architecture phase

Work order from A (integrator). Base on the current tip of
`arena/01a02c8a-arandommenu`; hand back a hash, A merges. No PRs, no main,
no force-push. Validate must end "All checks passed."

## Standing verdicts (do not regress)

Code face, 16 px type, blur on, RightShift = menu, Navigator only behind
the dock magnifier, zero console output (print/warn are gated shadows —
never call the real ones), empty choosers stay blank, 43 modules frozen,
identity frozen, Animation Changer ships its own pack catalog (no
catalog search at boot), Custom ID + Save ID pattern in the Spoof pair.

## D1 — Module authoring contract, written and enforced

The goal the user set: anyone should be able to create a module, or
re-skin the whole GUI, without touching anything else. Today that
contract exists only as folklore. Write `docs/architecture/modules.md`:

- the exact `Module.init(context)` surface a module may touch (framework
  categories, Create* builders, host services, Clean/Event) and what it
  must never touch (state internals, ScreenGui, configData outside the
  documented keys);
- the option-builder catalog with one honest example each (toggle,
  slider, dropdown, list, textbox, bind, color, button, note);
- teardown rules: everything a module creates dies in Clean/destroy —
  prove it by pointing at the teardown suite.

Then audit all 43 modules against your own document and fix violators
in your lane. Every deviation you cannot fix is a line item with a file
and a reason.

## D2 — GUI-swap seam audit

The renderer must be replaceable. Framework and modules may know
NOTHING about pixels: grep your lane for modules reaching into
row/label/window internals and route them through the documented
builders instead. Report the seams that remain (Cards/Widgets contracts
the shell owns) in `docs/requests/D-to-A-visual.md` so A can harden
them.

## D3 — Anti-slop copy pass, your lane

Every player-visible string in Furniture/SettingsPage/ClickGui/Cards
and the 43 modules: tooltips read like a person wrote them (short,
concrete, no "allows you to", no "simply", no filler adverbs), notifies
are lowercase-terse the way the Spoof pair now is ("saved 123", "no
character yet"), no row label ends in a period, no two rows say the
same thing in different words. List every string you changed in the
report.

## D4 — Next handoff: useful options and plain English

Base on the current tip of `arena/01a02c8a-arandommenu`; do not re-land D1–D3.

1. Audit every remaining player-visible option across the 43 universal modules.
   For each row ask whether it changes behavior, whether a safe default can
   replace it, and whether two rows express one decision. Remove only proven
   redundancy; preserve config keys for shipped behavior.
2. Finish the English pass in `src/library/**`, `src/modules/**` and
   `src/games/**`: short concrete tooltips, sentence case, no AI filler, no
   Spanish runtime strings. Do not rewrite historical third-party references.
3. Report direct service/state access that can move behind the documented
   module context without inventing wrappers for one-off calls.
4. Audit touch actions after the shortcut moved to the left lane. The slot must
   remain understandable, must not cover centred titles, and must not recreate
   the removed wide launcher/search surface.
5. List optional or experimental features that should be removed, finished or
   moved out of the default inventory. Do not change the frozen count without
   integrator approval.

## D5 — Capture follow-up: mobile action finish

Review the shared `MobileActionEditor` against the YARHM references already
listed in the authoring guide. Keep one panel, not one settings window per
button. Audit touch spacing, labels, press feedback and the 36–120 px range on
a real phone capture. Do not add decorative controls: Size, Opacity, Remove,
Reset and Done are the complete surface. Report any visual issue rather than inventing
another global mobile-settings page.

## D6 — Next architecture pass: module-owned state

The hard gate now blocks GUI-root and console reach-ins, but universal modules
still contain direct `host.state` access. Classify every use into:

- a module-local value that should leave global state;
- a real cross-module service that needs a documented context API;
- a temporary compatibility bridge with a named removal condition.

Start with Auto Clicker menu visibility, TriggerBot aim ray, Click Teleport key
capture, Fly/Speed movement input, mobile action placement, Friend List target
protection and the FOV/PlatformStand controllers. Do not wrap every state field
one-for-one; reduce the surface. Extend the conformance gate only after the
migration has a clean allowlist.

## D7 — Next run: remove direct host-state coupling

Base on the latest `arena/01a02c8a-arandommenu`. Runtime/docs and the tests that
prove your migration; do not restyle GUI surfaces in this lane.

Work in this order:

1. Move module-owned values out of `host.state` and into each module's local
   runtime (`InfiniteJump`, `Fullbright`, projectile calibration, Remote Logger,
   Improve FPS and similar single-owner values).
2. Publish small context services only for real cross-module contracts:
   movement input, aim ray, menu visibility, mobile-action placement, protected
   targets, FOV ownership and PlatformStand ownership. Group related methods;
   never create one wrapper per old state field.
3. Migrate callers, remove obsolete state fields and document the final context
   surface in `docs/architecture/modules.md`.
4. Extend module conformance with a narrow allowlist. New direct `host.state`
   access must fail; temporary bridges need an owner and removal condition.
5. After the surface is smaller, introduce concrete `Runtime`, `ModuleContext`
   and service types for the migrated path. Do not attempt a repository-wide
   `any` purge in the same commit.
6. Preserve all visible behavior, config keys, the 43-module inventory and
   teardown semantics.

Report: commit hash, state accesses before/after, local values removed from the
shell, services introduced, remaining bridges and types added.

## D8 — Module expansion review

Base on the latest integration tip with Chams, Arrows, NPCESP, WallHop and
SpinBot. Runtime/docs plus focused tests in your lane.

1. Compare each implementation with VapeV4's corresponding behavior and Roblox
   engine semantics. Keep this project's service/render architecture; do not
   copy Vape code.
2. Resolve the intentional overlap between PlayerESP's embedded Chams option and
   the standalone Chams card. Recommend one clear ownership and migrate without
   silently changing existing configs.
3. Audit target policy: friends, teammates, NPC classification, alive checks,
   max distance, respawn and streamed descendants.
4. Audit teardown/property restoration under disable, destruct, death and
   character replacement. No Highlight, render set, angular velocity or jump
   callback may survive.
5. Keep options lean. Every setting must change behavior; remove speculative
   modes instead of padding the module.
6. Report field-test debt separately for physics-sensitive WallHop and SpinBot.

## D9 — WallHop and combat-module design review

1. Field-review the fixed WallHop sequence: probe spacing, edge classification,
   offset order, cooldown, character replacement and server correction. Defaults
   are the algorithm; do not expose implementation constants as settings.
2. Compare requested Reach behavior with existing Hitboxes, Interact Extender,
   weapon activation and game-specific remotes. Recommend one non-duplicated
   ownership before adding another card.
3. Specify a transparent aim-assist contract if useful (target selection,
   visibility, FOV and explicit camera/input behavior). Do not introduce
   metamethod hooks, remote spoofing or anti-cheat evasion into the shared core.
4. Keep the option count small and report physics/game-specific limitations
   honestly rather than labeling them bypass modes.

## Rules

Suites that pin your surfaces update in the same commit. Report: hash,
branch, validate counts, per-item summary, honest debt.
