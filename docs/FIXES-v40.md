# v40 — SilentAIM, Teleport y optimización visual ampliada

Stamp: `v40-20261016-visual-controls`.

## Combat

SilentAIM contiene **Auto Shoot como primer control y Knife Throw como segundo**,
antes de los ajustes de Gun. La tarjeta sigue usando `MM2.Shoot` internamente
para conservar configuración y tecla manual de Gun. La información de arma del
helper `addInformationOption` era solo tooltip, no una fila visible; no se usa
como sustituto de una jerarquía comprobable. Se reordena la fila real de Knife
Throw y su array de opciones, no únicamente el registro.

- Knife Throw depende del master SilentAIM, NO de KillAura. Apagar SilentAIM
  desconecta su loop y cancela la animación pendiente, conservando su selección.
- KillAura contiene solo Knife Aura y Aura Range. Cambiar ese master no arranca
  ni detiene Knife Throw. Sigue sin ejecutar el ataque genérico en paralelo.
- Se migran selección y binding de Knife Throw desde KillAura v39 o Knife v38.
  Un false explícito o un binding nuevo existente no se sobrescriben.
- Ambos automáticos requieren el arma correspondiente equipada; no compiten
  intentando equiparla. El disparo manual de Gun conserva su autoequip explícito.
- Knife Throw conserva su preset único, animación y LOS; Gun conserva sus
  métodos. No se cambian `computeGunAim`, `predictAim` ni el baseline archivado.

## Utilities → Teleport

Una única tarjeta sustituye Click Teleport y la anterior tarjeta MM2 Teleport.
El ID universal anterior permanece para preservar ajustes y binding.

En MM2, Destination se inicia en **MM2** (migración una vez); después se respeta
la selección guardada por el usuario. MM2 target permite Map, Lobby, Player o
Gun; la acción principal ejecuta ese destino. Map es el destino MM2 inicial.

Se mantienen Auto Get Gun, su demora, el Get Gun key configurable y su botón
móvil. Se migran los valores previos desde MM2.Teleport. Los modos universales
Tap point, jugadores, Item, Waypoint y Last position permanecen disponibles.
Los controles incompatibles se ocultan al cambiar Destination. Cambiarlo también
cancela un Tap point armado para evitar que un click posterior use el modo viejo.

## Improve FPS: 11 opciones nuevas (15 en total)

Se mantienen Remove textures, Disable particles, Disable shadows y Simple
materials. Remove textures ahora cubre también SpecialMesh.TextureId.
Disable shadows incluye GlobalShadows además de CastShadow por pieza.

Opciones adicionales, **todas apagadas por defecto**:

| Control | Cambios visuales |
| --- | --- |
| Lowest render quality | Solicita QualityLevel.Level01 donde el cliente permita escribirlo. |
| Simple lighting | Desactiva reflexión difusa/especular del entorno. |
| Disable local lights | Desactiva PointLight, SpotLight y SurfaceLight; puede oscurecer el mapa. |
| Simplify terrain | Desactiva decoración, oleaje y reflejos de agua donde sean modificables. |
| Disable post effects | Desactiva bloom, blur (incluido el del menú), DOF, corrección de color y rayos solares. |
| Simplify game UI | Desactiva UIStroke, UIGradient y previews ViewportFrame del juego. |
| Hide world UI | Oculta BillboardGui y SurfaceGui; puede ocultar información del juego. |
| Hide game UI | Oculta ScreenGuis del juego, incluidos HUD/objetivos: opción agresiva. |
| Hide Roblox panels | Oculta lista de jugadores, mochila, chat y emotes mediante StarterGui. |
| Low detail meshes | Solicita RenderFidelity.Performance para mallas/uniones. |
| Hide distant scenery | Oculta localmente piezas estáticas del mapa a más de 350 studs; opción agresiva. |

### Seguridad, propiedad y coste

- No se destruyen assets ni se desactivan scripts del juego. Las optimizaciones
  nuevas no cambian CanCollide, CFrame o CollisionFidelity. Simple materials
  conserva su cambio de Material existente (y lo restaura al apagar).
- El menú propio, TouchGui estándar y sus descendientes se protegen del recorte
  de GUI. Hide Roblox panels no usa CoreGuiType.All ni desactiva Health.
  Las GUI móviles personalizadas del juego pueden quedar ocultas con Hide game UI;
  por eso esta opción es explícitamente agresiva y viene OFF.
- No se escanea ni altera arbitrariamente CoreGui: sus paneles públicos se
  gestionan con StarterGui y sus estados originales se conservan por separado.
- Cada propiedad modificada conserva su valor inicial, incluidos false y cero.
  OFF/cambio de opciones/unload restauran snapshots; instancias separadas del
  árbol también se restauran. Los objetos realmente destruidos se expulsan del
  cache y desconectan su watcher para no acumular basura durante partidas largas.
- Se observan nuevos descendientes en Workspace, Lighting y PlayerGui.
  Callbacks diferidos de objetos ya removidos no adquieren propiedad nueva.
- El escaneo inicial cede cada 250 objetos y usa generaciones para invalidar
  workers viejos. Las optimizaciones estáticas no hacen un escaneo por frame.
- El culling opcional actualiza por lotes de hasta 200 piezas por frame, con
  pausas entre pasadas. No toca personajes, accesorios ni herramientas, restaura
  piezas cercanas o que dejan de ser estáticas y no cambia sus colisiones.
- Propiedades no soportadas/protegidas se intentan con pcall independiente: no
  abortan las demás optimizaciones. No se promete que cada API sea escribible
  en todos los clientes/executors ni una ganancia fija de FPS.

## Role Tags

Se elimina el módulo y su carga/bundle: no queda una tarjeta oculta ni su loop
funcionando en segundo plano. No se elimina la información de roles del ESP ni
la calibración MM2, que son funcionalidades diferentes.

## Verificación

- 19 suites Python/Luau aprobadas.
- 76 fuentes compiladas; bundle actual de 67 fuentes; boot completo failures=0.
- Boot con UI real sobre mocks: una sola tarjeta Teleport, MM2 por defecto,
  controles condicionales, Knife Throw en segunda fila de SilentAIM y no en
  KillAura, apagado del master correcto y Role Tags ausente.
- FPS: las 11 opciones nuevas ejecutadas contra el módulo real; valores originales
  restaurados, GUI propia/táctil protegida, paneles previamente desactivados aún
  OFF, efectos nuevos cubiertos, culling cercano/dinámico, limpieza al destruir,
  listeners desconectados y workers antiguos invalidados.
- Teleport: ejecución de Map/Lobby/Player/Gun, recogida temporal y automática,
  migración de tecla/demora y dispatcher/unload.
- Predicción comparada textualmente con v39 y baseline archivado sin cambios.

Son pruebas automatizadas con servicios mock, no una medición de FPS ni una
validación dentro de Roblox real en PC/móvil. La ganancia depende de CPU/GPU,
resolución, mapa y configuración; ocultar GUI no detiene sus scripts de fondo.
