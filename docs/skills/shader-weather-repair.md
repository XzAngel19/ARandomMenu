# Skill — reparar clima y keybinds de Shaders

Formato de *skill* (como los catálogos `everything-claude-code` /
`antigravity-awesome-skills`): cuándo usarlo, entradas, flujo por fases y
puertas de verificación. No describe una personalidad: describe el
procedimiento que un agente debe seguir para que el trabajo quede completo y
comprobable.

## Cuándo usar

- El usuario reporta que `Rain`, `Snow`, `Fog`, reflejos o texturas «no se ven»
  o «se ven muy débiles».
- Un efecto del menú funciona con clic pero no con keybind (sobre todo en MM2).
- Hay que tocar `src/games/universal/Render/Shaders.lua`,
  `src/libraries/ShaderReflection.lua` o el despacho de atajos de `src/Wurst.lua`.

## Entradas

1. `RESUME.md` §1 (protocolo de publicación) y el informe `docs/FIXES-vNNN.md`
   más reciente.
2. Captura/log del usuario si existe (mapa, calidad gráfica, menú abierto o
   cerrado). Sin captura, el diagnóstico es **hipótesis**, no causa.
3. Documentación del motor que se va a tocar, leída en el momento:
   - [ParticleEmitter](https://create.roblox.com/docs/effects/particle-emitters):
     `Rate` tope 400/s escritorio y 100/s móvil, `Lifetime` tope 20 s, `Squash`
     negativo con `VelocityParallel`, cuadrícula de emisores para lluvia densa.
   - [Atmosphere](https://create.roblox.com/docs/environment/atmosphere):
     `Density` 0–1, `Haze` 0–10, `Offset`, `Glare`; reemplaza `FogEnd`.
   - [Lighting.FogEnd](https://create.roblox.com/docs/reference/engine/classes/Lighting#FogEnd).
4. Referencia de efecto denso: [buildthomas/Rain](https://github.com/buildthomas/Rain)
   (Apache-2.0, `NOTICE-Rain.txt`): `Rate` 600, `Lifetime` 0,8, `Speed` 60,
   texturas `1822883048` (trazo) y `1822856633` (salpicadura/top-down).

## Flujo

### Fase 1 — Medir el estado actual (no adivinar)

- Leer la tabla de perfiles (`WEATHER`) y contar emisores y partículas/s reales.
- Calcular partículas vivas = `Rate × Lifetime` por emisor.
- Buscar el camino de activación: clic y keybind deben llegar al mismo
  `onToggle`. Si no, el fallo está en el despacho de atajos, no en Shaders.

### Fase 2 — Corregir la causa, no el síntoma

- Densidad: subir `Rate` por emisor y añadir capas; nunca pasar de los topes del
  motor. Escalar por móvil en el mismo lugar donde se crea el emisor.
- Visibilidad: textura adecuada (trazo vs. cuadrado), `Size`, `Squash`,
  `LightEmission`/`LightInfluence` para mapas oscuros.
- Oclusión: `RespectCanCollide` para que decoraciones no-colisionables no
  bloqueen la lluvia; no apagar emisores al mover la cámara (produce el efecto
  «llueve solo un instante y desaparece»).
- Fog: `Atmosphere` del juego si existe (`Density`/`Haze`), si no
  `FogStart`/`FogEnd`/`FogColor`; niebla de partículas propia y visible.
- Keybind: quitar la puerta `gameProcessed` (el juego ya usó la tecla) y
  conservar la puerta de `TextBox`/captura para no disparar al escribir.

### Fase 3 — Presupuesto y limpieza

- Un único tope total de partículas/s y de emisores por celda.
- Todo lo creado se destruye al apagar; se restauran los valores del juego.
- Ningún bucle nuevo sin nombre en el reporte de rendimiento.

### Fase 4 — Pruebas

- Extender `tools/test_shaders.py` con los valores nuevos y, sobre todo, con el
  comportamiento: mover la cámara no apaga la lluvia, un techo no-colisionable
  no la bloquea, el presupuesto no se excede, OFF restaura.
- Test aparte para el despacho de atajos con `gameProcessed = true`.
- `python3 tools/audit_performance.py` no debe quejarse del bucle de clima.

### Fase 5 — Publicar

- `SOURCE_STAMP` nuevo, `python3 tools/build_bundle.py --stamp`, `bash
  tools/validate.sh` verde, commit y push normales a la rama de la sesión.
- Informe `docs/FIXES-vNNN.md` con cambios, presupuestos y **límites**: las
  pruebas son simuladas, no píxeles ni FPS.

## Puertas de verificación (todas obligatorias)

| Puerta | Cómo se comprueba |
| --- | --- |
| Densidad mínima | `test_shaders.py` exige `Rate` y partículas vivas por encima del umbral |
| Sin parpadeo al moverse | test: tras saltos de cámara, todos los emisores siguen `Enabled` |
| Oclusión coherente | test: techo colisionable oculta, decoración no-colisionable no |
| Presupuesto | test: suma de `Rate` ≤ tope del código |
| Restauración | test: OFF devuelve `FogEnd`/`Atmosphere`/`WaterReflectance` |
| Keybind en juego | test real del bloque de `Wurst.lua` con `gameProcessed=true` |
| Regresión | `bash tools/validate.sh` completo en verde |
