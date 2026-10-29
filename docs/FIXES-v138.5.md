# v138.5 — por qué el Fling "terminaba" en medio segundo

**Stamp:** `v138.5-20261027-fling-loop-not-aborted`
**Base:** v138.4 (`32398cb`)
**Alcance:** `src/games/universal/Blatant/Fling.lua` + `tools/test_fling_skid.py` + bundle/stamp.

## Síntoma reportado

> "Sigue sin funcionar. No pasa ni un segundo y ya dice *Fling finished* y al final
> no termina haciendo nada, el Target sigue en el mapa."

Un fling que dura menos de un segundo no puede lanzar a nadie: el `SkidFling` real
machaca durante **2 s**.

## Causa raíz (bug introducido en v138.4)

En `sfBasePart` el `until` incluía esta condición, copiada de `TargetPlayer.Parent ~= Players`:

```lua
or targetPlayer.Parent ~= Players
```

El host no usa el servicio directo: `Players` aquí es
`cloneReference(game:GetService("Players"))`, o sea el resultado de **`cloneref`**.
`cloneref` devuelve la misma instancia con **otra referencia**, así que
`targetPlayer.Parent ~= Players` era **siempre verdadero**, incluso con el objetivo
presente en la partida. Resultado:

- el bucle salía en la **primera** comprobación: **6 poses ≈ 0.1 s**;
- el pin `EpixVel` se destruía enseguida y nunca había contacto sostenido con la
  víctima (la replicación del servidor necesita varios frames);
- la notificación "fling finished" aparecía al instante y el objetivo no se movía.

### Segundo defecto, en la misma línea

```lua
if okState and type(baseVelocity) == "table" and type(baseVelocity.Magnitude) == "number" then
```

En el cliente real `Velocity` es un **`Vector3` userdata**, no una `table`, así que
`speed` valía **0 siempre**: la ruta rápida (las 10 poses de `WalkSpeed`) y la salida
por éxito (`speed > 500`) no podían funcionar nunca. Ahora la magnitud se lee con
`pcall` + `type(magnitude) == "number"`, que sirve para userdata y para la tabla del
harness.

### Tercero: el fling se podía quedar colgado

`task.spawn(runFling)` no capturaba errores. Cualquier error fuera del `pcall`
interno dejaba `flingRunning = true` para siempre y todos los intentos siguientes
respondían "fling already running". Ahora hay `guardedRun()` que resetea el estado
ante cualquier error y avisa con `fling error: …`.

## Cambios

1. **`playerStillHere()`** sustituye la comparación de referencias:
   pregunta al servicio (`Players:FindFirstChild(name)`) y, si no puede saberlo,
   responde `true` (nunca corta el fling por duda).
2. **`partSpeed()`**: lectura de velocidad por `pcall`, sin `type() == "table"`.
3. **`nowSeconds()`**: `tick()` (como YARHM) → `os.clock()` → `0`, más un tope de
   **600 poses** para que el bucle jamás sea infinito.
4. **`guardedRun()`**: ningún error deja `flingRunning` pegado.
5. **Pin con reintento**: si el ejecutor rechaza `math.huge` en `MaxForce`, se
   reintenta con `1e9` (misma catapulta en la práctica) en vez de quedarse sin pin.
6. **Rescate explícito**: si tras la coreografía la víctima sigue a menos de
   100 studs/s, se le aplican dos frames de `BodyAngularVelocity` +
   `BodyVelocity` en su propia parte (todo se destruye después) y la notificación
   dice `rescue used`. Solo corre cuando el camino de YARHM falló.
7. **Notificación con datos reales**, para no volver a adivinar:
   - `fling: <nombre> sent flying (<N> studs/s, <M> poses)`
   - `fling: <nombre> did not move (<M> poses, <N> studs/s[, rescue used])`
   - además `state.mm2LastFling = {target, poses, speed, pinned, rescued, ok}`.

La coreografía sigue siendo la de YARHM, sin cambios: 6 poses (<50 studs/s) o 10
poses (≥50), `Angle += 100`, `FPos` con `RootPart.CFrame` + `SetPrimaryPartCFrame` +
`Velocity (9e7, 9e7*10, 9e7)` + `RotVelocity 9e8`, pin `EpixVel` `(9e8, 9e8, 9e8)`
con `MaxForce` infinito, `FallenPartsDestroyHeight = 0/0` y vuelta a casa con
`OldPos * CFrame.new(0, .5, 0)`.

## Pruebas

`tools/test_fling_skid.py` → **7 suites** (antes 6). La nueva suite reproduce el
fallo exacto:

- el `Players` del harness es una referencia distinta a la del `Parent` del jugador
  (igual que `cloneref`), y aun así el fling debe seguir vivo a los 0.6 s;
- exige **≥ 12 poses** y **≥ 12** `SetPrimaryPartCFrame` (el fallo daba 6);
- exige **una sola** notificación al final y que diga `did not move` + `rescue used`
  cuando el objetivo nunca se movió;
- exige que el rescate no deje instancias vivas y que `state.mm2LastFling` publique
  el diagnóstico.

También se añadió `typeof()` al harness (Roblox lo tiene, el sandbox no) para que
las rutas con `options` no se fueran por el camino de error.

`validate.sh`: **93 fuentes**, **64 suites**, boot `failures=0`, menú 52 tarjetas /
release 51, API cruzada y menú de release sin cambios.

## Archivos tocados

- `src/games/universal/Blatant/Fling.lua`
- `tools/test_fling_skid.py`
- `src/Wurst.lua` (`SOURCE_STAMP`)
- `src/libraries/bundle.lua` (reconstruido con el stamp nuevo)
