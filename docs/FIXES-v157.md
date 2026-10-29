# v157 — Contrato Knife manual y simulación MM2

Stamp `v157-20261029-mm2-simulation-contract` · 2026-10-29.

## Contrato de Knife manual

En la copia de cliente `place, source.rbxlx` de TestingStuff (blob Git
`755f47708dfbe83a5eaad25d5a60a5a36788dcf6`), el módulo cliente decompilado
`WeaponService` devuelve `CFrame.new(...)` tanto de `GetMouseTargetCFrame` como
de `GetTargetPosition`. En v156 el segundo redirect de `KnifeThrow.lua`
devolvía el Vector3 directamente. El test anterior repetía ese error de
contrato. Ahora ambos devuelven un CFrame y, si no hay punto válido, conservan
la llamada y argumentos originales. El test ejecuta el redirect real con un
consumidor simulado que accede a `.Position`, tanto para cursor como para
coordenadas de pantalla, con objetivo y carril especulativo; también verifica
fallback, sin equipar, OFF y desmontaje. No accede a cámara ni envía un remote.

La copia puede no ser la versión actual del juego. No contiene el código
servidor ni prueba que los controles actuales en PC/móvil invocan esta función,
que la sustitución funcione en Delta o que se produzca daño.

## Auto Shoot

Las rutas Bullet y CFrame antiguas intentaban una segunda ruta si el helper
común devolvía false o lanzaba un error, aunque esto podía significar un rechazo
de seguridad o que ya se había enviado la primera solicitud. La ruta secundaria
solo debe existir cuando el helper común no está disponible. Un error local en
FireServer ya no devuelve éxito; ante un error incierto se mantiene el pacing
local para no repetir por frame. Experimental también aplica pacing al error y
muestra `send uncertain` en vez de afirmar que no hubo envío. Un error no
demuestra si se alcanzó a enviar una solicitud y un `pcall` exitoso
no demuestra aceptación ni impacto en servidor.

`tools/test_mm2_auto_shoot_dispatch.py` utiliza las funciones reales con
remotos simulados; cubre helper true/false/error, error posterior al envío,
WallCheck, un solo envío en fallback y error de transporte. La suite de
Experimental comprueba el pacing después de error.

## Simulación determinista reproducible

`LUAU=tools/luau/bin/luau python3 tools/test_mm2_trajectory_simulation.py`
ejecuta `Prediction.lua` real con mundo simulado: 30/60/120 Hz, RTT de
50/120/220 ms, distancias iniciales de 15/50/100 studs, velocidades de cuchillo
72/96/140 studs/s y seis trayectorias (486 casos, n=81 por trayectoria). El
simulador define de manera independiente un tiempo de resolución de `RTT +
25 ms` y cuchillo recto a velocidad constante; no prueba que MM2 use ese tiempo.
El error es la distancia entre el punto de mira y el centro del torso sintético
en el instante hipotético de resolución o llegada; **no es tasa de aciertos**.

| Trayectoria | Gun media / máx. studs | Knife media / máx. studs |
|---|---:|---:|
| quieto | 0 / 0 | 0 / 0 |
| lateral constante | 0 / 0 | 0 / 0 |
| aproximación constante | 0 / 0 | 0 / 0 |
| salto (disparo casi en ápice) | 2,174 / 4,076 | 4,076 / 4,076 |
| parada brusca después del disparo | 2,480 / 3,920 | 13,257 / 28,219 |
| giro brusco después del disparo | 3,507 / 5,544 | 18,748 / 39,908 |

Las trayectorias rectas, muestras perfectas, latencia e impacto elegidos por el
simulador son favorables al modelo: esos ceros no son una garantía de precisión.
En el salto simulado la velocidad vertical casi nula hace que el guard existente
no aplique gravedad; esto limita el pronóstico en un ápice genuino, pero otra
prueba previa documenta estados de salto/velocidad cero engañosos que castigaban
aplicar gravedad siempre. Hace falta evidencia real para distinguirlos antes de
cambiar un comportamiento compartido por Gun y Knife. Los cambios de dirección
ocurren después de la toma de datos y no son previsibles con certeza.

Las suites existentes prueban además geometría cercana, paredes, inocentes,
selección de Experimental, persistencia y otras funciones bajo mocks. Ninguna
simula completamente Roblox, anticheat, red, físicas o servidor de MM2; las
comparaciones de tasa de acierto Bullet/CFrame/Experimental siguen pendientes
con pruebas reales equivalentes.
