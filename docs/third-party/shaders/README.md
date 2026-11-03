# Shaders: investigación, recursos y licencias

El módulo usa capacidades visuales del cliente Roblox. Incluye una adaptación de
las ecuaciones MIT de proyección indicadas abajo, pero no descarga ni ejecuta
repositorios externos completos. La disponibilidad y apariencia en Delta
dependen del executor, la calidad gráfica y el juego; las pruebas de este
repositorio no representan imágenes ni FPS reales.

## Reflejo local de un piso

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
  No es SSR ni render de la escena original: una superficie grande, curvas,
  mallas irregulares y objetos omitidos pueden producir bordes o faltar.

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
encuentra una superficie compatible, no todas al inicio. La aplicación usa
`Texture.ColorMapContent` con respaldo a `Texture.Texture` en clientes antiguos,
mezclando parcialmente el color de la pieza. Son texturas 2D repetidas; no se
sustituyen `Material`, mallas, colisiones ni propiedades físicas. Solo se cubren
caras de bloques anclados elegibles próximos a la cámara: ciertos suelos y
paredes; no `MeshPart`, variantes, `SpecialMesh`, partes con decals existentes,
personajes ni herramientas. En un mapa que no tenga esas superficies no habrá
cambios de textura. `Glass reflections` y `Wet surfaces` usan `Reflectance`
en vidrio/ventanas y suelos de plástico: es brillo ambiental, no refleja
personajes. `Floor reflections` usa el viewport local descrito arriba. La
opción de agua actúa en `Terrain.WaterReflectance`.

Mientras se descarga cada imagen CC0 se intenta el ColorMap del material
correspondiente publicado en la tabla oficial de
[materiales base de Roblox](https://create.roblox.com/docs/parts/materials#current-base).
Al llegar el asset local se sustituye gradualmente; los ID públicos se referencian,
no se distribuyen como archivos. Esta alternativa puede parecerse mucho al
material que el juego ya tenía y tampoco garantiza que la imagen cargue.

`getcustomasset`/`getsynasset`, escritura local y HTTP funcionales son necesarios
para las imágenes CC0. Si su resolución falla, se avisa una vez y se conserva el
intento con las imágenes de Roblox; se reintenta la descarga al alternar
`Surface textures`. Que el executor devuelva una URL no demuestra que Roblox
vaya a dibujarla: aún hay que comprobar ambos caminos en el dispositivo real.

## Iluminación y clima existentes

- [Roblox-Skyscraper-Lighting, `PhotorealLighting.luau`](https://github.com/HathuwstAlkan/Roblox-Skyscraper-Lighting/blob/b7f77d16341dc06ac5030d36f8c7112528206871/src/shared/PhotorealLighting.luau),
  copyright © 2026 HathuwstAlkan, [MIT](LICENSE-Photoreal-MIT.txt). En v170 se
  adaptaron valores de efectos nativos. En v171 se retiraron todos los presets:
  la corrección, bloom, rayos, luz ambiental/especular y sombras forman una
  base fija. No se modifica `Lighting.Technology` ni se eliminan los efectos
  del juego; los ColorCorrection existentes pueden combinarse con el nuestro.
- [ShaderCloud/rbxts-weather](https://github.com/Shadercloud/rbxts-weather/tree/2e17de2d8defa641d1e4d7d993692c7cdbb274c9),
  copyright © 2026 ShaderCloud, [ISC](LICENSE-Weather-ISC.txt). Se adapta la
  idea de cuadrículas alrededor de la cámara y comprobación de techo. La hoja
  [`maple-orange-12.png`](https://github.com/Shadercloud/rbxts-weather/blob/2e17de2d8defa641d1e4d7d993692c7cdbb274c9/art/leaves/maple-orange-12.png)
  se usa sin cambios como `autumn-maple.png`. No se distribuye el paquete entero.
- [Kenney Particle Pack, `trace_01.png`](https://github.com/Calinou/kenney-particle-pack/blob/ab7086639ee73be31abd87feb21bf1402d4e8144/addons/kenney_particle_pack/trace_01.png),
  Kenney Vleugels, [CC0](LICENSE-Kenney-CC0.txt): reducido a 128×128 para
  `rain-trace.png`.
- [Godot particle and VFX textures, `spotlight_1.png`](https://github.com/RPicster/Godot-particle-and-vfx-textures/blob/9bb6fe7cc50534e171d2093630f3288773c8c865/textures/64/alpha/spotlight_1.png),
  Raffaele Picca, [CC0](LICENSE-RPicster-CC0.txt): `snow-soft.png` sin cambios,
  utilizado para nieve y polvo flotante.

Las tres imágenes de clima suman 72.807 bytes y tienen respaldo nativo/ID si no
se pueden descargar. Fog reutiliza la atmósfera existente o crea una temporal;
se restaura sin borrar la del juego. Si el juego cambia una propiedad que usamos,
solo se restaura cuando todavía tiene nuestro valor (un cambio externo al valor
exactamente igual no se puede distinguir).

## Proyectos y documentación inspeccionados

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

El barrido se hace a 120 studs como máximo cada 2 s y pide hasta 240 piezas;
además intenta un raycast hacia el suelo en ese mismo intervalo para priorizar
una superficie visible, aun si falla la consulta de radio. Procesa como máximo
240 candidatas y cuatro por tick; mantiene como máximo 80 `Texture` y 100
cambios de reflectancia a la vez. Las descargas, el streaming de mapas y los
cambios de cámara se gestionan sin recorrer `GetDescendants()` por frame. Se
pueden activar lluvia, nieve, hojas y polvo a la vez: máximo 13 emisores,
112 partículas nuevas por segundo, posiciones actualizadas hasta 20 Hz y una
comprobación de techo cada 0,15 s para toda la cuadrícula. El número de
partículas vivas depende de su duración. Si no hay ninguna de esas opciones, no
hay tarea de clima; si todas las opciones de superficies están apagadas, no hay
barrido. Sombras globales, texturas y partículas pueden afectar el rendimiento.
Además, el reflejo del piso tiene su propia consulta de hasta 100 piezas cada
2 s, hasta 54 partes copiadas (36 de hasta tres personajes y 18 de entorno),
tres copias nuevas por tick y poses hasta 30 Hz. Usa un solo viewport con lado
máximo 512 en el canvas y una superficie de hasta 24 × 20 studs. Al ocultarlo
por distancia/orientación se detiene su render, no necesariamente las tareas de
seguimiento. Estos presupuestos no sustituyen medir FPS y memoria en Roblox/Delta.
