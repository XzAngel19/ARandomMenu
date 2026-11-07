# Wurst

Menú para Roblox con módulos universales y para MM2, BedFight, TRS, VD y X2.
La versión de esta sesión está en la rama `arena/7446e4e3-arandommenu`
(build `v191`, se muestra como **Version 0.191**); `main` es independiente.

## Loader

```lua
getgenv().WURST_BRANCH = "arena/7446e4e3-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/7446e4e3-arandommenu/src/Wurst.lua"))()
```

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
