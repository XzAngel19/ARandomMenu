# Skill — revisar Shaders, clima y keybinds

Procedimiento técnico reutilizable; no instala plugins ni ejecuta código externo.
Se aplica a `src/games/universal/Render/Shaders.lua` y, si hay un problema de
teclas, al despacho de `src/Wurst.lua`. Ver primero `RESUME.md` y el último
`docs/FIXES-vNNN.md`. `Floor reflections` y su antigua librería se retiraron en
v178: no volver a añadir un espejo de parches como si cubriera todo el mapa.

## 1. Recoger evidencia

- Pedir mapa, plataforma, calidad gráfica, tarjeta y opciones activas; comparar
  con el menú cerrado, pues abierto aplica desenfoque. Leer `Diagnose`.
- `visits`, `reservedVisits` y `noStyleVisits` son **visitas acumuladas**, no
  piezas distintas. `configuredRate` es la suma configurada, no emisión real.
  `covered` puede ser normal bajo techo; `terrain=true` no demuestra que haya
  agua. Ni `PreloadAsync` ni mocks demuestran que el cliente dibuje píxeles.
- Distinguir clima global de niebla de distancia, partículas cerca de cámara,
  materiales individuales y brillo ambiental; no prometer SSR/RTX.

## 2. Diseñar bajo límites

- Priorizar APIs de Roblox documentadas y fallbacks seguros. `Atmosphere`
  reemplaza `FogEnd`; `ParticleEmitter.Acceleration` influye en partículas ya
  emitidas, pero no hay fuerza por partícula ni un hueco en la niebla global.
- Una cuadrícula acotada puede ampliar la cobertura visible pero no cubrir
  mundos arbitrariamente grandes/zonas no recibidas por streaming. Un raycast
  del cliente solo ve lo cargado. No construir un emisor por pieza/personaje.
- Presupuestar `Rate`, `Lifetime`, tamaño, superposición, emisores, raycasts y
  llamadas en CPU. Respetar el perfil móvil/táctil, techo y calidad; conservar
  una alternativa si una propiedad opcional no está disponible. No bajar
  densidad ni aumentar cobertura afirmando que se ve mejor sin prueba visual.
- El barrido es incremental, usa señales para streaming/decals, limita cola y
  registros y solo hace pasadas completas lentas. No poner `GetDescendants()` o
  bucles por jugador/mapa en cada frame. No alterar colisiones ni materiales
  físicos; respetar personajes, decals y los cambios posteriores del juego.
- Mantener cada opción independiente; OFF/Destruct deben desconectar y destruir
  recursos, cancelar tareas antiguas y restaurar condicionalmente los valores.

## 3. Verificar y publicar

- Extender `tools/test_shaders.py`, `tools/test_shader_fog_movement.py` y/o
  `tools/test_shader_surface_efficiency.py` según el cambio. Cubrir local y
  remotos, respawn, streaming, cámara ausente, techo y fallo de API; comparar
  límites de trabajo a distintas tasas de frames, no etiquetarlos como FPS real.
- Si cambian atajos, correr `tools/test_shortcut_game_input.py` y las suites de
  keybinds MM2; no confundir el botón de Gun Aimbot con un toggle.
- Actualizar `SOURCE_STAMP`, ejecutar `python3 tools/build_bundle.py --stamp …`,
  `bash tools/validate.sh`, `git diff --check`, commit y push normales a la rama
  de la sesión. Documentar qué se verificó por mocks y qué requiere Roblox/Delta.

Documentación principal: [ParticleEmitter](https://create.roblox.com/docs/effects/particle-emitters),
[Atmosphere](https://create.roblox.com/docs/environment/atmosphere),
[streaming](https://create.roblox.com/docs/workspace/streaming/techniques) y
[ViewportFrame](https://create.roblox.com/docs/ui/viewport-frames). Fuentes de
assets, versiones y licencias: `docs/third-party/shaders/README.md`.
