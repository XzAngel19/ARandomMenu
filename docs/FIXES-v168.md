# v168 — Destruct, teleport y ciclo de reinyección (2026-10-31)

Build: `v168-20261031-destruct-teleport-lifecycle`.

## Problema reproducido

En v167 se encolaba el loader al iniciar el menú. Destruct solo activaba
`getgenv().WURST_STOPPED` en el entorno actual. Una prueba con la cola real de
v167 y un `getgenv()` nuevo al llegar al destino reprodujo otra descarga del
menú después de Destruct. Desactivar **Keep after teleport** después de
encolar tenía el mismo punto débil. La simulación no identifica cómo comporta
la cola una versión concreta de Delta.

## Cambios

- La cola se presenta cuando `LocalPlayer.OnTeleport` llega a Started,
  WaitingForServer o InProgress, no durante el arranque; se deduplican eventos
  y se renueva la autorización si el teleport falla. La documentación de
  Synapse X muestra el patrón OnTeleport/Started para su propia API
  [1](https://synapsexdocs.github.io/libraries/syn/); no demuestra soporte de
  Delta. Roblox enumera los estados de `Player.OnTeleport`
  [2](https://developer.roblox.com/en-us/api-reference/event/Player/OnTeleport).
- Cuando funcionan `readfile` y `writefile`, el loader usa un token local por
  universo en `Wurst/Profiles/Teleport_<GameId>.txt`. Cada sesión/cambio de
  Keep usa otro token. Destruct y Keep OFF invalidan el anterior. El código
  encolado verifica autorización y universo al cargar, después de la espera y
  después de descargar, antes de ejecutar; falla cerrado si falta `readfile`
  en destino. Espera a que el juego cargue antes de comprobar `GameId`.
- La retirada normal de la interfaz durante un teleport conserva la cola ya
  presentada; Destruct explícito también la revoca después de esa retirada.
  Keep ON sigue encolando para el mismo universo y cambiar de PlaceId no lo
  impide. Keep OFF sigue guardado, y una inyección manual tras Destruct puede
  abrir de nuevo el menú sin reactivar los tokens anteriores.
- Se reconoce también `queueonteleport` además de `queue_on_teleport` y los
  proveedores `syn`/`fluxus`. Una llamada a la cola que devuelve `false` o
  falla no queda marcada como exitosa. Si el archivo ya no se puede escribir
  al revocar, se intenta eliminar el token propio.
- **Reinyección:** una referencia mínima al runtime activo permite retirarlo
  y vaciar su configuración antes de cargar el perfil nuevo. Destruct es
  idempotente y ya no destruye GUIs de otra instancia solo por compartir nombre.
  Las tareas de guardado y `BindToClose` retiradas dejan de escribir perfiles
  antiguos; el ownership por token también evita escrituras antiguas de
  configuración y de calibración MM2 cuando el entorno global cambia y el
  archivo es legible. El callback MM2 retirado no vuelve a guardar.
- Se retiró del código de producción la exposición accidental de estado interno
  de los tests en `getgenv().__expose`. El harness sigue inyectando su propia
  exposición solo en la copia que prueba.

## Límites importantes

- **Colas de v167 o anteriores ya enviadas:** su código no conoce el token de
  v168. No hay una API genérica fiable para retirar únicamente esos fragmentos
  de la cola del executor. La prueba `legacy` muestra que aún pueden ejecutar
  una vez con un `getgenv` nuevo. Puede ser necesario limpiar la cola del
  executor o reiniciar Roblox y el executor antes de probar la nueva versión;
  la persistencia exacta de la cola depende del executor.
- **Sin archivos persistentes compartidos entre origen y destino**, o si la
  lectura/escritura/borrado del token falla, no se puede garantizar la
  revocación de una cola ya enviada con un entorno nuevo. Se difiere el envío hasta que
  empiece el teleport y se emite un aviso en consola, pero el caso Destruct
  después del envío es de mejor esfuerzo. Si el token se escribió en origen
  pero no se puede leer en destino, el loader protegido no se ejecuta.
- Un **autoexecute externo** o un loader de otra aplicación puede volver a
  ejecutar el menú por su cuenta; Destruct no controla esas fuentes. Los
  tokens son archivos locales, no permisos del servidor ni una medida de
  seguridad. Las APIs de archivo no ofrecen aquí una operación atómica de
  compare-and-swap; no se garantiza la resolución de escrituras concurrentes
  que cedan durante la operación.
- No se ha probado en Roblox real, Delta ni otros ejecutores. No hay medición
  de FPS, comportamiento del servidor, física ni anticheat. La auditoría manual
  del resto de módulos sigue sin estar completa.

## Validación

`bash tools/validate.sh`: bundle de 89 archivos, **91 fuentes** Luau y
**108 suites** Python/Luau PASS; boot `failures=0`; 90 llamadas de API revisadas;
menú 50 tarjetas con debug y 49 en release.

`tools/test_teleport_persistence.py` ejecuta el boot y el texto realmente
encolado con archivos compartidos y entornos simulados distintos. Cubre Keep
ON/OFF y su guardado, mismo universo/PlaceId diferente, otro universo,
GameId disponible tras `Loaded`, estados repetidos/fallo, Destruct antes y
después del envío, durante la espera y descarga, retiro normal de interfaz,
reinserción manual, callbacks de perfil/calibración antiguos, alias de cola,
fallo de escritura y borrado, pérdida de almacenamiento y los límites de una
cola heredada o sin archivos. Son mocks, no una prueba de Delta.
