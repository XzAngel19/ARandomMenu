# v180 — predicción restaurada, calibración que aprende y controles que se dejan tocar

Fecha: 2026-11-04 · rama `arena/979b8402-arandommenu`

## Predicción de arma y cuchillo: de vuelta a como estaba

A petición del usuario, el tiro y el lanzamiento vuelven a la política anterior a
v179. Se revirtieron `src/games/MM2/Prediction.lua` y
`src/games/MM2/Combat/KnifeThrow.lua` al comportamiento previo:

- el horizonte vuelve a ser el ping hasta que exista un eco medido, y el eco se
  mezcla 60/40 cuando existe;
- se elimina el *prior* de aceptación (`setAcceptancePrior`) del camino de la
  predicción: la medición se sigue guardando, pero ya no decide el adelanto;
- el cuchillo vuelve a apuntar al intercepto crudo (el campo `leadCorrection` de
  `knifeAim` vuelve a ser 0), sin corrección aprendida en el filo.

Lo único que se conserva de v179 es el **bucket propio del cuchillo**
(`modeKey("knife") → "Knife"`): sin eso, cada confirmación de cuchillo se
promediaba dentro del bucket de las armas sin modo y retocaba todas ellas.

## Calibración: todo lo que faltaba para converger en 10–20 partidas

El agujero real no era la cantidad de datos, sino que **el modelo aprendido no
sobrevivía a la sesión**. Cada partida empezaba con la corrección a cero, así que
ningún número de partidas podía acumular nada. Ahora:

- `Prediction.lua` expone `exportLeadState()` (por modo: muestras, mediana y
  corrección aplicada) y `seedLeadError(modo, segundos, muestras)`;
- `base.lua` escribe un bloque `predictor` en el JSON de calibración y lo vuelve
  a inyectar al arrancar (`applyLearnedSeeds`), con reintento acotado porque el
  orden de carga entre `base.lua` y `Prediction.lua` no está fijado;
- las semillas con menos de tres muestras se rechazan: dos tiros son una
  anécdota, no una medición;
- la tarjeta **Calibration → Calibration status** muestra el progreso:
  `AimAssist…`/`Bullet 12/20 +14 ms`, es decir muestras acumuladas por modo,
  objetivo de 20 y corrección aplicada en milisegundos.

Con eso, 10–20 partidas dejan el bucket lleno y la corrección mediana aplicada
desde el primer tiro de la siguiente sesión.

## Freeze Movements: cualquier animación, cualquier emote

- **Emotes**: ya no depende de la lista de Roblox. Se reconoce un emote por
  palabras clave en el nombre de la pista y de hasta seis padres
  (`emote, dance, taunt, celebrat, cheer, wave, laugh, salute, groove, pose,
  victory, expression, emoji, flex, party, clap, bow, ridicule, point`), con una
  lista negra que impide confundir un espadazo (`attack, slash, stab, swing,
  sword, gun…`) con un baile.
- **Emotes personalizados sin nombre útil**: si el cuerpo está quieto y arranca
  un clip *loopeado* en prioridad Action/Idle que no está en la lista negra, se
  trata como emote del juego (nueva fila **Any emote**, activada por defecto).
- **Animación**: Motion congela también la locomoción propia del juego, no solo
  el set walk/run/idle de Roblox (nueva fila **Any animation**).

## «Anchor» pasa a llamarse Position Lock, con opciones

El modo se llamaba *Anchor* y no tenía ajustes. Ahora:

| Fila | Qué hace |
| --- | --- |
| **Freeze mode** | `Position Lock` (antes `Anchor`) o `Motion`; el valor guardado `Anchor` se migra solo |
| **Lock rotation** | además de la posición, impide giros (por defecto sí) |
| **Keep gravity** | no ancla el cuerpo: puede caer y aterrizar, pero los empujones se borran cada frame |
| **Return if pushed** | studs de deriva permitidos antes de devolver al personaje a su sitio (0 = desactivado) |

La restauración del estado OFF devuelve también la orientación original.

## Opciones con la tarjeta apagada, Get All Emotes y Fling

- **Interact Extender**: una fila encendida funciona con la tarjeta apagada. Los
  canales (prompts/click detectors) se activan por sí solos y la tarjeta ON sigue
  siendo el interruptor maestro. Los hooks se conectan y desconectan solo cuando
  hay algún canal vivo, y el escaneo completo ocurre una única vez.
- **Get All Emotes** es un **botón** (`action = true`): no se enciende ni se
  apaga, y no concede nada al arrancar. Un clic escribe los cinco emotes de
  tienda (`ninja, zen, dab, floss, zombie`) en el perfil local, y **Select Emote**
  elige y reproduce de inmediato. Restaurar el valor guardado del ciclo ya no
  dispara un emote (eso generaba un aviso en cada inyección).
- **Fling / Walk Fling**: slider **Power** (Fling 1–12, Walk Fling 1–3) y
  **Retries** en Fling, con fuerza finita y sin bucles infinitos.
- **Calibration**: la tarjeta vuelve a estar en release; solo guarda si el
  jugador responde **Sí** al aviso centrado. **No** borra el archivo y no vuelve
  a preguntar.

## Pruebas

Nuevas o reescritas: `tools/test_options_with_card_off.py`,
`tools/test_freeze_general.py`, `tools/test_mm2_emotes.py` (botón de cinco
emotes, Select Emote que reproduce, fallback al Animator, respawn y limpieza) y
los nuevos grupos de `tools/test_mm2_precision.py` (horizonte restaurado,
cuchillo sin corrección aprendida, exportación/semilla del modelo).
`tools/gen_full_boot_harness.py` se actualizó a la nueva API del botón.
