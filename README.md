# Wurst

Menú para Roblox con módulos universales y para MM2, BedFight, TRS, VD y X2.
La versión de esta sesión está en la rama `arena/7446e4e3-arandommenu`
(build `v190`); `main` es independiente.

## Loader

```lua
getgenv().WURST_BRANCH = "arena/7446e4e3-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/7446e4e3-arandommenu/src/Wurst.lua"))()
```

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
