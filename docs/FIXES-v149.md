# v149 — el Fling es el `walkfling` de Infinite Yield (sin girar)

Build: `v149-20261026-fling-is-walkfling-no-spin`
Base: `v148-20261026-fling-picks-a-player-and-keeps-your-control`

## 1. «Rota horrible y 0 % control» — tenías razón, era otro `fling`

IY trae **dos** funciones distintas y yo estaba usando la primera:

| IY | Línea | Qué hace |
| --- | --- | --- |
| `fling` | 11373 | Densidad `math.huge`, noclip y un `BodyAngularVelocity` de `99999 rad/s` en **tu** root, ciclo 0.2 s / 0.1 s. Hace volar al otro girando tu propio cuerpo: **te gira a ti** y ahí se va el control. |
| `walkfling` | 11453 | La propia descripción de IY: *«Basically fling but no spinning»*. |

Todo lo que hice de v146 a v148 fue la primera. De ahí el «rota horrible» y el
«0 % control»: no era un bug de mi código encima de IY, era el `fling` de IY.

v149 copia el **`walkfling`** entero, tal cual, y lo usa para **todo**: Touch
Fling, Fling Murderer, Fling Sheriff, Fling All Innocents, Fling y Auto Fling.

```lua
-- IY walkfling, línea por línea
local velocity = root.AssemblyLinearVelocity
root.AssemblyLinearVelocity = velocity * PULSE_SCALE + PULSE_LIFT
waitFrame(renderSignal)                     -- RunService.RenderStepped:Wait()
root.AssemblyLinearVelocity = velocity      -- se devuelve ANTES del paso físico
waitFrame(steppedSignal)                    -- RunService.Stepped:Wait()
root.AssemblyLinearVelocity = velocity + PULSE_DRIFT
```

con `PULSE_SCALE = 1000000`, `PULSE_LIFT = (0, 1000000, 0)` y
`PULSE_DRIFT = (0, 0.1, 0)`. Esos son los números de IY, no inventados.

**Por qué no te lanza a ti:** la velocidad gigante existe sólo durante la
ventana de render y se devuelve antes del paso de física. El servidor nunca ve
tu cuerpo viajando a `1e6`; sólo ve el impulso que recibe lo que tocas.

**Por qué no rota:** no hay ninguna restricción, ningún `BodyAngularVelocity`,
ninguna densidad infinita, ninguna colocación en el toque y ni un `lookAt`. El
personaje no cambia de orientación porque nada le escribe la orientación.

## 2. Lo que ya no existe en el módulo

La suite falla si vuelve cualquiera de estos:

```text
BodyAngularVelocity · math.huge · 99999 · AlignPosition · AlignOrientation
RigidityEnabled · Massless · CustomPhysicalProperties · SetNetworkOwner
lookAt · RenderStepped:Connect · Stepped:Connect · Heartbeat:Connect
```

- Nada se conecta a un frame: se **espera** en `RenderStepped`/`Stepped` dentro
  de la corrutina del pulso, igual que IY. Cero callbacks por frame.
- Sólo hay **dos** `PivotTo` en todo el archivo: la colocación de un fling
  dirigido (a 2.2 studs del objetivo, conservando la orientación) y la vuelta a
  casa al terminar. El Touch no coloca nada.
- Nunca se escribe el assembly del objetivo.

## 3. Touch: contacto → pulso corto, sin sesión

- `TOUCH_PULSE = 0.18 s` de pulsos de walkfling y `TOUCH_COOLDOWN = 0.35 s`.
- Entre pulsos no hay nada conectado, nada fijado y nada escrito: caminas,
  giras y saltas normal.
- El `CanTouch` de tus partes se restaura al apagar; OFF/muerte/destroy dejan el
  cuerpo exactamente como estaba (ni densidad ni colisión se tocan ya).

## 4. Bugs reales que aparecieron al portarlo

1. `host.game:GetService` sin llamada no es Lua válido (`a:b` exige `(...)`).
   Ahora se resuelve `RunService` con `type(host.game.GetService) == "function"`.
2. El check de que la velocidad era un vector usaba `typeof(v) == "Vector3"`.
   `typeof` no es fiable fuera de Roblox y devolvía `table`, así que el pulso
   se rendía en el primer frame. Ahora se comprueban `X`/`Y`/`Z` numéricos.

## 5. Verificación offline

```text
PASS 86 Lua sources compile
PASS 66 Python/Luau suites
[Wurst:Bootstrap] Load complete · failures=0
PASS bundle boot, silent startup, native controls and cleanup assertions
PASS every core.* and prediction.* call resolves to an export
PASS menu audit: 50 cards, every row dumped from the booted bundle
PASS release menu: 49 cards, no Calibration card
```

`tools/test_fling_physics.py` ahora corre un reloj y un `RunService` de mentira
con el orden real de frames (`Heartbeat` → `RenderStepped` → `Stepped`, un frame
por `pump`) y comprueba:

- el pulso llega a `1e6` **en la ventana de render** y ya está restaurado
  cuando se dispara `Stepped` (si se invierte ese orden, el test falla: es el
  bug que lanzaba al que flingea);
- la velocidad de caminar (`X = 16`) sobrevive a todos los pulsos;
- el Touch no rota (`LookVector` idéntico), no mueve (`Position` idéntico), no
  adjunta nada (`#created == 0`) y no cambia densidad ni colisión;
- cooldown, OFF, muerte y `destroy` no dejan pulsos ni listeners;
- el fling dirigido nunca escribe el assembly del objetivo.

## 6. Pendiente en vivo

1. **Cuánto vuela el tocado.** El mecanismo es exactamente el de IY, pero el
   pulso dura `0.18 s`. Si en vivo no alcanza, subir `TOUCH_PULSE`.
2. Si el pulso corto basta con ping alto (IY lo deja corriendo mientras camina).
3. Nada de knockback ni FPS se puede afirmar desde el mock.
