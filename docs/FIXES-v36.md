# v36 — Combat, opciones integradas y Knife WallCheck

Stamp: `v36-20261016-combat-controls`.

## Menú

- Auto Shoot, Shoot y Knife → Combat.
- Teleport de MM2 → Utilities; Click Teleport universal sigue siendo distinto.
- Sprint deja de tener tarjeta propia: checkbox dentro de Speed en MM2.
  Speed ON + Sprint ON usa WalkSpeed 30 y la estela; Speed es el único dueño
  de capturar/restaurar WalkSpeed. OFF, respawn y unload limpian la estela.
  Sin Sprint, Speed conserva sus métodos y opciones. El boost de vehículo no
  se sustituye por la velocidad peatonal de Sprint.
- Blurt Roles → World. Instant Roles es una opción privada una vez por ronda,
  independiente del delay/chat público. Se eliminó Instant Role Notify como
  tarjeta y archivo cargado por el bootstrap.
- RShift, bindings sin asignar por defecto, Freeze/FPS y Calibration de MM2
  conservan lo aceptado en v35.

## Disparos y Knife

- Shoot manual ya pasa la misma instrucción de disponibilidad que Auto Normal:
  no esperar una confianza/error de movimiento ideal. Sigue comprobando arma,
  disponibilidad, cooldown y WallCheck. Conserva autoequip al accionar Shoot;
  Auto permanece held-only. Auto Normal y los solvers no se reescribieron.
- Knife Normal añade WallCheck explícito, selección de objetivos parcialmente
  visibles, probes de torso/cabeza/extremidades y revalidación al release.
  Todas las posiciones alternativas conservan el lead del proyectil; no se
  copia el fallback raw/hitscan. El cuerpo presente del objetivo se excluye
  del raycast de vuelo para no ocultar una pared tras él. El filtro compartido
  de transparencia/WeaponPassthrough se conserva; Gun no cambia ese criterio.
- Silent mantiene intencionalmente su comportamiento de atravesar paredes.
- No se atribuye a estos cambios una accuracy medida en el servidor ni una
  animación nativa exacta. Ver `PREDICTION-NEXT-RUN.md` y el baseline v35.

## Spider

Los cuatro mecanismos ya eran diferentes y se conservaron:
Spiderman adhiere/alinea con paredes/techos, Velocity sostiene velocidad Y,
CFrame avanza por deltaTime e Impulse aplica impulsos.

Se corrigió Impulse: ya no suma +30 de velocidad por frame indefinidamente.
Ahora pulsa a intervalos configurables y solo aplica el delta hasta la velocidad
vertical elegida. Las opciones exclusivas se muestran por modo, cambiar modo
reinicia/limpia el anterior y destroy pasa por la restauración de postura.
También se evita normalizar un vector cero al orientar sobre techos.

## Verificación

- 15 suites Python/Luau, incluidas integración real Speed+Sprint, Instant Roles,
  cuatro ramas de Spider, Knife WallCheck y regresiones anteriores.
- Compilación de todas las fuentes Lua/Luau bajo src.
- Bundle regenerado/verificado: 68 fuentes, sin InstantRoleNotify.
- Boot completo con cero fallos y asserts de categorías, opciones anidadas,
  módulos eliminados, RShift, Freeze, Weapon Visuals y Calibration.
- Comparación de texto: `computeGunAim` y `predictAim` idénticos al baseline A.
- `git diff --check`.

Estas son pruebas estáticas y de ejecución con mocks; no sustituyen una prueba
visual/online en Roblox ni una validación física en un dispositivo móvil real.
