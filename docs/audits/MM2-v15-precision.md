# MM2 v15 — arreglo de Shoot y Knife basado en TestingStuff

**Build:** `v15-20261014-mm2-precision`  
**Rama de entrega:** `arena/f208cfd3-arandommenu`  
**Base preservada:** v14, `17c15f3ff802d0d2e036dbd18a6204d09169517f`  
**Evidencia externa:** [`XzAngel19/TestingStuff@302cc68c21f846aec221af1f992a8098720f3cd2`](https://github.com/XzAngel19/TestingStuff/tree/302cc68c21f846aec221af1f992a8098720f3cd2).

## Resumen

Se corrigieron las regresiones identificadas en [la auditoría v10–v14](MM2-v10-v14-20261014.md), sin restaurar hitboxes locales ni ráfagas de paquetes. La rama de esta sesión incorporó v14 mediante fast-forward; no se modificó ni publicó sobre `arena/2daf1a78-arandommenu`.

**Objetivo:** recuperar el comportamiento útil de v10/v11 y quitar errores verificables de predicción, muestreo y calibración. **No se promete 100 % de impactos ni se certifica una precisión máxima dentro del juego:** falta una prueba de sesión con el servidor real. Las pruebas incluidas ejecutan funciones originales del proyecto con un entorno simulado.

## 1. Qué muestran realmente los archivos aportados

| Archivo | Resultado de la revisión | Consecuencia para el arreglo |
|---|---|---|
| `MM2_Trajectory_Calibration.json` | 162 muestras de velocidad de Knife: mínimo, máximo y media = **96 studs/s** | Mantener 96 como fallback, aceptar una velocidad calibrada solo si es finita y plausible |
| Mismo archivo | 62 observaciones de aceptación de pistola; media **200,0177 ms**, mínimo **27,369 ms**, máximo **1624,154 ms** | No alimentar el solver con el promedio histórico sin filtrar |
| Mismo archivo | Spawn delay Knife: media **210,967 ms**, máximo **2312,898 ms** | No reemplazar RTT/2 por este promedio contaminado por demoras/atribución |
| Mismo archivo | Solo cuatro eventos detallados conservados, todos Knife; no hay un replay completo de las 62 observaciones de pistola | No afirmar que se ha recalibrado toda la pistola a partir de esos cuatro eventos |
| `Place_142823291_Game_Learning.json` | 191 registros; mezcla armas con juguetes y otros tools. Hay 49 de kind `gun`, 30 `stab` y otros sin kind | No interpretar el contador total como 191 disparos comparables de pistola |
| Mismo archivo | Through: dos registros y cero kills atribuidos; ping de los 191 registros entre **89,754 y 137,598 ms**, mediana **106,756 ms** | Dos registros no permiten elegir estadísticamente la mejor geometría. Through se restaura por compatibilidad con la versión reportada como buena, no por una supuesta prueba de 100 % de acierto |
| Archivo MM2 `.rbxl` | 292 propiedades Source: 270 dicen `decompilation panicked`, 21 `failed to get script bytecode`, una es README del serializador | No contiene código utilizable para verificar el algoritmo del servidor |
| `message.txt` | Fuente de otro menú. Permite comparar formas de argumentos `CFrame`, pero no demostrar qué acepta el servidor actual | Leído como referencia, no ejecutado ni copiado al runtime |
| Logs de otros PlaceId | Corresponden a juegos diferentes | No usados para inferir validaciones, velocidades ni aciertos de MM2 |

Los JSON de referencia no incluyen una etiqueta de build que identifique de forma inequívoca cada intento como v10/v11/v14. Además, las métricas de acierto antiguas son heurísticas, según la auditoría previa. Estos límites impiden atribuir a una versión toda la tasa de fallos del archivo.

### Integridad de las entradas

SHA-256, calculados sobre el contenido descargado del commit indicado:

```text
MM2_Trajectory_Calibration.json
22fb88a05a2698c37d3f2d7a0b3ce6eedaec9873820c9857195e3db36b75af78

Place_142823291_Game_Learning.json
5fc9bb8dbdc48c4e5fbf090c23225d46ff4678e11f67cab93469e84538fd584b

message.txt
2d8cf398c2da3be0f7c324d6fb26b839a0991c8bdcc7b060b8658301ccf20934
```

No se incorporan al repositorio los mapas, los archivos grandes ni nombres de jugadores de esas sesiones.

## 2. Cambios en Shoot

### Geometría y muestreo

- Default **Silent spawn = Through**, como v10/v11. El selector Front/Through/Top/Behind sigue disponible. Un perfil que guarde Front puede conservar su elección: comprobar el valor visible después de cargar.
- La posición capturada de Through corresponde ahora a la **misma pieza corporal** a la que se apunta. No mezcla el inicio en HumanoidRootPart con el final desplazado desde UpperTorso.
- La comprobación de terceros se ejecuta sobre el segmento real aunque `Silent sweep = 0`. Si el segmento alternativo también cruza un tercero, rechaza el disparo.
- Evita construir un `CFrame.lookAt` con origen y destino iguales.
- Muestrea continuamente **solo al objetivo seleccionado**, no a todos los jugadores. Vuelve a leer velocidad cuando se calcula el disparo.
- Reinicia la estimación de aceleración tras un respawn, una muestra vieja o un desplazamiento de teletransporte. Descarta velocidades no finitas.
- Corrige el uso de `false` en grounded y evita tratar como pegado al suelo un objetivo que asciende claramente, aunque FloorMaterial aún no haya cambiado. El log aportado muestra precisamente una muestra `grounded=true` con velocidad vertical 16,715.
- Mantiene WallCheck para Normal. Silent sigue omitiendo paredes deliberadamente, pero no la comprobación de terceros.
- No relaja los presupuestos de error artificialmente: se conserva el filtro del solver y el filtro adicional de Auto Shoot. La descripción del control se corrigió para no afirmar que sweep anula ese filtro.

### Horizonte y calibración

- Corrige el alcance léxico de `trajectoryCalibration`: la función de horizonte accede al controlador local real, no a una global inexistente.
- Conserva como arranque/fallback el horizonte conocido de v10: `max(RTT, 0.200) + 0.025 + 1/120`, más los biases acotados existentes.
- La adaptación basada en aceptación utiliza **solo observaciones nuevas correlacionadas con un disparo pendiente**, no las medias guardadas ni los eventos de pistola sin correlación.
- Para usarlas: mínimo **6 muestras**, ventana de **60 s**, hasta **24 muestras**, aceptación entre **30 y 450 ms**. Usa mediana, no media acumulada.
- Limita la diferencia frente al fallback a **±75 ms** para no saltar a un lead extremo por una tanda anómala. Es una protección conservadora, no una constante demostrada óptima por el servidor.
- Lectura de RTT a un máximo aproximado de 10 Hz y suavizado por tiempo transcurrido. Subir Motion/Throw Hz ya no acelera artificialmente el suavizado por aumentar el número de llamadas.

### Auto tune lead, separado de la calibración de latencia

- Sigue siendo **opt-in** y no cambia el slider manual.
- Conserva la trayectoria a 30 Hz, pero calcula el instante de cruce mediante **interpolación entre segmentos**, en vez de redondear al frame más próximo.
- Corrige la diferencia de altura torso/root al comparar el punto apuntado con las posiciones muestreadas.
- Solo ajusta a partir de un hit directo reportado por la señal observada. Desaparición, cambio de rol o reducción genérica de salud no entrenan el lead.
- No entrena desde Silent: acertar algún punto de un segmento Through no identifica el instante de cruce de su endpoint.

## 3. Cambios en Knife

### Throw

- Restaura **RTT/2**, eliminado después de v11, para el movimiento del objetivo durante el viaje de ida del paquete.
- Después del viaje estimado del paquete, resuelve la intercepción de **velocidad constante**:

```text
posiciónAlSpawn = posiciónActual + velocidadObjetivo × RTT/2
|posiciónAlSpawn - origen + velocidadObjetivo × t| = velocidadKnife × t
```

- Usa la raíz positiva más temprana; trata explícitamente el caso casi lineal y rechaza soluciones inexistentes/no finitas o mayores de cinco segundos. No inventa una intercepción acortando un tiempo físicamente imposible.
- Esto corrige el defecto del cálculo de una sola pasada `distanciaActual / velocidadKnife`, que no tenía en cuenta que el objetivo seguía cambiando la distancia durante el vuelo.
- Funciona tanto desde el origen Normal como desde el origen cercano de Silent.
- `Throw Hz` **sí controla el loop**. Mantiene el sobrante temporal y evita lanzar una ráfaga de recuperación tras un frame lento.
- `Fire delay` continúa siendo el límite de lanzamientos: 120 comprobaciones/s no significan 120 cuchillos/s.

**Límite del modelo:** RTT/2 supone un viaje de red aproximadamente simétrico. La intercepción supone velocidad constante; no puede anticipar giros voluntarios ni todos los saltos futuros. No se afirma que el movimiento vertical de un objetivo durante varios segundos sea lineal en el juego real.

### Animación

- No toma cualquier primera Animation; busca una identificada como throw. Si no existe, omite la animación cosmética sin bloquear el envío.
- Cachea por Humanoid, herramienta y AnimationId; cambia la pista si cambia alguno.
- Envía el paquete, fija cooldown y registra el intento **antes** del trabajo cosmético.
- Detiene/destruye la pista al apagar la opción, apagar Throw, cambiar de pista, reaparecer o destruir el módulo. Destroy se intenta aunque Stop falle.

### Aura / Auto Range

- Usa la misma política de rango al seleccionar el objetivo y validar el contacto diferido.
- Revalida el personaje y que el objetivo siga siendo válido/protegible; un respawn no hereda un contacto pendiente.
- Comprueba cooldown antes de recorrer objetivos.
- Los intentos no confirmados dejan de ampliar Auto Range. **Con los logs actuales no hay confirmaciones directas de stab utilizables, así que Auto Range recurre al rango manual.** El colector actual no proporciona un acuse autoritativo de cada stab; no se finge que lo haga. Esto es deliberadamente más conservador que llamar “verificado” al máximo alcance intentado.

## 4. ¿Por qué no ponerlo todo a 120 Hz?

**Hz de muestreo, tiempo de predicción y ritmo del servidor son cosas distintas.** El lead está expresado en segundos y se calcula cuando se resuelve un disparo. No existe un ajuste universal de “lead a 120 Hz” que multiplique su precisión.

| Tarea | Frecuencia nominal en v15 | Motivo |
|---|---|---|
| Historial de movimiento de Shoot | **60 Hz**, configurable 20–120 | Baja latencia sobre un solo objetivo. 120 opcional en clientes de FPS alto |
| Lectura para resolver un disparo | **En el momento de disparar** | No esperar a la siguiente muestra del historial |
| Búsqueda de oportunidad de Auto Shoot | **60 Hz** | Reduce espera nominal frente a los 30 Hz anteriores, respetando fireDelay |
| Comprobación de Knife Throw | **60 Hz**, configurable 20–120 | Restaurar el control que quedó desconectado |
| Knife Aura | **20 Hz** | Su cooldown de ataque sigue siendo 0,86 s; se revalida el contacto |
| Trayectoria del autoajuste de lead | **30 Hz + interpolación** | Medir el cruce sin cuantizarlo al frame ni cuadruplicar muestras |
| Trayectorias de diagnóstico del objetivo | Aproximadamente **30 Hz** | Son registros, no el solver que decide el disparo |
| Observación de proyectiles Knife activos | Callback de Heartbeat mientras existan | Registrar el movimiento real disponible, sin nuevos loops permanentes |
| Consulta de RTT | Como máximo aproximadamente **10 Hz** | No hay beneficio en consultar Stats varias veces por frame |
| Estimaciones compartidas | Caché de **0,25 s** | No recorrer hasta 2400 eventos por cada consulta de rango |
| Autosave MM2 | Agrupado cada **10 s** con eventos nuevos | Fuera de la ruta crítica de cada disparo |

A 60 FPS un callback de Heartbeat no produce 120 observaciones distintas por segundo. A 120 FPS, cambiar una tarea de 60 a 120 reduce su intervalo nominal de 16,7 a 8,3 ms, pero no inventa datos de red nuevos. Se eliminó el antiguo límite interno de 12 ms del muestreador para que la opción 120 pueda funcionar si el cliente realmente dispone de esa frecuencia.

**Recomendación de inicio: 60/60, no 120 en todo.** Comparar 120 solamente si el cliente mantiene FPS altos y frame times estables. Las pruebas simulan 20 combinaciones de frecuencia de frame/tarea y verifican conteos sin perder el sobrante ni emitir callbacks de recuperación en ráfaga.

Para movimiento recto, la prueba de cruce a `t = 0,2337 s` devuelve el mismo instante con muestras a 30, 60 y 120 Hz gracias a la interpolación. No extrapolar este resultado a giros o saltos arbitrarios: eso exige una prueba de sesión.

## 5. Correcciones relacionadas con los tirones y la telemetría

- El historial se carga **una sola vez**. Cada guardado escribe el estado acumulado actual; no vuelve a leer/decodificar/sumar todo el archivo anterior.
- Guardar dos veces sin actividad nueva ya no duplica contadores ni buckets.
- Autosave pasa de 0,8 s a **10 s**, agrupando eventos. El guardado manual y el de cierre/destrucción permanecen.
- Se mantiene un máximo de **2400 eventos**; también se limita lo cargado del historial.
- El formato de salida es **schema 3**. Conserva sumas/conteos de los buckets además de las medias legibles, para poder guardar y recargar sin volver a sumar medias como si fueran observaciones.
- Lee schema 2. Cuando el archivo antiguo solo conserva una media y un count, reconstruye la suma aproximada con esos datos; no puede recuperar denominadores que el formato antiguo no guardó.
- Si falla una escritura, mantiene dirty y los contadores para reintentar. Una revisión evita borrar dirty si entran eventos mientras el executor escribe.
- No se borran los archivos de usuario. Tampoco se corrigen mágicamente totales históricos ya inflados: se evita seguir duplicándolos.

Estas medidas eliminan trabajo innecesario y errores confirmados. **No constituyen una medición del origen del lag excesivo en tu dispositivo.** Todavía faltan frame times y observaciones dentro del juego.

## 6. Archivos de runtime afectados

- `src/games/MM2/base.lua`: helpers compartidos, movimiento/RTT, horizonte, calibración, guardado y lead tuner.
- `src/games/MM2/Blatant/Shoot.lua`: geometría, muestreo del objetivo, frecuencia de Auto Shoot y validaciones.
- `src/games/MM2/Blatant/KnifeThrow.lua`: latencia/intercepción, scheduler y animaciones.
- `src/games/MM2/Blatant/KnifeAura.lua`: validación de rango/objetivo y cooldown.
- `src/Wurst.lua`, `loadstring`: rama de entrega y sello de build.
- `src/libraries/bundle.lua`: regenerado desde las fuentes.

No se editaron ESP, GUI, movimiento ni otros módulos universales. El contenido de esos módulos dentro del bundle se vuelve a empaquetar sin modificar su fuente.

## 7. Validaciones

### Ejecutadas

- **14 grupos de regresión MM2**, usando cuerpos de funciones actuales y mocks, incluyendo:
  - 20 combinaciones de scheduler; pausa larga sin ráfaga.
  - Intercepción quieto/lateral/acercándose/alejándose/vertical; casos degenerados, imposibles y no finitos.
  - Muestreo a 120 Hz, teletransporte, respawn y limpieza de muestras inválidas.
  - Interpolación del lead a 30/60/120.
  - Calibración fresca y acotada, expiración, rechazo de medias históricas y de lotes insuficientes.
  - Jump con grounded atrasado, offset de torso, obstáculos de terceros y segmento de longitud cero.
  - Cooldown real del loop Knife con 20/60/120, error de animación y apagado.
  - Identidad/ciclo de vida de AnimationTrack y limpieza aunque Stop falle.
  - Rango diferido de Aura.
  - Writer real: guardados repetidos, migración, error/reintento y dirty durante escritura.
- **14 comprobaciones existentes** de `test_entity_team_provider.py`.
- Compilación con **Luau 0.732 de los 69 archivos `.lua`** bajo `src`.
- Verificación de las **67 entradas del bundle** y su sello.
- `git diff --check`.

### No ejecutadas

- Roblox/executor real, validación de servidor, benchmarks de FPS o tasa de impactos en una partida.
- Verificación autoritativa de las muertes históricas de Game Learning. Sus métricas heurísticas siguen existiendo, pero no alimentan el autoajuste nuevo como si fueran prueba directa.

### Reproducir

```bash
LUAU=/ruta/a/luau python3 tools/test_mm2_precision.py
LUAU=/ruta/a/luau python3 tools/test_entity_team_provider.py
python3 tools/build_bundle.py --check --stamp v15-20261014-mm2-precision

# Auditoría histórica, independiente del runtime modificado:
python3 tools/audit_mm2_history.py
```

El último script describe los defectos de snapshots antiguos; no es una suite que deba esperar esos defectos en v15.

## 8. Carga y prueba de sesión

Después de publicar esta rama, usar **la rama de entrega**, no la anterior:

```lua
getgenv().WURST_BRANCH = "arena/f208cfd3-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/f208cfd3-arandommenu/src/Wurst.lua?v=" .. tostring(os.time()), true))()
```

1. Exportar los logs previos antes de probar. No eliminarlos para ocultar errores.
2. Destruir la instancia anterior o iniciar una sesión limpia; comprobar el sello **`v15-20261014-mm2-precision`**.
3. Verificar **Silent spawn Through**, Motion Hz **60**, Throw Hz **60** y bias manual **0** como referencia. Dejar Auto tune OFF inicialmente para separar el modelo base de la corrección opcional. La mediana de aceptación reciente es una ruta distinta y se habilita cuando reúne sus muestras.
4. Probar Normal y Silent por separado, primero movimiento recto y después giros/saltos. Mantener el mismo fireDelay. Distinguir “rechazó por precisión/obstáculo” de “envió y falló”.
5. En un entorno privado/autorizado, registrar intentos, confirmaciones del arma e impactos observados. No usar el contador bruto de activaciones de tools como total de disparos.
6. Comparar 60 vs 120 **una opción a la vez**, sin cambiar simultáneamente geometría, bias y red. Registrar mediana/p95/p99 de frame time, ping, distancia y movimiento; no solo FPS medio.
7. Para investigar tirones, anotar si coinciden con el guardado, un lanzamiento, la animación, o si son constantes. Comparar animación OFF/ON sin alterar otras opciones.

**Si sigue fallando, lo que falta es una sesión etiquetada con este build**, sus ajustes efectivos y una captura/log de los fallos. No hace falta ninguna credencial. Hasta disponer de esa prueba, el resultado se describe como un arreglo verificado de lógica local, no como una garantía de máxima precisión en el servidor.
