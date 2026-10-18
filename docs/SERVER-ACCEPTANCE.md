# Aceptación del servidor de MM2: qué se puede demostrar

Este documento responde a la afirmación «el servidor acepta como máximo 200 ms
(200,33 ms)». Se contrasta con el código de cliente incluido en la copia del
place y con los registros guardados en `TestingStuff`.

## Lo que sí está en el código del cliente

`ClientServices.WeaponService` (`research/rbxlx/092_WeaponService_ModuleScript.lua`):

- Filtro de rayos: excluye el personaje local y todo lo etiquetado
  `WeaponPassthrough`; si el impacto tiene `Transparency == 1`, lo añade a la
  exclusión y repite el raycast.
- `GetTargetPosition` / `GetMouseTargetCFrame`: raycast desde la cámara de
  **300 studs**; con `MouseLock` activo y sin gamepad, el rayo se centra en el
  viewport.
- `ThrowKnife` solo dispara un `BindableEvent` local.
- `GunFired` es un `RemoteEvent` que el servidor reenvía a los clientes;
  `GunBeams` lo dibuja. El `hitPart` que llega en ese evento lo calcula el
  servidor, así que el eco `FireServer → GunFired` sí es evidencia del lado
  servidor.

No hay ninguna comprobación temporal, de distancia ni de «ventana de
aceptación» en este módulo. Es lógica de cliente, no validación del servidor.

`ThrowingKnifeVisuals` (`research/rbxlx/223_...`):

- El cuchillo avanza en línea recta: `CFrame + Direction * ThrowSpeed * dt`,
  `ThrowSpeed` por defecto **96**, sin gravedad y sin tiempo de vida.
- Por eso el alcance del cuchillo no está limitado por el cliente.

El servidor de MM2 no está incluido en la copia del place (no hay scripts de
servidor ni manejadores `OnServerEvent` entre los 229 scripts extraídos). Por
tanto **no se puede leer el umbral exacto** desde este repositorio.

## Lo que dicen los registros

`TestingStuff/Place_142823291_Game_Learning.json` (93 tiros; 29 confirmaciones
`GunFired`, 7 con impacto en un jugador). Para los 18 tiros con eco medido y
resultado, ordenados por eco:

| Eco (ms) | ¿Impacto en el objetivo? |
|---|---|
| 128.3 | no |
| 163.8 | no |
| 164.1 | no |
| 166.7 | no |
| 183.5 | no |
| 185.3 | sí |
| 187.1 | sí |
| 197.6 | no |
| 204.4 | no |
| 204.8 | sí |
| 210.4 | no |
| 211.5 | sí |
| 228.6 | sí |
| 255.2 | sí |
| 259.2 | sí |
| 359.3 | no |
| 679.2 | no |
| 1007.7 | no |

## Qué se puede puntuar con la telemetría

- **El disparo tomado**: `targetTrajectory` (hasta 120 puntos a 30 Hz desde el
  instante del disparo) + `endpoint` + `hitTarget` permiten medir el error del
  endpoint contra la posición real del objetivo.
- **Un predictor alternativo**: desde v61 cada disparo lleva `targetHistory`,
  la ventana de 0.6 s *anterior* al disparo (36 muestras como máximo, `dt`
  negativo). Con eso se puede re-correr otro predictor desde los mismos inputs.
- Lo que sigue sin existir es una etiqueta de impacto del servidor: `hitTarget`
  sale del `GunFired` que ve el cliente, no de daño confirmado.

## La «ventana dinámica» del 16 de octubre

`TestingStuff/MM2_Trajectory_Calibration.json` (stamp `v35-20261016-menu-motion`,
sesión con ping ~108 ms) guarda el estimador que usó el otro agente:

| Métrica | Valor |
|---|---|
| `confirmedShots` | 297 |
| `gunAcceptanceMs` mínimo | 3,73 ms |
| `gunAcceptanceMs` media | **123,51 ms** |
| `gunAcceptanceMs` máximo | **631,12 ms** |

Ese 123,5 ms es la **media** de una distribución con cola larga, no un umbral:
el propio registro contiene aceptaciones de 3,73 ms y de 631 ms. La media es
~15 ms mayor que el ping de esa sesión, así que la regla «ventana ≈ RTT + 10–20
ms» describe bien el centro de la distribución, pero **no es un corte**:
usar 123 ms como límite habría rechazado disparos que el servidor sí aceptó.

Es exactamente lo que ya hace el mod: la mediana de ecos medidos (con respaldo
del ping) es la «ventana» en vivo, sin constante mágica. La diferencia es que
nosotros usamos la mediana y no la media, y no descartamos por encima de un
número fijo.

Ojo con mezclar archivos: en `Place_142823291_Game_Learning.json` (14 oct) los
**297** son `hitboxAnomalies` y solo hay **29** `confirmations`; los 297
disparos confirmados y el 123,5 ms salen del archivo de calibración v35.

## Veredicto

La afirmación tal como suena —un corte duro de aceptación a 200 ms— **no queda
en pie como está formulada**, pero tampoco se puede declarar falsa sin matices:

1. **Si «200 ms» se refiere al eco `FireServer → GunFired`** (lo que cualquiera
   puede medir desde el cliente), está refutado: hay ecos de 679 y 1007 ms, y
   hubo impactos confirmados con 259,2 ms de eco. Ese número no es un umbral.
2. **Si «200 ms» se refiere a la edad del disparo al llegar al servidor**, los
   registros son compatibles con ello y no lo demuestran: con un ping de sesión
   de ~171 ms, un eco de 259 ms deja el disparo en el servidor a ~85 ms de
   haberse enviado. El eco no mide la edad de llegada.
3. **No hay fuente en el place** que fije 200,33 ms. Sin el código del servidor,
   no se puede confirmar ese número concreto; solo se puede desmentir que el eco
   tenga ese tope.

Consecuencia práctica: el mod **no construye nada sobre un umbral de 200 ms**.
El horizonte de predicción sale del eco medido y del ping real (tope de 1 s,
0,6 s para el lead automático) y el WallCheck no cambia según la latencia. Si en el futuro apareciera un
límite real, el diseño ya apunta al lado conservador (se apunta al futuro, no
al pasado), pero no se afirma que exista.

## Giro y frenado: medidos, no supuestos

El corredor recto falla en dos casos medibles: el objetivo dobla y el objetivo
frena. En vez de inventar constantes de "giro" o "violencia", el predictor hace
**dos ajustes ponderados separados 0,10 s** sobre las posiciones replicadas:

- La dirección de cada ajuste da una velocidad angular firmada
  `atan2(cross, dot) / dt`, limitada a ±10 rad/s y puesta a cero por debajo de
  ~23 °/s (ahí solo hay ruido de replicación).
- La diferencia de magnitudes a lo largo de la marcha da la aceleración
  longitudinal, limitada a ±120 studs/s².
- El lead rota `ω · (h/2 + retraso del ajuste)` y se recorta a **45°**: más que
  eso ya no lo describen las muestras.
- Si la aceleración indica frenada (≤ −6 studs/s²) y el horizonte supera el
  tiempo de parada `v/|a|`, el largo se recorta a media distancia de frenado.
- La velocidad usada es la del ajuste corregida por el retraso (`v + a·lag`),
  porque un ajuste es una cuerda y se queda corto al acelerar.

En recta ambos términos quedan exactamente en cero: no hay corrección
"mágica". El cuchillo re-resuelve el intercepto una vez con la velocidad media
del vuelo completo (cuerda + frenado), no con la tangente. La única gravedad
que entra es la **del objetivo en el aire**; la hoja se modela recta hasta el
endpoint, igual que `ThrowingKnifeVisuals`. Si el proyectil del servidor
tuviera caída propia, habría que subir el endpoint; eso no está medido y no se
afirma.

## Qué significa el número (y qué no)

- El lead **no** es un filtro: no acepta ni rechaza disparos. Es la línea de
  mira (el punto del corredor de la ventana al que se apunta). Lo que rechaza
  un disparo es la frescura de la muestra, el WallCheck y el arma; el cooldown
  es del juego/modo, no del valor del lead.
- Por eso «usar 123,5 ms como corte» era una frase mala: el riesgo de usar la
  media de por vida no es rechazar disparos, es **apuntar mal**.
- El mínimo y el máximo de aceptación **no** son la tolerancia por disparo:
  son ruido de emparejamiento del eco. 3,73 ms es físicamente imposible con
  ping ~108 ms y 631 ms es un eco tardío.
- El **tope de 1 s** (ahora 0,6 s para el lead automático) es del **lead**;
  el emparejamiento de ecos tiene su propio rango (50–1600 ms). Son dos
  límites distintos y no se deben confundir.
- Ecos: se exige una mediana de **6 muestras frescas**; si no, se usa el ping
  suavizado. Un eco aislado de 3 ms nunca mueve el lead.
- El límite superior de 1600 ms no acepta cruces: `base.lua` solo entrega un
  eco cuando coinciden arma, origen (±3,5 studs) y dirección (dot ≥0,965) del
  disparo pendiente, y abandona la cola a los 1,6 s. En v18 hay un eco
  emparejado de 1007,7 ms con ping de 270,3 ms (y otro de 679,2 ms con ping
  400,1); un corte de 800 ms los descartaba. La mediana y el tope de 0,6 s
  absorben un pico aislado.

## Lo que sí conviene explotar

1. **`WeaponPassthrough`.** Ciertas partes del mapa dejan pasar el disparo. El
   WallCheck las excluye igual que el juego, tanto para el arma como para el
   cuchillo, así que disparar o lanzar a través de ellas es legítimo.
2. **Rayo de puntería de 300 studs.** Es el límite del *aim* del cliente, no del
   daño; el WallCheck propio no impone distancia al disparo.
3. **Cuchillo sin caída y sin límite de vida.** El blade sigue recto hasta
   impactar; el límite útil lo pone la geometría, no la velocidad.
4. **Ping alto no impide acertar.** La sesión registrada tenía ping mediano
   ~171 ms y máximos de 507 ms, y aun así hubo impactos: por eso el lead
   automático usa el eco real en vez de un valor fijo.

## La sesión del 18-10: qué la explica y qué no

Archivo: `TestingStuff/MM2_Trajectory_Calibration.json` (sello
`v61-20261017-pre-shot-history`), 285,2 s, modo `Normal` en los 13 disparos.

- **13 autorados · 9 confirmados (`GunFired`) · 1 con `hitPart` del objetivo.**
  Los otros 4 no recibieron señal del servidor y no se cuentan como fallo de
  puntería.
- **5 de los 9 confirmados (1, 2, 4, 7, 11) terminaron 24–56 studs antes del
  punto apuntado**, con el WallCheck del cliente en verde. El error del modelo
  en esos disparos es 0.1–2.9 studs: la puntería no era el problema; el rayo
  murió antes. Los disparos 1 y 2 acaban en el **mismo plano**
  `z = 9017.9736`, que es una pared, no ruido.
- **2 de los 9 (8 y 10)** usaron un `rtt` de 0.314/0.342 s contra 0.104–0.108
  del resto. El horizonte salió 0.36–0.40 s y el error horizontal 2.3 y 9.3
  studs. Un pico de ping, no un cambio de modelo.
- **Los 2 restantes (6, 13)** dependían del modelo: 6 llevaba el error vertical
  del vértice de salto (−2.29 studs) y el 13 acertó con 1.9 studs de error
  horizontal gracias al hitbox.

Conclusión honesta: **el 1/9 no es «el predictor no sirve» ni «todo es el
lead»**. Es una parte de geometría del mapa (5), una parte de un pico de red
(2) y una parte de modelo (2). v62 ataca las tres: rechaza y **registra** el
bloqueador invisible, filtra el pico con mediana y corrige el vértice, el giro
por ruido y el alargue por aceleración.

La pregunta que este archivo **no** puede responder todavía es si el horizonte
correcto es el RTT completo o media ida: el ancla `referencePoint` está
desfasada ~1 stud de la primera muestra de `targetTrajectory` (hasta 1.12
studs), que es el mismo tamaño que la diferencia entre ambos modelos. Por eso
no se cambia el horizonte y se sigue midiendo (`echoSamples`, `turnRate`,
`brakeSeconds` y los eventos `blocked` van ahora en cada disparo).

## Corrección (v63): el ping que se usaba no era el ida y vuelta

La sesión del 18-10 con sello v62 permite comparar por primera vez las dos
lecturas del motor contra el eco medido (activación → `GunFired`) en el mismo
disparo, y con la sesión v61 completa: **17 disparos**.

- `Data Ping` (Stats) queda a menos de 30 ms del eco en **12 de 17**.
- `GetNetworkPing` queda a menos de 30 ms en **3 de 17**. Es sistemáticamente
  50–90 ms más bajo en la sesión v61 y da los dos «picos» de 314/342 ms cuyos
  ecos reales fueron 152/164.
- Dos disparos de v61 que se habían atribuido a un pico de red no lo eran: el
  pico estaba en la lectura del motor, no en el camino.

Por eso el lead usa ahora **el menor de los dos**, y `rttEngine`/`rttData`
quedan grabados por disparo. Este archivo ya no sostiene la frase «el ping
mediano era ~171 ms» como si fuera el tiempo que tarda el disparo en llegar:
eso era `Data Ping`, y se confundía con `GetNetworkPing`.

Lo que sigue sin poder decidirse con estos archivos es si el horizonte correcto
es el ida y vuelta completo o la mitad. El barrido de horizonte favorece leads
más cortos, pero ese barrido está confundido por el error de dirección (en un
objetivo recto el error es plano en `h`), así que no se usa como prueba. La
próxima sesión graba las dos lecturas y el eco por disparo para poder separarlo.

## Qué agrega v64 a este archivo

v63 dejó dos cosas sin poder decidirse: el **ida y vuelta real** por disparo y
el **horizonte** (¿el viaje completo o la mitad?). Las dos dependían de cosas
que el archivo no guardaba. v64 las guarda, y además deja escrito el daño.

- **El ida y vuelta ya no se deduce.** `serverActivatedAt` y
  `serverConfirmedAt` se sellan al activar y al llegar la señal de `GunFired`,
  con el reloj del servidor en los dos extremos, y `serverEchoMs` sale de ahí.
  El sello anterior era la hora de finalización: por eso daba el viaje más
  500 ms y no servía. Con esto, la comparación `serverEchoMs` contra
  `rttEngineAtConfirmation` y `rttDataAtConfirmation` se hace en el mismo
  disparo, sin reconstruir nada.
- **El horizonte sí se puede separar del error de dirección.** La trayectoria de
  cada disparo se muestrea a 60 Hz con la hora del servidor por punto, así que
  se puede preguntar dónde estaba el objetivo en el instante de llegada y no
  solo en el de disparo. La trayectoria corta de los disparos 18, 20 y 186 ya
  tiene explicación escrita: el objetivo murió y el muestreador deja de tomar
  puntos con `Health <= 0`; el archivo lo dice en `samplingStoppedReason`.
- **El daño es un hecho, no una inferencia.** `hitPart` dice que el rayo tocó
  al personaje; `healthAfter`, `healthDropServerTime`, `died` y
  `diedServerTime` dicen si el servidor aplicó daño y cuándo. Un disparo con
  `hitTarget` y sin caída de salud es un toque sin daño, y eso se puede ver.
- **La geometría queda registrada también cuando el disparo sale.** `occluder`
  guarda lo primero que encuentra el rayo sin el filtro del juego (nombre,
  distancia, transparencia, `CanCollide`) en los disparos permitidos, no solo
  en los rechazados. Si un disparo "limpio" termina lejos del objetivo, el
  archivo dice contra qué.

Con el sello `v64-20261018-definitive-capture`, una sesión alcanza para cerrar
las tres preguntas de arriba. No se pide otra calibración hasta haber leído
ese archivo.

## Corrección (v65): el ida y vuelta ya está medido, y el eco ya tiene una fuente

Las dos sesiones con sello v64 (13 disparos confirmados) permiten por primera
vez comparar el ida y vuelta medido con **el reloj del servidor en los dos
extremos** contra el `latencyMs` del cliente: coinciden dentro de 9 ms en 13 de
13. El viaje real de esas sesiones fue **126–472 ms**, y la lectura del motor
que alimentaba el lead era **80–154 ms** — entre 1.15 y 4.7 veces menos.

Eso no se traduce en "el lead debe ser el doble": el punto de mira quedó dentro
del ancho del cuerpo en aciertos y fallos por igual (0.17–4.63 studs en los
aciertos, 0.27–3.82 en los fallos de la sesión corta), así que el error de lead
ya no separa el resultado. Lo que queda es qué parte del cuerpo corta el rayo.

Lo que sí quedó corregido es el caso en que el lead se disparaba por un eco
contaminado: en los disparos 9 y 10 de la sesión larga la mediana leía 318 y
303 ms contra 150 y 161 medidos, y el lead de 381/379 ms produjo los dos
mayores errores de puntería del archivo (3.90 y 6.15 studs). La causa era una
segunda fuente de eco; queda una sola, la que está verificada contra el reloj
del servidor. `MIN_ECHO_SAMPLES` baja de 6 a 3 por la misma razón.

Con esto, el archivo de una sesión responde: cuánto tardó el disparo de verdad
(`serverEchoMs`), qué tocó (`hitPart`, posición, tamaño), si hubo daño
(`healthAtAim` / `healthAfter` / `died` / `diedServerTime`), dónde estaba el
objetivo al llegar la señal (`rootAtConfirmation`) y con qué offset se apuntó
(`aimOffsetAtFire`).
