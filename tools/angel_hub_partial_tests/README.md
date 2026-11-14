# Angel Hub: pruebas parciales

Estas pruebas simulan Roblox; no verifican el comportamiento en el juego, la aceptación del servidor ni la compatibilidad con ejecutores.

Cubren arranque PC/móvil y fuera de MM2; Speed, Rise, X-Ray, Anti AFK, Get Gun, teletransportes y Gun/Trap ESP; Auto Farm Walk/Below, lobby, Safe Zone, bolsa, avance/atasco y contadores que se pausan y se reanudan; Coins Aura y Knife Aura; Gun Aura y Auto Get Gun, con restauración condicional y restricción de mapa; reproducción y catálogo local de emotes, sin duplicados ni animaciones predeterminadas; Auto Vote; Auto Shoot Bullet/CFrame básico; Auto Win parcial con plataforma, regreso, contadores por VictoryScreen, opción Sheriff independiente y limpieza; y Auto Unbox con catálogo/precios y saldo simulados, bloqueo de llamadas simultáneas y espera de respuestas.

Para contar victorias se usan los tres primeros argumentos de `Remotes.Gameplay.VictoryScreen` y las combinaciones de rol/resultado que aparecen en `GameplayAnimations` del volcado XML de TestingStuff, blob `755f47708dfbe83a5eaad25d5a60a5a36788dcf6`. Se ignoran resultados desconocidos o recibidos mientras Auto Win está apagado, y se evita contar dos veces la misma ronda. Esto no confirma que las señales o el comportamiento actual del servidor sigan iguales.

Auto Win solo tiene la plataforma y la opción Sheriff básica; Murder y ambas opciones de Fling siguen bloqueadas. La plataforma puede quedarse creada si retirarla dejaría al personaje en el vacío. El disparo usa predicción sencilla y no garantiza impacto; Auto Win Sheriff tiene WallCheck independiente, desactivado por defecto. Experimental y Gun Aimbot siguen pendientes.

Auto Unbox gasta la moneda seleccionada. `Auto` no elige Gems ni llaves; solamente compra cuando puede leer la caja, el precio y el saldo. Por defecto no reproduce animación. Tras una respuesta incierta o una compra, espera que el saldo se actualice antes de otra solicitud. El servidor puede aplicar otras condiciones y una solicitud ya enviada no se puede cancelar.

```sh
npm install --prefix /tmp/angel-test-deps @luau-rs/luau@0.739.0
node tools/angel_hub_partial_tests/run.cjs
```

Gun Aura mueve localmente la pieza de GunDrop dentro del radio seleccionado y restaura su estado cuando puede; Auto Get Gun solo solicita touch, sin teletransportar. Ambos dependen de `firetouchinterest` y de que la detección del mapa/objeto coincida con MM2: ni la recogida ni el alcance están garantizados por el servidor.

Get All Emotes añade entradas al perfil local, utilizando el catálogo disponible además de siete animaciones conocidas; no concede propiedad en el servidor. Play Emote solicita el BindableEvent del juego o reproduce una animación local: permisos, GUI legacy y replicación no están verificados.
