# v139.4 — Los cuatro puntos del revisor, verificados uno por uno

**Stamp:** `v139.4-20261028-constructor-release-version`
**Base:** v139.3 (`f7537da`)

Los cuatro informes eran correctos salvo un matiz de redacción. Este documento
dice, para cada uno: qué había exactamente, qué se reprodujo y qué se cambió.

## 1. Gun — Silent AIM CFrame

### 1.1 El constructor compartido se llamaba sin sus argumentos

`state.mm2FireSilentShot` es el constructor que usan Auto Shoot, Auto Win y el
farme del bolso. Su firma publicada era:

```lua
state.mm2FireSilentShot = function(target: Player?): boolean
    return fireGunAtTarget(target, {silent = true, quiet = true, continuous = true})
end
```

Un solo argumento: **el llamador no podía pasar sus opciones**. Auto Shoot tiene
su propio `settings.wallCheck` y lo perdía en el camino; el wrapper forzaba
`continuous = true`, que es justo el modo que se saltaba la comprobación de
geometría. Ahora acepta un segundo argumento (compatible con las llamadas
antiguas) y los tres módulos le pasan `wallCheck`:

```lua
state.mm2FireSilentShot = function(target: Player?, shotOpts: any): boolean
    local opts: any = type(shotOpts) == "table" and shotOpts or {}
    return fireGunAtTarget(target, {
        silent = true,
        quiet = opts.quiet ~= false,
        continuous = opts.continuous ~= false,
        wallCheck = opts.wallCheck,
    })
end
```

Además la construcción estaba **fijada a `"Through"`**:

```lua
local variant: string = "Through"   -- y mm2Settings.silentSpawn solo iba a la telemetría
```

Ahora respeta `mm2Settings.silentSpawn` (`Top` / `Behind` / `Front`; cualquier
otro valor sigue siendo `Through`), y la telemetría deja de mentir sobre la
variante usada.

### 1.2 "Termina usando una alternativa" — el fallback era un bypass

Los tres llamadores hacían lo mismo:

```lua
if state.mm2FireSilentShot(...) == false then
    remote:FireServer(shotOrigin, shotEnd)   -- CFrame propio, SIN wallcheck
end
```

Un rechazo del camino seguro se convertía en un disparo por el camino inseguro.
Ahora el fallback conserva su transporte pero pasa por la misma regla de
geometría (`isWeaponPathClear` desde el cañón real) y, si hay pared, **no
dispara**. Afecta a `AutoShoot.fireCFrameShotImmediate`, `AutoWin` y
`AutoFarm`.

### 1.3 El WallCheck miraba desde cerca del objetivo, no desde la pistola

Confirmado y era el fallo más serio. En `safeToSend`:

```lua
if useRaw then return true end   -- raw = mm2Settings.shootRaw o (continuous and silent)
```

Con `continuous and silent` (exactamente Auto Shoot / Auto Win) **no se ejecutaba
ninguna comprobación**: ni `validateGunShot` ni la pasada desde el cañón. Lo
único que se miraba en el camino Silent era el guardián de origen cercano
`isWeaponPathClear(shotOrigin.Position, ...)`, es decir **una línea que empieza a
1 stud del objetivo**, no en la pistola. Una pared entre la pistola y el asesino
no la veía nadie.

Ahora "raw" significa *no esperar al guardián del origen cercano*, nunca *no
mirar paredes*:

```lua
if useRaw then
    if not useWallCheck then return true end
    local rawClear = isWeaponPathClear(muzzle, shotEnd.Position, targetCharacter,
        nil, {ignoreTarget = true})
    if not rawClear then return reject("A wall or another body blocks the shot.") end
    return true
end
```

Es decir: en **todos** los modos la línea del cañón se comprueba. Si el usuario
apaga WallCheck, se respeta el apagado.

## 2. Knife — la velocidad no llegaba al predictor

Cierto. `resolveKnifeAim` leía `ThrowSpeed` y lo usaba **solo** en el cálculo
local de respaldo:

```lua
pcall(prediction.knifeAim, target, originPos)          -- antes
pcall(prediction.knifeAim, target, originPos, speed)   -- ahora
```

`Prediction.knifeAim` ya aceptaba el tercer argumento (`speed`) y caía a
`DEFAULT_KNIFE_SPEED`; el resolvedor principal nunca lo recibía. Con un cuchillo
a 140 studs/s el tiempo de vuelo se calculaba para 96. Los seis proyectiles de
la sesión guardada marcan 96 exacto, así que esto **no explica** esos
resultados — sigue siendo un error y está corregido.

## 3. Knife — la búsqueda de otra parte sumaba dos veces el torso

Cierto, y era geometría visible a ojo. El predictor devuelve
`predicted = rootFuturo + aimOffset`, y su propio `capturedPosition` es
`posiciónMuestreada + aimOffset`. El barrido hacía:

```lua
local leadOffset = predicted - root.Position     -- lead + offset del torso
candidatePoint = UpperTorso.Position + leadOffset -- + otro offset del torso
```

`UpperTorso` ya está 1–2 studs por encima del root, así que sumarle un vector que
**contiene** ese mismo desplazamiento apuntaba 2–4 studs por encima de la parte
que decía estar usando. Ahora se usa el punto de referencia del propio predictor:

```lua
local leadOffset = predicted - root.Position
if aimInfo and typeof(aimInfo.capturedPosition) == "Vector3" then
    leadOffset = predicted - aimInfo.capturedPosition   -- solo el lead temporal
end
candidatePoint = part.Position + leadOffset
```

Fijado en `tools/test_mm2_knife_aim.py`: con la cabeza a root + 3 y el objetivo
del predictor en root + 1,5 (torso) + 1,7 (lead), la candidata debe caer
**exactamente** en la cabeza + 1,7; antes caía 1,5 studs más arriba.

## 4. Telemetría — el error en studs era una aproximación

### 4.1 Faltaba el desplazamiento del torso

`base.lua` lo leía en tres sitios (`measureEndpointErrorStuds`,
`measureLeadErrorSeconds`, `aimOffsetAtFire`), pero `Prediction.getHistory`
**nunca lo devolvía**:

```lua
-- getHistory devolvía at/position/velocity/state/grounded/moveDirection
aimOffset = sample.aimOffset,   -- v139.4
aimPart = sample.aimPart,       -- v139.4
```

Consecuencia exacta: se comparaba la **posición del root** contra un aim que usaba
el **punto del torso**. Cada muestra llevaba el offset del torso (1,5 studs en un
R15) como error falso. Reproducido en `tools/test_telemetry_aim_offset.py`: el
mismo disparo puntuaba 1,5 studs con la historia sin offset y 0,00 con el offset
grabado.

### 4.2 Se descartaba la muestra más reciente

```lua
for _, sample in ipairs(history) do
    if #points >= 36 then break end   -- oldest -> newest: se perdían las NUEVAS
```

Por encima de 60 FPS la ventana de 0,6 s tiene más de 36 muestras y el corte se
llevaba **las últimas**, que son justo las que usa la interpolación del instante
de puntuación. Ahora la ventana se **decima** conservando el span y
garantizando que la última muestra siempre entra (verificado con 100 muestras:
la última llega con `dt = 0` y la ventana sigue cubriendo 0,6 s).

### 4.3 Por qué importa: ese número mueve un disparo real

`leadErrorSeconds` → `noteLeadError` → `leadUncertainty()` →
`getSilentSweepDistance()` → longitud del barrido adaptativo de **Silent AIM**.
Un error sesgado en 1,5 studs ensanchaba el segmento autorizado con una
incertidumbre que no existía. Con el offset grabado, el barrido vuelve a crecer
solo cuando el lead se equivoca de verdad.

Y el resumen de sesión ahora lo dice con todas las letras:

```
scope = "own predicted point vs the torso point at the scoring instant
         (interpolated from the newest pre-shot sample and the root at
         confirmation); an estimate, not a server measurement"
```

## Verificación

`bash tools/validate.sh` → verde: **91 fuentes**, **73 suites**, boot
`failures=0`, 52/51 tarjetas, 249 líneas `PASS`.

Suites nuevas (todas contra el código real, no copias):

| Suite | Qué fija |
|---|---|
| `tools/test_gun_silent_constructor.py` | pared entre pistola y asesino en continuo → se rechaza; línea limpia → dispara; WallCheck OFF → dispara; `silentSpawn = Front` → variante Front; punto blanco embistiendo → dispara |
| `tools/test_mm2_knife_aim.py` | `ThrowSpeed 140` llega al predictor; sin atributo sigue 96; el barrido no duplica el torso; la trayectoria primaria visible no se toca |
| `tools/test_telemetry_aim_offset.py` | la ventana conserva la más nueva y el span; aim perfecto al torso puntúa 0; sin offset habría inventado 1,5 studs; un fallo real conserva su distancia |
