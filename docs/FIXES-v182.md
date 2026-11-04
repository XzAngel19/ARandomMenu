# v182 — Emotes MM2, escala, opacidad y Calibration

Fecha: 2026-11-04 · rama `arena/9492e6b6-arandommenu` · stamp:
`v182-20261104-mm2-ui-calibration-repair`

La base integra la rama posterior v181 (`608c937`) sin perder la historia de la
sesión. Se respeta la eliminación de Shaders documentada en v179 y se conservan
las opciones posteriores; no se ha reescrito la política de tiro/cuchillo.

## Get All Emotes

- El catálogo confirmado incluye `sit`, `ninja`, `zen`, `dab`, `floss`,
  `zombie` y `headless`. El usuario confirmó que Zombie y Headless deben quedarse
  y que solo se excluyan los predeterminados. También se incorporan otros
  emotes reproducibles que aparezcan en el catálogo vivo de MM2, sin añadir
  defaults ni eliminar los que el jugador ya tenía. El inventario previo se
  conserva y repetir la acción no duplica IDs. La consulta del catálogo se hace
  aparte para que un `require` lento no bloquee los siete conocidos.
- Se contrastó `Database.Sync.Emotes`, el controlador moderno y el antiguo con
  el volcado de `XzAngel19/TestingStuff` (blob
  `755f47708dfbe83a5eaad25d5a60a5a36788dcf6`). El evento de inventario es un
  **BindableEvent**, por lo que se usa `InventoryDataChanged:Fire(...)`, no
  `InventoryDataChanged.Event:Fire(...)`. Si no existe, se intenta reconstruir
  la GUI antigua solo cuando su controlador está disponible, evitando un
  `require` que podía esperar indefinidamente.
- Es un botón: no concede al arrancar o reaparecer hasta que se use. Después de
  activarlo, al reaparecer se reintenta la actualización; destruir el módulo
  cancela la conexión y las tareas pendientes. La selección usa `PlayEmote` del
  juego y, si ese evento no existe, intenta cargar la animación en el Animator.
- **Límite importante:** los cambios son en el perfil local y la señal de la
  interfaz; no se ha demostrado concesión de inventario por el servidor ni
  reproducción/replicación a otros jugadores. `:Fire` es una solicitud, no una
  confirmación de que la animación se haya visto.

## UI Settings

- Antes se aplicaba `clamp(fit * preferencia, 0.7, 1.6)`; en móviles muchos
  valores diferentes daban el mismo 0.7. Ahora se limita el ajuste automático de
  pantalla y **después** se multiplica por la preferencia 0.7–1.3. El deslizador
  conserva su geometría al comenzar el arrastre para que el movimiento de la
  propia UI no desplace el valor bajo el dedo.
- Opacity compone la ventana completa con `CanvasGroup.GroupTransparency` en
  lugar de desvanecer individualmente los fondos y dejar textos, iconos y bordes
  con otra opacidad. Las ventanas nuevas heredan el valor. Los controles sin
  marco mantienen sus Frames y su estilo independiente.
- `Menu scale` y `Opacity` limitan también valores escritos/restaurados a sus
  rangos reales, y corrigen perfiles antiguos fuera de rango. Los sliders de
  movimiento mantienen el rango manual abierto, incluso valores negativos.
- Reflow actualiza las posiciones base al colocar o recolocar ventanas
  automáticamente; se preservan posiciones guardadas del usuario al reducir y
  ampliar la pantalla, y las posiciones manuales no se cambian al abrir por un
  solapamiento deliberado. En pantallas demasiado pequeñas aún puede haber
  solapamiento: no se promete que quepan todas las ventanas simultáneamente.
- **Límite visual:** `CanvasGroup` recorta sus descendientes y usa una textura;
  Roblox puede reducir su resolución o fallar al renderizarla si el dispositivo
  agota el presupuesto. Los mocks no prueban calidad visual, memoria, GPU ni
  rendimiento de Delta; hay que comprobar en dispositivo real.

## Calibration

- El diálogo se crea directamente bajo `ScreenGui`, sin heredar el `UIScale`
  del menú; ocupa una capa de pantalla completa, se centra con ancla `(0.5,0.5)`,
  limita el ancho a 340 px y ajusta su altura al texto.
- Se corrigió una regresión real de privacidad: importar un historial antiguo
  creaba su backup **antes de la respuesta**. Ahora leer es de solo lectura y
  el primer guardado autorizado verifica que el archivo no cambió, escribe una
  copia exacta y verifica sus bytes antes de reemplazarlo. Si cambió o falla la
  copia, bloquea el guardado y avisa; `Ask again` no borra el archivo.
- Sin `Yes` no se escriben archivos de telemetría, tampoco el fallback de
  `Clear MM2 history`. `No` detiene el guardado e intenta eliminar el archivo
  actual; la eliminación depende de `delfile`, y no borra backups anteriores.
  Los avisos ya no aseguran eliminación ni guardado cuando no se pudieron hacer.
- El estado muestra la ventana real de hasta **8** muestras por modo, no `/20`.
  Esa cantidad y el feedback local no prueban convergencia ni precisión del
  servidor.

## Pruebas y límites

`tools/test_mm2_emotes.py` comprueba los siete IDs, defaults, evento moderno,
GUI antigua, errores, respawn y destrucción. `tools/test_ui_visual_regressions.py`
comprueba las fórmulas reales, el arrastre, centro del modal, grupo de opacidad y
reflow con vistas de teléfono y escritorio. `tools/test_mm2_menu_scale.py`
verifica el cambio de cámara, viewport cero, preferencias y migración de valores.
`tools/test_calibration_consent.py` arranca el módulo real con IO simulado y
prueba consentimiento, conflicto, backup fallido/corrupto y callbacks del modal.
Las demás suites de `tools/validate.sh` siguen siendo obligatorias.

Ninguna de estas pruebas ejecuta Roblox/Delta real, verifica píxeles, FPS,
propiedad en servidor, permisos de animación o replicación. Validar esos puntos
con una sesión real antes de darlos por resueltos.
