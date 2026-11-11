# v199 (suffix `aim-camera-fire`) — Aimbot en FPS: cámara clavada al disparar y arma disparando a la esquina

Build: `SOURCE_STAMP = "v199-20261108-aim-camera-fire"` (el número de build
sigue siendo **v199 / 0.199**; solo cambia el sufijo del stamp).

Reporte del jugador: *«en ciertos juegos la cámara no funciona bien con el
aimbot, la pistola se bugea y mi cámara se queda en el lugar donde presiono
click con la pistola»*. Todo venía del módulo universal **Aimbot**
(`src/games/universal/Combat/AimAssist.lua`); abajo los dos mecanismos
concretos y su arreglo. Suite nueva: `tools/test_aim_fps_camera.py` (falla con
el código viejo, pasa con el nuevo).

## 1. Cámara congelada en el último punto de puntería

`tryCamera()` hacía dos cosas: escribía `camera.CFrame` de inmediato **y**
enganchaba un `BindToRenderStep("WurstAimAssistCam")` "de un solo uso" que
capturaba ese `newCFrame` y trataba de desengancharse **desde dentro del
propio render step** (con un `pcall` que se tragaba el error). Si ese unbind
fallaba, el binding seguía vivo y reescribía el mismo CFrame obsoleto **cada
frame para siempre**: la cámara quedaba clavada exactamente donde apuntaba al
click (matar al objetivo o perderlo no liberaba nada).

Arreglo: **ya no hay ningún `BindToRenderStep`**. La cámara se escribe solo
desde el callback por frame de la tarjeta, que corre en `RenderStepped`, es
decir **después** del update propio de la cámara del juego
(`RenderPriority.Camera`): la escritura gana el frame sin ningún binding que
pueda filtrarse. En cuanto no hay target (o el módulo pausa por menú, foco de
texto u otro adaptador de aim), no se escribe nada y el juego vuelve a ser el
dueño de la cámara. Los `UnbindFromRenderStep` de apagado se conservan por
higiene.

## 2. El arma "se bugea": click virtual en (0,0) y disparo doble

Tres problemas en la ruta de disparo (`tryFireOnce`):

- `VirtualInputManager:SendMouseButtonEvent(0, 0, …)` enviaba el click en la
  **esquina (0,0) de la pantalla**. En juegos que lanzan el rayo desde la
  posición del cursor al disparar, el tiro se iba a la esquina superior
  izquierda; con cursor libre, además, el movimiento del click podía arrastrar
  el ratón (y una cámara guiada por posición absoluta del ratón) a esa esquina.
  Ahora el evento se envía en la **posición real del cursor**
  (`GetMouseLocation()`, con fallback a centro de viewport + inset de la GUI),
  compartida con la ruta de apuntado (`getMouseScreenPosition`).
- En modo **Hold** el click real del jugador ya activa la herramienta
  (`Tool.Activated` se dispara con el click), así que llamar `Activate()` otra
  vez **doble-disparaba** las armas semi-auto. Ahora en Hold con el botón
  realmente pulsado el módulo no hace nada extra.
- Si la herramienta sólo estaba en la mochila se llamaba `hum:EquipTool(...)`:
  equipar en mitad de la pelea puede disparar la lógica de equipar/ADS del
  juego, que **cambia o bloquea la cámara** (cámara en primera persona) justo
  donde quedó el click. Se eliminó por completo: solo se activa una herramienta
  que ya se sostiene; si no hay, va el click virtual.

## Qué NO cambió

- El modo híbrido FPS (shift-lock / primera persona) sigue haciendo
  `mousemoverel` + CFrame en el mismo frame para que el `Mouse Hit` del arma y
  la cámara queden sincronizados; en tercera persona Auto sigue siendo solo
  ratón (CFrame solo como fallback si no hay `mousemoverel`).
- Sin target no se toca la cámara; al apagar la tarjeta se liberan callback y
  bindings.

## Verificación

`bash tools/validate.sh` en verde: 84 fuentes compilan, analyze con baseline
sin errores nuevos, `test_aim_fps_camera.py` (6 aserciones: no se filtra ningún
binding de render step, sin target la cámara no se reescribe, Activate con
throttle de CPS, Hold sin doble disparo, click virtual en la posición real del
ratón y sin `EquipTool`, limpieza al apagar), `test_aimassist49.py` sin
regresiones, bundle regenerado (82 archivos) con el stamp nuevo.
