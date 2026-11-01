# v167 — Organización del menú y auditoría de módulos

Fecha: 2026-10-31 · Stamp: `v167-20261031-menu-mm2-module-audit`

## Menú y MM2

- Se elimina la ventana **Combat**. Los módulos que todavía usan esa categoría
  como alias se presentan en **Exploits**. Universal muestra **KillAura** y
  **Aimbot** allí; `Universal.KillAura` y `Universal.AimAssist` conservan sus
  identidades de configuración. La búsqueda también acepta `Aim Assist`.
- Solo con MM2 activo, la tarjeta universal se muestra como **Knife Stab**, sin
  una segunda tarjeta KillAura. La adaptación también actualiza orden, búsqueda,
  título y controles flotantes cuando MM2 se detecta después del arranque.
  Se migran opciones y tecla antiguas de Knife sin sobreescribir una preferencia
  universal explícita. Knife Throw y Gun Aimbot están en Exploits.
- Gun Aimbot muestra **Normal(Bullet)**, **Silent(Cframe)** y **Experimental**.
  Los perfiles con `Bullet` o `CFrame` se migran manteniendo los buckets de
  opciones por modo. Se retiró **Avoid innocents** junto con su selección de
  puntos y bloqueo por inocentes detrás del objetivo; WallCheck sigue existiendo.
- Auto Shoot está en **Utilities**. El control **Aura** solo se muestra cuando
  **Proximity** está activo; ocultar esa fila ya no oculta todo el panel. El
  estado muestra el modo desde la activación inicial y el radio solo con
  Proximity. Los tres modos siguen conservando sus ajustes independientes.
- El Auto Shoot de Auto Farm usa exclusivamente el constructor Silent, con
  `wallCheck = false` sin importar el WallCheck de Gun Aimbot. Si ese
  constructor no está disponible, informa de ello y no hace fallback a Bullet.
  Esto no demuestra que una bala atraviese paredes ni que cause daño en el
  servidor.
- Fling ya no expone **Power**, **Duration** ni **Prediction**; conserva los
  defaults internos anteriores (4, 3 s y 0,15 s), el objetivo y las acciones.
  Se mantiene **Retries**, que no era uno de los tres controles solicitados
  para retirar, con su configuración y comportamiento anteriores. La rutina
  conserva adaptaciones propias y no se presenta como copia literal de YARHM.

## Auditoría y correcciones adicionales

- **Knife Stab / KillAura:** cleanup de listeners y transición MM2 tardía; se
  conserva la clave universal y la preferencia al descargar el adaptador.
- **Roles e ItemESP:** MM2 y VD retiran únicamente su propio proveedor de roles,
  sin eliminar uno más reciente. `Show Perk` aparece al detectar MM2 y se oculta
  al retirar el proveedor. Las filas Gun ESP/Trap ESP también se ocultan al
  retirar sus proveedores; si vuelve uno con el mismo nombre, la fila existente
  pasa a llamar al proveedor nuevo y conserva su selección.
- **Infinite Jump:** el primer salto positivo desde el suelo queda a cargo del
  motor tanto en PC como en móvil. Se mantienen impulsos aéreos, deduplicación,
  potencia negativa y cleanup. Los mocks no ejecutan el solver físico de Roblox.
- **Ghost:** al fallar la clonación inicial, el módulo informa del error y queda
  apagado; si se pierde el ghost activo o se descarga directamente, sincroniza
  la tarjeta, la actividad y sus conexiones. Walk sigue usando física nativa.
- **NPCESP:** el texto de `Force by name` ya no se aplica ni se borra letra por
  letra y un valor guardado no intenta usar el control antes de crearlo. Enter o
  el nuevo botón táctil **Add forced name** envían el nombre completo. Limpiar
  los nombres también retira dibujos de coincidencias anteriores; se desconecta
  el listener del campo al descargar.
- **Render y movimiento:** Fullbright, Zoom, FOV, HP y X-Ray evitan escrituras
  redundantes en los casos cubiertos; X-Ray conserva cambios externos al
  restaurar. Fly y Speed reutilizan parámetros de raycast, Spider y
  Freeze Movements corrigen actualizaciones/cleanup. Los tests no miden FPS.
- **BedFight:** Auto Swing y Round Info no mantienen trabajo de frame con la
  tarjeta apagada. Se revisaron Beds, Anti Void, Scaffold y su limpieza incluso
  si el Framework se descarga antes. **VD:** ownership de velocidades, boosts y
  animaciones ante cambios externos/respawn. **TRS:** cancelación generacional
  de acciones diferidas y liberación del hook al terminar los contextos; otro
  hook encima puede conservar un wrapper inerte. Todo esto se probó con mocks.
- **MM2:** Calibration Trails, Trajectory Calibration, Sprint y Blurt Roles
  reciben limpieza o ajustes de lifecycle. Se eliminó un helper no utilizado de
  Disguise, pero se conservó `restoreMotionBucket`, necesario para migración.
  X2 y BedFight trasladan sus tarjetas Combat a Exploits sin cambiar a otra base.

## Get All Emotes: alcance real

Se contrastó la implementación con el snapshot cliente
[`place, source.rbxlx` de TestingStuff](https://github.com/XzAngel19/TestingStuff/blob/a8498173955da3bc57c7f72325ec3af2ba0d6535/place%2C%20source.rbxlx).
En ese snapshot, `ProfileData` obtiene datos del servidor pero su tabla local y
`InventoryDataChanged` son del cliente; el evento `PlayEmote` llega al script
`Animate`, que usa el catálogo `Sync.Emotes` y solicita la animación. El
snapshot no contiene una concesión de inventario en el servidor ni verifica el
comportamiento de la versión actual del juego.

Se corrigieron los IDs de respaldo de los siete emotes MM2 según ese snapshot;
el catálogo `Sync.Emotes` disponible en el juego tiene prioridad y acepta IDs
numéricos o strings y su propiedad `Loop`. Se detiene el track propio al cambiar,
apagar o descargar y se invalidan callbacks de respawn viejos. El conteo solo
informa entradas de una tabla local disponible: disparar un BindableEvent no
cuenta por sí solo como propiedad.

Roblox documenta que una animación iniciada en el cliente de un personaje de
jugador puede replicarse si usa un `Animator` creado en servidor y replicado al
cliente: <https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Animator.yaml>.
Eso **no prueba** que el asset concreto sea permitido, que otros jugadores lo
vean en MM2/Delta, ni que se conceda propiedad en servidor. Esta parte de la
petición del usuario permanece **sin verificar y sin demostración de concesión**.

## Validación y límites

`python3 tools/build_bundle.py --stamp v167-20261031-menu-mm2-module-audit` y
`bash tools/validate.sh`:

- Bundle actualizado: **89 archivos**; **91 fuentes Lua** compilan.
- Catálogo: 39 módulos universales y 78 entradas de ventana; auditoría estática
  de callbacks por frame: PASS.
- **107 suites Python/Luau**: PASS. Incluyen pruebas nuevas de migración del
  menú, Auto Farm Silent, Proximity, activación tardía y ownership de roles,
  emotes, NPCESP, Infinite Jump, KillAura, BedFight, VD y TRS.
- Boot simulado `failures=0`; **90 llamadas API** verificadas; menú de debug
  50 tarjetas y release 49 sin Calibration: PASS.

Las compilaciones y mocks no prueban servidor, daño, física real, replicación,
executor, seguridad anticheat ni rendimiento o imagen en Roblox/Delta. La causa
visual de los Shaders negros aún no se ha confirmado con el usuario. Se continuó
la revisión y se compilaron todos los archivos, pero **no se ha completado ni
verificado una auditoría manual exhaustiva de todos los módulos**; no se debe
presentar esta versión como equivalente literal a Vape/YARHM ni como cierre de
esa parte pendiente.
