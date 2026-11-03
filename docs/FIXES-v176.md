# v176 — Densidad de clima real y keybinds en juego

## Contexto y qué se reportó

El usuario reportó que `Rain` y `Snow` seguían viéndose «muy pocos» y que `Fog`
era «muy suave o débil», además de que Shaders no respondía bien a los
**keybinds** en juego, sobre todo en **MM2**. Se pidió revisar el plugin
[Rain Plugin (asset 2166774609)](https://create.roblox.com/store/asset/2166774609/Rain-Plugin)
y arreglar «todas esas cosas», no una sola.

No hay captura de esta sesión: las causas de abajo son las que el código y la
documentación del motor permiten demostrar, y cada una tiene una prueba. Cómo se
ve en Roblox/Delta **sigue sin verificarse aquí**.

## Causas encontradas en el código (no hipótesis de sensación)

1. **Lluvia con presupuesto de juguete.** `rate = 18` por celda × 9 celdas =
   162 partículas/s en todo el mapa, con `Lifetime 0,85` ⇒ ~15 gotas vivas por
   celda y una textura `SquareParticle.png` de respaldo (un cuadrado).
   Referencia medida: [buildthomas/Rain](https://github.com/buildthomas/Rain)
   usa `Rate 600`, `Lifetime 0,8`, `Speed 60` y una textura de trazo.
2. **La lluvia se apagaba al caminar.** En cada movimiento de cámara > 30 studs
   se ponían **todos** los emisores en `Enabled = false` y el sondeo de techo
   reactivaba **una celda cada 0,15 s** (9 celdas ⇒ 1,35 s). Al moverse, el
   clima aparecía a ráfagas o no aparecía.
3. **Reescritura inútil de `Enabled`.** El sondeo escribía `Enabled` en todos
   los emisores de la celda muestreada en cada pasada, cambiara o no el valor.
   En el motor, escribir `Enabled` reinicia el presupuesto interno del emisor.
4. **Techo falso.** El raycast de cielo no usaba `RespectCanCollide`, así que
   cualquier decoración no-colisionable por encima de la cámara contaba como
   techo y ocultaba la lluvia.
5. **Nieve casi invisible.** `Rate 8`, `Size 0,45`, `LightEmission 0,2`: 72
   partículas/s en todo el mapa y grises en mapas oscuros.
6. **Niebla débil.** `Atmosphere.Haze` mínimo 1,25 (rango documentado 0–10),
   `FogEnd` máximo 180 y una niebla de partículas con `Rate 4`, `Size 10`,
   `Transparency 0,86` — prácticamente invisible.
7. **Keybind muerto en juego.** `shortcutInputAllowed` exigía
   `not gameProcessed`. Ese flag solo significa «el juego o la GUI principal ya
   usó la entrada»; MM2 liga varias teclas comunes, así que el atajo del menú se
   descartaba aunque el clic en la tarjeta funcionara.

## Cambios

### Densidad y aspecto (`src/games/universal/Render/Shaders.lua`)

- Perfil por **capas** en lugar de un emisor por tipo. Lluvia: capa de trazo
  `150/s` + capa cercana `90/s`; nieve `34/s`; hojas `3/s`. Celdas de `40 × 40`
  y offsets de ±36 (cobertura ~112 studs) para que el volumen visible importe
  menos que la densidad.
- Se respetan los topes del motor documentados: **400 partículas/s por emisor en
  escritorio y 100 en móvil** (`MAX_EMITTER_RATE`, `MAX_CELL_EMITTERS`,
  `MAX_WEATHER_RATE = 3000`). En móvil se crea directamente el perfil reducido
  (una capa a 92/s), no se crea y luego se recorta.
- Lluvia: `Squash` negativo con `VelocityParallel` (documentado para estelas),
  `Acceleration` descendente y viento leve, `LightEmission`/`LightInfluence`
  ajustados para no desaparecer en mapas oscuros.
- Nieve: copos más grandes (`Size 1,25`), `Lifetime 6,2`, `SpreadAngle 28`,
  deriva horizontal y `LightEmission 0,55` para verse en rondas nocturnas.
- Salpicaduras: tamaño `2,2`, vida `0,28–0,36`, textura de trazo/impacto y
  `Emit(2)` por muestra abierta.
- Respaldos: `rbxassetid://1822883048` (trazo) y `rbxassetid://1822856633`
  (impacto) en lugar de un cuadrado. Las imágenes CC0 locales siguen siendo la
  fuente primaria si el executor las carga.

### Bucle de clima

- Al mover la cámara ya **no** se apagan los emisores; se conserva la última
  visibilidad y el sondeo escalonado (un rayo cada 0,15 s) corrige cada celda.
- `Enabled` se escribe solo cuando una celda cambia de estado (`cell.applied`).
- `RespectCanCollide = true` en los rayos de cielo y de suelo: la decoración
  no-colisionable no tapa la lluvia. Un techo sólido sigue ocultándola y una
  pieza casi transparente sigue contando como abierta.
- Presupuesto compartido: si la suma de `Rate` superara `MAX_WEATHER_RATE`, se
  escala todo proporcionalmente y se avisa una vez. No se elimina un tipo de
  clima en silencio.

### Fog

- Con `Atmosphere` del juego: `Density` mínimo **0,58** y `Haze` mínimo **4,5**
  (antes 0,45 / 1,25). Si el juego ya tiene valores mayores, no se debilitan.
- Sin `Atmosphere`: `FogStart` ≤ 8, `FogEnd` ≤ 110 (antes 20/180) y un gris-azul
  legible en `FogColor`.
- Niebla local de partículas: `Rate 14`, `Size 30`, `Transparency 0,80`, celda
  de `80 × 16 × 80` que sigue a la cámara (antes 4 / 10 / 0,86 en 60×10×60).
- Se mantiene el contrato de restauración de v175: solo se restaura el último
  valor ajeno conocido y solo si el valor actual sigue siendo el aplicado.

### Keybinds (`src/Wurst.lua`, `src/guis/Wurst/Code/Cards.lua`)

- `shortcutInputAllowed` ya no descarta la entrada por `gameProcessed`; siguen
  bloqueando el **TextBox enfocado**, la captura de tecla y la espera de tecla
  del menú.
- El binding guarda `label` y `feedback`. Cuando un atajo se dispara con el menú
  cerrado se emite un aviso (`Shaders on` / `Shaders off`), que es la prueba
  visible de que el atajo corrió. Las opciones hijas ya notificaban.

## Presupuesto y límites (de código, no mediciones)

- Emisores máximos con todo el clima activo: 9 celdas × 2 capas de lluvia = 18,
  más 9 de nieve, 9 de hojas, 1 de polvo, 1 de niebla y 1 de salpicaduras = 39.
- Partículas/s: 2160 lluvia + 306 nieve + 27 hojas + 12 polvo + 14 niebla =
  **2519** de escritorio, más hasta ~13 salpicaduras/s por `Emit(2)`.
  Móvil: 9 × 92 + 9 × 20 + 18 + 12 + 14 ≈ **1052**.
- Partículas vivas (Rate × Lifetime) ≈ 1550 de lluvia y ~1900 de nieve con todo
  activo. Es el número que llena la pantalla y el que puede costar GPU; el
  usuario puede apagar lo que no use.
- Ninguno de estos números es una medición de FPS ni de memoria, y la calidad
  gráfica puede reducir partículas automáticamente.

## Pruebas

- `tools/test_shaders.py` (ampliado): densidad mínima por capa, `Squash`
  negativo, respaldos de textura, cámara en movimiento sin apagar emisores,
  `RespectCanCollide`, sin reescrituras de `Enabled` en estado estable, techo
  sólido vs. transparente, presupuesto total ≤ 3000, perfil móvil a 92/s y sin
  segunda capa, fog `0,58` / `4,5` / `110`, niebla de partículas visible y
  restauración al apagar.
- `tools/test_shortcut_game_input.py` (nueva): ejecuta el bloque real de
  `src/Wurst.lua`; un atajo funciona con `gameProcessed = true`, el aviso sale
  una vez por activación, y siguen bloqueando el TextBox, la captura y la espera
  de tecla; las teclas hold sueltan al perder foco.
- `bash tools/validate.sh`: **117 suites**, boot `failures=0`, 90 llamadas
  `core.*`/`prediction.*` resueltas, menú **50/49**, bundle de 84 fuentes con
  stamp `v176-20261103-weather-density-keybinds`.

## Pendiente en vivo

- Confirmar con captura o vídeo si la densidad se ve bien **con el menú
  cerrado** (el menú abierto aplica desenfoque) y en qué mapa/calidad.
- Medir el coste real de 39 emisores en Delta móvil; si pesa, subir el perfil
  móvil ya está por debajo del tope, pero no se ha medido FPS.
- En MM2: probar el atajo en una ronda con el mapa cargado y confirmar el aviso
  `Shaders on`; si el juego consume la tecla para su propia acción, el menú ya
  no la descarta, pero el juego también hará lo suyo.
- La niebla de partículas es una aproximación local; no es niebla volumétrica ni
  un shader de posproceso.
