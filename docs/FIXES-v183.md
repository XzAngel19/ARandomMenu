# v183 — Gun Aimbot PC, Calibration y Motion Lock

Fecha: 2026-11-04 · rama `arena/9492e6b6-arandommenu` · stamp
`v183-20261104-native-gun-calibration`.

## UI

- **Perf report** fue retirado. Session Info conserva sus métricas internas.
- **Move dock** solo aparece en dispositivos que el menú clasifica como móvil;
  allí sigue llamando al controlador de colocación. No aparece en PC.

## Calibration

- Ya no hay tarjeta, módulo visual ni opciones de Calibration o trails. El
  diálogo centrado Yes/No incluye **Don't Show Again**, desmarcado por defecto.
  Solo si se marca se recuerda la respuesta; los perfiles antiguos vuelven a
  preguntar. Con No no se observa ni escribe telemetría nueva y se conservan
  los archivos existentes. Con Yes se inicia el registro y se guarda la
  respuesta mediante el sistema normal de configuración.
- El archivo principal es `Wurst/Telemetry/MM2_Trajectory_Calibration.json`
  dentro del workspace del executor. Antes de sustituir un historial existente
  se comprueba que no cambió, se hace una copia y se verifica. También se
  protege un archivo vacío o uno creado mientras estaba abierto el diálogo. Si
  falla la copia o cambia el historial, se conserva y se informa del fallo.
- Se observan los proyectiles `ThrowingKnife` disponibles para el cliente,
  propios y de otros jugadores. Se guardan identificador, aparición, dirección,
  velocidad cuando existe, enlace al dueño si llega, trayectoria y final. Los
  intentos manuales observados mediante `WeaponService.KnifeThrown.Event` y los
  automáticos del menú llevan un identificador que se asocia al proyectil; la
  activación de la herramienta no cuenta por sí sola como impacto. Para tiros
  propios asociados se registran también trayectoria y salud del objetivo cuando
  están disponibles. La dirección del proyectil es una observación; la posición
  del mouse en el evento manual es solo una aproximación, no un paquete probado.
- No se descartan eventos al llegar al antiguo límite de 2400. Se guarda primero
  un snapshot y se archivan lotes en `Wurst/Telemetry/MM2_Trajectory_<sesión>_part_<n>.json`;
  solo se retiran de memoria cuando el archivo se relee con bytes idénticos.
  `session.archiveFiles` enumera los segmentos verificados. Si un intento deja
  un archivo parcial, el siguiente usa otro nombre sin sobrescribirlo. Si falla
  IO o se revoca consentimiento, los eventos no se descartan deliberadamente;
  fallos persistentes pueden consumir memoria o impedir que se guarden datos
  posteriores, y se advierten en consola.
- Para volver a preguntar después de marcar la casilla, con el menú descargado
  se puede poner `states["MM2.Calibration.DontShowAgain"] = false` en el perfil
  `Wurst/Profiles/Game_<GameId>.lua` y volver a cargar. No hace falta borrar los
  archivos de telemetría.

## Gun Aimbot en PC

- Solo PC ofrece **Bullet** y **Silent(CFrame)**. Cada modo conserva WallCheck,
  Macro y objetivo propios; una única Keybind opcional comparte el shortcut ya
  existente y dispara/equipa aun con el módulo apagado. Móvil conserva sus tres
  modos anteriores, incluido Experimental, y sus controles de acción.
- Con el módulo encendido, un hook de `__namecall` en PC intenta sustituir los
  dos CFrames del `Gun.Shoot:FireServer` nativo por los construidos por la ruta
  existente, sin girar la cámara y sin enviar un segundo paquete. Con WallCheck
  activado, una línea bloqueada no se redirige; el clic original sigue su curso.
  Si no hay objetivo válido, falla la geometría o falla la resolución, también
  se preserva el clic nativo. Las llamadas del executor y otros remotes no se
  redirigen. Al apagar se retira el hook cuando es seguro, o se deja inactivo si
  otro hook lo ha envuelto. Sin `hookmetamethod`, `getnamecallmethod` y
  `checkcaller` se avisa; la tecla todavía puede intentar disparar.
- El código usa el contrato `Gun.Shoot(CFrame, CFrame)` identificado en el
  menú. El script nativo exacto de la versión actual del juego no se ha podido
  contrastar; ni los mocks ni un paquete enviado prueban que el servidor acepte
  una posición Silent lejana o aplique daño.

## Motion Lock

- **Freeze Movements** pasa a llamarse **Motion Lock**, conservando la clave de
  configuración `Movement.FreezeMovements` y sus dos modos.
- **Position Lock:** con Lock rotation encendido se mantiene la orientación,
  también con Keep gravity. Si está apagado, no se ancla el root: se fija la
  posición sin forzar el giro. Keep gravity conserva la caída y Return if pushed
  corrige deriva horizontal cuando su límite es mayor que cero. Al apagar o
  cambiar de modo se restaura el estado previo de anclaje sin teletransportar ni
  restaurar un CFrame viejo.
- **Motion:** se conservan las opciones independientes de emotes y animaciones,
  exclusión de ataques, gestión de respawn y limpieza de pistas/conexiones.

## Pruebas y límites

`tools/test_calibration_consent.py` ejecuta los callbacks reales y prueba Yes,
No, checkbox, persistencia, legacy y errores de backup. `test_calibration_capture.py`
prueba eventos manuales/menú, correlación, trayectoria/salud, registro de
proyectiles sin enlace y archivos >2400, IO fallido, concurrencia y revocación.
`test_gun_native_pc.py`, `test_gun_safety.py` y `test_gun_mode_migration.py`
cubren el hook y su limpieza, un solo envío, WallCheck, modos, tecla real OFF y
móvil. `test_freeze_general.py`, `test_freeze_movements.py`, `test_gui_v181.py`
y `test_settings_v183.py` cubren modos, gravedad, rotación, restauración y UI.
`bash tools/validate.sh` terminó correctamente: 82 fuentes Lua compiladas,
121 suites Python/Luau, bundle de 80 fuentes, boot con `failures=0` y 48 tarjetas
en las auditorías debug y release. La matriz simulada incluye PC, móvil y carga
por fuentes para MM2 y los demás juegos.

Todas son pruebas con mocks: no prueban visualización de Roblox/Delta, el
comportamiento real de un executor, FPS, replicación ni la aceptación o daño en
el servidor. El cliente no puede registrar lanzamientos que no recibe por
streaming u otras restricciones del juego.
