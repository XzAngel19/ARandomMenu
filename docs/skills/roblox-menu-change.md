---
name: roblox-menu-change
description: Cambiar una tarjeta o una opción de este menú de Roblox sin romper el guardado, el arranque ni los controles del jugador. Úsala cuando la petición sea renombrar, mover, arreglar o añadir algo de una tarjeta (Utilities, Exploits, Render, MM2, universal) o cuando haya que leer el place real de un juego para saber cómo expone sus datos.
---

# Cambiar una tarjeta de este menú (Roblox / Luau)

Fuentes de referencia usadas para escribirla (todas de GitHub):

- `Roblox/creator-docs` — documentación oficial de API (propiedades, remotes,
  `PlayerGui`, `UserInputService`, `TeleportService`).
- `luau-lang/luau` — sintaxis y comprobación de tipos (`luau-analyze`).
- `anthropics/skills` (carpeta `skills/skill-creator`) — formato de skill
  (frontmatter `name` + `description`, fases, puertas de verificación).
- Los catálogos tipo `everything-claude-code` / `antigravity-awesome-skills`
  sirven para descubrir skills, pero aquí manda el repo: cada skill nueva se
  escribe en `docs/skills/` con el formato de esta carpeta.

## Fases

### 1. Localizar la fuente de verdad

- La tarjeta vive en `src/games/<juego>/<Categoría>/<Nombre>.lua` o en
  `src/games/universal/…`.
- Se carga desde `src/libraries/Manifest.lua` (lista y categoría) y se empaqueta
  en `src/libraries/bundle.lua` (generado, nunca a mano).
- Gui/helpers del menú: `src/guis/Wurst/Code/{Widgets,Cards,SettingsPage,WindowManager}.lua`.
- El módulo corre dentro del entorno del menú: `create`, `Theme`, `ScreenGui`,
  `state`, `notify`, `TaskManager`, `PRODUCT`, `LocalPlayer`, `Players` son
  globales. El `host` añade `host.create`, `host.PRODUCT`, `host.BUILD_LABEL`,
  `host.suppressTouchControls`, `host.TaskManager`, `host.featureConnections`.

### 2. La clave de configuración es sagrada

`Widgets.addToggleOption` deriva la clave de guardado del **nombre visible**:

```lua
local optionKey = feature.configKey .. "." .. labelText:gsub("%W", "")
```

Por eso un renombrado cambia la clave y el jugador pierde su ajuste. Solo se
acepta cuando el ajuste es cosmético y su valor por defecto es el mismo; si no,
se conserva la clave (patrón `addColorOption(..., keyText)`) o se migra en el
`init` del módulo (patrón `MM2.BlurtRoles.InstantRoles → MM2.Notifications.InstantRoles`).
Los **keybinds** no se tocan nunca al renombrar.

### 3. Escribir contra datos reales del juego

Antes de «arreglar la detección», mirar cómo el juego publica el dato. Para
Murder Mystery 2, leído del place real (`place, source.rbxlx`):

- `ReplicatedStorage.Remotes.Gameplay.GetCurrentPlayerData` (RemoteFunction) y
  `…Gameplay.PlayerDataChanged` (RemoteEvent) devuelven
  `{[nombre o UserId] = {Role = "Murderer"|"Sheriff"|"Hero"|"Innocent", Dead = bool}}`.
- Los roles son exactamente `Innocent`, `Sheriff`, `Murderer`, más `Hero` y los
  modos especiales.
- El HUD móvil del juego depende de `UserInputService:GetLastInputType() == Touch`
  y de `PlayerGui:GetAttribute("Device")` (`"PC"`, `"Phone"`, `"Tablet"`,
  `"Gamepad"`). Si aparece el HUD de celular en un PC con pantalla táctil, el
  dato que hay que corregir es ese atributo, no nuestros controles.

### 4. `cloneref` rompe las comparaciones

El menú guarda `Players = cloneReference(game:GetService("Players"))`. Un clon
**nunca** es igual al original, así que `player.Parent == Players` es falso para
todos los jugadores reales. Para decidir «esto es un jugador» se pregunta a la
instancia:

```lua
local ok, className = pcall(function() return player.ClassName end)
if not ok or className ~= "Player" then return false end
local parentOk, parent = pcall(function() return player.Parent end)
return parentOk and parent ~= nil
```

Este fue el fallo exacto que dejó el roster del Fling vacío en v191.

### 5. No tocar el esquema de entrada

- Nunca escribir `UserInputService.TouchEnabled`, `MouseIconEnabled` ni
  `MouseBehavior`.
- Un portátil con pantalla táctil reporta `TouchEnabled = true`: se trata como
  escritorio (`TouchEnabled and not KeyboardEnabled`) y se oculta el `TouchGui`
  de Roblox con `host.suppressTouchControls()`.
- Cualquier cosa que se muestre en pantalla y no sea el menú (overlays) se
  cuelga del `ScreenGui` del menú, no de `CoreGui`.

### 6. Verificar

```bash
node tools/luau/compile.mjs src/...            # sintaxis
python3 tools/test_<tarjeta>.py                # comportamiento con mocks
python3 tools/card.py check                    # catálogo de tarjetas
python3 tools/build_bundle.py --stamp <stamp>  # bundle al día
bash tools/validate.sh                         # todo, ~3 min
```

`state.listControls[key]` y `state.valueControls[key]` (`{apply, default}`) son
lo que el harness puede inspeccionar: **no** asumir filas en `card.Options`.

## Puertas de verificación

- La suite nueva imprime `PASS <tarjeta>: <qué probó>`.
- `card.py check` sigue diciendo `catalog OK`.
- `build_bundle.py --check` dice que el bundle es actual con el stamp nuevo.
- `validate.sh` → `EXIT=0`.

## Anti-patrones

- Comparar instancias clonadas con las reales (ver fase 4).
- `GetValue()` de `StatsItem` o `game:HttpGet` dentro del juego sin pasar por el
  ejecutor.
- Poner `Name` visible nuevo y dejar el `ConfigKey` viejo sin querer (o al
  revés: renombrar y perder el guardado sin decirlo).
- Escribir GUIs propias en `CoreGui` sin limpiar al `destroy()`.
