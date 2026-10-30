# v164 — Knife Tracer suave y predicción vertical del lanzamiento

Build `v164-20261029-knife-smooth-throw`. Esta nota distingue lo observado en
el cliente, las pruebas sintéticas y lo que sigue sin comprobarse en Roblox.

## Captura recibida: qué permite concluir

`MM2_Trajectory_Calibration-5.json` corresponde a **v162**, sesión
`8FEB9120-4676-41BE-BF51-3D56B7203A5F`, no a v163/v164. Registra 12
activaciones de Knife, 12 intentos de stab y 5 intentos de Knife contabilizados
con 5 proyectiles observados. Sus cinco eventos guardan `rawSpeed = 96`, pero
**no guardan el origen ni la dirección enviada al lanzar**, ni un impacto
confirmado. Los cinco llevan `passedThroughBody = false` junto con
`closestApproachStuds` y `bodyRadiusStuds` ausentes: eso **no demuestra cinco
fallos**. `latencyMs` en esos eventos es el retraso de emparejamiento/spawn,
no se debe presentar como RTT ni como tiempo de vuelo.

Por separado, la misma sesión registra 19 confirmaciones Gun emparejadas, 8
con hit al objetivo y 5 señales Gun sin emparejar. No son resultados Knife.

En el evento Knife `:15`, la trayectoria del objetivo empieza en Freefall con
velocidad vertical aproximada −28,15 studs/s y, durante 0,173 s, su Y observado
cambia −0,394 studs. El error **3D** del modelo balístico registrado es 7,38
studs; varios estados previos `Landed`/`Running` coinciden con descenso. Es
indicio de que extrapolar la caída sin considerar una superficie puede ser
muy incorrecto. No revela hacia dónde apuntó el lanzamiento ni su resultado.
La captura no guarda la geometría del suelo.

## Qué se cambió

- **Visual permanentemente suavizado:** la posición del punto usa interpolación
  exponencial basada en `deltaTime`, no un tween nuevo por frame. Sigue el
  desplazamiento observado del cuerpo entre cálculos. Al cambiar de objetivo o
  tras un salto grande, la línea aparece suavemente en el nuevo punto en vez de
  barrer el mapa hacia otro jugador. El origen sigue el Handle vivo. Perder el
  objetivo o fallar WallCheck oculta las piezas en la siguiente comprobación
  de visibilidad; no se mantiene una estela mientras se desvanece.
- Se reutilizan **dos Parts** no colisionables y sin consulta/touch; desaparecen
  al desactivar el trazador/módulo. Mientras no cambien punto, origen u opacidad,
  se evitan escrituras gráficas repetidas. La búsqueda de Knife/Handle no se
  repite cada frame cuando ya está equipado; si no hay Knife, se vuelve a
  buscar con un máximo aproximado de 10 Hz. Un lanzamiento real y el input
  nativo siguen resolviendo el arma y la puntería por separado.
- El preview solo recalcula selección/puntería como máximo a **10 Hz**, en vez
  de 15 Hz; cuando un auto throw está listo conserva el intervalo de 15 Hz.
  La interpolación visual por frame **no** hace raycasts ni selecciona
  jugadores. La vista puede diferir ligeramente del punto real porque este
  último se vuelve a calcular al enviar. Una obstrucción nueva se detecta en
  el siguiente cálculo, normalmente dentro de 0,1 s; no hay raycast por frame.
- En `knifeAim`, un objetivo descendente puede usar una consulta vertical de
  suelo local en el XZ previsto. Se filtran los dos personajes, se exige
  superficie suficientemente horizontal y colisionable y se calcula la altura
  de pie a partir de la fórmula R6/R15 de `HipHeight` de Roblox. No se toma a
  otro personaje, una pared inclinada o un obstáculo alto como suelo. Si la
  trayectoria cambia el XZ, se comprueba de nuevo como máximo una vez; la
  caché breve se invalida si la superficie se mueve, cambia de tamaño/colisión
  o se destruye. No se usa una altura arbitraria del jugador local como suelo.
- Si el modelo en caída no converge, se busca un intercepto físicamente
  coherente con número de pasos limitado. Si no existe o es incierto, devuelve
  fallo al módulo y este usa su fallback **alrededor del cuerpo observado**.
  Ese fallback antes aplicaba `vy * latencia` sin límite antes del clamp: a
  −120 studs/s y 0,5 s podía apuntar 60 studs abajo incluso antes del término
  de vuelo. Ahora limita **toda** la caída extrapolada del fallback a 2 studs.
  No se limita la altura real del objetivo a la altura del atacante: un
  objetivo en un piso inferior puede y debe producir un tiro hacia abajo.
- El objetivo se comprueba visible antes de pagar el predictor; siguen el
  WallCheck de cuerpo/corredor y la selección por tiempo de vuelo. Sin objetivo
  válido no se añade ningún carril ni punto de lanzamiento especulativo. Si
  llega un personaje nuevo por respawn, se descarta el track Knife anterior.
  **Gun y su clamp histórico compartido no se modificaron.**

Referencia para altura de pie de rigs: documentación oficial de Roblox,
[`Humanoid.HipHeight`](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Humanoid.yaml).

## Reproducciones y presupuesto (no son resultados del servidor)

`tools/test_mm2_knife_ground.py` ejecuta el predictor real con un suelo
analítico. Usa las muestras verticales anonimizadas de `:15`, pero el origen,
la distancia horizontal y el suelo son **sintéticos**. Para la misma pose,
sin suelo simulado, el algoritmo v163 llegó a `Y = −195,18` desde una raíz en
`Y = 273,21`, con un vuelo calculado de 4,88 s: el cálculo divergía. v164
rechaza ese intercepto imposible y el fallback acota su caída. Con una
superficie **hipotética** que situaría la raíz de pie en Y≈272,81, el predictor
apunta a esa altura; esa superficie no estaba registrada en la captura. Se
probaron además 36 caídas contra un barrido balístico independiente, suelo
R6/R15, caída libre alcanzable, suelo ausente, borde, suelo móvil/no colisionable,
modelo de jugador, pendiente, objetivo inferior y respawn. Son pruebas de
modelo/contrato local, no hits.

`tools/test_mm2_knife_tracer.py` ejecuta el loop real con mocks. A 30/60/120 Hz
la interpolación coincide para igual tiempo transcurrido. En 120 frames a
120 Hz con un objetivo estático se midieron **10 selecciones, 20 llamadas al
predictor, 70 llamadas al helper de visibilidad y 10 búsquedas del arma**; el
resto de frames no seleccionan ni lanzan rayos de visibilidad. Una llamada al
helper puede realizar varios raycasts, así que 70 llamadas no equivale a 70
rayos. Los tests verifican además reutilización, ocultación, fade-in, cambio de
objetivo/teleport, línea quieta sin reescrituras, OFF y tiro con puntería no
suavizada. El caso de v163 en el harness anterior hacía 13 selecciones en un
segundo a 60 Hz; el mismo test en v164 hace 9.

La nueva consulta de suelo añade hasta **dos raycasts por resolución Knife en
caída**, a menudo menos por caché; con varios candidatos, auto throw o input
manual el total crece. La búsqueda numérica tiene un máximo de 64 muestras y
12 pasos de bisección cuando hace falta. Las mediciones del mock no miden el
coste real de Roblox, GPU, executor o streaming y no garantizan FPS ni ausencia
de spikes. La geometría local puede estar incompleta y el modelo no conoce un
cambio futuro de movimiento/plataforma. No se infiere hit-rate, aceptación del
servidor ni seguridad anticheat.

Validación completa: bundle de 89 archivos actualizado; 91 fuentes Luau
compilan, 83 suites pasan, auditoría de callbacks sin fallos, boot completo con
`failures=0`, 93 llamadas de API verificadas y menú 50 tarjetas/49 en release.

## Comprobación real pendiente

En Roblox verificar la marca v164 y comparar Knife Tracer ON/OFF, un objetivo
quieto, uno que corre/salta/aterriza, un objetivo en un piso inferior y un muro
con WallCheck activo. Si vuelve a apuntar al suelo, guardar vídeo indicando
mapa, altura, si era manual/auto y el objetivo; el JSON actual no registra la
dirección real. Para el rendimiento comparar periodos similares con
`UI Settings → Perf report` antes/después. **No activar Gun Probe**: la prueba
anterior ya interfirió con disparos. La revisión de Shaders, Shift Lock y
spikes de v163 también sigue pendiente en una sesión Roblox real.
