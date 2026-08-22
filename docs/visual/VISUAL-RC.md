# Visual release checklist

Headless hold on integration tip `9016829`. Integrator: A. Integration
branch: `arena/01a0262f-arandommenu`.

The harness proves contracts and geometry. It does **not** rasterise
Roblox's engine. Nothing here is visually finished until the captures
below land from a real client.

Standing product (do not regress): Code face permanent, 16 px type,
blur mandatory, toasts on the unscaled shell, boot-time cache sweep.

## Next-round captures (user)

Take these on a real Roblox client. One PNG per row. Crop to the menu;
do not include the studio explorer. Console line (4) is text, not a PNG.

### Must-have (P0 — this round is blocked without them)

1. **Idle ClickGUI at 16 px Code** — 1600×900, scale 1. Five category
   windows + wordmark + dock. Type must read as the 16 px contract (not
   the old 11.5 / Monocraft atlas). No hail.
2. **Toast fully inside the corner** — trigger any notify (boot
   "Menu ready" is enough). The stack must sit in the physical
   bottom-right, not clipped by UIScale, not on PopupLayer.
3. **UI Settings without Font pack** — open UI Settings. The Font pack
   row is gone. Background / Accent / Text / Opacity still there.
4. **Cache sweep console line** — after an update that removed files,
   the executor console shows
   `[Wurst:Cache] swept <n> stale source(s), <m> stale asset(s)`.
   Seed a leftover under `ARandomMenu/` or `<storage>/Assets/` first.

### Should-have (P1)

5. **NoFall Settings** — title in the header at 16 px, clipped, no
   body/chrome invasion. Scales 0.7 / 1 / 1.25 / 1.6.
6. **Menu style exclusivity** — Wurst open / Navigator closed, then
   the reverse.
7. **Keybind square** — bindable Combat row, no KEY pill, title centred.
8. **HackList Color** — window opens, list recolours, no output error.
9. **Viewport extremes** — 390×844 and 3440×1440, scale 1.
10. **Blur on** — GUI open, game behind is softened; GUI closed, blur off.

### Optional (P2)

11. Theme Monochrome vs Wurst, same windows.
12. Dock hidden (desktop) / HackList hidden.
13. Navigator WurstDoor.

## C1 classification (carried)

| Item | Status |
|---|---|
| A P1 Retile clamp | **resuelto + test bloqueante** |
| A P1 keybind / dock tooltip measure | **resuelto + test bloqueante** |
| APPLY-4 menu-hide | **resuelto + test bloqueante** |
| APPLY-4 `closeInvalidPopups` | **deuda demostrada** |
| Widget `disabled` API | **deuda demostrada** |
| Real Roblox captures | **deuda demostrada** — this list |
| captionFontSize 12 vs secondary 14 | **deuda demostrada** — see `C-size-parity.md` |

## What headless already gates

- 38 universal modules, empty Blocks / Chat / Items.
- Identity: `Wurst` / `0.1 Beta` / `RandomTestingMenu0001`.
- `state.layout.titleFontSize` / `bodyFontSize` = 16; no Font pack row.
- `ToastContainer` is a direct child of the shell ScreenGui, AnchorPoint
  (1,1), position (1,−12)/(1,−12).
- `sweepStaleSources` / `sweepStaleAssets` delete leftovers, spare
  `.stamp` and shipped names, no-op without an accepted bundle.
- Stored `interfaceFont = "Minecraft (Monocraft)"` boots into Code.

`C_CACHE_TOAST_TYPE_READY`
