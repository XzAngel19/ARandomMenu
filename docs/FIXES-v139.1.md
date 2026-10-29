# v139.1 — Lag spikes: medirlos y quitar los que venían del menú

**Stamp:** `v139.1-20261027-spikes-release-version`
**Base:** v139.0 (`4289d52`)

La v139.0 bajó el coste **constante** del menú. Un *spike* es otra cosa: un frame
suelto que se va a 60–200 ms y se siente como un tirón. Aquí se mide aparte y se
quitan las causas que sí estaban en nuestro lado.

## 1. Versión

El menú deja de decir **0.1 Beta** y pasa a **0.823 Release**:
`PRODUCT.version` en `Wurst.lua` y el valor de respaldo de `ClickGui.lua`. El ancho
de la placa del logo se calcula con `#productVersion`, así que se adapta solo.

## 2. Detector de spikes (lo que hacía falta para no adivinar)

`state.performance` gana cinco campos:

```lua
spikeMs      -- el último frame que se pasó del presupuesto
spikeCount   -- cuántos frames >= 45 ms desde la inyección
spikeTask    -- la tarea más cara de ESE frame (nombre del módulo)
spikeAgo     -- hace cuántos segundos fue el último
worstSpikeMs -- el peor visto
```

- Umbral **45 ms** (~2,7 frames a 60 FPS): suficiente para cazar un tirón real sin
  que el jitter normal llene la consola.
- Un aviso **como mucho cada 5 s**:
  `[Wurst:Perf] frame spike 120 ms (menu 0.31 ms · HUD animations)`.
  Si el coste del menú es ridículo, el tirón es del juego o del executor: eso
  también sirve para saberlo.
- `state.perfReport()` añade una línea `spikes N · worst X ms · last Y s ago · tarea`.
- En *Session Info*: `Spikes  3 · 84 ms · Prediction sampler`.
- `runBucket` ahora devuelve también la tarea más cara del frame, así que el aviso
  dice **quién** estaba corriendo cuando el frame se fue.

## 3. Spikes que quitamos (asignaciones y escrituras repetidas)

Un spike típico en Roblox es el **recolector de basura**: cientos de tablas por
segundo no se notan hasta que el GC se pone a limpiar y regala un tirón de 30–80 ms.
Esto es lo que se dejó de asignar/repetir:

| Sitio | Antes | Ahora |
| --- | --- | --- |
| `Prediction` (60 Hz, por jugador) | una tabla por muestra (~700/s con 12 jugadores) | **pool de muestras**: se reutilizan las tablas retiradas |
| `Prediction` | `Players:GetPlayers()` en cada frame (array nuevo) | lista cacheada **0,25 s** |
| `ImproveFps` (barrido de paisaje) | `pending = {}` cada segundo (miles de partes) | `table.clear(pending)`, el array no se tira |
| `Render:Label` (todos los ESP) | `Size` + `BackgroundTransparency` **por label y por frame** | sólo cuando cambian (un `Size` re-calcula layout) |
| `Nametags` | `Font`, `BackgroundColor3`, `TextStrokeTransparency`, `Size` y `TextTruncate` por frame y por jugador | sólo cuando cambian; `GetTextSize` cacheado por texto+tamaño |
| `Furniture` (HUD) | cualquier cambio de estado re-dibujaba **todas** las filas | sólo la fila que cambió (`row.name`/`row.status`), todas si cambia de lado |

`Font` era el peor de los tres: reasignarlo no cambia nada visualmente pero obliga a
re-formar los glifos de **todos** los nametags, cada frame.

## 4. Lo que ya estaba bien (no se tocó)

- `Chams`: crea el `Highlight` sólo si falta y compara color/transparencia antes de
  escribir.
- `bitmapText.draw`: firma cacheada, no reconstruye si el texto no cambió.
- `Entity:Refresh` a 1/30 s con pools y `table.clear`.
- `ImproveFps` en trozos de 200 partes por frame.

## 5. Verificación

- `bash tools/validate.sh` **verde**: 91 fuentes Lua, **67 suites**, `card.py check`,
  boot `failures=0`, menú 52 tarjetas / release 51.
- Harness: 6 tareas always-on, todas con nombre, y ahora también comprueba
  `spikeCount` / `worstSpikeMs` / `spikeAgo`.
- `tools/test_mm2_precision.py` sigue verde tras el pool de muestras y la caché de
  jugadores (11 grupos de regresión).
- `tools/test_render_roles.py`: los mocks de GUI ahora tienen `Position`/`Size`,
  como cualquier `GuiObject` real.

## 6. Cómo leer el resultado en vivo

```lua
print(state.perfReport())
```

- **`tasks` bajo + spikes frecuentes** → el tirón no es del menú (juego, executor o
  carga de assets). Mira `Menu` en *Session Info*: si es <1 ms, no somos nosotros.
- **spikes con nombre de módulo** → es esa tarjeta; baja su rango o apágala y
  compara.
- **sin spikes y `tasks` alto** → es coste constante, no tirones: eso lo ataca v139.0.
