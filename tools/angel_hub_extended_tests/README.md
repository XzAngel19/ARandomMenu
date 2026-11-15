# Extensiones de GUI: pruebas simuladas

```sh
bash tools/luau/setup.sh
node tools/angel_hub_extended_tests/run.cjs
```

Reutiliza fixtures de la integración previa y prueba FreeCam y espectador en
perfiles PC/móvil, restauración de cámara y controles, cambios de cámara y
cancelación durante operaciones que ceden; Air Walk y controles táctiles; Air Swim y restauración condicional de voxels, asiento, muerte y reintento ante errores; Zoom Through Walls y restauración de la cámara; Blurt (chat público opt-in y cancelación); Walk Fling, conflictos de movimiento,
pulsos y restauración; X-Ray, objetos nuevos y cambios externos; y las opciones
FPS, lotes de 200 objetos, limpieza y exclusión mutua entre X-Ray y Hide Distant
Scenery; solicitudes de emotes, catálogo/perfil local y limpieza durante cargas pendientes. `LUAU_TEST_PREFIX` permite usar una instalación externa de Luau.

No prueba físicas, streaming, rendimiento, controles táctiles reales ni las
restricciones del executor o del servidor Roblox. Las funciones aún marcadas
como pendientes siguen desactivadas.
