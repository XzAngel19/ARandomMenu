# v38 — Menú sin controles duplicados y Knife Throw por preset

Stamp: `v38-20261016-simple-presets`.

## Shoot

- Eliminado Shoot now y su shortcut adicional. El keybind principal de Shoot
  sigue llamando a la misma acción manual (incluido autoequip explícito).
- Auto Shoot sigue siendo una opción, no otro módulo ni otro botón de disparo.
- WallCheck se oculta en Silent AIM, donde no tiene efecto. Se conserva para
  Prediction; los controles exclusivos de Silent conservan su gate de modo.

## Knife Throw: un solo interruptor

Eliminados de la UI y de sus rutas configurables: Throw now, Mode, Silent,
Fire delay, Throw Range, Spawn offset, WallCheck, Throw animation y Throw Hz.
Los valores antiguos guardados para esos controles ya no se leen.

El preset hace lo siguiente:

- Solo usa el cuchillo que el usuario tiene equipado; respeta arma deshabilitada
  y master Knife OFF. No autoequipa ni inventa un origen junto al objetivo.
- Elige automáticamente al jugador válido visible más cercano. Sin radio de
  usuario ni el antiguo horizonte de 4 segundos que imponía otro límite de
  distancia indirecto a la intercepción. Se mantienen las guardas finitas.
- WallCheck obligatorio: visibilidad del cuerpo presente y trayectoria futura
  libre, preservando el lead del proyectil (no se copia el fallback hitscan).
- Animación siempre activa: preparación, release y recuperación. Un solo paquete
  por ciclo; la animación sigue ocupada hasta recuperar, no solo hasta release.
- Intenta otro ciclo en el siguiente frame disponible, sin Fire delay adicional.
  Eso significa repetir lanzamientos completos, no reiniciar el brazo o enviar
  una ráfaga de remotes en el mismo frame. El servidor conserva sus reglas.
- Reelige objetivo, origen y aim al release. Si el primero cierra el peek durante
  la preparación, puede usar el siguiente visible en vez de conservarlo oculto.
- OFF, unequip y respawn cancelan/restauran la pose y el paquete pendiente.
- La opción tiene su propio KEY configurable; no necesita Throw now duplicado.

Aura Range se conserva porque controla otra función (stab/Knife Aura), pero
solo se muestra cuando Knife Aura está activado.

## Disguise en Utilities

El archivo ya existía, pero no estaba en Manifest.universal: nunca se cargaba.
Se añadió al manifiesto, se corrigieron categoría del módulo/mapa/orden y se
verifica que realmente aparezca en Utilities en el boot completo.

Sus acciones para el avatar de un usuario (movimiento y lista de emotes) solo
se muestran en Character, no en el modo de bundle Animation. La acción de
copiar movimiento no modifica el personaje con Disguise OFF o modo equivocado.
No se eliminan cosméticos, emotes ni restauración de avatar aceptados antes.

## Revisión adicional

- Auditoría de todas las filas de opciones renderizadas: no se permiten nombres
  de fila duplicados dentro de un mismo módulo.
- Corregida una integración real de Spider: addNumberOption devuelve la FILA,
  pero addToggleOption devuelve el BOTÓN. Ocultar el parent del slider estaba
  ocultando el contenedor completo, no solo Impulse interval. Ahora cada regla
  oculta su fila correcta y mantiene los tres controles específicos por modo.
- No se borran funciones distintas simplemente porque ambas tengan un keybind.
  El retiro de acciones duplicadas se aplica a Shoot/Knife según lo solicitado;
  acciones como High Jump o Teleport no son equivalentes a activar su módulo.

## Verificación

- 18 suites Python/Luau, incluyendo un nuevo test del módulo KnifeThrow completo
  (selección + predictor + pose + scheduler + packet), no solo de funciones mock.
  El entorno físico/servicios sí son mocks, no Roblox real.
- Ese test cubre retarget al release, objetivo a 2000 studs, ciclo no interrumpido,
  repetición sin pausa extra, arma deshabilitada, master OFF, respawn y cleanup.
- Se mantienen pruebas matriciales de poses R6/R15, predicción, visibilidad,
  Shoot/Auto, Sprint, Jump, Freeze, FPS, apariencias y UI.
- Boot completo: failures=0, Disguise cargado en Utilities, ausencia de los
  controles retirados, shortcut principal de Shoot conservado, filas por modo,
  auditoría de duplicados y regresiones de RShift/Calibration.
- 77 fuentes compiladas, bundle de 68 fuentes regenerado/verificado y
  `git diff --check`. Baseline de predicción archivado sin cambios.

No se afirma una prueba online, accuracy medida ni fidelidad visual confirmada
con dispositivo móvil real. El modelo base de intercepción sigue siendo el
actual; no se añade una fórmula nueva como parte de limpiar la configuración.
