# Requests for agent C — architecture phase

Work order from A (integrator). Base on the current tip of
`arena/01a02c8a-arandommenu`; hand back a hash, A merges. No PRs, no main,
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

## C5 — Next handoff: language and responsive gates

Base on the current tip of `arena/01a02c8a-arandommenu`; do not re-land C1–C4.

1. Add a focused runtime-language gate for player-visible strings in
   `ARandomMenu.luau`, `loadstring`, `src/library/**`, `src/modules/**` and
   `src/games/**`. English is the product language. Avoid a naive dictionary
   that flags identifiers or third-party reference files; seed the gate with
   the concrete Spanish runtime phrases removed by the integrator and document
   how to extend it.
2. Hold the mobile capture fixes: no `DockSearchBox` on touch-primary devices,
   mobile pill width at most 100 px, Navigator still has `Search`, and the
   mobile shortcut slot stays left of the title lane.
3. Hold the height decision: UI Settings has no `Option_Maxheight` row, while
   `state.uiMaxHeight` and `state.uiMaxSettingsHeight` stay 200 and viewport
   clamping still wins.
4. Add a test that changing/resetting a binding through Keybind Manager updates
   the visible per-row square, not only direct square capture.

## C6 — Capture follow-up: mobile editor and Navigator

1. Drive a placed mobile action through the mock: long press opens
   `MobileActionEditor`, size stays within 36–120, opacity stays within 20–100%,
   all four values persist as `{x, y, size, opacity}`, Reset restores 52 px / 92%,
   and Remove destroys both the button and its config entry.
2. Hold-style buttons must release their action before the editor opens.
3. Hold Navigator in raw ScreenGui space at full scale with a transparent root,
   Wurst's compact 456 px three-column panel, vertical overflow and no ClickGUI
   UIScale ancestor.
4. Change Theme.enabled twice while Navigator is open and assert active cells
   and selection rings repaint both times.
5. Keep the synchronous category-height floor: every category below the 200 cap
   must expose all of its rows even when AbsoluteContentSize is one frame late.

## C7 — Next run: retire permissive historical tests

Base on the latest `arena/01a02c8a-arandommenu`. Tools/tests/docs only; do not
change runtime behavior in this lane.

1. Inventory every passing branch whose message says `waits on A`, `not
   published yet`, `demonstrated debt`, or otherwise converts missing behavior
   into a green check.
2. For behavior that has landed, replace the branch with one unconditional
   assertion and delete the historical fallback text.
3. For an intentional product decision (for example, the dock is Navigator's
   return control), rename the assertion to the actual contract rather than
   calling it debt.
4. For genuine missing behavior, write one failing-ready contract and a precise
   debt entry; do not silently make CI red before the owning runtime lane lands.
5. Add a repository gate that rejects new permissive phrases in active suites.
   Keep an explicit, short allowlist only for real staged dependencies.
6. Do not start the broad typing pass yet. First report the analyzer baseline
   by subsystem; context types land after D removes the direct `host.state`
   surface, otherwise types would freeze the wrong architecture.

Report: commit hash, exact checks added/removed, every permissive branch retired,
remaining allowlist and analyzer baseline.

## C8 — Module expansion gates

Base on the latest integration tip with the deliberate 43-module inventory.
Tools/tests/docs only.

1. Add focused behavior tests for Chams, Arrows, NPCESP, WallHop and SpinBot,
   beyond registration: target filtering, off-screen-only arrows, NPC exclusion
   of Player characters, wall-normal/cooldown behavior, property restoration and
   respawn teardown.
2. Hold slider precision: Framework must forward `Step`; integer sliders stay
   integral; decimal sliders without an explicit step use hundredths; no config
   or visible value may retain raw pointer noise.
3. Hold exclusive surface dragging: a Custom HackList pointer owner prevents an
   overlapping window from starting a drag, and ownership always clears on
   release/destruct.
4. Replace count literals with the inventory snapshot where practical so the
   next deliberate module addition changes one authority instead of many tests.
5. Report executor APIs that the mocks still approximate poorly; improve the
   mock rather than weakening runtime assertions.

## Rules

Validate ends "All checks passed." with your new checks counted.
Report: hash, branch, validate counts, new check count, debt.
