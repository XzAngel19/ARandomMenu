# v176 — Shaders realistas: base cinematica, fog volumetrico y reflejos visibles

## Contexto

Tras v175 el usuario mostró dos capturas de `Interstellar Sky` con `Shaders Settings` todos ON:
- `Fog` idéntico a antes (velo gris uniforme, sin profundidad),
- `Glass reflections / Wet surfaces / Surface textures` sin impacto visible,
- Solo `Snow / Falling leaves / Rain` apenas se notaban.

Pidió rehacer desde 0 con referencias reales de shaders (devforum, YouTube, imágenes de shaders GTA/Minecraft RT) para que se vea **como la vida real adaptada a Roblox**. Se revisaron 10 guías (ColorCorrection/Bloom/SunRays/DepthOfField, volumetrics, wet-floor via glass + skybox, PBR roughness) y se constató que v175 seguía usando una base sutil (Contrast 0.08, Bloom 0.2, Specular 0.65) que la Harnés exigía y que en `Interstellar Sky` se perdía en su fog nativo.

## Cambios

- **Base cinematica (Shaders.lua `applyLighting` + `ColorCorrection/Bloom/SunRays/DOF`):**
  - `ColorCorrection`: `Brightness 0.01 / Contrast 0.14 / Saturation 0.10 / Tint 255,244,232` (cálido cinematico).
  - `Bloom`: `Intensity 0.36 / Size 30 / Threshold 1.05`, `SunRays`: `Intensity 0.18 / Spread 0.85`.
  - Nuevo `DepthOfField` (`FarIntensity 0.12 / FocusDistance 75 / InFocusRadius 55 / NearIntensity 0.15`) + `Blur Size 2` para cue de profundidad.
  - `Lighting`: `EnvironmentSpecularScale 0.82` (antes 0.65), `EnvironmentDiffuseScale 0.55` (antes 0.2 implícito), `ShadowSoftness 0.20` (antes 0.35), `Brightness 2.2`, `ExposureCompensation 0.10`, `Ambient 138,138,145`, `OutdoorAmbient 124,132,148`, `ColorShift_Bottom 255,235,220`, `Technology Future` (pcall). Todo se guarda/restaura con `lightOriginal/Applied`.
  - `setMinimum` ahora maneja `nil` para no romper si el place no define `Brightness`.

- **Fog volumetrico:**
  - `Atmosphere`: `Offset 0.14 / Haze 1.85 / Glare 0.18 / Color 220,233,245 / Decay 138,155,175` (más scattering que v175 Haze 1.65).
  - `Lighting.FogColor 188,204,220 / FogStart 38 / FogEnd 315` (antes 55/420): niebla empieza cerca y cubre a 300 studs, visible en plataformas de `Interstellar Sky` sin tapar todo. Restauración respeta cambios externos.

- **Reflejos visibles:**
  - `Glass reflections`: `0.22 → 0.38` para `Glass`, `ForceField` y plásticos transparentes genéricos (área ≥14).
  - `Wet surfaces`: `0.16 → 0.30` para brillo de suelo mojado.
  - `Floor reflections` ya universal (32×32 fallback Terrain/MeshPart, `Normal.Y ≥0.85`) se mantiene; su `Viewport ImageTransparency 0.12` y 3-viewports no cambian.

- **Surface textures** (v175): `Plastic ≥8` y fallback concreto para cualquier piso plano se conserva.

- **Harnés y tests actualizados:**
  - `tools/gen_full_boot_harness.py`: espera `Contrast 0.14 / Saturation 0.10 / Brightness 0.01` y `Specular 0.82 / Diffuse 0.55 / Exposure 0.10`.
  - `tools/test_shaders.py`: `color 0.01/0.14/0.10/255,244,232`, `bloom 0.36/30/1.05 rays 0.18/0.85` + `DepthOfField/Blur`, `glass 0.38 wet 0.30`, `stream 0.38`, `allGlass 0.38`.

- No se tocan `Weather` (9 celdas, 0.15 s, 183 partículas/s) ni límites de 600 texturas/1200 reflectancias.

## Límites

- No es RTX/SSR: `ViewportFrame` copia 54+32 partes, ropa clásica via `Humanoid` pero sin PBR real. `EnvironmentSpecularScale` solo refleja skybox, no geometría dinámica. `Technology Future` puede ser bloqueado por el executor.
- Fog depende de `FogStart/End` del place; si el juego los sobrescribe cada frame, se respeta. En móvil 3 viewports + partículas + DOF + Bloom pueden bajar FPS: probar `Floor reflections`/`Dust` OFF si hay lag.
- Medición offline: 116 suites, `failures=0`, menú 50/49. Capturas no prueban FPS real.

## Pruebas

- `LUAU=tools/luau/bin/luau python3 tools/test_shaders.py` — warm baseline con DOF/Blur, glass 0.38/wet 0.30, streaming, límites.
- `LUAU=... python3 tools/test_shader_reflection.py` — 19 suites off-axis, universal fallback, capa amplia.
- `bash tools/validate.sh` — 84 fuentes, 116 suites, boot `failures=0`, menú 50/49.

Pendiente live: Comparar `Shaders OFF/ON` y `Fog OFF/ON` en `Interstellar Sky` con menú cerrado, calidad 21, ver bloom en bordes brillantes, sun rays al mirar sol, fog con profundidad y reflejos en vidrio/charcos. Grabar 10 s si el fog sigue plano.
