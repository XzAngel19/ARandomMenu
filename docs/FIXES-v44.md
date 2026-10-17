# v44 — cámara y presentación simple

## Uso

- **World → FreeCam**. PC: WASD/flechas, Q/E o Ctrl/Espacio, arrastrar con clic derecho para mirar, Shift para acelerar. Solo Speed y Sensitivity; sin tecla preasignada.
- Móvil: joystick izquierdo, arrastre derecho para mirar, +/− para subir/bajar y Exit FreeCam. Movimiento y giro aceptan dedos distintos; soltar fuera del botón también libera la acción.
- **Render → Zoom → Through walls**. Se conserva el desbloqueo de primera persona y los límites existentes. Through walls empieza desactivado para no cambiar configuraciones anteriores.
- Self HP pasa a un rectángulo pequeño con corazón, cifra y barra. Sin borde redondeado, placa de estado ni etiquetas HEALTHY/CRITICAL. Los colores del fondo y los controles táctiles siguen el tema. Se retiró “Studio” de los títulos de Text GUI y Radar; no se quitaron controles ni configuraciones guardadas.

## Implementación de cámara

FreeCam controla CFrame/Focus con CameraType Scriptable después del paso de cámara. No mueve ni ancla el root, no cambia FOV ni CameraSubject. Usa controles nativos desactivables; si PlayerModule no está disponible, consume las teclas de movimiento, oculta TouchGui y manda movimiento cero al Humanoid. La gravedad y otros módulos que muevan explícitamente al personaje siguen siendo independientes.

Se restauran los controles previamente habilitados, TouchGui, cursor y cámara. Pérdida de foco o escritura limpia entradas pendientes. Se manejan cámara ausente/reemplazada y respawn sin restaurar un CameraSubject muerto. Si otro controlador toma la cámara antes de apagar FreeCam, no se pisa su nuevo tipo/posición.

Zoom intercepta `Update(dt, desiredCameraCFrame, desiredCameraFocus)` de la oclusión. Con el controlador moderno, `GetCameras()` devuelve `{}`: se obtiene la clase Poppercam del CameraModule y se restaura su método por identidad. No se modifican constantes, no se usan debug/getconnections y no se cambia la colisión física de paredes. El extrapolador de Poppercam se reinicia para no reanudar con una posición antigua. También se admite el controlador antiguo que expone la instancia activa. Require se hace fuera del render; si no hay un módulo accesible se indica **walls unavailable**, sin romper el zoom normal. Cámaras personalizadas pueden no usar este contrato.

### Referencias inspeccionadas, no copiadas

VapeV4ForRoblox:
- Freecam `e6a68b8735aa900f71d7ff659d613c6a3025e1b4`: Classic depende de conexiones/upvalues; no trae nuestros controles táctiles.
- CameraPhase `d3ad8b7e420517fcfb0914452ef6833acf44ed74`: cambia una constante interna de Popper. No se replicó ese parche.

Roblox-Client-Tracker, fuentes consultadas mediante GitHub:
- PlayerModule `d0666833fb98001134375a10e528e2a67ea8faac`.
- CameraModule `a86b371c9f9e5dc50825995f9cc862f86c9d41df`: instancia interna, retorno público vacío y contrato Update.
- BaseOcclusion `d569ce0d41383e0e21b9a74451d35160b0afbbd1`.
- Poppercam `5b8eb0de54d6f57dd4c02f6d78c85ed37d87c8b6`: clase compartida y extrapolador.
- Invisicam `00887efab57e7ad15477f5d1513926c3760baae8`: limpieza de transparencia al interceptar una instancia antigua.

## Predicción: corrección acotada, no una mejora enorme demostrada

Se conservaron los originales v43 en `prediction-baselines/v43/`, con hashes. **Reference v41 sigue seleccionable** en Calibration. Adaptive añade un caso específico para Gun y Knife: velocidad horizontal replicada casi cero, pero dos intervalos de posiciones consecutivas y coherentes demuestran desplazamiento. No se inventa velocidad desde MoveDirection/WalkSpeed. Se rechazan ventanas cortas, paradas, cambios bruscos, valores no finitos y velocidades superiores al límite existente. El historial está acotado y se reinicia tras teleports/respawn. Se registra `motionSource` para distinguir posición de velocidad.

Knife recalcula el intercepto a 96 studs/s —o ThrowSpeed válido— antes de aplicar la gravedad del **objetivo**, no de la cuchilla. El endpoint anterior permanece en la telemetría. No se agregaron opciones a Knife Throw, paquetes extra ni gates de distancia/movimiento a Auto Shoot. WallCheck sigue comprobando el cuerpo actual.

Se volvió a consultar TestingStuff: el principal conserva blob `80ed658e206c330ab28145ff05fafb146d507ed3`; no es una captura nueva. Se añadió al contraste el respaldo v33 `f5c02e990990f450830452f7afeeb4bb1c9eceee` (varios nombres de respaldo apuntan al mismo blob). Su fixture desidentificada guarda el hash original. Los Learning actual/histórico `6b07e30dab4f747bdda801f211e9fb216c53487a` / `b2ca36c6b8b519d880e03ddbffb5dc6c21e56b5d` contienen 93/300 registros de shots guardados pero ninguna targetTrajectory comparable. Sus etiquetas antiguas de miss/unconfirmed no permiten ajustar una fórmula causal ni contar aciertos fiables.

| Replay del solver Gun | Muestras | MAE v43 | MAE v44 |
|---|---:|---:|---:|
| desarrollo v35 | 176 | 0.459032 | 0.459032 |
| sesión histórica v30 | 284 | 3.211581 | 3.211581 |
| pequeñas v34/v31 | 17 | 0.203354 | 0.203354 |
| respaldo v33 | 170 | 0.437873 | 0.432303 |

Solo cambian **2 de 647 muestras**. En v33 son ventanas registradas alrededor de Knife usadas como movimiento adicional para evaluar el solver Gun, no evidencia de aciertos de Knife. Los casos sintéticos comprueban el intercepto real de Knife, pero no reemplazan una prueba online. No se presenta esta mejora limitada como “muchísimo mejor”.

Se descartaron reemplazos generales por CV, eliminación indiscriminada de aceleración y velocidad vertical sin gravedad: empeoraban los replays. Aplicar física vertical completa indiscriminadamente tampoco mejoró todos los conjuntos. Los resultados y candidatos quedan resumidos en `prediction-baselines/v44/evidence.json`. Son conjuntos ya conocidos, no validación ciega ni hit-rate del servidor.

## Verificación

27 suites `tools/test_*.py`, incluidas cámara y predicción v44; boot completo con módulos reales y bundle; compilación de las fuentes Lua; comprobación del bundle y diff. La suite de cámara prueba teclado, multitouch, diagonales, entradas simultáneas, foco, restauración, reemplazo de cámara, API moderna vacía, oclusión y límites de Zoom.

No se ejecutó un cliente Roblox vivo. Falta confirmar controles en dispositivos/executores concretos, cámaras personalizadas y precisión de servidor con sesiones nuevas. No se afirma perfección ni superioridad sobre Vape.
