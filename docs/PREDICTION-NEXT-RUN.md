# Nueva predicción: plan de la siguiente run

## Qué queda guardado

La referencia A es `42379f5` (v35). `prediction-baselines/v35/` contiene los
archivos completos de Shoot y KnifeThrow de esa versión, sus hashes y el commit
para recuperar también `src/games/MM2/base.lua` (filtro, latencia y calibración).
No se cargan esos `.txt` como módulos. En v36 se comprobó por comparación de
texto que `computeGunAim` y `predictAim` conservan exactamente su matemática.
Los cambios de v36 son de activación, WallCheck y organización, no un modelo B
presentado sin haberlo contrastado.

## Qué aportan los tres logs nuevos

Origen: XzAngel19/TestingStuff.

| Archivo | Blob | Hallazgo |
|---|---|---|
| 2026-10-16T22_14_51Z.log | 56ccae0d2ca6d9a44d6e02fc40e31b78a5f6ae6a | 1 Shoot del módulo; 12 registros GunFired de listeners = 3 ecos distintos, solo 1 de nuestra pistola |
| 2026-10-16T22_18_17Z.log | a7e658f2699e66ee276bbda23e33bb9e7928cee3 | 1 Shoot del módulo; 4 listeners del mismo eco propio |
| 2026-10-16T22_19_27Z.log | f37b77506dea04401e4bd353046cfb1e06c06ad5 | 5 KnifeThrown del KnifeClient nativo, no del predictor |

Reproducción: `tools/analyze_mm2_remote_logs.py <logs...>`.
Resultado numérico guardado en `prediction-baselines/v35/new-log-audit.json`.

Los dos ecos propios quedan sobre la dirección enviada, a aproximadamente
0.000203 y 0.000303 studs de la línea. Sus endpoints están, respectivamente,
3.146678 studs antes y 2.158225 después del aim enviado. Eso es compatible con
un raycast que termina en la primera superficie: NO debe interpretarse como
un error de adelanto de esas distancias. El primer eco toca un accesorio de
avatar; el segundo, RightFoot. No equivalen por sí solos a dos kills ni a una
medición general del porcentaje de aciertos del objetivo elegido.

Los intervalos outgoing→echo medidos por CreationTime son 119.671 y 132.397 ms;
por las cabeceras son 127.135 y 152.589 ms. El logger añade tiempos de entrega
por listener. Ninguno de esos intervalos revela directamente cuánto rewind
aplicó el servidor. No ajustar RTT/2 frente a RTT a partir de ese número solo.

Los cinco lanzamientos nativos conservan el origen orientado y dos CFrames.
Sus intervalos son 1.487754, 1.513330, 1.497152 y 3.236049 s. Esa cadencia del
usuario NO demuestra un cooldown obligatorio de 1.5 s. Ninguno de estos logs
contiene AnimationId, AnimationPlayed, LoadAnimation ni Motor6D; son trazas de
remotes, no capturas de los keyframes locales.

## Animación compatible con móvil y PC

No hay una incompatibilidad general de CFrame con móviles. Cambiar el CFrame
del personaje puede pelear con el controlador, la física o la implementación
del executor. La reconstrucción actual mueve Motor6D.C0/Transform del brazo,
no teletransporta el personaje ni depende de teclado/ratón.

Copiar la animación nativa no es imposible. La captura útil para la siguiente
run es:

1. Desactivar Auto Throw y la reconstrucción durante una prueba nativa.
2. Armar una captura local con un pequeño historial circular ANTES del throw.
3. Pulsar el botón nativo en móvil/PC: observar AnimationPlayed (asset ID,
   prioridad, tiempo, velocidad) y C0/Transform de hombro/codo/muñeca durante
   preparación, release y recuperación. No llamar un segundo remote.
4. Si existe un track utilizable, reutilizar ese asset observado. Si la pose
   es procedural, reconstruir la curva observada con los joints del rig.
5. Confirmar en R6/R15 y en móvil/PC; un test de matrices no es una captura
   visual del juego ni prueba de replicación hacia otros clientes.

No se añadió un asset supuesto en v36 ni se declaró que la reconstrucción
actual sea idéntica a la nativa.

## Diseño de B, sin duplicar disparos

- A permanece reversible. B se implementará como funciones separadas.
- Primero modo sombra: A y B calculan sobre la MISMA muestra, pero solo uno
  envía el paquete. Nunca disparar dos veces para "comparar" una predicción.
- Instrumentación únicamente dentro de Calibration de MM2; no reintroducir
  Learning/Metrics universales.
- Correlacionar shotId, modelo, objetivo, origen, aim, muestras con timestamp,
  frame time, ping/jitter, postura y eco propio deduplicado. Distinguir intento,
  aceptación, colisión con objetivo, kill y resultado desconocido.

### Gun

Es hitscan, no necesita tiempo de vuelo ni gravedad de la bala. Separar edad de
la observación, tiempo de envío/aceptación y posible rewind. Contrastar un
modelo constante mínimo con modelos de aceleración/giros, usando el historial
de posiciones y no solo AssemblyLinearVelocity. Validar en particular:

- sesgo de filtro frente a cambios de dirección y frenadas;
- la hipótesis de un RTT completo para el horizonte;
- las constantes actuales de aceleración, salto mínimo y límites verticales;
- el fallback a posición observada cerca de esquinas, que presupone rewind.

La incertidumbre se registra, NO bloquea la acción manual o automática para
esperar un supuesto momento perfecto. Cooldown, arma válida y WallCheck siguen
siendo condiciones de disponibilidad, no un temporizador de oportunidad.

### Knife

El código recuperado de ThrowingKnifeVisuals usa velocidad lineal, 96 studs/s
por defecto. No confundir gravedad del OBJETIVO que salta con caída del blade.
Separar preparación local, liberación real, transporte y vuelo. Calcular desde
el origen al release, no desde una pose guardada antes de levantar el brazo.

Contrastar CV/intercepción con aceleración horizontal acotada y fases de salto
solo cuando las muestras lo sustenten. Reiniciar el estimador en respawn,
teleport o discontinuidades. Modelar aterrizaje para no extrapolar a través del
suelo. Validar colisión y geometría del blade antes de decidir si un raycast o
un volumen barrido reproduce mejor al servidor.

WallCheck no es el predictor: v36 ya rescata partes visibles usando el mismo
filtro de Shoot, pero mantiene el adelanto del proyectil. Excluye el cuerpo
presente del objetivo para comprobar la pared hasta la posición futura. Copiar el fallback
sin adelanto de un hitscan a un blade con vuelo sería una falsa mejora.

## Cómo decidir si B realmente mejora

1. Casos controlados: quieto, lateral, acercamiento, huida, freno, inversión,
   salto/apex/caída/aterrizaje y cobertura parcial. Distancias y latencias por
   separado; tanto móvil/PC como R6/R15.
2. Separar sesiones de ajuste y validación; no evaluar sobre las mismas
   trayectorias usadas para elegir constantes. Repetir en otras condiciones.
3. Medir error geométrico y acierto confirmado por servidor; también rechazos,
   desconocidos y disponibilidad del disparo. No convertir ausencia de eco en
   hit, ni inflar el porcentaje dejando de disparar en casos difíciles.
4. Promover B solo si mejora frente a A en datos reservados sin empeorar
   disponibilidad o provocar tiros bloqueados/duplicados. Mantener rollback.

## Sobre 99.99%

Es una aspiración, no una garantía técnicamente justificable para todas las
partidas. Un cliente no conoce los próximos giros del rival ni controla jitter,
replicación, rewind o validación del servidor. Optimizar geometría, estimación
y disponibilidad sí es medible; asegurar decisiones futuras no lo es.

Incluso bajo el supuesto ideal de ensayos independientes y representativos,
respaldar una tasa mayor o igual a 99.99% con un límite unilateral del 95% y
cero fallos requeriría aproximadamente 30 mil intentos. Un par de ecos o un
promedio de partidas fáciles no sustenta esa cifra. El resultado útil será un
porcentaje validado por escenarios, con sus intervalos y límites, no un
"99.99" fijo en la interfaz.
