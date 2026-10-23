# v50 — Points compartidos, Spectate dentro de FreeCam y movimiento

## Markers

- **Save here** guarda el `x, y, z` del HumanoidRootPart del personaje, no la posición de FreeCam. Un nombre escrito guarda/actualiza ese punto; sin nombre genera `Point N`.
- Selector renombrado **Point**. Eliminado **Remove named place**. Cada fila del selector tiene una **×** pequeña a la derecha para borrar ese punto.
- Seleccionar y borrar usan botones hermanos separados: la × no es parte del botón de selección. Tras borrar se reconstruye la lista si quedan puntos; borrar el último cierra el selector.
- La eliminación actualiza persistencia, selección y dibujos, y notifica a Teleport si tenía ese punto elegido.
- Se conservan Touch, nombres consecutivos (`Point 1`, `Point 2`, `hi #1`, `hi #2`), menú oculto/restaurado y coordenadas manuales. Touch no sobrescribe puntos existentes.
- Se migra la selección antigua Places → Point, manteniendo las coordenadas persistidas por juego. El nombre interno histórico del almacenamiento no se muestra en la interfaz.

## Teleport → Destination: Waypoint

- Eliminado **Save waypoint**, que guardaba una posición separada y temporal.
- **Point** muestra los mismos puntos persistidos de Markers, con selección única y botón **Teleport to point**. La acción principal de Teleport usa la misma selección.
- Lista actualizada al guardar/borrar puntos. Borrar el destino elegido limpia la selección y cancela su viaje en curso.
- Save here/coordenadas conservan su posición de personaje exacta. Los nuevos puntos Touch guardan que son una superficie: al viajar se aplica HipHeight + Height offset para no colocar el root dentro del suelo. Se conservan los puntos antiguos, que no tenían esa metadata.

### Glide

- Sustituido el ambiguo **Glide step** por **Glide speed**, en **studs por segundo**; predeterminado 60.
- Movimiento continuo por Heartbeat y delta de tiempo, sin el antiguo número fijo de 360 pasos ni una distancia por frame dependiente de FPS. Conserva orientación.
- Un viaje nuevo cancela el anterior. También cancelan cambiar Destination, eliminar el punto seleccionado, respawn/reemplazo del root y descargar el módulo.
- Keep momentum OFF elimina velocidades lineal/angular durante el viaje; ON las conserva. Una velocidad cero no inicia un viaje sin fin.
- La actividad explícita de Glide se comunica a Anti Void/Anti fling para no pelear por el movimiento.

No se promete que Glide atraviese restricciones del servidor ni que sea aceptado donde Instant se rechaza.

## Spectate: hijo de FreeCam, independiente de su interruptor

Se corrige la interpretación de v49:

- Ya **no hay una tarjeta independiente Spectate** en World.
- **FreeCam Settings → Spectate → Spectate Player**, con selector de un jugador. El interruptor Spectate funciona **aunque FreeCam esté OFF**.
- Sus conexiones no se registran como limpieza del interruptor principal de FreeCam: apagar FreeCam no apaga accidentalmente Spectate.
- Se mantienen retorno a cámara propia/punto previo de FreeCam, salida del jugador, respawn, cambio de cámara y distinción entre sesiones de FreeCam.
- Se migran estado/selección del Spectate separado de v49. Un sujeto anterior destruido —por ejemplo un Ghost desactivado— devuelve la cámara al Humanoid local actual, no a un sujeto eliminado.
- Spectate.lua queda como controlador interno de esas opciones, no como otra tarjeta visible.

## Ghost Walk real

El problema anterior no era solo el valor por defecto: todas las piezas del ghost estaban ancladas y el modo Walk también escribía su CFrame, manteniendo una altura artificial cuando no encontraba suelo.

- Walk usa ahora un **clon local sin anclar**, con Humanoid, colisiones corporales, AutoRotate, movimiento nativo y gravedad. No hay asignación de CFrame ni ajuste de altura por rayos en la rama Walk.
- **WalkSpeed 16**, **Left Shift mantenido = 32**, al soltar vuelve a 16. Una caja de texto enfocada no activa sprint/movimiento.
- JumpRequest solicita un salto al Humanoid del ghost solo con suelo; no agrega saltos en el aire.
- Animación idle/walk/run/jump/fall propia del ghost. Usa las animaciones de Animate cuando existen, con referencias R6/R15 de respaldo; cachea tracks, no los carga por frame. Un error de permisos de una animación no bloquea el controlador de movimiento.
- **Solo Ghost Fly** ancla el root, desactiva colisiones y permite movimiento CFrame con WASD, Space arriba y Ctrl abajo. Al desactivarlo se restaura la simulación nativa, no un plano 2D.
- El personaje real sigue oculto; no se sustituye LocalPlayer.Character. Se excluye esta actividad intencional de Anti Void/Anti fling. Se limpia el clon, tracks, cámara propia y conexiones; respawn crea un ghost del personaje nuevo, sin llevarlo a una posición vieja.

La física y las animaciones reales requieren comprobación dentro de Roblox: los tests verifican propiedades, llamadas y ausencia de bloqueo de posición, no ejecutan el solver físico de Roblox ni garantizan invisibilidad ante el servidor.

## Anti fling / Anti Void

- **Eliminado el retroceso de CFrame** a una posición anterior. Anti fling ya no compara la magnitud lineal total y, por tanto, no interpreta una caída vertical rápida como un fling.
- Mitigación de impulsos laterales bruscos/giro extremo cerca de otros personajes. Respeta WalkSpeed/Speed configurado y mantiene dirección de movimiento y velocidad descendente. No convierte todos los lanzamientos distantes del juego en ataques de otro jugador.
- Omite asientos, roots anclados, Fly y actividades explícitas Ghost/Teleport/MM2 Fling. Es una heurística local, no protección absoluta contra todas las variantes de fling.
- Anti Void elimina la regla «120 studs por debajo del último suelo». Una caída larga hacia una plataforma inferior ya no crea una plataforma de rescate por esa diferencia de altura.
- Solo interviene en descenso próximo a FallenPartsDestroyHeight y comprueba si hay suelo colisionable antes de esa capa, respetando el grupo de colisión del personaje.
- Un rescate crea una sola plataforma temporal, frena la caída y deja aterrizar al Humanoid sin teletransportarlo ni forzar Landed. Tokens de limpieza evitan que un timer viejo destruya una plataforma nueva tras respawn.

## Inicio silencioso

Eliminada la notificación de **Menu ready / build / versión** al inyectar. Se mantienen avisos de módulos/bibliotecas que no cargan y el error de arranque del menú. Los fallos de una sección de juego también notifican; los logs de diagnóstico de consola no se convierten en popups de éxito.

## Validación

- **38 suites Python/Luau pasan**, incluidas tres nuevas de Ghost, Anti Void/Anti fling e integración Markers–Teleport.
- **74 fuentes Lua compilan**, bundle de **72 archivos** sincronizado con `v50-20261017-points`.
- Ejecución completa con **Luau 0.732**, la versión fijada por el workflow: `failures=0`, `[HARNESS] done`.
- Boot verifica que una inyección correcta no cree ningún Toast, la × del selector nativo realmente borre, Spectate permanezca dentro de FreeCam y Teleport no exponga el antiguo Save waypoint.
- Glide comprobado a 30/60/144 FPS, viajes reemplazados/cancelados, orientación, respawn y limpieza.
- Ghost comprobado sin CFrame de Walk ni recargas de animación por frame; Shift/release, salto/suelo, Fly ↔ Walk, cámara y respawn.
- Anti Void/Anti fling comprobados con salto alto, caída rápida, suelo inferior, contacto, Speed 5000, exclusiones, rescate/timer y limpieza.
- Añadido **`tools/validate.sh`**, el runner que ya invocaba el workflow pero faltaba en el repositorio. Reproduce compilación, suites, verificación de bundle y boot: `LUAU_DIR=/ruta/a/luau bash tools/validate.sh`.

No se ejecutó Roblox vivo ni se hicieron capturas nuevas. Nametags y los cálculos/protecciones de disparo no se modificaron.
