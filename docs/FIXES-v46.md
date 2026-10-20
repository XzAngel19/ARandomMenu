# v46 — Speed, Vehicle Speed e Infinite Jump Fall

## Referencia consultada: VapeV4ForRoblox

Se inspeccionaron los fuentes reales de `7GrandDadPGN/VapeV4ForRoblox`, no solo la interfaz:

- `src/games/universal - base/Blatant/Speed.lua`, blob `bf864c979be03c2d3241c71bec0a2da85426ce7e`: ejecución en PreSimulation, MoveDirection nativo, exclusión de Climbing/Fly y restauración de WalkSpeed.
- `src/games/universal - base/base.lua`, blob `3e06c0e8276568e2cf6a89d8b985c50febe370fc`: implementaciones de Velocity, Impulse, CFrame, TP y WalkSpeed. CFrame añade solamente la diferencia respecto a WalkSpeed; Velocity conserva Y e Impulse corrige solamente X/Z.
- Prison Life, `src/games/prison life/155615604 - main/Blatant/VehicleSpeed.lua`, blob `45571571a390e395c665e1b654b9f512506d1852`: modifica MaxSpeed/Torque de asientos del contenedor específico del juego.
- Jailbreak, `src/games/jailbreak/606849621 - main/Blatant/VehicleSpeed.lua`, blob `504ac5e57b2eab231bcf4d6b94d87018a9bb701f`: hooks de AlexChassis/Boat específicos de ese motor.

Repositorio: https://github.com/7GrandDadPGN/VapeV4ForRoblox

No se copiaron hooks de Jailbreak ni rutas de Prison Life a un módulo universal: no tienen esos contratos en otros juegos.

## Speed

- Los cinco modos siguen disponibles: WalkSpeed, Velocity, Impulse, CFrame y Teleport. Ahora se actualizan antes de la simulación física.
- La dirección viene de Humanoid.MoveDirection, conservando la intensidad analógica del control móvil/gamepad. No se reconstruye como WASD relativo a la cámara.
- Velocity e Impulse corrigen X/Z y conservan Y; al soltar el movimiento no mantienen el último empuje horizontal.
- CFrame/Teleport añaden solo `max(0, Speed - WalkSpeed)`, evitando sumar toda la velocidad encima de la marcha nativa. Teleport acumula el intervalo de ráfaga; el delta de un frame se limita para no producir un gran salto tras un bloqueo del cliente.
- Wall check de esos modos usa Blockcast del volumen del root, respeta CanCollide y el grupo de colisión. Hay fallback de rayo.
- Se omite el movimiento a pie estando sentado, anclado, nadando, escalando, en Physics/PlatformStanding o usando Fly.
- WalkSpeed guarda el valor previo y el último que escribió. Una modificación externa posterior no se pisa al desactivar; si ocurre mientras el módulo sigue activo, se convierte en la nueva base de restauración.
- Sprint sigue siendo una acción mantenida dentro de Speed y funciona con Speed OFF. No activa Auto jump con Speed OFF y no reduce un Speed configurado por encima de 30.

## Vehicle Speed

Solo actúa sobre un VehicleSeat ocupado por el propio Humanoid, nunca sobre un pasajero ni sobre una plataforma debajo del personaje.

- **Multiplier:** multiplica el MaxSpeed y Torque nativos del asiento desde su base, sin multiplicar repetidamente la velocidad física actual.
- **Seat:** límite MaxSpeed absoluto.
- **Velocity:** velocidad horizontal absoluta según ThrottleFloat, incluyendo marcha atrás y aceleración parcial; conserva Y. Con acelerador a cero deja que el vehículo ruede/frene con su física normal, sin obligarlo a ir hacia delante.
- **Motors:** multiplica comandos nativos de HingeConstraint en modo Motor, sin realimentar la propia escritura. Respeta comandos nuevos/reversos, pone el comando a cero al soltar el acelerador y no restaura un comando antiguo de movimiento después de detenerse. Necesita un controlador de motores compatible; no se inventa el sentido de giro de las ruedas.
- Velocidad absoluta y multiplicador tienen controles separados y visibles solo en los modos relevantes. La velocidad del vehículo ya no depende del slider a pie.
- Los motores se descubren una vez por vehículo y mediante DescendantAdded; no se recorre todo el modelo cada frame. Los que salen del modelo o dejan de ser motores se restauran y dejan de controlarse.
- Cambiar de modo, salir, cambiar de vehículo, desactivar o destruir restaura las propiedades que todavía conservan nuestra última escritura y desconecta el observador. No se restaura una velocidad física vieja: sería un nuevo impulso artificial.

**Límite:** vehículos con chasis personalizados, autoridad del servidor o motores propios pueden ignorar estas propiedades. No es soporte universal para todos los vehículos de Roblox ni una garantía contra correcciones del servidor.

## Infinite Jump — Fall real del cliente

- Se eliminó todo el manejo manual de AnimationTracks: no se carga, reproduce, detiene ni reinicia una animación de caída por frame.
- Mientras Fall está activo, el Humanoid local tiene Jumping deshabilitado y Freefall habilitado. Se limpia Humanoid.Jump antes de la simulación y se corrige una transición forzada a Jumping como respaldo.
- Cada solicitud de salto aplica la velocidad vertical configurada, conserva X/Z y entra en **Freefall aunque Y sea positiva**. No espera a que el personaje empiece a bajar.
- Si ya está en Freefall, el mantenimiento no llama ChangeState continuamente. Animate decide la animación a partir del estado nativo.
- Se mantiene Normal y Rise, además de los controles dependientes del modo. PC y móvil usan solicitudes nativas de salto; el móvil respeta el intervalo configurado, sin imponer 0.25 segundos ocultos.
- Fall no fuerza la caída estando parado ni aplica impulsos estando sentado, nadando, escalando, anclado, muerto o en estados de ragdoll/Physics. En estados incompatibles libera los flags, permitiendo el comportamiento nativo, y vuelve a adquirirlos cuando procede.
- Cambio de modo, desactivación, respawn y destrucción restauran exactamente los dos flags previos, incluso si alguno ya estaba deshabilitado antes de activar Fall.

**Esto controla el estado local, no falsifica una velocidad descendente.** Y sigue siendo positiva al subir; SetStateEnabled no garantiza el mismo estado en el servidor. El servidor puede observar posición/velocidad, rechazar impulsos o detectar saltos adicionales. No se promete invisibilidad al anticheat.

## Verificación

- 30 suites Python/Luau con cero fallos, incluida una nueva suite que ejecuta Speed completo con mocks de asiento, chasis, motores, señales y cambios externos.
- Jump ejecutado completo: Freefall ascendente, flags reales, ausencia de APIs de animación, aterrizaje, estados incompatibles, intervalo móvil, Normal/Rise, respawn y restauración de flags inicialmente falsos.
- Integración Speed + Sprint: mantener/soltar, OFF/ON, no reducir Speed, respawn, trail y limpieza.
- Full boot del bundle: `failures=0`, `[HARNESS] done`; verifica controles por modo y acciones de Sprint por teclado/touch.
- 74 fuentes Lua compiladas. Bundle regenerado con 72 archivos, stamp `v46-20261017-movement` coincidente con el loader.
- No se modificaron la seguridad de disparo ni las fórmulas de predicción publicadas en v45; sus regresiones siguen pasando.

Son pruebas deterministas del código y del arranque, **no una ejecución en Roblox vivo** ni evidencia de compatibilidad con un chasis concreto o de evasión del servidor.
