# Requests for agent C — architecture phase

Work order from A (integrator). Base on the current tip of
`arena/01a0262f-arandommenu`; hand back a hash, A merges. No PRs, no main,
no force-push. Tools, tests and docs only.

## Standing verdicts (do not regress)

Zero console output by default: the shell shadows print/warn behind
`getgenv().ARANDOMMENU_DEBUG` and injects the shadows into the module
environment. Boot waits for LocalPlayer (teleport reinjection lands
before the player exists). Teleport persistence chains through
queue_on_teleport with genv flags ARANDOMMENU_STOPPED /
ARANDOMMENU_TP_QUEUED. Animation Changer ships 16 built-in packs
(`Module.builtinPacks`).

## C1 — Silence gate

A permanent suite check: boot the shell with print/warn captured in the
mock env and assert zero calls without the debug flag, plus at least one
with it. Then a validate step that greps the bundle for direct
`realPrint`/`realWarn` style escapes outside the shell's own gate, so a
future module cannot reintroduce console noise.

## C2 — Teleport-boot regression

The 422 crash from the field: boot must survive `Players.LocalPlayer`
being nil at chunk start. Extend the mock so `world.localPlayer` can be
published N ticks late, and assert the shell boots anyway. Also assert
the queued snippet contains the game-loaded wait and compiles.

## C3 — Architecture conformance gates

Support D's module contract (docs/architecture/modules.md once D lands
it) with teeth: a validate step that walks src/modules/** and rejects
(a) direct ScreenGui/PopupLayer reach-ins, (b) configData keys outside
the documented namespaces, (c) bare print/warn additions. Start in
report-only mode if the tree is not clean; flip to hard-fail in the
same commit the tree becomes clean.

## C4 — Save ID / built-in pack coverage

Suite checks: Save ID appends to the persisted CSV once (no dupes),
saved entries appear in the chooser after Refresh, the 16 built-in
packs each carry seven slots (already pinned in spoof.luau — extend to
the EmotePlayer saved-id path).

## Rules

Validate ends "All checks passed." with your new checks counted.
Report: hash, branch, validate counts, new check count, debt.
