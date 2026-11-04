# v178 — Fog reactivo, clima más amplio y trabajo acotado

## Base e informe recibido

Se integraron completos los commits v176/v177 de
`arena/979b8402-arandommenu` (`8e85f920bf8a4089533e7aa597ad26afecb387df`)
a la rama fija `arena/9492e6b6-arandommenu`, por fast-forward y sin cambiar de
rama. Esta versión continúa sobre esa base. El usuario solicita que la niebla
se aparte ante su avatar y otros jugadores, mayor realismo/cobertura y que no
aparezcan lag ni mayor consumo de CPU. También pide quitar Floor reflections si
no puede cubrir el mapa de forma aceptable.

En la captura de Barn de v177 se ve `weather: cells=9 emitters=36 on=0
covered=9` dentro de un edificio: es compatible con estar bajo techo, no
identifica por sí solo un fallo ni prueba que se rendericen partículas fuera.
`scanned=124235` era un contador de **visitas acumuladas**, no necesariamente
124.235 piezas distintas; `textured=187`, `parts=392/1200` y el panel de CPU/GPU
no son un benchmark controlado. El espejo indicaba un piso y una copia parcial,
no cobertura global. La otra captura muestra ajustes en otro interior.

## Cambios

### Retirada del espejo de piso

El toggle, librería `ShaderReflection.lua`, su carga en el manifest y su prueba
se retiraron. Sus hasta tres viewports solo cubrían algunos pisos y copiaban
una fracción de la escena; multiplicarlos no garantiza un reflejo de mapa
completo y añade renderizado/copia. No se alteran la transparencia, geometría o
colisiones para aparentar un espejo. `Glass reflections`, `Wet surfaces` y
`Water reflections` permanecen independientes: son reflectancia ambiental, no
reflejan personajes como SSR. Las licencias históricas se conservan.

### Fog y movimiento

La niebla de distancia sigue siendo global en el cliente: usa la Atmosphere del
juego, o `FogStart/FogEnd/FogColor` si no existe; observa escrituras posteriores
y restaura condicionalmente. A eso se suman nueve parches cercanos y ocho
exteriores, más dispersos, con sprites suaves que se funden. Cada 0,25 s se
considera al jugador local y hasta 16
ranuras remotas en rotación; no se crean emisores ni conexiones por jugador. Se
detecta movimiento horizontal por `AssemblyLinearVelocity` o desplazamiento de
posición, y el parche cercano recibe una aceleración en dirección opuesta al
personaje. Al parar o desaparecer vuelve al viento suave. También se controla la
sustitución de personaje y la pérdida/recuperación de cámara.

Roblox documenta que `Acceleration` puede afectar a partículas ya emitidas. El
empuje es **colectivo por parche**, no una fuerza individual ni una simulación
volumétrica; la niebla global de `Atmosphere` no puede abrir un hueco alrededor
de cuerpos. Solo se procesan personajes y parches cercanos a la cámara; no hay
cambio en los demás clientes. Las pruebas modelan propiedades, no el aspecto.

### Clima y rendimiento

- Rain, Snow, hojas y mist usan 9 celdas cercanas de 40 × 40 y 8 exteriores de
  112 × 112: cobertura geométrica de ~336 × 336 studs alrededor de cámara. El
  anillo exterior es más disperso; el polvo sigue cerca. La cobertura no es
  todo mapa arbitrario: streaming, culling,
  calidad, el tamaño del mapa y el executor pueden impedir que se vea.
- Los emisores se recolocan cuando la cámara cambia al menos 2,5 studs, en lugar
  de reescribir sus posiciones en cada intervalo. Se mantiene una prueba de
  techo por 0,15 s entre las 17 celdas (una vuelta ~2,55 s) y una muestra de
  suelo por celda abierta para salpicaduras. Si la cámara desaparece se
  invalidan los estados de techo: al volver, se sondean y habilitan otra vez.
- Snow, hojas, polvo y niebla usan fundidos al comienzo/final; los clientes sin
  keypoints usan transparencia constante. Se conservan texturas locales y
  fallbacks, sin afirmar que los recursos funcionen en todos los executors.
- Perfil compacto también si `TouchEnabled` es true aunque haya teclado.
  Rain/Snow/hojas/polvo/Fog, todos activos, tienen tasas configuradas de
  **1.978/s escritorio y 927/s móvil/táctil**, más hasta ~13 salpicaduras/s.
  Máximos compartidos: 2.000/1.000; por emisor 320/100. Hay hasta 79/70
  emisores respectivamente. v177 configuraba 2.618/1.106 partículas/s en esos
  perfiles, con menos emisores; no se deduce de ello el coste real del motor.
- Ya no se fuerza `GlobalShadows=true`, respetando la elección del juego.

### Superficies y diagnóstico

Las opciones de superficies recorren toda la jerarquía **recibida** por el
cliente, sin radio ni expulsión por alejarse. Se limitan a cuatro piezas/20
nodos por intervalo de hasta 30 Hz; después de una pasada completa esperan
30 s salvo cambio de opciones o recuperación. Los registros existentes se
reconcilian en lotes; los decals y entradas/salidas por streaming se encolan de
inmediato. Una tabla acotada de 2.048 propietarios de decals permite recuperar
la cara incluso si `DescendantRemoving` llega con `Parent=nil`; al llegar al tope
se depende de la siguiente pasada. Una resolución de imagen actualiza solo los
registros relacionados, no reinicia todo el mapa. Cola máx. 2.048: una caída se cuenta y provoca una
pasada de recuperación. Un fallo transitorio de textura tiene un reintento
acotado; fallos persistentes no generan reintentos infinitos.

Se mantienen los límites de 600 instancias `Texture` y 1.200 cambios de
reflectancia. Mallas, variantes y otras superficies no compatibles no reciben
estas texturas. `Diagnose` informa `visits`, `passes`, `reservedVisits`,
`noStyleVisits`, `queueDrops`, `fogCells`, `moving`, `configuredRate` y
`profile`; las visitas son acumuladas y la tasa configurada incluye emisores
que pueden estar apagados bajo techo. Terrain existente no implica agua visible.

## Validación y límites

- Pruebas enfocadas: `test_shaders.py` cubre opciones, texturas, restauración,
  refugio, celdas cerca/lejos, límites, móviles/táctiles, cámara y fallos.
- `test_shader_fog_movement.py` prueba local y remoto, movimiento por posición,
  50 jugadores en rotación, respawn, límites, keypoints/Acceleration ausentes y
  limpieza. `test_shader_surface_efficiency.py` verifica lotes a 60/120 Hz
  simulados, espera, decals, streaming lejano y recuperación de cola llena.
- `test_runtime_boots.py`, `gen_full_boot_harness.py`, inventario, build y
  `tools/validate.sh` verifican que el bundle no exponga ni arranque el espejo
  retirado y que el resto del menú conserve sus contratos.
- Validación completa: **85 fuentes Lua compiladas, 118 suites, 83 fuentes en el
  bundle y 14 assets**, auditoría de tareas OK, boot `failures=0`, 90 llamadas
  entre módulos resueltas y menú 50/49 (audit/release). `git diff --check` pasó.
  El log local es `build/validate-v178-final.log` (carpeta generada, no publicada).

**No se ha probado visualmente ni medido CPU, GPU o FPS en Roblox, Delta, PC,
móvil o consola.** El nuevo anillo usa más emisores pese a reducir las tasas y
la vida de partículas; las propiedades y la carga real varían. No se puede
prometer cero lag, niebla física, visibilidad universal ni cobertura completa de
mapas de tamaño arbitrario desde un único cliente. Pendiente prueba con menú
cerrado, Fog junto a otro jugador, Rain/Snow fuera y mirando desde un interior;
si falla, recoger captura, mapa, plataforma, calidad y `Diagnose`.

Fuentes: [ParticleEmitter](https://create.roblox.com/docs/effects/particle-emitters),
[Atmosphere](https://create.roblox.com/docs/environment/atmosphere),
[streaming del cliente](https://create.roblox.com/docs/workspace/streaming/techniques),
[ViewportFrame](https://create.roblox.com/docs/ui/viewport-frames),
[MaterialVariant BaseMaterial/PluginSecurity](https://robloxapi.github.io/ref/class/MaterialVariant.html#member-BaseMaterial),
y atribuciones de recursos en `docs/third-party/shaders/README.md`.
