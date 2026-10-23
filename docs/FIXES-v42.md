# v42 — Teleport agrupado, Freeze tras respawn y predicción implementada

Stamp: `v42-20261016-teleport-respawn-prediction`.

## Teleport

`Destination` tiene **una sola entrada MM2**, primera y predeterminada.
Dentro aparecen juntos **Teleport to Map**, **Teleport to Lobby**,
**Player name / Teleport to Player** y **Get Gun**, con su tecla y recogida
automática. No hay MM2 Target ni destinos separados MM2 Map/Lobby/Player/Gun.
Los destinos universales siguen disponibles; ocultan los controles MM2.
Se migran los valores MM2 separados de v41 y se conservan teclas/delays propios.
El botón principal no elige implícitamente otro destino dentro de MM2.

## Freeze Emotes / Freeze Animation

- ON conserva las preferencias al morir y rearma el scheduler en CharacterAdded.
- CharacterRemoving/Dead sueltan tracks y propiedad de Anchor; la ausencia
  temporal de personaje/Animator no deja referencias al avatar anterior.
- Se vuelven a enlazar Humanoid, Animator y Animate nuevos, incluso si llegan
  después del evento de respawn. Los cambios de Animator también renuevan el
  track de locomoción.
- Metadata de emotes se revisa cada dos segundos y ante cambios relevantes.
  Los catálogos resueltos se cachean por personaje, sin descargar el mismo
  asset cada revisión. Los fallos transitorios tienen hasta tres intentos.
- Una cola pequeña conserva tracks recién iniciados/cancelados antes de que
  llegue la descripción UGC. No se adivina que todo Action sea un emote.
- OFF/unload desconecta listeners de personaje, invalida trabajos pendientes
  y destruye los tracks que posee; las dos casillas siguen independientes.

## Predicción — no pospuesta

En **Calibration → Prediction model** se puede alternar **Adaptive** (default)
y **Reference v41**. Es un rollback compartido de Gun/Knife, no otro modo o
configuración dentro de Knife Throw. El cambio reinicia la corrección aprendida.
Los tres archivos A completos y sus SHA-256 están en
`prediction-baselines/v41/`; el archivo v35 anterior permanece intacto.

### Gun

Modelo conservador: conserva A donde no hay evidencia para cambiarlo. Integra
frenadas coherentes hasta detenerse (sin adelanto hacia atrás), sigue curvas
con signo respaldadas por varias observaciones y elimina el arrastre de
aceleración cuando el objetivo ya está quieto. Ignora cambios menores que la
incertidumbre corporal existente. El historial está acotado y no confunde cada
frame interpolado con una observación nueva de velocidad; se reinicia en
respawn/teleports y no usa muestras antiguas para activar esas correcciones.

Corrige desacuerdos entre estado de salto y velocidad, sin inventar un impulso
vertical mínimo. Un piso collidable bajo el punto proyectado puede limitar la
caída. La incertidumbre se registra, **no bloquea Adaptive** esperando un
movimiento perfecto. Se mantienen disponibilidad del arma, held-only en Auto,
autoequip manual y WallCheck de la geometría actual.

### Knife

Mantiene el blade lineal de 96 studs/s recuperado en ThrowingKnifeVisuals
(o el ThrowSpeed válido del arma). Ahora puede interceptar un **objetivo**
aéreo con gravedad y aterrizaje; no añade gravedad al cuchillo. El solver usa
bracketing/bisección acotados y mantiene A si no encuentra una raíz fiable.
La selección, posición y WallCheck se vuelven a resolver al release.

No se cambia la animación móvil/PC ni se añade configuración al throw. No se
presenta como recuperación exacta de KnifeClient, ausente de la fuente nativa
recuperada, ni de keyframes que los logs de remotes no contienen.

### Comparación sin doble disparo

Adaptive calcula también el endpoint A sobre la misma muestra y lo guarda en
los settings de Calibration como `referencePoint`, junto al modelo elegido.
Gun compara el punto cinemático antes del fallback de visibilidad, no simula
un segundo disparo completo; Knife compara el punto raíz antes del offset de
la parte visible. Solo el endpoint elegido se envía. No se duplica el remote.

Los ecos de Gun ahora deben coincidir en geometría incluso si coincide el Tool.
Si se sobreescribió un intento pendiente, el resultado es ambiguo y se excluye
del ajuste/estadísticas en vez de asignarlo a ciegas. Un eco no demuestra kill,
rewind ni porcentaje global de aciertos. La corrección automática sigue OFF
por defecto y no aprende de una predicción pendiente de otro modelo.

## Verificación y límites

Ver [evidencia reproducible](prediction-baselines/v42/README.md). Se probaron
los módulos reales bajo Luau, el arranque del bundle y casos de ausencia de
personaje, nuevo Humanoid/Animator, Animate tardío y UGC cancelado al caminar.
Eso no sustituye una prueba en el cliente Roblox del usuario.

El replay del **solver Gun** reduce error geométrico medio de pose de cliente
0.5062 → 0.4590 studs en desarrollo; en la sesión antigua reservada,
3.2560 → 3.2116. El conjunto pequeño queda igual. Las trayectorias incluyen
ventanas registradas alrededor de Gun y Knife: **no son el acierto de Knife**,
ni aciertos confirmados de servidor. Los registros antiguos son imperfectos;
la mejora online, ping/jitter, pisos reales y dispositivo requieren comprobación
real. No se afirma un porcentaje de precisión a partir de estos números.

Validación final: **24 suites**, **69 fuentes Lua compiladas**, bundle de
**67 módulos** sincronizado y full boot sin fallos. Sin prueba online Roblox.
