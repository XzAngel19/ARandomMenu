# v177 — Efectos visibles, o una explicación en el cliente

## Contexto

Con una captura de **MM2** (mapa de granja de Halloween, de noche) el usuario
reportó que estos toggles, con el interruptor en ON, no producían nada visible:

`Floor reflections`, `Surface textures`, `Glass reflections`, `Falling leaves`,
`Dust motes`, `Wet surfaces`, `Water reflections`.

La regla que se aplicó es la del usuario: **un toggle debe verse o decir por qué
no aplica**. Este documento lista qué cambió y qué se puede demostrar sin el
juego delante. Cómo se ve en Roblox/Delta **sigue sin verificarse aquí**.

## Causas demostrables

1. **Toggle hijo con la tarjeta apagada.** El callback de cada opción cambiaba
   su casilla y no hacía nada si `Shaders` estaba OFF. Se veía como un efecto
   roto. Ahora avisa una vez y solo después de que el usuario haya encendido la
   tarjeta alguna vez (la restauración de valores guardados al construir la UI no
   dispara avisos).
2. **Hojas y polvo por debajo del umbral de lo visible.** Hojas a **3/s**, polvo
   a **12/s con 0,35 studs** de tamaño: en una escena nocturna eso es
   literalmente invisible. Hojas: `12/s` (6/s en móvil), `Size 1,6`,
   `Lifetime 8`, `Transparency 0,05`, `LightEmission 0,4`. Polvo: `30/s`,
   `Size 0,55`, `Lifetime 6`, `Transparency 0,26`, caja `26×8×26` con
   `Acceleration` para que no se quede quieto.
3. **Reflejos demasiado suaves para una escena oscura.** `Glass reflections`
   pasó de `Reflectance 0,36` a **0,5**; `Wet surfaces` de `0,16` a **0,32**;
   `Water reflections` de `0,55` a **0,75**.
4. **Texturas casi invisibles.** El `Texture` de superficie estaba a
   `Transparency 0,55`; ahora **0,42**. Sigue tiñéndose con `part.Color` en vez
   de aclarar hacia blanco.
5. **Cobertura de materiales.** MM2 usa piedra, arena y hielo, no solo Wood o
   Marble. `MATERIAL_STYLES` añade `stone` (Cobblestone, Slate, Rock, Basalt,
   Sandstone, Limestone, Granite, Pebble), `sand` (Sand, Ground, Mud) e `ice`
   (Ice, Glacier) reutilizando los álbedos ya descargados con su propio tiling
   (8×4, 16×8, 8×8). Se construye con `pcall` sobre `Enum.Material`, así que un
   cliente sin ese material simplemente no lo mapea.
6. **`Water reflections` sin Terrain.** El mapa de granja no tiene Terrain: el
   toggle no podía hacer nada. Ahora lo dice (`card:Notify`) en vez de quedarse
   callado.

## Diagnóstico en el cliente (lo que hacía falta para dejar de adivinar)

- Botón **`Diagnose`** al final de la tarjeta `Shaders`. Imprime y muestra:
  stamp, estado de los post-efectos, superficies escaneadas/texturizadas,
  cuántas quedaron reservadas por decals o mallas, cuántas no tenían estilo de
  material, cuántas tienen reflectancia, el estado del espejo
  (`floor`, `gui`, `sceneParts`, `actors`, `candidates`) y el clima
  (`cells`, `emitters`, `on`, `covered`), más Terrain y cámara/personaje.
- `ShaderReflection` expone `session:Describe()` con esos datos; al parar la
  sesión limpia también `currentFloor`, así que una sesión parada se describe
  como parada y sin suelo.
- La línea de estado de la tarjeta ahora cuenta **todas** las familias
  (`Floor · Surfaces · Glass · Wet · Water · Fog · Rain · Snow · Leaves ·
  Dust`), con tope de cuatro y un resto `+N`, en vez de solo el clima.

## Verificación

- `bash tools/validate.sh` **VERDE**: 117 suites, boot `failures=0`, arranque
  silencioso (ningún toast al inyectar), 90 call sites, menú 50 (audit) / 49
  (release).
- `tools/test_shaders.py`: toggles nuevos, aviso con la tarjeta apagada,
  restauración guardada sin avisos, status con tope `+4`, `Diagnose` con sus
  campos, hoja 12/s, polvo 30/s, glass 0,5, wet 0,32, agua 0,75,
  textura 0,42.
- `tools/test_shader_reflection.py`: `Describe()` en sesión viva y parada.
- `tools/test_runtime_boots.py`: la fila `Diagnose` es la única acción de la
  tarjeta y aparece en todos los perfiles de arranque.

## Pendiente de verificar en vivo

- Aspecto real en MM2 con la tarjeta cerrada (hojas, polvo, reflejo de suelo).
- Qué imprime `Diagnose` en el mapa de granja; con ese texto se decide si hay
  que relajar `eligibleFloor()` (`Size.X/Z ≥ 6`, `UpVector.Y ≥ 0,97`,
  `Transparency < 0,95`) o el `ImageTransparency` del viewport.
- FPS en móvil con hojas + polvo + lluvia + nieve a la vez.
