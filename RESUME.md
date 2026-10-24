# RESUME — Wurst (MM2) · Handoff para el próximo agente

> Léelo entero antes de tocar nada. Resume el estado real del proyecto, las
> reglas del usuario, y los errores que ya se pagaron una vez. Si algo aquí
> contradice lo que crees, gana este documento (y los datos de calibración).
>
> **Estado al escribir esto:** rama `arena/e412e3e8-arandommenu`, sucesor de
> `e9aa057`, build **`v116-20261024-x2duels-halloween`**.
> El usuario se comunica en español. Respóndele en español.

---

## 1. Qué es esto y cómo llega al usuario

- Menú "Wurst" para Roblox, foco principal **MM2** (place id `142823291`).
  También hay módulos universales y de otros juegos (BedFight, TRS, VD y
  X2Duels/MVS).
- El loader carga el **bundle**: `getgenv().WURST_BRANCH = "arena/e412e3e8-arandommenu"`.
- **Protocolo de publicación (obligatorio, sin excepciones):**
  1. Edita en `src/…`, nunca directamente en `src/libraries/bundle.lua`.
  2. Sube `SOURCE_STAMP` en `src/Wurst.lua` (`vNNN-AAAAMMDD-descripcion`).
  3. `python3 tools/build_bundle.py --stamp <el mismo stamp>`
  4. `bash tools/validate.sh` — debe terminar VERDE (81 fuentes, 61 suites,
     boot `failures=0`, auditoría de menú 38/37 tarjetas).
  5. Commit + push **normales** a `arena/e412e3e8-arandommenu`. Sin force-push,
     sin reescribir historia, sin trabajar en otra rama.
- Sin bundle regenerado + stamp, el cambio **no llega al usuario**. El watermark
  "UI Settings · vNNN" en el menú es como el usuario verifica la versión.

## 1A. X2Duels (MVS): evidencia y contratos

- PlaceIds registrados: `92876937625630` y el MVS anterior `135856908115931`.
  Fuentes: `Rules.lua`, `base.lua`, `Other/AutoFarm.lua` y `Render/TeamESP.lua`,
  más sus dos perfiles. La sección de menú existente se llama `MVSD`.
- Hay exactamente siete tarjetas X2: Auto Farm, Auto Win, Silent AIM, Knife
  Throw, Kill Aura, Hitbox (Exploits) y Team ESP. El único TriggerBot es el
  universal, adaptado al core X2 para Gun/Knife; no se debe crear otra tarjeta.
- Auto Shoot es una subopción de Silent AIM, sigue el master y muestra
  Legit/Silent. Play Again es una subopción de Auto Win. Sender CFrame/Button
  usa `Tool:Activate()` y no depende de `mouse1press` ni inyección de mouse.
- Auto Farm busca monedas Halloween `PumpkinCurrency_*` por contacto nativo,
  reintenta y restaura el CFrame al apagarse. Un intento no se cuenta como
  moneda confirmada. El RBXL guarda esas partes con `CanTouch=false`; la
  recolección real sigue pendiente y no se inventan argumentos para
  `CollectEventSpawnable`.
- Auto Win controla el combate de ronda, dispara al inicio, cuenta solo
  victorias locales explícitas y se apaga en 5/5. `RemovePlayer` marca el fin
  de ronda y reactiva el escaneo de Play Again; no cuenta una victoria por sí
  solo. Play Again pulsa el botón GUI visible, incluidas etiquetas hijas.
  `RematchTeleport("back_to_lobby")` no es un sustituto probado de Play Again.
- Team Check falla cerrado: aliados y lados desconocidos no son objetivos; el
  ESP usa rojo/verde/ámbar. No convertir una pantalla ambigua en una victoria.
- El log más reciente de TestingStuff no capturó Shoot/Throw/Hit/Damage. No se
  deben inventar argumentos ni reintroducir GUID/remotes históricos. El
  extractor independiente `tools/X2DuelsDecompiler.luau` vuelca fuentes,
  bytecode, inventario con parents y argumentos entrantes/salientes; su guía es
  `tools/X2DuelsDecompiler.md`.
- `python3 tools/test_x2duels.py` ejecuta 61 reglas, contratos y un boot real
  del bundle con siete tarjetas, modos, Auto Win 5/5, RemovePlayer→Play Again,
  contacto/restauración de pumpkin y cleanup. `python3
  tools/test_x2duels_decompiler.py` valida el extractor con DataModel simulado.
  Todo ello es validación offline, no aceptación del servidor ni precisión live.

## 2. La trampa de los dos árboles Shoot (NO repetir)

- Hubo una divergencia real: `src/games/MM2/Blatant/Shoot.lua` llegó a ser un
  *solver standalone* de 1,051 líneas sin módulo Prediction, mientras el bundle
  ejecutaba el Shoot de menú de 852 líneas con `state.mm2Prediction`.
- La telemetría del usuario lo zanjó: sus sesiones emiten `model: "kinematic-v51"`
  + `rttEngine`/`echoSamples`/`leadCorrection`, que **solo existen en el árbol
  de menú** (Prediction-driven). Ese es el producto. En v106 se restauró el
  árbol de menú desde `734635c` y se trabajó ahí.
- `Shoot_WallCheck_Standalone.txt` es un artefacto aparte para pegar suelto.
  **No es la fuente del menú.** No mejores el standalone pensando que arreglas
  el menú, y no aceptes "Both trees": es como nació la divergencia.
- Si un revisor externo cita métricas como `maxError`, `errorRadius`,
  "Shot accuracy is too low to fire." o `gunAcceptanceMs=514`: **no existen**
  ni en el código ni en los logs. Verifica cada cifra contra el archivo exacto
  antes de actuar.

## 3. Shoot / Prediction — lo medido, no lo adivinado

- Horizonte correcto = **pipeline completo (eco FireServer→GunFired o ping) +
  interpolación 25 ms**, cap 0.6 s. Confirmado con ShootProbe ×3 y telemetría:
  el servidor puntúa a ~ping + 20–26 ms sobre la línea temporal del cliente.
  **No dividas el lead entre 2** (v85 lo probó y falló sistemáticamente corto)
  y no toques el lead global sin una sesión de calibración que lo pida.
- **Envenenamiento del eco (la saga v103→v105):** emparejamientos tardíos de
  confirmación (416–1840 ms) entraban en la mediana del eco y la arrastraban de
  106 → 532 ms, adelantando cada disparo ~0.4 s. Defensas actuales en
  `Prediction.lua` (`noteEcho`):
  - Puerta de plausibilidad: `delay ≤ clamp(currentRtt()*2.5 + 0.05, 0.30, 1.6)`
    (usa `currentRtt()`, **no** `robustRtt()` — el harness lo rompe).
  - Auto-reset por divergencia: mediana > 1.5×RTT ⇒ se limpia la ventana y el
    lead cae a ping hasta reunir 3 ecos frescos.
  - Expiración por edad: ecos de más de 30 s no cuentan.
  - Corrección cerrada por `leadErrors`: cap ±60 ms, descarta |error| > 150 ms.
- **v106, dos arreglos desde telemetría v105:**
  1. `safeToSend` pasaba el origen *silent* (cerca del objetivo) como muzzle a
     `validateGunShot(target, character, targetCharacter, muzzle, origin,
     endpoint, walls)` — el check de línea de visión salía desde el objetivo y
     nunca veía muros ni transeúntes entre la pistola y el blanco. Ahora muzzle
     = pistola real. Confirma la firma antes de tocar esa llamada.
  2. Gate de un disparo pendiente: `SHOT_CONFIRM_WINDOW = 1.5` s. 14 peticiones
     a ~0.1 s sin eco en la sesión v105; cada petición tras un eco fue respondida.
     En v109 el gate se hizo visible: mensaje con tiempo restante, contador en
     `state.mm2ShotGateHold` y acción "Shot gate status".
- **Cómo leer una calibración sin engañarte:**
  - `hitTarget` (el rayo tocó el personaje) **≠ kill**. Una sesión tuvo 20
    hitTarget y 0 kills con la salud siempre a 100 (lobby/intermisión/blancos
    quietos). Mira `died`/kills y filtra: velocidad ≈ 0, latencias extremas,
    `healthAfter = nil`, endpoint idéntico repetido = blancos de relleno.
  - Sesiones con el bot **volando o todo `targetJumped`** (velocidades hasta
    60, vy −61…+59) **no sirven para calibrar precisión en suelo**. Ya se han
    perdido dos análisis por esto. Pide: Difícil / Patrón Auto / Saltos Normal /
    Sin extras, y 15–20 confirmados por modo en la misma sesión.
  - Recomendación práctica vigente (provisional, muestra pequeña): **Silent +
    Front**. v104 mixta: Front 3/4, Through 1/4, Prediction 3/10.
  - La telemetría vive en `MM2_Trajectory_Calibration.json` (+ `.before-*`).
    Campos útiles: `session.gunByMode`, `session.predictionError`,
    `endpointErrorStuds`, `serverEchoMs`, `leadErrorSeconds`, `silentSpawn`.
    Replay offline: `tools/replay_gun_prediction.py`.

## 4. Evidencia: repo TestingStuff

- `XzAngel19/TestingStuff` (público) guarda los logs y calibraciones del
  usuario. **Solo lectura y solo como evidencia.** Reglas:
  - Cada archivo es de UN build: mira `buildStamp` dentro antes de concluir.
    No promedies entre builds. El más reciente no siempre es el de la raíz:
    busca el nombre con la versión (p. ej. `MM2_Trajectory_Calibration_v105_2026-10-23.json`,
    sesión `F9F125A2…`).
  - No subas código ahí, no copies implementaciones desde ahí, y nunca subas
    credenciales/tokens/configs de executor. Es público.

## 5. Auto Farm / Auto Get Gun — reglas duras del usuario

- Movimiento: **física, jamás CFrame por tick** — MM2 expulsa con error 267
  ("Invalid position"). Walk = `Humanoid:Move` con slider 5–60. Below (Hitbox)
  = vuelo por velocidad, erguido, NoClip, root 4×8×4, centro 3.0 bajo la moneda.
  **Prohibido el prone/tumbar el cuerpo** (rechazado dos veces) y prohibido el
  movimiento en dos fases.
- Acciones de bolsa llena (50) **solo** con bolsa llena: Kill All → Teleport to
  Map → Auto Grab + Shoot → Reset → Flings. Nada de esto en el farmeo normal.
- **Auto Grab / Auto Get Gun: solo Innocent, solo ronda activa, nunca Murderer,
  nunca lobby.** Fail-closed: si el rol no se conoce positivamente
  (`getPlayerRole(LocalPlayer) == "Innocent"` + `isRoundLifecycleActive()` +
  `findMM2Map()`), no actúa. (Kill All sí es de Murderer, por diseño.)
- Recogida instantánea: pulso `firetouchinterest` raíz↔parte de la gun
  (`state.fireTouchInterest`), el mismo mecanismo que las `Coin_Server`.
  Auto Get Gun **ya no teletransporta**; el botón/tecla manual "Get Gun" sí
  sigue siendo teletransporte porque es un acto explícito del usuario.
- Al terminar/devolver el personaje: **Teleport to Map a un spawn aleatorio**
  (`map.Spawns`, +3 studs, erguido, velocidades a cero), nunca el CFrame "home"
  guardado — tras Below ese punto puede estar bajo el suelo y el personaje se
  quedaba encajado. Sin mapa activo (lobby), el retorno a home sí aplica.

## 6. Velocidad: qué significa "instantáneo" aquí (v112)

- El suelo físico es **un frame** (Heartbeat ≈ 16.7 ms a 60 FPS) + ping. Todos
  los `TaskManager:Connect` corren por Heartbeat; los binds disparan en el evento.
- Eliminado en v112: poll de 0.5 s de Auto Get Gun (ahora cada frame + tick
  inmediato al activar) y caché negativa de `findDroppedGun` 0.4 s → 0.05 s.
  Auto Farm espera *condiciones* frame a frame, no sleeps fijos.
- **Delays deliberados que NO debes "optimizar"** (están fijados por
  `tools/test_action_latency.py`, que falla si los quitas o si reintroduces
  los de arriba):
  - Shoot: gate 1.5 s entre disparos (ver §3).
  - KnifeThrow: intervalo de paquete 0.25 s + ciclo de animación. **La animación
    del throw debe verse** (sin ella es blatant); se eliminó "Throw with button".
  - KnifeAura: ciclo de swing medido 0.86 s.
  - Auto Unbox: delay entre cajas **configurable y a propósito lento** — es el
    arreglo de la pantalla gris/negra al spamear. No lo aceleres.
  - Rates con slider del usuario (TriggerBot Delay, KillAura swings/s, etc.):
    son suyos, no delays ocultos.
  - Refrescos de status/visuales a 0.2–5 s (ESP, Chams, Coin ESP): no retrasan
    ninguna acción.

## 7. Otros módulos — decisiones ya tomadas

- **Coin ESP:** detección por el mecanismo real del juego:
  `CollectionService:GetTagged("CoinVisual")`, pareja `CoinContainer[Model] >
  Coin_Server[Part] > CoinVisual[Part]`, familia activa por `CoinsStarted`
  (Coin/Candy/SnowToken/BeachBall/Egg). Render: UN `BoxHandleAdornment`
  ×1.3 del tamaño del pickup, **sin Nametags/Highlight/clones**. El cheap-scan
  de v84 detectó cero en vivo: no lo reintroduzcas.
- **Disguise:** 17 packs oficiales por dropdown persistido + resolución
  dinámica de bundles UGC por ID (`GetProductInfo`, exigir
  `BundleType == "AvatarAnimations"`). El rig de MM2 es `AnimationConstraint`
  ×15, **sin Motor6D ni Animate.Disabled**. ÚNICO juez de validez fiable:
  `GetProductInfo` (los probes con `LoadAnimation` spamean y con
  `PreloadAsync` condenan todo — no los resucites). v101 va sin bridge ni
  driver, a propósito. Que otros te vean animado exige tracks reales en tu
  Animator; el espejo es solo local. "Show Advanced": al abrirlo, el pack se
  quita al instante y vuelven las animaciones por defecto hasta que el usuario
  pega IDs por slot (Idle/Walk/Run/Swim/Jump/Fall/Climb/SwimIdle). El desync
  Mage→Ninja era real y se arregló en v97 (juicio por GetProductInfo, slots
  primero). **Pendiente solo veredicto en vivo del usuario.**
- **Menú:** las posiciones de ventana sobreviven a cualquier resize
  (`homePositions` en WindowManager — `Reclamp()` no debe persistir posiciones
  clampadas). Watermark de versión junto a "UI Settings".
- **Anti Fling** (= Anti Void; el usuario lo llama "Auto Fling") y **Anti AFK**
  ("Auto AFK"): v108 dejó Anti Fling sin slider, con umbrales derivados del
  propio cuerpo (spin 20 rad/s, velocidad 2.2×WalkSpeed, salto 3×JumpPower) y
  sin depender de Anti Void.
- **TargetBot** (`tools/diagnostics/TargetBot.lua` v5): el único actuador que
  mueve en MM2 es `Humanoid:MoveTo` (`Humanoid:Move` y empujes por velocidad
  son ignorados — probado). Debe verse natural, no chocar con paredes, saltar
  de verdad, respetar la distancia; Caótico/Imposible extremos (vuelo, dash,
  blink) van aparte. Mini-menú para detenerlo y configurar.
- **EliminatePlayer:** solo en servidor privado con una cuenta alt. Nunca en
  partida viva.
- Cajas MM2: `Remotes.Shop.OpenCrate:InvokeServer(boxId, "MysteryBox"|"Eggs",
  currency)`; una a la vez + reveal ~5 s = sin pantalla gris. KnifeBox1-5,
  MysteryBox1/2, GunBox1-3, cajas de evento por temporada.

## 8. Errores de proceso (los caros)

1. **Commits desde un workspace reseteado regresaron el árbol a v50 una vez.**
   Si `git status` muestra HEAD en `40aba40` ("Create README.md") con cientos
   de archivos "modificados", el workspace está mezclado: el árbol bueno es el
   del tip remoto. Verifica con `git show origin/arena/...:<archivo>`,
   publica con índice temporal + `git commit-tree` sobre el tip remoto y
   `git update-ref`. Nunca fuerces.
2. **CRLF (v107, commit hecho en Windows):** convirtió 6 archivos de texto a
   CRLF y `validate.sh` moría en Linux (`pipefail\r`). Ya hay `.gitattributes`
   (`* text=auto eol=lf`). No lo quites.
3. **Editar el mismo archivo con varias llamadas en paralelo pierde
   ediciones** (pasó dos veces: el edit "exitoso" no estaba en el archivo).
   Ediciones al mismo archivo: **secuenciales**, y verifica con grep antes de
   compilar.
4. La toolchain Luau no persiste entre sesiones: `bash tools/luau/setup.sh`
   (hay `luau` y `luau-compile` en `tools/luau/bin`). Sin red a
   `raw.githubusercontent` (SSL): usa `gh api` o clone.
5. `tools/audit_module_api.py` corre desde validate.sh: todo `core.*` /
   `prediction.*` llamado debe existir como export en `state.mm2Core` /
   Prediction. Si añades una llamada, añade el export o el test te detiene.
6. Los tests son la red: si un test espera el comportamiento viejo y tu cambio
   es correcto, **actualiza el test explicando el porqué en el comentario**
   (pasó con la puerta de eco en v104/v105). No hagas que el código mienta
   para que un test viejo pase.

## 9. Pendiente de verificación EN VIVO (no lo des por hecho)

Nada de esto está probado en partida real todavía; está probado en estático,
boot y las 61 suites:

- Shoot v106–v112: si con el muzzle real desaparecen los impactos en geometría
  del mapa (`Smooth Block Model`), y si el gate de 1.5 s recupera los ecos.
- La sesión limpia que falta: bot en el suelo de verdad (Difícil/Auto/Saltos
  Normal/Sin extras), 15–20 confirmados por modo (Prediction, Silent Front,
  Silent Through). Sin eso, no se retoca el predictor.
- Auto Farm v107–v111: roaming sin monedas, void guard, Teleport to Map al
  terminar, y si el toque instantáneo entrega la gun tras el teletransporte.
- Fling por network ownership (v107) y Anti Fling (v108) contra un fling real.
- Disguise v101: packs del objetivo / por ID, en servidor.
- Salidas del standalone (Step 1 nil-parent, Step 4 origen) y TargetBot v5.
- X2 v116: recolección real de Halloween, activación nativa de Gun/Knife,
  precisión del throw, Team ESP/filtro con datos live, Sender CFrame en móvil,
  y cinco victorias con RemovePlayer/Play Again. El harness cubre la máquina de
  estados, no los argumentos ni la aceptación del servidor. La siguiente
  evidencia debe obtenerse con `tools/X2DuelsDecompiler.luau`.

## 10. Cómo trabajar con este usuario

- Aporta las calibraciones **antes** de pedir cambios: analízalas (con los
  filtros de §3) y da veredicto con números de SU archivo, no de memoria.
- No toques el predictor sin datos. No generalices desde n=4. Si la muestra es
  pequeña, dilo y pide la sesión que falta, con la configuración exacta.
- Cuando algo no se puede verificar desde aquí, dilo explícitamente y separa
  "verificado" de "plausible" de "pendiente en vivo".
- Cambios pequeños, versionados (bump de stamp por cambio), con test que fije
  el comportamiento y `validate.sh` verde antes de pushear.

---
*Última actualización: v112 (2026-10-23). Al publicar una versión nueva,
actualiza la línea de estado de arriba y cualquier sección que cambie.*
