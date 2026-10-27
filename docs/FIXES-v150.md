# v150 — reconstrucción total de Fling / Anti fling / Anti Void / Touch Fling / Auto Farm

Rama: `arena/2ec6eed9-arandommenu`
Stamp: `v150-20261027-mm2-place-evidence-rebuild`
Build visible en el menú: **v150**

El usuario pidió borrar **todo** el código de esas cinco funciones y
reconstruirlo, y pidió leer "absolutamente todo lo posible" del repositorio
`TestingStuff` con el `place` para Auto Farm. Este documento es la bitácora de
esa lectura y de las decisiones que salieron de ella. Las secciones históricas
de `RESUME.md` (v144–v149) describen código que **ya no existe**.

---

## 1. Fuentes consultadas

### 1.1 Repositorio `XzAngel19/TestingStuff` (solo lectura)

| Archivo | Qué se extrajo |
| --- | --- |
| `place, source.rbxlx` (18,6 MB, XML) | Árbol completo de MM2, **303 scripts descompilados**, 115 `RemoteEvent`, 53 `RemoteFunction`, 23.591 instancias. Guardado con UniversalSynSaveInstance: `PlaceId 142823291`, `PlaceVersion 1447`, cliente `0.725.0.7251138`. |
| `Place_142823291_Murder Mystery 2_05-10-2026_19-35-36.rbxl` (binario LZ4) | Instantánea en ronda activa en el mapa `Bank2`: 29.021 instancias, 107 `Coin_Server`, 107 `TouchInterest` (`TouchTransmitter`), 157 transmisores en total. Incluye `Wurst_Chams`, es decir se guardó con el menú funcionando. |
| `Place_92876937625630_[DUELS] 2v2_11-10-2026_03-43-11.rbxl` | Instantánea de X2 Duels: 39.906 instancias, 919 scripts (casi todos *stubs* de descompilación), 189 remotos. Se revisó para no mezclar evidencia de otro juego. |
| `2026-10-15T23_30_07Z.log`, `...00_49_35Z.log`, `...22_14_51Z.log`, `...22_18_17Z.log`, `...22_19_27Z.log` | Logs de espía de remotos: 234 `CoinCollected`, 21 `CoinsStarted`, 21 `RoundStart`, 248 `PlayerDataChanged`, 35 `VictoryScreen`, 12 `TeleportToPart`, 12 `LoadingMap`, 127 `GetCurrentPlayerData`, 159 `HandleTouched` (del cuchillo). |
| `2026-10-24T05_32_41Z.log`, `2026-10-24T16_49_55Z.log` | Logs de X2 Duels (`DefaultGun`, `DefaultKnife`, `PlayerRespawned`, `SetDead`). |
| `Place_*_Game_Learning.json` (4 lugares) | Telemetría de disparos/movimiento; se revisó para descartar conclusiones de un build distinto. No contiene evidencia de Fling ni de CPU. |
| `MM2_Trajectory_Calibration*.json` | Calibraciones históricas de Shoot; no se tocaron (este cambio no toca el predictor). |
| `Shoot..txt` | Argumentos reales del remoto `Shoot` (origen/orientación); no se usa aquí. |

Se clonó todo el repositorio a `.cache/testingstuff` (ignorado por Git), se
descomprimió el XML con un extractor propio (`ElementTree`), se decodificaron
`Tags` y `AttributesSerialize` en Base64, y se escribió un lector del formato
binario RBXL (chunks LZ4, arrays entrelazados zig-zag) para los dos `.rbxl`.
No se subió nada a `TestingStuff`.

### 1.2 Documentación oficial de Roblox (consultada en esta sesión)

- [Network ownership](https://create.roblox.com/docs/physics/network-ownership.md)
  — el servidor siempre posee las partes ancladas; los eventos `Touched` están
  ligados a la propiedad de red.
- [BasePart](https://create.roblox.com/docs/reference/engine/classes/BasePart.md)
  — `CanTouch` debe ser `true` en **ambas** partes; `CanCollide=false` no
  desactiva `Touched`; dos partes ancladas nunca se tocan; `AssemblyLinearVelocity`
  es la velocidad del assembly.
- [Humanoid](https://create.roblox.com/docs/reference/engine/classes/Humanoid.md)
  — `Humanoid:Move()` es sobrescrito cada frame por el script de control por
  defecto; se evita con `BindToRenderStep` por encima de `Character`.
  `Humanoid:MoveTo()` usa `WalkToPoint` y expira a los 8 s si no se refresca.
- [PathfindingService](https://create.roblox.com/docs/reference/engine/classes/PathfindingService.md)
  — `CreatePath`/`ComputeAsync`/`GetWaypoints`, `AgentCanJump`, `PathStatus`.

---

## 2. Lo que el place dice del juego (MM2)

### 2.1 Física y colisiones

`Workspace` del lugar guardado:

```text
Gravity                    = 196.2
FallenPartsDestroyHeight   = -500
FallHeightEnabled          = true
TouchesUseCollisionGroups  = false
TouchEventsUseCollisionGroups = 0
StreamingEnabled           = false
Players.CharacterAutoLoads = false
StarterPlayer.CharacterWalkSpeed = 16
StarterPlayer.CharacterJumpPower = 50
```

Grupos de colisión (7): `Default`, `GiftDoor`, `AnchoredRagdolls`,
`Murderer`, `Ragdolls`, `Characters`, `PlayerNoCollision`. `Characters`
colisiona consigo mismo y con `Murderer`. Los mapas (`House2`, `Bank2`,
`Mansion2`, `Office3`, `Workplace`) viven en `Y ≈ 240…280` y **no tienen suelo
por debajo**; hay partes invisibles `GlitchProof` grandes (`CanCollide=true`,
`Transparency=1`) bajo/entre los pisos. Un "Below" que vuele bajo el mapa choca
con esas partes y además no puede tocar las monedas desde el servidor.

### 2.2 Monedas: el mecanismo real de cobro

En el XML (fin de ronda, `House2`) y en el binario (ronda activa, `Bank2`):

```text
workspace.<Mapa>.CoinContainer
  └─ Coin_Server (Part)            tag "ServerCoinPart"
       ├─ CoinVisual (Part)        tag "CoinVisual"
       │    ├─ MainCoin (MeshPart)
       │    ├─ DecalPart
       │    └─ 2Part
       └─ TouchInterest (TouchTransmitter)   ← 107/107 en el .rbxl
```

Propiedades de `Coin_Server`:

```text
Anchored = true, CanCollide = false, CanTouch = true, CanQuery = true
Size = 1.2 x 2 x 2, Transparency = 0 (viva) / 1 (cobrada)
CollisionGroup = "Default"
Atributos: CoinID = "Coin"   (+ Collected = true tras el cobro)
CoinVisual añade IsSetup / RoundEnd al terminar la ronda.
```

El lugar tiene `CoinVisualizer.lua`, `CoinBagContainerScript.lua` y
`CurrentRoundClient.lua` (cliente), y `Remotes/Gameplay/*`. **No hay ningún
script de cliente que pida una moneda**: el único camino es el `Touched` del
servidor sobre esas partes ancladas. Los logs confirman el contrato:

```text
CoinsStarted  → { Coin = { CollectedAmount = 0, CollectionLimit = 50 } }
CoinCollected → ("Coin", 1..50, 50, { Value = 1 })
RoundStart    → (180, { [Nombre] = { Role, Dead, Coins, ... } })
RoundEndFade  → (true)
VictoryScreen → (won, "Hero"|"Murderer", reason, player, n)
TeleportToPart→ (workspace.<Mapa>.Spawns:GetChildren()[k])
LoadingMap    → ("Classic")
ChangeInventoryItem → ("Materials", "Coins", saldo_persistente)
```

`RoundTimerPart:GetAttribute("Time")` cuenta los 180 s (`RoundLength` = 180);
el mapa activo lleva el tag `CurrentMap` y el atributo `MapID`, y expone
`Spawns` con `Part` llamados `Spawn`. `CharacterClient.lua` responde a
`TeleportToPart` con **un** `character:PivotTo(CFrame.lookAt(...))`: un
teletransporte puntual es un mecanismo del propio juego; un `CFrame` por frame
no lo es.

Conclusión dura: `firetouchinterest` desde el cliente dispara eventos locales,
pero **no puede disparar el `Touched` del servidor** de una parte anclada que
el servidor posee. Las monedas se cobran solapando físicamente el personaje con
el volumen de `Coin_Server`. Cualquier contador que cuente intentos locales no
está contando monedas.

### 2.3 Movimiento

`ControlsEnable.lua` habilita el `PlayerModule` estándar, así que
`Humanoid:Move()` escrito una vez se pierde en el siguiente frame. La
documentación oficial recomienda `BindToRenderStep` con prioridad mayor que
`Character`; `MoveTo()` es la alternativa con `WalkToPoint` y timeout de 8 s.
`CoinESP` del propio menú ya publica `state.mm2CoinPickups()` con las partes
visuales reales (filtra `Collected`/`Delete`).

---

## 3. Qué se borró y qué se reconstruyó

Se reemplazaron **por completo** (no se parchearon) estos archivos:

| Archivo | Antes | Ahora |
| --- | --- | --- |
| `src/libraries/Fling.lua` | `walkfling` de IY: `velocidad * 1e6 + 1e6Y` en ventana RenderStepped, restaurada antes de `Stepped`, pulsos 0.18 s | **Impulso finito y acotado** (`ApplyImpulse`, 190 studs/s) sobre un assembly que el cliente puede gobernar: root del objetivo si `GetNetworkOwner()` confirma la propiedad, si no root propio por contacto. Sin giro, sin constraints, sin CFrame por frame. |
| `src/games/MM2/Blatant/Fling.lua` | Adaptador con bucle bloqueante `task.wait`, sesión dirigida | Adaptador con cola para "Fling All Innocents" (sin bloqueo), misma lista viva de jugadores con rol, mismas claves de configuración. |
| `src/games/universal/Blatant/TouchFling.lua` | Interruptor del motor IY | Interruptor del nuevo controlador, `restore = false`. |
| `src/games/universal/Movement/AntiVoid.lua` | Plataforma física `256x4x256` durante 3 s + anti-fling con strip por frame | **Anti Void**: recuerda el último `CFrame` en suelo y hace **un** `PivotTo` acotado cuando cae sin suelo debajo (raycast). **Anti fling**: amortigua el root local y quita colisiones de un flinger cercano **una vez por ventana de 0.45 s**, con lista de partes cacheada. |
| `src/games/MM2/Other/AutoFarm.lua` | 2249 líneas: Walk/Below, hitbox `4x8x4`, `LinearVelocity`+`AlignOrientation`, `firetouchinterest`, zona segura, Kill All / flings / Auto Grab al llenar la bolsa | ~1000 líneas: descubrimiento real de `Coin_Server`, navegación nativa (`BindToRenderStep` + `Humanoid:Move`, fallback `MoveTo`), `PathfindingService` opcional, salto nativo, conteo **solo** desde `CoinCollected`, guards de ronda/rol/muerte, rescate de vacío acotado, y cero writers de física. |

También se reescribieron las suites que fijaban el contrato viejo:
`test_fling_physics.py`, `test_antivoid50.py`, `test_mm2_auto_farm.py`,
`test_mm2_auto_farm_dynamics.py`, y se actualizaron
`test_action_latency.py` y `gen_full_boot_harness.py`. No se relajó ningún
requisito: los tests nuevos exigen el comportamiento nuevo y prohíben
explícitamente los mecanismos retirados.

### 3.1 Decisiones de diseño

1. **Auto Farm ya no finge cobros.** `firetouchinterest` se eliminó del módulo.
   El farm camina hasta `Coin_Server`, se queda dentro de su volumen y espera
   el `CoinCollected` del servidor; si en 2.5 s no llega, descarta esa moneda
   8 s. `Coins Collected` solo aumenta con ese evento.
2. **Sin CFrame por tick.** Solo hay un `PivotTo` puntual en el rescate de
   vacío (y uno de colocación/retorno por sesión de Fling), igual que el
   `CharacterClient` del juego. Nada de `root.CFrame =` en bucles.
3. **Un solo dueño del movimiento.** Auto Farm enlaza un `BindToRenderStep`
   después del control por defecto; si el host no lo soporta, usa `MoveTo`
   refrescado en cada paso. No compite con Speed: no toca `WalkSpeed`.
4. **Fail-closed en ronda/rol.** `isRoundLifecycleActive`, `getRoundPhase`,
   `findMM2Map`, `RoundTimerPart.Time`, `getPlayerRole == "Innocent"`,
   Humanoid vivo, y cesión a `fling`/`teleport`/`ghost`/`Fly`.
5. **Bolsa llena = parar.** Se eliminaron las acciones terminales (Kill All,
   flings, Auto Grab + Shoot, reset) que solo añadían superficie de fallo.
6. **Fling sin mentiras.** El impulso es finito. Si el executor expone un
   setter de network ownership y `GetNetworkOwner()` lo confirma, el impulso
   va al root del objetivo; si no, va al root local y el contacto entre
   personajes (grupo `Characters` colisiona consigo mismo) transfiere el
   momento. `lastStrategy()` expone qué camino se usó. No se afirma knockback
   aceptado por el servidor desde un mock.

---

## 4. Validación offline

```bash
python3 tools/build_bundle.py --stamp v150-20261027-mm2-place-evidence-rebuild
bash tools/validate.sh
```

Resultado:

```text
PASS 84 fuentes en el bundle (mismo stamp)
PASS 66 Python/Luau suites
PASS bundle boot, failures=0
PASS 103 call sites core.*/prediction.*
PASS menu audit: 50 tarjetas
PASS release menu: 49 tarjetas, sin Calibration
```

Las suites nuevas comprueban: impulsos finitos, orden de frames/actividad,
propiedad liberada, cooldown de Touch, OFF/destrucción, amortiguación sin
teletransporte, strip restaurado, rescate único de vacío, caminata nativa,
conteo solo con `CoinCollected`, límite de bolsa, guards de lobby/rol,
limpieza de listeners y snapshot de estado.

---

## 5. Pendiente de aceptación EN VIVO (no se da por hecho)

1. Que el servidor de MM2 acepte el knockback del nuevo impulso (con y sin
   propiedad de red). Si falla, el primer número a revisar es
   `PULSE_SPEED` en `src/libraries/Fling.lua`, no la lógica.
2. Que un solapamiento físico real con `Coin_Server` dispare el `Touched` del
   servidor y llegue el `CoinCollected`. Observar `Coins Collected` y el saldo
   de `ChangeInventoryItem ("Materials","Coins",...)`.
3. Que `BindToRenderStep` + `Humanoid:Move` mueva de verdad al personaje en
   MM2 con el `PlayerModule` activo; si no, probar el modo `Direct`/`MoveTo`.
4. Que PathfindingService encuentre rutas en mapas multinivel con
   `GlitchProof`; si no, usar `Navigation = Direct`.
5. Que el rescate de vacío de Anti Void/Auto Farm no pelee con el del otro
   módulo (Auto Farm cede si la tarjeta Anti Void está ON).
6. Rendimiento A/B (Physics/Render/FPS) con los cinco módulos activos.

---

## 6. Alcance

`src/games/X2Duels/Other/AutoFarm.lua` **no se tocó**: pertenece a otro juego
(place `92876937625630`), tiene su propio contrato (`PumpkinCurrency_*`,
podios, `PumpCoins`) y su propia suite (`test_x2duels.py`). La evidencia y la
petición de esta versión apuntan al `place` de MM2. Si se quiere reconstruir
también ese farm, debe hacerse con la evidencia de X2 y sus pruebas, en un
cambio separado para no mezclar builds.
