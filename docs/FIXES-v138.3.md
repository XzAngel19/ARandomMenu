# v138.3 — Fling es un módulo universal con «Target player» como única lista

Build: `v138.3-20261027-universal-fling-target-only`
Base: `v138.2-20261027-walkfling-platform-antifling`

Pedido del usuario, textual: *«Saca el Fling de Aquí para Fling Module. Elimina el
select target, que solo quede target player y ese cuadro de texto será la lista.
Y walkfling simplemente que sea una función porque tiene una opción, no es
necesario. Verifica que todo funcione.»*

---

## 1. Fling deja de ser tarjeta de MM2 y pasa a módulo universal

| Antes (v138.2) | Ahora (v138.3) |
| --- | --- |
| `src/games/MM2/Blatant/Fling.lua` | `src/games/universal/Blatant/Fling.lua` |
| Sección **MM2**, `configKey = MM2.Fling` | Sección **Universal**, `configKey = Universal.Fling` |
| Solo aparecía en Murder Mystery 2 | Aparece en cualquier juego, en **Exploits** (orden 7) |

El módulo se borró de `gameModules.MM2` en `src/libraries/Manifest.lua` y del
manifiesto de respaldo de `src/Wurst.lua`; la tarjeta universal se registró en
las mismas dos listas. La sección MM2 queda con 13 tarjetas.

El mecanismo es el mismo de v138.2 (**SkidFling**): `CFrame` sobre la víctima,
`9e7`/`9e8`, `BodyVelocity(0, MaxForce 9e9)` de anclaje, `FallenPartsDestroyHeight`
desactivado solo durante el fling y restaurado, y vuelta acotada al CFrame
guardado.

### Acceso a MM2 sin depender de él

Las acciones de rol (Fling Murderer / Sheriff / All Innocents) siguen ahí, pero
resuelven el core **en el momento del clic**:

```lua
local function coreFunction(name: string): any
    local ok, core = pcall(function() return state.mm2Core end)
    if ok and type(core) == "table" and type(core[name]) == "function" then
        return core[name]
    end
    return nil
end
```

Fuera de MM2 avisan «Fling Murderer needs Murder Mystery 2; use Target player
here» en vez de fallar. También quedaron perezosos `protectedTargets` y
`activity`.

### Exportes que Auto Win / Auto Farm usan

`state.mm2PerformFling` y `state.mm2FlingStep` los publica ahora el módulo
universal, con la misma firma (`silent`, `duration`, `shouldStop`, `blocking`,
`returnCFrame`). El harness de arranque lo comprueba en cada build.

## 2. Fuera «Select Target»: el cuadro de texto es la lista

Se eliminó por completo del código:

- el ciclo `addCycleOption("Select Target", ...)` y `selectedTargetChoice`;
- `targetChoices`, `rebuildTargetChoices()`;
- las conexiones `PlayerAdded` / `PlayerRemoving` que solo servían para
  reconstruir ese desplegable.

Queda una sola entrada de objetivo, **Target player** (texto), y la tarjeta
interpreta lo escrito como lista: coincidencia exacta por nombre o display name,
luego prefijo, luego subcadena. Vacío = no flingea y avisa «No player matched what
is typed in Target player».

Opciones de la tarjeta en el menú real (volcado del bundle):

```
Fling [group] — Exploits — 5 options
  Target player, Fling, Fling Murderer, Fling Sheriff, Fling All Innocents
```

## 3. Walk Fling es una función, sin opciones

`src/games/universal/Blatant/WalkFling.lua`:

- se eliminó la opción **Power**; el multiplicador queda fijo en `POWER = 10000`
  (el valor de Infinite Yield, que es el que funciona);
- la tarjeta se declara `noOptions = true`, así que se dibuja como un toggle
  simple, sin flecha ni fila de opciones.

Volcado real: `Walk Fling — Exploits — 0 options`.

## 4. Verificación

- `tools/test_fling_skid.py` (6 suites, módulo real con mocks deterministas):
  - la tarjeta publica solo acciones y «Target player» (sin «Select Target»),
  - **Target player vacío no flingea** y avisa,
  - **escribir el nombre y pulsar Fling sí flingea** (pico 9e7 real),
  - las acciones de rol fuera de MM2 avisan en vez de romper,
  - el fling sigue escribiendo 9e7/9e8, ancla con BodyVelocity, restaura
    `FallenPartsDestroyHeight`, vuelve a casa y libera la actividad.
- `tools/test_walkfling.py` (4 suites): sin opciones, inerte al inyectar, el
  pulso solo con la tarjeta ON, OFF/destroy restauran colisiones.
- `tools/gen_full_boot_harness.py`: comprueba sección y clave (`Universal.Fling`),
  que existe `Option_Targetplayer`, que **no** existe `Option_SelectTarget`, que
  Walk Fling no tiene opciones y que `mm2PerformFling` / `mm2FlingStep` siguen
  publicados tras el arranque.
- `tools/test_menu47.py` y `tools/test_mm2_auto_shoot_option.py` ajustados a la
  nueva ruta.
- `bash tools/validate.sh` en verde: 93 fuentes, 64 suites, boot `failures=0`,
  menú 52/51 tarjetas.

## 5. Lo que no se tocó

- Anti Void (plataforma invisible), Anti Fling y Noclip siguen como en v138.2.
- El fling dirigido no se puede probar en vivo desde aquí: la mecánica es la
  copia de SkidFling, pero el knockback real solo se confirma en Roblox.
