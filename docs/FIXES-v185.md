# v185 — Collision Shield, Safe Zone y Gun PC

Fecha: 2026-11-05. Stamp del loader y bundle:
`v185-20261105-collision-safety-pc`.

## Cambios

- Se retiran las tarjetas universales **Fling**, **Swim Walk** y **Anti Void**.
  **Walk Fling** permanece. El motor SkidFling sigue siendo interno de MM2 y
  conserva sus exportaciones para Auto Farm y Auto Win, sin tarjeta universal.
  Al destruir el motor se cancela una ejecución en curso y se retira su pin.
  La Anti Void **propia de BedFight** no era universal y permanece intacta.
- **Infinite Jump** mantiene el comportamiento por pulsación en **Normal** y
  añade **Rise**: mientras se mantiene Space o el botón de salto se aplica la
  velocidad vertical elegida. Soltar, perder foco, escribir o desactivar detiene
  el mantenimiento; no se cambia la velocidad horizontal ni se fuerza un asiento.
- **Interact Extender** se llama **Proximity Prompts**. Conserva las opciones,
  incluidos Click detectors e Instant prompts, y la clave de configuración
  histórica `Universal.InteractExtender`.
- **Anti Fling** usa la protección local **Collision Shield**, con Player Shield
  e Impact Shield. Crea pares `NoCollisionConstraint` entre el propio cuerpo y
  personajes cercanos o piezas no ancladas que se mueven/giran a velocidad
  extrema. Excluye el suelo que sostiene al personaje, vehículos mientras está
  sentado y herramientas ordinarias; un mango extremadamente rápido se trata
  temporalmente como peligro. El escaneo se limita a 0,15 s, 200 piezas y 2048
  pares, priorizando peligros y jugadores cercanos. La atenuación de velocidad
  propia solo se activa ante un peligro observado. OFF, respawn y Destruct
  eliminan los pares; los flings voluntarios suspenden temporalmente el escudo.
- **Auto Farm / Safe Zone:** apagar Auto Farm o su opción Safe Zone devuelve al
  mismo personaje al punto seguro del mismo mapa y elimina la plataforma, sin
  iniciar reset, fling ni recogida. Si el mapa original ya no está disponible,
  se conserva el suelo en vez de enviar al personaje a un destino obsoleto. Se
  reintenta la salida cuando vuelve el mismo mapa; si Auto Farm se reactivó, su
  worker arranca tras la salida. Una teleportación o respawn del servidor no se
  revierten a una ronda vieja.
- **Gun Aimbot PC:** el hook se instala antes del observador opcional y no espera
  a que WeaponService aparezca. En una llamada nativa ya iniciada, la redirección
  no se bloquea porque el script del juego haya deshabilitado la Tool o porque
  quede un feedback pendiente; esas puertas siguen vigentes para disparos
  propios. Si todavía falta el historial del predictor, el clic nativo puede
  usar la posición/velocidad observadas, pero debe pasar las mismas validaciones
  finales y WallCheck. Cuando falta el muzzle se puede usar el origen de la
  llamada nativa. Se envía un único paquete y no se gira la cámara. Errores del
  feedback o Calibration no invalidan los CFrames ya construidos; la captura
  del clic nativo se difiere. Si la validación falla, se deja pasar el clic
  original y se muestra el motivo. Móvil mantiene sus modos y controles.
- **Calibration:** con consentimiento, el evento Tool.Activated y la redirección
  del mismo clic se guardan como observaciones separadas, pero cuentan como un
  solo intento y se asocian al origen redirigido para el eco. No se encontró
  evidencia de que Calibration causara el fallo reportado; el aislamiento evita
  que un error opcional futuro bloquee una redirección válida. No se han borrado
  archivos de telemetría ni se ha cambiado el consentimiento.

## Verificación y límites

- Las pruebas ejecutan código real con mocks: pares y limpieza de Collision
  Shield, límite de pares y prioridad, herramientas y suelos, flings voluntarios;
  los dos modos de salto; 33 escenarios de movimiento y retorno de Auto Farm;
  SkidFling MM2, cancelación y destrucción; redirección PC, un solo envío,
  WallCheck, fallback, errores de observadores y contabilidad de Calibration.
- El arranque simulado cubre PC, móvil y fallback por fuentes en Universal, MM2,
  BedFight, TRS, VD y X2. `bash tools/validate.sh`: **81** fuentes compiladas,
  **126** suites, bundle de **79** fuentes, boot `failures=0` y **46** tarjetas
  en MM2 tanto en debug como en release.
- Las restricciones y la detección de peligros son **locales y acotadas**: no
  garantizan bloquear física de servidor, objetos que no hayan replicado o
  impactos entre escaneos. Plataformas móviles inusuales y juegos que dependen de
  contacto físico requieren pruebas en partida.
- No se probó Roblox/Delta desde este entorno. El script nativo concreto de Gun
  y el contrato que usa al disparar no están confirmados aquí; el hook requiere
  `hookmetamethod`, `getnamecallmethod` y `checkcaller` y solo modifica una llamada
  `Gun.Shoot:FireServer` con dos CFrames. Un clic redirigido o un eco **no**
  demuestran daño aceptado por el servidor. Física, rendimiento y replicación
  también requieren verificación real.
