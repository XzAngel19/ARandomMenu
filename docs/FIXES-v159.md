# v159 — Knife: sin especulación, WallCheck estricto y predicción consistente

Fecha: 2026-10-29 · Stamp: `v159-20261029-mm2-knife-wallcheck`

## Lo que pidió el usuario

> «No mejora nada. Quita eso. De todo eso deja solo el WallCheck y trata de
> mejorar esta predicción del cuchillo.»

Se elimina **todo** lo especulativo (v157: radios alrededor del rival oculto;
v158: carriles de apertura). El cuchillo solo se lanza a un objetivo visible, y
la predicción sí cambia.

## 1. Fuera la especulación

- `resolveSpeculativeAim` y sus cuatro usos borrados: `throwKnife`, los dos
  redirects de `WeaponService` y `solveAim`.
- Sin objetivo visible no hay paquete. `Auto Knife Throw` gasta cuchillo solo
  con objetivo válido y visible; el redirect nativo devuelve el aim original
  del juego (`GetMouseTargetCFrame`/`GetTargetPosition` sin tocar).
- Estado del módulo: `No visible target` / `Target blocked · WallCheck` /
  `Predicted target` / `Throw sent · hit unconfirmed`.
- Se conserva el rechazo de cadáveres de v158 (`Health 0`, `Dead`, `Physics`,
  atributo `Dead`), que era la otra mitad del reporte y no tiene que ver con
  los carriles.

## 2. WallCheck ahora sí es la garantía

Tres cambios, todos dentro de `KnifeThrow.lua`:

1. **Pase estricto del helper compartido.** Antes se llamaba a
   `isWeaponPathClear(..., strict = nil)`, que es la regla del primer pase del
   gun: *toda* parte con `Transparency == 1` se salta. Con eso una barrera
   invisible pero sólida (`CanCollide = true`) no frenaba el cuchillo. Ahora se
   pasa `strict = true`: solo se saltan las transparentes que además no
   colisionan.
2. **Corredor de cinco rayos** (±0,45 studs lateral y vertical) en vez de una
   línea matemática: una baranda o un poste fino no se cuela entre muestras.
   Los cinco rayos usan la misma regla estricta; un raycast crudo en los
   offsets haría que una decoración no-colisionable bloqueara el tiro.
3. **El cuerpo tiene que verse AHORA**, no solo el punto predicho. El punto
   predicho asoma por la esquina cuando el rival frena o gira, y ahí el
   cuchillo recto no llega: se rechaza el lanzamiento.

`findTarget` usa el modo barato (solo visibilidad del cuerpo) para elegir; el
corredor se comprueba con el origen vivo justo antes de `FireServer`.

## 3. Predicción del cuchillo

- **Intercepto a punto fijo.** `knifeAim` hacía una sola re-solución: usaba el
  tiempo de vuelo para calcular la cuerda y luego recalculaba el tiempo con la
  cuerda nueva, dejando el punto y el `flightSeconds` devuelto en desacuerdo
  cuando el objetivo gira o frena. Ahora itera (máx. 4 pasadas, corta a
  `1e-4 s`) hasta que el tiempo de vuelo deja de moverse, y mantiene la
  velocidad con la que se resolvió ese último tiempo. Propiedad verificable:
  `|punto − mano| == velocidad × flightSeconds`.
- **Camino aéreo**: el punto se sustituye por la proyección balística del
  cuerpo, así que el `flightSeconds` de la cuerda ya no correspondía a la
  distancia real. Se recalcula como distancia / velocidad. Ese número lo usan
  la selección de objetivo y la telemetría.
- **Selección por tiempo de vuelo**, no por distancia: `score = flightSeconds`,
  con −0,08 s para Sheriff/Hero. Un cuerpo más lejos que corre hacia el
  cuchillo recibe el impacto antes que uno más cercano parado, y antes
  significa menos extrapolación y menos error.

## 4. Pruebas

- `tools/test_mm2_knife_targeting.py` (nueva) — mapa analítico de cajas con el
  `isWeaponPathClear` **real** de `base.lua`:
  - objetivo visible: un paquete, aim sobre el cuerpo;
  - pared opaca: sin lanzamiento, aim nativo intacto en ambos métodos;
  - barrera invisible sólida: rechazada por el pase estricto;
  - decoración invisible no-colisionable: pasa;
  - poste a 0,28–0,62 studs del rayo central: el corredor lo rechaza;
  - esquina: el punto predicho no vale si el cuerpo está tapado;
  - cadáveres (salud 0, `Dead`, `Physics`, atributo): nunca objetivo;
  - dos objetivos: gana el de menor tiempo de vuelo aunque esté más lejos;
  - `WallCheck` OFF permite, ON rechaza.
- `tools/test_mm2_knife_equip.py` — reescrita al contrato nuevo: lobby vacío y
  objetivo tapado no gastan cuchillo; los redirects caen al original.
- `tools/test_mm2_precision.py` — exige la identidad `velocidad × vuelo` en
  suelo y en aire, y mantiene el rechazo de cadáveres del predictor.
- `tools/test_mm2_knife_openings.py` — **borrada** con la función que probaba.
- `tools/test_mm2_trajectory_simulation.py` — mismos 486 escenarios y mismos
  números que v157 (los casos sintéticos tienen velocidad constante en la
  ventana, el punto fijo converge al mismo sitio).

## Límites

- Geometría y contrato de cliente con mocks. No prueba Volt, el servidor,
  daño, hit-rate ni anticheat.
- El corredor de 0,45 studs es una elección, no una medida del grosor del
  proyectil de MM2: si el cuchillo real es más ancho, el corredor se queda
  corto; si es un punto, puede rechazar pasillos válidos.
- La identidad de vuelo asume velocidad constante y trayectoria recta. El
  servidor no está comprobado: los dos proyectiles observados en la sesión
  `221E2F3D` desaparecieron (`destroyed`) tras 0,21–0,22 s sin pasar por el
  cuerpo, con objetivos quietos. Eso apunta a que el cuchillo muere contra
  geometría o se empareja mal, no a que el adelanto esté mal calculado; sigue
  sin datos que lo demuestren.
- `WallCheck` ON solo comprueba el instante del envío: el rival puede meterse
  detrás de una pared durante el vuelo, y el cuchillo no corrige.
