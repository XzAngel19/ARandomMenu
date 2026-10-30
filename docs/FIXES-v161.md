# v161 — Prediction con lazo cerrado (Bullet y CFrame) y el módulo Shaders

Fecha: 2026-10-30 · Stamp: `v161-20261030-prediction-shaders`

Dos cosas: (1) el `Prediction` de MM2 por fin **usa** lo que mide, y separa lo
que aprende por vía de disparo; (2) módulo universal nuevo **Shaders** en
Render. Todo lo que sigue está medido con las capturas que aportaste
(`MM2_Trajectory_Calibration-4.json`, sesión `354627F6`, stamp v159; y
`…json.before-3FADBDA3…`, sesión `221E2F3D`, stamp v157) o con las suites del
repo. Nada aquí demuestra aceptación del servidor ni hit-rate.

## 1. El problema real: la corrección se medía y se tiraba

Desde v120 el predictor calculaba `leadError` en cada confirmación, la guardaba
en el evento de calibración… y **no la aplicaba a nada**: el horizonte se
quedaba fijo. Los datos de tu sesión lo enseñan en pequeño: los cuatro tiros
confirmados tenían `leadCorrection` de 0, 0, +11,3 ms y +13,0 ms, y el
horizonte usado era el mismo en los cuatro.

v161 la aplica, con tres frenos para no repetir el fallo que hizo quitarla:

| Freno | Valor | Por qué |
|---|---|---|
| Muestras mínimas antes de mover nada | 3 | Dos muestras no son una mediana |
| Tope por corrección | ±60 ms (`MAX_LEAD_CORRECTION`) | Un sesgo no puede comerse el plomo entero |
| Paso máximo por confirmación | 20 ms (`LEAD_SLEW_PER_SAMPLE`) | El error se mide *después* de la corrección anterior; sin paso limitado el lazo oscila |

Y una separación que antes no existía:

- **Bullet** (`mode = Normal`, CFrame `lookAt`) y **CFrame/Silent** (`mode =
  Silent`, origen+punto explícitos) llevan **cubetas de error distintas**. Se
  autoricen como se autoricen, no hay ninguna evidencia de que el servidor
  rebobine igual las dos, así que el sesgo medido en una no debe mover la otra.
  `Prediction.gunAim(target, muzzle, mode)` recibe el modo; `AutoShoot`,
  `AutoWin`, `AutoFarm` y `Shoot` lo pasan.
- El **cuchillo** usa la cubeta neutra (`default`), que nadie alimenta: las
  capturas solo puntúan la pistola. Antes de v161 el cuchillo habría heredado
  cualquier sesgo de pistola.

### Cuánto mejora (replay offline, no hit-rate)

`tools/replay_lead_loop.py` lee los `leadErrorSeconds` grabados y simula el lazo
con las constantes leídas del propio `Prediction.lua` (no pueden desviarse):

```
python3 tools/replay_lead_loop.py <captura.json> [...]
```

| Sesión | Confirmaciones | error de plomo grabado | con lazo v161 |
|---|---|---|---|
| `354627F6` (v159) | 4 | 15,4 ms de media · 15,8 de mediana | 9,3 ms · 9,3 ms |
| `221E2F3D` (v157) | 10 | 39,6 ms · 23,4 ms | 26,7 ms · 5,2 ms |

Es una afirmación sobre el mecanismo: dice cuánto se acercaría el plomo del
**siguiente** disparo si el error medido se corrige. No dice que el servidor
acepte más tiros.

### Lo que las capturas dicen que NO era el problema

De los dos fallos de la sesión v159, ninguno era de plomo:

- `4:12` terminó a **0,24 studs** del torso (plomo +11,3 ms, error residual 0)
  y aun así no hizo daño. El `occluder` grabado es
  `Workspace.Workplace.Raggy.HumanoidRootPart`, con `transparency = 1` y
  `canCollide = false`, a 10,3 studs del origen.
- `4:14` disparó a un objetivo con `targetJumped = true`,
  `rootAtConfirmation.state = Freefall` y `hitPart = CoinVisual`.

Por eso v161 **no** sube el plomo global: +12 ms fijos mejoraban esos dos y
empeoraban `4:1`. Lo que hace es corregir el sesgo medido, por vía, y tratar la
geometría.

## 2. Geometría: dos correcciones concretas

### 2.1 El suelo no puede levantar la puntería 20 studs

`predictedRoot` aplicaba un clamp de suelo sin límite: si la predicción caía por
debajo de la última muestra en el suelo, la subía a esa altura. En una de las
sesiones archivadas eso levantó la puntería **20,9 studs** (el objetivo se
estaba cayendo, no aterrizando).

v161 limita la subida a **6 studs** (`MAX_FLOOR_LIFT_STUDS`, más o menos la
altura de un salto): dentro de ese margen el clamp sigue haciendo su trabajo
(aterrizajes), más abajo es una caída y se acompaña, no se cancela.

Replay sobre **411 muestras aéreas de las 13 sesiones guardadas**
(`targetTrajectory`, horizonte = latencia grabada, gravedad 196,2):

| Regla | error vertical medio | peor sesión |
|---|---|---|
| clamp sin límite (v160) | 3,07 studs | 17,62 |
| sin clamp | 2,95 studs | 5,58 |
| clamp limitado a 6 studs (v161) | **2,55 studs** | **4,62** |

El clamp limitado gana a las dos alternativas: mantiene lo que ya estaba bien y
quita el desastre. No se reajustó ningún otro parámetro vertical (la parte
balística con gravedad viene de v91 y sigue igual).

### 2.2 Puntería que atraviesa un cuerpo fantasma

Un objetivo perfecto puede quedar tapado por una parte **invisible y sin
colisión** (ragdoll, accesorio, `CoinVisual`): todos los chequeos de pared del
cliente la saltan por diseño. No se sabe qué hace el rayo del servidor con ella,
así que v161 **no rechaza** el disparo: intenta primero otro punto del **mismo**
cuerpo cuya línea no la cruce (`Shoot.avoidGhostAim`, usando el nuevo export
`core.describeRayHit`). Si ningún candidato la evita, se dispara al punto
original exactamente como antes. El punto elegido se graba en
`settings.ghostAvoided` para que la próxima captura pueda decir si sirvió.

## 3. Telemetría nueva en la confirmación

Cada evento `confirmation` de la calibración graba ahora también:

- `leadCorrectionTargetSeconds`: lo que pide la mediana, antes del paso máximo;
- `leadFeedbackSamples`: cuántas confirmaciones de **esa** vía sostienen la
  corrección;
- `aimMode`: `Bullet` / `CFrame` / `default`;
- `settings.ghostAvoided`: parte a la que se movió la puntería, si la hubo.

Con eso una sola sesión futura demuestra si el lazo converge y a qué velocidad,
sin tener que adivinarlo.

## 4. Módulo nuevo: `Shaders` (Render, universal)

`src/games/universal/Render/Shaders.lua`, categoría **Render**, orden
alfabético en el catálogo (`tools/card.py add`). Solo usa post-proceso del
motor: `ColorCorrectionEffect`, `BloomEffect` y `SunRaysEffect`.

- **Sin executor**: nada de `hookfunction`, ni `Drawing`, ni assets externos.
  No escribe en remotes: no cambia lo que ve el servidor ni los demás.
- **Sin bucle**: no hay `while true` ni tarea por frame. Un cambio en una opción
  escribe los efectos una vez y termina (la auditoría de rendimiento lo confirma
  contando los callbacks).
- **Se limpia al apagar**: todo vive en una carpeta `ARandomMenuShaders` dentro
  de `Lighting`; desactivar el módulo deshabilita los tres efectos y destruye la
  carpeta. Si el executor no deja crear los efectos, la tarjeta lo dice
  (`Post-processing unavailable`) en vez de fallar en silencio.
- **Presets que no pelean con la UI**: `Look` (None, Cinematic, Vivid, Neon,
  Noir, Warm, Frost, Dream) se **suma** a los sliders; no los sobrescribe, así
  que nadie tiene que escribir el valor de un widget desde el código.
- Opciones: Saturation, Contrast, Brightness, Tint, Bloom, Bloom threshold,
  Bloom size, Sun rays, Ray spread. Los valores se recortan a los rangos que
  acepta el efecto, para que un slider al máximo no congele la actualización.

## 5. Verificación

- `tools/test_prediction_lead_feedback.py` reescrito: 13 comprobaciones sobre el
  lazo (3 muestras mínimas, tope ±60 ms, paso de 20 ms, cubetas por vía, cuchillo
  aislado, rechazo de valores absurdos, incertidumbre) y que el blend 60/40 del
  eco no cambió.
- `tools/test_prediction_floor_lift.py` (nuevo): el clamp se aplica a un
  aterrizaje, no a una caída, y no toca una predicción que ya está por encima.
- `tools/replay_lead_loop.py` (nuevo): el replay de la tabla de arriba.
- `bash tools/validate.sh`: VERDE (91 fuentes, 78 suites, auditoría de
  rendimiento, boot `failures=0`, menú **50/49**).

## Lo que esto no afirma

- No hay evidencia de que el servidor rebobine igual Bullet y CFrame: por eso
  hay dos cubetas y no una.
- `4:12` (`Raggy.HumanoidRootPart`) y `4:14` (`CoinVisual`) siguen sin
  explicación cerrada: cliente y servidor pueden usar filtros distintos y solo
  una captura nueva, con `ghostAvoided` y `leadFeedbackSamples`, puede decidirlo.
- Shaders es cosmético del cliente. No mejora puntería, no oculta nada al
  servidor y no cambia el anticheat.
