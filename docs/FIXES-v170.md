# v170 — Shaders simplificado, clima y transición de Auto Farm

## Shaders

- `Render > Shaders` muestra **Look**, **Weather**, **Fog** y **Advanced**.
  El valor predeterminado de Look es `Photoreal`; las configuraciones existentes
  conservan sus looks anteriores si estaban guardados. Weather empieza en
  `Clear` y Fog apagado. `Advanced` despliega todos los sliders, tint y Diagnose
  anteriores, con las mismas claves de configuración.
- Cuatro grados (`Photoreal`, `Golden Hour`, `Blue Hour`, `Overcast`) adaptan
  valores reales del proyecto MIT de HathuwstAlkan. Conservan ColorCorrection,
  Bloom y SunRays de Roblox, límites contra brillo/tinte negros y los efectos
  propios del juego. No se cambia tecnología gráfica, cielo, hora o geometría.
  No son RTX, ReShade ni una copia literal del motor original.
- Weather ofrece `Rain`, `Snow` y `Autumn`. Hay cuatro partes invisibles y sin
  colisión/consulta/toque, un emisor por parte, centradas alrededor de la cámara.
  Se actualizan como máximo 20 veces/s y los raycasts de techo se escalonan a
  uno cada 0,15 s como máximo, con salida segura ante ausencia/cambio de cámara.
  Tasas totales elegidas: 60 gotas/s, 28 copos/s o 12 hojas/s; `Clear` no crea
  celdas, conexión ni descarga. No es una medición de FPS o coste GPU.
- Se incorporaron los tres PNG requeridos para los efectos (72.807 bytes en
  total), reduciendo la textura de lluvia. Descarga y caché son diferidas a la
  primera selección; hay fallbacks si el executor no proporciona archivos,
  red o `getcustomasset`. Una descarga que termina tarde no puede reactivar ni
  modificar otro clima ya elegido. Los créditos, commits fijados y licencias
  MIT, ISC y CC0 están en `docs/third-party/shaders/`.
- Fog usa una `Atmosphere` ya existente cuando existe; si no, crea una temporal.
  No destruye la del juego y restaura los valores del juego que aún son los
  aplicados por el menú. La llegada o sustitución de una atmósfera se trata por
  eventos. Si otro script escribe exactamente el mismo valor, no se puede
  distinguir su escritura de la nuestra.

## Auto Farm / scheduler

- Reproducción sobre el módulo real en el harness: tras `CoinCollected(50/50)`,
  si el personaje desaparecía y llegaba otro mapa antes de un tick válido en
  lobby, la bolsa llena de la ronda anterior sobrevivía. El estado mostraba
  `full bag (50/50)` en el mapa nuevo; apagar/encender lo eliminaba. No hay
  evidencia de que esta sea la única causa del síntoma observado en vivo.
- Se reinician bolsa, reintentos, posición de origen y caché local al cambiar
  de mapa o recibir `RoundEndFade`, incluso sin personaje. `RoundStart`, un
  mapa nuevo o una salida observada permiten iniciar la siguiente ronda. No se
  borra una bolsa llena solo por reaparecer en el **mismo** mapa y ronda. Un
  reporte de moneda que llega antes del primer tick del nuevo mapa se conserva.
- Las acciones opcionales de bolsa llena conservan su orden, pero una secuencia
  que quedó esperando se cancela al apagar o al cambiar de ronda; la acción
  Silent mantiene `wallCheck = false`. La secuencia comprueba el lobby con una
  referencia cacheada y revisa el mapa al cambiar de personaje, incluso si
  despierta antes de Heartbeat. El controlador pre-física suelta colisiones y
  velocidad al detectar un traslado grande del mismo personaje, sin devolverlo
  a un origen antiguo en el lobby.
- En pruebas con el Fling real, una cancelación a mitad de SkidFling todavía
  aplicaba varias poses y devolvía al personaje al CFrame de la ronda anterior.
  Ahora comprueba la cancelación entre poses, limpia el impulso y el pin, y
  Auto Farm solicita no devolver un cuerpo trasladado o nuevo. El uso normal de
  Fling y el retorno explícito de Auto Win mantienen su comportamiento. Sin
  un evento o una referencia de lobby/mapa identificable no hay garantía total.
- El scheduler antes desconectaba una tarea tras **tres fallos acumulados** en
  toda su vida, incluso separados por muchos ticks correctos. Ahora los fallos
  consecutivos se ponen a cero tras un tick correcto; tres fallos seguidos aún
  detienen la tarea. La relación de este defecto con el caso en vivo no está
  demostrada.

## Pruebas y límites

`bash tools/validate.sh`: 85 fuentes Luau, 111 suites, bundle de 83 fuentes,
9 assets descargables, boot con `failures=0`, 90 llamadas cruzadas y menú
50/49. Los tests usan el Framework, módulo de Shaders, AssetManager y Auto Farm
reales con servicios simulados: restauración de efectos ajenos, fallo/caché de
PNG, techos, cambios rápidos, pérdida de cámara, mapas y rondas, lobby, modos
Walk/Below y acciones opcionales de bolsa llena. No son una prueba gráfica,
una medición de rendimiento, una comprobación del servidor ni una prueba de
Delta/Roblox. Los techos se muestrean por celda, no ocluyen cada gota de forma
perfecta. La calidad gráfica, el motor o el executor pueden omitir efectos o
texturas. La auditoría integral de todos los módulos continúa pendiente.
