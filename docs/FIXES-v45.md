# v45 — rehacer la seguridad de Gun y retirar Adaptive

## Fallos encontrados en v44

- Silent pasaba `ignoreVisibility=true` aunque WallCheck estuviera ON; además ocultaba ese control.
- La ruta normal no ejecutaba el chequeo de otros jugadores usado por Silent.
- El filtro compartido omitía partes totalmente transparentes y objetos WeaponPassthrough. Eso no es apropiado para proteger a otros jugadores con Gun.
- Un punto futuro sin colisiones podía aceptarse aunque el rayo final no intersectara al objetivo actual.
- La comprobación de Silent terminaba en el endpoint. No cubría a un inocente detrás si el disparo fallaba al objetivo.

Se inspeccionaron directamente los commits `66d7152796ecb4562a8e4aa50f983fee7d6d7c60` y `7385fcdae7457056ac22b8ae4cf8f5fb0fcaafbb`. Sus bloques de WallCheck son idénticos (SHA-256 `29b723ae95dab8223d57a324b3654317ca046f09110a5d0c979f29a6f2cbf003`): raycast directo, excluyendo solo al personaje local, sin saltar capas transparentes. El nuevo guard recupera ese criterio y exige además un hit real sobre el objetivo.

## Nueva ruta de disparo

1. Seleccionar únicamente un Murderer vivo y no protegido. Custom tampoco permite elegir un inocente.
2. Calcular el aim actual. Primero se prueba su rayo; si no atraviesa al Murderer, se buscan puntos del cuerpo expuesto con trabajo acotado. No se conserva visibilidad de un peek anterior.
3. Antes de enviar, releer el origen real de Gun y verificar arma, recarga, personajes, vida, ronda y rol. Un rol cacheado no basta si contradice el dato actual de ronda o ya no hay evidencia actual de Murderer.
4. Con WallCheck ON, exigir al Murderer como primer impacto desde el muzzle y desde el origen final de Silent. No se omiten transparencias ni tags. Silent ya no se salta WallCheck; el control permanece visible en ambos modos.
5. En ambos modos y aun con WallCheck OFF, comprobar otros jugadores con intersecciones rayo/OBB. Incluye partes transparentes/CanQuery=false y toda la línea hacia delante, no solo hasta el endpoint. Se amplían los volúmenes según velocidad observada y horizonte/latencia para cubrir entradas a la trayectoria. Es conservador: puede cancelar un tiro que habría sido válido.
6. Si un origen Silent está dentro del cuerpo o no demuestra un primer hit, volver al muzzle normal; no inventar una excepción. Errores de geometría/validación cancelan el envío. No hay paquete ni feedback de autoría cuando se cancela.

No se añadieron remotes extra, gates de distancia/confianza ni un cooldown local inventado. Auto Shoot sigue intentando cada Heartbeat y al activarse, con datos actuales y una comprobación final por intento. En el escenario controlado despejado normal se hacen **dos raycasts de mundo**: uno al resolver y otro al validar. La búsqueda bloqueada está acotada; ya no multiplica cada probe por hasta 32 capas transparentes. Las intersecciones de protección de jugadores son trabajo adicional.

### Frecuencia y límites reales

Un `task.wait(0.001)` no crea física ni replicación de red a 1000 Hz. Los chequeos se ejecutan en cada ciclo disponible del cliente, sin un temporizador de visibilidad. A 60 FPS eso normalmente supone unos 16.7 ms entre Heartbeats, no 1 ms. Tampoco se puede prometer protección absoluta contra información todavía no replicada, Streaming, cambios futuros de dirección, jitter o reglas privadas del servidor. No se ejecutó un cliente Roblox vivo.

## Predicción: rollback explícito, no otra promesa de mejora

- Se retiraron del runtime el híbrido Adaptive, sus historiales auxiliares, la inferencia de movimiento por posiciones de v44 y el interceptador experimental de gravedad de Knife.
- **66d es el modo por defecto de Gun**, con su ecuación, fallback de intención y timing legacy. Reference v41 sigue disponible en Calibration. Un valor guardado Adaptive ya no es una elección válida y vuelve al modo por defecto.
- Knife vuelve al intercepto lineal de Reference v41; no se tocaron su animación, inputs PC/móvil ni protocolo.
- Los originales de v44 están archivados con hashes en `prediction-baselines/v44/`. El fragmento original de 66d y su identidad están en `prediction-baselines/66d/`.
- Cuando la seguridad sustituye el lead por una parte visible, se desactiva la sensibilidad del autoajuste de esa muestra; no debe aprender del punto recortado como si fuera el lead original.

La ecuación actual de Gun coincide con el fragmento original de 66d en **576 casos controlados con iguales entradas**. Eso no demuestra precisión en el servidor ni replica cada condición histórica de red. Tampoco se presenta este rollback como una nueva mejora de hit-rate. Un replay retrospectivo de v35, con horizonte común y MoveDirection desconocido asumido cero, da MAE cliente 0.612079 para 66d frente a 0.506216 para v41: no demuestra una mejora. El cambio responde al rollback solicitado y a fallos verificables de seguridad, no a ajustar otra vez estos logs.

Los tests v42/v44 ahora indican explícitamente que ejecutan archivos **archivados**. No se cuentan como prueba del predictor nuevo. El replay permite elegir 66d o Reference v41; el campo heredado `adaptiveMAE` identifica el candidato indicado por `candidateModel`, no un Adaptive activo.

## Verificación

- 29 suites automatizadas, incluidas `test_gun_safety.py` y `test_prediction_66d.py`.
- Geometría dinámica: pared que abre/cierra, enemigo oculto con lead despejado, inocente delante/detrás del endpoint, transparencia, CanQuery=false, movimiento de un tercero, origen Silent dentro del cuerpo, cambios de rol/ronda/vida/respawn y excepciones antes de enviar.
- Solver real + guard real: ruta despejada de dos raycasts, búsqueda bloqueada acotada y siguiente intento sin caché de visibilidad.
- Ambas llamadas reales a FireServer ejecutadas en mocks: ninguna debe enviar al fallar la validación.
- Comparación con la ecuación original 66d y conservación de Reference v41; boot completo con default 66d y WallCheck visible en Silent; compilación de 74 fuentes Lua y bundle sincronizado.

Estas pruebas validan código y casos controlados, no garantizan “nunca dispara a un inocente” en una partida real.
