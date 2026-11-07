# v190 — El hook devolvía el clic con el método roto (Gun Aimbot PC)

Fecha: 2026-11-07. Stamp: `v190-20261107-gun-ping-names`.
Rama de la sesión: `arena/7446e4e3-arandommenu` (desde el tip v189 de
`arena/05c45e27-arandommenu`).

Peticiones del jugador en la misma tanda:

1. El Gun Aimbot en PC no funciona y siempre sale el mismo error que «ningún
   agente puede solucionar».
2. Se borró el Fling de MM2 junto con el Fling Universal.
3. Aviso cuando hay Anti Fling activado y se intenta Walk Fling o flingear a
   alguien (solo MM2).
4. Renombrar **Ghost** → **Invisibility**.
5. Renombrar **Motion Lock** → **Freeze Animations**.
6. Anti Fling hace noclip a través de los cuerpos de las demás personas.

---

## 1. Gun Aimbot en PC: el error era nuestro

### Síntoma (captura de consola, sesión real)

En bucle, cada pocos clics:

```
The current thread cannot call 'GetValue' (lacking capability Plugin)
Stack Begin
Script 'Workspace.<jugador>.Gun.GunClient', Line 70
Stack End
```

El hilo es del juego, pero la llamada era nuestra: la captura de v187 ya había
identificado ese texto como el lector de `Data Ping`
(`Stats.Network.ServerStatsItem["Data Ping"]:GetValue()`), y **`GetValue` es un
método con seguridad Plugin**. Delta corre el script sin esa capability, así que
la llamada falla siempre.

### Por qué v187 no lo cerró

v187 dejó el plan «solver dentro del hook y reenviar por el motor». Ese plan
depende de que el **registro de método namecall** del hilo siga intacto al
llegar al trampolín. Cualquier llamada a método hecha por el hook o por el
solver lo sobrescribe; el motor entonces despacha **el último método ejecutado**
en vez de `FireServer`. Cuando ese último método era `GetValue` (el ping), el
error que salía era `GetValue (lacking capability Plugin)` y el paquete nativo
del disparo moría en el hook: la gun no accionaba. `pcall` no ayuda: captura el
error, pero el registro ya quedó pisado.

### Corrección

Dos reglas, una en cada extremo:

- **Ninguna lectura restringida** (ver §2). `GetValue` desapareció de `src/`;
  la latencia sale de `Player:GetNetworkPing`, siempre dentro de `pcall`.
- **El hook ya no ejecuta nada antes del trampolín.** Decidir redirigir y
  devolver: captura `table.pack(...)`, lanza un `task.defer` con los argumentos
  y devuelve `nil`. Ese hilo nuevo resuelve el objetivo y envía **un solo**
  paquete:
  - redirigido (CFrames del solver + argumentos extra del paquete original), o
  - el original tal cual si el solver rechaza (sin objetivo, pared, geometría).

  El paquete del juego nunca llega a un registro corrupto y ningún error nuestro
  puede viajar al `GunClient`. El reenvío sale de un hilo del executor, así que
  `checkcaller()` lo manda directo al trampolín y una bandera
  (`sendingRedirect`) impide que nuestro propio paquete vuelva a entrar en la
  redirección.

Se conserva lo que ya estaba probado: un único transporte por clic, cámara
intacta, WallCheck que rechaza sin bloquear el clic, `Auto Shoot`/`Auto Farm`/
cuchillo fuera del hook, y móvil sin este hook.

## 2. Ping sin `GetValue`

- `base.lua`: `readLatencyReadings()` devuelve solo la lectura del motor
  (`GetNetworkPing`); el hueco de «Data Ping» queda en `nil` porque nada
  accesible lo expone. `getPingMilliseconds()` (telemetría) lee lo mismo.
- `Prediction.lua`: sigue prefiriendo la fuente de calibración cuando existe y
  cae al motor cuando no; el eco medido y el prior de aceptación no cambian.
- `FloatingWindows.lua`: el ping del overlay sale de `GetNetworkPing`.
- `tools/diagnostics/ShootProbe.lua`: idem.

Consecuencia honesta: se pierde la lectura de Data Ping. El predictor ya tenía
camino de respaldo (mediana de 8 muestras, eco propio, corrección aprendida por
disparo) y ese es el que queda activo. No se promete la misma precisión que con
Data Ping en todas las conexiones: se mide en vivo.

## 3. Fling de MM2 vuelve (solo el de MM2)

- Módulo nuevo `src/games/MM2/Other/Fling.lua`, tarjeta **Fling** en Exploits,
  página MM2, tipo grupo (la tarjeta no se «activa», solo tiene controles).
- Controles: **Target player** (lista viva, un solo objetivo; elegir a alguien
  lanza el fling de inmediato y la fila se limpia para poder repetir),
  **Power** (1-10, por defecto 6) y **Retries** (0-3, por defecto 2).
- Una selección guardada en el perfil **no** flingea al inyectar: la lista
  publica su estado inicial y eso se ignora a propósito.
- `FlingEngine.lua` acepta `options.power` y `options.retries` para esa llamada
  y restaura sus valores al terminar, así Auto Farm/Auto Win conservan sus
  números. Ya no borra las claves `MM2.Fling*` del perfil al arrancar.
- El Fling **Universal** sigue eliminado (era lo que el jugador pidió borrar).

## 4. Aviso de Anti Fling (solo MM2)

Anti Fling protege justamente del contacto que un fling necesita, así que con
la protección activa el fling se ve «roto». Ahora, en MM2:

- **Walk Fling**: al activarla, el handler lanza un error con el motivo, así que
  la tarjeta se revierte sola y el menú avisa
  `Could not toggle Walk Fling: Anti Fling is ON. Turn it off first to use Walk
  Fling.`
- **Fling (MM2)**: elegir un objetivo con Anti Fling activo no llama al motor y
  avisa `Anti Fling is ON: turn it off before flinging someone.`; el estado de
  la tarjeta queda en `Anti Fling is ON`.
- La bandera compartida es `state.antiFlingActive`, que publica el propio
  módulo Anti Fling al conectarse y al apagarse. Fuera de MM2 la puerta no
  existe.

## 5. Anti Fling ya no es un noclip contra las personas

Antes: cada cuerpo visible recibía `NoCollisionConstraint` contra cada parte
local (hasta 2048 pares). Caminar hacia alguien atravesaba su cuerpo: eso es lo
que el jugador reportó.

Ahora el escudo es **solo contra cuerpos que de verdad están flingeando**:

- un cuerpo dentro de 30 studs con alguna parte a ≥80 studs/s o ≥70 rad·stud de
  giro se marca como peligro y se sostiene `0.75 s`;
- solo las partes **colisionables** de ese cuerpo se enlazan, y solo con las
  partes colisionables locales;
- cuando el peligro expira, los pares se destruyen y las colisiones normales
  vuelven.

El resto del módulo (Impact Shield para objetos sueltos veloces, exclusión de
suelos/vehículos/herramientas, pausa durante flings voluntarios, limpieza
OFF/respawn y amortiguación de emergencia) no cambia.

## 6. Renombres

| Antes | Ahora | `ConfigKey` |
| --- | --- | --- |
| `Ghost` | `Invisibility` | `Universal.Ghost` (sin cambios) |
| `Motion Lock` | `Freeze Animations` | `Movement.FreezeMovements` (sin cambios) |

En Invisibility, tres filas dejan de llevar el prefijo viejo: `Ghost Fly` →
`Fly`, `Ghost WalkSpeed` → `WalkSpeed`, `Ghost transparency` → `Transparency`.
Los ids de opción se derivan del nombre, así que esas tres filas vuelven a su
default una vez; `Void depth` (la única que el jugador suele ajustar) conserva su
nombre y su valor. El keybind y el estado ON/OFF de la tarjeta no cambian.

## 7. Pruebas

- `tools/test_gun_native_pc.py`: el mock ahora modela `task.defer`; el clic se
  envía en el hilo diferido y sigue habiendo **un solo** transporte, con
  argumentos extra, cámara intacta, WallCheck, objetivo ausente y solver con
  error.
- `tools/test_ping_capability.py` (nuevo): falla si `:GetValue(` reaparece en
  `src/`, si el overlay vuelve a leer Data Ping o si el hook reenvía por el
  motor después de resolver.
- `tools/test_mm2_fling_card.py` (nuevo): tarjeta, lista viva, Power/Retries,
  prohibido flingear al inyectar y aviso con Anti Fling.
- `tools/test_walkfling.py`: el caso MM2 + Anti Fling (y que fuera de MM2 no
  bloquee).
- `tools/test_antifling.py`: cuerpo calmado ⇒ sin pares (ya no noclip), cuerpo a
  velocidad de fling ⇒ pares, y liberación al parar.
- `tools/test_fling_skid.py`: Power/Retries por llamada y restauración.
- `tools/test_mm2_precision.py`: latencia solo del motor, `GetValue` prohibido en
  el mock, valores inválidos y tope duro.
- `tools/test_ghost50.py`, `tools/test_gui_v181.py`, `tools/gen_full_boot_harness.py`:
  nombres nuevos.

## 8. Pendiente en vivo (sin cambios en la política)

- Confirmar en Delta con Gun Aimbot ON: (a) no reaparece el error de `GetValue`,
  (b) la gun dispara en Bullet y Silent, (c) el cuchillo acciona normal.
- La latencia ahora es el motor + eco propio: comparar unos disparos reales.
- Fling de MM2: probar con Anti Fling **apagado** y confirmar que el aviso
  aparece cuando está encendido.
- Anti Fling: caminar contra otro jugador debe chocar; recibir un fling debe
  seguir protegiendo.
