# MM2: resultados de tus JSON y actualización v18

> Histórico de v18. La rama entrega ahora [v21: selector local rápido, red inestable y menú ligero](MM2-v21-fast-projections.md).

**Build:** `v18-20261014-mm2-evidence-motion`
**Rama:** `arena/d83a806d-arandommenu`
**Evidencia:** [TestingStuff, snapshot 43ee19a](https://github.com/XzAngel19/TestingStuff/tree/43ee19ac7946861c2106822fa9060258e62758de).
**Comparación de código:** `66d7152` frente a v17 `64e203e`.

## Conclusión práctica

No recomiendo volver a todo el runtime antiguo. Sí encontré diferencias concretas que pueden explicar por qué `66d7152` respondía mejor: un filtro mucho más permisivo con Hitbox, varios horizontes por trigger con Burst y un horizonte temporal que podía ser menor que el de v17. V17 conservó un suelo temporal de 200 ms y endureció la respuesta a giros; esas decisiones no estaban demostradas como mejores en tu sesión.

V18 recupera una opción de movimiento clásico, elimina el suelo obligatorio en el nuevo modo RTT y separa el filtro manual del automático. Además añade una comprobación acotada del suelo para no extrapolar una caída debajo de una superficie detectada. No reintroduce cajas locales ni ráfagas que antes reportaste como costosas.

**Hay cambios utilizables, no una certificación de 99,99 %.** La comparación retrospectiva mide posiciones visibles, no reproduce el servidor. La percepción de que antes funcionaba mejor es válida como señal para investigar; los JSON permiten identificar mecanismos y comparar modelos, pero no transformar cada ausencia de confirmación en un fallo ni cada muerte cercana en un acierto.

## 1. Inventario: se revisaron todos los archivos disponibles

En el snapshot hay ocho JSON. Tres backups de calibración son byte por byte el mismo archivo: `05e71909e95d53ff578667486f49b3111036f4e0` es su Git blob. Por tanto se usan una vez y se excluyen las otras dos copias del cálculo. No son tres tandas independientes.

| Dataset único | Contenido útil | Tratamiento |
|---|---|---|
| MM2 Calibration actual, schema 4 / v17 | 83 eventos, 188 puntos de trayectoria | Sesión actual, separada del histórico |
| MM2 Calibration antiguo, schema 3 | 206 eventos, 2.150 puntos | Posiciones aprovechadas; contadores gigantes no se usan como denominador |
| Game Learning MM2 actual, schema 2 / v17 | 17 registros: 14 Knife y 3 Stab | No contiene Gun; no sirve como segunda evaluación de Shoot |
| Game Learning MM2 antiguo, schema 1 | 300 registros retenidos, 13 entradas en hits | Escenas/contexto; etiquetas antiguas no son confirmaciones fiables de autoría |
| Place 135856908115931 | Otro lugar | No mezclado con MM2 |
| Place 92876937625630 | Otro juego | No mezclado con MM2 |

**2.338 puntos brutos de trayectoria** entre calibración nueva e histórica. Se evalúan las trayectorias utilizables, no solamente cuatro señales de Gun. Los JSON originales no se vuelven a subir a este repositorio; el [resultado reproducible](audits/MM2-json-20261014-results.json) contiene hashes SHA-256, inventario y estadísticas sin nombres de jugadores.

El histórico incluye `gunAttempts ≈ 3,139 × 10^57`; eso es corrupción de acumulación, no una cantidad real de disparos. No impide estudiar sus posiciones individuales, pero invalida un porcentaje calculado con esos totales.

## 2. Qué dice exactamente la sesión nueva

### Shoot

- **9 intentos registrados:** 6 authored por el menú, 3 activaciones nativas.
- Los **6 authored fueron Normal**, Motion Hz 120, bias 0, adaptación temporal OFF, auto tune ON.
- Todos esos authored guardaron **horizonte 0,233333 s**.
- **4 señales correlacionadas:** 3 authored y 1 nativa. Las cuatro tienen `hitTarget=false`.
- **5 intentos sin confirmar**, 0 señales ambiguas y 2 señales locales no asociadas.
- Los intentos Gun retenidos abarcan aproximadamente **20:36:46–20:37:25 UTC** del 14 de octubre: unos 39 segundos dentro de una sesión del logger de unos 928 segundos.

| Intento | Origen | Demora observada | Parte del objetivo reportada |
|---|---|---:|---|
| 2 | Authored Normal | 459,5 ms | No |
| 3 | Authored Normal | 220,3 ms | No |
| 4 | Authored Normal | 207,0 ms | No |
| 6 | Activación nativa | 147,9 ms | No |

Esto respalda que **los disparos observados no estaban resolviendo bien**, pero no da un porcentaje de todas tus rondas. Los cinco sin confirmar no se pueden clasificar automáticamente como cinco misses. Tampoco existe aquí una tanda nueva de Silent que permita afirmar que su geometría fue mejor o peor que Normal.

Hay además un defecto de captura de v17: las trayectorias muestreadas de los intentos que caducaban **no se escribían en el evento de caducidad**. Los datos de posiciones de esos cinco intentos no pueden reconstruirse del JSON. V18 los conserva, junto con origen/destino, sin inventar un resultado.

### Knife

- **24 authored throws: todos `Replica RTT`**, Normal, delay 1 s, rango 120, 60 Hz.
- 10 observaciones de proyectil con velocidad válida, 14 authored sin confirmar y 5 señales ambiguas.
- Las 10 velocidades nuevas son **96 studs/s**; el histórico también conserva 96. En esta captura activar la velocidad aprendida no proporciona una velocidad mejor o diferente del fallback.
- Game Learning contiene 5 asociaciones temporales con muertes, **no cinco impactos atribuibles demostrados**.

Tu preferencia por RTT completo se conserva. Estos archivos no incluyen una tanda contemporánea RTT/2 con la que cuantificar la ventaja; no se cambia a media vuelta por una hipótesis. V18 usa Replica RTT como valor inicial para perfiles nuevos y respeta el valor que ya tengas guardado.

## 3. Qué aportaban realmente Hitbox y Burst en `66d7152`

### Hitbox también cambiaba cuándo se permitía disparar

El código no se limitaba a crear una caja:

```text
bodyHalfWidth = hitboxSize × 0,5
allowedErrorBudget Normal = max(1, bodyHalfWidth)
allowedErrorBudget Silent = 1,75 × max(1, bodyHalfWidth)
```

Con tamaño 8, el margen interno Normal pasaba de **1 a 4 studs**; Silent, de **1,75 a 7**. Un intento que el solver sin Hitbox rechazaba por giro podía pasar con esa opción. Auto Shoot seguía teniendo además su propio `Max error`: ampliar la caja no anulaba ese segundo filtro.

La caja era un `Part` local llamado `WurstHitbox`, anclado bajo el personaje y reposicionado al aplicar la función. Esta ruta de Gun enviaba dos CFrames, no un tamaño de hitbox al servidor. El comentario antiguo de que ensanchaba la cápsula puntuable del servidor **no está demostrado por ese código ni por los JSON**. Sí está demostrado el cambio del filtro de disparo.

### Burst cubría varios tiempos

En v10 enviaba hasta cuatro peticiones por trigger, con offsets:

```text
0, +horizonte/2, −horizonte/2, +horizonte
```

Por tanto podía cubrir varias posiciones previstas. Eso no es lo mismo que mejorar la precisión de una única predicción. Para que ayudara al resultado real el servidor tendría que procesar peticiones relevantes; el cliente no demuestra cuántas acepta frente a cooldown/validaciones.

No he reintroducido Burst a ciegas ni las cajas. En cambio, v18 recupera la posibilidad de enviar la mejor solución manual sin ese veto interno, conserva el filtro Auto y permite comparar el movimiento clásico sin restaurar los problemas de configuración y telemetría antiguos.

## 4. El tiempo de adelanto sí cambió

La fórmula de `66d7152` podía consumir la media histórica de `gunAcceptanceMs` tras dos muestras. El backup tiene **145,705 ms**. Introducida en esa fórmula, produciría aproximadamente:

```text
145,705 + 25 + 8,333 = 179,038 ms
```

Los seis authored nuevos guardaron **233,333 ms**. La diferencia es **54,295 ms**, equivalente a unos **0,869 studs a velocidad 16** antes de descuentos/correcciones. No estoy afirmando que todos los disparos históricos usaran 179 ms: faltan sus estados internos. Sí muestra que «la fórmula seguía igual» no significaba «el adelanto efectivo era el mismo».

Tampoco conviene restaurar sin más aquella media: mezclaba asociaciones problemáticas, sesiones y demoras que no son instantes de colisión.

V18 ofrece:

- **Gun timing → RTT**: RTT suavizado actual + el margen heredado de 33,3 ms, sin suelo de 200 ms.
- **Gun timing → V17 floor**: baseline anterior, `max(RTT, 200 ms) + 33,3 ms`.

Se mantienen los biases y la adaptación opcional. El límite heredado del estimador de RTT sigue siendo 30–300 ms. Ninguno de los dos modos convierte una demora de GunFired en una medida directa del momento del impacto.

## 5. Comparación retrospectiva de movimiento

Se compararon siete kernels a horizontes fijos de 150, 200, 233,33 y 300 ms, usando trayectorias del objetivo registradas tanto en Gun como en Knife. Esto estudia movimiento del personaje, **no impactos de Knife ni tiros completos de Gun**.

A **233,33 ms** hay:

- Histórico: **113 trayectorias, 1.173 ventanas** utilizables.
- Nuevo: **13 trayectorias, 102 ventanas** utilizables.

Cada trayectoria pesa lo mismo; sus ventanas se promedian primero. Las ventanas se solapan y no son disparos independientes. La referencia futura se interpola entre posiciones registradas, sin extrapolar huecos mayores de 150 ms. No se usan posiciones futuras para construir la predicción. Gravedad asumida: 196,2.

| Kernel aproximado | Error medio histórico | Error medio nuevo | P90 nuevo de medias por trayectoria |
|---|---:|---:|---:|
| Movimiento clásico | 3,605 | 2,671 | 7,180 |
| Movimiento v17 | 3,470 | 2,579 | 6,741 |
| Mezcla 50 % velocidad / 50 % dirección | **3,325** | **2,380** | 7,168 |

Unidades: studs. **No son porcentajes de acierto.** Los kernels clásico/v17 se evalúan a la cadencia del log, no con el estado interno completo de su sampler original. La comparación es exploratoria retrospectiva, no un holdout ciego. No prueba que reinstalar v10 ganaría partidas.

La mezcla reduce el error medio frente al proxy v17 aproximadamente **4,2 % en el histórico y 7,7 % en lo nuevo**, pero empeora su P90 nuevo. Por eso `Intent blend` es experimental y no el default.

### La vertical es un problema mayor que unos pocos Hz

En el conjunto nuevo, el proxy v17 tiene error medio horizontal **0,897 studs** y vertical **1,936**; la mezcla baja el horizontal a **0,554**, pero su vertical sigue en **1,998**. Son métricas separadas, no sumandos directos del error euclídeo.

Ambas fórmulas balísticas continúan descendiendo si no modelan contacto con el suelo. Por eso v18 añade **Landing guard**: una sola consulta vertical del mapa en el X/Z previsto, con alcance máximo de 64 studs, exclusión de personajes/objetos passthrough, clearance R6/R15 y rechazo de paredes inclinadas, superficies por encima del root o visuales no colisionables. Cuando detecta suelo admisible, impide apuntar por debajo de la altura de pie estimada.

**El efecto de ese guard no está incluido en la tabla anterior:** los JSON no conservan el mapa/sondeo necesario para reproducirlo. Está probado con escenarios simulados; no se atribuye a él una mejora porcentual medida. No adivina un salto futuro, choques laterales ni cambios del mapa.

### Hz y rendimiento

La mediana entre puntos Gun nuevos es **49,1 ms**, con máximo de 117,8 ms; 9 de 61 pares consecutivos repiten posición. El colector detallado limita su propio muestreo, así que esto **no es una medición del FPS ni de la tasa de replicación**. Sí confirma que el log no contiene una secuencia de posiciones independientes a 120 Hz.

El último coste de guardado previo informado es **7,37 ms para 120.788 bytes**. No es una medición de todo el coste de telemetría ni prueba que no haya tirones. El registro detallado y los observadores continúan siendo opt-in.

## 6. Actualización disponible y ajustes iniciales

Destruye la instancia anterior antes de cargar:

```lua
getgenv().WURST_BRANCH = "arena/d83a806d-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/d83a806d-arandommenu/src/Wurst.lua?v=" .. tostring(os.time()), true))()
```

Verifica **`v18-20261014-mm2-evidence-motion`**.

| Control | Punto de partida |
|---|---|
| Shoot → Motion model | **Classic 66d** |
| Shoot → Gun timing | **RTT** |
| Shoot → Hold uncertain manual shots | **OFF** |
| Shoot → Landing guard | **ON** |
| Shoot → Lead bias | 0 |
| Shoot → Auto tune lead / Metrics → Adaptive gun timing | OFF para comparar |
| Motion Hz | 60 para empezar; mismo valor entre tandas |
| Knife latency model | **Replica RTT** |
| Use observed knife speed | OFF: en estos archivos no cambia 96 |

`Classic 66d` recupera la respuesta de giro por muestra y su extrapolación horizontal, **no es un rollback byte por byte**: mantiene correcciones de respawn, clasificación de salto, transporte/telemetría y timing seguro; Landing guard también es un cambio respecto a v10. Puedes seleccionar `V17` y `V17 floor` para contrastar el baseline anterior, y desactivar Landing guard para aislar esa diferencia.

`Hold uncertain manual shots OFF` significa **enviar la mejor solución disponible**, no convertirla en una solución de alta confianza. Auto Shoot sigue obedeciendo su `Max error` y su propio `Mode`. No subas Max error interpretándolo como porcentaje; es un umbral en studs de una estimación heurística.

Para probar el candidato nuevo, cambia **solo Motion model a Intent blend**. Si mejora la media pero pierde tiros difíciles, la tabla ya advierte de ese intercambio; no se ha seleccionado por ocultar esos casos.

### Qué se registra mejor desde v18

- `Shoot diagnostics`: comprobaciones del solver, envíos Normal/Silent y motivos de rechazo acumulados. Las comprobaciones rechazadas pueden repetirse por frame: **no son disparos intentados**.
- Snapshot authored con modelo, timing, horizonte/lead, velocidad medida/usada, aceleración, dirección, posición root/parte, error estimado y datos del guard.
- Trayectoria de intentos caducados, si Detailed MM2 trajectories estaba ON.
- Los rechazos no se escriben uno a uno por frame; se guardan contadores acotados por motivo en el snapshot de calibración.

Esto corrige puntos ciegos descubiertos en tus archivos. No hace falta que repitas todo para justificar los hallazgos actuales. Para medir el resultado de v18, las próximas tandas deben guardar Gun y Silent explícitamente; el Game Learning actual que subiste solo registra Knife/Stab.

## 7. Sobre el objetivo de 99,99 %

Podemos perseguir la máxima precisión y separar tasa por petición, tasa por activación, cobertura y coste. No podemos certificar 99,99 % con señales desconocidas, contadores corruptos o asociaciones temporales.

Incluso observando cero fallos harían falta aproximadamente **29.956 ensayos independientes y representativos** para sostener una cota unilateral del 95 % de al menos 99,99 % bajo un modelo binomial. Muchas ventanas de la misma trayectoria no equivalen a esos ensayos. Tampoco existe una garantía universal de predecir decisiones de movimiento tomadas después de la última observación.

La estrategia no es rendirse: es restaurar la respuesta útil del clásico, corregir sesgos temporales y límites físicos identificables, y comprobar que cada cambio mejora impactos sin ocultar rechazos ni aumentar tirones.

## 8. Reproducibilidad y validación

```bash
python3 tools/analyze_mm2_json.py --data /ruta/al/snapshot/TestingStuff \
  --output /ruta/resultados.json
python3 tools/test_mm2_json_analysis.py
LUAU=/ruta/luau python3 tools/test_mm2_precision.py
LUAU=/ruta/luau python3 tools/test_mm2_v16.py
LUAU=/ruta/luau python3 tools/test_mm2_v17.py
LUAU=/ruta/luau python3 tools/test_mm2_v18.py
python3 tools/build_bundle.py --check
```

- Análisis: **5 tests** sintéticos de deduplicación, separación de lugares, referencia temporal y errores conocidos.
- MM2: **14 + 4 + 12 + 7 grupos** de pruebas con Luau 0.732.
- Entity/team provider: **14 comprobaciones**.
- **70 fuentes Lua** compiladas; bundle de **68 entradas** con sello v18.
- Sin ejecución de Roblox ni medición de hit rate/FPS en juego. Los resultados offline y los tests no se presentan como esa medición.
