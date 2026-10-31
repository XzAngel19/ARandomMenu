# v165 — Shaders nativos y primera simplificación de módulos

Fecha: 2026-10-31 · Stamp: `v165-20261031-native-shaders-simple`

## Petición y alcance

El usuario pidió estudiar shaders reales de Roblox, conservar los códigos de
Vape/YARHM que ya utiliza el menú y simplificar el código propio, sin añadir
comprobaciones ni mecanismos innecesarios. Eligió **efectos nativos de Roblox**
para Shaders, no ReShade externo.

Este es un **primer pase**, no una afirmación de que los 67 archivos de
`src/games` ya se hayan simplificado ni de que todos sean copias originales al
100 %. Se inventariaron los archivos; se cambiaron los diez identificados abajo.
Otros módulos propios o adaptados aún necesitan revisión individual. No se
restauró una versión antigua del proyecto ni se copiaron ciegamente scripts
ajenos, porque se perderían funciones y los módulos no comparten un único origen.

## Investigación de shaders

- Roblox documenta `BloomEffect`, `ColorCorrectionEffect`, `SunRaysEffect`,
  `DepthOfFieldEffect` y otros posprocesos; se aplican directamente en
  `Lighting` o `CurrentCamera`, y ciertos efectos pueden verse distintos o no
  funcionar con calidad baja:
  <https://create.roblox.com/docs/environment/post-processing-effects> y
  <https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/PostEffect.yaml>.
- Tanto `BloomEffect` como `ColorCorrectionEffect` pueden componerse con otros
  efectos de la misma clase. No es necesario destruir los del juego:
  <https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/BloomEffect.yaml>
  y <https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/ColorCorrectionEffect.yaml>.
- El ejemplo público
  <https://github.com/Gubbyoso/Roblox-Shaders-Script/blob/main/SCRIPT>
  combina color, bloom y rayos, pero también destruye efectos y el cielo del
  juego y cambia varias propiedades globales. Se estudió como ejemplo de uso;
  **no se copió ese comportamiento ni su script**.
- Luau no equivale a ReShade o a un shader GPU personalizado. Un proyecto de la
  comunidad que distingue explícitamente ambas cosas es
  <https://github.com/xslvrrr/Solstice>. No se instaló ni ejecutó software
  externo y no se promete RTX, trazado de rayos o compatibilidad con anticheat.

## Cambios

### Shaders

`src/games/universal/Render/Shaders.lua` pasa de 425 a 146 líneas. Crea tres
instancias nativas propias directamente en Lighting, aplica opciones cuando se
enciende o cambia un control y las destruye al apagar. Sin tarea por frame ni
sondeos, sin tocar cielo, efectos ajenos, propiedades globales o remotes.

Se mantienen nombres de controles, presets, suma de presets con sliders,
configuración guardada y botón `Diagnose`. El preset por defecto `Cinematic`
se ajusta a color ligeramente cálido/saturado y contraste moderado, con bloom
y rayos configurables. La apariencia real depende del mapa, efectos existentes
y calidad gráfica. `Improve FPS > Disable post effects` puede interferir.

Ya no hay reparación automática cuando otro script destruye o mueve el efecto:
si ocurre, se puede apagar y volver a encender Shaders. Un error inesperado al
crear un efecto llega al llamador; el cleanup se registra antes y limpia lo
que se haya creado al apagar. `Diagnose` muestra parent y Enabled, no demuestra
lo que renderiza la GPU.

### Fling y movimiento universal

- `Fling.lua`: se conservan los movimientos `FPos`, velocidad/rotación,
  `EpixVel`, los `task.wait()` y la estructura procedentes del SkidFling de
  YARHM. Se simplificaron lecturas, cronómetro, señales y helpers protegidos
  redundantes. Si una pose falla, el pin, `FallenPartsDestroyHeight`, el estado
  del Humanoid y la actividad se restauran.
- Se retira `rescueImpulse`: era un segundo impulso añadido que modificaba
  partes del objetivo y **no era parte del SkidFling original**. Si el intento
  no mueve al objetivo, se informa sin aplicar ese empuje adicional.
- **No es una copia byte a byte:** siguen la interfaz propia, protección,
  retorno y adaptaciones ya existentes `Power`, `Prediction` y `Retries`.
  `Power = 3` reproduce las magnitudes base de YARHM; el default del menú no se
  bajó. No se valida network ownership ni eficacia en un servidor real. Se
  retiró el fallback de fuerza finita para mantener la fuerza infinita del
  original; su aceptación por cualquier executor no se ha comprobado.
- `WalkFling.lua`: espera directamente Heartbeat/RenderStepped/Stepped como
  requiere el pulso de Infinite Yield. Mantiene el token de sesión y restauración
  de colisiones; nunca se activa al inyectar.
- `AntiFling.lua`: acceso directo al contrato del Framework para la opción de
  velocidad, sin `pcall` por frame. Sigue respetando el propio Fling/Walk Fling.

### MM2

Se simplificaron lecturas de propiedades `BasePart` y resultados ya tipados en
`CoinsAura.lua`, `GunAura.lua`, `AutoVote.lua`, `AutoWin.lua` y `base.lua`. Se
eliminó una restauración duplicada de Coin_Server. Se conservan las distancias,
los resets/touches existentes y las reglas de mapa/lobby; no se cambió el
contrato de recogida ni se aumentó el alcance.

`Prediction.lua` lee directamente el estado, salud y atributos de un
`Humanoid`; ya no protege esas propiedades nativas con múltiples `pcall`. Se
mantienen las reglas de muerto/Physics/atributo Dead, la predicción de Gun y
Knife, WallCheck y los límites de suelo de v164. No se modificaron los tiempos,
coeficientes ni fórmulas del predictor.

No se retiraron indiscriminadamente condiciones de objetivo visible, protección,
ronda, respawn y cleanup: son decisiones previas del usuario o parte del ciclo
de vida, no simples redundancias. Las fuentes de Vape/YARHM que no se tocaron
siguen como estaban; en particular, X-Ray y Fullbright continúan siendo
adaptaciones, no se presentan como código original exacto.

## Validación y límites

- `tools/test_shaders.py` ejecuta el Framework y módulo reales: padre directo,
  ajustes, cleanup, configuración restaurada, error de construcción y
  diagnóstico; no simula imagen GPU.
- `tools/test_fling_skid.py` verifica poses, pin, flags, la eliminación del
  impulso ajeno a YARHM y cleanup tras un fallo de pose simulado.
- `tools/test_walkfling.py` y `tools/test_antivoid50.py` prueban ciclo ON/OFF,
  restauración, actividad y opción Speed.
- `tools/test_mm2_map_checks.py` ejecuta las funciones reales de mapa/lobby en
  los límites 350/1500, ausencia de mapa y countdown. La suite de monedas
  ejecuta Coins Aura/Gun Aura/Auto Vote. Las suites de Prediction cubren estados
  y atributos Dead, 36 caídas y 486 trayectorias sintéticas.
- `bash tools/validate.sh`: 91 fuentes compilan, bundle de 89 archivos al día,
  84 suites pasan, boot `failures=0`, 93 llamadas API verificadas y menú 50/49.
  No se probaron Roblox, shaders renderizados, FPS, Volt/Delta, daño, servidor ni
  anticheat.
