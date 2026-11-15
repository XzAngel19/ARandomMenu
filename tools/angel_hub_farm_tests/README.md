# Auto Farm, Auto Win, Fling y Auto Unbox: pruebas simuladas

```sh
bash tools/luau/setup.sh
node tools/angel_hub_farm_tests/run.cjs
node tools/angel_hub_farm_tests/win.cjs
node tools/angel_hub_farm_tests/unbox.cjs
node tools/angel_hub_completion_tests/run.cjs
```

Cubren Farm Walk/Below, monedas y contadores, reset, lobby, Safe Zone y
restauración; Coins Aura con alcance fijo de 15 studs, touch y restauración;
y Auto Grab Gun And Shoot exclusivamente con bolsa llena. Auto Win verifica
plataforma, contadores, Murder/Sheriff, flings optativos y coordinación con el
motor Fling: volver a la plataforma, tocar GunDrop, cancelar al acabar ronda,
retaliación tras muerte y regreso al punto de respawn, y conflictos con Farm.
Auto Unbox comprueba catálogo/saldo y peticiones asíncronas. Las pruebas usan
fixtures de `angel_hub_partial_tests` y `angel_hub_completion_tests`.

Los mocks no verifican físicas, validaciones del servidor, recogidas, compras,
impactos, victorias ni compatibilidad real con Roblox/executores. El Fling
Murder If Dead intenta el movimiento desde el lugar del respawn, incluido lobby,
solo después de una muerte detectada y con el interruptor activado. En Auto
Farm no se hace esa salida desde el lobby. Los flings y Kill All tras bolsa
llena de Farm y otros controles siguen bloqueados.
