# v48 — Render, Markers y controles del dock

## Render

- **Nametags se conserva sin cambios** respecto a v47: mismo texto plano, fondo, opciones y distancia desactivada por defecto.
- **Self HP** deja de ser una tarjeta con fondo, vida máxima y barras de daño. Ahora es texto Arial 18 transparente con vida y corazón (`100 ❤️`), tomando como referencia Health de VapeV4. Se oculta el texto al morir o no tener personaje. Posición Center por defecto, Bottom opcional y escala ajustable.
- HP de jugadores: pista negra de 3 px y relleno de 1 px, colores de salud más vivos. Texto de vida opcional, desactivado por defecto, sin placa.
- Etiquetas compartidas de ItemESP, NPCESP, Markers y demás consumidores de Render: Arial, fondo negro plano semitransparente, sin tarjeta redondeada ni borde decorativo. Las barras compartidas siguen el mismo estilo fino. No se reemplaza el menú Wurst ni se cambia la implementación independiente de Nametags.
- Distancias de ItemESP y Arrows usan `[N]`, en unidades del mundo, sin llamarlas metros.
- Se mantienen filtros de equipos, paletas de roles, Chams/Highlights y geometría de PlayerESP; no se inventan opciones de Vape que no correspondan a esos módulos.

## Markers

Orden: Name, Save here, Touch, Remove named place, Places, coordenadas manuales y apariencia.

- **Save here** guarda siempre la posición actual del personaje.
- **Touch** permite hacer clic o tocar una superficie del mundo para guardar un punto. Funciona también con Markers apagado; encenderlo muestra los puntos seleccionados. Si no hay nombre, genera `Point N`.
- Ignora entradas consumidas por la interfaz y mientras se escribe; Escape o pulsar Touch de nuevo cancela la selección. El rayo ignora al personaje local y busca una superficie colisionable, hasta 5000 unidades. Un toque sin superficie no guarda un punto falso.
- **Manual coordinates** muestra Coordinates con la pista real **`x, y, z`**, junto con **Save coordinates** separado. El Framework transmite ahora Placeholder al TextBox nativo.
- Se conserva persistencia por juego, selección de lugares y validación: hasta 128 puntos, nombres nuevos de hasta 48 caracteres y coordenadas finitas dentro del límite admitido.

## X-Ray

Referencia real: el módulo Xray de VapeV4 modifica `LocalTransparencyModifier` a 0.5 y permite mantener visibles nombres de partes. Se conserva esa idea, ampliándola sin copiar su restauración incondicional a cero.

Opciones, en orden:

1. **Scope**: All map, Walls o Named parts.
2. **Transparency**, predeterminada 0.5.
3. **Part names**, visible en Named parts; nombres exactos separados por comas.
4. **Keep visible**, lista de nombres que nunca se desvanecen, inspirada en Vape.
5. **Keep floors**, **Collidable only**, **Include unanchored**.
6. **Limit range** y **Range**, predeterminada 250.

Las listas no distinguen mayúsculas y minúsculas. Walls y Keep floors usan la forma de las partes como heurística, no reconocimiento semántico del mapa. Excluye personajes, herramientas, plataforma Anti Void y objetos del menú identificados por el host.

La actualización normal procesa como máximo 200 candidatos por frame, con una pausa de 0.2 s entre recorridos completos. Admite partes que llegan por streaming y restaura partes retiradas temporalmente del árbol. La enumeración inicial y la restauración al cambiar opciones/apagar no se dividen en esos lotes.

Cada parte conserva su valor anterior y la última escritura propia: se respeta un cambio externo posterior al apagar, y se toma como nueva base si se detecta durante una actualización. No se hace más opaca una parte que ya tenía una transparencia local mayor.

## Dock

- **Oculto por defecto en PC**, también con configuración nueva. Una elección previa explícita de Show dock se respeta. En dispositivos principalmente táctiles se conserva el dock accesible.
- **UI Settings → Move dock** muestra temporalmente un control para arrastrarlo con ratón o touch, incluso si está oculto.
- Soltar guarda; Enter también guarda. Escape, pérdida de foco o cerrar el menú cancelan y restauran la posición previa.
- Al terminar vuelve a la visibilidad configurada, sin activar Show dock. Posición normalizada persistente, limitada al viewport y reajustada al cambiar el tamaño. Se limpian conexiones y controles temporales.

## Selectores Wurst

ChoiceList y MultiList —incluido Spectate Player de FreeCam— conservan su estructura nativa, con transparencia 0.22 y borde más suave. Reutilizan el BlurEffect existente a tamaño 6 mientras están abiertos; al cerrar vuelve al comportamiento normal del menú (14), sin crear efectos adicionales.

**El BlurEffect de Roblox desenfoca la escena 3D, no las interfaces GUI que estén detrás del selector.** No se afirma que sea un backdrop blur de GUI.

## Referencias y verificación

Fuentes consultadas en `7GrandDadPGN/VapeV4ForRoblox`:

- Health: blob `d1a7f342ff52c50cbd6b311550f5c91d0580b75f`.
- Xray: blob `b8b48e9a7db750b6916fe1eed8313741080b38b0`.
- ESP: blob `8a2909db01db981c4fe06c0f1b5da68764b08dc2`.

Resultados locales:

- **33 suites Python/Luau pasan**, incluidas nuevas pruebas del controlador real del dock y del módulo real X-Ray.
- Dock: mouse/touch, límites, guardado/recarga, resize, Escape, Enter, foco, cierre del menú, visibilidad temporal y limpieza.
- X-Ray: filtros, listas, exclusiones, streaming, partes sin padre, cambios externos, lotes y restauración.
- Render: Self HP de texto, muerte/respawn, posiciones, barras finas y regresiones de Nametags/roles.
- Markers: persistencia, coordenadas separadas, placeholder y selección Touch, entradas GUI ignoradas y cancelación.
- Arranque del bundle: **`failures=0` y `[HARNESS] done`**, con controles nativos de selectores y comprobación del blur. Repetido con perfil sin Show dock guardado: **`uiShowDock=false`**.
- **73 fuentes Lua compilan**; bundle de **71 archivos** sincronizado con `v48-20261017-render`.

No se ejecutó Roblox vivo ni se obtuvieron capturas nuevas. Estas pruebas no garantizan apariencia idéntica en todos los dispositivos, rendimiento en mapas concretos ni comportamiento del servidor/anticheat. No se modificaron los cálculos ni las protecciones de disparo de v47.
