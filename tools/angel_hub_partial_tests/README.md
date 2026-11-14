# Angel Hub: pruebas parciales

Estas pruebas simulan Roblox; no verifican el comportamiento en el juego, la aceptación del servidor ni la compatibilidad con ejecutores.

Cubren arranque PC/móvil y fuera de MM2; Speed, Rise, X-Ray, Anti AFK, Get Gun, teletransportes y Gun/Trap ESP; Auto Farm Walk/Below, lobby, Safe Zone, bolsa y avance/atasco; Coins Aura y Knife Aura; Auto Vote; Auto Shoot Bullet/CFrame básico, detección por Knife o datos de roles, WallCheck, radio y cambios de ronda; y Auto Unbox con catálogo/precios y saldo simulados, bloqueo de llamadas simultáneas, actualización de saldo y espera de respuestas. También prueban limpieza y bloqueo de módulos pendientes.

Auto Unbox gasta la moneda seleccionada. `Auto` no elige Gems ni llaves; solamente compra cuando puede leer la caja, el precio y el saldo. Por defecto no reproduce animación. Tras una respuesta incierta o una compra, espera que el saldo se actualice antes de otra solicitud. El servidor puede aplicar otras condiciones y una solicitud ya enviada no se puede cancelar.

Auto Shoot usa una predicción sencilla, no el predictor completo; Experimental sigue bloqueado. El menú continúa siendo parcial: Gun Aimbot, Auto Win y otros módulos aún no están integrados.

```sh
npm install --prefix /tmp/angel-test-deps @luau-rs/luau@0.739.0
node tools/angel_hub_partial_tests/run.cjs
```
