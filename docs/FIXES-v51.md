# v51 — Predicción cinemática propia para MM2

## Qué se eliminó

- Toda la predicción antigua de **Shoot** y **KnifeThrow**: `computeGunAim`,
  `predictAim`, `GUN_LEAD`, corrección automática de lead, `motionSampleHz`,
  `gunLeadBias`, `predictionModel`, descuentos por giro, amortiguación de
  frenada y la integración balística de la hoja.
- El muestreo de movimiento de `base.lua` (`motionSamples`,
  `getFilteredVelocity`, `MotionSample`) y los helpers que solo existían para
  alimentarlo (`closestCrossing`, `isMotionGrounded`, `sampleDue`). Quedan
  únicamente `predictionMath.finite` e `interceptTime`, que son aritmética pura
  compartida.
- El selector **Prediction model** de Calibration. El modelo ya no se elige:
  hay uno solo, medido y con estado visible.

## Modelo nuevo (`src/games/MM2/Prediction.lua`, `kinematic-v51`)

- Muestrea a 60 Hz el `HumanoidRootPart` de cada jugador remoto: posición,
  `AssemblyLinearVelocity`, estado del Humanoid y la parte de aim
  (`UpperTorso`/`Torso`/`HumanoidRootPart`/`Head`).
- Historial de 0,6 s por jugador. Un salto mayor a `8 + 120·dt` studs se trata
  como teleport/respawn y limpia el historial.
- Velocidad horizontal por mínimos cuadrados ponderados sobre los últimos
  0,16 s (peso exponencial τ = 0,055 s). Se usa el ajuste solo con ≥3 muestras,
  ≥0,06 s de cobertura y residual ≤0,5 studs; si no, la velocidad replicada.
  Tope horizontal de 60 studs/s.
- Vertical: solo si el Humanoid está en `Jumping`/`Freefall`. Se proyecta
  `v·t − ½·g·t²`; en suelo no se inventa caída (el `FloorMaterial` remoto miente
  en los logs).
- Sin aceleración extrapolada, sin descuento por giro y sin corrección
  automática: la velocidad local ya refleja el cambio de dirección.
- Horizonte del arma: mediana de los últimos 8 ecos `FireServer → GunFired`
  (mínimo 2, rango 0,02–1,2 s). Si aún no hay ecos, RTT de `Stats`/Data Ping
  suavizado. Se suma la interpolación de replicación (1/40 s) y el ajuste
  manual **Lead offset ms**; el total se limita a 0,005–0,75 s.
- Cuchillo: el mismo horizonte de transporte y luego un intercepto lineal con
  `predictionMath.interceptTime` a la velocidad real de la hoja (96 por defecto;
  atributo `ThrowSpeed` aceptado entre 24 y 300). Sin gravedad, igual que
  `ThrowingKnifeVisuals`.
- La muestra deja de ser válida a los 0,35 s: se rechaza el disparo en vez de
  extrapolar una posición vieja.
- `noteEcho(sentAt, receivedAt)` cierra el lazo desde el validador de
  `GunFired` de `base.lua`. Un eco tardío no mueve el siguiente disparo porque
  se usa la mediana.

## WallCheck conservado

- El filtro es el del propio `ClientServices.WeaponService`: excluye el
  personaje local y todo lo etiquetado `WeaponPassthrough`, y continúa el rayo
  cuando la parte golpeada tiene `Transparency == 1`.
- `validateGunShot` recibe el punto capturado, el origen real y el endpoint
  futuro. Comprueba rol/evidencia del Murderer, ronda activa, vida propia,
  geometría finita y, si WallCheck está activo, el segmento completo con el
  filtro del juego (con `ignoreTarget`, porque el endpoint es una pose futura).
- El fallback silencioso comprueba el segmento y, si el origen cercano queda
  dentro de un cuerpo, vuelve al muzzle real; nunca salta el chequeo.

## Interfaz

- **Aim method**: Prediction / Silent AIM.
- **Auto lead** (por defecto ON) no requiere configurar nada: usa la mediana
  de los ecos `FireServer → GunFired` y, mientras aprende, el ping del motor
  (`Player:GetNetworkPing()`) con `Stats → Network → Data Ping` como respaldo;
  suma la ventana de interpolación (25 ms) y la antigüedad real de la muestra. Como la antigüedad se mide, un equipo a 30 FPS o 144 FPS recibe
  el mismo trato: no hay un número fijo por dispositivo.
- **Lead offset ms** (−300 a 600 ms, paso 1 ms) es el respaldo manual, oculto
  mientras Auto lead está ON. El campo numérico acepta cualquier valor escrito
  sin cuantizarlo (`37.5` es válido); el deslizador avanza de 1 en 1 ms. Se
  suma al horizonte: `eco (o ping) + 25 ms + manual`. El total se corta en
  1,0 s y **Prediction status** muestra `auto lead (echo|ping)` o `manual`,
  `interp`, `lead` y `(capped)`. Se guarda en la configuración.
- **Prediction status** muestra RTT, eco mediano y su cantidad, interpolación,
  ajuste manual, horizonte final (con `(capped)` si saturó) y, para el objetivo
  elegido, velocidad, muestras, antigüedad y si está en el aire.
- **Reset prediction** limpia historial y ecos.
- La telemetría guarda `model = "kinematic-v51"`, `leadSeconds`, `flightSeconds`,
  `sampleAge`, `samples`, `motionSource`, `rtt`, `echoDelay`, `capturedPosition`
  y `predictedPoint`. Ya no se guardan `predictionModel`, `gunLeadBias` ni
  correcciones automáticas.

## Validación

- `LUAU_DIR=... bash tools/validate.sh` → 75 fuentes Luau compilan, bundle de
  73 archivos actualizado, 38 suites Python y `build/full_boot.luau` con
  `Load complete · failures=0`.
- `tools/test_mm2_precision.py` ejecuta el módulo real con reloj y raíces
  simuladas: ajuste ponderado, mediana de ecos, rechazo por muestra vieja,
  reset por teleport y gravedad en caída.
- `tools/test_gun_safety.py` ejecuta `validateGunShot` y `fireGunAtTarget`
  reales contra un motor de rayos independiente: muro opaco bloquea, parte
  transparente se ignora, inocente en la línea bloquea, y ningún rechazo
  encola o envía paquetes.
- `tools/test_mm2_knife_wallcheck.py` verifica el corredor completo del cuchillo:
  un rayo de cobertura al cuerpo actual y cinco rayos (centro ±0,5 studs) sobre
  el segmento futuro, todos estrictos con las partes invisibles.
- `tools/test_prediction_66d.py` (modelo 66d contra el código vivo) se eliminó
  junto con el modelo que probaba.

## Disguise: modo Animation

- **Character** copia cosméticos y emotes del avatar objetivo y, con **Use
  target movement animations** ON (por defecto), también sus animaciones de
  movimiento.
- **Animation** ya no pide un bundle de animación: usa el mismo **Target ID**
  (usuario) que Character y aplica **solo** sus emotes y sus animaciones de
  movimiento (idle, walk, run, jump, climb, fall, swim, mood) al personaje
  propio. No clona mallas, accesorios, ropa ni rostro: el avatar local sigue
  visible tal cual.
- **Use target movement animations** ahora es un toggle visible en **ambos**
  modos, ON por defecto. *(v58 lo dejó solo en Character y lo hizo instantáneo
  desde caché; ver «v58» al final.)* En Character se aplica junto con el disfraz; en
  Animation decide si se copian las animaciones de movimiento (los emotes se
  aplican igual). Al apagarlo se restauran solo las animaciones originales,
  sin quitar el disfraz ni los emotes.
- Se eliminó el botón antiguo y su ruta `applyTargetMovementAnimationsToCharacter`,
  que podía quedarse para siempre en `Downloading target movement animations...`
  cuando la consulta del avatar no respondía.
- Al desactivar, se restauran los emotes y las animaciones originales desde el
  snapshot. Si el personaje cambia a mitad de la aplicación, se revierten los
  emotes aplicados y no se reporta éxito.
- **Show target emotes** funciona en ambos modos. *(v58: pasó a ser un check
  independiente, solo en Character.)*
- Se eliminó el flujo de bundles de animación (`applyAnimationBundle`,
  `getBundleItems`, `getAnimationType`), que era la causa de que Animation
  pareciera "no hacer nada" al introducir un ID de usuario.

## Frecuencia de muestreo

El predictor muestrea a **60 Hz** aunque el render vaya a 144: el personaje
remoto se replica a ~20 Hz, así que 60 Hz da tres observaciones por pose
replicada. Subir a 120 Hz solo repite más veces la misma pose y no mejora el
error dominante, que es el horizonte de transporte (eco/ping); además duplica
el costo por jugador.

## v57 — Character arreglado y cuchillo que ya no se clava en la pared

### Character volvía a mostrar tu propio avatar

- El bloque de **Use target movement animations** corría **antes** de
  `copyCharacterAppearance`. Cualquier espera o fallo ahí —`ApplyDescription`
  del clon, lectura del `Animate`, el antiguo `InsertService`— devolvía o
  abortaba la función antes de copiar el avatar, y el resultado era el
  personaje local intacto.
- Ahora el orden es: filtro de apariencia → copia del avatar →
  `SetStatus("Character")` → animaciones de movimiento **al final**, dentro de
  un `pcall` con aviso propio. Un fallo de animaciones ya no puede impedir el
  disfraz ni deshacerlo.
- La copia de animaciones lee los `rbxassetid://` directamente del
  `HumanoidDescription` (`animationIdFromValue`) y los asigna a cada
  `Animation` del `Animate`. Se eliminaron `extractAnimationsFromAsset` y la
  caché `animationAssetCache`: nada de `game:GetObjects` ni `InsertService`,
  que solo existen en Studio/servidor y eran la causa de que el disfraz se
  quedara pensando.
- La `HumanoidDescription` se destruye al final y también en las salidas
  tempranas (copia fallida, token viejo), sin dejar instancias colgando.

### Cuchillo: por qué se clavaba en la pared

El predictor acertaba, pero el chequeo era un solo rayo por el centro:

- Un rayo central pasa junto a una esquina que la hoja real (con grosor) sí
  toca, sobre todo en tiros con lead largo.
- El endpoint es una pose **futura**; si el objetivo está detrás de una pared
  **ahora**, el rayo futuro puede pasar por el hueco que dejó y la hoja se
  estrella contra esa pared al salir.

Ahora `resolveKnifeAim`:

1. Descarta el lanzamiento si el objetivo no es visible **en este instante**
   desde la mano: un rayo al cuerpo actual, sin excluirlo, con el filtro del
   juego y en modo `strict`: la hoja ignora las partes invisibles que no
   colisionan, pero una pared invisible sólida sí la detiene.
2. Comprueba un corredor de cinco rayos (centro, ±0,5 studs en horizontal y
   vertical) sobre el segmento futuro, excluyendo al objetivo y a
   `WeaponPassthrough`, igual que el filtro del juego.
3. Rechaza solo leads absurdos (>400 studs). No hay tope de distancia normal:
   la hoja sigue recta hasta chocar, así que un tiro largo y despejado vale.
4. Si el objetivo más cercano está tapado, prueba los **tres** más cercanos y
   no todos los de la partida: máximo 3 selecciones por ciclo.

La precisión no cambia: se sigue apuntando al mismo intercepto cinemático; lo
que cambia es que un tiro con el corredor sucio no se envía. Menos cuchillos
gastados en paredes y más en el Murderer.

### La afirmación de los 200 ms

No se pudo confirmar como constante y **no se usa**. Detalle y evidencia en
`docs/SERVER-ACCEPTANCE.md`: el place no incluye scripts de servidor, y los
registros guardados muestran ecos `FireServer → GunFired` de hasta 1007 ms y
cinco impactos confirmados con más de 200 ms de eco (máximo 259,2 ms). El
estimador del 16 de octubre da una media de 123,5 ms con ping ~108 ms, pero su
distribución va de 3,7 a 631 ms: es una media, no un umbral. Un tope fijo de
200,33 ms no aparece en ninguna parte del código recuperado.

- `tools/test_mm2_knife_wallcheck.py` cubre el orden de los rayos, el rechazo
  por cobertura y por corredor, el fallback de velocidad y el límite de 400
  studs.
- `tools/test_mm2_knife_presets.py` recorta su caso de 2000 studs a 300: el
  módulo ya no finge alcanzar cualquier distancia, pero tampoco impone un tope
  de 120 studs.

## v58 — Disfraz: animaciones y emotes independientes

### La carga ocurre una sola vez

- Al aplicar **Character**, el `HumanoidDescription` se lee **al principio** y
  se guardan en caché las animaciones de movimiento de cada slot y los emotes.
  Esa es la carga en segundo plano: después se copia el avatar, y a partir de
  ahí los dos toggles trabajan sobre la caché, sin volver a pedir el avatar ni
  volver a clonarlo.
- La caché guarda también el `UserId`; al cambiar el Target ID, al desactivar el
  módulo, al cambiar de modo o al empezar otra aplicación se invalida, así que
  nunca se aplican animaciones del usuario anterior.
- Los dos checks recuperan su estado guardado con la misma clave que persiste el
  widget (`Universal.Disguise.<nombre>`), de modo que un check guardado en OFF
  no sigue aplicando datos al iniciar.

### Character: dos checks independientes

- **Use target movement animations**: visible solo en Character, ON por defecto.
  Al encenderlo aplica los slots desde la caché en el acto
  (`applyCachedMovementAnimations`); al apagarlo restaura solo las animaciones
  originales (`restoreMovementAnimationsOnly`). No toca emotes.
- **Show target emotes**: deja de ser un botón Run y pasa a ser un check, también
  solo en Character y ON por defecto. Al encenderlo aplica los emotes y slots
  equipados desde la caché (`applyCachedEmotes`); al apagarlo restaura solo los
  emotes originales (`restoreEmotesOnly`). No toca el avatar ni las animaciones.
- Se eliminó el listado de emotes y sus helpers: el botón ya no existe. Si el
  avatar no expone emotes, el check avisa y no hace nada más.
- Los dos checks no se pisan: un fallo o un cambio en uno no revierte el otro.

### Animation: fijo, sin controles

- **Animation** ya no muestra **Use target movement animations** ni **Show
  target emotes**: en ese modo los emotes y las animaciones de movimiento del
  usuario objetivo se aplican siempre y no se pueden desactivar. Sigue sin
  copiar nada visible del avatar.
- El modo Animation ignora el valor de los checks de Character (aunque estén
  apagados, ahí se aplica todo).

### Pruebas

- `tools/test_disguise_toggles.py`: los dos handlers son independientes, usan la
  caché sin refetch, no hacen nada en Animation y fallan cerrado sin personaje.
- `tools/test_disguise_character.py`: orden caché → avatar → animaciones, y
  bloques de emotes/animaciones separados.
- `tools/test_disguise_animation.py`: Animation aplica siempre ambos y no lee
  los checks de Character.

## v59 — Giro y frenado medidos, ecos frescos y tope de lead

### Lo que se corrige de la crítica

- **«Corte» era la palabra equivocada.** El número del lead es la línea de mira,
  no un filtro: nada rechaza disparos por su valor. Lo que rechaza es la
  frescura de la muestra, el WallCheck y la disponibilidad del arma. La frase
  anterior mezclaba la ventana de aceptación del servidor con el lead.
- **El mínimo/máximo de aceptación no es tolerancia por disparo.** Es ruido de
  emparejamiento del eco: 3,73 ms es imposible con ping de ~108 ms y 631 ms es
  un eco tardío. Por eso ahora se filtran los ecos individuales y se exige una
  mediana de muestras frescas.
- **El tope de 1 s era del lead**, no del emparejamiento (que tiene su propio
  rango). Se mantiene solo para el offset manual; el lead automático se corta
  en 0,6 s.

### Giro medido (cuerda)

- Dos ajustes ponderados separados 0,10 s dan la dirección de la velocidad en
  dos instantes. El ángulo con signo entre ellos, dividido por la separación,
  es la velocidad angular `ω` (rad/s), acotada a ±10 rad/s.
- El lead se rota `ω · (h/2 + retraso_del_ajuste)` en la dirección del giro,
  con un tope de **45°**. El `retraso_del_ajuste` está medido (el ajuste es una
  cuerda sobre la ventana, así que su dirección corresponde al centro de esa
  ventana, no a «ahora»).
- La corrección se anula si el objetivo va a menos de 2 studs/s, si el ajuste
  tiene residual >0,5 studs o si no hay suficientes muestras. En línea recta
  vale exactamente 0.

### Frenado medido (stop-time)

- La misma pareja de ajustes da la aceleración longitudinal. Si se opone a la
  velocidad, se corrige la longitud del lead por el retraso del ajuste y por
  `½·a·h²`, y se limita a la distancia de frenado `v²/(2·|a|)` cuando el
  horizonte supera el tiempo de parada.
- `|a|` está acotada a 120 studs/s² y el frenado solo se activa por encima de
  6 studs/s². Caminar o correr recto deja la corrección en 0.

### Cuchillo

- El intercepto se resuelve una vez con la velocidad instantánea y se
  **re-resuelve** con la velocidad media del vuelo completo (cuerda + frenado),
  en lugar de asumir la tangente durante todo el trayecto.
- El término vertical de ese re-cálculo es la **caída del objetivo** cuando está
  en el aire (`v·t − ½·g·t²` sobre su root), no una gravedad del proyectil: la
  hoja se modela en línea recta hasta el endpoint, igual que
  `ThrowingKnifeVisuals`.

### Ecos y horizonte

- La mediana de ecos exige **6 muestras** (antes 2). Con menos, el lead usa el
  ping suavizado.
- Se descartan los ecos fuera de **50–1600 ms** (v59 usaba 800 ms; ver v60):
  por debajo es un emparejamiento imposible; por encima ya no es un eco de este
  disparo. El rango es más ancho que el [60,250] de la sesión de 108 ms porque
  este usuario juega con RTT de 150–500 ms.
- Lead automático limitado a **0,6 s**. El offset manual sigue llegando a 1,0 s.
- «Prediction status» muestra `turn ±X deg/s` y `brake X.XX s` cuando la
  corrección está activa.

### Pruebas

- `tools/test_mm2_precision.py` añade dos casos sintéticos: un objetivo en
  círculo (el lead con cuerda debe quedar a menos de la mitad del error del
  tangente) y un frenado fuerte (el lead con stop-time debe quedar a menos de
  la mitad del error de velocidad constante).
- El caso de ecos comprueba que 5 muestras no forman mediana (se usa el ping),
  que un eco de 40 ms se rechaza por imposible y que con la sexta manda la
  mediana.

## v60 — Cierre de la revisión de v59

### Ecos tardíos: evidencia, no un multiplicador

- La sesión v18 (`TestingStuff/Place_142823291_Game_Learning.json`) tiene un
  eco emparejado (verdict `shot-confirmed`, `hitTarget=false`) de **1007,7 ms
  con ping de 270,3 ms**. El corte de 800 ms lo descartaba; el de 679,2 ms
  (ping 400,1) también.
- Ese eco no es un cruce: `base.lua` solo llama a `noteEcho` cuando coinciden el
  arma, el origen (±3,5 studs) y la dirección (dot ≥0,965) del disparo pendiente;
  además, la cola se abandona a los 1,6 s. Todo lo que llega a `noteEcho` ya
  pasó ese emparejamiento geométrico.
- Por eso el límite superior pasa a **1600 ms**, el mismo horizonte de la cola
  de disparos, en vez de un `max(800, 3×RTT)`: con 270,3 ms de ping, 3×RTT =
  810,9 ms, que sigue rechazando el caso observado de 1007,7 ms.
- La mediana sigue siendo la protección: 1 eco de 1 s entre 6 de 120 ms deja la
  mediana en 120 ms y solo se cuenta como muestra; 6 ecos de 1 s suben la
  mediana a 1 s, el lead automático se corta en 0,6 s y el estado lo marca
  `(capped)`.

### Tope de lead visible

- «Prediction status» marca `(capped)` cuando el tope de 0,6 s (o el absoluto
  de 1 s) recorta el horizonte. Así el tope no puede volverse invisible ni
  confundirse con el valor medido.

### Gravedad del cuchillo

- El re-cálculo del intercepto solo aplica gravedad **al objetivo en el aire**;
  no modela caída del proyectil. Un objetivo en suelo se apunta a su root actual
  (Y sin corrección), que es lo que asume una hoja recta.
- No hay todavía impactos de cuchillo confirmados con posición en la telemetría
  (38 tiros de cuchillo en v18: 27 `unconfirmed`, 11 `projectile-observed`, 0
  `shot-confirmed`), así que la comprobación empírica de si el servidor aplica
  caída a la hoja queda pendiente de datos, no afirmada.

### Pruebas

- Eco de 1 s aceptado y contado, sin mover la mediana de 180 ms.
- 6 ecos de 1 s → lead 600 ms y `(capped)` en el estado.
- Cuchillo contra objetivo en suelo: `aim.Y` no lleva corrección de gravedad.

## v61 — Ventana pre-disparo para puntuar offline

### Lo que se corrige del intercambio

- La telemetría **sí** guardaba `targetTrajectory` (hasta 120 puntos a 30 Hz
  desde el instante del disparo): `PendingGun.targetTrajectory` se crea en la
  activación y `finalizeGunCapture` la adjunta al evento de confirmación.
- Y **sí** guardaba los contadores de sesión `session.gunAttempts` /
  `session.gunConfirmed` (9/9 en la sesión v35), que salen de
  `runtime.sessionGunAttempts` / `runtime.sessionGunConfirmed`.
- La afirmación anterior («no guarda trayectorias» / «el 9/9 no está») salió de
  inspeccionar solo la primera entrada de `events` y los escalares de nivel
  superior del JSON. Fue una ausencia no comprobada, no un dato.

### Lo que faltaba de verdad

Un segundo predictor no se puede volver a ejecutar solo con la trayectoria
posterior al disparo: necesita la **historia anterior**, las muestras que su
ajuste habría usado. Eso es lo que se añade:

- `Prediction.getHistory(player, 0.6)` expone el ring buffer real del predictor
  (60 Hz, 0.6 s) con `at` relativo al instante de la llamada (negativo).
- `captureTargetHistory` lo convierte en `targetHistory`, con `dt` negativo y
  la misma forma que `targetTrajectory`: `dt`, `position`, `velocity`,
  `humanoidState`, `grounded`.
- Se adjunta al evento `authored` (el que lleva `settings`) y a la confirmación
  de pistola y de cuchillo, con un máximo de 36 muestras. Las muestras que no
  son `Vector3` se descartan; sin predictor devuelve vacío en vez de inventar.
- Con `targetHistory` + `targetTrajectory` + `endpoint`, los dos predictores se
  pueden puntuar sobre los mismos vuelos, sin depender de acertar en vivo.

### Pruebas

- `getHistory` devuelve ≥25 muestras tras 0.5 s de muestreo, en orden
  cronológico, acotadas a 0.6 s y con la última en `dt ≈ 0`.
- `captureTargetHistory` filtra muestras inválidas, respeta el límite de 36 y
  devuelve vacío cuando no hay predictor.

## v62 — La sesión real del 18-10 (13 disparos, 9 confirmados, 1 acierto)

El archivo `MM2_Trajectory_Calibration.json` del repo `TestingStuff` es la
sesión v61 completa: 13 disparos autorados, 9 confirmaciones de servidor, **1
`hitTarget`** (disparo 13) y 4 disparos sin confirmar (3, 5, 9, 12). Antes de
tocar nada se reprodujo el modelo validado (`referencePoint` + `targetHistory`,
sin giro ni frenado) contra el `predictedPoint` grabado: mediana 0.10 studs,
máximo 1.68. Las cifras de abajo son error real de puntería, no del análisis.

### Lo que estaba mal y se corrige

1. **Relojes distintos en la historia.** `Prediction.getHistory` devolvía `at`
   restado del `os.clock()` del módulo de predicción y `base.lua` le restaba
   *otro* `os.clock()`. En el archivo guardado la última muestra tenía
   `dt = -238.19 s`: cuatro minutos de desfase. La ventana pre-disparo existía
   pero no era reproducible. Ahora `at` es relativo a la muestra más nueva y la
   edad de esa muestra se devuelve aparte (`age`); `captureTargetHistory` la
   aplica en el mismo lado y los `dt` quedan en `[-0.6, 0]`.

2. **Un pico de ping estiraba el lead.** Los disparos 8 y 10 usaron
   `rtt = 0.314 / 0.342` cuando el ping del resto de la sesión era 0.104–0.108
   (ping real 172/147 ms). El horizonte salió 0.359/0.395 s y los dos fallaron.
   `robustRtt()` toma la **mediana de las últimas 8 lecturas** (una cada
   0.25 s): un pico aislado no mueve el lead, un cambio sostenido sí (en ~1 s).

3. **La aceleración positiva también estiraba el lead.** `leadHorizontal`
   aplicaba `v·h + ½a·h²` con el signo que fuera; en carrera el término `a`
   medido llegaba al tope de +120 studs/s² y alargaba el tiro por delante del
   objetivo. Solo la **desaceleración** acorta el vuelo; con `a > 0` el modelo
   asume velocidad constante. En la sesión, apagar el término positivo bajó el
   error horizontal medio de 2.27 a 1.94 studs.

4. **El giro se disparaba con ruido.** Con el umbral de residuo 0.5, una
   carrera recta producía giros de −224° (disparo 6) y −152° (13) y el disparo
   2 se clavaba en el tope de 10 rad/s. Dos ajustes separados 0.10 s que
   difieren menos de **0.20 studs** no son un giro: el umbral pasa a 0.20
   (`TURN_RESIDUAL`) y el tope de 45° sigue en pie.

5. **Salto en el vértice.** El estado `Jumping` dura unos frames en el vértice,
   con velocidad vertical ≈0. v61 aplicaba la caída balística completa: −2.29
   studs en el disparo 6. Ahora el término vertical solo se aplica si la
   velocidad vertical medida supera **5 studs/s** (`VERTICAL_MIN_SPEED`); por
   debajo se mantiene la altura, que es exactamente lo que hace un cuerpo en el
   vértice. `Climbing` nunca fue aéreo y ya se quedaba en Y.

6. **El eco no se medía nunca.** `echoDelay` fue `nil` en los 13 disparos
   aunque hubo 9 confirmaciones: la conexión que alimentaba `noteEcho` no se
   creó. Ahora el eco se cierra en `finalizeGunCapture`, el mismo camino que
   produjo esas 9 confirmaciones, y se guarda `echoSamples` para saber si el
   horizonte vino del ping o de una mediana real.

7. **Pared invisible.** Cinco de las nueve confirmaciones terminaron 24–56
   studs *antes* del punto apuntado (los disparos 1 y 2 en el mismo plano
   `z = 9017.9736`) con el WallCheck local en verde. El primer pase usa la
   regla del juego (salta todo lo transparente); se añade un **segundo pase
   estricto** que solo salta lo transparente que además no colisiona. Un
   bloqueador transparente y sólido se rechaza y se registra (`noteBlockedShot`
   → evento `gun`/`blocked` con nombre, transparencia, `CanCollide` y
   distancia). Así el siguiente informe dice *qué* pared come el rayo, en vez
   de deducirlo de un fallo.

### Proyección medida (no promesa)

Reproduciendo la sesión con el modelo nuevo sobre las mismas muestras y la
misma verdad (`targetTrajectory`), error horizontal contra el objetivo:

| | media | mediana | máximo |
|---|---|---|---|
| v61 (lo grabado) | 2.27 | 2.02 | 9.32 |
| v62 (proyección) | 1.27 | 1.46 | 1.99 |

Los cinco disparos con bloqueo geométrico (1, 2, 4, 7, 11) bajan su error de
puntería (media 1.77 → 1.28 studs), pero seguirían sin acertar: el rayo del
servidor muere 24–56 studs antes. Se arreglan rechazándolos y anotando el
bloqueador, no apuntando más lejos. La mejora grande es la de los disparos que
sí dependían del modelo: 6, 8, 10, 13 y los de las sesiones 03:51/04:04
(media 2.58 → 1.27).

### Lo que no se cambia (y por qué)

- **El horizonte sigue siendo el RTT completo + 25 ms de interpolación.** El
  mejor `lead` empírico por disparo sale 0.00–0.09 s, pero el ancla
  `referencePoint` está desfasada ~1 stud respecto de la primera muestra de
  `targetTrajectory` (hasta 1.12 studs en el disparo 1, en la dirección del
  movimiento). Con ese piso de ruido no se puede decidir entre RTT completo y
  media ida, y mover el horizonte a ciegas sería repetir el error que este
  documento critica. Queda como pregunta abierta para la próxima sesión, que ya
  registra `echoSamples`.

### Pruebas

- `v62 aim`: vértice sin caída, caída con velocidad real, pico de ping
  filtrado, aceleración ignorada, `getHistory` con edad reportada.
- `invisible wall`: un sólido transparente detiene el pase estricto y se
  nombra; la decoración no colisionable sigue pasando.
- `test_gun_safety`: el segundo pase cuesta un rayo más y el rechazo lleva
  bloqueador; un `WeaponPassthrough` sigue sin bloquear.
- Total: `tools/validate.sh` EXIT=0, 41 suites, 73 archivos, sello
  `v62-20261018-invisible-wall`.

## v63 — La sesión v62: el eco ya mide, y el ping mentía

Archivo nuevo de `TestingStuff`: `MM2_Trajectory_Calibration.json`, sello
**`v62-20261018-invisible-wall`**, 1104.7 s, mismo servidor y misma cuenta.

### Resultado

- **22 intentos de pistola · 8 confirmados · 4 con `hitPart` del objetivo.**
  En v61 fue 13 / 9 / 1. La tasa sobre confirmados pasa de 11 % a 50 %.
- **8 disparos rechazados antes de salir** (`gun/blocked`): todos contra muros
  opacos (`Hotel`, `Office3`, `BioLab`, `Transparency 0`, `CanCollide true`).
  Son los mismos que el pase del juego ya rechazaba; ahora queda escrito cuál
  era. Ninguno fue un falso positivo del pase estricto.
- **El eco ya se mide**: `echoSamples` crece 0 → 1 → 2 → 3 → 4 → 6 → 7 durante
  la sesión. En v61 era `nil` en los 13 disparos.
- Error de puntería en los disparos cuya trayectoria cubre el lead usado:
  2.40 · 2.06 · 0.02 · 0.57 studs (mediana 1.32, antes 2.02).

### Lo que este archivo sí permite separar

1. **El acierto no depende del lead largo.** Los 4 aciertos usaron leads de
   0.139–0.196 s; los fallos 17 y 1/3 no. El disparo 17 tenía el objetivo
   **parado** (`|v| = 0.0`, verdad constante 0.72 s) y la mira a **0.02 studs**:
   aun así el servidor devolvió un impacto a 11.88 studs. Eso no es puntería ni
   lead; es geometría u otro cuerpo. El pase estricto es la única defensa que
   queda y sigue sin poder verse desde el cliente.

2. **El residuo del modelo es la dirección, no el largo.** Ángulo entre la
   velocidad ajustada y el desplazamiento real del objetivo durante el lead:

   | disparo | ángulo | resultado |
   |---|---|---|
   | 18 | 1.6° | acierto |
   | 20 | 10.5° | acierto |
   | 11 | 11.8° | acierto |
   | 3 | 18.6° | fallo |
   | 1 | 23.6° | fallo |
   | 17 | 0.0° (parado) | fallo por geometría |

   Los aciertos quedaron por debajo de 12° y los fallos por encima de 18°. El
   error crece con el horizonte exactamente como crece un error angular fijo,
   que es lo que explica el barrido de abajo.

3. **`GetNetworkPing` no es el ida y vuelta que usa el lead.** Comparando las
   dos lecturas del motor con el eco medido (activación → `GunFired`) en **17
   disparos de tres sesiones**:

   | fuente | dentro de 30 ms del eco |
   |---|---|
   | `Data Ping` (Stats) | 12 de 17 |
   | `GetNetworkPing` | 3 de 17 |

   Los dos «picos de ping» que en v61 se culparon (disparos 8 y 10, `rtt`
   314/342 ms) tenían eco de **151.9 / 164.0 ms**: el pico era de
   `GetNetworkPing`, no de la red. Y al arrancar la sesión v62,
   `GetNetworkPing` leyó **240.8 ms** con `Data Ping` en **130.4** y eco de
   **144.4**; los dos primeros disparos usaron el lead inflado (0.289/0.290 s)
   y fallaron por 2.40/2.06 studs.

### El cambio

`getEstimatedLatency` toma **el menor** de `GetNetworkPing` y `Data Ping`
(ambos validados, y `Data Ping` acotado a 10–2000 ms). La mediana de 8 muestras
del predictor sigue rechazando una caída puntual.

Proyección sobre los 17 disparos grabados, reescalando el lead con la misma
dirección de la mira registrada:

| | media | mediana | máximo |
|---|---|---|---|
| lead actual | 2.08 | 1.85 | 11.00 |
| con `min(GetNetworkPing, Data Ping)` | **1.51** | **1.31** | **3.35** |

Solo cambia el lead en 5 de los 17 disparos; los otros 12 quedan idénticos.
En v61 solo mejora (2.92 → 2.03 de media, máximo 11.00 → 3.35); en la sesión
v62 mejora 1.09 → 0.84 salvo el disparo 20 (0.97 → 1.16, que igual acertó).

### Lo que se probó y se descartó (con los datos)

- **Barrido de horizonte.** Barrer el lead de 0.04 a 0.28 s da un mínimo en
  0.04 s en las tres sesiones (media 0.31 studs en v62). Tentador, pero está
  confundido: para un objetivo en línea recta y velocidad constante el error es
  **plano** en el horizonte; lo que crece con `h` es el error **angular** (23.6°
  en el disparo 1). No es evidencia de que el lead deba ser 0.04 s, y no se
  cambia por eso.
- **`Humanoid.MoveDirection` como dirección de tiro.** Es una señal replicada
  real (el disparo 1 pulsaba +X mientras la velocidad caía en −Z), así que se
  probó como dirección en vez de la velocidad ajustada, sobre los cinco
  disparos con muestras suficientes:

  | disparo | velocidad ajustada | `MoveDirection` |
  |---|---|---|
  | 3 | 18.6° | **1.1°** |
  | 18 | 1.6° | **0.4°** |
  | 1 | 23.6° | **8.2°** |
  | 11 | 11.8° | 15.9° |
  | 20 | 10.5° | 17.2° |

  Mejora tres y empeora dos, y los dos empeoramientos son aciertos: en el
  disparo 11 el jugador giraba y `MoveDirection` seguía apuntando al lado
  anterior. Sin un umbral medido que separe los dos casos, no entra. v64
  graba también el `MoveDirection` de cada muestra del historial para poder
  decidir esto sin otra sesión.
- **`MIN_ECHO_SAMPLES` de 6 a 3.** En esta sesión habría adelantado el eco a los
  disparos 17–19 con efecto neutro (sus objetivos casi no se movían). Sin
  evidencia a favor, no se toca.

### Añadido para la próxima sesión

`rttEngine` y `rttData` viajan en `settings` de cada disparo, junto a
`echoSamples`, `turnRate` y `brakeSeconds`. Así la próxima calibración puede
decidir el horizonte con el eco y las dos lecturas del motor en el mismo
registro, sin reconstruirlo.

## v64 — Una sola sesión que responda todo

v63 ya no cambia el modelo: cambia lo que la sesión **guarda**. La sesión v62
dejó tres preguntas abiertas y ninguna se puede cerrar sin volver a jugar, así
que v64 graba en el mismo `MM2_Trajectory_Calibration.json` lo que hace falta
para contestarlas después, sin pedir otra calibración.

### Lo que la sesión v62 no permitía contestar

1. **El ida y vuelta de verdad.** `confirmation.serverTime − authored.serverTime`
   daba 501.5 · 514.6 · 507.4 · 502.7 · 517.9 · 546.6 · 506.4 ms en los siete
   disparos confirmados: eso no es el viaje, es el viaje **más** los 0.5 s que
   el capturador espera antes de cerrar el disparo. `finalizeGunCapture` sellaba
   la hora al finalizar, no al llegar la señal. Con esos números no se puede
   saber si el lead debe usar `GetNetworkPing` o `Data Ping`.
2. **Dónde terminó la bala.** El `endpoint` viene del extremo del `CreateBeam`,
   no del impacto: los fallos 1/3/17/18 terminaron a 35.2 / 15.9 / 31.0 / 14.9
   studs de cualquier superficie, y el acierto 18 también, a 14.9. Sin el
   cuerpo y el tamaño de la parte golpeada no se puede distinguir “el rayo
   pasó por al lado” de “el rayo se detuvo en un muro que el cliente no ve”.
3. **Por qué la trayectoria se corta.** En los tres disparos enlazados la
   muestra duraba 0.09–0.14 s aunque el capturador muestrea durante medio
   segundo más. La causa ya está localizada: `captureTrajectoryPoint` devuelve
   `nil` si el humanado tiene `Health <= 0`, y los disparos 18, 20 y 186 son
   justamente los que mataron. La trayectoria no está truncada: termina en la
   muerte. v64 lo escribe en el registro en vez de dejarlo a la deducción.
4. **Daño real.** `hitTarget` dice que el rayo tocó el personaje; no dice que
   el servidor haya aplicado daño. La única prueba del lado del cliente es la
   caída de `Humanoid.Health`.
5. **El desvío de dirección.** La tabla de ángulos se calculó comparando la
   velocidad ajustada contra el desplazamiento real y después, fuera de línea,
   contra `MoveDirection`, que no estaba guardado.

### Lo que graba v64

| campo | dónde | para qué |
|---|---|---|
| `serverActivatedAt`, `serverConfirmedAt`, `serverEchoMs` | confirmación | ida y vuelta real, con el mismo reloj del servidor en los dos extremos |
| `rttEngineAtConfirmation`, `rttDataAtConfirmation` | confirmación | las dos lecturas del motor **en el momento de llegar**, no solo al disparar |
| `aim`, `origin` | confirmación | puntuar un disparo sin depender del evento `authored` |
| `hitPart`, `hitPartPosition`, `hitPartSize` | confirmación | qué tocó el rayo, dónde y de qué tamaño |
| `rootAtConfirmation` (posición, velocidad, estado) | confirmación | dónde estaba el objetivo cuando llegó la señal |
| `lastSeenPosition` | confirmación | última posición muestreada, útil si el objetivo murió |
| `healthAtAim`, `healthAtConfirmation`, `healthAfter`, `healthDropAt`, `healthDropServerTime`, `died`, `diedAt`, `diedServerTime` | confirmación | daño y muerte con los dos relojes |
| `trajectoryPoints`, `trajectorySpanSeconds`, `trajectoryCapped`, `samplingStoppedReason` | confirmación | cuánta trayectoria hay y por qué termina |
| `occluder` (nombre, clase, distancia, transparencia, `CanCollide`) | `settings` del disparo | lo primero que encuentra el rayo sin el filtro del juego, **también en los disparos permitidos** |
| `moveDirection` por muestra | `targetHistory` | decidir velocidad contra `MoveDirection` sin otra sesión |
| `clock` | `authored` y confirmación | alinear `os.clock` con el reloj del servidor en la misma máquina |

Además:

- La trayectoria se muestrea a **60 Hz** (antes 30 Hz) y el tope sube de 120 a
  **200 puntos**: a 30 Hz no se puede resolver un horizonte de 0.02 s.
- El límite de eventos ya no borra el disparo de pistola cuando la sesión llena
  el registro con cuchillos: primero se descarta el `knife/authored` más viejo
  y se cuenta en `session.evictedEvents`.
- Las conexiones de `HealthChanged` se desconectan al cerrar y al compactar la
  cola; sin eso una sesión larga filtra conexiones.
- Cada disparo de cuchillo guarda también `rtt`, `echoSamples`, `rttEngine`,
  `rttData`, `turnRate` y `brakeSeconds`, que antes solo tenía la pistola.

No cambia ninguna constante del modelo: el lead sigue siendo el menor de
`GetNetworkPing` y `Data Ping`, acotado a 0.02–0.6 s, y el horizonte sigue
siendo `echo or (rtt + 0.025 + sampleAge)`.

## v65 — Las dos sesiones v64: el reloj quedó probado y el eco tenía dos fuentes

Archivos nuevos en `TestingStuff`: dos sesiones con sello
`v64-20261018-definitive-capture`.

| sesión | duración | intentos | confirmados | tocaron al objetivo | bloqueados |
|---|---|---|---|---|---|
| `91bec4b8` | 1340.4 s | 11 | 8 | **6** | 5 |
| `e995782f` | 188.9 s | 13 | 5 | **0** | 3 |
| total | — | 24 | 13 | **6** | 8 |

Los otros tres `.json` nuevos son el mismo archivo v62 subido tres veces: mismo
`md5` (`5d0ccad…`), mismo `savedAt` (05:40:11) y mismo `sessionId`. No aportan
nada y no se contaron.

### Lo que la captura v64 sí resolvió

1. **El reloj del servidor quedó probado.** `serverEchoMs` no llegó al archivo
   (ver el fallo de abajo), pero se reconstruye restando `serverConfirmedAt`
   menos el `serverTime` del evento `authored`, que se sella justo después de
   `FireServer`. Contra el `latencyMs` medido en el cliente:

   | disparo | reloj servidor | `latencyMs` | diferencia |
   |---|---|---|---|
   | 1 | 182.8 | 182.9 | 0.1 |
   | 3 | 182.3 | 182.4 | 0.1 |
   | 5 | 188.5 | 188.5 | 0.0 |
   | 7 | 448.1 | 448.2 | 0.1 |
   | 8 | 469.2 | 472.3 | 3.1 |
   | 9 | 142.2 | 150.4 | 8.2 |
   | 10 | 160.9 | 160.6 | 0.3 |
   | 11 | 189.1 | 189.2 | 0.1 |
   | 1 (B) | 126.4 | 126.4 | 0.0 |
   | 3 (B) | 151.8 | 151.8 | 0.0 |
   | 6 (B) | 280.2 | 280.2 | 0.0 |
   | 8 (B) | 166.5 | 158.1 | 8.4 |
   | 11 (B) | 382.4 | 382.4 | 0.0 |

   **13 de 13 dentro de 9 ms.** El ida y vuelta real de estas sesiones fue
   **126–472 ms**, y el `rtt` con el que se construía el lead (la menor de las
   dos lecturas del motor) fue **80–154 ms**: entre 1.15 y 4.7 veces menos
   (mediana 1.6). Es la primera vez que el insumo del lead está medido y
   verificado contra el reloj del servidor en el mismo disparo.

2. **La trayectoria ya se graba completa.** 3–38 puntos por disparo con
   ventanas de 0.09–0.89 s, `trajectoryCapped = false` en los trece, cero
   eventos desalojados y cero señales sin pareja. En v62 eran 4 puntos y 0.12 s
   en los disparos enlazados: el problema está cerrado.

3. **El daño se puede leer, aunque el disparo que lo mata se escape.** En 5 de
   los 6 aciertos el objetivo estaba en `healthAtConfirmation = 0` cuando llegó
   la señal, o sea que murió dentro del ida y vuelta del disparo. En el sexto
   (disparo 8) estaba en 100: fue un impacto sin muerte.

### El fallo que la propia sesión destapó

`healthAtAim` quedó en `nil` en los trece disparos y `serverEchoMs` no se
escribió. La causa: había **dos** constructores del registro pendiente. El
camino real (`noteAuthoredShot`) armaba su propia tabla y no llamaba a
`watchPendingHealth` ni sellaba `serverActivatedAt`; el único que lo hacía era
el observador de `tool.Activated`, que en estas sesiones creó un solo registro.
Ahora hay un constructor único (`beginPendingShot`) y una prueba que impide que
vuelva a haber dos.

### El segundo defecto: el eco tenía dos fuentes

En el disparo 9 la mediana del eco era **318 ms** mientras el ida y vuelta
medido de ese mismo disparo era **150 ms**. El lead salió 381 ms, el error de
puntería en el momento del disparo fue **3.90 studs** (el mayor del archivo) y
el disparo falló. En el 10, igual: eco 303 ms, real 161, lead 379, error 6.15
studs, fallo.

La mediana no podía ser 318 con los ocho ecos reales (todos entre 150 y 472,
mediana 188). La causa es que `Prediction.noteEcho` recibía muestras de **dos**
caminos: la confirmación (`finalizeGunCapture`, que mide activación → señal) y
el emparejador de `mm2ShotFeedback`, que mide desde la cola de feedback. En el
disparo 9 la lista tenía 8 muestras cuando solo habían ocurrido 5
confirmaciones: tres venían del segundo camino, y eran las grandes.

Queda una sola fuente, la verificada contra el reloj del servidor.

### Lo que estas sesiones NO explican

Los cinco fallos de la sesión corta son otra cosa. El objetivo se movía a
14–18 studs/s y el punto de mira quedó a **0.27 · 0.87 · 2.31 · 3.54 · 3.82**
studs del root en el instante en que llegó la señal; el rayo siguió de largo y
terminó en una pared detrás. Los aciertos de la sesión larga quedaron a
**0.17 · 0.81 · 1.36 · 1.92 · 3.69 · 4.63** studs: **los dos rangos se
solapan**. O sea que el error del punto de mira ya no separa acierto de fallo;
lo que decide es qué parte del cuerpo corta el rayo (postura, brazos, aire).
Eso no se arregla con más lead: se arregla eligiendo la parte que se apunta, y
para eso el archivo ahora guarda `aimOffset` en cada muestra del historial y
`aimOffsetAtFire` por disparo, además de `hitPart`, `hitPartSize` y
`hitPartPosition`, que ya estaban.

### Cambios de v65

- Constructor único del registro pendiente: la salud en el momento del disparo
  y los dos sellos del servidor ya no dependen de qué camino disparó.
- Una sola fuente de eco (la confirmación), y `MIN_ECHO_SAMPLES` de 6 a 3: con
  la fuente verificada, tres muestras alcanzan, y en sesiones cortas el lead ya
  no se queda con la lectura del motor, que es la mitad del ida y vuelta.
- `aimOffset` por muestra y `aimOffsetAtFire` por disparo.
- Tres pruebas nuevas: una sola fuente de eco, constructor compartido, y que
  ningún sitio llame a `table.insert(runtime.pendingGuns` por fuera.

No cambia ninguna constante del modelo de movimiento.

## v66 — El cuchillo vuela como una hoja, no como un rayo

El cuchillo fallaba donde el arma de fuego no: la puntería se resolvía con un
rayo de grosor cero. Un rayo atraviesa el hueco entre el pecho y una barandilla
que la hoja no atraviesa, y el servidor sí colisiona el proyectil. La
consecuencia práctica es la que se veía en las partidas: la puntería "acertaba"
en el archivo y el cuchillo se clavaba en la pared o en la reja que estaba
delante del pecho.

### Lo que cambió

- **La hoja tiene grosor.** `knifeRadius` sale del `Handle.Size`: la mediana de
  las tres mitades de sus ejes, que es la sección que tiene que pasar por el
  hueco, acotada entre **0.12 y 0.6** studs (por defecto **0.25** si el modelo
  no expone un Handle usable). El eje largo corre a lo largo del vuelo, así que
  el hueco lo limita la mediana y no la mitad mayor.
- **La prueba es de cuerpo, no de rayo.** `knifeReaches` usa `workspace:Spherecast`
  con el radio de la hoja: el resultado tiene que ser el objetivo. Donde el motor
  no tenga Spherecast, un rayo central más un anillo a `radius` demuestra lo
  mismo, y **falla cerrado**: si un rayo del anillo se topa con algo que no es el
  objetivo antes de llegar, la puntería no vale.
- **El filtro es el del juego.** El sondeo excluye el propio `Character` y los
  objetos con la etiqueta `WeaponPassthrough`, igual que el `WeaponService` del
  cliente; no se descarta nada por transparencia, porque una parte invisible con
  colisión también detiene una hoja.
- **La puntería sube por el mundo.** La escalera de puntería es ahora
  `pecho → pecho alto (+0.55) → cabeza (+1.05) → sobre la cabeza (+1.5) →
  piernas (−0.6) → hombros (±0.6)` y **todos los pasos se aplican sobre el eje Y
  del mundo**. Con el vector perpendicular al vuelo, que era lo anterior, un
  lanzamiento inclinado movía la puntería de lado y no por encima de una
  barandilla horizontal.
- **No se lanza sin destino.** Si ninguna grada alcanza al objetivo porque hay
  geometría en medio, el lanzamiento se rechaza con `covered` en vez de
  gastarse. Los otros dos rechazos son `unreachable` (el predictor no cerró el
  intercepto) y `too far`, que ya no es un alcance artificial: el cuchillo vuela
  hasta chocar, así que solo se rechaza un lead absurdo de más de **400 studs**
  (objetivo desaparecido o muestra rota).
- **Un tiro, un paquete, resuelto al soltar.** `performThrow` vuelve a elegir
  objetivo visible y resuelve la puntería en el instante del envío, así que la
  pose del gesto no puede disparar desde una mano vieja, y el paquete es el
  mismo que manda el cliente del juego: `CFrame.new(orig.Position),
  CFrame.new(aim)`, **solo posición**, sin la rotación del Handle. El origen se
  toma del `Handle`, y si no existe del `RightHand`, del brazo o del
  `HumanoidRootPart`.
- **Botón para móvil.** Segundo checkbox **"Lanzar con el boton"** (clave
  `MM2.Shoot.KnifeThrowButton`, apagado por defecto) justo debajo de "Knife
  Throw". En ese modo no hay gesto de espera: el lanzamiento sale en el
  `Tool.Activated`, que es el evento que producen tanto un toque como un clic, y
  se ignora un segundo toque dentro de **0.25 s**. La conexión sigue al cuchillo
  equipado también después de reaparecer.
- **La grabación aprende dónde pegó.** Cada lanzamiento anota en la captura
  `aimHeight` (la grada usada), `aimOffsetStuds`, `knifeRadius`, `throwSource`
  (`auto`/`manual`) y `windupSeconds`, para poder auditar después por qué una
  grada funcionó y otra no.

### Pruebas

- `tools/test_mm2_knife_wallcheck.py` (nueva, 6 comprobaciones): un solo sondeo
  con el pecho despejado; una barandilla sobre el pecho obliga a subir a la
  cabeza (Y 5.05) en tres sondeos; radio 0.2 / 0.12 / 0.6 desde el tamaño del
  Handle y el valor por defecto; siete gradas tapadas fallan cerrado; el anillo
  veta un hueco que el rayo central no ve (14 rayos, no 35); y los rechazos
  `unreachable` y `too far` (400).
- `tools/test_mm2_knife_presets.py` amplía el escenario con `Spherecast` y el
  bloque de disparo manual: un toque lanza una vez, el doble toque no lanza, y
  apagar la casilla suelta el `Activated`.
- `tools/test_mm2_knife_rebuild.py` comprueba que el paquete lleva **solo la
  posición** del Handle y sigue el objetivo reelegido en el momento de soltar.

`bash tools/validate.sh` → **75 fuentes compilan, 41 suites en verde**, arranque
del bundle con `failures=0`.

### Lo que esta versión NO afirma

Todavía no hay sesión real con el sello v66. El grosor, la escalera y el botón
están probados en el arnés contra un mundo simulado, no medidos contra el
servidor de Murder Mystery 2. El lado de `Shoot` no se tocó en esta versión.

## v67 — Móvil con botones de verdad, secciones en las opciones y Disguise con animaciones completas

### Móvil: lo que no se puede hacer desaparece, y aparece Buttons

La ventana **UI Settings** tenía una fila **Keybinds** en todos los dispositivos.
Un teléfono no tiene teclado, así que esa fila ahora se llama **Buttons** y
abre otra ventana, solo en táctil; en PC sigue siendo Keybinds y no cambia
nada. Además:

- **Cada acción puede tener su botón.** La lista muestra los botones ya
  colocados (tocar uno abre su editor) y **Add button** ofrece cada atajo que
  todavía no tiene botón: al elegir uno se entra en el modo de colocación de
  siempre. Los botones de mantener (vuelo, etc.) conservan su
  `isActive`/`onPress`/`onRelease`.
- **Forma, color, tamaño y opacidad.** El editor del botón (mantener pulsado
  el botón, o tocar su fila en la lista) añade **Shape** (Square / Rounded /
  Circle) y **Colour** (ocho colores). El texto del botón cambia solo entre
  claro y oscuro según el fondo para seguir siendo legible. **Apply to all
  buttons** copia la apariencia a todos los botones de una vez.
- **Valores por defecto para botones nuevos.** La misma ventana tiene
  **Default shape** y **Default colour**; el botón por defecto sigue siendo
  **cuadrado** (Square), como antes, pero ahora es una elección.
- Se guardan en la misma entrada de siempre: los cuatro valores originales
  (`x`, `y`, `size`, `opacity`) y dos nuevos (`shape`, `color`), así que los
  perfiles viejos cargan sin migración.
- **La casilla de atajo en cada card ya no es un hueco de teclado.** En táctil
  muestra `+` cuando la acción no tiene botón y, cuando lo tiene, dibuja una
  vista previa de su forma y color; al tocarla abre el editor (o inicia la
  colocación si todavía no existe).
- **Las opciones de tecla desaparecen en táctil.** `addKeyOption` (Pickup key,
  Shot key, PowerShot key, etc.) ya no deja filas vacías que no se pueden
  pulsar: se quitan de la card. Las teclas de teclado y los cuadraditos de
  keybind ya estaban ocultos en móvil.

### Secciones (headers) en las opciones

`addSectionOption` era un marco invisible que cada módulo rellenaba a mano.
Ahora es un **header real**: título en mayúsculas, color atenuado, altura fija
y una línea fina hasta el borde. `Freeze Movements` dejó de dibujar su propia
etiqueta y usa el mismo widget.

En **SilentAIM** el orden queda:

```
Gun
  Auto Shoot
  Aim method
  Target
  WallCheck
  Macro
  …
Knife
  Knife Throw
  Throw with button
```

Es decir: el header **Gun** abre las opciones del arma de fuego y el header
**Knife** abre las del cuchillo, que es lo que el módulo del cuchillo crea de
todos modos. Se eliminó el truco que movía la fila de Knife Throw a la
posición 2 a mano: ya no hace falta. De paso, **"Lanzar con el boton"** pasó a
**"Throw with button"**: el menú está en inglés y esa era la única etiqueta en
español.

### Disguise: el ID por defecto y las animaciones que faltaban

- **ID por defecto: 78492.** Es una cuenta real (`fatcat`), no el usuario del
  autor de Vape que se había heredado (239702688 = 7GrandDadPGN). El cuadro de
  texto ya arranca con 78492.
- **Las 7 animaciones de Roblox ya no se pierden.** Un `HumanoidDescription`
  guarda `0` en los slots que usan la animación por defecto. Copiar solo los
  valores distintos de cero dejaba *nuestras* animaciones en el avatar
  disfrazado. Ahora los slots vacíos se rellenan con el set R15 de Roblox
  (idle ×3: 507766666 / 507766951 / 507766388, walk 507777826, run 507767714,
  jump 507765000, fall 507767968, climb 507765644, swim 507784897, swim-idle
  507785072), que son exactamente los IDs del script `Animate` por defecto.
  Si el objetivo sí eligió un pack, sus IDs mandan.
- **Los tres idles se aplican en orden**, no el mismo repetido: `Animation1`,
  `Animation2` y `Animation3` reciben su variante; si solo hay un ID, se usa
  para todos como antes. El campo `MoodAnimation` no se fuerza porque el set
  por defecto no trae uno.
- **Animation mode acepta un pack de animación**, como el Disguise de Vape.
  Si el número no es un usuario, se consulta
  `MarketplaceService:GetProductInfo(id, Enum.InfoType.Bundle)`; si es
  `AvatarAnimations` se mapean sus ítems (Idle/Walk/Run/Jump/Fall/Climb/Swim/
  Swim Idle) y se usa el `AnimationId` real cuando el ejecutor permite
  `game:GetObjects` (es lo que hace Vape), o el id del ítem si no. Si el
  bundle no es de animaciones, se avisa: no se finge que se aplicó.
  `game:GetObjects` / `InsertService` siguen **fuera** de las funciones de
  copia de avatar, que es donde antes colgaban el botón.
- **Character mode sigue necesitando un usuario** (un pack no tiene avatar).

### Pruebas

- `tools/test_mobile_buttons.py` (nueva): formas, paleta, contraste del texto,
  esquina aplicada, página Buttons en táctil y solo en táctil, guardado de
  `shape`/`color`, vista previa de la card y eliminación de filas de tecla.
- `tools/test_option_headers.py` (nueva): el header se dibuja visible con su
  caption y su línea, Gun/Knife en el orden correcto, etiqueta inglesa y
  `Freeze Movements` sin etiqueta duplicada.
- `tools/test_disguise_defaults.py` (nueva): los siete clips por defecto, los
  tres idles en orden, mapeo del pack (incluido Swim vs Swim Idle) y errores
  cerrados.
- `tools/test_mm2_knife_presets.py` actualizado a **"Throw with button"**.
- El arnés de arranque completo comprueba ahora los dos headers y que la
  opción del botón vive bajo Knife.

`bash tools/validate.sh` → **75 fuentes compilan, 44 suites en verde**,
arranque con `failures=0`.

### Lo que esta versión NO afirma

No hay prueba en un dispositivo táctil real: el layout del editor y la
colocación se validan en el arnés de UI, no con un teléfono en la mano. El
paquete de animación depende de que el ejecutor exponga `game:GetObjects` para
leer el `AnimationId` real; si no, se usa el id del ítem y puede no sonar.

---

## v68-20261018-rig-animations-and-lead-feedback

### El avatar congelado del Disguise

La captura mostraba el avatar propio **quieto en su pose de reposo** después de
Disguise en modo Animation. No era un idle equivocado: era el rig equivocado.

- **MM2 corre en R6.** El set que se rellenaba por defecto era el de R15
  (`507766666`, `507777826`, …). Esas animaciones están construidas sobre
  `UpperTorso` y `RightUpperArm`; en un cuerpo R6 **no se reproducen**, y el
  `Animate` se queda sin pista activa. El personaje conserva la última pose.
- **Los defaults ahora dependen del rig.** `rigDefaultSlots(humanoid)` lee
  `Humanoid.RigType`: R6 recibe el set clásico (idle `180435571` +
  `180435792`, walk/run `180426354`, jump `125750702`, fall `180436148`,
  climb `180436334`) y R15 conserva el suyo. `cacheTarget` ya **no** hornea
  defaults: guarda solo lo que el objetivo eligió, porque cuál es el default
  depende de nuestro cuerpo, no del suyo.
- **Un set R15 sobre un cuerpo R6 se detecta y se sustituye.** Un avatar sin
  pack llega con los ids 50xxxxx; `belongsToR15Defaults` los reconoce y
  `resolvedAnimationSlots` los trata como hueco. Un pack propio se intenta tal
  cual.
- **El reinicio del `Animate` se verifica.** El script clásico solo reproduce
  el idle desde un evento `Humanoid.Running`, que un cuerpo parado nunca
  dispara: reiniciarlo puede dejar cero pistas. `settleMovementAnimations`
  espera 0.1 s, cuenta pistas con `GetPlayingAnimationTracks` y, si no hay
  ninguna, **puentea el idle** cargando el mismo `Animation` del `Animate`
  (`playIdleBridge`) y retirándose en cuanto otra pista empieza.
- **Si nada suena, se vuelve atrás.** Con el set del rig tampoco: se restaura
  el snapshot, `animationOverrideApplied` vuelve a `false` y la barra de estado
  lo dice. Nunca se deja al jugador en una pose fija y nunca se afirma que se
  aplicó lo que no se aplicó.
- La copia del avatar sigue **sin esperar**: `applyAnimationSlots` solo
  escribe ids y reinicia; toda la verificación vive en
  `settleMovementAnimations`, fuera del camino de copia.

### Disparo: el lead ahora se corrige con las confirmaciones

- **Error de lead medido, con signo.** En `finalizeGunCapture` se interpola
  dónde estaba el root del objetivo **cuando el servidor procesó el disparo**
  (`activación + ida`), se le suma el `aimOffset` del último sample y se
  proyecta sobre su velocidad horizontal: positivo = iba por delante de
  nuestra puntería (faltó lead), negativo = sobró.
- **Corrección acotada.** Mediana de las últimas 8 mediciones (mínimo 3),
  cada muestra limitada a ±0.15 s, resultado acotado a **±0.06 s** y sumado al
  horizonte solo cuando el lead es automático. Un teleport, un cambio de
  objetivo o un NaN se descartan en vez de aprenderse.
- **Todo queda en el archivo.** Cada confirmación escribe
  `leadErrorSeconds` y `leadCorrectionSeconds`; cada disparo enviado escribe
  `leadCorrection`. No hace falta otra ronda de instrumentación: la siguiente
  sesión ya llega con el lazo cerrado.

### Cuchillo: CFrame coherente y transporte medido

- **El origen ya no es una posición suelta.** Se envía
  `CFrame.lookAt(handle.Position, aim)`: misma posición de siempre y un
  `LookVector` que apunta al punto predicho. Los registros nativos mostraban
  un origen **con rotación no identidad**; con la rotación identidad, cualquier
  servidor que lea `LookVector` lanzaría hacia el -Z del mundo. El segundo
  argumento sigue siendo una posición: ahí debe terminar la hoja.
- **El cuchillo usa el eco medido.** `knifeHorizon` toma la mediana del viaje
  real `FireServer → GunFired` cuando existe (misma conexión, mismo servidor) y
  solo cae al ping del motor si no hay muestras. En v64 el viaje real fue
  126–472 ms contra una lectura de motor de 80–154 ms: hasta 300 ms de
  movimiento sin liderar, que es el cuchillo quedándose atrás.
- La captura anota `originRotation` y `echoDelay` para poder separar ambas
  cosas en la próxima sesión.

### Pruebas

- `tools/test_disguise_defaults.py` reescrita: sets R6/R15, sustitución de
  defaults R15 en R6, pack propio intacto, fallback al set del rig, restore
  cuando nada suena, y los mapeos de bundle de siempre. **9 comprobaciones.**
- `tools/test_prediction_lead_feedback.py` (nueva): mediana, mínimo de 3
  muestras, tope ±60 ms, rechazo de teleports/NaN, offset manual intacto y
  horizonte del cuchillo con eco. **7 comprobaciones.**
- `tools/test_prediction_lead_measure.py` (nueva): signo del error, objetivo
  parado, salto de 20 studs y datos faltantes. **6 comprobaciones.**
- `test_mm2_knife_rebuild.py` y `test_mm2_knife_wallcheck.py` actualizados al
  CFrame con `lookAt`, con la comprobación de que la rotación identidad **no**
  vuelve.

`bash tools/validate.sh` → **75 fuentes compilan, 46 suites en verde**,
arranque completo con `failures=0`.

### Lo que esta versión NO afirma

Las calibraciones nuevas **no llegaron al workspace**: no hay ningún
`MM2_Trajectory_Calibration.json` en el repositorio ni en las subidas de esta
sesión, así que no se revisaron. Lo de arriba se apoya en los registros
nativos ya citados (v33/v34) y en la sesión v64 que sí está en el repo. No hay
prueba en dispositivo táctil ni sesión real con este sello.

---

## v69 — un paquete por cuchillazo y el rig que de verdad se mueve

Sello: `v69-20261018-single-knife-packet-and-moving-rig`.

### Lo que dicen las 27 calibraciones de `XzAngel19/TestingStuff`

Se descargaron y procesaron **las 27 capturas** (`MM2_Trajectory_Calibration.json`
más sus 26 copias `.before-*`, 4 KB–10 MB) y el `Shoot..txt`. Números reales:

| dato | valor |
| --- | --- |
| sesiones con eventos | 20 |
| lanzamientos de cuchillo anotados (sesión grande, v67) | **722 en 22 s** (máximo **77 en un segundo**) |
| cuchillo confirmado por proyectil observado | 15 de esas 722 |
| velocidad del cuchillo medida | **96 studs/s en las 20 sesiones** |
| retardo de aparición del cuchillo | mediana ≈ 151 ms |
| aceptación del disparo (`GunFired`) | media 237 ms, mínimo 95, máximo 980 |
| aciertos de arma sobre confirmaciones | **95 de 173 (55 %)**; sesión v67: 25/48 |
| error de lead en el instante de resolución | mediana **−10…+12 ms** por sesión |

El hallazgo que explica la falta de precisión del cuchillo no es la puntería:
`performThrow` se llamaba **una vez por frame**. Con `throwPending` armado
después de comprobar la pose, la rama «este rig no tiene hombro que animar»
largaba el paquete sin armar la guarda, y el bucle de `RenderStepped` volvía a
entrar al frame siguiente. El servidor recibe decenas de paquetes por segundo y
usa el primero que acepta: la hoja sale con el aim de *ese* frame, no con el
que el predictor consideró bueno.

### Cuchillo

- **Un paquete por ciclo.** `throwPending` se arma **antes** de inspeccionar la
  pose; si no hay articulación que animar se lanza una vez y un `task.delay`
  libera la guarda al terminar el ciclo (0.55 s). El ciclo ahora es la constante
  `KNIFE_CYCLE_SECONDS`.
- **Segunda barrera antes del cable**: `MIN_PACKET_INTERVAL` (0.25 s). Ningún
  llamador —auto, botón, reentrada— puede emitir dos paquetes dentro de esa
  ventana. Todo lo anterior es lectura, así que un paquete rechazado no cuesta
  nada.
- El `CFrame.lookAt(handle, aim)` de v68 se mantiene: el registro sigue
  anotando `originRotation` para distinguir builds.

### Gafas (Disguise): el rig que no se mueve

La captura del avatar «en pose rara» es un rig **congelado**, no un idle
equivocado. Un pack R15 comprado sobre un cuerpo R6 no escribe ni una
articulación, pero Roblox devuelve igual un `AnimationTrack` con
`IsPlaying = true`. La comprobación de v68 miraba ese flag, así que daba por
buena una animación que no movía nada; solo el objetivo sin pack (el 78492 por
defecto) caía en los defaults R6 y se movía. De ahí que «solo funcione con
fatcat».

- `poseSignature`/`poseMoves` leen `Motor6D.Transform` del cuerpo y exigen que
  la pose **cambie** en una ventana de 5 muestras. Si no cambia, el clip no es
  del rig.
- `settleMovementAnimations` comprueba la pose en las tres ramas (track del
  script, puente de idle y set propio del rig). Solo acepta la que mueve el
  cuerpo.
- Si el set propio del rig tampoco mueve el cuerpo, se restaura el snapshot y se
  avisa; nunca se deja el avatar tieso.
- `applyCachedMovementAnimations` vuelve a asentar aunque no haya escrituras:
  reaplicar el mismo objetivo tiene que arreglar un cuerpo que quedó congelado
  en una aplicación anterior.

### Puntería silenciosa

- El segmento del bypass silencioso ya no es un largo fijo: crece con la
  **incertidumbre de lead medida** (`getLeadUncertainty`, mediana de los
  |errores| de las últimas confirmaciones) por la velocidad horizontal del
  objetivo, con el mismo tope del slider. Sin muestras vale cero y el slider se
  usa tal cual.
- El `Shoot..txt` confirma el formato del remoto: `FireServer(CFrame, CFrame)`
  desde el arma, igual que ya se envía.

### Herramienta nueva

`tools/analyze_calibration_sessions.py` lee un directorio de capturas y saca
por sesión: sellos, disparos, confirmaciones, aciertos, eco vs ping, error de
lead en el instante de resolución, lead ideal, lanzamientos y velocidad medida.
Es de solo lectura.

### Pruebas

- `tools/test_silent_aim_sweep.py` (nueva): el segmento con el slider, con la
  incertidumbre medida (0.06 s × 16 studs/s = 0.96 studs), con objetivo quieto,
  con el tope y con una medición ausente o que falla. **5 comprobaciones.**
- `test_disguise_defaults.py`: nuevo caso de rig congelado —un track «sonando»
  que no mueve ninguna articulación— que debe acabar en el set del rig y avisar.
  **10 comprobaciones.**
- `test_prediction_lead_feedback.py`: incertidumbre medida, sin signo y cero sin
  muestras. **8 comprobaciones.**
- `test_mm2_knife_rebuild.py` y `test_mm2_knife_presets.py`: el segundo paquete
  dentro de la ventana se descarta y el ciclo siguiente vuelve a enviar.

`bash tools/validate.sh` → **75 fuentes compilan, 47 suites en verde**,
arranque completo con `failures=0`.

### Lo que esta versión NO afirma

- No hay medición en el juego con este sello: los números salen de las capturas
  guardadas, no de una sesión nueva.
- El cuchillo sigue dependiendo de que el servidor acepte el paquete; lo que
  cambia es que ahora manda **uno** con la puntería buena en vez de decenas.
- El set R15 de un objetivo **no puede** reproducirse en un cuerpo R6: en ese
  caso se muestra el set del rig y se avisa. Si prefieres que la casilla
  desaparezca en rigs R6, dilo y se quita.

## v70 — el clip tiene que ser del cuerpo, no del objetivo

Sello: `v70-20261019-disguise-rig-guard-and-menu-audit`.

### La captura `Screenshot_20261018_192834_Roblox.jpg`

El avatar disfrazado aparece **arrodillado y hundido**: los muslos atraviesan
el suelo, el torso va inclinado hacia delante y los brazos quedan pegados al
cuerpo. Las articulaciones son de un cuerpo **R6**. Eso no es una pose idle
equivocada: es el resultado de escribir clips **R15** en un `Animate` de R6.
El motor no rechaza el clip que no encaja, lo reproyecta y deforma el cuerpo.

Coincide con el único patrón del informe: **solo pasa con packs que no son el
de defecto**. Con el pack de defecto la descripción devuelve los ids R15 por
defecto, que ya se descartaban, así que el cuerpo se quedaba con su set y se
veía bien. Con Toy, Ninja y compañía los ids no son de defecto y se escribían.

La versión anterior (v69) solo protegía el caso «el objetivo es R15». En una
partida R6 el objetivo **también es R6**, así que esa condición no se cumplía
nunca y el cuerpo seguía recibiendo clips que no son suyos. Por eso el fallo
seguía ahí.

### La regla nueva

La pregunta ya no es de qué rig es el objetivo, sino **de quién es el clip**:

- Un cuerpo **R6** solo acepta ids del set R6 por defecto. Cualquier otro
  (pack comprado, bundle manual, id suelto) se descarta.
- Un cuerpo **R15** rechaza el set R6 y acepta lo demás, que es donde se
  escriben los clips de pack.
- El descarte se informa **una vez por objetivo** y el estado de la tarjeta
  ahora dice cuántos slots se saltaron: `Character · R6 · 0 slots · 4 pack
  clips skipped`.

No hay forma de saber el rig de un clip desde una `HumanoidDescription`: no
lleva ese dato. El único set que el cliente puede avalar es el de defecto de
su propio rig. Preferimos un avatar que se mueve con su set antes que uno
deformado con el del objetivo.

### Auditoría del menú MM2

`tools/audit_menu.py` (nuevo) arranca el bundle real en el entorno simulado y
vuelca **cada tarjeta y cada fila** en el orden en que se ven, en Markdown o
JSON. Sirve porque un módulo puede compilar, viajar en `bundle.lua` y no
registrarse nunca: el grep no lo distingue.

Resultado: **35 tarjetas**, de las cuales la sección MM2 tiene **4**
(SilentAIM, Fling, Blurt Roles, Calibration). El resto de controles de MM2
(Gun ESP, Trap ESP, colores por rol, Knife Aura, Sprint, teleports y Get Gun)
viven dentro de tarjetas universales. El informe completo, con la comparación
contra Eclipse Hub y OverDrive H, está en `docs/MM2-MENU-AUDIT.md`.

### Pruebas

- `test_disguise_defaults.py`: **14 comprobaciones**. Cambian los casos 9-12:
  un pack ya no entra en un cuerpo R6 aunque el objetivo sea R6, y el set R6
  tampoco entra en un cuerpo R15.
- `test_disguise_animation.py` (4), `test_disguise_character.py` (3),
  `test_disguise_toggles.py` (11): en verde.
- `bash tools/validate.sh` → **75 fuentes compilan, 47 suites en verde**,
  arranque completo con `failures=0`.

### Lo que esta versión NO afirma

- No hay prueba en el juego: la regla se apoya en la captura y en el
  comportamiento documentado del retargeting, no en una sesión nueva.
- En un cuerpo R6 con un pack comprado, la animación que se verá es la del
  **rig**, no la del pack. Es el precio de no volver a enseñar el muñeco
  hundido; si se prefiere lo contrario, hay que aceptar el riesgo.
- La auditoría no arregla nada por sí misma: enumera lo que falta y lo que
  está muerto. Los arreglos propuestos están al final del informe.

## v71 — fuera lo muerto, y los módulos nuevos hacen algo

Sello: `v71-20261019-menu-cleanup-coin-esp-and-real-modules`.

### Lo que se borró (y por qué)

| archivo | líneas | estado |
| --- | --- | --- |
| `src/games/MM2.luau` | 5.229 | fuera del bundle y del cargador; describía 17 tarjetas que ya no existen |
| `src/games/TRS.luau` | 1.923 | lo mismo: el cargador usa `TRS/base.lua` |
| `src/games/VD.luau` | 1.987 | ídem |
| `src/games/MVSD.luau` | 1.288 | ídem |
| `src/games/Universal.luau` | 75 | solo tipos, sin un solo lector |
| `Blatant/WallHop.lua` | — | compilaba, viajaba en el bundle, no se registraba |
| `Other/LagSwitch.lua` | — | ídem |
| `Other/RemoteLogger.lua` | — | ídem |

**10.502 líneas** de monolitos más los tres módulos huérfanos. El bundle pasa
de 73 a **71 archivos** (entra `CoinEsp`, salen cuatro fuentes).

La lista de módulos del `fallbackManifest` de `Wurst.lua` se generaba a mano y
ya no coincidía con `Manifest.lua`: un fallo de red podía arrancar un menú
distinto del probado. Ahora se escribe desde la misma lista y
`tools/test_manifest_sync.py` falla si vuelven a separarse, si el manifiesto
apunta a un archivo que no existe o si hay un módulo universal en disco sin
registrar.

### Lo que se registró

`Rejoin Server` estaba escrito, funcionaba y nunca se cargaba. Entra en el
manifiesto (33 módulos) como acción de Wurst Options, donde ya viven
`Reinject` y `Destruct`.

### Lo que estaba roto y se arregló

- **Gun ESP / Trap ESP.** Son toggles dentro de Item ESP y solo dibujan con la
  tarjeta encendida. Se podían dejar en ON sin efecto. Ahora
  `setProviderEnabled` enciende la tarjeta con su propio interruptor cuando la
  fila se pone en ON, y el ON siempre dibuja.
- **Calibration** (captura de trayectorias, TrailESP, guardar historial) ya no
  aparece en un arranque normal: solo con `WURST_DEBUG`. El grabador de
  `base.lua` sigue funcionando porque lo usa la predicción.

### Lo nuevo, con prueba

- **`src/games/MM2/Render/CoinEsp.lua`**: una tarjeta `Coin ESP` que resalta
  cada moneda del mapa y muestra la cuenta viva en el estado. Usa la carpeta
  `MM2Effects/CoinChams`, `coinColor` y `coinTransparency`, que estaban en
  `base.lua` sin un solo lector. Sigue las monedas que aparecen y las que se
  recogen, y al apagarse no deja ni un Highlight.
- **Lista de ignorados de Kill Aura**: nombres, nombres visibles o ids,
  separados por comas. Se aplica antes de rotar o golpear, así que un jugador
  de la lista no se elige nunca. Sin texto no filtra a nadie.

### Herramientas en la rama

Como el entorno borra `/home/user/.tools`, el toolchain queda versionado en
`tools/luau/`: el paquete `@luau-rs/luau@0.739` (2,7 MB) en `vendor/`,
`setup.sh` que lo descomprime sin red y sin npm, y los dos runners. `validate.sh`
lo instala solo si falta y prefiere `tools/luau/bin/*`. Un clon limpio pasa la
validación con solo tener `node`.

### Verificación

`tools/validate.sh` → **EXIT=0**: 73 fuentes Luau compilan, **52 suites**
(+5 nuevas), arranque completo `failures=0` y auditoría del menú con **36
tarjetas**.

Nuevas: `test_mm2_coin_esp.py` (tarjeta, un resaltado por moneda, conteo vivo,
alta/baja, color, apagado, mapa vacío, sin remotos, descarga),
`test_killaura_ignore.py` (nombres, display, ids, separadores, NPCs),
`test_item_provider_activation.py` (ON con tarjeta apagada la enciende; ON con
tarjeta encendida activa; OFF apaga) y `test_manifest_sync.py` (33 módulos, sin
huérfanos, fallback idéntico, 13 archivos MM2 listados).

### Lo que NO se agregó, y por qué

- **God mode**: el daño lo aplica el servidor. Escribir `Humanoid.Health` en el
  cliente lo pisa la siguiente réplica y no evita la muerte.
- **Kill all**: necesita un remoto de daño; en el tráfico capturado solo hay
  `Shoot`, `KnifeThrown` y `GunFired`, y el arma dispara un proyectil a un
  objetivo.
- **No-spread**: el spread lo decide el servidor al procesar el disparo.
- **Auto unbox**: son productos pagos; automatizar la compra gastaría Robux
  sin confirmación.

No se pone un módulo que no haga nada: es el código muerto que esta versión
acaba de sacar.
