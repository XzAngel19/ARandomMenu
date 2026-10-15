# MM2 v20 — Old / Actual / Experimental

> Histórico de v20. La rama entrega ahora [v21: selector local rápido, red inestable y menú ligero](MM2-v21-fast-projections.md).

Build: **`v20-20261014-mm2-prediction-profiles`**.

Esta entrega implementa la organización elegida: tres perfiles dentro de **Shoot → Mode: Prediction**, recupera las funciones legacy solicitadas y añade una opción vertical independiente para Knife. No declara un nuevo ganador ni una vulnerabilidad verificada.

## 1. Interfaz y perfiles

```text
Shoot
  Mode                 Prediction / Silent AIM
  Target               Murder / Custom
  Target player        solo Custom
  Prediction profile   Old / Actual / Experimental   [solo Prediction]
```

| Perfil | Comportamiento |
|---|---|
| **Old** | Respuesta de movimiento Classic 66d, su filtro de error y opciones Hitbox/Burst. Conserva las correcciones actuales de ciclo de vida, geometría, datos y timing seguro. |
| **Actual** | Configuración de v19, incluyendo tu Motion model y Gun timing guardados. Es la selección inicial para perfiles sin esta opción. Sin Hitbox ni Burst. |
| **Experimental** | Fija el candidato Intent blend, con la física vertical y Landing guard existentes. No es una fórmula nueva presentada como ya superior. Sin Hitbox ni Burst. |

Solo Old muestra Hitbox, Hitbox size, Burst y Old status; Hitbox size se oculta si Hitbox está apagado. Motion model se muestra en Actual para conservar y consultar su configuración anterior. Old y Experimental fijan su modelo, sin un segundo selector que lo contradiga.

**Silent AIM no hereda Hitbox, Burst ni el perfil Old/Experimental.** Usa el modelo compartido guardado de Actual y sus opciones Silent. Auto Shoot en Prediction utiliza el perfil de Shoot; Auto Shoot en Silent sigue separado.

No se borran preferencias al esconder controles. En un perfil nuevo Hitbox empieza OFF y Burst en 1. Si existen preferencias legacy de Hitbox/Burst, los widgets las restauran dentro de sus límites, pero no tienen efecto mientras no se elija Old.

## 2. Qué se recupera de 66d y qué se corrige

Referencia: commit `66d7152796ecb4562a8e4aa50f983fee7d6d7c60`. No es un rollback byte por byte: no recupera la media histórica contaminada como timing ni afirmaciones falsas sobre la colisión del servidor.

### Hitbox

Se recuperan ambas partes del comportamiento original:

1. Un Part local `WurstHitbox`, anclado e invisible bajo el personaje elegido, con query/touch activados y sin colisión física.
2. Un margen del solver igual a `max(1, tamaño / 2)`. Tamaño 8 permite hasta 4 studs de error estimado para superar ese filtro.

Old vuelve a aplicar ese filtro aunque el interruptor de retener tiros inciertos de Actual esté apagado. Auto Shoot conserva además su propio **Max error**: Hitbox no lo anula.

Correcciones y límites:

- Una sola caja reutilizada, no una colección acumulada por todos los jugadores.
- Actualización periódica como máximo a 10 Hz, además del ajuste al disparar.
- Limpieza al cambiar de objetivo/perfil/Mode, perder el objetivo, cambiar su personaje, desequipar el arma o apagar toda la infraestructura de tiro.
- No se modifican las partes originales del personaje.
- Un fallo al actualizar la caja no cancela el envío.

**La caja se crea en el cliente: no amplía automáticamente la hitbox que utiliza el servidor.** El código anterior lo afirmaba en comentarios/tooltips, pero no lo demostraba. El efecto comprobable en este solver es ampliar su tolerancia; los efectos sobre contactos locales se conservan como comportamiento legacy, no como impactos autoritativos.

### Burst

Se conserva el orden de candidatos original, siendo `h` el horizonte base:

```text
0, +h/2, −h/2, +h
```

La predicción base siempre va primero. Los offsets modifican el horizonte, no son esperas entre paquetes.

Mejoras:

- 1–4 peticiones por grupo y como máximo un grupo cada **0,5 s**, compartido entre tiro manual y Auto. Es un límite del menú, no un cooldown inferido del servidor.
- Sin ráfagas de recuperación después de una pausa de frames.
- Horizonte efectivo acotado a 0,03–0,60 s. Si dos candidatos terminan con el mismo horizonte por ese límite, no se envían dos copias.
- Un único horizonte base capturado para el grupo; cada candidato sigue comprobando arma, geometría y Max error.
- Cancelación si cambian los controles durante una espera de equipamiento, si una tanda nueva sustituye a la anterior o si cambia la época de calibración.
- Macro se ejecuta una vez por grupo con envíos, no una vez por candidato.
- Un fallo de transporte detiene el resto del grupo. Se limpia el motivo de rechazo anterior para no detener una tanda posterior que sí funciona.

No se afirma que cuatro peticiones sean cuatro disparos aceptados, ni cuatro oportunidades independientes de impactar. Los límites reducen trabajo y evitan algunos problemas antiguos; el FPS real requiere probarlo en Roblox.

## 3. Calibration: evidencia útil sin impactos falsos

Cada petición de Old registra:

- `settings.prediction.profile`, modelo, época, horizonte realmente usado y margen de error;
- `settings.burst.groupId`, `index`, `count`, `bias` y época;
- Hitbox local activada/tamaño, cuando corresponda.

`count` es el número de candidatos planeados. El número de registros authored indica cuántas peticiones se enviaron; puede ser menor por límites, deduplicación o rechazos.

### Caja sintética ≠ cuerpo real

Un contacto reportado con `WurstHitbox` se marca **`syntheticHit`** y no se cuenta como impacto en el cuerpo del objetivo ni se usa para aprender el timing. Esta distinción se aplica tanto al registro de Calibration como al feedback del predictor.

Los grupos con más de una petición tampoco entrenan el ajuste de lead ni el timing adaptativo. Una señal puede encajar con varios candidatos; asignarla arbitrariamente contaminaría el aprendizaje.

### Observación de grupo, sin inventar el tiro responsable

Cuando una señal es ambigua entre candidatos pero todos los candidatos geométricamente compatibles pertenecen al **mismo grupo y personaje**, se conserva un evento `burst-signal`:

- grupo y número de candidatos compatibles;
- contacto sintético o señal con una parte del cuerpo;
- endpoint y momento observado.

No se confirma ninguna petición individual con ese evento. Si también encaja otro grupo o una activación nativa, no se adjudica al grupo. Son callbacks observados, **no un contador de disparos únicos aceptados**.

El analizador separa perfiles, grupos y modelos de movimiento de Knife. Sus contadores de señales de grupo no se suman a impactos/disparos individuales. Los logs antiguos sin perfil quedan como `unrecorded`, no se reinterpretan como v20.

## 4. Knife: opción vertical nueva, independiente

En Knife aparece **Knife motion**:

- **Linear:** conserva la intercepción de velocidad constante de v19. Sigue siendo el valor inicial.
- **Vertical (experimental):** predice el movimiento vertical del objetivo durante el desfase de red y el vuelo, y resuelve numéricamente dónde interceptarlo.

El modelo experimental:

1. Distingue suelo y aire con el detector actual de movimiento.
2. Aplica gravedad al **objetivo** mientras está en el aire; no inventa gravedad para el cuchillo.
3. Considera un suelo detectado para no prolongar la caída a través de él.
4. Hace como máximo dos consultas de suelo por intento de predicción y una búsqueda temporal acotada; no añade un raycast por frame para todos los jugadores.
5. Revisa el suelo en el primer endpoint resuelto. Si la solución cambia de suelo y se aleja demasiado de la zona consultada, la rechaza.
6. Si no encuentra una intercepción acotada, no inventa una forzando el tiempo a un máximo. Limpia también el resultado anterior para no mostrar una predicción obsoleta.

Se registran modelo, velocidad usada, tiempo de vuelo, adelanto de red, estado de suelo, gravedad y suelo detectado. Se conserva RTT/RTT/2 como referencia temporal; esta entrega **no implementa todavía un estimador completo del desfase efectivo independiente del ping**.

Limitaciones: el vuelo del cuchillo sigue modelado recto; el movimiento horizontal sigue siendo de velocidad constante; un suelo consultado no reconstruye todo el mapa ni predice el próximo salto/giro del rival. Una búsqueda acotada también puede rechazar trayectorias cuya solución no consiga acotar. Esto es una alternativa comprobable, no un 99,99 % prometido.

## 5. Qué significan los 200 ms y cómo buscar una ventaja real

Un intervalo de unos 200 ms entre petición y señal observada no demuestra:

- un cooldown de 200 ms;
- una ventana de rebobinado del servidor de 200 ms;
- que acepte cualquier posición durante ese intervalo;
- ni el instante exacto de colisión.

Además, `V17 floor` era un mínimo **configurado en el cliente** de 200 ms. Esa constante debe distinguirse de una medición.

Calibration sirve para formular y contrastar hipótesis. No obtiene por sí sola la implementación privada del servidor ni demuestra una vulnerabilidad por observar una demora.

Pruebas recomendadas, idealmente en una partida privada con un jugador que colabore. Mantén activo únicamente el modo evaluado para evitar mezclar tiro manual, Auto y contacto de una caja local de otro modo:

| Comparación | Mantener fijo | Qué buscar |
|---|---|---|
| Old Hitbox OFF/ON, Burst 1 | Timing, objetivo/movimiento y distancia | Diferencia en rechazos del solver, contactos sintéticos y señales con cuerpo real. |
| Old Burst 1/2/4 | Hitbox, movimiento y timing | Envíos, callbacks de grupo, señales individuales identificables y efectos reales observados. No llamar aceptadas a todas las peticiones. |
| Actual frente a Experimental | Red, configuración temporal y escenas comparables | Error/impactos nuevos, especialmente giros y casos difíciles, sin reutilizar muestras de ajuste para evaluar. |
| Knife Linear frente a Vertical | Cadencia, velocidad usada y modelo de latencia | Saltos/caídas/aterrizajes, error vertical, soluciones rechazadas y proyectiles observados. |
| Variantes de origen Silent | Sweep y resto de parámetros | Qué geometrías producen resultados repetibles. Aparición visual cerca del objetivo no demuestra daño. |

Hay que guardar también oportunidades rechazadas o no confirmadas: acertar solo los casos fáciles y ocultar el resto produciría una comparación engañosa. Para medir instantes autoritativos se necesita instrumentación en un servidor de pruebas propio/autorizado; sus resultados no demostrarían automáticamente que MM2 use las mismas reglas.

No se ha encontrado ni probado una vulnerabilidad nueva en esta entrega.

## 6. Cargar y verificar

Destruct en la instancia anterior:

```lua
getgenv().WURST_BRANCH = "arena/d83a806d-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/d83a806d-arandommenu/src/Wurst.lua?v=" .. tostring(os.time()), true))()
```

Sello esperado: **`v20-20261014-mm2-prediction-profiles`**.

1. Shoot → Prediction → Prediction profile → Old.
2. Comprueba que aparecen Hitbox/Burst; empieza comparando con Burst 1, no activando todo a la vez.
3. Cambia a Actual y Silent: no deben conservar la caja activa ni aplicar Burst.
4. Para la prueba vertical: Knife motion → Vertical (experimental). Cadencia y Sleight siguen siendo opciones independientes.
5. Metrics → Calibration → Detailed MM2 trajectories para capturar trayectorias, y Save calibration al terminar. Cambiar de panel no cambia la grabación.

## 7. Validación y alcance

- Suites MM2 precision, v16, v17, v18 y v19: 44 grupos de compatibilidad.
- Nueva suite v20: **9 grupos** con código real extraído, servicios simulados y casos de UI, caja, grupos, cancelación, error de transporte, aprendizaje y física vertical.
- Analizador: **8 tests**, incluyendo separación de callbacks de grupo y peticiones confirmadas.
- Entity/team provider: 14 comprobaciones.
- **70 fuentes Lua** compiladas con Luau 0.732; bundle de **68 entradas** regenerado/verificado.

No se ejecutó Roblox. No se certifican FPS, apariencia visual, aceptación de cada petición, beneficio de Hitbox/Burst ni tasa de aciertos a partir de estos tests. Los informes v18/v19 permanecen históricos; no se han convertido sus resultados en un supuesto benchmark de v20.
