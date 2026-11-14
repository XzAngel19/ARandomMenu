# Nueva GUI: pruebas simuladas

Desde la raíz, preparar el Luau empaquetado y ejecutar:

```sh
bash tools/luau/setup.sh
node tools/angel_hub_new_tests/run.cjs
```

Se puede usar otro directorio con `LUAU_TEST_PREFIX` si contiene
`node_modules/@luau-rs/luau`. El runner reutiliza los mocks de
`tools/angel_hub_partial_tests/` y prueba la compilación, el arranque GUI,
entrada PC/móvil, cancelación, WallCheck, Macro, roles, hook y limpieza, Aura,
y el filtrado/adaptación de confirmaciones. Estas son simulaciones, no pruebas
en Roblox; no validan la disponibilidad del ejecutor, la recogida o impactos en
el servidor. No se escriben datos de calibración en estas pruebas.
