# v193 — Lectura de servidor viva, hops que no fallan, controles de celular ocultos sin tocar el juego

Build: `SOURCE_STAMP = "v193-20261107-live-server-readout"` → se muestra como
**`0.193`** en los títulos y **`0.193 Release`** en la línea de producto.

Esta tanda responde a lo que el jugador reportó después de v192: *«Disguise
keeps doing it, Server Settings don't work now? Doesn't work smallest server nor
largest server and the overlay is inside the options, it's an overlay just like
AutoFarm and make it not stop…»*.

## 1. La lectura del servidor es ahora una sección viva, como AutoFarm

v192 dibujaba un **Frame flotante** colgado del ScreenGui del menú: caía encima
de las opciones, y además dependía del tick de la tarjeta, así que al apagarla
dejaba de refrescarse.

v193 la sustituye por el patrón de **AutoFarm**: `state.addSectionOption(card,
"Overlay Info")` + `state.addStatOption(card, <fila>, <valor>)`. Son filas de la
propia tarjeta, sin ventana, y **nunca se paran**:

- el ticker se crea en `init` y solo lo suelta `destroy()`; apagar o encender la
  tarjeta no lo toca;
- corre a **1 Hz** fijo (se eliminó el deslizador `Refresh every`, que era lo que
  dejaba el tiempo «congelado»);
- cada fila solo escribe su etiqueta **cuando el texto cambia** (el
  `set` de `addStatOption` ya evita escrituras repetidas).

Filas, y solo datos del servidor:

| Fila | Dato |
| --- | --- |
| `Server` | Job ID corto (`abc123de`), o `private server` |
| `Players` | `n / maxPlayers` |
| `In server` | nombres de los jugadores, recortados |
| `Uptime` | `workspace.DistributedGameTime` — tiempo del **servidor** |
| `Server time` | `workspace:GetServerTimeNow()` en UTC |
| `Place` | **nombre del place**, con `· subplace` cuando `PlaceId ~= GameId` |

Se quitaron las filas `Build`, `Round` y `You`, tal como pidió el jugador.

## 2. Hops: ya no dependen de una bandera ni se rinden

v192 mandaba `excludeFullServers=true` y exigía hueco. Si el endpoint no acepta
esa bandera, **todas** las peticiones fallaban: «Server hop: the server list
request failed». Y si el place está lleno de instancias 12/12, el pool quedaba
vacío y el aviso era «no se encontró servidor», sin mover al jugador.

v193:

- la URL lleva solo `sortOrder`, `limit=100` y, para páginas siguientes,
  `cursor` (nada más);
- se leen hasta **2 páginas por orden** (`MAX_PAGES`), es decir ~200 candidatos
  por hop, en vez de una sola página;
- el filtro de hueco real (`playing < maxPlayers`) se hace en el cliente, así que
  el aviso puede explicar lo que vio;
- **si ningún servidor listado tiene hueco**, el hop ya no falla: avisa
  (`all 200 listed servers are full · joining any server instead…`) y llama a
  `TeleportService:Teleport(game.PlaceId, LocalPlayer)`, que deja que Roblox
  elija una instancia con sitio;
- `smallest` sigue ignorando las instancias vacías y `largest` sigue siendo la
  más llena **con hueco** (11/12 en un place de 12); `random` mezcla las dos
  ordenaciones.

## 3. Controles de celular: qué se tocaba y qué se toca ahora

Dos GUIs son, literalmente, los controles de celular:

1. `PlayerGui.TouchGui` — el thumbstick/salto de Roblox.
2. `PlayerGui.TouchInteractButtons` — la GUI propia de MM2 con los botones
   `Lanzar / Equipar / Beneficio` (leída del place real: `ScreenGui` con
   `ResetOnSpawn = false`, `DisplayOrder = 3`).

En un portátil con pantalla táctil `TouchEnabled` es `true`, Roblox crea la
primera y MM2 enciende la segunda (su cliente decide con
`GetLastInputType() == Touch` y `TouchEnabled and not KeyboardEnabled`).

v193 **solo escribe `ScreenGui.Enabled = false`** en esas dos GUIs, y solo si hay
teclado (máquina de escritorio; si no hay ratón se acepta como escritorio cuando
la última entrada fue ratón o teclado). Se re-aplica cuando la GUI aparece y
cuando el juego la vuelve a encender, con un watcher por GUI.

**Se eliminó la escritura del atributo `Device` de PlayerGui** que hacía v192:
eso no es una GUI, es estado que el juego lee para decidir su HUD, y reescribirlo
provoca que el juego reconstruya su interfaz (y con ella toda la cascada de
`Requested module experienced an error while loading` que se ve en consola
cuando el juego tiene sus propios módulos rotos). El menú no debe cambiar la
lógica del juego para arreglar una GUI.

Nada de esto escribe `TouchEnabled` (un cliente no puede), ni `MouseIconEnabled`,
ni `MouseBehavior`, ni toca keybinds o cámara.

## 4. Disguise: sigue pidiendo el arreglo, sin tocar el juego

`Disguise` llama a `host.suppressTouchControls()` 0,6 s después de cada
aplicación, así que disfrazarse no puede dejar al jugador con los botones de
celular. El arreglo en sí ya no escribe estado del juego: solo apaga esas dos
GUIs. Se mantiene el reinicio de las banderas por cuerpo en `CharacterAdded`
(`restoring`, `emotesAppliedToHumanoid`, `animationOverrideApplied`, `cloned`,
`disguisedItems`), que era lo que dejaba el disfraz a medias tras un respawn.

**Lo que no se puede prometer:** las animaciones del avatar dependen del motor de
Roblox y de los módulos del juego. Los errores de la consola que acompañaban la
captura (`ProfileData, Line 32: Toys is not a valid member of RemoteFunction`) son
del propio MM2 en esa versión (servidor 1462): nuestro módulo no toca
`ProfileData` al inyectar, y el menú no engancha `require`.

## 5. Importante sobre la tanda anterior

v193 revierte a propósito dos cosas de v192:

- la ventana flotante del servidor (sustituida por las filas vivas);
- la reescritura del atributo `Device` (sustituida por apagar las dos GUIs de
  controles).

Sigue en pie lo demás: `Rejoin Server` fuera, hops con hueco real, versión única
derivada del `SOURCE_STAMP`, Fling con el roster arreglado (cloneref) y las
skills de `docs/skills/`.

## Verificación de este build

- `node tools/luau/compile.mjs` sobre los ficheros tocados: sin errores.
- `python3 tools/test_server_settings.py` → `PASS`: filas vivas que no se paran
  con la tarjeta apagada, place + subplace, hops con hueco sobre varias páginas,
  fallback cuando todo está lleno, cooldown, sin rejoin.
- `python3 tools/test_v193_build.py` → `PASS`: reglas de fuente de este build.
- `python3 tools/test_mm2_fling_card.py` → `PASS` con `Players` clonado.
- `bash tools/validate.sh` → `EXIT=0`.

**No medido en vivo:** que el endpoint devuelva las páginas con cursor en tu
región, que el teleport lo acepte el servidor, y que el juego no vuelva a
encender sus GUIs táctiles con otro nombre. Si reaparecen los botones, el nombre
de la GUI se lee en la consola de F9 (`PlayerGui`) y se añade a
`DESKTOP_HIDDEN_GUIS`.
