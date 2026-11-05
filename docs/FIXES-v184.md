# v184 — Auto Farm, Team Check, Kill Aura y avisos MM2

Fecha: 2026-11-04. Fuentes en `src/`; versión del bundle y loader:
`v184-20261104-farm-teams-notifications`.

## Cambios

- **Auto Farm:** vuelve a intentar el tick tras errores transitorios en vez de
  dejar que el planificador lo desconecte; cambia de objetivo si la ruta no
  progresa; evita monedas recogidas, de otro mapa o de una caché caducada. Una
  caché local limitada a 0,5 s usa las monedas etiquetadas o el mapa activo, y
  se invalida al aparecer una moneda. Señales positivas de inicio permiten
  reanudar un mapa reutilizado sin mover al personaje en el lobby. Conserva
  las acciones y los límites de bolsa llena, las dos modalidades de movimiento
  y el Silent WallCheck OFF de Farm. En el volcado MM2 disponible, 93 pares
  `Coin_Server/CoinVisual` están bajo `Workspace/House2/CoinContainer`; otros
  mapas o futuras versiones del juego aún requieren prueba real.
- **Walk Fling:** quitada la opción Power solo de esta tarjeta. El pulso usa
  un factor y componente vertical fijos de 30000, el máximo anterior. No se
  inicia automáticamente al inyectar; al apagar se restauran colisiones y al
  destruirlo ya apagado no se alteran las velocidades existentes. La tarjeta
  **Fling** independiente conserva sus opciones propias.
- **Team Check:** respeta proveedores con `GetRelation`, `IsFriendly` o `Get`,
  equipos/facciones por atributos o valor `Team`, neutralidad y roles MM2.
  FFA conocido trata a los demás como adversarios; información incompleta de
  proveedores o roles no se convierte en una confirmación hostil. Entity y el
  chequeo avanzado comparten el veredicto y no reinterpretan equipos de lobby
  como aliados cuando el proveedor del juego da otra relación.
- **Kill Aura universal:** el límite de objetivos se aplica después de filtrar
  ignorados/aliados; el pulso de contacto usa inicio y fin en orden. Una Tool
  deshabilitada o no equipada no se presenta como activada, y se mantiene el
  autoequipamiento cuando el usuario lo solicita. **Knife Stab MM2** reintenta
  activaciones fallidas y cancela contactos diferidos tras OFF/OFF-ON; también
  vuelve a comprobar herramienta, rol, distancia y protección antes del contacto.
- **Notifications (MM2 → Utilities):** tarjeta para avisos privados. Instant
  Roles salió de Blurt Roles, que sigue siendo exclusivamente chat público;
  una configuración antigua activa migra a la opción nueva y activa la
  tarjeta si no existía una preferencia explícita. Incluye Gun Notification
  (caída y nuevo portador observado), Murder Close (30 studs, salida a 38 y
  cooldown de 8 s), rol propio, entrada/fin de ronda y muerte confirmada del
  Murderer. La ausencia de la gun o un portador anterior todavía replicado no
  se anuncia por sí sola como recogida. La resolución de roles reentrante se
  coalesce para evitar duplicados o recursión.
- **Calibration:** sigue sin tarjeta visible y solo observa/escribe tras Yes;
  No detiene la captura y conserva los archivos. Generaciones invalidan cargas
  asíncronas antiguas; snapshots simultáneos se serializan y coalescen, se
  verifican sus bytes y se bloquea la sobrescritura ante cambios externos.
  Se conserva el backup importado y, ante truncamiento o escritura parcial, se
  intenta guardar y verificar una copia separada `*.recovery-<sesión>-N.json`
  sin reemplazar archivos existentes. No se inicia una recuperación después de
  revocar el consentimiento. Reset interno y archivo de lotes también respetan
  las carreras de escritura. La última salud observada se guarda aparte de una
  caída: una curación no se clasifica como daño y una caída tras curarse no se
  pierde. Las observaciones de salud no demuestran causalidad ni impacto.

## Verificación y límites

- `bash tools/validate.sh`: **83** fuentes Lua compiladas, **127** suites
  Python/Luau, bundle de **81** fuentes, boot con `failures=0` y **49** tarjetas
  tanto en debug como en release. El boot simulado incluye PC, móvil y carga
  individual de fuentes para MM2, Universal y los demás juegos registrados.
- Las pruebas Luau/Python ejecutan el código con mocks: 28 escenarios de
  movimiento/transiciones de Farm, Walk Fling ON/OFF, relación de equipos,
  selección/activación universal y Knife Stab. X2Duels conserva sus pruebas.
- Notifications se prueba tanto aislada (migración, reentrada, Gun, proximidad
  y eventos) como arrancando el bundle y los controles reales con perfiles
  antiguos y nuevos simulados.
- Calibration prueba consentimiento, archivos existentes y backups, conflicto
  externo, lectura/escritura parcial, recuperación, callbacks antiguos, No/Yes
  mientras una escritura cede, reset y archivo simultáneos, y curación/daño.
- Las comprobaciones de bytes no convierten el filesystem del executor en
  atómico: una caída, un fallo general de escritura o un escritor externo
  simultáneo pueden impedir la recuperación. El aviso y la ruta de copia se
  registran en la consola; si falla el almacenamiento no se promete que todos
  los datos sobrevivan a cerrar el cliente.
- **Pendiente en Roblox/Delta:** confirmar que Farm continúa en rondas y mapas
  reales, que los avisos reflejan la replicación de armas/roles y que Kill Aura,
  Knife Stab y Walk Fling tienen el efecto deseado. Los tests no prueban
  network ownership, daño aceptado, física del servidor ni rendimiento/FPS.
  Calibration solo puede registrar lo que el cliente y executor observan.
