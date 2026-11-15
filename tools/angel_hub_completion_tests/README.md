# GUI de continuación: pruebas simuladas

```sh
bash tools/luau/setup.sh
node tools/angel_hub_completion_tests/run.cjs
```

Se reutilizan fixtures de `angel_hub_visual_tests` y
`angel_hub_partial_tests`. Se comprueban los botones reales de la GUI,
selección de jugadores, Knife Aura, Kill All y Kill Selected (equipar cuchillo,
objetivos lejanos, cooldown, interrupción y retorno), Gun Aimbot PC/móvil,
WallCheck, hook nativo y arma en mochila. Knife Throw prueba el predictor,
WallCheck, restauración del hook y carga tardía de WeaponService en ambos
perfiles. Auto Pickup Gun prueba la tecla configurable, ausencia de API,
roles, lobby y touch. Incluye Fling manual/automático, ESP, movimiento y Auto
Vote. Las demás pruebas están en `tools/angel_hub_farm_tests`.
`LUAU_TEST_PREFIX` permite otra instalación de Luau.

Los mocks no verifican física, streaming, validaciones del servidor, contratos
cambiantes de MM2, daño, captura de GunDrop ni compatibilidad con un executor
real. Los intentos no confirman impactos. Otros controles permanecen marcados
como pendientes, incluidos los flings y Kill All de Farm con bolsa llena.
