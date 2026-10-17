# v43 — Chams por roles, Nametags y HP separados

Stamp: `v43-20261016-render-roles`.

## Chams / MM2

- Cinco roles configurables: **Murderer, Sheriff, Hero, Innocent y Dead**.
  Cada uno tiene su filtro y su color, además del interruptor Role colours.
- La paleta pertenece al módulo: cambiar Chams no cambia PlayerESP, Nametags,
  ni las constantes del proveedor MM2. Los ajustes se guardan con las opciones
  normales del menú.
- MM2 reemplaza controles de equipos irrelevantes por roles. En juegos sin
  proveedor siguen existiendo Teammates/Team colours, sin filas falsas de MM2.
- Dead también puede resaltar el cadáver actual si aún existe en
  Player.Character. No clona ni reconstruye avatares eliminados.
- Chams solo administra highlights y su icono de perk MM2; ya no contiene
  Nametags/Nametag distance ni indicadores de vida. Se limpia el icono si el
  perk cambia a uno desconocido.

## Nametags — módulo independiente

Tipografía nativa GothamMedium, contorno oscuro, placa con borde discreto,
segunda línea para rol/cuenta/distancia/herramienta, tamaño configurable y
colores de rol propios. Puede mostrar nombre de cuenta o display name, sin
repetirlos si son iguales. Distancias rotuladas en **studs**, no falsos metros.

El texto conserva Unicode y se dibuja sin RichText: nombres con `<...>` no se
interpretan como formato. Se mide con TextService y se cachea por texto/tamaño/
ancho de viewport; etiquetas largas se truncan y ajustan al ancho del móvil.
No se olvida el ancho explícito en los frames posteriores. Los objetivos fuera
de pantalla, fuera de distancia, eliminados o tapados (si Through walls está
OFF) sueltan sus dibujos; no deja nombres pegados a los bordes.

## HP — módulo independiente

- **Players**: barras de vida con lectura numérica opcional, distancia máxima
  y Through walls; no requiere PlayerESP ni Chams.
- **Self HP**: HUD inferior con **❤️**, salud actual/máxima, estado
  Healthy/Injured/Critical/Respawning y barra con estela de daño reciente.
- Escala configurable y limitada al ancho disponible en pantallas pequeñas.
  Puede funcionar solo para uno mismo desactivando Players.
- Relee el Humanoid actual: muerte, ausencia de personaje y nuevo MaxHealth no
  dejan la vida anterior. Se protegen divisiones inválidas y valores no finitos.
  OFF/unload retira sus dibujos y observadores.

Se eliminan los controles/dibujos duplicados Name tags, Health bar y Health
text de PlayerESP. Distancia y herramienta del jugador viven en Nametags.
No se crea una tarjeta adicional “Health Indicators”. NPCESP e ItemESP mantienen
sus etiquetas específicas de NPCs/objetos, no son los nametags de jugadores.

## Mejoras de render y coherencia

- Boxes Full/Corner con contorno oscuro detrás del color, reutilizando frames.
  OFF y cambio de modo ocultan también el contorno; esquinas limitadas al
  tamaño de cajas pequeñas para evitar picos y cruces.
- Barras más legibles (4 px), fondo de contraste y transición rojo/ámbar/verde.
- Labels con fuente explícita, stroke y borde de placa. Fill OFF ya no crea
  un Frame inútil por objetivo.
- PlayerESP universal usa TeamColor real, no rojo para todos los enemigos.
  Los controles ocultos de equipos no siguen afectando MM2 por detrás.
- ESP oculta la capa si no hay cámara y desconecta render/eventos al destruirse.
  Conserva los extras de otros juegos; se libera su listener del bridge.
- Orden explícito de Render: ItemESP, PlayerESP, Chams, Nametags, HP, Arrows,
  NPCESP, FOV, Fullbright, Time Changer, X-Ray y Zoom.
- Se migran overlays que estaban activos y las preferencias de texto/paleta;
  una elección explícita del nuevo módulo tiene prioridad.

## GameRoles para futuros juegos

API documentada en [GAME-ROLES.md](GAME-ROLES.md). Se usa el mismo servicio en
PlayerESP, Chams, Nametags y, sin paleta, HP. Admite registro tardío, cambio de
proveedor y cleanup con propiedad: limpiar el juego anterior no borra uno nuevo.

## Referencia revisada y verificación

Se consultó `7GrandDadPGN/VapeV4ForRoblox`, en particular:

- `src/guis/new/base.lua`, blob `bc6cf6b1b1162939112be4544213428f26ed8ccd`:
  medición de texto, fuentes y capas de GUI.
- `src/games/universal - base/Render/NameTags.lua`, blob
  `71b960462244dc2b1fd3a14f2455571273876219`: caché de texto y legibilidad.
- `.../Render/Health.lua`, blob `d1a7f342ff52c50cbd6b311550f5c91d0580b75f`:
  indicador propio con corazón y proporción de vida.
- `.../Render/ESP.lua`, blob `8a2909db01db981c4fe06c0f1b5da68764b08dc2`, y
  `.../Render/Chams.lua`, blob `17fae5f33c0f9e5ce5db011e39fc90f3ca3f3222`:
  separación de overlays, colores y propiedad de recursos.

Se tomó como referencia de diseño, sin incorporar sus fuentes, assets,
Drawing API ni dependencias al runtime. La implementación usa nuestros
servicios Entity/Render/Framework y no necesita descargar otro menú.

Validación: suites reales bajo Luau, prueba integrada nueva de los seis
módulos/servicios de render, full boot con proveedores MM2/futuros y compilación.
No se probó en un cliente Roblox vivo: apariencia final y rendimiento en el
executor/dispositivo del usuario siguen requiriendo comprobación allí.

Resultado final: **25 suites aprobadas**, **72 fuentes Lua compiladas**,
bundle de **70 fuentes** sincronizado y full boot sin módulos fallidos.
Los tests de predicción/menú/FPS de v42 siguen pasando; no se modificaron
las fórmulas de Gun/Knife en esta actualización.
