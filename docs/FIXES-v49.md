# v49 — Aim Assist, valores libres y Spectate independiente

## Aim Assist

Se consultó el AimAssist universal real de VapeV4 (`7GrandDadPGN/VapeV4ForRoblox`, blob `984e0eb167be5551b81f1afc91dd223e3f754377`). Su control es **Speed**, no Smoothing; utiliza movimiento relativo del ratón. Aquí se conserva la implementación de cámara compatible con PC/touch, sin copiar esa dependencia.

- Eliminado **Smoothing** de la interfaz.
- **Speed**: velocidad máxima de giro en grados por segundo; predeterminada 180. Más alto = giro más rápido.
- **Strength**: fuerza de seguimiento, predeterminada 75 %. Más alto = seguimiento más firme, especialmente cerca del objetivo.
- Un valor cero en cualquiera de los dos deja de asistir, sin reescribir la cámara. El rango del slider es solo una guía: se pueden escribir valores mayores.
- Interpolación angular, limitada por Speed, con respuesta exponencial basada en tiempo. Evita el vector nulo entre direcciones opuestas y no depende de contar frames.
- Aimbot sigue siendo el modo de giro inmediato; Speed/Strength pertenecen a Aim Assist.
- Conserva selección, FOV, visibilidad, equipos, predicción y sticky target. Se pausa con el menú, entrada de texto, FreeCam, Spectate o el adaptador de apuntado incompatible, para no pelear por la cámara.

No se afirma que los valores numéricos sean equivalentes a los del ratón de Vape: las unidades y el mecanismo son distintos. Strength es una ampliación propia, no una opción atribuida falsamente a esa referencia.

## Valores numéricos

El control numérico compartido ya **no recorta la entrada escrita ni los valores restaurados de perfiles al Min/Max del slider**. Por ejemplo, Speed acepta 1000, 5000 o `1e12`, aunque la barra siga mostrando un rango práctico de 16–200.

- Arrastrar sigue usando el rango y paso anunciados.
- Escribir, aplicar un perfil y volver a cargarlo conservan el número finito introducido, incluso fuera del rango.
- La posición visual del knob se limita al extremo de la barra, no el valor efectivo.
- Se admite notación científica. `NaN`, infinito y desbordamientos como `1e999` se rechazan sin dañar el último valor válido.
- Los controles de doble valor conservan su entrada libre y el orden inferior/superior.

Esto elimina el límite artificial de la GUI; **no elimina las restricciones nativas de Roblox ni las validaciones semánticas de cada módulo**. Valores extremos pueden causar movimientos bruscos, pérdidas de precisión o problemas de rendimiento; no se promete movimiento aceptado por el servidor.

## Ghost

**Ghost Fly apagado por defecto**, por lo que el comportamiento inicial es Walk. Fly speed solo se muestra al activar Ghost Fly. Una preferencia guardada explícitamente en un perfil se respeta; no se borra la configuración del usuario ni se cambia la mecánica existente de Ghost.

## Spectate

Nuevo módulo **World → Spectate**, separado de FreeCam, incluido tanto en el manifiesto normal como en el fallback del loader.

- Una lista **Player** de selección única, sin el botón incorrecto All / none. Elegir otro jugador reemplaza al anterior; pulsar el seleccionado otra vez lo deselecciona.
- Funciona con FreeCam apagado y utiliza la cámara nativa de Roblox con el Humanoid del jugador como sujeto.
- Con FreeCam encendido, suspende su escritura de cámara, entrada de giro y controles táctiles propios. Guarda su posición/orientación sin mover ese punto de retorno al jugador especteado.
- Deseleccionar o apagar Spectate restaura la cámara anterior: FreeCam vuelve a su punto previo si continúa la misma sesión; en uso normal se restaura la cámara propia/anterior.
- Si el jugador sale, se elimina la selección, se refresca la lista y se vuelve a la cámara anterior. Si muere, se vuelve temporalmente y se espera su respawn mientras siga en el juego.
- Maneja reemplazo de CurrentCamera y respawn local. Si se apaga FreeCam durante Spectate, no deja una cámara Scriptable huérfana. También distingue apagar y volver a encender FreeCam como una sesión nueva.
- Al desactivar, no sobrescribe una cámara que ya tenga otro tipo/sujeto escrito por un propietario posterior. Se liberan los render bindings y servicios al descargar.

FreeCam conserva sus controles de vuelo libre y ya no contiene Spectate Player. World presenta FreeCam y Spectate juntos, en ese orden.

## Markers Touch

- **Touch oculta el menú**, como ItemESP, para buscar una superficie libremente. No caduca a los 20 segundos mientras se busca.
- Al guardar vuelve al menú si estaba visible antes de empezar. Escape o pulsar Touch de nuevo cancela; empezar desde un menú ya oculto no fuerza su apertura al terminar.
- Nombre vacío: `Point 1`, `Point 2`, etc.
- Nombre `hi`: `hi #1`, `hi #2`, etc. Se busca el primer nombre libre, también entre puntos persistidos, sin sobrescribirlos ni cambiar el nombre base del campo.
- Se mantienen el límite de puntos, longitud, coordenadas finitas y selección persistida. Save here y Save coordinates mantienen su guardado explícito por nombre.
- Se limpian la selección y conexiones al descargar sin volver a abrir el menú durante esa limpieza.

## Selectores y blur

- Corregida la regresión de v48: abrir un selector **ya no cambia el blur del menú de 14 a 6**. Mantiene el efecto existente y su visibilidad correcta al abrir/cerrar; no asigna una intensidad distinta.
- Se conserva la transparencia ligera y el borde suave del selector Wurst, sin rediseñar la interfaz.
- ChoiceList y MultiList usan una única función de colocación: **debajo de la ventana completa de ajustes**, no encima del control. Si no cabe debajo, intenta un lateral; como último recurso, arriba. Se limita al viewport, con altura acotada y lista desplazable.
- En controles sin ventana administrada se coloca debajo de la fila completa. Se admite el viewport de cámara como respaldo durante el primer layout.
- Escape cierra los selectores. Se cierran también si el control se mueve/cambia de tamaño, cambia el viewport o deja de ser válido; un refresco de lista cierra su popup para no dejar jugadores/filas obsoletos.
- La selección única se implementa como capacidad compartida de listas, no como parche exclusivo de Spectate.

El BlurEffect de Roblox sigue afectando la escena 3D, **no proporciona blur local detrás de otras interfaces GUI**.

## Verificación

- **35 suites Python/Luau pasan**.
- Aim Assist real: límite angular, Strength, cero, valores grandes, direcciones opuestas, respuesta a 30/60/144 FPS, Aimbot, filtros, arbitraje de cámara y limpieza.
- Cámara real: Spectate independiente, pausa/retorno de FreeCam, entradas de ratón/teclas, selección, muerte/respawn, salida, reemplazo de cámara, respawn local, apagar/reiniciar FreeCam durante Spectate y propietarios posteriores.
- Markers real: menú oculto/restaurado, nombres automáticos sucesivos, ausencia de sobrescritura, cancelación e input GUI ignorado, además de persistencia y coordenadas.
- Geometría compartida extraída del código real: debajo del panel/fila, bordes derecho/izquierdo/superior, pantalla móvil, listas largas y viewport inicial.
- Speed real: WalkSpeed recibe **1000, 5000 y 1e12** sin un segundo recorte en el módulo; conserva restauración y regresiones de sus cinco modos/vehículos.
- Arranque simulado completo del bundle: **`failures=0` y `[HARNESS] done`**. Comprueba valores grandes escritos/restaurados, rechazo de infinito, Ghost Fly por defecto, separación y orden de Spectate, clics reales de selección única y cierre Escape sin pérdida de blur.
- **74 fuentes Lua compilan**. Bundle sincronizado de **72 archivos**, stamp `v49-20261017-controls`.

No se ejecutó Roblox vivo ni se tomó una captura nueva. Las pruebas no sustituyen la comprobación visual en el juego ni garantizan rendimiento, física aceptada por el servidor o compatibilidad con todas las cámaras personalizadas. Nametags, predicción de disparo y sus protecciones no se modificaron.
