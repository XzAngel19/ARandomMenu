# v47 — controles de salto y organización del menú

## Infinite Jump Fall

- La pulsación inicial desde el suelo se deja al Humanoid de Roblox: salto y animación normales, con su JumpPower habitual.
- Solo una nueva pulsación en el aire aplica el impulso adicional. En Fall ese impulso usa el estado local Freefall, incluso con velocidad Y positiva, conservando X/Z.
- Se debe soltar y volver a pulsar Space / ButtonA / el botón táctil. Las solicitudes repetidas mientras se mantiene pulsado no producen más saltos. En táctil se identifica el dedo del salto cuando está disponible para que soltar otro dedo no reactive el salto.
- El bloqueo local de Jumping se adquiere únicamente después de un salto adicional Fall, no durante el primer salto. Al aterrizar se restauran los flags previos; también al cambiar de modo, desactivar, morir, reaparecer o entrar en estados incompatibles.
- Normal mantiene el mismo control por pulsaciones. Rise sigue siendo el modo explícito de mantener para subir. Auto jump sigue siendo una opción separada, apagada por defecto.
- No se cargan/reproducen animaciones manuales por frame. Animate recibe el cambio de estado nativo y conserva sus propias transiciones.

**No se afirma que sea indetectable.** El estado local y SetStateEnabled no garantizan la interpretación del servidor; la velocidad y posición ascendentes siguen siendo observables.

## Spider

Eliminados Spiderman, Ceiling Walk, la adhesión y toda la rotación del cuerpo. Quedan tres modos:

- Velocity: velocidad vertical continua al empujar una pared.
- Impulse: impulsos temporizados y acotados, sin acelerar indefinidamente.
- CFrame: pasos verticales con delta limitado y comprobación de espacio superior.

Se exige una pared vertical cercana y movimiento dirigido hacia ella. No actúa sentado, muerto o anclado. Respeta el grupo de colisión. La opción Climb state libera el estado que adquirió al dejar la pared, dejar de moverse, desactivar o cambiar de modo/personaje.

## Ámbito y opciones

- **Fling eliminado de universal** y de su manifiesto/fallback. El archivo reside ahora en `src/games/MM2/Blatant/Fling.lua`, se carga solo con MM2 y registra la tarjeta como `MM2.Fling`, en el registro MM2. La descripción ya no afirma funcionar en cualquier juego. Al descargar, la ejecución deja de aplicar impulsos; no se teletransporta un personaje nuevo a la posición de uno anterior ni se desancla un root ajeno.
- **Anti fling dentro de Anti Void**. Comparte su ciclo de vida, con Velocity limit visible cuando se marca la opción. La posición segura no se conserva entre personajes. Se omite durante una acción explícita de MM2 Fling.
- **Time Changer dentro de Fullbright**. Time/Fast time dependen de esa opción. Fullbright solo no cambia la hora. Desmarcar Time Changer restaura la hora; desactivar el módulo restaura únicamente propiedades que todavía conservan su última escritura, respetando cambios externos.
- **Spectate Player debajo de los controles de FreeCam**. Selección de un jugador, seguimiento con cámara libre orbital, giro por ratón/touch. Se resuelve el personaje vivo cada frame para soportar respawn. Deseleccionar vuelve al vuelo libre; salir conserva la restauración de cámara/controles ya existente.

Anti fling y Time Changer requieren que su módulo padre esté encendido. Se retiraron sus tarjetas/archivos independientes y se compactaron los órdenes de presentación.

## Notificaciones

- Las tarjetas ya no muestran toasts genéricos de enabled/disabled ni de acción ejecutada. El propio control refleja el resultado; los errores siguen notificándose.

- Cargar/reaplicar Disguise correctamente, incluido tras respawn, actualiza el estado de la tarjeta; no muestra un toast de éxito. Los errores de carga/copia/emotes y las consultas explícitas siguen disponibles.
- Los rechazos habituales de Shoot (pared, recarga, objetivo no disponible, protección) actualizan el estado, sin popup. Una excepción real de ejecución sigue notificándose. Un envío manual exitoso limpia el estado anterior. No se relajaron WallCheck, la protección de jugadores ni la predicción.
- Añadir objetos a ItemESP, cancelar la selección, limpiar su lista, guardar un waypoint de Teleport o vincular un arma usan estado en vez de mensajes de éxito rutinarios.
- Se mantienen errores e instrucciones necesarias de acciones explícitas, además de información solicitada deliberadamente (por ejemplo listas de emotes/calibración).
- El notificador compartido descarta mensajes consecutivos idénticos durante tres segundos para evitar ráfagas repetidas.

## Markers — Waypoints sin escribir coordenadas

Módulo Render nuevo **Markers**:

1. Escribir un nombre como Home o Exit.
2. Pulsar **Save here** para guardar la posición actual; el mismo nombre actualiza el punto.
3. Activar/desactivar puntos en **Places**.
4. Para borrar, escribir su nombre y pulsar **Remove named place**.

Las posiciones se guardan con la configuración, separadas por PlaceId; necesitan la capacidad de escritura del executor para persistir entre sesiones. **Manual coordinates** es opcional y está oculto por defecto, con formato `x, y, z`, validación y límite de 128 puntos por lugar. Se toleran datos de configuración inválidos. Es un marcador visual, no otro teletransporte.

## Nametags y colores

Se inspeccionaron los fuentes reales de VapeV4ForRoblox:

- `src/games/universal - base/Render/NameTags.lua`, blob `71b960462244dc2b1fd3a14f2455571273876219`: una línea compacta, fondo negro semitransparente, margen pequeño, distancia opcional en corchetes, sin tarjeta redondeada ni borde decorativo.
- `src/games/universal - base/Render/Waypoints.lua`, blob `a3033eb3666578f43196d8d1192461fca35ecd17`: marcadores de posición con nombre; el original codifica coordenadas y nombre en texto. Markers sustituye esa entrada habitual por Save here.

Referencia: https://github.com/7GrandDadPGN/VapeV4ForRoblox

Nametags usa ahora una sola línea de 14 px por defecto, sin segunda fila, esquinas redondeadas, borde ni sombra de texto. Fondo negro al 50 %. Cuenta, rol, herramienta y distancia siguen siendo opciones; **distancia y rol apagados por defecto**. La distancia, si se activa, aparece como `[123]`, sin el sufijo studs. Se mantienen medición/cache de texto, Unicode literal sin interpretar HTML y liberación fuera de pantalla.

El color base por defecto de PlayerESP, Chams (relleno/contorno), Arrows, NPCESP, ItemESP, Nametags y Markers es verde **#55FF55**. Los colores de equipo/rol, la semántica de HP y los colores personalizados guardados no se sobrescriben. Los valores por defecto se aplican a opciones no configuradas; un perfil que ya guardó distancia/colores mantiene su elección.

Es una aproximación deliberadamente simple al estilo Vape, no una afirmación de igualdad visual pixel a pixel en un cliente vivo.

## Verificación

- **31 suites** Python/Luau sin fallos.
- Pruebas del Jump real: primer salto nativo, mantener sin repetir, pulsaciones adicionales, Freefall ascendente, dedo táctil ajeno, aterrizaje, flags inicialmente falsos, Normal/Rise, respawn y limpieza.
- Nuevas pruebas de Markers (persistencia, límites de formato, coordenadas opcionales, eliminación y separación por PlaceId), Fullbright/Time Changer, Anti Void/Anti fling y notificación/estado de Disguise.
- Pruebas de cámara incluyen Spectate y conservan las comprobaciones de teclado/touch, controles, reemplazo de cámara y limpieza.
- Pruebas de render verifican el nametag plano de una línea y distancia opcional, junto con roles, paletas independientes, Unicode, cache y HP.
- Full boot del bundle con `failures=0` y `[HARNESS] done`: verifica ámbito MM2 de Fling, ausencia de tarjetas retiradas, opciones agrupadas, visibilidad y Save here con controles de lista reales.
- **73 fuentes Lua compiladas**. Bundle de **71 archivos** sincronizado con stamp `v47-20261017-menu` y con el loader.

No se ejecutó Roblox vivo. Las pruebas no prueban evasión del servidor, compatibilidad con todos los scripts Animate ni un resultado visual exacto en cada resolución/rig.
