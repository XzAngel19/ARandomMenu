# v181 — GUI que no se rompe, seis emotes y el HackList con su interruptor

Fecha: 2026-11-04 · rama `arena/979b8402-arandommenu`

## 1. Freeze Movements: cambiar de Modo ya no vacía la tarjeta

El fallo no estaba en la lógica de visibilidad por modo (esa siempre estuvo
bien): `addToggleOption`/`addCycleOption` devuelven el **control** dentro de la
fila, mientras que `addNumberOption`/`addRangeOption` devuelven la **fila**. El
código hacía `row.Parent` sobre las dos cosas, así que para las filas numéricas
el «padre» era el **contenedor de opciones** de la tarjeta. Al pasar a `Motion`
se ocultaba el contenedor entero; al volver a `Position Lock` ya no había nada
que mostrar.

- `FreezeMovements.lua`: nuevo `rowFor`/`registerRow` que resuelve la fila real
  (nombre `Option_*` / `Section_*`) y **nunca** registra el contenedor.
- `Widgets.setOptionVisible` ahora resuelve la fila igual —si le pasas el
  control interno, oculta su fila— y **rechaza** el contenedor de la tarjeta
  con un aviso, para que ningún módulo pueda volver a vaciar una tarjeta.
- Regresión nueva: `tools/test_gui_v181.py` cambia de modo cuatro veces
  (`Motion → Position Lock → Motion → Position Lock`) y exige el mismo número de
  filas visibles por modo, altura medida > 0 y el bloque de cada modo.

## 2. Opacity y Menu scale: los dos sliders de tamaño de la GUI

- **Opacity** (`0.15–0.85`) sólo cambiaba `BackgroundTransparency` del marco de
  la ventana: las filas seguían opacas encima, así que el menú se veía como
  tiras sueltas flotando. Ahora `WindowManager.SetOpacity` difumina el árbol
  completo (marco, cabecera y filas) con una base memorizada por objeto, y la
  aplica también a las ventanas que se crean después.
- **Menu scale** (`0.7–1.3`) hacía `refreshLayout(true)` en **cada** paso del
  slider: reflow completo decenas de veces por segundo, con las ventanas
  apilándose mientras se arrastraba. Ahora `ClickGui.ApplyScale()` da respuesta
  inmediata al `UIScale` y el reflow pesado (reclamp de todas las ventanas en el
  nuevo viewport lógico) se ejecuta una sola vez, 150 ms después de soltar.

## 3. HackList: sólo aparece si su opción está activada

`Furniture.lua` calculaba `hudVisible = hudAlways or state.visible`, o sea que el
overlay salía **con el menú abierto** aunque no hubiera nada encendido, y encima
se aceptaba la clave heredada `ClickGUI.ShowHackList` que ningún control
escribía. Ahora:

- la visibilidad depende únicamente de `HackList.Show`;
- el interruptor **Show** guarda el valor en la config (`HackList.Show`), aplica
  `SetAlways` + `SetVisible` y arranca leyendo lo guardado;
- abrir/cerrar el menú nunca enciende el HackList.

## 4. Get All Emotes: seis, Headless incluido, y por el camino del juego

Revisado contra el `.rbxlx` de `XzAngel19/TestingStuff` (`place, source.rbxlx`),
concretamente `Database.Sync.Emotes`, `Modules.ProfileData` y
`Modules.EmoteModule`:

- el catálogo real del juego tiene **seis** entradas que se compran o salen de
  cajas: `ninja` (650), `zen` (800, Rare), `dab` (700), `floss` (750, Rare),
  `zombie` y **`headless`** (`AnimationID 2513664073`, `NotForSale` pero con
  animación propia). Faltaba `headless`;
- `Modules.ProfileData` devuelve **la tabla viva** del perfil que lee la ventana
  de emotes, así que escribir en `Emotes.Owned` es lo que la llena (no es una
  copia: `GenerateEmotes(ProfileData.Emotes.Owned, gui)` es exactamente lo que
  llama el cliente al arrancar);
- la reconstrucción usa el camino del propio juego:
  `EmoteModule.GenerateEmotes(owned, EmoteModule.EmoteGUI)` con respaldo en
  `_G.EmoteFrame`, y después dispara el `InventoryDataChanged` interno
  (BindableEvent) como hace `ChangeInventoryItem`;
- el botón y `Select Emote` siguen usando `Remotes.Misc.PlayEmote:Fire(id)`; el
  `Animate` del juego sólo comprueba que el id exista en `Sync`, por lo que la
  animación se reproduce aunque el servidor no tenga la propiedad.

La prueba `tools/test_mm2_emotes.py` se amplió a seis ids, verifica que el
`GenerateEmotes` se llame con la lista viva y el GUI vivo, y que el ciclo tenga
`Headless` como sexta opción.

## Verificación

`bash tools/validate.sh` → **exit 0**: 84 fuentes compilan, **401** suites PASS,
menú debug 49 cards / 329 filas, release 49 cards con `Calibration` detrás del
consentimiento.

Loader:

```lua
getgenv().WURST_BRANCH = "arena/979b8402-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/979b8402-arandommenu/src/Wurst.lua"))()
```
