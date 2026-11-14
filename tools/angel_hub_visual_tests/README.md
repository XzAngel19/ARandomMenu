# GUI independiente: visuales y utilidades

```sh
bash tools/luau/setup.sh
node tools/angel_hub_visual_tests/run.cjs
```

Los mocks de `tools/angel_hub_partial_tests/` prueban los módulos anteriores y
la adaptación Player ESP/Nametags/HP, roles MM2, Chams, Coin ESP, Gun/Trap ESP,
Auto Vote, Infinite Jump, Noclip, iluminación/cámara, botones y limpieza.
También cubren PC/móvil simulados. `LUAU_TEST_PREFIX` permite usar otra
instalación de `@luau-rs/luau`. No prueban física, replicación ni rendimiento
reales en Roblox.
