# v175 — Shaders universal: cualquier suelo, fog realista y vidrio/texturas visibles

## Contexto

El usuario reportó con captura (`Ivan's Adventure II`) el mensaje:

> `Shaders: Floor reflection needs a nearby flat solid floor`

Sobre un piso dorado/marrón aparentemente válido, `Surface textures`, `Glass reflections`, `Fog`, `Rain/Snow` seguían sin verse como shaders reales. Pidió que todo funcione **client-sided, en cualquier juego de Roblox y sobre cualquier suelo**, con un fog mucho más realista que el actual, y fijó la versión en **v175**. Se investigaron los hilos de `devforum` sobre shaders (`ColorCorrection + contraste + SurfaceGui delante de cámara`) y la documentación de `Lighting.FogEnd/FogStart/FogColor`.

La causa: `ShaderReflection` solo aceptaba pisos estrictos — `Anchored`, `Transparency <0.95`, `UpVector.Y >=0.97`, `Size.X/Z >=3` y además `>=6` para el registro — y el `Raycast` de 15 studs descartaba `MeshPart/Union/Terrain` o pisos con material `Plastic` pequeño. `textureStyle` solo texturizaba materiales mapeados (`Concrete/Plastic>=12/Wood/Brick/...`) y `wantedReflection` solo `Glass` o `Plastic+nombre ventana`. `Fog` solo usaba `Atmosphere` sin tocar `Lighting.Fog*`, por lo que a distancia no se notaba.

## Cambios

- **Floor reflections universal (ShaderReflection.lua):**
  - Se conserva el camino estricto (fidelidad máxima con clamp a los bordes del `Part` real, hasta 64×64 detalle + capa amplia 256×256).
  - Nuevo fallback genérico: si el hit tiene `Position`+`Normal` con `Normal.Y >=0.85` y distancia `<=18`, se acepta:
    - `Terrain` siempre;
    - `BasePart` walkable si `Anchored`, `Transparency <0.90`, `Size.X/Z >=3` y `UpVector.Y >=0.80` (pendientes suaves).
  - El plano genérico es de **32×32 studs** a `+0.06` del hit, con `CFrame.new` si es horizontal o `CFrame.fromMatrix(right,up,-forward)` si es inclinado. Ya no exige ser un `Part` enorme y plano perfecto: un `MeshPart`, `Union` o `Terrain` de cualquier juego ahora genera reflejo.
  - `loseFloor`, `scanScene`, `updateWork` y `render` ahora dependen de `planePoint` en lugar de solo `currentFloor`, y `isScenePart` sigue excluyendo el piso activo. Mensaje de error solo tras 6 s sin ningún hit válido.
  - Se mantienen los 3 viewports máximos, 54/32 copias y límites móviles.

- **Surface textures más visibles (Shaders.lua `textureStyle`):**
  - `Plastic/SmoothPlastic` bajo de `Size >=12` a `>=8` y `Y <=4`, para pisos típicos de 8–10 studs.
  - Fallback universal: cualquier `Part` plano (`floorShape`) que no sea `Glass/ForceField` y sin `MaterialVariant` recibe `concrete` aunque su material sea `Metal/Slate/Sand/DiamondPlate`, etc. Así `Surface textures = ON` se ve en casi cualquier mapa sin inventar PBR.

- **Glass reflections ampliado (`wantedReflection`):**
  - `Glass` siempre 0.22;
  - `ForceField` con `0.15 <= Transparency <0.9` → 0.22;
  - `Plastic/SmoothPlastic` con `Transparency >=0.15` y (`window` en nombre o `>=0.25`) → 0.22;
  - Genérico: `Transparency 0.2–0.85` + área `>=16` + `Plastic/SmoothPlastic/Metal` → 0.22. Cubre ventanas transparentes de muchos juegos sin marcar cada pieza.

- **Fog realista (Shaders.lua `refreshFog/releaseFog`):**
  - Se preserva `Atmosphere.Density =0.38` (compatibilidad con tests) pero se sube `Haze 1.25→1.65`, `Glare 0.1→0.14`, `Color 218,227,238`, `Decay 148,164,180`.
  - Además, en cliente se escribe `Lighting.FogColor = 199,212,225`, `FogStart =55`, `FogEnd =420` (niebla de distancia documentada en `Lighting.FogEnd`). Al apagar se restaura solo si el valor sigue siendo el aplicado (no pisa cambios externos del juego). Esto da un fog visible en exteriores + partículas cercanas en interiores, sin perder la `Atmosphere` existente.
  - `releaseFog` ahora limpia también `fogLightingOriginal/Applied`.

- No se tocan `Rain/Snow/Falling leaves/Dust` (9 celdas, raycast cada 0.15 s, splashes) ni los presupuestos de CPU/GPU: solo se asegura que `Floor reflections` no bloquee su visibilidad.

## Límites

- No es RTX/SSR ni espejo global: hasta 3 `ViewportFrame`, copias sanitizadas (solo geometría+Decal), ropa clásica vía `Humanoid` pero capas/mallas asimétricas pueden diferir. `Terrain` y pendientes fuertes se aproximan con un plano genérico, no con deformación del suelo.
- Texturas siguen siendo `Texture.ColorMapContent` 2D (fallback `rbxassetid` de materiales Roblox), no `SurfaceAppearance` PBR ni cambio de `MaterialVariant`.
- Fog de distancia depende de `Lighting.Fog*` del executor; si el juego sobrescribe `FogEnd` cada frame, nuestra restauración lo respeta. Calidad gráfica 21+ recomendada para partículas.
- Medición offline: `test_shader_reflection` y `test_shaders` no renderizan píxeles ni miden FPS. Probar en Roblox/Delta con menú cerrado, tercera persona sobre piso sólido, alternando `Floor reflections` y `Fog` ON/OFF.

## Pruebas

- `LUAU=tools/luau/bin/luau python3 tools/test_shader_reflection.py` — 19 suites (geometría off-axis, seguimiento del avatar, FOV, culling, missing-floor warning, pendientes/móviles/pequeños, espejos adicionales, capa amplia, fallback genérico, integración con `Shaders`).
- `bash tools/validate.sh` — 84 fuentes en bundle, 116 suites Python/Luau, `failures=0`, menú 50/49. `Fog uses atmosphere plus independent particles and restores dynamic replacements` pasa con los nuevos `FogStart/End`.

Pendiente live: Verificar en `Ivan's Adventure II` y otros juegos que el reflejo aparece sobre cualquier suelo (Terrain/Mesh/Union), que `Surface textures` tiñe pisos `Plastic` pequeños y que `Fog` se note a distancia sin blanquear en exceso. Capturar `Shift+F9` calidad, `WurstBlur` off.
