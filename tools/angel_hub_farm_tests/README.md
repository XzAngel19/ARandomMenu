# Auto Farm, Auto Win y Auto Unbox: pruebas simuladas

```sh
bash tools/luau/setup.sh
node tools/angel_hub_farm_tests/run.cjs
node tools/angel_hub_farm_tests/win.cjs
node tools/angel_hub_farm_tests/unbox.cjs
node tools/angel_hub_completion_tests/run.cjs
```

Reutilizan fixtures de `angel_hub_partial_tests` y comprueban Walk/Below,
progreso/atasco, monedas y contadores, bolsa llena y reset, lobby, Safe Zone,
retorno y guardas de vacío. Auto Win: plataforma y retorno, eventos de victoria,
contador por ronda, Murder/restauración ante cancelación y conflicto con Farm;
Sheriff usa pruebas del predictor integrado y WallCheck en completion_tests.
Auto Unbox: catálogo/precios/saldo, bloqueo de peticiones y cancelación con
operaciones asíncronas. Las cuatro automatizaciones de movimiento/gasto no se
reactivan automáticamente al cargar la configuración al inyectar.

Son mocks: no verifican físicas, validaciones del servidor, compras, premios,
impactos, victorias o compatibilidad real con Roblox/executores. Las opciones
pendientes siguen bloqueadas, incluidos ambos flings de Auto Win y los extras
de bolsa llena que no están conectados.
