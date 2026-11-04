# v178 — Todo el mapa, no solo donde estás

## Qué pidió el usuario

Captura de MM2 con el panel `Shaders` y el `Diagnose` v177 a la vista:

```
surfaces:  on · scanned=124235 textured=187 reservedByDecalOrMesh=2 noMaterialStyle=118683 cap=600
reflectance: wet=on glass=on parts=392/1200
mirror: floor=Workspace.Barn.Base_Part gui=true sceneParts=23 actors=1 candidates=187
weather: folder=true cells=9 emitters=36 on=0 sheltered=9 kinds=Rain/Snow/Falling leaves wakes=—
water:   on · terrain=true reflectance=1
```

Sus palabras: los efectos «se ven como una pegatina así bien barata»; quiere que
se apliquen **a todo el mapa**, que la niebla se **abra al caminar** (y que pase
con todas las personas), y **sin lag ni más CPU**. Y autorizó quitar lo que no se
pueda hacer mejor, mencionando `Floor reflections`.

## Causas que el propio diagnóstico delató

1. **`on=0` con 36 emisores.** Bug de v176/v177: los emisores se creaban con
   `Enabled = false` mientras la celda arrancaba con `applied = false`
   («muestreada y abierta»). La primera muestra de cielo abierto comparaba
   `false ~= false` y no escribía nada: la lluvia, la nieve y las hojas se
   quedaban apagadas toda la partida salvo que la celda hubiera empezado tapada.
   Ahora `applied` empieza en `nil` (desconocido) y los emisores nacen visibles.
2. **`noMaterialStyle = 118.683`.** El mapa no es Wood ni Marble: es plástico,
   metal y materiales que no estaban mapeados. Se añadieron `metal` y `fabric` y,
   para cualquier piso opaco de 10×10 studs en adelante, detalle `concrete`
   aunque su material no esté en la tabla.
3. **`textured = 187` de 600.** No era un problema de presupuesto sino de
   cobertura de caras: los muros solo se texturizaban si eran `brick` o
   `concrete`. Ahora cualquier estilo texturiza muros (ambas parejas de caras
   según el eje largo).
4. **Pegatinas.** Dos causas reales: `StudsPerTileU/V` fijos (12×6 studs) sobre
   piezas de 200 studs o de 3 studs, y hojas con sprite estático sin giro. Ahora
   el tiling se deriva del tamaño de la pieza, con offsets por posición, y las
   hojas giran (`RotSpeed ±240`), son más grandes y llevan `LightEmission` 0,45.
5. **`wet` invisible.** `Reflectance` solo refleja el skybox: en un interior
   oscuro no hay nada que reflejar. `Wet surfaces` ahora combina reflectancia
   0,45, `EnvironmentSpecularScale ≥ 0,95` y un `ColorCorrectionEffect` propio
   (`ARMShaderWet`) de lluvia. Eso sí se ve en cualquier mapa y cuesta cero por
   frame.
6. **`mirror` con 23 partes copiadas.** El `ViewportFrame` solo cubría el piso
   bajo el jugador, copiaba una escena parcial y era la parte más cara de la
   tarjeta. **Se eliminó** con su biblioteca y sus pruebas (decisión autorizada
   por el usuario).
7. **CPU.** El barrido completo se reiniciaba cada 2 s sobre 124.235 partes. Con
   presupuesto de 4 trabajos por frame eso nunca termina de recorrer el mapa y es
   un impuesto permanente. Ahora el barrido completo es una red de seguridad de
   30 s; lo cotidiano es un ciclo de 2 s sobre las piezas **ya conocidas**
   (8 por tick), más cola de reintento con espera de 0,5 s para las texturas que
   fallan (antes solo se reintentaban en el siguiente barrido).

## Niebla que se abre al caminar

Roblox no tiene niebla volumétrica desplazable desde un script y las partículas
no colisionan, así que la niebla no se puede «empujar» de verdad. La
aproximación implementada es una **estela**: cada personaje que camina (jugador
local y demás personas, hasta 8) tiene un emisor de niebla pegado a los pies con
`Rate = 0` que emite 2 puffs cada 1,2 studs recorridos. Quieto no cuesta nada;
al caminar, la niebla parece desprenderse y abrirse a su paso. La niebla de
cámara también subió a `Rate 18`, `Size 34`, 0,82 de transparencia.

## Cobertura y presupuestos

| Elemento | v177 | v178 |
|---|---|---|
| Cobertura de superficies | incremental, tope 600 texturas / 1.200 reflectancias | tope **1.600 / 2.400** escritorio, 900 / 1.200 móvil |
| Estilos de material | concrete, wood, brick, grass, marble, stone, sand, ice | + **metal, fabric**, y `concrete` para cualquier piso opaco ≥10×10 |
| Tiling | fijo 12×6 | proporcional a la pieza (2–16 studs) + offsets |
| Muros | solo brick/concrete | cualquier estilo mapeado |
| Espejo de piso | 3 ViewportFrames | **eliminado** |
| Barrido completo | cada 2 s | cada **30 s** + ciclo de conocidos 2 s |
| Hojas | 12/s, sprite estático | **18/s** (9 móvil), giro, 1,9 studs, 9 s |
| Niebla | cámara 14/s | cámara **18/s** + estela por personaje |
| Clima total | 2.604 partículas/s | 2.658 partículas/s (tope 3.000) |

## Verificación

`bash tools/validate.sh` **VERDE**: 116 suites (una menos: se borró la de la
biblioteca del espejo), boot `failures=0`, arranque silencioso, 90 call sites,
menú 50 (audit) / 49 (release).

Pruebas nuevas o reescritas en `tools/test_shaders.py`:

- los emisores nacen visibles y una celda nunca muestreada no los deja apagados;
- hojas con giro, tamaño y luz;
- estela de niebla: aparece con un personaje, emite al moverse, deja de emitir
  quieta y se limpia al apagar `Fog`;
- `Wet surfaces` sube el especular, crea `ARMShaderWet` y restaura ambos;
- topes 1.600/2.400 con aviso único;
- `Floor reflections` ya no existe y no se crea ningún contenedor de espejo;
- el mock de `Instance` ahora emite `DescendantAdded`/`DescendantRemoving`, como
  Roblox, para probar el descubrimiento de partes sin depender del barrido.

## Límites honestos (lo que no se puede dar)

- **Nada de esto es PBR.** Las `Texture` son mapas de color planos; no hay
  normal map ni roughness por pieza en el mapa de otro juego. Un piso con
  detalle seguirá viéndose como una foto pegada si se mira de cerca.
- **No hay reflejos reales del mapa.** Sin SSR ni espejo global; el espejo se
  quitó y lo que queda es brillo ambiental (skybox) más el grado de lluvia.
- **La niebla no es volumétrica.** La estela es una aproximación, no
  desplazamiento de un volumen.
- **El clima tarda.** El barrido necesita segundos; el menú lo dice con
  `Diagnose`.
- Sin verificar en vivo en MM2 con esta build: aspecto de hojas, estela de niebla
  y FPS móvil con todo encendido.
