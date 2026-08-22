# Visual release checklist

Headless RC hold for the composed tree at `e866116` plus this pass.
Integrator: A. Integration branch: `arena/01a0262f-arandommenu`.

The harness proves contracts and geometry. It does **not** rasterise
Roblox's engine. Nothing here is visually finished until the captures
below land from a real client.

## C1 — P0 / P1 classification

| Item | Status |
|---|---|
| A P1: `ClickGui.Retile` writes Position without manager clamp | **resuelto + test bloqueante** (`visual-rc`, `placement-final`) |
| A P1: Cards keybind tooltip estimates `#texto*8` | **resuelto + test bloqueante** (`visual-rc`) |
| A P1: Furniture `showPillTip` estimates `#text * 5.5` | **resuelto + test bloqueante** (`visual-rc`) |
| A P2: widgets have no `disabled` API | **deuda demostrada** — no blocking test, no new function |
| APPLY-4 menu-hide closes `ChoiceList` | **resuelto + test bloqueante** |
| APPLY-4 owner-window close / scroll-clip (`closeInvalidPopups`) | **deuda demostrada** — functions unpublished; do not add them |
| HackList `SetColor` crash (`row.label`) | **defecto pequeño** — fixed to `hudColor = color; forceHudRefresh()` |
| Real Roblox captures | **deuda demostrada** — this file is the list |
| ClickGui.order vs `CATEGORY_ORDER` (Combat left of Render) | **deuda demostrada** unless a post-module retile is proven |

## Captures the user must send

Take these on a real Roblox client, GUI scale matching the pin, font pack
as labelled. One PNG per row. Crop to the menu; do not include the
studio explorer.

### Must-have (P0 — release blocked without them)

1. **Idle Wurst ClickGUI** — 1600×900, scale 1, Monocraft fallback.
   Five category windows + wordmark + dock. No hail, no blur.
2. **NoFall Settings** — title in the header, clipped, no body/chrome
   invasion, no second visible TextLabel. Scales **0.7 / 1 / 1.25 / 1.6**
   (four shots).
3. **HackList settings Color** — window opens, list recolours, no
   output-window error.
4. **Menu style exclusivity** — Wurst open, Navigator closed; then
   Navigator open, Wurst closed. Two shots.
5. **Keybind square** — bindable Combat row, 12×12 square, no KEY pill,
   title still centred.

### Should-have (P1 — ship-with-known-debt if missing)

6. **Exact font** — Minecraft 1.18.1 pack installed, UI Settings
   "Font pack" = that name. Same idle frame as (1).
7. **Vector stand-in** — no atlas (rename/remove the cache). Menu still
   readable.
8. **Widget matrix** — one settings window showing toggle / slider /
   range / combo / colour / text. No rounded TextBoxes.
9. **Viewport extremes** — 390×844 (phone) and 3440×1440 (ultrawide),
   scale 1.
10. **Dock hidden** — desktop, Show dock = false, RightControl still
    opens the menu.
11. **HackList hidden** — Show HackList = false, enabled modules
    unchanged.
12. **Navigator WurstDoor** — `< Wurst ClickGUI` top-left, click
    returns to Wurst.

### Optional (P2)

13. Theme Monochrome vs Wurst, same windows.
14. Long tooltip on the keybind square and on the dock ≡.
15. Five settings open at once (budget / overlap sanity).

## Remaining P0 / P1 after this hold

- **P0**: the must-have captures above. Headless cannot close them.
- **P1**: APPLY-4 owner/scroll-clip, unpublished as `closeInvalidPopups`
  / `closePopupsOutsideArea`. Menu-hide is already blocking.
- **P1**: ClickGui.order may still follow first-module-load, so Combat
  is not asserted left-of-Render on screen.
- **P2**: widget `disabled` API, no consumer.

## What this hold already gates

- 38 universal modules, no new hacks, empty Blocks / Chat / Items.
- Identity: `Wurst` / `0.1 Beta` / `RandomTestingMenu0001`.
- Font authority: Minecraft 1.18.1; committed raster is Monocraft OFL.
- `pickAtlas` downscale-only; `measure` / `wrap` / `ellipsis` (two ASCII
  dots); `snapPixel` on clamp/snap.
- Bitmap budgets: idle 700, five settings 1600, Navigator delta 800,
  HackList 250, open/close growth < 80, theme/font/scale created < 200,
  destruct 0.

`C_VISUAL_RC_READY`
