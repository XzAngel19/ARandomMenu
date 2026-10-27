# v144 — Touch Fling deja de secuestrar tu personaje y Auto Farm vuelve a cobrar

Build: `v144-20261027-touch-momentum-farm-collect`
Rama: `arena/83897e25-arandommenu`
Base: `v143-20261026-boot-restore-lifecycle`

Los cuatro reportes del usuario eran: **Below/Under no funciona bien**, **faltan
checks coherentes para no farmear en lobby ni muerto**, **no agarra monedas**, y
**Touch Fling hace un movimiento circular tonto en vez de mandar a volar al
tocado**. Más el reporte de CPU alta en MM2. Esto es lo que cambió y por qué.

---

## 1. Touch Fling: el impulso va al tocado, no a tu personaje

Antes, cada contacto hacía lo siguiente *sobre tu propio avatar*: `CanCollide`
en todas las partes, `Humanoid:ChangeState(Physics)`, `AutoRotate = false`,
`Sit = false`, estado `Seated` deshabilitado, velocidad lineal de hasta `~205`
con lift, y **`AssemblyAngularVelocity = (0, 120, 0)`**, repetido cada `1/30 s`
durante la ventana de contacto de `0.25 s`. Eso es exactamente el «movimiento
tonto circular»: el giro local no lanzaba a nadie, solo rotaba al jugador.

Ahora (`src/libraries/Fling.lua`):

- El contacto aplica un pulso **acotado al assembly del jugador tocado**:
  `200` horizontal + `60` de lift (magnitud `≈209 < 250`), con `25` de giro en Y
  sobre el objetivo. Ese es el fling.
- Sobre tu personaje se escribe **un solo paso de física**: `165` horizontal sin
  lift, `AssemblyAngularVelocity = 0` (cero giro), restaurado en el `Heartbeat`
  siguiente. Ese paso es el que el servidor sí acepta, porque tu assembly es el
  que tu cliente posee; por eso el empujón llega al choque.
- **Nunca** se tocan estado del Humanoid, `AutoRotate`, `Sit`, `PlatformStand`,
  ni se pide network ownership. Ya no hay `ChangeState(Physics)`.
- Las colisiones del cuerpo se habilitan **una vez al encender** Touch (snapshot
  y restauración en OFF/respawn), no en cada contacto. Ese toggle por contacto
  reconstruía assemblies y era coste de física puro.
- Cada objetivo tiene cooldown de `1/20 s`; el pulso ya no se repite a 30 Hz
  mientras el contacto siga «fresco».
- El fling dirigido (`start`) mantiene **una** colocación de contacto y pulsa el
  objetivo sin girar al jugador local.

Efecto lateral en CPU: menos escrituras de física por contacto, cero rebuilds de
assembly por toque.

## 2. Auto Farm: un contexto de ronda, no tres comprobaciones sueltas

`isCharacterInActiveRound` era una cadena con cachés parciales (lobby a `0.75 s`,
referencia del mapa a `1 s`, distancia `> 1500` como lobby) y podía devolver
`false` o `true` por caminos que otras rutas no compartían. Ahora hay **una**
función `roundContext(root)` que devuelve `"active" | "lobby" | "dead"`:

- sin cuerpo vivo o `Humanoid.Health <= 0` → `"dead"`;
- rol local `Dead` → `"dead"`;
- `isRoundLifecycleActive() == false` (RoundEndFade / teleport al lobby) → `"lobby"`;
- `getRoundPhase() == "lobby"` → `"lobby"`;
- sin mapa MM2 cargado → `"lobby"`;
- cuerpo a ≤300 studs de una referencia del lobby → `"lobby"`;
- cuerpo a >1500 studs de la referencia del mapa → `"lobby"`;
- en cualquier otro caso → `"active"`.

Solo se cachean las búsquedas caras (modelo del mapa, referencia del mapa,
scan del lobby). El veredicto se recalcula en cada llamada: cachear el veredicto
retrasaba muerte/lobby hasta un frame y dejaba pasar la acción justo en el
estado que debía bloquear.

Además, al salir de ronda se limpia **siempre** la memoria de ronda
(`rememberedBagAmount`, `fullHandled`, `collectAttempts`), no solo cuando se
detecta la transición. Un `CoinCollected` viejo ya no puede sobrevivir al lobby.

## 3. Auto Farm: por qué no agarraba monedas y qué hace ahora

El hitbox `4×8×4` es **local**: agrandar `HumanoidRootPart` cambia lo que colisiona
tu cliente, no lo que ve el servidor. Un farm que se aparca tres studs debajo de
la moneda y solo pulsa un `firetouchinterest` local no tiene garantía de cobro.

- **Below**: conserva el viaje oculto con `LinearVelocity` + `AlignOrientation` +
  NoClip, pero cuando llega al contacto y la moneda no ha desaparecido, hace
  **una colocación física acotada dentro del volumen del pickup** (centro del
  root en la moneda, erguido, mismo yaw), pulsa el touch desde ahí y vuelve a
  bajar en el frame siguiente. Máximo **2 intentos por moneda**, separados
  `0.35 s`; después la moneda entra en blacklist y el farm sigue.
- **Walk**: mismo fallback acotado, para pickups que están por encima del suelo
  (mesa, repisa) y que caminar nunca alcanza.
- `state.fireTouchInterest` ahora **se resuelve en cada llamada**. Antes se leía
  una sola vez en el boot (`getfenv().firetouchinterest`); si el executor no lo
  exponía en ese instante, **toda** recogida instantánea quedaba muerta en
  silencio (monedas, gun tirada, contactos de cuchillo). Se cachea en cuanto
  aparece.
- El contador `Coins Collected` solo cuenta confirmaciones: si el servidor nunca
  manda `CoinCollected`, cuenta el pickup que desapareció mientras el personaje
  estaba aparcado en él; nunca se mezcla con el bag autoritativo y nunca se
  inventa un bag lleno.

## 4. CPU: qué se dejó de pagar

- Auto Farm conectaba **dos** writers por frame (`Stepped` y `PreSimulation`) más
  una tarea de `Heartbeat`. Ahora conecta solo el que el modo usa (`Stepped` en
  Walk, `PreSimulation` en Below) y lo cambia al cambiar de modo.
- La lista de pickups compartida (`state.mm2CoinPickups`) hacía un
  `workspace:GetDescendants()` completo cada `0.5 s` mientras el farm la
  consultaba cada `0.1 s`. Ahora el scan se hace como máximo **1 vez por
  segundo**, y el farm la invalida explícitamente cuando cobra o cuando descarta
  una moneda. La detección completa (tag `CoinVisual` + atributo `CoinID` +
  estructura `Coin_Server`/`CoinVisual`) **no** se reemplazó por una heurística
  barata: v84 ya demostró que eso deja de ver monedas en vivo.
- El overlay ya no reescribe el mismo texto cada frame.
- El scan de lobby del farm pasó de `0.75 s` a `1.5 s`, y la referencia del mapa
  quedó memoizada.

## 5. Validación (offline)

```bash
python3 tools/build_bundle.py --stamp v144-20261027-touch-momentum-farm-collect
bash tools/validate.sh
```

Resultado: `bundle.lua current: 90 files`, `PASS 92 Lua sources compile`,
`PASS 65 Python/Luau suites`, boot `failures=0`, `call sites checked: 110`,
`PASS menu audit: 50 cards`, `PASS release menu: 49 cards`.

Suites actualizadas con el contrato nuevo:

- `tools/test_fling_physics.py`: el fling dirigido y el Touch ya **no** tocan
  Humanoid/colisiones locales por contacto; exige impulso al objetivo, un solo
  paso local sin giro, restauración en `Heartbeat`, colisiones con snapshot y
  expiración del contacto sin repetición.
- `tools/test_mm2_auto_farm_dynamics.py`: añade el escenario Below de collect
  físico acotado (colocación en la moneda, pulso, máximo 2 intentos) y mantiene
  los guards de muerte/lobby y la idempotencia del bag lleno.
- `tools/test_mm2_auto_farm.py`: contrato estático de `roundContext`,
  `attemptCollect` y `ensureFarmSignals`.

Esto es estructura, orden y llamadas en mocks. **No** demuestra knockback
aceptado por el servidor, monedas cobradas, ni FPS. La aceptación live sigue
pendiente y depende del veredicto del usuario.
