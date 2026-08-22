# C3 — size parity vs ref-wurst-719

Report only. Base: integration tip `9016829`. Identity pin: Wurst 7.19
`v7.19` / `dbc25e9`. Capture: `docs/design/reference/ref-wurst-719.jpg`
(1600×900, GUI scale 2). Java metrics from `spec.wurst.chrome` /
`spec.wurst.screenshot.absoluteAtScale2` (ClickGuiWindow / FeatureButton /
HackList). Surface changes go through A.

Logical units stay GUI-scale-1. The port draws at GUI scale 2, so every
Java number below is shown next to its ×2 absolute.

| Surface | Wurst 7.19 (logical) | ×2 absolute | Port today | Delta |
|---|---|---|---|---|
| Title bar (`Window` / `TITLE_HEIGHT`) | 13 | 26 | 26 | **exact** |
| Feature row (`FeatureButton.getDefaultHeight`) | 11 | 22 | `layout.cardHeight` 22 | **exact** |
| Category window width | packed (`null`) | — | `WINDOW_WIDTH` 200 | **adaptación** — Roblox packed-to-200; Java sizes to content |
| Feature settings width | packed | — | `packedWidth` / measure | **adaptación** — same idea, different numbers |
| Settings line | 11 | 22 | `optionRowHeight` 22 | **exact** |
| Slider block | 22 | 44 | 44 | **exact** |
| Slider rail | 3 | 6 | 6 | **exact** |
| Slider knob | 8×8 | 16×16 | 16×16 | **exact** |
| Checkbox | 11 | 22 | 22 | **exact** |
| Colour row | 22 | 44 | 44 | **exact** |
| Glyph / title type | MC.font 8 on a 9 line | 16 / 18 | `titleFontSize`/`bodyFontSize` **16** on the Code vector face | **type size exact; face is a user-ordered deviation** (Code, not `MC.font`) |
| Secondary / caption | ~7 logical | 14 | toast copy is 14; `layout.captionFontSize` is **12** | **−2 px vs the 14 px contract C.md names** |
| Logo blit | 72×18 | 144×36 | Furniture 142×36 | **−2 px width** (aspect lock on `wurst_128.png`) |
| HackList line | 9 | 18 | 18 | **exact** |
| Child inset / gap | 2 | 4 | 4 | **exact** |
| Title-bar buttons | 11 | 22 | 22 | **exact** |

## Face and raster (not a size, but it changes how 16 px reads)

ref-wurst-719 is Minecraft 1.18.1 `MC.font` (8 px glyphs, per-column
advance, 1 px shadow). The port now ships the engine `Code` vector face
at 16 px as the permanent default. That is the user's 2026-08-22 order
after real captures, not a Wurst 7.19 match. The bitmap pipeline remains
as a suite-tested internal; UI Settings no longer offers a Font pack row.

## What is not a size bug

- Window width 200 vs Java packed-to-content — already classified as a
  Roblox adaptation in `docs/wurst-deviations.md`.
- Code vs `MC.font` — user mandate, not a calibration miss.
- Blur behind the menu — user mandate (Wurst draws none).

## Remaining size debt (for A, not this pass)

1. `layout.captionFontSize` is 12; the standing 16 px contract asked for
   14 on secondary text. Toasts already pass 14 into `makeTextLabel`.
2. Category windows stay a fixed 200; official Wurst still packs.
3. Logo width 142 vs the 144 the scale-2 table predicts.

No surface was changed in this pass.
