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
