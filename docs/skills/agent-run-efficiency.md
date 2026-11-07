---
name: agent-run-efficiency
description: How to spend one agent run on this repository. Use when a request touches several cards at once (menu work, MM2 work, docs, release) and the goal is to finish the whole batch — code, tests, bundle, docs, push — inside a single run instead of dribbling out tool calls.
---

# Aprovechar cada run (eficiencia de agente)

Regla de oro: **un run = una tanda cerrada**. Si una petición pide seis cosas, el
run no debe terminar con «investigué las seis». Debe terminar con las seis
implementadas, el bundle regenerado, `tools/validate.sh` en verde y el commit
empujado.

## Cuándo usar esta skill

- La petición del usuario trae una lista numerada de cambios.
- El repo ya tiene suites (`tools/test_*.py`) que cubren lo que se va a tocar.
- Hay que publicar al final (rama `arena/…`).

## Fases

### 1. Mapa antes de tocar (una sola pasada de lectura)

Lanzar los greps en **paralelo**, no de uno en uno:

- localizar los ficheros que mencionan el símbolo del cambio;
- leer los bloques exactos (no el fichero entero);
- apuntar en la memoria de trabajo: fichero → línea → qué hay que cambiar.

Nunca se vuelve a leer algo que ya se leyó. Si un fichero es grande
(`src/Wurst.lua` ~7k líneas, `Disguise.lua` ~2.8k), se lee **solo** el rango.

### 2. Orden de implementación: causa raíz primero

El bug que explica un síntoma del usuario va **antes** que los cosméticos: si el
Fling no ve targets, ese arreglo decide si los demás cambios se pueden probar.

### 3. Verificar con la herramienta más barata primero

```
node tools/luau/compile.mjs <ficheros tocados>   # segundos, sintaxis y tipos
python3 tools/test_<lo tuyo>.py                  # segundos, comportamiento
bash tools/validate.sh                           # ~3 min, todo
```

Compilar primero ahorra runs: un error de sintaxis detectado ahí no gasta los
tres minutos de `validate.sh`.

### 4. Un solo `validate.sh`, al final

Se lanza **una vez**, en background, y se espera con `sleep` + `grep` del
resultado. Repetirlo tras cada edición multiplica el coste sin aportar nada.

### 5. Publicar sin conflictos

```
git fetch origin arena/<rama>
# si el remoto avanzó:
git reset --soft origin/arena/<rama> && git commit ...
git push origin arena/<rama>
```

`git rebase` a mano en este repo produce conflictos en `bundle.lua`,
`Manifest.lua` y el harness: no se reintenta.

## Puertas de verificación

- `tools/luau/compile.mjs` sin salida = sin errores.
- Cada suite nueva termina en `PASS …` con una frase que diga **qué** se probó.
- `bash tools/validate.sh` → `EXIT=0`, con el número de fuentes y de suites.
- El commit menciona la versión cerrada (`v192: …`) y el push sale limpio.

## Anti-patrones (costaron runs enteros)

- Leer un fichero de 20 MB con `grep -n` cuando es una sola línea XML: usar
  `python3` + `re.finditer` con contexto.
- Escribir Luau de depuración desde heredocs con comillas anidadas.
- Añadir una suite que dependa de texto que otro cambio va a renombrar: se
  actualiza en el mismo run.
- Terminar el run con «pendiente de probar» algo que se podía haber mockeado.
