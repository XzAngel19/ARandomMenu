# v163 — Postefectos de Shaders y medición honesta de picos

Fecha: 2026-10-29 · Stamp: `v163-20261029-shaders-parent-perf`

## Lo reportado

El usuario indica que Shaders sigue sin cambiar la imagen y aporta una captura
con `FPS 16`, `menu 0.36+0.01 ms`, `spikes 42`, `worst 988 ms` y
`MM2 Knife Throw`. La captura no muestra qué tarea causó el peor pico.

## Shaders: error de jerarquía, no un fallo demostrado del interruptor

En v161/v162 el módulo creaba `ColorCorrectionEffect`, `BloomEffect` y
`SunRaysEffect` dentro de un `Folder` que era hijo de `Lighting`. Roblox
requiere que un `PostEffect` sea hijo directo de `Lighting` o de
`Workspace.CurrentCamera` para funcionar. Véase la documentación oficial:
<https://create.roblox.com/docs/reference/engine/classes/PostEffect> y
<https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/ColorCorrectionEffect.yaml>.

La explicación dada en v162 sobre `card.Enabled` fue incorrecta: el
`onToggle` de `src/libraries/Framework.lua` pone `created.Enabled` antes de
llamar al callback. Cambiar la bandera y los valores iniciales no arregló la
jerarquía. El test anterior confirmó propiedades del mock, pero no modeló que
un PostEffect anidado en una carpeta es inerte.

Ahora los tres efectos son **hijos directos de Lighting**. Se guardan sus
referencias y se destruyen individualmente al apagar, sin alterar propiedades
ni efectos ajenos del juego. Las creaciones parciales y los fallos se muestran
como `Unavailable` y también se limpian. Cambiar una opción repara una instancia
propia eliminada/reparentada. No hay un bucle de reescritura que luche con el
juego u otros módulos. `Saturation` tiene paso de 0.01 en el slider real.

`Diagnose` imprime el padre, el estado `Enabled`, los valores de color y la
calidad que se pueda leer. Esta información no demuestra qué imagen renderizó
la GPU. Una calidad baja puede reducir o impedir postefectos, y `Improve FPS →
Disable post effects` puede deshabilitarlos; no se deben modificar estos
controles automáticamente. Para una prueba evidente, seleccionar `Noir` y
`Saturation = 0`. Las configuraciones guardadas del usuario no se borran.

## Picos: separar observaciones, no atribuir una causa

En v162 el resumen combinaba el máximo `deltaTime` de toda la ventana con el
nombre de la tarea más lenta del **último** evento de spike, y los milisegundos
`menu` eran una muestra posterior. El `deltaTime` de Heartbeat describe el
intervalo transcurrido desde el frame anterior, mientras las tareas medidas se
llaman después; no es una atribución de causa. Por tanto, ni `Knife Throw` ni
`juego/executor` quedan identificados como culpables por la captura.

El informe muestra por separado:

- Intervalos de Heartbeat de al menos 45 ms, contador y peor intervalo.
- Mayor tiempo transcurrido de un callback del scheduler durante la ventana,
  nombre y fase (`heartbeat` o `render`). No está vinculado al peor intervalo.
- Costes muestreados recientes y puntuaciones de tareas (pico con decaimiento).

`Perf report` imprime y después reinicia tanto los picos como el máximo de
callback. Esta medición no cubre necesariamente tareas desacopladas, el
renderizado/GPU u otro código; un callback que cede también puede acumular
espera. Para investigar, comparar periodos similares con Knife Throw encendido
y apagado; no afirmar que el módulo, el juego o el executor causaron el pico sin
más evidencia.

## Knife Throw: trabajo innecesario eliminado

En el bucle real se recalculaba un objetivo hasta 15 veces por segundo incluso
cuando Auto Knife Throw y Knife Tracer estaban apagados. En ese modo los hooks
de entrada manual resuelven objetivo y WallCheck en el momento del input y no
usan esa preselección. Ahora el bucle no selecciona objetivos en modo manual sin
tracer, ni durante el cooldown de un lanzamiento automático exitoso cuando el
tracer está apagado. El tracer sigue actualizándose con el límite anterior; el
siguiente lanzamiento automático se evalúa al terminar el cooldown. El
comportamiento de WallCheck, selección por tiempo de vuelo y los hooks manuales
se mantiene. Es una reducción comprobable de trabajo, **no** prueba de que los
988 ms de la captura se debieran a Knife Throw ni una garantía de FPS.

## Verificación y límites

- `tools/test_shaders.py`: ejecuta el módulo y `Framework.lua` reales contra un
  modelo que descarta efectos en carpetas; verifica jerarquía directa, presets,
  pasos, diagnóstico, fallos parciales, reactivación y limpieza de objetos
  propios sin tocar efectos ajenos. No reproduce el motor gráfico real.
- `tools/gen_full_boot_harness.py`: al arrancar el bundle verifica con el
  Framework y widgets reales el padre directo, `Noir`, paso 0.01 y apagado.
- `tools/test_spike_attribution.py`: ejecuta scheduler y botón reales con reloj
  simulado; confirma que pico de frame y callback son independientes, que se
  mide también RenderStepped y que el botón reinicia ambos.
- `tools/test_mm2_knife_equip.py` / `test_mm2_knife_targeting.py`: cero
  selecciones en reposo manual; tracer limitado, cooldown sin recálculos,
  lanzamiento puntual, redirect manual, WallCheck y selección preservados.
- `bash tools/validate.sh`: verde, 91 fuentes, 81 suites, auditoría de
  rendimiento, boot con `failures=0`, 93 call sites y menú 50/49.

No se ha ejecutado Roblox/MM2 ni se ha visto la pantalla del usuario; la
comprobación final de imagen y de rendimiento sigue requiriendo su prueba real.
