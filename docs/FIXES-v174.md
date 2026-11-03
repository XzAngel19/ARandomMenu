# v174 — Estado visual en MM2, escala y detalle del reflejo

## Contexto y diagnóstico

El usuario reportó que, después de v173, seguía viendo desacuerdos entre la
HackList y las tarjetas de MM2, que el menú se achicaba y que Shaders se veía
menos. La prueba anterior ejercitaba el Navigator con Speed y Fullbright, pero
no cubría el estado de la tarjeta MM2 ni operaciones que cedieran el hilo.

Se reprodujeron con el bundle y señales simuladas tres casos distintos:

- Una tecla asignada pintaba el cuadrado verde incluso si el módulo estaba OFF.
  En la captura la fila de Shaders se ve gris: el verde de su tecla no demuestra
  que Shaders estuviese encendido.
- El estado se guardaba antes de repintar la tarjeta. Si la escritura del
  executor cedía, la HackList podía observar el estado nuevo mientras la tarjeta
  seguía con el color anterior. También se simuló una activación/restauración
  que cede y termina después de una tecla posterior.
- Un cambio de `ViewportSize` no avisaba al escalado cuando el modo y la altura
  de tarjeta no cambiaban. Una cámara temporalmente 0×0 podía además reducir la
  escala al mínimo. Esto reproduce un defecto de código, no confirma por sí solo
  la causa concreta del tamaño de la captura.

El menú abierto aplica su propio `WurstBlur` de tamaño 14, independiente de
Shaders. Por tanto, el desenfoque de la captura no prueba que Shaders esté roto;
para comparar visualmente hay que cerrar el menú.

## Cambios

- Las tarjetas, el cuadro de tecla, favoritos y Navigator se repintan al iniciar
  el cambio, antes de una activación o escritura que pueda ceder. Ante error se
  revierte el indicador. Una generación evita que una activación o restauración
  anterior reescriba el estado visual/configuración tras una tecla más reciente.
  La letra indica asignación; el cuadrado solo usa el color de activación cuando
  el módulo está ON y los conflictos conservan su color de advertencia. Al
  cambiar o borrar una asignación se actualizan ambos extremos de un conflicto.
- **Gun Aimbot conserva su excepción**: su tecla intenta disparar/equipar Gun,
  no alterna el módulo. Las pruebas no cambian ese callback.
- El último viewport válido se conserva durante cambios de cámara. Cuando la
  cámara nueva obtiene dimensiones válidas se actualiza la escala aunque el
  modo/alto de tarjeta no cambien; las posiciones no se reclampan con 0×0.
  `UI.MenuScale` guardado sigue respetándose, sin resetearlo.
- En v173 el reflejo principal pasó de un parche de hasta 24 studs con canvas
  512 a una superficie de hasta 256 con canvas 1024. Sobre un piso cuadrado
  grande, el máximo teórico pasó de ~21,3 a 4 px/stud antes de la reducción
  fuera de eje. Eso podía disminuir el detalle del avatar, aunque no demuestra
  el aspecto real de la captura.
- El espejo principal usa ahora hasta 64×64 studs para detalle cercano. Para un
  piso más grande se reserva uno de los dos viewports adicionales para cubrir
  hasta 256×256 de ese piso; queda uno para otro piso visible. En un piso pequeño
  pueden seguir seleccionándose dos pisos adicionales. Si falla la reserva de
  la capa amplia y no existe una para ese piso, el plano principal vuelve al
  tamaño amplio, con menor detalle. La pieza original no se vuelve translúcida,
  ni se aumenta exposición/difusión o se mezcla su textura hacia blanco.
- No se cambiaron Fog, Rain, Snow, los demás toggles independientes, ni Speed
  (Velocity por defecto y modo guardado conservado). No hay Look ni presets.

## Límites

Máximo tres viewports, 54 copias principales y 32 por adicional; hasta tres
creaciones y 32 comprobaciones por tick, con los límites de resolución y
frecuencia móvil de v173. En un piso grande donde antes había un solo viewport,
la capa de detalle puede agregar otro y costar más GPU/memoria, aunque el máximo
simultáneo no aumenta. La capa amplia usa una resolución menor y solo refleja
una parte de la escena cercana. No es RTX/SSR ni cubre todos los pisos, Terrain,
ropa y geometrías. La superposición y el rendimiento no se han visto en Roblox.

Las pruebas de activación y escrituras que ceden verifican el estado visual y
el estado de configuración en memoria, no que Delta ejecute esas rutas igual ni
el orden físico de escrituras simultáneas. La generación no cancela por sí misma
los efectos internos de un callback antiguo que haya cedido. No se promete FPS,
seguridad anticheat ni un resultado visual determinado.

## Pruebas

- `tools/test_mm2_ui_keybinds.py`: Gun Aura y Shaders reales del bundle, tecla y
  clic, HackList, conflictos, fallo/activación lenta, escrituras suspendidas en
  orden inverso y callback manual de Gun Aimbot (mocks).
- `tools/test_mm2_restore_keybind.py`: restauración ON suspendida seguida de una
  tecla OFF; su finalización no debe reactivar la tarjeta ni el estado guardado
  en memoria (mock).
- `tools/test_mm2_menu_scale.py`: viewport redimensionado, cámara reemplazada,
  0×0 al arrancar y durante el cambio, desconexión de la cámara anterior,
  preferencias guardadas y cambio manual durante la transición (mocks).
- `tools/test_shader_reflection.py`: álgebra, detalles de un piso grande y de
  uno estrecho, capa amplia, otro piso, movimiento, salida del piso, fallo de
  reserva y límites móviles; no dibuja píxeles.
- `bash tools/validate.sh`: 86 fuentes compiladas, 116 suites Python/Luau,
  inventario 84 fuentes/14 assets, arranque simulado `failures=0`, menú 50/49.

Pendiente: probar v174 en MM2/Delta. Con el menú cerrado, comparar Shaders ON/OFF
y Floor reflections ON/OFF en tercera persona sobre un piso sólido; comprobar
que tarjeta y HackList coinciden con la tecla y el clic y observar FPS. Si sigue
fallando, recoger mapa, plataforma/calidad y capturas o video de ambos estados.
