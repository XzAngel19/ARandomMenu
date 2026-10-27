# v151 — walkfling real, Auto Farm “Below Map” y control manual preservado

Rama: `arena/2ec6eed9-arandommenu`  
Stamp: `v151-20261027-walkfling-below-map-manual-control`  
Build visible en el menú: **v151**

El usuario probó v150 en vivo y reportó: «Ninguno funciona. No funciona Fling
ni TouchFling. AutoFarm no sirve no mueve mi personaje, Cuando lo tengo
activado no puedo mover mi personaje e Path Finder solo llamalo Below Map para
que recolecte las coins Below Map». v150 queda como evidencia del place, pero
sus mecanismos de Fling/Touch Fling/Auto Farm se sustituyen aquí.

---

## 1. Diagnóstico: por qué v150 falló en vivo

| Síntoma | Causa encontrada en el código | Corrección |
| --- | --- | --- |
| Fling / Touch Fling no lanzan a nadie | v150 usaba `ApplyImpulse` de 190 studs/s sobre el root propio o sobre un root ajeno cuya propiedad de red no se podía confirmar. El servidor no aceptó ese knockback. | Volver al mecanismo completo de `walkfling` de Infinite Yield, no a una aproximación. El cliente es dueño de su propio root: publica una ventana de velocidad alta por frame y el servidor resuelve el contacto. |
| v149 tampoco era ese mecanismo | Había copiado `1e6` en vez de `10000`, no alternaba `movel` y omitía el noclip que IY activa junto con `walkfling`. | Se clonó el repositorio oficial `EdgeIY/infiniteyield` (`febace97c7d45697054eb1a3ebc9ee3fb783d5f8`, comando `walkfling` cerca de la línea 11835) y se reproducen sus tres señales y constantes exactas. |
| Auto Farm no mueve el personaje | `PathfindingService` no encontraba rutas útiles en mapas MM2 con `GlitchProof`; además `roundContext()` exigía `getPlayerRole(LocalPlayer) == "Innocent"` y podía quedarse en “Waiting” aunque hubiera monedas. | Se elimina por completo el solver de rutas y el guard de rol. El contexto usa fase/ronda/mapa/timer con fallback a un evento de monedas y pickups reales. |
| Auto Farm bloquea el control del jugador | Un `BindToRenderStep` permanente ejecutaba `Humanoid:Move(...)` después del `PlayerModule` cada frame, incluso sin objetivo, con `Vector3.zero`. | Ya no hay binding de render ni `Humanoid:Move`. El modo Direct usa `Humanoid:MoveTo` nativo; Below Map usa `PivotTo` acotado y cede 1.2 s cuando detecta `MoveDirection`/`Jump`. |
| “Path Finder” confunde al usuario | La opción `Navigation` tenía valores `Pathfinding`/`Direct`. | Pasa a `Farm mode` con valores **`Below Map`** (por defecto) y `Direct`. No queda ningún selector ni servicio de Pathfinding. |

---

## 2. Fling / Touch Fling: secuencia exacta de IY

Código de referencia (`EdgeIY/infiniteyield`, comando `walkfling`):

```text
noclip ON
Heartbeat:
  vel = root.Velocity
  root.Velocity = vel * 10000 + Vector3.new(0, 10000, 0)
RenderStepped:
  root.Velocity = vel
Stepped:
  root.Velocity = vel + Vector3.new(0, ±0.1, 0)
  movel = -movel
```

Implementación v151 (`src/libraries/Fling.lua`):

1. Conexiones permanentes a `Heartbeat`, `RenderStepped` y `Stepped`, con un
   único motor activo por bandera `engineActive`.
2. Escribe `Velocity` y `AssemblyLinearVelocity` **solo del root local**. No
   escribe el root del objetivo, no llama `SetNetworkOwner`, no aplica
   `ApplyImpulse` y no crea constraints.
3. En `Stepped` mantiene `CanCollide=false` en las partes del personaje local
   (noclip de IY) y restaura su valor original al apagar. La tarjeta `Noclip`
   existente cede mientras `activity.set("fling", true)` esté activo.
4. `Touch Fling` enciende el motor continuo: el usuario camina contra otros
   jugadores. Ya no depende de listeners `Touched` por parte del cuerpo.
5. Un Fling dirigido de MM2 usa el mismo motor durante una sesión acotada
   (2.2 s por defecto), con **un** `PivotTo` de colocación y otro de retorno.
   Puede ejecutarse aunque Touch Fling esté ON; no se crean dos motores.
6. `cancel`, OFF, muerte, respuesta o `destroy` restauran velocidad y
   colisiones y desconectan la tarea del scheduler, para no dejar costo idle.
   `lastStrategy()` reporta `walkfling`; `hasOwnership()` es falso.

Archivos cambiados: `src/libraries/Fling.lua`,
`src/games/MM2/Blatant/Fling.lua` y
`src/games/universal/Blatant/TouchFling.lua`.

---

## 3. Auto Farm: “Below Map” sin robar el control

La evidencia del place no cambia: `Coin_Server` está anclada, tiene
`CanTouch=true`, `CanCollide=false`, tamaño `1.2 × 2 × 2`, un `TouchInterest`
propio y paga mediante el `Touched` del servidor. `CoinsStarted` anuncia
`{Coin={CollectedAmount=0,CollectionLimit=50}}` y `CoinCollected` confirma
cada pago.

### 3.1 Modo por defecto: `Below Map`

1. Se descubre el pickup real con `state.mm2CoinPickups()`, la etiqueta
   `CoinVisual` o el nombre exacto `Coin_Server` (cache de 0.3 s).
2. Se filtra `Collected`, `Delete`, `RoundEnd`, `Transparency == 1` y
   `CanTouch == false`, tanto en el visual como en el padre servidor.
3. Para cada moneda se aparca el modelo entero **4 studs debajo** del centro
   de `Coin_Server` con un `character:PivotTo`.
4. Tras 0.08 s se coloca el root **0.6 studs debajo** del centro: el root de
   un personaje mide ~2 studs, así que sigue solapando el volumen vertical de
   la moneda. Es un contacto físico real, no un hitbox local agrandado.
5. Mientras espera `CoinCollected`, refresca esa posición como máximo cada
   0.12 s (no por frame) y opcionalmente llama
   `state.fireTouchInterest(root, Coin_Server, 0/1)` una sola vez como nudge
   local. Ese nudge **no cuenta como moneda**.
6. Si el servidor no confirma en 1.6 s, descarta esa moneda 8 s. Si confirma,
   `coinsConfirmed` sube uno y se invalida la cache de pickups.
7. `Coins Collected` solo aumenta con `CoinCollected`; el saldo de
   `ChangeInventoryItem` se observa pero no se cuenta.

### 3.2 Control manual

- No hay `BindToRenderStep`, `UnbindFromRenderStep` ni `Humanoid:Move`.
- En Below Map, `humanoid.MoveDirection` o `humanoid.Jump` pausa las
  colocaciones durante 1.2 s. El `PlayerModule` conserva el control.
- OFF solo cancela un `MoveTo` propio si existe; no escribe `Move(zero)`.
- `Manual override` es una opción visible por si el usuario quiere
  desactivar esa cesión.

### 3.3 Modo `Direct`

- Usa `Humanoid:MoveTo(position)` refrescado en el tick de Heartbeat; no
  modifica `WalkSpeed`, CFrame, tamaño ni velocidad.
- Mantiene salto nativo para pickups altos y roaming a spawns reales.
- El rescate de vacío de Auto Farm queda desactivado en Below Map, para no
  confundir una colocación intencional bajo el mapa con una caída.

La opción se llama `Farm mode`, no `Navigation`; los valores son
`Below Map` y `Direct`. `Direct` ya no usa waypoints.

---

## 4. Validación offline

```bash
python3 tools/build_bundle.py --stamp v151-20261027-walkfling-below-map-manual-control
bash tools/validate.sh
```

Resultado observado tras esta reconstrucción:

```text
PASS 84 fuentes en el bundle (mismo stamp)
PASS 66 Python/Luau suites
PASS bundle boot, failures=0
PASS 102 call sites core.*/prediction.*
PASS menu audit: 50 tarjetas
PASS release menu: 49 tarjetas, sin Calibration
```

Suites reescritas/actualizadas:

- `tools/test_fling_physics.py`: constantes literales de IY, secuencia de tres
  señales, noclip local, restauración, sesión continua + dirigida y destroy.
- `tools/test_mm2_auto_farm.py`: contrato estático de Below Map, ausencia de
  pathfinding/render binding, control manual y conteo solo por servidor.
- `tools/test_mm2_auto_farm_dynamics.py`: dos colocaciones físicas, refresco
  acotado, pausa manual, `CoinCollected`, bolsa llena, lobby, rol, Direct y
  limpieza de listeners.
- `tools/test_action_latency.py` y `tools/gen_full_boot_harness.py`: nuevos
  nombres de opciones y prohibición del writer que bloqueaba controles.

---

## 5. Pendiente de aceptación EN VIVO (no se afirma)

1. Que MM2 acepte el knockback del `walkfling` real con el executor del
   usuario. El orden de señales y las constantes ya son las de IY; la latencia
   entre cliente/servidor y las colisiones del juego siguen siendo factores
   externos.
2. Que el solapamiento físico desde Below Map dispare el `Touched` del
   servidor y llegue `CoinCollected`. Verificar también el saldo real en
   `ChangeInventoryItem ("Materials","Coins",...)`.
3. Que el `PivotTo` bajo el mapa no sea empujado por `GlitchProof` en todos
   los mapas. Si un mapa bloquea el parqueo, probar `Farm mode = Direct`.
4. Que `Manual override` detecte correctamente el input en el dispositivo del
   usuario; en teclado usa `Humanoid.MoveDirection`, en salto `Humanoid.Jump`.
5. Que Touch Fling no pelee con la tarjeta `Noclip` cuando ambas están ON, y
   rendimiento A/B (FPS/Physics) con ambos motores activos.

---

## 6. Alcance

No se tocó `src/games/X2Duels/Other/AutoFarm.lua`: es otro place con contratos
distintos. Tampoco se reabrieron Anti Void/Anti fling; v150 sigue siendo su
implementación vigente. v151 cambia Fling, Touch Fling y MM2 Auto Farm,
además de los tests, bundle, README y este handoff.
