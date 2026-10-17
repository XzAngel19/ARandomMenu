# Restauración v22 — Menú clásico + Shoot/Knife reparados

**Fecha:** 15 de octubre de 2026.
**Rama:** `arena/184d6123-arandommenu`.
**Carga:**

```lua
getgenv().WURST_BRANCH = "arena/184d6123-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/184d6123-arandommenu/src/Wurst.lua", true))()
```

## Qué pasó y qué se hizo

La rama anterior (`arena/d83a806d`) apiló v17→v21 sobre la base buena: rediseñó
el menú (botones segmentados, gráficas de telemetría, paneles de modos) y
partió la predicción en tres perfiles (`Old` / `Actual` / `Experimental`) con
modelos de movimiento, épocas, ráfagas e hitboxes. Esta rama vuelve al diseño
clásico de v14 —el de tu loadstring `arena/2daf1a78`— y conserva solo las
reparaciones verificadas de v15/v16 más las correcciones de los defectos que
la propia auditoría reprodujo.

**Lo que se eliminó por completo:**

- Perfiles de predicción (Old/Actual/Experimental) y sus "modelos de movimiento".
- Hitbox local, burst, época de predicción, landing guard, budgets de escena.
- Gráficas de telemetría, botones segmentados y paneles reorganizados del menú.
- `WeaponVisuals` (visuales locales de arma: no añaden daño).
- Herramientas de test v17–v21 y sus documentos.

## ¿Tres modos en Shoot? No — y no afectan a SilentAIM

**No deberían existir tres modos de predicción.** El error de la rama anterior
fue convertir tres revisiones históricas del mismo solver en un selector de
perfil: cada "perfil" duplicaba la lógica con reglas distintas y ninguna era
la buena. La predicción correcta es **una sola**: horizonte RTT medido +
descuento por giro + aceleración, la de v14 que "tenía buena predicción".

SilentAIM **no es un modo de predicción**: usa exactamente el mismo solver que
el disparo normal; solo cambia *dónde se firma el disparo* (junto al objetivo,
con la variante Front/Through/Top/Behind). Por eso en esta versión:

- `Shoot` → Manual/Custom elige **objetivo**, no algoritmo.
- `SilentAIM` (interruptor) → misma predicción, dispara a través de paredes.
- `Auto Shoot` → Normal/Silent decide si el disparo automático espera línea
  de visión o no. Es el único "modo" real y es de autoría, no de predicción.

## Reparaciones incluidas (todas quirúrgicas, sin tocar el diseño)

### Shoot (v16 verificado + correcciones de auditoría)

1. **Giro normalizado por tiempo** (antes fallaba la auditoría 5.2): el turn
   rate ahora se mide en radianes/segundo sobre la ventana real de cambio de
   dirección. Con un giro físico de 180°/s, antes daba 0.074 a 20 Hz y 0.002
   a 120 Hz (el descuento dependía de Motion Hz); ahora da ~π rad/s en
   20/60/120 Hz (verificado por caracterización).
2. **Correlación de confirmaciones FIFO** (auditoría 5.1): la señal `GunFired`
   se empareja con el intento **más antiguo** cuya herramienta y origen
   geométrico coinciden. Antes confirmaba el disparo más reciente con la misma
   arma y metía una latencia equivocada en el horizonte adaptativo.
3. **Max error empieza en 0.35** (auditoría 5.4): el solver nunca reporta
   menos de 0.35 studs; el slider ya no permite valores que bloquean todo.
4. **Spawn A/B sin falsos hits** (auditoría 5.6): solo el `hitPart` del
   servidor cuenta como hit; desconexiones/cambios de rol no cuentan ni como
   hit ni como miss.
5. De v16: `Through` como variante por defecto, segmentos silentes que no
   cruzan transeúntes, muestreo de movimiento solo del objetivo seleccionado.

### Knife (v16 verificado + lead mejorado con TU telemetría)

1. **Lead de vuelo de paquete con datos medidos**: el cuchillo se genera en el
   servidor un RTT completo después de autorizar el tiro, y tu observación del
   objetivo está un RTT desfasada. La calibración mide exactamente esa ventana
   (`knifeSpawnDelayMs`, **243 ms de media con 21 lanzamientos confirmados** en
   tu JSON); ahora el lead usa esa medida (con ≥3 confirmaciones) y cae a RTT
   completo —no RTT/2— como respaldo. v10/v16 usaban RTT/2 y quedaban cortos.
2. **Intercepción de velocidad constante** (v16): resuelve el punto de
   encuentro real en vez de distancia/velocidad de una sola estimación.
3. **Throw Hz funciona** (v16): controla de verdad la cadencia de comprobación.
4. **Animación después del paquete** (v16), identificada por nombre "throw",
   nunca bloquea el envío.
5. **Interruptor maestro coherente** (auditoría 4.1): apagar `Knife` detiene
   Aura y Throw **y** desmarca sus casillas (visual, perfil guardado y
   controlador juntos). Nunca más "encendido pero muerto".
6. **Rangos separados** (auditoría 4.2): `Aura Range` y `Throw Range` ahora
   tienen claves de guardado independientes; antes compartían `MM2.Knife.Range`
   y se sobrescribían entre sí.

### Menú / widgets (mínimo, sin rediseño)

- Los campos numéricos acotan al rango anunciado tanto al escribir a mano como
  al restaurar un perfil (auditoría 4.3).

## Datos que alimentan la predicción (de tu TestingStuff)

| Medida | Valor de tu JSON | Uso |
|---|---|---|
| `knifeSpeed` | 96 studs/s (21 confirmados) | velocidad de la hoja |
| `knifeSpawnDelayMs` | 243 ms media (196–489) | lead del paquete del cuchillo |
| `gunAcceptanceMs` | 278 ms media (128–1008) | horizonte del disparo |

`Auto tune lead` sigue desactivado por defecto y solo aprende de impactos
confirmados por el servidor; `Lead bias` sigue siendo manual y acotado.

## Verificación ejecutada

- 69 archivos `.lua` compilados con Luau 0.732 (compilador oficial) — 0 errores.
- Bundle regenerado (`tools/build_bundle.py`) y verificado: 67 módulos,
  sello `v22-20261015-classic-restore`, sin restos de WeaponVisuals.
- 13 comprobaciones de caracterización sobre la lógica reparada (invariancia
  Hz del giro, decaimiento en línea recta, correlación FIFO, lead del cuchillo,
  intercepción) — todas pasan.

## Cómo probar (una variable a la vez)

1. Shoot Manual Normal (quieto → recta → giro → salto → pared).
2. Shoot Manual + SilentAIM (misma diana, compara variantes en Spawn A/B).
3. Auto Shoot Normal → Auto Shoot Silent.
4. Knife Throw Normal → Silent; Knife Aura solo; luego maestro ON/OFF y
   confirma que las casillas se apagan y nada queda "vivo" tras reinyectar.

---

## v23 — Organización limpia del menú + WallCheck con visibilidad parcial

**Sello:** `v23-20261015-clean-org`.

### Shoot: Mode / Target como en la última versión que te gustó

El card de Shoot ahora abre con la organización clara:

1. **Mode** — `Prediction` / `Silent AIM`. Prediction dispara desde tu pistola
   con compensación de lead; Silent AIM firma el disparo junto al objetivo
   (misma predicción, atraviesa paredes). Reemplaza al interruptor SilentAIM.
2. **Target** — `Murder` / `Custom`. Murder persigue al asesino; Custom usa el
   jugador de "Target player" (que solo aparece con Custom).
3. Los controles exclusivos de Silent (Silent sweep, Silent spawn, Spawn A/B)
   se ocultan mientras el modo es Prediction — menos ruido visual.

`Auto Shoot` conserva su propio Mode Normal/Silent (autoría del disparo
automático), igual que antes.

### Cards Metrics y Learning con paneles

- **Metrics** tiene un selector **Mode** arriba: `Calibration` /
  `Game learning` / `Projectiles`. Solo se muestra el panel activo; cambiar de
  vista no detiene ningún observador encendido ni descarta datos. En MM2 abre
  por defecto en Calibration; en otros juegos en Game learning. La última
  vista elegida se recuerda entre sesiones.
- **Learning** (nuevo card agrupado, misma mecánica): `Remote logger` +
  `Screen samples`. Remote Logger ya no es un card suelto: vive dentro de
  Learning junto a las capturas de pantalla. Misma lógica de hook, mismo
  formato de reporte, sin cambios de comportamiento.

### WallCheck: dispara a la partícula visible

Antes: si el torso previsto estaba bloqueado, el disparo se rechazaba
("obstructed") aunque se viera un pedacito del enemigo. Ahora, cuando el punto
principal está bloqueado, se prueban las demás partes del cuerpo en orden de
prioridad (torso → cabeza → manos → brazos → piernas) con el mismo lead
aplicado, y **el disparo se apunta a la primera parte visible**: la manito con
el cuchillo asomando tras la pared cuenta como blanco. Solo si absolutamente
nada del cuerpo tiene línea de visión libre se rechaza el tiro. Silent AIM
sigue ignorando el WallCheck como siempre (firma el disparo en el objetivo).

### Verificación

- 69 archivos `.lua` compilados con Luau 0.732 — 0 errores.
- Bundle regenerado: 67 módulos, sello `v23-20261015-clean-org`.
- Las 13 comprobaciones de caracterización de v22 siguen pasando.

### Prueba sugerida del WallCheck nuevo

1. Sheriff, WallCheck ON, Mode Prediction.
2. Pega al asesino a una esquina hasta que solo se le vea la mano/brazo.
3. Dispara: el tiro debe salir apuntado a la parte visible (antes decía
   "A wall blocks the shot").
4. Ocultación total detrás de la pared → sigue rechazando correctamente.

## v24 — TeamCheck avanzado + desactivación real + Weapon Visuals restaurado

Pedido: arreglar Kill Aura y crear TriggerBot; persistencia de teletransporte;
Chams con nametags y blanco por defecto (dejaba todo rojo); quitar opciones MM2
del Chams universal; Xray y Speed deben restaurar al apagarse; Double Gun /
Double Knife deben levantar AMBOS brazos; Electric Effects no hacía nada;
Arrows con colores de rol; y un TeamCheck avanzado siempre activo.

### TeamCheck avanzado (siempre activo, no es módulo, no configurable aún)

`state.teamCheck` en Wurst.lua responde con el primer método que pueda decidir:

1. Proveedor de equipos del juego (`registerTeamProvider`).
2. Lados por rol cuando el juego registra roles (MM2: Inocente/Héroe/Sheriff
   juntos, Asesino solo).
3. Servicio Teams de Roblox (`player.Team`).
4. TeamColor, solo si el juego usa equipos.
5. Neutrales jamás son compañeros.

Todo lo que no pueda decidir devuelve "desconocido" — nunca adivina. Lo usan
TriggerBot, Chams, Arrows y Killaura (post-filtro tras `InRange`).

### Reparaciones incluidas

- **Kill Aura**: opciones reordenadas (activación → alcance → campo → armas →
  filtros → resaltado), post-filtro del TeamCheck avanzado, destroy real
  (apaga el aura antes de limpiar) y bloque de activación reindentado.
- **TriggerBot (nuevo, universal, Combat)**: dispara cuando la mira reposa
  sobre un enemigo válido. Alcance, retardo y "disparar a compañeros"
  (protegidos por el TeamCheck mientras esté apagado). Usa `mouse1press`
  cuando el executor lo ofrece, `VirtualInputManager` como respaldo.
- **Teleport persistente**: el snippet ahora se arma por `game.GameId`
  (universo), no por PlaceId — los teletransportes internos del juego (nueva
  instancia, lobby) mantienen el menú.
- **Chams (reescrito, universal)**: color de relleno BLANCO por defecto. La
  causa del "todo rojo" era la opción "Team colours" activada por defecto sin
  datos de equipo — se eliminó del default y se migra el estado heredado.
  Opciones nuevas: **Nametags** (nombre + distancia, coloreado por rol) y
  distancia de nametag. Colores de equipo solo con la opción Team colours
  (genérica, Roblox teams); los colores de rol del juego siempre ganan.
- **Role Tags (nuevo, MM2, Render)**: todo lo MM2 que vivía en el Chams
  universal — Murder tag con icono de perk, role tags por jugador, Gun ESP y
  Trap ESP. Los módulos universales quedan 100 % agnósticos al juego.
- **X-Ray**: además del restore normal, un barrido de
  `LocalTransparencyModifier` atascado al iniciar y al apagar — nunca más
  queda el mapa translúcido tras una sesión muerta.
- **Speed**: recuerda `baseWalkSpeed`/`lastAppliedWalkSpeed`; al apagar, el
  humanoide vivo vuelve a su velocidad base inmediatamente aunque el mapa
  débil de capturas se haya perdido (respawn).
- **Arrows**: color por defecto blanco; colores de rol cuando el juego conoce
  roles; Team colours opcional para compañeros; TeamCheck avanzado integrado.
- **Weapon Visuals (restaurado de v16 + fix de brazos)**: Double Gun y Double
  Knife ahora levantan AMBOS brazos — el brazo izquierdo copia la animación
  del derecho espejada (hombro/codo/muñeca en R15, hombro en R6) cada frame
  vía `RunService.PreSimulation`. Electric Knife vuelve a funcionar (el
  módulo no estaba en la lista de carga; ahora sí). Los R6 guardan sus
  Motor6D en el Torso — la búsqueda cubre ambos rigs.

### Verificación

- 72 archivos `.lua` compilados con Luau 0.732 — 0 errores.
- Bundle regenerado: 70 módulos, sello `v24-20261015-teamcheck-visuals`.
- `test_entity_team_provider`: 14/14. `test_mm2_v16`: 4/4 grupos (incluye
  aserciones nuevas del espejo de brazos R6 y de la cadena R15 completa).
- `test_mm2_precision`: 14/14 grupos — estaba roto desde v22 (el extractor
  del test no seguía los cambios de base.lua: GUN_LEAD, knifeSpawnDelay,
  mm2KnifeRuntime y el modelo de lead medido de v22); reparado y actualizado
  a la fórmula aceptada (ventana de paquete = RTT completo, con demora de
  spawn medida cuando hay ≥3 confirmaciones).

### Prueba sugerida

1. Chams ON sin tocar nada → todos blancos (ya no rojos).
2. MM2 con roles revelados → Role Tags con colores; Chams/Arrows heredan el
   color de rol.
3. Double Gun/Knife + apuntar → ambos brazos se levantan simétricos.
4. Electric Knife → arcos visibles sobre el cuchillo real y el clonado.
5. X-Ray ON/OFF → el mapa vuelve opaco al instante. Igual Speed.
6. TriggerBot con el dedo fuera del gatillo → dispara solo contra enemigos.
7. Teletransporte interno del juego → el menú reaparece solo.

## v24.1 — Puntería real del arma + color "Enabled" en los checkboxes

Reporte: el disparo cae demasiado abajo desde altura (posición imposible), la
predicción se va a la izquierda/derecha de objetivos que giran lento, el Silent
AIM falla demasiado, y el color "Enabled" de la paleta no se ve en los
checkboxes.

### Por qué fallaba el disparo (dos defectos encadenados)

1. **El horizonte apuntaba al futuro que MM2 nunca acepta.** La telemetría
   midió ~277 ms de "aceptación" y el modelo los interpretó como lead
   ADELANTE: horizonte = RTT(≥0.2) + staleness + frame ≈ 0.23 s. Pero esa
   ventana es de *rewind*: el servidor acepta tiros apuntados a posiciones que
   el objetivo ocupó en los últimos ~277 ms. Lo que vemos ya llega retrasado
   por replicación (~½ RTT), o sea que la posición observada ya está dentro de
   la ventana. Sumarle 0.23 s hacia adelante apunta a una posición futura que
   el rewind no cubre → fallos sistemáticos adelante del movimiento
   ("a la izquierda o derecha") y, desde 30 m de altura, el rayo pasa de largo
   y se estrella en el suelo lejos del objetivo ("una posición donde el murder
   no podría estar").
2. **Caída balística fantasma.** `isMotionGrounded` exige
   `FloorMaterial ~= Air`, pero los personajes remotos suelen leer `Air` en
   nuestro cliente, así que un jugador caminando por suelo plano entraba en la
   rama "aérea" y recibía `−½·g·lead²` ≈ **−5.6 studs**: el tiro se enterraba
   bajo sus pies.

### Correcciones

- **Lead por defecto = 0** (apuntar a lo que se ve): `getGunHorizonSeconds` ya
  no suma RTT/staleness/frame ni la aceptación medida; solo el "Lead bias"
  manual (±0.1 s) y la corrección automática (opt-in) pueden añadir lead,
  acotado a **[0, 0.15] s**. Con lead 0 el chequeo "turning too hard" y el
  descuento por giro quedan inertes: nunca más rechaza tiros por girar lento.
- **Vertical blindado**: velocidad vertical ≈ 0 ⇒ lead vertical 0 (aunque el
  FloorMaterial mienta); la rama aérea real queda acotada a ±3 studs. El arma
  es hitscan — no hay caída de bala propia.
- **Silent AIM hereda todo** (usa el mismo `computeGunAim`): ahora dispara a
  la posición observada, con el barrido/opción de spawn intactos.
- **Color "Enabled" aplicado de verdad**: el checkbox (caja + borde) se repinta
  al cambiar la paleta — antes solo se releía el tema al togglear cada opción,
  y el checkmark interior estaba hardcodeado en verde. El check ahora usa un
  color de contraste automático (oscuro/claro según luminancia) para seguir
  visible sobre cualquier color elegido. Se aplica en vivo y persiste igual
  (ya se guardaba en el config).

### Verificación

- 72 archivos compilados con Luau 0.732 — 0 errores; bundle 70 módulos,
  sello `v24.1-20261015-aim-palette`.
- `test_mm2_precision` 14/14 con bloques nuevos: "gun horizon: rewind
  semantics; zero default lead; bias+auto capped at 0.15" y la regresión
  "no phantom drop" (FloorMaterial=Air en suelo plano ⇒ lead vertical 0).
- Los tests del solver confirman: lead horizontal intacto cuando hay bias,
  torso/root offset, salto real, y muestra de respawn obsoleta ignorada.

### Prueba sugerida

1. Sheriff en Mil, subido a una carga con el murder abajo caminando: el tiro
   debe ir A SU CUERPO (ni al suelo ni adelante de su movimiento).
2. Murder girando la cámara mientras camina: el tiro ya no se desvía a
   izquierda/derecha.
3. Silent AIM: la tasa de acierto debe subir drásticamente (misma posición
   observada, sin lead fantasma).
4. Opciones → UI → color "Enabled" → cualquier color: todos los checkboxes
   activados se repintan al instante y el check interior sigue visible.

## v25 — Gun ESP/Trap ESP en ItemESP · Fast time · lead ½-ping · Weapon Visuals blindado

Reporte: no aparecían Gun ESP ni Trap ESP (había que ponerlas en ItemESP);
TimeChanger necesita un "Fast time" que recorra 00:00→24:00 en menos de 5
segundos; Weapon Visuals sigue con un error; y el disparo ahora apunta
demasiado tarde — a donde el Murder estaba hace ~1 segundo — sin acertar
ningún tiro con movimiento activo.

### Por qué no veías Gun ESP / Trap ESP (bug real de carga)

Los módulos de juego (MM2) corrían sin la fachada `services`: RoleTags leía
`services.gameBridge` sobre un entorno donde `services` era nil → el módulo
fallaba al cargar y sus opciones desaparecían del menú. Arreglado: el entorno
de juego recibe `state.moduleServices` como el del framework.

### Gun ESP / Trap ESP ahora viven en ItemESP

Nuevo servicio `itemEsp` (registro de proveedores): el ItemESP universal
renderiza un toggle por proveedor y sigue siendo agnóstico al juego — MM2
registra "Gun ESP" y "Trap ESP" (respaldados por los toggles del core de
RoundEsp), y aparecen como opciones dentro de la tarjeta ItemESP, con el
interruptor maestro de la tarjeta controlándolos. Role Tags conserva Murder
tag / Role tags / Show Perk.

### Fast time (Time Changer)

Nuevo toggle "Fast time": recorre el día completo 00:00→24:00 en ~4 segundos,
en bucle mientras el módulo esté activo. Al apagarlo vuelve a la hora del
slider. El estado de la tarjeta muestra la hora ciclando.

### Predicción del arma: lead de ½ ping

Dos reportes de campo, uno por dirección: v24 (lead del ventana completa de
aceptación ~277 ms) fallaba por DELANTE; v24.1 (lead 0) fallaba por DETRÁS
("apunta a donde estaba"). La reconciliación física: nuestra vista del
objetivo llega al servidor con ~½ RTT de retraso (víctima → servidor →
nosotros), así que el lead correcto es exactamente ese staleness — ni 0, ni
277 ms. Ahora: `horizonte = ½·RTT (máx 0.15) + Lead bias (±0.15) + auto
(opt-in, máx 0.1)`, acotado a [0, 0.25] s. Con ping de 120 ms el lead
automático es 0.06 s; el slider permite afinar ±0.15 s si tu conexión lo
pide. La aceptación medida (277 ms) es un rewind y ya no se gasta como lead
adelante.

### Weapon Visuals (blindado)

- **Reset R6 roto (bug real)**: la lista de candidatos usaba `ipairs` con
  huecos nil — en R6 el Torso nunca se alcanzaba y el hombro izquierdo quedaba
  congelado en la última pose espejada tras apagar. Ahora se colectan solo
  las partes existentes.
- **Espejo tras el Animator**: el write del Transform ahora cae en
  `PostAnimation` (el momento exacto posterior al paso del Animator) con
  `PreSimulation` de respaldo — si el orden del entorno era el problema, ya
  no lo es.
- **Errores visibles**: el rebuild diferido va con pcall y `warn` — si algo
  falla verás "[Wurst] Weapon Visuals rebuild failed: <motivo>" en consola en
  vez de un fallo mudo.
- **Respaldo de búsqueda de arma**: si el lookup por tags no encuentra el
  arma, se intenta por nombre (solo visual).

### Verificación

- 72 archivos compilados con Luau 0.732 — 0 errores; bundle 70 módulos,
  sello `v25-20261015-itemesp-fasttime-lead`.
- `test_mm2_precision` 14/14 con el bloque nuevo "gun horizon: half-ping
  staleness lead; auto capped at 0.1; huge ping capped" (ping gigante ⇒
  staleness tope 0.15). `test_entity_team_provider` 14/14, `test_mm2_v16`
  4/4.

### Prueba sugerida

1. ItemESP → activa "Gun ESP" / "Trap ESP" (aparecen ahí mismo).
2. Time Changer → "Fast time" → el día cicla completo en ~4 s.
3. Sheriff vs murder caminando: el tiro debe caer SOBRE el cuerpo; si tu
   conexión es inusual, ajusta "Lead bias" (+ si sigue corto, − si se pasa).
4. Double Gun/Knife: ambos brazos; al apagar, el brazo izquierdo vuelve a su
   pose (R6 incluido). Si ves "[Wurst] Weapon Visuals rebuild failed: …",
   mándame el texto exacto del motivo.

## v26 — Profiles completos · paleta Arrows · auditoría UI · predicción peek/salto/frenado

Pedido: verificar que nada esté hardcodeado y todo coincida con UI Settings;
paleta "Arrows" para las flechas de los módulos; keybinds de los módulos
coincidiendo con Enabled; "KeyBind profiles" pasa a ser **Profiles** con
snapshot completo, update, panic y borrado por perfil; y la predicción del
Shoot corregida (peek contra pared, tiros por detrás/lados/salto).

### Auditoría UI: hallazgos y correcciones

- **Defaults de la paleta mentían**: el picker "Enabled" mostraba un verde
  (32,175,32) que no era el color real del tema (236,236,238); Background,
  Accent y Text igual. Ahora los defaults de TODOS los pickers salen de los
  tokens vivos del tema.
- **Flechas hardcodeadas en verde**: flecha de expansión de cada módulo,
  flechas de secciones de ajustes, flechas de dropdowns y chevron de ventanas
  — todas usaban `Color3.fromRGB(0, 204, 0)` fijo. Nuevo token de tema
  **`arrows`** + fila "Arrows" en UI Settings; los píxeles de cada icono se
  registran con `ThemeEngine.Bind` (tabla débil: los iconos destruidos salen
  solos) y se repintan EN VIVO al cambiar el color.
- **Cuadraditos de keybind hardcodeados**: un bind activo pintaba verde fijo
  y un conflicto rojo fijo. Ahora: bind activo = color **Enabled** de la
  paleta, conflicto = color negativo del tema, con repintado en vivo.
- **Chrome de ventanas**: cruz de cerrar y pin usaban colores fijos; ahora
  Theme.negative / Theme.enabled.

### Keybinds junto a Enabled

El cuadradito de keybind de cada módulo (clic → presiona una tecla; Backspace
limpia) ahora pinta con el color "Enabled" que elijas, en vivo, igual que los
checkboxes.

### Profiles (antes "Keybind Profiles")

- **Snapshot completo**: cada perfil guarda TODOS los estados de módulos,
  TODOS los valores de opciones, y los keybinds — no solo teclas.
- **Aplicación en vivo**: cargar un perfil enciende/apaga las tarjetas (con
  sincronización de UI completa), mueve los toggles de opciones, aplica
  sliders/colores/ciclos/texto EN PANTALLA (nuevo registro
  `state.valueControls` con apply+default por opción) y restaura keybinds.
- **Detalle por perfil**: fecha y hora de guardado, módulos activos y número
  de opciones guardadas.
- **UPD** por perfil: actualiza ese perfil con la configuración actual.
- **x** por perfil: botón pequeño que borra ese perfil.
- **PANIC**: apaga todos los módulos, apaga todas las opciones, devuelve cada
  valor a su default EN VIVO y limpia el config guardado (los perfiles y los
  keybinds sobreviven para poder recuperar todo con un LOAD).

### Predicción del Shoot (peek, detrás, lados, salto)

- **Peek contra pared**: el rescate de visibilidad ahora prueba también la
  posición OBSERVADA (sin lead) de la parte grande — la ventana de rewind la
  acepta y durante un peek el torso crudo está expuesto aunque el punto con
  lead siga dentro de la pared. Antes solo probábamos puntos con lead, y el
  disparo acababa en la pierna.
- **"Como prediciendo el futuro" (se pasa de largo)**: damping por tiempo de
  frenado — nunca se lidera más allá del tiempo que el objetivo necesita para
  detenerse. Un strafe que se invierte (peek in/out) reduce el lead al
  momento, en vez de sobrepasarse adelante.
- **"Le da por detrás por un poco"**: el lead de staleness pasa de ½·RTT a
  **0.6·RTT** (mismo tope de 0.15 s).
- **"Demasiado recto, no le da cuando salta"**: el estado del humanoid
  (Jumping/Freefall) llega antes que la física replicada; ahora un salto
  recién iniciado recibe lead vertical (mínimo 8 studs/s de subida asumidos
  mientras la velocidad no llegue), en vez de un tiro plano.

### Verificación

- 72 archivos compilados con Luau 0.732 — 0 errores; bundle 70 módulos,
  sello `v26-20261015-profiles-arrows-aim`.
- Tests 14/14 con el bloque ampliado del solver: "linear lead; torso offset;
  jump; stale sample; no phantom drop; **stop damping; jump state**" y el
  horizonte "0.6xRTT staleness lead".

### Prueba sugerida

1. UI Settings → cambia "Arrows" y "Enabled": flechas, checkboxes y
   cuadraditos de keybind se repintan al instante.
2. Profiles → guarda un perfil con todo configurado → PANIC (todo a default)
   → LOAD del perfil → todo vuelve tal cual estaba.
3. Sheriff vs murder en peek: el tiro debe buscar el torso visible, no la
   pierna; strafes con inversión no se sobrepasan; saltos reciben lead
   vertical.

## v26.1 — 2026-10-15 — Reparación de la regresión v26 (UI Settings desaparecido + dock reaparecido)

### Síntoma reportado

Tras v26 la ventana **UI Settings dejaba de aparecer** y el **dock volvía a
verse** aunque estuviera desactivado en la config guardada. El resto del menú
funcionaba normalmente.

### Diagnóstico (reproducido con harness de arranque completo)

Se construyó un harness (`full_boot.luau`) que ejecuta el **Wurst.lua real de
punta a punta** sobre mocks de Roblox/executor, con el **bundle real v26**.
El boot log mostró la causa exacta:

```
[Wurst:Bootstrap] Library failed (src/guis/Wurst/Code/SettingsPage.lua):
  src/guis/Wurst/Code/Widgets.lua:2288: attempt to index nil with 'R'
```

Cadena completa:

1. v26 añadió el token de tema `arrows` al preset **Monochrome** pero **no al
   preset Wurst** (el que carga por defecto). `Theme.arrows` quedaba `nil`.
2. SettingsPage crea la fila de paleta "Arrows" con `default = Theme.arrows`
   (nil) → `colorFromConfig(valorGuardado, nil)` → nil (nadie tenía
   `ClickGUI.Arrows` guardado: la fila es nueva en v26).
3. `hexOf(nil)` en Widgets.lua:2288 → crash → **SettingsPage.init aborta a
   mitad** ("Library failed", el boot continúa sin esa librería).
4. Como SettingsPage muere **antes** de crear el toggle "Show dock", nunca se
   restaura `state.uiShowDock` desde la config guardada → Furniture ve
   `state.uiShowDock ~= false` → **dock visible** aunque el usuario lo tenía
   apagado.

El harness con mocks aislados (Widgets+WindowManager+SettingsPage) no lo
reproducía porque el mock incluía `Theme.arrows` a mano; hizo falta el boot
completo con el theme real para verlo.

### Arreglos

1. **Raíz** — `src/Wurst.lua`: el preset **Wurst** ahora incluye
   `arrows = Color3.fromRGB(0, 204, 0)` (mismo valor que Monochrome). Ninguna
   ruta del ThemeEngine puede dejar el token en nil (`Set`/`SetMany` solo
   añaden, `Apply` nunca borra).
2. **Defensa en SettingsPage** — `Theme.arrows or Theme.enabled or (0,204,0)`
   para la constante de paleta, `row.default or Theme.text` por fila, y el
   bucle de filas de paleta envuelto en `pcall`: si una fila volviera a
   fallar (token nuevo ausente, color guardado corrupto) se salta esa fila
   con un warn y **la página sigue construyéndose** (incluido "Show dock").
3. **Defensa en Widgets** — `addColorOption` nunca deja pasar un color nil a
   `hexOf` (fallback blanco). Un default ausente ya no puede tumbar ninguna
   página de ajustes.

### Verificación

- Harness de arranque completo: "Library failed (SettingsPage)" desaparece;
  la página construye Background/Accent/Text/Enabled/Arrows/Rainbow/Opacity/
  **Show dock**. Variantes: preset sin `arrows` (simula theme pre-v26) también
  pasa — los guards defensivos sostienen la página sin crash.
- 72/72 archivos compilan; bundle 70 módulos, sello
  `v26.1-20261015-settingspage-palette-fix`.
- Suites: entity_team_provider 14/14, mm2_v16 4 grupos, mm2_precision 14
  grupos — sin cambios de comportamiento (los fixes solo tocan la paleta).

### Prueba sugerida en MM2

1. Ejecuta con tu config habitual (dock desactivado): el dock debe seguir
   oculto y UI Settings debe abrir con todas sus filas, incluida "Arrows".
2. Cambia "Arrows" en la paleta: los chevrones de la barra de título y las
   flechitas de keybind se repintan al instante.
3. Todo lo demás de v26 (Profiles, predicción) sigue igual.

## v27 — 2026-10-15 — Flechas vivas + right-click en ventanas; lead 1×RTT, pierce y sondas de torso

### UI (pedido directo)

- **Las flechas ya repintan solas**: los chevrones de colapso de las ventanas
  (y el pin/cross del chrome) usaban `Theme.arrows` estático capturado al
  crear la ventana — no se enteraban del cambio de paleta hasta que las
  tocabas ("tengo que tocarlas para que puedan cambiarse de color
  totalmente"). Ahora todos los íconos del chrome se dibujan con token de
  tema (`arrows`/`enabled`/`negative`), igual que las flechas de las cards,
  keybinds y Settings: al elegir un color en la paleta, TODAS las flechas se
  repintan al instante (bind por píxel + refresh del chrome por ventana).
- **Click derecho en la barra de título** colapsa/expande la ventana, además
  de presionar la flecha. (Las cards ya tenían ambos: flecha y click
  derecho.)

### Predicción — diagnóstico de "siempre en la misma dirección"

El tiro tenía el grado correcto pero caía desplazado hacia un lado
(strafe) o adelante/atrás (profundidad), siempre en la misma dirección, y en
strafes rápidos "le daba al centro" del recorrido. Causa: **sub-liderazgo**.
La posición del murder viaja murder→server→nosotros, así que lo que vemos ya
tiene ~1 RTT de atraso, y el servidor procesa nuestro disparo otro medio
RTT después. Con el factor 0.6×RTT de v26 solo compensábamos el 60% del
atraso real: el punto de mira siempre quedaba atrás del movimiento — en un
strafe rápido ese atraso se ve como el centro de su recorrido.

1. **Lead 0.6×RTT → 1.0×RTT** (tope de 0.15 s igual). El damping por tiempo
   de frenado y el descuento por giro siguen protegiendo contra el
   sobrepaso.
2. **Pierce del endpoint (4 studs)**: el remoto del arma castea un SEGMENTO
   hasta el punto que le pasamos, no un rayo infinito — por eso un fallo
   "chocaba con el aire" justo donde predijimos al murder, en vez de
   volarse a la pared de atrás. No hay ninguna entidad invisible: es el
   final de nuestro propio punto de mira. Ahora el punto se extiende 4
   studs MÁS ALLÁ del murder (el segmento lo atraviesa), así un error
   chico de lead sigue dando en el torso. La extensión solo se aplica si
   ningún inocente está en el tramo extra (el sheriff muere si dispara a
   un inocente).
3. **Sondas del torso en el wallcheck** ("detectando la pierna cuando no
   era necesario"): el rayo de visibilidad sale del arma, no de la cámara;
   una esquina puede tapar el CENTRO del torso desde la mira aunque en
   pantalla se viera expuesto, y el rescate caía directo a la pierna.
   Ahora se prueban 5 puntos dentro de la caja del torso (±0.55
   lateral, +0.35 arriba y las diagonales) antes de bajar a las
   extremidades. La pierna sigue siendo el último recurso.

### Verificación

- 72/72 compilan; bundle 70 módulos, sello `v27-20261015-live-arrows-lead-pierce`.
- test_mm2_precision 15 grupos (nuevo: "wallcheck rescue: torso probe beats
  the leg; leg-only still fires; fully blocked rejects"; horizonte actualizado
  a 1×RTT: 0.08/0.18/0/0.21/0.23/0.13/0.15). mm2_v16 4 grupos,
  entity_team_provider 14/14.
- Harness de arranque completo: sin "Library failed"; SettingsPage y
  WindowManager inicializan; sello v27 en el log.

### Prueba sugerida en MM2

1. UI Settings → Arrows → blanco: chevrones de ventanas, flechas de cards y
   keybinds se ponen blancos al instante, sin tocarlos.
2. Click derecho en la barra de una ventana: colapsa/expanda; la flecha
   sigue haciendo lo mismo.
3. Sheriff vs murder en strafe rápido: el tiro ya no debe quedar "en el
   centro" del recorrido ni atrás; los fallos por poco ahora atraviesan al
   murder en vez de morir en el aire.

## v28 (Parte 1) — 2026-10-15 — Theme con bindings fuertes, paleta persistente, Chams por roles, detección de Hero

### Flechas de los módulos — causa raíz encontrada

El fix de v27 arregló las ventanas por el redibujo explícito, no por el bind:
en producción **el bind de ThemeEngine no repintaba nada**. La causa: el
registro de bindings era una tabla **débil** (`__mode="k"`) — el userdata de
las Instancias puede ser recolectado aunque la instancia siga en el
DataModel (comportamiento dependiente del ejecutor), así que SetMany
iteraba un registro vacío y cada píxel conservaba su color de creación
hasta que lo tocabas (el click redibuja con el Theme vivo). El harness de
mocks no lo reproducía porque las instancias mock son tablas Lua
fuertemente referenciadas por el árbol.

Arreglos:
- **Wurst.lua**: `themeBindings` ahora es una tabla **fuerte**; los muertos
  se podan en cada repintado (Parent nil o fallo de escritura). `SetMany` y
  `Apply` comparten `repaintThemeBindings`.
- **Cards.lua**: las flechas de expandir de cada módulo se registran además
  en el refresh de tema (redibujo inmediato en cambio de paleta).
- **Widgets.lua**: las flechas de los combos (dropdowns) ídem.
- **SettingsPage.lua**: la paleta guardada se **re-aplica al Theme al
  arrancar** — antes los colores elegidos se perdían al re-ejecutar (el
  Theme nacía del preset) y los swatches mostraban el color guardado
  mientras la UI usaba el del preset.

### Chams en MM2 — modo por roles

- En MM2 ya no aparecen "Teammates"/"Team colours" (eso es de Universal);
  en su lugar: **Murderer ESP / Sheriff ESP / Hero ESP / Innocent ESP**
  (todos on por defecto) + **Show Perk** (ícono del perk sobre el murder).
  El color del highlight sigue el color de rol. En juegos universales las
  opciones de equipo siguen igual.
- PlayerESP ya tenía sus colores por rol (Murderer/Sheriff/Hero/Innocent/
  Dead colour) — sin cambios ahí.

### Detección de Hero (agarra la gun) — bug de datos rancios

Cuando el sheriff moría y alguien agarraba la gun, los nametags seguían
diciendo "Innocent" para siempre: el índice de roles solo re-consultaba el
remote de datos cuando NADIE tenía rol, y con datos rancios el portador
quedaba como estaba. Ahora:
- Quien tiene la gun con dato de ronda "Innocent" o "Hero" resuelve
  **Hero** inmediatamente (el sheriff spawn-ea con la gun; cualquier otro
  portador la recogió a media ronda).
- Cuando el set de portadores de gun cambia entre rebuilds, se fuerza
  `requestRoleRefresh()` para re-sincronizar (baja el Hero real, sube el
  sheriff muerto).

### Weapon Visuals — diagnósticos visibles

El módulo cargaba y su lógica es correcta (suite v16 verde), pero "no
funciona" en MM2 live sin decir nada. Ahora el rebuild pone **estado en la
card** (p.ej. "2x12 gun · arc x2") y si pides Double Gun/Knife con el arma
equipada y no se copia geometría, **avisa por notificación** ("found no gun
geometry - report the skin name") en vez de fallar en silencio. Con ese
mensaje sabremos exactamente qué skin no expone geometría en el tool.

### Verificación (harness de arranque completo, tools/gen_full_boot_harness.py)

El harness ahora bootea el Wurst real + bundle real con **0 fallos de
módulos** (mocks: typeof, ancestros, personajes, remotes de ronda) y
verifica de punta a punta:
- `HERO DETECTION VERIFIED`: ronda con dato "Innocent" + gun en mano →
  rol **Hero**; inocente normal → Innocent; lobby → Sheriff para el
  portador.
- `SAVED PALETTE + DOCK RESTORE VERIFIED`: config guardada con
  ClickGUI.Arrows blanco y Show dock off → Theme.arrows=(255,255,255) y
  state.uiShowDock=false tras el boot; swatch "Arrows | #FFFFFF".
- Chams MM2 muestra Murderer/Sheriff/Hero/Innocent ESP + Show Perk.
- 72/72 compilan; suites 14/14 + 4 + 15; bundle 70 archivos, sello
  `v28-20261015-theme-roles-chams`.

### Parte 2 completada en el mismo sello

Ver `## v28 (Parte 2)` abajo.

## v28 (Parte 2) — 2026-10-15 — Cadencia del servidor, animación del cuchillo, TrailESP/Tracer Data

Sello `v28-20261015-shoot-cadence-knife-visuals`. La Parte 2 se armó contra
los **logs reales** (`Shoot..txt` + `2026-10-15T23_30_07Z.log` de
TestingStuff), que demostraron por qué "shoot seguía igual":

### Shoot — cadencia del servidor (causa raíz #1)

- La telemetría v18 y el log del día muestran que el servidor **descarta en
  silencio** todo disparo que llegue <3.1 s después del anterior (los 18
  confirmados tuvieron brechas ≥3.6 s; todos los rápidos de 0.11–0.33 s
  murieron sin eco). El 2026-10-15, 2 de nuestros 5 disparos estaban a
  0.08 s → rechazados por cadencia.
- `GUN_SERVER_COOLDOWN = 3.1` en Shoot.lua: **una única compuerta** antes de
  la bifurcación silencioso/normal cubre ambos caminos (el gate viejo estaba
  solo en el camino normal), y ambos `FireServer` sellan
  `lastGunFireServer`. AutoShoot comparte la ventana: reintenta cada
  `Fire delay` y dispara apenas la ventana se libera (notificación
  "Auto Shoot waiting: Gun is cooling down…" deduplicada).

### Shoot — fin del pierce (causa raíz #2)

- Los otros 3 disparos del día tenían brechas legales (5.8 s / 4.3 s) y aun
  así 0/5 ecos: el servidor valida el endpoint contra la posición
  *rebobinada* del objetivo y el +4 studs del v27 mataba el disparo. El
  endpoint ahora es el punto predicho exacto; `GUN_PIERCE_STUDS` eliminado y
  el test de precisión lo prohíbe explícitamente.

### Knife Throw — animación reparada

- Causa: los cuchillos de MM2 **no traen ninguna Animation con "throw" en el
  nombre** (Animaciones genéricas Animation1/2/3), así que la búsqueda
  manual no encontraba nada → cero animación; y cuando encontraba algo, el
  Stop(0)/Destroy por lanzamiento rompía el rig.
- Ahora: **`toolanim` clásico** (StringValue "Lunge" dentro del tool) — el
  propio Animate del juego lo reproduce con prioridad y blending correctos y
  nunca deja el rig pegado; encima, si el cuchillo sí trae Animation
  "throw", se layer con track cacheado (restart por lanzamiento, fade suave
  al cambiar de arma). El test de ciclo de vida de animación sigue verde.

### Weapon Visuals — TrailESP + Tracer Data

- `GunFired(gunHandle, origin, hitPosition, hitPart)` es la verdad del
  servidor sobre dónde cayó cada bala (de todos, incluida la nuestra).
- **TrailESP**: haz neón origin→hit (color del módulo), esfera de aterrizaje
  y Highlight sobre la parte golpeada, con fade 1.4 s y limpieza por
  `task.delay`.
- **Tracer Data**: cuando el eco es de NUESTRA arma (handle descendiente de
  nuestro personaje), calcula la distancia studs entre el hit del servidor y
  la posición actual del Murderer → "Tracer: landed X.X studs from <name>
  (shot range Y)".

### Freeze Movements — modos nuevos

- **Freeze Emotes**: los tracks de prioridad Action (emotes) se recuerdan y
  se re-reproducen mientras te mueves → caminas mientras el emote sigue
  sonando.
- **Glitch Animations**: reinicia los tracks vivos con fade 0.05 cada frame
  → el personaje tiembla/glitchea para todos (el Animator local replica).
- Ambos modos no tocan WalkSpeed; Anchor/Humanoid siguen igual y la
  restauración completa al desactivar se mantiene.

### Flight y AutoShoot — verificación

- **Flight** (universal/Blatant/Fly.lua) auditado: suavizado exponencial
  independiente del framerate (`1-exp(-12·response·dt)`), LinearVelocity con
  `VectorVelocity` asignado cada tick, wallchecks con sobrepaso, Hover con
  nivel mantenido + chequeo de techo, plataforma Floor parentada a
  CurrentCamera (no replicada), PlatformStand con ownership y restauración
  completa al apagar. Sin cambios necesarios.
- **AutoShoot** verificado contra la compuerta de cadencia: reintentos
  silenciosos con dedupe, dispara apenas se libera la ventana del servidor.

### Verificación

- Harness full_boot: `failures=0`, HERO + paleta + dock verificados, y las
  etiquetas nuevas (TrailESP, Tracer Data, Throw animation) presentes.
- Suites: precisión 15/15 (con pins nuevos: sin pierce, gate compartido, 2
  sellos de `lastGunFireServer`), v16 4/4, teams 14 checks.
- 71/71 archivos compilan; bundle 70 archivos, sello
  `v28-20261015-shoot-cadence-knife-visuals`.

## v28 (Parte 2.1) — 2026-10-15 — Hotfix: Freeze Emotes, flechas que cierran, errores visibles

Sello `v28-20261015-emotes-arrows-toggle-errors`. Responde al test de campo
con screenshots (menú de emotes de Roblox + burbuja de chat):

### Freeze Emotes — reparado de raíz

Reporte: "No los detecta y no puedo caminar ni moverme en sí". Dos causas:

1. **Quedarse congelado al cambiar de modo**: cambiar el selector de
   "Anchor" (modo por defecto) a "Freeze Emotes" con el módulo activo no
   restauraba el WalkSpeed=0 y el root anclado del modo anterior → no
   podías caminar. Ahora cambiar de modo re-aplica el feature completo
   (deshace el modo anterior y arranca el nuevo limpio).
2. **Detección rota**: la versión anterior BORRABA el track recordado
   justamente cuando el juego lo detenía (al empezar a moverte), o sea en
   el único momento en que hacía falta. Ahora:
   - Los emotes (tracks con prioridad Action/Action2/3/4, o nombres
     dance/wave/point/cheer/laugh/emote — los del menú de emotes de Roblox,
     con o sin Action priority) se recuerdan mientras suenan.
   - Si el juego los detiene mientras te mueves → se re-reproducen (el
     baile sigue mientras caminas).
   - Parado y terminado de verdad → se olvida tras 0.5 s (no resucita
     para siempre).
   - Lógica validada con test de máquina de estados (recordar /
     resucitar×2 / olvidar / nunca recordar tracks de movimiento /
     detección por nombre con prioridad Core).

### Flechas: volver a presionar cierra la ventana de opciones

`toggleExpansion` solo abría la ventana; ahora, si la ventana del módulo ya
está visible, el mismo click la CIERRA (mismo camino que la X) — las
flechas son un toggle real de abrir/cerrar.

### "Could not toggle Weapon Visuals" — ahora autodiagnóstico

El pcall del framework tragaba el error real (solo iba al warn de consola).
Ahora:
- La notificación incluye la RAZÓN: "Could not toggle X: <error>".
- `setEnabled` de Weapon Visuals se envuelve en pcall interno: si algo
  falla, imprime el traceback completo en consola, corre la limpieza
  completa (nada queda mitad activado) y relanza el error para que la
  tarjeta lo reporte.
- El harness ahora prueba ciclos ON/OFF de Weapon Visuals y Freeze
  Movements (incluida la re-aplicación por cambio de modo) en cada build:
  `WEAPON VISUALS TOGGLE CYCLE CLEAN` / `FREEZE MOVEMENTS TOGGLE CYCLES
  CLEAN`.

### Verificación

- Harness: failures=0, HERO + paleta + dock + ciclos de toggle verificados.
- Suites 15/15 + 4 + 14 checks; 71/71 compilan; bundle 70 archivos, sello
  `v28-20261015-emotes-arrows-toggle-errors`.

## v28 (Parte 2.2) — 2026-10-16 — Lead de arco + feedback de hit, con los logs del 16 como verdad

Sello `v28-20261016-arc-lead-hit-feedback`.

### Lo que dicen los logs reales del 2026-10-16 (TestingStuff)

- `2026-10-16T22_14_51Z.log` y `22_18_17Z.log`: los DOS disparos del
  módulo fueron **aceptados por el servidor** (GunFired con nuestro handle y
  origen exacto) y **mataron al murderer** (sabinita130 DeadTime=88;
  Snowflakes12370 DeadTime=82 + `VictoryScreen` inmediato). El viejo
  "GunFired nunca se ecoa al tirador" era FALSO: sí hay eco.
- `MM2_Trajectory_Calibration.json` (sesión E16D1B0E, build v35 del otro
  branch): **9/9 disparos aceptados, 7/9 impactaron el cuerpo** del
  objetivo. El gate de cadencia de 3.1 s eliminó los rechazos por completo.
- Los 2 fallos: objetivos **girando bruscamente** al momento del disparo
  (velocidad rotada ~65-70° en la ventana de observación).

### Lead de arco (la corrección de los giros)

El turn-discount anterior solo escalaba la magnitud del lead (con
horizons de ~0.1 s quedaba en 97-99% = nada) y jamás corregía la
DIRECCIÓN. Ahora:

- `getFilteredVelocity` mide el giro **con signo** (componente Y del
  producto cruz velocidad_previa × velocity_actual; +1 izquierda, -1
  derecha, decae a 0 tras 0.2 s en línea recta).
- `getGunLeadChordRotation`: el objetivo que sigue girando se mueve por
  una CURVA, no por la tangente vieja; la cuerda hasta el punto medio del
  arco es la tangente rotada por MEDIO ángulo barrido, en la dirección del
  giro (máx 45°). El displacement del lead se rota con
  `CFrame.fromEulerAnglesYXZ(0, chord, 0)`.
- Convención verificada contra el miss real (north→west, crossY=+0.907)
  y contra la matriz R_y(θ) de Roblox; el suite de precisión ahora trae
  mini-Vector3 con Cross + mini-CFrame con rotación Y real, y un grupo
  nuevo "gun arc lead" (16/16).

### Feedback: el Shoot nunca más se ve "muerto"

- **Hit confirmado**: cuando el eco de GunFired trae un hitPart dentro del
  personaje objetivo → notificación "Hit <nombre> (<parte>) - server
  confirmed" (evidencia del servidor, no heurística).
- **Cooldown visible**: si disparas dentro de la ventana de 3.1 s del
  servidor, la notificación ahora dice "Gun ready in X.Xs (the server
  drops faster shots)" en vez de parecer que no pasa nada.

### Verificación

- Harness: failures=0, HERO + paleta + ciclos de toggle verificados
  (mocks extendidos con Vector3:Cross y CFrame.fromEulerAnglesYXZ).
- Suites: precisión 16/16 (grupo nuevo de arc lead), v16 4/4, teams 14.
- 71/71 compilan; bundle 70 archivos, sello
  `v28-20261016-arc-lead-hit-feedback`.
