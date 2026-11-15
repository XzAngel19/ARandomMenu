# GUI de continuación: pruebas simuladas

```sh
bash tools/luau/setup.sh
node tools/angel_hub_completion_tests/run.cjs
```

Se reutilizan fixtures de `angel_hub_visual_tests` y
`angel_hub_partial_tests`. Incluye listas de jugadores, Knife de corto alcance,
Fling manual y automático con diagnóstico y sin depender de spawns, visuales sin filtro de distancia, disparos de Auto Win y Auto Farm, y bloqueo de autoload de
automatizaciones. Ejecuta también regresiones de visuales, movimiento y Auto
Vote. Las pruebas de Farm, Coins Aura, Auto Win y Auto Unbox están en
`tools/angel_hub_farm_tests`. `LUAU_TEST_PREFIX` permite otra instalación.

Los mocks no verifican física, autoridad del servidor, restricciones de un
executor ni funcionamiento efectivo en Roblox. Otros controles permanecen
marcados como pendientes, incluidos los flings y Kill All de Farm tras llenar
la bolsa.
