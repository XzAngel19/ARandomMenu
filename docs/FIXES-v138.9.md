# v138.9 — Orden alfabético, un solo catálogo, `card.py` y Fling con ping

**Stamp:** `v138.9-20261027-alphabetical-one-catalog-fling-ping`
**Base:** v138.8 (`91048be`)

## 1. Las tarjetas vuelven a estar en orden alfabético

Se va todo el andamiaje del orden aleatorio de v138.6–v138.8:

- `Cards.lua`: fuera `sessionSeed`, `nextRandomRank`, `randomState`, el atributo
  `FeatureSortRank`, `FeatureSortOrder` y el mapa `ordered` (la lista curada de
  posiciones). Ese mapa es el **punto 3** de la lista de arquitectura: con el orden
  alfabético ya no decide nada, sólo existía para "colocar" tarjetas a mano.
- `ClickGui.sortCategoryRows` ordena por `FeatureSortName` (el nombre en
  minúsculas), con el nombre de la fila como desempate para que dos tarjetas con el
  mismo nombre no bailen entre refrescos.
- Se ordena en **cada ventana** en el momento de colocar la tarjeta, así que el
  orden es siempre el mismo: `Anti Fling, Anti Void, Auto Farm, Auto Unbox, …`.

El harness comprueba ahora el invariante real leyendo los cuerpos de las ventanas:
slots 1..n sin huecos y claves no decrecientes.

## 2. Un solo catálogo (punto 1)

`src/libraries/Manifest.lua` es **el único** sitio donde se declara un módulo. Se
elimina el `fallbackManifest` de `Wurst.lua` (~160 líneas de copia, 6.9 KB): era la
causa de que un fallo de descarga arrancara *otro* menú, distinto al probado. Si el
catálogo no se puede cargar ahora el arranque **para** con un error claro, en vez de
inventarse un menú.

## 3. Un solo sitio para categorías (punto 2)

El catálogo también manda sobre las ventanas:

```lua
categories = { order = {...}, aliases = {...}, default = "Utilities" },
cards = { ["Walk Fling"] = "Exploits", ... },   -- tarjeta -> ventana
```

- `Wurst.lua` arranca con las tablas **vacías** y las rellena desde el catálogo
  (`OFFICIAL_CATEGORIES`, `CATEGORY_ALIASES`, `FEATURE_CATEGORIES`).
- `ClickGui.lua` usa `state.categories` (misma fuente) en vez de su propia copia con
  alias distintos; su tabla local queda sólo como último recurso.
- Resultado: una ventana nueva = **una línea** en `categories.order` de
  `Manifest.lua`; la GUI la crea sola cuando hay una tarjeta dentro.

## 4. `tools/card.py` — alta y baja en un comando (punto 4)

```
python3 tools/card.py list [--category Combat]
python3 tools/card.py add "Combat Logger" --category Combat --stub
python3 tools/card.py add "Auto Thing" --game MM2 --category Utilities --stub
python3 tools/card.py window "Coin ESP" Render
python3 tools/card.py remove "Combat Logger" --delete-file
python3 tools/card.py check
```

- Escribe siempre el catálogo en forma canónica y ordenado por nombre, así dos altas
  seguidas nunca chocan en medio de la lista.
- `--stub` crea un módulo compilable con `init`/`destroy` y su tarjeta ya
  registrada en la ventana correcta.
- `--game MM2|VD|BedFight|X2Duels|TRS` registra en la lista de carga del juego.
- `check` (también corre en `validate.sh`) verifica ficheros, duplicados, categorías
  desconocidas y módulos de juego que faltan.

Se añade además `tools/test_manifest_sync.py` comprobando que **toda** tarjeta que
crea un módulo tiene ventana en el catálogo (si no, caería en Utilities y sería
imposible de encontrar).

## 5. Fling: más potencia, ping y objetivos rápidos

La coreografía de YARHM se queda exactamente igual (poses FPos + `9e7`/`9e8` +
`EpixVel`); lo que se añade alrededor es lo que faltaba cuando el rival se movía o
había 300 ms de ping:

| Opción | Por defecto | Qué hace |
| --- | --- | --- |
| **Power** | 4 (3 = YARHM exacto) | Escala a la vez la velocidad de las poses y el `EpixVel`. Con 6 el pin va a 1.8e9. |
| **Duration** | 3 s | Cuánto tiempo se siguen escribiendo poses (antes 2 s). |
| **Prediction** | 0.15 s | Adelanto extra sobre el `ping/2` automático. |
| **Retries** | 1 | Pasadas extra si el rival no se movió (usa su otra parte con boost temporal ×1.5). |

Interno:

- **Adelanto por ping**: cada pose se escribe donde el rival *estará*
  (`velocidad plana × (ping/2 + Prediction)`), usando `GetNetworkPing` (acepta
  segundos o milisegundos). Es lo que hace que a 300 ms el contacto llegue.
- **Re-resolución por pose**: se vuelven a leer `Character`, `Humanoid`, `RootPart`
  y `Head` en cada pose, así un respawn o un ragdoll no termina el fling.
- **Mínimo de 12 poses** antes de decidir que ya vuela: un solo frame de
  replicación atrasada ya no corta el fling a la mitad.
- **Segunda pasada** automática con la otra parte del cuerpo y boost ×1.5 cuando la
  primera no lo movió (la "rescue impulse" sigue detrás, como último recurso).
- El aviso final informa de los reintentos: `fling: X sent flying (…, 2 retries)`.

Pruebas nuevas en `tools/test_fling_skid.py`: el adelanto a 300 ms de ping (≥22
studs), `Power` escalando pose y pin, y una víctima inmóvil recibiendo la segunda
pasada.

## 6. Verificación

- `bash tools/validate.sh`: **91 fuentes Lua**, **66 suites**, `card.py check`,
  boot `failures=0`, menú **52** tarjetas / release **51**, API cruzada OK.
- `tools/card.py` probado de ida y vuelta (alta + compilación + baja) sin dejar
  rastro en el árbol.
