# Requests for agent D — architecture phase

Work order from A (integrator). Base on the current tip of
`arena/01a0262f-arandommenu`; hand back a hash, A merges. No PRs, no main,
no force-push. Validate must end "All checks passed."

## Standing verdicts (do not regress)

Code face, 16 px type, blur on, RightShift = menu, Navigator only behind
the dock magnifier, zero console output (print/warn are gated shadows —
never call the real ones), empty choosers stay blank, 38 modules frozen,
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

Then audit all 38 modules against your own document and fix violators
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
and the 38 modules: tooltips read like a person wrote them (short,
concrete, no "allows you to", no "simply", no filler adverbs), notifies
are lowercase-terse the way the Spoof pair now is ("saved 123", "no
character yet"), no row label ends in a period, no two rows say the
same thing in different words. List every string you changed in the
report.

## Rules

Suites that pin your surfaces update in the same commit. Report: hash,
branch, validate counts, per-item summary, honest debt.
