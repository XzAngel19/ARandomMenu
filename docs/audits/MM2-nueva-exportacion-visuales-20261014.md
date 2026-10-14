# Nueva exportación MM2, calibración y viabilidad de visuales locales

## Alcance

Revisión de [`TestingStuff@239c20f21fea1b6e23811fd4c908d6fbcae657ab`](https://github.com/XzAngel19/TestingStuff/tree/239c20f21fea1b6e23811fd4c908d6fbcae657ab):

- `e6c4be8`: añade `place, source.rbxlx` (18.663.943 bytes).
- `239c20f`: actualiza `MM2_Trajectory_Calibration.json` (889.694 bytes).
- `Place_142823291_Game_Learning.json` no cambió respecto de la revisión anterior.

Se inspeccionó XML, propiedades Source, dependencias y telemetría, y se compiló el código recuperado sin ejecutarlo. **No se ejecutó Roblox, no se verificó daño en servidor ni se añadieron todavía opciones cosméticas al menú.**

## 1. Dictamen

**La exportación mejoró mucho, pero no contiene todo el código ni permite decir que todo funciona perfectamente.** Ahora sí hay fuentes útiles para estudiar cómo se dibujan las armas y para diseñar Double Gun, Double Knife y un efecto eléctrico exclusivamente local.

Todavía faltan:

- Implementaciones de servidor.
- Dos fuentes que no se descompilaron.
- Reparación o una mejor exportación de dos fuentes reconstruidas con sintaxis inválida.
- Una sesión de prueba identificada por build, con contadores sanos y métricas correlacionadas.

## 2. Fuentes recuperadas y compilación

Se encontraron **303 propiedades Source**:

| Contenido | Cantidad |
|---|---:|
| ModuleScript con fuente candidata | 164 |
| LocalScript con fuente candidata | 118 |
| Script con fuente candidata | 3 |
| Comentarios indicando fuente de servidor no disponible | 15 |
| `Failed to decompile` | 2 |
| README del exportador | 1 |

De las **285 fuentes candidatas**, **283 compilan con Luau 0.732** y **2 fallan**. Compilar no garantiza que una descompilación sea semánticamente correcta o que sus dependencias estén disponibles.

### Errores exactos detectados

**`StarterGui/BackpackUI/BackpackScript`**

- Líneas 110 y 191 del Source extraído: `goto l0;`.
- Diagnóstico: `SyntaxError: Incomplete statement: expected assignment or a function call`.

**`StarterPlayer/StarterCharacterScripts/Animate`**

- Líneas 738, 740, 748 y 770: instrucciones como `goto l0;`, `goto l3;`, `goto l2;`, `goto l1;`.
- Mismo diagnóstico.

Luau no admite esas instrucciones. Son defectos del código reconstruido; **no demuestran que el script original que ejecuta MM2 tenga ese error**. Tampoco conviene borrar los goto a ciegas: eso puede romper el flujo de control.

### Fuentes aún no recuperadas

- `ReplicatedStorage/MainGUI/Game/Emotes` contiene un LocalScript cuyo Source dice `Failed to decompile`.
- `StarterPlayer/StarterPlayerScripts/StatusEffectScript` contiene el mismo mensaje.
- Quince objetos Script conservan únicamente el aviso sobre scripts de servidor no disponibles.
- `ServerScriptService` y `ServerStorage` aparecen como contenedores **sin hijos**. Su presencia no significa que se haya recuperado su contenido original.

El snapshot contiene solo dos objetos Tool (`Emotes` y `AAAAA`), no las herramientas Gun/Knife equipadas con todos sus controladores. Esto limita la revisión de su lógica específica y de sus grips, aunque el sistema visual común sí está presente.

Por separado, los **69 archivos Luau del menú actual** compilan, y el bundle v15 coincide con sus **67 fuentes incrustadas**. Esta comprobación es de compilación/empaquetado, no una prueba de juego.

## 3. Qué código importante ahora sí se puede estudiar

### WeaponService

Ruta: `ReplicatedStorage/ClientServices/WeaponService`.

- `GunFired` apunta a un **RemoteEvent** hijo del módulo.
- `KnifeThrown` se crea como **BindableEvent**: en este servicio es una notificación local, no el remoto de lanzamiento de la herramienta.
- Resuelve objetivos de cursor/cámara mediante raycasts.
- Excluye el personaje local y objetos con la etiqueta `WeaponPassthrough`.
- Sigue buscando tras partes totalmente transparentes.

Esto coincide con la ruta que utiliza nuestro observador de GunFired. También muestra una diferencia relevante: el WallCheck Normal de Shoot hace un raycast más simple y **no reproduce todos los filtros `WeaponPassthrough`/transparencia del selector de cursor**. Puede ser más restrictivo en algunos escenarios. No debe asumirse, sin el servidor, que copiar el filtro del cursor equivale a reproducir la validación autoritativa de balas.

### GunBeams / CreateBeam

Ruta: `StarterPlayer/StarterPlayerScripts/WeaponVisuals/GunBeams`.

- Escucha `WeaponService.GunFired.OnClientEvent`.
- `CreateBeam` utiliza arma, origen, endpoint y una pieza opcional de impacto.
- Crea soportes locales con Attachments y Beam, permite `CustomBeam`, genera chispas y elimina los objetos temporales.

Esto demuestra que **la representación gráfica está separada del envío del disparo**. Un segundo beam cosmético no requiere un segundo paquete ni una segunda validación de daño.

### ThrowingKnifeVisuals

Ruta: `StarterPlayer/StarterPlayerScripts/WeaponVisuals/ThrowingKnifeVisuals`.

- Observa objetos etiquetados `ThrowingKnife`.
- Utiliza `HandleLink` y `BladePosition`.
- Clona el handle como `KnifeVisual`; contempla un hijo `VH` como handle visual.
- Avanza el visual usando `Direction` y `ThrowSpeed`, con fallback **96 studs/s**.
- Añade una trail y limpia el seguimiento cuando desaparece el proyectil.

El fallback coincide con la velocidad de 96 observada en la calibración. **Es código visual del cliente**, no la implementación completa de colisión/daño del servidor.

## 4. Qué dice realmente la calibración nueva

### Mezcla historial con un guardado posterior

- Formato: **schema 3**.
- Guardado: **14/10/2026 16:21:08 UTC / 11:21:08 Lima**.
- Evento más reciente: **14/10/2026 06:24:06 UTC / 01:24:06 Lima**.
- Diferencia: casi **diez horas**.
- `elapsedSeconds`: aproximadamente **71,74 s** para el controlador que guardó el archivo.

Por tanto, el guardado reciente **no demuestra que todos los eventos sean de una prueba reciente**. El contenido incluye actividad anterior importada. Schema 3 identifica el formato, no el build bajo el que ocurrió cada evento.

Hay **206 eventos detallados**: 114 Knife, 48 Gun y 44 Stab, distribuidos entre el 11, 12 y 14 de octubre UTC.

### Contadores históricos inutilizables

```text
gunAttempts     ≈ 3,139 × 10^57
gunConfirmed    ≈ 1,177 × 10^57
knifeAttempts   ≈ 1,100 × 10^57
knifeConfirmed  ≈ 3,919 × 10^56
```

No representan cantidades reales plausibles. Son compatibles con la acumulación corrupta identificada anteriormente. **Un único archivo no demuestra que el writer v15 esté duplicando ahora mismo**: v15 conserva los totales que carga del historial.

Hay además pérdida de resolución numérica: a ese tamaño, sumar uno a cualquiera de esos campos no cambia su valor en coma flotante. No basta con evitar duplicaciones futuras; hay que separar/quarantinar los acumulados dañados y empezar contadores de sesión fiables.

No conviene borrar el archivo original: debe conservarse como evidencia. Los eventos detallados todavía sirven para análisis parcial. Tampoco esos cuatro contadores enormes implican automáticamente que el predictor esté usando un horizonte de magnitud absurda: v15 usa otras estadísticas y una ventana de observaciones nuevas para el ajuste de latencia.

### Siete registros Gun finales

Se toma exclusivamente el bloque de pistola más reciente, de 01:08 a 01:24 Lima:

| Hora del registro, Lima | Latencia de aceptación registrada | hitTarget |
|---|---:|---|
| 01:08:31 | 177,275 ms | false |
| 01:08:35 | 181,232 ms | true |
| 01:10:41 | 200,133 ms | true |
| 01:17:25 | 190,064 ms | true |
| 01:21:28 | 196,445 ms | false |
| 01:22:00 | 242,373 ms | true |
| 01:24:06 | 164,138 ms | false |

Resultado: **4 true y 3 false**. La proporción descriptiva es 4/7, aproximadamente 57 %, **solo sobre estas siete confirmaciones registradas**, no sobre todos los intentos ni necesariamente solo disparos de Shoot. Es una muestra pequeña, con historial y sin build por evento.

Mediana de latencia: **190,064 ms**. No debe confundirse esa latencia registrada con el instante exacto en que el servidor evaluó la colisión.

### Contradicción concreta con Game Learning

Al cruzar hora y ping con el archivo de Game Learning:

- Sus IDs **4, 6 y 67** dicen `miss`, pero los eventos correspondientes de calibración tienen **`hitTarget = true`**.
- Su ID **5** no tiene outcome, y el evento correspondiente sí tiene `hitTarget = true`.
- El último evento de calibración corresponde por esos campos al registro **76**, no a los 77/78 posteriores.

Esto confirma que el logger de muertes no debe usarse como verdad de acierto. `hitTarget` se calcula a partir de la pieza comunicada por GunFired; es evidencia más específica, pero **no es sinónimo de kill confirmada ni una certificación independiente del daño del servidor**.

Otro límite: estos siete eventos están muy espaciados; no reúnen seis confirmaciones dentro de una ventana de 60 segundos. Por sí solos **no demuestran que se activara la calibración fresca de v15**. El fallback puede haber seguido siendo la ruta utilizada.

### Knife

- Estadística de velocidad: **114 observaciones**, mínimo, máximo y media **96 studs/s**.
- Cinco eventos Knife recientes también muestran speed/rawSpeed 96.
- No contienen una confirmación equivalente `hitTarget` de impacto del cuchillo.
- `reason = destroyed` indica que terminó el seguimiento al desaparecer el proyectil; no acredita que matara o golpeara al objetivo.

Puede verificarse la coherencia de la velocidad visual/observada, **no una precisión perfecta de Knife**.

## 5. Viabilidad de Double Gun, Double Knife y electricidad

**Sí, los tres son viables como efectos exclusivamente locales.** No requieren que se haya exportado la lógica del servidor.

| Función | Implementación visual | No implica |
|---|---|---|
| Double Gun | Copia de geometría del arma equipada, asociada a la mano libre | Otra Tool funcional, munición, daño o disparo extra |
| Double Knife | Copia de geometría del cuchillo en la mano libre | Más alcance, doble contacto o un segundo lanzamiento real |
| Electric Knife | Attachments, Beams, Trail/ParticleEmitters y luz opcional locales | Comprar/desbloquear Electric, replicarlo a otros jugadores o activar su efecto de muerte |

### Referencias nativas encontradas

En `ReplicatedStorage/Database/Sync/Effects`:

```text
Electric / "Electric Knife"
KnifeModule = 236756675
DeathModule = 4980680584

Dual / "Dual Wield"
KnifeModule = 3187377961
```

**Son referencias a assets/módulos externos.** La búsqueda del XML encuentra esos identificadores en el catálogo, no una implementación incrustada de sus efectos. Tener un ID no demuestra que pueda cargarse desde el cliente ni que permita reconstruir exactamente el efecto oficial.

Podemos hacer un efecto eléctrico propio y una duplicación local independiente. Para una réplica exacta del aspecto oficial harían falta los assets/fuentes accesibles legítimamente o una referencia visual suficiente. No es necesario ejecutar módulos remotos desconocidos para la versión cosmética.

### Diseño para no interferir con Shoot y Knife

Módulo independiente propuesto: **Weapon Visuals**, categoría Render, desactivado inicialmente.

- Controles separados: Double Gun, Double Knife, Electric Knife, color e intensidad.
- Copiar únicamente geometría y elementos visuales permitidos; **no clonar Tools completas con Scripts, remotos ni lógica de toque**.
- Partes sin colisión, sin touch y sin query. Si se vinculan al rig, sin anclajes que inmovilicen al personaje y sin masa que altere la física.
- No copiar etiquetas funcionales como `Weapon_Gun`, `Weapon_Knife` o `ThrowingKnife` a las réplicas cosméticas.
- Respetar el handle visible `VH` cuando exista y soportar R6/R15.
- No modificar los argumentos de Shoot/KnifeThrown, el raycast de precisión, la hitbox real ni las herramientas originales.
- Si se añade un segundo beam de pistola, dibujarlo como reacción al evento observado del arma local, sin un nuevo `FireServer`.
- Limpiar todos los clones, conexiones y efectos al desequipar, morir, reaparecer, cambiar de arma, apagar el módulo o destruir/reinyectar el menú.
- Usar partículas/beams del motor; no es necesario un loop permanente de 120 Hz. Cualquier actualización manual debe estar acotada y existir solo mientras el efecto esté activo.

El resultado sería visible para ese cliente. No debe prometerse que otros jugadores lo vean ni que aparezca como un efecto adquirido en el inventario.

## 6. Qué falta antes de afirmar «funciona perfectamente»

1. Reparar el registrador universal: filtrar armas, correlacionar eventos, guardar build/sessionId y separar historial de sesión.
2. Quarantinar los contadores históricos corruptos sin perder los eventos de referencia.
3. Obtener una tanda nueva con timestamps realmente nuevos, ajustes efectivos y resultados observados.
4. Revisar la diferencia de filtros de WallCheck respecto del cliente nativo, sin equipararla automáticamente con validación de servidor.
5. Probar cualquier módulo visual dentro de Roblox: equip/unequip, ambos rigs, respawn, cambio de cámara, reinyección y ausencia de remotos extra.

**Esta revisión no instala los visuales ni cambia el runtime.** Confirma que hay una base técnica para implementarlos como cosméticos aislados y que la nueva exportación es útil, pero también identifica defectos de exportación y telemetría que impiden certificar perfección.

## Integridad de archivos revisados

```text
place, source.rbxlx
SHA-256 69723d60a0e9199daebae1c0e632f72d44b95c6bc828fe66bf12042027135f0d

MM2_Trajectory_Calibration.json
SHA-256 7abb89c96decd71740277d12d6326a2c7bc10c9cd0d4ef0baf697c1305043787
```

No se copiaron al repositorio el mapa de 18 MB, fuentes de terceros ni datos personales de los jugadores. Se conservaron únicamente las conclusiones de esta revisión.
