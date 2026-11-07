# v192 — Server Settings sin Rejoin, hops con hueco real, overlay de servidor, versión única y roster del Fling arreglado

Build: `SOURCE_STAMP = "v192-20261107-server-hop-overlay"`, que se muestra como
**`0.192`** en los títulos de ventana y **`0.192 Release`** en la línea de
producto (las dos etiquetas salen del mismo sitio).

## 1. El Fling ya ve a todos los jugadores (causa raíz encontrada)

**Síntoma:** el Fling no detectaba ningún target; la lista salía vacía y los
botones de rol contestaban «no hay nadie».

**Causa:** el menú guarda `Players = cloneReference(game:GetService("Players"))`.
En los ejecutores que exponen `cloneref`, ese `Players` es un **clon**, y un clon
nunca es igual a la instancia original. v191 usaba como filtro:

```lua
if not player or player == localPlayer or player.Parent ~= playerService then
    return false
end
```

`player.Parent` es el servicio **real**, `playerService` es el **clon** → la
condición se cumplía siempre → `canFling` devolvía `false` para todos → roster
vacío. v190 no tenía esa comparación, y por eso v190 funcionaba.

**Arreglo:** el guardia ya no compara tablas, pregunta a la instancia
(`ClassName == "Player"` y `Parent ~= nil`). El mock de
`tools/test_mm2_fling_card.py` reproduce el cloneref a propósito (jugadores con
`Parent = realPlayers`, módulo leyendo `Players` clonado) y el roster sigue
devolviendo los tres vivos.

**Detección de roles:** se revisó el place real de MM2 (`place, source.rbxlx`).
Los roles no viven en `RoundInfo`/`GetPlayerRole` (no existen): se publican por
`ReplicatedStorage.Remotes.Gameplay.GetCurrentPlayerData` y `PlayerDataChanged`
como `{[nombre o UserId] = {Role = "Innocent"|"Sheriff"|"Hero"|"Murderer", Dead = bool}}`.
`base.lua` ya consumía ese par; ahora además resuelve claves numéricas
(UserId) con `Players:GetPlayerByUserId`, que antes no tenían rama y dejaban la
tabla entera sin rol.

## 2. Fuera `Rejoin Server`

La acción desapareció de la tarjeta (y con ella el helper `rejoin`). Duplicaba el
menú de Roblox y cada pulsación accidental echaba al jugador de la ronda.

## 3. Hops con lógica real

v191 pedía la lista con `sortOrder=Asc|Desc` y elegía de un pool que **incluía
servidores llenos**: el «hop» caía en un 1/12 o fallaba porque un 12/12 rechaza
la entrada.

Ahora:

- el endpoint se pide con `excludeFullServers=true`;
- un candidato solo existe si `playing < maxPlayers` (hueco real);
- **smallest** ignora las instancias vacías (0/12 no es «el más pequeño», es una
  partida que no existe) y elige el servidor con menos jugadores *con gente*;
- **largest** es el más lleno al que todavía se puede entrar: en un place de 12,
  **11/12**, exactamente el caso que describió el jugador;
- **random** mezcla las dos páginas (`Asc` + `Desc`) para no quedar sesgado al
  extremo vacío;
- el aviso dice la verdad: `Hopping to the largest server: 11/12 players…`.

## 4. `Show server info` abre una overlay

Overlay propio (`WurstServerInfo`) colgado del ScreenGui del menú, con cabecera
arrastrable y cierre que apaga la opción. Filas:

| Fila | Dato |
| --- | --- |
| Job ID | el `game.JobId` completo |
| Players | `n / maxPlayers` |
| In server | nombres de los jugadores |
| Uptime | `workspace.DistributedGameTime` (tiempo del **servidor**, no de tu sesión) |
| Server clock | `workspace:GetServerTimeNow()` en UTC |
| Place | `game.Name` + `game.PlaceVersion` |
| You | tu nombre y UserId |
| Build | `0.192 Release` |
| Round | fase de ronda de MM2, cuando la hay |

Se refresca cada `Refresh every` segundos y solo mientras la tarjeta está
encendida; al apagar la tarjeta la overlay se destruye.

## 5. Controles de celular: qué pasaba de verdad

Del place de MM2: su HUD táctil se activa con
`UserInputService:GetLastInputType() == Touch` o con
`TouchEnabled and not KeyboardEnabled`, y el modo queda en
`PlayerGui:GetAttribute("Device")` (`"PC"`, `"Phone"`, `"Tablet"`, `"Gamepad"`)
— es el atributo que leen todas sus GUIs. En un portátil con pantalla táctil
`TouchEnabled` es `true`, así que el juego puede quedarse en modo teléfono y
sacar los botones `Lanzar / Equipar / Beneficio`.

El menú **no** escribía `TouchEnabled` (no se puede) ni cambiaba el esquema de
entrada; lo que faltaba era deshacer ese estado ajeno. Añadido
`suppressTouchControls()` (`src/Wurst.lua`), que solo actúa en una máquina con
teclado **y** ratón:

1. `PlayerGui.TouchGui.Enabled = false` (y otra vez si el juego lo recrea);
2. si `PlayerGui:GetAttribute("Device")` dice `Phone`/`Tablet`, se pone en `PC`,
   que es lo que el propio MM2 hace en un PC.

No toca keybinds, ni el icono del ratón, ni `MouseBehavior`, ni el esquema de
entrada. En un móvil real o en una tablet sin teclado no hace nada.

## 6. Disguise

- La opción se llama **`Use target movement animations if able`** (el renombrado
  es solo visible: el ajuste cae a su valor por defecto una vez porque la clave
  de guardado se deriva del nombre; su valor por defecto ya era el mismo).
- Tras cada aplicación pide `host.suppressTouchControls()`: disfrazarse ya no
  puede dejar al jugador con el esquema táctil.
- Al reaparecer se reinician las banderas por cuerpo
  (`restoring`, `emotesAppliedToHumanoid`, `animationOverrideApplied`) y se
  vacían `cloned`/`disguisedItems`. Antes sobrevivían al respawn, así que la
  siguiente aplicación creía que los emotes/animaciones ya estaban escritos y el
  disfraz salía a medias: ese era uno de los «muchos problemas».

**Pendiente de medir en vivo:** que un avatar concreto cargue todos sus clips con
la caché caliente, y cuántos respawns aguanta sin re-aplicar. Los mocks prueban
la lógica, no el motor de animación de Roblox.

## 7. Skills de referencia

Nuevas, en `docs/skills/`:

- `agent-run-efficiency.md` — cómo cerrar una tanda entera (código, pruebas,
  bundle, docs, push) en un solo run.
- `roblox-menu-change.md` — cómo cambiar una tarjeta sin romper guardado,
  arranque ni controles, con el formato de skill del catálogo `anthropics/skills`
  (`skills/skill-creator`) y las fuentes `Roblox/creator-docs` y `luau-lang/luau`.

## Verificación de este build

- `node tools/luau/compile.mjs` sobre los ficheros tocados: sin errores.
- `python3 tools/test_server_settings.py` → `PASS` (readout + uptime, overlay,
  clipboard, smallest/largest/random con hueco real, cooldown, fallos, sin
  rejoin).
- `python3 tools/test_mm2_fling_card.py` → `PASS` con `Players` clonado.
- `python3 tools/test_v192_build.py` → `PASS` (reglas de fuente; v193 lo sustituyó
  por `tools/test_v193_build.py`).
- `bash tools/validate.sh` → `EXIT=0` (fuentes, suites, catálogo, release).

**No medido:** nada de esto prueba física de Roblox, aceptación del teleport por
parte del servidor, ni que el motor de animación cargue cada clip. Eso se mide
en partida.
