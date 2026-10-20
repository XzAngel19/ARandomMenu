# v39 — Propiedad de módulos y controles coherentes

Stamp: `v39-20261016-combat-ownership`.

## Árbol visible en MM2

- Combat
  - SilentAIM
    - Weapon: Gun (información, no selector de una sola opción)
    - Auto Shoot (primer control, visible en ambos métodos)
    - Aim method: Prediction / Silent AIM
    - Target y resto de controles actuales de Gun
  - KillAura
    - Knife Aura
    - Aura Range (solo con Knife Aura)
    - Knife Throw
- Exploits > Speed
  - Sprint: botón HOLD + keybind, no checkbox

Se eliminan las tarjetas separadas Shoot y Knife. Auto Shoot sigue siendo un
control de Gun dentro de SilentAIM, no otra tarjeta Combat. Gun es una sección
porque todavía no hay otra arma que justifique un selector de modo de arma.
El método de apuntado sí tiene dos comportamientos distintos y se conserva.

## Sprint: respuesta explícita del usuario

Mantener tecla/botón, no alternar estado. Funciona con Speed APAGADO también.

- Framework añade acciones Hold con OnRelease obligatorio para esta acción;
  el widget no conecta MouseButton1Click para ejecutar un toggle al soltar.
- Teclado, botón de menú y acción táctil usan press/release. Soltar fuera del
  botón y perder foco liberan la acción. Soltar otro dedo no cancela Sprint.
- Presión simultánea de botón y tecla se mantiene hasta liberar ambos.
- No se lee ni guarda el antiguo booleano Universal.Speed.Sprint.
- Se conserva el keybind existente, sin asignar uno por defecto.
- Speed sigue siendo el único dueño de capturar/escribir/restaurar WalkSpeed.
  Su mismo frame path atiende el Sprint independiente mientras Speed está OFF;
  no se enciende Speed de fondo ni se añaden dos escritores de WalkSpeed.
- Soltar restaura el Speed normal si está ON o la velocidad original si está
  OFF. Cambiar Speed ON/OFF durante el hold conserva esa regla. Respawn y
  unload limpian estela/velocidad y desconectan el loop independiente.

## KillAura: una ruta de ataque, no dos

MM2 adjunta un adaptador al KillAura universal existente. Cuando ese adaptador
está activo, el controlador genérico retorna antes de crear sus loops/watchers.
Por tanto no compite un Swing genérico con HandleTouched/KnifeThrown de MM2.

Los controles genéricos que no aplica ese controlador (FOV, Rotation, Weapons,
etc.) no se muestran en MM2. Framework vuelve a aplicar la disponibilidad junto
con las reglas Show, evitando que reaparezcan al cambiar otra opción.

KillAura es el master de ambos ataques. OFF detiene controladores y cancela
poses pendientes SIN borrar la selección de Knife Aura/Knife Throw. ON reanuda
los ataques seleccionados. En perfiles nuevos Knife Aura viene seleccionado;
las preferencias existentes se respetan. Fuera de MM2 se conserva KillAura
universal. Al retirar el adaptador no se exponen controles MM2 obsoletos.

## Gun / SilentAIM

- Se conserva el identificador interno MM2.Shoot para que ajustes, activación y
  favoritos existentes no pierdan su identidad al renombrar la tarjeta.
- Auto Shoot se encuentra arriba, no enterrado al final de los ajustes.
- El control puede restaurar su valor al crearse, pero el loop solo se arma
  cuando todos los ajustes guardados (método, target, lead, etc.) terminaron de
  restaurarse. Así el primer disparo no usa accidentalmente el modo por defecto.
- Después de inicializar sigue intentando por frame, sin nueva espera por
  confianza/distancia ni cambios de fórmulas. El Gun manual conserva su tecla.
- El antiguo valor Mode se migra a Aim method; ambos métodos reales se mantienen.

## Revisión de redundancias y semántica

- Un botón de acción no persiste un booleano; un toggle sí tiene estado.
- Un hold tiene liberación, no una segunda pulsación para apagarlo.
- Una opción no pasa por encima del master de su módulo (salvo Sprint, cuya
  independencia fue solicitada explícitamente).
- Acciones y toggles ocultos por modo/juego ya no se ejecutan por su shortcut.
  Esto no bloquea opciones por tener el menú cerrado: se comprueba la fila,
  no la visibilidad de todos sus ancestros.
- No se duplica un controlador genérico y uno de juego detrás de la misma UI.
- La auditoría de nombres de filas duplicadas sigue cubriendo todos los módulos
  cargados; ahora además hay asserts de tipo, jerarquía y disponibilidad real.

## Compatibilidad

Se migran una vez los estados Knife Aura/Throw, alcance y bindings desde
MM2.Knife a Universal.KillAura, sin sobrescribir valores nuevos ya guardados.
Los viejos controles/valores no se convierten en otra tarjeta escondida.

## Verificación

18 suites Python/Luau, 77 fuentes compiladas, bundle de 68 fuentes actualizado,
boot completo failures=0 y git diff --check. El boot prueba la UI/control real
con servicios mock: Sprint hold sin Speed, mouse/touch/tecla/foco, Auto visible,
master KillAura, preferencias de ataques retenidas, ausencia de tarjetas viejas,
controles genéricos no disponibles y ausencia de loop genérico paralelo.

Comparación textual con v38: computeGunAim y predictAim no cambian. El baseline
archivado v35 sigue intacto. Esta run NO reemplaza la predicción ni afirma una
accuracy online o prueba física en móvil/Roblox real.
