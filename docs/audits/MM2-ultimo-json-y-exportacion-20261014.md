# Último JSON de TestingStuff y diagnóstico del RBXL

**Revisión consultada:** [`TestingStuff@b3fc3bcfd3a64a8f97824d50ba8fa0576cc18a71`](https://github.com/XzAngel19/TestingStuff/commit/b3fc3bcfd3a64a8f97824d50ba8fa0576cc18a71). Subida: 14/10/2026, 06:35:03 UTC / 01:35:03 Lima.

Este cambio modifica solamente `Place_142823291_Game_Learning.json`. No actualiza el mapa ni `MM2_Trajectory_Calibration.json`. No se ha cambiado el runtime para elaborar este informe.

## 1. El archivo RBXL es legible: el fallo es recuperar el código

Volví a leer los chunks del archivo binario y sus propiedades `Source`. Resultado:

| Clase | `decompilation panicked` | `failed to get script bytecode` | Otro |
|---|---:|---:|---:|
| Script | 5 | 21 | 1 README del serializador |
| ModuleScript | 158 | 0 | 0 |
| LocalScript | 107 | 0 | 0 |
| **Total** | **270** | **21** | **1** |

Hay 292 campos Source, pero ninguno de los 291 correspondientes a scripts del juego contiene código recuperado utilizable. El único texto distinto es el README añadido por el serializador.

Ejemplo exacto en `WeaponService`:

```lua
-- Saved with DexRESerializer (https://github.com/Tesker-103/DexRecontinued/)

-- decompilation panicked
```

`GunBeams` y `ThrowingKnifeVisuals` también contienen el mensaje de panic. Los otros fallos dicen:

```lua
-- failed to get script bytecode
```

### Qué significa cada error

- **`decompilation panicked`:** la herramienta encargada de reconstruir texto desde bytecode informó un fallo interno. No es un diagnóstico de sintaxis de WeaponService y no incluye una línea original o stack trace con el que identificar la causa interna exacta.
- **`failed to get script bytecode`:** no consiguió recuperar el bytecode de ese script. Los 21 casos de este archivo son objetos de clase Script. Eso es compatible con limitaciones de acceso a scripts de servidor, pero el mensaje por sí solo no prueba una causa única para cada objeto.
- **No hay un error de lectura del contenedor RBXL:** se han podido extraer las propiedades. El contenido que falta no está escondido detrás de una extensión incorrecta: fue sustituido por esos comentarios al exportar.

El README guardado dentro del propio archivo registra:

```text
Decompile = true
DecompileTimeout = 10
MaxThreads = 3
SaveBytecode = false
SaveScriptCache = false
Binary = true
Mode = full
```

Por tanto, **no fue simplemente que desactivaras Decompile**. Tampoco hay evidencia para afirmar que todo falló por el timeout: los mensajes guardados dicen panic/bytecode, no timeout.

Como comprobación adicional, el código público actual del serializador, [`DexRecontinued@649010f`](https://github.com/Tesker-103/DexRecontinued/blob/649010f94ebbf1e8f6fb6978ca4c872032916eb7/Serializer.lua), delega en una función `decompile` proporcionada por el entorno y guarda su texto de salida. El commit exacto de la herramienta usada para exportar tu archivo no está identificado; no se asume que fuera esa revisión actual. Cambiar únicamente el serializador no garantiza arreglar el descompilador externo.

### Lo que no arregla esto

- Renombrar `.rbxl` a `.rbxlx`.
- Abrir el archivo exportado y volverlo a guardar.
- Subir el timeout si el problema real es un panic o falta de bytecode.
- Activar un caché cuando no existe ninguna recuperación válida que guardar.
- Usar `Mode = full`: significa el alcance que intenta guardar la herramienta, no acceso al código privado del servidor.

## 2. Cómo entregar una copia útil

### Si tienes acceso de edición al proyecto original

1. Abre el proyecto original en Roblox Studio con una cuenta autorizada, en edición, no solo la copia exportada por el cliente.
2. Comprueba que puedes abrir los scripts y ver funciones reales. En particular, los módulos de armas, sus dependencias y sus controladores de cliente/servidor.
3. Guarda o descarga una copia local desde Studio (`Save to File` / `Download a Copy`, según la interfaz).
4. Puedes enviarla como **`.rbxl`** o **`.rbxlx`**. Ambos formatos sirven; `.rbxlx` facilita inspecciones textuales, pero no mejora la disponibilidad del código.
5. Alternativamente, envía las fuentes `.lua`/`.luau` en un ZIP, conservando sus rutas de Explorer y señalando qué es Script, LocalScript o ModuleScript.
6. Incluye dependencias utilizadas por esos scripts; un nombre de remoto o un módulo aislado no muestra todas las validaciones de servidor.
7. Omite secretos, claves y datos privados que no sean necesarios.

**Prueba de calidad antes de subir:** abrir `WeaponService` y varios scripts importantes. Si solo aparece `decompilation panicked`, `failed to get script bytecode`, un comentario genérico o contenido vacío, todavía no es una copia con fuentes utilizables.

### Si solo dispones del juego ejecutándose como cliente

El cliente no recibe toda la implementación del servidor. En particular, el contenido de servicios exclusivos del servidor y el código fuente de scripts de servidor no se obtienen por guardar las instancias visibles en el cliente. Ningún cambio de formato convierte eso en un proyecto completo.

Incluso una descompilación exitosa de código que sí está disponible en el cliente es una reconstrucción: puede perder comentarios, nombres y estructura. No equivale al proyecto fuente original ni permite demostrar todas las reglas de validación del servidor.

Para diagnosticar el fallo de tu herramienta en código que tienes autorización para inspeccionar hacen falta:

- Nombre y versión del serializador/exportador y del entorno que proporciona la descompilación.
- Mensaje completo de consola al fallar un único script, no solo el comentario final.
- Si falla también con un script de prueba sencillo de un proyecto propio, o únicamente con estos módulos.
- Si una versión compatible devuelve código válido en esa prueba mínima.

No se necesita ninguna contraseña o token. Si no existe acceso autorizado al proyecto fuente, el análisis tendrá que limitarse a lo observable, fuentes disponibles y pruebas controladas; no se puede prometer acceso a “cada pieza” del servidor.

## 3. Qué significa realmente el contador de tiros

El último archivo contiene:

```text
aggregates.shots = 1317
#shots = 300
```

**1317 no es el número de tiros de la última sesión ni necesariamente tiros de arma.**

En [GameLearning de la versión publicada](https://github.com/XzAngel19/ARandomMenu/blob/0aec767e9c0f32e69fa5f298a6c33be00c473d64/src/games/universal/Other/GameLearning.lua):

1. `loadStoredLogs()` recupera `aggregates` del archivo anterior: el contador es histórico.
2. `observeContainer()` observa cualquier Tool; `observeTool()` registra `Tool.Activated` sin exigir que sea un arma.
3. `finalizeShot()` incrementa `aggregates.shots` para esos registros y recorta el detalle a `maxEvents = 300`.
4. También existe la ruta de disparos autorados por el bridge. Sin un identificador compartido de acción/disparo no se puede deduplicar rigurosamente ambas rutas.

Es perfectamente posible que un Teddy incremente `shots`. En el último bloque eso ocurre 64 veces. Incluso se le asignan nueve resultados `miss`, lo que demuestra que esa etiqueta no representa exclusivamente fallos de pistola.

**No hay base para atribuir este 1317 al doble conteo del writer MM2 que se corrigió en v15:** este es otro archivo, producido por el módulo universal Game Learning, que no se modificó en aquel parche. El problema demostrado aquí es la mezcla de activaciones, historial y denominadores, además del riesgo de doble registro por rutas distintas.

Tampoco es correcto restar `1317 - 191` y decir que hubo 1126 tiros nuevos desde la subida anterior. Comparando ambos archivos, no comparten registros detallados idénticos, y algunos acumulados disminuyen —por ejemplo teleports 28→20—. No es una continuación simple verificable del archivo anterior.

## 4. Aislamiento de lo último, sin mezclarlo con versiones antiguas

El bloque final identificable en `shots` tiene:

- **78 registros**, al final del array.
- IDs **1–78** consecutivos y `clockAt` creciente.
- Hora **14/10/2026, 01:08:29–01:24:05, Lima**.
- Archivo guardado a las **01:34:03, Lima**.

El reinicio de IDs permite separar este bloque de los anteriores, pero **no sustituye un sessionId real**. No hay sello de build ni versión por registro. Se trata del bloque final reconstruible, no de una prueba inequívoca de que se ejecutó v15 durante todo él.

### Composición del bloque final

| Herramienta | Registros | `kind = gun` | Etiquetados `miss` | Sin outcome |
|---|---:|---:|---:|---:|
| Gun | **14** | **7** | **7** | **7** |
| Teddy | **64** | 0 | **9** | **55** |
| **Total** | **78** | **7** | **16** | **62** |

Los 14 registros Gun se dividen en:

- 7 con `kind = gun`: seis marcados miss y uno sin outcome.
- 7 sin kind: uno marcado miss y seis sin outcome.

**No se debe interpretar como 50 % de precisión ni 0 % de precisión.** Un registro sin outcome no equivale a un acierto. Un miss se asigna mediante una heurística de escena/muerte, no por un acuse negativo del servidor. Tampoco todos los registros representan disparos únicos confirmados.

En este bloque final:

- **No hay Knife.** No se reutilizan los registros de Knife de las 23:44–23:45 del día anterior en Lima para evaluar “lo último”.
- **No hay registros con silentSpawn.** No se puede calcular aquí una comparación Front/Through.
- El acumulado `Front 0/5` pertenece a registros antiguos del archivo, del 12 de octubre UTC, no a este bloque final.
- **No hay kills atribuidos dentro del bloque final.** Esto no acredita que el servidor rechazara todos los tiros ni permite asignar una tasa fiable.
- Ping de los **14 registros Gun**: mínimo **134,889 ms**, mediana **152,296 ms**, máximo **171,110 ms**. La mediana de todo el bloque es mayor, pero está dominada por Teddy y no debe sustituir esta medida de Gun.

## 5. Los tres últimos registros

Todos tienen tiempo de pared 01:24:05 Lima, pero el reloj de alta resolución los distingue:

| ID | Origen de registro indicado por el JSON | Resultado guardado | Observaciones de escena |
|---|---|---|---|
| 76 | Gun, sin kind | Sin outcome | Un jugador observado; LOS `blocked`; ángulo 37,9° |
| 77 | Gun, `kind = gun` | `miss` | Un jugador observado; LOS `blocked`; ángulo 6° |
| 78 | Gun, `kind = gun` | `miss` | Un jugador observado; LOS `clear`; ángulo 5,5° |

Separación temporal:

- 76→77: **237,407 ms**.
- 77→78: **147,538 ms**.

Esto podría contener registros de distintas fases/acciones, pero sin shotId y confirmación del arma no se puede decidir cuántos paquetes únicos aceptó el servidor. **No se han eliminado como duplicados por proximidad temporal.** No son copias JSON idénticas.

En 77/78 el endpoint está aproximadamente a **4,24 / 4,09 studs** de la raíz observada. **Eso no es automáticamente error de puntería**: el punto puede estar adelantado deliberadamente. El JSON no incluye la trayectoria futura ni el instante autoritativo del impacto necesarios para comprobar si el lead fue correcto. Tampoco la LOS calculada por el logger prueba cuál fue la validación del servidor.

## 6. Otros defectos de medición confirmados al leer el código

- `session.startedAt` se escribe con `os.time()` al guardar, por lo que en este archivo coincide con `savedAt`; no indica realmente cuándo comenzó la sesión.
- No hay `buildStamp`, `sessionId`, ajustes efectivos ni un identificador de disparo común entre activación, autoría y confirmación.
- El bridge MM2 envía `targetName`, pero Game Learning intenta extraer `info.target` como Instance. Esa incompatibilidad deja sin nombre objetivo muchos registros autorados y dificulta atribuir sus resultados.
- El insight que afirma que hubo impactos verificados por hitbox ampliado no demuestra eso. El contador `hitboxKills` usa heurísticas como cuchillo a más de cinco studs o una separación de cabeza grande. No observa directamente una expansión aceptada por el servidor.
- Los insights sobre ausencia de validación de paredes tampoco deben tratarse como una lectura del código del servidor. Son inferencias a partir de atribución de muertes y raycasts locales.

El JSON nuevo es útil para detectar estos problemas, pero **no permite certificar la precisión real de Shoot/Knife ni las reglas internas del servidor**.

## 7. Qué hace falta para la siguiente verificación

### Ahora, sin perder los datos existentes

1. Conservar una copia del JSON actual.
2. Capturar el sello de build que muestra el loader y los ajustes efectivos.
3. Si se hace una prueba nueva, usar un historial de prueba separado o el control de limpiar logs solo después del respaldo. Evitar activar Teddy/otros toys durante esa tanda.
4. Subir también el **`MM2_Trajectory_Calibration.json` actualizado**. El último commit no lo cambió: sigue siendo el archivo antiguo, no la calibración de esta tanda.
5. Registrar unos intentos controlados por modo, anotando qué ocurrió realmente, junto con ping y frame time.

### Corrección necesaria del registrador, no aplicada en este informe

- Separar `toolActivations`, intentos de gun, throws y stabs.
- Identificar armas, sin convertir todo Tool en arma.
- Crear `sessionId`, `buildStamp` y shotId correlacionable.
- Guardar ajustes, modo y targetName con un contrato consistente.
- Separar intento, rechazo local, envío, confirmación y resultado observado.
- Distinguir contadores de sesión de contadores históricos.
- No presentar heurísticas de muerte como validación autoritativa de hitbox/paredes.

**Conclusión:** el RBXL no permite estudiar el código porque la exportación guardó errores de descompilación en vez de fuentes; el último JSON no contiene 1317 tiros nuevos, sino un contador histórico de registros heterogéneos. Lo último identificable son 78 registros, de los que 64 son Teddy y 14 Gun. Antes de seguir afinando el solver con esas cifras, hay que separar correctamente los eventos y obtener una captura de sesión identificada.
