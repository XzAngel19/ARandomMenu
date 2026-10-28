# v139.0 — Rendimiento: qué estaba gastando frames

**Stamp:** `v139.0-20261027-performance-pass`
**Base:** v138.9 (`17fc275`)

La queja era concreta: *"tengo lag"*. La respuesta corta es que **no había un solo
culpable**: había tres patrones repetidos por todo el menú. Este parche los quita
uno por uno y, sobre todo, deja una forma de **medir** en vez de adivinar.

## 1. Los tres patrones

| Patrón | Ejemplo real | Coste |
| --- | --- | --- |
| Loop por frame que escribe propiedades de GUI | cooldown de fallo MM2 (`Text` + `Size` cada frame) | `Text` obliga a re-medir y re-formar glifos: es la propiedad más cara de un `TextLabel` |
| Loop por frame que **busca** en el árbol | `Noclip` hacía `GetDescendants()` en el personaje a 60 Hz | ~3000 escrituras/s de `CanCollide` |
| Loop "de fondo" que se **queda encendido** | HUD del menú recoloreando todas las filas a 20 Hz, overlay de sesión reconstruyendo líneas 8 veces/s | trabajo constante con el menú quieto |

También había **closures nuevas por frame** (`pcall(function() … end)` dentro de
bucles) y **tablas nuevas** cada tick (`{color, colorMuted}` por fila, reconciliación
completa de adornos del Coin ESP). Eso no pinta nada en pantalla: sólo le da trabajo
al recolector de basura, que es justo el lag que aparece *a los minutos* de jugar.

## 2. Instrumentación: ahora se puede preguntar

`TaskManager` mide cada tarea y publica el resultado:

```lua
state.performance
--> { fps, frameMs, tasksMs, renderMs, taskCount, renderCount,
      slowestTask, slowestMs, updatedAt }

state.taskManager:Stats()
--> { taskCount, renderCount, tasksMs, renderMs, slowest, top = {...} }

state.perfReport()
--> "FPS 58.9 · frame 16.3 ms · tasks 0.42 ms (4) · render 0.11 ms (2) · ..."
```

- Cada tarea lleva una media exponencial de su coste (`os.clock` dos veces por tarea
  por frame: ~0,2 µs) y su **etiqueta**: `MM2 round clock`, `Prediction sampler`,
  `HUD animations`, `Floating overlays`, `Auto Vote sync`, …
- Si una tarea pasa de **3 ms** por frame, sale un aviso **una sola vez**:
  `[Wurst:Perf] <etiqueta> is taking X ms per frame`. Ya no hay que adivinar qué
  tarjeta rompe el juego.
- El overlay *Session Info* muestra `Menu X.XX+Y.YY ms` (tareas + render). El FPS
  también sale de aquí: antes se calculaba **tres veces** con tres medias distintas.

## 3. Bug real encontrado por el test nuevo

`tools/test_scheduler.py` (8 suites, extrae el bloque real de `Wurst.lua` y lo corre
contra un `RunService` falso) destapó un fallo de verdad:

- Al desconectar una tarea **desde dentro de sí misma**, el bucket hace *swap-remove*
  (la última tarea ocupa el hueco). El `index += 1` de después se saltaba la tarea
  que acababa de entrar en ese hueco: **una conexión viva dejaba de ejecutarse** o,
  peor, seguía viva y sin limpiar.
- El primer arreglo (no avanzar nunca si la tarea se había desconectado) creó un
  bucle infinito —`table overflow`—. El bueno es: no avanzar si la tarea acaba de
  ser removida/deshabilitada, avanzar sólo cuando realmente se ejecutó.

## 4. Lo que se quitó, módulo por módulo

- **Prediction (MM2):** se cachean las partes del rival (0,5 s) y se eliminó la
  closure `pcall` por jugador por frame. El muestreo sigue a 60 Hz porque alimenta la
  predicción de disparo; lo caro era buscar `HumanoidRootPart`/`UpperTorso` 60 veces
  por segundo por jugador.
- **`MM2/base.lua`:** lobby y mapa en caché (0,1 s / 0,25 s), la fase de ronda se
  refresca a 10 Hz y el **cooldown de fallo** ya no reescribe `Text`/`Size` cada
  frame: ~12 Hz y sólo si el texto o la barra cambiaron.
- **Coin ESP:** los adornos se reconcilian en vez de recrearse; el recoloreo va a
  2 Hz.
- **Auto Farm:** fuera el `pcall(function() … end)` por moneda.
- **Noclip:** pasa a **evento + barrido a 5 Hz** que sólo toca las partes que
  volvieron a `CanCollide = true`. Adiós al `GetDescendants()` a 60 Hz.
- **HUD (Furniture):** sólo anima si hay *Rainbow* o pulso activos; cada fila
  reutiliza **una** tabla de color y el pulso baja a 10 Hz (20 Hz sólo con rainbow).
- **Overlays flotantes:** si Session Info, TextGUI, Target Info y Radar están
  apagados, la tarea **no hace nada** (antes reconstruía las líneas 8 veces/s).
- **`featureConnections`:** `MM2/Combat/AutoShoot.lua` usaba la misma clave que
  `MM2/Blatant/Shoot.lua` (`MM2AutoShoot`): al desactivar una tarjeta se mataba la
  conexión de la otra y quedaba un **loop de disparo fantasma**. Ahora la clave es
  `MM2AutoShootCard` y se desconecta antes de conectar. Un escaneo del repo confirma
  **0 claves compartidas**.

## 5. Regresiones que blindan esto

- Bloque **PERF** en `tools/gen_full_boot_harness.py`:
  - `state.performance` existe y publica números reales.
  - **≤ 26 tareas always-on** (hoy son 6) y `state.perfReport()` legible.
  - **Leak check:** 8 encendidos/apagados seguidos de `PlayerESP` (render) y de
    `Coins Aura` (task) dejan los buckets exactamente como estaban.
  - **Cada tarea always-on tiene nombre de módulo**: nada de `task` ni de rutas de
    código. Hoy: `Floating overlays | HUD animations | MM2 round phase |
    MM2 round clock | Prediction sampler | Auto Vote sync`.
- `tools/test_scheduler.py`: connect/run/disconnect, swap-remove, autodesconexión,
  desactivación tras 3 fallos, `Stats()`, `perfReport()`, bucket de render y
  `Destroy()`.

## 6. Verificación

- `bash tools/validate.sh`: **91 fuentes Lua**, **67 suites**, `card.py check`,
  boot `failures=0`, menú **52** tarjetas / release **51**, API cruzada OK,
  `[HARNESS] PERF: 6 always-on tasks, no toggle leak`.

## 7. Qué NO se tocó (y por qué)

- `Entity.lua:Refresh` ya va a 1/30 s con pools.
- `ImproveFps` ya trabaja en trozos de 200 partes por frame con rescaneo de 1 s.
- `InteractExtender` ya refresca a 0,5 s con escaneo asíncrono.
- El muestreo de Prediction sigue a 60 Hz: es el que alimenta la predicción de tiro.
