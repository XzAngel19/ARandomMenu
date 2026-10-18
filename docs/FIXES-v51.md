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

### Ecos y horizonte

- La mediana de ecos exige **6 muestras** (antes 2). Con menos, el lead usa el
  ping suavizado.
- Se descartan los ecos fuera de **50–800 ms**: por debajo es un emparejamiento
  imposible; por encima es un eco tardío o cruzado. El rango es más ancho que
  el [60,250] de la sesión de 108 ms porque este usuario juega con RTT de
  150–500 ms.
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
