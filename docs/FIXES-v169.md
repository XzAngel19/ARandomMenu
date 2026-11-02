# v169 — Limpieza del repositorio y arranque Universal

Build `v169-20261102-repo-runtime-cleanup` · 2026-11-02.

## Qué se retiró

- `src/gui/Current/`: GUI anterior y sus 144 archivos de recursos, sin carga
  desde el Wurst actual. Su procesador `tools/process_manga_assets.py` ya no
  tenía un uso vigente y también se retiró.
- `src/library/`: dos registries de aquel sistema; `src/Profile/`: cinco
  perfiles antiguos no incluidos en el Manifest actual.
- 43 informes históricos reemplazados por versiones posteriores, tres guías
  de versiones antiguas y 13 datos históricos que los tests actuales no leen.
  Siguen disponibles en el historial, por ejemplo:
  `git show a4e9fb3:docs/FIXES-v163.md`.
- `AGENTS.md` contenía una hoja de instrucciones de agente ajena al proyecto,
  sin referencias a Wurst ni función en el menú; se retiró. `RESUME.md` sigue
  siendo la guía de desarrollo y se conservaron las configuraciones de las
  integraciones `.claude`, `.cursor` y `.entire`.

No se reescribió el historial: esto limpia el árbol actual, no recupera el
espacio ocupado por blobs de commits anteriores. La limpieza se publica en
`arena/9492e6b6-arandommenu`, no modifica `main`.

Se conservaron los módulos de todos los juegos, el constructor del bundle, las
pruebas, sus fixtures, Luau y herramientas de diagnóstico. Las referencias
históricas que sí usan tests (`docs/prediction-baselines/v41`, `v43`, `v44`)
permanecen. También permanecen los seis archivos en `src/guis/Wurst/Assets/`:
no van dentro del bundle, pero `src/Wurst.lua` los descarga directamente.

El bundle pasó de 89 a **83 fuentes**: el Manifest más las 82 fuentes que
lista. No se quitó ningún módulo de su catálogo. Hay 85 archivos Lua en `src`
contando el loader y el bundle generado.

## Fallo de readiness encontrado

En un PlaceId sin sección específica, `SectionManager.initializeAllAsync()`
volvía con cero secciones sin marcar `state.menuReady`. En un móvil cuyo dock
no hubiera podido inicializarse, el botón alternativo permanecía oculto aunque
el menú universal ya estuviese construido. El dock móvil normal ya existía y
no dependía de ese botón de respaldo; no afirmar que todos los móviles estaban
bloqueados.

Se comparte la misma finalización diferida para cero secciones y para el final
de las secciones de juego. La simulación fuerza un fallo de inicialización de
Furniture, comprueba que aparece el botón de respaldo y lo usa para abrir el
menú. Otro test encola `spawn`/`defer` para verificar que no se muestra el
lanzador antes de que terminen las secciones, incluso si alguna falla.

## Comprobaciones

- `tools/test_source_inventory.py`: el disco, el Manifest y el bundle coinciden;
  comprueba los seis assets separados y sus cabeceras, sin afirmar que Roblox
  los haya descargado o renderizado.
- `tools/test_runtime_boots.py`: boots simulados de escritorio y móvil más
  fallback a descargas individuales cuando el bundle no está disponible. Todos
  los archivos de cada juego se obtienen y las tarjetas/opciones del fallback
  coinciden con el boot del bundle.
- Antes y después se compararon tarjetas, encabezados, filas y visibilidad
  inicial en los siete boots simulados (sin cambios):

| Place simulado | Tarjetas con debug |
| --- | ---: |
| Universal | 37 |
| MM2 | 50 |
| BedFight | 47 |
| TRS | 48 |
| VD | 51 |
| X2 Legacy | 42 |
| X2 | 42 |

- Se actualizó el test X2 que aún exigía los perfiles viejos: ahora comprueba
  los PlaceIds en el mapa real del loader y el registro de la sección; la matriz
  también verifica las tarjetas `MVSD` con ambos IDs.
- `bash tools/validate.sh`: **PASS**, 85 fuentes compiladas, 110 suites,
  boot `failures=0`, 90 llamadas de API comprobadas y menú MM2 50/49
  (debug/release). Son comprobaciones offline, no un resultado en partida.

## Pendiente antes de hablar de «menú completo»

No se ha hecho una auditoría manual exhaustiva de todos los módulos ni se ha
probado esta versión en Roblox/Delta. Hay que verificar imagen real de Shaders,
lag y Shift Lock, Destruct/Keep entre instancias, Gun/Knife/Auto Farm en MM2 y
la aceptación/visibilidad de emotes por el servidor. Los mocks no prueban daño,
FPS, física, compatibilidad del executor ni seguridad anticheat. No usar Gun
Probe para estas pruebas: anteriormente bloqueó disparos y generó BAC-1583.
