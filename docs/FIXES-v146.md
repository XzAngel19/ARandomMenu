# v146 — Fling igual a Infinite Yield (sin giro local) y el lag, atacado en su origen

Build: `v146-20261027-iy-fling-and-zero-frame-cost`
Rama canónica: `arena/83897e25-arandommenu`
Base: `v145-20261027-canonical-loader-cache-purge`

Referencia usada: `infinite_yield_O1_v2.lua` (la copia que pasó el usuario).
Se copió el **mecanismo**, no el archivo: sin `math.huge` sueltos en velocidades,
sin giro local, sin `PlatformStand`, sin `ChangeState(Physics)`.

## 1. Por qué el Fling «no hacía nada»

La versión de v144/v145 escribía `AssemblyLinearVelocity` sobre las partes del
**jugador tocado**. Eso no puede funcionar: el cliente no es dueño del assembly
de otro jugador, así que el servidor sobrescribe esa velocidad en el siguiente
frame. El script se veía correcto y no movía a nadie.

Lo que sí funciona —y es exactamente lo que hace Infinite Yield— es hacer girar
**tu propio assembly** con `BodyAngularVelocity` a `99999 rad/s`, `MaxTorque`
infinito y densidad infinita, con el cuerpo `Massless` y sin colisión. El
contacto resuelto por la física arrastra al otro. Ese es el `fling` de IY:

```lua
v.CustomPhysicalProperties = PhysicalProperties.new(math.huge, 0.3, 0.5)
local BodyAngularVelocity = Instance.new("BodyAngularVelocity")
BodyAngularVelocity.AngularVelocity = Vector3.new(0, 99999, 0)
BodyAngularVelocity.MaxTorque = Vector3.new(0, math.huge, 0)
BodyAngularVelocity.P = math.huge
-- ciclo: 0.2 s girando / 0.1 s quieto
```

`src/libraries/Fling.lua` ahora implementa eso:

| Antes (v144/v145) | Ahora (v146) |
| --- | --- |
| Velocidad escrita al objetivo (sobrescrita por el servidor) | Giro del assembly local (replicado por nosotros) |
| `PreSimulation` + `Heartbeat` todo el frame, toda la sesión | **Cero Lua por frame**: `task.wait` 0.2/0.1 y un `Touched` |
| Colocación + `PlatformStand` + `ChangeState(Physics)` + giro local | Un solo `PivotTo` al contacto, igual que IY |
| Restauración manual frágil | Snapshots de densidad/colisión/massless, restaurados al salir |

- Una sola sesión dirigida (`start`), un solo dueño de Touch (`setTouchEnabled`).
- Touch: `CanTouch = true` en las partes del cuerpo (no cambia colisiones), un
  `Touched` por parte y `DescendantAdded` para herramientas; al contacto gira
  0.6 s y se apaga solo. Si no tocas a nadie, no gira y no cuesta nada.
- OFF / muerte / respawn / destroy destruyen el constraint y restauran
  `CanCollide`, `Massless` y `CustomPhysicalProperties`.
- Auto Farm usa el mismo Fling (una sola ruta), así que ya no hay dos
  mecanismos distintos.

**Lo que sigue sin poder afirmarse desde aquí:** que el servidor acepte el
knockback y cuánto vuele el tocado. Eso es física replicada y se mide en vivo.
Lo que sí cambia es que ahora se usa el mecanismo que sí funciona en partida.

## 2. El lag: eran escrituras de física por frame

El snapshot en vivo decía `Physics 12.4 ms (44 %)`, `Render 1.0 ms`,
`Network 0.5 ms`. El costo estaba en física, no en el dibujo. Había tres
culpables, y los tres escribían propiedades de física **cada frame**:

### 2.1 Anti fling (el peor)

Cada frame, por cada otro jugador:

- `GetDescendants()` del personaje completo;
- por cada parte: 3 `pcall` con **una closure nueva por parte y por frame**;
- `CanCollide = false`, `AssemblyLinearVelocity = 0`, `AssemblyAngularVelocity = 0`.

Con 11 jugadores y ~15 partes: **~500 escrituras de física y ~500 closures por
frame**. Cada escritura de `CanCollide` reinserta la parte en el broadphase, y
eso es lo que convertía la física del servidor/cliente en 12 ms.

Ahora:

- se leen **dos magnitudes** por jugador (`AssemblyAngularVelocity.Magnitude`,
  `AssemblyLinearVelocity.Magnitude`) y nada más;
- solo se toca un personaje que **realmente** parece estar flingeando
  (`>20 rad/s` o `>1.5×` su propia velocidad de caminata);
- la lista de partes se cachea por personaje y se invalida con
  `DescendantAdded` (una conexión por personaje, no un recorrido por frame);
- el strip dura `0.45 s` y se reafirma cada `0.1 s` sin volver a escribir
  `CanCollide`; al expirar restaura los valores guardados;
- `destroy` libera cualquier strip pendiente.

Resultado medido en la suite: **1 recorrido de árbol por fling detectado y 0
escrituras por frame** mientras el strip está activo (antes: cientos por frame).

### 2.2 Noclip

Recorría el personaje entero con `GetDescendants()` **y** reescribía
`CanCollide = false` en cada parte en cada frame. La lista de partes ahora se
arma una vez por personaje, se mantiene con `DescendantAdded` y solo se escriben
las partes que todavía tienen `CanCollide` en `true`.

### 2.3 Fling

El diseño anterior mantenía un cuerpo `PreSimulation` + `Heartbeat` durante toda
la sesión, escribiendo constraints y CFrames. Ahora la sesión completa no tiene
ni una conexión de frame: duerme en `task.wait`.

## 3. Cómo se verifica

```bash
python3 tools/build_bundle.py --stamp v146-20261027-iy-fling-and-zero-frame-cost
bash tools/validate.sh
```

```text
bundle.lua is current: 84 files, stamp v146-20261027-iy-fling-and-zero-frame-cost
PASS 66 Python/Luau suites
[Wurst:Bootstrap] Load complete · failures=0
PASS menu audit: 50 cards
PASS release menu: 49 cards, no Calibration card
```

`tools/test_fling_physics.py` (reescrito) ejecuta el controlador real con un
reloj y un scheduler deterministas y comprueba:

- arranque OFF: cero conexiones, cero `PivotTo`, cero constraint;
- fling dirigido: `BodyAngularVelocity` 99999, `MaxTorque` infinito, densidad
  infinita, cuerpo `Massless` y sin colisión;
- **nunca** escribe el assembly del objetivo (la prueba falla si aparece una
  línea `targetRoot.*`);
- ciclo de trabajo 0.2 s / 0.1 s;
- restauración de densidad, massless y colisión al terminar, al morir y al
  destruir;
- Touch: escucha con `CanTouch`, no toca colisiones, no gira en reposo, gira al
  contacto, se apaga al expirar y restaura todo;
- tarjeta universal Touch ON/OFF y su cleanup;
- Noclip no recorre el árbol por frame y restaura su snapshot;
- contratos del wrapper MM2 (lobby, muerte, auto-target, sesión única, bloqueo).

`tools/test_antivoid50.py` cuenta escrituras y recorridos: 0 escrituras por frame
durante el strip y liberación de colisiones en detección, expiración y destroy.

## 4. Qué mirar en vivo (lo único que falta)

1. Touch Fling con dos cuentas: al tocarse, el otro debe salir despedido.
2. Fling dirigido (Fling Murderer / Fling Sheriff) en ronda activa.
3. FPS/Physics con `Anti fling` + `Noclip` activos y 10+ jugadores: el
   microprofiler debería dejar de mostrar `Physics` como el bloque dominante.
4. Si el tocado no sale despedido, lo siguiente es medir el desplazamiento de su
   root antes/después del contacto. **No** subir magnitudes: el mecanismo es el
   de IY y ya está en su valor de referencia.
