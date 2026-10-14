# MM2 v17 — actualización utilizable y guía de diagnóstico

**Build:** `v17-20261014-mm2-controls-calibration`

**Rama:** `arena/d83a806d-arandommenu`.

Esta entrega incorpora el runtime Wurst v16 de `2c7ab1a` como base y aplica reparaciones concretas. No se fusiona con `main`. La auditoría anterior y su script siguen siendo históricos: describen v16, no los cambios de esta entrega.

**No es una certificación de precisión perfecta:** las pruebas ejecutadas son de lógica local con Luau y mocks, no de física o aceptación del servidor de Roblox.

## 1. Loader

Destruye la instancia anterior con **Destruct** antes de reinjectar. No cambies solo el nombre de rama dentro de una instancia que ya está ejecutándose.

```lua
getgenv().WURST_BRANCH = "arena/d83a806d-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/d83a806d-arandommenu/src/Wurst.lua?v=" .. tostring(os.time()), true))()
```

Comprueba en consola el sello **`v17-20261014-mm2-controls-calibration`**. El bootstrap y las 68 entradas del bundle se distribuyen con el mismo sello. El archivo `loadstring` del repositorio contiene este loader.

## 2. RTT frente a RTT/2: aclaración

El fallo histórico encontrado fue **retirar RTT/2 de Knife sin una compensación sustitutiva**, no demostrar que RTT/2 sea universalmente correcto y RTT universalmente incorrecto.

Un modelo conceptual del adelanto es:

```text
adelanto temporal ≈ edad efectiva de la posición que observo
                  + viaje de mi petición al servidor
                  + procesamiento relevante
                  + vuelo del proyectil
```

- RTT es ida y vuelta; RTT/2 aproxima solo la ida si la red es aproximadamente simétrica.
- La posición recibida puede tener antigüedad adicional. La interpolación/extrapolación del motor puede modificar esa antigüedad efectiva. No conviene sumarla dos veces ni asumir que es conocida.
- Para una pistola tratada como hitscan, el vuelo se aproxima a cero. El modelo heredado de Shoot usa RTT completo, un suelo de 200 ms, una estimación de antigüedad y un margen de frame. Es una heurística, no una demostración del instante de colisión del servidor.
- Knife sí tiene vuelo. Si su posición de partida observada tiene la misma antigüedad, también puede necesitar algo próximo a RTT completo **más** vuelo. Que RTT funcione en Gun no basta para demostrarlo en Knife.

Ejemplo ilustrativo: con RTT de 200 ms, ida estimada de 100 ms y posición efectiva 100 ms atrasada, serían aproximadamente 200 ms antes del vuelo. Si la posición ya está extrapolada al presente, esos 100 ms adicionales podrían sobrar.

### Comparación disponible en Knife

`Knife latency model`:

- **Packet RTT/2**: conserva el modelo base de v16; compensa media vuelta antes de resolver el vuelo.
- **Replica RTT**: presupuesta RTT completo antes del vuelo. Es una alternativa de comparación, no una mejora garantizada.

`Knife lead bias`: corrección manual entre −0,15 y +0,15 segundos. Empieza en cero. `Throw prediction status` muestra el último tiempo de red usado, tiempo de vuelo y velocidad.

El estimador de RTT conserva el límite heredado de **30–300 ms**. La intercepción sigue siendo de velocidad constante del objetivo, incluida la vertical. No se ha presentado como resuelto el salto/aterrizaje completo ni los giros futuros voluntarios.

## 3. Hz: qué cambia y qué no

| Frecuencia | Intervalo nominal |
|---|---:|
| 60 Hz | 16,67 ms |
| 120 Hz | 8,33 ms |
| 240 Hz | 4,17 ms |

120 es el límite configurado de Motion/Throw en esta build, **no un máximo universal de precisión**. Una implementación a 240 Hz podría reducir espera local si el cliente dispone de frames suficientes, pero no inventaría posiciones replicadas nuevas ni eliminaría el cooldown. También aumentaría el trabajo de selección/raycast/muestreo.

A 60 FPS, este scheduler no produce 120 observaciones Heartbeat independientes. Repetir una lectura o enviar más paquetes no equivale a predecir mejor. Se mantienen **60 Hz por defecto, 120 opcional**, sin ráfagas para recuperar frames perdidos.

Ahora el giro se normaliza por tiempo y las lecturas repetidas de la misma dirección no se toman como actualizaciones independientes. Esto corrige una dependencia de la fórmula respecto a Hz; no demuestra una tasa mayor de impactos.

## 4. Reparaciones incluidas

### Knife

- Principal y preferencias Aura/Throw comparten un controlador. OFF pausa; ON restaura las preferencias marcadas. Una subopción marcada con el principal OFF permanece pausada.
- **Aura Range** y **Throw Range** tienen claves distintas.
- El antiguo `MM2.Knife.Range` era ambiguo. Se conserva una copia `LegacyRange`, sin aplicarlo a ambos controles. Los nuevos valores iniciales son Aura 14 y Throw 120, salvo que ya exista una preferencia nueva.
- Los límites numéricos se aplican al slider, escritura y carga del perfil. El arreglo del widget también protege otros controles numéricos del menú.
- Conserva intercepción, animación fuera de la ruta previa al envío y frecuencia configurable; añade origen de mano R6.
- `Knife status` informa principal/preferencias/estado. `Throw prediction status` muestra modelo, rango, delay y última solución. Errores del loop quedan en consola con prefijo de módulo y reintentos acotados por delay.
- Aura solo registra un intento de contacto si la llamada correspondiente no falla; no inventa confirmación de Stab.

### Shoot / Silent

- Giro basado en tiempo, con manejo de direcciones replicadas repetidas.
- `Max error` ya no permite valores menores que el suelo real de 0,35. Default 0,6.
- Respeta señales locales `Disabled`/`Enabled` del arma; errores de envío no se registran como peticiones exitosas.
- `Shoot status` muestra motivo, modo manual, modo automático, error máximo y horizonte efectivo.
- La UI conserva una cola de intentos, en vez de atribuir todas las respuestas al último.
- Spawn A/B separa intentos, señales observadas, partes del objetivo reportadas e intentos sin confirmar. Una desconexión, cambio de rol o salud genérica ya no incrementa aciertos.
- **Auto Shoot mantiene su propio Mode**. `Shoot → SilentAIM` no sustituye `Auto Shoot → Mode`.

No se restauran hitboxes locales ni burst. Silent modifica la geometría enviada, pero no garantiza que el servidor acepte cualquier origen o atraviese cualquier pared.

## 5. Por qué «calibración» parecía no ayudar

Hay varios sistemas distintos bajo Metrics; no todos entrenan la puntería:

| Sistema | Qué observa | Qué no demuestra / no hace |
|---|---|---|
| MM2 Calibration | Intentos propios, señales GunFired correlacionadas, proyectiles Knife por HandleLink, velocidad y ventanas opcionales de movimiento | Observar una señal/proyectil no demuestra baja; demora de respuesta no identifica el instante exacto de impacto |
| Game Learning | Escena alrededor de los intentos, movimientos, geometría y confirmaciones del puente MM2 | No entrena directamente Shoot/Knife; una muerte posterior no prueba autoría |
| Projectile observer universal | Tool.Activated y candidatos físicos nuevos por proximidad/nombre/movimiento | Puede no ver peticiones directas o hitscan; MM2 no consume su dataset |
| Learning | Capturas de pantalla y metadatos, si el executor dispone de la API | No es aprendizaje automático de trayectorias |

Antes, el correlador podía asignar a la petición más reciente una respuesta de otra anterior. Además, había adaptación temporal aunque `Auto tune lead` estuviera OFF, porque era un mecanismo separado. El histórico aportado contiene contadores contaminados y no es una referencia válida de precisión.

### Qué cambia en MM2 Calibration

1. Gun exige coincidencia geométrica de origen/dirección y arma cuando está disponible, dentro de una ventana temporal. Si varias peticiones encajan, **no elige arbitrariamente la última**: registra ambigüedad y no entrena.
2. Una asociación de cliente sigue siendo observacional, no un ID autoritativo del servidor. Los umbrales conservadores también pueden dejar sin confirmar disparos reales; eso se informa como desconocido, no como fallo.
3. Solo la demora de un envío authored correlacionado puede entrar en la ventana de adaptación de Gun. Tool.Activated no garantiza que el envío nativo haya ocurrido inmediatamente.
4. Knife no toma el último pending por handle cuando existen varios elegibles. Los proyectiles se deduplican. La activación no clasificada se mantiene distinta del intento de throw confirmado por observación.
5. Una velocidad de atributo se etiqueta **ThrowSpeed attribute**; una medida por desplazamiento, **client visual displacement**. Ninguna es un impacto. Con atributo válido y captura detallada OFF no se añade un muestreador visual por frame.
6. Se usa la identidad del personaje para evitar mezclar ventanas de movimiento con un respawn.
7. Los intentos que caducan se guardan como **unconfirmed**, no miss. Los ajustes efectivos, origen y destino authored se conservan en eventos acotados.
8. El historial antiguo queda protegido por el backup de v16. No se reimportan sus contadores como sesión actual.

### Controles nuevos de Metrics

| Control | Default nuevo | Efecto |
|---|---|---|
| Detailed MM2 trajectories | OFF | ON añade ventanas del objetivo; OFF conserva intentos/señales básicos |
| MM2 automatic saves | OFF | ON agrupa guardados a 10 s; manual y final en Destruct siguen disponibles |
| Adaptive gun timing | OFF | ON permite la mediana de al menos 6 respuestas authored únicas, recientes, entre 30 y 450 ms; ventana 60 s; efecto ±75 ms frente al baseline |
| Use observed knife speed | OFF | OFF usa 96; ON exige al menos 3 observaciones recientes, ventana 60 s, hasta 16 muestras, con mediana; no usa la media histórica como velocidad actual |
| Reset live timing | Acción | Borra ventanas recientes y corrección automática de lead; conserva historial y biases manuales |
| Game learning observer | OFF | Activa/desactiva el logger de escena y sus probes; no controla el colector MM2 básico |
| Projectile observer | OFF | Activa/desactiva el logger universal; no controla el solver MM2 |

`Auto tune lead` continúa siendo otra opción de Shoot, basada en impactos directos correlacionados y trayectoria disponible. No cambia el slider manual. Para comparar el baseline, déjala OFF junto con Adaptive gun timing.

`Show learned profile` imprime también en F9: build, conexión de GunFired, intentos, observaciones, ambigüedades, caducados, tamaños de ventanas recientes, persistencia y duración/bytes del último guardado. El historial detallado está acotado a **600 eventos**; para comparar tasas no uses la longitud de una lista recortada como denominador de toda la sesión.

Desactivar observadores y captura detallada reduce trabajo, pero no se ha medido la ganancia de FPS en tu equipo. Game Learning tiene su propio guardado de 15 s cuando está habilitado; no lo apaga el control MM2 automatic saves.

## 6. Qué hacer ahora, sin tocar código

### Primera tanda: verificar funcionamiento

1. Carga v17 y confirma su sello. No dejes dos instancias activas.
2. **Knife**: principal ON, **Knife Throw ON**, Aura OFF para aislar Throw. Modo Normal, Throw Range 120, Fire delay 1 s, Throw Hz 60, Packet RTT/2, bias 0. Con el rol Murderer y un objetivo visible, comprueba `Knife status` y `Throw prediction status`.
3. Apaga/enciende el principal: Throw debe volver a ejecutarse manteniendo la casilla marcada. Prueba también después de respawn.
4. **Shoot**: Motion Hz 60, Lead bias 0, Auto tune lead OFF. Prueba primero Normal manual; después Silent manual con Through. No cambies ambos modos durante la misma tanda.
5. **Auto Shoot**: elige explícitamente Normal o Silent en su propio Mode. Mantén Max error 0,6 y Fire delay 0,5 s inicialmente. Consulta `Shoot status` si no envía.
6. Mantén los observadores opcionales apagados para esta primera comprobación de funcionamiento/rendimiento.

Son ajustes de partida reproducibles, no afirmaciones de cooldown óptimo del servidor ni máxima precisión.

### Segunda tanda: registrar y comparar

1. En Metrics activa **Detailed MM2 trajectories** y **Game learning observer**, con **Log shots ON**. Para estudiar puntería no necesitas activar Log movement, Log hitboxes ni Projectile observer; puedes apagar los dos primeros.
2. Mantén Adaptive gun timing y Use observed knife speed OFF durante la comparación inicial.
3. Haz tandas separadas con objetivo quieto, recta, giro y salto. Guarda al terminar cada tanda y copia/renombra externamente los archivos para no confundirlas.
4. Para Knife compara Packet RTT/2 frente a Replica RTT sin cambiar a la vez Hz, range, delay, bias o modo Normal/Silent. La calibración no certifica impactos Knife: acompaña los datos con observación o grabación.
5. Usa **Save calibration** y **Save learning logs**. Consulta el estado después de guardar para detectar errores de API/backup.
6. Desactiva la captura detallada y Game learning observer cuando termines. Prueba 120 Hz solamente si mantienes FPS altos y no introduces tirones.

Archivos en el workspace del executor, no en este repositorio:

```text
Wurst/Telemetry/MM2_Trajectory_Calibration.json
Wurst/Telemetry/Universal/Place_142823291_Game_Learning.json
```

Comprueba `buildStamp`, `sessionId` y ajustes por evento. Un timestamp reciente de guardado no convierte datos antiguos en una sesión nueva.

## 7. Qué sigue pendiente

- Prueba real en Roblox de aceptación de remotos, impactos, apariencia y frame time.
- Modelo de salto/aterrizaje de Knife; por ahora la velocidad constante puede fallar en esos escenarios.
- Selección de otro objetivo cuando el más cercano visible tiene una intercepción imposible o su punto futuro está bloqueado.
- Confirmación autoritativa de Stab/impacto Knife: no disponible en la evidencia inspeccionada. Auto Range no se alimenta de intentos como si fueran aciertos.
- Evaluar empíricamente el suelo heredado de 200 ms de Gun y los límites del estimador de RTT. No se han cambiado a ciegas.
- El observador universal sigue siendo heurístico, no un detector infalible de proyectiles. Esta actualización da control sobre su ejecución; no lo presenta como reescrito o certificado.

## 8. Validación

Con Luau oficial 0.732:

- **70 fuentes `.lua` compiladas**, sin errores.
- Bundle consistente con **68 entradas**, sello v17.
- `tools/test_mm2_precision.py`: **14 grupos** (mocks actualizados para las nuevas dependencias/opciones explícitas).
- `tools/test_mm2_v16.py`: **4 grupos** de compatibilidad.
- `tools/test_mm2_v17.py`: **12 grupos** nuevos de control, migración, clamp numérico, normalización temporal, opt-in, RTT A/B, correlación Gun/Knife, evidencia, captura ligera y observadores opcionales.
- `tools/test_entity_team_provider.py`: **14 comprobaciones**.

Los tests ejecutan funciones/módulos originales con servicios simulados. Compilar y pasar mocks no equivale a haber ejecutado el juego. Esta entrega sí contiene arreglos utilizables; **no se denomina arreglo total ni se promete 100 % de aciertos**.
