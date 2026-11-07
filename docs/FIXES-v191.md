# v191 — Doce ajustes de menú, Fling completo y Server Settings

Fecha: 2026-11-07. Stamp: `v191-20261107-server-settings-fling-hold`.
Rama de la sesión: `arena/7446e4e3-arandommenu` (desde el tip v189
`9b06cca` de `arena/05c45e27-arandommenu`).
Etiqueta visible en el menú: **Version 0.191**.

Peticiones del jugador en esta tanda:

1. Llamar de otra manera el módulo `Arrows`.
2. Que ese módulo también modifique el pequeño botón de **Pin**.
3. `Opacity` debe afectar sólo al **fondo**, no a todo el menú.
4. Llamar la versión **0.190** (se implementó como etiqueta `Version 0.NNN`; este
   build dice **Version 0.191**).
5. **Fling** de MM2 completo (Murderer / Sheriff / …) y **al máximo poder**.
6. **Disguise** debe cargar al inyectar (a veces «failed to load»).
7. **Blurt Roles** como botón instantáneo, sin `Blurt Now`.
8. `Spider` → **Wall Crawling**.
9. `Swim` → **Air Swim**.
10. Mejorar **Notifications**.
11. **Knife Stab**: opción **Hold Mouse** (sin kill aura automático).
12. Nueva tarjeta **Server Settings** en **Utilities**.

---

## 1–2. `Arrows` → `Player Pointers`, y el Pin con su color

`src/games/universal/Render/Arrows.lua` y `src/guis/Wurst/Code/WindowManager.lua`.

- El nombre visible de la tarjeta es **`Player Pointers`**. Sólo cambia el
  nombre: `ConfigKey = "Universal.Arrows"`, su estado guardado y su keybind
  siguen siendo los mismos (precedente de v179/v190).
- El botón de bloquear ventana (`pin`) ya no usa `Theme.enabled`: se crea con el
  token **`arrows`**, el mismo de los chevrones, y lleva detrás un `PinTint`
  enlazado a ese token. Resultado: cambiar el color de las flechas cambia
  también el chip de Pin (icono y tinte al estar fijado).
- En Ajustes, la fila de paleta `Arrows` pasa a llamarse **`Buttons`**, porque
  ahora pinta los botones de ventana además de las flechas. La fila lleva
  `key = "Arrows"` y `addColorOption` acepta un `keyText`, así que el color
  guardado en `UISettings.Arrows` **no se pierde** con el renombrado.

## 3. `Opacity` = sólo el fondo

`src/guis/Wurst/Code/WindowManager.lua` y `SettingsPage.lua`.

Antes `SetOpacity` escribía `root.GroupTransparency = 1 - alpha` en el
`CanvasGroup` de cada ventana: se difuminaba la ventana **entera**, título,
textos e iconos incluidos, y con valores bajos el menú se volvía ilegible.

Ahora:

- `root.GroupTransparency` queda en `0` siempre.
- El panel se marca con el atributo `WurstPanelSurface` y `SetOpacity` escribe
  `root.BackgroundTransparency = 1 - alpha`: **sólo el fondo** se transparenta.
- El texto y los controles mantienen opacidad completa en cualquier posición del
  slider (la descripción del ajuste lo dice).

## 4. Etiqueta de versión

`SettingsPage.lua` deriva el número del `SOURCE_STAMP`
(`v191-…` → `Version 0.191`) y lo usa en el título de la ventana de ajustes. El
stamp interno sigue siendo el de siempre para el bundle y las cachés.

## 5. Fling de MM2 completo, al máximo poder

`src/games/MM2/Other/Fling.lua` (reescrito sobre `FlingEngine.lua`).

- Vuelven los botones del Fling histórico: **Fling Murderer**,
  **Fling Sheriff**, **Fling All Innocents**, la lista **Fling target** (jugadores
  vivos ordenados por rol: Murderer → Sheriff/Hero → Innocent) y el botón
  **Fling**, más **Auto Fling Selected Target**.
- El rol se resuelve con los datos de la ronda y, si faltan, con la herramienta
  que el servidor replica (cuchillo = Murderer, pistola = Sheriff), que es lo que
  hacía falta para que «Fling Murderer» no dijera «nadie encontrado».
- **Poder máximo:** `Power` sale en **12** (el máximo que acepta el motor, 4× la
  velocidad de pose de YARHM 9e7/9e8) y `Retries` en **3** (el máximo).
- Nunca finge al inyectar: la selección guardada se recuerda pero no dispara.
- Con **Anti Fling** activo todos los caminos se niegan y avisan.

No se mezclan motores: el histórico (`src/libraries/Fling.lua`) sigue sin
volver; la tarjeta usa `state.mm2PerformFling`, que es el que conoce
`flingBoost`, el pin EpixVel y los reintentos.

## 6. Disguise carga al inyectar

`src/games/universal/Other/Disguise.lua`.

El «failed to load animation with sanitized ID …» lo imprime el script `Animate`
del juego cuando el asset no está descargado todavía: se rinde en el primer
intento y no vuelve a pedirlo hasta que el personaje reaparece (de ahí el
«reinicia el personaje para verlo»). Tres guardas:

1. **Precarga**: antes de escribir los slots se crean `Animation` temporales con
   los ids y se pasan por `ContentProvider:PreloadAsync`, para que el primer
   intento del script ya tenga el asset en caché. Es silencioso y se hace una vez
   por id.
2. **Espera al rig**: si el script `Animate` aún no replicó, se espera hasta ~6 s
   en vez de responder «ese avatar no expone animaciones».
3. **Reintento**: si la pose queda congelada, se reinicia el script (y se
   reescriben los ids una vez) hasta tres veces antes de caer al set propio del
   rig.

## 7. Blurt Roles = botón instantáneo

`src/games/MM2/Fun/BlurtRoles.lua`.

La tarjeta pasa a ser de tipo **acción**: al pulsarla se dicen los roles en el
chat público **al instante**. La fila `Blurt now` se eliminó y el
comportamiento automático vive en la opción **`Auto blurt`** (apagada por
defecto), junto con `Delay`, `Repeat on change` y `Fake Blurt Roles`.

## 8–9. `Spider` → `Wall Crawling`, `Swim` → `Air Swim`

Sólo el nombre visible. `Spider` pasa a declarar explícitamente
`configKey = "Universal.Spider"` (antes lo derivaba del nombre, y el renombrado
habría huérfano el estado guardado); `Swim` ya tenía `ConfigKey =
"Universal.Swim"`. Se actualizaron también las entradas del catálogo
(`Manifest.lua`).

## 10. Notifications

`src/games/MM2/Other/Notifications.lua` y el toast de `src/Wurst.lua`.

- El aviso de **Murderer cercano** ahora trae **dirección** (N/NE/E/SE/S/SO/O/NO),
  distancia exacta y un extra «VERY close» cuando está muy encima.
- **Radio** (10–120 studs, por defecto 30) y **enfriamiento** (2–30 s, por
  defecto 8) configurables.
- Nueva alerta **Sheriff Down** (cuando el sheriff/héroe cae, que es cuando la
  pistola queda suelta).
- Toasts: color por tipo (`danger` rojo, `good` verde, resto acento), duración
  según la longitud del texto (2,6–7 s) y pila máxima de 5 para que no tapen la
  pantalla.

## 11. Knife Stab: `Hold Mouse`

`src/games/MM2/Blatant/KnifeAura.lua`.

Con `Hold Mouse` activo el bucle automático **no** golpea; se instala un
`UserInputService.InputBegan` que, al **clic** (o toque), busca el objetivo vivo
más cercano dentro de **`Aura Range`** y manda el mismo `HandleTouched` que el
aura. Detalles:

- El alcance es exactamente el del kill aura (`Aura Range`, 7–30 studs).
- El ritmo manual es el del cuchillo (0,3 s), no el intervalo lento del aura.
- Se ignora el clic si el juego lo procesó, si hay un cuadro de texto enfocado o
  si el menú está capturando una tecla.
- El listener se desconecta al apagar la opción y al destruir el módulo.

## 12. `Server Settings` (Utilities)

Nuevo `src/games/universal/Other/ServerSettings.lua`, registrado con
`tools/card.py` (aparece en Utilities en todos los juegos).

- Muestra **Job ID** (corto) y **jugadores/máximo** en el estado de la tarjeta,
  refrescado cada `Refresh every` segundos (1–15, por defecto 3) y **sólo con la
  tarjeta encendida**.
- Acciones: **Copy Job ID**, **Rejoin Server**, **Hop: smallest server**,
  **Hop: largest server**, **Hop: random server**.
- El salto lee la lista pública de servidores del mismo place desde el ejecutor
  (`game:HttpGet`), descarta el servidor actual, elige el más pequeño / más
  grande / uno al azar y llama a `TeleportToPlaceInstance`. Hay enfriamiento de
  3 s y todos los fallos (HTTP bloqueado, lista vacía, teleport rechazado) se
  avisan sin teleportar.
- **No escribe nada en el servidor**: un cliente de Roblox no puede cambiar los
  ajustes de un servidor. La tarjeta lo dice en su fila de información.

---

## Verificación

`bash tools/validate.sh` → `EXIT=0`: 83 fuentes compilan, **131 suites**
Python/Luau, boot con `failures=0`, `PASS menu audit: 48 cards` (47 + Server Settings), `PASS release menu: 48 cards`.

Suites nuevas o ampliadas para esta tanda:

- `tools/test_mm2_fling_card.py` — tarjeta completa, roster por rol, Power 12 /
  Retries 3, sin fling al inyectar, negativa con Anti Fling.
- `tools/test_mm2_hold_mouse.py` — `Hold Mouse` apaga el aura automática, el
  clic/toque golpea al alcance de `Aura Range`, respeta el cooldown y limpia el
  listener.
- `tools/test_server_settings.py` — lectura del servidor, portapapeles, saltos
  pequeño/grande/aleatorio, enfriamiento, fallos y rejoin.
- `tools/test_mm2_blurt_roles.py` — la tarjeta es acción instantánea y el
  automático vive en `Auto blurt`.
- `tools/test_mm2_notifications_boot.py` — las filas nuevas existen en el UI
  booteado con sus valores por defecto.
- `tools/test_disguise_animation.py` — la precarga ocurre antes de escribir los
  slots y el reintento del script va antes del fallback.
- `tools/test_v191_labels.py` — etiqueta `Version 0.NNN`, fila `Buttons` con su
  clave guardada, Pin con el token `arrows`, renombrados con su `ConfigKey`.
- `tools/gen_full_boot_harness.py` — bootea el bundle real y comprueba
  `Opacity` sólo-fondo y el Pin teñido por `Theme.arrows`.

**Lo que estas suites NO prueban:** física real de Roblox, aceptación del
servidor (fling, stab, teleport), ni que Delta permita `game:HttpGet` en la
sesión del jugador. Todo eso queda pendiente de medir en vivo.
