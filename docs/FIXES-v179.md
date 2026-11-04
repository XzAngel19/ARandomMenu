# v179 — Shaders fuera, nombres con espacio y precisión de Shoot/Knife

Build: `v179-20261103-names-and-precision`

## 1. Shaders eliminado

No queda nada de la tarjeta: ni módulo (`src/games/universal/Render/Shaders.lua`),
ni entrada en `src/libraries/Manifest.lua`, ni descarga de assets en
`src/Wurst.lua`, ni los `Assets/Shaders/*.png|jpg`, ni su suite de pruebas.

El arranque ahora **comprueba la ausencia**: si `GetModule("Shaders")` devolviera
algo, si apareciera un `ARMShader*` en `Lighting` o si el módulo tocara las
propiedades de iluminación del juego, la validación falla. El menú pasa de **50 a
49** tarjetas en audit y de **49 a 48** en release.

## 2. Nombres nuevos

| Antes | Ahora | ConfigKey |
| --- | --- | --- |
| `Jesus` | **`Swim Walk`** | `Universal.Jesus` (sin cambios) |
| `Jump` | **`Jump Hack`** | `Universal.Jump` (sin cambios) |
| `Speed` | **`Speed Hack`** | `Universal.Speed` (sin cambios) |

Los `ConfigKey` se conservan a propósito: cambiar el nombre visible no debe
borrarte perfiles, opciones ni teclas ya guardadas. Lo que sí cambió es el
nombre de módulo que usan otros módulos (`AntiFling` y `Sprint` ahora piden
`GetModule("Speed Hack")`), el archivo `Jesus.lua` → `SwimWalk.lua`, y los tiles
del navegador (`Nav_SpeedHack`, etc.).

## 3. Precisión de Shoot y Knife

Trabajado a partir de tus 11 exportaciones `MM2_Trajectory_Calibration*.json`.
Lo que dicen los datos:

- `gunAcceptanceMs` (tiempo real entre tu `FireServer` y la confirmación del
  servidor) ronda **196-204 ms** de media desde v157, mientras que tu `Data
  Ping` marca 150-165 ms. La diferencia es el procesado del servidor. Cuando no
  hay ecos medidos, la mira usaba el ping → **se quedaba 40-50 ms corta**.
- `knifeSpeed` está clavado en **96** en 48 muestras: la velocidad por defecto
  es correcta, leer el atributo del tool apenas aportaba.
- El cuchillo **no tenía realimentación ninguna**: los `leadCorrection` solo se
  alimentaban de confirmaciones de cañón, así que su corrección estaba
  permanentemente vacía.

### Cambios

**a) Prior de aceptación medido.** `base.lua` publica la media de aceptación de
sus propias confirmaciones (más la del historial importado) al predictor. Ese
valor se usa **solo cuando todavía no hay ecos** y solo si encaja con la conexión
en uso (0,75×–2,5× el RTT y ≥8 muestras). Un fichero viejo de otra red no puede
envenenar la mira; si no encaja, manda el ping como siempre.

**b) El cuchillo aprende de sus propios lanzamientos.** Ahora:

1. `KnifeThrow` reporta el punto real que apuntó (root predicho + velocidad +
   tiempo de vuelo). Antes ese dato no llegaba a la telemetría.
2. `base.lua` guarda en cada `KnifeTrack` la posición y la velocidad del cuerpo
   en el **paso más cercano** de la hoja.
3. Ese desvío se proyecta sobre la velocidad del objetivo y se convierte en
   **segundos**, con el mismo signo que el cañón (positivo = el cuerpo iba por
   delante, nos quedamos cortos) y sus mismos límites: ±0,15 s, velocidad mínima
   2 studs/s, desvío máximo 6 studs.
4. Los cuchillos escriben en su propio bucket (`Knife`) y mueven el horizonte con
   *slew* limitado (máx. 20 ms por confirmación), igual que los cañones.

No se reescribió ni el modelo de movimiento ni el aim: los datos
(`constantVelocityResidual` ≈ 0 en suelo, 1 sola muestra balística) no justifican
otro modelo. La API y la telemetría existentes se conservan; los eventos de
cuchillo añaden `leadErrorSeconds`, `predictedRoot`, `approachRoot` y
`approachAtMs` para que la próxima sesión se pueda puntuar sin reconstruir nada.

### Cómo notarlo

- Tira con el cuchillo a alguien que corra en línea recta: el primer par de
  lanzamientos usa lo medido en la cuenta; a partir del tercero la corrección
  propia del cuchillo empieza a moverse (hasta 20 ms por lanzamiento, tope
  60 ms).
- En el estado del módulo MM2 verás el horizonte y, en la telemetría, el
  `leadErrorSeconds` de cada hoja.

## Protocolo

`SOURCE_STAMP = v179-20261103-names-and-precision` → bundle regenerado (82
fuentes) → `tools/validate.sh` verde: 84 fuentes compilan, 114 suites, boots
`failures=0`, arranque silencioso, menú 49/48.
