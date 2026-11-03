# Shaders: investigación, recursos y licencias

El módulo usa capacidades visuales del cliente Roblox. Incluye una adaptación de
las ecuaciones MIT de proyección indicadas abajo, pero no descarga ni ejecuta
repositorios externos completos. La disponibilidad y apariencia en Delta
dependen del executor, la calidad gráfica y el juego; las pruebas de este
repositorio no representan imágenes ni FPS reales.

## Reflejos locales en pisos

- [ViewportStencil, commit `6130e70df7e732666a96dd28c59aff11d75988b6`](https://github.com/sebasvcx/ViewportStencil/tree/6130e70df7e732666a96dd28c59aff11d75988b6),
  copyright © 2026 Aziorux (Sebas_Devv), [MIT](LICENSE-ViewportStencil-MIT.txt).
  `src/libraries/ShaderReflection.lua` adapta el cálculo de `Projection.lua`
  para orientar la cámara de un `ViewportFrame` fuera del eje, con límite de
  FOV y `CFrame` escalado. También sigue el montaje documentado del `SurfaceGui`
  en PlayerGui con `Adornee` a una parte invisible. El seguimiento limitado de
  actores/mapa, la reflexión geométrica y la limpieza son propios del menú.
- La proyección de ViewportStencil se basa en
  [EgoMoose/rbx-viewport-window, commit `d62f04651afa8f56459bdb42efa69d8cd65e04b0`](https://github.com/EgoMoose/rbx-viewport-window/tree/d62f04651afa8f56459bdb42efa69d8cd65e04b0),
  copyright © 2025 EgoMoose, [MIT](LICENSE-EgoMoose-MIT.txt). Se incluyen ambos
  avisos de licencia porque se adapta el código derivado.
- [Storm99999/Reflections, commit `4b317526e8d00750c4c7c5e3db830ad95f1d1c47`](https://github.com/Storm99999/Reflections/tree/4b317526e8d00750c4c7c5e3db830ad95f1d1c47)
  (MIT) se inspeccionó, pero su enfoque con suelo translúcido no se incorporó:
  no se quiere alterar la transparencia ni la física del mapa.
- [ViewportFrame de Roblox](https://create.roblox.com/docs/ui/viewport-frames)
  solo dibuja la escena copiada y tiene restricciones de luces, sombras,
  materiales y posprocesado. Las prendas clásicas requieren un Model/Humanoid
  como en este [ejemplo de avatares](https://devforum.roblox.com/t/how-to-render-a-character-within-a-viewportframe/524239);
  la copia limitada no garantiza fidelidad de ropa en capas o mallas asimétricas.
  No es SSR ni render de la escena original: se dibuja el piso cercano y hasta
  dos planos adicionales. Si el piso es grande, uno de esos planos se reserva
  para una capa amplia de ese mismo piso; solo queda uno para otro piso. Las
  curvas, mallas irregulares, Terrain y objetos omitidos pueden producir bordes o
  faltar. Desde v175 la búsqueda bajo el personaje puede saltar obstáculos
  invisibles con hasta cuatro raycasts; si no hay root usa la cámara con mayor
  alcance, y el piso primario puede ser una plataforma móvil. Los espejos
  adicionales siguen requiriendo un piso primario válido bajo el foco. El
  resultado y la superposición de capas no se han comprobado en Delta.

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
con transparencia 0,55, sin mezclar hacia blanco como en v172. Son texturas 2D;
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
mallas. `Floor reflections` usa los viewports locales descritos arriba. La
opción de agua actúa en `Terrain.WaterReflectance`.

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
  la corrección, bloom, rayos, luz especular y sombras forman una base fija.
  Desde v173 no se aumenta la exposición ni la luz difusa del juego para
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

## Límites de diseño, no mediciones

La jerarquía del `Workspace` se recorre progresivamente: hasta 20 nodos y cuatro
piezas por tick, con un raycast de prioridad al suelo por pasada y una pausa de
2 s entre pasadas completas. El streaming se encola y los registros obsoletos se
revisan en lotes. Como máximo se retienen 600 `Texture`, 1.200 cambios de
reflectancia y 600 pisos candidatos para espejos; se avisa si se llega a un
límite. Los mapas más grandes pueden tener piezas sin cambios y la primera
pasada tarda según su tamaño. No se ejecuta `GetDescendants()` del mapa por frame.

El plano principal cubre hasta 64 × 64 studs bajo el personaje. Para un piso
mayor, uno de los dos planos adicionales cubre hasta 256 × 256 studs de ese piso;
el otro puede mostrar otro piso compatible. En un piso pequeño pueden mostrarse
dos pisos adicionales. Si no se consigue reservar la capa amplia, el plano
principal vuelve a cubrir hasta 256 × 256, con menos detalle. Se copian hasta
54 partes en el viewport principal y 32 en cada adicional (118 como máximo).
La selección revisa hasta 32 candidatos por tick. El escaneo cercano de escena
pide hasta 100 piezas cada 2 s; el presupuesto compartido es de tres creaciones
de partes por tick. Las poses se actualizan hasta 30/15 Hz en PC y 20/10 Hz en
móvil (principal/adicionales), solo cuando un viewport relevante está visible.
El lado efectivo máximo del render principal es 1.024 px en PC o 768 en móvil;
los adicionales son 512/384. El límite tiene en cuenta el escalado fuera de eje.
Los viewports no comparten escena ni reflejan todos los objetos del mapa. Un
piso grande sin otros espejos consume ahora dos viewports, no uno: puede costar
más GPU aunque el máximo total no aumentó.

Fog, Rain, Snow, hojas y polvo suman hasta 39 emisores y 2.519 partículas/s de
escritorio (2.160 lluvia en dos capas, 306 nieve, 27 hojas, 12 polvo y 14
niebla), más hasta dos salpicaduras por muestra abierta: unas 13/s como máximo.
En móvil se crea directamente el perfil reducido (≈1.052 partículas/s) porque un
emisor está limitado a 100/s. El tope de `Rate` por emisor es 320 en escritorio
y 100 en móvil, y la suma total se recorta a `MAX_WEATHER_RATE = 3000` escalando
todas las capas. Las posiciones se actualizan hasta 20 Hz y se reparte una prueba
de techo cada 0,15 s entre nueve celdas; la lluvia exterior puede verse desde un
interior cercano, no recortar perfectamente cada borde. Solo la geometría
colisionable cuenta como techo (`RespectCanCollide`), mover la cámara no apaga los
emisores y `Enabled` solo se reescribe cuando una celda cambia de estado. Si la
comprobación de techo falla, se notifica y los emisores siguen visibles, incluso
bajo techo. Las partículas vivas son `Rate × Lifetime`: ≈1.550 de lluvia y ≈1.900
de nieve con todo activo. Sin emisores disponibles no queda tarea de clima; sin
texturas, reflectancia ni espejo no hay barrido superficial. Son presupuestos de
código, **no mediciones de FPS, GPU ni memoria** en Roblox/Delta. Las sombras, los
assets, los sprites y tres `ViewportFrame` pueden resultar costosos en móvil.
