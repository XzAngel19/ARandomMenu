# v172 — Reflejo local del suelo y retiro de Vehicle Speed

## Petición y alcance

El usuario mostró una referencia con luz cálida y un reflejo del avatar y de la
habitación en el piso. Su captura actual es un interior de MM2 con todas las
opciones de Shaders activadas. La reflectancia de vidrio/superficies de v171
solo cambia el reflejo ambiental del motor: **no refleja personas ni la
habitación**. Rain, Snow y Falling leaves se detienen bajo techo, de manera que
esa captura no demuestra por sí sola que la lluvia esté rota. No se dispone de
una prueba visual de Roblox o Delta para confirmar el fallo exacto en vivo.

## Cambios

- Se eliminó **Vehicle Speed** y todo su código, modos y controles de motores y
  asientos. Speed conserva sus modos a pie y Sprint; mientras el jugador está
  sentado no modifica el asiento, la velocidad del vehículo ni el movimiento
  del personaje, y restaura el WalkSpeed que aún controla.
- `Floor reflections` es un toggle independiente, activado inicialmente con
  Shaders. Crea una sola superficie invisible y no física sobre el piso plano
  cercano al personaje, sin volver translúcido el suelo ni alterar su física.
  Un `SurfaceGui` local en `PlayerGui` apunta a esa superficie; un
  `ViewportFrame` muestra copias reflejadas y sanitizadas del avatar, personas
  cercanas y parte del entorno. La proyección fuera de eje adapta las fórmulas
  MIT de ViewportStencil y rbx-viewport-window; fuentes y licencias completas
  en `third-party/shaders/README.md`. Se conservan prendas clásicas cuando son
  accesibles, con Humanoid nuevo, sin copiar scripts ni joints del original.
- Es una **aproximación local**, no SSR, ReShade, RTX ni un reflejo perfecto.
  Solo cubre una zona cercana del piso; necesita una parte sólida, anclada y
  casi horizontal bajo el avatar. Se omiten Terrain, pendientes fuertes,
  piezas pequeñas y partes transparentes o no ancladas. Si la geometría de una
  malla no llena su bounding box puede verse un borde artificial. Las piezas
  simétricas se reflejan mejor; mallas asimétricas, ropa en capas, luces,
  sombras, materiales y texturas pueden diferir. No se reproducen todas las
  piezas de la habitación ni se garantiza el resultado de la captura.
- La corrección de color es un poco más cálida y el umbral del bloom se ajusta
  para que pueda afectar objetos claros. El polvo se genera en un volumen menor,
  con partículas algo más visibles; permanece activo en interiores. Los demás
  toggles siguen siendo independientes, sin Look, modos ni presets.
- El reflejo se retira completamente al apagar su toggle o Shaders; si falla
  el montaje, la proyección o la copia del avatar se avisa sin apagar las demás
  opciones. Las copias se limpian al cambiar de personaje o perder el suelo;
  al desactivar también se destruyen la escena y sus conexiones.

## Límites de trabajo, no mediciones de FPS

Una superficie de hasta 24 × 20 studs; un sondeo de piso cada 0,20 s; una
consulta de hasta 100 piezas cada 2 s en radio 32; hasta tres personajes, 24
partes del local, 36 partes de personajes en total y 18 piezas del entorno
(máximo 54 partes copiadas). Se crean hasta tres copias de partes por tick y se
actualizan las poses hasta 30 Hz. La dimensión mayor del canvas es 512 píxeles;
el viewport se oculta con la cámara demasiado lejos, bajo el piso, fuera del
ángulo permitido o con la superficie detrás de ella. Son límites de código:
renderizar otro `ViewportFrame`, las sombras, los assets y las partículas sí
pueden costar GPU/memoria y provocar lag, especialmente en móvil.

El clima mantiene hasta 13 emisores y 112 partículas nuevas por segundo con
todo activo; sigue haciendo las comprobaciones escalonadas de techo. El sistema
de texturas y reflectancia ambiental conserva sus propios límites de v171.

## Pruebas

- `tools/test_speed_modes.py`: cinco modos a pie, restauración al sentarse,
  salida del asiento, ausencia de controles de vehículo y cero escrituras en
  asiento/vehículo (mocks).
- `tools/test_shader_reflection.py`: álgebra de la proyección y reflejos con
  CFrame/Vector3 simulados, límites, ropa clásica sanitizada, cámara, piso
  inclinado, movimiento, respawn, caída de suelo, fallos parciales y cleanup.
- `tools/test_shaders.py`: opción y ciclo de vida independientes, efectos,
  lluvia con techo, polvo en interior y aislamiento de fallos; más las pruebas
  anteriores de iluminación, assets, Fog, clima y superficies.
- `tools/validate.sh`: 86 fuentes compiladas, 112 suites, bundle de 84
  fuentes/14 assets separados, boots simulados sin fallos, menú 50/49. No
  renderiza píxeles ni mide GPU/FPS.

Falta la prueba visual en Roblox/Delta: activar `Render > Shaders` y comprobar
`Floor reflections` en tercera persona, sobre una superficie plana y sólida,
con calidad gráfica suficiente; comparar con el toggle apagado. Probar lluvia y
nieve en exterior. Si no se aprecia, observar avisos de Shaders y guardar una
captura con mapa, calidad gráfica y dispositivo. No se afirma que el resultado
sea idéntico a la referencia, que el cliente soporte la técnica, ni que el
rendimiento sea aceptable sin medirlo.
