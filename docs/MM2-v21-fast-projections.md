# MM2 v21 — selector local rápido, red inestable y menú ligero

> La rama entrega ahora [v21.1: aspecto Wurst clásico](Wurst-v21.1-classic.md). Se conservan las mejoras MM2 de esta guía; la paleta violeta y Midnight aquí descritas son históricas.

Build: **`v21-20261014-mm2-fast-projections`**. Rama: `arena/d83a806d-arandommenu`.

Implementa el plan aprobado: comparar predicciones **antes de enviar**, distinguir el ping observado de su estimación y ordenar el menú sin añadir efectos continuos costosos. Se prioriza responder con los frames disponibles, no esperar artificialmente 5–10 ms entre candidatos.

**No hay todavía una medición de aciertos, FPS o apariencia en Roblox para v21.** Las pruebas descritas abajo ejecutan código real con servicios simulados. Los datos históricos de TestingStuff no son un benchmark de esta versión.

## 1. Para empezar

Haz **Destruct** en la instancia anterior y carga la misma rama:

```lua
getgenv().WURST_BRANCH = "arena/d83a806d-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/d83a806d-arandommenu/src/Wurst.lua?v=" .. tostring(os.time()), true))()
```

Verifica el sello **`v21-20261014-mm2-fast-projections`**.

1. **Shoot → Mode: Prediction → Prediction profile: Experimental.** El perfil inicial continúa siendo Actual si no había una selección guardada: la actualización no cambia silenciosamente tu perfil.
2. **Network policy: Best effort**, para no añadir retención por inestabilidad de red. Gun y Knife tienen políticas independientes.
3. **Advanced** empieza OFF en configuraciones nuevas; actívalo cuando quieras ajustar el timing, el margen manual o consultar diagnósticos. Si ya lo guardaste ON, se restaura. Ocultar controles no cambia sus valores.
4. Para comparar, alterna **Actual / Experimental** manteniendo el mismo timing y Lead bias. Hitbox/Burst solo existen en **Old**, no en Experimental ni Silent AIM.
5. Para la paleta nueva con una configuración antigua: **Settings → UI → Rainbow OFF → Midnight preset**. Las preferencias de color existentes se conservan hasta que lo pidas. El preset cambia la paleta, no tus tamaños/opacidad guardados.

Auto Shoot conserva **Max error** y **Fire delay**. Best effort no los anula. Knife conserva cadencia Auto/Manual, detección de Sleight y sus modelos Linear/Vertical; esta entrega no sustituye esas decisiones por las del Gun.

## 2. Experimental: tres candidatos, un envío

En una misma evaluación, sin `task.wait` entre candidatos:

- Proyección con velocidad medida.
- Proyección con mezcla de velocidad e intención de movimiento disponible.
- Proyección con aceleración horizontal acotada a 80 studs/s².

Cada modelo se calcula para el horizonte central y dos tiempos vecinos: **nueve hipótesis**. La separación temporal depende de variabilidad del ping, diferencia entre lectura/estimación y tiempo observado de frame; queda acotada entre 5 y 150 ms. **Es una separación matemática, no una espera.**

Se comparan los tres segmentos origen→endpoint con esas nueve posiciones: 27 comparaciones. La puntuación combina 70 % de la peor distancia y 30 % de la media. Se ordenan con desempate determinista y se toma el primer candidato que supera los filtros pertinentes. Endpoints prácticamente idénticos se deduplican.

### Presupuesto de trabajo

- Hasta tres consultas de suelo cuando se necesita Landing guard.
- Hasta tres comprobaciones de visibilidad, con **12 raycasts de mundo como presupuesto total compartido**, incluyendo capas transparentes; no 32 por candidato.
- Hasta tres raycasts adicionales para otros jugadores.
- Por tanto, hasta **18 raycasts en esta etapa del selector**, no un coste dependiente de esperar nuevas réplicas.
- No crea Parts ni dibuja líneas por frame. Las alternativas solo son vectores/tablas locales.
- Si hay una opción válida: **una petición de disparo**. Si ninguna pasa: ninguna petición. No reenvía los candidatos restantes.

El presupuesto compartido puede rechazar escenas con muchas capas transparentes: informa `Scene check budget reached; no clear projection`. No interpreta agotar el presupuesto como demostrar que exista una pared. La opción Wall Check sigue controlando la consulta de mundo; el filtro de otros jugadores permanece activo en Experimental.

**La concordancia entre hipótesis no es una probabilidad de impacto.** Todas pueden equivocarse juntas ante un giro, salto, réplica atrasada o regla del servidor que el cliente no conoce. El error de este perfil tampoco debe interpretarse como estadísticamente equivalente al error de Actual: utilizar el mismo Max error puede producir distinta cobertura de oportunidades.

## 3. Red: observado, estimado y desconocido

Antes se podía ocultar un pico real detrás del límite de 300 ms del estimador. Ahora se mantienen por separado:

| Campo | Significado |
|---|---|
| Raw RTT | Última lectura válida de `Stats / Data Ping`, no una medición del instante de colisión. |
| Estimate | Estimación rápida utilizada como base temporal. Un cambio grande sube o baja en la primera lectura que lo observa; cambios pequeños se suavizan con tiempo real. |
| Baseline | Referencia lenta, no una media histórica de todas las partidas. |
| Jitter | Variabilidad suavizada de cambios entre lecturas; no es desviación estándar ni intervalo de confianza. |
| Age / stale | Edad del último dato válido y señal de lectura ausente/inválida. No se convierte un fallo en ping cero. |
| Spike / capped | Cambio brusco observado o estimación que excede el límite protector. |

El monitor compartido consulta nominalmente a **10 Hz**. Un disparo manual listo o la predicción de Knife pueden pedir una lectura adicional, reutilizando la caché si tiene menos de 1/120 s. No hay espera para obtenerla ni se afirma que Stats produzca una medición independiente en cada consulta.

Se corrigió además una interacción entre temporizador y caché que, por redondeo, podía saltarse lecturas programadas. Las pruebas verifican la detección en secuencias variables de frames, no solo a 60 FPS.

### Estados y políticas

- **Stable:** lectura válida sin pico detectado.
- **High:** RTT observado por encima de 300 ms; un ping alto sostenido no es necesariamente un pico.
- **Spike:** cambio brusco observado; se conserva la marca al menos 0,6 s desde su última detección.
- **Unknown:** no hay lectura válida, falló la última consulta o el dato supera un segundo de edad. El HUD muestra RTT `stale`, no lo presenta como una medición nueva.
- **capped:** el estimador alcanzó su límite superior; visible en el estado.

**Best effort**, valor inicial, no retiene por esos estados. **Hold spikes** retiene ante Spike, Unknown o estimación superior al límite. No retiene simplemente porque el cliente esté a 30 FPS o porque el ping alto sea estable y esté dentro del límite. La retención opcional puede durar después de recuperarse el ping; no es apropiada si prefieres disparar aun con datos inciertos.

No se añadió un hook global de red. Se usan el sensor local y las peticiones/señales de arma que ya observa Calibration. No se elimina el viaje del paquete ni se obtiene el estado privado del servidor.

### Límites protectores explícitos

| Componente | Límite |
|---|---|
| Estimación RTT utilizada | 0,03–1,20 s; la lectura observada se conserva aparte. |
| Horizonte central Gun | 0,02–0,85 s. |
| Horizonte Old/Burst | Conserva 0,03–0,60 s. |
| Separación temporal de hipótesis Experimental | 0,005–0,15 s; extremos entre 0,02 y 1 s. |
| Adelanto de red Knife | 0–1,20 s tras multiplicador/bias. |
| Búsqueda de vuelo Knife vertical | Hasta 5 s de vuelo, hasta 6,20 s contando red. |

Estos límites **no compensan por completo una conexión arbitrariamente lenta**. El límite del horizonte Gun es distinto del indicador `network.capped`; un horizonte puede estar al límite antes de llegar a 1,20 s de RTT. Las peticiones Gun registran `horizonLimit` y `horizonAtLimit`.

El controlador Gun conserva sus márgenes temporales heurísticos heredados (edad de réplica/frame de servidor). No son mediciones de tick del servidor ni una afirmación de que tu cliente funcione a 60 FPS.

## 4. FPS variables y velocidad

- Los temporizadores y filtros utilizan tiempo transcurrido real. No se multiplica el ping por los 90 Hz de la pantalla.
- Auto Shoot puede evaluar hasta 120 veces por segundo, pero **como máximo una vez por callback disponible**. A 30 FPS no inventa 90 evaluaciones faltantes.
- Después de una pausa larga no hay un bucle para recuperar disparos atrasados.
- Motion Hz y Throw Hz son límites de muestreo/evaluación, no FPS garantizados, réplicas nuevas ni disparos por segundo. La cadencia del arma sigue aplicándose.
- El HUD estima FPS a partir de `RenderStepped`; el tiempo de `Heartbeat` para el control se registra por separado. Ninguno mide la frecuencia física del monitor.
- No se añadió una espera antes de enviar por usar Experimental. **La espera de equipamiento preexistente del Gun permanece**, y ahora también cancela un tiro no-Burst si los controles cambian durante esa espera.

Un frame de 33 ms o una pérdida de conexión siguen imponiendo un retraso real. El cambio reduce trabajo superfluo y evita esperas nuevas; no permite prometer disparos instantáneos ni FPS constantes.

## 5. Interfaz

- Paleta oscura con violeta como acento inicial; colores configurables y preset explícito para perfiles antiguos.
- Mode, Target, Prediction profile y Network policy utilizan botones segmentados. Los menús con listas largas mantienen su selector habitual.
- Se conserva **Mode: Prediction / Silent AIM**, seguido de **Target: Murder / Custom**.
- Advanced agrupa ajustes y diagnósticos sin mezclar los perfiles. Experimental no ofrece el interruptor del aprendiz escalar que no utiliza.
- Panel de estado con arma, ping observado/estimado, jitter, FPS y una gráfica de **40 muestras válidas**.
- La gráfica se actualiza como máximo a 4 Hz mientras sus ancestros están visibles; no crea Instances durante las actualizaciones y desconecta al eliminar la fila. Los dos monitores numéricos compartidos siguen activos mientras vive MM2 y se limpian al destruirlo.
- Las barras no representan necesariamente cuatro segundos: las lecturas bajo demanda cambian el espaciado y los fallos no se dibujan como muestras cero. La escala vertical se adapta al máximo visible, con referencia mínima de 300 ms.
- No se añadieron blur, partículas ni efectos gráficos continuos. El Rainbow anterior sigue siendo opcional; dejarlo OFF evita ese trabajo adicional.

Las pruebas verifican jerarquía, selección, persistencia y ciclo de vida con mocks. Falta inspección visual dentro de Roblox, especialmente textos en ventanas estrechas y escalado de pantalla.

## 6. Calibration y aprendizaje

Experimental registra el candidato escogido, los tres endpoints/puntuaciones, horizonte, incertidumbre, contadores de consultas, movimiento de entrada y estado de red. Los snapshots de tiros no copian las 40 muestras de la gráfica.

**No alimenta el ajuste escalar de auto-lead**: seleccionar entre modelos no tiene la derivada de una corrección temporal simple. Tampoco inicia su tarea de seguimiento. Los snapshots con red inestable/desconocida/recortada, horizontes Gun al límite o grupos Burst múltiples no entrenan esa corrección. Un cambio de época/perfil detiene el seguimiento anterior.

La adaptación opt-in de timing por señales Gun excluye inestabilidad tanto **al enviar** como **al observar la señal**. Sigue siendo una medida petición→señal, no el instante autoritativo del impacto.

Se conservan las distinciones anteriores: desconocido no significa fallo, contacto local con `WurstHitbox` no significa impacto real, señal de arma no significa daño/muerte, y un grupo Burst ambiguo no confirma cada petición.

### Comparación útil en juego

En una partida privada/autorizada, alterna Actual/Experimental con escenas y distancias comparables. Separa caminar, giro, salto y aterrizaje; anota periodos de 30–40 y 70–80 FPS y picos de red. Mantén timing/bias/cadencia constantes y no mezcles Hitbox/Burst con la prueba del selector.

Usa captura detallada solo durante bloques cortos si necesitas trayectorias y guarda al terminar, fuera del momento competitivo. Revisa envíos **y rechazos/oportunidades**, señales identificables y resultados realmente observados. Un algoritmo que deja pasar solo los casos fáciles puede parecer más preciso sin ayudar en más situaciones. La grabación y guardado de JSON tienen un coste que la paleta nueva no elimina.

## 7. Validación reproducible

- **64 grupos MM2:** precision 14 + v16 4 + v17 12 + v18 7 + v19 7 + v20 9 + **v21 11**.
- **8 tests** del analizador JSON y **14 comprobaciones** del proveedor de equipos.
- **70 archivos Lua** compilados con Luau oficial 0.732.
- Bundle regenerado y comprobado: **68 entradas**, sello v21 igual al loader.

La suite nueva ejecuta funciones reales para red, FPS variables/pausas, límites de raycasts, candidatos, envío único, aprendizaje, Knife, Advanced, preset y widgets:

```bash
LUAU=/ruta/luau python3 tools/test_mm2_v21.py
python3 tools/build_bundle.py --check --stamp v21-20261014-mm2-fast-projections
```

**Pendiente de validar en Roblox:** coste real por frame, geometría/otros jugadores en mapas reales, aceptación del servidor, animación, presentación visual y tasa de aciertos. No se promete 99,99 % ni una ventaja cuantificada a partir de estas pruebas.
