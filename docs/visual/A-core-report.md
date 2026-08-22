# A Visual Core Report

Base: `b47dd40` (Fase 0). Lane: renderer/font/style del shell, Widgets,
WindowManager, assets/font, tools de fuente. Hashes de esta pasada:

| Etapa | Commit | Contenido |
|---|---|---|
| Sync Fase 0 | `b47dd40` (merge, ff) | Sin conflictos; contratos compartidos = b47dd40 |
| A1 + A2 | `bc28a1d` | measure/wrap/ellipsis centralizados; ventanas pixel-snapped |
| A3 + A4 + A5 | `fc9c344` | flatTextBox (StyleCorner fuera de widgets); min/max medidos; sims verdes |
| A6 | (este doc) | Reporte |

## Superficies y matrices probadas (headless, mock del harness)

- **Tipografía (A1)**: 4 variantes (Monocraft familia 8/16/24/32,
  Minecraft 1.18.1 local mockeado vía `loadExactAtlas` con advances
  variables, Minecraft 26.2 local mockeado, vector sin atlas) × 4
  escalas (0.7/1/1.25/1.6) × 11 textos ("NoFall Settings", "Projectile
  Calibration", "Max settings height", "Minecraft 1.18.1",
  "RightControl", "Tooltip opacity", corta, larga, "0.15", "#FF00FF",
  "12345.678"). Verificado por texto: un holder por nombre, clip,
  `maxWidth` respetado, rects físicos enteros, glifos dentro del
  holder, sin doble tinta (glifos XOR fallback vectorial), redraw
  idéntico = 0 instancias nuevas, font switch acotado a un redraw por
  holder, destruct sin error. **Resultado: 0 defectos** en el núcleo.
- **Widgets (A3)**: panel sintético con toggle/slider/range/combo/color
  construido por los mismos builders que usan los módulos, 3 modos de
  fuente × 4 escalas. **1 defecto encontrado y corregido** (abajo).
- **Chrome (A4)**: título largo en ventana de 160 (clip dentro de la
  región de chrome), height ilimitado (Max settings height 0) contenido
  al viewport, posiciones de ventana en la rejilla física a escalas
  fraccionarias, viewport corto 800×450. **0 defectos tras el fix**.
- **Rendimiento (A5)**: 5 settings reales abiertas (Killaura,
  PlayerESP, NoFall, Flight, ItemESP) dentro del presupuesto de glifos
  (<1600); close/reopen ×5 reutiliza el pool (<40 creaciones); theme
  write de mismo color crea 0; destruct deja 0 holders vivos.

## Fuentes y métricas

- Layout SIEMPRE sobre el atlas-16 del contrato (advances 11/12-est);
  el raster es downscale-only: ≤8→8, 9..16→16, 17..24→24, 25..32→32,
  mayor→el mayor disponible; Pixelated; snapping a píxel físico.
- `measure` es la única vara: `width()` delega en `measure`;
  el ancho de nacimiento de OpenFeatureSettings y los end-labels del
  slider miden por contrato (el conteo de glifos sobrevive solo para
  el stub del harness, que no publica el contrato).
- `wrap(text, width, size)` central (el tooltip lo consume);
  `ellipsis` opcional en draw() = dos puntos ASCII (el atlas no tiene
  U+2026; nada finge glifos).

## Defectos resueltos en esta pasada

1. `contract.width()` ignoraba `measure` (deriva posible entre packing
   y render) → delega en measure.
2. Ancho de nacimiento de settings por `#text*12` → measure.
3. End-labels min/max del slider por `#texto*9` → measure.
4. **Geometría de ventanas fraccionaria en píxeles físicos** a escala
   1.25/0.7 (borde 1px difuminado en dos píxeles) → snap central en
   `clamp()`/`snap()`; cubre create/drag/place/reflow/reclamp.
5. **StyleCorner residual** (radius 0, herencia del menú viejo) dentro
   de todos los TextBox de widgets → `flatTextBox` los elimina al
   nacer (slider value, range low/high, filtro de choice list, text
   option, hex y RGB del picker).
6. Wrap duplicable + sin ellipsis → centralizados en el contrato.

## Bloqueos externos

- El sandbox bloquea TLS a piston-meta/data (documentado): el
  downloader oficial se ejercita en máquinas reales; pins verificados
  vía fetch proxied. Sin cambios de pipeline esta pasada.

## P0/P1 restantes (honesto)

- **P1 (lane D)**: `ClickGui.Retile`/`nextSlot` escriben Position sin
  pasar por el clamp del manager → posiciones de categoría pueden caer
  en píxel físico fraccionario a escala 1.25 (mismas coordenadas
  lógicas enteras; el snap central no las cubre). Fix de una línea en
  ClickGui (snap vía `state.windows.LogicalToScreen` o clamp) — para D
  en su D1.
- **P1 (lane D)**: tooltip del keybind square en Cards estima
  `#texto*8+24` — debe usar `state.bitmapText.measure`/`wrap`.
- **P1 (lane D)**: `showPillTip` en Furniture estima `#texto*5.5`.
- **P2**: estado `disabled` no existe como API de widgets (ningún
  consumidor lo pide hoy); si D lo necesita para composición, lo
  añadimos coordinado.
- **Capturas reales pendientes**: nada de esta pasada se declara
  visualmente terminado sin captura del usuario en Roblox real. Las
  sims verifican geometría y contratos, no el rasterizado del engine.

`A_VISUAL_CORE_READY`
