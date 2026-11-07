# Wurst

Menú para Roblox con módulos universales y para MM2, BedFight, TRS, VD y X2.
La versión de esta sesión está en la rama `arena/7446e4e3-arandommenu`
(build `v193`, se muestra como **`0.193`** y **`0.193 Release`**); `main` es
independiente.

## Loader

```lua
getgenv().WURST_BRANCH = "arena/7446e4e3-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/7446e4e3-arandommenu/src/Wurst.lua"))()
```

## Cambios de v193

- **La lectura del servidor es una sección viva**, como el `Overlay Info` de
  AutoFarm: `Server`, `Players`, `In server`, `Uptime`, `Server time` y `Place`.
  Sin ventana flotante, sin deslizador `Refresh every`, y **nunca se para**: el
  ticker se crea al inyectar y solo lo suelta `destroy()`, también con la tarjeta
  apagada. Se quitaron las filas `Build`, `Round` y `You`.
- **`Place` dice el nombre del place** y añade `· subplace` cuando
  `game.PlaceId ~= game.GameId`.
- **Hops que ya no fallan:** la URL lleva solo `sortOrder`, `limit` y `cursor`;
  se leen hasta 2 páginas por orden; el filtro de hueco libre se hace en el
  cliente y, si **todas** las instancias listadas están llenas, el hop avisa y
  hace `Teleport(placeId)` en vez de dejar al jugador donde estaba.
- **Controles de celular ocultos sin tocar el juego:** se apagan solo dos
  `ScreenGui` (`TouchGui` de Roblox y `TouchInteractButtons` de MM2), y solo en
  una máquina con teclado. Se eliminó la escritura del atributo `Device` de
  `PlayerGui` que hacía v192 (eso es estado del juego y le hace reconstruir el
  HUD). Nunca se escribe `TouchEnabled`, ni el icono del ratón, ni los keybinds.

## Cambios de v192

- **El Fling vuelve a ver a todo el mundo.** v191 comparaba `player.Parent` con
  el `Players` **clonado** (`cloneref`), y un clon nunca es igual al original:
  el guardia fallaba para todos y la lista salía vacía. Ahora el guardia
  pregunta a la instancia (`ClassName == "Player"`). La detección de roles se
  revisó contra el place real de MM2 (`Remotes.Gameplay.GetCurrentPlayerData` /
  `PlayerDataChanged`) y entiende claves por UserId.
- **`Rejoin Server` eliminado** de Server Settings.
- **Hops con lógica real:** sólo se aceptan servidores con **hueco libre**
  (`playing < maxPlayers`, `excludeFullServers=true`). `smallest` ignora los
  vacíos (0/12 no es una partida) y `largest` es el más lleno al que se puede
  entrar — **11/12** en un place de 12. `random` mezcla las dos páginas de la
  lista.
- **`Show server info` abre una overlay** con Job ID, jugadores, lista de
  nombres, **uptime del servidor** (`workspace.DistributedGameTime`), hora del
  servidor, place y versión, tu usuario, el build y la fase de ronda de MM2.
- **El menú no deja al jugador en modo móvil:** en una máquina con teclado y
  ratón se oculta el `TouchGui` de Roblox y se devuelve a `PC` el atributo
  `Device` de `PlayerGui` que usa MM2 para su HUD táctil. Nunca se escribe
  `TouchEnabled`, ni el icono del ratón, ni el esquema de entrada.
- **Una sola versión:** `SOURCE_STAMP` → `0.192` en los títulos y
  `0.192 Release` en la línea de producto. Ya no queda ningún `0.823` escrito a
  mano.
- **Disguise:** la opción se llama **`Use target movement animations if able`**,
  pide el arreglo de controles tras cada aplicación y reinicia sus banderas por
  cuerpo al reaparecer (antes sobrevivían y el disfraz salía a medias).
- **Skills nuevas** en `docs/skills/`: `agent-run-efficiency.md` y
  `roblox-menu-change.md`.

## Cambios de v191

- **Etiqueta de versión:** el menú ya no muestra `v191`, sino
  **`Version 0.191`** (derivada del `SOURCE_STAMP`), en la ventana de ajustes.
- **`Arrows` pasa a llamarse `Player Pointers`.** Sólo el nombre visible: el
  `ConfigKey` (`Universal.Arrows`), el estado guardado y el keybind siguen
  iguales.
- **El botón de Pin usa el color de las flechas.** La fila de paleta
  `Arrows` ahora se llama **`Buttons`** (conservando su clave guardada) y pinta
  los chevrones *y* el botón de Pin: al fijar una ventana, el chip se tiñe con
  ese color.
- **`Opacity` ya no apaga todo el menú:** sólo afecta al **fondo** de la
  ventana. Títulos, textos, iconos y controles quedan siempre a opacidad
  completa.
- **Fling de MM2 completo otra vez:** `Fling Murderer`, `Fling Sheriff`,
  `Fling All Innocents`, lista de objetivos con su rol y `Auto Fling Selected
  Target`, sobre el motor actual (`FlingEngine`). **Power y Retries vienen al
  máximo** (12 / 3) de fábrica.
- **Disguise carga al inyectar:** los clips se precargan antes de escribir los
  slots, se espera al script `Animate` si aún no replicó y, si la pose queda
  congelada, se reintenta el script antes de devolver tus animaciones.
- **Blurt Roles es un botón:** al pulsar la tarjeta se dicen los roles al
  instante. `Blurt Now` desapareció y el envío automático pasó a la opción
  `Auto blurt`.
- **`Spider` → `Wall Crawling`** y **`Swim` → `Air Swim`** (sólo el nombre
  visible; `Universal.Spider` y `Universal.Swim` se conservan).
- **Notifications mejorado:** radio y enfriamiento configurables del aviso de
  Murderer cercano, dirección (N/NE/E…) en el mensaje, aviso de **Sheriff
  caído** y toasts con color por tipo, duración según el texto y pila limitada
  a 5.
- **Knife Stab: nueva opción `Hold Mouse`.** Apaga el kill aura automático y
  ataca al hacer clic o tocar la pantalla, con el **mismo alcance de
  `Aura Range`**.
- **Nueva tarjeta `Server Settings`** en Utilities: Job ID y número de
  jugadores, copiar Job ID, rejoin y salto al servidor público más pequeño,
  más grande o aleatorio. No escribe nada en el servidor (un cliente no puede).

## Cambios de v190

- **Gun Aimbot (PC) arreglado en la raíz.** El error en bucle
  `The current thread cannot call 'GetValue' (lacking capability Plugin)` era
  nuestro lector de `Data Ping` ejecutándose dentro del hook del clic: Delta no
  da la capability Plugin y, además, el hook dejaba el método namecall pisado,
  así que el `FireServer` del `GunClient` moría antes de salir. Ahora no queda
  ninguna lectura restringida y el hook sólo captura el clic y lo resuelve en un
  hilo aparte, enviando un único paquete.
- **Fling de MM2 vuelve** como tarjeta propia en Exploits (Target player,
  Power, Retries). El Fling universal sigue eliminado; era el que pediste
  borrar.
- **Aviso de Anti Fling (sólo MM2):** con Anti Fling activo, Walk Fling se
  niega y Fling avisa en vez de fallar en silencio.
- **Anti Fling ya no es un noclip contra personas:** sólo protege de cuerpos que
  de verdad se están moviendo a velocidad de fling; un jugador tranquilo
  conserva sus colisiones normales.
- **Renombres** (mismo `ConfigKey`, se conservan perfiles y keybinds):
  `Ghost` → `Invisibility` y `Motion Lock` → `Freeze Animations`.

## Cambios de v179

`Shaders` se eliminó por completo: no hay tarjeta, no hay assets y el arranque
no toca `Lighting`. Con él se fueron `Surface textures`, `Wet surfaces`, `Fog`,
`Rain`, `Snow`, `Falling leaves`, `Dust motes`, `Water reflections` y el botón
`Diagnose`.

Tres tarjetas de **Exploits** cambian de nombre (misma función, mismo
`ConfigKey`, así que tus perfiles y keybinds se conservan):

| Antes | Ahora |
| --- | --- |
| `Jesus` | `Swim Walk` |
| `Jump` | `Jump Hack` |
| `Speed` | `Speed Hack` |

## Precisión de Shoot y Knife

Medido con las exportaciones `MM2_Trajectory_Calibration` del propio usuario
(schema 4, 11 sesiones): el viaje real `FireServer` → confirmación del servidor
está en **196-204 ms**, mientras que el `Data Ping` marca 150-165 ms. La
diferencia es el procesado del servidor, y usar el ping como horizonte dejaba
cada tiro corto. v179 lo corrige en dos frentes:

- **Antes de tener ecos propios**, la mira arranca del promedio de aceptación ya
  confirmado en la cuenta (historial importado + sesión actual). Si esa cifra no
  encaja con la conexión en uso (fuera de 0,75×–2,5× el RTT) o tiene menos de 8
  muestras, se ignora y manda el ping.
- **El cuchillo aprende de sus propios tiros.** Cada hoja lanzada se sigue hasta
  su paso más cercano al cuerpo; el desvío se proyecta sobre la velocidad del
  objetivo y se convierte en segundos, con el mismo signo y los mismos límites
  que el cañón. El horizonte del cuchillo se corrige solo, poco a poco, con ese
  dato.

No se cambió el modelo de movimiento ni se reescribió el aim: los datos no lo
justifican y la telemetría existente se conserva (los eventos de cuchillo
incluyen ahora `leadErrorSeconds`, `predictedRoot` y `approachRoot`).

## Desarrollo

`src/libraries/Manifest.lua` es el catálogo de módulos; `src/Wurst.lua` carga
el bundle y descarga los assets de la interfaz por separado. No edites
`src/libraries/bundle.lua` a mano. Tras cambiar fuentes, actualiza el
`SOURCE_STAMP` y ejecuta:

```bash
python3 tools/build_bundle.py --stamp <SOURCE_STAMP>
bash tools/validate.sh
```

Se conservan las pruebas, sus fixtures y la herramienta de Luau. La validación
es simulada: no sustituye probar Roblox, Delta ni el servidor. Los detalles y
contratos del proyecto están en `RESUME.md`.
