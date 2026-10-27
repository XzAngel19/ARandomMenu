# v138.6 — Auto Farm (Below y Walk) y orden aleatorio del menú

**Stamp:** `v138.6-20261027-autofarm-motion-random-menu`
**Base:** v138.5 (`9d15167`)
**Alcance:** `src/games/MM2/Other/AutoFarm.lua`, `src/guis/Wurst/Code/Cards.lua`,
`src/guis/Wurst/Code/ClickGui.lua`, `src/guis/Wurst/Code/SettingsPage.lua`,
`tools/test_autofarm_motion.py` (nuevo), `tools/test_mm2_auto_farm.py`,
`tools/gen_full_boot_harness.py`.

## 1. Auto Farm se caía al vacío en vez de seguir volando

El vuelo de **Below (Hitbox)** era un `BodyVelocity`/`AssemblyLinearVelocity`
escrito **desde el tick del Heartbeat**, que en Roblox corre **después** del paso
de física. Entre una escritura y la siguiente, la gravedad del paso acumulaba
velocidad hacia abajo: el cuerpo no "volaba", **se hundía** poco a poco hasta
salirse del mapa. Y había un segundo agravante que lo hacía mucho peor: cuando no
había moneda objetivo, el código "rebasaba" el punto de referencia del round a la
posición actual del cuerpo (`homeCFrame = CFrame.new(root.Position)`), **incluso
estando ya debajo del mapa**; como el objetivo de altura se calculaba como
`homeCFrame - 7`, cada tick bajaba la referencia y con ella el objetivo: una
espiral autoalimentada hacia el vacío. En el banco de pruebas se veía exactamente
así: el cuerpo se estabilizaba 7 studs más abajo cada vez.

### Lo que hace ahora

- **`applyBelowControl`** corre en `RunService.Stepped`, es decir **antes** del paso
  de física, y es quien vuela: velocidad horizontal hacia el destino y un término
  vertical proporcional (`delta.Y * 10`, limitado al Farm Speed) que **cancela la
  gravedad** en lugar de dejar que se acumule. El tick de tareas ya solo **elige el
  destino** (`moveTowards` guarda `hoverTarget`), así que un tick ocupado (secuencia
  de bolsa llena, `busy`) ya no deja al cuerpo sin control.
- **`clampBelowTarget`** limita el destino a `[home - MAX_BELOW_DEPTH, home + 80]` y
  **`floorBudgetY`** nunca deja pedir una altura por debajo de
  `FallenPartsDestroyHeight + 40`.
- **`recoverFromVoid`**: si el cuerpo baja de
  `max(destroyHeight + 40, home - VOID_RECOVER_DEPTH)`, se le devuelve **dentro** del
  mapa (Below: debajo del suelo en el punto de inicio del round, sin perder NoClip;
  Walk: de pie sobre el suelo del round).
- El "rebase" del punto de referencia solo ocurre **con el cuerpo sobre el mapa**
  (`not hiddenUnderMap and bodyOnMap`), nunca desde dentro del suelo.
- Ya no se escribe `CFrame` para volar (eso era lo que provocaba los kicks
  `Invalid position` 267): solo velocidad, y `CFrame` únicamente en el rescate.

## 2. Walk Method no hacía nada

Tres causas concretas:

1. **"Stay Under When Round starts" enterraba también el modo Walk.** Con el toggle
   por defecto en ON, al empezar la ronda el personaje se metía bajo el mapa con
   NoClip + `PlatformStand`, y luego "salía" con un raycast que, lanzado desde
   dentro del suelo, no encontraba suelo y dejaba el cuerpo en geometría. Con
   `Humanoid:Move` en ese estado no se mueve nada. Ahora el toggle **solo aplica a
   Below**: en Walk el personaje se queda de pie donde apareció.
2. **El cuerpo no se normalizaba al entrar en Walk.** Si antes hubo una sesión
   Below (o el hold bajo el mapa), quedaban `PlatformStand = true`, `AutoRotate =
   false`, NoClip en todas las partes y el hitbox 4x8x4: un cuerpo así **ignora
   `Humanoid:Move`**. Ahora `engage()` normaliza una vez por sesión de farm:
   devuelve colisiones, tamaño del root, `PlatformStand = false`, `AutoRotate =
   true`, `Sit = false` y fija `WalkSpeed` (el slider) en cada tick.
3. **`restoreCharacter` se ejecutaba cada tick sin moneda** y devolvía al personaje
   a casa una y otra vez (tirón atrás cada vez que se recogía una moneda). En Walk
   ya no se llama: solo se detiene el movimiento.

Además, si `Humanoid:Move` no reduce la distancia durante **2 s** (controlador del
juego roto, muro, borde), se aplica durante **1 s** un **carry horizontal por
velocidad** que sí desplaza el cuerpo, con salto incluido. Sin teleports.

## 3. Orden del menú: aleatorio, no alfabético

El orden dentro de cada ventana lo decidían los slots explícitos y, en caso de
empate, **el nombre en orden alfabético** — de ahí que la mitad de las tarjetas
apareciera en orden alfabético.

- `Cards.lua` sortea un **rango por tarjeta** con un LCG sembrado por sesión
  (`randomState = seed * 16807 mod 2^31-1`). Cada tarjeta guarda su rango en el
  atributo `FeatureSortRank`.
- `ClickGui.sortCategoryRows` ordena por ese rango cuando
  `state.randomCardOrder ~= false` (por defecto **aleatorio**), y vuelve al orden
  curado si se apaga.
- El orden es **estable durante la sesión**: se sortea una vez, así que refrescar la
  UI no reordena nada bajo el cursor. Cada arranque del script da un orden distinto.
- Nuevo toggle en **Settings → Random Card Order** (ON por defecto) que reordena en
  el acto (`ClickGui.restack()`).
- El orden de las **ventanas** (Combat, Exploits, Utilities, World, Render, Blocks,
  Items) no se toca: es intencional.

## 4. Pruebas

### `tools/test_autofarm_motion.py` (nuevo, 4 suites)

Arranca el módulo real con un modelo de física: por frame ejecuta `Stepped`, aplica
**gravedad** (196.2) e integra el root, y después el tick con su `deltaTime`.

1. **Below** vuela 40 studs hasta la moneda, se queda 3 studs debajo (hitbox 4x8x4),
   `PlatformStand` on, y **nunca** baja del presupuesto de profundidad. Incluye una
   prueba de **tick congelado** (60 frames sin tick, como cuando `busy` está activo):
   el cuerpo **sigue en el aire**.
2. **Walk** deja el cuerpo caminable (`PlatformStand` off, `AutoRotate` on, hitbox
   normal, `WalkSpeed` = slider) y entrega una dirección real al humanoid; cuando el
   humanoid no mueve el cuerpo, el carry por velocidad lo desplaza (X > 4).
3. Tirar el cuerpo a Y = -600 se detecta y se recupera por encima del destroy height.
4. "Stay Under" en Walk **no** entierra el cuerpo (se queda en el suelo, Y ≥ 10.5).

### Resto

- `tools/test_mm2_auto_farm.py` actualizado: contratos del controlador en
  `Stepped`, `clampBelowTarget`/`floorBudgetY`/`recoverFromVoid`, el rebase
  protegido, el gating de Stay Under y el carry de Walk.
- `tools/gen_full_boot_harness.py`: el orden del menú se comprueba como
  **permutación** por ventana (cada tarjeta con su slot), los slots deben seguir el
  **rango aleatorio**, todos los rangos distintos y **al menos una ventana tiene que
  no estar en orden alfabético** (si no, falla: el menú no puede volver a ser
  alfabético).
- `validate.sh`: **93 fuentes**, **65 suites**, boot `failures=0`, 52 tarjetas /
  release 51.
