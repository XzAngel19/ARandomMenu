# v138.7 — Auto Farm sin paradas, UI de Settings limpia, loader sin caché y launcher sin parpadeo

**Stamp:** `v138.7-20261027-autofarm-flythrough-no-cache`
**Base:** v138.6 (`33a15ed`)
**Alcance:** `src/games/MM2/Other/AutoFarm.lua`, `src/Wurst.lua`,
`src/guis/Wurst/Code/SettingsPage.lua`, `src/guis/Wurst/Code/ClickGui.lua`,
`tools/test_autofarm_motion.py`, `tools/test_mm2_auto_farm.py`,
`tools/test_loader_launcher.py` (nuevo), `tools/gen_full_boot_harness.py`.

## 1. Auto Farm ya no hace la parada corta bajo la moneda

Antes, al llegar a una moneda el farm **frenaba**, se quedaba quieto, pulsaba el
touch y esperaba a que la moneda desapareciera (con un temporizador de "atascado").
Ese alto de menos de un segundo por moneda era justo lo que sobraba.

Ahora las monedas son **waypoints de paso**:

- Al acercarse (9 studs) se pulsa el touch contra `Coin_Server` y se sigue.
- Al pasar por encima (4.5 studs horizontales) la moneda se marca como "barrida"
  y el objetivo pasa a ser **un punto 26 studs más allá**, en la dirección de
  avance actual, para no frenar.
- La moneda recién barrida se salta **2.5 s**, así el cuerpo elige otra en vez de
  frenar sobre la misma. La de atrás se reintenta en cuanto no haya nada adelante.
- **Compromiso de rumbo** (`COURSE_COMMIT_SECONDS = 1.2`): durante ese tiempo solo se
  apuntan monedas que estén delante; antes, el tick siguiente re-apuntaba la moneda
  de atrás y el vuelo ping-pongueaba entre dos pickups (visto y corregido en el
  banco de pruebas).
- Si no hay monedas, o todas están barridas, **no se detiene en el sitio**: sigue
  hasta el punto ya marcado y ahí mantiene la altura (`holdAltitude`).
- Una moneda que sobrevive a **5 pasadas** se manda a la lista negra 6 s (antes
  era un temporizador de estar parado, que ya no existe).

Walk funciona igual: camina a través de la moneda y sigue, sin el `arrived` que
detenía el humanoid.

## 2. Renombrado a "after full bag" (con migración)

- `Fling Murder after reset` → **`Fling Murder after full bag`**
- `Fling Sheriff after reset` → **`Fling Sheriff after full bag`**

Las claves de configuración se derivan de la etiqueta, así que al arrancar se copia
el valor guardado de la clave vieja (`MM2.AutoFarm.FlingMurderafterreset`) a la
nueva y se borra la vieja: nadie pierde el ajuste. Ambas siguen ejecutándose **con o
sin** `Reset When Full Coin Bag` (eso ya era así; ahora el texto lo dice).

## 3. Cosas innecesarias eliminadas

- **Auto Farm:** `Stay Under When Round starts`. Era lo que enterraba también el
  cuerpo en Walk y obligaba a esperar bajo el mapa al empezar la ronda. Sin ese
  toggle, cuando no hay monedas el farm simplemente mantiene la posición/altura.
  Con él se van `holdHiddenUnderMap`, `getHiddenUnderMapPosition`,
  `hideAnchorPosition`, `firstCoinSeenThisRound`, `STUCK_SECONDS`/`stuckPart`.
- **UI Settings:** `Random Card Order` y `Rainbow`. El barajado de tarjetas sigue
  (sin interruptor), y el "Rainbow" del HUD (otra ventana) no se toca.
- La tarjeta de Auto Farm pasa de 11 a **10 opciones** y su descripción ya no
  menciona el modo de espera bajo el mapa.

## 4. Loader: sin caché de fuentes y una sola petición

Antes `fetchRepositorySource` hacía, **por cada fuente**, `isfile` + `readfile` del
`Wurst/src/...` guardado y, si faltaba, la descarga; además escribía el archivo y un
`Wurst/.stamp`. Eran ~93 comprobaciones de disco antes de arrancar.

Ahora: **bundle → memoria → un `HttpGet`**. Nada de caché por archivo.

- `readCachedSource`, `writeCachedSource`, `ensureSourceFolders` y
  `sweepStaleSources` se eliminan.
- `state.purgeLegacySourceCache()` borra en segundo plano (`task.spawn`) la carpeta
  legada `Wurst/src` y `Wurst/.stamp` de versiones anteriores; no bloquea el arranque.
- La caché de **assets** (fuentes/imágenes vía `getcustomasset`) se mantiene: esa sí
  acelera los siguientes arranques y es necesaria para el atlas de texto.

## 5. El "círculo con tres rayas" ya no aparece antes del menú

Era `MobileMenuButton` (52×52, `UICorner` 1 → círculo, texto `≡`), creado con
`Visible = state.isMobile`. En móvil aparecía **al inyectar**, varios segundos antes
de que existiera el menú.

- Se crea con `Visible = false`.
- `refreshLauncherVisibility()` exige `state.menuReady == true`.
- `state.menuReady` se pone cuando la última sección termina de inicializar (justo
  al imprimir `Load complete`), con un `task.defer` para que el frame ya esté pintado.
  Después de eso se llama a `state.refreshLauncher()`.

## 6. Pruebas

- `tools/test_autofarm_motion.py` (4 suites, física simulada con gravedad):
  - Below barre la moneda (**pasa a menos de 2.6 studs**, dentro del hitbox 4×8×4) y
    mantiene altura, incluso con el tick congelado 60 frames;
  - Walk deja el cuerpo caminable y avanza;
  - una caída a Y = −600 se recupera dentro del mapa;
  - **fly-through**: con 4 monedas el farm recoge ≥ 3 y **nunca frena más de 20
    frames seguidos** (≈0.33 s); con una moneda que nunca paga, el cuerpo sigue
    moviéndose >70 de 120 frames en vez de quedarse plantado.
- `tools/test_loader_launcher.py` (nuevo): sin caché de fuentes, purga en
  `task.spawn`, launcher oculto al crearse y liberado por `state.menuReady`, y
  Settings sin `Random Card Order`/`Rainbow` conservando paleta, opacidad y dock.
- `tools/test_mm2_auto_farm.py`: nombres nuevos, migración de claves, fly-through y
  ausencia de las cosas eliminadas.
- `tools/gen_full_boot_harness.py`: exige las dos opciones nuevas, la ausencia de
  `after reset`/`Stay Under` y `state.menuReady == true` tras el arranque.
- `validate.sh`: **93 fuentes**, **66 suites**, boot `failures=0`, menú 52 tarjetas /
  release 51, Auto Farm con 10 opciones.
