# GUI independiente: Knife Throw y Anti Fling

```sh
bash tools/luau/setup.sh
node tools/angel_hub_knife_tests/run.cjs
```

Usa los mocks de `tools/angel_hub_partial_tests/`. `LUAU_TEST_PREFIX` permite
usar otra instalación de `@luau-rs/luau`. Comprueba Knife Throw manual y
automático, WallCheck, fallo/NaN del predictor, propiedad y restauración de
hooks, equipamiento, tipos de retorno y limpieza, además de Anti Fling,
suspensión, soporte del suelo y módulos previamente implementados. Las pruebas
son simulaciones y no comprueban física, replicación ni resultados en Roblox.
