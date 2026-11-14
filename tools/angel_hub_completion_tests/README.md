# GUI de continuación: pruebas simuladas

```sh
bash tools/luau/setup.sh
node tools/angel_hub_completion_tests/run.cjs
```

Se reutilizan los fixtures de `angel_hub_visual_tests` y
`angel_hub_partial_tests`. Incluye pruebas de listas actualizadas, acciones
Knife de corto alcance y ciclo de vida de Fling: inhibición por conflictos,
fin de ronda, salida/muerte del objetivo, proximidad al vacío, cancelación y
limpieza. También ejecuta las regresiones de visuales, movimiento y Auto Vote.
`LUAU_TEST_PREFIX` permite usar otra instalación de la herramienta.

Los mocks no verifican física real, autoridad del servidor, restricciones de
un executor ni funcionamiento efectivo en Roblox. Farm, Auto Win, Auto Unbox y
los demás controles marcados como pendientes siguen sin integrarse.
