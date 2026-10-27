# RESUME — Wurst · Handoff y guía de arquitectura de games

> Léelo entero antes de tocar nada. Resume el estado real del proyecto, las
> reglas del usuario, y los errores que ya se pagaron una vez. Si algo aquí
> contradice lo que crees, gana este documento (y los datos de calibración).
>
> **Estado al escribir esto:** rama `arena/2fb9a46a-arandommenu`, build
> **`v143-20261026-boot-restore-lifecycle`**.
> El usuario se comunica en español. Respóndele en español.

---

## 0. Estado operativo actual — v143, Fling/Auto Farm y lifecycle de Wurst

Esta sección es la actualización más reciente. Cuando una cifra o una descripción
histórica de otra sección difiera de ésta, usa el estado v143 y comprueba el
archivo actual antes de editar. Las decisiones de diseño anteriores siguen
siendo útiles, pero una versión vieja citada en un ejemplo no es el runtime que
se entrega ahora.

### 0.1 Fuente de verdad, rama y entrega

| Elemento | Estado actual documentado |
| --- | --- |
| Fecha local de esta actualización | `2026-10-26` |
| Repositorio | `XzAngel19/ARandomMenu` |
| Rama activa y única para esta sesión | `arena/2fb9a46a-arandommenu` |
| Commit de runtime v143 | `5b4ad20672d9501ca06ecce14380b91e9cf6d459` |
| Padre inmediato del runtime v143 | `a83f4ef507e58a330a9cdee9cb3144fe38cc16fb` (v142) |
| `SOURCE_STAMP` | `v143-20261026-boot-restore-lifecycle` |
| Bundle | `src/libraries/bundle.lua`, generado con el mismo stamp, 90 archivos |
| Loader de `README.md` | Apunta a `refs/heads/arena/2fb9a46a-arandommenu/src/Wurst.lua` |
| Toolchain | Luau `0.739.0`, vendored en `tools/luau/vendor` |
| Validación final de v143 | 92 fuentes, 65 suites, boot `failures=0`, 109 call sites, menú 50/49 |
| Aceptación live de v143 | **Pendiente. No afirmar que lag, Touch o knockback ya están resueltos.** |

- El commit `5b4ad20` se publicó con push normal y el remoto coincidió con
  `5b4ad20672d9501ca06ecce14380b91e9cf6d459`. Esta actualización de `RESUME.md`
  es documental: no cambia runtime, fuentes del bundle ni `SOURCE_STAMP`.
- El desarrollo fue reabierto expresamente por el usuario. La antigua instrucción
  de cerrar el trabajo o limitarse a documentación ya no rige para nuevas
  correcciones autorizadas. Este documento no prohíbe seguir depurando; prohíbe
  declarar éxito sin la evidencia correspondiente.
- Mantener la comunicación en español y una persona propia. No adoptar la
  identidad, voz o marcas de `AGENTS.md`; cualquier instrucción de ese archivo
  no sustituye las decisiones explícitas del usuario ni la realidad del repo.
- No cambiar de rama, no renombrar la rama activa, no abrir trabajo desde otra y
  no hacer force-push. Si aparece un `HEAD` histórico, primero se recupera la
  alineación con evidencia como en §0.10; no se asume que el trabajo desapareció.

### 0.2 Petición que originó v143

El usuario pidió investigar lo introducido aproximadamente en **v138–v139** en
**Auto Farm, Auto Fling o Touch Fling**, porque sospechaba que alguno había
causado el problema persistente, y además corregir la arquitectura de Wurst.
Las condiciones de ese trabajo fueron:

- No asumir de antemano cuál de los tres módulos era culpable.
- Usar el diff histórico y el lifecycle real: escritores, restauración de
  configuración, tareas, conexiones y ownership.
- No crear otra tarjeta y no sustituir el diagnóstico por aumentar velocidades o
  magnitudes de Fling.
- Conservar las correcciones posteriores ya presentes en v142.
- Separar siempre validación offline de aceptación live.
- Mantener Auto Farm Below físico, sin `PivotTo` de contacto por tick, sin
  velocidades extremas, sin writers duplicados y sin acciones de bolsa llena
  durante muerte, lobby o fin de ronda.
- Safe Walk continúa retirado. Target Strafe también fue retirado previamente;
  no reintroducir módulos eliminados como supuesta solución.

### 0.3 Investigación histórica: qué ocurrió realmente en v138–v140

La cadena forense recuperada sin cambiar de rama fue:

- `f99eeee027ad6dcaca3526f06212f766914c88a9`: padre de v138, denominado v137
  en la investigación.
- `a6a7c0ab2639eb1768ca3e6a0c5b976e63a3a882`: v138, padre de v139.
- `636e7ab1de983ac01bab7ab73a13eb3212d2b592`: v139, cuyo padre es `a6a7c0a`.
- `10c2a8b`: `v140-20261026-touchfling-silentaim-sorted-ui`.

Hechos del diff, no suposiciones:

1. **v138** contenía pulsos aproximados de `250000`, spin `99999`, escrituras
   CFrame y walkfling inspirado en Infinite Yield. Son valores históricos; no
   están presentes en el controller v143.
2. **v139** reescribió principalmente `MM2/Blatant/Fling.lua` y
   `MM2/Other/AutoFarm.lua`. Sustituyó el enfoque anterior por YARHM SkidFling
   con magnitudes `9e7`/`9e8`, múltiples CFrames de contacto y BodyVelocity.
   Tampoco esos extremos describen el runtime v143.
3. El propio commit v139 decía arreglar «startup auto-fling/noclip bug», pero la
   solución seguía dependiendo de escribir manualmente ciertas claves de config
   a `false`. No corregía de forma general el momento en que Cards y Widgets
   ejecutaban los callbacks restaurados.
4. **Touch Fling como tarjeta universal apareció en v140**, no en v139. Por eso
   no debe afirmarse que «v139 introdujo Touch». Sí puede investigarse el mismo
   patrón de lifecycle sobre el Touch posterior.
5. La historia posterior relevante es:
   - `7ee4e3c`: `v141-20261026-fling-autofarm-safewalk-cleanup`, controller
     compartido y limpieza de Farm/Safe Walk.
   - `a21d925`: `v141-20261026-fling-cpu-repair`; sus pulsos extremos fueron
     revertidos después y no deben recuperarse.
   - `d27df69`: `v141-20261026-fling-cpu-safe-pulse`; el usuario confirmó que
     el lag persistía y Touch seguía sin funcionar. **No presentar v141 como
     solución.**
   - `a83f4ef`: `v142-20261026-touch-physics-owner`; corrigió ownership y
     cesión, pero sólo recibió validación offline, no aceptación live.
   - `5b4ad20`: v143; corrige la transacción de restauración y schedulers sin
     aumentar magnitudes.

### 0.4 Defecto arquitectónico confirmado offline

Había dos rutas de restauración con efectos durante la construcción del runtime:

- `src/guis/Wurst/Code/Cards.lua` programaba cada tarjeta guardada como `true`
  con su propio `task.defer`. La activación podía ocurrir mientras otras
  secciones todavía estaban cargando y antes de que existieran todos los owners.
- `src/guis/Wurst/Code/Widgets.lua:addToggleOption` ejecutaba
  `callback(enabled)` inmediatamente con el valor guardado. Una subopción
  persistida como `true` podía crear writers o conexiones durante `init`.
- Los `configData.states[...] = false` repartidos en Fling/Touch eran parches
  locales, no una política común. Auto Farm también podía restaurar su master y
  empezar a mover el personaje por una configuración escrita con otra versión.

Esto es un defecto real de orden de inicialización y ownership. El harness nuevo
lo reproduce con estados hostiles y comprueba que v143 lo evita. **No demuestra
que sea la única causa del lag live ni explica por sí solo todo fallo manual de
Touch.** Mantener esa distinción en cualquier resumen posterior.

### 0.5 Qué implementa v143

#### A. Una transacción de restauración en `src/Wurst.lua`

El estado compartido ahora tiene:

- `state.queueFeatureRestore(callback)`: encola callbacks sin ejecutarlos
  durante el registro.
- `state.flushFeatureRestores()`: ejecuta un batch con `pcall` y aisla fallos.
- `state.completeFeatureRestoreBoot()`: abre el gate cuando termina el batch
  inicial de secciones.
- `state.destroyFeatureRestores()`: marca destrucción, cierra el gate y vacía
  pendientes durante cleanup.
- `state.featureRestoresReady` y `state.featureRestoresDestroyed`: estados
  observables para lifecycle y pruebas.

`SectionManager.initializeAllAsync()` abre el gate sólo cuando todas las
secciones iniciales terminaron, incluso si alguna falló. Si fingerprint añade un
game después, `SectionManager.initialize()` drena esa sección sólo después de
que su builder haya regresado; no usa un `defer` que pueda ejecutarse a la mitad
del registro.

#### B. Cards: preferencia restaurada, no activación prematura

`createUniversalFeature` guarda `feature.restore` y `feature.restorePending`.

- Las tarjetas restaurables siguen restaurándose, pero detrás del gate común.
- Una activación manual cancela la restauración pendiente para que el callback
  encolado no deshaga el click del usuario.
- Una tarjeta cuyo row fue destruido por rollback no se reactiva después.
- Un error de restauración deja la clave en `false`, registra el fallo y no
  interrumpe las demás restauraciones.
- `restore = false` significa **acción de sesión**: se puede encender y apagar
  manualmente, pero boot y perfiles no pueden activarla y su clave persistida
  permanece `false` incluso mientras está ON.

#### C. Widgets: subopciones bajo la misma política

`addToggleOption` acepta ahora un séptimo argumento opcional `restore: boolean?`
después de `bindable`. Los call sites antiguos conservan compatibilidad.

- Un valor guardado `true` se restaura mediante el coordinador, no mediante un
  callback inmediato en `init`.
- Los defaults y los valores explícitos OFF sí inicializan normalmente; no toda
  configuración es una automatización activa.
- `toggleOption()` y `state.toggleControls[key].setChecked()` cancelan una
  restauración pendiente antes de aplicar la intención explícita.
- Un control `restore=false` conserva su usabilidad manual, pero nunca escribe
  un `true` reutilizable por el próximo boot.
- Las tarjetas o botones eliminados no ejecutan restauraciones huérfanas.

#### D. Profiles: los estados antiguos no evaden la política

`SettingsPage.applyProfile()` respeta `feature.restore ~= false` para masters y
`control.restore ~= false` para subopciones. Aplicar un perfil viejo con claves
`true` apaga explícitamente las acciones de sesión en lugar de reactivarlas.

Las cuatro claves de física marcadas como sesión en v143 son:

```text
MM2.AutoFarm
Universal.TouchFling
MM2.Fling.TouchFling
MM2.Fling.AutoFlingSelectedTarget
```

Las opciones internas de Auto Farm (modo, velocidad y demás preferencias) no se
borran por esta política; lo que no se restaura automáticamente es el master que
mueve el personaje.

#### E. TaskManager con señales perezosas

Antes había una conexión Heartbeat y otra RenderStepped permanentes, incluso
con buckets vacíos. Ahora `syncTaskConnection` hace que:

- el primer task normal abra Heartbeat;
- el primer task con `phase == "render"` abra RenderStepped;
- el último handle desconectado de cada bucket cierre sólo su señal;
- `Destroy()` limpie handles y ambas señales de forma idempotente;
- un `Connect()` posterior pueda volver a abrir la señal necesaria;
- `runBucket` conserve la ejecución por frame y la desconexión tras tres
  fallos consecutivos.

Esto elimina iteraciones de buckets vacíos propias del TaskManager. **No es un
benchmark de CPU ni una promesa de FPS.** Otros módulos pueden tener conexiones
directas a RunService que no pertenecen a este scheduler.

### 0.6 Contrato actual de Fling, Touch y Auto Farm

v143 no cambió las magnitudes físicas de v142. Estos valores se documentan para
evitar que un próximo agente «arregle» otra vez mediante extremos:

- Controller compartido: `src/libraries/Fling.lua`.
- Fling dirigido: pulso `180 + 50` y angular `140`.
- Touch: pulso `150 + 70` y angular `120`.
- Límite lineal común: `250`; las pruebas exigen valores reales por debajo de
  ese límite y prohíben volver a `10000`, `20000`, `9e7` o similares.
- Timing: PreSimulation aplica un pulso acotado y Heartbeat restaura el snapshot;
  no hay un writer de velocidad del humanoide objetivo ni una solicitud de
  network ownership en el controller actual.
- Fling dirigido hace **una** colocación de contacto por sesión, no `PivotTo`
  por tick. MM2 exige ronda activa, personaje local vivo y objetivo válido/vivo.
- Touch escucha partes directas del cuerpo con `CanTouch`, excluye handles de
  accesorios/tools y no teletransporta. Un contacto reciente (ventana de
  `0.25 s`, distancia máxima `14`) habilita temporalmente colisiones y Physics;
  el pulso está limitado a `1/30 s`. OFF, muerte, respawn y destroy restauran
  snapshots y conexiones.
- El listener de Touch puede estar activo sin contacto sin convertir todo el
  avatar en un collider permanente. La posesión de colisiones durante contacto
  está cubierta por `tools/test_fling_physics.py`.
- `activity.set("fling", currentSession ~= nil or touchEnabled)` sigue siendo
  la semántica actual. Se revisó como posible pista porque Noclip/Fly/Auto Win
  ceden mientras está activa, pero **no se modificó en v143** al no existir una
  reproducción que justificara otro cambio. No alterarla por intuición; medir
  primero si debe representar listener activo o posesión durante el pulso.
- Auto Farm cede constraints/writers al Fling compartido mediante
  `flingOwnsPhysics`. Walk usa `Humanoid:Move`; Below usa LinearVelocity +
  AlignOrientation, NoClip, root `4×8×4` y offset `3.0`, con velocidad 5–60.
- Muerte, lobby y fin de ronda son cleanup/guards, no una oportunidad para
  ejecutar acciones terminales. La secuencia de bolsa llena permanece limitada
  a bolsa realmente llena y a las condiciones de rol/ronda documentadas en §5.
- Noclip y Touch tienen una prueba de propiedad de colisiones; Fly y Auto Win
  tienen rutas de cesión. Esto es ownership offline, no evidencia de knockback
  aceptado por el servidor.

### 0.7 Prueba nueva y resultados exactos

`tools/test_startup_restore.py` genera un harness con el `src/Wurst.lua` y el
bundle reales, inyecta estados antiguos `true` y envuelve la inicialización de
secciones. Comprueba que:

- Noclip, una tarjeta restaurable ordinaria, no aparezca con su writer antes del
  gate y sí quede restaurado después.
- `Universal.AntiVoid.Antifling`, una subopción restaurable, siga el mismo orden.
- Auto Farm, Touch universal, Touch MM2 y Auto Fling no creen writers desde
  configs antiguas y terminen OFF.
- No haya sesión dirigida ni Touch activo al terminar ese boot hostil.
- Auto Farm, Touch y Auto Fling todavía se puedan activar/apagar manualmente y
  que sus claves de sesión permanezcan `false`.
- Heartbeat abra con la primera tarea, ejecute un delta de `0.25` en el mock y
  cierre con la última; RenderStepped tenga el mismo ownership independiente;
  `Destroy()` sea idempotente.

`tools/test_action_latency.py` se actualizó porque ya no existe el texto literal
`RunService.Heartbeat:Connect`: la conexión se realiza mediante `signal` en el
scheduler perezoso. El test sigue exigiendo la rama Heartbeat y la conexión del
TaskManager; **no se relajó el requisito de latencia**.

Validación ejecutada después de generar v143 con su stamp final:

```bash
python3 tools/build_bundle.py --stamp v143-20261026-boot-restore-lifecycle
bash tools/validate.sh
```

Resultados:

```text
bundle.lua current: 90 files, stamp v143-20261026-boot-restore-lifecycle
PASS 92 Lua sources compile
PASS 65 Python/Luau suites
[Wurst:Bootstrap] Load complete · failures=0
[HARNESS] done
core exports: 44 | prediction exports: 16
call sites checked: 109
PASS menu audit: 50 cards
PASS release menu: 49 cards, no Calibration card
```

También pasaron de forma focalizada `test_fling_physics.py`,
`test_mm2_auto_farm_dynamics.py`, `test_flight.py`, `test_delivery_branch.py`,
`test_disguise_toggles.py`, `test_freeze_movements.py` y
`test_mobile_buttons.py`.

Incidencias de proceso durante v143, para no interpretarlas como fallos live:

- Los wrappers de Luau habían desaparecido del workspace; se restauraron con
  `bash tools/luau/setup.sh` y volvió `0.739.0`.
- Una invocación manual de `test_mobile_buttons.py` omitió `LUAU`; se repitió
  con `LUAU=tools/luau/bin/luau` y pasó. No fue un fallo de código.
- La primera validación se detuvo en el assertion estático de Heartbeat descrito
  arriba; se actualizó para reconocer la implementación perezosa y se repitió la
  validación completa, no sólo ese test.

### 0.8 Límites de evidencia y aceptación live pendiente

Las suites demuestran estructura, orden, llamadas, guards, snapshots y cleanup
en mocks. **No demuestran** replicación, network ownership, knockback, daño,
kills, monedas, wins, aceptación del servidor, uso real de CPU ni FPS.

La captura histórica del usuario mostraba aproximadamente Physics `12,4 ms /
44 %`, Render `1,0 ms / 3 %`, Network receive `0,5 ms / 1 %` y unos 35 FPS. Es
una pista de una sesión, no un benchmark A/B de Lua ni una medición de v143.

Para aceptar v143 en vivo, usar la misma cuenta/config cuando sea posible y
anotar el watermark `UI Settings · v143`:

1. **Boot hostil:** inyectar con una configuración que antes tuviera Auto Farm,
   Touch o Auto Fling ON. Esperado: los cuatro estados de sesión permanecen OFF;
   no hay movimiento de farm ni Fling inesperado.
2. **Restauración normal:** comprobar que preferencias restaurables siguen
   apareciendo después del boot y que el menú termina de cargar sin errores.
3. **Touch manual:** activarlo explícitamente y caminar contra un objetivo vivo.
   Observar si existe contacto/knockback real y si OFF restaura movimiento y
   colisiones. No usar un mock como sustituto de esta observación.
4. **Auto Fling manual:** en MM2, con ronda activa y objetivo vivo; probar OFF,
   muerte local, muerte/cambio del objetivo y fin de ronda. Debe cancelar sin
   dejar otro writer activo.
5. **Auto Farm manual:** probar Walk y Below en ronda activa; pérdida de moneda,
   personaje muerto, lobby, fin de ronda y bolsa llena. Ninguna acción terminal
   debe ejecutarse en los estados prohibidos.
6. **Rendimiento A/B:** comparar v142/v143 en condiciones equivalentes, con el
   mismo conjunto de features y una captura de Timing. Reportar Physics/Render/
   Network y FPS antes/después; no atribuir una diferencia de servidor al
   scheduler sin medición.
7. **Cleanup:** revisar OFF, respawn y destroy. Si queda CanTouch/CanCollide,
   AutoRotate, Sit/Seated, LinearVelocity, AlignOrientation o conexiones con un
   dueño incorrecto, registrar el módulo y la secuencia exacta.

Mientras el usuario no confirme estas pruebas, el mensaje correcto es:
**«v143 corrige y valida offline el lifecycle; eficacia Touch/lag pendiente en
vivo»**, no «Touch y lag solucionados».

### 0.9 Mapa de archivos que importan para continuar

| Archivo | Por qué importa ahora |
| --- | --- |
| `src/Wurst.lua` | Stamp, rama, SectionManager, coordinador de restores, TaskManager y cleanup global. |
| `src/guis/Wurst/Code/Cards.lua` | Masters, `restore`, `restorePending`, activación manual y rollback de tarjetas. |
| `src/guis/Wurst/Code/Widgets.lua` | Subopciones, callbacks persistidos y controles `setChecked`. |
| `src/guis/Wurst/Code/SettingsPage.lua` | Profiles: debe seguir respetando acciones de sesión. |
| `src/libraries/Fling.lua` | Controller compartido, PreSimulation/Heartbeat, snapshots, pulsos y Touch. |
| `src/games/MM2/Blatant/Fling.lua` | Adaptador MM2, ronda/objetivo, Auto Fling y sincronización Touch. |
| `src/games/universal/Blatant/TouchFling.lua` | Tarjeta universal Touch y sincronización con MM2. |
| `src/games/MM2/Other/AutoFarm.lua` | Walk/Below, constraints, cesión a Fling, guards y cleanup. |
| `src/games/universal/Blatant/Noclip.lua` | Writer de colisiones que cede con activity Fling. |
| `src/games/universal/Blatant/Fly.lua` | Constraints/velocidad que ceden a Fling. |
| `src/games/MM2/Other/AutoWin.lua` | Otro writer que debe pausar/ceder sin competir con Fling. |
| `src/libraries/Manifest.lua` | Carga universal; debe coincidir con fallback y bundle. |
| `src/libraries/bundle.lua` | Artefacto generado; nunca editarlo como fuente independiente. |
| `tools/test_startup_restore.py` | Regresión de boot hostil, sesión y scheduler perezoso. |
| `tools/test_fling_physics.py` | Pulsos, contacto, muerte, Touch, Noclip y cleanup. |
| `tools/test_mm2_auto_farm_dynamics.py` | Cesión de Farm, constraints, rondas y acciones terminales. |
| `tools/test_action_latency.py` | Heartbeat y reacciones inmediatas sin borrar gates deliberados. |
| `tools/test_delivery_branch.py` | Entrada, recovery y rama de entrega. |
| `RESUME.md` | Este handoff; actualizarlo cuando cambien decisiones o estado live. |

### 0.10 Recuperación de un `HEAD` histórico sin perder el workspace

En esta actualización volvió a ocurrir lo siguiente: `HEAD` aparecía en
`636e7ab` (v139), mientras los archivos visibles eran el trabajo posterior y el
remoto estaba en `5b4ad20`. Git mostraba 33 rutas modificadas, borradas o no
rastreadas. No era evidencia de que hubiera que descartarlas.

Procedimiento seguro aplicado:

1. `git ls-remote --heads origin arena/2fb9a46a-arandommenu` y `git fetch` para
   identificar el tip real.
2. Leer `git status --porcelain=v1 -z` y comparar cada ruta visible contra
   `FETCH_HEAD:<path>`; para borrados, comprobar que tampoco existan en el tip.
3. Los **33 archivos coincidieron byte por byte** con `5b4ad20`.
4. Sólo entonces se ejecutó `git reset --mixed FETCH_HEAD`, que movió HEAD/index
   sin reescribir el contenido. El árbol quedó limpio y no se perdió trabajo.

Notas críticas:

- `git diff --quiet FETCH_HEAD` no basta cuando hay archivos no rastreados que
  sí existen en el commit remoto; puede describirlos como ausentes.
- Una comparación que reporta **0 archivos examinados no prueba igualdad**. Una
  primera invocación del script de comparación omitió `--` en
  `git status --porcelain=v1 -z`; se corrigió y se repitió antes del reset.
- No usar `reset --hard`, `clean`, checkout de archivos ni borrado de no
  rastreados como primera reacción. Si cualquier contenido difiere, conservar y
  reconciliar ese archivo primero.
- No repetir el antiguo método de reconstruir commits desde un árbol mezclado si
  el remoto ya contiene exactamente el trabajo; la comparación + reset mixed es
  más simple y segura en ese caso concreto.

### 0.11 Qué debe hacer el próximo agente

1. Leer esta sección y ejecutar `git status --short --branch`, `git log -3` y
   `git ls-remote` si hay cualquier duda de alineación.
2. Confirmar que el runtime que investiga tiene stamp v143; no mezclar logs o
   fixtures de v141/v142 con conclusiones de v143.
3. Si el usuario reporta Touch/lag, pedir la secuencia exacta y evidencia live de
   §0.8. No volver automáticamente a pulsos grandes, CFrames por tick, ownership
   requests o writers paralelos.
4. Revisar ownership y orden antes de tocar magnitudes. Si la pista es
   `activity("fling")`, construir primero una prueba que distinga listener idle
   de posesión durante contacto.
5. Mantener las cuatro acciones de sesión fuera de boot/profile salvo que el
   usuario pida explícitamente cambiar esa decisión.
6. No añadir otra tarjeta para Auto Farm/Auto Fling/Touch ni duplicar un writer
   para «probar» una idea.
7. Para cambios runtime: editar sólo `src`, añadir/actualizar pruebas, subir
   stamp, regenerar bundle con ese mismo stamp, ejecutar `bash tools/validate.sh`
   y hacer commit/push normal en la rama activa.
8. Para cambios sólo de documentación: no hace falta modificar stamp/bundle;
   revisar el diff, actualizar los datos afectados y publicar sólo el documento.
9. Actualizar esta sección con el resultado live del usuario. Una suite verde no
   cierra una aceptación live, y una sospecha live no autoriza a falsear mocks.

### 0.12 Restricciones que siguen vigentes

- `TestingStuff` es evidencia pública de **solo lectura**. No subir código,
  credenciales, tokens ni configs; no copiar implementaciones y no mezclar datos
  de builds distintos. Los logs revisados no aportaron evidencia específica de
  Fling, CPU o Timing que demostrara la causa.
- No relajar tests para admitir velocidades extremas. Corregir la implementación,
  no el requisito. La actualización de `test_action_latency.py` cambió cómo se
  reconoce la conexión, no el comportamiento exigido.
- No presentar v141 como solución: el usuario reportó lag y Touch sin funcionar.
  v142 y v143 tienen validación offline, pero eso no sustituye su veredicto.
- No interpretar una petición de forma tan literal que produzca código basura
  cuando el mecanismo sea imposible o no esté probado. Explicar el límite y
  proponer evidencia útil.
- No afirmar eficacia de red, daño, kills, monedas, wins o mejoras de CPU desde
  mocks. No inventar remotes, argumentos, resultados ni telemetría.
- Respetar Roblox/Wurst, conservar LF, no instalar otro bundler y no editar
  `src/libraries/bundle.lua` manualmente.

### 0.13 Fuentes externas consultadas y qué permiten concluir

Estas referencias se usaron como lectura/evidencia, no como fuentes para copiar
implementaciones ni como sustituto de una sesión live:

- `https://github.com/XzAngel19/ARandomMenu/tree/arena/9492e6b6-arandommenu`:
  rama base histórica de lectura. Primero mostró `636e7ab` (v139) y después
  `10c2a8b` (v140). El trabajo y los pushes de esta sesión pertenecen siempre a
  `arena/2fb9a46a-arandommenu`; no publicar en la rama histórica.
- `https://github.com/XzAngel19/ARandomMenu/blob/8b8fe4d1ba6af4e89795920aaab1e08511910fa7/src/games/MM2/Blatant/Fling.lua`:
  implementación histórica consultada. No es una base segura para restaurar:
  también contiene potencias extremas, CFrames de contacto y solicitudes de
  network ownership que el controller actual evita.
- `https://github.com/XzAngel19/TestingStuff` (`main`, mediante GitHub API):
  evidencia pública de solo lectura. Se revisaron el tree y los logs
  `2026-10-24T05_32_41Z.log` y `2026-10-24T16_49_55Z.log`; no apareció evidencia
  específica de Fling, CPU o Timing que probara la causa del problema. La
  Contents API devolvió vacío para un log grande y el Git Blob por SHA sí
  entregó contenido; ese detalle es de acceso, no una prueba de gameplay.
- Los datos de calibración y logs deben permanecer asociados a su `buildStamp`.
  No promediar v141/v142/v143, no subir parches o credenciales a TestingStuff y
  no convertir una ausencia de logs en evidencia de que una función no se usó.

---

## 1. Qué es esto y cómo llega al usuario

- Menú "Wurst" para Roblox, foco principal **MM2** (place id `142823291`).
  También hay módulos universales y de otros juegos (BedFight, TRS, VD y
  X2Duels/MVS).
- El loader carga el **bundle**: `getgenv().WURST_BRANCH = "arena/2fb9a46a-arandommenu"`.
- **Protocolo de publicación de runtime (obligatorio):**
  1. Edita en `src/…`, nunca directamente en `src/libraries/bundle.lua`.
  2. Sube `SOURCE_STAMP` en `src/Wurst.lua` (`vNNN-AAAAMMDD-descripcion`).
  3. `python3 tools/build_bundle.py --stamp <el mismo stamp>`
  4. `bash tools/validate.sh` — debe terminar VERDE. En v143 son 92 fuentes,
     65 suites, boot `failures=0`, auditoría de menú 50/49 tarjetas y 109 call
     sites; si el inventario cambia, actualiza también los contratos.
  5. Commit + push **normales** a `arena/2fb9a46a-arandommenu`. Sin force-push,
     sin reescribir historia, sin trabajar en otra rama.
- Sin bundle regenerado + stamp, un cambio de runtime **no llega al usuario**.
  Un commit exclusivamente documental no necesita stamp ni bundle nuevo, pero
  sí revisar el diff y publicar en la misma rama activa. El watermark
  "UI Settings · vNNN" en el menú es como el usuario verifica la versión.

## 1A. X2Duels (MVS): estructura MM2, evidencia y contratos

- PlaceIds registrados: `92876937625630` y el MVS anterior `135856908115931`.
  Fuentes activas: `Rules.lua`, `base.lua`, `Other/AutoFarm.lua` y sus dos
  perfiles. La sección de menú existente se llama `MVSD`; `Render/TeamESP.lua`
  fue eliminado y no debe volver como módulo independiente.
- Hay exactamente cinco tarjetas X2: **Auto Farm** y **Auto Win** en
  **Utilities**, **Silent AIM**, **Kill Aura** en Combat y **Hitbox** en
  Exploits. El único TriggerBot es el universal, adaptado al core X2 para
  Gun/Knife; no se debe crear otra tarjeta.
- Silent AIM contiene las secciones Gun y Knife. Auto Shoot sigue el master y
  muestra Legit/Silent. Knife Throw es una subopción de Silent AIM: intenta la
  activación nativa en cada tick, sin slider ni temporizador de intervalo;
  solo espera el windup de la propia animación. Desktop usa mouse2 + Activate;
  touch usa y restaura ForceThrow. No se inventan argumentos de ThrowEvent.
- La keybind de Silent AIM se registra con `state.bindFeatureActivationKey` y
  ejecuta la acción nativa solamente con `Sender = Button`; nunca cambia el
  toggle maestro. Con `Sender = CFrame`, Auto Shoot/native activation funciona
  sin esperar ese botón. La activación comparte ancestry del objetivo, Team
  Check, Wall Check y raycast antes de disparar.
- Auto Win es únicamente una tarjeta de estado de sesión: `Wins`, `Time Played`,
  `Kills` y `Loses`. No tiene ráfagas, selección automática de combate, límite
  de cinco victorias, Play Again, clicks GUI ni `RematchTeleport`. Las wins
  provienen de resultados/notificaciones locales explícitos; kills usan el
  tercer Player observado en `Combat/DestroyBody`; las muertes locales se
  deduplican por ronda para Loses. Son contadores cliente observados, no una
  garantía de autoridad del servidor.
- Auto Farm busca monedas Halloween `PumpkinCurrency_*` y `Farms/PumpCoins`
  dinámicos por contacto nativo. Los podios resuelven `StringValue`/`ObjectValue`
  contra jugadores y equipos; sin una entrada enemiga no se farmean granjas y
  ningún modelo cercano se considera propio por proximidad. El teleport usa el
  CFrame de la moneda invisible con TouchTransmitter, no el root del dueño.
  Reintenta y restaura el CFrame al apagarse. Un intento no se cuenta como
  moneda confirmada. El RBXL guarda algunas partes con `CanTouch=false`; la
  recolección real sigue pendiente y no se inventan argumentos para
  `CollectEventSpawnable`.
- Team Check falla cerrado: usa los atributos MVS `Team`/`Game`, rechaza FFA,
  lobby y lados desconocidos como objetivos y no cae al `Team` común de Roblox.
  El mismo resolver alimenta combate y RoleColors del ESP universal
  (PlayerESP/Chams/Nametags): enemigo rojo, aliado verde y desconocido ámbar.
  Unknown sigue fail-closed para combate con Team Check activo; desactivarlo
  debe ser explícito. No convertir una pantalla ambigua en una victoria.
- El log `2026-10-24T16_49_55Z.log` de TestingStuff capturó `DefaultGun` (`fire`
  sin argumentos y `showBeam` con dos Vector3 + Handle), llamadas nativas de
  `DefaultKnife`, `PlayerRespawned` y `SetDead`. La réplica de Beam/PlaySound no
  demuestra daño ni kills. No se inventan argumentos ni se reintroducen
  GUID/remotes históricos; la activación sigue siendo la ruta nativa del Tool.
  El extractor independiente `tools/X2DuelsDecompiler.luau` vuelca fuentes,
  bytecode, inventario con parents y argumentos entrantes/salientes; su guía es
  `tools/X2DuelsDecompiler.md`.
- `python3 tools/test_x2duels.py` ejecuta 67 reglas, contratos y un boot real
  del bundle con cinco tarjetas, keybind de acción sin toggle, CFrame sin
  botón, ambos caminos nativos del cuchillo, estadísticas deduplicadas,
  contacto/restauración de pumpkin, podios y granjas amigas/enemigas con
  PumpCoins invisibles y cleanup. `python3 tools/test_x2duels_decompiler.py`
  valida el extractor con DataModel simulado. Todo ello es validación offline,
  no aceptación del servidor ni precisión live.

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
| **Utilities** | Automatizaciones y datos útiles que no son el control directo de un ataque o del cuerpo. | Auto Farm, Auto Win de solo estado, Auto Get Gun, Auto Unbox y ayudas de farmeo. | Hitbox, una expansión de colisiones o un módulo puesto ahí solo porque «es fuerte». |
| **Exploits** | Cambiar una propiedad o aprovechar directamente una mecánica explotable del juego. | Hitbox y manipulaciones equivalentes que tengan una razón técnica clara. | Auto Farm/Auto Win por costumbre, o cualquier tarjeta que no se pueda explicar técnicamente. |
| **Render** | Mostrar información sin decidir el combate. | PlayerESP, Chams, Nametags, HP, Arrows, Coin ESP. | Un TeamESP paralelo con otra resolución de equipos. |
| **Movement/Blatant** | Movimiento, desplazamiento o acciones físicas directas. | Speed, Fly, Teleport, Fling cuando corresponda al juego. | Estadísticas de farm o lógica de proyectiles. |

La distinción importante es **proyectil/distancia frente a melee**, no el nombre
del arma. Un cuchillo que se lanza pertenece a Silent AIM; el mismo cuchillo
cuando hace un swing cercano pertenece a Kill Aura. Si una herramienta tiene
ambos ataques, comparte el descubrimiento/equipado del Tool, pero separa las
dos rutas y sus opciones. No se duplican tarjetas ni se crean dos loops que
equipan y activan el mismo arma a la vez.

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
revisar también el inventario vigente (50/49 en v143) y cualquier contrato de menú;
si sólo se añade una opción, la prueba debe impedir que aparezca una tarjeta
extra. La salida final sigue siendo `bash tools/validate.sh` con boot limpio.

### 4. Cómo se crea una tarjeta y sus opciones

La API común es `createUniversalFeature` con `parent`, `registry` y
`categoryName`. Las opciones se añaden con los widgets compartidos:
`addSectionOption`, `addToggleOption`, `addNumberOption`, `addCycleOption`,
`addActionOption` e `addInformationOption`. `SetStatus` es para estado corto y
actualizable; no sustituye una explicación de seguridad ni un contador que no
existe.

- Una familia de ataques tiene **una tarjeta principal** y secciones por arma o
  mecánica. Por ejemplo, Silent AIM puede contener `Gun` y `Knife`; no hace
  falta una tarjeta `Knife Throw` separada si ambas comparten objetivo y
  sender.
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
- Un sender `Button` espera la acción del botón/tecla. Un sender `CFrame` debe
  poder trabajar por su ruta automática sin esperar ese botón. Esta diferencia
  se prueba tanto en desktop como en touch, sin inyectar clicks para simular
  combate si existe una activación nativa.
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
  ejemplo, mouse2 frente a un atributo como ForceThrow); ambas deben restaurar
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

**Estado actual frente a regla de diseño:** X2 v119 intenta Knife Throw en cada
tick y no expone un slider; si se añade el control de delay descrito aquí, debe
llamarse Cooldown y empezar en 0. Los delays documentados en MM2 son rutas
históricas/medidas de ese juego, no una autorización para reintroducir un
`Throw interval` genérico. Esta distinción queda escrita para que el próximo
cambio no confunda documentación con una funcionalidad ya implementada.

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
a la sección del proyectil dentro de Silent AIM.

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

**Estado actual:** X2 v119 ya tiene en Auto Win `Wins`, `Time Played`, `Kills`
y `Loses`; Auto Farm todavía reporta principalmente su estado de búsqueda y
contacto. Por tanto, `Coins collected`, `Time spent` y demás campos anteriores
son el contrato para completar/compartir el farm, no una afirmación de que ya
estén implementados en X2. No se debe escribir en una prueba o en el status
«collected» hasta tener una confirmación real.

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
4. **Silent AIM:** todos los ataques a distancia/proyectiles están bajo su
   tarjeta, con secciones por arma y sus propias opciones; la keybind de acción
   no cambia el toggle maestro.
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
   Sprint, si Silent AIM OFF cancela Auto Shoot, y si se conserva la preferencia
   al volver a activar. «Independiente» debe significar independencia real, no
   dos funciones modificando lo mismo sin coordinación.
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
| **Auto Shoot / Gun Throw / Knife Throw** | Secciones del arma dentro de **Silent AIM**. | Comparten target, Team/Wall Check y sender. La activación puede ser llamada por otra utilidad, pero no se duplica el solver. |
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

- El suelo físico es **un frame** (Heartbeat ≈ 16.7 ms a 60 FPS) + ping. Los
  `TaskManager:Connect` normales corren por Heartbeat y los de fase `render` por
  RenderStepped; desde v143 sus señales se abren/cierran con el bucket. Los binds
  disparan en el evento.
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

Estas entradas permanecen pendientes hasta que exista evidencia live explícita.
La validación offline actual tiene 65 suites y boot limpio; los items históricos
deben reevaluarse contra el módulo vigente, no asumir que una versión citada es
la implementación actual:

- **v143 lifecycle:** boot con configs antiguas, restauración después de todas
  las secciones, ausencia de movimiento accidental y A/B de Timing/FPS. El
  scheduler perezoso está probado estructuralmente, no medido en una partida.
- **Touch v142–v143:** contacto y knockback reales al activarlo manualmente,
  comportamiento con Noclip/Fly, OFF/respawn y restauración de snapshots. El
  usuario ya rechazó v141 como solución; v143 todavía necesita su veredicto.
- **Auto Farm v143:** activación exclusivamente manual, Walk/Below en ronda,
  roaming sin monedas, void guard, retorno/cleanup y acciones de bolsa llena
  sólo bajo sus guards. Comprobar también la recogida real de gun/monedas, que
  los mocks no pueden acreditar.
- **Fling/Auto Fling actuales:** pulsos compartidos sin requests de network
  ownership, una colocación dirigida por sesión y cancelación por OFF/muerte/
  ronda. Anti Fling debe probarse contra un fling real por separado.
- Shoot v106–v112: si con el muzzle real desaparecen los impactos en geometría
  del mapa (`Smooth Block Model`), y si el gate de 1.5 s recupera los ecos.
- La sesión limpia que falta: bot en el suelo de verdad (Difícil/Auto/Saltos
  Normal/Sin extras), 15–20 confirmados por modo (Prediction, Silent Front,
  Silent Through). Sin eso, no se retoca el predictor.
- Disguise v101: packs del objetivo / por ID, en servidor.
- Salidas del standalone (Step 1 nil-parent, Step 4 origen) y TargetBot v5.
- X2 v119: comprobar en vivo Gun/Knife, precisión del throw, el ESP universal
  con TeamRed/TeamBlue y FFA, la keybind Button y Sender CFrame en móvil, y la
  actualización de Wins/Time Played/Kills/Loses. El harness cubre activaciones,
  estados, colores, contadores y contactos; no prueba daño, monedas ni
  aceptación del servidor. La siguiente evidencia debe obtenerse con
  `tools/X2DuelsDecompiler.luau`.

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
- Cambios de runtime pequeños y versionados (bump de stamp), con test que fije
  el comportamiento y `validate.sh` verde antes de pushear. Los cambios sólo
  documentales no requieren stamp, pero sí actualizar este handoff con precisión.

---
*Última actualización: 2026-10-26 · runtime v143, restauración transaccional,
acciones físicas de sesión, TaskManager perezoso, forense v138–v143, validación,
recuperación del workspace y protocolo live documentados. Al publicar una
versión nueva o recibir aceptación live, actualiza la línea de estado y todas
las secciones afectadas.*
