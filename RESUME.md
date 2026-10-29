# RESUME — Wurst · Handoff y guía de arquitectura de games

> Léelo entero antes de tocar nada. Resume el estado real del proyecto, las
> reglas del usuario, y los errores que ya se pagaron una vez. Si algo aquí
> contradice lo que crees, gana este documento (y los datos de calibración).
>
> **Estado al escribir esto:** rama `arena/9492e6b6-arandommenu`, build
> **`v155-20261029-x2duels-cframe-knife`**.
> El usuario se comunica en español. Respóndele en español.

---

## 1. Qué es esto y cómo llega al usuario

- Menú "Wurst" para Roblox, foco principal **MM2** (place id `142823291`).
  También hay módulos universales y de otros juegos (BedFight, TRS, VD y
  X2Duels/MVS).
- El loader carga el **bundle**: `getgenv().WURST_BRANCH = "arena/9492e6b6-arandommenu"`.
- **Protocolo de publicación (obligatorio, sin excepciones):**
  1. Edita en `src/…`, nunca directamente en `src/libraries/bundle.lua`.
  2. Sube `SOURCE_STAMP` en `src/Wurst.lua` (`vNNN-AAAAMMDD-descripcion`).
  3. `python3 tools/build_bundle.py --stamp <el mismo stamp>`
  4. `bash tools/validate.sh` — debe terminar VERDE (v145: 93 fuentes,
     64 suites, boot `failures=0`, auditoría de menú 51/50 tarjetas).
  5. Commit + push **normales** a `arena/9492e6b6-arandommenu`. Sin force-push,
     sin reescribir historia, sin trabajar en otra rama.
- Sin bundle regenerado + stamp, el cambio **no llega al usuario**. El watermark
  "UI Settings · vNNN" en el menú es como el usuario verifica la versión.

## 1P. Rendimiento MM2 v141 — evidencia y límites

- La queja era CPU alta y carga lenta. Sin MicroProfiler/F9 del dispositivo no
  se conoce la causa exacta ni hay porcentaje de mejora en Roblox. El boot mock
  y los conteos siguientes no son tiempos, consumo real ni aceptación del juego.
- `Prediction.lua` conserva los **60 Hz**, el historial y la calibración pasiva
  con todo apagado; no bajar la frecuencia para ahorrar CPU sin probar la
  precisión inmediata. Ahora cachea Humanoid, root y UpperTorso mientras sigan
  válidos y vuelve a buscar ante reemplazo/respawn. Mismo mock y 60 ticks por un
  jugador R15: v140 hizo 60+60+60 búsquedas, v141 hizo 1+1+1.
- `base.lua` comparte un cache de lobby y referencia para core/Auto Farm/Auto Win,
  con invalidación por llegada/remoción/streaming y 0,25 s de retry en ausencia.
  El core mantiene su clasificación de lobby directo; farm/win mantienen además
  el fallback estacional anidado. En un mock con lobby estable, 120 consultas de
  Auto Farm pasaron de 120 `GetChildren` y 240 búsquedas recursivas a 1 y 2.
  La caché no debe retrasar detección del mapa en countdown ni activar farm en
  lobby. Las señales se desconectan al descargar.
- Auto Farm ya no retrocede `scanAt` si no encuentra objetivo: con lista vacía
  consulta cada ~0,1 s en vez de cada frame, y con lista no vacía cada ~0,25 s.
  En el mismo mock de 120 frames vacíos pasó de 119 consultas a 18; una moneda
  nueva aparece en la siguiente ventana. Coin ESP conserva los tres mecanismos
  reales de detección y su escaneo, no reintroducir el cheap-scan v84.
- Silent AIM instala el hook global `__namecall` solo al habilitarlo y lo
  desmonta si sigue siendo el hook superior. Si otro script lo envuelve, deja
  un bridge inerte y reutilizable sin desplazar ese hook. La versión v140 ya
  inyectada puede haber dejado su hook anterior, que no se puede retirar de modo
  fiable: para comparar v141 se debe reiniciar Roblox o volver a entrar. Los
  wrappers PC/móvil de WeaponService de Silent AIM y Knife Throw se retiran por
  identidad, conservan scripts ajenos y se desenrollan en ambos órdenes.
- El JSON de calibración aportado mide 4.917.941 bytes y 648 eventos: se lee,
  respalda byte a byte y decodifica al inyectar; con cambios se guarda cada 10 s.
  Puede aportar demora/picos, no demuestra por sí solo CPU al 100 %. No diferir
  lectura/backup ni borrar datos sin resolver sincronización, reset y fallos;
  `tools/test_mm2_v16.py` exige respaldo exacto y persistencia bloqueada si falla.
- `tools/test_mm2_performance.py` comprueba conteos, invalidación de rigs y
  lobby, countdown y monedas; `tools/test_mm2_hook_lifecycle.py` prueba OFF/ON,
  config restaurada, reinyección, hooks ajenos y PC/móvil + Knife en ambos
  órdenes. Validación completa v141: 92 fuentes, 64 suites, boot `failures=0`,
  51/50 tarjetas. Falta prueba live: perfil CPU por fase, menú apagado/activo,
  PC/móvil, executor, tiempo de inyección y revisión F9/MicroProfiler.

## 1Z. X2 v155 — Knife CFrame experimental a partir de fuentes capturadas

El usuario adjuntó cinco fuentes de `DefaultKnife` y su manifiesto 5/5. El
LocalScript principal muestra `Packages.Net["RE/ThrowEvent"]:FireServer(
"959d5e90-231d-4f6e-8861-050e2c22b938", CFrame.new(hitPosition), origin)`.
El origen depende del AB test `NormalKnifeThrow`: posición de Handle o
RightHand.RightGripAttachment (fallback Handle). Inmediatamente después el
juego fabrica un proyectil con `MakeLocalFlyingHandle`, inicializa `VelocityV`
y `VelocityVClient`, clona `ThrowingKinfeHandlerScript` con `creator`, lo
parenta en `RenderedObjects`/workspace y emite `ActivateThrowing:Fire`, con
Debris de 7 s. El handler nativo realiza colisiones y decide enviar `KnifeKill`;
**no se fabrica ni envía directamente ese remoto**. El servidor no está en la
captura y ninguna prueba confirma que acepte esto o produzca daño en vivo.

- `Knife Throw` ahora tiene acción de botón/tecla y `Auto Throw` independiente
  (por defecto ON para conservar el automático anterior; OFF para solo botón).
  En móvil se coloca tocando el pequeño cuadro de acceso de la tarjeta. El modo
  CFrame funciona con Silent activo o apagado sin hooks ni escribir cámara, y
  comparte el arbitraje de arma con Gun/Auto Win. El antiguo camino nativo aún
  existe para otras llamadas como TriggerBot, que no debe confundirse con esta
  ruta CFrame. Wall Check, equipo, vida, partida, protección, ronda terminada,
  infección zombi cuando el API la informa y distancia se vuelven a comprobar;
  se cancela si cambia objetivo/equipo, match, vida, estado o se apaga. La fuente
  de Knife dice `RoundStarted == false`, en conflicto con otras fuentes: no se
  reinterpreta ese campo sin evidencia de funcionamiento real.
- Falla sin enviar si falta ThrowEvent, Handle, BindableEvent, módulos del
  proyectil o ABTests, o el handler/creator; requiere estos componentes y el
  listener original ya iniciado al equipar. Usa el valor `Debounce - 0.3` con
  mínimo conservador más el Delay del usuario, sin afirmar reproducir el timing
  completo de ThrowCharge/animación. Predicción opcional usa 78 studs/s por la
  trayectoria local de ~1,3 studs por 1/60 s, no un dato de física del servidor.
  Status distingue petición enviada y fallo local, nunca confirma impacto.
- `tools/test_x2duels.py` simula forma y orden, handler sin/ con choque simulado,
  origen AB verdadero/falso, módulo o remoto ausente, OFF durante equip y maker
  que cede, limpieza, equipo/pared/ronda/cooldown y acceso táctil colocado real.
  Son fixtures, no ejecutan el LocalScript real ni prueban Delta/servidor/BAC.
  Validación v155: `tools/validate.sh` PASS, 64 suites, boot `failures=0` y
  auditorías; `git diff --check` PASS.
- El manifiesto Gun nuevo es `DefaultGun`, pero solo se adjuntó su archivo Maid
  2/2; el LocalScript principal disponible sigue siendo `MimicGlare`. La firma
  Gun de v154 **no está corroborada para DefaultGun ni todas las skins**. No
  pedir activar Gun Probe: el usuario reportó BAC-1583 e interferencia. Para
  completar ese dato se necesita el archivo Gun 1/2 o una captura de fuentes sin
  activar Probe. Probar en vivo con cuenta controlada, indicar Status exacto y si
  hubo impacto real; no afirmar seguridad anticheat ni compatibilidad Delta.

## 1Y. X2 v154 — histórico, Knife pendiente en ese momento (v155 lo sustituye)

El usuario reportó que nada de Raycast/Oth le sirve en su celular y pidió CFrame
como MM2 para Silent con botón, Auto Shoot y Knife. MM2 CFrame **no gira cámara**:
construye dos CFrame y llama `Gun.Shoot` o `KnifeThrown`, cuyos protocolos no
son intercambiables con X2. Se investigó la Gun real que el usuario adjuntó.

- En X2 Silent AIM ahora es **solo botón CFrame** (no redirige disparos normales)
  y Auto Shoot usa la misma ruta independientemente, sin Oth ni hookmetamethod
  ni wrappers MouseCast, y sin escribir cámara. Mantienen sus filtros de equipo,
  vida, partida, alcance, opciones y Wall Check; este último usa un raycast normal
  desde HRP para consultar visibilidad, no un hook. Sin Wall Check no se consulta.
- El LocalScript de `MimicGlare` usa `fire:FireServer()`,
  `showBeam:FireServer(hitPosition, HRP.Position, Handle)` y después
  `Packages.Net["RE/GunKill"]:FireServer(guid, targetPlayer,
  CFrame.lookAt(Handle.Position, hitPosition).LookVector, HRP.Position,
  hitPosition)`. El RBXL 1v1 confirma la ubicación `Packages.Net.RE/GunKill`.
  La nueva ruta envía ese formato observado y usa el centro de la parte objetivo
  como hitPosition, **no un RaycastResult de impacto**. Servidor desconocido: puede
  rechazar el paquete o sancionarlo. Status solo dice request sent, no hit. Si
  falta cualquier RemoteEvent/Handle, no envía; Cooldown conservador 2,5 s
  compartido entre botón/Auto Shoot/Auto Win, inferido de MimicGlare, no medido
  para todas las skins. No promete eficacia ni seguridad anticheat.
- En v154 la fuente de Knife disponible solo tenía `MobileKnifeLocalScript` (GUI) y
  efectos visuales; el RBXL contenía `Packages.Net.RE/ThrowEvent`, pero NO se
  conocían la firma ni GUID de la petición de lanzamiento en ese momento. No se inventó un
  protocolo ni se afirmó implementado Knife CFrame. Su implementación nativa
  anterior podía mover la cámara y se pausaba con Silent. Para completarlo,
  Gun Probe ofrece acción **Save knife sources** sin activar Probe ni hooks;
  guarda `X2Duels-knife-sources.json` y `X2Duels-knife-source-*.luau` sin
  sobrescribir los de Gun. Decompile puede fallar o ser detectado.
- Tests X2 ejercitan el botón táctil real simulado, orden/forma de tres paquetes,
  sin cámara/hook, falta de remoto, equipo, OFF, cooldown y Auto Shoot separado;
  captura Knife independiente. Las pruebas mock no son Roblox/Delta/servidor.
  Reiniciar Roblox para quitar nodos Oth antiguos, probar en cuenta controlada
  con Gun Probe y Safe Place apagados, reportar Status y resultado real; en ese
  momento se pidieron archivos Knife con la acción sin activar Probe.

## 1X. X2: cámara y Auto Shoot v153 — histórico, sustituido en v154

El usuario reportó que Auto Shoot y Silent AIM no funcionan y que la cámara se
sale del personaje. La captura móvil `X2Duels-calibration.json` (SHA256
`a54a8d525ef7c4eed9b5d409c03d62cb84289697c6ccae2a00ac098bc396d220`)
retuvo 400 eventos, descartó 470 y tenía `silent=false` en todos los eventos
conservados: **no permite atribuir el giro a Silent**. Tenía Probe activo, 58
activaciones y ocho rayos Gun de 10.000 studs; las ráfagas de activación y tres
rayos separados ~2,6 s son compatibles con el debounce Gun de 2,5 s, no prueban
hits ni soporte de Oth. El LocalScript real de MimicGlare recuperado usa
Mouse.Hit cacheado al toque y Raycast de HRP; Tool:Activate no crea Button1Down.

- Auto Shoot ya no llama al giro de cámara de v152. Instala/reutiliza Oth sin
  hookmetamethod y arma una ventana de 0,35 s, de un rayo, para un LocalScript
  descendiente de ESA Gun, origen próximo al HRP, RaycastParams Exclude y longitud
  ~10.000, con controles de personaje/partida/equipo/vida/rango y Wall Check en
  selección y raycast. Conserva longitud y parámetros. Si falta Oth o la API de
  caller, no activa Gun y avisa. Si el hook parece instalado pero no intercepta
  el rayo, puede haber activación sin redirección: Status lo informa, no equivale
  a daño; no garantiza impedir un disparo mal dirigido. Las APIs y semántica de
  checkcaller/Activated en Delta siguen SIN probarse.
- Una sola activación queda pendiente hasta su diagnóstico, evitando solapes.
  Solo para la skin MimicGlare se limita a 2,5 s según el código observado; no se
  extrapola a todas las armas. Auto Win usa esa misma ruta sin cámara si Silent
  o Auto Shoot están activos; Auto Win por sí solo y Knife Throw nativo aún
  pueden rotar la cámara. Los lanzamientos automáticos Knife se cancelan/pausan
  mientras Silent está activo para no hacer aim lock. Safe Place puede mover el
  personaje: desactivarlo al aislar cámara. Los ajustes propios siguen separados.
- Se ignoran CameraModule y descendientes, y pings; compatibilidad amplia no
  redirige si el caller es desconocido. Una identidad ausente no permite probar
  que sea Gun, por lo que este modo ahora falla cerrado y puede dejar de funcionar
  en executors que la ocultan. No promete interceptar otros diseños de Gun.
- Gun Probe NO funciona simultáneamente con Silent, Auto Shoot, Auto Win, Knife
  Throw ni Kill Aura: se detiene al activar combate y se rechaza su arranque
  mientras esos módulos estén activos. `Save gun sources` sigue independiente.
  El usuario reportó BAC-1583 y disparos bloqueados con Probe; **no pedir que lo
  active para probar esto** ni garantizar seguridad anticheat.
- `tools/test_x2duels.py` simula Gun/cámara/ping, Caller/Oth ausentes, args y
  longitud, equipo, pared tardía, OFF/expiración, simultaneidad, cooldown y
  pausa Knife; mocks no prueban Roblox ni servidor. Prueba sugerida en sesión
  limpia: Gun Probe, Knife Throw, Auto Win y Safe Place OFF; probar Silent solo
  con disparo normal, luego OFF y Auto Shoot solo; anotar Status y si cámara,
  rayo y daño funcionan. Reiniciar Roblox para retirar posibles hooks viejos.

## 1W. X2: fuente Gun, Vape CameraModule y Auto Shoot nativo v152 (histórico)

El usuario aclaró que su Vape móvil no presenta Oth y que en Delta Silent AIM
solo acciona botones; no inferir que alguna versión o executor soporte Oth/Silent
sin prueba. Pidió investigar cómo dispara la pistola y mejorar Auto Shoot móvil.
La experiencia reportada corrige cualquier afirmación anterior de compatibilidad
móvil; usar una cuenta de prueba y no prometer que no haya kick ni impacto.

- Fuente Vape universal commit `5d951c27f9677cc1d4a658c44a42c120356b9f58`,
  `src/games/universal - base/Combat/SilentAim.lua`, blob
  `051dc5b17d6a4d5c2c16df737fd5168a72d83996`: `Ignored Scripts` tiene por
  defecto `CameraModule`, compara nombre vía `getcallingscript` y deriva a
  original; si no identifica caller no puede excluirlo. El archivo expone el
  toggle Oth y fallback hookmetamethod, pero no demuestra que esté disponible
  ni funcione en el Vape/Delta móvil del usuario. Vape AutoFire depende de
  `mouse1press/release`, no se asume que funcione en touch.
- Volvimos a leer el RBXL 1v1 TestingStuff blob `8968d4dc5906b3f52fe93b59d8ce4f8e9f9d918c`
  SHA256 `4abae6cae221a32bbddabdea6f54ec0ac559537b93ada74c38f9daaa7bb0816d`:
  928 LuaSourceContainer, 8 Tools y **ningún Tool con nombre Gun/revolver/pistol**.
  El `DefaultGun` vivo y LocalScript principal no aparecen. `GunCrosshairController`
  solo contiene `return {}`. `Client.Modules.MouseCast` convierte posición de
  pantalla a `ViewportPointToRay`, luego llama Raycast 500 studs con filtros;
  no hay evidencia de que Gun use MouseCast, pues otros módulos como pings lo
  consumen. `CreateBeam` dibuja el efecto, no comprueba daño ni velocidad real.
  `DualWieldGun` reconoce `CollectionService:HasTag(tool, "Gun")`: toolKind de
  v152 ahora reconoce ese tag además de nombre/hijos, para skins desconocidas.
- El JSON adjuntado (touch=false, keyboard=true) registró a ~31,301 s un
  Raycast Exclude de 10.000 studs y remoto `fire` sin argumentos, caller nombre
  `LocalScript`, tras Activated; no ofrece ruta completa ni prueba entrega a
  servidor. Visto junto con `MouseCast` de 500, **no son intercambiables**.
  No afirmar método de puntería móvil ni inventar remotos/validación servidor.
- `Save gun sources` es ahora acción independiente: con Gun en Backpack o
  equipada y **Gun Probe desactivado**, usa únicamente `decompile`/`writefile`,
  sin instalar hooks ni tocar el informe previo. Genera en workspace raíz
  `X2Duels-gun-source-<timestamp>-<generación>-<n>.luau` y manifiesto
  `X2Duels-gun-sources.json` (se sobrescribe cada intento). Indica éxito/error y
  no elimina fuentes anteriores. `decompile` depende del executor, puede fallar
  o ser detectado, y las fuentes pueden contener información privada; el usuario
  debe revisarlas antes de compartir. El action en Probe activo actualiza además
  el JSON de esa sesión sin reinstalar hooks. No es prueba de datos del servidor.
- Auto Shoot no depende de Silent ni instala hooks: usa selección propia, equipa,
  aguarda Heartbeat si venía de Backpack, apunta con cámara brevemente y activa
  Tool nativo. No es Silent, puede mover cámara; no se ha validado cómo Gun
  interpreta el cursor/touch. Ahora reconoce Gun-tagged skin, verifica pared
  tanto desde origen del arma como de cámara, no activa si cámara falta y reporta
  cancelación o arma deshabilitada tras equipar. Cooldown y checks siguen
  independientes de Silent; nada garantiza disparo o impacto real. La fuente de
  Gun es necesaria antes de proponer una solución fiable para Delta touch.
- Tests mock: captura sin Probe ni hooks, decompile desde getgenv y fallo,
  conservación JSON previo, Tool Gun etiquetado, pared cámara/muzzle, cámara
  ausente, cancelación/dehabilitado tras Heartbeat, Auto Shoot móvil con Oth,
  hookmetamethod y hookfunction ausentes. No son prueba Roblox/Delta/servidor.

## 1V. X2 Duels: Raycast inspirado en Vape y predicción Knife v151

El usuario indica que Vape V4 Silent AIM Raycast le funciona y pidió adaptarlo,
predecir Knife y comprobar si el anticheat excluye hitboxes. No se dispone de la
implementación completa del anticheat ni código de servidor: en las 1.847
fuentes 1v1/2v2 extraídas solo aparece `BAC = {}` en ProfileTemplate entre
`anti.?cheat`, `hitbox` y `BAC`; 2v2 tiene numerosas decompilaciones fallidas,
y Net está ofuscado. No se encontró ninguna exclusión demostrable. **No llamar
indetectable a Hitbox**: la tarjeta existente expande localmente HumanoidRootPart,
el servidor puede ignorar/rechazarlo y el cambio o el hook pueden detectarse.
No se agregó un bypass de anticheat ni se prometen impactos.

- Referencia Vape (commit `5d951c27f9677cc1d4a658c44a42c120356b9f58`):
  `src/games/universal - base/Combat/SilentAim.lua` usa Oth en `__namecall` y
  cambia la dirección a objetivo conservando longitud, pasando parámetros;
  su selección amplia y hooks opcionales directos no son idénticos a este menú.
  Su Projectile se aplica a métodos PointToRay/Ray, no a su hook Raycast.
- Nuestra ruta Oth mantiene longitud/parámetros, respeta equipo, objetivo,
  checks y alcance. `Raycast Compatibility` OFF por defecto limita atribución;
  ON aproxima el alcance amplio de Vape, acepta orígenes distantes, excluye
  callers Camera/Ping identificados pero puede redirigir llamadas ajenas.
  ON no significa que un servidor acepte impactos. El bridge manda namecalls no
  Raycast directamente al predecesor si Probe está OFF, preservando nils/retornos;
  Probe usa llamadas IsA directas para evitar namecalls anidados de ese filtro.
  El usuario reportó Probe interrumpía disparos: esto no prueba su causa ni que
  se haya resuelto; Delta/PC live y seguridad de Oth no verificadas.
- Archivo del usuario: JSON con Gun y touch=false/keyboard=true; una activación,
  seguida a ~8 ms por Raycast 10.000 studs, Exclude, caller nombre genérico
  LocalScript y `fire:FireServer()` sin args. Registro es antes de reenviar y
  solo muestra nombre de caller/remoto; conexión con Gun probable, no probada.
  11.537 eventos descartados y últimos 400 retenidos. Silent estaba OFF: no
  confirma redirección ni impacto. El test txt confirmó escritura para esa prueba.
- `Knife Prediction` bajo Silent AIM es OFF por defecto y solo predice el punto
  de Knife para Raycasts capturados. No sabemos si lanzamiento nativo usa esa
  ruta. `Projectile Prediction` bajo Knife Throw automático es OFF e independiente
  de Silent y de Auto Win; predice su aim en la secuencia nativa desktop/touch,
  que usa cámara. Cada modo tiene su propio Speed/Gravity estimados; 100 studs/s
  y gravedad 0 son valores iniciales sin calibrar. Predicción balística numérica
  limitada a 5 s, velocidad objetivo medida de raíz, fallback sin lead cuando
  no hay solución; Wall Check comprueba línea recta, no trayectoria curva. No
  inyecta ni fabrica remotos, no garantiza servidor, hit rate ni ausencia de kick.
- `tools/test_x2duels.py` cubre solución estacionaria/móvil/gravedad/imposible,
  Oth 10k atribuido, preservación de args/longitud, modo amplio, excepción
  Camera/Ping, passthrough de no-ray, predicción Silent vs Knife Throw separadas,
  además del harness móvil. Mocks no prueban físicas ni executors reales.

## 1U. X2 Duels: guardado en workspace universal v150

El usuario indicó que el JSON no apareció en workspace y pidió que funcione en
Delta y PC. No se conoce la causa ni se ha validado ninguno de esos executors en
vivo. `Gun Probe` usa un **nombre relativo plano** `X2Duels-calibration.json`:
por contrato de `writefile`, apunta a la raíz del workspace del executor, sin
carpetas ni rutas OS hardcodeadas. La ubicación física, visibilidad externa y
permisos dependen del executor/dispositivo; no hay API universal para forzar el
mismo directorio físico ni garantizar éxito. No se envía información por red.

- Busca APIs de filesystem en el entorno del módulo y, si faltan, en `getgenv`.
  Distingue fallos de JSON, `writefile` ausente/error/false, archivo no visible
  a `isfile`, y contenido distinto en `readfile`. El status diferencia contenido
  verificado, solo existencia, y escritura sin verificar. Un resultado sin error
  **no prueba** que el usuario pueda acceder al directorio desde el dispositivo.
- `Test workspace` crea únicamente `X2Duels-workspace-test.txt` en raíz y verifica
  si puede; no requiere activar Gun Probe, instalar hooks ni borrar el JSON previo.
  Reutilizar el nombre sobrescribe el test. No confundir ese archivo con el JSON.
- Al activar Probe se intenta guardar snapshot mínimo **antes de instalar Oth**;
  luego se guarda de nuevo al arrancar, por cambios ~3 s, manual y al detener.
  Esto sobrescribe el informe anterior al empezar; copiarlo antes. Un kick
  inmediato puede perder el contenido restante, no guardar o truncar escritura.
  `Save gun sources` opcional usa la misma raíz/resolución/chequeo, y decompile.
- El usuario también reportó que Gun Probe impide disparar. El puente Oth puede
  interferir con las llamadas originales (hay llamadas anidadas en el observador),
  pero no hay diagnóstico probado en Delta ni se ha corregido en esta versión.
  **No instruir a reactivar Gun Probe** hasta investigarlo; `Test workspace` puede
  utilizarse con el módulo apagado. Oth no garantiza evitar BAC-1583.
- Mocks prueban ruta relativa, entorno `getgenv`, test sin hook/sin sobrescribir
  JSON, contenido/existencia/sin verificación, errores false/ausencia/JSON,
  snapshot previo al hook y ciclos Oth. No prueban directorios o disparos reales.

## 1T. X2 Duels: Gun Probe Oth compartido v149

El usuario confirmó que **BAC-1583 apareció al activar Gun Probe v148**. Eso
correlaciona la expulsión con ese momento, pero no identifica cuál API/hook lo
provocó. v148 instalaba tres hooks Oth. v149 elimina los de `__index` y el
`workspace.Raycast` directo y usa un único Oth sobre `__namecall`, compartido
con Silent AIM, en ambos órdenes ON/OFF y sin hooks clásicos como fallback.
No afirmar que esto impide la expulsión: Oth, el cliente/executor y otras APIs
pueden igualmente ser detectados. Pruebas en cuentas de prueba, no la principal.

- Gun Probe es pasivo: registra con Gun equipada namecalls observados para
  `Raycast`, `FindPartOnRay` y variantes, `ScreenPointToRay`,
  `ViewportPointToRay`, `FireServer`/`InvokeServer`, más touch y Activated. Un
  rayo conserva origen/dirección y `RaycastParams.FilterType` si está disponible.
  Los remotos solo tienen tipo de argumentos, no sus valores. Nombre del caller
  puede ser desconocido y eventos pueden pertenecer a otros scripts. No captura
  lecturas Mouse, `Ray.new` ni llamadas directas que eviten `__namecall`; la
  ausencia no prueba que el juego no las use. No confirma daño.
- El JSON v3 registra configuración y cambios de Silent (backend, habilitado,
  parte, FOV, Wall/Team, rango, compatibilidad) y eventos antes/después de un
  rayo redirigido. Status muestra presencia de namecall, no prueba que se use.
  Guarda hasta los 400 eventos más recientes, contando descartes; guarda un
  snapshot inicial, luego cambios cada 3 s, y al OFF/60 s para mitigar pérdida
  ante kick. El mismo nombre se sobrescribe; puede perderse lo más reciente y
  no hay garantía si falla `writefile`. Archivos pueden contener coordenadas y
  nombres: revisar antes de compartir. `Save gun sources` es opcional, emplea
  API `decompile` (no Oth), y puede contener datos privados.
- El bridge queda inerte en OFF/destrucción y se reutiliza; reentrar a Roblox
  lo quita. Reiniciar Roblox antes de v149 para retirar los nodos v148. Mocks de
  `tools/test_x2duels.py` prueban un solo hook, ausencia de fallback, Silent y
  Probe activados en ambos órdenes, compatibilidad, móvil, eventos sin valores
  de remotes, FIFO de 400, autosave, OFF y expiración. No prueban semántica
  Oth off-thread ni el anticheat/servidor reales.

## 1S. X2 Duels: Gun Probe Oth pasivo v148 (histórico; reemplazado en v149)

El usuario pidió el grabador para descubrir el método de disparo. v147 lo había
bloqueado por sus hooks anteriores; v148 reactiva la tarjeta existente **Gun
Probe** en Combat con un recolector pasivo basado exclusivamente en `oth.hook`.
Sin `oth.hook` / `getrawmetatable` / `checkcaller` no usa fallback clásico;
Status indica qué hooks se instalaron o no. Se puede activar independientemente
con Silent OFF para una captura base y repetir con Silent ON para comparación.

- Busca Gun en mochila/personaje, `Equip gun` la equipa, captura hasta 60 s y
  máximo 400 eventos; guarda localmente al OFF/vencimiento o con `Save report`
  en `X2Duels-calibration.json`, sobrescribiendo el informe anterior. Turn OFF
  después de vencer antes de reiniciar. En Delta, ubicación exacta de archivos
  depende de versión/plataforma; si falta `writefile`, Status informa fracaso.
- Señales: Touch/MouseButton1, `Tool.Activated`, Mouse Hit/Target/UnitRay vía
  `__index`, `Raycast` directo y `__namecall`, y `FireServer`/`InvokeServer`
  observados con Gun equipada. Los eventos registran tiempos, tipo de argumentos,
  nombre de script/remoto y vectores del rayo; **no** valores de remotes.
  Pueden incluir scripts ajenos, repetirse entre hooks o faltar por executor;
  no inferir que sean disparos ni que el servidor haya aceptado daño. No ejecuta
  Tool:Activate ni modifica args/resultados. `Save gun sources` es manual y
  usa decompile/writefile (hasta 20 scripts del arma); revisar datos sensibles.
- Nodos Oth inactivos y reutilizables al OFF/destrucción, sin unhook riesgoso;
  una reinyección puede dejar nodos inertes, reentrar los elimina. Posibles
  incompatibilidades entre hooks/caller off-thread, ni Delta ni prevención de
  expulsiones están probados. El colector externo `X2DuelsDecompiler.luau`
  sigue usando hookmetamethod: no proponerlo como alternativa segura en este juego.
- `tools/test_x2duels.py` cubre Oth ausente sin fallback, pasividad (argumentos,
  nils/retornos), Input/Activated/Mouse/Raycast directo/namecall, privacidad de
  remotes, 400 eventos, timeout, OFF/ON, teléfono simulado y módulos previos.

## 1R. X2 Duels: Silent AIM Oth Raycast v147 (Gun Probe actualizado en v148)

El usuario probó Vape en Delta: reporta kick con hook habitual, sin kick en esa
prueba con Oth; solo Raycast parece funcionar y Projectile quizás reconoce el
cuchillo. Es una observación real del usuario, no prueba de inmunidad futura,
daño, ni velocidad/gravedad del arma. Vape universal usa `oth.hook` sobre
`__namecall`; no se copia código ni se usa `oth` como garantía anticheat.

- Reutilizar la tarjeta **Silent AIM** existente en Combat. El backend por
  defecto es Oth Raycast (`oth.hook`, `getrawmetatable`, `getnamecallmethod`,
  `checkcaller`): si falta/falla, muestra estado unavailable y **no** recurre a
  `hookmetamethod`, `hookfunction`, fallback raw ni MouseCast. No se restaura el
  master al inyectar; el usuario lo activa explícitamente. El master con Gun o
  Knife equipados intenta redirigir solo Raycast nativo, conserva longitud,
  argumentos y Wall/Team/partida/rango/FOV; no gira cámara ni inventa remotos.
- `Raycast Compatibility` OFF por defecto permite aceptar rayos sin procedencia
  fiable o ajenos con arma equipada; excluye callers Camera/Ping identificados,
  pero puede afectar otros scripts. OFF restringe a caller atribuible al arma.
  `Mouse Compatibility` se quitó de la UI pues el backend Oth no la usa; el código
  legado existe únicamente para fixtures de regresión, sin selector productivo.
- La acción táctil equipa Gun y activa la Tool nativa; el estado distingue hook
  instalado, redirección observada y daño desconocido. También redirige rayos de
  Knife dentro de Silent, sin subordinar la tarjeta independiente Knife Throw.
  No se añadió Projectile: ninguna captura acredita velocidad/gravedad ni que
  esa ruta inflija daño. Auto Shoot/Knife Throw conservan opciones independientes.
- OFF/destrucción desactiva el callback Oth sin borrar hooks ajenos; se conserva
  un nodo inerte reutilizable porque `oth.unhook` tiene semánticas distintas por
  executor y puede quitar hooks posteriores. Reentrar a Roblox lo elimina;
  reinyecciones sin reentrar pueden acumular nodos inertes. Gun Probe v146 queda
  **bloqueado** en Oth por usar hooks anteriores; no genera captura nueva.
- Los mocks prueban ausencia de fallback, provenance/opción amplia, camera/ping,
  checkcaller, alcance, equipar Knife, equipo, OFF/ON sin nodo nuevo y botón
  táctil. No prueban semántica OTH off-thread de Delta, reconocimiento de caller,
  ni impactos/detección en Roblox. Solicitar versión Delta, modo 1v1/2v2 y Status;
  usar cuenta de prueba, no la principal.

## 1Q. X2 Duels: Gun Probe temporal v146 (histórico; bloqueado en v147)

El usuario usa Delta en celular y pidió un módulo temporal para diagnosticar
su disparo. **Gun Probe** es una tarjeta Combat separada y no se restaura al
inyectar. Al habilitarla durante 60 s busca la Gun en Backpack/Character;
`Equip gun` intenta equiparla. Desactivar, vencer el tiempo o descargar detiene
los hooks; si el contador vence la tarjeta permanece visualmente encendida y
hay que apagarla antes de reiniciar. La captura no dispara automáticamente.

- Prueba deliberadamente amplia y de riesgo: con Gun equipada y `checkcaller`
  funcional, intenta redirigir lecturas nativas de Mouse `Hit`, `Target` y
  `UnitRay`, incluso de scripts ajenos. Emplea objetivo, partido, equipo,
  distancia y Wall Check, sin mover cámara. Puede interferir con otros controles.
  No forzar `checkcaller` ni prometer que esas lecturas sean usadas en celular.
  Este módulo no instala el fallback raw de Silent y no intercepta todas las APIs.
- Registra hasta 400 eventos con tiempo relativo: toque/clic y processed,
  Tool.Activated, lecturas Mouse/redirecciones, y llamadas observadas via
  `__namecall` FireServer/InvokeServer/Raycast mientras la Gun está equipada.
  Guarda nombre de remoto/script y tipos de argumentos, no valores, y estructura
  de descendientes de Gun. Puede recoger eventos no relacionados; no se debe
  interpretar correlación como causalidad. APIs presentes/hooks instalados no
  prueban que capturen todo, ni `Activated`/lectura/remote prueban daño.
- `Save report` o fin de sesión escribe `X2Duels-calibration.json` en la carpeta
  de archivos del executor, sobrescribiendo la captura previa. `Save gun sources`
  decompila hasta 20 LocalScript/ModuleScript de la Gun a archivos locales
  `X2Duels-gun-source-<n>.luau` si Delta expone decompile/writefile. Puede
  tardar o no estar disponible. Revisar contenido sensible antes de compartir;
  ninguno se envía por red. El recolector externo sigue siendo útil para scripts
  de disparo fuera de Gun o capturas más amplias.
- Hooks propios tienen lease por sesión y preservan hooks posteriores; captura
  limitada y cierre automático. `tools/test_x2duels.py` cubre en mocks reads
  ajenos y del executor, tipos sin valores, toque, hook encadenado, expiración y
  reinicio; no prueba Delta/Roblox en vivo. Si no hay lectura Mouse observada,
  no concluir que solo funciona PC: el cliente puede usar otra ruta o el hook
  puede no funcionar. Pedir informe, fuentes disponibles y Status.

## 1A. X2Duels (MVS): evidencia 1v1 y contratos v145

**Fuentes:** `XzAngel19/TestingStuff` commit `a849817395`, log
`2026-10-28T04_16_18Z.log` y `Place_124848751642883_[DUELS] 1v1_27-10-2026_23-21-39.rbxl`.
El log tiene 1.709 eventos de ~10,5 minutos, todos sin llamadas del executor;
el RBXL 1v1 contiene fuentes decompiladas útiles. El RBXL 2v2 anterior tiene
fuentes en su mayoría stubs: no presentar sus mecánicas como verificadas.
Estas capturas son **evidencia cliente**, no prueba de que el servidor acepte
daño o recompensas ni de lo que ocurre en todos los executors/places.

- **Identidad:** `124848751642883` (1v1), `92876937625630` y
  `135856908115931` están en loader/manifest/perfiles; el fingerprint también
  acepta nombres literales con barras, como
  `Packages.Networking["RE/Match/SetDead"]`, y conserva fallback de carpetas.
  Las mismas rutas literales se conectan y se vuelven a conectar si el remoto se
  reemplaza. No inferir nombres estables para remotos hash bajo `Packages.Net`.
- **Estado/equipos:** en la captura `Client.Modules.MatchState` consume
  `ClientGlobals.PlayerMatches` y `RunningGames`: `getGameId`, `getTeamId`,
  `getMode` e `isDead`. El core carga la API sin bloquear el boot, reintenta y,
  en los places conocidos, falla cerrado mientras no está lista, no hay GameId,
  los jugadores están en juegos distintos o el equipo es desconocido.
  `FFA` con el mismo GameId identifica adversarios sin tratar FFA como equipo.
  Priorizar esta API sobre atributos de lobby; el cliente puede aún no haber
  recibido todos los datos. PlayerESP/Chams/Nametags usan providers compartidos.
- **Función y ubicación:** X2 tiene tarjetas **Silent AIM**, **Auto Shoot** y
  **Knife Throw** independientes en Combat. Tras el reporte de fallo móvil,
  v144 elimina el modo `Legit` que giraba la cámara y descarta ese valor de los
  perfiles guardados. Silent intenta redirigir lecturas nativas de puntería sin
  mover la cámara; su tecla/botón también equipa la Gun del Backpack, espera un
  `Heartbeat` si acaba de equiparla, revalida personaje/partida/arma/objetivo y
  llama `Tool:Activate()`. Si no hay adaptador disponible, equipa pero **no
  dispara** y lo informa. Un adaptador instalado no prueba que la Gun lo use
  ni impide un tiro sin redirección: después del intento el status distingue
  lectura redirigida de ausencia de evidencia; ninguno confirma impacto o daño.
  `Wall Check` está primero al expandir Silent, Auto Shoot y Knife Throw, con
  estado multilínea y toast en el botón manual para pared/cuerpo, rango, equipo,
  partida, vida, arma, recarga y compatibilidad. Wall Check comprueba también
  desde Handle/root y cámara; no afirma atravesar paredes cuando se desactiva.
  Auto Shoot y Knife Throw conservan checks/rango/cooldown propios, por defecto
  0 s extra; funcionan sin Silent. Kill Aura tiene checks propios. La cola de
  Gun espera un Heartbeat al equipar y cancela OFF/respawn/cambio de partida o
  equipo; el arbiter no interrumpe el windup de Knife. Auto Shoot/Auto Win aún
  usan la cámara temporal visible del v143: no confundirlos con Silent. TriggerBot
  conserva `noAim`. Hitbox restaura propiedades, pero el servidor puede rechazar
  impactos fuera del tamaño real. Masters OFF en executor nuevo; migración v143
  mantiene apagados los nuevos automáticos en perfiles antiguos. No se inventan
  ni repiten paquetes de combate.
- **Adaptadores restringidos y límites:** el RBXL decompilado contiene
  `Client.Modules.MouseCast`, que devuelve `RaycastResult` real y endpoint de 500
  studs y también usa `PingsController`. v144 envuelve sus cinco funciones sin
  alterar filtros ni ampliar el alcance, **sólo** con procedencia del arma:
  `getcallingscript` descendiente del Tool o, cuando corresponde, un stack
  `debug.info` que identifica jugador/Tool/LocalScript reales. Un caller ajeno
  explícito siempre se deja intacto. También intenta `Mouse.Hit/Target/UnitRay`
  y hooks de rayo si el executor los admite; esos accesos son alternativas, no
  evidencia de que el script de Gun los use. Los wrappers desactivados quedan
  inertes si otro script los encadena, incluso tras OFF/ON. La ruta Knife
  observada conserva el remoto y GUID/CFrame genuinos al cambiar sólo el Vector3.
  Sigue faltando el LocalScript principal de Gun y su cadena de aim: ningún mock
  verifica compatibilidad real en un executor concreto, `Tool:Activate`, daño
  ni precisión. No sustituir este límite por paquetes MM2 o hashes inventados.
- **Investigación y alternativas v145:** ScriptBlox mezcla dos juegos: el
  perfil X2/MVS usa lobby `135856908115931` (universe `7219654364`), 1v1
  `124848751642883` y 2v2 `92876937625630`; RED21 `12355337193` es otro
  universe (`4348829796`). No importar sus remotes por el parecido del nombre.
  Para el juego correcto se inspeccionaron estáticamente
  [K1ngfcs](https://scriptblox.com/script/DUELS-Murderers-VS-Sheriffs-Silent-aim-201630)
  y [imshrak](https://delta-scripts.org/scripts/murderers-vs-sheriffs-script-keyless-silent-aim-open-source/):
  ambos proponen redirigir lecturas de mouse, pero sus anuncios/comentarios no
  prueban funcionamiento. Las fuentes GitHub respectivas no declaraban licencia;
  no se copiaron ni ejecutaron. La muestra imshrak además intenta una invitación
  vía RPC de Discord: esa solicitud tampoco se incorporó. Synergy y Nova
  entregaban loaders de servicios externos; Synergy declara recopilar datos, así
  que no se cargaron. Una muestra de Rscripts propone un `kill` directo, sin
  evidencia vigente suficiente: **no** se envía ni se adivina ese remote.
- **Fallback Mouse v145:** en un botón/tecla de Silent, si se reconoce la Gun
  por los RemoteEvents directos `fire` y `showBeam`, se instala una autorización
  de hasta 0,2 s para lecturas nativas no atribuibles de **ese Mouse** y sólo
  `Hit`/`Target`; exige `checkcaller() == false`, objetivo de la partida y checks
  vigentes. Se cancela al apagar, cambiar la partida o expirar. El toggle
  **Mouse Compatibility**, OFF por defecto en una instalación nueva, permite
  además esas lecturas fuera de la acción para el disparo normal. Puede afectar
  otros scripts locales cuyo origen no se pueda identificar; un caller ajeno
  identificado se deja intacto. El resto de rayos, MouseCast y Knife continúa
  requiriendo procedencia del arma. Si `hookmetamethod` falla, se puede intentar
  `getrawmetatable`/`setreadonly`/`isreadonly`, preservando el estado previo y
  sin desplazar un hook posterior. Esto es **un adaptador**, no prueba de que la
  Gun real use Mouse.Hit/Target ni de que un tiro cause daño. Si no se observa
  redirección, el status lo informa; un intento podría haberse disparado sin
  redirigir antes del diagnóstico. El `capabilities.json` del recolector anota la
  presencia de `checkcaller` y de las tres APIs raw, no su funcionamiento real.
- **Opciones propias de Silent v145:** `Target Part` elige Head o Body
  (UpperTorso/Torso/root), sin cambiar Auto Shoot, Knife Throw automático,
  TriggerBot ni Auto Win. La intercepción manual de Knife que ya pertenecía a
  Silent también comparte su selección. `Aim FOV`, OFF por defecto, y
  `Aim FOV Radius` filtran oponentes en pantalla
  por píxeles: cursor en PC (`WorldToScreenPoint`) o centro del viewport en
  móvil, con revalidación antes de redirigir. No cambia el FOV de cámara ni
  dibuja un círculo; Wall Check, Team Check, alcance y partido siguen activos.
  Se usan las tarjetas existentes, sin duplicar ESP, Hitbox, Auto Farm ni Rejoin.
- **Móvil:** `PlayerGui.Main.MobileKnifeGui.ThrowMode` es el BoolValue que
  alterna `MobileKnifeLocalScript`; se usa temporalmente y se restaura sin
  sobreescribir un cambio posterior. Desktop conserva el input derecho nativo.
  No se encontró el script principal de cuchillo; cómo consume ese BoolValue y
  la precisión real del throw siguen pendientes en móvil y PC. No usar el
  supuesto atributo `Tool.ForceThrow` como si estuviera probado.
- **Auto Win en Utilities (v143):** intenta combate automáticamente con la
  Gun o el Knife nativos sólo durante un juego activo con `Phase == "InGame"`,
  `RoundStarted == true` y `CurrentRoundEnded ~= true`. No garantiza victoria;
  el servidor decide daño y resultado. Las filas `Time Spent` miden sólo tiempo
  activo de este Auto Win, `Duels Won` cuenta sólo `MatchResults` finales con
  `Outcome == "Win"` mientras está encendido y deduplica por ID incluso si un
  evento repetido llega más tarde, y `Current Game mode` usa FFA o PlaceId 1v1/
  2v2 cuando hay GameId (en otro caso `Lobby / unknown`). Las cifras son de esta
  sesión cliente, no son un total persistente del servidor. Se conservan los
  contadores antiguos del core por compatibilidad: `WinNotification` mide
  **rondas**, `SetDead` no es derrota de equipo, `Killed` y `DestroyBody` se
  deduplican, y Draw/Tie/Forfeit/Cancelled no cuentan como victoria final.
- **Safe Place:** toggle opcional bajo Auto Win; requiere GameId, MatchId,
  `Phase == "InGame"`, personaje vivo y `Workspace.ActiveMaps[MatchId]`. Calcula
  el techo desde las partes cercanas, rechaza alturas excesivas y usa un
  `BodyPosition` temporal en vez de una plataforma que intercepte raycasts.
  Limpia en OFF, muerte, respawn, fin y cambio de match/mapa; sólo restaura el
  CFrame si siguen siendo el mismo personaje, GameId, MatchId y mapa activo.
  Es una sujeción local: física del servidor/anticheat, streaming y techos pueden
  impedirla o bloquear el tiro. Revisar el status; no presentarla como invulnerabilidad.
- **Revancha:** toggle opcional; `ClientGlobals.GameValues:TryIndex({"Rematch"})`
  alimenta el mismo estado nativo que el botón del juego. Sólo si `active` es
  true, no está cancelada y no se ha votado, envía una vez el remoto observado
  `RE/Rematch/RematchVote:FireServer()` sin argumentos. Se rearma al terminar el
  estado activo; los demás jugadores deben votar. No usa `RematchTeleport` ni
  `queue_again`. Status distingue espera, cancelación, voto enviado y falta de
  estado/remoto; una llamada saliente no demuestra que el servidor aceptó.
- **Auto Farm en Utilities:** `EventsController` clona modelos numerados en
  `Workspace.SpawnablesClient`, luego añade tag `Pumpkin` y conecta
  `PrimaryPart` invisible `Touch.Touched` al personaje local. Auto Farm espera
  GameId, escucha el tag, contacta esa PrimaryPart y restaura el CFrame guardado
  sólo si el personaje/match siguen vigentes. `PumpkinCurrency_*` en `FallDecoration` y
  lobby es decoración, no moneda. El antiguo camino `Farms/PumpCoins` conserva
  protección por podium y equipo, pero no se observó en el nuevo log; también
  necesita prueba live. Ni teletransporte ni `firetouchinterest` prueban saldo
  o aceptación por el servidor; no usar `Coins collected` como confirmación.
- `tools/test_x2duels.py` cubre MatchState/equipos/resultados, módulos separados,
  arbitraje y cancelación tras `Heartbeat`, mensajes Wall/rango/arma, migración
  del antiguo Legit, filtros y límites de MouseCast, pings ajenos, hooks ajenos
  OFF/ON y un boot táctil que coloca el botón y lo pulsa con `InputBegan/Ended`.
  Conserva Safe Place, Rematch, Hitbox, ThrowMode, farm y fingerprint. El
  recolector `tools/X2DuelsDecompiler.luau` tiene ahora `snapshotWeapons()` para
  decompilar Tools presentes *después* de inyección/respawn; sus capturas y APIs
  tienen prueba simulada en `tools/test_x2duels_decompiler.py`. Son mocks: **no
  prueban daño, precisión, física, votos aceptados ni recompensas**. Falta
  capturar el Gun/Knife completo y probar 1v1 + 2v2 en PC/móvil.

## 1B. Cómo construir un game sin mezclar responsabilidades

Esta es la guía de diseño para MM2, X2Duels/MVS y cualquier juego nuevo. La
referencia de estructura es `games/MM2`; no se copian sus remotes, tiempos ni
argumentos a otro juego sin evidencia propia. La primera pregunta no es «¿qué
nombre suena más potente?», sino **qué mecanismo controla el módulo, qué estado
necesita y qué puede restaurar al apagarse**.

### 1. El mapa de responsabilidades

| Lugar | Responsabilidad | Ejemplos | No debe contener |
| --- | --- | --- | --- |
| **Silent AIM** | Seleccionar un objetivo y dirigir/activar ataques a distancia o proyectiles. | Shoot, Gun, Knife Throw, flechas, cohetes, lanzamientos y otras variantes de proyectil. | Swings cuerpo a cuerpo, un segundo selector de equipos, una tarjeta independiente por cada skin. |
| **Kill Aura** | Ataques melee de corto alcance contra objetivos válidos. | Knife, machete, sword, bat, axe y cualquier arma cuyo ataque sea un swing/contacto cercano. | Redirección de proyectiles, Silent Ray, predicción de una trayectoria o un ThrowEvent inventado. |
| **TriggerBot** | Reaccionar a una condición ya visible/validada y activar la acción correspondiente. | Disparar cuando el objetivo está bajo el crosshair, usando el adaptador nativo compartido. | Otro Silent AIM, otro bucle de selección o una copia del módulo de cada juego. |
| **Utilities** | Automatizaciones y datos útiles; el usuario puede pedir una secuencia de combate coordinada. | Auto Farm, Auto Win (también combate automático en X2/MM2), Auto Get Gun, Auto Unbox. | Hitbox, una expansión de colisiones o un módulo puesto ahí solo porque «es fuerte». |
| **Exploits** | Cambiar una propiedad o aprovechar directamente una mecánica explotable del juego. | Hitbox y manipulaciones equivalentes que tengan una razón técnica clara. | Auto Farm/Auto Win por costumbre, o cualquier tarjeta que no se pueda explicar técnicamente. |
| **Render** | Mostrar información sin decidir el combate. | PlayerESP, Chams, Nametags, HP, Arrows, Coin ESP. | Un TeamESP paralelo con otra resolución de equipos. |
| **Movement/Blatant** | Movimiento, desplazamiento o acciones físicas directas. | Speed, Fly, Teleport, Fling cuando corresponda al juego. | Estadísticas de farm o lógica de proyectiles. |

La distinción importante es **proyectil/distancia frente a melee**, no el nombre
del arma. En X2 el usuario pidió expresamente que Knife Throw y Auto Shoot sean
tarjetas independientes de Silent AIM; comparten el adaptador y un arbiter de
armas, pero no sus checks ni su toggle. El swing cercano sigue en Kill Aura.
En otros juegos no se impone esa excepción sin revisar sus requisitos. No se
crean loops que equipen armas distintas simultáneamente.

**Kill Aura no es un cajón para cualquier ataque automático.** Su alcance,
animación, swing, hit window y recovery pertenecen a la mecánica melee del
juego. **Silent AIM tampoco es sinónimo de “cualquier cosa con Silent en el
nombre”**: debe existir una selección de objetivo y una acción a distancia que
realmente se pueda redirigir o activar.

### 2. Estructura de archivos y orden de inicialización

Un game puede tener un `base.lua` pequeño o uno grande por razones históricas,
pero debe mantener estas fronteras conceptuales:

```text
src/games/<Game>/
  Rules.lua                 -- decisiones puras: equipos, Tools, resultados
  base.lua                  -- core, providers, adaptadores y coordinación
  Blatant/ o Combat/        -- ataques y módulos de combate del juego
  Other/AutoFarm.lua        -- utilidad de farmeo, si existe
  Render/                   -- presentación, nunca otra lógica de equipos
src/Profile/<PlaceId>.lua   -- sección/perfil del PlaceId
src/Wurst.lua               -- fingerprint, loader, registro y cleanup global
```

- `Rules.lua` no crea GUI ni conexiones. Expone funciones comprobables para
  normalizar equipos, clasificar herramientas, resolver relaciones y evaluar
  resultados. Un nombre de remote no es una regla suficiente.
- `base.lua` publica un único `state.<game>Core` y, cuando exista,
  `state.<game>Rules`. Los módulos usan ese core; no vuelven a escanear
  Backpack, personajes o remotes de una forma incompatible.
- El orden normal es **Rules → core/providers → módulos de combate →
  utilidades/render**. El core debe existir antes de registrar un módulo que
  lo consume. El loader debe enumerar explícitamente los archivos que realmente
  existen; un archivo retirado también se retira del loader y del bundle.
- `registerTeamProvider` y `registerRoleProvider` comparten la resolución de
  equipos con Entity, Targeting y el ESP. No se crea un ESP específico para
  arreglar colores que el provider ya puede resolver.
- Cada módulo implementa `init(runtime)` y `destroy()`, guarda sus conexiones
  en `featureConnections` o en su lista de cleanup y usa el `TaskManager`
  compartido. Al destruir: desconectar, cancelar trabajos pendientes, restaurar
  CFrame/cámara/atributos/propiedades y retirar providers que sean propios.
- La configuración se migra con una versión de layout. Las opciones retiradas
  se eliminan o migran de forma explícita; no se restaura automáticamente una
  automatización antigua solo porque su estado guardado era `true`.

### 3. Del archivo a una tarjeta visible: registro obligatorio

Hay tres hechos distintos que no se deben confundir:

```text
Estar en bundle.lua  = la fuente está disponible para el loader.
Estar en una load list = el loader ejecuta init del módulo.
createUniversalFeature = ese init registra una tarjeta y sus opciones.
```

Que un archivo compile y viaje en el bundle **no significa que se ejecute**;
que su `init` se ejecute tampoco significa necesariamente que cree una tarjeta.
Sprint es el ejemplo: se carga como módulo técnico de MM2, pero registra una
opción dentro de Speed mediante la tarjeta que ya existe.

- **Módulo universal nuevo:** añade su `{path, name, category}` a
  `src/libraries/Manifest.lua` y exactamente lo mismo al `fallbackManifest` de
  `src/Wurst.lua`. El manifest normal y el fallback no pueden describir menús
  distintos. El módulo debe devolver `init(context)` y `destroy()`; el loader
  universal llama después a cada `init` en el orden del manifest.
- **Módulo de un game:** añade la ruta a la lista explícita de
  `loadGameModule` en `src/Wurst.lua`, respetando las dependencias. MM2 exige
  que la lista cubra exactamente sus archivos; X2 carga Rules → base/core →
  AutoFarm. Un archivo como Sprint necesita aparecer ahí aunque no añada una
  tarjeta propia. Si sólo es un helper sin `init`/`destroy`, debe cargarlo su
  dueño mediante la ruta existente, no fingir que es un módulo autónomo.
- **Juego o PlaceId nuevo:** un archivo `src/Profile/<PlaceId>.lua` sólo declara
  metadata y secciones; **no registra gameplay por sí solo**. Hay que revisar
  el mapa `GAME_MODULES`, la rama de `loadGameModule`, `GAME_CHECK`, la llamada
  `registerPlaceModule`, cleanup y, cuando proceda, fingerprint. Para añadir
  otro PlaceId de un juego ya soportado, conserva el mismo module key y comprueba
  también su perfil; no clones el árbol completo.
- **Tarjeta:** dentro de un módulo ya cargado,
  `src/guis/Wurst/Code/Cards.lua:createUniversalFeature` la inserta en el
  `registry` elegido y en `allFeatures`, además de conectar búsqueda, UI y
  restauración de configuración. Por eso hay que pasar el `parent`, `registry`
  y `categoryName` correctos. El `category` del manifest identifica la entrada
  del módulo, pero no sustituye la categoría configurada al crear la tarjeta.
- **Opción dentro de una tarjeta existente:** no añadas otra entrada universal
  si el archivo no es un módulo independiente. El módulo técnico sí necesita
  una ruta de carga; después obtiene la tarjeta dueña y registra el widget, como
  hace Sprint con Speed.

Al retirar una función se aplica el recorrido inverso: quitar widget/tarjeta,
cleanup, entrada de carga y entradas del manifest/fallback que correspondan;
después regenerar el bundle. No dejar un archivo huérfano «por si acaso».

Las pruebas de esta frontera ya existen: `tools/test_manifest_sync.py` detecta
módulos universales sin registrar, paths ausentes/duplicados, divergencia del
fallback y diferencias en la lista MM2. `tools/audit_menu.py` comprueba lo que
realmente se registra al arrancar. Si se añade o retira una tarjeta, hay que
revisar también el inventario 38/37 documentado y cualquier contrato de menú;
si sólo se añade una opción, la prueba debe impedir que aparezca una tarjeta
extra. La salida final sigue siendo `bash tools/validate.sh` con boot limpio.

### 4. Cómo se crea una tarjeta y sus opciones

La API común es `createUniversalFeature` con `parent`, `registry` y
`categoryName`. Las opciones se añaden con los widgets compartidos:
`addSectionOption`, `addToggleOption`, `addNumberOption`, `addCycleOption`,
`addActionOption` e `addInformationOption`. `SetStatus` es para estado corto y
actualizable; no sustituye una explicación de seguridad ni un contador que no
existe.

- Por defecto una familia de ataques puede tener **una tarjeta principal** y
  secciones por arma o mecánica. La petición explícita del usuario prevalece:
  en X2 `Auto Shoot` y `Knife Throw` son tarjetas independientes de Silent AIM
  con un adaptador y arbitraje compartidos (§1A).
- Las opciones dependen del mecanismo real. Un arma con carga puede necesitar
  `Charge`; una con timing de impacto puede necesitar `Hit Time`; una con
  críticos puede exponer `Critical` y sus ventanas `Miss/Bad/Okay` **solo si
  esos estados existen y se pueden detectar**. No se rellenan tarjetas con
  sliders genéricos que el juego no utiliza.
- Las opciones de una mecánica especial deben explicar qué significan y qué
  ocurre si el estado es desconocido. Un texto `Critical` no prueba que el
  servidor haya aceptado un crítico; un resultado `Miss` tampoco debe contarse
  como daño.
- La keybind de una tarjeta puede ser de toggle o de acción, pero no ambas a la
  vez. Para una acción como Shoot se usa `state.bindFeatureActivationKey` y se
  asigna el callback de disparar; el callback no debe llamar al toggle maestro.
  El valor `Unknown` deja la tecla sin asignar hasta que el usuario la capture.
- Si un módulo ofrece senders `Button`/`CFrame`, sus nombres deben corresponder
  al comportamiento y probarse en desktop/touch. X2 v143 ya no expone ese sender:
  su tecla de acción dispara en ambos modos, sin toggle adicional.
- El estado de una opción hija no debe encender accidentalmente otra tarjeta.
  Si una subopción requiere el master, se documenta y se comprueba el gate; al
  apagar el master se cancela la acción pendiente pero se conserva la
  preferencia de la subopción cuando eso sea útil.

### 5. Adaptadores nativos y evidencia mínima

Antes de escribir un ataque se identifica la cadena real:
**input/acción → Tool o controller → animación/estado → remote observado →
resultado visible**. Se prefiere `Tool:Activate()`, el input nativo o el
controller que el juego ya usa. No se inventan `FireServer` ni argumentos por
similitud con otro juego.

- El objetivo se valida antes de activar: personaje y parte siguen en el
  DataModel, está vivo, no es el jugador local ni un objetivo protegido, la
  relación de equipo lo permite y, si existe Wall Check, el raycast no atraviesa
  geometría. La parte usada para apuntar debe ser la parte vigente, no un
  CFrame guardado de otro personaje.
- Gun/hitscan y projectile físico no son intercambiables. El primero necesita
  origen, dirección y filtro coherentes; el segundo puede necesitar posición de
  release, velocidad, gravedad, windup y recuperación. La predicción es una
  hipótesis medible, no una promesa de rewind del servidor.
- En un throw se conserva la animación y el momento de release cuando forman
  parte de la mecánica. Desktop y móvil pueden tener entradas distintas (por
  ejemplo, mouse2 frente al BoolValue ThrowMode del cliente móvil); ambas deben restaurar
  su estado al cancelar.
- La evidencia se clasifica como **observado**, **intentado**, **confirmado por
  un evento local** o **desconocido**. Beam, PlaySound, DestroyBody, una
  animación o una llamada saliente no demuestran por sí solos daño, kill,
  recompensa ni aceptación del servidor.
- El servidor sigue siendo autoritativo. Un mock puede comprobar que se llamó
  `Activate`, que se hizo un raycast o que se restauró una propiedad; no puede
  demostrar que el juego live otorgó una moneda o una victoria.

## 1C. Cooldown, velocidad y mecánicas con timing

Esta convención evita dos errores opuestos: poner un intervalo arbitrario que
hace lento el módulo, o borrar un tiempo que la mecánica necesita para funcionar.

### Regla de la opción Cooldown

- Cuando un módulo de ataque permite añadir **delay artificial del usuario**,
  la opción simple se llama **`Cooldown`**, está expresada en segundos y su
  valor por defecto es **`0`**. No se presenta como `Throw interval`,
  `Spam interval` ni como una sucesión de sliders escondidos.
- `0` significa **cero espera adicional**: se vuelve a intentar en el siguiente
  tick del scheduler o en cuanto la ruta nativa esté lista. Así se busca la
  máxima frecuencia que el Tool, la animación, la replicación y el servidor
  permitan. No significa que todos los intentos serán aceptados ni que se pueda
  ignorar un cooldown real del juego.
- Un valor positivo añade solamente la espera elegida por el usuario. Debe
  existir una sola fuente de verdad para ese reloj, sin un `nextKnifeAt`,
  `task.wait(interval)` y un timer de UI compitiendo entre sí. Al cambiar el
  valor se define si afecta al siguiente intento; no se reinicia el contador de
  estadísticas ni se duplica el trabajo pendiente.
- El cooldown de usuario no sustituye **windup, recovery, animación, reload,
  `Tool.Enabled`, hit window, cooldown replicado, RTT, rate limit ni un gate de
  confirmación medido**. Esos tiempos se nombran por lo que son y se conservan
  cuando hay evidencia. Tampoco se copia el `0.25` de MM2, el `0.86` de un swing
  o el gate de Shoot a otro juego como si fueran universales.
- Los refrescos de status/ESP no son cooldown de ataque. Un `Step interval` de
  Auto Farm tampoco es el Cooldown de Knife Throw: son bucles y propósitos
  distintos.
- La prueba mínima de esta convención es: default `0`, un intento sin espera
  artificial cuando la ruta está libre, un valor positivo que sí espera, y
  cancelación sin timers ni atributos colgados. La prueba no debe afirmar una
  tasa de aceptación del servidor que el harness no puede observar.

**Estado v143:** X2 Auto Shoot y Knife Throw ofrecen `Cooldown` independiente,
por defecto 0; el de Knife empieza tras el windup/release nativo, no en paralelo.
Ambos son límites de intentos del cliente, no prometen frecuencia aceptada por
el servidor. Los delays medidos en MM2 no se copian a X2 como evidencia.

### Cuando el arma tiene críticos o calidad de impacto

No todo se resuelve con «más rápido». Si el juego tiene estados como `Miss`,
`Bad`, `Okay`, `Good`, `Critical`, `Perfect`, `Block` o `Parry`, primero se
descubre dónde nace cada estado y qué lo confirma:

1. Se registra la entrada y el instante de la ventana de impacto.
2. Se identifica el estado nativo de carga/swing y su animación.
3. Se observa el resultado sin convertir una etiqueta ambigua en daño.
4. Se decide si la opción debe ser tiempo, modo, prioridad o simplemente status.
5. Se prueban los límites: demasiado pronto, dentro de ventana, demasiado tarde,
   objetivo muerto, cambio de Tool y respawn.

Por ejemplo, `Hit Time` puede controlar cuándo se intenta el impacto, mientras
`Critical` puede ser una prioridad o un modo; `Miss/Bad/Okay` pueden ser
resultados que sólo se muestran. No se deben convertir todos en toggles ni
prometer críticos si sólo se observó una animación. En Kill Aura estos detalles
pertenecen a las opciones del melee correspondiente; en Knife Throw pertenecen
a la tarjeta o sección del proyectil que el usuario haya pedido para ese juego.

## 1D. Auto Farm, Auto Win y estadísticas útiles

Las utilidades deben explicar qué están haciendo y qué han conseguido. Una
tarjeta de farm no debería obligar a mirar el output para saber si está
esperando, moviéndose, reintentando o realmente recolectando.

### Contrato de datos para Auto Farm

Como regla de diseño, la tarjeta o su status de sesión debe poder representar,
cuando el juego tenga evidencia para ello:

- **`Coins collected`**: recolecciones confirmadas, no simples intentos de
  `firetouchinterest`, teletransportes o ProximityPrompt.
- **`Wins` y `Loses`**: resultados locales explícitos, deduplicados por ronda;
  un respawn, una muerte o una pantalla ambigua no se convierte en victoria.
- **`Time spent`**: tiempo de la sesión de farm, definiendo si cuenta sólo el
  tiempo activo o también esperas. La opción recomendada es medir tiempo activo
  con `os.clock()` y acumular delta al pausar/apagar, sin sumar dos veces al
  cambiar de personaje.
- **Contexto opcional**: `Coins/min`, rondas, monedas pendientes, reintentos,
  objetivo actual, estado (`Waiting`, `Farming`, `Returning`, `No currency`) y
  último error útil. Sólo se añaden si ayudan; no se inventan métricas para
  llenar la tarjeta.

Los contadores deben tener una fuente única. Si Auto Farm y Auto Win muestran
las mismas wins/losses, leen el mismo store de sesión en lugar de incrementar
cada uno su propia copia. Hay que separar **sesión**, **ronda** y **total
persistente**, y documentar cuándo se reinicia cada uno. Las cifras del cliente
no se presentan como saldo autoritativo del servidor.

**Estado actual:** X2 v143 Auto Win muestra `Time Spent`, `Duels Won` y
`Current Game mode` con las definiciones de §1A. Auto Farm sigue reportando
principalmente búsqueda y contacto. No escribir `Coins collected` como si
estuviera confirmado sin una señal real de recompensa del servidor.

### Qué significa Utilities en este proyecto

Auto Farm y Auto Win van en **Utilities** porque son ayudas de gestión,
recolección, estado o farmeo, no una modificación directa de la hitbox del
objetivo. Que una utilidad sea poderosa no la convierte en Exploits. En cambio,
**Hitbox sí va en Exploits** porque altera una propiedad de colisión/tamaño y
debe restaurar exactamente lo que cambió.

La categoría no sustituye la seguridad: una utilidad puede seguir necesitando
Team Check, comprobación de ronda, ownership y cleanup; un módulo Exploits no
recibe permiso para inventar remotes. La pregunta de categoría es «qué tipo de
ayuda ofrece», y la pregunta de seguridad es «qué puede cambiar y cómo se
restaura».

## 1E. Checklist de salida para un game

Antes de dar un módulo por terminado, el próximo agente debe poder responder
«sí» o dejar escrito por qué todavía no puede:

1. **Identidad:** PlaceId, perfil, fingerprint y loader apuntan al juego correcto;
   no se carga otro game por un nombre parecido.
2. **Reglas:** equipos, relación Enemy/Teammate/Unknown/Outside, Tools y
   resultados tienen funciones puras y pruebas; Unknown no se convierte en
   enemigo por conveniencia.
3. **Core:** existe un solo adaptador de objetivo/ataque y los módulos lo usan;
   no hay dos árboles Shoot ni dos loops equipando el mismo Tool.
4. **Silent AIM:** la keybind de acción no cambia el toggle maestro; las
   tarjetas de proyectiles siguen la ubicación solicitada para ese juego. En X2
   Auto Shoot y Knife Throw son independientes, con arbitraje compartido.
5. **Kill Aura:** sólo contiene melee; reach, swing, hit time, críticos,
   miss/bad/okay, recovery y cooldown se modelan únicamente si la mecánica los
   tiene y se pueden observar.
6. **Cooldown:** el delay artificial nuevo se llama Cooldown, empieza en 0 y no
   se duplica con otro intervalo; los tiempos nativos/medidos siguen explicados
   por separado y no se promete aceptación del servidor.
7. **Utilities:** Auto Farm/Auto Win muestran estado y datos reales; Coins
   collected no se incrementa por un intento, y Wins/Loses/Time spent tienen
   una definición de sesión/ronda y deduplicación.
8. **Categorías:** Utilities no se usa como sinónimo de Exploits; Hitbox y
   otras manipulaciones directas tienen cleanup y van en Exploits; ESP queda en
   Render usando los providers compartidos.
9. **Ciclo de vida:** OFF, cambio de Tool, muerte, respawn, salida del jugador,
   cambio de PlaceId y destroy cancelan trabajos y restauran todo lo tocado.
10. **Pruebas y publicación:** se actualizan los contratos afectados, se compila,
    `bash tools/validate.sh` queda verde, se regenera el bundle con un stamp
    nuevo para cambios de runtime y se publica en la rama de la sesión.
11. **Límite de evidencia:** el handoff separa lo verificado offline de lo que
    falta comprobar live. Nunca se escribe «funciona daño/monedas/wins» sólo
    porque un mock llamó a Activate o porque apareció una animación.

## 1F. Antes de añadir una función: pensar, ubicar y después escribir

No se empieza por `createUniversalFeature`. Se empieza por entender la función y
buscar su dueño actual. El prefijo `Auto`, que la idea parezca pequeña o que el
código quepa en un archivo nuevo **no justifica una tarjeta nueva**.

### Archivo, tarjeta, opción y categoría no son lo mismo

- **Archivo técnico:** separa código para mantenerlo legible. Puede existir sin
  añadir ninguna entrada al menú.
- **Tarjeta:** representa una intención de control independiente, con su master,
  estado, opciones y ciclo de vida. Es lo que hay que limitar.
- **Opción/acción:** una variante o paso dentro de una tarjeta que ya posee el
  mecanismo. Puede ser toggle, dropdown, slider, botón hold o texto de estado.
- **Categoría:** la ventana/grupo en que aparece la tarjeta: Combat, Utilities,
  Exploits, Render, World, etc. No indica por sí sola quién debe ser el padre.

El ejemplo canónico es **Sprint**: `src/games/MM2/Movement/Sprint.lua` es un
archivo separado, pero registra su botón dentro de **Speed** y usa
`SetSprintHeld`, `StepSprint`, `SprintFrame` y `ClearSprint`. No crea una tarjeta
Sprint independiente. Si se añade **Auto Sprint**, la ubicación por defecto es
una opción **dentro de Speed**, reutilizando ese mismo estado de locomoción;
no una tarjeta `Auto Sprint` con otro Heartbeat y otra escritura de WalkSpeed.

Esto también evita una simplificación incorrecta: no todo lo relacionado debe
fusionarse. Aim Assist, Silent AIM y TriggerBot pueden compartir targeting sin
ser la misma tarjeta porque su comportamiento de activación es distinto. Speed
y Noclip comparten el personaje, pero WalkSpeed/velocidad y colisión tienen
propósitos, riesgos y restores diferentes. La regla es compartir el **estado y
el ciclo de vida real**, no solamente el tema.

### El árbol de decisión obligatorio

Antes de implementar, recorre estas preguntas en orden y escribe las respuestas
en el análisis o en el resumen del cambio:

1. **¿Qué quiere hacer el usuario, en una frase?** «mantener sprint al caminar»
   no es lo mismo que «aumentar WalkSpeed», «saltar automáticamente» o «volar».
2. **¿Ya existe una tarjeta que haga eso o controle el mismo estado?** Busca por
   nombre, propiedad, Tool, cámara, target, remote, conexión y cleanup. Si la
   respuesta es sí, la primera opción es una subopción, no otra tarjeta.
3. **¿Qué recurso sería compartido?** WalkSpeed, Humanoid, cámara, Tool,
   proyectil, selección de objetivo, lista de monedas, ventana de resultados,
   scheduler o estadísticas. Dos dueños escribiendo el mismo recurso son un bug
   aunque cada uno pase sus tests por separado.
4. **¿Puede ser sólo una opción, una acción, un provider o un status?** No toda
   función necesita master propio. Un contador puede ser status; Team/Role ESP
   puede ser provider; un click puntual puede ser botón dentro de Teleport.
5. **Si es una opción, ¿depende del master?** Define si Speed OFF detiene Auto
   Sprint y qué preferencias se conservan. En X2 Silent AIM OFF no desactiva
   Auto Shoot ni Knife Throw. «Independiente» significa independencia real con
   coordinación del recurso compartido.
6. **¿Cuál es su mecanismo dominante?** Proyectil → Silent AIM; melee → Kill
   Aura; locomoción → Speed/Jump/Fly/Teleport según la acción; información →
   Render/status; farm o resultado automatizado → Utilities; alteración directa
   de una propiedad explotable → Exploits. El nombre no decide por encima del
   mecanismo.
7. **¿Es universal o específica del juego?** Sólo es universal si el contrato es
   realmente genérico. Un remote, animación, atributo o Tool particular pertenece
   al game; el adaptador universal puede recibirlo mediante un provider.
8. **¿Qué opciones necesita y cuáles sobran?** No añadir Range, Cooldown, Mode o
   Team Check por plantilla. Para delay artificial nuevo, Cooldown empieza en 0;
   para mecánicas especiales se usan sus términos reales, con evidencia.
9. **¿Cuál es el comportamiento por defecto?** Lo seguro suele ser OFF, tecla
   Unknown y sin restaurar automatizaciones antiguas. Un valor por defecto no
   debe cambiar el movimiento, disparar o farmear al cargar el menú sin que el
   usuario lo haya elegido.
10. **¿Qué ocurre al apagar, morir, respawnear, cambiar de Tool/personaje,
    teleportar o destruir el módulo?** Si no se pueden enumerar los restores y
    las conexiones, todavía no está lista la función.
11. **¿Cómo se prueba la ubicación y la propiedad?** Debe existir un contrato
    que impida la tarjeta duplicada y compruebe que sólo hay un scheduler/dueño,
    además de las pruebas funcionales y de cleanup.
12. **¿Qué sigue siendo una suposición?** Si falta el mecanismo live, se pide
    evidencia o se deja pendiente; no se rellena el hueco con un remote o un
    comportamiento inventado.

Si una respuesta cambia, hay que volver a las anteriores. Por ejemplo, si al
responder «¿qué recurso comparte?» se descubre que Auto Sprint necesita
WalkSpeed y el estado de Speed, ya no se puede justificar una tarjeta aislada
sin explicar cómo se evita la doble escritura.

### Ejemplos de ubicación antes de crear nada

| Idea solicitada | Ubicación inicial que debe evaluar el agente | Motivo y límite |
| --- | --- | --- |
| **Auto Sprint / Sprint hold / sprint trail** | Opción o acción dentro de **Speed**. | Comparte Humanoid, velocidad, estados sentado/aire y restores. El archivo Sprint puede existir, pero no otra tarjeta ni otro escritor de velocidad. |
| **Auto Jump / Bunny Hop** | Si mantiene el movimiento de Speed, dentro de **Speed**; si cambia impulso/altura de salto, dentro de **Jump**. | El nombre «jump» no basta: decide si el efecto principal es continuar desplazándose o modificar el salto. Si ambas lecturas cambian el comportamiento, preguntar. |
| **Click Teleport / teleport a un marker** | Acción u opción de **Teleport**, reutilizando destinos y coordenadas. | No crear otro sistema de CFrame ni otra lista de puntos. Markers puede seguir siendo Render si su responsabilidad es mostrar/guardar marcadores. |
| **Auto Shoot / Gun Throw / Knife Throw** | Evaluar secciones de **Silent AIM** o tarjetas separadas si el usuario lo solicita. | En X2 Auto Shoot/Knife Throw son tarjetas separadas por petición expresa; comparten adaptador y arbitraje, no checks ni master. |
| **Melee Reach / Hit Time / Critical** | Opciones del arma bajo **Kill Aura**. | Reach como distancia de selección no es Hitbox. Si se cambia el tamaño real de una parte, eso sí pertenece a Hitbox/Exploits y necesita restore. |
| **Team ESP / Role ESP / Enemy ESP** | **PlayerESP** y los providers compartidos de equipos/roles. | No crear otro scanner, otra paleta incompatible ni otra lista de jugadores. Chams/Nametags pueden ser tarjetas distintas si renderizan objetos distintos, pero usan la misma relación. |
| **Coin ESP / Gun ESP / otro pickup ESP** | Provider del **ItemESP/CoinESP** que ya descubre esa familia. | Añadir una fuente o un estilo no exige repetir el escaneo completo. Si el mecanismo visual es realmente distinto, se justifica antes de crear otra tarjeta. |
| **Anti Fling** | Subopción de **Anti Void**, como ya ocurre, con su propia preferencia. | Comparte protección física y ciclo de vida, pero no se fuerza a depender del toggle de Anti Void. |
| **Remove textures / particles / shadows / simple materials** | Opciones de **Improve FPS**. | Son variantes del mismo objetivo y cleanup; una tarjeta por propiedad sería ruido y multiplicaría restores. |
| **Freeze Emotes / Freeze Animation** | Opciones de **Freeze Movements**. | Comparten personaje, Animator y snapshot; cada preferencia puede seguir siendo independiente. |
| **Disguise packs / Body / Animation / Advanced** | Secciones y opciones de **Disguise**. | No una tarjeta por pack, bundle o slot. Las rutas de apariencia y animación comparten snapshot y restauración. |
| **Auto Farm / Auto Win** | Tarjetas de **Utilities**, con estadísticas compartidas cuando midan lo mismo. | Tienen intenciones y ciclos diferentes, así que compartir datos no obliga a fusionarlas. Ninguna va en Exploits sólo por automatizar. |
| **Auto Unbox** | **Utilities**, con sus propias opciones de caja/reveal/delay. | Es otra utilidad, no una subopción de Auto Farm ni una variante de Shoot. |
| **Noclip** | Tarjeta propia en **Exploits**, no un modo de Speed por defecto. | Aunque afecta al movimiento, cambia colisiones y tiene otro riesgo/cleanup. Éste es un ejemplo válido de no anidar. |

Estas ubicaciones son el punto de partida, no una excusa para ignorar el código.
Si el módulo existente ya tiene un dueño distinto, hay que leerlo y explicar la
migración antes de mover nada. Y si una nueva función sólo es un paso de una
secuencia de farm, Auto Farm puede invocarla, pero la mecánica de combate debe
delegar en el adaptador correspondiente: **llamar a Shoot no autoriza a copiar
Shoot dentro de Auto Farm**.

### Cuándo el agente debe preguntar al usuario

No hay que interrumpir para lo obvio: `Auto Sprint → Speed`, `Knife Throw →
Silent AIM`, `Team ESP → PlayerESP/providers` ya tienen respuesta estructural.
El agente la aplica y deja la ubicación en el resumen.

En cambio, **debe detenerse y preguntar antes de escribir** cuando ocurra
cualquiera de estos casos:

- quiere crear una **tarjeta nueva de nivel superior** o una **categoría nueva**
  que el usuario no pidió explícitamente;
- hay dos tarjetas existentes que podrían ser dueñas y la elección cambia el
  comportamiento, las keybinds o los valores guardados;
- quiere dividir una tarjeta actual, fusionar dos, mover una función de
  categoría o convertir una opción existente en otra tarjeta;
- la función necesita un nuevo bucle global, otro escritor del mismo recurso,
  una automatización con efecto en servidor o un comportamiento activo por
  defecto;
- la evidencia no permite saber si es proyectil o melee, utilidad o exploit,
  universal o específica del juego;
- el cambio altera una decisión anterior del usuario o rompe compatibilidad de
  configuración.

La pregunta debe ser concreta y traer una recomendación, no «¿qué hago?». Usa
este formato:

```text
La función controla <recurso> y comparte <estado/cleanup> con <tarjeta>.
Propongo ponerla como <opción/acción/status> dentro de <tarjeta>, en
<categoría>, porque <razón>. La alternativa sería una tarjeta independiente,
pero duplicaría <coste/estado>. ¿Confirmas la ubicación propuesta?
```

Ejemplo:

```text
Auto Sprint controla la misma velocidad y estados Humanoid que Speed.
Propongo añadirlo como toggle dentro de Speed, no como tarjeta nueva. Hay que
definir si, como el Sprint hold actual, puede trabajar con Speed OFF o si
depende del master, sin crear otro escritor de velocidad. ¿Confirmas esa
ubicación y esa dependencia?
```

Si el usuario ya respondió esa pregunta para una familia, no se vuelve a pedir
confirmación por cada skin o variante. Se conserva la decisión y se documenta.
El control debe venir de una estructura comprensible, no de veinte preguntas
repetidas ni de veinte tarjetas casi idénticas.

### Nota mínima que debe acompañar a cada función nueva

Antes de marcarla como terminada, deja estas seis líneas en el análisis, test o
RESUME cuando sea una decisión durable:

```text
Función: <qué hace>
Ubicación: <tarjeta padre / opción / acción / provider / status>
Categoría: <Combat / Utilities / Exploits / Render / World / ...>
Dueño del estado: <core, propiedad, scheduler y cleanup>
Opciones/defaults: <sólo las necesarias; Cooldown = 0 si aplica>
Evidencia y pruebas: <observado, offline, pendiente live>
```

Si no se puede rellenar «Ubicación» o «Dueño del estado», todavía no toca crear
la función.

## 1G. Toolchain: qué hace falta y qué no hay que instalar

No basta con escribir «usa Luau». Un agente que retoma el proyecto debe poder
preparar un clone limpio, compilar, ejecutar las pruebas y saber qué evidencia
sale de cada herramienta. Tampoco debe convertir nombres conocidos —Darklua,
StyLua, Selene o Rojo— en dependencias obligatorias si el pipeline no los usa.

### Requisitos del pipeline normal

| Herramienta | Para qué se necesita | Estado y preparación |
| --- | --- | --- |
| **Bash** y utilidades Unix (`find`, `grep`, `cut`, `tar`) | `tools/validate.sh`, setup y comprobaciones de salida. | Ejecutar con `bash`, no con `sh`: el script usa `pipefail` y process substitution. En Windows usar WSL o Git Bash conservando LF. |
| **Python 3** como `python3` | Build/check del bundle, harness, suites, auditorías y análisis offline. | El build y las suites de `validate.sh` usan la biblioteca estándar; no hace falta un `pip install` general. Comprobar con `python3 --version`. |
| **Node.js** como `node` | Ejecutar el paquete Luau WASM vendored. | Es el único runtime externo del toolchain Luau. **No hace falta npm ni `npm install`** para el flujo normal. Comprobar con `node --version`. |
| **Luau 0.739.0** (`luau` y `luau-compile`) | Ejecutar harnesses y compilar cada fuente `.lua`. | Está fijado en `tools/luau/vendor/luau-rs-luau-0.739.0.tgz`; `bash tools/luau/setup.sh` crea los wrappers en `tools/luau/bin/`. |
| **Git** | Revisar el diff, preservar el alcance y publicar el commit correcto. | No interviene en las pruebas, pero sí en el protocolo de publicación. |
| **GitHub CLI (`gh`)**, cuando haga falta | PR, issues, checks, releases o recuperación mediante API. | No es requisito de `validate.sh`; no sustituye a `git` para commit/push ni debe pedirse ninguna credencial al usuario. |

`tools/luau/bin/` y `tools/luau/node_modules/` están ignorados porque son
artefactos locales. Lo reproducible y versionado es el tarball de `vendor/` más
`setup.sh`, `run.mjs` y `compile.mjs`. En un clone limpio, `validate.sh` intenta
el setup automáticamente si falta el wrapper y existe el tarball; aun así, ante
un fallo conviene ejecutar el setup explícitamente para ver el error real.

### Arranque y comprobación desde la raíz

```bash
git status --short
python3 --version
node --version
bash tools/luau/setup.sh
tools/luau/bin/luau-compile src/Wurst.lua
bash tools/validate.sh
```

El `luau-compile` aislado es un smoke test de sintaxis; el pase completo es
`bash tools/validate.sh`. Ese runner comprueba que el bundle y el stamp no estén
desincronizados, compila todas las fuentes, ejecuta todos los `tools/test_*.py`,
genera y arranca el harness completo, audita exports `core.*`/`prediction.*` y
vuelca el menú debug/release. No se declara éxito mirando sólo el final del log:
cualquier comando fallido detiene el script.

Si se usa otra instalación de Luau, se puede seleccionar sin editar el runner:

```bash
LUAU_DIR=/ruta/al/directorio bash tools/validate.sh
# o rutas independientes:
LUAU=/ruta/a/luau LUAU_COMPILE=/ruta/a/luau-compile bash tools/validate.sh
```

No se copian binarios al repositorio ni se cambia el PATH global del usuario.
Si falta una herramienta, se arregla el entorno o el setup; no se omite la suite
ni se relaja un assertion para obtener un falso verde.

### Mapa de herramientas del propio repositorio

| Herramienta | Cuándo usarla | Qué demuestra / qué no demuestra |
| --- | --- | --- |
| `python3 tools/build_bundle.py --stamp <stamp>` | Después de un cambio de runtime, con el mismo `SOURCE_STAMP` de `src/Wurst.lua`. | Regenera `src/libraries/bundle.lua` desde las fuentes. No valida por sí solo el comportamiento. |
| `python3 tools/build_bundle.py --check --stamp <stamp>` | Antes de publicar y dentro de `validate.sh`. | Detecta fuentes ausentes, huérfanas o distintas y stamps incompatibles. |
| `bash tools/validate.sh` | Antes de cualquier push de runtime y después de preparar el entorno. | Es la puerta offline completa; no prueba daño, recompensas ni aceptación de un servidor Roblox live. |
| `python3 tools/test_<nombre>.py` | Durante el desarrollo, para iterar sobre el módulo afectado. | Da feedback focalizado; no reemplaza la validación completa final. Ejemplos: `test_mm2_sprint_option.py`, `test_speed_modes.py`, `test_x2duels.py`. |
| `python3 tools/gen_full_boot_harness.py` | Normalmente mediante `validate.sh`; de forma directa para depurar el boot. | Genera `build/full_boot.luau`; el archivo generado no se edita como si fuera una fuente. |
| `python3 tools/audit_menu.py` / `--release` | Cuando cambien tarjetas, categorías, opciones o visibilidad debug. | Arranca el bundle real y vuelca lo registrado, no sólo nombres encontrados por grep. `--release` debe excluir Calibration. |
| `python3 tools/audit_module_api.py` | Al añadir o renombrar llamadas `core.*` o `prediction.*`. | Comprueba que cada llamada tenga un export; no demuestra que su comportamiento sea correcto. |
| `python3 tools/replay_gun_prediction.py` y `analyze_*.py` / `audit_*.py` pertinentes | Sólo con capturas o fixtures relacionados con la pregunta investigada. | Reproducen o resumen evidencia cliente. Sus límites deben acompañar al resultado; no convierten muestras pequeñas en precisión live. |
| `tools/X2DuelsDecompiler.luau` + `tools/X2DuelsDecompiler.md` | Para obtener evidencia específica de X2 en el entorno live apropiado. | El colector vuelca fuentes, inventario y llamadas observadas. `python3 tools/test_x2duels_decompiler.py` sólo valida sus contratos contra un DataModel simulado. |
| `tools/diagnostics/*` | Sólo para un diagnóstico concreto y con el alcance indicado por su propia guía. | No son parte del arranque normal ni se deben cargar todos por rutina. |

Roblox Studio, un executor y una sesión live **no son requisitos de las pruebas
offline**, pero las pruebas offline tampoco los sustituyen cuando la pregunta es
si el servidor aceptó una acción. Hay que nombrar siempre cuál de esos dos
entornos produjo la evidencia.

### Darklua, formato, lint y dependencias opcionales

- **Darklua** (no «Darkluau») **no está instalado, configurado ni es necesario**.
  Este repositorio no lo invoca: el empaquetador real es
  `tools/build_bundle.py`, y `src/libraries/bundle.lua` contiene las fuentes
  para el loader actual. No añadir un segundo bundler, minificador o reescritor
  de `require` sólo porque existe; podría producir un artefacto distinto del que
  prueban los harnesses.
- **StyLua, Selene, luau-analyze, Lune y Rojo tampoco forman parte del pipeline
  actual.** No hay configuración que los convierta en una puerta. Si una tarea
  los necesita de verdad, se fija versión y configuración, se prueba el comando
  y se documenta el motivo; no se formatea todo el árbol ni se introduce otra
  cadena de build de manera incidental.
- `tools/process_manga_assets.py` es una excepción opcional: importa **Pillow**
  (`PIL`) y **NumPy**. Esas dependencias sólo se instalan para procesar esos
  assets (`python3 -m pip install Pillow numpy`); no son necesarias para
  compilar, generar el bundle ni ejecutar `validate.sh`.
- Los mocks y herramientas ya incluidos son la primera opción. Antes de añadir
  una dependencia nueva hay que explicar qué hueco cubre, cómo se instala de
  forma reproducible, qué comando la ejecuta y qué prueba impide que quede
  abandonada. Una herramienta experimental no se convierte en un paso que el
  usuario tenga que arreglar manualmente.

En resumen: **el toolchain obligatorio es Bash + Python 3 + Node.js + el Luau
vendored; Git/gh cubren publicación. Darklua no es un requisito**. El comando
que reúne la comprobación normal sigue siendo `bash tools/validate.sh`.

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

## 6. Velocidad, Cooldown y delays: qué significa "instantáneo"

- El suelo físico es **un frame** (Heartbeat ≈ 16.7 ms a 60 FPS) + ping. Todos
  los `TaskManager:Connect` corren por Heartbeat; los binds disparan en el evento.
- Eliminado en v112: poll de 0.5 s de Auto Get Gun (ahora cada frame + tick
  inmediato al activar) y caché negativa de `findDroppedGun` 0.4 s → 0.05 s.
  Auto Farm espera *condiciones* frame a frame, no sleeps fijos.
- Para delay artificial de combate en módulos nuevos se usa **Cooldown = 0 por
  defecto** (ver §1C): no hay espera extra y se intenta a la máxima frecuencia
  que la ruta nativa permita. Un valor mayor es una preferencia del usuario, no
  una prueba de que el servidor acepte más o menos acciones.
- **Delays deliberados que NO debes "optimizar" sin evidencia** (están fijados
  por `tools/test_action_latency.py` para las rutas actuales; no son una
  plantilla de Cooldown para otros juegos):
  - Shoot MM2: gate 1.5 s entre disparos (ver §3), ligado a confirmación y no a
    un slider genérico de spam.
  - KnifeThrow MM2: timing de paquete/animación de 0.25 s + ciclo de animación.
    **La animación del throw debe verse** (sin ella es blatant); se eliminó
    "Throw with button". Este valor histórico/medido no se copia a X2 ni se
    confunde con el Cooldown opcional de una implementación nueva.
  - KnifeAura MM2: ciclo de swing medido 0.86 s, propio de esa mecánica melee.
  - Auto Unbox: delay entre cajas **configurable y a propósito lento** — es el
    arreglo de la pantalla gris/negra al spamear. No lo aceleres.
  - Rates con slider del usuario (TriggerBot Delay, KillAura swings/s, etc.):
    son suyos, no delays ocultos. Si se migra una opción a Cooldown, se conserva
    el valor sólo cuando representa exactamente el mismo delay.
  - Refrescos de status/visuales a 0.2–5 s (ESP, Chams, Coin ESP): no retrasan
    ninguna acción ni deben usarse como reloj de combate.

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
4. Los wrappers y `node_modules` de Luau no persisten entre sesiones: ejecuta
   `bash tools/luau/setup.sh` y comprueba los requisitos de §1G. El tarball sí
   está versionado; no uses npm ni instales Darklua para sustituirlo. Sin red a
   `raw.githubusercontent` (SSL): usa `gh api` o clone.
5. `tools/audit_module_api.py` corre desde validate.sh: todo `core.*` /
   `prediction.*` llamado debe existir como export en `state.mm2Core` /
   Prediction. Si añades una llamada, añade el export o el test te detiene.
6. Los tests son la red: si un test espera el comportamiento viejo y tu cambio
   es correcto, **actualiza el test explicando el porqué en el comentario**
   (pasó con la puerta de eco en v104/v105). No hagas que el código mienta
   para que un test viejo pase.

## 9. Pendiente de verificación EN VIVO (no lo des por hecho)

Nada de esto está probado en partida real todavía; v145 pasó las 64 suites,
el boot simulado y las auditorías, que no sustituyen una prueba en juego:

- v141: consumo real al inyectar y en reposo/con funciones activas, Auto Farm y
  Auto Win en lobby/countdown, detección de monedas y Silent AIM/Knife PC/móvil;
  reiniciar Roblox antes de comparar para retirar hooks anteriores de v140.
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
- X2 v145: el usuario reportó que v143 no funcionaba en celular. Probar en vivo
  1v1 y 2v2 con nombre de executor, botón Silent PC/móvil y disparo nativo, con
  Mouse Compatibility OFF/ON, Head/Body y Aim FOV OFF/ON. Verificar si `fire` y
  `showBeam` están en la Gun, `checkcaller` y hooks funcionan y qué status aparece;
  comprobar si el arma usa MouseCast/Mouse/rayos y si `getcallingscript` o el
  stack la identifican. Un tiro intentado o lectura redirigida no prueban daño.
  Con el arma ya disponible ejecutar `snapshotWeapons()` del recolector y esperar
  el mensaje de fin: el dump inicial puede preceder al arma. Revisar también
  independientes Auto Shoot/Knife, ThrowMode, Safe Place (física/techo/restore),
  Revancha, checks, FFA, Hitbox, TriggerBot, hooks ajenos, Pumpkin/saldo y
  resultados finales. Un `MatchResults` atrasado previamente no visto de otra
  partida aún podría limpiar Safe Place actual; IDs no están correlacionados.

## 10. Cómo trabajar con este usuario

- Aporta las calibraciones **antes** de pedir cambios: analízalas (con los
  filtros de §3) y da veredicto con números de SU archivo, no de memoria.
- No toques el predictor sin datos. No generalices desde n=4. Si la muestra es
  pequeña, dilo y pide la sesión que falta, con la configuración exacta.
- Cuando algo no se puede verificar desde aquí, dilo explícitamente y separa
  "verificado" de "plausible" de "pendiente en vivo".
- Antes de añadir cualquier función, aplica la puerta de §1F: explica dónde irá,
  qué tarjeta/estado ya es dueño y por qué no duplica otro módulo. Si hará falta
  una tarjeta/categoría nueva o hay dos ubicaciones razonables, pregunta con una
  propuesta concreta antes de escribir; no crees `Auto Sprint` fuera de Speed.
- Cambios pequeños, versionados (bump de stamp por cambio), con test que fije
  el comportamiento y `validate.sh` verde antes de pushear.

---
*Última actualización: 2026-10-29 · v155, Gun y Knife CFrame experimentales sin
hooks; Delta móvil, BAC, aceptación del servidor y daño real siguen sin validar.
Al publicar una versión nueva, actualiza la línea de estado de arriba y cualquier
sección que cambie.*
