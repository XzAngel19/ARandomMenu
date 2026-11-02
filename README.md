# Wurst

Menú para Roblox con módulos universales y para MM2, BedFight, TRS, VD y X2.
La versión de esta sesión está en la rama `arena/9492e6b6-arandommenu`; `main`
es independiente.

## Loader

```lua
getgenv().WURST_BRANCH = "arena/9492e6b6-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/9492e6b6-arandommenu/src/Wurst.lua"))()
```

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
