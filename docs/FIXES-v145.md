# v145 — un solo loader, cero caché vieja, versión real

Build: `v145-20261027-canonical-loader-cache-purge`
Rama canónica y única: `arena/83897e25-arandommenu`
Base: `v144-20261027-touch-momentum-farm-collect`

## 1. Por qué aparecía una versión vieja

Tres cosas distintas podían producir ese síntoma, y las tres se atacaron:

1. **Etiqueta de versión congelada.** `PRODUCT.version` era el literal
   `"0.1 Beta"` (y `ClickGui` lo repetía como fallback). El chip del header
   mostraba eso aunque el runtime fuera otro.
2. **Caché en disco sin identidad.** `Wurst/src/**` se reutilizaba con solo
   comparar `Wurst/.stamp`; no se guardaba la rama ni la versión de layout, y
   `sweepStaleSources` sólo miraba archivos `src/` que estuvieran en el bundle.
   Un `Wurst/Assets` viejo, un `legacy-bundle.lua` o un árbol de otra rama podía
   sobrevivir indefinidamente.
3. **Loader suelto.** Cualquier archivo `Wurst.lua` copiado de otra rama se
   ejecuta y trae *su* árbol y *su* estampado. El `Reinject` aceptaba cualquier
   descarga que tuviera el marcador de compatibilidad, sin mirar la rama.

## 2. Qué hace v145

### 2.1 Versión derivada del build real

```lua
local BUILD_LABEL: string = string.match(SOURCE_STAMP, "^v%d+") or SOURCE_STAMP
...
version = BUILD_LABEL,
```

El chip del menú y el título `UI Settings · vNNN` salen del mismo `SOURCE_STAMP`.
Ya no existe ningún literal de versión en el runtime (`0.1 Beta` fue eliminado
del código y de los tests que lo toleraban). Un build no puede mostrar una
versión que no es.

### 2.2 Identidad de caché (stamp + rama + layout)

Marcadores nuevos en la carpeta del executor:

```text
Wurst/.stamp    -> SOURCE_STAMP
Wurst/.branch   -> RUNTIME_BRANCH
Wurst/.layout   -> "2"        (CACHE_LAYOUT, se sube si cambia el formato)
```

`state.cacheIdentityMatches()` exige los **tres**. Si alguno no coincide, la
caché no se lee y se borra.

`state.purgeLegacyCache(force)` recorre `Wurst/` y elimina:

- todo archivo cuyo marcador no coincida con el build actual;
- fuentes `src/**` que no estén en el bundle vigente;
- assets que no estén en el manifiesto de assets del build;
- cualquier resto desconocido (bundles viejos, `.stamp.old`, basura de loaders
  anteriores).

**Nunca** toca `Wurst/Profiles/**` (configuración y perfiles del usuario).

Se ejecuta **antes** de leer nada de la caché en cada inyección, y otra vez tras
aceptar el bundle. `force = true` (botón *Clear cache*) borra también la caché
del build actual.

### 2.3 Una sola rama, con override validado

- `CANONICAL_BRANCH = "arena/83897e25-arandommenu"` y
  `RUNTIME_BRANCH = CANONICAL_BRANCH` por defecto.
- `getgenv().WURST_BRANCH` sigue permitiendo otra rama, pero pasa por
  `normalizeBranchName`: recorta espacios y comillas, quita `refs/heads/`,
  rechaza vacío, `..`, más de 120 caracteres y cualquier cosa fuera de
  `[A-Za-z0-9-_./]`. Un valor inválido se ignora (se usa la canónica) en vez de
  cargar un árbol arbitrario.
- El snippet de `queue_on_teleport` re-inyecta siempre con `RUNTIME_BRANCH` y
  `?t=os.time()`.

### 2.4 Reinject que no puede revivir un loader viejo

- Limpia la caché (`force`) **antes** de descargar.
- Cache-buster real: `?reinject=v4&t=<os.time()>&v=<stamp>`.
- Lee la rama declarada dentro del archivo descargado
  (`local RUNTIME_BRANCH: string = "..."`). Si declara otra rama, **se rechaza**
  con `stale loader for branch <x>` en lugar de ejecutarla. Un loader antiguo
  que no declare la constante sólo se acepta si el texto contiene la rama
  vigente.
- Si ambas URLs fallan, no ejecuta nada y lo dice en el output.

### 2.5 Árboles de versiones viejas eliminados del repositorio

Se borraron del repo las tres ramas muertas que nadie cargaba y que viajaban en
el bundle (13 MB):

| Ruta | Qué era | Estado |
| --- | --- | --- |
| `src/gui/Current/**` | menú standalone viejo (`gui.lua` + 145 archivos de assets) | eliminado |
| `src/library/*.luau` | `AssetRegistry` / `ProfileRegistry` legacy | eliminado |
| `src/Profile/*.lua` | perfiles por PlaceId que sólo leía `ProfileRegistry` | eliminado |
| `tools/process_manga_assets.py` | generador de los assets de ese menú viejo | eliminado |

El bundle pasó de **90 a 84 archivos**. La metadata de PlaceId vive ahora en un
único sitio: `src/libraries/Manifest.lua` (y su fallback en `src/Wurst.lua`).
`tools/test_x2duels.py` verifica los dos PlaceId de X2 directamente contra el
manifiesto y prohíbe que `src/Profile` reaparezca.

## 3. Estado de Fling (respuesta a «¿ya está arreglado?»)

Lo que **está corregido y verificado offline**:

- El impulso va al jugador tocado; el avatar local ya no entra en estado
  `Physics`, no se apaga `AutoRotate`, no se togglean colisiones por contacto y
  no hay giro local (`AssemblyAngularVelocity` local = 0). Eso era el «movimiento
  circular tonto».
- Hay un único dueño de la sesión, un pulso por objetivo con cooldown `1/20 s`,
  límites por debajo de 250 studs/s, restauración en `Heartbeat`, snapshots de
  `CanTouch`/`CanCollide`, y cleanup en OFF/muerte/respawn/destroy.
- Las suites `test_fling_physics.py` y `test_startup_restore.py` cubren esos
  contratos.

Lo que **no se puede afirmar desde aquí**: que el servidor acepte el knockback
(el desplazamiento real del tocado) y cuánto dura. Eso es física replicada y sólo
se ve en vivo. Si al probarlo el tocado no se mueve, el siguiente paso es medir
distancia del root tocado antes/después del contacto, no subir la magnitud.

## 4. Validación

```bash
python3 tools/build_bundle.py --stamp v145-20261027-canonical-loader-cache-purge
bash tools/validate.sh
```

```text
bundle.lua is current: 84 files, stamp v145-20261027-canonical-loader-cache-purge
PASS 86 Lua sources compile
PASS 66 Python/Luau suites
[Wurst:Bootstrap] Load complete · failures=0
PASS menu audit: 50 cards
PASS release menu: 49 cards, no Calibration card
```

Suite nueva `tools/test_loader_cache.py` (ejecuta el código real de caché contra
un filesystem simulado):

- caché de otro stamp/rama/layout se borra y no se lee;
- la caché vigente se conserva, y se barren módulos retirados, assets viejos y
  restos desconocidos;
- *Clear cache* borra todo lo generado y **conserva** `Wurst/Profiles`;
- cambiar de rama invalida la caché aunque el stamp sea el mismo.
