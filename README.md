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

Al activar `Render > Shaders` se aplican iluminación y reflejos ambientales,
con texturas de color en superficies compatibles cercanas. No hay selector de
`Look`: `Fog`, `Rain`, `Snow`, `Falling leaves`, `Dust motes`, `Wet surfaces` y
`Water reflections` son opciones independientes. `Surface textures` y
`Glass reflections` también se pueden apagar. Al desactivar Shaders se retiran
sus efectos y se restauran los valores que aún controla.

Las imágenes se descargan bajo demanda. Mientras cargan, o si el executor no
permite assets locales, se intentan imágenes de materiales de Roblox; si fallan
los assets propios aparece un aviso. La disponibilidad de ambos tipos depende
del cliente. Solo se retocan ciertas piezas, no todas las mallas del mapa. La
calidad gráfica y el juego pueden limitar los cambios visibles. Son efectos
nativos y mapas de color, no RTX, ReShade ni PBR completo. Fuentes y licencias
en `docs/third-party/shaders/README.md`.

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
