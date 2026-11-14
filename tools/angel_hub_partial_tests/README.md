# Angel Hub: pruebas parciales

Estas pruebas simulan Roblox; no verifican el comportamiento en el juego, la aceptación del servidor ni la compatibilidad con ejecutores.

Cubren arranque PC/móvil y fuera de MM2; Speed, Rise, X-Ray, Anti AFK, Get Gun, teletransportes y Gun/Trap ESP; Auto Farm Walk/Below, lobby, Safe Zone, bolsa, avance/atasco y contadores que se pausan y se reanudan; Coins Aura y Knife Aura; Gun Aura y Auto Get Gun, con restauración condicional y restricción de mapa; reproducción y catálogo local de emotes, sin duplicados ni animaciones predeterminadas; Coin ESP con señales de monedas y limpieza; avisos de roles/ronda, proximidad y respuestas tardías; Air Walk y Fly Velocity PC/móvil, Walk Fling, Player Pointers, Chams, Nametags y HP Players; Auto Vote; Auto Shoot Bullet/CFrame básico; Auto Win parcial con plataforma, regreso, contadores por VictoryScreen, ataques Murder/Sheriff y limpieza; marcadores, listas dinámicas, teletransporte y Glide; y Auto Unbox con catálogo/precios y saldo simulados, bloqueo de llamadas simultáneas y espera de respuestas.

Para contar victorias se usan los tres primeros argumentos de `Remotes.Gameplay.VictoryScreen` y las combinaciones de rol/resultado que aparecen en `GameplayAnimations` del volcado XML de TestingStuff, blob `755f47708dfbe83a5eaad25d5a60a5a36788dcf6`. Se ignoran resultados desconocidos o recibidos mientras Auto Win está apagado, y se evita contar dos veces la misma ronda. Esto no confirma que las señales o el comportamiento actual del servidor sigan iguales.

Auto Win tiene la plataforma, la opción Sheriff básica y una adaptación experimental de Murder basada en AutoWin/Knife Aura: usa la Knife local, mueve temporalmente la raíz del objetivo y solicita HandleTouched (o touch). Restaura los valores condicionalmente incluso al cancelar o finalizar ronda, y limita los intentos; no se conoce el contrato del servidor ni se garantiza un impacto o victoria. Ambas opciones Fling siguen bloqueadas. La plataforma puede quedarse creada si retirarla dejaría al personaje en el vacío. El disparo usa predicción sencilla y Auto Win Sheriff tiene WallCheck independiente, desactivado por defecto. Experimental y Gun Aimbot siguen pendientes.

Auto Unbox gasta la moneda seleccionada. `Auto` no elige Gems ni llaves; solamente compra cuando puede leer la caja, el precio y el saldo. Por defecto no reproduce animación. Tras una respuesta incierta o una compra, espera que el saldo se actualice antes de otra solicitud. El servidor puede aplicar otras condiciones y una solicitud ya enviada no se puede cancelar.

```sh
npm install --prefix /tmp/angel-test-deps @luau-rs/luau@0.739.0
node tools/angel_hub_partial_tests/run.cjs
```

Gun Aura mueve localmente la pieza de GunDrop dentro del radio seleccionado y restaura su estado cuando puede; Auto Get Gun solo solicita touch, sin teletransportar. Ambos dependen de `firetouchinterest` y de que la detección del mapa/objeto coincida con MM2: ni la recogida ni el alcance están garantizados por el servidor.

Get All Emotes añade entradas al perfil local, utilizando el catálogo disponible además de siete animaciones conocidas; no concede propiedad en el servidor. Play Emote solicita el BindableEvent del juego o reproduce una animación local: permisos, GUI legacy y replicación no están verificados.

Coin ESP marca las piezas de recogida detectadas dentro del mapa, filtra por familia y usa `CoinsStarted` cuando está disponible. Los avisos de roles y colores utilizan `GetCurrentPlayerData` y eventos cliente cuando existen; si esos datos no llegan no se garantiza identificar roles. La desaparición de un jugador no se trata como prueba de muerte.

Air Walk usa una plataforma local; Space sube y Control baja en PC, con botones en móvil. Se bloquea su uso simultáneo con Auto Farm, Auto Win y Noclip. Chams y Nametags usan los colores/filtros de rol disponibles; `Chams Show Perk` y `Self HP` siguen bloqueados. Estas rutas están probadas con mocks, no en partidas Roblox.

Los marcadores se guardan por PlaceId dentro de la configuración del menú: hay que usar Save o Autoload para conservarlos. Se pueden guardar desde el personaje, coordenadas o un punto pulsado, seleccionar y borrar. Teleport ofrece tap, jugador cercano o por nombre, objeto, waypoint y posición anterior, con Instant y Glide; los viajes se cancelan al cambiar destino o iniciar Auto Farm, Auto Win o Air Walk. Los controles y eventos se han probado con mocks, no en Roblox.

## Inventario del menú MM2

Se cuentan los controles `addModule` del menú MM2, incluidas las cuatro opciones de Auto Win, pero no sus sliders, ciclos, toggles auxiliares ni botones. Hay **49** controles: **44 con alguna lógica conectada** y **5 bloqueados**. Esto no significa que los 44 estén completos: Auto Farm, Auto Win, sus ataques, Auto Shoot, Fly, Speed, Chams y Zoom tienen modos u opciones pendientes, y ninguno se ha verificado en Roblox.

Los 5 bloqueados son: Gun Aimbot, Auto Fling Selected Target, Fling Sheriff And Get Gun, Fling Murder If Dead y Disguise Character.

Además hay 26 botones: 21 conectados y 5 pendientes (Kill All, Fling Murderer, Fling Sheriff, Fling All Innocents y Fling). Hay 25 opciones auxiliares expresamente bloqueadas; pueden existir otras opciones sin efecto bajo módulos pendientes. La prueba `run.cjs` comprueba el inventario para evitar desactualizarlo sin revisar.

Fly admite solo método y flotación Velocity, desplazamiento del humanoide, teclas configurables y botones móviles, velocidades, respuesta, WallCheck y orientación opcional. Otros métodos y flotaciones están bloqueados. Walk Fling usa pulso fijo de 30000 basado en la referencia, restaura velocidad/colisiones y nunca se activa desde una configuración guardada; su efecto real y seguridad dependen de las físicas del juego. Player Pointers muestra indicadores de dirección/distancia, respeta rango, equipo y colores disponibles. Todo sigue sin prueba en Roblox.

Chams usa los colores de rol compartidos para relleno y contorno; sin rol conocido usa blanco, o el color del equipo fuera de MM2 si está activado. La caja de Nametags mide 200 × 30 y conserva el control existente de tamaño de texto.

Calibration y sus controles se retiraron temporalmente. La tecla de menú predeterminada RightShift se acepta aunque Roblox marque la entrada procesada; se ignora al escribir y se respeta la captura de keybinds. Auto Blurt y Blurt Roles solicitan envío al chat público, con demora, roles invertidos opcionales y repetición opcional al cambiar; solo usan roles disponibles mientras el jugador está en el mapa. El módulo no se activa por configuración guardada. Puede haber filtrado o rate limits, una solicitud ya enviada no se puede cancelar y la recepción no está garantizada. Pruebas con mocks, no en Roblox.

Player ESP usa cajas Corner/Full, relleno, esqueletos R6/R15, trazadores, distancia, equipos y roles; la visibilidad oscurece el color si el raycast detecta un obstáculo. Se proyecta el bounding box completo y se oculta cuando cruza el plano cercano o sale de pantalla. Requiere comprobar calidad y rendimiento en partidas.

Player Shield e Impact Shield usan pares NoCollisionConstraint locales, sin cambiar CanCollide global ni editar partes ajenas. La protección de impactos evita herramientas normales, piezas ancladas, soporte y vehículos mientras el humanoide está sentado; se limita a objetos rápidos cercanos y suspende el escaneo/damping apropiadamente. Walk Fling suspende las protecciones. La física y efectos en servidor no están garantizados.

Wall Crawl adapta los modos Velocity, Impulse y CFrame de la referencia, requiere movimiento hacia una pared vertical, limita el impulso y comprueba techo para CFrame. Se bloquea frente a Farm, Auto Win, Fly, Air Walk, Air Swim y Walk Fling.

Air Swim usa voxeles locales de agua y solo transforma celdas Air con ocupación 0. Al mover, sentarse, apagar o descargar intenta restaurar únicamente las celdas que siguen siendo agua con ocupación 1; preserva agua preexistente y otras modificaciones que se puedan distinguir. No puede distinguir una modificación externa idéntica en la misma celda, ni garantizar restauración si el acceso a Terrain falla o se interrumpe el cliente. Puede afectar el entorno local: probar con cuidado. Todos estos cambios están probados solo con mocks.

Auto Knife Throw requiere rol local Murderer y roles detectados en el mapa, equipa Knife cuando encuentra un candidato y espera antes de solicitar `Knife.Events.KnifeThrown`. Selecciona por tiempo de vuelo, usa una predicción básica limitada y comprueba siempre que el cuerpo actual sea visible; WallCheck adicional verifica el trayecto al punto predicho. No intercepta los lanzamientos manuales ni implementa Knife Tracer o el predictor completo. No se garantiza que el servidor acepte el lanzamiento o que impacte. Auto Win y Auto Knife Throw no se ejecutan simultáneamente.

FreeCam incluye WASD/flechas, Q/E o Space/Control, cámara con clic derecho en PC y joystick, ascenso/descenso y giro táctil en móvil. Spectate sigue al jugador seleccionado desde la lista dinámica. Al desactivar o descargar intenta restaurar el tipo, posición y foco de la cámara y el estado previo de controles; no se activa desde configuración guardada. El soporte para gamepad no está implementado; el menú mantiene bloqueos frente a automatizaciones de movimiento. Self HP es independiente de HP Players y admite posición y escala. Probados con mocks, no en Roblox.
