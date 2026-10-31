# v166 — Shaders oscuros y continuación de la simplificación

Fecha: 2026-10-31 · Stamp: `v166-20261031-shaders-black-module-cleanup`

## Shaders

El usuario informó que algunos modos vuelven la pantalla completamente negra.
No hay captura de los valores afectados ni prueba de que fueran causados por
el módulo, pero se reprodujo una causa posible: tanto la entrada manual como
los valores guardados pueden superar el rango visible. Con `Brightness=-20`,
v165 aplicaba `-1`; la documentación de Roblox indica que ese valor vuelve
negros los píxeles. `TintColor` multiplica canales, por lo que un tinte negro
también puede oscurecer toda la imagen:
<https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/ColorCorrectionEffect.yaml>.

- Se limitan **los valores aplicados**, después de sumar el Look: brillo a
  `[-0.05, 0.3]`, contraste a `[-0.35, 0.25]` y cada canal de tinte a
  `[0.6, 1]`. Los valores de configuración existentes no se sobrescriben.
  `Noir` sigue siendo monocromo; se conservan los ocho Looks y los controles.
- Si falla la creación o aplicación al activar, el módulo apaga y limpia lo
  creado inmediatamente, incluso si la restauración de configuración captura
  el error sin enviar OFF. El error sigue llegando al llamador.
- `Diagnose` imprime Look, propiedades reales, intensidades, padres y estados;
  también enumera efectos `ColorCorrectionEffect` habilitados directamente bajo
  Lighting o CurrentCamera, sin modificarlos. Otros efectos pueden combinarse
  con los propios; el diagnóstico no verifica píxeles ni GPU.
- Los límites evitan esos valores extremos en el efecto propio, **no
  garantizan** que no pueda haber pantalla negra por el mapa, otros efectos,
  ajustes gráficos, el cliente o la GPU. No se deshabilitan efectos ajenos.

## Módulos revisados

Se trabajó en 13 archivos de `src/games`, incluido Shaders; no se revisaron
ni convirtieron en originales todos los demás. Se conservaron restricciones,
fallbacks funcionales, opciones y limpieza, retirando envoltorios innecesarios
sobre APIs nativas donde se conocen sus contratos.

- **Noclip:** señales y limpieza simplificadas. Sigue inactivo al inyectar,
  atiende nuevas partes y respawn y restaura las colisiones originales en OFF.
- **Anti Void / AirWalk:** acceso directo a APIs nativas y plataformas más
  simples; se conservan entrada de teclado/touch, altura, muerte y limpieza.
  Se corrige la afirmación anterior sobre Anti Void: `CanQuery=false` no excluye
  una pieza colidable de raycasts, según
  <https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/BasePart.yaml>.
- **Swim:** se recupera el `Region3:ExpandToGrid(4)` del algoritmo Vape antes
  de `Terrain:ReplaceMaterial`; la región de resolución 4 debe estar alineada:
  <https://robloxapi.github.io/ref/class/Terrain.html#member-ReplaceMaterial>.
  Si la región no cambió, no se reescriben los mismos voxels cada frame.
  **Advertencia:** como en el algoritmo original, al moverse o desactivar se
  reemplaza Water por Air en la región anterior, lo que también puede borrar
  agua natural *local* allí. Se advierte en el tooltip. No se probó replicación
  de terreno ni física de agua en Roblox; cuando se mueve puede seguir siendo
  costoso. El original es
  <https://github.com/7GrandDadPGN/VapeV4ForRoblox/blob/5d951c27f9677cc1d4a658c44a42c120356b9f58/src/games/universal%20-%20base/Blatant/Swim.lua>.
- **Jesus:** conserva los tres modos ya existentes, no el modo plataforma
  literal de Vape. Reutiliza `RaycastParams` durante cada activación y cambia
  el filtro al reaparecer; sigue ejecutando raycasts mientras está habilitado.
- **Gravity:** únicamente restaura una gravedad capturada al activar el módulo;
  descargarlo sin haberlo usado no vuelve a imponer una captura antigua. No
  reescribe la propiedad cada frame si ya tiene el valor seleccionado. Es la
  variante propia, no los tres modos de Vape; OFF restaura la captura de ON,
  no la última modificación externa ocurrida durante ON.
- **Anti AFK:** se simplifican accesos y limpieza, conservando las alternativas
  VirtualUser y VirtualInputManager. Ya no promete que un kick sea imposible:
  una llamada exitosa no prueba que el executor o servidor reinicien el timer.
- **Interact Extender:** se comparten las rutas de actualización de prompts y
  detectores. Un escaneo asíncrono anterior termina al apagar/encender, en lugar
  de seguir modificando objetos en la siguiente sesión.
- **MM2:** Round ESP simplifica la lectura/restauración de trampas; Auto Unbox
  lee atributos nativos de evento directamente. Coin ESP conserva detección,
  filtros y familias y destruye adornos cuando la moneda queda sin padre.
  Teleport usa métodos nativos de Instance sin guardas redundantes; Get Gun y
  Auto Get Gun siguen usando touch inmediato **sin mover al personaje**, y el
  modo automático conserva los requisitos de rol, ronda y mapa.

Estas implementaciones son adaptaciones con contratos propios. Swim conserva el
mecanismo Vape con el ajuste de no reescribir una región sin cambios, pero no
es una copia literal. Anti AFK, Gravity, Jesus, Noclip y el resto tampoco deben
presentarse como copias 100 % de Vape o YARHM.

## Validación y límites

- `tools/test_shaders.py`: los ocho Looks con ajustes normales y extremos,
  más valores extremos restaurados; límites aplicados sin sobrescribir configuración; diagnóstico
  de efectos ajenos y cleanup. Las pruebas simulan propiedades, no render.
- Nuevos `tools/test_noclip.py`, `test_airwalk.py`, `test_anti_afk_runtime.py`,
  `test_swim.py`, `test_jesus.py`, `test_gravity.py` y
  `test_interact_extender.py`; este último reproduce la carrera OFF/ON antes de
  la corrección. Se ampliaron tests de Anti Void, MM2 Teleport, Coin ESP, Round
  ESP y Auto Unbox.
- `bash tools/validate.sh`: bundle de 89 archivos, 91 fuentes compiladas,
  catálogo de 39 universales y 75 ventanas, auditoría de rendimiento, 91 suites
  Python/Luau, boot `failures=0`, 93 llamadas API y menú 50/49: PASS.
- No se ejecutó en Roblox/Delta ni se midieron FPS, imagen real, cambios de
  terreno replicados, eficacia del Anti AFK o comportamiento del servidor. Si
  persiste el negro, pedir el Look, ajustes, captura y salida de `Diagnose`.
