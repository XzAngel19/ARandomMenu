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
