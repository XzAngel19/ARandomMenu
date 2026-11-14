# GUI independiente: Speed y Sprint Tail MM2

```sh
bash tools/luau/setup.sh
node tools/angel_hub_sprint_tests/run.cjs
```

El runner reutiliza `tools/angel_hub_partial_tests/`; `LUAU_TEST_PREFIX` permite
usar otra instalación de `@luau-rs/luau`. Comprueba Speed por botón sin tecla,
Sprint Tail con tecla o acción táctil mantenida en MM2, prioridad con Speed y
Fly, soltar/foco, muerte, respawn y unload. También prueba Gravity y regresiones
de Main en simulaciones PC/móvil. No sustituye pruebas reales en Roblox.
