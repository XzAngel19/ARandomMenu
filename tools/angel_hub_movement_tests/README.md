# GUI independiente: movimiento y regresiones

```sh
bash tools/luau/setup.sh
node tools/angel_hub_movement_tests/run.cjs
```

Utiliza los mocks de `tools/angel_hub_partial_tests/`. `LUAU_TEST_PREFIX`
permite usar otro directorio con `node_modules/@luau-rs/luau`.
Verifica compilación, GUI y entrada numérica manual, regresiones de Gun Aimbot,
Auto Shoot, Gun Aura, Knife Aura, y Fly/Speed/Gravity en PC y móvil: teclas,
prioridad, modos, WallCheck, salto, fuerzas, cambios externos, respawn y unload.
Son pruebas simuladas; no ejecutan Roblox ni verifican física o aceptación real.
