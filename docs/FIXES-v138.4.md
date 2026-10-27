# v138.4 — Fling = SkidFling de YARHM, literal

**Stamp:** `v138.4-20261027-yarhm-fling-epixvel`
**Base:** v138.3 (`c968428`)
**Alcance:** `src/games/universal/Blatant/Fling.lua` + `tools/test_fling_skid.py` + bundle/stamp.

## Síntoma que reportó el usuario

> "El de nosotros no sirve pero el de ellos sí. El nuestro dibuja un círculo raro al
> target y el personaje local parece que se está desvaneciendo; el de YARHM
> simplemente se teletransporta al target, hace unos movimientos precisos y lo
> manda a volar rápidamente."

Traducción técnica: nuestro fling **no transfería energía** al objetivo, solo lo
sujetaba; y el cuerpo local se sacudía hasta parecer que desaparecía.

## Causa raíz (comparando con `SkidFling` de YARHM, líneas 4203–4385)

El puerto anterior hacía tres cosas que el original **nunca** hace:

| Nuestro v138.3 (mal) | YARHM `SkidFling` (correcto) |
| --- | --- |
| `BodyVelocity` con `Velocity = Vector3.zero` y `MaxForce 9e9` → **pin** que inmoviliza | `BodyVelocity` `"EpixVel"` con `Velocity = (9e8, 9e8, 9e8)` y `MaxForce = (1/0, 1/0, 1/0)` → **catapulta** |
| Escribía `AssemblyLinearVelocity` y `CustomPhysicalProperties` en cada frame | Solo `RootPart.CFrame`, `Character:SetPrimaryPartCFrame`, `RootPart.Velocity`, `RootPart.RotVelocity` |
| Pulsos por `RenderStepped` alrededor del target (el "círculo") | Poses fijas con `task.wait()` (un paso de física entre pose y pose) |
| Fuerza global 9e9 aplicada desde fuera | El impulso sale del **contacto** del propio assembly a 9e8 studs/s |

El pin a velocidad cero es un ancla: mantiene el personaje local pegado al
objetivo pero no le entrega momento, así que el objetivo no sale volando. Las
escrituras de física por frame son además las que producían el parpadeo
("desvanecerse") del personaje local.

## Lo que hace ahora, punto por punto

1. `fpos()` — exactamente `FPos`:
   `RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang`, seguido de
   `SetPrimaryPartCFrame` de la misma CFrame (con `PivotTo` como respaldo) y
   `RootPart.Velocity = (9e7, 9e7*10, 9e7)`, `RootPart.RotVelocity = (9e8, 9e8, 9e8)`.
2. `sfBasePart()` — la coreografía literal, con `Angle = Angle + 100`:
   - víctima **< 50 studs/s**: 6 poses (arriba, abajo, diagonal +2.25/-2.25,
     diagonal -2.25/+2.25, y las dos con `MoveDirection`), `task.wait()` entre cada una;
   - víctima **≥ 50 studs/s**: las 10 poses de `WalkSpeed` y
     `TRootPart.Velocity.Magnitude / 1.25`, con `math.rad(90)`/`math.rad(-90)`.
   - Termina cuando la víctima pasa de **500 studs/s**, el jugador sale, cambia de
     personaje, se sienta, morimos, o pasan **2 s**.
3. `createPin()` — `BodyVelocity` llamado `"EpixVel"`, padre el `HumanoidRootPart`,
   `Velocity = (9e8, 9e8, 9e8)`, `MaxForce = math.huge` (idéntico a `1/0`), creado
   **antes** de la coreografía y destruido **después**, igual que el original.
4. Secuencia completa: cámara al target (`Head` → `Handle` del accesorio → `Humanoid`),
   `FallenPartsDestroyHeight = 0/0`, pin, `Seated` deshabilitado, elegir la parte
   (`Head` si está a más de 5 studs del root, si no `RootPart`), coreografía, destruir
   pin, `Seated` habilitado, cámara de vuelta, **volver a casa** con
   `OldPos * CFrame.new(0, 0.5, 0)` + velocidades a cero hasta quedar a menos de
   25 studs, y `FallenPartsDestroyHeight` restaurado.
5. `state.mm2FlingStep` (lo usa Auto Win por frame) usa **la misma** pose y el mismo
   pin `EpixVel` a 9e8; el pin se limpia 0.5 s después de la última llamada para no
   dejar una catapulta infinita pegada al personaje.

Nada de `AssemblyLinearVelocity`, nada de `CustomPhysicalProperties`, nada de
`RenderStepped`. Nada se autoactiva al inyectar: el módulo es una tarjeta con
`Target player` y botones.

## Pruebas

`tools/test_fling_skid.py` se reescribió para blindar justo lo que fallaba; ahora
son 6 suites (todas en verde):

1. La tarjeta expone solo `Target player` + acciones (sin `Select Target`, sin
   `Auto Fling`, sin `Touch Fling`).
2. `Target player` vacío no flingea y avisa.
3. El fling escribe ≥ 6 poses con `Velocity` ≥ 8e8 y `RotVelocity` ≥ 8e8, pasa por
   `SetPrimaryPartCFrame`, **no** escribe `AssemblyLinearVelocity` ni
   `CustomPhysicalProperties`, crea un `BodyVelocity` llamado `EpixVel` con
   `Velocity` ≥ 8e8 y `MaxForce` infinito, lo destruye, restaura
   `FallenPartsDestroyHeight`, vuelve a casa y libera la actividad.
4. Un objetivo sin personaje falla cerrado sin dejar el vacío apagado.
5. `mm2FlingStep` (Auto Win) usa la misma pose y limpia su pin al parar.
6. Las acciones de rol degradan limpiamente fuera de MM2.

`validate.sh`: **93 fuentes** compilan, **64 suites** en verde, boot del bundle
`failures=0`, menú 52 tarjetas / release 51, `Walk Fling — 0 options`,
`Fling [group] — Exploits — 5 options`.

## Archivos tocados

- `src/games/universal/Blatant/Fling.lua` — núcleo reescrito (mecánica + pin).
- `tools/test_fling_skid.py` — 6 suites nuevas.
- `src/Wurst.lua` — `SOURCE_STAMP` → `v138.4-20261027-yarhm-fling-epixvel`.
- `src/libraries/bundle.lua` — reconstruido con el stamp nuevo (91 archivos).
