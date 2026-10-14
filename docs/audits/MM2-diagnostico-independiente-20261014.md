# Wurst / MM2: diagnóstico independiente después de v16

**Fecha:** 14 de octubre de 2026, UTC.

**Trabajo de esta sesión:** `arena/d83a806d-arandommenu`.

**Alcance original de este informe:** estudio y reproducciones de v16, sin modificar su runtime ni ejecutar Roblox. La auditoría se publicó después en el PR #39.

> **Actualización posterior:** esta misma rama incorpora ahora una implementación v17 y el baseline v16. Consulta [la guía de cambios, loader y pruebas](../MM2-v17-guia.md). Las conclusiones de este informe describen las revisiones históricas fijadas; `audit_mm2_remaining.py` reproduce sus defectos, no verifica el runtime v17.

## Conclusión

No es correcto reducir el problema a «quitamos Hitboxes y Burst y por eso todo dejó de funcionar». Hubo regresiones adicionales, varias ya reparadas en la segunda rama, y **siguen existiendo defectos de integración y medición en v16**.

Los candidatos más concretos para «Knife no acciona» son el estado incoherente del interruptor principal y las subopciones, la colisión de los dos rangos guardados y los rechazos sin diagnóstico. Para Shoot quedan problemas de correlación de confirmaciones, dependencia del muestreo y controles que permiten configuraciones que nunca dispararán. No puedo atribuir tu sesión concreta a uno de ellos sin sus ajustes/logs, pero sí pude reproducir varios en el código original.

**No recomiendo restaurar toda v11, reintroducir hitboxes/burst ni subir todo a 120 Hz como solución.** Primero hay que estabilizar activación/configuración y medir qué intentos realmente se envían y confirman.

## 1. Qué versiones se estudiaron realmente

| Referencia | Sello del loader | Significado |
|---|---|---|
| `fa5a0f6` | `v9-20261013-0030` | Cambio de CanTouch y Motion Hz |
| `66d7152` | `v10-20261013-0130` | Base histórica mencionada; RTT/2 de Knife y Through |
| `7385fcd` | `v11-20261013-2130` | Añade animación de Knife y Throw Hz |
| `076e166` | `v12-20261013-2355` | Quita hitboxes/burst y revierte más lógica |
| `bfba7cc` | `v13-20261014-0115` | Recuperación parcial de Shoot |
| `17c15f3` | `v14-20261014-0230` | Punta consultada de `arena/2daf1a78-arandommenu` |
| `0aec767` | `v15-20261014-mm2-precision` | Reparación de predicción, temporización y guardado |
| `2c7ab1a` | `v16-20261014-mm2-visuals-telemetry` | Punta consultada de `arena/f208cfd3-arandommenu` |

La etiqueta v11 **no corresponde a `66d7152`**: corresponde a `7385fcd`. No es una crítica al recuerdo de la versión; importa para que la comparación sea reproducible.

El loader pegado en la consulta apunta a **`arena/2daf1a78-arandommenu`, es decir, v14 en el momento de esta revisión**. No incorpora automáticamente los cambios de v15/v16 que están en la otra rama.

Leí los snapshots mediante Git, sin cambiar el checkout de esta sesión. La base local de esta sesión procede de `main` y todavía tiene la arquitectura anterior, no el runtime Wurst de esas ramas. Este informe no instala una versión nueva del menú.

Referencias: [historial v10→v14](https://github.com/XzAngel19/ARandomMenu/compare/66d7152796ecb4562a8e4aa50f983fee7d6d7c60...17c15f3ff802d0d2e036dbd18a6204d09169517f), [v16 fijada](https://github.com/XzAngel19/ARandomMenu/tree/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77).

## 2. TestingStuff: qué contiene y qué permite concluir

Revisión fijada: [`239c20f21fea1b6e23811fd4c908d6fbcae657ab`](https://github.com/XzAngel19/TestingStuff/tree/239c20f21fea1b6e23811fd4c908d6fbcae657ab). Inspeccioné los ocho archivos, separando MM2 de los otros PlaceId.

| Archivo | Resultado de la inspección |
|---|---|
| `MM2_Trajectory_Calibration.json` | Schema 3; 206 eventos detallados; contadores históricos contaminados |
| `Place_142823291_Game_Learning.json` | Logger antiguo de MM2, schema 1; no es un medidor fiable de impactos |
| `Place_135856908115931_Game_Learning.json` | Otro PlaceId; sin disparos detallados; no valida MM2 |
| `Place_92876937625630_Game_Learning.json` | Otro juego; no transferir sus supuestos de daño a MM2 |
| MM2 `.rbxl` del 5 de octubre | 29.021 instancias; 292 Source: 270 errores de descompilación, 21 de bytecode y un texto de exportación |
| DUELS `.rbxl` del 11 de octubre | 39.906 instancias; 919 Source, dominados por errores del exportador; no es MM2 |
| `message.txt` | Código de YARHM 1.21, no documentación oficial ni implementación del servidor |
| `place, source.rbxlx` | Exportación útil: 303 propiedades Source; permite estudiar servicios/visuales del cliente |

### Exportación XML

De las 303 fuentes, 285 son candidatas con código, 15 indican falta de código de servidor, dos fallaron al descompilar y una es el README del exportador. Compilé las 303 propiedades sin ejecutarlas: dos fuentes candidatas fallan por instrucciones `goto` reconstruidas por el descompilador:

- `StarterGui/BackpackUI/BackpackScript`.
- `StarterPlayer/StarterCharacterScripts/Animate`.

Las otras **283 candidatas compilan**. Los comentarios vacíos de código también compilan, pero eso no los convierte en implementaciones recuperadas. Los errores de la exportación **no demuestran que esos errores estén en el juego original**.

`ServerScriptService` y `ServerStorage` están vacíos. Los únicos Tool del XML son `Emotes` y `AAAAA`, no los controladores completos Gun/Knife equipados. Por tanto, faltan pruebas directas de las condiciones actuales de aceptación/cooldown de las armas en servidor.

### Contratos útiles que sí aparecen

- `ReplicatedStorage/ClientServices/WeaponService`: `GunFired` es un RemoteEvent; **su `KnifeThrown` es un BindableEvent local**, diferente de `Tool.Events.KnifeThrown`.
- `GetTargetPosition`/`GetMouseTargetCFrame`: selección del cursor mediante rayos de 300 studs, excluyendo personaje local, tags `WeaponPassthrough` y partes totalmente transparentes. Ese alcance del cursor no demuestra el alcance autoritativo del servidor.
- `StarterPlayer/StarterPlayerScripts/WeaponVisuals/GunBeams/CreateBeam`: dibuja usando arma, origen, endpoint y parte opcional. Ver un beam no equivale a producir daño.
- `ThrowingKnifeVisuals`: usa tag `ThrowingKnife`, `HandleLink`, `BladePosition`, `Direction` y `ThrowSpeed`, con fallback 96 studs/s. **La calibración puede estar midiendo ese visual**, pues el observador prefiere `KnifeVisual`.
- `message.txt`, líneas 6110–6189: referencia histórica a `Knife.Events.KnifeThrown:FireServer(CFrame, CFrame)` y loop de 1,5 s. Ayuda a entender la intención del módulo, pero no certifica el protocolo actual ni obliga a usar 1,5 s.

No hace falta inventar acceso al servidor para corregir bugs locales. Tampoco hay que tratar los comentarios optimistas de otro script como si fueran una especificación autoritativa.

## 3. Qué se rompió al quitar Hitboxes/Burst

Reejecuté la auditoría histórica incluida en la segunda rama, en lugar de aceptar sus conclusiones sin probarlas.

### Regresiones verificadas de v12 que llegan a v14

1. **Silent spawn inicial cambió de Through a Front.** v13 recuperó la geometría Through, pero no su default.
2. **Knife perdió el término RTT/2.** A 16 studs/s y RTT de 200 ms, el término retirado equivale a 1,6 studs de movimiento no compensado.
3. **Throw Hz quedó sin efecto:** v14 muestra la opción, pero comprueba a 30 Hz fijos.
4. Al retirar hitbox también se retiró un ensanchamiento del **presupuesto local de error**. Para tamaño 8 pasaba de 4/7 studs Normal/Silent a 1/1,75; puede haber menos envíos aunque la pieza local no ayudase a impactar.

La fórmula central de Shoot Normal con **Hitbox OFF y Burst 1** se conserva de v10 a v14 en los casos reproducidos. Tampoco hay cambio de Shoot, core, Aura o GameLearning entre v10 y v11: son byte-idénticos en ese salto.

Burst era 1 por defecto; quitarlo solo elimina paquetes extra si el usuario lo había aumentado. No hay aquí prueba de aceptación de cada paquete adicional por el servidor.

La antigua implementación creaba una pieza local. El comentario que decía que parentarla al personaje ajeno la replicaba al servidor **no está respaldado por el código**. `CanTouch=true` tampoco demuestra daño autoritativo. No restauraría esta función basándome en ese comentario.

### Reparaciones que v15/v16 sí contienen

- Recuperación de Through como default y de RTT/2 en Knife.
- Intercepción de velocidad constante para Knife, no una sola estimación distancia/velocidad.
- Throw Hz conectado, sobrante temporal conservado y sin ráfagas de recuperación tras tirones.
- Corrección del alcance léxico del controlador de calibración de Shoot.
- Animación después del envío, identificada por nombre throw y con limpieza.
- Validación de terceros de Silent incluso con sweep cero y revalidación del segmento alternativo.
- Visibilidad con filtros nativos en Normal; muestreo continuo de un objetivo en vez de todos.
- Guardado sin reimportar y sumar otra vez contadores acumulados; autosave a 10 s.
- v16 separa sesiones y protege el historial con backup; mejora las etiquetas de evidencia de GameLearning.

No conviene borrar estas reparaciones para regresar indiscriminadamente a v11.

## 4. Defectos todavía presentes en Knife v16

### 4.1 Interruptor principal y subopciones desincronizados — reproducido

**Código:** [KnifeAura, 202–228](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/Blatant/KnifeAura.lua#L202-L228), [KnifeThrow, 245–299](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/Blatant/KnifeThrow.lua#L245-L299), [Widgets, 232–312](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/guis/Wurst/Code/Widgets.lua#L232-L312).

- Encender `Knife` por sí solo no activa Aura ni Throw.
- Apagarlo detiene los dos controladores, **sin actualizar las casillas internas ni sus valores guardados**.
- Encenderlo de nuevo no los restaura. La casilla Throw puede seguir marcada, pero el controlador ya no existe.
- La subopción también puede arrancar Throw con el principal apagado, porque su callback no consulta el estado principal.

Ejecuté **ambos módulos completos** con servicios/widgets simulados y reproduje esa secuencia. Es un problema local real compatible con «está encendido pero no hace nada», no una hipótesis de latencia.

**Solución a diseñar:** un estado único con `masterEnabled`, `auraWanted` y `throwWanted`; ejecución efectiva derivada de esos valores, UI sincronizada y restauración explícita.

### 4.2 Aura Range y Throw Range colisionan al guardar — reproducido

Ambos llaman a `addNumberOption(..., "Range", ...)` sobre la misma tarjeta `MM2.Knife`. Widgets genera la clave con tarjeta + etiqueta: **`MM2.Knife.Range`**.

Son opciones distintas, con defaults 14 y 120, pero comparten almacenamiento. Si se guarda Aura Range = 14, después de recargar Throw puede heredar 14. Si se guarda Throw Range = 120, Aura puede heredar 120.

**No se sincronizan entre sí inmediatamente:** el efecto principal aparece al restaurar el perfil. Además, el widget no limita los valores cargados al intervalo, por lo que el segundo caso puede dejar Aura fuera de su rango anunciado de 7–30.

Referencias: [Aura 229–233](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/Blatant/KnifeAura.lua#L229-L233), [Throw 314–324](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/Blatant/KnifeThrow.lua#L314-L324), [clave numérica](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/guis/Wurst/Code/Widgets.lua#L410-L429).

### 4.3 El control numérico deja saltarse los límites — reproducido

`quantize` devuelve el número sin limitarlo si no viene del slider. La escritura manual y la carga del perfil usan justamente esa ruta. La prueba con el código real del widget acepta `Fire delay=-1` y un valor cargado `999`.

Knife copia ese valor directamente. Un delay negativo puede convertir el intento en uno por cada comprobación disponible, aunque el servidor rechace la mayoría. Un rango negativo puede dejarlo sin objetivos. Es también un candidato de carga innecesaria si hay configuraciones anómalas, **no una afirmación de que tu perfil las tenga**.

Referencia: [Widgets 580–668](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/guis/Wurst/Code/Widgets.lua#L580-L668).

### 4.4 Rechazos silenciosos y predicción todavía limitada

Throw retorna sin explicar el motivo cuando falta rol, herramienta, remoto, parte de origen, objetivo válido, trayectoria visible o intercepción. Aura exige arma equipada; Throw sí intenta equiparla. Si un callback falla, el TaskManager solo registra un número de tarea y puede desconectarlo después de tres fallos consecutivos; la tarjeta no necesariamente refleja esa desconexión.

La mejora de intercepción sigue asumiendo **velocidad constante del objetivo, incluida Y**. No modela su salto completo, aterrizaje, escalones ni cambios de dirección. Por ejemplo, un blanco a 96 studs implica alrededor de un segundo de vuelo en un caso simple: extrapolar un segundo la velocidad vertical instantánea no reproduce un salto con gravedad. Esto es una limitación del modelo, no una medición de fallos reales.

En Normal se elige primero el objetivo más cercano visible en su posición actual; si después su punto predicho queda bloqueado o no tiene solución, retorna sin probar el siguiente candidato. v16 evita parte del bloqueo por objetivos ocultos, pero no todos los casos de selección fallida.

La velocidad 96 es un fallback defendible con la evidencia disponible. No hay base para prometer que aumentar velocidad, offset o frecuencia arreglará esas limitaciones.

## 5. Shoot / SilentAIM: problemas que quedan en v16

### 5.1 La correlación puede asignar una confirmación al disparo equivocado — reproducido

[Core 2525–2604](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/base.lua#L2525-L2604) recorre los pendientes **del más reciente al más antiguo**. Si coincide la Tool, no exige que coincidan origen o dirección.

Reproducción: intento A a t=0, B con la misma arma a t=0,2; llega a t=0,3 una señal con el origen de A. El código confirma **B**, incluso poniendo su origen a 100 studs del origen de la señal. Registra unos 100 ms, no los 300 ms que corresponderían al escenario A.

Ese valor entra en `freshGunLatency`. Por tanto, el problema no solo ensucia un log: **puede alimentar el horizonte adaptativo**. Es relevante cuando hay intentos solapados, latencia o cooldowns que rechazan algunos envíos. No prueba que cada señal de tus sesiones haya sido emparejada mal.

El observador de feedback de UI, además, conserva un único `pending`, reemplazado en cada envío. Knife también busca pendientes recientes por handle, sin un identificador autoritativo emitido por el servidor.

### 5.2 El tratamiento del giro depende de la frecuencia — reproducido

`stability` se calcula como el producto escalar entre dos direcciones consecutivas; `getGunTurnRate` usa `(1-stability)*6` **sin dividir por el tiempo entre muestras**.

Con el mismo giro físico de 180°/s y velocidad de 16 studs/s, ejecutando las funciones originales:

| Muestreo | Valor calculado de turn rate |
|---|---:|
| 20 Hz | 0,073870 |
| 60 Hz | 0,008223 |
| 120 Hz | 0,002056 |

Son intervalos sintéticos controlados, no la frecuencia de replicación medida de Roblox. Demuestran que subir Motion Hz cambia el significado del indicador, no solamente la rapidez de reacción. Dado que se usa para descuento de lead y error, faltan pruebas de invariancia temporal y de datos repetidos/actualizados a saltos.

Referencias: [movimiento 1342–1404](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/base.lua#L1342-L1404), [turn rate 1499–1517](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/base.lua#L1499-L1517).

### 5.3 Hay dos controles de Silent distintos — reproducido

`Shoot.SilentAIM` afecta el disparo manual. Auto Shoot pasa expresamente `silent = autoSettings.mode == "Silent"`, sobrescribiendo ese ajuste. **Shoot SilentAIM ON + Auto Shoot Mode Normal sigue enviando Normal.** No es necesariamente un bug del algoritmo, pero sí una fuente importante de confusión al probarlo.

Referencia: [Shoot 357–365 y 569–586](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/Blatant/Shoot.lua#L357-L365).

### 5.4 Max error permite valores que bloquean absolutamente todo

El solver nunca reporta menos de **0,35 studs**, pero el control ofrece **0,1–1**. Cualquier valor efectivo inferior a 0,35 rechaza todos los resultados, incluso un objetivo inmóvil y perfectamente visible. Por defecto es 0,6, así que no afecta a todo el mundo.

También hay dos filtros: presupuesto del solver de 1 Normal / 1,75 Silent y el filtro adicional de Auto Shoot. Que Manual dispare y Auto espere puede ser ese diseño, no fallo del remoto.

Referencia: [Shoot 74–76, 184–194 y 431–435](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/Blatant/Shoot.lua#L184-L194).

### 5.5 La calibración nueva cambia el comportamiento aunque Auto tune lead esté OFF

Son mecanismos distintos:

- `Auto tune lead` controla la corrección aprendida a partir de impactos directos.
- `getGunHorizonSeconds` consume por su cuenta una mediana de aceptación con al menos seis muestras nuevas, ventana de 60 s, ajuste acotado a ±75 ms del baseline.

La segunda ruta no consulta el toggle de Auto tune lead. Esto ya está descrito en el informe previo, pero importa en una comparación contra v10, cuyo fallo léxico impedía usar ese controlador. La demora hasta observar `GunFired` tampoco identifica por sí sola el instante exacto de colisión del servidor.

Además persisten un suelo de RTT de 200 ms para el baseline y un estimador limitado a 300 ms antes de construir el horizonte. Son heurísticas conservadas, **no constantes demostradas óptimas para cada red**.

Referencia: [core 1408–1496](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/base.lua#L1408-L1496).

### 5.6 Spawn A/B todavía puede mostrar un falso «hit» — reproducido

v16 mejora GameLearning, pero el contador de la UI sigue usando `hitConfirmed` por desaparición del jugador/personaje, pérdida de salud o cambio de rol, además del impacto directo.

Ejecuté `resolve(candidate, false)` con el jugador desconectado y humanoide de la referencia todavía a 100 de salud: **Through.hits sube a 1**. No entrena el autoajuste con ese caso, lo cual es correcto, pero su etiqueta `hits/shots` sigue siendo demasiado fuerte para comparar geometrías.

Referencia: [core 3520–3575](https://github.com/XzAngel19/ARandomMenu/blob/2c7ab1a36164bd17fd0d0643cb8395c2e4a4da77/src/games/MM2/base.lua#L3520-L3575).

## 6. Qué dicen los datos, sin inventar tasas de acierto

El archivo de calibración está guardado el **14/10 a las 16:21:08 UTC**, pero su evento más reciente es de las **06:24:06 UTC**. Guardar más tarde no convierte la actividad importada en una sesión nueva.

- 206 eventos: **114 Knife, 48 Gun, 44 Stab**.
- Fechas UTC: 22 del 11 de octubre, 169 del 12, 15 del 14.
- Gun: 19 registros con `hitTarget=true`, 29 con false. **No equivalen a 19 aciertos de 48 intentos enviados**: son registros detallados conservados, no un denominador completo.
- Los siete Gun finales contienen cuatro impactos reportados. La muestra es demasiado pequeña y no lleva build por evento para declarar una versión ganadora.
- Los 44 Stab no contienen confirmaciones `hitTarget`; no justifican aprender alcance efectivo.
- Knife reporta velocidad 96 en las observaciones; no contiene una prueba equivalente de cada impacto o baja.
- `session.gunAttempts ≈ 3,139×10^57`, `gunConfirmed ≈ 1,177×10^57`: inutilizables como cantidades reales. En esa escala ni sumar uno cambia el número representado.
- GameLearning MM2 conserva 1.317 shots agregados, 442 misses y 9 kills inferidos, pero solo 300 shots detallados y una metodología antigua que no demuestra autoría/resultado. No calcularía precisión con esos totales.

La revisión de TestingStuff consultada **no contiene el schema 4 con build/sessionId de una prueba v16**. No permite certificar si v16 mejoró o empeoró tu sesión actual.

## 7. Lag: hallazgos y límites

### Trabajo innecesario histórico confirmado

En v10/v11/v14 el guardado vuelve a combinar archivo acumulado con runtime acumulado y conserva el resultado para el siguiente guardado. Eso produce crecimiento repetido de contadores/buckets y lectura/decodificación del archivo; no debe interpretarse como actividad real. v15 elimina esa realimentación; v16 aísla la sesión de los totales ya contaminados.

### Riesgos todavía a medir

- Serialización del historial completo: hasta 2.400 eventos, con trayectorias que pueden llegar a 120 puntos por registro. La escritura diferida evita ponerla directamente en el envío, pero JSONEncode sigue consumiendo CPU.
- Reintentos de Auto Shoot/Throw sin éxito vuelven a recorrer objetivos y/o hacer raycasts a la frecuencia configurada; no todos los rechazos tienen backoff.
- Un Fire delay fuera de rango puede disparar mucho más trabajo del esperado.
- Gun ESP puede llegar a recorrer `workspace:GetDescendants()` para buscar el arma; su caché reduce frecuencia, no el coste de cada barrido.
- Cambiar 60→120 Hz no crea paquetes nuevos de posición ni garantiza precisión. A 60 FPS no hay 120 callbacks Heartbeat distintos por segundo.

**No se midieron FPS, p95/p99 de frame time ni coste de JSONEncode en tu dispositivo.** Los números de contadores corruptos no consumen CPU por su magnitud por sí solos; los riesgos son el procesamiento/guardado y el volumen de estructura, entre otros.

## 8. Revisión complementaria de los demás módulos MM2

Se revisaron las rutas de integración, no se certificó cada función en juego:

| Módulo | Observación |
|---|---|
| Roles / core | Índice compartido por Shoot, Knife, ESP y notificaciones. Herramientas/tags/collision group/datos de ronda pueden determinar el rol; registrar su procedencia ayudaría a explicar rechazos |
| Knife Aura | Auto Range ahora ignora intentos no confirmados; sin productor de confirmación Stab utilizable se queda en el rango manual. No venderlo como aprendizaje ya efectivo |
| RoundEsp | Gun con polling/caché; Trap por eventos y barrido inicial. No existe prueba nueva de precisión/rendimiento visual en juego |
| Teleport | `Teleport to Lobby` busca literalmente `workspace.Lobby.Spawns`; el XML actual contiene `RegularLobby`. Incompatibilidad concreta con ese snapshot, pendiente de comprobar en la sesión real |
| Auto Get Gun | Una tarea ya iniciada puede continuar tras desactivar; no tiene token de cancelación. Conviene probar off/on, respawn y recogida fallida |
| Sprint | Guarda/restaura velocidad, pero no asocia la base al Humanoid específico y puede competir con Speed universal. Falta prueba combinada y de respawn |
| InstantRoleNotify / BlurtRoles | Consumen roles compartidos; Blurt usa tareas diferidas y chat real. Necesitan prueba de transición de ronda/cancelación, no ajustes de predicción |
| WeaponVisuals | Geometría local separada del daño. Los mocks de limpieza pasan; no aporta precisión ni confirma doble daño |
| Metrics / TrajectoryCalibration | El texto visible todavía dice «Schema 2», aunque el escritor de v16 produce schema 4. Abrir/cerrar la tarjeta no apaga el colector iniciado por el core |

Los perfiles se guardan por GameId/PlaceId, **no por rama** (`Wurst/Profiles/Game_….lua`). Cambiar de rama no limpia el perfil. Un Front guardado puede prevalecer sobre el nuevo default Through; el rango compartido también puede sobrevivir al cambio de versión.

## 9. Verificación ejecutada en esta sesión

Con **Luau oficial 0.732**, construido desde su tag:

- Reejecutada auditoría histórica: cinco bundles concordantes, 35 archivos históricos compilados y 24 caracterizaciones ejecutadas en v10/v11/v14.
- Compilación adicional de snapshots `fa5a0f6`, `66d7152`, `17c15f3`: 69 archivos `.lua` en cada uno, sin errores.
- v16: **70 archivos `.lua` compilan**; bundle con **68 entradas** concuerda con sus fuentes y sello.
- `test_mm2_precision.py`: **14 grupos aprobados**.
- `test_mm2_v16.py`: **4 grupos aprobados**.
- `test_entity_team_provider.py`: **14 comprobaciones aprobadas**.
- XML: 303 propiedades compiladas sin ejecutarlas; dos candidatas con errores de descompilación, descritas arriba.
- Nuevo `tools/audit_mm2_remaining.py`: **6 grupos de caracterización aprobados**, reproduciendo estado Knife/rangos, límites numéricos, dependencia de Hz, override de Silent, correlación incorrecta y falso hit en Spawn A/B; más comprobación estática del mínimo error imposible.

**Los tests anteriores pasan y, aun así, los nuevos defectos se reproducen.** Su cobertura no incluye todos los estados de interfaz ni toda la correlación nativa. Esto explica por qué «pasa los tests» no significa «ya funciona perfectamente».

Reproducción del nuevo diagnóstico desde esta rama, con el objeto Git de v16 disponible:

```bash
git fetch origin arena/f208cfd3-arandommenu
python3 tools/audit_mm2_remaining.py --luau /ruta/a/luau
```

El script no cambia ramas ni archivos de runtime. Sus asserts describen defectos de la revisión fijada: **PASS significa reproducido, no reparado**. Las dependencias Roblox/GUI se simulan; no son pruebas de servidor, física o interfaz renderizada.

## 10. Orden recomendado para reparar, sin otra reescritura ciega

1. **Activación/configuración:** estado único de Knife, IDs independientes `AuraRange`/`ThrowRange`, migración explícita del antiguo Range ambiguo, validación numérica tanto al cargar como al escribir.
2. **Diagnóstico visible:** estado Ready/No role/No tool/Equipping/Disabled/No target/Blocked/Cooldown/No intercept/Error, y último intento/confirmación. No convertir todos esos estados en «no funciona».
3. **Correlación:** un registro de intentos consistente, comparación temporal y geométrica, tratamiento explícito de ambigüedad. No entrenar con una asociación dudosa. No inventar identificadores del servidor.
4. **Predicción:** normalizar el giro por tiempo, distinguir muestras nuevas de datos repetidos y revisar saltos/aterrizajes. Conservar un baseline histórico seleccionable para un A/B controlado, no restaurar toda v11.
5. **Evidencia coherente:** separar enviado, señal observada, impacto reportado y muerte asociada en logs **y** Spawn A/B. Que todas las mediciones lleven build, sesión y ajustes efectivos por intento.
6. **Prueba en Roblox:** Normal manual, Silent manual, Auto Normal, Auto Silent, Knife Throw Normal/Silent y Aura por separado; quieto, recta, giro, salto, aterrizaje y pared. Empezar en 60 Hz y cambiar una variable cada vez.
7. **Rendimiento:** tandas comparables con/sin telemetría y medir frame time, duración/bytes de serialización, raycasts y rechazos. No atribuir lag a un módulo por intuición.

Para cerrar MM2 con confianza hacen falta pruebas de ciclo completo —off/on, reinyección, perfil guardado, muerte/respawn, cambio de ronda y herramienta— además de impactos. Lo encontrado justifica correcciones concretas; todavía no justifica prometer precisión perfecta.
