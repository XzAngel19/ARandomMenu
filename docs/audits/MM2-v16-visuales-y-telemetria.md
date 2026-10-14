# MM2 v16 — Weapon Visuals, visibilidad y telemetría fiable

**Build:** `v16-20261014-mm2-visuals-telemetry`  
**Rama:** `arena/f208cfd3-arandommenu`  
**Base:** v15, commit `0aec767e9c0f32e69fa5f298a6c33be00c473d64`.

Esta entrega sí modifica el runtime. Las dos auditorías anteriores describían lo observado, no una implementación de Weapon Visuals. No se cambió `main`.

## Evidencia utilizada

La [auditoría de la nueva exportación](MM2-nueva-exportacion-visuales-20261014.md) documenta los archivos de [TestingStuff@239c20f](https://github.com/XzAngel19/TestingStuff/tree/239c20f21fea1b6e23811fd4c908d6fbcae657ab), sus hashes y las limitaciones de la descompilación.

- El selector del cliente nativo excluye al personaje local y `WeaponPassthrough`, y vuelve a lanzar el rayo cuando encuentra transparencia exactamente 1.
- En los siete eventos finales de Gun, cuatro tienen `hitTarget=true`. Tres de ellos estaban clasificados como `miss` en GameLearning. No es válido usar ese logger como una tasa de fallos fiable.
- Los contadores históricos de aproximadamente 10^57 pierden precisión incluso para sumar una unidad. v15 dejó de duplicar al guardar, pero todavía importaba esos contadores contaminados.
- Las observaciones de Knife siguen respaldando 96 studs/s como fallback. No justifican cambiar arbitrariamente velocidad, lead o cadencias.

## 1. Weapon Visuals, separado en Render

Archivo nuevo: `src/games/MM2/Render/WeaponVisuals.lua`, registrado en el cargador y en el bundle.

- Master y opciones apagados por defecto: **Double Gun**, **Double Knife**, **Electric Knife**, color e intensidad eléctrica.
- Solo trabaja con armas equipadas del jugador local. Contempla `LeftHand`/`RightHand` de R15 y `Left Arm`/`Right Arm` de R6, y geometría anidada en `VH`.
- Duplica piezas geométricas, no Tools. Antes de introducir cada copia en el mundo elimina descendientes funcionales, tags y atributos, y reconstruye únicamente hijos visuales admitidos.
- Las copias son no ancladas, massless, sin colisión, touch ni query; llevan uniones propias hacia la mano izquierda. Máximo 64 piezas por arma duplicada.
- Electric utiliza carriers invisibles, attachments y beams propios. No añade objetos a la Tool real ni ejecuta módulos de assets externos. **Es un efecto local original, no una reproducción certificada del efecto oficial.**
- Doble arma no necesita loop permanente. El efecto eléctrico actualiza a 8 Hz únicamente mientras tiene geometría visible. No se añadió un loop cosmético de 120 Hz.
- Reconstrucción por eventos; limpieza al desequipar, cambiar personaje, desactivar y destruir el módulo. Las tareas diferidas se invalidan al apagarlo.

No desbloquea inventario, no añade daño ni envíos de armas, y no promete que otros jugadores vean las copias. La colocación y apariencia de skins concretas requieren prueba visual en Roblox.

## 2. Mejora concreta de Shoot y Knife

### Shoot Normal

WallCheck usa ahora un filtro compartido basado en el selector nativo: personaje local + tags `WeaponPassthrough`, omitiendo piezas completamente transparentes mediante recasts acotados. Una pared opaca sigue bloqueando. Si se agotan 32 recasts, rechaza conservadoramente.

Esto evita rechazos por geometría que el selector nativo omitiría. No significa que el servidor permita penetración de paredes ni cambia sus reglas. El toggle WallCheck se conserva; Silent no adquiere esta nueva comprobación.

### Knife Throw Normal

La elección del objetivo más próximo exige ahora una ruta visible, de modo que un objetivo bloqueado no impida considerar otro visible. Antes de enviar también comprueba la ruta hacia el punto predicho. Comparte los filtros anteriores; Silent conserva su comportamiento previo.

Se mantienen la intercepción y RTT/2 de v15, el fallback de 96 studs/s, los cooldowns y las protecciones existentes. No se restauraron hitboxes ni ráfagas.

## 3. Calibration: sesión nueva sin destruir el historial

`MM2_Trajectory_Calibration.json` pasa a **schema 4**:

- `sessionId`, build, comienzo estable, identificadores locales de intento y fases explícitas.
- Los contadores, eventos detallados y buckets de movimiento pertenecen solo a la sesión nueva. No se reconstruyen totales inventados desde una lista parcial de eventos.
- Antes de sustituir un archivo no vacío, guarda sus bytes en `archivo.json.before-<sessionId>.json` y verifica que se pueden leer iguales. Si no puede protegerlo, bloquea la escritura del archivo principal. Los backups no se borran automáticamente.
- Solo importa estadísticas agregadas finitas y plausibles para las estimaciones históricas. Esos agregados se etiquetan como históricos + sesión, no como denominador de aciertos. No alimentan las muestras frescas de Gun.
- Las activaciones de Knife se separan de los intentos clasificados de throw/stab. Observar un proyectil no equivale a confirmar impacto.
- Una señal GunFired sin intento correlacionado se registra aparte; ya no inventa otro intento ni una latencia de cero.
- Guarda configuración relevante de Shoot/Knife y etiquetas de fase. Para contar intentos no se debe sumar indiscriminadamente todos los eventos: un mismo `shotId` puede tener fase de intento y confirmación.

Los identificadores correlacionan los dos logs locales. La asociación de señales nativas con intentos pendientes sigue siendo observacional, basada en los datos disponibles; no es un identificador autoritativo emitido por el servidor.

## 4. GameLearning: evidencia, no falsos misses

`Place_142823291_Game_Learning.json` pasa a **schema 2**:

- En MM2 usa el observador de armas del core, en lugar de contar tanto el click como cualquier Tool.Activated. Ignora la activación no clasificada de Knife como disparo y deduplica por `shotId`.
- Lee correctamente `targetName`, build, sesión, fuente y ajustes del intento.
- Consume confirmaciones con el mismo `shotId`. GunFired puede registrar `target-hit` o `shot-confirmed`; Knife registra `projectile-observed`.
- Un timeout produce **`unconfirmed`**, no `miss`. Una confirmación posterior puede reemplazar ese estado sin duplicar contadores.
- Una muerte posterior del objetivo se guarda por separado como asociación temporal: no prueba quién la causó y no sobreescribe el impacto observado.
- Los textos de diagnóstico ya no aseguran tolerancia del servidor, penetración o eficacia de hitboxes a partir de observaciones locales.
- Sesión y hora de inicio estables; historial protegido mediante backup verificado y sin reimportar contadores al alternar el logger. El guardado conserva cambios ocurridos durante una escritura que ceda ejecución.

Los campos antiguos de kills/misses se conservan sin uso por compatibilidad; `outcomeContract` lo indica. No interpretar sus ceros como una medición de bajas o fallos.

## 5. Frecuencias

No se subió todo a 120 Hz. Se conservan Motion y Throw a 60 Hz por defecto con opción de 120, Auto Shoot a 60, Aura a 20 y medición/interpolación del lead a 30. La reconstrucción cosmética es por eventos y Electric a 8 Hz. Aumentar comprobaciones no elimina el cooldown ni demuestra más aciertos.

## 6. Verificación ejecutada

Con Luau oficial 0.732, sin ejecutar Roblox ni fuentes de terceros:

- `tools/test_mm2_precision.py`: **14 grupos aprobados**, ahora con schema 4 y comprobación de bloqueo de Knife Normal sin alterar Silent.
- `tools/test_mm2_v16.py`: **4 grupos aprobados**, ejecutando código real del proyecto con mocks: filtros/recasts; backup y aislamiento de datos corruptos; deduplicación/confirmaciones/timeouts/muertes; ciclo completo de Weapon Visuals con R6/R15, VH, sanitización, respawn, unequip, electricidad y destrucción.
- `tools/test_entity_team_provider.py`: **14 comprobaciones aprobadas**.
- **70 fuentes propias compiladas; cero errores sintácticos.**
- Bundle sincronizado: **68 entradas**, stamp v16. `git diff --check` sin errores.

La compilación y los mocks no certifican física, apariencia, FPS ni porcentaje de impactos en Roblox.

## 7. Prueba recomendada en el juego

1. Recargar la rama de esta sesión y comprobar el stamp `v16-20261014-mm2-visuals-telemetry` en consola. No basta con dejar abierta una instancia de v15.
2. En Render → Weapon Visuals, encender el master y una opción cada vez. Equipar/desequipar Gun y Knife, reaparecer y apagar el módulo. Comprobar ausencia de copias residuales y de cambios al arma real.
3. Probar Shoot Normal con WallCheck frente a geometría transparente/passthrough y una pared opaca. Probar Knife Normal con un objetivo cercano bloqueado y otro visible. Separar estas observaciones de Silent.
4. Hacer tandas identificadas por modo, manteniendo iguales los parámetros de precisión. No cambiar a la vez frecuencia, lead y modo.
5. Guardar Calibration y GameLearning desde Metrics. Enviar los **dos archivos principales nuevos**, cuya cabecera tenga este build; los backups solo son necesarios para comparar con el historial.
6. Comparar intentos/confirmaciones/impactos por `shotId`, no por totales mezclados ni por muerte inferida. Para medir daño real o aciertos de Knife, acompañar con observación o grabación de la tanda.

**Conclusión:** hay mejoras implementadas gracias a los archivos aportados, especialmente en visibilidad y calidad de los datos. No se afirma todavía una ganancia cuantificada de precisión; hace falta la prueba de esta build dentro del juego, no otra búsqueda de ServerScriptService/ServerStorage como requisito para estos cambios.
