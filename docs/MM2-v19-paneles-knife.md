# MM2 v19 — Shoot/Metrics organizados, Throw continuo y nueva evidencia

> Histórico de v19. La rama entrega ahora [v21: selector local rápido, red inestable y menú ligero](MM2-v21-fast-projections.md).

Build: **`v19-20261014-mm2-panels-knife`**. Rama: `arena/d83a806d-arandommenu`.

## 1. Shoot: Mode separado de Target

La tarjeta queda así:

```text
Shoot
  Mode     [Prediction | Silent AIM]
  Target   [Murder | Custom]
  Target player [...]              solo cuando Target = Custom
  ...opciones del modo elegido...
```

- **Prediction:** WallCheck, Motion model, Gun timing, Landing guard, Hold uncertain manual shots, Auto tune lead, Lead bias, Motion Hz, Lead status y Reset auto lead correction.
- **Silent AIM:** Silent sweep, Silent spawn y Spawn A/B status.
- **Compartidos:** Mode, Target, Macro, Shoot diagnostics y Shoot status.

No hay un segundo interruptor SilentAIM que contradiga Mode. Cambiar el modo o esconder Target player no borra preferencias ni el nombre escrito.

Silent sigue usando el solver compartido: los parámetros configurados en Prediction permanecen aplicados aunque sus controles estén ocultos. Este cambio organiza la interfaz, no sustituye silenciosamente el algoritmo de puntería.

Auto Shoot también muestra **Prediction / Silent AIM**, conservando su selector independiente, el Target de Shoot y su filtro Max error.

### Perfiles anteriores

Migración de una sola vez:

- `Shoot.Mode = Manual/Custom` pasa a `Target = Murder/Custom`.
- El antiguo booleano `SilentAIM` determina el nuevo Mode, salvo que ya exista una selección nueva válida.
- Target player y el resto de valores se conservan.
- Auto Shoot traduce Normal/Silent a Prediction/Silent AIM sin cambiar su significado.

## 2. Metrics: elegir un panel

```text
Metrics
  Mode [Calibration | Game learning | Projectiles]
```

Solo aparecen los controles del panel seleccionado. El selector se comparte entre módulos y también funciona si MM2 se detecta por estructura después de cargar las utilidades universales.

**Elegir un panel no activa o desactiva grabación por sí solo.** En Game learning se usa `Game learning observer` para comenzar/parar. Las preferencias de otros paneles se conservan; un observador ya encendido sigue encendido al cambiar de vista. Así cambiar la interfaz no corta una tanda de datos ni cambia ajustes de predicción ocultamente.

Learning de capturas de pantalla es una utilidad independiente; no se confunde con Game learning.

## 3. Knife: se elimina el segundo fijo obligatorio

Los 38 throws authored de tu sesión principal v18 guardaron **Fire delay = 1 s**, Normal, 60 Hz. El intervalo mínimo observado fue **1,001 s**, mediana **1,183 s**. Había una pausa larga entre tandas; esa pausa no se interpreta como cooldown.

Ahora existe **Throw cadence**:

| Modo | Intervalo elegido |
|---|---|
| Auto, con atributo válido | `ThrowCooldown` o `ThrowDelay` del arma |
| Auto, sin atributo, sin Sleight detectado | 0,50 s de fallback |
| Auto, sin atributo, con Sleight detectado | 0,25 s de fallback |
| Manual | Tu Fire delay guardado, entre 0,1 y 3 s |

- **Auto es el default nuevo.** El 1 s guardado no lo limita; permanece disponible en Manual.
- Fire delay solo se muestra en Manual.
- Sleight se consulta en atributos/datos de rol y objetos etiquetados `Perk` del personaje o PlayerGui, como los que usa el PerkSystem recuperado.
- Un atributo explícito válido tiene prioridad; no se divide otra vez un cooldown que podría estar ya ajustado.
- Se sigue comprobando Murderer, arma equipada, Enabled/Disabled, objetivo, visibilidad e intercepción.
- No hay espera de animación antes del envío, ni recuperación de frames perdidos con una ráfaga de remotos.
- `Throw prediction status` muestra el intervalo, su procedencia y el estado de animación. Cada intento guarda cadence, fireDelay efectivo, manualFireDelay, cadenceSource y sleight.

**0,50/0,25 son una política de fallback del cliente, no cooldowns del servidor demostrados.** La documentación disponible dice que Sleight permite lanzar más rápido, pero no contiene aquí una implementación autoritativa del cooldown. El estado real del arma puede imponer una espera mayor. Si muestra `normal fallback` teniendo Sleight equipado, esa lectura identifica un fallo de detección que debe corregirse; no debe presentarse como Sleight activo.

## 4. Animación: cambios concretos

Antes se elegía el primer Animation cuyo nombre contenía `throw` y se ejecutaba Play en cada envío. Eso podía seleccionar una pista de carga/idle, reiniciar una pista anterior o superponerse a una nativa. No existía la nueva limpieza específica de unequip/death.

Ahora:

1. Selección determinista de nombres de release conocidos: ThrowRelease, KnifeThrow o Throw, con variantes R6/R15. Charge/Idle/Equip no se eligen por mera coincidencia de texto.
2. Caché por arma y humanoide; no se recorren todos los descendientes en cada lanzamiento. Una animación añadida al arma invalida la caché.
3. Si la misma animación nativa ya está reproduciéndose, no se añade una copia encima.
4. Una sola pista propia, sin loop, con velocidad adaptada al intervalo y a Sleight.
5. Se libera la pista propia antes del siguiente ciclo. Un identificador de reproducción impide que un temporizador viejo corte un throw nuevo.
6. Limpieza al desactivar, desequipar, morir o reaparecer. No se paran indiscriminadamente las animaciones del juego.
7. Un error cosmético no cancela ni demora el envío.

Si no se reconoce una animación de release, el estado lo indica y no reproduce una pista arbitraria. La selección/lifecycle se probaron con servicios simulados; falta confirmar el aspecto visual de cada arma dentro de Roblox.

## 5. Qué dicen los nuevos JSON

Snapshot estudiado: [TestingStuff `6779e0d`](https://github.com/XzAngel19/TestingStuff/tree/6779e0d2ed88b7dec2b6b2d12de654e323319d04).

Se inventariaron **10 JSON, 8 datasets únicos**. Los tres backups antiguos idénticos se cuentan una vez. Se preservan separados los lugares y las sesiones; el historial anterior no se convierte en evidencia nueva.

La captura principal contiene **202 eventos y 2.090 puntos de trayectoria**. También se analizó el backup MM2 de Place 636649648 (**50 eventos / 138 puntos**), separado de Place 142823291. El histórico único conserva sus 206 eventos / 2.150 puntos. El [resultado reproducible](audits/MM2-v19-json-results.json) incluye hashes, cohortes y estadísticas.

### Shoot de la sesión principal

| Auto tune lead | Envíos authored | Señales correlacionadas | Señales con parte del objetivo | Sin confirmar |
|---|---:|---:|---:|---:|
| OFF | 7 | 2 | 0 | 5 |
| ON | 38 | 16 | 7 | 22 |

Total: **45 envíos del menú**, todos Normal / Classic 66d / RTT. Hay además 3 activaciones nativas sin confirmar: 48 intentos totales, 18 señales correlacionadas y 30 sin confirmar.

Game Learning principal conserva **93 registros: 48 Gun, 38 Knife y 7 Stab**, y reporta los mismos 7 impactos en el objetivo. Es otra representación del mismo puente de eventos, **no siete impactos adicionales**.

Otros hallazgos:

- **75 de 130 comprobaciones** del solver se detuvieron por `A wall blocks the shot`. Son bloqueos de WallCheck, no misses enviados ni 75 tiros rechazados por el servidor. Mode ahora hace más clara esta distinción.
- Ningún envío authored fue Silent; esta tanda no mide su tasa de impactos.
- En ON hubo **10 peticiones con ping bruto superior a 300 ms**, máximo **507,1 ms**; en OFF ninguna, máximo 204,6 ms. El estimador todavía tiene el límite heredado de 300 ms. No se cambia ese límite dentro de una actualización de interfaz/cadencia sin una comparación controlada.
- ON/OFF tienen tamaños y condiciones distintos: 7 frente a 38, con cambios de red/objetivo/ronda. Los siete impactos con ON son una observación favorable, **no prueba de que activar la opción causara todos ellos**.
- V18 no guardaba la corrección automática aplicada por intento. La opción ON no prueba que el aprendiz llegara a ajustar: exige al menos seis muestras y otros filtros. En seis de las siete ventanas de calibración con hit hay menos de seis puntos hasta la señal; esas ventanas no son idénticas al sampler del tuner, pero exponen por qué no se debe asumir aprendizaje efectivo.
- V19 añade **`settings.prediction.autoLeadCorrection`**: en los siguientes registros se podrá distinguir «opción encendida» de «corrección realmente aplicada». No se redujo a ciegas el filtro del aprendiz.

### Knife y captura en otro lugar

Principal: **38 authored, 11 proyectiles observados, 27 sin confirmar y 13 señales ambiguas**. No son 11 bajas. Más frecuencia tampoco vuelve autoritativa la asociación por handle; con throws solapados seguirá habiendo observaciones ambiguas que no entrenan.

Encontré otro defecto en la sesión de Place **636649648**: MM2 se había activado por detección estructural, pero Game Learning decidía si era MM2 únicamente por PlaceId. Su archivo mezcla **118 registros genéricos sin kind/eventSource y 10 observaciones Knife**. No se interpreta como 128 throws distintos.

Se corrigió esa condición: Game Learning sigue ahora la detección activa de MM2, incluso si se resuelve después de inicializarse. Evita tratar como un juego genérico una sesión con el puente MM2 activo. El analizador también reconoce esos datasets por su tipo explícito, sin mezclarlos con la sesión principal.

### Coste observado

La captura principal informa **54,03 ms para 887.847 bytes** en el guardado previo. Ese dato es relevante para posibles tirones; no es el FPS ni mide todo el coste del menú. Si estás jugando normalmente, puedes apagar MM2 automatic saves y guardar manualmente al terminar la tanda. Cambiar de panel Metrics no apaga un autosave ya activado.

## 6. Cargar y comprobar

Destruct en la instancia anterior, luego:

```lua
getgenv().WURST_BRANCH = "arena/d83a806d-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/d83a806d-arandommenu/src/Wurst.lua?v=" .. tostring(os.time()), true))()
```

Sello esperado: **`v19-20261014-mm2-panels-knife`**.

Prueba corta:

1. Shoot: alterna Prediction/Silent AIM; Target sigue independiente. Custom muestra el nombre y Murder lo oculta sin borrarlo.
2. Metrics: elige Game learning; solo sus controles deben quedar visibles. Usa su observer para grabar.
3. Knife: principal y Knife Throw ON, Throw cadence Auto, Throw animation ON. Consulta Throw prediction status con y sin Sleight; debe explicar la fuente del intervalo.
4. Desequipa, vuelve a equipar, apaga/enciende y prueba tras respawn. No deberían acumularse pistas propias ni quedar callbacks antiguos cortando el nuevo throw.
5. Si quieres comparar con el intervalo anterior, selecciona Manual: conserva el Fire delay guardado.

## 7. Validación

- **44 grupos MM2**: 14 precision + 4 v16 + 12 v17 + 7 v18 + 7 v19.
- **7 tests del analizador**: incluye cohortes ON/OFF y separación de lugares detectados como MM2.
- **14 comprobaciones de entity/team provider**.
- **70 fuentes Lua** compiladas con Luau 0.732; bundle de **68 entradas** y sello v19 consistente.
- Tests nuevos ejecutan el código de la UI completa de Shoot, migración, paneles Metrics, detección de perks, scheduler y reproducción/limpieza de animaciones con mocks.
- No se ejecutó Roblox ni se certifica una tasa de aciertos, cooldown del servidor o apariencia visual a partir de esos tests.

Reproducir el análisis:

```bash
python3 tools/analyze_mm2_json.py --data /ruta/TestingStuff \
  --snapshot 6779e0d2ed88b7dec2b6b2d12de654e323319d04 \
  --output /ruta/resultados-v19.json
LUAU=/ruta/luau python3 tools/test_mm2_v19.py
```
