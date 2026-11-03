# v171 — Shaders realistas sin selector de modos

## Petición y alcance

El usuario rechazó los looks de v170 porque no notaba mejoras útiles. Se
inspeccionaron proyectos reales y documentación oficial (revisiones y licencias
en `third-party/shaders/README.md`), incluyendo motores Luau por píxel,
implementaciones de efectos nativos, texturas CC0 y una herramienta PBR para
Studio. No se ejecutaron scripts externos durante la investigación. El módulo
no puede instalar ReShade de escritorio ni prometer iluminación RTX o PBR
completo en un juego ajeno.

## Cambios

- Se eliminaron todos los presets, `Look`, el selector `Weather` y `Advanced`.
  Al activar Shaders se aplican directamente corrección de color moderada,
  bloom, rayos de sol, iluminación difusa/especular del entorno, sombras y un
  pequeño aumento de exposición que no reduce la exposición original.
- `Surface textures` y `Glass reflections` empiezan activadas. Cinco mapas de
  color CC0 (concreto, madera, ladrillo, hierba, mármol) se resuelven desde el
  AssetManager y se colocan en caras de bloques estáticos compatibles y
  próximos. Los suelos grandes de plástico pueden recibir concreto. Se omiten
  mallas, piezas con textura/decal o variante, herramientas y personajes;
  no se modifica `Material`, geometría, colisión ni propiedades físicas.
  Los JPEG se descargan únicamente para materiales detectados. Mientras llegan
  se intentan imágenes ColorMap oficiales de Roblox; si falta el soporte de
  archivos/assets, se notifica y se conserva ese respaldo. La disponibilidad
  y apariencia de las imágenes dependen del cliente.
- El brillo de vidrio/ventanas existentes modifica solo `Reflectance`, sin
  convertir piezas en `Glass`, ni alterar su transparencia. Los reflejos son
  aproximaciones propias del motor y dependen del material y calidad gráfica.
- `Fog`, `Rain`, `Snow`, `Falling leaves`, `Dust motes`, `Wet surfaces` y
  `Water reflections` son toggles independientes. Pueden combinarse; el polvo
  funciona también en interiores, mientras lluvia/nieve/hojas comparten cuatro
  celdas y comprobaciones de techo. La humedad añade brillo solo a suelos
  plásticos; el agua cambia solo `Terrain.WaterReflectance`.
- Se retiran los objetos creados y se restauran propiedades si aún coinciden
  con los valores aplicados. Se respeta un valor distinto escrito después por
  el juego. Una escritura externa del mismo valor no se puede distinguir.
  La atmósfera propia se sustituye por la del juego si aparece una, y la del
  juego no se destruye. Cambios de mapa, carga tardía y descargas que terminan
  después de apagar se manejan sin reactivar los efectos.
- Presupuestos de código: consulta de hasta 240 piezas por radio 120 cada 2 s
  y un raycast de suelo como máximo por consulta para priorizar el piso cercano;
  cuatro piezas procesadas por tick, hasta 80 texturas y 100 reflectancias;
  13 emisores y 107 partículas/s con todas las opciones de clima, una prueba de
  techo por al menos 0,15 s y posición actualizada hasta 20 Hz. No son mediciones
  de rendimiento: las sombras y los efectos pueden costar en el dispositivo.

## Comprobación

`tools/test_shaders.py` ejecuta el módulo y el Framework reales con mocks:
interfaz sin modos, valores iniciales de Lighting, selección/omisión de piezas,
texturas de color, fallback oficial y respaldo legado de `ColorMapContent`,
reflejos, cambios de mapa, decals entrantes, cancelaciones, límites, exposición
alta, restauración condicional, Fog,
agua, techo, cámara, lluvia/nieve/hojas/polvo simultáneos y errores parciales.
`tools/test_shader_assets.py` comprueba firmas, dimensiones y SHA-256 de las
cinco imágenes y tres partículas, licencias, y descarga/cache del AssetManager
con red y executor simulados. El boot real del bundle y la matriz de siete
lugares comprueban el panel con mocks de PC y móvil.

La compilación y los mocks no dibujan ningún píxel ni miden GPU, memoria o FPS.
No verifican si Delta admite `getcustomasset`, si el juego usa superficies
compatibles, o si otro efecto/ajuste gráfico altera el resultado. Probar con
calidad gráfica suficiente en un mapa con un piso de bloques y vidrio, esperando
la descarga y el barrido; comparar Shaders ON/OFF y observar si aparece un aviso
de assets. Si no se ve, hace falta una captura, mapa, nivel gráfico y el texto
del aviso para diagnosticarlo, no afirmar que ya se ve.

Auto Farm, Fling y demás módulos no se modificaron en este cambio.
