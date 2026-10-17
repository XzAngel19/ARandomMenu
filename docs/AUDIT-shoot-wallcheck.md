# Auditoría Shoot / WallCheck — MM2 (rama `arena/72024298-arandommenu`)

**Base de código:** `arena/7905a47c-arandommenu` (`52bc4f9`), sin cambios de código en esta rama.
**Fecha:** 2026-10-17

## Estado: no se cambió código de disparo

Tras revisar las pruebas de 7905, no apliqué cambios de disparo. Motivos:

1. `tools/test_mm2_precision.py` afirma que **no existe** `GUN_SERVER_COOLDOWN` ni `lastGunFireServer`. Tú indicaste que el enfriamiento no sirve, así que no lo reintrodujimos.
2. `tools/test_gun_safety.py` / `test_mm2_precision.py` fijan que el rayo del arma es **estricto** (no comparte el filtro de Knife ni salta partes transparentes). Cambiarlo altera una decisión de seguridad que no puedo validar sin jugar. Ver pregunta abajo.
3. Las suites necesitan el runtime `luau`, que no pude instalar en el sandbox (la descarga de releases de GitHub está bloqueada). Solo pude validar sintaxis con StyLua (parser Luau) y ejecutar las suites Python.

## Hallazgo crítico: el bundle tiene prioridad

`src/Wurst.lua` carga `src/libraries/bundle.lua` **antes** que los módulos si su `stamp` coincide con `SOURCE_STAMP`. Por eso, **cualquier edición en `src/games/...` no tiene efecto** hasta ejecutar:

```
python3 tools/build_bundle.py --stamp <nuevo-stamp>   # y subir SOURCE_STAMP en src/Wurst.lua
python3 tools/build_bundle.py --check                  # debe decir "current"
```

Verificado en esta rama: el bundle coincide byte a byte con `Shoot.lua` y `bundle.lua` está "current". Si en alguna prueba el código nuevo "no hace nada", revisa esto primero.

## Datos del juego (fuentes)

Fuente: `XzAngel19/TestingStuff` — `place, source.rbxlx` (scripts cliente completos; scripts de servidor no guardados), `MM2_Trajectory_Calibration*.json`, logs `2026-10-15/16`.

### Filtro de muros del juego (verificado en `WeaponService`)

El cliente oficial apunta el arma con un raycast que:
- excluye el propio personaje y los objetos con tag `WeaponPassthrough`;
- **salta partes con `Transparency == 1`** y sigue buscando;
- cualquier otra parte bloquea.

`computeGunAim` ya usa este filtro, pero `validateGunShot` (la compuerta final antes de `FireServer`) usa `isGunPathClear`, que es **estricto**: no salta partes invisibles. Resultado: el apuntado puede dar "libre" y la validación final "bloqueado". **Esta es la inconsistencia principal de WallCheck en 7905.**

### Telemetría de disparos (`MM2_Trajectory_Calibration.json`, build v35)

- 33 confirmaciones de disparo del servidor: **20 impactaron** al objetivo, 13 no.
- Error endpoint → posición observada del objetivo: impactos 1.8–3.3 studs; fallos hasta 6.2 studs.
- Latencia de confirmación: 112–208 ms (una de 362 ms).
- Mejor modelo de movimiento según la propia telemetría: `observedAcceleration` en 24 de 33 casos.
- Un disparo a 17.9 studs con WallCheck activo impactó un `Union` (muro): la validación no lo detectó en ese instante.

### Cadencia

- 2026-10-15: dos disparos separados 0.16 s produjeron **un solo** eco `GunFired`. El segundo no fue aceptado.
- Separaciones aceptadas más cortas en la telemetría: ~3.3 s. Pero esa build ya tenía su propio gate cliente, así que no prueba el límite del servidor.

## Rama 2daf1a78 (predictor "bueno")

Su `computeGunAim` es más simple: horizonte RTT, lead con descuento, sin tope vertical (`clamp -3..6`), sin el filtro de muros del cliente y sin la lógica de paradas. No encontré evidencia en los logs de que sea más preciso que 7905. No la porté.

## Rama 6c16216 (arena/184d6123)

- Tiene un gate de cadencia de 3.1 s y confirmación por eco `GunFired`.
- Eliminó `validateGunShot` / `isGunPathClear` / `gunBystanderOnRay`: el disparo normal ya no comprueba bystanders ni muros estrictos.
- Su texto de UI "otros jugadores bloquean aunque WallCheck esté OFF" es falso para el disparo normal.

## Pregunta abierta (decide tú)

¿El rayo de WallCheck debe copiar el filtro del juego (saltar `Transparency == 1`) o quedarse estricto?
- Copiar el juego: menos falsos "muro", coherente con el apuntado, pero podría disparar a través de muros invisibles.
- Estricto (actual): más conservador, pero bloquea tiros que el propio cliente considera libres.

Hasta tener eso decidido y poder correr `luau` en las pruebas, no cambio la lógica de disparo.
