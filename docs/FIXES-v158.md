# v158 — Knife: openings estratégicos, no enemigos detrás de pared ni cadáveres

Fecha: 2026-10-29 · Stamp: `v158-20261029-mm2-knife-openings`

## Lo que reportó el usuario

> «Mira el Knife. Este nuevo cosa que implementaste funciona horriblemente,
> Apunta a donde estan los enemigos detras de la pared y tambien apunta a
> enemigos muertos ya en el piso, prediciendoles. En vez de apuntar en openings
> estrategicos.»

La captura adjunta (`MM2_Trajectory_Calibration-3.json`) es una sesión v157
(`221E2F3D-60E4-46AB-9973-B65B6A6411DF`, guardada 2026-10-29T21:59:33Z,
`wallCheck=true`, `silentAim=false`) con 12 intentos Gun (10 confirmados, 7
bajas), 2 lanzamientos Knife registrados y confirmados como proyectil, 5 stabs
y 10 activaciones nativas. No contiene marcas de «pared» ni de «cadáver» por
evento, así que la captura **no mide** el defecto; lo que se corrige es el
algoritmo que lo producía.

## Causa

`resolveSpeculativeAim` (Knife Throw) se usaba siempre que `findTarget()`
devolvía `nil`, es decir, justo cuando el rival está tapado o no hay nadie
visible. El código v157 hacía esto:

1. Elegía al jugador elegible **más cercano** y usaba su
   `HumanoidRootPart.Position` como centro (`centre = hidden.Position`).
2. Recorría radios 4/9/16 studs alrededor de ese cuerpo y lanzaba el cuchillo
   al primer punto con suelo y rayo despejado.

Resultado: con WallCheck encendido el redirect nativo (y Auto Knife Throw)
apuntaba a un punto «cerca del enemigo» que el jugador no puede ver, y si el
elegible era un ragdoll, el mismo cálculo predecía un cuerpo inmóvil en el
piso. La intención original («carril visible cercano al rival oculto») se
convirtió en apuntar a través de la geometría.

Segundo defecto: «estar vivo» era solo `Humanoid.Health > 0`. MM2 deja el
cuerpo en el workspace después de la kill y el cliente puede leer `Health > 0`
mientras el `Humanoid` ya está en `Dead`/`Physics`; el predictor entonces
seguía calculando adelanto para un cadáver.

## Cambios

### `src/games/MM2/Combat/KnifeThrow.lua` — carriles de apertura

La especulación ya **no lee ninguna posición de jugador**. Es una decisión de
mapa:

- Dirección base: `Camera.CFrame.LookVector` aplanado (o el `LookVector` del
  personaje si no hay cámara).
- 16 rumbos cada 22,5°. Para cada uno se lanza un rayo desde la mano +1,2
  studs (`eye`) hasta 140 studs; la distancia libre es la del impacto menos 1,5.
- Si la dirección libre es menor que 16 studs (pared en la cara) se descarta.
- Punto de aterrizaje: se prueba de lejos a cerca `{140, 80, 45, 26, 16}` y se
  toma el primero con suelo (`Normal.Y >= 0.55`), altura compatible con el
  suelo propio (±14 studs), hueco de 8 studs y línea despejada desde la mano.
  Así el borde de un mapa no produce un punto en el vacío.
- Puntuación: `facing * 40 + min(distancia, 60) * 0,5 + ancho * 8`, donde
  `facing = direction:Dot(forward)` y `ancho` cuenta los dos laterales libres a
  6 studs en la boca del carril (ancho de puerta, no de la sala).
  Mirar hacia la apertura manda: una puerta al frente gana a un trozo de piso
  más amplio a la espalda.
- Se ignoran todos los personajes en los rayos (el rival puede estar en el
  carril: eso sería impacto, no pared; un cadáver no desplaza la apertura).
- Se mantienen: caché de 0,4 s con revalidación del rayo, rotación de
  desempate entre envíos, guardas de ronda/Murderer/protegido, Delay y equip.

Status: `Opening lane · no visible target`.

### `src/games/MM2/base.lua` — `isPlayerAlive` rechaza ragdolls

Además de `Health > 0`, ahora devuelve `false` si el `Humanoid` está en
`Dead`/`Physics` o si el atributo `Dead` del modelo es `true`. Lo consumen
Knife Throw, Knife Aura, Shoot, Auto Shoot, Auto Win y Auto Farm por igual, así
que el filtro es uno solo.

### `src/games/MM2/Prediction.lua` — cuerpo antes de predecir

- `bodyIsAlive(humanoid)`: salud, estado `Dead`/`Physics` y atributo `Dead` en
  el `Humanoid` o en su padre.
- `refreshTrackParts` y `samplePlayer` descartan la pista en cuanto el cuerpo
  deja de estar vivo, en vez de esperar 0,5 s al refresco de partes.
- `knifeAim` y `gunAim` comprueban el cuerpo del objetivo al entrar y devuelven
  `nil, nil, "dead target"`.

## Pruebas

- `tools/test_mm2_knife_openings.py` (nueva): mapa analítico de cajas
  alineadas a ejes (suelo, pared con puerta, pared lateral, sala sellada,
  borde de mapa). Comprueba:
  - puerta al frente con rival oculto al lado → el carril pasa por la puerta y
    queda a más de 10 studs del rival;
  - el mismo rival visible por la puerta → vuelve a ser objetivo;
  - puerta tapiada → se elige la apertura lateral y no la pared;
  - cadáver en el piso → nunca `findTarget`, nunca el punto de mira, y el
    lanzamiento sale igual;
  - `Health 0`, `Dead`, `Physics` y atributo `Dead` → rechazados; cuerpo vivo →
    vuelve a ser objetivo;
  - sala sellada sin apertura → no se envía nada;
  - borde de suelo → el punto queda sobre el piso, no en el vacío;
  - `base.lua` y el predictor aplican la misma regla de cadáver.
- `tools/test_mm2_knife_equip.py` (actualizada): el caso «objetivo oculto»
  ahora exige que el carril **no** esté construido alrededor del rival
  (`> 30` studs), al revés que en v157.
- `tools/test_mm2_precision.py` (ampliada): `knifeAim`/`gunAim` fallan con
  `"dead target"` ante salud 0, `Dead` y `Physics`, y vuelven a apuntar al
  cuerpo vivo.

## Límites

- Todo esto es geometría y contrato de cliente con mocks deterministas. No
  prueba Volt, el servidor, daño, hit-rate, ni comportamiento anticheat.
- `WeaponService` sigue hookeado; la captura no demuestra que Volt comparta esa
  tabla con el juego, ni que un lanzamiento manual haya pasado por el hook.
- El puntaje de apertura (40/0,5/8, radio 140, tolerancias) es una heurística
  razonable, no calibrada con datos de mapa real. El mapa real de MM2 puede
  ofrecer corredores largos donde un carril de 80 studs sea mejor que uno de
  45; no hay medición que lo confirme.
- `Humanoid:GetState()` y el atributo `Dead` son señales del cliente: si MM2
  retira el cuerpo sin replicar ninguno de los dos, el filtro vuelve a depender
  de `Health`.
