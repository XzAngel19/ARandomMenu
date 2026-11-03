# v173 — Shaders en más superficies, sincronización de atajos y Speed

## Qué se investigó

El usuario vio el reflejo en MM2, pero muy tenue, y el suelo más blanco. En
v172 la textura usaba un tinte mezclado 55 % hacia blanco, la iluminación
subía la exposición 0,12 y fijaba la luz difusa a un mínimo de 0,65. Estas son
causas plausibles de blanqueamiento en el código; las capturas no permiten
atribuir el resultado a una sola de ellas. Además, solo se retenían superficies
en radio de 120 studs y el espejo cubría un parche de 24 × 20 studs.

Se revisaron el hilo de Fog y el Rain Plugin enlazados por el usuario. El
plugin de buildthomas es Apache-2.0; fuentes, aviso, licencia y detalle de la
implementación separada están en `third-party/shaders/README.md`.

## Cambios

- La base de iluminación ya no aumenta la exposición ni la luz difusa. Las
  texturas usan el color original de la pieza sin mezclarlo hacia blanco y son
  más transparentes; bloom y corrección también se moderaron. No se modifican
  materiales físicos, colisiones ni transparencia del suelo original.
- El barrido de las superficies visita el mapa progresivamente y no elimina
  una mejora porque el jugador se aleje. Detecta piezas transmitidas, prioriza
  el suelo visible y restaura los cambios propios. Su cobertura sigue limitada
  a piezas compatibles y por los presupuestos descritos abajo.
- `Floor reflections` usa `ImageTransparency=0,12` en vez de 0,46 y amplía el
  piso principal a su tamaño hasta 256 × 256 studs. El barrido descubre otros
  pisos compatibles; hasta dos se muestran con viewports adicionales, según la
  cámara, con sus propios planos y copias. La escena principal sigue al avatar
  para no consultar solo el centro de un piso grande. No son reflejos de toda
  la escena: hay selección, culling, límites y diferencias de apariencia.
- Fog añade sprites de niebla a `Atmosphere`, manteniendo restauración
  condicional y funcionamiento independiente. Rain/Snow/hojas comparten nueve
  celdas con pruebas escalonadas de techo. Las exteriores próximas pueden
  seguir activas cuando la cámara está bajo un techo pequeño; Rain también
  intenta pequeñas salpicaduras al encontrar suelo. Las demás opciones se
  mantuvieron individuales, sin `Look` ni presets.
- Al accionar una tecla, el `Navigator` abierto no repintaba su baldosa aunque
  la tarjeta principal, el estado del módulo y la hacklist sí cambiaran. Se
  reprodujo en el arranque simulado y se conecta el repintado al mismo cambio
  que usa la tarjeta. El test acciona señales reales de teclado y clic; no se
  ha confirmado si el usuario observó exactamente esa misma ruta en Roblox.
- `Speed` usa `Velocity` como opción inicial en configuraciones nuevas. Una
  elección guardada, por ejemplo `WalkSpeed`, se conserva. Speed a pie y Sprint
  permanecen; Vehicle Speed sigue retirado.

## Presupuestos y limitaciones

- Hasta 20 nodos y cuatro partes procesadas por tick, 600 texturas, 1.200
  cambios de reflectancia y 600 pisos candidatos; se avisa al llegar a un
  límite. Las piezas incompatibles y las que excedan esos límites no reciben el
  efecto. El recorrido puede tardar, y un mapa en streaming solo tiene lo que
  el cliente recibió.
- Hasta tres `ViewportFrame`, con 54 copias en el principal y 32 en cada uno
  adicional. Hasta tres creaciones de partes y 32 comprobaciones de candidatos
  por tick; poses principal/adicional hasta 30/15 Hz en PC y 20/10 Hz en móvil
  cuando son visibles. Tamaño efectivo máximo del render principal 1.024/768 px
  y adicionales 512/384 en PC/móvil. Se sondea el piso a 0,2 s y hasta 100
  objetos de escena cada 2 s.
- No hay SSR, RTX ni acceso al framebuffer original. Los viewports no renderizan
  Terrain y tienen limitaciones de ropa, materiales, sombras y mallas. El piso
  principal necesita un suelo anclado casi horizontal; los otros dos no hacen
  que todas las piezas del mapa sean espejos simultáneamente.
- Con todos los climas activos: hasta 30 emisores y 187 partículas/s, más hasta
  una salpicadura por muestra de techo abierta, aproximadamente 6,7/s. La prueba
  por celda es una aproximación y puede fallar en bordes y techos grandes.
- Estos son límites de diseño, no mediciones de FPS, GPU, memoria ni latencia.
  Tres viewports, sombras y partículas pueden causar lag en móvil.

## Pruebas y pendientes

Validación final: `bash tools/validate.sh` PASS; 86 fuentes compiladas,
113 suites Python/Luau, 84 fuentes y 14 assets en el inventario, arranque del
bundle con `failures=0` y auditoría de menú 50/49.

`tools/test_shader_reflection.py` prueba geometría, limpieza, dos pisos
adicionales, streaming, errores, integración real entre el barrido y la
biblioteca y presupuestos móviles con mocks matemáticos. `tools/test_shaders.py`
comprueba los diez toggles, rayos/techo, Fog con partículas, lluvia exterior,
rollback, assets, recorridos distantes y topes en un mundo simulado grande.
`tools/test_keybind_visual_sync.py` acciona el atajo, el clic, la hacklist y
Navigator y favoritos con Speed y Fullbright; prueba además el modo por defecto
y uno guardado de Speed, y el Sprint con ambos modos. Ninguna suite renderiza
píxeles ni prueba físicamente Roblox/Delta.

Pendiente: prueba real en MM2/Delta con calidad gráfica y dispositivo conocidos;
comparar Shaders ON/OFF, después Floor reflections ON/OFF, probar Fog solo y
Rain cerca de una salida, y observar FPS. Pedir una captura si sigue blanco o
el reflejo no se distingue. No se promete una cobertura universal ni seguridad
frente a anticheat.
