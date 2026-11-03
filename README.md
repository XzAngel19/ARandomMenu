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

`Render > Shaders` usa efectos **locales al cliente**. `Floor reflections`
intenta un reflejo intenso sobre el piso plano del personaje y pisos compatibles
frente a la cámara. Para conservar detalle cerca del avatar, el plano principal
abarca hasta 64 × 64 studs; si el piso es mayor, una segunda capa cubre hasta
256 × 256 y queda espacio para un piso adicional. En pisos pequeños pueden
mostrarse hasta dos pisos adicionales. Los viewports copian solo parte de la
escena: no es un espejo global, RTX ni SSR. Terrain, pendientes fuertes, objetos
omitidos, ropa o mallas irregulares pueden verse distintos o no reflejarse.

No hay selector de `Look`. `Fog`, `Rain`, `Snow`, `Falling leaves`, `Dust motes`,
`Wet surfaces`, `Water reflections`, `Surface textures` y `Glass reflections`
son opciones independientes. Fog combina atmósfera con partículas. Las celdas de
lluvia y nieve hacen pruebas de techo; las exteriores cercanas pueden verse
desde interiores. El barrido de superficies recorre progresivamente el mapa,
sin limitarse al lugar donde camina el jugador, pero solo modifica piezas
compatibles y tiene límites de recursos; puede tardar y no cubre todas las
mallas. Glass/Wet usan reflectancia ambiental, no el reflejo de personajes.
Al apagar se retiran los efectos y se restauran los valores aún controlados.

Las imágenes se descargan bajo demanda y pueden intentar recursos de Roblox como
respaldo. La disponibilidad depende del executor y la calidad gráfica. No se
ha probado la apariencia ni el rendimiento en Roblox/Delta: tres viewports,
partículas y sombras pueden ser costosos. Si notas lag, apaga `Floor reflections`
o los efectos que no uses. Fuentes, licencias y límites detallados en
`docs/third-party/shaders/README.md`.

Para comparar, prueba primero `Shaders` con `Floor reflections` encendido y
apagado en tercera persona sobre un piso sólido. Cierra el menú para comparar:
al abrirlo se aplica un desenfoque de la interfaz, independiente de Shaders.
Prueba Fog y Rain por separado, y Rain cerca de una salida. Espera a que se
recorra el mapa y revisa los avisos.

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
