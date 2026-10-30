# RESUME — Wurst · Handoff y guía de arquitectura de games

> Léelo entero antes de tocar nada. Resume el estado real del proyecto, las
> reglas del usuario, y los errores que ya se pagaron una vez. Si algo aquí
> contradice lo que crees, gana este documento (y los datos de calibración).
>
> **Estado al escribir esto:** rama fija `arena/9492e6b6-arandommenu`, build
> **`v162-20261030-shiftlock-shaders-fix`**, con árbol base de
> `arena/76bc3f2f-arandommenu` en el commit `9395998`.
> El usuario se comunica en español. Respóndele en español.

---

## 1. Qué es esto y cómo llega al usuario

- Menú "Wurst" para Roblox, foco principal **MM2** (place id `142823291`).
  También hay módulos universales y de otros juegos (BedFight, TRS, VD y
  X2Duels/MVS).
- El loader carga el **bundle**: `getgenv().WURST_BRANCH = "arena/9492e6b6-arandommenu"`.
- **Protocolo de publicación (obligatorio, sin excepciones):**
  1. Edita en `src/…`, nunca directamente en `src/libraries/bundle.lua`.
  2. Sube `SOURCE_STAMP` en `src/Wurst.lua` (`vNNN-AAAAMMDD-descripcion`).
  3. `python3 tools/build_bundle.py --stamp <el mismo stamp>`
  4. `bash tools/validate.sh` — debe terminar VERDE (v162: 91 fuentes,
     80 suites, auditoría de rendimiento, boot `failures=0`, menú 50/49).
  5. Commit + push **normales** a `arena/9492e6b6-arandommenu`. Sin force-push,
     sin reescribir historia, sin trabajar en otra rama.
- Sin bundle regenerado + stamp, el cambio **no llega al usuario**. El watermark
  "UI Settings · vNNN" en el menú es como el usuario verifica la versión.

## v162 — Shift Lock, Shaders que no hacía nada, coste de los rayos (2026-10-30)

Detalle y tablas: `docs/FIXES-v162.md`.

- **Shift Lock / ratón libre (causa encontrada).** El menú pedía el cursor al
  abrirse y al cerrarse **escribía siempre** un valor, pisando el `LockCenter`
  que el juego acababa de poner (mismo atajo) y liberando a `Default` un
  `LockCenter` capturado al entrar. Además peleaba con el juego cada frame.
  Reglas nuevas: solo se deshace lo que escribió el menú, nunca se escribe
  `LockCenter`, y tras 8 reafirmaciones en 1 s el menú cede. Test:
  `tools/test_menu_cursor.py` (8 comprobaciones sobre el bloque real).
- **Shaders no hacía nada (dos causas).** `apply()` salía en la primera línea
  porque `card.Enabled` todavía es `false` dentro del callback del interruptor
  (ahora usa un flag propio), y los valores por defecto eran neutros (Look
  `None`, saturación/contraste/brillo 0). Ahora `Look = Cinematic`, bloom 0.6,
  sun rays 0.2: se enciende y se ve. Test: `tools/test_shaders.py`.
- **Lag spikes.** Lo único que v161 añadía por frame era el chequeo de cuerpo
  fantasma (hasta 13 rayos/frame con Auto Shoot): ahora máximo 5 rayos cada
  0.15 s. Para el resto, **UI Settings → Perf report** imprime el informe,
  muestra un resumen y reinicia el contador de spikes: pulsar, jugar un minuto,
  pulsar otra vez. Si dice `menu 0.30+0.10 ms`, el menú no es el culpable.
- **Menu scale** (0.7–1.3) en UI Settings, guardado en `UI.MenuScale`. No había
  ningún cambio de tamaño entre v139 y v161 (cardHeight, optionRowHeight,
  WINDOW_WIDTH y shape.scale idénticos), así que la escala es ahora un número
  en vez de una decisión de código.

## v161 — Prediction con lazo cerrado por vía + módulo Shaders (2026-10-30)

Detalle, tablas y límites: `docs/FIXES-v161.md`.

- **El lazo de plomo vuelve, con frenos.** Desde v120 `leadError` se medía y se
  tiraba a la basura. Ahora se aplica con 3 muestras mínimas, tope ±60 ms
  (`MAX_LEAD_CORRECTION`) y paso máximo de 20 ms por confirmación
  (`LEAD_SLEW_PER_SAMPLE`) para no oscilar.
- **Cubetas por vía.** Bullet y CFrame/Silent aprenden por separado
  (`Prediction.gunAim(target, muzzle, mode)`); el cuchillo usa la cubeta neutra
  y no hereda sesgo de pistola. Replay offline: error medio de plomo 15,4→9,3 ms
  (sesión v159, 4 confirmaciones) y 39,6→26,7 ms (sesión v157, 10) con mediana
  23,4→5,2 ms. Es el mecanismo, no hit-rate.
- **Suelo:** el clamp vertical ya no puede levantar la puntería más de 6 studs
  (`MAX_FLOOR_LIFT_STUDS`). Sobre 411 muestras aéreas de 13 sesiones: 3,07→2,55
  studs de error vertical medio, y la peor sesión 17,62→4,62.
- **Cuerpo fantasma:** si la línea de tiro cruza una parte invisible y sin
  colisión (ragdoll/`CoinVisual`), se prefiere otro punto del mismo cuerpo
  (`avoidGhostAim`, export `core.describeRayHit`); nunca se rechaza el disparo.
- **Dos fallos de la sesión v159 no eran de plomo:** `4:12` terminó a 0,24 studs
  del torso tapado por `Raggy.HumanoidRootPart` (transparency 1, canCollide
  false) y `4:14` disparó a un objetivo en `Freefall` con `hitPart = CoinVisual`.
- **Módulo universal nuevo `Shaders`** (Render): color grading + bloom + sun
  rays solo con post-proceso del motor, sin bucle y con limpieza total al
  apagar. Presets que se suman a los sliders, no los sobrescriben.

## v160 — Auditoría de rendimiento (2026-10-29)

El usuario reportó lag y pidió verificar si lo causa el executor o el menú, en
MM2 y Universal. Detalle y tabla de hallazgos: `docs/FIXES-v160.md`.

- **Diagnóstico que ya existe y ahora sirve:** overlay `Session Info` muestra
  `FPS`, `Ping`, `Menu X+Y ms` y `Spikes`, y el scheduler avisa por consola si
  una tarea pasa de 3 ms o un frame de 45 ms, nombrando el módulo. Con el menú
  por debajo de ~1.5 ms y FPS malo, el culpable no es el menú. También
  `print(state.perfReport())`.
- **Etiquetas:** las 33 tareas por frame de MM2 y Universal tienen nombre
  (`MM2 Auto Shoot`, `MM2 Knife Throw`, `Spider`, `Noclip`, `Anti Void`…). Antes
  muchas se reportaban como `task`.
- **Corregido:** el muestreador de cuchillos ya no queda conectado para siempre
  tras el primer lanzamiento; Auto Shoot evalúa las compuertas baratas (shot
  pendiente / remote / arma) ANTES de predecir y raycastear; Spider lee input
  antes de construir params y lista de jugadores (y la refresca a 2 Hz);
  Anti Void deja de reescribir CFrame/Size/Transparency cada frame; las filas de
  estadística (`addStatOption`) solo escriben `Text` cuando el texto cambia.
- **Nuevo control permanente:** `tools/audit_performance.py`, ejecutado por
  `tools/validate.sh`. Analiza los 72 callbacks por frame, exige autolímite a
  quien raycastea o enumera instancias, exige etiqueta en MM2/Universal y exige
  `disconnectFeatureConnection` para cada registro (una conexión que nadie
  desconecta es CPU permanente al apagar el módulo).
- Las bases BedFight/TRS/VD/X2 tienen bucles propios sin limitar; la auditoría
  los lista como información porque no se cargan en MM2.

## v159 — Knife: fuera toda especulación; WallCheck real y solver consistente (2026-10-29)

El usuario rechazó el invento de "aperturas" de v158 («no mejora nada, quita
esa
cosa», en resumen): **no quiere que el cuchillo apunte a nada que no sea un
objetivo visible**. Detalle: `docs/FIXES-v159.md`.

- **Eliminado por completo** `resolveSpeculativeAim` y sus cuatro usos. Sin
  objetivo visible no hay lanzamiento: `Auto Knife Throw` gasta cuchillo solo
  con objetivo válido y visible; el redirect nativo devuelve el aim original
  del juego. Estado del módulo: `No visible target` / `Target blocked ·
  WallCheck`.
- **WallCheck es ahora la única garantía y es estricta**:
  1. el helper compartido se llama con `strict = true`, así una barrera
     invisible pero sólida (Transparency 1, CanCollide true) frena el cuchillo,
     cosa que el primer pase del gun sí salta;
  2. el trayecto se prueba como **corredor de 5 rayos** (±0,45 studs), no una
     línea matemática, así una baranda o poste no se cuela entre muestras;
  3. **el cuerpo tiene que verse AHORA**, no solo el punto predicho: un punto
     que asoma por la esquina ya no se acepta (era el "cuchillo a través de la
     pared").
  Ningún rayo del corredor usa un raycast crudo: usan la misma regla estricta,
  o una decoración no-colisionable bloquearía el tiro.
- **Predicción**: `knifeAim` resuelve el intercepto a **punto fijo** (hasta 4
  pasadas, corta a 1e-4 s) en vez de una sola re-solución; así
  `|punto - mano| == velocidad × flightSeconds` deja de ser aproximado cuando
  el objetivo gira o frena. En el camino aéreo se **recalcula el tiempo de
  vuelo** con la distancia real al punto balístico (antes quedaba el del
  cálculo de cuerda).
- **Selección de objetivo por tiempo de vuelo**, no por distancia bruta: un
  cuerpo más lejos que corre hacia el cuchillo se impacta antes que uno más
  cercano parado, y antes = menos error de predicción. Bonus Sheriff/Hero
  −0,08 s. `findTarget` usa el modo barato (solo visibilidad del cuerpo) y el
  corredor se comprueba con el origen vivo justo antes del paquete.
- Se mantiene el rechazo de cadáveres de `isPlayerAlive`/`bodyIsAlive`
  (`Health 0`, `Dead`, `Physics`, atributo `Dead`).
- Pruebas: `tools/test_mm2_knife_targeting.py` nueva (mapa de cajas con
  `isWeaponPathClear` REAL de base.lua: pared, barrera invisible sólida,
  decoración, poste en el corredor, esquina, cadáveres, tiempo de vuelo y
  toggle). `test_mm2_knife_equip.py` reescrita al contrato "nada visible = nada
  se gasta". `test_mm2_precision.py` exige la identidad
  `velocidad × vuelo` en suelo y en aire. `test_mm2_knife_openings.py`
  (aperturas) **borrada**.

## v158 — Knife apunta a aperturas, no a enemigos ocultos ni cadáveres (2026-10-29) — aperturas retiradas en v159

El usuario reportó que el Knife especulativo apuntaba a enemigos detrás de
paredes y a enemigos muertos en el piso, «prediciéndoles», en vez de apuntar a
aperturas estratégicas. Detalle completo: `docs/FIXES-v158.md`.

- `resolveSpeculativeAim` ya **no usa ninguna posición de jugador**. Antes
  centraba radios 4/9/16 studs en el elegible oculto más cercano; por eso con
  WallCheck encendido el redirect nativo apuntaba a través de la geometría.
  Ahora muestrea 16 rumbos alrededor de la mirada de cámara (o del personaje),
  descarta paredes a menos de 16 studs y elige el carril con suelo, hueco y
  línea despejada, puntuando **primero la dirección mirada**, luego la
  profundidad y el ancho de la boca del carril. El carril nunca es un objetivo
  ni un hit confirmado.
- `isPlayerAlive` (base.lua) rechaza `Health 0`, estado `Dead`/`Physics` y
  atributo `Dead`, no solo salud. El predictor (`Prediction.lua`) aplica la
  misma regla y devuelve `nil, "dead target"`; las pistas se descartan en el
  muestreo, no 0,5 s después.
- Pruebas: nueva `tools/test_mm2_knife_openings.py` con mapa analítico (puerta,
  pared, sala sellada, borde de suelo, cadáver); `test_mm2_knife_equip.py`
  ahora exige que el carril NO se construya alrededor del rival oculto;
  `test_mm2_precision.py` cubre la retirada de cadáveres.
- Sigue sin probarse Volt, servidor, daño ni hit-rate; los pesos del puntaje son
  heurística sin calibrar.

## v157 — contrato Knife manual y simulación MM2 (2026-10-29)

- La copia de cliente de TestingStuff (`place, source.rbxlx`, blob
  `755f47708dfbe83a5eaad25d5a60a5a36788dcf6`) devuelve CFrame tanto en
  `GetMouseTargetCFrame` como en `GetTargetPosition`. Knife Throw ahora respeta
  ese contrato en ambos redirects; antes el segundo devolvía Vector3 y el mock
  incorrecto lo exigía. El test actualizado usa un consumidor CFrame y prueba
  objetivo, carril especulativo, caída al original con argumentos, tool sin
  equipar, OFF y restore. Una copia antigua no demuestra que el juego actual o
  Delta invoquen esta ruta; falta prueba live.
- Auto Shoot Bullet/CFrame no hacen un fallback después de que el helper común
  rechace o falle: así no saltan una negativa ni mandan otra solicitud incierta.
  El fallback solo se usa si no existe el helper; respeta WallCheck y propaga un
  error local de FireServer. Un error incierto también activa el pacing local
  en los tres modos. `pcall` exitoso significa envío local, no hit ni aceptación.
- `tools/test_mm2_trajectory_simulation.py` ejecuta el predictor actual en 486
  casos sintéticos; compara posición simulada con una hipótesis explícita de
  RTT + 25 ms y Knife recto de velocidad constante. En el salto de ejemplo, el
  estado Freefall cerca del ápice con velocidad vertical casi 0 hace que el
  predictor mantenga la altura; una prueba anterior exige ese comportamiento
  ante estados de salto engañosos. No se cambió el modelo sin datos que permitan
  distinguir ápice verdadero de estado/velocidad replicados incorrectamente.
  Giros o paradas futuros causan grandes errores de predicción como es de
  esperar. Estos valores NO son tasas de acierto del servidor. Resultados y
  alcance: `docs/FIXES-v157.md`.
- `tools/test_mm2_auto_shoot_dispatch.py` prueba rechazos, errores, una llamada
  que envía antes de lanzar error, WallCheck del fallback y salida correcta.
  `test_mm2_experimental.py` comprueba además el pacing y estado incierto tras
  error. Validación final: 90 fuentes, 76 suites, boot `failures=0` y menú
  49/48 tarjetas PASS. Esto no supone compatibilidad live.

## v156 — migración completa y experimentos MM2 (2026-10-29)

El usuario eligió expresamente usar **todo** el árbol de la rama
`arena/76bc3f2f-arandommenu` commit `9395998` como base, no solo MM2. Se
mantuvo la rama fija de esta sesión `arena/9492e6b6-arandommenu` y el loader
apunta a ella. Esto revierte también X2 y funciones universales al estado de la
rama elegida; las versiones anteriores de esta sesión quedan en su historia
hasta `f968cee`, no se debe afirmar que X2 v155 sigue instalado. Documentación
v138.x/v139.x de abajo es histórica de la rama elegida.

- Eliminados del catálogo, disco y boot `Safe Walk`, `StrafeBot` y `TriggerBot`.
  Se retiraron o adaptaron solo pruebas que exigían módulos eliminados; los
  demás juegos conservan la implementación de la rama migrada.
- `Gun Aimbot > Aim method` y `Auto Shoot > Mode` tienen `Experimental` como
  tercer modo, solicitado en **ambas** tarjetas. Política compartida: con
  distancia >= 30 studs y velocidad horizontal >= 8 studs/s selecciona CFrame;
  en otro caso Bullet. Es una heurística inicial, no hay datos que demuestren
  que sea la mejor opción. Envía solo una ruta por intento, respeta WallCheck y
  Proximity propios de cada tarjeta y no dispara una segunda ruta tras un
  rechazo incierto. Status distingue envío de impacto. Los controles y otros modos
  siguen independientes; no gira la cámara. WallCheck, Macro, destino y
  seguridad en Gun Aimbot, y WallCheck/Proximity/Aura en Auto Shoot, se guardan
  por separado para Bullet, CFrame y Experimental, con migración del estado
  legado al modo activo.
- `Knife Throw` intenta primero el predictor existente. Si no encuentra una
  trayectoria visible, busca hasta tres radios en torno al enemigo elegible más
  cercano; sin ninguno busca caminos a 24/45/70 studs alrededor del personaje.
  **Retirado en v158 y eliminado del todo en v159:** el cuchillo ya no
  especula. Sin objetivo visible y con el cuerpo visible ahora, no se envía
  nada.
  Exige suelo y un raycast despejado, incluso con WallCheck apagado; son carriles
  especulativos, no detección de jugadores ni una prueba de hit. No especula si
  hay jugadores protegidos, si no es Murderer, está muerto o se conoce el fin de
  ronda; conserva el Delay y el equip con espera antes del remote. Cachea el
  análisis 0,4 s, revalida el raycast al usarlo y rota la dirección tras cada
  envío especulativo. Sirve tanto al redirect de WeaponService como a Auto Knife
  Throw, que puede gastar lanzamientos aun con nadie visible. Status lo indica.
- `tools/test_mm2_experimental.py`, `test_gun_pointblank.py` y
  `test_mm2_knife_equip.py` prueban selector, un solo envío, opciones, paredes,
  protegido, ronda, suelo, equip, OFF, delay, carriles sin objetivo y redirect
  en mocks. `test_mm2_mode_persistence.py` comprueba restauración entre arranques
  y el boot verifica cambios entre modos. No prueban Roblox, Delta, anticheat, aceptación del servidor ni
  aciertos. Faltan pruebas en vivo para ajustar heurística y tasa de acierto.
- `tools/validate.sh`: 74 suites, boot y auditorías de menú; los resultados de
  versiones anteriores no equivalen a prueba en juego.

> **v138.1 (2026-10-27):** esta rama sirve v138 con un parche encima. Se borró
> **Auto Fling Selected Target** (se restauraba del guardado al inyectar y
> flingeaba la partida sola) y el pulso de Infinite Yield `walkfling` —el que
> limpia `CanCollide` y el usuario lee como noclip— pasó a ser la opción
> **Touch Fling**: solo corre mientras esa opción está encendida, y al apagarse
> devuelve las colisiones. La tarjeta `Fling` es un grupo y ya no lanza nada.
> Evidencia: `docs/FIXES-v138.1.md`.
>
> **v138.2 (2026-10-27):** Walk Fling es su propia tarjeta universal
> (`src/games/universal/Blatant/WalkFling.lua`, Exploits, orden 8) y el Fling de
> MM2 usa **SkidFling** (copia de la implementación pública de zqyDSUWX:
> CFrame sobre la víctima + `9e7`/`9e8` + BodyVelocity de anclaje +
> `FallenPartsDestroyHeight = 0/0` restaurado). **Anti Void** es ahora una
> plataforma local invisible (`Wurst_AntiVoidPlatform`, `CanQuery=false`,
> `CanTouch=false`, `Transparency=1`, `Distance` 1–40) que no baja al caer.
> **Anti Fling** es tarjeta propia (`src/games/universal/Movement/AntiFling.lua`,
> Utilities, orden 5) que recorta impulso planar/subida/caída/giro cada frame y
> respeta `fling`/`walkfling`. Evidencia: `docs/FIXES-v138.2.md`,
> `tools/test_walkfling.py`, `tools/test_fling_skid.py`, `tools/test_antivoid50.py`.
>
> **v138.3 (2026-10-27):** **Fling** dejó de ser tarjeta de MM2 y es un módulo
> universal (`src/games/universal/Blatant/Fling.lua`, Exploits, orden 7,
> `configKey = Universal.Fling`). Solo tiene **Target player** como lista (se
> borraron `Select Target`, `targetChoices` y las conexiones PlayerAdded/Removing
> que lo alimentaban); el texto se resuelve exacto → prefijo → subcadena. Los
> botones de rol resuelven `state.mm2Core` en el clic y avisan fuera de MM2.
> `state.mm2PerformFling` / `state.mm2FlingStep` los publica este módulo y el
> harness los verifica tras el arranque. **Walk Fling** ya no tiene slider
> (`POWER = 10000`, `noOptions = true`). Evidencia: `docs/FIXES-v138.3.md`.
>
> **v138.4 (2026-10-27):** la mecánica de **Fling** se reescribió copiando
> `SkidFling` de YARHM tal cual. El bug era el pin: nuestro `BodyVelocity` iba con
> `Velocity = 0` (ancla) y escrituras de `AssemblyLinearVelocity` /
> `CustomPhysicalProperties` por frame (el "círculo" y el personaje que
> "desaparece"). Ahora es `BodyVelocity` `"EpixVel"` con `Velocity = (9e8, 9e8, 9e8)`
> y `MaxForce = (1/0, 1/0, 1/0)`, poses `RootPart.CFrame` +
> `SetPrimaryPartCFrame` + `RootPart.Velocity = (9e7, 9e7*10, 9e7)` +
> `RotVelocity = 9e8` con `task.wait()` entre pose y pose, y volver a casa con
> `OldPos * CFrame.new(0, .5, 0)`. `state.mm2FlingStep` (Auto Win) usa el mismo
> golpe y limpia su pin a los 0.5 s. Evidencia: `docs/FIXES-v138.4.md`,
> `tools/test_fling_skid.py` (6 suites).
>
> **v138.5 (2026-10-27):** el Fling "terminaba" en medio segundo porque el `until`
> comparaba `targetPlayer.Parent ~= Players` con el **cloneref** del servicio (otra
> referencia ⇒ siempre distinto) y cortaba tras 6 poses sin contacto útil. También
> `type(velocity) == "table"` era falso con un `Vector3` real (userdata), así que la
> velocidad se leía 0 y nunca se detectaba el éxito. Ahora: `playerStillHere()` por
> `FindFirstChild`, `partSpeed()` por `pcall`+`Magnitude`, `nowSeconds()` (`tick()` →
> `os.clock()`) con tope de 600 poses, `guardedRun()` que nunca deja `flingRunning`
> pegado, pin con reintento a `1e9` si `math.huge` falla, rescate de 2 frames si la
> víctima no se movió, y notificación con poses/velocidad reales +
> `state.mm2LastFling`. Evidencia: `docs/FIXES-v138.5.md`,
> `tools/test_fling_skid.py` (7 suites).
>
> **v138.6 (2026-10-27):** **Auto Farm** dejó de caerse al vacío: el vuelo de
> Below lo hace `applyBelowControl` en `RunService.Stepped` (antes de física) con
> control de altitud proporcional que cancela la gravedad; antes se escribía solo
> desde el Heartbeat y la gravedad se acumulaba entre escrituras. El "rebase" de
> `homeCFrame` ya no se calcula desde un cuerpo que está debajo del mapa (eso bajaba
> el objetivo 7 studs por tick hasta el fondo). `clampBelowTarget`/`floorBudgetY`
> limitan la profundidad y `recoverFromVoid` devuelve el cuerpo dentro del mapa.
> **Walk** funciona: "Stay Under" ya solo aplica a Below (antes enterraba el cuerpo
> de Walk), `engage()` normaliza PlatformStand/NoClip/hitbox una vez por sesión, no
> se re-ejecuta `restoreCharacter` cada tick y hay carry por velocidad si
> `Humanoid:Move` no mueve. **Menú**: el orden de las tarjetas dentro de cada
> ventana es **aleatorio por sesión** (LCG + atributo `FeatureSortRank`), no
> alfabético, con toggle *Settings → Random Card Order*. Evidencia:
> `docs/FIXES-v138.6.md`, `tools/test_autofarm_motion.py` (4 suites, con gravedad
> simulada y tick congelado), `tools/test_mm2_auto_farm.py`,
> `tools/gen_full_boot_harness.py` (prueba de orden no alfabético).
>
> **v138.7 (2026-10-27):** Auto Farm vuela **a través** de las monedas (sin la
> parada corta): pulso de touch al acercarse, objetivo 26 studs más allá al pasar,
> moneda barrida saltada 2.5 s y compromiso de rumbo 1.2 s para no ping-ponguear;
> `holdAltitude` mantiene la altura cuando no hay objetivo. `Fling Murder/Sheriff
> after reset` pasan a **after full bag** con migración de la clave guardada. Se
> eliminan `Stay Under When Round starts` (y su estado muerto) y, en UI Settings,
> `Random Card Order` y `Rainbow`. El **loader** ya no cachea fuentes en disco:
> bundle → memoria → un GET, y purga `Wurst/src` en segundo plano. El antiguo
> abridor circular (círculo + `≡`) se crea oculto y solo aparece cuando
> `state.menuReady` (fin de todas las secciones). Evidencia: `docs/FIXES-v138.7.md`,
> `tools/test_autofarm_motion.py`, `tools/test_loader_launcher.py`.
>
> **v138.8 (2026-10-27):** se revierte el **fly-through** del Auto Farm (velocidad
> proporcional, punto 26 studs pasado la moneda y compromiso de rumbo: "se movía
> flojo" y "hacia ninguna trayectoria") y vuelve el ir-y-cobrar, pero **sin la espera
> de ~1 s**: velocidad plena, primer touch en el mismo frame de llegada
> (`lastTouchPulse = 0`), `DWELL_SECONDS = 0.3` con `RETRY_SECONDS = 1.5` /
> `RETRY_LIMIT = 3` y cambio de objetivo inmediato al desaparecer la moneda.
> **Stay Under When Round starts** vuelve y aplica a **ambos** modos; al salir del
> escondite el cuerpo va a la superficie en `homeCFrame` (antes raycast desde debajo
> del suelo, que era lo que dejaba el cuerpo enterrado en Walk). **Anti Fling** queda
> sin opciones (`noOptions = true`, umbrales 2.5× WalkSpeed). Evidencia:
> `docs/FIXES-v138.8.md`, `tools/test_autofarm_motion.py` (7 suites).
>
> **v138.9 (2026-10-27):** las tarjetas vuelven al **orden alfabético** (fuera
> `nextRandomRank`, `FeatureSortRank` y el mapa curado `ordered`); se elimina el
> `fallbackManifest` de `Wurst.lua` (un solo catálogo: `Manifest.lua`) y las copias
> de categorías/alias de `ClickGui.lua` (`categories` + `cards` viven en el
> catálogo). Nuevo `tools/card.py` (`list` / `add --stub` / `remove` / `window` /
> `check`) para dar de alta o borrar módulos y ventanas en un comando; `check` corre
> en `validate.sh`. **Fling**: opciones Power (3 = YARHM exacto), Duration,
> Prediction y Retries, adelanto por `ping/2` en cada pose, re-resolución de las
> partes del rival, mínimo de 12 poses y segunda pasada con boost ×1.5. Evidencia:
> `docs/FIXES-v138.9.md`, `tools/test_fling_skid.py` (10 suites).
>
> **v139.0 (2026-10-27):** pase de rendimiento ("tengo lag"). El `TaskManager` se
> mide a sí mismo (`state.performance`, `state.taskManager:Stats()`,
> `state.perfReport()`, aviso `[Wurst:Perf]` a partir de 3 ms por frame) y cada
> tarea lleva el nombre del módulo. Arreglado: `Prediction` cachea partes y pierde
> la closure por jugador; `MM2/base.lua` cachea lobby/mapa y el cooldown de fallo
> escribe `Text`/`Size` a ~12 Hz y sólo si cambió; Coin ESP reconcilia adornos a
> 2 Hz; Auto Farm sin `pcall` por moneda; **Noclip** pasa a evento + barrido a 5 Hz
> (adiós `GetDescendants()` a 60 Hz); HUD sólo anima si hay rainbow/pulso y
> reutiliza la tabla de color; los overlays flotantes no hacen nada si están
> apagados; clave duplicada `MM2AutoShoot` (disparo fantasma) renombrada. El test
> nuevo `tools/test_scheduler.py` (8 suites) destapó el bug del swap-remove al
> autodesconectarse una tarea. Harness: 6 tareas always-on, todas con nombre, y
> 8 toggles seguidos no dejan conexiones. Evidencia: `docs/FIXES-v139.0.md`.
>
> **v139.1 (2026-10-27):** "tengo lag spikes" + versión. `PRODUCT.version` pasa de
> `0.1 Beta` a **`0.823 Release`**. Se añade detector de hitches en
> `state.performance` (`spikeCount`, `worstSpikeMs`, `spikeAgo`, `spikeTask`) con
> aviso `[Wurst:Perf] frame spike X ms (menu Y ms · tarea)` como mucho cada 5 s y
> línea nueva en `state.perfReport()` y en *Session Info*. Se quitan asignaciones
> por frame: pool de muestras en `Prediction` (~700 tablas/s menos) + lista de
> jugadores cacheada 0,25 s; `ImproveFps` reutiliza el array del barrido;
> `Render:Label` ya no escribe `Size`/`BackgroundTransparency` si no cambian (los
> ESP completos se benefician); `Nametags` deja de reasignar `Font` y de re-medir
> texto cada frame; el HUD del menú sólo redibuja la fila que cambió. Evidencia:
> `docs/FIXES-v139.1.md`.

> **v139.2 (2026-10-27):** "¿Shoot y Auto Throw son lo mejor?". Estudio físico del
> personaje (17 studs/s de mediana, `moveDirection` <0,08 en el 8 % de las
> muestras ⇒ el error del predictor es irreducible) y dos arreglos medidos:
> **(1) pistola** — el rayo del servidor no muere en nuestro endpoint; 2 de 10
> tiros de v139.1 acabaron en el `HumanoidRootPart` de un inocente. El punto de
> mira pasa a elegirse por lo que hay **detrás** (`describeRayBeyond`, sondeo
> 12 → **200** studs, `INNOCENT_DANGER_STUDS = 35`): si ningún punto del cuerpo
> deja una línea limpia, el disparo se **salta** con motivo visible. Opción
> nueva `Avoid innocents` (ON). **(2) cuchillo** — `throwKnife` ya no dispara
> desde la mochila (`ensureEquipped`: espera a que el tool cuelgue del
> personaje; de 13 activaciones sólo 9 produjeron cuchillo y los 4 perdidos
> salían del `RightHand` de respaldo) y el bucle cachea la puntería 1/15 s
> (13 resoluciones/s a 60 FPS en vez de 61). Telemetría nueva: `missReason` +
> `gunMisses`/`gunMissReasons` en el resumen y `closestApproachStuds` /
> `passedThroughBody` en `projectile-observed`. **El lead no se tocó.** Evidencia:
> `docs/FIXES-v139.2.md`, `tools/test_gun_corridor.py`,
> `tools/test_mm2_knife_equip.py`.

> **v139.3 (2026-10-28):** "¿está bien que el wallcheck detecte el cuerpo del
> murderer y no dispare?". **No**, pero el cuerpo del objetivo nunca bloqueaba
> (está excluido desde v106): lo que bloqueaba eran dos comprobaciones nuestras.
> **(1)** En Silent, la construcción "Through" perfora a lo largo del movimiento
> del objetivo; si el asesino **corre hacia ti**, esa dirección apunta a ti y el
> segmento acababa en el cañón (`muzzle 0,5 · endpoint 0,5`) → `"Invalid shot
> geometry"`. Dentro de **`POINT_BLANK_STUDS = 6`** el punto de mira pasa a ser el
> `HumanoidRootPart` sin lead y el disparo se autoriza **desde el cañón real**
> (`variant = "PointBlank"`). **(2)** `OVERSHOOT_PROBE_STUDS` se había subido a
> 200 en v139.2 y esa constante la compartía `bystanderBlocks`, cuyo rayo sólo ve
> personajes: un inocente 108 studs detrás **y detrás de una pared** bloqueaba
> todos los disparos Silent. Ahora hay **`BODY_OVERSHOOT_STUDS = 12`** (segmento
> autorizado) y **`CORRIDOR_PROBE_STUDS = 200`** (corredor), y el sondeo de
> "cuerpo detrás" usa `describeRayBeyond`, que **se detiene en la primera
> pared**. Un cadáver (cuerpo sin dueño, salud 0) ya no cuenta como inocente. Los
> rechazos del corredor se registran con `reason = "corridor"`. **El lead no se
> tocó** (error mediano 12 ms). Evidencia: `docs/FIXES-v139.3.md`,
> `tools/test_gun_pointblank.py` (25 comprobaciones).

> **v139.4 (2026-10-28):** cuatro puntos de revisión, los cuatro reales.
> **(1) Pistola:** `state.mm2FireSilentShot` se llamaba sin opciones (el
> WallCheck propio de Auto Shoot se perdía) y forzaba `continuous = true`, que
> hacía `useRaw = true` → `safeToSend` **no comprobaba nada**: sólo existía el
> guardián de origen cercano, desde ~1 stud del objetivo, nunca desde la pistola.
> Ahora raw sólo salta el guardián del origen cercano y **siempre** valida la
> línea del cañón; los fallbacks de AutoShoot/AutoWin/AutoFarm ya no son un
> bypass (misma regla de geometría); `silentSpawn` se usa de verdad en vez de un
> `"Through"` fijo. **(2) Cuchillo:** `ThrowSpeed` ahora se pasa a
> `prediction.knifeAim(target, origin, speed)` (antes solo lo usaba el respaldo
> local). **(3) Cuchillo:** el barrido de partes sumaba dos veces el desplazamiento
> del torso (`predicted - root.Position` ya contenía `aimOffset`); ahora usa
> `aimInfo.capturedPosition`. **(4) Telemetría:** `Prediction.getHistory` no
> devolvía `aimOffset` (el error se medía root-vs-torso: sesgo falso de 1,5 studs)
> y el tope de 36 puntos cortaba por el lado viejo, perdiendo **las muestras
> nuevas**; ahora se decima conservando el span y la última. Ese error alimenta
> `leadUncertainty` → barrido adaptativo de Silent. Evidencia:
> `docs/FIXES-v139.4.md`, `tools/test_gun_silent_constructor.py`,
> `tools/test_mm2_knife_aim.py`, `tools/test_telemetry_aim_offset.py`.

## 1A. X2Duels (MVS): estructura MM2, evidencia y contratos

- PlaceIds registrados: `92876937625630` y el MVS anterior `135856908115931`.
  Fuentes activas: `Rules.lua`, `base.lua`, `Other/AutoFarm.lua` y sus dos
  perfiles. La sección de menú existente se llama `MVSD`; `Render/TeamESP.lua`
  fue eliminado y no debe volver como módulo independiente.
- Hay exactamente cinco tarjetas X2: **Auto Farm** y **Auto Win** en
  **Utilities**, **Silent AIM**, **Kill Aura** en Combat y **Hitbox** en
  Exploits. El único TriggerBot es el universal, adaptado al core X2 para
  Gun/Knife; no se debe crear otra tarjeta.
- Silent AIM contiene las secciones Gun y Knife. Auto Shoot sigue el master y
  muestra Legit/Silent. Knife Throw es una subopción de Silent AIM: intenta la
  activación nativa en cada tick, sin slider ni temporizador de intervalo;
  solo espera el windup de la propia animación. Desktop usa mouse2 + Activate;
  touch usa y restaura ForceThrow. No se inventan argumentos de ThrowEvent.
- La keybind de Silent AIM se registra con `state.bindFeatureActivationKey` y
  ejecuta la acción nativa solamente con `Sender = Button`; nunca cambia el
  toggle maestro. Con `Sender = CFrame`, Auto Shoot/native activation funciona
  sin esperar ese botón. La activación comparte ancestry del objetivo, Team
  Check, Wall Check y raycast antes de disparar.
- Auto Win es únicamente una tarjeta de estado de sesión: `Wins`, `Time Played`,
  `Kills` y `Loses`. No tiene ráfagas, selección automática de combate, límite
  de cinco victorias, Play Again, clicks GUI ni `RematchTeleport`. Las wins
  provienen de resultados/notificaciones locales explícitos; kills usan el
  tercer Player observado en `Combat/DestroyBody`; las muertes locales se
  deduplican por ronda para Loses. Son contadores cliente observados, no una
  garantía de autoridad del servidor.
- Auto Farm busca monedas Halloween `PumpkinCurrency_*` y `Farms/PumpCoins`
  dinámicos por contacto nativo. Los podios resuelven `StringValue`/`ObjectValue`
  contra jugadores y equipos; sin una entrada enemiga no se farmean granjas y
  ningún modelo cercano se considera propio por proximidad. El teleport usa el
  CFrame de la moneda invisible con TouchTransmitter, no el root del dueño.
  Reintenta y restaura el CFrame al apagarse. Un intento no se cuenta como
  moneda confirmada. El RBXL guarda algunas partes con `CanTouch=false`; la
  recolección real sigue pendiente y no se inventan argumentos para
  `CollectEventSpawnable`.
- Team Check falla cerrado: usa los atributos MVS `Team`/`Game`, rechaza FFA,
  lobby y lados desconocidos como objetivos y no cae al `Team` común de Roblox.
  El mismo resolver alimenta combate y RoleColors del ESP universal
  (PlayerESP/Chams/Nametags): enemigo rojo, aliado verde y desconocido ámbar.
  Unknown sigue fail-closed para combate con Team Check activo; desactivarlo
  debe ser explícito. No convertir una pantalla ambigua en una victoria.
- El log `2026-10-24T16_49_55Z.log` de TestingStuff capturó `DefaultGun` (`fire`
  sin argumentos y `showBeam` con dos Vector3 + Handle), llamadas nativas de
  `DefaultKnife`, `PlayerRespawned` y `SetDead`. La réplica de Beam/PlaySound no
  demuestra daño ni kills. No se inventan argumentos ni se reintroducen
  GUID/remotes históricos; la activación sigue siendo la ruta nativa del Tool.
  El extractor independiente `tools/X2DuelsDecompiler.luau` vuelca fuentes,
  bytecode, inventario con parents y argumentos entrantes/salientes; su guía es
  `tools/X2DuelsDecompiler.md`.
- `python3 tools/test_x2duels.py` ejecuta 67 reglas, contratos y un boot real
  del bundle con cinco tarjetas, keybind de acción sin toggle, CFrame sin
  botón, ambos caminos nativos del cuchillo, estadísticas deduplicadas,
  contacto/restauración de pumpkin, podios y granjas amigas/enemigas con
  PumpCoins invisibles y cleanup. `python3 tools/test_x2duels_decompiler.py`
  valida el extractor con DataModel simulado. Todo ello es validación offline,
  no aceptación del servidor ni precisión live.

## 1B. Cómo construir un game sin mezclar responsabilidades

Esta es la guía de diseño para MM2, X2Duels/MVS y cualquier juego nuevo. La
referencia de estructura es `games/MM2`; no se copian sus remotes, tiempos ni
argumentos a otro juego sin evidencia propia. La primera pregunta no es «¿qué
nombre suena más potente?», sino **qué mecanismo controla el módulo, qué estado
necesita y qué puede restaurar al apagarse**.

### 1. El mapa de responsabilidades

| Lugar | Responsabilidad | Ejemplos | No debe contener |
| --- | --- | --- | --- |
| **Silent AIM** | Seleccionar un objetivo y dirigir/activar ataques a distancia o proyectiles. | Shoot, Gun, Knife Throw, flechas, cohetes, lanzamientos y otras variantes de proyectil. | Swings cuerpo a cuerpo, un segundo selector de equipos, una tarjeta independiente por cada skin. |
| **Kill Aura** | Ataques melee de corto alcance contra objetivos válidos. | Knife, machete, sword, bat, axe y cualquier arma cuyo ataque sea un swing/contacto cercano. | Redirección de proyectiles, Silent Ray, predicción de una trayectoria o un ThrowEvent inventado. |
| **TriggerBot** | Reaccionar a una condición ya visible/validada y activar la acción correspondiente. | Disparar cuando el objetivo está bajo el crosshair, usando el adaptador nativo compartido. | Otro Silent AIM, otro bucle de selección o una copia del módulo de cada juego. |
| **Utilities** | Automatizaciones y datos útiles que no son el control directo de un ataque o del cuerpo. | Auto Farm, Auto Win de solo estado, Auto Get Gun, Auto Unbox y ayudas de farmeo. | Hitbox, una expansión de colisiones o un módulo puesto ahí solo porque «es fuerte». |
| **Exploits** | Cambiar una propiedad o aprovechar directamente una mecánica explotable del juego. | Hitbox y manipulaciones equivalentes que tengan una razón técnica clara. | Auto Farm/Auto Win por costumbre, o cualquier tarjeta que no se pueda explicar técnicamente. |
| **Render** | Mostrar información sin decidir el combate. | PlayerESP, Chams, Nametags, HP, Arrows, Coin ESP. | Un TeamESP paralelo con otra resolución de equipos. |
| **Movement/Blatant** | Movimiento, desplazamiento o acciones físicas directas. | Speed, Fly, Teleport, Fling cuando corresponda al juego. | Estadísticas de farm o lógica de proyectiles. |

La distinción importante es **proyectil/distancia frente a melee**, no el nombre
del arma. Un cuchillo que se lanza pertenece a Silent AIM; el mismo cuchillo
cuando hace un swing cercano pertenece a Kill Aura. Si una herramienta tiene
ambos ataques, comparte el descubrimiento/equipado del Tool, pero separa las
dos rutas y sus opciones. No se duplican tarjetas ni se crean dos loops que
equipan y activan el mismo arma a la vez.

**Kill Aura no es un cajón para cualquier ataque automático.** Su alcance,
animación, swing, hit window y recovery pertenecen a la mecánica melee del
juego. **Silent AIM tampoco es sinónimo de “cualquier cosa con Silent en el
nombre”**: debe existir una selección de objetivo y una acción a distancia que
realmente se pueda redirigir o activar.

### 2. Estructura de archivos y orden de inicialización

Un game puede tener un `base.lua` pequeño o uno grande por razones históricas,
pero debe mantener estas fronteras conceptuales:

```text
src/games/<Game>/
  Rules.lua                 -- decisiones puras: equipos, Tools, resultados
  base.lua                  -- core, providers, adaptadores y coordinación
  Blatant/ o Combat/        -- ataques y módulos de combate del juego
  Other/AutoFarm.lua        -- utilidad de farmeo, si existe
  Render/                   -- presentación, nunca otra lógica de equipos
src/Profile/<PlaceId>.lua   -- sección/perfil del PlaceId
src/Wurst.lua               -- fingerprint, loader, registro y cleanup global
```

- `Rules.lua` no crea GUI ni conexiones. Expone funciones comprobables para
  normalizar equipos, clasificar herramientas, resolver relaciones y evaluar
  resultados. Un nombre de remote no es una regla suficiente.
- `base.lua` publica un único `state.<game>Core` y, cuando exista,
  `state.<game>Rules`. Los módulos usan ese core; no vuelven a escanear
  Backpack, personajes o remotes de una forma incompatible.
- El orden normal es **Rules → core/providers → módulos de combate →
  utilidades/render**. El core debe existir antes de registrar un módulo que
  lo consume. El loader debe enumerar explícitamente los archivos que realmente
  existen; un archivo retirado también se retira del loader y del bundle.
- `registerTeamProvider` y `registerRoleProvider` comparten la resolución de
  equipos con Entity, Targeting y el ESP. No se crea un ESP específico para
  arreglar colores que el provider ya puede resolver.
- Cada módulo implementa `init(runtime)` y `destroy()`, guarda sus conexiones
  en `featureConnections` o en su lista de cleanup y usa el `TaskManager`
  compartido. Al destruir: desconectar, cancelar trabajos pendientes, restaurar
  CFrame/cámara/atributos/propiedades y retirar providers que sean propios.
- La configuración se migra con una versión de layout. Las opciones retiradas
  se eliminan o migran de forma explícita; no se restaura automáticamente una
  automatización antigua solo porque su estado guardado era `true`.

### 3. Del archivo a una tarjeta visible: registro obligatorio

Hay tres hechos distintos que no se deben confundir:

```text
Estar en bundle.lua  = la fuente está disponible para el loader.
Estar en una load list = el loader ejecuta init del módulo.
createUniversalFeature = ese init registra una tarjeta y sus opciones.
```

Que un archivo compile y viaje en el bundle **no significa que se ejecute**;
que su `init` se ejecute tampoco significa necesariamente que cree una tarjeta.
Sprint es el ejemplo: se carga como módulo técnico de MM2, pero registra una
opción dentro de Speed mediante la tarjeta que ya existe.

- **Módulo universal nuevo:** añade su `{path, name, category}` a
  `src/libraries/Manifest.lua` y exactamente lo mismo al `fallbackManifest` de
  `src/Wurst.lua`. El manifest normal y el fallback no pueden describir menús
  distintos. El módulo debe devolver `init(context)` y `destroy()`; el loader
  universal llama después a cada `init` en el orden del manifest.
- **Módulo de un game:** añade la ruta a la lista explícita de
  `loadGameModule` en `src/Wurst.lua`, respetando las dependencias. MM2 exige
  que la lista cubra exactamente sus archivos; X2 carga Rules → base/core →
  AutoFarm. Un archivo como Sprint necesita aparecer ahí aunque no añada una
  tarjeta propia. Si sólo es un helper sin `init`/`destroy`, debe cargarlo su
  dueño mediante la ruta existente, no fingir que es un módulo autónomo.
- **Juego o PlaceId nuevo:** un archivo `src/Profile/<PlaceId>.lua` sólo declara
  metadata y secciones; **no registra gameplay por sí solo**. Hay que revisar
  el mapa `GAME_MODULES`, la rama de `loadGameModule`, `GAME_CHECK`, la llamada
  `registerPlaceModule`, cleanup y, cuando proceda, fingerprint. Para añadir
  otro PlaceId de un juego ya soportado, conserva el mismo module key y comprueba
  también su perfil; no clones el árbol completo.
- **Tarjeta:** dentro de un módulo ya cargado,
  `src/guis/Wurst/Code/Cards.lua:createUniversalFeature` la inserta en el
  `registry` elegido y en `allFeatures`, además de conectar búsqueda, UI y
  restauración de configuración. Por eso hay que pasar el `parent`, `registry`
  y `categoryName` correctos. El `category` del manifest identifica la entrada
  del módulo, pero no sustituye la categoría configurada al crear la tarjeta.
- **Opción dentro de una tarjeta existente:** no añadas otra entrada universal
  si el archivo no es un módulo independiente. El módulo técnico sí necesita
  una ruta de carga; después obtiene la tarjeta dueña y registra el widget, como
  hace Sprint con Speed.

Al retirar una función se aplica el recorrido inverso: quitar widget/tarjeta,
cleanup, entrada de carga y entradas del manifest/fallback que correspondan;
después regenerar el bundle. No dejar un archivo huérfano «por si acaso».

Las pruebas de esta frontera ya existen: `tools/test_manifest_sync.py` detecta
módulos universales sin registrar, paths ausentes/duplicados, divergencia del
fallback y diferencias en la lista MM2. `tools/audit_menu.py` comprueba lo que
realmente se registra al arrancar. Si se añade o retira una tarjeta, hay que
revisar también el inventario 38/37 documentado y cualquier contrato de menú;
si sólo se añade una opción, la prueba debe impedir que aparezca una tarjeta
extra. La salida final sigue siendo `bash tools/validate.sh` con boot limpio.

### 4. Cómo se crea una tarjeta y sus opciones

La API común es `createUniversalFeature` con `parent`, `registry` y
`categoryName`. Las opciones se añaden con los widgets compartidos:
`addSectionOption`, `addToggleOption`, `addNumberOption`, `addCycleOption`,
`addActionOption` e `addInformationOption`. `SetStatus` es para estado corto y
actualizable; no sustituye una explicación de seguridad ni un contador que no
existe.

- Una familia de ataques tiene **una tarjeta principal** y secciones por arma o
  mecánica. Por ejemplo, Silent AIM puede contener `Gun` y `Knife`; no hace
  falta una tarjeta `Knife Throw` separada si ambas comparten objetivo y
  sender.
- Las opciones dependen del mecanismo real. Un arma con carga puede necesitar
  `Charge`; una con timing de impacto puede necesitar `Hit Time`; una con
  críticos puede exponer `Critical` y sus ventanas `Miss/Bad/Okay` **solo si
  esos estados existen y se pueden detectar**. No se rellenan tarjetas con
  sliders genéricos que el juego no utiliza.
- Las opciones de una mecánica especial deben explicar qué significan y qué
  ocurre si el estado es desconocido. Un texto `Critical` no prueba que el
  servidor haya aceptado un crítico; un resultado `Miss` tampoco debe contarse
  como daño.
- La keybind de una tarjeta puede ser de toggle o de acción, pero no ambas a la
  vez. Para una acción como Shoot se usa `state.bindFeatureActivationKey` y se
  asigna el callback de disparar; el callback no debe llamar al toggle maestro.
  El valor `Unknown` deja la tecla sin asignar hasta que el usuario la capture.
- Un sender `Button` espera la acción del botón/tecla. Un sender `CFrame` debe
  poder trabajar por su ruta automática sin esperar ese botón. Esta diferencia
  se prueba tanto en desktop como en touch, sin inyectar clicks para simular
  combate si existe una activación nativa.
- El estado de una opción hija no debe encender accidentalmente otra tarjeta.
  Si una subopción requiere el master, se documenta y se comprueba el gate; al
  apagar el master se cancela la acción pendiente pero se conserva la
  preferencia de la subopción cuando eso sea útil.

### 5. Adaptadores nativos y evidencia mínima

Antes de escribir un ataque se identifica la cadena real:
**input/acción → Tool o controller → animación/estado → remote observado →
resultado visible**. Se prefiere `Tool:Activate()`, el input nativo o el
controller que el juego ya usa. No se inventan `FireServer` ni argumentos por
similitud con otro juego.

- El objetivo se valida antes de activar: personaje y parte siguen en el
  DataModel, está vivo, no es el jugador local ni un objetivo protegido, la
  relación de equipo lo permite y, si existe Wall Check, el raycast no atraviesa
  geometría. La parte usada para apuntar debe ser la parte vigente, no un
  CFrame guardado de otro personaje.
- Gun/hitscan y projectile físico no son intercambiables. El primero necesita
  origen, dirección y filtro coherentes; el segundo puede necesitar posición de
  release, velocidad, gravedad, windup y recuperación. La predicción es una
  hipótesis medible, no una promesa de rewind del servidor.
- En un throw se conserva la animación y el momento de release cuando forman
  parte de la mecánica. Desktop y móvil pueden tener entradas distintas (por
  ejemplo, mouse2 frente a un atributo como ForceThrow); ambas deben restaurar
  su estado al cancelar.
- La evidencia se clasifica como **observado**, **intentado**, **confirmado por
  un evento local** o **desconocido**. Beam, PlaySound, DestroyBody, una
  animación o una llamada saliente no demuestran por sí solos daño, kill,
  recompensa ni aceptación del servidor.
- El servidor sigue siendo autoritativo. Un mock puede comprobar que se llamó
  `Activate`, que se hizo un raycast o que se restauró una propiedad; no puede
  demostrar que el juego live otorgó una moneda o una victoria.

## 1C. Cooldown, velocidad y mecánicas con timing

Esta convención evita dos errores opuestos: poner un intervalo arbitrario que
hace lento el módulo, o borrar un tiempo que la mecánica necesita para funcionar.

### Regla de la opción Cooldown

- Cuando un módulo de ataque permite añadir **delay artificial del usuario**,
  la opción simple se llama **`Cooldown`**, está expresada en segundos y su
  valor por defecto es **`0`**. No se presenta como `Throw interval`,
  `Spam interval` ni como una sucesión de sliders escondidos.
- `0` significa **cero espera adicional**: se vuelve a intentar en el siguiente
  tick del scheduler o en cuanto la ruta nativa esté lista. Así se busca la
  máxima frecuencia que el Tool, la animación, la replicación y el servidor
  permitan. No significa que todos los intentos serán aceptados ni que se pueda
  ignorar un cooldown real del juego.
- Un valor positivo añade solamente la espera elegida por el usuario. Debe
  existir una sola fuente de verdad para ese reloj, sin un `nextKnifeAt`,
  `task.wait(interval)` y un timer de UI compitiendo entre sí. Al cambiar el
  valor se define si afecta al siguiente intento; no se reinicia el contador de
  estadísticas ni se duplica el trabajo pendiente.
- El cooldown de usuario no sustituye **windup, recovery, animación, reload,
  `Tool.Enabled`, hit window, cooldown replicado, RTT, rate limit ni un gate de
  confirmación medido**. Esos tiempos se nombran por lo que son y se conservan
  cuando hay evidencia. Tampoco se copia el `0.25` de MM2, el `0.86` de un swing
  o el gate de Shoot a otro juego como si fueran universales.
- Los refrescos de status/ESP no son cooldown de ataque. Un `Step interval` de
  Auto Farm tampoco es el Cooldown de Knife Throw: son bucles y propósitos
  distintos.
- La prueba mínima de esta convención es: default `0`, un intento sin espera
  artificial cuando la ruta está libre, un valor positivo que sí espera, y
  cancelación sin timers ni atributos colgados. La prueba no debe afirmar una
  tasa de aceptación del servidor que el harness no puede observar.

**Estado actual frente a regla de diseño:** X2 v119 intenta Knife Throw en cada
tick y no expone un slider; si se añade el control de delay descrito aquí, debe
llamarse Cooldown y empezar en 0. Los delays documentados en MM2 son rutas
históricas/medidas de ese juego, no una autorización para reintroducir un
`Throw interval` genérico. Esta distinción queda escrita para que el próximo
cambio no confunda documentación con una funcionalidad ya implementada.

### Cuando el arma tiene críticos o calidad de impacto

No todo se resuelve con «más rápido». Si el juego tiene estados como `Miss`,
`Bad`, `Okay`, `Good`, `Critical`, `Perfect`, `Block` o `Parry`, primero se
descubre dónde nace cada estado y qué lo confirma:

1. Se registra la entrada y el instante de la ventana de impacto.
2. Se identifica el estado nativo de carga/swing y su animación.
3. Se observa el resultado sin convertir una etiqueta ambigua en daño.
4. Se decide si la opción debe ser tiempo, modo, prioridad o simplemente status.
5. Se prueban los límites: demasiado pronto, dentro de ventana, demasiado tarde,
   objetivo muerto, cambio de Tool y respawn.

Por ejemplo, `Hit Time` puede controlar cuándo se intenta el impacto, mientras
`Critical` puede ser una prioridad o un modo; `Miss/Bad/Okay` pueden ser
resultados que sólo se muestran. No se deben convertir todos en toggles ni
prometer críticos si sólo se observó una animación. En Kill Aura estos detalles
pertenecen a las opciones del melee correspondiente; en Knife Throw pertenecen
a la sección del proyectil dentro de Silent AIM.

## 1D. Auto Farm, Auto Win y estadísticas útiles

Las utilidades deben explicar qué están haciendo y qué han conseguido. Una
tarjeta de farm no debería obligar a mirar el output para saber si está
esperando, moviéndose, reintentando o realmente recolectando.

### Contrato de datos para Auto Farm

Como regla de diseño, la tarjeta o su status de sesión debe poder representar,
cuando el juego tenga evidencia para ello:

- **`Coins collected`**: recolecciones confirmadas, no simples intentos de
  `firetouchinterest`, teletransportes o ProximityPrompt.
- **`Wins` y `Loses`**: resultados locales explícitos, deduplicados por ronda;
  un respawn, una muerte o una pantalla ambigua no se convierte en victoria.
- **`Time spent`**: tiempo de la sesión de farm, definiendo si cuenta sólo el
  tiempo activo o también esperas. La opción recomendada es medir tiempo activo
  con `os.clock()` y acumular delta al pausar/apagar, sin sumar dos veces al
  cambiar de personaje.
- **Contexto opcional**: `Coins/min`, rondas, monedas pendientes, reintentos,
  objetivo actual, estado (`Waiting`, `Farming`, `Returning`, `No currency`) y
  último error útil. Sólo se añaden si ayudan; no se inventan métricas para
  llenar la tarjeta.

Los contadores deben tener una fuente única. Si Auto Farm y Auto Win muestran
las mismas wins/losses, leen el mismo store de sesión en lugar de incrementar
cada uno su propia copia. Hay que separar **sesión**, **ronda** y **total
persistente**, y documentar cuándo se reinicia cada uno. Las cifras del cliente
no se presentan como saldo autoritativo del servidor.

**Estado actual:** X2 v119 ya tiene en Auto Win `Wins`, `Time Played`, `Kills`
y `Loses`; Auto Farm todavía reporta principalmente su estado de búsqueda y
contacto. Por tanto, `Coins collected`, `Time spent` y demás campos anteriores
son el contrato para completar/compartir el farm, no una afirmación de que ya
estén implementados en X2. No se debe escribir en una prueba o en el status
«collected» hasta tener una confirmación real.

### Qué significa Utilities en este proyecto

Auto Farm y Auto Win van en **Utilities** porque son ayudas de gestión,
recolección, estado o farmeo, no una modificación directa de la hitbox del
objetivo. Que una utilidad sea poderosa no la convierte en Exploits. En cambio,
**Hitbox sí va en Exploits** porque altera una propiedad de colisión/tamaño y
debe restaurar exactamente lo que cambió.

La categoría no sustituye la seguridad: una utilidad puede seguir necesitando
Team Check, comprobación de ronda, ownership y cleanup; un módulo Exploits no
recibe permiso para inventar remotes. La pregunta de categoría es «qué tipo de
ayuda ofrece», y la pregunta de seguridad es «qué puede cambiar y cómo se
restaura».

## 1E. Checklist de salida para un game

Antes de dar un módulo por terminado, el próximo agente debe poder responder
«sí» o dejar escrito por qué todavía no puede:

1. **Identidad:** PlaceId, perfil, fingerprint y loader apuntan al juego correcto;
   no se carga otro game por un nombre parecido.
2. **Reglas:** equipos, relación Enemy/Teammate/Unknown/Outside, Tools y
   resultados tienen funciones puras y pruebas; Unknown no se convierte en
   enemigo por conveniencia.
3. **Core:** existe un solo adaptador de objetivo/ataque y los módulos lo usan;
   no hay dos árboles Shoot ni dos loops equipando el mismo Tool.
4. **Silent AIM:** todos los ataques a distancia/proyectiles están bajo su
   tarjeta, con secciones por arma y sus propias opciones; la keybind de acción
   no cambia el toggle maestro.
5. **Kill Aura:** sólo contiene melee; reach, swing, hit time, críticos,
   miss/bad/okay, recovery y cooldown se modelan únicamente si la mecánica los
   tiene y se pueden observar.
6. **Cooldown:** el delay artificial nuevo se llama Cooldown, empieza en 0 y no
   se duplica con otro intervalo; los tiempos nativos/medidos siguen explicados
   por separado y no se promete aceptación del servidor.
7. **Utilities:** Auto Farm/Auto Win muestran estado y datos reales; Coins
   collected no se incrementa por un intento, y Wins/Loses/Time spent tienen
   una definición de sesión/ronda y deduplicación.
8. **Categorías:** Utilities no se usa como sinónimo de Exploits; Hitbox y
   otras manipulaciones directas tienen cleanup y van en Exploits; ESP queda en
   Render usando los providers compartidos.
9. **Ciclo de vida:** OFF, cambio de Tool, muerte, respawn, salida del jugador,
   cambio de PlaceId y destroy cancelan trabajos y restauran todo lo tocado.
10. **Pruebas y publicación:** se actualizan los contratos afectados, se compila,
    `bash tools/validate.sh` queda verde, se regenera el bundle con un stamp
    nuevo para cambios de runtime y se publica en la rama de la sesión.
11. **Límite de evidencia:** el handoff separa lo verificado offline de lo que
    falta comprobar live. Nunca se escribe «funciona daño/monedas/wins» sólo
    porque un mock llamó a Activate o porque apareció una animación.

## 1F. Antes de añadir una función: pensar, ubicar y después escribir

No se empieza por `createUniversalFeature`. Se empieza por entender la función y
buscar su dueño actual. El prefijo `Auto`, que la idea parezca pequeña o que el
código quepa en un archivo nuevo **no justifica una tarjeta nueva**.

### Archivo, tarjeta, opción y categoría no son lo mismo

- **Archivo técnico:** separa código para mantenerlo legible. Puede existir sin
  añadir ninguna entrada al menú.
- **Tarjeta:** representa una intención de control independiente, con su master,
  estado, opciones y ciclo de vida. Es lo que hay que limitar.
- **Opción/acción:** una variante o paso dentro de una tarjeta que ya posee el
  mecanismo. Puede ser toggle, dropdown, slider, botón hold o texto de estado.
- **Categoría:** la ventana/grupo en que aparece la tarjeta: Combat, Utilities,
  Exploits, Render, World, etc. No indica por sí sola quién debe ser el padre.

El ejemplo canónico es **Sprint**: `src/games/MM2/Movement/Sprint.lua` es un
archivo separado, pero registra su botón dentro de **Speed** y usa
`SetSprintHeld`, `StepSprint`, `SprintFrame` y `ClearSprint`. No crea una tarjeta
Sprint independiente. Si se añade **Auto Sprint**, la ubicación por defecto es
una opción **dentro de Speed**, reutilizando ese mismo estado de locomoción;
no una tarjeta `Auto Sprint` con otro Heartbeat y otra escritura de WalkSpeed.

Esto también evita una simplificación incorrecta: no todo lo relacionado debe
fusionarse. Aim Assist, Silent AIM y TriggerBot pueden compartir targeting sin
ser la misma tarjeta porque su comportamiento de activación es distinto. Speed
y Noclip comparten el personaje, pero WalkSpeed/velocidad y colisión tienen
propósitos, riesgos y restores diferentes. La regla es compartir el **estado y
el ciclo de vida real**, no solamente el tema.

### El árbol de decisión obligatorio

Antes de implementar, recorre estas preguntas en orden y escribe las respuestas
en el análisis o en el resumen del cambio:

1. **¿Qué quiere hacer el usuario, en una frase?** «mantener sprint al caminar»
   no es lo mismo que «aumentar WalkSpeed», «saltar automáticamente» o «volar».
2. **¿Ya existe una tarjeta que haga eso o controle el mismo estado?** Busca por
   nombre, propiedad, Tool, cámara, target, remote, conexión y cleanup. Si la
   respuesta es sí, la primera opción es una subopción, no otra tarjeta.
3. **¿Qué recurso sería compartido?** WalkSpeed, Humanoid, cámara, Tool,
   proyectil, selección de objetivo, lista de monedas, ventana de resultados,
   scheduler o estadísticas. Dos dueños escribiendo el mismo recurso son un bug
   aunque cada uno pase sus tests por separado.
4. **¿Puede ser sólo una opción, una acción, un provider o un status?** No toda
   función necesita master propio. Un contador puede ser status; Team/Role ESP
   puede ser provider; un click puntual puede ser botón dentro de Teleport.
5. **Si es una opción, ¿depende del master?** Define si Speed OFF detiene Auto
   Sprint, si Silent AIM OFF cancela Auto Shoot, y si se conserva la preferencia
   al volver a activar. «Independiente» debe significar independencia real, no
   dos funciones modificando lo mismo sin coordinación.
6. **¿Cuál es su mecanismo dominante?** Proyectil → Silent AIM; melee → Kill
   Aura; locomoción → Speed/Jump/Fly/Teleport según la acción; información →
   Render/status; farm o resultado automatizado → Utilities; alteración directa
   de una propiedad explotable → Exploits. El nombre no decide por encima del
   mecanismo.
7. **¿Es universal o específica del juego?** Sólo es universal si el contrato es
   realmente genérico. Un remote, animación, atributo o Tool particular pertenece
   al game; el adaptador universal puede recibirlo mediante un provider.
8. **¿Qué opciones necesita y cuáles sobran?** No añadir Range, Cooldown, Mode o
   Team Check por plantilla. Para delay artificial nuevo, Cooldown empieza en 0;
   para mecánicas especiales se usan sus términos reales, con evidencia.
9. **¿Cuál es el comportamiento por defecto?** Lo seguro suele ser OFF, tecla
   Unknown y sin restaurar automatizaciones antiguas. Un valor por defecto no
   debe cambiar el movimiento, disparar o farmear al cargar el menú sin que el
   usuario lo haya elegido.
10. **¿Qué ocurre al apagar, morir, respawnear, cambiar de Tool/personaje,
    teleportar o destruir el módulo?** Si no se pueden enumerar los restores y
    las conexiones, todavía no está lista la función.
11. **¿Cómo se prueba la ubicación y la propiedad?** Debe existir un contrato
    que impida la tarjeta duplicada y compruebe que sólo hay un scheduler/dueño,
    además de las pruebas funcionales y de cleanup.
12. **¿Qué sigue siendo una suposición?** Si falta el mecanismo live, se pide
    evidencia o se deja pendiente; no se rellena el hueco con un remote o un
    comportamiento inventado.

Si una respuesta cambia, hay que volver a las anteriores. Por ejemplo, si al
responder «¿qué recurso comparte?» se descubre que Auto Sprint necesita
WalkSpeed y el estado de Speed, ya no se puede justificar una tarjeta aislada
sin explicar cómo se evita la doble escritura.

### Ejemplos de ubicación antes de crear nada

| Idea solicitada | Ubicación inicial que debe evaluar el agente | Motivo y límite |
| --- | --- | --- |
| **Auto Sprint / Sprint hold / sprint trail** | Opción o acción dentro de **Speed**. | Comparte Humanoid, velocidad, estados sentado/aire y restores. El archivo Sprint puede existir, pero no otra tarjeta ni otro escritor de velocidad. |
| **Auto Jump / Bunny Hop** | Si mantiene el movimiento de Speed, dentro de **Speed**; si cambia impulso/altura de salto, dentro de **Jump**. | El nombre «jump» no basta: decide si el efecto principal es continuar desplazándose o modificar el salto. Si ambas lecturas cambian el comportamiento, preguntar. |
| **Click Teleport / teleport a un marker** | Acción u opción de **Teleport**, reutilizando destinos y coordenadas. | No crear otro sistema de CFrame ni otra lista de puntos. Markers puede seguir siendo Render si su responsabilidad es mostrar/guardar marcadores. |
| **Auto Shoot / Gun Throw / Knife Throw** | Secciones del arma dentro de **Silent AIM**. | Comparten target, Team/Wall Check y sender. La activación puede ser llamada por otra utilidad, pero no se duplica el solver. |
| **Melee Reach / Hit Time / Critical** | Opciones del arma bajo **Kill Aura**. | Reach como distancia de selección no es Hitbox. Si se cambia el tamaño real de una parte, eso sí pertenece a Hitbox/Exploits y necesita restore. |
| **Team ESP / Role ESP / Enemy ESP** | **PlayerESP** y los providers compartidos de equipos/roles. | No crear otro scanner, otra paleta incompatible ni otra lista de jugadores. Chams/Nametags pueden ser tarjetas distintas si renderizan objetos distintos, pero usan la misma relación. |
| **Coin ESP / Gun ESP / otro pickup ESP** | Provider del **ItemESP/CoinESP** que ya descubre esa familia. | Añadir una fuente o un estilo no exige repetir el escaneo completo. Si el mecanismo visual es realmente distinto, se justifica antes de crear otra tarjeta. |
| **Anti Fling** | Subopción de **Anti Void**, como ya ocurre, con su propia preferencia. | Comparte protección física y ciclo de vida, pero no se fuerza a depender del toggle de Anti Void. |
| **Remove textures / particles / shadows / simple materials** | Opciones de **Improve FPS**. | Son variantes del mismo objetivo y cleanup; una tarjeta por propiedad sería ruido y multiplicaría restores. |
| **Freeze Emotes / Freeze Animation** | Opciones de **Freeze Movements**. | Comparten personaje, Animator y snapshot; cada preferencia puede seguir siendo independiente. |
| **Disguise packs / Body / Animation / Advanced** | Secciones y opciones de **Disguise**. | No una tarjeta por pack, bundle o slot. Las rutas de apariencia y animación comparten snapshot y restauración. |
| **Auto Farm / Auto Win** | Tarjetas de **Utilities**, con estadísticas compartidas cuando midan lo mismo. | Tienen intenciones y ciclos diferentes, así que compartir datos no obliga a fusionarlas. Ninguna va en Exploits sólo por automatizar. |
| **Auto Unbox** | **Utilities**, con sus propias opciones de caja/reveal/delay. | Es otra utilidad, no una subopción de Auto Farm ni una variante de Shoot. |
| **Noclip** | Tarjeta propia en **Exploits**, no un modo de Speed por defecto. | Aunque afecta al movimiento, cambia colisiones y tiene otro riesgo/cleanup. Éste es un ejemplo válido de no anidar. |

Estas ubicaciones son el punto de partida, no una excusa para ignorar el código.
Si el módulo existente ya tiene un dueño distinto, hay que leerlo y explicar la
migración antes de mover nada. Y si una nueva función sólo es un paso de una
secuencia de farm, Auto Farm puede invocarla, pero la mecánica de combate debe
delegar en el adaptador correspondiente: **llamar a Shoot no autoriza a copiar
Shoot dentro de Auto Farm**.

### Cuándo el agente debe preguntar al usuario

No hay que interrumpir para lo obvio: `Auto Sprint → Speed`, `Knife Throw →
Silent AIM`, `Team ESP → PlayerESP/providers` ya tienen respuesta estructural.
El agente la aplica y deja la ubicación en el resumen.

En cambio, **debe detenerse y preguntar antes de escribir** cuando ocurra
cualquiera de estos casos:

- quiere crear una **tarjeta nueva de nivel superior** o una **categoría nueva**
  que el usuario no pidió explícitamente;
- hay dos tarjetas existentes que podrían ser dueñas y la elección cambia el
  comportamiento, las keybinds o los valores guardados;
- quiere dividir una tarjeta actual, fusionar dos, mover una función de
  categoría o convertir una opción existente en otra tarjeta;
- la función necesita un nuevo bucle global, otro escritor del mismo recurso,
  una automatización con efecto en servidor o un comportamiento activo por
  defecto;
- la evidencia no permite saber si es proyectil o melee, utilidad o exploit,
  universal o específica del juego;
- el cambio altera una decisión anterior del usuario o rompe compatibilidad de
  configuración.

La pregunta debe ser concreta y traer una recomendación, no «¿qué hago?». Usa
este formato:

```text
La función controla <recurso> y comparte <estado/cleanup> con <tarjeta>.
Propongo ponerla como <opción/acción/status> dentro de <tarjeta>, en
<categoría>, porque <razón>. La alternativa sería una tarjeta independiente,
pero duplicaría <coste/estado>. ¿Confirmas la ubicación propuesta?
```

Ejemplo:

```text
Auto Sprint controla la misma velocidad y estados Humanoid que Speed.
Propongo añadirlo como toggle dentro de Speed, no como tarjeta nueva. Hay que
definir si, como el Sprint hold actual, puede trabajar con Speed OFF o si
depende del master, sin crear otro escritor de velocidad. ¿Confirmas esa
ubicación y esa dependencia?
```

Si el usuario ya respondió esa pregunta para una familia, no se vuelve a pedir
confirmación por cada skin o variante. Se conserva la decisión y se documenta.
El control debe venir de una estructura comprensible, no de veinte preguntas
repetidas ni de veinte tarjetas casi idénticas.

### Nota mínima que debe acompañar a cada función nueva

Antes de marcarla como terminada, deja estas seis líneas en el análisis, test o
RESUME cuando sea una decisión durable:

```text
Función: <qué hace>
Ubicación: <tarjeta padre / opción / acción / provider / status>
Categoría: <Combat / Utilities / Exploits / Render / World / ...>
Dueño del estado: <core, propiedad, scheduler y cleanup>
Opciones/defaults: <sólo las necesarias; Cooldown = 0 si aplica>
Evidencia y pruebas: <observado, offline, pendiente live>
```

Si no se puede rellenar «Ubicación» o «Dueño del estado», todavía no toca crear
la función.

## 1G. Toolchain: qué hace falta y qué no hay que instalar

No basta con escribir «usa Luau». Un agente que retoma el proyecto debe poder
preparar un clone limpio, compilar, ejecutar las pruebas y saber qué evidencia
sale de cada herramienta. Tampoco debe convertir nombres conocidos —Darklua,
StyLua, Selene o Rojo— en dependencias obligatorias si el pipeline no los usa.

### Requisitos del pipeline normal

| Herramienta | Para qué se necesita | Estado y preparación |
| --- | --- | --- |
| **Bash** y utilidades Unix (`find`, `grep`, `cut`, `tar`) | `tools/validate.sh`, setup y comprobaciones de salida. | Ejecutar con `bash`, no con `sh`: el script usa `pipefail` y process substitution. En Windows usar WSL o Git Bash conservando LF. |
| **Python 3** como `python3` | Build/check del bundle, harness, suites, auditorías y análisis offline. | El build y las suites de `validate.sh` usan la biblioteca estándar; no hace falta un `pip install` general. Comprobar con `python3 --version`. |
| **Node.js** como `node` | Ejecutar el paquete Luau WASM vendored. | Es el único runtime externo del toolchain Luau. **No hace falta npm ni `npm install`** para el flujo normal. Comprobar con `node --version`. |
| **Luau 0.739.0** (`luau` y `luau-compile`) | Ejecutar harnesses y compilar cada fuente `.lua`. | Está fijado en `tools/luau/vendor/luau-rs-luau-0.739.0.tgz`; `bash tools/luau/setup.sh` crea los wrappers en `tools/luau/bin/`. |
| **Git** | Revisar el diff, preservar el alcance y publicar el commit correcto. | No interviene en las pruebas, pero sí en el protocolo de publicación. |
| **GitHub CLI (`gh`)**, cuando haga falta | PR, issues, checks, releases o recuperación mediante API. | No es requisito de `validate.sh`; no sustituye a `git` para commit/push ni debe pedirse ninguna credencial al usuario. |

`tools/luau/bin/` y `tools/luau/node_modules/` están ignorados porque son
artefactos locales. Lo reproducible y versionado es el tarball de `vendor/` más
`setup.sh`, `run.mjs` y `compile.mjs`. En un clone limpio, `validate.sh` intenta
el setup automáticamente si falta el wrapper y existe el tarball; aun así, ante
un fallo conviene ejecutar el setup explícitamente para ver el error real.

### Arranque y comprobación desde la raíz

```bash
git status --short
python3 --version
node --version
bash tools/luau/setup.sh
tools/luau/bin/luau-compile src/Wurst.lua
bash tools/validate.sh
```

El `luau-compile` aislado es un smoke test de sintaxis; el pase completo es
`bash tools/validate.sh`. Ese runner comprueba que el bundle y el stamp no estén
desincronizados, compila todas las fuentes, ejecuta todos los `tools/test_*.py`,
genera y arranca el harness completo, audita exports `core.*`/`prediction.*` y
vuelca el menú debug/release. No se declara éxito mirando sólo el final del log:
cualquier comando fallido detiene el script.

Si se usa otra instalación de Luau, se puede seleccionar sin editar el runner:

```bash
LUAU_DIR=/ruta/al/directorio bash tools/validate.sh
# o rutas independientes:
LUAU=/ruta/a/luau LUAU_COMPILE=/ruta/a/luau-compile bash tools/validate.sh
```

No se copian binarios al repositorio ni se cambia el PATH global del usuario.
Si falta una herramienta, se arregla el entorno o el setup; no se omite la suite
ni se relaja un assertion para obtener un falso verde.

### Mapa de herramientas del propio repositorio

| Herramienta | Cuándo usarla | Qué demuestra / qué no demuestra |
| --- | --- | --- |
| `python3 tools/build_bundle.py --stamp <stamp>` | Después de un cambio de runtime, con el mismo `SOURCE_STAMP` de `src/Wurst.lua`. | Regenera `src/libraries/bundle.lua` desde las fuentes. No valida por sí solo el comportamiento. |
| `python3 tools/build_bundle.py --check --stamp <stamp>` | Antes de publicar y dentro de `validate.sh`. | Detecta fuentes ausentes, huérfanas o distintas y stamps incompatibles. |
| `bash tools/validate.sh` | Antes de cualquier push de runtime y después de preparar el entorno. | Es la puerta offline completa; no prueba daño, recompensas ni aceptación de un servidor Roblox live. |
| `python3 tools/test_<nombre>.py` | Durante el desarrollo, para iterar sobre el módulo afectado. | Da feedback focalizado; no reemplaza la validación completa final. Ejemplos: `test_mm2_sprint_option.py`, `test_speed_modes.py`, `test_x2duels.py`. |
| `python3 tools/gen_full_boot_harness.py` | Normalmente mediante `validate.sh`; de forma directa para depurar el boot. | Genera `build/full_boot.luau`; el archivo generado no se edita como si fuera una fuente. |
| `python3 tools/audit_menu.py` / `--release` | Cuando cambien tarjetas, categorías, opciones o visibilidad debug. | Arranca el bundle real y vuelca lo registrado, no sólo nombres encontrados por grep. `--release` debe excluir Calibration. |
| `python3 tools/audit_module_api.py` | Al añadir o renombrar llamadas `core.*` o `prediction.*`. | Comprueba que cada llamada tenga un export; no demuestra que su comportamiento sea correcto. |
| `python3 tools/replay_gun_prediction.py` y `analyze_*.py` / `audit_*.py` pertinentes | Sólo con capturas o fixtures relacionados con la pregunta investigada. | Reproducen o resumen evidencia cliente. Sus límites deben acompañar al resultado; no convierten muestras pequeñas en precisión live. |
| `tools/X2DuelsDecompiler.luau` + `tools/X2DuelsDecompiler.md` | Para obtener evidencia específica de X2 en el entorno live apropiado. | El colector vuelca fuentes, inventario y llamadas observadas. `python3 tools/test_x2duels_decompiler.py` sólo valida sus contratos contra un DataModel simulado. |
| `tools/diagnostics/*` | Sólo para un diagnóstico concreto y con el alcance indicado por su propia guía. | No son parte del arranque normal ni se deben cargar todos por rutina. |

Roblox Studio, un executor y una sesión live **no son requisitos de las pruebas
offline**, pero las pruebas offline tampoco los sustituyen cuando la pregunta es
si el servidor aceptó una acción. Hay que nombrar siempre cuál de esos dos
entornos produjo la evidencia.

### Darklua, formato, lint y dependencias opcionales

- **Darklua** (no «Darkluau») **no está instalado, configurado ni es necesario**.
  Este repositorio no lo invoca: el empaquetador real es
  `tools/build_bundle.py`, y `src/libraries/bundle.lua` contiene las fuentes
  para el loader actual. No añadir un segundo bundler, minificador o reescritor
  de `require` sólo porque existe; podría producir un artefacto distinto del que
  prueban los harnesses.
- **StyLua, Selene, luau-analyze, Lune y Rojo tampoco forman parte del pipeline
  actual.** No hay configuración que los convierta en una puerta. Si una tarea
  los necesita de verdad, se fija versión y configuración, se prueba el comando
  y se documenta el motivo; no se formatea todo el árbol ni se introduce otra
  cadena de build de manera incidental.
- `tools/process_manga_assets.py` es una excepción opcional: importa **Pillow**
  (`PIL`) y **NumPy**. Esas dependencias sólo se instalan para procesar esos
  assets (`python3 -m pip install Pillow numpy`); no son necesarias para
  compilar, generar el bundle ni ejecutar `validate.sh`.
- Los mocks y herramientas ya incluidos son la primera opción. Antes de añadir
  una dependencia nueva hay que explicar qué hueco cubre, cómo se instala de
  forma reproducible, qué comando la ejecuta y qué prueba impide que quede
  abandonada. Una herramienta experimental no se convierte en un paso que el
  usuario tenga que arreglar manualmente.

En resumen: **el toolchain obligatorio es Bash + Python 3 + Node.js + el Luau
vendored; Git/gh cubren publicación. Darklua no es un requisito**. El comando
que reúne la comprobación normal sigue siendo `bash tools/validate.sh`.

## 2. La trampa de los dos árboles Shoot (NO repetir)

- Hubo una divergencia real: `src/games/MM2/Blatant/Shoot.lua` llegó a ser un
  *solver standalone* de 1,051 líneas sin módulo Prediction, mientras el bundle
  ejecutaba el Shoot de menú de 852 líneas con `state.mm2Prediction`.
- La telemetría del usuario lo zanjó: sus sesiones emiten `model: "kinematic-v51"`
  + `rttEngine`/`echoSamples`/`leadCorrection`, que **solo existen en el árbol
  de menú** (Prediction-driven). Ese es el producto. En v106 se restauró el
  árbol de menú desde `734635c` y se trabajó ahí.
- `Shoot_WallCheck_Standalone.txt` es un artefacto aparte para pegar suelto.
  **No es la fuente del menú.** No mejores el standalone pensando que arreglas
  el menú, y no aceptes "Both trees": es como nació la divergencia.
- Si un revisor externo cita métricas como `maxError`, `errorRadius`,
  "Shot accuracy is too low to fire." o `gunAcceptanceMs=514`: **no existen**
  ni en el código ni en los logs. Verifica cada cifra contra el archivo exacto
  antes de actuar.

## 3. Shoot / Prediction — lo medido, no lo adivinado

- Horizonte correcto = **pipeline completo (eco FireServer→GunFired o ping) +
  interpolación 25 ms**, cap 0.6 s. Confirmado con ShootProbe ×3 y telemetría:
  el servidor puntúa a ~ping + 20–26 ms sobre la línea temporal del cliente.
  **No dividas el lead entre 2** (v85 lo probó y falló sistemáticamente corto)
  y no toques el lead global sin una sesión de calibración que lo pida.
- **Envenenamiento del eco (la saga v103→v105):** emparejamientos tardíos de
  confirmación (416–1840 ms) entraban en la mediana del eco y la arrastraban de
  106 → 532 ms, adelantando cada disparo ~0.4 s. Defensas actuales en
  `Prediction.lua` (`noteEcho`):
  - Puerta de plausibilidad: `delay ≤ clamp(currentRtt()*2.5 + 0.05, 0.30, 1.6)`
    (usa `currentRtt()`, **no** `robustRtt()` — el harness lo rompe).
  - Auto-reset por divergencia: mediana > 1.5×RTT ⇒ se limpia la ventana y el
    lead cae a ping hasta reunir 3 ecos frescos.
  - Expiración por edad: ecos de más de 30 s no cuentan.
  - Corrección cerrada por `leadErrors`: cap ±60 ms, descarta |error| > 150 ms.
- **v106, dos arreglos desde telemetría v105:**
  1. `safeToSend` pasaba el origen *silent* (cerca del objetivo) como muzzle a
     `validateGunShot(target, character, targetCharacter, muzzle, origin,
     endpoint, walls)` — el check de línea de visión salía desde el objetivo y
     nunca veía muros ni transeúntes entre la pistola y el blanco. Ahora muzzle
     = pistola real. Confirma la firma antes de tocar esa llamada.
  2. Gate de un disparo pendiente: `SHOT_CONFIRM_WINDOW = 1.5` s. 14 peticiones
     a ~0.1 s sin eco en la sesión v105; cada petición tras un eco fue respondida.
     En v109 el gate se hizo visible: mensaje con tiempo restante, contador en
     `state.mm2ShotGateHold` y acción "Shot gate status".
- **v139.2 — el rayo no muere donde termina nuestro endpoint.** Es una línea
  larga: un error de 1 stud no se pierde, entra en el cuerpo de detrás. Por eso
  el punto de mira se elige por lo que hay **detrás** (`describeRayBeyond`,
  sondeo 200 studs) y se salta el tiro si un cuerpo vivo está a menos de
  **35 studs** detrás de todas las opciones del cuerpo. Un **muro** detrás no es
  peligro (el rayo muere ahí). Si tocas el umbral, mide antes: 35 studs ≈ 2× la
  distancia típica de enfrentamiento y el coste de pasarse es *no disparar*.
  Para saber si un fallo fue balística o geometría, el evento del disparo trae
  `missReason` (`hit` / `other-player` / `geometry` / `no-hit-part`) y el
  resumen de sesión `gunMisses` + `gunMissReasons`.
- **v139.4 — el error en studs es una estimación, y ahora es una estimación
  honesta.** `Prediction.getHistory` **debe** devolver `aimOffset`/`aimPart`:
  `measureEndpointErrorStuds` y `measureLeadErrorSeconds` lo suman al root
  interpolado, así que sin él se comparaba root contra un aim de torso (1,5
  studs de error falso) y ese número alimenta `noteLeadError` →
  `leadUncertainty` → el barrido adaptativo de Silent. El tope de 36 puntos de
  `captureTargetHistory` **decima**, no corta por el lado viejo: la última
  muestra tiene que llegar siempre. Alcance declarado en `predictionError.scope`:
  estimación del cliente, no medida del servidor.
- **v139.4 — "raw" no significa "sin paredes".** `useRaw` (continuous+silent, o
  `shootRaw`) sólo puede saltarse el guardián del **origen cercano**; la línea
  del cañón se valida en todos los modos. Si añades un modo que dispare sin pasar
  por `safeToSend`, está mal.
- **v139.3 — punto blanco.** El cuerpo del asesino está excluido de todos los
  rayos; a 0,8 studs el disparo sale. Lo que sí rompía era el **lead**: a 6
  studs o menos, 17 studs/s × 0,1 s = 1,7 studs, y si viene **hacia ti** el punto
  predicho cae detrás del cañón → `"Invalid shot geometry"`. Regla: dentro de
  `POINT_BLANK_STUDS = 6` se apunta al `HumanoidRootPart` **sin lead** y se
  autoriza desde el cañón real (`PointBlank`). Y ojo con las constantes
  compartidas: `bystanderBlocks` (sólo personajes, **las paredes no lo frenan**)
  y `corridorSafePoint` (primera pared y para) son preguntas distintas con
  alcances distintos: `BODY_OVERSHOOT_STUDS = 12` frente a
  `CORRIDOR_PROBE_STUDS = 200`. Un cadáver no es un inocente.
- **El cuchillo va a ~96 studs/s** (`ThrowSpeed`, clamped 24–300): a 30 studs el
  vuelo es 0,31 s y el objetivo recorre 5,2 studs; el lead del cuchillo importa
  3× más que el de la pistola. `throwKnife` **no** dispara hasta que el tool
  está colgado del personaje (`EquipTool` es ida y vuelta; el remote no). El
  bucle cachea la puntería 1/15 s; el disparo siempre re-resuelve desde el mango.
- **Cómo leer una calibración sin engañarte:**
  - `hitTarget` (el rayo tocó el personaje) **≠ kill**. Una sesión tuvo 20
    hitTarget y 0 kills con la salud siempre a 100 (lobby/intermisión/blancos
    quietos). Mira `died`/kills y filtra: velocidad ≈ 0, latencias extremas,
    `healthAfter = nil`, endpoint idéntico repetido = blancos de relleno.
  - Sesiones con el bot **volando o todo `targetJumped`** (velocidades hasta
    60, vy −61…+59) **no sirven para calibrar precisión en suelo**. Ya se han
    perdido dos análisis por esto. Pide: Difícil / Patrón Auto / Saltos Normal /
    Sin extras, y 15–20 confirmados por modo en la misma sesión.
  - Recomendación práctica vigente (provisional, muestra pequeña): **Silent +
    Front**. v104 mixta: Front 3/4, Through 1/4, Prediction 3/10.
  - La telemetría vive en `MM2_Trajectory_Calibration.json` (+ `.before-*`).
    Campos útiles: `session.gunByMode`, `session.predictionError`,
    `endpointErrorStuds`, `serverEchoMs`, `leadErrorSeconds`, `silentSpawn`.
    Replay offline: `tools/replay_gun_prediction.py`.

## 4. Evidencia: repo TestingStuff

- `XzAngel19/TestingStuff` (público) guarda los logs y calibraciones del
  usuario. **Solo lectura y solo como evidencia.** Reglas:
  - Cada archivo es de UN build: mira `buildStamp` dentro antes de concluir.
    No promedies entre builds. El más reciente no siempre es el de la raíz:
    busca el nombre con la versión (p. ej. `MM2_Trajectory_Calibration_v105_2026-10-23.json`,
    sesión `F9F125A2…`).
  - No subas código ahí, no copies implementaciones desde ahí, y nunca subas
    credenciales/tokens/configs de executor. Es público.

## 5. Auto Farm / Auto Get Gun — reglas duras del usuario

- Movimiento: **física, jamás CFrame por tick** — MM2 expulsa con error 267
  ("Invalid position"). Walk = `Humanoid:Move` con slider 5–60. Below (Hitbox)
  = vuelo por velocidad, erguido, NoClip, root 4×8×4, centro 3.0 bajo la moneda.
  **Prohibido el prone/tumbar el cuerpo** (rechazado dos veces) y prohibido el
  movimiento en dos fases.
- Acciones de bolsa llena (50) **solo** con bolsa llena: Kill All → Teleport to
  Map → Auto Grab + Shoot → Reset → Flings. Nada de esto en el farmeo normal.
- **Auto Grab / Auto Get Gun: solo Innocent, solo ronda activa, nunca Murderer,
  nunca lobby.** Fail-closed: si el rol no se conoce positivamente
  (`getPlayerRole(LocalPlayer) == "Innocent"` + `isRoundLifecycleActive()` +
  `findMM2Map()`), no actúa. (Kill All sí es de Murderer, por diseño.)
- Recogida instantánea: pulso `firetouchinterest` raíz↔parte de la gun
  (`state.fireTouchInterest`), el mismo mecanismo que las `Coin_Server`.
  Auto Get Gun **ya no teletransporta**; el botón/tecla manual "Get Gun" sí
  sigue siendo teletransporte porque es un acto explícito del usuario.
- Al terminar/devolver el personaje: **Teleport to Map a un spawn aleatorio**
  (`map.Spawns`, +3 studs, erguido, velocidades a cero), nunca el CFrame "home"
  guardado — tras Below ese punto puede estar bajo el suelo y el personaje se
  quedaba encajado. Sin mapa activo (lobby), el retorno a home sí aplica.

## 6. Velocidad, Cooldown y delays: qué significa "instantáneo"

- El suelo físico es **un frame** (Heartbeat ≈ 16.7 ms a 60 FPS) + ping. Todos
  los `TaskManager:Connect` corren por Heartbeat; los binds disparan en el evento.
- Eliminado en v112: poll de 0.5 s de Auto Get Gun (ahora cada frame + tick
  inmediato al activar) y caché negativa de `findDroppedGun` 0.4 s → 0.05 s.
  Auto Farm espera *condiciones* frame a frame, no sleeps fijos.
- Para delay artificial de combate en módulos nuevos se usa **Cooldown = 0 por
  defecto** (ver §1C): no hay espera extra y se intenta a la máxima frecuencia
  que la ruta nativa permita. Un valor mayor es una preferencia del usuario, no
  una prueba de que el servidor acepte más o menos acciones.
- **Delays deliberados que NO debes "optimizar" sin evidencia** (están fijados
  por `tools/test_action_latency.py` para las rutas actuales; no son una
  plantilla de Cooldown para otros juegos):
  - Shoot MM2: gate 1.5 s entre disparos (ver §3), ligado a confirmación y no a
    un slider genérico de spam.
  - KnifeThrow MM2: timing de paquete/animación de 0.25 s + ciclo de animación.
    **La animación del throw debe verse** (sin ella es blatant); se eliminó
    "Throw with button". Este valor histórico/medido no se copia a X2 ni se
    confunde con el Cooldown opcional de una implementación nueva.
  - KnifeAura MM2: ciclo de swing medido 0.86 s, propio de esa mecánica melee.
  - Auto Unbox: delay entre cajas **configurable y a propósito lento** — es el
    arreglo de la pantalla gris/negra al spamear. No lo aceleres.
  - Rates con slider del usuario (TriggerBot Delay, KillAura swings/s, etc.):
    son suyos, no delays ocultos. Si se migra una opción a Cooldown, se conserva
    el valor sólo cuando representa exactamente el mismo delay.
  - Refrescos de status/visuales a 0.2–5 s (ESP, Chams, Coin ESP): no retrasan
    ninguna acción ni deben usarse como reloj de combate.

## 7. Otros módulos — decisiones ya tomadas

- **Coin ESP:** detección por el mecanismo real del juego:
  `CollectionService:GetTagged("CoinVisual")`, pareja `CoinContainer[Model] >
  Coin_Server[Part] > CoinVisual[Part]`, familia activa por `CoinsStarted`
  (Coin/Candy/SnowToken/BeachBall/Egg). Render: UN `BoxHandleAdornment`
  ×1.3 del tamaño del pickup, **sin Nametags/Highlight/clones**. El cheap-scan
  de v84 detectó cero en vivo: no lo reintroduzcas.
- **Disguise:** 17 packs oficiales por dropdown persistido + resolución
  dinámica de bundles UGC por ID (`GetProductInfo`, exigir
  `BundleType == "AvatarAnimations"`). El rig de MM2 es `AnimationConstraint`
  ×15, **sin Motor6D ni Animate.Disabled**. ÚNICO juez de validez fiable:
  `GetProductInfo` (los probes con `LoadAnimation` spamean y con
  `PreloadAsync` condenan todo — no los resucites). v101 va sin bridge ni
  driver, a propósito. Que otros te vean animado exige tracks reales en tu
  Animator; el espejo es solo local. "Show Advanced": al abrirlo, el pack se
  quita al instante y vuelven las animaciones por defecto hasta que el usuario
  pega IDs por slot (Idle/Walk/Run/Swim/Jump/Fall/Climb/SwimIdle). El desync
  Mage→Ninja era real y se arregló en v97 (juicio por GetProductInfo, slots
  primero). **Pendiente solo veredicto en vivo del usuario.**
- **Menú:** las posiciones de ventana sobreviven a cualquier resize
  (`homePositions` en WindowManager — `Reclamp()` no debe persistir posiciones
  clampadas). Watermark de versión junto a "UI Settings".
- **Anti Fling** (= Anti Void; el usuario lo llama "Auto Fling") y **Anti AFK**
  ("Auto AFK"): v108 dejó Anti Fling sin slider, con umbrales derivados del
  propio cuerpo (spin 20 rad/s, velocidad 2.2×WalkSpeed, salto 3×JumpPower) y
  sin depender de Anti Void.
- **TargetBot** (`tools/diagnostics/TargetBot.lua` v5): el único actuador que
  mueve en MM2 es `Humanoid:MoveTo` (`Humanoid:Move` y empujes por velocidad
  son ignorados — probado). Debe verse natural, no chocar con paredes, saltar
  de verdad, respetar la distancia; Caótico/Imposible extremos (vuelo, dash,
  blink) van aparte. Mini-menú para detenerlo y configurar.
- **EliminatePlayer:** solo en servidor privado con una cuenta alt. Nunca en
  partida viva.
- Cajas MM2: `Remotes.Shop.OpenCrate:InvokeServer(boxId, "MysteryBox"|"Eggs",
  currency)`; una a la vez + reveal ~5 s = sin pantalla gris. KnifeBox1-5,
  MysteryBox1/2, GunBox1-3, cajas de evento por temporada.

## 8. Errores de proceso (los caros)

1. **Commits desde un workspace reseteado regresaron el árbol a v50 una vez.**
   Si `git status` muestra HEAD en `40aba40` ("Create README.md") con cientos
   de archivos "modificados", el workspace está mezclado: el árbol bueno es el
   del tip remoto. Verifica con `git show origin/arena/...:<archivo>`,
   publica con índice temporal + `git commit-tree` sobre el tip remoto y
   `git update-ref`. Nunca fuerces.
2. **CRLF (v107, commit hecho en Windows):** convirtió 6 archivos de texto a
   CRLF y `validate.sh` moría en Linux (`pipefail\r`). Ya hay `.gitattributes`
   (`* text=auto eol=lf`). No lo quites.
3. **Editar el mismo archivo con varias llamadas en paralelo pierde
   ediciones** (pasó dos veces: el edit "exitoso" no estaba en el archivo).
   Ediciones al mismo archivo: **secuenciales**, y verifica con grep antes de
   compilar.
4. Los wrappers y `node_modules` de Luau no persisten entre sesiones: ejecuta
   `bash tools/luau/setup.sh` y comprueba los requisitos de §1G. El tarball sí
   está versionado; no uses npm ni instales Darklua para sustituirlo. Sin red a
   `raw.githubusercontent` (SSL): usa `gh api` o clone.
5. `tools/audit_module_api.py` corre desde validate.sh: todo `core.*` /
   `prediction.*` llamado debe existir como export en `state.mm2Core` /
   Prediction. Si añades una llamada, añade el export o el test te detiene.
6. Los tests son la red: si un test espera el comportamiento viejo y tu cambio
   es correcto, **actualiza el test explicando el porqué en el comentario**
   (pasó con la puerta de eco en v104/v105). No hagas que el código mienta
   para que un test viejo pase.

## 9. Pendiente de verificación EN VIVO (no lo des por hecho)

Nada de esto está probado en partida real todavía; está probado en estático,
boot y las 61 suites:

- Shoot v106–v112: si con el muzzle real desaparecen los impactos en geometría
  del mapa (`Smooth Block Model`), y si el gate de 1.5 s recupera los ecos.
- La sesión limpia que falta: bot en el suelo de verdad (Difícil/Auto/Saltos
  Normal/Sin extras), 15–20 confirmados por modo (Prediction, Silent Front,
  Silent Through). Sin eso, no se retoca el predictor.
- Auto Farm v107–v111: roaming sin monedas, void guard, Teleport to Map al
  terminar, y si el toque instantáneo entrega la gun tras el teletransporte.
- Fling por network ownership (v107) y Anti Fling (v108) contra un fling real.
- Disguise v101: packs del objetivo / por ID, en servidor.
- Salidas del standalone (Step 1 nil-parent, Step 4 origen) y TargetBot v5.
- X2 v119: comprobar en vivo Gun/Knife, precisión del throw, el ESP universal
  con TeamRed/TeamBlue y FFA, la keybind Button y Sender CFrame en móvil, y la
  actualización de Wins/Time Played/Kills/Loses. El harness cubre activaciones,
  estados, colores, contadores y contactos; no prueba daño, monedas ni
  aceptación del servidor. La siguiente evidencia debe obtenerse con
  `tools/X2DuelsDecompiler.luau`.

## 10. Cómo trabajar con este usuario

- Aporta las calibraciones **antes** de pedir cambios: analízalas (con los
  filtros de §3) y da veredicto con números de SU archivo, no de memoria.
- No toques el predictor sin datos. No generalices desde n=4. Si la muestra es
  pequeña, dilo y pide la sesión que falta, con la configuración exacta.
- Cuando algo no se puede verificar desde aquí, dilo explícitamente y separa
  "verificado" de "plausible" de "pendiente en vivo".
- Antes de añadir cualquier función, aplica la puerta de §1F: explica dónde irá,
  qué tarjeta/estado ya es dueño y por qué no duplica otro módulo. Si hará falta
  una tarjeta/categoría nueva o hay dos ubicaciones razonables, pregunta con una
  propuesta concreta antes de escribir; no crees `Auto Sprint` fuera de Speed.
- Cambios pequeños, versionados (bump de stamp por cambio), con test que fije
  el comportamiento y `validate.sh` verde antes de pushear.

---
*Última actualización: 2026-10-29 · v156, base migrada completa y modos MM2
experimentales; los resultados reales y la aceptación del servidor no verificados.
Al publicar una versión nueva, actualiza la línea de estado de arriba y cualquier
sección que cambie.*
