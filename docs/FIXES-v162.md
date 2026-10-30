# v162 — Shift Lock, Shaders que no hacía nada, y el coste de los rayos nuevos

Fecha: 2026-10-30 · Stamp: `v162-20261030-shiftlock-shaders-fix`

> **Corrección posterior (v163):** este informe sobrestimó el arreglo de
> Shaders y la capacidad del informe de rendimiento. El Framework sí actualiza
> `created.Enabled` antes del callback; los efectos estaban en un Folder inerte.
> La muestra de `menu` y la etiqueta del último spike no identifican la causa
> del peor intervalo. Ver `docs/FIXES-v163.md` para evidencia y corrección.

Tres cosas reportadas: **el Shift Lock dejó de funcionar y el ratón se queda
libre**, **Shaders no hace nada**, y **lag spikes**. Las dos primeras tienen
causa encontrada y corrección con test. La tercera se acota por lo que el menú
añadió y se mide a un botón de distancia.

## 1. Shift Lock: el menú se quedaba el cursor

`src/Wurst.lua`, bloque `menuCursorState`. El menú pide el cursor libre al
abrirse (si no, no se puede hacer clic) y lo devuelve al cerrarse. La devolución
tenía dos defectos:

1. **Escribía siempre un valor**, aunque el que estuviera puesto ya no fuera el
   suyo. Si abrías/cerrábamos el menú con un atajo y el juego activaba el Shift
   Lock en ese mismo instante, el cierre lo pisaba con `Default`: el ratón se
   quedaba libre y el Shift Lock no volvía hasta pulsarlo otra vez.
2. **Volvía a escribir `LockCenter` nunca**, pero sí lo *capturaba*: si entrabas
   al menú con el Shift Lock puesto, al salir se liberaba a `Default` y el juego
   no recuperaba el bloqueo por sí solo.

Y además peleaba: dos escuchas a `MouseBehavior`/`MouseIconEnabled` reafirmaban
`Default` cada vez que el juego lo cambiaba, 60 veces por segundo mientras el
menú estuviera abierto.

v162 aplica tres reglas, cada una con su comprobación en
`tools/test_menu_cursor.py` (ejecuta el bloque real de `Wurst.lua`):

| Regla | Qué evita |
|---|---|
| Solo se deshace **lo que escribió el menú**: al cerrar, si el cursor no está en `Default`, ese estado es del juego y se respeta | El cierre pisa el Shift Lock recién activado |
| Nunca se escribe `LockCenter`; un `LockCenter` capturado se libera a `Default` | Quedarse con la cámara bloqueada sin el estado de Shift Lock del juego |
| Tras **8** reafirmaciones en **1 s** el menú cede: deja de pelear por el cursor hasta la siguiente apertura | Pelea de cursor cada frame, cursor parpadeando y CPU regalada |

Extra: al reaparecer con el menú cerrado se suelta cualquier posesión vieja
(`LocalPlayer.CharacterAdded`). Un menú cerrado es **completamente inerte**: no
escribe ni un valor, lo comprueba el test con 120 cambios externos.

## 2. Shaders: corrección de la explicación original

v162 cambió el preset y agregó una bandera `active`, pero **no corrigió** el
padre de los efectos, que seguían en un Folder bajo Lighting. El Framework pone
`created.Enabled` antes de llamar al callback: el diagnóstico previo que
culpaba esa guarda era incorrecto. v163 mueve los efectos directamente a
Lighting, modela ese contrato en tests y conserva la prueba visual real como
pendiente; ver `docs/FIXES-v163.md`.

## 3. Lag spikes

No puedo reproducir tu sesión, así que separo lo que **sí** añadía coste de lo
que hay que medir.

Lo que v161 añadía y v162 acota:

- El chequeo de "cuerpo fantasma" de la puntería (`avoidGhostAim`) hacía
  **1 raycast y hasta 12 más por frame** con Auto Shoot encendido, porque se
  ejecutaba en cada intento de disparo. Ahora son como mucho **5 rayos cada
  0.15 s** y, entre medias, se reutiliza la parte elegida (un
  `FindFirstChild` + la misma aritmética de plomo). Es una preferencia de
  puntería, así que puede ser algo vieja sin ningún riesgo.
- Nada más del menú corre por frame a causa de v161/v162 (la auditoría de
  rendimiento lo comprueba en `tools/validate.sh`).

Lo que hay que medir, y ahora es un botón: **UI Settings → Perf report**.

- Imprime en consola `state.perfReport()` (FPS, ms del menú, top de módulos) y
  muestra un resumen en pantalla.
- **Reinicia el contador de spikes**. Púlsalo, juega un minuto con lo que
  suelas tener encendido, púlsalo otra vez: la segunda lectura describe ese
  minuto.
- Corrección v163: `menu 0.30+0.10 ms` es una muestra, no el coste del peor
  pico. La etiqueta de v162 era la tarea del último evento, no necesariamente
  la del peor. Ni esa muestra ni esa etiqueta identifican un culpable.

El overlay `Session Info` muestra lo mismo en vivo (`Menu`, `Spikes`).

## 4. Escala del menú

No encontré ningún cambio de tamaño entre v139 y ahora: `cardHeight`,
`optionRowHeight`, `WINDOW_WIDTH` y `ThemeEngine.shape.scale` son idénticos. Lo
que sí faltaba era una forma de ajustarlo sin tocar código, así que UI Settings
tiene ahora **Menu scale** (0.7–1.3), que se guarda en la config
(`UI.MenuScale`) y solo afecta a la escala del ClickGUI. Para dejarlo como la
v139, ponlo en el valor que te cuadre (1.0 es el actual; 0.9 se ve ~10 % más
pequeño).

## Verificación

- `tools/test_menu_cursor.py` (nuevo, 8 comprobaciones): apertura/cierre normal,
  Shift Lock que sobrevive al cierre, `LockCenter` nunca reescrito, cesión tras
  la pelea, cesión por sesión, menú cerrado inerte y respawn.
- `tools/test_shaders.py` en v162 comprobaba valores en un mock, pero no modeló
  el requisito de padre directo; se reemplazó y amplió en v163.
- `tools/validate.sh`: VERDE (91 fuentes, 80 suites, auditoría, boot
  `failures=0`, menú 50/49).
