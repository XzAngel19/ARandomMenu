# Wurst

Menú para Roblox con módulos universales y para MM2, BedFight, TRS, VD y X2.
La versión de esta sesión está en la rama `arena/9492e6b6-arandommenu`; `main`
es independiente.

## Loader

```lua
getgenv().WURST_BRANCH = "arena/9492e6b6-arandommenu"
loadstring(game:HttpGet("https://raw.githubusercontent.com/XzAngel19/ARandomMenu/refs/heads/arena/9492e6b6-arandommenu/src/Wurst.lua"))()
```

## Shaders

`Render > Shaders` usa efectos **locales al cliente**, aplicados a **todo el
mapa**, no solo alrededor del jugador. No hay selector de `Look`; las opciones
son independientes: `Surface textures`, `Glass reflections`, `Fog`, `Rain`,
`Snow`, `Falling leaves`, `Dust motes`, `Wet surfaces` y `Water reflections`.

- **Barrido de todo el workspace.** El módulo recorre el mapa por partes con un
  presupuesto por frame y revisa las piezas ya conocidas en un ciclo ligero de
  2 s. Los topes de instancias son 1.600 texturas y 2.400 reflectancias en
  escritorio (900 / 1.200 en móvil); si se alcanzan, se avisa. Desde v178 se
  eliminó el espejo por `ViewportFrame` (`Floor reflections`): solo cubría el
  piso bajo el jugador, copiaba una escena incompleta y era la parte más cara de
  la tarjeta.
- **Materiales.** `Surface textures` añade detalle por cara a pisos y muros
  compatibles (hormigón, piedra, ladrillo, madera, mármol, arena, hielo, metal y
  tela), con densidad de texel proporcional a la pieza y offsets variables para
  que no se repita el patrón. Respeta los decals del juego por cara y no toca
  mallas, `SurfaceAppearance`, objetos móviles ni avatares.
- **Mojado.** `Wet surfaces` combina reflectancia 0,45 en el piso, un aumento de
  `EnvironmentSpecularScale` y un ajuste de color de lluvia: es lo único de
  "mojado" que se ve también en interiores oscuros, porque la reflectancia sola
  depende del skybox.
- **Clima.** Lluvia en dos capas (trazo y gotas cercanas), nieve con copos
  grandes y hojas que giran; nueve celdas que siguen a la cámara, 3.000
  partículas/s de presupuesto total y topes de emisor (320 en escritorio, 100 en
  móvil). Las celdas prueban el techo con `RespectCanCollide` y solo se apagan
  cuando hay geometría sólida encima.
- **Niebla.** Sube `Atmosphere.Density`/`Haze` (0,58/4,5) o acerca `FogEnd` a 110
  si el juego no tiene atmósfera, añade una capa de niebla local y una **estela**
  en los pies de cada personaje que camina (jugador y demás personas), para que
  la niebla parezca abrirse a su paso. No es niebla volumétrica: ni Roblox ni un
  script de cliente permiten desplazar un volumen real de niebla ni colisionar
  partículas, así que la estela es la aproximación honesta.

La tarjeta tiene un botón **`Diagnose`**: imprime y muestra lo que cada efecto
alcanzó en ese cliente (superficies escaneadas/texturizadas/reservadas por
decals, reflectancias, emisores del clima, estelas, Terrain y cámara). Úsalo
cuando un toggle parezca no hacer nada. Con la tarjeta apagada, un toggle hijo
avisa en vez de cambiar la casilla sin efecto.

Las imágenes se descargan bajo demanda; si la precarga local falla se intentan
recursos de Roblox como respaldo. Una precarga exitosa no garantiza que se
visualicen. La apariencia depende del juego, el executor y la calidad gráfica;
no puede garantizarse en todos los juegos. No se ha probado visualmente ni
medido el rendimiento en Roblox/Delta: texturas, partículas y sombras pueden ser
costosas. Si notas lag, apaga los efectos que no uses o revisa el contador del
menú. Fuentes, licencias y límites: `docs/third-party/shaders/README.md`.

Los **keybinds** funcionan aunque el juego ya haya usado la tecla (MM2 liga
varias): solo se bloquean al escribir en un `TextBox`, durante la captura de una
tecla o mientras el menú espera una tecla nueva. Al disparar un atajo con el
menú cerrado aparece un aviso (`Shaders on`/`Shaders off`) que confirma que el
atajo corrió.

Para comparar, enciende `Shaders` y espera unos segundos: el barrido necesita
recorrer el mapa. Pulsa `Diagnose` para ver qué encontró. Prueba `Fog` con
alguien caminando cerca, y `Rain` cerca de un techo para comprobar que la lluvia
se corta donde debe. Cierra el menú para comparar: al abrirlo se aplica un
desenfoque de la interfaz, independiente de Shaders.

## Desarrollo

`src/libraries/Manifest.lua` es el catálogo de módulos; `src/Wurst.lua` carga
el bundle y descarga los assets de la interfaz por separado. No edites
`src/libraries/bundle.lua` a mano. Tras cambiar fuentes, actualiza el
`SOURCE_STAMP` y ejecuta:

```bash
python3 tools/build_bundle.py --stamp <SOURCE_STAMP>
bash tools/validate.sh
```

Se conservan las pruebas, sus fixtures y la herramienta de Luau. La validación
es simulada: no sustituye probar Roblox, Delta ni el servidor. Los detalles y
contratos del proyecto están en `RESUME.md`.
