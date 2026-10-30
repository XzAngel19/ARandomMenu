# v160 — Auditoría de rendimiento: qué consume CPU y qué se corrigió

Fecha: 2026-10-29 · Stamp: `v160-20261029-perf-audit`

## Cómo saber si el lag es el menú o el executor

El menú ya mide su propio costo y ahora **nombra** lo que lo consume:

1. **Overlay Session Info** (Render → Floating overlays → Session Info). Muestra
   `FPS`, `Ping`, `Menu X.XX+Y.YY ms` y `Spikes N · ms · módulo`.
   - `Menu` bajo (por ejemplo < 1.5 ms) y FPS bajo ⇒ **no es el menú**: es el
     juego o el executor.
   - `Menu` alto, o `Spikes` con nombre de módulo ⇒ ese módulo es el culpable;
     apágalo o baja su rango.
2. **Consola**: el scheduler avisa cuando una tarea pasa de 3 ms
   (`[Wurst:Perf] <módulo> is taking X ms per frame`) y cuando un frame supera
   45 ms (`frame spike N ms (menu X ms · módulo)`). Si el aviso de spike dice
   `menu 0.20 ms`, el tirón no vino del menú.
3. **`print(state.perfReport())`** en la consola del executor: FPS, ms de tareas
   y render, y el top 6 de módulos por costo.

Todo eso existía; lo que faltaba era que las tareas tuvieran nombre. Antes casi
todas se reportaban como `task`.

## Lo que se encontró (auditoría estática nueva)

`tools/audit_performance.py` analiza las 72 suscripciones por frame del proyecto:
extrae el cuerpo real del callback equilibrando paréntesis y cuenta lo que
cuesta (raycasts, `GetPlayers`, `GetChildren`/`GetDescendants`, `Instance.new`,
`FindFirstChild`) y si el callback se autolimita con `os.clock`. Además exige:

- que ninguna tarea por frame de MM2/Universal quede sin nombre;
- que cada `featureConnections.X` tenga su `disconnectFeatureConnection("X")`
  (si no, apagar un módulo deja el callback vivo pagando CPU);
- que ningún `while true do` gire sin espera ni salida.

Hallazgos corregidos:

| Dónde | Problema | Corrección |
|---|---|---|
| `MM2/base.lua` | El muestreador de cuchillos se conectaba en el primer lanzamiento y **nunca** se desconectaba: quedaba midiendo una tabla vacía para siempre | Se retira solo cuando no quedan cuchillos y se re-arma en el siguiente lanzamiento |
| `MM2/Blatant/Shoot.lua` (Auto Shoot) | En cada frame resolvía predicción + corredor + raycasts **y después** rechazaba por la compuerta de 1.5 s o por arma recargando | Las compuertas baratas (shot pendiente, remote, origen, arma deshabilitada) se evalúan antes del cálculo |
| `universal/Blatant/Spider.lua` | Construía `RaycastParams` y una lista con `GetPlayers()` en **cada** frame, antes de mirar si había input | Lee personaje e input primero; parámetros reutilizados y lista de ignorados a 2 Hz |
| `universal/Movement/AntiVoid.lua` | Escribía `Size`, `CFrame` y `Transparency` de la plataforma cada frame, dentro de un `pcall`, aunque no hubiera cambiado nada | Solo escribe cuando el destino cambió más de 0.05 studs o cambió la visibilidad |
| `guis/.../Widgets.lua` (`addStatOption`) | `set()` asignaba `Text` siempre; módulos como Auto Farm/Auto Win lo llaman por frame | Solo escribe cuando el texto cambia |
| 33 tareas MM2/Universal | Se reportaban como `task`, así que el aviso de FPS no decía nada | Todas llevan etiqueta (`MM2 Auto Shoot`, `MM2 Knife Throw`, `MM2 knife sampler`, `Spider`, `Noclip`, `Anti Void`…) |

## Lo que ya estaba bien (y por tanto no se tocó)

- Los ESP (Coin ESP, Gun ESP, Trap, Roles) están **dirigidos por eventos** o con
  periodo (0.4–0.5 s), no por frame.
- Auraciones (Coins, Gun, Knife) van a 12–20 Hz con `os.clock`, no a 60.
- Predicción: un solo muestreador a 60 Hz con caché de partes a 2 Hz; su costo
  es lectura de propiedades, no raycasts.
- `ImproveFps` procesa como máximo 200 objetos por frame, y solo si está activo.
- Anti Fling compara antes de escribir; Speed/Jump escriben solo si cambian.
- El scheduler mide cada tarea con dos `os.clock()`; si una falla 3 veces se
  desconecta sola.

## Bugs / defectos reales encontrados

- El muestreador de cuchillos sin desconectar (arriba) era una **fuga de
  conexión permanente**, no solo un costo.
- Auto Shoot gastaba CPU durante toda la ventana de confirmación para luego
  rechazar; no cambiaba el instante de disparo, solo el costo.
- `test_action_latency.py` y `test_mm2_precision.py` afirmaban el texto exacto
  `TaskManager:Connect(autoGetGunTick)` / `(autoShootTick)`, que ahora lleva
  etiqueta; se ajustaron al prefijo (la intención, no la forma).

## Cómo se verificó

`bash tools/validate.sh` en verde: **90 fuentes**, **77 suites**, auditoría de
rendimiento nueva (72 callbacks, todos por frame autolimitados o baratos),
boot `failures=0`, menú 49/48 tarjetas.

## Límites

- Es análisis estático + contrato; los milisegundos reales dependen del
  dispositivo, del executor y del mapa. Los números que importan son los del
  overlay en el juego.
- Las otras bases (BedFight, TRS, VD, X2Duels) tienen sus propios bucles sin
  limitar; la auditoría los lista como información, no como fallo, porque no se
  cargan en MM2. Si se juega alguno de esos juegos, ese es el siguiente lugar a
  mirar.
- No se puede distinguir desde el script cuánto del frame se va en el executor:
  si `Menu` es bajo y los FPS siguen mal, la comparación honesta es con el mismo
  juego sin el menú inyectado.
