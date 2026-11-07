# v189 — Ghost reescrito: dejó de trabarse, de volar y de teletransportar

Fecha: 2026-11-07. Stamp: `v189-20261107-ghost-rewrite`.
Rama: `arena/05c45e27-arandommenu` (base v188 `5605cae`).

## Reporte del jugador

> «No funciona Ghost para nada, se traba demasiado … hace que mi personaje vuele
> hacia arriba o se teletransporte de manera rara estando abajo.»

Los tres síntomas eran reales y cada uno tenía una causa única en v188.

## Causa raíz

### 1. Se trababa: una escritura por frame en un cuerpo vivo

v188 hacía, en `PreSimulation` y **cada frame**:

```lua
root.CFrame = CFrame.new(...)                      -- cuerpo real, vivo
root.AssemblyLinearVelocity = Vector3.zero         -- y además lo frenaba
```

El cuerpo real seguía **no anclado, con colisiones**, y a profundidad 1-5 quedaba
dentro del piso. La física de Roblox empujaba hacia arriba mientras el script
lo empujaba hacia abajo: forcejeo → micro-teleportes, y cada escritura se
replica a todos los clientes → tirones. A eso se sumaba que el clon se
superponía con el cuerpo real, también colisionable.

### 2. Volaba hacia arriba

Los dos rigs colisionables (cuerpo real y clon) spawneaban **en el mismo
CFrame**. Roblox resuelve la interpenetración aplicando impulso a lo que
considera penetrante: el clon salía disparado hacia arriba.

### 3. Se teletransportaba estando abajo

Consecuencia de (1): la corrección de profundidad se aplicaba en cada frame
sobre un cuerpo que la física movía en paralelo, así que la posición visible
saltaba entre el valor del script y el de la simulación.

### 4. Ghost Fly no hacía nada (y explicaba el resto del movimiento raro)

`applyMode()` ponía `Anchored = true` en el root del clon y `applyFly` le
asignaba `AssemblyLinearVelocity`. **Una parte anclada ignora la velocidad.**
Fly era inerte: el clon quedaba clavado y sólo el cuerpo real seguía moviéndose
por el script, que es exactamente lo que se ve como «se teletransporta abajo».

## Corrección

`src/games/universal/Blatant/Invisible.lua`, contrato nuevo:

1. **El cuerpo real se aparca.** Al encender Ghost: `CanCollide = false` en todo
   el rig, `PlatformStand = true`, `WalkSpeed = 0` y `Anchored = true`. No hay
   física que pelee, porque el cuerpo no simula. Se lee una vez su
   `CanCollide` por parte para devolverlo intacto al apagar.
2. **Sincronización a 10 Hz.** El cuerpo aparcado se reubica debajo del clon
   como máximo cada 0,1 s (`syncBody`), no cada frame. Diez veces menos
   escrituras replicadas y ninguna corrección de posición que pueda saltar.
3. **El clon nace 3 studs ARRIBA del cuerpo**, nunca dentro. Dos rigs no se
   interpenetran y el motor no tiene motivo para aplicarles impulso.
4. **Fly = velocidad sobre un rig NO anclado.** Se elimina el anclaje del modo
   vuelo; `AssemblyLinearVelocity` hace el trabajo, sin raycasts en el bucle y
   sin escribir `CFrame` ni una vez.
5. **Caminar es 100 % físico nativo**: `Humanoid:Move` con el vector del
   servicio de movimiento (teclado, stick móvil y binds incluidos), sin tocar
   `CFrame` ni fijar altura.
6. **Opciones eliminadas:** `Void guard`, `Sprint multiplier` y `Outline`. El menú
   queda en cinco filas: `Ghost Fly`, `Fly speed`, `Void depth`,
   `Ghost WalkSpeed`, `Ghost transparency`.
7. **Void depth = 5 por defecto** (mínimo 5, máximo 350). Migración de una vez:
   120 (default v187), cualquier valor menor a 5 y un perfil sin valor pasan a
   5; un valor elegido (por ejemplo 42 o 200) se respeta.
8. **Al apagar** se restauran las colisiones **antes** de devolver el cuerpo
   (el primer borrador lo hacía al revés y dejaba el rig atravesando el piso),
   se desancla, se coloca en el CFrame del clon y se libera `PlatformStand`.

## Pruebas

`tools/test_ghost50.py` reescrita para este contrato. Comprueba, entre otras:

- el cuerpo real queda **anclado y sin colisiones** mientras Ghost está ON, y
  recupera ambos al apagar / perder el clon / descargar el módulo;
- el clon nace 3 studs por encima del cuerpo (`near(gr.Position.Y, 23)`);
- el cuerpo se reubica **como máximo una vez cada 0,1 s** y aun así sigue al clon;
- caminar no escribe `CFrame` del clon ni recarga animaciones cada frame;
- Fly deja el rig **desanclado**, responde al servicio de movimiento y no
  escribe `CFrame`; sin input la velocidad es exactamente cero;
- las cinco opciones y la ausencia de `Void guard`, `Sprint multiplier` y
  `Outline`;
- migración 120 → 5, 1 → 5, y 200/42 conservados;
- spawn fallido no aparca el cuerpo y deja la tarjeta OFF.

`tools/gen_full_boot_harness.py` verifica los defaults en el boot real del
bundle. `bash tools/validate.sh` completo en verde (126 suites, `failures=0`,
46 tarjetas, Ghost con 5 opciones).

## Límites

- Sigue siendo local: el servidor ve tu cuerpo real donde estaba, no al clon.
- El aparcado desancla tu cuerpo del lado local; si el juego reasigna
  `Anchored` (respawn, anti-cheat del juego) el módulo vuelve a aparcarlo en el
  siguiente frame.
- Los mocks no sustituyen la prueba en Roblox/Delta: faltan FPS reales,
  replicación y comportamiento del servidor.
