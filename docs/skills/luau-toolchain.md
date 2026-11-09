---
name: luau-toolchain
description: Compilar, analizar, formatear y minificar este repo Luau/Wurst sin red. Úsala cuando un cambio toque Luau y haya que saber por qué un fichero falla, cuando haga falta una puerta de tipos antes de `validate.sh`, o cuando haya que tocar el toolchain vendorizado (Luau, DarkLua, StyLua, definiciones de Roblox).
---

# Toolchain Luau de este repo (sin red, sin npm install)

Todo el toolchain vive vendorizado en `tools/luau/`. Un clon nuevo (o un
sandbox con el `node_modules` borrado) se reconstruye con un solo comando y **no
necesita red**:

```bash
bash tools/luau/setup.sh            # descompacta y repara
bash tools/luau/setup.sh --verify   # además prueba cada herramienta
```

## Qué hay dentro

| Herramienta | Binario | Origen | Para qué |
| --- | --- | --- | --- |
| Luau 0.739 (wasm) | `tools/luau/bin/luau` | `vendor/luau-rs-luau-0.739.0.tgz` | ejecutar los harness de `tools/test_*.py` |
| Luau compile | `tools/luau/bin/luau-compile` | idem | puerta de sintaxis/tipos: `validate.sh` |
| luau-analyze | `tools/luau/bin/luau-analyze` | idem (`@luau-rs/luau/analysis`) | chequeo de tipos + lints sobre `src/` |
| StyLua 2.6 (wasm) | `tools/luau/bin/luau-format` | `vendor/johnnymorganz-stylua-2.6.0.tgz` | formatear/chequear formato |
| DarkLua 0.19 (wasm) | `tools/luau/bin/luau-minify` | `vendor/darklua-wasm-0.1.0.tgz` | reglas de release (quitar tipos, renombrar, comprimir) |
| valibot 1.5 | — | `vendor/valibot-1.5.0.tgz` | única dependencia de `@luau-rs/luau` |

Los binarios de GitHub (`darklua`, `stylua`, `luau-analyze` nativos) **no** están
disponibles en este sandbox: la red solo permite `registry.npmjs.org`,
`pypi.org`, `github.com` y `api.github.com`, y las releases de GitHub viven en
`release-assets.githubusercontent.com`, que está bloqueado. Por eso las tres
herramientas corren como wasm desde npm, vendorizadas en el repo.

## Uso diario

```bash
# 1. ¿compila? segundos, sin ruido
tools/luau/bin/luau-compile src/Wurst.lua

# 2. ¿tipos y lints? errores nuevos fallan, los conocidos están en baseline
tools/luau/bin/luau-analyze src/games/MM2/Other/FlingEngine.lua
tools/luau/bin/luau-analyze --baseline          # árbol entero contra la baseline
tools/luau/bin/luau-analyze --errors --json     # solo errores, para scripts

# 3. formato: la puerta de un cambio, no del árbol entero
tools/luau/bin/luau-format --check src/libraries/Framework.lua
tools/luau/bin/luau-format --diff src/libraries/Framework.lua
tools/luau/bin/luau-format src/libraries/Framework.lua     # reescribe

# 4. artefacto de release
tools/luau/bin/luau-minify src/Wurst.lua -o build/Wurst.min.lua
```

## Definiciones de tipos (el punto delicado)

`luau-analyze` necesita saber que `CFrame`, `Vector3`, `Enum`, `Instance`... son
tipos. La fuente autoritativa es `globalTypes.d.luau` de **luau-lsp**
(generado del API dump de Roblox, 880 KB, 2 400 declaraciones).

Ese fichero entero **no** se puede cargar: el analizador wasm contesta

```
Internal error: Code is too complex to typecheck!
```

Por eso `tools/luau/definitions/build_definitions.py` construye un subconjunto
**cerrado sobre sí mismo**: renderiza, lo carga con el analizador real, lee los
`Unknown type` que le faltan, los añade, y repite hasta que carga limpio. Salida:
`tools/luau/definitions/core.d.luau` (~3 700 líneas).

```bash
# regenerar (necesita el dump; se baja con la API de GitHub, 1 línea)
python3 tools/luau/definitions/build_definitions.py /tmp/globalTypes.d.luau
python3 tools/luau/definitions/build_definitions.py --check   # ¿está al día?
```

Reglas del generador, en orden (el orden es load-bearing):

1. `Enum` y `EnumItem` (tipos valor, no clases).
2. Tipos miembro (`EnumKeyCode`, ...) que extienden `EnumItem`.
3. Tipos valor (`CFrame`, `Vector3`, `UDim2`, `RaycastParams`...) expandidos, con
   todo tipo valor que mencionan.
4. Clases del motor: las de `FULL_CLASSES` con miembros (el runtime los lee cada
   frame); el resto solo nombre + superclase (`extends X with end`), con la
   superclase **antes** de la subclase o el analizador dice
   `Cannot use non-class type 'X' as a superclass of class 'Y'`.
5. Tablas globales (`declare CFrame: {...}`, `declare task: {...}`) y
   `game`/`workspace`/`shared`. `Enum` se declara `{ [string]: any }` a
   propósito: tiparlo como `ENUM_LIST` arrastra los 656 enums y vuelve el
   problema del presupuesto.

`tools/luau/definitions/runtime.d.luau` es a mano y no se genera: declara el
**entorno del ejecutor** (`getgenv`, `gethui`, `getconnections`, `hookmetamethod`,
`setclipboard`, `readfile`...) y los **globales del host** (`create`, `Theme`,
`state`, `notify`, `TaskManager`, `configData`, `Players`, `LocalPlayer`,
`RunService`...), que es lo que `docs/skills/roblox-menu-change.md` llama "el
módulo corre dentro del entorno del menú". Añadir un global nuevo ahí es una
línea; no se esparcen casts por el código de las tarjetas.

## Baseline: por qué existe y cuándo tocarla

`tools/luau/analyze-baseline.json` guarda los errores **ya leídos y aceptados**.
Son dos limitaciones del front end wasm, no bugs del menú:

- `obj:IsA("MeshPart")` no estrecha el tipo: el analizador sigue viendo
  `Instance` y se queja de `MeshId`, `Part1`, `Attachment1`, `R6`...
- `Enum.KeyCode` **como tipo** (`local k: Enum.KeyCode`) no resuelve: el
  analizador ve `Enum` como la tabla global, no como espacio de nombres. La
  expresión `Enum.KeyCode.A` sí funciona.

`luau-analyze --baseline` falla solo con errores **nuevos**. Cuando un cambio
añade a propósito una de esas limitaciones:

```bash
tools/luau/bin/luau-analyze --write-baseline   # regraba la lista, revisa el diff
```

La baseline es una lista de deuda visible, no un basurero: si un cambio quita
una limitación (por ejemplo anotando el cast), la entrada sobra y el siguiente
`--write-baseline` la borra.

## DarkLua: el pipeline de release

`tools/luau/minify.mjs` aplica la lista de `tools/luau/darklua.release.json`
(las dos tienen que coincidir; el script falla si divergen):

```
remove_types → remove_debug_profiling → remove_compound_assignment →
convert_local_function_to_assign → group_local_assignment → remove_empty_do →
remove_unused_if_branch → remove_unused_while → remove_unused_variable →
remove_method_definition → rename_variables → remove_comments → remove_spaces
```

Medido sobre `src/Wurst.lua` (259 KB):
**126 KB, −51.1 %**, y el resultado compila con `luau-compile`.
No hay reglas de `require`/`inject_global_value`: `Wurst.lua` ya es un loader
autocontenido y no usa `require`.

## Puertas

| Puerta | Comando | Falla cuando |
| --- | --- | --- |
| Sintaxis | `tools/luau/bin/luau-compile <files>` | un fichero no compila |
| Tipos/lints | `tools/luau/bin/luau-analyze --baseline` | hay un error fuera de la baseline |
| Definiciones | `build_definitions.py --check` | `core.d.luau` no viene del dump fijado |
| Formato | `tools/luau/bin/luau-format --check <files>` | el fichero tocado está sin formatear |
| Release | `tools/luau/bin/luau-minify src/Wurst.lua -o …` | DarkLua no puede procesarlo |
| Todo | `bash tools/validate.sh` | cualquiera de arriba, o bundle/menú/suites |

## Anti-patrones

- Descargar binarios de `github.com/…/releases` — bloqueado en este sandbox.
  Usa los tarballs de `vendor/`.
- Cargar `globalTypes.d.luau` entero — revienta el analizador.
- Editar `core.d.luau` a mano — se regenera, y `--check` lo detecta.
- Poner `declare X: any` para callar un error del código de una tarjeta: se
  declara en `runtime.d.luau` una vez, o se corrige el código.
- Reformatear el árbol entero en un cambio de una tarjeta: el diff se vuelve
  ilegible. Formatea solo los ficheros tocados.
