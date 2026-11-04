# Wurst

Menú para Roblox con módulos universales y para MM2, BedFight, TRS, VD y X2.
La versión de esta sesión está en la rama `arena/9492e6b6-arandommenu`; `main`
es independiente.

## Loader

```lua
getgenv().WURST_BRANCH = "arena/9492e6b6-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/9492e6b6-arandommenu/src/Wurst.lua"))()
```

## Shaders

`Render > Shaders` aplica efectos **solo en el cliente**. La iluminación, Fog,
Rain, Snow, Falling leaves, Dust motes, Surface textures, Glass reflections, Wet
surfaces y Water reflections siguen siendo independientes. No hay `Look` ni
presets. Se retiró `Floor reflections`: sus viewports solo reflejaban unos pocos
pisos y no podían cubrir de manera realista todo el mapa con un coste razonable.
Glass/Wet proporcionan brillo ambiental, no reflejos dinámicos de personajes.

Fog combina niebla global de Roblox con 17 parches de partículas, incluidos
parches exteriores más dispersos. Al caminar tu personaje u otros jugadores,
los parches cercanos responden desplazando sus
partículas; el cálculo se limita y reparte entre jugadores. Es una aproximación,
no una simulación de fluido: el `Atmosphere`/`FogEnd` global no se puede apartar
alrededor de los cuerpos. Se restaura la niebla del juego al apagar, cuando el
valor sigue siendo el aplicado por el menú.

Rain, Snow, hojas y niebla usan celdas cercanas y un anillo exterior que abarca
aproximadamente **336 × 336 studs alrededor de la cámara**. Las celdas del clima
comprueban el techo gradualmente; en interiores puede haber lluvia fuera aunque
el centro esté protegido. Si falla el raycast se avisa y las partículas pueden
atravesar techos. El polvo queda más cerca de la cámara;
**no se garantiza clima en cada punto de mapas más grandes ni en zonas que el
cliente aún no ha cargado**.

El barrido de superficies visita progresivamente el mapa cargado, incluso lejos
del jugador, sin eliminar lo ya tratado por distancia. Solo modifica piezas
compatibles; respeta decals y personajes y tiene límites de **600 texturas** y
**1.200 cambios de reflectancia**. Alcanzarlos deja otras piezas sin cambios y
produce un aviso. `Water reflections` afecta al Terrain si existe; eso no implica
que haya agua visible. La iluminación y niebla de distancia afectan a la escena
visible, pero las mallas, materiales personalizados, calidad y streaming pueden
limitar el resultado.

En escritorio el presupuesto configurado con todo el clima activo es 1.978
partículas/s; en móvil o dispositivos táctiles, 927/s, más salpicaduras manuales
limitadas. Son máximos configurados, no partículas necesariamente visibles ni
una medición de FPS. El barrido trabaja en lotes, escucha el streaming y espera
30 s antes de repetir una pasada completa; ya no se fuerzan sombras si el juego
las tenía apagadas. No se ha medido CPU/GPU ni probado visualmente en Roblox o
Delta: los efectos aún pueden causar lag o no verse en algún dispositivo/juego.
Las imágenes se cargan bajo demanda con respaldos de Roblox; incluso una
precarga exitosa no garantiza que se dibujen. Fuentes y límites:
`docs/third-party/shaders/README.md`.

El botón **`Diagnose`** muestra el estado del clima, parches de niebla,
jugadores en movimiento muestreados, tasas configuradas, visitas al mapa,
límites y Terrain. Las visitas son acumuladas, no piezas únicas. Una celda
`covered` bajo techo puede ser normal; tampoco confirma por sí sola que el
clima se haya dibujado. Los **keybinds** siguen funcionando aunque el juego use
la tecla, salvo al escribir o capturar una tecla; con el menú cerrado aparece
un aviso al activar/desactivar Shaders.

Para probar, cierra el menú (abierto aplica desenfoque), activa Fog por separado
y camina cerca de otro jugador. Prueba Rain/Snow al aire libre y desde un
interior mirando afuera. Si algo no se ve, comparte una captura y el resultado de
`Diagnose`, con mapa, plataforma y calidad gráfica.

## Desarrollo

`src/libraries/Manifest.lua` es el catálogo de módulos; `src/Wurst.lua` carga
el bundle y descarga los assets de la interfaz por separado. No edites
`src/libraries/bundle.lua` a mano. Tras cambiar fuentes, actualiza el
`SOURCE_STAMP` y ejecuta:

```bash
python3 tools/build_bundle.py --stamp <SOURCE_STAMP>
bash tools/validate.sh
```

Se conservan las pruebas, sus fixtures y la herramienta de Luau. La validación
es simulada: no sustituye probar Roblox, Delta ni el servidor. Los detalles y
contratos del proyecto están en `RESUME.md`.
