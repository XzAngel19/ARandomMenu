# Wurst v21.1 — mejoras nuevas, identidad clásica

Build: **`v21.1-20261014-wurst-classic`**. Rama: `arena/d83a806d-arandommenu`.

Ajuste visual basado en la referencia Wurst Client 7.47 proporcionada por el usuario. No es una copia pixel-perfect ni una captura verificada dentro de Roblox.

## Apariencia

- Fondo gris **#404040**, acento/bordes **#101010** y texto **#F0F0F0**.
- Funciones activadas en verde vivo **#00FF00**; flechas y chinchetas de píxeles en verde **#00CC00**. Se conservan la cabecera/logo y las ventanas por categoría existentes.
- Opacidad inicial del 75 %, sin añadir blur, partículas ni efectos animados.
- Filas de escritorio más compactas: 24 px con 2 px de separación. En móvil se conservan filas de 28 px.
- Selectores de Mode/perfil/política conservados, ahora rectangulares, con borde fino y selección verde. Texto oscuro en la selección para mejorar su lectura. Filas de selector reducidas de 54 a 46 px.
- La gráfica de red utiliza verde, no el acento negro, para mantener visibles las muestras.

## Configuración existente

Los perfiles nuevos usan el aspecto clásico. Si aplicaste la paleta Midnight completa de v21, se reconoce por los cuatro colores exactos y se migra una sola vez; su opacidad de 0,82 pasa a 0,75. Una opacidad personalizada se conserva.

Las paletas personalizadas, incompletas o mezcladas **no se sobrescriben**. Puedes aplicar **Settings → UI → Rainbow OFF → Wurst Classic preset**. Este botón cambia los cuatro colores; no modifica tus tamaños, opacidad personalizada ni ajustes de armas.

## Qué no cambia

Predicción Experimental, perfiles Old/Actual, Silent AIM, Knife, estimador de ping, políticas de red, límites de trabajo, Advanced y panel de estado permanecen como en [v21](MM2-v21-fast-projections.md). No se modificó ningún archivo de `src/games/MM2/` en esta revisión.

Para cargar: **Destruct** en la instancia anterior y recarga la rama con el loader habitual:

```lua
getgenv().WURST_BRANCH = "arena/d83a806d-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/d83a806d-arandommenu/src/Wurst.lua?v=" .. tostring(os.time()), true))()
```

## Validación

- 64 grupos MM2: todos pasan, incluidos selección/persistencia, Advanced y ciclo de vida del panel.
- 4 grupos nuevos de paleta/migración: valores clásicos reales, migración idempotente, conservación de paletas personalizadas y opacidad.
- 8 tests del analizador JSON y 14 comprobaciones de equipos.
- 70 archivos Lua compilados con Luau 0.732; bundle de 68 entradas regenerado y verificado.

**Pendiente:** comprobación visual dentro de Roblox. Los tests de widgets usan servicios simulados; no certifican apariencia pixel-perfect ni FPS reales.
