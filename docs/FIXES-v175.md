# v175 — Recuperación de Shaders en el cliente

## Contexto

El usuario informó que en v174 el reflejo del suelo, las texturas, el vidrio,
Fog, Rain, Snow y otros efectos no funcionaban o no se veían correctamente en
su cliente. Las pruebas offline de v174 no dibujaban píxeles: no demuestran la
causa concreta de ese reporte ni la apariencia en Roblox/Delta.

Se revisaron las referencias solicitadas de [FogEnd](https://create.roblox.com/docs/reference/engine/classes/Lighting#FogEnd)
y [creación de shaders](https://devforum.roblox.com/t/how-can-i-create-a-shader/3154598),
la documentación del motor y proyectos abiertos. En `docs/third-party/shaders/`
están las fuentes, commits y licencias: se adapta la proyección MIT de
ViewportStencil/EgoMoose, se usan imágenes CC0 y se inspeccionó Rain Apache-2.0.
El plugin Rain completo no se incorpora ni ejecuta. No se añade Look ni presets.

## Cambios

- **Independencia:** cada postproceso se crea por separado; un fallo no debe
  apagar los demás. Rain/Snow/hojas, así como polvo, niebla y salpicaduras, se
  crean por separado y limpian sus recursos si fallan. Si ningún emisor puede
  crearse no queda una tarea de clima vacía. Los efectos se siguen aplicando
  localmente, sin modificar la física del mapa.
- **Fog:** si el juego tiene `Atmosphere`, se reutiliza (Density mínima 0,45,
  Haze mínimo 1,25). Si no, se usan `FogStart`, `FogEnd` y `FogColor` de
  Lighting (FogEnd máximo 180). Roblox ignora FogEnd cuando hay Atmosphere.
  Los cambios del juego se observan y se restablece el último valor conocido al
  apagar si el valor actual sigue siendo el del módulo. Cambios que escriban
  exactamente el mismo valor no se distinguen. La niebla incluye partículas
  locales, pero no es volumétrica real.
- **Rain/Snow:** nueve celdas siguen la cámara y comprueban techo de manera
  escalonada. Si una comprobación o `RaycastParams` falla, los emisores siguen
  visibles con un aviso: pueden atravesar techos. Rain intenta salpicaduras
  independientes. Assets descargados que no informan precarga exitosa se
  sustituyen por el fallback, que tampoco garantiza renderizado.
- **Surface textures:** las imágenes de color CC0 se resuelven y precargan
  asíncronamente; si no se informa éxito se conserva el intento con los ID
  oficiales. Las URI locales usan preferentemente `Texture.Texture`, por un
  reporte comunitario de fallo silencioso de `ColorMapContent`. No se asume que
  un resultado de precarga exitoso pruebe píxeles. Se admiten piezas bloque y
  uniones CSG ancladas compatibles; un decal existente reserva su propia cara,
  no toda la pieza. Se excluyen mallas, variantes, apariencias especiales,
  personajes y herramientas. No se cambian material físico ni geometría.
- **Glass:** `Reflectance` mínima 0,36 para vidrio y ventanas transparentes
  compatibles, incluidos paneles finos de nombre genérico y vidrio móvil fuera
  de personajes/herramientas. Los cambios posteriores del juego se intentan
  conservar al apagar. Es reflectancia ambiental: Roblox puede ignorarla en
  ciertas mallas/materiales y no refleja dinámicamente a los jugadores.
- **Floor reflections:** se buscan pisos compatibles con hasta cuatro raycasts
  para poder saltar obstáculos inválidos; si falta HumanoidRootPart se usa la
  cámara con un alcance de hasta 80 studs, frente a 15 desde el root. Se admiten
  pisos móviles sin cambiar su física, también en la capa ancha. Si la librería
  detiene una sesión por fallo fatal se intenta iniciarla una vez; el usuario
  puede apagar/encender el toggle para reintentar. Al apagar, una generación
  impide que una tarea de recuperación antigua vuelva a activarla.
- La base no aumenta exposición ni luz difusa, y no cambia transparencia ni
  color del piso para producir el espejo. El resultado visible puede variar por
  la composición del propio viewport, luces y postprocesos del juego.

## Límites y coste

Hay hasta tres viewports: un plano local de hasta 64×64 studs, más hasta dos
planos adicionales, uno de los cuales se dedica a cobertura amplia de hasta
256×256 si el piso actual es grande. Los adicionales aún necesitan un piso
primario válido bajo el foco. No se refleja Terrain ni toda la escena; las
mallas, ropa y superposición pueden ser inexactas. No es SSR, RTX ni un shader
GPU general. El barrido progresivo tiene límites de 600 texturas, 1.200
reflectancias y 600 pisos candidatos; puede tardar o dejar piezas sin cambios.

Con todos los efectos de clima, el presupuesto máximo es de 30 emisores y 277
partículas/s (162 lluvia, 72 nieve, 27 hojas, 12 polvo, 4 niebla), más hasta
una salpicadura por muestra abierta. Es un límite del código, no una medición
de rendimiento. La calidad gráfica, el juego, permisos y executor pueden
impedir que algún efecto o recurso se muestre. No se puede garantizar el
funcionamiento en todos los juegos ni FPS determinados; tres viewports, sombras
y partículas pueden costar GPU/memoria, especialmente en móvil.

## Pruebas y siguiente comprobación

- `tools/test_shaders.py`: opciones independientes, carga/cancelación de
  assets, niebla con y sin Atmosphere y señales diferidas, restauración,
  streaming, decals por cara, vidrio móvil, lluvia/nieve y fallos de emisores,
  techo, postprocesos y recuperación acotada del espejo (mocks).
- `tools/test_shader_reflection.py`: raycasts con obstáculos, root ausente,
  cámara espectadora, pisos móviles, capas, límites y limpieza (mocks).
- `tools/test_shader_assets.py`: archivos PNG/JPEG, hashes, licencias y manejo
  simulado de cache/descarga. No valida la carga de imagen en Delta.
- `bash tools/validate.sh`: 86 fuentes compiladas, 116 suites, inventario de
  84 fuentes/14 assets, arranque simulado `failures=0`, menú de 50/49 tarjetas.

Falta prueba visual real: verificar la versión `v175` en el watermark; con el
menú cerrado, activar Shaders y probar cada opción por separado, primero sobre
un piso plano sólido, después Fog/Rain en un exterior y Glass/Surface textures
sobre piezas compatibles. Los ajustes guardados pueden haber dejado una opción
apagada. Si algo sigue sin verse, anotar juego/mapa, dispositivo, calidad
Roblox, avisos y capturas o vídeo ON/OFF. El menú abierto aplica su propio
`WurstBlur`, independiente de Shaders.
