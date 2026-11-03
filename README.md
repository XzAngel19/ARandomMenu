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

Al activar `Render > Shaders` se aplica iluminación cálida y se intenta un
reflejo local del avatar y parte del entorno sobre el piso cercano. La opción
`Floor reflections` puede apagarse por separado. Es una aproximación: requiere
una pieza sólida, anclada y casi plana bajo el personaje, cubre solo una zona y
no equivale a RTX, SSR ni ReShade. Las mallas irregulares, la ropa y los detalles
pueden verse distintos; hay que comprobar el resultado en el juego.

No hay selector de `Look`: `Fog`, `Rain`, `Snow`, `Falling leaves`, `Dust motes`,
`Wet surfaces`, `Water reflections`, `Surface textures` y `Glass reflections`
son opciones independientes. Lluvia, nieve y hojas se detienen bajo techo; el
polvo también aparece en interiores. Al desactivar Shaders se retiran sus efectos
y se restauran los valores que aún controla.

Las imágenes se descargan bajo demanda. Mientras cargan, o si el executor no
permite assets locales, se intentan imágenes de materiales de Roblox; si fallan
los assets propios aparece un aviso. La disponibilidad de ambos tipos depende
del cliente. Solo se retocan ciertas piezas, no todas las mallas del mapa. La
calidad gráfica y el juego pueden limitar los cambios visibles. Son efectos
nativos y mapas de color, no PBR completo. Fuentes y licencias en
`docs/third-party/shaders/README.md`.

Para probar el reflejo, usa cámara en tercera persona sobre un piso compatible,
activa `Shaders` y `Floor reflections`, espera unos segundos y compara al apagar
solo ese toggle. Si la escena se recarga o desaparece el piso, la copia se
reconstruye. No se ha verificado el resultado visual ni el rendimiento en Delta.

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
