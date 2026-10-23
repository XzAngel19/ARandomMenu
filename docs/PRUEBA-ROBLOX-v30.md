# Prueba práctica — v30-20261016-flight-item-templates

## Alcance

La revisión de «Fight» se interpretó como **Flight (vuelo)**. No constituye una
verificación funcional de BedFight ni de sus remotes.

Se corrigieron en Flight:
- pérdida de ownership de PlatformStand al limpiar constraints cada frame;
- restauración de WalkSpeed al cambiar método y al reaparecer;
- suelo invisible/constraints al cambiar combinación o destruir;
- pérdida del nivel de altura de Bypass entre frames;
- velocidad horizontal residual contra una pared detectada;
- lectura de teclas verticales mientras se escribe en un TextBox.

Constraint controla su propio vector vertical; Float aplica a los otros métodos.
Estas correcciones no garantizan compatibilidad con la validación de cada juego.

ItemESP incorpora Touch matching: Appearance (predeterminado) / Name.
Appearance compara plantillas pequeñas: clase, tamaño, MeshId/SpecialMesh,
escala y offset de malla y distancias entre piezas. Ignora nombre, color y
posición global; no usa reconocimiento semántico de imágenes. Admite Models,
Tools y partes; rechaza plantillas de más de 32 partes o 96 nodos. Cachea
firmas, invalida al cambiar descendientes y refresca cada cinco segundos para
assets cargados después de parenting. Los rebuilds se limitan a uno cada 250 ms;
no recorre geometría cada frame. Los cambios de propiedades pueden tardar hasta
ese refresco en reflejarse. Las plantillas son locales a esta sesión: los rótulos
Look # persistidos sin su plantilla no se interpretan como búsquedas por nombre.
No existe garantía de distinguir dos objetos que compartan esta firma geométrica.

## Preparación

1. Preferir servidor privado y alguien que acepte ayudar; no necesitas Studio.
2. Entrar a un servidor nuevo, ejecutar el loader de la rama publicada y comprobar
   en F9 que dice `v30-20261016-flight-item-templates`.
3. No cargar a la vez otra versión. Cambiar solo una opción por prueba.
4. Grabar un vídeo corto si es posible. Anotar dispositivo, rig R6/R15 y ping
   aproximado de las estadísticas de rendimiento de Roblox.

## Animación, Freeze y Weapon Visuals — 3 minutos

- Equipar Knife, lanzar tres veces y desactivar Throw animation. Indicar si
  ocurre una sola animación, ninguna o una postura atascada. Anotar el skin.
- Weapon Visuals: ON → Double Knife → OFF, desequipar/equipar y reaparecer.
  Si falla, enviar el primer error rojo de F9 con su stack, no toda la consola.
- Freeze: Anchor → Humanoid → Freeze Emotes → Glitch Animations → OFF.
  Comprobar caminar y saltar al apagar.
- Freeze Emotes: probar un baile clásico y un emote equipado del menú Roblox;
  empezar quieto y caminar. Anotar el nombre exacto del emote que no detecte.
- Glitch Animations: caminar y realizar un ataque. El ataque no debe reiniciarse
  como locomoción. Comprobar que el texto del selector no se superpone.

## Flight — 2 minutos

Usar velocidades moderadas (horizontal 30–50, vertical 20–30).
- Velocity / Velocity: avanzar, soltar, subir, bajar, OFF. Caminar después.
- WalkSpeed → Velocity sin apagar: al apagar debe recuperarse la velocidad previa.
- Velocity / Floor → Constraint sin apagar: no debe quedar el suelo invisible.
- Velocity / Bypass: observar si conserva altura entre sus ciclos. Puede haber
  correcciones del servidor; no confundirlas con un error rojo del script.
- Reaparecer y apagar. Anotar combinación exacta si queda bloqueado.

## ItemESP — 1 minuto

- ItemESP ON → Touch matching Appearance → Touch part → tocar la llave.
- Comprobar que otras copias de la misma llave se marquen y otros Models no.
- Si no aparece, esperar cinco segundos por la carga de mallas. Si falla,
  enviar captura del objeto elegido y de los falsos positivos; incluir juego.
- Clear list borra las plantillas. Name vuelve al criterio antiguo por nombre.

## Predicción — una tanda corta, sin prometer porcentajes

Con un ayudante en privado y si el modo lo permite, hacer 5 intentos por caso:
quieto, caminar en línea recta, cambio de dirección, salto. Primero Prediction;
luego repetir con Silent AIM y finalmente Knife Throw. No cambiar Lead bias ni
Auto tune lead entre intentos de la misma tanda. Dejar al menos cuatro segundos
entre tiros de pistola para no mezclar cooldown con fallos de puntería.

Anotar por tanda: modo, distancia aproximada, ping, intentos, impactos observados,
rechazos visibles y si el tiro queda adelante/atrás/arriba/abajo. Un envío remoto
no cuenta como impacto; confirmación GunFired tampoco demuestra por sí sola
que el objetivo recibió el tiro. Vídeo del fallo y tabla sencilla ayudan más que
miles de paquetes de remotes sin contexto.

## Qué enviar

Solo si falla, o al acabar una tanda controlada:
- build, juego, dispositivo, modo y opciones exactas;
- pasos para reproducir y vídeo de 15–30 segundos, si está a tu alcance;
- primer error F9 y stack si existe;
- Metrics → Calibration → Save calibration;
- si has activado la captura de Metrics, Save learning logs.

Si el ejecutor permite archivos, buscar en su workspace:
- `Wurst/Telemetry/MM2_Trajectory_Calibration.json`
- `Wurst/Telemetry/Universal/Place_142823291_Game_Learning.json`

Si no tienes acceso a esos archivos, basta con el vídeo, la tabla y F9. No hacen
falta contraseñas, tokens, una nueva copia completa del mapa ni logs masivos.
Revisar los JSON antes de compartir: pueden contener nombres de jugadores.

## Pruebas automatizadas añadidas

- `tools/test_flight.py`: ejecuta el módulo real con dobles para cambios de
  método, ownership, respawn, Bypass y destrucción.
- `tools/test_item_appearance.py`: ejecuta la firma real frente a mallas y tamaños
  distintos, composición, rotación/traslación, Tools y límites de recorrido.

El resto de pruebas MM2, Freeze, UI, Entity y arranque simulado se vuelven a
correr antes de publicar. No sustituyen la comprobación dentro de Roblox.
