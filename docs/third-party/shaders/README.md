# Fuentes y licencias de Shaders / Weather

Este directorio conserva las licencias de los materiales realmente usados.
Las referencias se fijaron a commits concretos; el menú no descarga ni ejecuta
código de terceros en tiempo de ejecución.

## Iluminación

- [Roblox-Skyscraper-Lighting, `PhotorealLighting.luau`](https://github.com/HathuwstAlkan/Roblox-Skyscraper-Lighting/blob/b7f77d16341dc06ac5030d36f8c7112528206871/src/shared/PhotorealLighting.luau),
  copyright © 2026 HathuwstAlkan, [licencia MIT](LICENSE-Photoreal-MIT.txt).
  `Photoreal`, `Golden Hour`, `Blue Hour` y `Overcast` adaptan los valores de
  color, bloom y rayos de los presets `HighNoon`, `GoldenHour`, `BlueHour` y
  `OvercastMoody`. El tinte se mezcla con el control del usuario y los sliders
  siguen actuando como offsets. No es una copia completa del motor: no cambia
  `Lighting.Technology`, la hora, luces, cielo ni geometría del juego, y no
  elimina sus efectos. Estas son capacidades nativas de Roblox, no RTX ni un
  shader ReShade ejecutado por Delta.

## Clima

- [ShaderCloud/rbxts-weather](https://github.com/Shadercloud/rbxts-weather/tree/2e17de2d8defa641d1e4d7d993692c7cdbb274c9),
  copyright © 2026 ShaderCloud, [licencia ISC](LICENSE-Weather-ISC.txt).
  La precipitación adapta el concepto de cuadrículas alrededor de la cámara,
  comprobación de techo y partículas. El original es un paquete roblox-ts
  completo con cuadrículas mucho mayores; aquí se usan cuatro celdas, un solo
  emisor por celda y comprobaciones escalonadas. La textura
  [`art/leaves/maple-orange-12.png`](https://github.com/Shadercloud/rbxts-weather/blob/2e17de2d8defa641d1e4d7d993692c7cdbb274c9/art/leaves/maple-orange-12.png)
  se conserva sin cambios para `Autumn`. El proyecto también indica los
  fallbacks nativos de lluvia/nieve y el ID de la hoja que empleamos.
- [Kenney Particle Pack, `trace_01.png`](https://github.com/Calinou/kenney-particle-pack/blob/ab7086639ee73be31abd87feb21bf1402d4e8144/addons/kenney_particle_pack/trace_01.png),
  por Kenney Vleugels, [CC0](LICENSE-Kenney-CC0.txt). Se redujo de 512×512 a
  128×128 y se retiraron metadatos para `rain-trace.png`.
- [Godot particle and VFX textures, `spotlight_1.png`](https://github.com/RPicster/Godot-particle-and-vfx-textures/blob/9bb6fe7cc50534e171d2093630f3288773c8c865/textures/64/alpha/spotlight_1.png),
  por Raffaele Picca, [CC0](LICENSE-RPicster-CC0.txt). Se conserva sin cambios
  como `snow-soft.png` (64×64).

Solo se distribuyen las tres imágenes utilizadas, no los paquetes enteros de
sonidos, nubes y mallas que este módulo no necesita. Los PNG viven en
`src/guis/Wurst/Assets/Shaders/`, se descargan a demanda desde esta rama y se
cachean mediante el AssetManager existente. Si faltan `getcustomasset`, archivos
locales o descarga, se usan las texturas/ID de respaldo; tampoco se puede
asegurar que un executor o dispositivo concreto renderice un asset custom.

Se analizaron también [buildthomas/Rain](https://github.com/buildthomas/Rain/tree/b4088187c457ae4e67c034b6244da680a154b567)
(Apache-2.0) y [RbxShader](https://github.com/AnotherSubatomo/RbxShader/tree/78dcb508ceb90df09934436be5b8e0a95a5fd326)
(MIT), pero no se incluye código o assets de ellos: la adaptación ligera no
necesita el sistema completo de lluvia ni un motor por píxel. Roshade/ReShade
es una herramienta externa de escritorio, no se ha integrado como Luau para
Roblox o Delta.

Los límites son de diseño, no mediciones de FPS: cuatro emisores como máximo,
60 gotas/s, 28 copos/s o 12 hojas/s en total y una comprobación de techo por
cada 0,15 s como máximo en el ritmo de actualización. El número de partículas
simultáneas depende de sus vidas (0,85 s lluvia, 4 s nieve/hojas), el render de
Roblox y las condiciones reales. `Clear` no crea emisor ni tarea de clima.
Fog usa el `Atmosphere` existente o crea uno temporal; al apagar restaura las
propiedades aún iguales a las aplicadas por el menú, sin borrar el del juego.
No es posible distinguir un cambio del juego que escriba exactamente el mismo
valor. Los resultados visuales, consumo y soporte móvil requieren prueba real.
