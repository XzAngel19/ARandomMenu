# Shaders: investigación, recursos y licencias

El módulo usa capacidades visuales del cliente Roblox; no descarga ni ejecuta
repositorios externos completos. La apariencia en Delta depende del executor,
la calidad gráfica y el juego; las pruebas no representan píxeles ni FPS reales.

## Reflejos de piso retirados (investigación histórica)

Hasta v177 se adaptaron ecuaciones MIT de
[ViewportStencil `6130e70`](https://github.com/sebasvcx/ViewportStencil/tree/6130e70df7e732666a96dd28c59aff11d75988b6)
(copyright © 2026 Aziorux, [licencia](LICENSE-ViewportStencil-MIT.txt)) y de su
base [EgoMoose/rbx-viewport-window `d62f046`](https://github.com/EgoMoose/rbx-viewport-window/tree/d62f04651afa8f56459bdb42efa69d8cd65e04b0)
(copyright © 2025 EgoMoose, [licencia](LICENSE-EgoMoose-MIT.txt)). El historial
conserva esos avisos. [Storm99999/Reflections](https://github.com/Storm99999/Reflections/tree/4b317526e8d00750c4c7c5e3db830ad95f1d1c47)
se inspeccionó, pero no se incorporó.

En v178 se retiraron `Floor reflections`, `ShaderReflection.lua` y su prueba:
los [ViewportFrames](https://create.roblox.com/docs/ui/viewport-frames) solo
dibujaban copias parciales en unos pocos pisos, no SSR ni reflejos de todo el
mapa; aumentar su número elevaría el coste de dibujar y copiar la escena. No se
cambian la transparencia ni la física del suelo para fingir un espejo.

## Superficies: cinco imágenes de color CC0

Los nuevos mapas son las imágenes **de color/albedo**, no los mapas de normales,
metalness o roughness. Las fuentes son materiales fotográficos de
[ambientCG](https://ambientcg.com/), que publica sus recursos bajo
[CC0 1.0](LICENSE-ambientCG-CC0.txt). Las copias se descargaron desde
[Mini Texture, commit `b080ca4df63813b3b764a8f31b3f418e3d6b6a2a`](https://github.com/amazingsammed/mini_textures/tree/b080ca4df63813b3b764a8f31b3f418e3d6b6a2a/mini_texture/textures);
[su README identifica los materiales y su licencia CC0](https://github.com/amazingsammed/mini_textures/blob/b080ca4df63813b3b764a8f31b3f418e3d6b6a2a/README.md#licensing-and-selling).
Solo se incluyen estos cinco JPEG; el código y los demás recursos del
repositorio intermediario no se ejecutan ni distribuyen:

| Origen ambientCG | Copia local | Dimensiones | ColorMap Roblox alternativo |
| --- | --- | --- | --- |
| `Concrete034_diffuse.jpg` | `surface-concrete.jpg` | 512×256 | `9920484153` |
| `WoodFloor051_diffuse.jpg` | `surface-wood-floor.jpg` | 512×512 | `9920626778` |
| `Bricks105_diffuse.jpg` | `surface-brick.jpg` | 512×256 | `9920482813` |
| `Grass005_diffuse.jpg` | `surface-grass.jpg` | 512×512 | `9920551868` |
| `Marble012_diffuse.jpg` | `surface-marble.jpg` | 512×512 | `9439430596` |

Se redujeron con ImageMagick `-resize '512x512>' -strip -quality 85`; las cinco
suman 221.681 bytes. El `AssetManager` las descarga y cachea por tipo cuando
encuentra una superficie compatible, no todas al inicio. Desde v175 se usa el
campo `Texture.Texture` para URI locales del executor y se intenta
`Texture.ColorMapContent` primero para los ID oficiales (con fallback al campo
anterior). Un [reporte de la comunidad](https://devforum.roblox.com/t/local-assets-do-not-work-when-used-with-surfaceappearances-and-materialvariants/4638719)
indica fallos silenciosos de algunas URI locales con `ColorMapContent`; no prueba
qué ocurre en todos los executors. El color original de la pieza sirve de tinte
con transparencia 0,42, sin mezclar hacia blanco como en v172. Son texturas 2D;
no se sustituyen `Material`, mallas, colisiones ni propiedades físicas.

El barrido visita el mapa sin descartar piezas al alejarse, pero solo cubre
bloques y uniones CSG anclados elegibles: ciertos suelos y paredes, no `MeshPart`,
variantes, `SpecialMesh`, `SurfaceAppearance`, personajes ni herramientas. Un
decal del juego reserva solo su cara, no las demás. El mapeo CSG puede diferir
según geometría. En un mapa sin superficies compatibles no habrá cambios de
textura. `Glass reflections` y `Wet surfaces` usan `Reflectance` en ventanas y
suelos compatibles: es brillo ambiental, no refleja personajes. Glass incluye
paneles transparentes finos y vidrio móvil fuera de personajes/herramientas,
sin modificar su física; Roblox puede ignorar la reflectancia en materiales o
mallas. `Floor reflections` ya no existe. La opción de agua actúa en
`Terrain.WaterReflectance`; que haya Terrain no significa que haya agua visible.

Mientras se descarga cada imagen CC0 se intenta el ColorMap del material
correspondiente publicado en la tabla oficial de
[materiales base de Roblox](https://create.roblox.com/docs/parts/materials#current-base).
Al llegar el asset local se sustituye gradualmente; los ID públicos se referencian,
no se distribuyen como archivos. Esta alternativa puede parecerse mucho al
material que el juego ya tenía y tampoco garantiza que la imagen cargue.

`getcustomasset`/`getsynasset`, escritura local y HTTP funcionales son necesarios
para las imágenes CC0. Desde v175 se usa `ContentProvider:PreloadAsync` en tareas
asíncronas: si no informa éxito o falla, se avisa y se conserva el intento con
imágenes de Roblox; se reintenta al alternar `Surface textures`. Esta política
conservadora puede descartar una URI que sí se vería, y un estado exitoso no
demuestra que la imagen haya dibujado píxeles. El fallback oficial también
puede fallar por permisos/calidad: ambos caminos requieren prueba real.

## Iluminación y clima existentes

- [Roblox-Skyscraper-Lighting, `PhotorealLighting.luau`](https://github.com/HathuwstAlkan/Roblox-Skyscraper-Lighting/blob/b7f77d16341dc06ac5030d36f8c7112528206871/src/shared/PhotorealLighting.luau),
  copyright © 2026 HathuwstAlkan, [MIT](LICENSE-Photoreal-MIT.txt). En v170 se
  adaptaron valores de efectos nativos. En v171 se retiraron todos los presets:
  la corrección, bloom, rayos y luz especular forman una base fija.
  Desde v178 se respeta si el juego tenía sombras desactivadas; desde v173
  no se aumenta la exposición ni la luz difusa del juego para
  reducir el blanqueamiento. No se modifica `Lighting.Technology` ni se
  eliminan los efectos del juego; los ColorCorrection existentes se combinan.
- [ShaderCloud/rbxts-weather](https://github.com/Shadercloud/rbxts-weather/tree/2e17de2d8defa641d1e4d7d993692c7cdbb274c9),
  copyright © 2026 ShaderCloud, [ISC](LICENSE-Weather-ISC.txt). Se adapta la
  idea de cuadrículas alrededor de la cámara y comprobación de techo. La hoja
  [`maple-orange-12.png`](https://github.com/Shadercloud/rbxts-weather/blob/2e17de2d8defa641d1e4d7d993692c7cdbb274c9/art/leaves/maple-orange-12.png)
  se usa sin cambios como `autumn-maple.png`. No se distribuye el paquete entero.
- [buildthomas/Rain, commit `b4088187c457ae4e67c034b6244da680a154b567`](https://github.com/buildthomas/Rain/tree/b4088187c457ae4e67c034b6244da680a154b567),
  autor buildthomas, [Apache-2.0](LICENSE-Rain-Apache-2.0.txt),
  [aviso original](NOTICE-Rain.txt). Se investigó el plugin solicitado: usa
  emisores alrededor de la cámara, muestras del cielo y salpicaduras para ver
  lluvia al mirar afuera desde un interior. La cuadrícula limitada de este
  proyecto es una implementación separada; no incluye ni ejecuta el plugin completo.
- [Hilo de Fog solicitado](https://devforum.roblox.com/t/how-can-i-create-a-fog-effect-that-works-with-everyone/439055):
  se comenta una geometría de niebla local que sigue al jugador y advierte que
  la calidad gráfica influye. Aquí se combina `Atmosphere` o `FogEnd`, según el
  juego, con sprites cercanos a la cámara; no es iluminación volumétrica real.
  La documentación de [Lighting](https://create.roblox.com/docs/reference/engine/classes/Lighting#FogEnd)
  y [Atmosphere](https://create.roblox.com/docs/reference/engine/classes/Atmosphere)
  indica que `Atmosphere` reemplaza los parámetros de niebla anteriores.
- [Kenney Particle Pack, `trace_01.png`](https://github.com/Calinou/kenney-particle-pack/blob/ab7086639ee73be31abd87feb21bf1402d4e8144/addons/kenney_particle_pack/trace_01.png),
  Kenney Vleugels, [CC0](LICENSE-Kenney-CC0.txt): reducido a 128×128 para
  `rain-trace.png`.
- [Godot particle and VFX textures, `spotlight_1.png`](https://github.com/RPicster/Godot-particle-and-vfx-textures/blob/9bb6fe7cc50534e171d2093630f3288773c8c865/textures/64/alpha/spotlight_1.png),
  Raffaele Picca, [CC0](LICENSE-RPicster-CC0.txt): `snow-soft.png` sin cambios,
  utilizado para nieve, polvo, niebla y salpicaduras.

Las tres imágenes de clima suman 72.807 bytes y tienen respaldo nativo/ID si no
se pueden descargar o la precarga no informa éxito. Desde v176 esos respaldos son
los assets públicos del módulo de referencia —`1822883048` (trazo de lluvia) y
`1822856633` (impacto/top-down)—, porque un cuadrado no puede leerse como gota.
Se **referencian por ID**, no se copian ni se redistribuyen, y su disponibilidad
en el cliente sigue dependiendo de Roblox. Fog utiliza la `Atmosphere`
del juego cuando existe; de lo contrario utiliza `Lighting.FogStart/FogEnd` y
`FogColor`. Añade partículas translúcidas sin crear ni borrar la atmósfera del
juego. Mientras está activo reacciona a cambios; al apagar restaura el último
valor ajeno conocido solo si el valor actual sigue siendo el aplicado por el
módulo. Una escritura externa exactamente igual no puede distinguirse.

## Proyectos y documentación inspeccionados

- [How can I create a shader?](https://devforum.roblox.com/t/how-can-i-create-a-shader/3154598),
  enlace solicitado: ejemplos con `ColorCorrection`/`Highlight` y una
  advertencia comunitaria de pantalla oscura al forzar niebla extrema en móvil.
  No se usa ese ajuste extremo ni se interpreta como acceso a shaders GPU.
- [ContentProvider](https://create.roblox.com/docs/reference/engine/classes/ContentProvider)
  documenta el callback de estado de `PreloadAsync`; no certifica los píxeles.
- [ParticleEmitter](https://create.roblox.com/docs/effects/particle-emitters)
  describe emisores en partes y lluvia con `VelocityParallel`/squash negativo.
- [Penumbra](https://github.com/Crazyblox/penumbra/tree/f730e0de5592503bcc9b99f313221a5f345aa74a),
  [MIT dentro de `license/penumbra.luau`](https://github.com/Crazyblox/penumbra/blob/f730e0de5592503bcc9b99f313221a5f345aa74a/license/penumbra.luau):
  pipeline por framebuffer y workers que requiere Pajamas/Actors y presenta sus
  propios píxeles. No es un postproceso automático y barato sobre la imagen del
  juego; no se integró ni se probaron sus costes en Delta.
- [RbxShader](https://github.com/AnotherSubatomo/RbxShader/tree/78dcb508ceb90df09934436be5b8e0a95a5fd326)
  (MIT) también implementa fragmentos en Luau, no acceso general a shaders GPU.
- [PBR-Surface-Applier](https://github.com/gaymeowing/PBR-Surface-Applier/tree/00ea47389a90215974fce82b8ae9f7ef0563a267)
  (Apache-2.0) aplica texturas con mapas a superficies como paquete/plugin. Su
  uso de mapas no implica que se puedan escribir en cualquier cliente: los
  mapas normales/roughness de `Decal`/`Texture` están documentados con
  `PluginSecurity`. No se incorporó su código.
- [Solstice](https://github.com/xslvrrr/Solstice/tree/6d1ccf47d40fca004390b7b725dbe4d62b02d49b)
  muestra otra combinación de luz nativa, reflectancia y partículas; no se
  encontró licencia en su repositorio y no se copió su código. `RO-TX` está
  ofuscado y sin licencia identificada; no se ejecutó ni incorporó.
- Roblox documenta [Texture](https://create.roblox.com/docs/reference/engine/classes/Texture),
  [Decal y sus permisos](https://create.roblox.com/docs/reference/engine/classes/Decal),
  [SurfaceAppearance](https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance)
  y [MaterialVariant](https://create.roblox.com/docs/reference/engine/classes/MaterialVariant).
  Sus mapas PBR normales/metalness/roughness no son escrituras ordinarias de
  script. [CreateSurfaceAppearanceAsync con EditableImage](https://devforum.roblox.com/t/in-experience-build-a-texture-editableimage-support-for-surfaceappearance/3866947)
  existe en experiencias publicadas, pero tiene requisitos de permisos, memoria
  y contenido; no se puede asumir acceso al material de un mapa ajeno en Delta.
  Por eso aquí no se anuncian los JPEG como materiales PBR completos.
- Roshade/ReShade son herramientas externas de escritorio, no ejecutables como
  un módulo Luau en Delta. No se ha instalado ni prometido RTX.

## Límites de diseño, no mediciones (v178)

El barrido de `Workspace` avanza hasta 20 nodos y cuatro piezas por intervalo,
con cadencia máxima de 30 Hz (~120 piezas/s), no por frame. Tras cada pasada
completa espera 30 s salvo cambios de opciones o recuperación de cola; señales de
streaming y decals alimentan una cola acotada de 2.048 elementos. Si se llena,
`queueDrops` lo indica y una pasada posterior recupera piezas. Una tabla de hasta
2.048 propietarios de decals permite recuperar caras con señales diferidas;
si se llena queda la reconciliación posterior. Los registros ya tratados se
reconcilian en lotes, y un fallo transitorio de textura tiene un
reintento acotado. No se usa `GetDescendants()` del mapa en cada frame. El máximo
es 600 `Texture` y 1.200 cambios de reflectancia, no cobertura universal; la
primera pasada puede tardar mucho en mapas grandes.

Rain/Snow/hojas y niebla tienen nueve celdas cercanas de 40 × 40 y ocho exteriores
de 112 × 112, distribuidas sobre ~336 × 336 studs alrededor de la cámara. Con
todo activo se configuran **1.978 partículas/s en escritorio** (1.574 lluvia,
262 nieve, 96 hojas, 20 polvo, 26 niebla) y **927/s en móvil/táctil** (688 lluvia,
158 nieve, 52 hojas, 12 polvo, 17 niebla); hay además hasta dos salpicaduras por
muestra abierta, ~13/s. Se limitan a 2.000 y 1.000/s respectivamente, y como
máximo 320 o 100/s por emisor. Con todos los tipos activos se crean hasta 79
emisores en escritorio o 70 en móvil, incluidos niebla, polvo y salpicaduras:
hay más emisores que antes para mayor cobertura, aunque menos partículas y sin
viewports de piso. `Rate × Lifetime` predice cantidad, no coste medido.

Los orígenes se recolocan si la cámara se mueve al menos 2,5 studs. Una prueba de
techo cada 0,15 s se reparte entre 17 celdas: una vuelta completa puede tardar
aprox. 2,55 s. Solo se prueban puntos, no cada gota ni cada borde. La cámara que
se pierde vuelve a sondear las celdas al recuperarse. Con cielo desconocido se
avisa y puede atravesar techos. La calidad/culling puede reducir la emisión. El
[streaming de Roblox](https://create.roblox.com/docs/workspace/streaming/techniques)
solo entrega al cliente un subconjunto del mundo y también limita sus raycasts;
no puede prometerse clima en cada punto de un mapa ilimitado desde este cliente.

Fog combina el estado global de Lighting con nueve emisores cercanos, de 2/s
cada uno (1/s en móvil), y ocho exteriores de 1/s. Cada 0,25 s se considera el
personaje local y hasta 16 ranuras remotas en rotación. `ParticleEmitter.Acceleration` puede mover también
partículas ya emitidas, según la
[API de Roblox](https://create.roblox.com/docs/effects/particle-emitters); se usa
para un desvío colectivo por parche alrededor del jugador en movimiento. No hay
un vector por partícula ni recorte de la niebla global de `Atmosphere`, así que
no es niebla volumétrica ni una colisión física. Snow, hojas, polvo y niebla usan
fundido al nacer y desaparecer cuando la API está disponible.

Estos límites y las pruebas son **conteos de código, no FPS, CPU, GPU ni memoria
medidos**. No hay validación visual en Roblox/Delta; el nuevo anillo, el coste de
sus emisores y la reacción del fog pueden comportarse distinto en cada cliente.
