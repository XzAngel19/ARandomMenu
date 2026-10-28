# v139.3 — Punto blanco: el cuerpo del asesino no es una pared

**Stamp:** `v139.3-20261028-pointblank-release-version`
**Base:** v139.2 (`260e8fb`)

La pregunta: *"¿Está bien que el wallcheck detecte el cuerpo del murderer y no
dispare? Si estoy demasiado cerca, la pistola casi dentro del cuerpo del asesino,
¿debería hacer wallcheck o estaría mal? Porque eso es lo que pasa."*

**Respuesta corta: no, no estaba bien — pero el cuerpo del asesino nunca fue el
que bloqueaba.** El objetivo está excluido de todos los rayos desde v106. Lo que
bloqueaba eran dos comprobaciones nuestras, y las dos están medidas y
reproducidas en `tools/test_gun_pointblank.py`.

## 1. Lo que se midió en la sesión v139.2 adjunta

53 minutos, `sessionId 34054AE9…`, 22 activaciones de pistola.

| Dato | Valor |
|---|---|
| Confirmados / intentos | 16 / 22 |
| Disparos que tocaron al asesino | 9 |
| Bajas | 8 |
| Fallos con motivo | 7 — **los 7 `geometry`** |
| Fallos `other-player` | **0** |
| Error del punto de mira (mediana) | **0,72 studs** |
| Error del *lead* (mediana) | **12 ms** |
| Eco del servidor (mediana) | 135 ms |
| Rechazos del cliente ("blocked") | 23, todos geometría del mapa, mediana 16,4 studs |

Por modo: **Normal** 18 intentos / 12 confirmados / 5 aciertos / 4 bajas (33 %).
**Silent** 4 / 4 / 4 / 4 (100 %, muestra pequeña).

Lectura: el *lead* está bien (12 ms de error mediano; no se toca). El punto de
mira está bien (0,72 studs). Ningún fallo fue a otro jugador: la corrección de
v139.2 funcionó. Lo que sí apareció es que **el cliente rechaza mucho**: 23
rechazos frente a 22 disparos reales.

## 2. Punto blanco: el asesino nunca bloquea, y aun así no disparaba

Reproducido en el harness con `fireGunAtTarget`, `buildSilentShot`,
`validateGunShot` y `describeRayBeyond` reales contra un `Raycast` de cajas:

| Distancia al asesino | Modo Normal | Modo Silent |
|---|---|---|
| 0,8 studs (cañón dentro del cuerpo) | dispara | dispara |
| 1,2 studs | dispara | dispara |
| 3 studs | dispara | dispara |

El cuerpo del objetivo está en `FilterDescendantsInstances` (Exclude) en las
cuatro pasadas de `validateGunShot` y en el sondeo del corredor. Punto blanco,
por sí solo, **no** era el motivo del rechazo. Los dos motivos reales:

### 2.1 `"Invalid shot geometry"` — el asesino venía corriendo hacia mí

La construcción Silent "Through" perfora **a lo largo del movimiento del
objetivo**. Si el asesino corre hacia ti a los 17 studs/s medidos, esa dirección
apunta hacia **ti**: el segmento autorizado acababa en el origen del disparo
(muzzle 0,5 · endpoint 0,5) y `validateGunShot` lo rechazaba por geometría.

**Arreglo:** dentro de `POINT_BLANK_STUDS = 6` el *lead* deja de ayudar (17
studs/s × 0,1 s = 1,7 studs > la distancia) y el cuerpo cubre toda la línea de
visión. A esa distancia:

- el punto de mira se fija en el `HumanoidRootPart` (sin lead), y
- el disparo se construye **desde el cañón real hasta ese punto**
  (`variant = "PointBlank"`), sin perforación ni barrido.

Si el punto predicho cae **detrás** del cañón (objetivo encima tuyo), también se
corrige: un segmento invertido no es geometría que el motor pueda resolver.

### 2.2 `"Another player blocks the silent shot"` — 200 studs y a través de paredes

En v139.2 subí un solo constante (`OVERSHOOT_PROBE_STUDS`) de 12 a 200 para el
sondeo del corredor. Esa constante la compartía `bystanderBlocks`, cuyo rayo está
filtrado **solo a personajes**: las paredes son transparentes para él. Resultado:
un inocente 108 studs detrás del asesino, **en otra habitación y detrás de una
pared**, bloqueaba *todos* los disparos Silent.

**Arreglo:** dos constantes con dos preguntas distintas.

| Constante | Valor | Para qué |
|---|---|---|
| `BODY_OVERSHOOT_STUDS` | 12 | cuánto sigue el rayo tras el punto autorizado (valor validado en v139.1) |
| `CORRIDOR_PROBE_STUDS` | 200 | cuánto mira el corredor detrás del punto de mira |

Y el sondeo de "cuerpo detrás" ahora usa `describeRayBeyond`, que **se detiene en
lo primero que encuentra**: si hay una pared, la pregunta termina ahí.

Además: un cuerpo **sin dueño y con salud 0** (un cadáver de MM2 en el suelo) ya
no cuenta como inocente. Antes, cualquier rig con Humanoid bloqueaba el tiro.

## 3. Lo que NO se tocó

- El *lead* (ni el de la pistola ni el del cuchillo): 12 ms de error mediano.
- `INNOCENT_DANGER_STUDS = 35`: un inocente **de verdad** a menos de 35 studs
  detrás sigue haciendo que el disparo se salte. Es la decisión que evita que te
  quiten la pistola por matar a un inocente; ahora, además, **se registra**.
- La comprobación de pared real entre el cañón y el asesino: sigue rechazando.

## 4. Telemetría nueva

Los rechazos del corredor se registran como evento `gun/blocked` con
`reason = "corridor"` (antes todos eran `"wall"`). Así la próxima sesión puede
responder *"¿cuántos disparos me costó esta política?"* con un número, no con una
impresión.

## 5. Cuchillo — lo que dice el nuevo medidor

`closestApproachStuds` ya mide. De 6 cuchillos observados:

| Aproximación mínima | ¿Pasó por el cuerpo? |
|---|---|
| 0,28 studs | sí |
| 0,71 studs | sí |
| 7,59 studs | no |
| 12,83 studs | no |
| 19,08 studs | no |
| (sin datos) | no |

Y el retraso observado entre la activación y el proyectil
(`knifeSpawnDelayMs`, histórico + sesión: 15 muestras) da **mín 33 · media 861 ·
máx 1839 ms**. Un cuchillo a 96 studs/s contra un objetivo a 17 studs/s con casi
un segundo de retraso explica perfectamente 7–19 studs de error. **No se cambia
el lead del cuchillo con 5 medidas**: la próxima sesión lo confirma o lo descarta.

## 6. Verificación

`bash tools/validate.sh` → verde: 91 fuentes, **71 suites**, boot `failures=0`,
52/51 tarjetas.

Suite nueva: `tools/test_gun_pointblank.py` — 25 comprobaciones sobre el código
real: punto blanco 0,8/1,2/3/6 studs en Normal y Silent; asesino embistiendo a 17
studs/s desde 1,5/3/5; asesino contra una pared; inocente a 108 studs detrás con
y sin pared; cadáver detrás; inocente a 13 studs detrás (se rechaza, con
`reason = "corridor"`); pared real entre los dos (se rechaza).
