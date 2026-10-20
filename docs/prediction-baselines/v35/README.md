# Referencia A: v35 / 42379f5

Estos `.lua.txt` son copias completas obtenidas con `git show 42379f5:<ruta>`;
no se incluyen en el bundle ni son módulos ejecutables. Los SHA-256 están en
`metadata.json`. Conservan los predictores de v34 que seguían vigentes en v35.

- `Shoot.lua.txt` → `src/games/MM2/Blatant/Shoot.lua`
- `KnifeThrow.lua.txt` → `src/games/MM2/Blatant/KnifeThrow.lua`
- Dependencia compartida: `git show 42379f5:src/games/MM2/base.lua`.

Para restaurar el comportamiento completo, recuperar también las dependencias
del commit, no mezclar a ciegas un archivo antiguo con una base futura.
En v36 las matemáticas de `computeGunAim` y `predictAim` son idénticas a esta
referencia; activación y WallCheck sí cambian. No se presenta un nuevo modelo
predictivo en esta run.

`new-log-audit.json` contiene el análisis reproducible de los tres logs nuevos,
no la calibración que entrenó el baseline ni una medición de su accuracy.
Ver [plan y límites](../../PREDICTION-NEXT-RUN.md).
