# v139.2 — ¿Shoot y Auto Throw son lo mejor posible? Medido contra el personaje

**Stamp:** `v139.2-20261027-corridor-release-version`
**Base:** v139.1 (`42c4fef`)

La pregunta del usuario fue literal: *"¿crees que el código de Shoot y AutoThrow
son los mejores? Determínalo estudiando el personaje de Roblox, su movimiento,
sus físicas"*. Esto es la respuesta en forma de evidencia, no de opinión: qué
hace bien el código actual, qué estaba mal y qué se cambió.

## 1. Qué es un personaje de MM2, en números medidos

De la telemetría de v139.1 (`MM2_Trajectory_Calibration.json`, 828 muestras):

| Magnitud | Mediana | p90 | Máx |
|---|---|---|---|
| Velocidad horizontal | 16,8 studs/s | 17,3 | 24,2 |
| `moveDirection` < 0,08 (giro brusco) | 67 / 828 muestras | — | — |
| Aceleración replicada | 17 studs/s² | 149 | 1196 |

Léelo así: el personaje **no** es una partícula balística, es un objeto con
voluntad. La mayor parte del tiempo va a velocidad casi constante (~17 studs/s)
y de golpe gira en 1–2 frames (`moveDirection` se va a casi cero en el 8 % de las
muestras) o cambia de dirección con aceleraciones de cientos de studs/s². Por eso
la predicción lineal acierta cuando el objetivo corre en línea recta y falla
siempre en el giro. Los dos módulos ya asumen esto; lo que cambia en v139.2 es
**qué se hace con el error que queda**.

## 2. Shoot (pistola): el error no se puede eliminar, se puede desviar

**Lo que ya estaba bien y no se tocó:** el *lead*. El horizonte (eco
FireServer→GunFired + 25 ms de interpolación, cap 0,6 s) está confirmado y
**no se re-calibró**. La pistola es *hitscan*: no hay caída ni tiempo de vuelo,
sólo latencia. Con 0,1 s de lead y 17 studs/s el desplazamiento que hay que
adelantar es **1,7 studs**; con giro brusco, el error residual típico queda en
1–2 studs. Eso es irreducible sin leer el input del otro jugador.

**El fallo real (v139.1):** 10 disparos confirmados → 4 al asesino, 3 se
paraban en geometría del mapa y **2 acabaron en el `HumanoidRootPart` de OTRO
jugador**. El rayo del servidor no termina donde termina nuestro endpoint: es
una línea larga. Un error de 1 stud no se pierde, **entra en el cuerpo que esté
detrás**. Con el sondeo de 12 studs que había antes ni siquiera se miraba tan
lejos.

**El arreglo (v139.2):** se elige el punto de mira por lo que hay **detrás** de
él, no sólo delante.

```lua
OVERSHOOT_PROBE_STUDS  = 200   -- antes 12: el alcance real del rayo
INNOCENT_DANGER_STUDS  = 35    -- cuerpo vivo a menos de esto = peligro
```

`corridorSafePoint(target, info, origin, preferred) -> (Vector3, bool, string)`
prueba primero el punto que dio el predictor y, si tiene un cuerpo vivo cerca
detrás, prueba `UpperTorso, Torso, HumanoidRootPart, Head`, brazos y piernas
(aplicando el **mismo** vector de lead a cada uno, para que los candidatos
cambien *a dónde apunta el rayo*, no cuánto se adelanta). Devuelve:

- el primer punto cuya línea no tiene ningún cuerpo vivo en 35 studs → dispara;
- si todos están tapados, el de mayor hueco y `false` → **no dispara**, con el
  motivo *"An innocent is right behind the murderer."* (MM2 le quita la pistola
  al sheriff que mata a un inocente: fallar el disparo es más barato que eso).

Un muro detrás **no** es un problema: el rayo muere en el muro. Sólo cuenta un
jugador. El dueño del cuerpo se identifica con
`Players:GetPlayerFromCharacter` subiendo por los ancestros (pcall), nunca por
comparación de referencias.

Opción nueva y apagable: **Avoid innocents** (`Avoid`…, por defecto ON). Al
apagarla, el comportamiento es el de v139.1 exactamente.

## 3. Auto Throw (cuchillo): dos fallos distintos, no uno

**Física:** el cuchillo sale a ~**96 studs/s** (`ThrowSpeed` del tool, clamped
24–300) contra los 16,8 studs/s medidos del objetivo. A 30 studs el vuelo dura
**0,31 s** y el objetivo recorre **5,2 studs** en ese tiempo: el lead del
cuchillo es 3× más importante que el de la pistola y ya estaba bien calculado.
No se tocó.

**Fallo 1 — se lanzaba desde la mochila.** `EquipTool` es un viaje de ida y
vuelta al servidor; `FireServer` del cuchillo no. La v139.1 lanzaba el remote en
el mismo frame en que pedía equipar, así que el cuchillo salía desde el
`RightHand` de respaldo, no desde el mango: **9 cuchillos observados de 13
activaciones, y los 4 que desaparecieron salieron todos del origen de respaldo**.
Ahora `throwKnife` devuelve `false` hasta que el tool está colgado del
personaje (`ensureEquipped`), y no re-pide el equip cada frame.

**Fallo 2 — el bucle resolvía la puntería cada frame.** `findTarget()` recorre
todos los jugadores y `resolveKnifeAim()` hace un raycast de línea de vista por
jugador; con 10 personas eso son decenas de raycasts por frame para un número
que cambia 3–4 veces por segundo. Ahora el objetivo se cachea **1/15 s**
(`AIM_CACHE_SECONDS`). El *disparo* no usa la caché: `throwKnife` vuelve a
resolver la puntería desde el mango real, así que la dirección siempre es la de
ahora. Medido en `tools/test_mm2_knife_equip.py`: **13 resoluciones por segundo
a 60 FPS** (antes 61) y los mismos 4 lanzamientos en 2 s con `Delay` 0,6.

## 4. Telemetría nueva: para que la próxima sesión se puntúe, no se discuta

- Cuchillo, evento `projectile-observed`:
  `closestApproachStuds`, `closestApproachAtMs`, `bodyRadiusStuds` (mitad de la
  dimensión mayor del torso) y `passedThroughBody` (mínimo ≤ radio del cuerpo).
  Un cuchillo con velocidad válida y **6 studs de aproximación mínima es un
  fallo medido**, no un "lanzamiento confirmado".
- Pistola: `missReason` en el evento del disparo — `hit` / `other-player` /
  `geometry` / `no-hit-part`, derivado del dueño de la parte golpeada. El
  resumen de sesión gana `gunMisses` y `gunMissReasons` (`{[motivo]: cuenta}`).
- El cuchillo se sigue midiendo con el `HumanoidRootPart` **leído en cada
  frame** (un jugador puede morir o salir a mitad de vuelo; cachear la parte
  falsea la medida).

## 5. Qué NO se tocó

- El lead (ni el de la pistola ni el del cuchillo). Ya está medido; moverlo sin
  una sesión de calibración nueva es el error que costó las sagas v103→v105.
- Los presets de disparo (Silent/Front/Through/Prediction) y sus orígenes.
- Nada de MM2 fuera de `Shoot.lua`, `base.lua` y `Combat/KnifeThrow.lua`.

## 6. Verificación

`bash tools/validate.sh` → verde: **91 fuentes**, **69 suites**, boot
`failures=0`, 52/51 tarjetas.

Suites nuevas:

- `tools/test_gun_corridor.py` — corre `describeRayBeyond` y `fireGunAtTarget`
  reales con un `workspace:Raycast` de cajas: línea limpia (no mueve la mira),
  cuerpo a 20 studs detrás (mueve y sigue apuntando al cuerpo), cuerpo pegado
  (rechaza el disparo), cuerpo 150 studs más allá (no toca la mira), opción OFF
  (dispara siempre).
- `tools/test_mm2_knife_equip.py` — mochila: equipa y **no** dispara; mismo
  frame: no re-equipa ni dispara; tool en el personaje: dispara una vez; ya
  equipado: dispara al instante. Y el presupuesto de frames del bucle.
