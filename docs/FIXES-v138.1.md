# v138.1 — Auto Fling borrado, y el walkfling solo dentro de Touch Fling

Build: `v138.1-20261027-no-autofling-touchfling-only`
Base: `v138-20261026-autofarm-antifling-iy-fixes` (`a6a7c0a`)

Pedido del usuario, textual: *«Lo que está pasando ahora mismo que se enciende
solo al inyectar. El AutoFling simplemente bórralo, ya que nadie puede hacerlo
bien por alguna razón, y lo del Noclip es walkfling. Que está bien: solo añade
ese código, que solo se active cuando la opción de Touch Fling esté activada.»*

## 1. Por qué se encendía solo al inyectar

`Cards.lua` restaura cualquier tarjeta cuyo `configKey` quedó en `true` en el
guardado:

```lua
if not feature.isAction
    and not feature.isCategory           -- la tarjeta Fling es un grupo: no entra
    and configuration.restore ~= false
    and configData.states[feature.configKey] == true then
    feature.onToggle(true)               -- se ejecuta en el arranque
end
```

La tarjeta `Fling` sí es un grupo (`category = true`, kind `group`), así que no
se restaura ella misma. Lo que se restauraba era su opción hija
**Auto Fling Selected Target**: al inyectar, `onToggle(true)` conectaba
`autoFlingTick`, que flingeaba al objetivo elegido cada 0.35 s antes de que el
menú estuviera ni abierto. En v139 se parcheó forzando esa clave a `false`;
aquí la opción ya no existe.

## 2. Auto Fling: borrado

- Se elimina la opción **Auto Fling Selected Target**, `autoFlingTick`,
  `autoFlingSelected`, `lastAutoFlingAt` y la conexión `MM2AutoFlingTarget`.
- En `Module.init` se limpia la clave vieja y se fuerza Touch Fling a `false`,
  para que un guardado anterior de v138/v139 no pueda arrancar nada:

```lua
configData.states["MM2.Fling.AutoFlingSelectedTarget"] = nil
configData.states["MM2.Fling.TouchFling"] = false
```

## 3. Walkfling: ahora es la opción Touch Fling

El pulso es **exactamente el mismo** de v138 (el de Infinite Yield):

```lua
local spike: Vector3 = savedVel * 10000 + Vector3.new(0, 10000, 0)
root.Velocity = spike
root.AssemblyLinearVelocity = spike
-- RenderStepped: root.Velocity = savedVel
-- Stepped:       root.Velocity = savedVel + Vector3.new(0, movel, 0); movel = -movel
```

Lo que cambia es el dueño y el alcance:

| Antes (v138) | Ahora (v138.1) |
| --- | --- |
| `startWalkFlingLoop()` se lanzaba desde el toggle módulo `Fling` | Solo lo lanza `Touch Fling` cuando se marca; nada lo llama al arrancar |
| El bucle podía quedar huérfano con `CanCollide = false` en las partes | Se guarda el `CanCollide` original por parte (weak table) y se restaura al apagar, al destruir el módulo y al terminar el bucle |
| Apagar no devolvía las colisiones | `stopTouchFling()` restaura colisiones y deja la velocidad en cero |
| El texto del menú decía «enable Fling for walk-fling» | El texto apunta a Touch Fling; la opción se describe como *«while ON, bumping into another player launches them»* |

El toggle módulo `Fling` queda como contenedor: encenderlo o apagarlo ya no
lanza a nadie. Todas las acciones (Fling Murderer / Sheriff / All Innocents /
Fling) siguen siendo botones explícitos.

## 4. Verificación

- `tools/test_fling_touch_only.py` (nueva, ejecuta el módulo real con mocks
  deterministas y un pump de frames):
  1. Inyectar no escribe física ni colisiones, y la clave vieja de Auto Fling
     queda en `nil`.
  2. El contenedor `Fling` no arranca walkfling.
  3. `Touch Fling` ON sí produce el pico de velocidad (>9000) y limpia
     `CanCollide`.
  4. `Touch Fling` OFF detiene el bucle, restaura `CanCollide` y no deja trabajo
     por frame.
  5. `destroy()` con Touch Fling encendido también restaura.
- `tools/test_mm2_auto_shoot_option.py` ahora exige que Auto Fling **no** esté y
  que Touch Fling nunca se restaure.
- `bash tools/validate.sh` en verde: 63 suites, boot `failures=0`.

## 5. Lo que no se tocó

- El **Noclip** universal sigue igual (el usuario lo dio por bueno).
- `performFling` (el fling dirigido a un jugador) queda intacto: sigue usando
  carga de CFrame + `BodyAngularVelocity` de IY. Si ese fling vuelve a lanzar
  al jugador local, ese es otro cambio, no este.
