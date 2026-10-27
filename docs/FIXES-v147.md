# v147 — el Fling ya no te lanza a ti, y el lag, medido en vez de adivinado

Build: `v147-20261027-fling-holds-you-and-script-cost`
Base: `v146-20261027-iy-fling-and-zero-frame-cost`

## 1. «Yo también salgo despedido»

Era el propio mecanismo de Infinite Yield: se hace girar **tu** assembly a
`99999 rad/s` con densidad infinita. El giro transfiere el impulso al tocado,
pero la reacción te empuja a ti igual. IY lo resuelve a su manera (`flyfling`,
`walkfling`), no en el `fling` base.

v147 mantiene el giro y **fija tu personaje en el sitio** mientras dura el
impulso:

```lua
hold = Instance.new("AlignPosition")
hold.Mode = Enum.PositionAlignmentMode.OneAttachment
hold.Position = root.Position   -- dónde ocurrió el contacto (mundo)
hold.Attachment0 = attachment   -- Attachment hijo del root
hold.RigidityEnabled = true     -- restricción rígida, no muelle
```

- Es una **restricción física**, no un `CFrame` por tick: nada de teletransporte.
- `Position` explícita: por defecto vale `(0,0,0)` y habría arrastrado al jugador
  al origen del mapa.
- Vive como máximo `HOLD_SECONDS = 0.8 s`, así que un fling largo (1.4 s) no te
  deja clavado: el impulso ya se entregó y el pin se suelta solo.
- Se destruye junto con el giro al apagar, morir, respawnear o destruir.
- Durante el pulso se fuerza `root.AssemblyLinearVelocity = 0`, así no queda
  deriva residual entre pulsos.

Resultado: el tocado sale despedido y tú te quedas donde estabas.

## 2. Por qué el lag empezó «de la nada» en v138

No fue el ejecutor ni el juego. El commit de v138
(`a6a7c0ab2639eb1768ca3e6a0c5b976e63a3a882`,
`v138-20261026-autofarm-antifling-iy-fixes`) introdujo esta función en
`AntiVoid.lua`, copiando el anti-fling de Infinite Yield:

```lua
-- En cada frame, por cada jugador:
local descendants = otherChar:GetDescendants()      -- recorre todo el personaje
for _, inst in ipairs(descendants) do
    pcall(function()                                 -- closure nueva por parte
        inst.CanCollide = false
        inst.AssemblyLinearVelocity = Vector3.zero
        inst.AssemblyAngularVelocity = Vector3.zero
    end)
end
```

Con 11 jugadores y ~15 partes cada uno son **~165 partes, 3 escrituras de física
y 3 closures por parte, 60 veces por segundo**: unas **500 escrituras de física y
500 asignaciones de closure por frame**. Y cada `CanCollide` que cambia
reinserta la parte en el broadphase y obliga al motor a recalcular contactos.
Eso es exactamente lo que se veía en el microprofiler: `Physics 12.4 ms (44 %)`
con `Render 1.0 ms` y `Network 0.5 ms`.

v146 eliminó ese bucle. v147 afina lo que quedaba:

| Antes (v138–v145) | Ahora (v147) |
| --- | --- |
| `GetDescendants()` del personaje entero por jugador y frame | Lista de partes cacheada por personaje (clave débil), invalidada con `DescendantAdded` |
| 3 `pcall` con closure nueva por parte y frame | `isBasePart` sin closure; cero asignaciones en régimen |
| `CanCollide` + 2 velocidades en **todas** las partes, cada frame | Solo se toca un personaje que **de verdad** está flingeando (giro > 20 rad/s o > 1.5× su caminata) |
| Escrituras mientras durase el fling | Se escribe **una vez** por detección (0.45 s) y se restaura una vez |
| Jugadores a 500 studs incluidos | Solo a ≤ 60 studs |
| El barrido corría 2 veces por frame (Heartbeat y Stepped) | Un solo dueño (Stepped), sin doble trabajo |

Medido en `tools/test_antivoid50.py` (que cuenta escrituras y recorridos):
**0 escrituras de física por frame** mientras el strip está activo y **1
recorrido de árbol por fling detectado** (antes: cientos por frame).

Noclip tenía el mismo patrón (`GetDescendants()` + `CanCollide=false` por parte
cada frame). Ahora arma la lista una vez por personaje, la mantiene con
`DescendantAdded` y solo escribe las partes que aún colisionan.

## 3. Cómo saber, en partida, si el menú es el culpable

Session Info → **Performance** ahora muestra una línea más:

```text
FPS       60
Ping      48 ms
Script    0.51 ms / 8 tasks
```

`Script` es el tiempo real de Lua de **todos** los callbacks por frame del menú
(medido dentro de `TaskManager`, en el evento del motor), y `tasks` cuántos
corren. Con eso se acaba la discusión:

- `Script` < 1 ms → el menú no está causando el tirón; el coste está en
  `Physics`/`Render` del propio juego o en el ejecutor.
- `Script` > 3 ms → sí es el menú, y el número dice cuánto.

`tools/perf_frame.py` hace lo mismo en el arnés, con 12 jugadores y 80 monedas y
los módulos de render encendidos:

```text
PROFILE frames=120 luaMs=95.0 perFrame=0.792
PROFILE 42.00 ms id=3 ... find=12350   (≈103 FindFirstChild/frame: ESP)
PROFILE 32.00 ms id=5 ... find=4800
PROFILE session_line=... | Script 0.51 ms / 8 tasks | Players 12/12 | Game MM2
```

≈0.8 ms/frame **en un mock de Lua puro**, que es mucho más lento que las llamadas
nativas de Roblox. En partida debería quedar bastante por debajo. Ese es el
presupuesto del menú; si el juego sigue a 35 FPS con `Script 0.4 ms`, el tirón no
viene de aquí.

## 4. Validación

```text
bundle.lua is current: 84 files, stamp v147-20261027-fling-holds-you-and-script-cost
PASS 66 Python/Luau suites
[Wurst:Bootstrap] Load complete · failures=0
PASS menu audit: 50 cards
PASS release menu: 49 cards, no Calibration card
```

Suites nuevas/actualizadas:

- `tools/test_fling_physics.py`: el pin rígido existe al girar, está anclado a la
  posición del contacto, expira solo a los 0.8 s, y se destruye con el giro al
  apagar/morir/respawnear/destruir. También comprueba que Fling **nunca** escribe
  el assembly del objetivo y que no hay ninguna conexión de frame.
- `tools/test_antivoid50.py`: 0 escrituras por frame, 1 recorrido por fling,
  colisiones liberadas en detección/expiración/destroy y jugadores lejanos
  ignorados.
- `tools/perf_frame.py`: perfil de coste por frame + comprobación de que la línea
  `Script` aparece de verdad en Session Info.

## 5. Lo que sigue pendiente (no se puede probar offline)

1. Que el servidor acepte el knockback y cuánto vuele el tocado.
2. FPS reales: ahora hay un número (`Script`) para reportarlos en vez de
   impresiones.
3. Si con el Fling apagado y `Script` bajo el juego sigue lento, el siguiente
   sospechoso es el ejecutor o el propio MM2, no este menú.
