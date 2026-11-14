# Pruebas simuladas de la GUI Main independiente

```sh
bash tools/luau/setup.sh
node tools/angel_hub_main_tests/run.cjs
```

Reutiliza los mocks del directorio `tools/angel_hub_partial_tests`. Se puede
seleccionar otra instalación de `@luau-rs/luau` con `LUAU_TEST_PREFIX`.
Comprueba compilación, arranque, controles condicionales, PC/móvil, Aimbot
apagado, Custom sin rol Murderer, WallCheck de Normal e Instakill, hook y
limpieza, feedback de predicción, roles, Auto Shoot independiente, Proximity,
recarga y cadencia, Gun Aura y Knife Aura con cancelación/tecla sostenida.
No ejecuta Roblox ni prueba impactos, replicación o compatibilidad del ejecutor.
