# v138.8 — Auto Farm instantáneo de verdad, Stay Under de vuelta, Anti Fling sin opciones

**Stamp:** `v138.8-20261027-autofarm-instant-stayunder-antifling-clean`
**Base:** v138.7 (`b393907`)
**Alcance:** `src/games/MM2/Other/AutoFarm.lua`,
`src/games/universal/Movement/AntiFling.lua`, bundle/stamp y pruebas.

## 1. Se revierte el "fly-through" y se arregla lo que molestaba de verdad

El fly-through de v138.7 añadió cosas que se notaron en juego: velocidad
proporcional (`math.min(speed, distancia * 6)`, de ahí el "se mueve muy flojo"), un
punto 26 studs *pasado* la moneda ("se mueve de frente hacia ninguna trayectoria") y
un compromiso de rumbo que hacía que pasara de largo sin cobrar.

Vuelve el comportamiento de antes —ir a la moneda más cercana, llegar y cobrar— con
tres cambios quirúrgicos que eliminan la espera:

1. **Velocidad plena.** `applyBelowControl` ya no atenúa al acercarse: vuela a Farm
   Speed hasta estar encima.
2. **Primer toque inmediato.** Al llegar a una moneda nueva se pulsa el touch **en
   ese mismo frame**; antes esperaba a que venciera el throttle de 0.25 s. Eso era
   el "se mueve un poco después".
3. **Sin parada de ~1 s.** El `STUCK_SECONDS = 1.4` que retenía el farm sobre una
   moneda que no pagaba se sustituye por `DWELL_SECONDS = 0.3`: se pulsa, si no paga
   en 0.3 s se deja para más tarde (`RETRY_SECONDS = 1.5`) y se sigue con la
   siguiente. A los 3 intentos fallidos (`RETRY_LIMIT`) esa moneda va a lista negra.
4. **Cambio de objetivo instantáneo.** El bucle de selección comprueba
   `stillCollectable` por candidato, así que en el mismo frame en que la moneda
   desaparece se apunta a la siguiente (probado: ≥4 de los 6 frames posteriores ya
   van a velocidad > 10 u/s hacia la otra moneda).

Se eliminan del módulo: `passThrough`, `passCount`, `PASS_SKIP_SECONDS`,
`PASS_LIMIT`, `BEHIND_PENALTY`, `COURSE_COMMIT_SECONDS`, `courseClearUntil` y el
punto `direction * 26`.

## 2. "Stay Under When Round starts" vuelve, y sirve para los dos modos

- Nueva opción (ON por defecto) que solo actúa **mientras la ronda arranca y no hay
  monedas**: el cuerpo espera bajo el mapa. En cuanto aparece la primera moneda,
  `restoreCharacter` lo devuelve **a la superficie en el punto de inicio de la
  ronda** y el farm continúa con normalidad en el modo elegido (Walk o Below).
- El fallo antiguo (cuerpo enterrado en Walk) era que al salir del escondite se
  lanzaba un raycast **desde debajo del suelo**, que no encontraba suelo. Ahora, si
  el cuerpo está bajo el mapa y hay `homeCFrame`, se usa directamente ese punto
  (está registrado en superficie). `holdUnderMap` es la única función que esconde.
- Probado en el banco de física: Walk espera debajo (Y ≈ 6), vuelve a Y > 10.5 con
  el cuerpo caminable y camina hasta la moneda; Below también espera y luego vuela.

## 3. Anti Fling: sin opciones

`Sensitivity` eliminada y la tarjeta declara `noOptions = true`, así que sale como
ON/OFF igual que Walk Fling. Los umbrales siguen escalando con el personaje (2.5×
WalkSpeed en plano, tres saltos hacia arriba, 500 studs/s de caída, 20 rad/s de
giro). Suite actualizada: `next(options) == nil`, `hasOptions() == false`, y el
límite se comprueba escalando con `WalkSpeed` en vez de con un slider.

## 4. Pruebas

- `tools/test_autofarm_motion.py` → **7 suites** (eran 4): velocidad plena, sin
  parada > 0.33 s mientras hay monedas, cambio inmediato de objetivo, moneda que
  nunca paga (se retira tras 0.3 s y sigue), Stay Under en Walk y en Below.
- `tools/test_mm2_auto_farm.py`: contratos de `DWELL_SECONDS`/`RETRY_*`,
  `lastTouchPulse = 0`, ausencia de taper y de fly-through, y la vuelta de
  `holdUnderMap` + salida a superficie.
- `tools/test_antivoid50.py`: Anti Fling sin opciones.
- `tools/gen_full_boot_harness.py`: exige `Option_StayUnderWhenRoundstarts` y que
  Anti Fling no exponga ninguna fila.
- `validate.sh`: **93 fuentes**, **66 suites**, boot `failures=0`, menú 52 tarjetas /
  release 51, Auto Farm con 11 opciones (Stay Under incluido) y Anti Fling con 0.

## 5. Nota de arquitectura (respuesta a la pregunta)

Lo que hoy está duplicado o es frágil, con nombres y sitios concretos:

| Punto | Dónde | Problema | Propuesta |
| --- | --- | --- | --- |
| Dos listas de módulos | `src/libraries/Manifest.lua` y `fallbackManifest` en `src/Wurst.lua` | añadir/quitar un módulo obliga a editar las dos y a mantenerlas en sync | una sola `Registry.lua`; el fallback se **genera** desde ella en el build |
| Categorías/ventanas duplicadas | `OFFICIAL_CATEGORIES`/`CATEGORY_ALIASES` en `Wurst.lua` y `CATEGORY_ORDER`/`CATEGORY_ALIASES` en `ClickGui.lua` | dos listas que pueden divergir (orden y alias distintos) | una `Categories.lua` que exporten ambas |
| Mapa `ordered` en `Cards.lua` | `Cards.lua:64` | ya no ordena nada (el orden es aleatorio), solo escribe el atributo | borrarlo cuando el harness deje de usarlo como "slot curado" |
| Alta/baja de tarjetas | 4–5 sitios a mano | fácil olvidarse de uno | `tools/card.py add|remove "<Nombre>" <Categoría>` que toque registro, manifest, harness y reconstruya el bundle |

Lo que le falta al menú (mi opinión, sin humo): **perfiles por juego**
(MM2 / universales con configuración independiente), **exportar/importar config** en
texto y un **panel "Modules"** con buscador y ON/OFF de todo en una lista. El PANIC
ya existe en Settings, así que esa parte está cubierta.
