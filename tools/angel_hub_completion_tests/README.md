# GUI de continuación: pruebas simuladas

```sh
bash tools/luau/setup.sh
node tools/angel_hub_completion_tests/run.cjs
```

Se reutilizan los fixtures de `angel_hub_visual_tests` y
`angel_hub_partial_tests`. Incluye listas de jugadores, Knife de corto alcance,
ciclo de Fling, Auto Win Sheriff y bloqueo de autoload de automatizaciones de
movimiento/gasto. Ejecuta también regresiones de visuales, movimiento y
Auto Vote. Las pruebas específicas de Auto Farm, Auto Win y Auto Unbox están en
`tools/angel_hub_farm_tests`. `LUAU_TEST_PREFIX` permite usar otra instalación.

Los mocks no verifican física, autoridad del servidor, restricciones de un
executor ni funcionamiento efectivo en Roblox. Otros controles permanecen
marcados como pendientes, incluidos los flings de Auto Win y acciones de bolsa
llena que todavía no se integraron.
